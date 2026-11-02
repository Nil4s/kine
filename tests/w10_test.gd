## godot --path . -s tests/w10_test.gd     (W10: cut / join failure helper; real clicks on the panel)
## BARS (written before the run): two boxes touching at one edge: Join says "line" + offers the nudge, counted bodies 2 before the nudge
## (control: raw union is NOT 1), the nudge click gives 1 counted body; face-touching boxes join to 1; Undo after the nudge is ONE step
## back to the original 2 parts; Cut/Overlap on the edge pair say "line"; New part keeps 2; Overlap of a real overlap is the shared volume.
extends SceneTree

const KCad := preload("res://scripts/kcad.gd")
const JH := preload("res://scripts/build/join_helper.gd")
const UI := preload("res://scripts/build/join_helper_ui.gd")
var fails := 0
const OUT := "C:/Users/Nick/tools/kine_workers/out/w10"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func click(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	for d in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = d
		e.position = p
		e.global_position = p
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if d else 0
		root.push_input(e)
		await idle(2)


func box_at(x: float, y: float) -> int:
	return KCad.translate(KCad.box(0.01, 0.01, 0.01), Vector3(x, y, 0))


func panel(a: int, b: int, size: Vector2i) -> UI:
	root.size = size
	var p := UI.new()
	p.position = Vector2(20, 20)
	root.add_child(p)
	p.setup(a, b)
	return p


func _init() -> void:
	if not KCad.available():
		print("SKIP no KineCAD DLL")
		print("w10: 0 fail")
		quit(0)
		return
	# --- logic ---
	var a := KCad.box(0.01, 0.01, 0.01)
	var e := box_at(0.01, 0.01)
	var f := box_at(0.01, 0.0)
	var raw := KCad.union(a, e)
	ok(JH.lumps(raw) == 2, "control: the raw union of the edge pair counts 2 lumps (the id count says 1 - the check is not vacuous)")
	ok(JH.lumps(a) == 1, "control: one box counts 1")
	ok(JH.contact(a, e)["kind"] == "line", "edge pair is a line contact")
	ok(JH.contact(a, f)["kind"] == "face", "face pair is a face contact")
	var rf := JH.run(a, f, "join")
	ok(rf["ok"] and rf["count"] == 1, "face-touching boxes join to 1 body (counted %s)" % rf["count"])
	var re := JH.run(a, e, "join")
	ok(not re["ok"] and re["nudge"] and "line" in re["message"], "edge Join refuses and says line + offers nudge: " + re["message"])
	ok(is_equal_approx(absf(re["nudge_by"].x), JH.NUDGE) and is_equal_approx(absf(re["nudge_by"].y), JH.NUDGE) and re["nudge_by"].z == 0.0, "nudge is 0.01 mm on the two touching axes only")
	ok(not JH.run(a, e, "cut")["ok"] and "line" in JH.run(a, e, "cut")["message"], "Cut on the edge pair says line")
	ok(not JH.run(a, e, "overlap")["ok"], "Overlap on the edge pair finds nothing")
	var rn := JH.run(a, e, "new")
	ok(rn["ok"] and rn["count"] == 2 and rn["bodies"].size() == 2, "New part keeps 2")
	var ov := box_at(0.005, 0.0)
	var ro := JH.run(a, ov, "overlap")
	ok(ro["ok"] and absf(KCad.volume(ro["bodies"][0]) - 0.5e-6) < 1e-9, "Overlap of a real overlap is the shared half")
	var rc := JH.run(a, ov, "cut")
	ok(rc["ok"] and absf(KCad.volume(rc["bodies"][0]) - 0.5e-6) < 1e-9, "Cut removes the overlapping half")
	# --- real clicks, two window sizes ---
	for sz in [Vector2i(1024, 600), Vector2i(1920, 1080)]:
		var p := panel(box_at(0, 0), box_at(0.01, 0.01), sz)
		await idle(3)
		ok(p.body_count() == 2, "%s: starts with 2 bodies" % str(sz))
		await click(p.mode_btns["join"])
		ok(not p.nudge_btn.visible == false and "line" in p.status.text, "%s: Join click -> line message + nudge button shown" % str(sz))
		ok(p.history.is_empty(), "failed Join made no history entry")
		root.get_viewport().get_texture().get_image().save_png("%s/before_%d.png" % [OUT, sz.x])
		await click(p.nudge_btn)
		ok(p.parts.size() == 1 and p.body_count() == 1, "%s: nudge click -> 1 body counted (%d)" % [str(sz), p.body_count()])
		ok(p.history.size() == 1, "nudge+join is ONE history entry")
		root.get_viewport().get_texture().get_image().save_png("%s/after_%d.png" % [OUT, sz.x])
		await click(p.undo_btn)
		ok(p.parts.size() == 2 and p.history.is_empty() and p.body_count() == 2, "%s: ONE Undo returns the original 2 parts" % str(sz))
		var v := KCad.volume(p.parts[1])
		ok(absf(v - 1e-6) < 1e-12, "undo gives the un-nudged tool")
		p.queue_free()
		await idle(2)
	print("w10: %d fail" % fails)
	quit(1 if fails > 0 else 0)
