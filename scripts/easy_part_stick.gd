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
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	box.add_child(col)
	col.add_child(h)
	for so in STICK_OPS:
		var b := _big_btn("easypart_stick_" + String(so[0]), String(so[1]), String(so[2]), _stick.bind(String(so[0]), String(so[1])))
		b.custom_minimum_size = Vector2(150, 44)
		h.add_child(b)
		stick_btns[so[0]] = b
	for jk in [["turn", "This turns here", "A hinge: the second piece turns on the first where they touch (saved on the part, Undo takes it off)"], ["slide", "This slides here", "A slide: the second piece slides along the first where they touch (saved on the part, Undo takes it off)"]]:
		var jb := _big_btn("easypart_joint_" + String(jk[0]), String(jk[1]), String(jk[2]), _joint_words.bind(String(jk[0])))
		jb.custom_minimum_size = Vector2(170, 44)
		h.add_child(jb)
		joint_btns.append(jb)
	smooth_btn =_big_btn("easypart_smooth", "Smooth the joints", "Round the inside corners where the two pieces meet, 2 mm (one step)", _smooth_joints)
	smooth_btn.custom_minimum_size = Vector2(190, 44)
	smooth_btn.visible = false
	h.add_child(smooth_btn)
	col.add_child(_align_row())
	col.add_child(_fasten_row())   # p063: Fasten these two, under the align chips
	return box


## P054 ALIGN CHIPS: the first pick stays, the second moves: Line them up (left sides level), Centre on that (middles on one spot), Same height (tops level)
const ALIGN_OPS := [["left", "Line them up", "Slide the second piece so its left side lines up with the first one's (one step)"], ["centre", "Centre on that", "Slide the second piece so its middle sits on the middle of the first one (one step)"], ["top", "Same height", "Slide the second piece up or down so its top is level with the first one's (one step)"]]


func _align_row() -> HBoxContainer:
	align_row = HBoxContainer.new()
	align_row.name = "easypart_align"
	align_row.add_theme_constant_override("separation", 6)
	align_row.visible = false
	for al in ALIGN_OPS:
		var b := _big_btn("easypart_align_" + String(al[0]), String(al[1]), String(al[2]), _align.bind(String(al[0]), String(al[1])))
		b.custom_minimum_size = Vector2(150, 44)
		align_row.add_child(b)
		align_btns[al[0]] = b
	return align_row


## P054 ALIGN CHIPS: one step (one undo step) that moves the second picked piece against the first. A refusal changes nothing
func _align(how: String, label: String) -> void:
	if stick_picks.size() < 2:
		_say("Click two pieces first: the first one stays, the second one moves")
		return
	_flush_if_dirty()
	var snap := _rec().duplicate(true)
	_begin(label)
	var rec := pu._ensure()
	var f := Part.new_feature(rec, "align", {"body": int(stick_picks[1]), "to": int(stick_picks[0]), "how": how})
	rec["features"].append(f)
	armed = ""
	var why := _last_error(rec, String(f["id"]))
	stick_picks = []
	if why != "":
		m.S.part = snap
		m._drop_undo()
		_edit_n = -1
		_say("Those two pieces cannot line up: " + _plain(why))
	else:
		_end()
		_say("%s: the second piece moved. Undo puts it back" % label)
	tweak = {}
	pu.upto = -1
	pu.sync()
	_rows_sync()
	_values_sync()


## P035 SMOOTH THE JOINS: the chip shows while the newest step is a Join (nothing armed). Undo or any other step hides it
func _smooth_on() -> bool:
	var fs: Array = _rec().get("features", [])
	return armed == "" and not fs.is_empty() and String(fs[-1]["t"]) == "combine" and String(fs[-1].get("op", "")) == "join"


