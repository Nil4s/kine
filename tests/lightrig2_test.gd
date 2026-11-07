## godot --path . -s tests/lightrig2_test.gd     (L48 LIGHT RIG 2: sky picks and light linking measured on the scene, and the agent tool; needs a window)
## GAP_AUDIT_1106 rendering item 4, second lane: the HDRI picker must change the MEASURED scene, not only the sky, and a light's
## "affects only these objects" toggle must be proven by numbers on two objects (scripts/light_rig.gd, scripts/light_rig_ui.gd).
## THESE BARS WERE WRITTEN AND COMMITTED BEFORE THE IMPLEMENTATION OF LightRig.serve. Numbers come from the lane brief, not from a run.
## MEASUREMENT PROTOCOL (fixed before the first run): the isolated stage of tests/lightrig_test.gd (own World3D, 480x360): a grey
## sphere (albedo 0.5, radius 0.5 m) at (0,1,0) = OBJECT A, a floor at y=0 (albedo 0.7, on WORLD_BIT only) = OBJECT B, a perspective
## camera at (0,1,4) looking along -z. Every frame is read back and turned to LINEAR light. "Scene luminance" = the mean linear
## luminance over every 4th pixel of the whole frame. "Lit luminance" of A = the 5x5 patch at 45 deg left of the lens on the sphere;
## of B = the 9x9 patch on the floor at (1.6, 0, 1.2).
##   1 SKY PICK ON THE SCENE (isolated stage, all three lights at energy 0, so the sky is the only light):
##     a. clear_day vs night: the whole-frame linear luminance of the clear day is >= 1.5 x the night frame (a swap moves it >= 50 percent).
##     b. clear_day vs sunset: the mean sRGB colour of the frame moves by >= 0.08 (Euclidean, 0..1).
##     PLANTED: swapping to the SAME map twice moves the luminance by < 1 percent and the colour by < 0.01; the same bars refuse it.
##   2 SKY PICK ON THE APP (the real main scene, UI hidden, no look): m.lr_hdri("night") then m.lr_hdri("clear_day") on the real
##     viewport: the whole-frame linear luminance differs by >= 20 percent. PLANTED: swapping to "no map" and back to "no map" differs by < 1 percent.
##   3 LINKING TOGGLE (isolated stage, studio look, ambient 0.4 so the floor is lit by something constant):
##     a. the key is LINKED (LightRig.set_link, character only): toggling the key OFF and ON (light.visible) moves object A's lit
##        luminance by >= 15 percent and object B's mean lit luminance by < 2 percent.
##     b. the key UNLINKED (everything mask): the same toggle moves B by >= 15 percent (the floor really does respond when not linked).
##     PLANTED: B must be lit at all (> 0.02) and the "< 2 percent" check is run on the unlinked toggle too and must REFUSE it.
##   4 AGENT TOOL (LightRig.serve through the app's main scene; the same functions the MCP "lightrig" tool calls):
##     a. {"sky": "night"} is ok, reports sky "night", and the app's lr_hdri_id is "night".
##     b. {"sky": "moonbase"} is refused (ok false), and the sky id stays what it was. PLANTED: the refusal must hold.
##     c. {"link": {"key": true}} is ok; the key's cull mask is link_mask(true), the fill's and rim's stay link_mask(false).
##     d. {"look": "noir"} is ok and the app's shot light reads "noir"; {} returns the facts (sky, links, lights) and is ok.
extends SceneTree

var fails := 0
var vp: SubViewport
var cam: Camera3D
var sph: MeshInstance3D
var flr: MeshInstance3D
var key: DirectionalLight3D
var fill: DirectionalLight3D
var rim: DirectionalLight3D
var env: Environment
const CAM_POS := Vector3(0, 1, 4)
const CAM_AIM := Vector3(0, 1, 0)
const SC := Vector3(0, 1, 0)


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func stage() -> void:
	vp = SubViewport.new()
	vp.size = Vector2i(480, 360)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment = env
	vp.add_child(we)
	cam = Camera3D.new()
	cam.fov = 40
	vp.add_child(cam)
	cam.position = CAM_POS
	cam.look_at_from_position(CAM_POS, CAM_AIM)
	sph = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 64
	sm.rings = 32
	sph.mesh = sm
	var mt := StandardMaterial3D.new()
	mt.albedo_color = Color(0.5, 0.5, 0.5)
	sph.material_override = mt
	sph.position = SC
	vp.add_child(sph)
	flr = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(8, 8)
	flr.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.7, 0.7, 0.7)
	flr.material_override = fm
	flr.layers = LightRig.WORLD_BIT   # the floor is "the world" (object B); the sphere stays on layer 1 (the character, object A)
	vp.add_child(flr)
	for pair in [["key", 0], ["fill", 1], ["rim", 2]]:
		var L := DirectionalLight3D.new()
		L.shadow_enabled = false
		vp.add_child(L)
		match pair[1]:
			0: key = L
			1: fill = L
			2: rim = L


