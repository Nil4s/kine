extends SceneTree
## S242 LOOK FACTS (agent look_facts, scripts/build/look_facts.gd): numbers for how the final picture looks, from an ID pass + the temple light.
## Fixture: grey ground, a red 2 m box on the axis, a hider with a small box behind it, a dark grid on a dark back, a light grid on a dark back, one ginkgo.
##   1 COLOUR    the red box: hue within 12 deg of its material's, saturation 0.55..1.0
##   2 COVERAGE  px within 6 % of its projected front face (pinhole maths at the mask size)
##   3 HIDDEN    a box behind a bigger one reports visible 0 with the hider named; a box in the open reports visible 1.0
##   4 CONTRAST  dark bars on a dark back: contrast < 0.08 (reads flat); light bars on the same back: > 0.3 (the control: the bar can fail)
##   5 NATURE    the ginkgo's canopy hue is within 25 deg of the mean hue of its leaf colours
##   6 UNCHANGED the scene record, the camera, the undo stack and the temple light are what they were
##   7 SPEED     one call under 5 s on the fixture
## Debug masks (shaded.png, ids.png, overlay.png): C:/Users/Nick/tools/kine_workers/out/242/
var fails := 0
var m: Node
const SHOT := "C:/Users/Nick/tools/kine_workers/out/242"
const DIRT := "user://s242_test"
var rec := {}
var nb := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ev_mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func add(t: String, f: Dictionary) -> String:
	var nf := Part.new_feature(rec, t, f)
	(rec["features"] as Array).append(nf)
	return String(nf["id"])


func box(x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, nm: String, c: Color) -> void:
	var pl := "top"
	if absf(y0) > 0.0001:
		pl = add("plane", {"from": "top", "mm": y0})
	var sk := add("sketch", {"plane": pl, "ents": [{"k": "rect", "a": [x0, -z1], "b": [x1, -z0]}], "dims": []})
	add("extrude", {"sketch": sk, "dist": y1 - y0, "both": false, "op": "new"})
	add("bname", {"body": nb, "called": nm})
	add("appear", {"name": "Look" + nm, "body": nb, "preset": "Custom", "color": [c.r, c.g, c.b], "rough": 0.9, "metal": 0.0, "alpha": 1.0})
	nb += 1


func fixture() -> Dictionary:
	rec = Part.make("Look facts")
	nb = 0
	var dark := Color(0.08, 0.08, 0.08)
	box(-40000, 40000, -100, 0, -40000, 40000, "Grey ground", Color(0.5, 0.5, 0.5))
	box(-1000, 1000, 0, 2000, -1000, 1000, "Red box", Color(0.8, 0.1, 0.1))
	box(6000, 10000, 0, 3000, 3000, 3200, "Hider", Color(0.3, 0.4, 0.7))
	box(7500, 8500, 0, 1000, -3200, -3000, "Behind", Color(0.9, 0.8, 0.2))
	box(-5000, -3000, 0, 1000, 0, 400, "Open box", Color(0.2, 0.7, 0.3))
	box(-16000, -12000, 0, 3000, -6000, -5900, "Dark back", dark)
	for k in 3:
		box(-15500 + k * 1300, -15300 + k * 1300, 0, 3000, -5900, -5700, "Dark bars %d" % (k + 1), dark)
	box(12000, 16000, 0, 3000, -6000, -5900, "Light back", dark)
	for k in 3:
		box(12500 + k * 1300, 12700 + k * 1300, 0, 3000, -5900, -5700, "Light bars %d" % (k + 1), Color(0.9, 0.9, 0.9))
	return rec


func state_sig() -> String:
	var c: Camera3D = m.cam
	return JSON.stringify([m.S.part, m.S.building, str(c.global_transform), c.fov, m.undo.size(), TempleLight.on, TempleLight.settings_dict(), Realistic.live_on])