## P035 SMOOTH THE JOINS: a 2 mm round on the inside corners where the two joined pieces meet (one fillet step, one undo step).
## The corners are the concave edges of the joined solid whose middle lies in the second piece's box (grown 1 mm). Nothing changes on a refusal
func _smooth_joints() -> void:
	if not _smooth_on() or not Part.available():
		_say("Join two solid pieces first, then press Smooth the joints")
		return
	_flush_if_dirty()
	var rec := _rec()
	var jf: Dictionary = rec["features"][-1]
	var pre := rec.duplicate(true)
	(pre["features"] as Array).pop_back()
	var before := Part.body_faces(pre, -1)
	var tools: Array = jf.get("tools", [])
	if tools.is_empty() or int(tools[0]) >= before.size():
		_say("Those pieces are no longer there: Undo the join, then join them again")
		return
	var box := AABB()
	var first := true
	for w in before[int(tools[0])]:
		box = AABB(w, Vector3.ZERO) if first else box.expand(w)
		first = false
	box = box.grow(0.001)
	var trial := Part.replay(rec, -1, {"edges": true, "keep": true})
	var kept: Array = trial.get("ids", [])
	var list := []
	for e in trial.get("edges", []):
		if int(e["body"]) == 0 and bool(e.get("inner", false)) and box.has_point(e["c"]):
			list.append(Part.describe(e))
	if kept.is_empty() or list.is_empty():
		Part.release_kept(kept)
		_say("The two pieces make no inside corner here, so there is nothing to smooth")
		return
	var err := Part.fillet_trial(int(kept[0]), 2.0, list)
	Part.release_kept(kept)
	if err != "":
		_say("The joint will not take a 2 mm smooth (%s). Undo the join, then join again" % err)
		return
	_begin("Smooth the joints")
	var f := Part.new_feature(rec, "fillet", {"body": 0, "r": 2.0, "edges": list})
	rec["features"].append(f)
	if _last_error(rec, String(f["id"])) != "":
		rec["features"].pop_back()
		m.S.part = pre
		m._drop_undo()
		_edit_n = -1
		_say("The joint will not take a 2 mm smooth: Undo the join, then join again")
		return
	_end()
	_say("Smoothed the joint: its inside corners are rounded 2 mm (Undo takes the round away)")
	pu.upto = -1
	pu.sync()
	_rows_sync()
	_values_sync()


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
		if why != "" and _join_overlaps(snap, rec):
			why = ""   # one piece passes through the other (a brace round the legs): they share volume, so Join makes one solid
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


## p121 JOINT WORDS: "This turns here" (a hinge) or "This slides here" (a slide) between the two picked pieces. The place is the middle of the two
## piece centres (mm). It is saved on the part as joints: [{kind, at}], one undo step. Pieces that do not touch are refused in words; nothing changes
func _joint_words(kind: String) -> void:
	if stick_picks.size() < 2:
		_say("Click two pieces first, then press This turns here or This slides here")
		return
	var a: PackedVector3Array = stick_tris.get(int(stick_picks[0]), PackedVector3Array())
	var b: PackedVector3Array = stick_tris.get(int(stick_picks[1]), PackedVector3Array())
	if a.is_empty() or b.is_empty() or not Part.tris_touch(a, b, 0.00005):
		_say("Those two pieces do not touch, so no joint fits between them: move one until it touches the other, then press the joint words again")
		return
	_flush_if_dirty()
	var at := (_centre(a) + _centre(b)) * 0.5 / Part.MM
	_begin("This turns here" if kind == "turn" else "This slides here")
	var rec := _rec()
	if not rec.has("joints"):
		rec["joints"] = []
	(rec["joints"] as Array).append({"kind": kind, "at": [snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01)]})
	armed = ""
	stick_picks = []
	_end()
	_say("Saved: one piece %s on the other where they touch, %s (Undo takes it off)" % ["turns" if kind == "turn" else "slides", "a hinge" if kind == "turn" else "a slide"])
	pu.upto = -1
	pu.sync()
	_rows_sync()
	_values_sync()


