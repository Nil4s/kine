extends "res://scripts/easy_part_repeat.gd"
## EASY PART PULL: Pull it up and Spin it round, and the Cut a hole chips that hollow a solid out (Hollow inside, the open side, the
## lid and its Snap-fit lip). What a pull becomes (joined to the body it sits on, its own body, a cut, a lid on the rim) is decided in ONE
## table, PULL_RULES, read by _pull_rule: a new pull case is one row there.

## the hole chips show after a Cut a hole press, while its step is the newest hole and nothing is armed
func _hole_on() -> bool:
	return not hole_base.is_empty() and armed == "" and not Part.feature(_rec(), hole_id).is_empty()


func _hole_sync() -> void:
	for k in hole_btns:
		(hole_btns[k] as Button).set_pressed_no_signal(k == hole_mode)
	if snap_btn != null:
		snap_btn.set_pressed_no_signal(_rec_has_lip())   # the record says it (an Undo takes the chip off with the lip)
		snap_btn.visible = hole_mode == "lid"   # the chip only exists for a lid
	if wall_btn != null:
		wall_btn.set_pressed_no_signal(wall_pick)
		wall_btn.visible = hole_mode == "hollow" and _hole_on()   # Thicker wall only exists for a hollow


## a Through / Hollow inside chip: the hole step is REPLACED (one undo step): the record from before the hole press, then the chosen hole.
## A hollow that fails (a body too thin for the wall) says so and changes nothing
func _hole_mode(mode: String, lip := false, rebuild := false) -> void:   # lip: the lid with its Snap-fit lip; rebuild: the same chip again (the Snap-fit lip press)
	if not _hole_on() or not Part.available() or (mode == hole_mode and not rebuild):
		_hole_sync()
		return
	_flush_if_dirty()
	armed = ""
	wall_pick = false
	var snap := _rec().duplicate(true)
	_begin("Hollow with a lid" if mode == "lid" else ("Hollow inside" if mode == "hollow" else "Cut a hole"))
	var rec: Dictionary = hole_base.duplicate(true)
	m.S.part = rec
	var why := ""
	if mode.begins_with("screw"):   # p030countersun: a screw chip (screw3 .. screw6) cuts the hole for that screw
		why = _screw_hole(rec, int(mode.trim_prefix("screw")))
	else:
		why = _hollow_lid(rec, lip) if mode == "lid" else (_hollow(rec) if mode == "hollow" else _hole(rec))
	if why != "":
		m.S.part = snap
		m._drop_undo()
		_edit_n = -1
		_say(why)
	else:
		_end()
		hole_mode = mode
		hole_id = String(tweak.get("id", "")) if not tweak.is_empty() else String(rec["features"][-1].get("id", ""))   # the lid has no slider: its newest step keeps the chips up
	pu.upto = -1
	pu.sync()
	_rows_sig = ""   # the step's id can repeat the last one (the chips rebuild from an older record): the slider box is rebuilt anyway
	_rows_sync()
	_values_sync()


## NOPENTOP: after Hollow inside, a click on a flat face makes THAT face the open side (one undo step): the shell's "open" is set to the
## face's direction and the Wall slider keeps its step (the same id). A side that cannot open says so and changes nothing. false = not a face click here
const OPEN_WORDS := {"+x": "right", "-x": "left", "+y": "top", "-y": "bottom", "+z": "front", "-z": "back"}


func _open_face(p: Vector2) -> bool:
	if hole_mode != "hollow" or not _hole_on() or _tpl() != "":
		return false
	var sh := Part.feature(_rec(), hole_id)
	if String(sh.get("t", "")) != "shell":
		return false
	var fc := _face_hit(p)
	if fc.is_empty():
		return false
	var ax := ["right", "top", "front"].find(String(fc.get("base", "")))
	if ax < 0:
		return false
	var dir: String = ["+x", "+y", "+z"][ax] if int(fc.get("out", 1)) > 0 else ["-x", "-y", "-z"][ax]
	var side: String = String(OPEN_WORDS[dir])
	if dir == String(sh.get("open", "")):
		_say("The %s is already open. Click another flat face to open that one" % side)
		return true
	_flush_if_dirty()
	armed = ""
	var snap := _rec().duplicate(true)
	_begin("Open the " + side)
	var rec: Dictionary = snap.duplicate(true)
	Part.feature(rec, hole_id)["open"] = dir
	var why := ""
	if _last_error(rec, hole_id) != "":
		why = "The %s cannot be the open side: click another flat face, or Cut a hole again" % side
	if why != "":
		m.S.part = snap
		m._drop_undo()
		_edit_n = -1
		_say(why)
	else:
		m.S.part = rec
		_end()
		_say("Open the %s: the %s is open now. The Wall slider still sets the wall" % [side, side])
	pu.upto = -1
	pu.sync()
	_rows_sync()
	_values_sync()
	return true


## SHELL WALLS (p022shellwalls, Friday plan 22): Thicker wall under Hollow inside arms the wall pick (the chip stays pressed); the next
## press on the outside of a side wall makes THAT wall thicker by the Extra wall slider (WALL_EXTRA_MM at first). The other walls keep the
## shell's thickness. Off with a second press. Only a hollow has the chip; the other shapes say what to press first
const WALL_EXTRA_MM := 1.0   # the extra thickness a picked wall starts with (mm)


func _wall_chip() -> void:
	if not _hole_on() or hole_mode != "hollow" or not Part.available():
		wall_pick = false
		_hole_sync()
		_say("Thicker wall needs a hollow first: press Cut a hole, then Hollow inside, then Thicker wall")
		return
	wall_pick = not wall_pick
	_hole_sync()
	_say("Click the outside of the side wall you want thicker. Press Thicker wall again to stop" if wall_pick else "Thicker wall is off")


