extends "res://scripts/easy_part_layout.gd"
## EASY PART STICK: the pieces. Stick together (click two pieces, then Join, Cut away or Keep the overlap), a click that picks a piece
## (its glow, Remove on the bar), and Cut in two with its keep chips (both halves, the lower one, the upper one).

## ECUT2: Cut in two keeps ONE half: three toggle chips after a Cut in two press. Both halves is the default (two bodies); the lower or upper half
## keeps only that side of the cut (one body). Each chip is one undo step; the slider still moves the cut
func _split_box() -> PanelContainer:
	var box := PanelContainer.new()
	box.name = "easypart_split"
	box.add_theme_stylebox_override("panel", _style(Color(0.1, 0.11, 0.14, 0.92), 10, 6))
	box.visible = false
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	box.add_child(h)
	for sk in [["both", "Keep both halves", "Keep both pieces of the cut (two bodies)"], ["lower", "Keep the lower half", "Keep only the half on the lower side of the cut (one body)"], ["upper", "Keep the upper half", "Keep only the half on the upper side of the cut (one body)"]]:
		var b := _big_btn("easypart_split_" + String(sk[0]), String(sk[1]), String(sk[2]), _split_keep.bind(String(sk[0])))
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(190, 44)
		h.add_child(b)
		split_btns[sk[0]] = b
	return box


## STICK TOGETHER: the three big buttons, shown once two pieces are picked in the view
func _stick_box() -> PanelContainer:
	var box := PanelContainer.new()
	box.name = "easypart_stick"
	box.add_theme_stylebox_override("panel", _style(Color(0.1, 0.11, 0.14, 0.92), 10, 6))
	box.visible = false
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	box.add_child(h)
	for so in STICK_OPS:
		var b := _big_btn("easypart_stick_" + String(so[0]), String(so[1]), String(so[2]), _stick.bind(String(so[0]), String(so[1])))
		b.custom_minimum_size = Vector2(150, 44)
		h.add_child(b)
		stick_btns[so[0]] = b
	return box


## CUT IN TWO: a split across the middle of the solid's longest side (Part's "split" feature, the one Expert's Split makes). The slider
## moves the cut along that side: its step is the split, its field the offset in mm (the slider says cm)
func _cut(rec: Dictionary) -> String:
	var res := Part.replay(rec)
	if int(res["bodies"]) == 0:
		return "Nothing solid to cut yet. Press Pull it up first"
	var bb: AABB = res["aabb"]
	var ax := 0
	if bb.size.y > bb.size.x and bb.size.y >= bb.size.z:
		ax = 1
	elif bb.size.z > bb.size.x and bb.size.z > bb.size.y:
		ax = 2
	var lo_mm: float = bb.position[ax] / Part.MM
	var hi_mm: float = bb.end[ax] / Part.MM
	var mid := snappedf((lo_mm + hi_mm) * 0.5, 1.0)
	var f := Part.new_feature(rec, "split", {"plane": ["right", "top", "front"][ax], "at": mid})
	rec["features"].append(f)
	if _last_error(rec, String(f["id"])) != "" or int(pu.replay_full(rec)["bodies"]) < 2:
		return "The cut would miss the solid: nothing was cut"
	tweak = {"id": f["id"], "field": "at", "label": "Where to cut", "unit": "cm", "lo": snappedf(lo_mm * 0.1 + 0.2, 0.1), "hi": snappedf(hi_mm * 0.1 - 0.2, 0.1), "step": 0.1, "scale": 10.0, "words": ["Toward one end", "Toward the other end"]}
	_say("Cut in two across the middle: drag the slider to move the cut")
	return ""


## ECUT2: the keep chips are shown while the newest step is the cut (its slider's step) and nothing is armed
func _split_on() -> bool:
	return split_id != "" and armed == "" and String(tweak.get("id", "")) == split_id and not Part.feature(_rec(), split_id).is_empty()


func _split_sync() -> void:
	var keep := _split_keep_of()
	for k in split_btns:
		(split_btns[k] as Button).set_pressed_no_signal(k == keep)


func _split_keep_of() -> String:
	var f := Part.feature(_rec(), split_id)
	var kp := int(f.get("keep", 0))
	return "upper" if kp > 0 else ("lower" if kp < 0 else "both")


## a keep chip: the cut step's "keep" field changes (one undo step). A chip that is already on changes nothing; a refusal changes nothing
func _split_keep(key: String) -> void:
	if not _split_on() or not Part.available() or key == _split_keep_of():
		_split_sync()
		return
	_flush_if_dirty()
	armed = ""
	var snap := _rec().duplicate(true)
	_begin("Keep " + String(split_btns[key].text).trim_prefix("Keep ").to_lower())
	var rec := _rec()
	var kp := 0 if key == "both" else (1 if key == "upper" else -1)
	Part.feature(rec, split_id)["keep"] = kp
	var why := _last_error(rec, split_id)
	if why == "" and kp != 0 and int(Part.replay(rec)["bodies"]) == 0:
		why = "Nothing would be left: keep both halves"
	if why != "":
		m.S.part = snap
		m._drop_undo()
		_edit_n = -1
		_say("That half cannot be kept: " + why)
	else:
		_end()
		_say("Kept the upper half: the other half is gone (Undo brings it back)" if kp > 0 else ("Kept the lower half: the other half is gone (Undo brings it back)" if kp < 0 else "Kept both halves of the cut"))
	pu.upto = -1
	pu.sync()
	_rows_sync()
	_values_sync()
	_split_sync()