## the middle of a piece's triangle corners (metres)
static func _centre(tris: PackedVector3Array) -> Vector3:
	var c := Vector3.ZERO
	for v in tris:
		c += v
	return c / maxf(1.0, float(tris.size()))


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
func _pick_at(p: Vector2, forced := {}) -> void:   # W09: forced = a piece chosen by name from the list
	_pick_clear()
	if _tpl() != "" or not _drag.is_empty() or not _draft.is_empty():
		return
	var rec := _rec()
	if (rec.get("features", []) as Array).is_empty():
		return
	var faces: Array = Part.body_faces(rec, -1)
	if _pstack == null:
		_pstack = PickStack.new()
	var hit: Dictionary = forced if not forced.is_empty() else _pstack.cycled(self, p, faces)   # W09: a repeat click goes down the pieces under it
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
			del_bi = int(hit["body"])   # HEIGHT: the picked piece's body (a "move" step takes it up or down)
			del_tris = _lump_of(faces[int(hit["body"])], pt)   # the piece: the pieces that touch the point (a join of apart pieces is one body)
			dots.queue_redraw()
			_say("Picked a piece: press Remove to take it out. Undo puts it back")
			return
	_say("That piece has no step to take out")


var _pstack: PickStack   # W09


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


## SIZE % (p052scalepiece, Friday plan 52): a picked piece that was pulled up from a shape gets a Size % slider (50 to 200 %) and a
## Taller only chip. One slider release is one undo step: the record from before the drag is rebuilt with the piece scaled about the
## middle of its shape (the bottom stays on the shape's plane). Taller only scales the up axis alone (width and depth stay). The slider
## goes back to 100 after each release, so the next drag scales the piece again from where it is now
const SIZE_MIN := 50.0
const SIZE_MAX := 200.0
const SIZE_ARC_N := 48          # a circle scaled taller (not wider) becomes a closed spline of this many points
const SIZE_AT := Vector2(520, 530)   # where the Size % box sits (1280 x 720 canvas): clear of the click spots, the block and the steps panel
var size_box: PanelContainer
var size_slider: HSlider
var size_label: Label
var size_taller: Button
var size_base: Dictionary = {}   # the record when a Size % drag began ({} = no drag)


func _size_box() -> PanelContainer:
	var box := PanelContainer.new()
	box.name = "easypart_size"
	box.add_theme_stylebox_override("panel", _style(Tok.c("panel"), 10, 6))
	box.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	box.add_child(v)
	size_label = Label.new()
	size_label.name = "easypart_size_label"
	size_label.add_theme_font_size_override("font_size", 16)
	size_label.add_theme_color_override("font_color", Tok.c("text"))
	v.add_child(size_label)
	size_slider = HSlider.new()
	size_slider.name = "easypart_size_slider"
	size_slider.min_value = SIZE_MIN
	size_slider.max_value = SIZE_MAX
	size_slider.step = 1.0
	size_slider.value = 100.0
	size_slider.focus_mode = Control.FOCUS_NONE
	size_slider.custom_minimum_size = Vector2(260, 24)
	size_slider.add_theme_icon_override("grabber", _knob())
	size_slider.drag_started.connect(_size_drag_start)
	size_slider.value_changed.connect(_size_preview)
	size_slider.drag_ended.connect(_size_drag_end)
	v.add_child(size_slider)
	size_taller = Button.new()
	size_taller.name = "easypart_size_taller"
	size_taller.text = "Taller only"
	size_taller.toggle_mode = true
	size_taller.tooltip_text = "On: the Size % slider makes the piece taller only. The width and depth stay"
	size_taller.custom_minimum_size = Vector2(0, 34)
	size_taller.add_theme_font_size_override("font_size", 15)
	v.add_child(size_taller)
	# HEIGHT (fstool 4b, Nick 11-01): the picked piece slides up or down, one slider in this same box (shown with two or more pieces)
	height_label = Label.new()
	height_label.name = "easypart_height_label"
	height_label.add_theme_font_size_override("font_size", 16)
	height_label.add_theme_color_override("font_color", Tok.c("text"))
	v.add_child(height_label)
	height_slider = HSlider.new()
	height_slider.name = "easypart_height_slider"
	height_slider.min_value = -500.0
	height_slider.max_value = 500.0
	height_slider.step = 1.0
	height_slider.value = 0.0
	height_slider.focus_mode = Control.FOCUS_NONE
	height_slider.custom_minimum_size = Vector2(260, 24)
	height_slider.add_theme_icon_override("grabber", _knob())
	height_slider.drag_started.connect(_height_start)
	height_slider.value_changed.connect(_height_preview)
	height_slider.drag_ended.connect(_height_end)
	v.add_child(height_slider)
	v.add_child(_name_row())   # s212: the picked piece's name
	_size_text()
	return box


