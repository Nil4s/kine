## C03 chips (Easy, in the newest-step chip box): Pull makes Join / New body, Mirror at an angle, Mirror in the face, Printer preset.
## Logic is in scripts/build/c03_tools.gd; ep is the EasyPart. Every chip is one undo step and changes nothing until pressed.
extends RefCounted

const T := preload("res://scripts/build/c03_tools.gd")
const Part := preload("res://scripts/build/part.gd")
const ANGLE := 45.0


static func build(ep, row: Control) -> void:
	var b = ep._big_btn("easypart_pull_newbody", "", "Pull it up joins the solid by default. Press to make the next pull its own New body instead (and the newest pull too)", func(): pull_press(ep))
	b.custom_minimum_size = Vector2(230, 44)
	row.add_child(b)
	ep.set_meta("c03_pull", b)
	var a = ep._big_btn("easypart_mirror_angle", "Mirror at an angle", "Mirror the solid across a plane through the middle turned 45 degrees (the slider turns it)", func(): angle_press(ep))
	a.custom_minimum_size = Vector2(230, 44)
	row.add_child(a)
	var fc = ep._big_btn("easypart_mirror_face", "Mirror in the face", "Mirror the solid across the face you last drew on", func(): face_press(ep))
	fc.custom_minimum_size = Vector2(230, 44)
	row.add_child(fc)
	var p = ep._big_btn("easypart_printer_preset", "", "Your printer: its name and the gap on each side that holes, lids and fasteners keep. Press to change it", func(): printer_press(ep))
	p.custom_minimum_size = Vector2(230, 44)
	row.add_child(p)
	ep.set_meta("c03_printer", p)
	sync(ep)


static func sync(ep) -> void:
	if ep.has_meta("c03_pull"):
		(ep.get_meta("c03_pull") as Button).text = "Pull makes: " + ("New body" if T.pull_new(ep._rec()) else "Join")
	if ep.has_meta("c03_printer"):
		(ep.get_meta("c03_printer") as Button).text = T.words(ep._rec()).replace("none", "any")


static func pull_press(ep) -> void:
	ep._begin("Pull makes New body" if not T.pull_new(ep._rec()) else "Pull makes Join")
	var rec: Dictionary = ep._rec().duplicate(true)
	var on := not T.pull_new(rec)
	rec["pull_new"] = on
	var last := T.last_pull(rec)
	var said := "the next pull is a New body" if on else "the next pull joins the solid"
	if not last.is_empty() and Part.sketch_used(rec, String(last.get("sketch", ""))) and last == (rec["features"] as Array)[-1]:
		if T.set_op(last, "new" if on else "join") == "":
			said = "the newest pull is a New body now" if on else "the newest pull joins the solid again"
	ep.m.S.part = rec
	ep._end()
	ep.pu.sync()
	sync(ep)
	ep._say("Pull makes %s: %s" % ["New body" if on else "Join", said])


static func angle_press(ep) -> void:
	if int(ep.pu.res.get("bodies", 0)) == 0:
		ep._say("Nothing solid to mirror yet. Press Pull it up first")
		return
	ep._begin("Mirror at an angle")
	var rec: Dictionary = ep._rec().duplicate(true)
	var pid := T.angle_plane(rec, ANGLE)
	var f := T.mirror_across(rec, pid)
	ep.m.S.part = rec
	var why: String = ep._last_error(rec, String(f["id"]))
	if why != "":
		ep.m._undo()
		ep._edit_n = -1
		ep._say("That cannot be mirrored across a plane at that angle")
		return
	ep.tweak = {"id": pid, "field": "deg", "label": "Mirror plane angle", "unit": "deg", "lo": -90.0, "hi": 90.0, "step": 5.0, "scale": 1.0, "words": ["Turn left", "Turn right"]}
	ep._end()
	ep.pu.sync()
	ep._say("Mirrored across a plane turned %d degrees: the slider turns it" % int(ANGLE))


static func face_press(ep) -> void:
	var pid := T.face_plane(ep._rec())
	if pid == "" or int(ep.pu.res.get("bodies", 0)) == 0:
		ep._say("Mirror in the face: draw a shape on a face of the solid first, then press this")
		return
	ep._begin("Mirror in the face")
	var rec: Dictionary = ep._rec().duplicate(true)
	var f := T.mirror_across(rec, pid)
	ep.m.S.part = rec
	if ep._last_error(rec, String(f["id"])) != "":
		ep.m._undo()
		ep._edit_n = -1
		ep._say("That face cannot be mirrored across")
		return
	ep._end()
	ep.pu.sync()
	ep._say("Mirrored across the face you drew on")


static func printer_press(ep) -> void:
	ep._begin("Printer preset")
	var rec: Dictionary = ep._rec().duplicate(true)
	T.apply(rec, T.next_index(rec))
	ep.m.S.part = rec
	ep._end()
	sync(ep)
	ep._say("%s. Holes, lids and fasteners keep that gap on each side" % T.words(rec))