## the press that picks the wall (wall_pick is on): a side wall's outside, not the open side. "" or why not (one undo step)
func _wall_press(p: Vector2) -> void:
	wall_pick = false
	_hole_sync()
	var fc := _face_hit(p)
	var ax := ["right", "top", "front"].find(String(fc.get("base", "")))
	if ax < 0 or ax == 1:   # the top is the open side or a lid: side walls only
		_say("Click a side wall (front, back, left or right), not the top. Then press Thicker wall again")
		return
	var out := int(fc.get("out", 1))
	var bb: AABB = pu.res.get("aabb", AABB())
	var edge: float = (bb.end[ax] if out > 0 else bb.position[ax]) / Part.MM
	if absf(float(fc.get("mm", 0.0)) - edge) > 0.05:
		_say("That is inside the box: click the outside of a side wall. Then press Thicker wall again")
		return
	var dir: String = ["+x", "+y", "+z"][ax] if out > 0 else ["-x", "-y", "-z"][ax]
	var side: String = String(OPEN_WORDS[dir])
	var sh := Part.feature(_rec(), hole_id)
	if dir == String(sh.get("open", "")):
		_say("The %s is the open side: click another side wall. Then press Thicker wall again" % side)
		return
	_flush_if_dirty()
	armed = ""
	var snap := _rec().duplicate(true)
	_begin("Thicker %s wall" % side)
	var rec: Dictionary = snap.duplicate(true)
	var why := _wall_add(rec, sh, ax, out, float(fc.get("mm", 0.0)))
	if why != "":
		m.S.part = snap
		m._drop_undo()
		_edit_n = -1
		_say(why)
	else:
		m.S.part = rec
		_end()
		_say("The %s wall is thicker now: use the Extra wall slider for how much more" % side)
	pu.upto = -1
	pu.sync()
	_rows_sync()
	_values_sync()


## the thicker wall, added to rec: a plate on the wall's inside (from the shell's inner face, out to the wall's own inside),
## joined to the body and running from the floor to the open side's rim, 0.2 mm into the other walls. The Extra wall slider
## is that plate's depth. "" or why not
func _wall_add(rec: Dictionary, sh: Dictionary, ax: int, out: int, outer_mm: float) -> String:
	var t := float(sh.get("thick", HOLLOW_MM))
	var bb: AABB = pu.res.get("aabb", AABB())
	var lo := bb.position / Part.MM
	var hi := bb.end / Part.MM
	var base: String = ["right", "top", "front"][ax]
	var inner := snappedf(outer_mm - float(out) * t, 0.01)   # the shell's inner face on this wall (mm along the axis)
	var pf := Part.new_feature(rec, "plane", {"from": base, "mm": inner})
	rec["features"].append(pf)
	var pl := Part.resolve_plane(rec, String(pf["id"]))
	var open := String(sh.get("open", ""))
	var names := ["x", "y", "z"]
	var w1 := Vector3.ZERO
	var w2 := Vector3.ZERO
	for a in 3:
		if a == ax:
			w1[a] = inner
			w2[a] = inner
			continue
		var lo_a := lo[a] + t - 0.2   # the plate runs 0.2 mm into the walls on each side
		var hi_a := hi[a] - t + 0.2
		if open == "-" + names[a]:
			lo_a = lo[a]   # an open side: the plate runs out to the rim
		if open == "+" + names[a]:
			hi_a = hi[a]
		w1[a] = lo_a
		w2[a] = hi_a
	var sk := Part.new_feature(rec, "sketch", {"plane": String(pf["id"]), "ents": [{"k": "rect", "a": Part.arr2(Part.to_plane(pl, w1 * Part.MM)), "b": Part.arr2(Part.to_plane(pl, w2 * Part.MM))}], "dims": []})
	rec["features"].append(sk)
	var ex := Part.new_feature(rec, "extrude", {"sketch": sk["id"], "dist": -float(out) * WALL_EXTRA_MM, "both": false, "op": "join", "into": 0})
	rec["features"].append(ex)
	if _last_error(rec, String(ex["id"])) != "" or int(Part.replay(rec)["bodies"]) != 1:
		return "That wall cannot take a thicker wall. Press Cut a hole again, then Hollow inside, and try the wall once more"
	tweak = {"id": ex["id"], "field": "dist", "label": "Extra wall", "unit": "mm", "lo": 0.5, "hi": 20.0, "step": 0.5, "scale": 1.0, "words": ["Thinner", "Thicker"], "sgn": -float(out)}
	return ""


## p030countersun (Kine's own): the hole knows the screw. Clearance hole for an ISO 4762 socket screw, through the middle of the newest solid
## (M3 3.4 mm, M4 4.5 mm, M5 5.5 mm, M6 6.6 mm), and a counterbore on the top face (+Z) for its head (head across and depth from
## PartTemplates.SCREW_HEAD). Both cuts are one step. A cut that misses the solid changes nothing and says so
const SCREW_CLEAR := {3: 3.4, 4: 4.5, 5: 5.5, 6: 6.6}


func _screw_hole(rec: Dictionary, d: int) -> String:
	var res := Part.replay(rec)
	if int(res["bodies"]) == 0:
		return "Nothing solid to cut a hole in yet. Press Pull it up first"
	var bb: AABB = res["aabb"]
	var c := bb.get_center() / Part.MM
	var head: Array = PartTemplates.SCREW_HEAD[d]   # [head across mm, head depth mm]
	var clear := float(SCREW_CLEAR[d])
	var before := float(res["volume"])
	var n0: int = rec["features"].size()
	var seq0 := int(rec.get("seq", 0))
	var top := Part.new_feature(rec, "plane", {"from": "front", "mm": bb.end.z / Part.MM})   # the top face: the plane the head's counterbore starts on
	rec["features"].append(top)
	var cb := Part.new_feature(rec, "sketch", {"plane": String(top["id"]), "ents": [{"k": "circle", "c": Part.arr2(Vector2(c.x, c.y)), "r": float(head[0]) / 2.0}], "dims": []})
	rec["features"].append(cb)
	rec["features"].append(Part.new_feature(rec, "extrude", {"sketch": cb["id"], "dist": -float(head[1]), "both": false, "op": "cut"}))   # a negative dist runs down into the solid
	var th := Part.new_feature(rec, "sketch", {"plane": "front", "ents": [{"k": "circle", "c": Part.arr2(Vector2(c.x, c.y)), "r": clear / 2.0}], "dims": []})
	rec["features"].append(th)
	rec["features"].append(Part.new_feature(rec, "extrude", {"sketch": th["id"], "dist": snappedf(2.0 * (maxf(absf(bb.position.z), absf(bb.end.z)) / Part.MM + 10.0), 1.0), "both": true, "op": "cut"}))
	var after := float(pu.replay_full(rec)["volume"])
	if not (after < before - 1e-12 and after > 1e-9):
		rec["features"].resize(n0)
		rec["seq"] = seq0
		return "The screw hole would miss the shape: nothing was cut. Make the shape bigger, or pick a smaller screw"
	tweak = {}   # the screw hole has no Hole size slider: its newest step keeps the chips up
	_say("M%d screw: a %s mm hole, its %s mm head sunk %s mm deep. Mirror that or Repeat it next" % [d, _mm_words(clear), _mm_words(float(head[0])), _mm_words(float(head[1]))])
	return ""


