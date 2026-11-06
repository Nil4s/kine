## godot --path . -s tests/render1_test.gd     (L49 RENDER1; GAP_AUDIT_1106 Rendering item 1: a final-quality offline preset "Final HQ"; needs a window)
## THESE BARS WERE WRITTEN AND COMMITTED BEFORE THE IMPLEMENTATION (scripts/final_hq.gd). Numbers come from the lane brief, not from a run.
## All stages are isolated (own World3D, unshaded or one sun), pixels are turned to LINEAR light before any luminance is taken.
##   1 GI: a white floor lit by a sun that shines from behind a wall; the wall's front face is in the wall's own shadow. Ambient and sky are BLACK, so
##     with GI off the patch is dark. FinalHQ.gi(env, true) (SDFGI bounce) must RAISE the linear luminance of a 40x40 px wall patch by >= 0.02 absolute
##     and to >= 3x the GI-off value (floored at 0.005). PLANTED: GI off vs GI off raises it by < 0.02, so the same check refuses it. CONTROL: with a
##     black floor (albedo 0) GI on adds <= 40% of what the white floor adds (the light comes from the floor, not from the preset).
##   2 DOF: two white cards, one at the focus distance (3 m) and one at 12 m, vertical edge at the same screen column, black background; FinalHQ.dof on.
##     The 10-90% edge width of the far card >= 3.0 x the in-focus card's (floored at 1 px) AND >= 6 px. CONTROL: with DOF off the far width is
##     < 1.5 x the near one. PLANTED: the in-focus width against itself fails the 3x check.
##   3 MOTION BLUR (sub-frame accumulation): an ortho camera (80 px per m), a 0.5 m white bar moving 10 m/s at 24 fps with shutter 0.5 of a frame,
##     16 sub-frames, FinalHQ.motion_times + FinalHQ.accumulate. Streak length (columns above 0.5% of the bar value, minus the bar's own 40 px) is
##     speed x shutter x 80 px = 16.67 px within 15%. CONTROL: 1 sub-frame gives a streak < 3 px. PLANTED: the expectation for shutter 1.0 (33.3 px)
##     is refused by the same 15% check.
##   4 ACCUMULATION: a flat patch whose colour is noise redrawn per frame (a Monte-Carlo stand-in: a hash shader seeded per frame). The std of the
##     accumulated patch over N frames / std of one frame is within +-20% of 1/sqrt(N) for N = 4 and N = 16. PLANTED: accumulating the SAME frame
##     16 times gives a ratio ~1 and fails that band.
##   5 PRESET + WIRING: FinalRender.apply("final_hq") reads back SDFGI, SSAO, SSR on, glow off, MSAA >= 4x, and FinalHQ.PRESET has dof on, subframes >= 8,
##     accum >= 2; restore() puts the original back. The Final render dialog has a quality list (opt_preset) with Draft, Final, Final HQ; the agent tool
##     final_render is in AgentTools.MCP_EXTRA and tools/mcp/poser_mcp.py, and calling it in the app makes N PNGs at the asked size.
##     CONTROL: an unknown preset is refused with an error.
##   6 PICTURE: tests/out/render1_final.png (<= 1000 px wide), one frame of the app scene rendered with Final HQ.
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func lin(v: float) -> float:
	return pow((v + 0.055) / 1.055, 2.4) if v > 0.04045 else v / 12.92


func lum_lin(c: Color) -> float:
	return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)


func patch_lin(img: Image, r: Rect2i) -> float:
	var t := 0.0
	for y in range(r.position.y, r.position.y + r.size.y):
		for x in range(r.position.x, r.position.x + r.size.x):
			t += lum_lin(img.get_pixel(x, y))
	return t / float(r.size.x * r.size.y)


func make_svp(w: int, h: int, msaa := Viewport.MSAA_4X) -> SubViewport:
	var svp := SubViewport.new()
	svp.size = Vector2i(w, h)
	svp.own_world_3d = true
	svp.msaa_3d = msaa
	svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(svp)
	return svp


func black_env() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0, 0, 0)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	return env