func apply(id: String) -> void:
	LightRig.apply_rig(LightRig.rig(id, CAM_POS, CAM_AIM), key, fill, rim, env)


func frame() -> Image:
	await idle(3)
	await RenderingServer.frame_post_draw
	return vp.get_texture().get_image()


func lin(c: Color) -> float:
	var l := c.srgb_to_linear()
	return 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b


## mean linear luminance of a (2r+1)^2 patch at a screen point
func patch(img: Image, p: Vector2, r := 2) -> float:
	var s := 0.0
	var n := 0
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			s += lin(img.get_pixel(clampi(int(p.x) + dx, 0, img.get_width() - 1), clampi(int(p.y) + dy, 0, img.get_height() - 1)))
			n += 1
	return s / float(n)


func sph_px(az: float) -> Vector2:
	var n := LightRig.source_dir(Vector3(0, 0, -1), az, 0.0)
	return cam.unproject_position(SC + n * 0.5)


func floor_px() -> Vector2:
	return cam.unproject_position(Vector3(1.6, 0, 1.2))


## mean linear luminance of every 4th pixel of the whole frame
func scene_lum(img: Image) -> float:
	var s := 0.0
	var n := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			s += lin(img.get_pixel(x, y))
			n += 1
	return s / float(n)


## mean sRGB colour of a frame (every 4th pixel)
func mean_col(img: Image) -> Color:
	var s := Vector3.ZERO
	var n := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var c := img.get_pixel(x, y)
			s += Vector3(c.r, c.g, c.b)
			n += 1
	s /= float(n)
	return Color(s.x, s.y, s.z)