## the box's words: the % the slider is at, and whether it is taller only
func _size_text() -> void:
	var pct := int(roundf(size_slider.value))
	size_label.text = ("Taller only: %d %%" if size_taller.button_pressed else "Size: %d %%") % pct
	if height_label != null:
		height_label.text = "Height: %d mm" % int(roundf(height_slider.value))


## the box shows with a picked piece (its Remove shows too) and sits in the lower middle of the grid, clear of the Tilt rows and the steps panel
func _slider_box_sync(on: bool) -> void:
	size_box.visible = on and _rec().get("features", []).size() > 0 and del_on and armed == ""
	if not size_box.visible:
		return
	_height_sync()
	_name_sync()
	size_box.reset_size()
	size_box.position = SIZE_AT   # the grid's lower middle: right of the Tilt and Draft rows, left of the steps panel (1280 x 720)
	_box_clear_of_size_line()


func _size_drag_start() -> void:
	size_base = _rec().duplicate(true)


## the slider moves: the piece is shown at the new % (the record is not an undo step yet); a size that cannot be built says why
func _size_preview(v: float) -> void:
	_size_text()
	if size_base.is_empty():
		size_base = _rec().duplicate(true)
	var out := _size_build(size_base, v / 100.0, size_taller.button_pressed)
	if out.has("err"):
		m.S.part = size_base.duplicate(true)
		_say(String(out["err"]))
	else:
		m.S.part = out["rec"]
	pu.upto = -1
	pu.sync()


## the release: one undo step from the record before the drag, to the scaled record. The slider goes back to 100
func _size_drag_end(changed: bool) -> void:
	var base := size_base
	size_base = {}
	if base.is_empty():
		return
	var pct := size_slider.value
	var taller := size_taller.button_pressed
	var out := _size_build(base, pct / 100.0, taller) if changed and absf(pct - 100.0) >= 0.5 else {}
	m.S.part = base
	if out.has("err"):
		_say(String(out["err"]))
	elif not out.is_empty():
		_begin("Taller %d %%" % int(roundf(pct)) if taller else "Size %d %%" % int(roundf(pct)))
		m.S.part = out["rec"]
		_end()
		_say("The piece is %d %% %s. Undo puts it back" % [int(roundf(pct)), "taller" if taller else "of its size"])
	pu.upto = -1
	pu.sync()
	_rows_sync()
	size_slider.set_value_no_signal(100.0)
	_size_text()