## STICK TOGETHER: Part's combine step (Expert Combine): the first picked piece is the target, the second the tool; one undo step
func _stick(op: String, label: String) -> void:
	if stick_picks.size() < 2:
		_say("Click two solid pieces first")
		return
	_flush_if_dirty()
	var snap := _rec().duplicate(true)
	_begin(label)
	var rec := pu._ensure()
	var f := Part.new_feature(rec, "combine", {"target": int(stick_picks[0]), "tools": [int(stick_picks[1])], "op": op, "keep": false})
	rec["features"].append(f)
	armed = ""
	var why := _last_error(rec, String(f["id"]))
	if why == "" and op == "join":   # JOIN: the two picks must touch (apart pieces would "join" into one body with a gap: refused, nothing changes)
		why = _join_gap(Part.body_faces(snap, -1), stick_picks)
	stick_picks = []
	if why != "":
		m.S.part = snap
		m._drop_undo()
		_edit_n = -1
		_say("Those two pieces cannot do that: " + _plain(why))
	else:
		_end()
		_say("%s: the two pieces are one solid now" % label)
	tweak = {}
	pu.upto = -1
	pu.sync()
	_rows_sync()
	_values_sync()


## JOIN: the two picked pieces must touch (the smallest distance between their triangles is under 0.05 mm). "" or the words for the user
static func _join_gap(before: Array, picked: Array) -> String:
	if picked.size() < 2:
		return ""
	# the same test as the gap under 0.05 mm (tris_touch finds it without the full pair scan: a Join of two big pieces froze the app)
	if not Part.tris_touch(before[int(picked[0])], before[int(picked[1])], 0.00005):
		return "the two pieces do not touch, so Join cannot make one solid: move one until it touches the other, then press Stick together again"
	return ""


## a click in the view while Stick together is armed: the body under the pointer is picked (a second click takes it off)
func _stick_pick(bi: int, faces: Array) -> void:
	if stick_picks.has(bi):
		stick_picks.erase(bi)
		stick_tris.erase(bi)
		stick_edges.erase(bi)
	elif stick_picks.size() < 2:
		stick_picks.append(bi)
		stick_tris[bi] = faces[bi]
		stick_edges[bi] = _creases(faces[bi])
	else:
		_say("Two pieces are picked: press Join, Cut away or Keep the overlap, or click one to take it off")
		return
	_say(_arm_words("stick"))


## FDELETE: a click on a piece picks it (the glow shows it; Remove or the Delete key takes it out). A click on empty grid clears the pick.
## The piece is the step that first put the clicked surface in the solid: the first step whose result has that point on a face
func _pick_at(p: Vector2) -> void:
	_pick_clear()
	if _tpl() != "" or not _drag.is_empty() or not _draft.is_empty():
		return
	var rec := _rec()
	if (rec.get("features", []) as Array).is_empty():
		return
	var faces: Array = Part.body_faces(rec, -1)
	var hit: Dictionary = pu._ray_hit(p, faces)
	if hit.is_empty():
		return
	var pt: Vector3 = hit["at"]
	var fs: Array = rec["features"]
	for k in fs.size():
		var t := String(fs[k].get("t", ""))
		if t == "sketch" or t == "plane":
			continue   # a sketch or a face plane adds no surface
		if _pt_on(Part.body_faces(rec, k), pt):
			del_on = true
			del_id = String(fs[k].get("id", ""))
			del_n = fs.size()
			del_pt = pt
			del_tris = _lump_of(faces[int(hit["body"])], pt)   # the piece: the pieces that touch the point (a join of apart pieces is one body)
			dots.queue_redraw()
			_say("Picked a piece: press Remove to take it out. Undo puts it back")
			return
	_say("That piece has no step to take out")


func _pick_clear() -> void:
	del_on = false
	del_id = ""
	del_n = -1
	del_tris = PackedVector3Array()
	dots.queue_redraw()


## is the point on a triangle of the faces (within 0.05 mm; the faces are metres)
static func _pt_on(faces: Array, pt: Vector3) -> bool:
	for tris in faces:
		var t: PackedVector3Array = tris
		for k in range(0, t.size() - 2, 3):
			if _pt_on_tri(t[k], t[k + 1], t[k + 2], pt):
				return true
	return false