## SNAP-FIT LIP (nsnaplip): the on/off chip under Hollow with a lid. On: the lid's ridge and the box's groove are rebuilt from the same
## hole base (one undo step). Only a lid has a snap; the other shapes say what to press first
func _snap_press() -> void:
	if hole_mode != "lid" or not _hole_on() or not Part.available():
		_hole_sync()
		_say("Snap-fit lip needs a lid first: press Cut a hole, then Hollow with a lid, then Snap-fit lip")
		return
	_hole_mode("lid", not _rec_has_lip(), true)   # on: rebuild the lid with the lip; off: rebuild it plain (the same chip, one step)

## the record has a snap-fit lip (its groove step is tagged "lip")
func _rec_has_lip() -> bool:
	for f in _rec().get("features", []):
		if bool((f as Dictionary).get("lip", false)):
			return true
	return false


## HOLLOW INSIDE: Part's shell on the newest solid, open at its TOP face ("+y": the planar face with the largest +Y centre),
## a HOLLOW_MM wall. The Wall slider moves the thickness (mm)
func _hollow(rec: Dictionary) -> String:
	var res := Part.replay(rec)
	var n := int(res["bodies"])
	if n == 0:
		return "Nothing solid to hollow out yet. Press Pull it up first"
	var bb: AABB = res["aabb"]
	var thin := minf(bb.size.x, minf(bb.size.y, bb.size.z)) / Part.MM   # the body's smallest size (mm): a wall needs room on both sides
	var too_thin := "That solid is too thin to hollow out with a 3 mm wall: Pull it up taller, then press Cut a hole again"
	if thin <= 2.0 * HOLLOW_MM:
		return too_thin
	var last: Dictionary = rec["features"][-1] if not rec["features"].is_empty() else {}
	if String(last.get("t", "")) == "loft" and (last.get("sketches", []) as Array).size() == 2:
		return _hollow_loft(rec, last)   # a blended bowl: Part's shell on a loft takes minutes, so the wall is an inner loft cut out instead
	var f := Part.new_feature(rec, "shell", {"body": n - 1, "open": "+y", "thick": HOLLOW_MM})
	rec["features"].append(f)
	if _last_error(rec, String(f["id"])) != "":
		rec["features"].pop_back()   # the kernel's shell refuses a cup standing on a base (it picks the base's ring for the open top): cut the cup's inside instead
		return _hollow_cup(rec, too_thin)
	tweak = {"id": f["id"], "field": "thick", "label": "Wall", "unit": "mm", "lo": 1.0, "hi": 10.0, "step": 0.5, "scale": 1.0, "words": ["Thinner", "Thicker"]}
	_say("Hollowed out, open at the top: use the slider for the wall")
	return ""


## HOLLOW WITH A LID (nlid): a box (one body, a rectangle pulled up) is split at its top LID_MM: the top slice is the LID, a solid plate on
## the box's footprint; the rest is hollowed out (a HOLLOW_MM wall, open at the top). A lip (1 mm ring, LID_LIP_MM tall, 0.2 mm inside the
## walls) hangs under the lid into the box: a plug cut back to a ring. Box-shaped only; no slider (the lip is cut to the walls). "" or why not
func _hollow_lid(rec: Dictionary, snap := false) -> String:
	var res := Part.replay(rec)
	if int(res["bodies"]) == 0:
		return "Nothing solid to hollow out yet. Press Pull it up first"
	var bb: AABB = res["aabb"]
	var sz := bb.size / Part.MM
	var too_small := "That box is too small for a lid: Pull it up at least 12 mm tall and 12 mm wide, then press Cut a hole again"
	if int(res["bodies"]) != 1 or minf(sz.x, minf(sz.y, sz.z)) < 12.0:
		return too_small
	if float(res["volume"]) / (Part.MM * Part.MM * Part.MM) < 0.98 * sz.x * sz.y * sz.z:
		return "A lid needs a box: Pull a rectangle up into a box, then press Cut a hole again"
	var x0 := bb.position.x / Part.MM
	var x1 := bb.end.x / Part.MM
	var z0 := bb.position.z / Part.MM
	var z1 := bb.end.z / Part.MM
	var top := bb.end.y / Part.MM
	var ins_o := HOLLOW_MM + 0.2          # the lip's outer face: 0.2 mm inside the wall
	var ins_i := ins_o + 1.0              # the lip's inner face: a 1 mm ring
	var sp := Part.new_feature(rec, "split", {"plane": "top", "at": top - LID_MM, "keep": 0})   # bodies: [the top slice (the lid), the box]
	rec["features"].append(sp)
	var sh := Part.new_feature(rec, "shell", {"body": 1, "thick": HOLLOW_MM, "open": "+y"})
	rec["features"].append(sh)
	var fids := [sp["id"], sh["id"]]
	var band_y := top - LID_MM - LID_LIP_MM + 1.0   # the snap band: 1 mm tall, the lip's middle third (under the plate, above the lip's floor)
	var gr: Dictionary = {}
	if snap:   # the groove first (the box is alone on its wall here; a cut hits every body): a ring 0.5 mm deep in the wall
		var pg := Part.new_feature(rec, "plane", {"from": "top", "mm": band_y})
		rec["features"].append(pg)
		var sg := Part.new_feature(rec, "sketch", {"plane": String(pg["id"]), "ents": [_rect_ent(x0 + HOLLOW_MM - LIP_RIDGE_MM, z0 + HOLLOW_MM - LIP_RIDGE_MM, x1 - HOLLOW_MM + LIP_RIDGE_MM, z1 - HOLLOW_MM + LIP_RIDGE_MM)], "dims": []})
		rec["features"].append(sg)
		gr = Part.new_feature(rec, "extrude", {"sketch": sg["id"], "dist": 1.0, "both": false, "op": "cut", "lip": true})
		rec["features"].append(gr)
		fids.append(gr["id"])
	var pf := Part.new_feature(rec, "plane", {"from": "top", "mm": top - LID_MM - LID_LIP_MM})
	rec["features"].append(pf)
	var s1 := Part.new_feature(rec, "sketch", {"plane": String(pf["id"]), "ents": [_rect_ent(x0 + ins_o, z0 + ins_o, x1 - ins_o, z1 - ins_o)], "dims": []})
	rec["features"].append(s1)
	var f1 := Part.new_feature(rec, "extrude", {"sketch": s1["id"], "dist": LID_LIP_MM, "both": false, "op": "join", "into": 0})
	rec["features"].append(f1)
	var s2 := Part.new_feature(rec, "sketch", {"plane": String(pf["id"]), "ents": [_rect_ent(x0 + ins_i, z0 + ins_i, x1 - ins_i, z1 - ins_i)], "dims": []})
	rec["features"].append(s2)
	var f2 := Part.new_feature(rec, "extrude", {"sketch": s2["id"], "dist": LID_LIP_MM, "both": false, "op": "cut"})
	rec["features"].append(f2)
	fids.append_array([f1["id"], f2["id"]])
	if snap:   # the ridge: a ring 0.5 mm proud of the lip, joined to the lid (body 0) in the same band as the groove
		var pr := Part.new_feature(rec, "plane", {"from": "top", "mm": band_y})
		rec["features"].append(pr)
		var ro := HOLLOW_MM + 0.2 - LIP_RIDGE_MM   # the ridge's outside: 2.7 mm in (0.5 mm proud of the lip's 3.2 mm face)
		var ri := HOLLOW_MM + 0.2                  # the ridge's inside: the lip's own outer face
		var bars := [[x0 + ro, z0 + ro, x1 - ro, z0 + ri], [x0 + ro, z1 - ri, x1 - ro, z1 - ro], [x0 + ro, z0 + ri, x0 + ri, z1 - ri], [x1 - ri, z0 + ri, x1 - ro, z1 - ri]]
		fids.append(pr["id"])
		for b in bars:   # four bars (front, back, left, right), each joined to the lid (body 0): a ring with no cut
			var sr := Part.new_feature(rec, "sketch", {"plane": String(pr["id"]), "ents": [_rect_ent(b[0], b[1], b[2], b[3])], "dims": []})
			rec["features"].append(sr)
			var fr := Part.new_feature(rec, "extrude", {"sketch": sr["id"], "dist": 1.0, "both": false, "op": "join", "into": 0, "lip": true})
			rec["features"].append(fr)
			fids.append(fr["id"])
	for fid in fids:
		if _last_error(rec, String(fid)) != "":
			return too_small
	if Part.replay(rec)["bodies"] != 2:
		return too_small
	tweak = {}
	_say("Hollowed out with a lid and a snap-fit lip: the lid's ridge clicks into the box's groove. Ctrl+Z undoes it" if snap else "Hollowed out with a lid: the top 5 mm is the lid, sitting on the box. Ctrl+Z undoes it")
	return ""


