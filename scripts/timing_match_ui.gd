## MATCH THE REFERENCE'S TIMING panel (ROADMAP I29; the maths: scripts/timing_match.gd). Kept out of main.gd: main makes one
## (main.tm_ui), lists its command and its ribbon button (ANIMATE > STYLE), nothing else.
##   Reference...  opens a Poser scene (an imported video clip, scenes/_wip/*.json) as the reference
##   Preview       computes both speed curves and the matched events and DRAWS them; the open clip is not touched
##   Accept        retimes the cards (poses untouched) on the matched events: ONE undo step. Close drops the preview.
## The overlay: the reference's curve grey, the clip before amber, the clip after (the preview, on a copy) blue; a thin line joins
## each matched pair of events, a cross marks an event with no partner (skipped).
class_name TimingMatchUI
extends RefCounted

var m: Node
var ref: Scene = null
var ref_name := ""
var plan: Dictionary = {}          # TimingMatch.plan of the last Preview
var after: Dictionary = {}         # the speed curve of the clip with the plan applied (on a copy)
var _over: Control
var _note: Label


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Match the reference timing", "", show, "match reference timing video speed peaks strikes holds retime align dtw events cards",
		false, "retimes the open clip's cards so its strikes and holds land when the reference video's do: both limb-speed curves are drawn, matched events joined; poses are not touched; Preview first, Accept = one undo step")


func set_reference(R: Scene, nm := "reference") -> void:
	ref = R
	ref_name = nm
	plan = {}
	after = {}
	_redraw()