static func _pt_on_tri(a: Vector3, b: Vector3, c: Vector3, pt: Vector3) -> bool:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-18:
		return false
	n = n.normalized()
	if absf((pt - a).dot(n)) > 0.00005:
		return false
	var q := pt - n * (pt - a).dot(n)
	return (b - a).cross(q - a).dot(n) >= -0.00005 and (c - b).cross(q - b).dot(n) >= -0.00005 and (a - c).cross(q - c).dot(n) >= -0.00005


## the triangles of the piece that holds pt: the ones joined to the triangle under pt by shared corners (a join of apart pieces is one body)
static func _lump_of(tris: PackedVector3Array, pt: Vector3) -> PackedVector3Array:
	var nt := tris.size() / 3
	var by := {}
	for t in nt:
		for j in 3:
			var kk := Vector3i(roundi(tris[3 * t + j].x * 1e5), roundi(tris[3 * t + j].y * 1e5), roundi(tris[3 * t + j].z * 1e5))
			if not by.has(kk):
				by[kk] = []
			(by[kk] as Array).append(t)
	var start := -1
	for t in nt:
		if _pt_on_tri(tris[3 * t], tris[3 * t + 1], tris[3 * t + 2], pt):
			start = t
			break
	var out := PackedVector3Array()
	if start < 0:
		return out
	var seen := {start: true}
	var todo := [start]
	while not todo.is_empty():
		var t: int = todo.pop_back()
		for j in 3:
			var kk := Vector3i(roundi(tris[3 * t + j].x * 1e5), roundi(tris[3 * t + j].y * 1e5), roundi(tris[3 * t + j].z * 1e5))
			for u in by[kk]:
				if not seen.has(u):
					seen[u] = true
					todo.append(u)
	for t in seen.keys():
		out.append(tris[3 * int(t)])
		out.append(tris[3 * int(t) + 1])
		out.append(tris[3 * int(t) + 2])
	return out


func _remove_piece() -> void:
	if not del_on:
		_say("Click a piece first, then press Remove")
		return
	if not _drag.is_empty() or not _draft.is_empty():
		return
	_flush_if_dirty()
	var rec := _rec()
	var fs: Array = rec.get("features", [])
	var k := Part.index_of(rec, del_id)
	if k < 0 or fs.size() != del_n:
		_pick_clear()
		_say("The part changed: click the piece again")
		return
	var test: Dictionary = rec.duplicate(true)
	var tfs: Array = test["features"]
	var gone: Dictionary = tfs[k]
	tfs.remove_at(k)
	var extra: Array = []
	for key in ["sketch", "plane"]:
		if gone.has(key):
			extra.append(String(gone[key]))
	for sid in extra:
		if sid == "" or JSON.stringify(tfs).contains("\"%s\"" % sid):
			continue
		for i in tfs.size():
			if String(tfs[i].get("id", "")) == sid:
				tfs.remove_at(i)
				break
	var errs: Dictionary = Part.replay(test).get("errors", {})
	if not errs.is_empty():
		_say("A step after it needs this piece, so it stays. Take those steps out first")
		return
	if _pt_on(Part.body_faces(test, -1), del_pt):
		_say("That face is still there after the step: click the piece on its outside")
		return
	_begin("Remove piece")
	var live := _rec()
	live["features"] = tfs
	armed = ""
	tweak = {}
	pu.upto = -1
	pu.sync()
	_pick_clear()
	_rows_sync()
	_end()
	_say("Took out the piece. Undo puts it back")


## EXPLODE (p103): Pull apart, one slider from Together (0 mm) to Apart (100 mm). The pieces fly out from the middle of the whole part:
## the view only (the record, its undo steps and the saved part do not change). Shown while the part has two or more pieces
func _explode_box() -> PanelContainer:
	var box := PanelContainer.new()
	box.name = "easypart_explode"
	box.add_theme_stylebox_override("panel", _style(Color(0.1, 0.11, 0.14, 0.92), 10, 6))
	box.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	box.add_child(v)
	explode_label = Label.new()
	explode_label.name = "easypart_explode_label"
	explode_label.add_theme_font_size_override("font_size", 16)
	v.add_child(explode_label)
	explode_slider = HSlider.new()
	explode_slider.name = "easypart_explode_slider"
	explode_slider.min_value = 0.0
	explode_slider.max_value = EXPLODE_MAX_MM
	explode_slider.step = 1.0
	explode_slider.focus_mode = Control.FOCUS_NONE
	explode_slider.custom_minimum_size = Vector2(260, 24)
	explode_slider.add_theme_icon_override("grabber", _knob())
	explode_slider.value_changed.connect(_explode_set)
	v.add_child(explode_slider)
	_explode_reset()
	return box


## the slider's value: the pieces move to it (mm), and the label names it in plain words
func _explode_set(v: float) -> void:
	pu.explode_mm = v
	pu.sync()   # the view draws the pieces at the new distance now (the record is not touched)
	explode_label.text = "Pull apart: %d mm" % int(v) if v > 0.0 else "Pull apart: together"


func _explode_reset() -> void:
	explode_slider.set_value_no_signal(0.0)
	_explode_set(0.0)