## a rectangle sketch entity from its two corners in the sketch's plane (top plane: v = -Z), mm
func _rect_ent(xa: float, za: float, xb: float, zb: float) -> Dictionary:
	return {"k": "rect", "a": Part.arr2(Vector2(xa, -za)), "b": Part.arr2(Vector2(xb, -zb))}


## FCANDLE: Hollow inside for a cup on a base (the newest round piece on a solid): a circle HOLLOW_MM inside the cup's own shape, cut down
## from the top of the whole solid to HOLLOW_MM above the cup's floor. The cup keeps its floor and wall and is open at the top. "" or why not
func _hollow_cup(rec: Dictionary, too_thin: String) -> String:
	var sk := _last_sketch(rec)
	if sk.is_empty() or (sk["ents"] as Array).size() != 1 or String((sk["ents"][0] as Dictionary).get("k", "")) != "circle":
		return too_thin
	var ent: Dictionary = sk["ents"][0]
	var pl := Part.resolve_plane(rec, String(sk.get("plane", "top")))
	var floor_mm: float = float(pl["o"].y) / Part.MM   # the cup's floor: the plane it was drawn on (mm)
	var top_mm: float = Part.replay(rec).get("aabb", AABB()).end.y / Part.MM
	var r_in := float(ent.get("r", 0.0)) - HOLLOW_MM
	var depth := top_mm - (floor_mm + HOLLOW_MM)
	if r_in <= 1.0 or depth <= 1.0:
		return too_thin
	var before := float(pu.replay_full(rec)["volume"])
	var pf := Part.new_feature(rec, "plane", {"from": "top", "mm": snappedf(top_mm, 0.1)})
	rec["features"].append(pf)
	var c: Array = ent.get("c", [0.0, 0.0])
	var s := Part.new_feature(rec, "sketch", {"plane": String(pf["id"]), "ents": [{"k": "circle", "c": c.duplicate(), "r": snappedf(r_in, 0.1)}], "dims": []})
	rec["features"].append(s)
	var f := Part.new_feature(rec, "extrude", {"sketch": s["id"], "dist": -snappedf(depth, 0.1), "both": false, "op": "cut"})
	rec["features"].append(f)
	if _last_error(rec, String(f["id"])) != "" or float(pu.replay_full(rec)["volume"]) >= before - 1e-12:
		return too_thin
	tweak = {"id": f["id"], "field": "dist", "label": "How deep", "unit": "cm", "lo": 0.1, "hi": 40.0, "step": 0.1, "scale": 10.0, "words": ["Shallower", "Deeper"], "sgn": -1.0}
	_say("Hollowed out, open at the top: use the slider for how deep")
	return ""


## HOLLOW A BLEND (FSPOON): the inner loft of the blend's two shapes, each pulled in by HOLLOW_MM (the lower one lifted HOLLOW_MM off
## the bottom, the upper one carried past the top), cut out of the solid: open at the top, a 3 mm wall. Part's shell on the same loft
## took about 3 minutes per replay; this cut takes a few seconds. The wall is fixed (no Wall slider)
func _hollow_loft(rec: Dictionary, lf: Dictionary) -> String:
	var a: Dictionary = Part.feature(rec, String(lf["sketches"][0]))
	var b: Dictionary = Part.feature(rec, String(lf["sketches"][1]))
	var ha := _half_mm(a["ents"])
	var hb := _half_mm(b["ents"])
	var height := maxf(absf(_plane_mm(rec, b) - _plane_mm(rec, a)), 1.0)
	var taper := maxf((ha - hb) / height, 0.0)   # the blend narrows by this much per mm of height: the top of the cut follows it
	var ia := _inner_sketch(rec, a, HOLLOW_MM, HOLLOW_MM)
	var ib := _inner_sketch(rec, b, 20.0, HOLLOW_MM + taper * 20.0)
	if (ia["ents"] as Array).is_empty() or (ib["ents"] as Array).is_empty():
		return "Those two shapes are too small to hollow out with a 3 mm wall: draw bigger shapes, then press Blend two shapes again"
	var f := Part.new_feature(rec, "loft", {"sketches": [ia["id"], ib["id"]], "ruled": true, "op": "cut"})
	rec["features"].append(f)
	if _last_error(rec, String(f["id"])) != "":
		return "That blend is too thin to hollow out with a 3 mm wall: draw bigger shapes, then press Blend two shapes again"
	tweak = {}
	_say("Hollowed out, open at the top: the wall is 3 mm")
	return ""