## the record with the picked piece scaled by f (1.0 = as it is): {"rec": record} or {"err": what to press next}.
## The piece is its Pull step (an extrude): its shape's points and dimensions scale about the shape's middle, and its pull distance too
func _size_build(base: Dictionary, f: float, taller: bool) -> Dictionary:
	var k := Part.index_of(base, del_id)
	if k < 0:
		return {"err": "Click a piece first, then drag Size %"}
	var rec: Dictionary = base.duplicate(true)
	var ex: Dictionary = rec["features"][k]
	if String(ex.get("t", "")) != "extrude" or not ex.has("sketch"):
		return {"err": "Size % works on a piece you pulled up from a shape. Press Undo, or click a piece that has a Pull step"}
	var sk := Part.feature(rec, String(ex["sketch"]))
	if sk.is_empty():
		return {"err": "This piece has no shape left to scale. Press Undo"}
	var pl: Dictionary = Part.resolve_plane(rec, String(sk.get("plane", "front")))
	# the plane's axes that point up: Taller only scales those alone (x and y of the shape, and the pull)
	var fu := f if (not taller or absf((pl["x"] as Vector3).y) > 0.5) else 1.0
	var fv := f if (not taller or absf((pl["y"] as Vector3).y) > 0.5) else 1.0
	var fn := f if (not taller or absf((pl["n"] as Vector3).y) > 0.5) else 1.0
	var ents: Array = sk.get("ents", [])
	var c := _size_centre(ents)
	var conv := {}   # entity index -> true when a circle became a spline (taller only: an ellipse)
	for i in ents.size():
		ents[i] = _size_ent(ents[i], c, fu, fv, i, conv)
	var dims: Array = []
	for d in sk.get("dims", []):
		var di := int(d.get("ent", -1))
		if conv.has(di):
			continue   # the spline has no size of its own: its dimension goes (the points carry the shape)
		var kind := String(d.get("kind", ""))
		if kind == "w":
			d["mm"] = float(d.get("mm", 0.0)) * fu
		elif kind == "h":
			d["mm"] = float(d.get("mm", 0.0)) * fv
		elif kind == "r":
			d["mm"] = float(d.get("mm", 0.0)) * fu
		elif kind == "len" and di >= 0 and di < ents.size():
			var e: Dictionary = ents[di]
			var dir := _v2(e["b"]) - _v2(e["a"]) if e.has("b") else Vector2(1, 0)
			d["mm"] = float(d.get("mm", 0.0)) * (fu if absf(dir.x) >= absf(dir.y) else fv)
		dims.append(d)
	sk["dims"] = dims
	ex["dist"] = float(ex.get("dist", 0.0)) * fn
	var before := Part.replay(base)
	var after := Part.replay(rec)
	var bad := (after.get("errors", {}) as Dictionary).size() > (before.get("errors", {}) as Dictionary).size()
	if bad or int(after.get("bodies", -1)) != int(before.get("bodies", -2)):
		return {"err": "That size does not fit the steps after this piece. Press Undo, or try a smaller size"}
	return {"rec": rec}


## a point as Vector2 (the record holds [x, y] arrays)
static func _v2(p) -> Vector2:
	return Vector2(float(p[0]), float(p[1]))


## the middle of a shape's points (mm): the middle of its box, circles and arcs counted by their edges
static func _size_centre(ents: Array) -> Vector2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for e in ents:
		var pts: Array = []
		for key in ["a", "b", "m", "c"]:
			if e.has(key):
				pts.append(_v2(e[key]))
		for p in e.get("pts", []):
			pts.append(_v2(p))
		if e.has("r"):
			for p in [_v2(e["c"]) - Vector2(float(e["r"]), 0), _v2(e["c"]) + Vector2(float(e["r"]), 0), _v2(e["c"]) - Vector2(0, float(e["r"])), _v2(e["c"]) + Vector2(0, float(e["r"]))]:
				pts.append(p)
		for p in pts:
			lo = lo.min(p)
			hi = hi.max(p)
	return (lo + hi) * 0.5 if lo.x < INF else Vector2.ZERO


