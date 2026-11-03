## C03 chips (Easy, in the newest-step chip box): Pull makes Join / New body, Mirror at an angle, Mirror in the face, Printer preset.
## Logic is in scripts/build/c03_tools.gd; ep is the EasyPart. Every chip is one undo step and changes nothing until pressed.
extends RefCounted

const T := preload("res://scripts/build/c03_tools.gd")
const Part := preload("res://scripts/build/part.gd")
const ANGLE := 45.0


## the four chips live in ONE floating panel of their own (a 2 x 2 grid low in the view, centred): it is not in any box the layout moves, so no
## existing control shifts (Easy's suites drag from fixed spots). It shows with a solid on the screen.
static func build(ep, _row: Control = null) -> void:
	var box := PanelContainer.new()
	box.name = "easypart_c03_box"
	box.visible = false
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	box.add_child(g)
	var specs := [
		["easypart_pull_newbody", "", "Pull it up joins the solid by default. Press to make the next pull its own New body instead (and the newest pull too)", pull_press],
		["easypart_mirror_angle", "Mirror at an angle", "Mirror the solid across a plane through the middle turned 45 degrees (the slider turns it)", angle_press],
		["easypart_mirror_face", "Mirror in the face", "Mirror the solid across the face you last drew on", face_press],
		["easypart_printer_preset", "", "Your printer: its name and the gap on each side that holes, lids and fasteners keep. Press to change it", printer_press],
	]
	for sp in specs:
		var b: Button = ep._big_btn(sp[0], sp[1], sp[2], func(): (sp[3] as Callable).call(ep))
		b.custom_minimum_size = Vector2(190, 36)
		b.add_theme_font_size_override("font_size", 14)
		g.add_child(b)
		if sp[0] == "easypart_pull_newbody":
			ep.set_meta("c03_pull", b)
		elif sp[0] == "easypart_printer_preset":
			ep.set_meta("c03_printer", b)
	ep.set_meta("c03_box", box)
	ep.m.get_tree().process_frame.connect(func():   # a full-screen dialog (What to build) is never covered by the panel
		var bc = ep.m.get("build_choose")
		if is_instance_valid(box) and box.visible and bc != null and bool(bc.get("open")):
			box.visible = false
		elif is_instance_valid(box) and box.visible and Engine.get_process_frames() % 12 == 0:
			place(box))   # the layout moves its boxes after a press: look again, so the panel never ends up over one
	sync(ep, false)


static func sync(ep, show := false) -> void:
	if ep.has_meta("c03_pull"):
		(ep.get_meta("c03_pull") as Button).text = "Pull makes: " + ("New body" if T.pull_new(ep._rec()) else "Join")
	if ep.has_meta("c03_printer"):
		(ep.get_meta("c03_printer") as Button).text = T.words(ep._rec()).replace("none", "any")
	if ep.has_meta("c03_box"):
		var box := ep.get_meta("c03_box") as Control
		if box.get_parent() == null and ep.tilt_box != null and ep.tilt_box.get_parent() != null:
			ep.tilt_box.get_parent().add_child(box)   # beside the other Easy boxes (the panel's own layer)
		box.visible = show and box.get_parent() != null
		if box.visible:
			place(box)


## Controls the panel must not cover: every visible button, label, slider and panel in the window except the panel itself, the controls it sits
## in, and the big background layers (a rect over 40 pct of the window is the scene, not a control)
static func blockers(box: Control) -> Array:
	var out: Array = []
	var win := Vector2(box.get_viewport().get_visible_rect().size)
	var stack: Array = [box.get_viewport()]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			if c == box:
				continue
			stack.append(c)
			if not (c is Control) or not (c as Control).is_visible_in_tree() or c.is_ancestor_of(box):
				continue
			if not (c is BaseButton or c is Label or c is Range or c is PanelContainer or c is LineEdit or c is RichTextLabel):
				continue
			if c is Label and (c as Label).text == "":
				continue
			var r := (c as Control).get_global_rect()
			if r.size.x < 2.0 or r.size.y < 2.0 or r.get_area() > 0.4 * win.x * win.y:
				continue
			out.append(r)
	return out


## the panel goes where it overlaps none of them (4 px apart), as far from the middle of the view (where the model stands) as the free room allows
static func place(box: Control) -> void:
	box.reset_size()
	var par := box.get_parent() as Control
	var vs: Vector2 = par.size
	var bl := blockers(box)
	var sz := box.size
	if box.has_meta("c03_placed") and box.get_meta("c03_vs") == vs and Rect2(Vector2.ZERO, vs).encloses(Rect2(box.position, sz)):   # sticky: it stays where it is while that place is still clear (a button must not slide under the mouse)
		var cur := Rect2(par.get_global_transform() * box.position, sz).grow(4.0)
		var clear := true
		for b in bl:
			if cur.intersects(b):
				clear = false
				break
		if clear:
			return
	box.set_meta("c03_placed", true)
	box.set_meta("c03_vs", vs)
	var mid := vs * 0.5
	var best := Vector2(-1, -1)
	var best_d := -1.0
	var y := 0.0
	while y <= vs.y - sz.y:
		var x := 0.0
		while x <= vs.x - sz.x:
			var r := Rect2(par.get_global_transform() * Vector2(x, y), sz).grow(4.0)
			var hit := false
			for b in bl:
				if r.intersects(b):
					hit = true
					break
			if not hit:
				var d := (Vector2(x, y) + sz * 0.5).distance_to(mid)
				if d > best_d:
					best_d = d
					best = Vector2(x, y)
			x += 12.0
		y += 12.0
	box.position = best if best.x >= 0.0 else Vector2(vs.x * 0.5 - sz.x * 0.5 - 90.0, vs.y - sz.y - 110.0)


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