## the offset of a sketch's plane along its normal (mm)
func _plane_mm(rec: Dictionary, sk: Dictionary) -> float:
	var pid := String(sk["plane"])
	return 0.0 if pid in Part.PLANES else float(Part.feature(rec, pid).get("mm", 0.0))


## a sketch on a plane lift mm above its own, its outline pulled in by shrink mm (a new plane and a new sketch; the sketch is returned)
func _inner_sketch(rec: Dictionary, sk: Dictionary, lift: float, shrink: float) -> Dictionary:
	var pid := String(sk["plane"])
	var pl := Part.new_feature(rec, "plane", {"from": _base_plane(rec, pid), "mm": _plane_mm(rec, sk) + lift})
	rec["features"].append(pl)
	var s2 := Part.new_feature(rec, "sketch", {"plane": String(pl["id"]), "ents": _shrunk(sk["ents"], shrink), "dims": []})
	rec["features"].append(s2)
	return s2


## the middle and the half of the smaller side (mm) of a sketch's entities: a circle's half is its radius
func _mid_half(ents: Array) -> Array:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var rad := -1.0
	for e in ents:
		if String((e as Dictionary).get("k", "")) == "circle":
			rad = maxf(rad, float(e["r"]))
			lo = lo.min(Vector2(float(e["c"][0]), float(e["c"][1])))
			hi = hi.max(Vector2(float(e["c"][0]), float(e["c"][1])))
			continue
		for q in _ent_pts(e):
			lo = lo.min(Vector2(float(q[0]), float(q[1])))
			hi = hi.max(Vector2(float(q[0]), float(q[1])))
	if lo.x > hi.x:
		return [Vector2.ZERO, 0.0]
	var half := minf(hi.x - lo.x, hi.y - lo.y) * 0.5
	if rad >= 0.0:
		half = rad
	return [(lo + hi) * 0.5, half]


## the half of a sketch's smaller side (mm): the wall needs room inside it
func _half_mm(ents: Array) -> float:
	return float(_mid_half(ents)[1])


## the outline pulled in by d mm: its points scale about the middle (a circle's radius less d); [] when d leaves nothing
func _shrunk(ents: Array, d: float) -> Array:
	var mh := _mid_half(ents)
	var c: Vector2 = mh[0]
	var half: float = mh[1]
	if half <= d + 1.0:
		return []
	var k := (half - d) / half
	var out := []
	for e in ents:
		var e2: Dictionary = (e as Dictionary).duplicate(true)
		if String(e2.get("k", "")) == "circle":
			e2["r"] = float(e2["r"]) - d
		else:
			for key in ["a", "b"]:
				if e2.has(key) and e2[key] is Array:
					e2[key] = Part.arr2(c + (Vector2(float(e2[key][0]), float(e2[key][1])) - c) * k)
			if e2.has("pts"):
				var np := []
				for q in e2["pts"]:
					np.append(Part.arr2(c + (Vector2(float(q[0]), float(q[1])) - c) * k))
				e2["pts"] = np
		out.append(e2)
	return out


func _pull(rec: Dictionary) -> String:
	var sid := Part.profile_sketch(rec)
	if sid == "" or Part.sketch_used(rec, sid):
		return "Draw a shape first, then pull it up"
	var sk := Part.feature(rec, sid)
	var ext := 0.0
	for e in sk["ents"]:
		for k in ["a", "b", "c"]:
			if e.has(k):
				ext = maxf(ext, maxf(absf(float(e[k][0])), absf(float(e[k][1]))))
	var pf := Part.feature(rec, String(sk.get("plane", "front")))
	var on_face := String(pf.get("t", "")) == "plane" and pf.has("out")   # a sketch on a face: the pull goes OUTWARD from it
	var sg := float(pf["out"]) if on_face else 1.0
	var through := bool(pf.get("through", false))   # an upright sketch (through the middle) pulls BOTH ways
	var inward := on_face and not through and _overhangs(rec, sk) and not _top_face(pf)
	if inward:
		sg = -sg   # a face drawing that hangs past the body (a roof above the walls) pulls back INTO it: it extends the body's outline; one inside the face (a leg) pulls out
	# ETABLE: a top drawn on the TOP of the legs hangs past them, but it stands ON them: a top face pulls up (out), never into the legs
	var dist := 20.0 * sg
	# A ROUND CUP (FMUG3): the first pull of a blank part, of one circle, stands as tall as its radius (a mug, not a 2 cm puck)
	if not through and not on_face and sk["ents"].size() == 1 and String(sk["ents"][0].get("k", "")) == "circle" and not _has_pull(rec):
		dist = maxf(20.0, snappedf(float(sk["ents"][0]["r"]), 1.0))   # sketch units are mm: the radius is the height
	if through and _sits_on_body(rec, sk):
		# A ROOF: pulled out both ways from the middle to the box's depth (the slider changes it from there)
		var bb: AABB = Part.replay(rec).get("aabb", AABB())
		var depth := bb.size.z if String(pf.get("from", "front")) == "front" else bb.size.x
		dist = snappedf(depth / Part.MM, 1.0)
	# FBOX: a LID: a face drawing on the top of a hollow (shelled) body is a separate piece, not joined to the box (it rests on the rim)
	var lid := on_face and _top_face(pf) and _has_shell(rec)
	var slot := not on_face and not through and _slot_cut(rec, sk, dist)   # FWRENCH2: a jaw slot at the end of a solid CUTS it
	var rule := _pull_rule({"lid": lid, "slot": slot, "through": through, "inward": inward, "on_face": on_face,
		"flat": not (lid or slot or through or on_face) and _flat_plate(sk, dist)})
	var nb0 := int(Part.replay(rec).get("bodies", 0))   # FLAMP: a shape that stands apart from the solid is its own body, not one lump
	var lk0 := _lumps(Part.replay(rec)) if nb0 > 0 else 0
	var f := Part.new_feature(rec, "extrude", {"sketch": sid, "dist": dist, "both": through, "op": String(rule["op"])})
	rec["features"].append(f)
	var err := _last_error(rec, String(f["id"]))
	if err == "" and nb0 > 0 and bool(rule["sits_on"]):
		f["into"] = Part.touching_body(rec, f)   # FLAMP5: a pull joins the body it sits on (saved on the step), not the last body
		err = _last_error(rec, String(f["id"]))
		var joined := Part.replay(rec)
		if int(joined.get("bodies", 0)) == nb0 and _lumps(joined) > lk0:
			f["op"] = "new"
			err = _last_error(rec, String(f["id"]))
	if err != "":
		return "That shape is not closed, so it cannot be pulled up: drag back to the start to close it"
	tweak = {"id": f["id"], "field": "dist", "label": "How far", "unit": "cm", "lo": 0.2, "hi": _pull_hi(), "step": 0.2, "scale": 10.0, "words": ["Flatter", "Taller"], "sgn": sg}
	if String(rule["slider"]) == "thickness":
		tweak = _thickness_tweak(f["id"], sg)
	var words := String(rule["say"])
	if bool(rule["slider_says"]):
		tweak["say"] = words   # the words follow the slider (a beginner walk: "2 cm" stayed at 8 cm)
	match String(rule["fill"]):
		"2 cm":
			words = words % _fmt(2.0, "cm")
		"how far":
			words = words % _fmt(absf(dist) / 10.0, "cm")
		"where":
			# FWRENCH2: a beginner does not know the word "face": the top of a solid says "top", a side says "side" (the bottom keeps "face": eface_test pins that text)
			words = words % ("top" if _top_face(pf) else ("side" if String(pf.get("from", "")) in ["front", "right"] else "face"))
	_say(words)
	taper_tw = {"id": f["id"], "label": "Taper", "unit": "deg", "lo": -15.0, "hi": 15.0, "step": 0.5, "words": ["Wider at the top", "Narrower at the top"]} if bool(rule["taper"]) else {}
	return ""