func hue_diff(a: float, b: float) -> float:
	var d := fposmod(a - b, 360.0)
	return minf(d, 360.0 - d)


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT)
	if not Part.available():
		print("FAIL: no KineCAD DLL")
		quit(1)
		return
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	var cb: Control = ss._easy_btn["building"]
	var pt := cb.get_global_rect().get_center()
	await ev_mouse(pt, true)
	await ev_mouse(pt, false)
	await idle(3)
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	var pu: PartUI = m.bld.part
	m.S.part = fixture()
	pu.upto = -1
	pu.sync()
	await idle(40)
	if m.grid_node != null:
		m.grid_node.visible = false
	print("bodies ", pu.res.get("bodies", -1))
	var nr: Dictionary = NatureAgent.serve(m, {"op": "add", "item": {"kind": "tree", "species": "ginkgo", "season": "amber", "x": -9.0, "z": -2.0, "height": 6.0}})
	var tid := String(nr.get("id", ""))
	await idle(20)
	var cam := {"pos": [0.0, 1.5, 32.0], "target": [0.0, 1.5, 0.0], "fov": 45.0}
	TempleLight.set_camera(m, Vector3(0, 1.5, 32), Vector3(0, 1.5, 0), 45.0)
	await idle(5)
	var before := state_sig()
	var t0 := Time.get_ticks_msec()
	var r: Dictionary = await LookFacts.serve(m, {"camera": cam, "debug_dir": SHOT, "targets": [
		{"piece": "Red box"}, {"piece": "Hider"}, {"piece": "Behind"}, {"piece": "Open box"},
		{"piece": "Dark bars", "vs": {"piece": "Dark back"}}, {"piece": "Light bars", "vs": {"piece": "Light back"}},
		{"nature": tid, "part": "canopy"}, {"nature": tid, "part": "trunk"}]})
	var ms := Time.get_ticks_msec() - t0
	ok(bool(r["ok"]), "call ok " + String(r.get("error", "")))
	if not bool(r["ok"]):
		quit(1)
		return
	var after := state_sig()
	print(JSON.stringify(r["facts"][0]))
	for line in r["verdicts"]:
		print("   ", line)
	var F := {}
	for f in r["facts"]:
		F[String(f["label"])] = f
	var W: int = r["size"][0]
	var H: int = r["size"][1]
	var red: Dictionary = F["Red box"]
	var mat_col := Color(0.8, 0.1, 0.1)
	var hd := hue_diff(float(red["hue_deg"]), mat_col.h * 360.0)
	ok(hd <= 12.0 and float(red["sat"]) >= 0.55 and float(red["sat"]) <= 1.0, "1 red box hue %.1f deg (material %.1f, diff %.1f <= 12) sat %.2f in 0.55..1.0 (material %.2f)" % [red["hue_deg"], mat_col.h * 360.0, hd, red["sat"], mat_col.s])
	var fpx := (H * 0.5) / tan(deg_to_rad(45.0) * 0.5)
	var expect := pow(2.0 * fpx / 31.0, 2.0)   # the front face at z = +1 m: 31 m from the camera
	var err := absf(float(red["px"]) - expect) / expect
	ok(err <= 0.06, "2 red box coverage %d px vs projected %.0f px (%.1f %% off, <= 6 %%)" % [red["px"], expect, err * 100.0])
	var bh: Dictionary = F["Behind"]
	var hb: Array = bh.get("hidden_by", [])
	ok(int(bh["px"]) == 0 and float(bh["visible"]) == 0.0 and int(bh["solo_px"]) > 0 and hb.size() > 0 and String(hb[0]["by"]) == "Hider", "3 'Behind' visible %.2f, would cover %d px, hidden by %s" % [bh["visible"], bh["solo_px"], str(hb)])
	ok(float(F["Open box"]["visible"]) >= 0.99, "3 control: 'Open box' visible %.3f" % F["Open box"]["visible"])
	var dv: float = F["Dark bars"]["vs"]["contrast"]
	var lv: float = F["Light bars"]["vs"]["contrast"]
	ok(dv < 0.08, "4 dark bars on a dark back: contrast %.3f < 0.08" % dv)
	ok(lv > 0.3, "4 control: light bars on the same dark back: contrast %.3f > 0.3" % lv)
	var tree := Nature.make_tree(NatureAgent.serve(m, {"op": "list"})["items"][0])
	var hs := 0.0
	var hc := 0.0
	for c in tree["leaf_col"]:
		hs += sin((c as Color).h * TAU)
		hc += cos((c as Color).h * TAU)
	var want_h := fposmod(rad_to_deg(atan2(hs, hc)), 360.0)
	var can: Dictionary = F["%s canopy" % tid]
	ok(int(can["px"]) > 200 and hue_diff(float(can["hue_deg"]), want_h) <= 25.0, "5 ginkgo canopy hue %.1f (%s) vs leaf colours' mean %.1f: %.1f deg off (<= 25), %d px" % [can["hue_deg"], can["hue_name"], want_h, hue_diff(float(can["hue_deg"]), want_h), can["px"]])
	ok(after == before, "6 scene, camera, undo stack and temple light unchanged")
	print("call ms ", ms, " (shot ms ", r["shot_ms"], ") at ", W, " x ", H)
	ok(ms < 5000, "7 one call %d ms < 5000" % ms)
	var t1 := Time.get_ticks_msec()
	var r2: Dictionary = await LookFacts.serve(m, {"camera": cam})
	ok(bool(r2["ok"]) and (r2["facts"] as Array).size() >= 5, "8 no target: %d facts in %d ms" % [(r2["facts"] as Array).size() if r2.has("facts") else -1, Time.get_ticks_msec() - t1])
	var r3: Dictionary = await LookFacts.serve(m, {"piece": "No such piece"})
	ok(not bool(r3["ok"]), "9 an unknown piece is an error naming the pieces: " + String(r3.get("error", "")).left(90))
	print("s242: %d fail" % fails)
	quit(1 if fails > 0 else 0)