func pick_reference() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.json ; Poser scenes"])
	fd.use_native_dialog = true
	fd.title = "The reference: a scene made from a video"
	fd.file_selected.connect(func(p): load_reference(p); fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	m.add_child(fd)
	fd.popup_centered(Vector2i(800, 500))


func load_reference(path: String) -> bool:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not (d is Dictionary) or not (d as Dictionary).has("cards"):
		m._say("could not read %s as a scene: pick a scene made from a video (scenes/_wip, from From video) as the reference" % path.get_file())
		return false
	var R := Scene.new()
	R.from_dict(d)
	set_reference(R, path.get_file())
	m._say("reference: %s (%.2f s). Press Preview to see both speed curves" % [ref_name, R.length()])
	return true


func show() -> void:
	if m.S.cards.size() < 2:
		m._say("Match the reference timing needs a clip of two cards or more: press Enter to add the body as a card (two at least), or open a scene in the list below")
		return
	var L: VBoxContainer = m.ui_find_list
	for c in L.get_children():
		L.remove_child(c)
		c.queue_free()
	var head := HBoxContainer.new()
	L.add_child(head)
	var title: Label = m._label("MATCH THE REFERENCE TIMING", 18, "heading")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(m._button("Close", close))
	L.add_child(m._label("Pick the reference (a scene made from a video). Preview draws both limb-speed curves and the events that match; Accept retimes your cards to them (one Ctrl+Z). Poses are not changed.", 13, "text:0.6", true))
	var row := HBoxContainer.new()
	var rb: Button = m._button("Reference...", pick_reference, "open the scene made from the reference video")
	rb.name = "tm_ref"
	row.add_child(rb)
	var pb: Button = m._button("Preview", preview, "compute and draw both speed curves and the matched events; nothing is changed")
	pb.name = "tm_preview"
	row.add_child(pb)
	var ab: Button = m._button("Accept", accept, "retime the cards to the reference (poses untouched): one undo step")
	ab.name = "tm_accept"
	row.add_child(ab)
	L.add_child(row)
	_over = TMOverlay.new()
	_over.name = "tm_overlay"
	_over.ui = self
	_over.custom_minimum_size = Vector2(330, 150)
	L.add_child(_over)
	_note = m._label("", 12, "text:0.5", true)
	_note.name = "tm_note"
	L.add_child(_note)
	_text()
	(m.ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(350, 420)
	m.ui_find.visible = true
	m._say("match the reference timing: pick the reference, press Preview, then Accept (Ctrl+Z undoes it)")


func close() -> void:
	plan = {}
	after = {}
	m._close_findings()


func _text() -> void:
	if _note == null or not is_instance_valid(_note):
		return
	if ref == null:
		_note.text = "no reference yet: press Reference... and pick the scene made from the video"
	elif plan.is_empty():
		_note.text = "reference: %s (%.2f s). Press Preview" % [ref_name, ref.length()]
	else:
		var al: Dictionary = plan["al"]
		_note.text = "%d events matched, %d of yours and %d of the reference's left out; the clip %.2f s -> %.2f s" % [
			(plan["anc"] as Array).size(), (al["skip_clip"] as Array).size(), (al["skip_ref"] as Array).size(), m.S.length(), float(after.get("end", m.S.length()))]


func _redraw() -> void:
	_text()
	if _over != null and is_instance_valid(_over):
		_over.queue_redraw()


## computes the plan and the clip's curve after it, on a COPY: the open clip is not touched
func preview() -> bool:
	if ref == null:
		m._say("pick the reference first: press Reference... and choose the scene made from the video")
		return false
	if m.S.cards.size() < 2:
		m._say("the clip needs two cards or more: press Enter to add the body as a card")
		return false
	plan = TimingMatch.plan(m.S, ref, m.B)
	if (plan["anc"] as Array).is_empty():
		after = {}
		m._say("no events could be matched: the clip or the reference barely moves (no speed peaks). Pick a reference with strikes or actions, or a clip with motion")
		_redraw()
		return false
	var C: Scene = m.S.clone()
	TimingMatch.apply(C, plan["anc"])
	after = TimingMatch.speed_curve(C, m.B)
	after["end"] = C.length()
	_redraw()
	m._say("preview: %d events matched (Accept retimes the cards, Ctrl+Z undoes it)" % (plan["anc"] as Array).size())
	return true


## the retime: ONE undo step. "" = done, else what was wrong
func accept() -> String:
	if plan.is_empty() or (plan["anc"] as Array).is_empty():
		m._say("press Preview first: it shows what will move, then Accept applies it")
		return "no preview"
	m._step_hint = "Match the reference timing"
	m._push_undo()
	m._markers_hold()
	TimingMatch.apply(m.S, plan["anc"], false)
	m._markers_follow()
	m._retimed()
	m.ui_find.visible = true   # _retimed hides the findings; this panel is the match itself
	plan = {}
	after = {}
	_redraw()
	m._say("cards retimed to the reference: the clip is now %.2f s. Ctrl+Z takes it back in one step" % m.S.length())
	return ""


## the overlay: drawn from the UI's plan / after
class TMOverlay extends Control:
	var ui: TimingMatchUI

	func _curve(c: Dictionary, col: Color, x0: float, w: float, t1: float, y0: float, h: float, vmax: float, wd: float) -> void:
		if c.is_empty():
			return
		var t: PackedFloat32Array = c["t"]
		var v: PackedFloat32Array = c["v"]
		var pts := PackedVector2Array()
		for i in t.size():
			pts.append(Vector2(x0 + t[i] / t1 * w, y0 + h - v[i] / vmax * h))
		if pts.size() > 1:
			draw_polyline(pts, col, wd, true)

	func _draw() -> void:
		var f := get_theme_default_font()
		draw_rect(Rect2(Vector2.ZERO, size), Tok.c("tl_bg"))
		var pl: Dictionary = ui.plan
		if pl.is_empty():
			draw_string(f, Vector2(10, size.y * 0.5), "Preview draws the speed curves here", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Tok.dim(0.6))
			return
		var x0 := 8.0
		var w := size.x - 16.0
		var y0 := 18.0
		var h := size.y - 40.0
		var t1 := 0.1
		var vmax := 0.1
		for c in [pl["cr"], pl["cc"], ui.after]:
			if (c as Dictionary).is_empty():
				continue
			t1 = maxf(t1, float((c["t"] as PackedFloat32Array)[-1]))
			for x in (c["v"] as PackedFloat32Array):
				vmax = maxf(vmax, x)
		var grey := Tok.dim(0.55)
		var amber := Tok.c("onion_past")
		var blue := Tok.c("pick_sel")
		# matched pairs: a line from the clip's event (before) to the reference's, along the top
		var ec: Array = pl["ec"]
		var er: Array = pl["er"]
		var al: Dictionary = pl["al"]
		for p in al["pairs"]:
			var xa := x0 + float(ec[p[0]]["t"]) / t1 * w
			var xb := x0 + float(er[p[1]]["t"]) / t1 * w
			draw_line(Vector2(xb, y0), Vector2(xb, y0 + h), Color(blue, 0.35), 1.0)
			draw_line(Vector2(xa, y0 + h * 0.5), Vector2(xb, y0), Color(Tok.c("ink"), 0.55), 1.0)
		for i in al["skip_clip"]:
			var x := x0 + float(ec[i]["t"]) / t1 * w
			draw_string(f, Vector2(x - 4, y0 + h + 2), "x", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, amber)
		for j in al["skip_ref"]:
			var x2 := x0 + float(er[j]["t"]) / t1 * w
			draw_string(f, Vector2(x2 - 4, y0 + 10), "x", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, grey)
		_curve(pl["cr"], grey, x0, w, t1, y0, h, vmax, 2.0)
		_curve(pl["cc"], amber, x0, w, t1, y0, h, vmax, 1.5)
		_curve(ui.after, blue, x0, w, t1, y0, h, vmax, 2.0)
		draw_line(Vector2(x0, y0 + h), Vector2(x0 + w, y0 + h), Tok.dim(0.4), 1.0)
		var ly := size.y - 8.0
		draw_string(f, Vector2(x0, ly), "reference", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, grey)
		draw_string(f, Vector2(x0 + 80, ly), "your clip", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, amber)
		draw_string(f, Vector2(x0 + 160, ly), "after the match", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, blue)
		draw_string(f, Vector2(x0 + w - 70, ly), "%.1f s" % t1, HORIZONTAL_ALIGNMENT_RIGHT, 70, 12, Tok.dim(0.5))