func box(parent: Node, size: Vector3, pos: Vector3, col: Color, unshaded := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mt := StandardMaterial3D.new()
	mt.albedo_color = col
	if unshaded:
		mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mt
	mi.position = pos
	parent.add_child(mi)
	return mi


func grab(svp: SubViewport) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return svp.get_texture().get_image()


# ------------------------------------------------------------------ bar 1
func gi_patch(gi_on: bool, floor_col: Color) -> float:
	var svp := make_svp(480, 270, Viewport.MSAA_DISABLED)
	var env := black_env()
	var we := WorldEnvironment.new()
	we.environment = env
	svp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 180, 0)   # shines toward +z: from behind the wall, so the wall's front (+z) face is in its own shadow
	sun.light_energy = 2.0
	sun.shadow_enabled = true
	svp.add_child(sun)
	box(svp, Vector3(24, 0.2, 24), Vector3(0, -0.1, 0), floor_col)
	box(svp, Vector3(6, 3, 0.3), Vector3(0, 1.5, -2), Color(0.8, 0.8, 0.8))
	var cam := Camera3D.new()
	svp.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.5, 5), Vector3(0, 1.5, -2))
	cam.fov = 40.0
	cam.current = true
	FinalHQ.gi(env, gi_on)
	await idle(60 if gi_on else 8)
	var img: Image = await grab(svp)
	var p := patch_lin(img, Rect2i(220, 115, 40, 40))
	svp.queue_free()
	await idle(2)
	return p


# ------------------------------------------------------------------ bar 2
## 10-90% width in px of the falling edge (card on the left, background on the right) along a row-averaged profile, sub-pixel
func edge_width(img: Image, y0: int, y1: int, x0: int, x1: int) -> float:
	var prof := []
	for x in range(x0, x1):
		var t := 0.0
		for y in range(y0, y1):
			t += lum_lin(img.get_pixel(x, y))
		prof.append(t / float(y1 - y0))
	var lo: float = prof[prof.size() - 1]
	var hi: float = prof[0]
	var c10 := -1.0
	var c90 := -1.0
	for i in range(prof.size() - 1):
		var a: float = (prof[i] - lo) / maxf(hi - lo, 1e-6)
		var b: float = (prof[i + 1] - lo) / maxf(hi - lo, 1e-6)
		if c90 < 0.0 and a >= 0.9 and b < 0.9:
			c90 = float(i) + (a - 0.9) / maxf(a - b, 1e-6)
		if c10 < 0.0 and a >= 0.1 and b < 0.1:
			c10 = float(i) + (a - 0.1) / maxf(a - b, 1e-6)
	if c10 < 0.0 or c90 < 0.0:
		return -1.0
	return c10 - c90


func dof_widths(dof_on: bool) -> Array:
	var svp := make_svp(640, 360, Viewport.MSAA_DISABLED)
	var env := black_env()
	var we := WorldEnvironment.new()
	we.environment = env
	svp.add_child(we)
	box(svp, Vector3(10, 5, 0.05), Vector3(-5, 2.5, -3), Color(1, 1, 1), true)     # near card: x < 0, upper half, at the focus distance
	box(svp, Vector3(40, 5, 0.05), Vector3(-20, -2.5, -12), Color(1, 1, 1), true)  # far card: x < 0, lower half
	var cam := Camera3D.new()
	svp.add_child(cam)
	cam.position = Vector3(0, 0, 0)
	cam.fov = 40.0
	cam.current = true
	if dof_on:
		FinalHQ.dof(cam, 3.0)
	await idle(6)
	var img: Image = await grab(svp)
	var cx := 320
	var wn := edge_width(img, 40, 130, cx - 40, cx + 40)
	var wf := edge_width(img, 230, 320, cx - 40, cx + 40)
	svp.queue_free()
	await idle(2)
	return [wn, wf]


# ------------------------------------------------------------------ bar 3
func bar_frames(times: Array, speed: float, svp: SubViewport, barn: Node3D) -> Array:
	var imgs := []
	for t in times:
		barn.position.x = -3.0 + speed * float(t)
		imgs.append(await grab(svp))
	return imgs


func streak_px(img: Image, row: int) -> float:
	var mn := 9999
	var mx := -1
	for x in img.get_width():
		if lum_lin(img.get_pixel(x, row)) > 0.005:
			mn = mini(mn, x)
			mx = maxi(mx, x)
	return float(mx - mn + 1) - 40.0


