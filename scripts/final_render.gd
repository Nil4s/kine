class_name FinalRender
## FINAL RENDER (GAP_AUDIT_1106 top-10 #3): the quality preset of the shot render and the dialog's resolution list. The render loop is
## main.gd's _render_shots (the same one "Render shots (mp4)" uses; opts {preset, w, h, first, count} make it a final render: the
## frames are drawn by a SubViewport of w x h that shares the scene's World3D, through the shot camera, with the preset applied).
## "final": SSAO, SSR, SDFGI (Forward+), 4x MSAA, shadows with the softest filter, glow OFF. "draft": none of them (cheap).
## apply() returns what it replaced; restore() puts it back exactly; read() says what is set (the test reads it back).

const RES := [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]
const DEFAULT_RES := Vector2i(1920, 1080)

const PRESETS := {
	"draft": {"ssao": false, "ssr": false, "sdfgi": false, "glow": false, "msaa": Viewport.MSAA_DISABLED, "shadows": false,
		"soft_q": RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, "atlas": 1024},
	"final": {"ssao": true, "ssr": true, "sdfgi": true, "glow": false, "msaa": Viewport.MSAA_4X, "shadows": true,
		"soft_q": RenderingServer.SHADOW_QUALITY_SOFT_ULTRA, "atlas": 4096},
}

## the global soft-shadow filter (RenderingServer has no getter): what this class last set, else the project's value
static var _soft_q := -1
## a hook called at the end of apply() with (env, vp, lights): a test compares a candidate against another setting on the same frame
static var post_apply := Callable()


static func soft_q_now() -> int:
	if _soft_q < 0:
		_soft_q = int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality", 2))
	return _soft_q


static func _set_soft_q(q: int) -> void:
	_soft_q = q
	RenderingServer.directional_soft_shadow_filter_set_quality(q)
	RenderingServer.positional_soft_shadow_filter_set_quality(q)


static func read(env: Environment, vp: Viewport, lights: Array) -> Dictionary:
	var sh := not lights.is_empty()
	for L in lights:
		sh = sh and (L as Light3D).shadow_enabled
	return {"ssao": env.ssao_enabled, "ssr": env.ssr_enabled, "sdfgi": env.sdfgi_enabled, "glow": env.glow_enabled,
		"msaa": int(vp.msaa_3d), "shadows": sh, "soft_q": soft_q_now(), "atlas": int(vp.positional_shadow_atlas_size),
		"ssao_intensity": env.ssao_intensity, "ssao_radius": env.ssao_radius, "ssao_power": env.ssao_power,
		"lights": lights.map(func(L): return [(L as Light3D).shadow_enabled, (L as Light3D).shadow_blur, (L as Light3D).shadow_normal_bias])}


## sets the preset; returns the state to hand back to restore()
static func apply(preset: String, env: Environment, vp: Viewport, lights: Array) -> Dictionary:
	var p: Dictionary = PRESETS[preset]
	var saved := read(env, vp, lights)
	env.ssao_enabled = p["ssao"]
	env.ssr_enabled = p["ssr"]
	env.sdfgi_enabled = p["sdfgi"]
	env.glow_enabled = p["glow"]
	if p["ssao"]:
		env.ssao_radius = 1.2
		env.ssao_intensity = 3.0   # the contact darkening at feet and under props
		env.ssao_power = 1.8
	RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_HIGH if p["ssao"] else RenderingServer.ENV_SSAO_QUALITY_MEDIUM, true, 0.5, 2.0, 50.0, 300.0)   # less grain (L15 measured: SSAO is not the grain; ULTRA / full-res / 4 passes changed it by < 2%)
	vp.msaa_3d = p["msaa"]
	vp.positional_shadow_atlas_size = p["atlas"]
	_set_soft_q(p["soft_q"])
	for L in lights:
		var l := L as Light3D
		l.shadow_enabled = p["shadows"]
		if p["shadows"]:
			l.shadow_blur = 0.5   # L15: 1.6 left a dithered hatch on the shadow side of the skinned body (measured: the grain is the soft-shadow filter, not the SSAO)
			l.shadow_normal_bias = 2.0   # no acne on the skinned mesh
	if post_apply.is_valid():
		post_apply.call(env, vp, lights)
	return saved


static func restore(saved: Dictionary, env: Environment, vp: Viewport, lights: Array) -> void:
	env.ssao_enabled = saved["ssao"]
	env.ssr_enabled = saved["ssr"]
	env.sdfgi_enabled = saved["sdfgi"]
	env.glow_enabled = saved["glow"]
	env.ssao_intensity = saved["ssao_intensity"]
	env.ssao_radius = saved["ssao_radius"]
	env.ssao_power = saved["ssao_power"]
	RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_MEDIUM, true, 0.5, 2.0, 50.0, 300.0)
	vp.msaa_3d = saved["msaa"]
	vp.positional_shadow_atlas_size = saved["atlas"]
	_set_soft_q(saved["soft_q"])
	var ls: Array = saved["lights"]
	for i in lights.size():
		var l := lights[i] as Light3D
		l.shadow_enabled = ls[i][0]
		l.shadow_blur = ls[i][1]
		l.shadow_normal_bias = ls[i][2]


## one drawn frame of a SubViewport, as an image (the caller has set the camera)
static func grab(tree: SceneTree, svp: SubViewport) -> Image:
	await tree.process_frame
	await RenderingServer.frame_post_draw
	return svp.get_texture().get_image()
