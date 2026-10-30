extends "res://scripts/easy_part_stick.gd"
## EASY PART REPEAT: the copies. Repeat it (a row, a ring, or the corners of the seat it sits on; its How many and Gap sliders),
## Duplicate (a second copy of the whole part beside it) and Mirror that (a copy on the other side of the middle line, a hole with it).

## REPEAT IT: Row or Ring, then How many (2..20 copies, the original counts; FCOMB: a comb of 20 teeth) and Gap (cm between the copies). Its sliders write the Part pattern
## step fields (count, mm, kind): the same replay as Expert Pattern
func _repeat_box() -> PanelContainer:
	var box := PanelContainer.new()
	box.name = "easypart_repeat"
	box.add_theme_stylebox_override("panel", _style(Color(0.1, 0.11, 0.14, 0.92), 10, 6))
	box.visible = false
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	box.add_child(vb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	vb.add_child(h)
	for md in [["row", "Row", false], ["ring", "Ring", true]]:
		var tip := "Copies sideways in a straight row" if not md[2] else "Copies round the up axis, in a full turn"
		var b := _big_btn("easypart_rep_" + String(md[0]), String(md[1]), tip, _rep_mode.bind(bool(md[2])))
		b.toggle_mode = true
		h.add_child(b)
		rep_btns[md[0]] = b
		if md[0] == "row":   # EREPEATUP: Up and Forward sit beside Row (the same straight line, another direction)
			for dd in [["up", "Up", "y", "Copies stacked upward, one on top of the other (a shelf stack)"], ["forward", "Forward", "z", "Copies straight forward, one behind the other"]]:
				var ub := _big_btn("easypart_rep_" + String(dd[0]), String(dd[1]), String(dd[3]), _rep_dir.bind(String(dd[2])))
				ub.toggle_mode = true
				h.add_child(ub)
				rep_btns[dd[0]] = ub
	var cb := _big_btn("easypart_rep_corners", "Corners", "Four copies, one at each corner of the piece it sits on (the legs of a chair or table)", _rep_corners)
	cb.toggle_mode = true
	h.add_child(cb)
	rep_btns["corners"] = cb
	var sb := _big_btn("easypart_rep_stairs", "Up and Forward", "Steps: each copy goes up one step and forward one step, a staircase of 8", _rep_stairs)
	sb.toggle_mode = true
	h.add_child(sb)
	rep_btns["stairs"] = sb
	rep_rows.append(_make_row("How many", 2.0, 20.0, 1.0, REP_WORDS["count"], "rep", "count", "copies", vb))
	rep_rows.append(_make_row("Gap", 0.5, 30.0, 0.5, REP_WORDS["gap"], "rep", "gap", "cm", vb))
	return box


## the Repeat it sliders: How many = the copies; Gap = cm between the copies (the spacing = the body width + the gap, in the record mm)
func _apply_rep(row: Dictionary, v: float) -> void:
	var f := Part.feature(_rec(), rep_id)
	if f.is_empty():
		return
	if String(row["key"]) == "count":
		f["count"] = int(roundf(v))
	else:
		f["gap"] = v * 10.0
		f["mm"] = _span(f) + v * 10.0


func _mirror(rec: Dictionary) -> String:
	var res := Part.replay(rec)
	if int(res["bodies"]) == 0:
		return "Nothing solid to mirror yet. Press Pull it up first"
	var bb: AABB = res["aabb"]
	var off := bb.position.x > 0.0005 or bb.end.x < -0.0005   # EMIRROR: the solid does not touch the middle line (x = 0)
	if _hole_last(rec):   # MSIGN: a hole is the newest step: its copy is cut on the other side (a join copy would fill the hole back in)
		var why_h := _mirror_hole(rec, res, off)
		if why_h == "":
			tweak = {}
			_say("Mirrored across the middle line: the hole is copied to the other side")
		return why_h
	var f := Part.new_feature(rec, "mirror", {"plane": "right", "op": "join"})
	if off:
		f["mid"] = true   # the mirror plane goes through the middle of the part, not the world line
	rec["features"].append(f)
	if _last_error(rec, String(f["id"])) != "":
		return "That shape cannot be mirrored"
	tweak = {}
	var after: Dictionary = pu.replay_full(rec)
	var gap := int(after["bodies"]) == 1 and _lumps(after) > 1   # the mirror left a gap: the same test as the status line
	var where := "across the middle of the part" if off else "across the middle line"
	_say("Mirrored %s" % where + (": the two halves do not touch. Push them together with Stick together" if gap else ": press Repeat it or Cut a hole next"))
	return ""


## MSIGN: the newest step is a cut through a shape drawn on a face (a hole, a window): Mirror that copies the hole
func _hole_last(rec: Dictionary) -> bool:
	var feats: Array = rec.get("features", [])
	if feats.is_empty():
		return false
	var cut: Dictionary = feats[feats.size() - 1]
	if String(cut["t"]) != "extrude" or String(cut.get("op", "")) != "cut":
		return false
	var sk := Part.feature(rec, String(cut.get("sketch", "")))
	if sk.is_empty():
		return false
	var pf := Part.feature(rec, String(sk.get("plane", "")))   # only a hole drawn ON A FACE (a plane with "out"): a centre hole keeps the join copy
	if String(pf.get("t", "")) != "plane" or not pf.has("out"):
		return false
	return absf((Part.resolve_plane(rec, String(sk.get("plane", "")))["n"] as Vector3).x) < 0.0001


## MSIGN: the same hole cut again, its sketch reflected across the middle line (x = mid, the same middle the join mirror uses)
func _mirror_hole(rec: Dictionary, res: Dictionary, off: bool) -> String:
	var cut: Dictionary = rec["features"][rec["features"].size() - 1]
	var sk := Part.feature(rec, String(cut["sketch"]))
	var pl := Part.resolve_plane(rec, String(sk["plane"]))
	var bb: AABB = res["aabb"]
	var mid := (bb.position.x + bb.end.x) * 0.5 if off else 0.0
	var o: Vector3 = pl["o"]
	var px: Vector3 = pl["x"]
	var py: Vector3 = pl["y"]
	var ents := []
	for e in sk.get("ents", []):
		var ne: Dictionary = e.duplicate(true)
		for k in ["a", "b", "c"]:
			if e.has(k):
				var w := o + px * float(e[k][0]) * Part.MM + py * float(e[k][1]) * Part.MM
				w.x = 2.0 * mid - w.x
				var d := w - o
				ne[k] = Part.arr2(Vector2(d.dot(px) / Part.MM, d.dot(py) / Part.MM))
		ents.append(ne)
	var fields: Dictionary = sk.duplicate(true)
	for k in ["t", "id", "name"]:
		fields.erase(k)
	fields["ents"] = ents
	var s := Part.new_feature(rec, "sketch", fields)
	rec["features"].append(s)
	var f := Part.new_feature(rec, "extrude", {"sketch": s["id"], "dist": cut["dist"], "both": bool(cut.get("both", false)), "op": "cut"})
	rec["features"].append(f)
	if _last_error(rec, String(f["id"])) != "":
		return "That hole cannot be copied"
	if float(pu.replay_full(rec)["volume"]) >= float(res["volume"]) - 1e-12:
		return "The copy would miss the solid: nothing was cut"
	return ""


## BLEND TWO SHAPES: a loft of the two last sketches (Part's "loft" feature, the same one Expert's Loft makes). Two shapes on the same plane
## cannot be blended, so the newer one moves 40 mm behind the older one (an offset plane, in the same undo step)
## FPHONE: the base plane (front | top | right) a sketch's plane id sits on, a plane feature or a base plane itself
func _plane_base(rec: Dictionary, pid: String) -> String:
	return pid if pid in Part.PLANES else _base_plane(rec, pid)


## FDUP: Duplicate: a second copy of the WHOLE part beside it (not Repeat's row of the newest solid). One Part pattern step per body, each with
## two copies and op "new": every body is copied by the same move, the whole part's width plus a 10 mm gap, so the copy sits beside all of it
func _duplicate(rec: Dictionary) -> String:
	var res := Part.replay(rec)
	var nb := int(res["bodies"])
	if nb == 0:
		return "Make something solid first, then duplicate it"
	var bb: AABB = res["aabb"]
	var gap := 10.0
	var step_mm := maxf(bb.size.x / Part.MM, 1.0) + gap
	for bi in nb:
		var f := Part.new_feature(rec, "pattern", {"kind": "linear", "body": bi, "count": 2, "dir": "x", "axis": "y", "deg": 360.0,
			"mm": step_mm, "w": bb.size.x / Part.MM, "h": bb.size.y / Part.MM, "d": bb.size.z / Part.MM, "gap": gap, "op": "new"})
		rec["features"].append(f)
		if _last_error(rec, String(f["id"])) != "":
			return "The copy would not fit: nothing was changed"
	tweak = {}
	_say("Duplicated: a second copy of the whole part sits beside it. Undo takes the copy back")
	return ""


## REPEAT IT: Part's pattern step (Expert Pattern) on the newest solid: a row along X, spacing = the body's width + a 1 cm gap
func _repeat(rec: Dictionary) -> String:
	var fs: Array = rec.get("features", [])
	if not fs.is_empty() and String(fs[-1].get("t", "")) == "extrude" and String(fs[-1].get("op", "")) == "cut" and not bool(fs[-1].get("off", false)):
		return _repeat_cut(rec, fs[-1])   # FRULER: the newest step is a cut (a slot or hole): the row copies the cut, not the body
	var res := Part.replay(rec)
	var nb := int(res["bodies"])
	if nb == 0:
		return "Make something solid first, then repeat it"
	var bi := nb - 1
	var w_mm := 10.0
	var h_mm := 10.0   # EREPEATUP: the body's height and depth too, so Up and Forward space the copies by their own size
	var d_mm := 10.0
	var src := Part.pattern_piece(rec)   # REPEAT THE PIECE: the newest piece (its own size) when it is the newest step, else the whole body
	var mrec: Dictionary = Part.pattern_src_rec(rec, src) if src != "" else rec
	var mbi := -1 if src != "" else bi
	var faces := Part.body_faces(mrec, -1)
	if mbi < 0:
		mbi = faces.size() - 1
	if mbi >= 0 and mbi < faces.size() and (faces[mbi] as PackedVector3Array).size() > 0:
		var pts: PackedVector3Array = faces[mbi]
		var bb := AABB(pts[0], Vector3.ZERO)
		for q in pts:
			bb = bb.expand(q)
		w_mm = maxf(bb.size.x / Part.MM, 1.0)
		h_mm = maxf(bb.size.y / Part.MM, 1.0)
		d_mm = maxf(bb.size.z / Part.MM, 1.0)
	var fields := {"kind": "linear", "body": bi, "count": 3, "dir": "x", "axis": "y", "deg": 360.0,
		"mm": w_mm + 10.0, "w": w_mm, "h": h_mm, "d": d_mm, "rise": h_mm, "run": d_mm, "gap": 10.0, "op": "join"}
	if src != "":
		fields["src"] = src
	var f := Part.new_feature(rec, "pattern", fields)
	rec["features"].append(f)
	if _last_error(rec, String(f["id"])) != "":
		return "The copies would not fit: nothing was changed"
	rep_id = String(f["id"])
	tweak = {}
	_say("Repeated in a row: move the sliders for how many and the gap, or pick Up, Forward or Ring")
	return ""


## FRULER: Repeat it on a newest cut: a Row pattern step over that cut (Part _cut_row replays the copies). The spacing = the cut's width + the gap
func _repeat_cut(rec: Dictionary, ext: Dictionary) -> String:
	var sk := Part.feature(rec, String(ext.get("sketch", "")))
	if sk.is_empty():
		return "Draw the cut first, then repeat it"
	var lo := INF
	var hi := -INF
	for e in sk.get("ents", []):
		for k in ["a", "b"]:
			if e.has(k):
				lo = minf(lo, float(e[k][0]))
				hi = maxf(hi, float(e[k][0]))
		if e.has("c"):
			lo = minf(lo, float(e["c"][0]) - float(e.get("r", 0.0)))
			hi = maxf(hi, float(e["c"][0]) + float(e.get("r", 0.0)))
	if lo == INF or hi - lo < 1e-6:
		return "Draw the cut first, then repeat it"
	var w_mm := hi - lo
	var nb := int(Part.replay(rec)["bodies"])
	var f := Part.new_feature(rec, "pattern", {"kind": "linear", "body": maxi(nb - 1, 0), "count": 3, "dir": "x", "axis": "y", "deg": 360.0,
		"mm": w_mm + 10.0, "w": w_mm, "h": 10.0, "d": 10.0, "gap": 10.0, "op": "cut", "sketch": sk["id"], "dist": float(ext.get("dist", -10.0)), "both": bool(ext.get("both", false))})
	rec["features"].append(f)
	if _last_error(rec, String(f["id"])) != "":
		return "The copies would not fit: nothing was changed"
	rep_id = String(f["id"])
	tweak = {}
	_say("Repeated in a row: move the sliders for how many and the gap")
	return ""


## Up and Forward (FSTAIRS): a staircase of 8 steps, each one rise up and one run forward from the last (the piece's own height and depth)
func _rep_stairs() -> void:
	if Part.feature(_rec(), rep_id).is_empty():
		return
	_flush_if_dirty()
	_begin("Up and Forward")
	var cur := Part.feature(_rec(), rep_id)
	cur["kind"] = "stairs"
	cur["count"] = 8
	cur["beside"] = false
	_end()
	pu.sync()
	_rep_sync()
	_values_sync()
	var err: String = pu.replay_full(_rec())["errors"].get(rep_id, "")
	if err != "":
		_say(_plain(err) + ". Press Repeat it again, or undo")
	else:
		_say("Up and Forward: 8 steps. Move How many for more or fewer steps")


## Corners (EREPEAT): the newest piece goes to the four corners of the body it touches, one undo step; the four become one body with it
func _rep_corners() -> void:
	if Part.feature(_rec(), rep_id).is_empty():
		return
	_flush_if_dirty()
	_begin("Corners")
	var cur := Part.feature(_rec(), rep_id)
	cur["kind"] = "corners"
	cur["count"] = 4
	_end()
	pu.sync()
	_rep_sync()
	var err: String = pu.replay_full(_rec())["errors"].get(rep_id, "")
	if err != "":
		_say(_plain(err) + ". Move the piece onto a corner of the piece it sits on, then press Corners again, or undo")
	else:
		_say("Corners: four copies, one at each corner of the piece it sits on")


## Row (linear, along X) or Ring (circular, round the up axis Y, a full turn): one undo step; Gap spaces both (in a Ring it sets the circle size)
func _rep_mode(ring: bool) -> void:
	if Part.feature(_rec(), rep_id).is_empty():
		return
	_flush_if_dirty()
	_begin("Ring" if ring else "Row")
	var cur := Part.feature(_rec(), rep_id)
	cur["kind"] = "circular" if ring else "linear"
	cur["beside"] = ring   # round a point beside the piece: a ring round the origin piles copies of a piece AT the origin onto each other
	cur["axis"] = "y"
	cur["deg"] = 360.0
	if not ring and String(cur.get("dir", "x")) != "x":   # FBENCH: back from Forward or Up: the spacing is the piece's width ALONG X
		var wx := _feat_mm(cur, "x")
		if wx > 0.0:
			cur["w"] = wx
	cur["dir"] = "x"
	cur["mm"] = _span(cur) + float(cur.get("gap", 10.0))
	_end()
	pu.sync()
	_rep_sync()
	_values_sync()
	_say("Ring: the copies go round in a circle" if ring else "Row: the copies go in a straight line")   # FWHEEL: "beside it" lied for a spoke (its copies go round the middle)


## EREPEATUP + FBENCH: Up or Forward: the same straight copies, stacked up (y) or put one behind the other (z); spaced by the body's
## height or depth (its real size, measured from the body; the feature's size when the body is not there) plus the gap. One undo step
func _rep_dir(ax: String) -> void:
	if Part.feature(_rec(), rep_id).is_empty():
		return
	_flush_if_dirty()
	_begin("Up" if ax == "y" else ("Forward" if ax == "z" else "Row"))
	var cur := Part.feature(_rec(), rep_id)
	cur["kind"] = "linear"
	cur["beside"] = false
	cur["axis"] = "y"
	cur["deg"] = 360.0
	cur["dir"] = ax
	var sp := _feat_mm(cur, ax)
	cur["mm"] = (sp if sp > 0.0 else _span(cur)) + float(cur.get("gap", 10.0))
	_end()
	pu.sync()
	_rep_sync()
	_values_sync()
	_say("Up: the copies stack upward, one on top of the other" if ax == "y" else ("Forward: the copies go one behind the other" if ax == "z" else "Row: the copies go sideways in a straight line"))


## FBENCH: the size of the copied piece of a Repeat step along one way ("x" | "y" | "z") in mm; -1 when it is not there (the caller falls back)
func _feat_mm(cur: Dictionary, dir: String) -> float:
	var src := String(cur.get("src", ""))
	if src != "":
		var sub := Part.pattern_src_rec(_rec(), src)
		if not sub.is_empty():
			return _piece_mm(sub, -1, dir)
	return _piece_mm(_rec(), int(cur.get("body", -1)), dir)


## FBENCH: the size of body bi along one way ("x" | "y" | "z") in mm (bi -1: the last body); -1 when the body is not there (the caller falls back to the feature's size)
func _piece_mm(rec: Dictionary, bi: int, dir: String) -> float:
	var faces := Part.body_faces(rec, -1)
	if bi < 0:
		bi = faces.size() - 1
	if bi < 0 or bi >= faces.size() or (faces[bi] as PackedVector3Array).size() == 0:
		return -1.0
	var pts: PackedVector3Array = faces[bi]
	var bb := AABB(pts[0], Vector3.ZERO)
	for q in pts:
		bb = bb.expand(q)
	var s := bb.size
	var n := s.x if dir == "x" else (s.y if dir == "y" else s.z)
	return maxf(n / Part.MM, 1.0)


## the repeat box follows the last Repeat it step (its count, its gap, Row or Ring)
func _rep_sync() -> void:
	if repeat_box == null:
		return
	var f := Part.feature(_rec(), rep_id)
	if f.is_empty():
		return
	var ring := String(f.get("kind", "linear")) == "circular"
	var lin := String(f.get("kind", "linear")) == "linear"
	(rep_btns["row"] as Button).set_pressed_no_signal(lin and String(f.get("dir", "x")) == "x")
	(rep_btns["up"] as Button).set_pressed_no_signal(lin and String(f.get("dir", "x")) == "y")
	(rep_btns["forward"] as Button).set_pressed_no_signal(lin and String(f.get("dir", "x")) == "z")
	(rep_btns["ring"] as Button).set_pressed_no_signal(ring)
	(rep_btns["corners"] as Button).set_pressed_no_signal(String(f.get("kind", "")) == "corners")
	(rep_btns["stairs"] as Button).set_pressed_no_signal(String(f.get("kind", "")) == "stairs")
	var kind := String(f.get("kind", ""))
	var rows_on := kind != "corners"   # CORNERS: four copies at the corners, no How many or Gap to set
	for r in rep_rows:
		# UP AND FORWARD: the steps are a count (How many); a Gap would mean nothing between the steps, so it is not shown
		(r["box"] as Control).visible = rows_on and not (kind == "stairs" and String(r["key"]) == "gap")
	for r in rep_rows:
		var s: HSlider = r["slider"]
		var v := float(f.get("count", 3)) if String(r["key"]) == "count" else float(f.get("gap", 10.0)) / 10.0
		if not bool(r.get("held", false)):
			s.set_value_no_signal(v)
		_pill_text(r, v)