# ------------------------------------------------------------------ bar 4
const NOISE_SHADER := "shader_type spatial;\nrender_mode unshaded;\nuniform float seed = 0.0;\nvoid fragment() {\n float n = fract(sin(dot(FRAGCOORD.xy + vec2(seed * 17.31, seed * 3.7), vec2(12.9898, 78.233))) * 43758.5453);\n ALBEDO = vec3(0.5 + (n - 0.5) * 0.3);\n}\n"


func patch_std(img: Image, r: Rect2i) -> float:
	var s := 0.0
	var s2 := 0.0
	var n := 0.0
	for y in range(r.position.y, r.position.y + r.size.y):
		for x in range(r.position.x, r.position.x + r.size.x):
			var c := img.get_pixel(x, y)
			var v := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			s += v
			s2 += v * v
			n += 1.0
	var mean := s / n
	return sqrt(maxf(s2 / n - mean * mean, 0.0))


func _init() -> void:
	# ------------------------------------------------------------ bar 1
	var gi_off := await gi_patch(false, Color(0.8, 0.8, 0.8))
	var gi_off2 := await gi_patch(false, Color(0.8, 0.8, 0.8))
	var gi_on := await gi_patch(true, Color(0.8, 0.8, 0.8))
	var gi_on_black := await gi_patch(true, Color(0, 0, 0))
	var raise := gi_on - gi_off
	print("     GI wall patch (linear): off %.4f, off again %.4f, on %.4f (raise %.4f, x%.1f), black floor on %.4f" % [gi_off, gi_off2, gi_on, raise, gi_on / maxf(gi_off, 0.005), gi_on_black])
	ok(raise >= 0.02 and gi_on >= 3.0 * maxf(gi_off, 0.005), "1 GI on raises the shadowed wall patch by %.4f (want >= 0.02) to %.1fx of GI off (want >= 3x)" % [raise, gi_on / maxf(gi_off, 0.005)])
	ok(not (gi_off2 - gi_off >= 0.02), "  PLANTED: GI off vs GI off raises it by %.4f: the check refuses it (< 0.02)" % (gi_off2 - gi_off))
	ok(gi_on_black - gi_off <= 0.4 * raise, "  CONTROL: a black floor adds %.4f, <= 40%% of the white floor's %.4f" % [gi_on_black - gi_off, raise])

	# ------------------------------------------------------------ bar 2
	var w_on: Array = await dof_widths(true)
	var w_off: Array = await dof_widths(false)
	print("     edge 10-90%% width px: DOF on near %.2f far %.2f; DOF off near %.2f far %.2f" % [w_on[0], w_on[1], w_off[0], w_off[1]])
	var wn := maxf(float(w_on[0]), 1.0)
	ok(w_on[0] >= 0.0 and w_on[1] >= 3.0 * wn and w_on[1] >= 6.0, "2 DOF: far edge %.2f px vs in-focus %.2f px (x%.1f, want >= 3.0 and >= 6 px)" % [w_on[1], w_on[0], w_on[1] / wn])
	ok(w_off[1] < 1.5 * maxf(float(w_off[0]), 1.0), "  CONTROL: DOF off, far %.2f px < 1.5 x near %.2f px" % [w_off[1], w_off[0]])
	ok(not (wn >= 3.0 * wn), "  PLANTED: the in-focus width against itself (x1.0) fails the 3x check")

	# ------------------------------------------------------------ bar 3
	var svp3 := make_svp(640, 360, Viewport.MSAA_4X)
	var env3 := black_env()
	var we3 := WorldEnvironment.new()
	we3.environment = env3
	svp3.add_child(we3)
	var cam3 := Camera3D.new()
	cam3.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam3.size = 4.5
	cam3.position = Vector3(0, 0, 5)
	cam3.current = true
	svp3.add_child(cam3)
	var barn := box(svp3, Vector3(0.5, 1.5, 0.1), Vector3(-3, 0, 0), Color(1, 1, 1), true)
	await idle(6)
	var speed := 10.0
	var fps := 24
	var expect := speed * 0.5 / float(fps) * 80.0
	var times16: Array = FinalHQ.motion_times(1.0, fps, 16, 0.5)
	var imgs16: Array = await bar_frames(times16, speed, svp3, barn)
	var acc16: Image = FinalHQ.accumulate(imgs16)
	var st16 := streak_px(acc16, 180)
	var imgs1: Array = await bar_frames(FinalHQ.motion_times(1.0, fps, 1, 0.5), speed, svp3, barn)
	var st1 := streak_px(FinalHQ.accumulate(imgs1), 180)
	print("     streak px: 16 sub-frames %.2f (speed x shutter = %.2f), 1 sub-frame %.2f" % [st16, expect, st1])
	ok(absf(st16 - expect) <= 0.15 * expect, "3 motion blur streak %.2f px vs speed x shutter %.2f px (within 15%%)" % [st16, expect])
	ok(st1 < 3.0, "  CONTROL: 1 sub-frame streak %.2f px (< 3)" % st1)
	ok(not (absf(st16 - 2.0 * expect) <= 0.15 * 2.0 * expect), "  PLANTED: the expectation for shutter 1.0 (%.1f px) is refused by the same 15%% check" % (2.0 * expect))
	svp3.queue_free()
	await idle(2)

	# ------------------------------------------------------------ bar 4
	var svp4 := make_svp(256, 256, Viewport.MSAA_DISABLED)
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2, 2)
	q.mesh = qm
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = NOISE_SHADER
	sm.shader = sh
	q.material_override = sm
	svp4.add_child(q)
	var cam4 := Camera3D.new()
	cam4.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam4.size = 2.0
	cam4.position = Vector3(0, 0, 3)
	cam4.current = true
	svp4.add_child(cam4)
	await idle(4)
	var frames4 := []
	for i in 16:
		sm.set_shader_parameter("seed", float(i + 1))
		await process_frame
		frames4.append(await grab(svp4))
	var pr := Rect2i(78, 78, 100, 100)
	var s1 := 0.0
	for i in 4:
		s1 += patch_std(frames4[i], pr)
	s1 /= 4.0
	var a4: Image = FinalHQ.accumulate(frames4.slice(0, 4))
	var a16: Image = FinalHQ.accumulate(frames4)
	var r4 := patch_std(a4, pr) / s1
	var r16 := patch_std(a16, pr) / s1
	var same := []
	for i in 16:
		same.append(frames4[0])
	var rs := patch_std(FinalHQ.accumulate(same), pr) / s1
	print("     noise std: 1 frame %.4f; ratio N=4 %.3f (1/sqrt = 0.500), N=16 %.3f (0.250), same frame x16 %.3f" % [s1, r4, r16, rs])
	ok(s1 > 0.03, "4 the single-frame patch is noisy (std %.4f > 0.03), so the ratios mean something" % s1)
	ok(absf(r4 - 0.5) <= 0.2 * 0.5 and absf(r16 - 0.25) <= 0.2 * 0.25, "  accumulation: std ratio N=4 %.3f (want 0.5 +-20%%), N=16 %.3f (want 0.25 +-20%%)" % [r4, r16])
	ok(not (absf(rs - 0.25) <= 0.05), "  PLANTED: the same frame accumulated 16 times gives ratio %.3f and fails the 1/sqrt(16) band" % rs)
	svp4.queue_free()
	await idle(2)

	# ------------------------------------------------------------ bar 5 preset + wiring, in the app
	var svp5 := make_svp(64, 64)
	var env5 := black_env()
	var key5 := DirectionalLight3D.new()
	svp5.add_child(key5)
	var r_orig := FinalRender.read(env5, svp5, [key5])
	var saved := FinalRender.apply("final_hq", env5, svp5, [key5])
	var r_hq := FinalRender.read(env5, svp5, [key5])
	FinalRender.restore(saved, env5, svp5, [key5])
	var r_back := FinalRender.read(env5, svp5, [key5])
	print("     final_hq: %s  HQ: %s" % [r_hq, FinalHQ.PRESET])
	ok(bool(r_hq["sdfgi"]) and bool(r_hq["ssao"]) and bool(r_hq["ssr"]) and not bool(r_hq["glow"]) and int(r_hq["msaa"]) >= Viewport.MSAA_4X,
		"5 final_hq reads back: SDFGI, SSAO, SSR on, glow off, MSAA >= 4x")
	ok(bool(FinalHQ.PRESET["dof"]) and int(FinalHQ.PRESET["subframes"]) >= 8 and int(FinalHQ.PRESET["accum"]) >= 2,
		"  FinalHQ.PRESET: dof %s, subframes %s, accum %s" % [FinalHQ.PRESET["dof"], FinalHQ.PRESET["subframes"], FinalHQ.PRESET["accum"]])
	ok(r_back == r_orig, "  restore() puts the original back exactly")
	svp5.queue_free()

	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var S := Scene.new()
	S.name = "zz_render1"
	S.fps = 30
	for i in 3:
		var R := Body.new()
		R.load_files("res://data/skeleton.json", "res://data/body_limits.json")
		R.set_ang("thigh_l", Vector3([0.0, 70.0, -25.0][i], 0, 0))
		R.fk()
		S.add("c%d" % i, R.to_dict())
		S.cards[i]["move"] = 0.8
		S.cards[i]["hold"] = 0.6 if i < 2 else 0.0
	m.S = S
	m._rebuild_cards()
	m.sel_card = 0
	m.playhead = 0.5
	m._refresh()
	await idle(3)
	S.shots = [{"t": 0.0, "name": "Wide", "keys": [{"t": 0.0, "pos": Vector3(2.8, 1.3, -1.2), "aim": Vector3(0, 1.0, 0), "f": 50.0}]}]
	m._final_render_dialog()
	await idle(2)
	var opt: OptionButton = m.ui_fr_dlg.find_child("opt_preset", true, false)
	var names := []
	if opt != null:
		for i in opt.item_count:
			names.append(opt.get_item_text(i))
	ok(opt != null and names.has("Draft") and names.has("Final") and names.has("Final HQ"), "  the Final render dialog has the quality list %s" % [names])
	m.ui_fr_dlg.hide()
	ok("final_render" in AgentTools.MCP_EXTRA, "  final_render is in AgentTools.MCP_EXTRA")
	ok(FileAccess.get_file_as_string("res://tools/mcp/poser_mcp.py").contains("\"final_render\""), "  final_render is in tools/mcp/poser_mcp.py")
	var tmp := OS.get_environment("TEMP").replace("\\", "/")
	if tmp == "":
		tmp = "/tmp"
	var out_root := "%s/render1_%d" % [tmp, OS.get_process_id()]
	DirAccess.make_dir_recursive_absolute(out_root)
	var at := AgentTools.new(m)
	var rsp: Dictionary = await at.request(1, "final_render", {"preset": "final_hq", "w": 480, "h": 270, "first": 34, "count": 2, "out": out_root, "subframes": 8, "accum": 2})
	var rr: Dictionary = rsp.get("result", {})
	var dir := String(rr.get("dir", ""))
	var pngs := Array(DirAccess.get_files_at(dir)).filter(func(f): return String(f).ends_with(".png")) if dir != "" else []
	var sz_ok := not pngs.is_empty()
	for f in pngs:
		var im := Image.load_from_file(dir + "/" + f)
		sz_ok = sz_ok and im != null and im.get_width() == 480 and im.get_height() == 270
	ok(rsp.has("result") and pngs.size() == 2 and sz_ok and dir.begins_with(out_root), "  the agent tool final_render made %d PNGs at 480x270 under the path given (%s)" % [pngs.size(), dir.get_file()])
	var bad: Dictionary = await at.request(2, "final_render", {"preset": "bogus"})
	ok(bad.has("error"), "  CONTROL: an unknown preset is refused")

	# ------------------------------------------------------------ bar 6: the picture
	if not pngs.is_empty():
		var img := Image.load_from_file(dir + "/" + pngs[0])
		img.resize(960, 540, Image.INTERPOLATE_LANCZOS)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/out"))
		img.save_png(ProjectSettings.globalize_path("res://tests/out/render1_final.png"))
		ok(FileAccess.file_exists("res://tests/out/render1_final.png") and img.get_width() <= 1000, "6 tests/out/render1_final.png written (%dx%d)" % [img.get_width(), img.get_height()])
	else:
		ok(false, "6 no frame to save")
	print("\nrender1: %s" % ("ALL OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails > 0 else 0)
