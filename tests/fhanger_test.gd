extends SceneTree
## FHANGER (Nick 2026-10-28: "free 3D building, like Fusion 360"): a beginner builds a CLOTHES HANGER from the BUILDING card, real clicks at 1280x720.
## Walk (Easy only, no Expert): BUILDING -> Draw shape (Round chip) + drag a small disc -> Curvy line (the hanger wire, an OPEN V) ->
##   Sweep along (the disc goes along the wire: one solid) -> Curvy line (a small HOOK at the top of the V) -> Sweep along (the hook) -> one Undo.
## shots: C:/Temp/claude/fhanger/
const SHOT := "C:/Temp/claude/fhanger"
const DIRT := "user://fhanger_test"

var fails := 0
var m: Node


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


func ev_move(p: Vector2, held := true) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


## a real press, a drag through the points (8 steps a segment), a release
func drag_path(pts: Array) -> void:
	await ev_move(pts[0], false)
	await ev_mouse(pts[0], true)
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		for k in range(1, 9):
			await ev_move(a.lerp(b, k / 8.0))
	await ev_mouse(pts[pts.size() - 1], false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func texts_under(n: Node, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Label and (n as Label).text.strip_edges() != "":
		out.append((n as Label).text)
	elif n is Button and (n as Button).text.strip_edges() != "":
		out.append((n as Button).text)
	for c in n.get_children():
		texts_under(c, out)


func pu():
	return m.bld.part


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


## world floor points (metres, x and z) as screen points
func floor_px(pts: Array) -> Array:
	var out := []
	for p in pts:
		out.append(scr(Vector3(p.x, 0.0, p.y)))
	return out


func sweeps_of(rec: Dictionary) -> Array:
	var out := []
	for f in rec.get("features", []):
		if f["t"] == "sweep":
			out.append(f)
	return out


func _init() -> void:
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
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return

	# 0 the BUILDING card, one click
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(50)
	await shot("01_open")
	ok(m.cur_page == "BUILD" and m.S.kind == "building" and pu().on and pu().easy and (m.S.part.get("features", []) as Array).is_empty(),
		"0 BUILDING card, one click -> Easy Part on, the part is empty (page %s)" % m.cur_page)
	var ep = pu().ep
	m.target = Vector3.ZERO
	m.pitch = -35.0
	m.yaw = 20.0
	m._cam()
	await idle(60)

	# 1 Draw shape, Round chip, a real drag: a small disc (the wire's cross-section) off to the side of the hanger
	# design changed in P153 (symmetry on by default; d92c83b4 p153symmetryon): a shape drawn off the middle line also gets a twin on the other side,
	# and a profile of two separate circles is not one closed profile for a sweep; bar fixture fixed 11-01 per Nick: the wire's cross-section is ONE disc
	# (press "One side only", which ends Draw shape, then Draw shape and Round again)
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.one_side_btn)
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["round"])
	var c0 := scr(Vector3(0.22, 0.0, -0.05))
	var c1 := scr(Vector3(0.22 + 0.006, 0.0, -0.05))
	await drag_path([c0, c1])
	await shot("02_disc")
	var rad := -1.0
	for f in pu()._ensure().get("features", []):
		if f.get("t", "") == "sketch":
			for e in f.get("ents", []):
				if String(e.get("k", "")) == "circle":
					rad = float(e["r"])
	ok(rad >= 5.0, "1 Round chip + a real drag draws a round shape (circle r %.1f mm)" % rad)

	# 2 the wire: an OPEN Curvy line in a V (two arms, the apex in the middle), drawn by a real drag
	await click_ctl(ep.make_btns["curve"])
	var wire_pts := [Vector2(-0.10, -0.02), Vector2(0.0, -0.08), Vector2(0.10, -0.02)]
	await drag_path(floor_px(wire_pts))
	await shot("03_wire")
	var say: String = ep.hint_l.text
	# design changed in 8997d0ac P026 (Pull along): the "Sweep along" chip became "Pull along"; bar rewritten 11-01 per Nick: same check on the new name
	ok(say.find("Pull along") >= 0 and say.find("pipe") >= 0, "2 an open Curvy line names the Pull along step (%s)" % say)

	# 3 Sweep along (a real click): one sweep step, one solid, volume = pi r^2 L of the wire
	var rec_w: Dictionary = pu()._ensure()
	var n_before := sweeps_of(rec_w).size()
	var wire_id := String(pu()._sketch_ids(rec_w)[-1])
	var wire_ents: Array = Part.feature(rec_w, wire_id).get("ents", [])
	var rcut := maxf(2.0, 1.5 * rad)
	var wlen: float = float(Part.sweep_path(wire_ents, rcut)["len"]) if wire_ents.size() == 1 else 0.0
	var v0: float = float(Part.replay(rec_w)["volume"])
	var sb = ep.get("pull_along_btn")   # the Pull along chip (P026; it was the Sweep along chip)
	ok(sb != null and sb.visible, "2b the Pull along chip shows while a round shape and an open Curvy line wait")
	if sb != null and sb.visible:
		await click_ctl(sb)
		await idle(20)
	await shot("04_wire_swept")
	var rec_a: Dictionary = pu()._ensure()
	var n_a := sweeps_of(rec_a).size()
	var res_a: Dictionary = pu().res
	var v1: float = float(Part.replay(rec_a)["volume"])
	var want := PI * rad * rad * wlen * 1e-9
	ok(n_a == n_before + 1 and int(res_a.get("bodies", 0)) == 1 and (res_a.get("errors", {}) as Dictionary).is_empty()
		and absf((v1 - v0) - want) <= 0.03 * want,
		"3 Pull along: one sweep step, one solid, no error, adds %.0f mm3 (want pi r^2 L = %.0f mm3)" % [(v1 - v0) * 1e9, want * 1e9])

	# 4 the hook: a second open Curvy line from the apex of the V, up the -z side and over (a J), then Sweep along again
	await click_ctl(ep.make_btns["curve"])
	var hook_pts := [Vector2(0.0, -0.08), Vector2(0.0, -0.105), Vector2(0.015, -0.12), Vector2(0.03, -0.105), Vector2(0.03, -0.09)]
	await drag_path(floor_px(hook_pts))
	var sb2 = ep.get("pull_along_btn")
	if sb2 != null and sb2.visible:
		await click_ctl(sb2)
		await idle(20)
	await shot("05_hook")
	var rec_h: Dictionary = pu()._ensure()
	var sw_h := sweeps_of(rec_h)
	var hook_id := String(pu()._sketch_ids(rec_h)[-1])
	var hook_ents: Array = Part.feature(rec_h, hook_id).get("ents", [])
	var hlen: float = float(Part.sweep_path(hook_ents, rcut)["len"]) if hook_ents.size() == 1 else 0.0
	var v2: float = float(Part.replay(rec_h)["volume"])
	var want_h := PI * rad * rad * hlen * 1e-9
	var bb: AABB = pu().res.get("aabb", AABB())
	var top_z := bb.position.z
	ok(sw_h.size() == 2 and int(pu().res.get("bodies", 0)) == 1 and (pu().res.get("errors", {}) as Dictionary).is_empty()
		and hlen > 0.0 and absf((v2 - v1) - want_h) <= 0.05 * want_h and top_z <= -0.115,
		"4 hook: a second sweep, one solid, reaches z %.1f mm, adds %.0f mm3 (want %.0f mm3)" % [top_z * 1000.0, (v2 - v1) * 1e9, want_h * 1e9])

	# 5 one Undo takes back only the hook
	await click_ctl(ep.undo_btn)
	await idle(20)
	await shot("06_undo")
	var rec_u: Dictionary = pu()._ensure()
	ok(sweeps_of(rec_u).size() == 1 and int(pu().res.get("bodies", 0)) == 1 and absf(float(Part.replay(rec_u)["volume"]) - v1) <= 1e-12,
		"5 one Undo takes back only the hook (sweeps %d, back to the wire)" % sweeps_of(rec_u).size())

	# 6 the words on screen are plain
	var seen: Array = []
	texts_under(m, seen)
	var bad: Array = []
	for t in seen:
		var low := String(t).to_lower()
		for w in ["profile", "spline", "normal", "chain", "sketch", "kernel", "bspline", "body", "extrude", "feature"]:
			if low.find(w) >= 0:
				bad.append(String(t))
	ok(bad.is_empty(), "6 plain words on screen (no profile / spline / sketch / body: %s)" % str(bad.slice(0, 3)))

	print("fhanger: %d FAIL" % fails)
	print("FHANGER: %s" % ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)