## THE PULL RULES: what a Pull it up becomes, one row per case, read top down by _pull_rule (the first row whose "when" is true wins).
##   name         the case in plain words
##   when         the fact _pull found true for it ("" = every pull that got this far)
##   op           the extrude's op: "join" (onto a body), "new" (its own body), "cut" (into the solid)
##   sits_on      the JOIN PASS (FLAMP5): the pull joins the body it sits on (saved on the step as "into"), and a shape that stands apart from
##                the solid (it joined nothing: no new body, one more lump) becomes its own body ("new") instead of one lump
##   slider       its slider: "how far" (How far) or "thickness" (NTHICK: Thickness, a thin plate 2 mm to a thick block 40 cm)
##   taper        FPLANTER: a Taper slider under How far (a pot wider at the top)
##   say          the sentence after the press; fill: what goes in its %s ("2 cm", "how far" = the pull's own size, "where" = top / side / face)
##   slider_says  the sentence is kept on the slider (tweak "say"), so its size follows a slider move
## A new pull case is one row here (and its fact in _pull).
const PULL_RULES := [
	{"name": "A lid on the rim of a hollow box (FBOX): its own piece, never folded back into the box", "when": "lid",
		"op": "new", "sits_on": false, "slider": "how far", "taper": false, "fill": "", "slider_says": false,
		"say": "A lid on the rim: a separate piece. Use the slider for how tall it is"},
	{"name": "A jaw slot at the end of a solid (FWRENCH2): it cuts the solid, never a new body", "when": "slot",
		"op": "cut", "sits_on": false, "slider": "how far", "taper": true, "fill": "2 cm", "slider_says": true,
		"say": "Cut a slot %s deep into the solid: use the slider to change it, or press Round the edges or Cut a hole next"},
	{"name": "An upright shape through the middle: pulled out both ways (a roof on a box goes to the box's depth)", "when": "through",
		"op": "join", "sits_on": true, "slider": "how far", "taper": false, "fill": "", "slider_says": false,
		"say": "Pulled out both ways from the middle: use the slider for how thick, or press Mirror that or Cut a hole next"},
	{"name": "A face drawing that hangs past the body: pulled back into it (it extends the body's outline)", "when": "inward",
		"op": "join", "sits_on": true, "slider": "how far", "taper": false, "fill": "", "slider_says": false,
		"say": "Pulled into the solid: use the slider to change it, or press Cut a hole next"},
	{"name": "A shape drawn on a face: pulled out of that face, joined to the body it sits on", "when": "on_face",
		"op": "join", "sits_on": true, "slider": "how far", "taper": false, "fill": "where", "slider_says": false,
		"say": "Pulled out of the %s: use the slider to change it, or press Mirror that next"},
	{"name": "A flat plate on the floor (NTHICK): a slab, its slider is Thickness", "when": "flat",
		"op": "join", "sits_on": true, "slider": "thickness", "taper": true, "fill": "how far", "slider_says": true,
		"say": "Pulled up %s: use the slider to change it, or press Round the edges or Cut a hole next"},
	{"name": "A shape on the floor: pulled up, joined to the body it sits on, or its own body when it stands apart", "when": "",
		"op": "join", "sits_on": true, "slider": "how far", "taper": true, "fill": "how far", "slider_says": true,
		"say": "Pulled up %s: use the slider to change it, or press Round the edges or Cut a hole next"},
]


## the first PULL_RULES row whose fact is true (facts: the names _pull worked out, each true or false)
func _pull_rule(facts: Dictionary) -> Dictionary:
	for r in PULL_RULES:
		if String(r["when"]) == "" or bool(facts.get(r["when"], false)):
			return r
	return PULL_RULES[-1]


## NTHICK: a FLAT PLATE is a plain pull of a floor shape whose narrow side is at least 10 cm and whose height is at most half of it (and at most 40 cm):
## a slab, not a wall or a pillar. Its slider reads Thickness, from a thin plate (2 mm) to a thick block (40 cm)
func _flat_plate(sk: Dictionary, dist: float) -> bool:
	if String(sk.get("t", "")) != "sketch":
		return false
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var ents: Array = sk.get("ents", [])
	if ents.is_empty():
		return false
	for e in ents:
		var k := String(e.get("k", ""))
		if k != "rect" and k != "line":   # a circle, an arc or a curve is not a plate: the How far stays
			return false
		for key in ["a", "b"]:
			var p: Array = e[key]
			lo = Vector2(minf(lo.x, float(p[0])), minf(lo.y, float(p[1])))
			hi = Vector2(maxf(hi.x, float(p[0])), maxf(hi.y, float(p[1])))
	var narrow := minf(hi.x - lo.x, hi.y - lo.y)
	return narrow >= 100.0 and absf(dist) <= minf(narrow * 0.5, 400.0)