## one entity scaled about c by (fu, fv): lines, rects, arcs and splines map their points; a circle stays a circle when the scale is even,
## else it becomes a closed spline (recorded in conv)
static func _size_ent(e: Dictionary, c: Vector2, fu: float, fv: float, i: int, conv: Dictionary) -> Dictionary:
	var sc := Vector2(fu, fv)
	var out := e.duplicate(true)
	var k := String(e.get("k", ""))
	if k == "circle":
		var cc := c + (_v2(e["c"]) - c) * sc
		var r := float(e["r"])
		if absf(fu - fv) < 1e-9:
			out["c"] = Part.arr2(cc)
			out["r"] = r * fu
			return out
		var pts: Array = []
		for j in SIZE_ARC_N:
			var t := TAU * float(j) / float(SIZE_ARC_N)
			pts.append(Part.arr2(cc + Vector2(cos(t) * r * fu, sin(t) * r * fv)))
		conv[i] = true
		return {"k": "bspline", "pts": pts, "closed": true}
	for key in ["a", "m", "b"]:
		if e.has(key):
			out[key] = Part.arr2(c + (_v2(e[key]) - c) * sc)
	if e.has("pts"):
		var sp: Array = []
		for p in e["pts"]:
			sp.append(Part.arr2(c + (_v2(p) - c) * sc))
		out["pts"] = sp
	return out


## p063 FASTEN THESE TWO (Friday plan 63): with two pieces picked in Stick together, one press picks the screw (size from the thinner piece, length from
## both, rounded down to a stock length), two places along the overlap, cuts the holes and puts the screws in: one undo step. The rule is printed
## beside the button. The maths and the features are PartFasten (scripts/build/part_fasten.gd).
var fasten_btn: Button
var fasten_row: HBoxContainer


func _fasten_row() -> HBoxContainer:
	fasten_row = HBoxContainer.new()
	fasten_row.name = "easypart_fasten_row"
	fasten_row.add_theme_constant_override("separation", 8)
	fasten_row.visible = false
	fasten_btn = _big_btn("easypart_fasten", "Fasten these two", "Screws for the two picked pieces: Kine picks the screw size and length and the hole places (one step, Undo takes it back)", _fasten_two)
	fasten_btn.custom_minimum_size = Vector2(170, 44)
	fasten_row.add_child(fasten_btn)
	var rule := Label.new()
	rule.name = "easypart_fasten_rule"
	rule.text = PartFasten.RULE_WORDS
	rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rule.custom_minimum_size = Vector2(520, 0)
	rule.add_theme_font_size_override("font_size", 11)
	rule.add_theme_color_override("font_color", Color(0.8, 0.82, 0.86))
	fasten_row.add_child(rule)
	return fasten_row


func _fasten_two() -> void:
	if stick_picks.size() < 2:
		_say("Click two pieces first, one lying on the other, then press Fasten these two")
		return
	if not Part.available():
		_say("Fasten these two needs the CAD engine, which is not here")
		return
	var ia := int(stick_picks[0])
	var ib := int(stick_picks[1])
	var plan := PartFasten.plan(stick_tris.get(ia, PackedVector3Array()), stick_tris.get(ib, PackedVector3Array()))
	if String(plan["why"]) != "":
		_say(String(plan["why"]))
		return
	_flush_if_dirty()
	var snap := _rec().duplicate(true)
	_begin("Fasten these two")
	var rec := pu._ensure()
	var d: int = plan["d"]
	var sc = load("res://scripts/easy_part_pull.gd")   # the Cut a hole chips' clearance table (a subclass of this script: read by its resource)
	var pr := String(get("printer")) if get("printer") != null else ""
	var clear := float((sc.PRINTER_CLEAR as Dictionary).get(pr, sc.SCREW_CLEAR)[d])
	var head_i := ib if bool(plan["swap"]) else ia
	var far_i := ia if bool(plan["swap"]) else ib
	var why := PartFasten.build(rec, plan, head_i, far_i, clear, float(rec.get("fit_mm", 0.0)))
	armed = ""
	stick_picks = []
	if why != "":
		m.S.part = snap
		m._drop_undo()
		_edit_n = -1
		_say(why)
	else:
		if not rec.has("fasteners"):
			rec["fasteners"] = []
		(rec["fasteners"] as Array).append({"d": d, "L": int(plan["L"]), "n": (plan["pts"] as Array).size()})
		_end()
		_say("%dx M%d x %d: %s hole%s through the first piece, a pilot in the second, the screws in (Undo takes it all back)" % [(plan["pts"] as Array).size(), d, int(plan["L"]), _mm_words(clear), "" if (plan["pts"] as Array).size() == 1 else "s"])
	tweak = {}
	pu.upto = -1
	pu.sync()
	_rows_sync()
	_values_sync()