func cdist(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


## a relative change of v1 against v0 (v0 > 0)
func rel(v0: float, v1: float) -> float:
	return absf(v1 - v0) / maxf(v0, 1e-9)


func pose() -> Dictionary:
	var R := Body.new()
	R.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	R.fk()
	return R.to_dict()


func _init() -> void:
	stage()
	await idle(4)
	for L in [key, fill, rim]:
		L.light_energy = 0.0

	# ---------------------------------------------------------------- 1 the sky pick moves the measured scene
	env.ambient_light_energy = 1.0
	LightRig.apply_hdri(env, "clear_day", 0.0, 1.0)
	var f_day := await frame()
	var lum_day := scene_lum(f_day)
	var col_day := mean_col(f_day)
	LightRig.apply_hdri(env, "night", 0.0, 1.0)
	var f_night := await frame()
	var lum_night := scene_lum(f_night)
	LightRig.apply_hdri(env, "sunset", 0.0, 1.0)
	var col_sun := mean_col(await frame())
	var lr_ratio := lum_day / maxf(lum_night, 1e-6)
	ok(lr_ratio >= 1.5, "1a clear day vs night: whole-frame linear luminance %.4f vs %.4f, ratio %.2f (bar >= 1.5)" % [lum_day, lum_night, lr_ratio])
	var cd := cdist(col_day, col_sun)
	ok(cd >= 0.08, "1b clear day vs sunset: mean sRGB colour moves %.3f (bar >= 0.08)" % cd)
	LightRig.apply_hdri(env, "clear_day", 0.0, 1.0)
	var same_a := scene_lum(await frame())
	var same_c := cdist(mean_col(await frame()), col_day)
	LightRig.apply_hdri(env, "clear_day", 0.0, 1.0)
	var same_b := scene_lum(await frame())
	var same_moves := rel(same_a, same_b)
	ok(same_moves < 0.01 and same_c < 0.01, "1 PLANTED the same map twice moves luminance %.4f percent and colour %.4f: the 50 percent and 0.08 bars refuse it" % [100.0 * same_moves, same_c])
	ok(not (rel(lum_night, lum_day) >= 0.5 and same_moves >= 0.5), "1 PLANTED control: the same-map swap does not pass the sky-swap luminance bar")

	# ---------------------------------------------------------------- 2 the sky pick in the real app
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.ui_root.visible = false
	m.ui_find.visible = false
	var S := Scene.new()
	S.name = "zz_lightrig2"
	S.fps = 24
	S.add("c0", pose())
	m.S = S
	m._rebuild_cards()
	m.sel_card = 0
	m.playhead = 0.0
	m._refresh()
	await idle(3)
	m.lr_hdri("night")
	await idle(3)
	var app_night := scene_lum(await frame_app(m))
	m.lr_hdri("clear_day")
	await idle(3)
	var app_day := scene_lum(await frame_app(m))
	var app_ratio := rel(app_night, app_day)
	ok(app_ratio >= 0.20, "2 the app: night map -> clear day moves the whole-frame luminance %.4f -> %.4f (%.0f percent, bar >= 20)" % [app_night, app_day, 100.0 * app_ratio])
	m.lr_hdri("")
	await idle(3)
	var app_none_a := scene_lum(await frame_app(m))
	m.lr_hdri("")
	await idle(3)
	var app_none_b := scene_lum(await frame_app(m))
	ok(rel(app_none_a, app_none_b) < 0.01, "2 PLANTED no map twice moves the app's luminance %.2f percent: the 20 percent bar refuses it" % [100.0 * rel(app_none_a, app_none_b)])

	# ---------------------------------------------------------------- 3 the linking toggle on two objects
	apply("studio")
	env.ambient_light_energy = 0.4   # the floor is lit by something that does not change with the key
	env.adjustment_enabled = false
	LightRig.apply_hdri(env, "", 0.0, 1.0)
	env.ambient_light_energy = 0.4
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var fA := 0.0
	var fB := 0.0
	# a. key LINKED (character only); fill and rim unlinked and dark, so the key is the only thing being toggled
	LightRig.set_link(key, true)
	LightRig.set_link(fill, false)
	LightRig.set_link(rim, false)
	fill.light_energy = 0.0
	rim.light_energy = 0.0
	var on_img := await frame()
	var a_on := patch(on_img, sph_px(45.0))
	var b_on := patch(on_img, floor_px(), 4)
	key.visible = false
	var off_img := await frame()
	var a_off := patch(off_img, sph_px(45.0))
	var b_off := patch(off_img, floor_px(), 4)
	key.visible = true
	ok(b_on > 0.02, "3 PLANTED object B is lit at all: floor %.4f > 0.02" % b_on)
	ok(rel(a_on, a_off) >= 0.15, "3a linked key: object A (sphere) lit %.4f -> %.4f (%.0f percent, bar >= 15)" % [a_on, a_off, 100.0 * rel(a_on, a_off)])
	ok(rel(b_on, b_off) < 0.02, "3a linked key: object B (floor) lit %.4f -> %.4f (%.2f percent, bar < 2)" % [b_on, b_off, 100.0 * rel(b_on, b_off)])
	# b. key UNLINKED: the same toggle must reach the floor (the bar of 3a is not vacuous)
	LightRig.set_link(key, false)
	var un_on := await frame()
	var ub_on := patch(un_on, floor_px(), 4)
	key.visible = false
	var un_off := await frame()
	var ub_off := patch(un_off, floor_px(), 4)
	key.visible = true
	ok(rel(ub_on, ub_off) >= 0.15, "3b unlinked key: object B (floor) lit %.4f -> %.4f (%.0f percent, bar >= 15)" % [ub_on, ub_off, 100.0 * rel(ub_on, ub_off)])
	# PLANTED: the < 2 percent check must REFUSE the unlinked toggle
	var refused := not (rel(ub_on, ub_off) < 0.02)
	ok(refused, "3 PLANTED the unlinked key moves the floor %.0f percent, and the < 2 percent check refuses it" % [100.0 * rel(ub_on, ub_off)])
	fA = a_on
	fB = b_on
	print("  linking numbers: A lit %.4f -> %.4f, B lit %.4f -> %.4f (linked); B %.4f -> %.4f (unlinked)" % [a_on, a_off, b_on, b_off, ub_on, ub_off])

	# ---------------------------------------------------------------- 4 the agent tool, through the app
	m.lr_hdri("")
	var r1: Dictionary = LightRig.serve(m, {"sky": "night"})
	ok(bool(r1.get("ok", false)) and String(r1.get("result", {}).get("sky", "")) == "night" and m.lr_hdri_id == "night", "4a {sky: night} is ok, reports night, and the app's sky is night")
	var r2: Dictionary = LightRig.serve(m, {"sky": "moonbase"})
	ok(not bool(r2.get("ok", true)) and m.lr_hdri_id == "night", "4b PLANTED {sky: moonbase} is refused and the sky stays night")
	m.lr_hdri("")
	var r3: Dictionary = LightRig.serve(m, {"link": {"key": true}})
	ok(bool(r3.get("ok", false)) and m.light_key.light_cull_mask == LightRig.link_mask(true) and m.light_fill.light_cull_mask == LightRig.link_mask(false) and m.light_rim.light_cull_mask == LightRig.link_mask(false), "4c {link: key on} is ok: key character-only, fill and rim everything")
	LightRig.serve(m, {"link": {"key": false}})
	var r4: Dictionary = LightRig.serve(m, {"look": "noir"})
	ok(bool(r4.get("ok", false)) and String(m.S.shots[0].get("light", "")) == "noir", "4d {look: noir} is ok and the app's shot light reads noir")
	var r5: Dictionary = LightRig.serve(m, {})
	ok(bool(r5.get("ok", false)) and r5.get("result", {}).has("sky") and r5.get("result", {}).has("links"), "4d {} returns the facts (sky, links, lights)")
	print("lightrig2: %d fail" % fails)
	quit(fails)


## one frame of the app's main viewport, UI hidden
func frame_app(m: Node) -> Image:
	await idle(3)
	await RenderingServer.frame_post_draw
	return m.get_viewport().get_texture().get_image()