## NTHICK: the slider of a flat plate: its pull's dist, labelled Thickness (cm, 0.2 = 2 mm to 40 = 40 cm)
func _thickness_tweak(id: String, sg: float) -> Dictionary:
	return {"id": id, "field": "dist", "label": "Thickness", "unit": "cm", "lo": 0.2, "hi": 40.0, "step": 0.2, "scale": 10.0, "words": ["Thin plate", "Thick block"], "sgn": sg}


## FMUG3: a part that already has a pull (an extrude step) in its features
func _has_pull(rec: Dictionary) -> bool:
	for f in rec.get("features", []):
		if String(f.get("t", "")) == "extrude":
			return true
	return false

## FWRENCH2: a JAW SLOT. A floor shape (on the top plane) that lies inside one solid's width and runs past one of its ends (or the other way round)
## cuts that solid when pulled. Only when the trial cut lowers the volume, leaves one solid and no error; else the Pull joins as before
func _slot_cut(rec: Dictionary, sk: Dictionary, dist: float) -> bool:
	var res := Part.replay(rec)
	if int(res["bodies"]) != 1:
		return false
	var bb: AABB = res["aabb"]
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var pl := Part.plane("top")
	for e in sk["ents"]:
		for q in _ent_pts(e):
			var w := Part.to_world(pl, Part.v2(q))
			lo = lo.min(Vector2(w.x, w.z))
			hi = hi.max(Vector2(w.x, w.z))
	if lo.x == INF:
		return false
	var eps := 0.5 * Part.MM
	var x0 := bb.position.x - eps
	var x1 := bb.end.x + eps
	var z0 := bb.position.z - eps
	var z1 := bb.end.z + eps
	# FWRENCH3: a slot is INSIDE the solid's width, so it must keep clear of both sides (a strip that spans the floor's full depth is a WALL on the edge, not a jaw: the froom wall B)
	var in_z := lo.y > bb.position.z + eps and hi.y < bb.end.z - eps
	var in_x := lo.x > bb.position.x + eps and hi.x < bb.end.x - eps
	var past_x := (lo.x < x0 or hi.x > x1) and hi.x > x0 and lo.x < x1   # runs past an end along x, and overlaps the solid
	var past_z := (lo.y < z0 or hi.y > z1) and hi.y > z0 and lo.y < z1
	# FWRENCH4: a slot must go DEEP into the solid (a third of its length inside it). A box that mostly sticks OUT past an end and only
	# clips the edge (the glasses arm at the ring's outer edge) is a pull that goes out: it adds, it does not cut
	var reach_x := (minf(hi.x, bb.end.x) - maxf(lo.x, bb.position.x)) / maxf(hi.x - lo.x, 1e-9)
	var reach_z := (minf(hi.y, bb.end.z) - maxf(lo.y, bb.position.z)) / maxf(hi.y - lo.y, 1e-9)
	var deep_x := in_z and past_x and reach_x >= 1.0 / 3.0
	var deep_z := in_x and past_z and reach_z >= 1.0 / 3.0
	if not (deep_x or deep_z):
		return false
	var v0 := float(res["volume"])
	var trial := rec.duplicate(true)
	var f := Part.new_feature(trial, "extrude", {"sketch": sk["id"], "dist": dist, "both": false, "op": "cut"})
	trial["features"].append(f)
	var r2 := Part.replay(trial)
	var v1 := float(r2["volume"])
	return String(r2["errors"].get(f["id"], "")) == "" and int(r2["bodies"]) == 1 and v1 > 0.0 and v1 < v0 - 1e-12


## an upright sketch whose lowest point is at or above the body's top (a roof on the box)
func _sits_on_body(rec: Dictionary, sk: Dictionary) -> bool:
	var bb: AABB = Part.replay(rec).get("aabb", AABB())
	if bb.size == Vector3.ZERO:
		return false
	var low := INF
	for e in sk["ents"]:
		for q in _ent_pts(e):
			low = minf(low, float(q[1]))
	return low >= bb.end.y / Part.MM - 1.0


## ETABLE: a face plane on the top of a solid (the floor-facing normal is up: out +1 on the Part top plane)
func _top_face(pf: Dictionary) -> bool:
	return String(pf.get("from", "")) == "top" and int(pf.get("out", 0)) > 0


## FBOX2: the newest solid step is a LID: a pull with op "new" on a hollow box (the lid is its own piece)
func _lid_last(rec: Dictionary) -> bool:
	if not _has_shell(rec):
		return false
	var last := {}
	for f in rec.get("features", []):
		if String(f.get("t", "")) == "extrude":
			last = f
	return not last.is_empty() and String(last.get("op", "")) == "new"


## FBOX: the record has a shell (Hollow inside) step: a hollow body whose top is open
func _has_shell(rec: Dictionary) -> bool:
	for f in rec.get("features", []):
		if String(f.get("t", "")) == "shell":
			return true
	return false


## a face sketch hangs past the body when one of its points lies outside the body's box (by more than 0.5 mm) along the face's own axes
func _overhangs(rec: Dictionary, sk: Dictionary) -> bool:
	var bb: AABB = Part.replay(rec).get("aabb", AABB())
	if bb.size == Vector3.ZERO:
		return false
	var pl := Part.resolve_plane(rec, String(sk.get("plane", "front")))
	var g := bb.grow(0.5 * Part.MM)
	var n: Vector3 = pl["n"]
	for e in sk["ents"]:
		for q in _ent_pts(e):
			var w := Part.to_world(pl, Vector2(float(q[0]), float(q[1])))
			w -= n * n.dot(w - bb.get_center())   # onto the body's middle along the normal: only the in-face position counts
			if not g.has_point(w):
				return true
	return false