## HEIGHT (fstool 4b): the picked piece (a body of its own) moves up or down along the world vertical. The slider is the piece's lowest point in
## mm above the floor (the part's lowest point), 1 mm steps, up to the piece's top level with the part's top; one drag = one undo step, recorded as a "move" step (Your steps lists it, a save keeps it)
var height_label: Label
var height_slider: HSlider
var height_base: Dictionary = {}   # the record when a Height drag began ({} = no drag)
var height_from := 0.0             # mm: the piece's lowest point when the drag began


## the piece's lowest and highest point (mm) and the part's (mm); empty when the pick cannot move
func _height_range(rec: Dictionary) -> Dictionary:
	var faces: Array = Part.body_faces(rec, -1)
	if faces.size() < 2 or del_bi < 0 or del_bi >= faces.size():
		return {}
	var lo := INF
	var hi := -INF
	for w in faces[del_bi]:
		lo = minf(lo, (w as Vector3).y)
		hi = maxf(hi, (w as Vector3).y)
	var plo := INF
	var phi := -INF
	for b in faces:
		for w in b:
			plo = minf(plo, (w as Vector3).y)
			phi = maxf(phi, (w as Vector3).y)
	return {"lo": lo / Part.MM, "hi": hi / Part.MM, "plo": plo / Part.MM, "phi": phi / Part.MM}


## the row shows with a picked piece that is one of two or more; its range follows the part
func _height_sync() -> void:
	var on := false
	if height_base.is_empty():
		var r := _height_range(_rec())
		on = not r.is_empty()
		if on:
			# the shown number is the piece's bottom above the floor (the part's lowest point), 0 = on the floor, the top = the piece's top level with the part's top
			height_slider.min_value = 0.0
			height_slider.max_value = maxf(ceilf(float(r["phi"]) - float(r["plo"]) - (float(r["hi"]) - float(r["lo"]))), 1.0)
			height_slider.set_value_no_signal(roundf(float(r["lo"]) - float(r["plo"])))
			_size_text()
	else:
		on = true
	height_label.visible = on
	height_slider.visible = on


func _height_start() -> void:
	height_base = _rec().duplicate(true)
	var r := _height_range(height_base)
	height_from = (float(r["lo"]) - float(r["plo"])) if not r.is_empty() else 0.0   # the shown height when the drag began (mm above the floor)


## the record with the picked piece moved dy mm up (or down) as one more step
func _height_build(base: Dictionary, dy: float) -> Dictionary:
	var rec: Dictionary = base.duplicate(true)
	var f := Part.new_feature(rec, "move", {"body": del_bi, "d": [0.0, dy, 0.0]})
	rec["features"].append(f)
	var why := String(Part.replay(rec).get("errors", {}).get(String(f["id"]), ""))
	if why != "":
		return {"err": "That piece cannot move there: " + _plain(why)}
	return {"rec": rec}


func _height_preview(v: float) -> void:
	_size_text()
	if height_base.is_empty():
		return
	var out := _height_build(height_base, v - height_from)
	m.S.part = (out["rec"] if out.has("rec") else height_base.duplicate(true))
	del_n = (m.S.part["features"] as Array).size()   # the preview's extra step must not clear the pick (that would hide this slider mid-drag)
	pu.upto = -1
	pu.sync()
	_height_retarget()


## the picked piece's red glow follows the piece (Lead 11-01: after a Height move the glow stayed where the piece had been, a red disc over nothing)
func _height_retarget() -> void:
	var faces: Array = Part.body_faces(_rec(), -1)
	if del_on and del_bi >= 0 and del_bi < faces.size():
		del_tris = faces[del_bi]
		dots.queue_redraw()


func _height_end(changed: bool) -> void:
	var base := height_base
	height_base = {}
	if base.is_empty():
		return
	var dy := height_slider.value - height_from
	var out := _height_build(base, dy) if changed and absf(dy) >= 0.5 else {}
	m.S.part = base
	del_n = (base["features"] as Array).size()
	if out.has("err"):
		_say(String(out["err"]))
	elif not out.is_empty():
		_begin("Height %d mm" % int(roundf(height_slider.value)))
		m.S.part = out["rec"]
		_end()
		del_n = (m.S.part["features"] as Array).size()
		_say("The piece is %d mm up from the floor. Undo puts it back" % int(roundf(height_slider.value)))
	pu.upto = -1
	pu.sync()
	_rows_sync()
	_size_text()
	_height_retarget()


## JOIN: true when joining made the solid smaller than the two pieces were together: they overlap (an edge of one passes through a face of the other), which the touch test above does not see
static func _join_overlaps(before: Dictionary, after: Dictionary) -> bool:
	var v0 := float(Part.replay(before).get("volume", 0.0))
	var v1 := float(Part.replay(after).get("volume", 0.0))
	return v0 > 0.0 and v1 < v0 * (1.0 - 1e-6)



# ---------------------------------------------------------------- s212 NAME A PIECE
## A picked piece has a name field in the Size box (Body1 until it is given one). Enter or leaving the field sets it: one undo step, the same record step
## the Expert browser's Rename writes (PartUI.body_rename). The name shows in the Expert browser, the exports and the part's readouts.
var bname_row: HBoxContainer
var bname_edit: LineEdit


func _name_row() -> HBoxContainer:
	bname_row = HBoxContainer.new()
	bname_row.name = "easypart_name_row"
	var l := Label.new()
	l.text = "Name"
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Tok.c("text"))
	bname_row.add_child(l)
	bname_edit = LineEdit.new()
	bname_edit.name = "easypart_name_edit"
	bname_edit.custom_minimum_size = Vector2(200, 30)
	bname_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bname_edit.max_length = 40
	bname_edit.tooltip_text = "Give the picked piece a name. It shows in the Expert browser, on the exported files and in the readouts"
	bname_edit.text_submitted.connect(func(t: String): _name_commit(t))
	bname_edit.focus_exited.connect(func(): _name_commit(bname_edit.text))
	bname_row.add_child(bname_edit)
	return bname_row


## the field shows the picked piece's name (not while the maker is typing in it)
func _name_sync() -> void:
	if bname_edit == null or bname_edit.has_focus():
		return
	bname_target = del_bi
	var shown := Part.body_name(pu.res, del_bi) if del_bi >= 0 else ""
	if bname_edit.text != shown:
		bname_edit.text = shown
	bname_edit.placeholder_text = "Body%d" % (del_bi + 1)
	bname_row.visible = del_bi >= 0 and del_bi < int(pu.res.get("bodies", 0))


## the piece the field was showing when the maker started typing (a click on another piece must not rename that one)
var bname_target := -1


func _name_commit(t: String) -> void:
	var bi := bname_target
	if bi < 0 or bi >= int(pu.res.get("bodies", 0)):
		return
	_flush_if_dirty()
	var keep := del_on and del_bi == bi
	var k_id := del_id
	var k_pt := del_pt
	var k_tris := del_tris
	if pu.body_rename(bi, t):
		if keep:   # the naming step must not end the pick (the pick ends with the step it was made on)
			del_on = true
			del_bi = bi
			del_id = k_id
			del_pt = k_pt
			del_tris = k_tris
			del_n = (_rec().get("features", []) as Array).size()
			dots.queue_redraw()
		_rows_sync()
		_say("The piece is now called %s. Undo takes it back" % Part.body_name(pu.res, bi))
	_name_sync()