func _spin(rec: Dictionary) -> String:
	var sid := Part.profile_sketch(rec)
	if sid == "" or Part.sketch_used(rec, sid):
		return "That shape is solid already. Draw a new one, then Spin it round"
	var axis := "x"
	var sk := Part.feature(rec, sid)
	var before := sk.duplicate(true)   # a refused spin gives the drawing back as it was (it is not used up)
	var pf := Part.feature(rec, String(sk.get("plane", "")))
	var on_piece := false   # ELAMP: a profile drawn ABOVE a solid already in the part (a shade on a lamp stick) keeps the height it was drawn
	if String(sk.get("plane", "")) == "top":
		_stand_up(sk)   # a floor drawing is flat: spun round the up axis it has no volume, so it stands up first (a lathe profile)
		axis = "y"
	elif String(pf.get("t", "")) == "plane" and bool(pf.get("through", false)):
		# an UPRIGHT drawing (side-on, through the middle): the bowl turns round the UP line through the middle (the sketch's
		# vertical axis, x = 0), so the profile must lie on one side of that line. Its lowest point goes down to the floor,
		# unless it starts on a piece already standing (then it stays where it was drawn, joined to that piece).
		on_piece = _starts_on_piece(rec, sk)
		if not on_piece:
			_lift_to_floor(sk)
		axis = "y"
	if axis == "y" and _past_axis(sk) < -3.0 and _past_axis(sk) >= -CLIP_MM:
		_clip_axis(sk)   # FBOWL2: a spline's overshoot past the middle line (a bowl's foot corner) is clipped onto it, not refused
	if axis == "y" and _past_axis(sk) < -3.0 and _on_left(sk):
		_flip_x(sk)   # a drawing wholly on the -X side is the same solid as its mirror image on the +X side (a lathe is symmetric): flip it, then spin
	if axis == "y" and _past_axis(sk) < -3.0:
		sk.clear()
		sk.merge(before, true)
		return "A shape that crosses the middle line cannot be spun: draw it on one side"
	var f := Part.new_feature(rec, "revolve", {"sketch": sid, "axis": axis, "deg": 360.0, "op": "join", "onside": axis == "y"})
	rec["features"].append(f)
	if _last_error(rec, String(f["id"])) != "":
		rec["features"].pop_back()
		sk.clear()
		sk.merge(before, true)
		return "A shape that crosses the middle line cannot be spun: draw it on one side"
	if axis == "y" and not on_piece:
		# a spline dips a little below its points: the solid's real lowest point goes onto the floor (a bowl's foot is on the floor, not in it)
		var low := float(Part.replay(rec)["aabb"].position.y) / Part.MM
		if absf(low) > 0.001:
			_shift_y(sk, low)
	tweak = {"id": f["id"], "field": "deg", "label": "How far round", "unit": "deg", "lo": 10.0, "hi": 360.0, "step": 5.0, "scale": 1.0, "words": ["A bit", "All the way"]}
	_say("Spun all the way round: use the slider for less, or press Cut a hole or Mirror that next")
	return ""



## ELAMP: true when the upright drawing starts ABOVE the floor and on a solid already in the part: its lowest point (mm) lies within
## the solid's height range (a shade whose first point is on a stick top). A drawing on the floor, or in the air over nothing, is not on a piece
func _starts_on_piece(rec: Dictionary, sk: Dictionary) -> bool:
	var res := Part.replay(rec)
	if int(res["bodies"]) == 0:
		return false
	var bb: AABB = res["aabb"]
	var bot := bb.position.y / Part.MM
	var top := bb.end.y / Part.MM
	var low := INF
	for e in sk["ents"]:
		for q in _ent_pts(e):
			low = minf(low, float(q[1]))
	if low == INF:
		return false
	return low > 0.5 and low >= bot - 0.5 and low <= top + 0.5


## SPIN A FLOOR DRAWING: the sketch moves from the floor (top plane) to the front plane, its far edge up, and slides so its nearest point
## sits on the floor: spun round the up axis it is a lathe piece (a ring, a vase) standing on the floor beside the middle line
func _stand_up(sk: Dictionary) -> void:
	_lift_to_floor(sk)
	sk["plane"] = "front"


## the drawing slides up or down (in its own plane) so its lowest point sits on the floor (y = 0)
func _lift_to_floor(sk: Dictionary) -> void:
	var lo := INF
	for e in sk["ents"]:
		for q in _ent_pts(e):
			lo = minf(lo, float(q[1]) - (float(e["r"]) if e.has("r") and String(e["k"]) == "circle" else 0.0))
	if lo == INF:
		lo = 0.0
	_shift_y(sk, lo)


## how far the drawing reaches past the middle line (x < 0, mm; 0 when it stays on the +X side). A spline counts where its curve goes, not only its points
func _past_axis(sk: Dictionary) -> float:
	var lo := 0.0
	for e in sk["ents"]:
		if String(e["k"]) == "bspline":
			for q in Part.spline_curve(e.get("pts", []), bool(e.get("closed", false)), 16):
				lo = minf(lo, q.x)
		elif String(e["k"]) == "circle":
			lo = minf(lo, float(e["c"][0]) - float(e["r"]))
		else:
			for q in _ent_pts(e):
				lo = minf(lo, float(q[0]))
	return lo


## FBOWL2: a curve drawn through corner points (a salad bowl's foot) overshoots the middle line by a few mm between its points: the curve
## is sampled, the part past the middle line is set to x = 0 (a flat piece on the axis), and the sketch keeps the sampled points
func _clip_axis(sk: Dictionary) -> void:
	for e in sk["ents"]:
		if String(e["k"]) != "bspline":
			continue
		var closed := bool(e.get("closed", false))
		var dense := Part.spline_curve(e.get("pts", []), closed, 16)
		var out := []
		for q in dense:
			out.append([maxf(q.x, 0.0), q.y])
		if closed and out.size() > 1:
			out.pop_back()   # the sample ends on the first point again: the closed line keeps one of them
		e["pts"] = out


## true when no point of the drawing is on the +X side of the middle line (x <= 0.5 mm everywhere)
func _on_left(sk: Dictionary) -> bool:
	for e in sk["ents"]:
		for q in _ent_pts(e):
			if float(q[0]) > 0.5:
				return false
	return true


## every point of the drawing reflects across the middle line (x = -x, mm); a circle's centre moves with it, its radius does not
func _flip_x(sk: Dictionary) -> void:
	for e in sk["ents"]:
		for q in _ent_pts(e):
			q[0] = -float(q[0])


## every point of the drawing moves down by lo (mm) in its own plane
func _shift_y(sk: Dictionary, lo: float) -> void:
	for e in sk["ents"]:
		for q in _ent_pts(e):
			q[1] = snappedf(float(q[1]) - lo, 0.0001)


## the [x, y] points of a sketch entity (the arrays themselves: writing them moves the entity)
func _ent_pts(e: Dictionary) -> Array:
	var out := []
	for k in ["a", "b", "m", "c"]:
		if e.has(k) and e[k] is Array:
			out.append(e[k])
	if e.has("pts"):
		out.append_array(e["pts"])
	return out
