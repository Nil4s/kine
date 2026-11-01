extends "res://scripts/easy_part_repeat.gd"
## EASY PART PULL: Pull it up and Spin it round, and the Cut a hole chips that hollow a solid out (Hollow inside, the open side, the
## lid and its Snap-fit lip). What a pull becomes (joined to the body it sits on, its own body, a cut, a lid on the rim) is decided in ONE
## table, PULL_RULES, read by _pull_rule: a new pull case is one row there.

## the hole chips show after a Cut a hole press, while its step is the newest hole and nothing is armed
func _hole_on() -> bool:
	if _screw_group(_rec()) >= 0 and armed == "":   # P082: a screw hole the part was saved with: its chips show after Change the part
		return true
	return not hole_base.is_empty() and armed == "" and not Part.feature(_rec(), hole_id).is_empty()


func _hole_sync() -> void:
	_fill_sync()   # s051 (first: it repairs hole_mode after an Undo or Redo)
	if _screw_group(_rec()) >= 0 and hole_base.is_empty():   # P082: the chip on is the screw the hole was cut for
		hole_mode = "screw%d" % int(_rec()["features"][_screw_group(_rec())]["screw_hole"])
	for k in hole_btns:
		(hole_btns[k] as Button).set_pressed_no_signal(k == hole_mode)
	if snap_btn != null:
		snap_btn.set_pressed_no_signal(_rec_has_lip())   # the record says it (an Undo takes the chip off with the lip)
		snap_btn.visible = hole_mode == "lid"   # the chip only exists for a lid
	if wall_btn != null:
		wall_btn.set_pressed_no_signal(wall_pick)
		wall_btn.visible = hole_mode == "hollow" and _hole_on()   # Thicker wall only exists for a hollow
	if lattice_btn != null:
		lattice_btn.visible = _lattice_shown()   # p208latticeinf: Lattice inside shows after a hollow, not after a lattice
	if stack_btn != null:
		stack_btn.visible = _stack_shown()   # s209: Make it stackable shows after a hollow, not after the lip
		if _rec_has_stack() and wall_btn != null:
			wall_btn.visible = false
	_hpat_sync()   # s029
	_lighter_sync()   # p195generative


	_smartfit_sync()   # s202


## a Through / Hollow inside chip: the hole step is REPLACED (one undo step): the record from before the hole press, then the chosen hole.
## A hollow that fails (a body too thin for the wall) says so and changes nothing
func _hole_mode(mode: String, lip := false, rebuild := false, fit_set := -1.0) -> void:   # lip: the lid with its Snap-fit lip; rebuild: the same chip again (the Snap-fit lip press)
	if not _hole_on() or not Part.available() or (mode == hole_mode and not rebuild):
		_hole_sync()
		return
	_flush_if_dirty()
	armed = ""
	wall_pick = false
	var snap := _rec().duplicate(true)
	_begin("Change fit" if fit_set >= 0.0 else ("Hollow with a lid" if mode == "lid" else ("Hollow inside" if mode == "hollow" else "Cut a hole")))
	var rec: Dictionary = (hole_base if not hole_base.is_empty() else _without_screw_hole(_rec())).duplicate(true)   # P082: after Change the part, the chips rebuild from the record without its screw hole
	rec["fit_mm"] = fit_set if fit_set >= 0.0 else _fit_of(snap)   # s202: the part's fit survives the rebuild
	m.S.part = rec
	var why := ""
	if mode.begins_with("screw"):   # p030countersun: a screw chip (screw3 .. screw6) cuts the hole for that screw
		why = _screw_hole(rec, int(mode.trim_prefix("screw")))
	elif mode == "magnet":   # p074magnetsapo: the round pocket for a magnet
		why = _magnet_pocket(rec)
	elif mode == "lighter":   # p195generative: round holes in the regions away from the load path (the end of this file)
		why = _lighter(rec)
	elif mode == "fingers":   # p118fingerjoin: a comb of notches along the top edge (see _finger_joints, at the end of this file)
		why = _finger_joints(rec)
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
	var clear := float(PRINTER_CLEAR.get(printer, SCREW_CLEAR)[d])   # p203screwholea: resin tight, FDM loose, any = medium
	var before := float(res["volume"])
	var n0: int = rec["features"].size()
	var seq0 := int(rec.get("seq", 0))
	var top := Part.new_feature(rec, "plane", {"from": "front", "mm": bb.end.z / Part.MM})   # the top face: the plane the head's counterbore starts on
	top["screw_hole"] = d   # P082: the hole's five steps start here and keep the screw's size (the record remembers it after Change the part)
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
	_say("M%d screw: a %s mm hole%s, its %s mm head sunk %s mm deep. Mirror that or Repeat it next" % [d, _mm_words(clear), _printer_tag(), _mm_words(float(head[0])), _mm_words(float(head[1]))])
	return ""


## p074magnetsapo (Kine's own): the magnet pocket. A round pocket on the top face (+Z) of the newest solid, in the middle, for a real round
## magnet: 6 mm across and 3 mm thick (MAGNET_D, MAGNET_T). The pocket is 0.1 mm wider than the magnet on each side and 0.2 mm deeper,
## so the magnet sits in it and does not stick. The Magnet size slider sets the pocket's width. A pocket that misses the solid changes nothing
const MAGNET_D := 6.0      # mm across: a real 6 x 3 mm neodymium disc magnet
const MAGNET_T := 3.0      # mm thick
const MAGNET_FIT := 0.2    # mm of clearance in all: 0.1 mm each side, and 0.2 mm deeper than the magnet


func _magnet_pocket(rec: Dictionary) -> String:
	var res := Part.replay(rec)
	if int(res["bodies"]) == 0:
		return "Nothing solid to put a magnet in yet. Press Pull it up first"
	var bb: AABB = res["aabb"]
	var c := bb.get_center() / Part.MM
	var before := float(res["volume"])
	var n0: int = rec["features"].size()
	var seq0 := int(rec.get("seq", 0))
	var top := Part.new_feature(rec, "plane", {"from": "front", "mm": bb.end.z / Part.MM})   # the top face, as the screw's counterbore
	rec["features"].append(top)
	var pk := Part.new_feature(rec, "sketch", {"plane": String(top["id"]), "ents": [{"k": "circle", "c": Part.arr2(Vector2(c.x, c.y)), "r": (MAGNET_D + MAGNET_FIT) / 2.0}], "dims": []})
	rec["features"].append(pk)
	rec["features"].append(Part.new_feature(rec, "extrude", {"sketch": pk["id"], "dist": -(MAGNET_T + MAGNET_FIT), "both": false, "op": "cut"}))   # a negative dist runs down into the solid
	var after := float(pu.replay_full(rec)["volume"])
	if not (after < before - 1e-12 and after > 1e-9):
		rec["features"].resize(n0)
		rec["seq"] = seq0
		return "The magnet would miss the solid: nothing was cut. Pull it up bigger, then press Cut a hole again"
	tweak = {"id": pk["id"], "ent": 0, "field": "r", "label": "Magnet size", "unit": "cm", "lo": 0.62, "hi": 1.22, "step": 0.2, "scale": 5.0, "words": ["Smaller", "Bigger"]}   # the slider is the pocket's width (cm): radius mm = width cm * 5
	_say("Magnet 6 x 3 mm: a 6.2 mm pocket, 3.2 mm deep. Use the slider for its size, then Mirror that or Repeat it next")
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
	var ins_o := HOLLOW_MM + _fit_of(rec)   # the lip's outer face: the part's fit (s202: Slides = 0.2 mm) inside the wall
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
		var ro := ins_o - LIP_RIDGE_MM   # the ridge's outside: 0.5 mm proud of the lip's outer face
		var ri := ins_o                  # the ridge's inside: the lip's own outer face
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
	# P024: a Twist slider under the Taper one, for a one-way pull of one closed shape (the twisted post); a box or any closed shape turns, a round one looks the same
	twist_tw = {"id": f["id"], "label": "Twist", "unit": "deg", "lo": 0.0, "hi": 120.0, "step": 5.0, "words": ["Straight", "Twisted more"]} if bool(rule["taper"]) and not through and Part.loops_of(sk["ents"]).size() == 1 else {}
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
	tweak = _spin_tweak(String(f["id"]))
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


## P082 LIBRARY PARTS STAY PARAMETRIC (Kine's own): a screw hole is five steps (its plane, the counterbore, the clearance hole); the first
## keeps the screw's size ("screw_hole"). -1 unless those five are the newest steps of the record
func _screw_group(rec: Dictionary) -> int:
	var fs: Array = rec.get("features", [])
	var i := fs.size() - 5
	if i < 0 or not (fs[i] as Dictionary).has("screw_hole"):
		return -1
	return i


## P082: the record without its newest screw hole (the same record, its ids and seq kept): the base a new chip rebuilds the hole on
func _without_screw_hole(rec: Dictionary) -> Dictionary:
	var r := rec.duplicate(true)
	var g := _screw_group(rec)
	if g >= 0:
		(r["features"] as Array).resize(g)
	return r


## P028 ANGLE: the Spin it round slider is an Angle in degrees, 30 (a slim part of a bowl) to 360 (all the way round); its record field is deg
func _spin_tweak(id: String) -> Dictionary:
	return {"id": id, "field": "deg", "label": "Angle", "unit": "deg", "lo": 30.0, "hi": 360.0, "step": 5.0, "scale": 1.0, "words": ["A bit", "All the way"]}


## p118fingerjoin: FINGER JOINTS, a comb of notches along the TOP edge of a pulled-up box, cut through its whole depth (a laser-cut box
## joins its walls this way). Each finger and each notch is FINGER_MM wide (a fortieth of the width for a wide box), the notch is a third of
## the height deep, and the comb is centred so a tab is left at both ends. Box-shaped only. "" or why not
const FINGER_MM := 3.0   # p118fingerjoin: the finger width for a box up to 120 mm wide (a laser cuts sheet this thick)
func _finger_joints(rec: Dictionary) -> String:
	tweak = {}
	var res := Part.replay(rec)
	var nb := int(res["bodies"])
	if nb == 0:
		return "Nothing solid to cut notches in yet. Press Pull it up first"
	if nb > 1:
		return "Finger joints need one box, not two pieces. Press Undo, then Pull it up as one box"
	var bb: AABB = res["aabb"]
	var x0 := bb.position.x / Part.MM
	var wide := bb.size.x / Part.MM
	var top := bb.end.y / Part.MM
	var hgt := bb.size.y / Part.MM
	var fw := maxf(FINGER_MM, snappedf(wide / 40.0, 0.5))
	var n := int(floor(wide / (2.0 * fw)))
	if n < 2:
		return "That box is too narrow for finger joints (two fingers across): Pull it up wider, then press Cut a hole again"
	if hgt < 3.0:
		return "That box is too short for finger joints: Pull it up taller, then press Cut a hole again"
	var depth := snappedf(hgt / 3.0, 0.5)
	var xs := x0 + (wide - (2.0 * n - 1.0) * fw) * 0.5   # the first notch's left edge: the comb is centred
	var ents: Array = []
	for i in n:
		var xa := xs + 2.0 * i * fw
		ents.append({"k": "rect", "a": Part.arr2(Vector2(xa, top - depth)), "b": Part.arr2(Vector2(xa + fw, top + 1.0))})
	var before := float(res["volume"])
	var s := Part.new_feature(rec, "sketch", {"plane": "front", "ents": ents, "dims": []})
	rec["features"].append(s)
	var f := Part.new_feature(rec, "extrude", {"sketch": s["id"], "dist": snappedf(2.0 * (maxf(absf(bb.position.z), absf(bb.end.z)) / Part.MM + 10.0), 1.0), "both": true, "op": "cut"})
	rec["features"].append(f)
	var after := float(pu.replay_full(rec)["volume"])
	if after >= before - 1e-12 or after <= 1e-9:
		return "The notches would miss the box: nothing was cut. Press Cut a hole again"
	_say("Finger joints: %d notches along the top edge. Use Ctrl+Z to take them out" % n)
	return ""


## p208latticeinf (Friday plan 208; Kine's own idea: light and strong): Lattice inside shows under Cut a hole once the newest step is the
## hollow (its shell). The button is hidden after the lattice, so a second press cannot stack one on top
func _lattice_shown() -> bool:
	var fs: Array = _rec().get("features", [])
	return hole_mode == "hollow" and _hole_on() and not fs.is_empty() and String(fs[-1].get("t", "")) == "shell"


## p208latticeinf: Lattice inside: ONE step ("lattice", its Gap slider: how far apart the bars are) after the hollow box. The bars fill the
## hollow from wall to wall. Only a box-shaped hollow takes one: a shape that is not a box says so and changes nothing. One press = one undo step
func _lattice_press() -> void:
	var rec0 := _rec()
	var fs: Array = rec0.get("features", [])
	if not _lattice_shown() or not Part.available() or fs.size() < 2:
		_say("Hollow it first: press Hollow inside, then Lattice inside")
		_hole_sync()
		return
	var pre := Part.replay(rec0, fs.size() - 2)   # the solid before the hollow: a box is solid right up to its bounding box
	var pb: AABB = pre["aabb"]
	var box_vol := pb.size.x * pb.size.y * pb.size.z
	if int(pre["bodies"]) == 0 or box_vol <= 0.0 or float(pre["volume"]) < box_vol * 0.99:
		_say("The lattice fills a box-shaped hollow only: make the hollow a box first (Pull it up from a square)")
		return
	_flush_if_dirty()
	armed = ""
	wall_pick = false
	var snap := rec0.duplicate(true)
	_begin("Lattice inside")
	var rec: Dictionary = snap.duplicate(true)
	var f := Part.new_feature(rec, "lattice", {"body": int(fs[-1].get("body", 0)), "gap": 10.0, "bar": 2.0})
	rec["features"].append(f)
	m.S.part = rec
	var why := _last_error(rec, String(f["id"]))
	if why != "":
		m.S.part = snap
		m._drop_undo()
		_edit_n = -1
		_say(why)
		return
	_end()
	tweak = {"id": f["id"], "field": "gap", "label": "Gap", "unit": "mm", "lo": 6.0, "hi": 20.0, "step": 1.0, "scale": 1.0, "words": ["Denser", "Airier"]}
	pu.upto = -1
	pu.sync()
	_rows_sig = ""
	_rows_sync()
	_values_sync()
	_say("Filled with a lattice: move the Gap slider for how far apart the bars are")


## p203screwholea (Kine's own): THE PRINTER SETS THE HOLE. Resin prints small, so a screw hole is TIGHT (ISO 273 fine: M4 4.3 mm);
## FDM prints loose, so it is LOOSE (ISO 273 coarse: M4 4.8 mm). Any printer = the medium hole (SCREW_CLEAR). One chip on the Cut a hole
## panel cycles any -> resin -> FDM -> any. Pressing it while a screw hole is the newest step cuts that hole again (one undo step); the
## counterbore for the head does not change. The choice is for this session (no record field, no undo step by itself)
const PRINTER_CLEAR := {"resin": {3: 3.2, 4: 4.3, 5: 5.3, 6: 6.4}, "fdm": {3: 3.6, 4: 4.8, 5: 5.8, 6: 7.0}}
var printer := ""   # "" any printer, "resin", "fdm"
var printer_btn: Button = null


func _printer_tag() -> String:
	return " (resin: tight)" if printer == "resin" else (" (FDM: loose)" if printer == "fdm" else "")


func _printer_chip(h: Control) -> void:
	printer_btn = _big_btn("easypart_hole_printer", "", "Your printer: resin prints small, so its screw holes are tight; FDM prints loose, so they are loose. Any = the usual medium hole. Press to change it; a screw hole on the screen is cut again", _printer_press)
	printer_btn.custom_minimum_size = Vector2(150, 44)
	h.add_child(printer_btn)
	_printer_sync()


func _printer_sync() -> void:
	if printer_btn != null:
		printer_btn.text = "Printer: " + {"": "any", "resin": "resin", "fdm": "FDM"}[printer]


func _printer_press() -> void:
	printer = {"": "resin", "resin": "fdm", "fdm": ""}[printer]
	_printer_sync()
	if hole_mode.begins_with("screw") and _hole_on():
		_hole_mode(hole_mode, false, true)   # the screw hole on the screen is cut again for this printer (one undo step)
	else:
		_say("Printer: %s. The next screw hole uses it" % ("any" if printer == "" else ("resin (tight)" if printer == "resin" else "FDM (loose)")))


## s209 MAKE IT STACKABLE (Friday plan 209): on a hollow box (open top), a lip on the bottom that fits inside the rim of an identical box,
## STACK_CLEAR mm of play on every side: the lip's outside = the rim's inside - 2 x 0.3 mm. A ring STACK_RING mm thick, STACK_LIP mm tall
## (less on a shallow box), hanging under the floor. Two steps (sketch + pull) tagged "stack"; one press = one undo step.
## The stacked pair: the second box is raised by the box's height (its rim to rim), its lip stands in the first box's rim.
const STACK_CLEAR := 0.3
const STACK_LIP := 4.0
const STACK_RING := 1.5
var stack_btn: Button = null


func _rec_has_stack() -> bool:
	for f in _rec().get("features", []):
		if bool((f as Dictionary).get("stack", false)):
			return true
	return false


func _stack_shell() -> Dictionary:
	for f in _rec().get("features", []):
		if String((f as Dictionary).get("t", "")) == "shell" and String(f.get("open", "")) == "+y" and not bool(f.get("off", false)):
			return f
	return {}


func _stack_shown() -> bool:
	return hole_mode == "hollow" and _hole_on() and not _stack_shell().is_empty() and not _rec_has_stack()


## the rim's inside (mm): [x0, z0, x1, z1] read from the built mesh (the top ring's vertices that are not on the outside box), or []
func _stack_inner(res: Dictionary) -> Array:
	var mesh: ArrayMesh = res.get("mesh")
	if mesh == null:
		return []
	var bb: AABB = res["aabb"]
	var lo := bb.position / Part.MM
	var hi := bb.end / Part.MM
	var x0 := INF
	var z0 := INF
	var x1 := -INF
	var z1 := -INF
	for s in mesh.get_surface_count():
		for v in (mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			var p := v / Part.MM
			if absf(p.y - hi.y) > 0.05 or p.x < lo.x + 0.05 or p.x > hi.x - 0.05 or p.z < lo.z + 0.05 or p.z > hi.z - 0.05:
				continue
			x0 = minf(x0, p.x)
			x1 = maxf(x1, p.x)
			z0 = minf(z0, p.z)
			z1 = maxf(z1, p.z)
	return [] if x0 > x1 or z0 > z1 else [x0, z0, x1, z1]


func _stack_press() -> void:
	var sh := _stack_shell()
	if sh.is_empty() or hole_mode != "hollow" or not _hole_on() or not Part.available():
		_hole_sync()
		_say("Make it stackable needs a hollow box first: press Cut a hole, then Hollow inside, then Make it stackable")
		return
	if _rec_has_stack():
		_say("It is stackable already. Undo to take the lip off")
		return
	var rec0 := _rec()
	var res := Part.replay(rec0)
	var why := ""
	var inner: Array = []
	if int(res["bodies"]) != 1:
		why = "Make it stackable works on one hollow box: stick the pieces together first"
	else:
		inner = _stack_inner(res)
		if inner.is_empty():
			why = "Make it stackable needs a box that is open at the top"
	var bb: AABB = res["aabb"]
	var bot := bb.position.y / Part.MM
	var top := bb.end.y / Part.MM
	var lip := minf(STACK_LIP, top - bot - float(sh.get("thick", 3.0)) - 1.0)
	if why == "" and (lip < 2.0 or float(inner[2]) - float(inner[0]) - 2.0 * STACK_CLEAR < 2.0 * STACK_RING + 2.0 or float(inner[3]) - float(inner[1]) - 2.0 * STACK_CLEAR < 2.0 * STACK_RING + 2.0):
		why = "That box is too small or too shallow for a stacking lip: make it taller (at least 7 mm inside) and wider"
	if why != "":
		_say(why)
		return
	_flush_if_dirty()
	armed = ""
	wall_pick = false
	var snap := rec0.duplicate(true)
	_begin("Make it stackable")
	var rec: Dictionary = snap.duplicate(true)
	var o := STACK_CLEAR
	var r := STACK_CLEAR + STACK_RING
	var pf := Part.new_feature(rec, "plane", {"from": "top", "mm": bot - lip})
	rec["features"].append(pf)
	var s1 := Part.new_feature(rec, "sketch", {"plane": String(pf["id"]), "ents": [_rect_ent(float(inner[0]) + o, float(inner[1]) + o, float(inner[2]) - o, float(inner[3]) - o)], "dims": []})
	rec["features"].append(s1)
	var f1 := Part.new_feature(rec, "extrude", {"sketch": s1["id"], "dist": lip + 0.5, "both": false, "op": "join", "into": 0, "stack": true})
	rec["features"].append(f1)
	var s2 := Part.new_feature(rec, "sketch", {"plane": String(pf["id"]), "ents": [_rect_ent(float(inner[0]) + r, float(inner[1]) + r, float(inner[2]) - r, float(inner[3]) - r)], "dims": []})
	rec["features"].append(s2)
	var f2 := Part.new_feature(rec, "extrude", {"sketch": s2["id"], "dist": lip, "both": false, "op": "cut", "stack": true})
	rec["features"].append(f2)
	m.S.part = rec
	var err := _last_error(rec, String(f1["id"]))
	if err == "":
		err = _last_error(rec, String(f2["id"]))
	if err == "" and int(Part.replay(rec)["bodies"]) != 1:
		err = "the lip split the box in two"
	if err != "":
		m.S.part = snap
		m._drop_undo()
		_edit_n = -1
		_say("The lip did not build: " + err)
		return
	_end()
	tweak = {}   # the Wall slider would make the box fit the lip no more
	pu.upto = -1
	pu.sync()
	_rows_sig = ""
	_rows_sync()
	_values_sync()
	_hole_sync()
	_say("Stackable: a lip %s mm tall under the floor fits inside the rim of another one, with %s mm of play" % [_plain_num(lip), _plain_num(STACK_CLEAR)])


## s029 HOLES IN A PATTERN (Friday plan 29): after Cut a hole, Row / Around / Grid copy the round hole into one pattern. It is still ONE build step:
## the hole's own sketch gets more circles (the first circle keeps the Hole size slider; the others follow it) and the sketch carries the
## pattern ("hpat": kind, count, gap, rows, columns, radius, the centres), so a slider only rewrites the circles. Each press and each slider
## change is one undo step. The holes are real cuts: the same pull-through cut as the single hole
const HPAT_WORDS := {"row": "Holes in a row", "around": "Holes around", "grid": "Holes in a grid"}
var hpat_btns := {}          # "row" / "around" / "grid" / "pick": the chips
var hpat_rows := []          # the slider rows (How many, Spacing, Radius, Rows, Columns)
var hpat_box: HFlowContainer  # the slider rows' column (hidden while no pattern is on)
var hpat_pick := false       # true while Pick centre waits for the click on the part


func _hpat_chips(h: Control) -> void:
	for kd in [["row", "Holes: Row", "Copy the hole into a straight row: set how many and the spacing in mm"], ["around", "Holes: Around", "Copy the hole round a circle: set how many and the radius in mm. The circle is round the middle of the part, or a point you pick"], ["grid", "Holes: Grid", "Copy the hole into a grid: set the rows, the columns and the spacing in mm"]]:
		var b := _big_btn("easypart_hole_" + String(kd[0]), String(kd[1]), String(kd[2]), _hpat_mode.bind(String(kd[0])))
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(130, 44)
		h.add_child(b)
		hpat_btns[kd[0]] = b
	var pb := _big_btn("easypart_hole_pickc", "Pick centre", "Then click the part: the holes go round that point instead of the middle", _hpat_pick_press)
	pb.toggle_mode = true
	pb.custom_minimum_size = Vector2(120, 44)
	pb.visible = false
	h.add_child(pb)
	hpat_btns["pick"] = pb
	hpat_box = HFlowContainer.new()
	hpat_box.name = "easypart_hole_pattern"
	hpat_box.custom_minimum_size = Vector2(700, 0)
	hpat_box.add_theme_constant_override("h_separation", 12)
	hpat_box.add_theme_constant_override("v_separation", 0)
	hpat_box.visible = false
	hpat_rows.append(_make_row("How many", 2.0, 24.0, 1.0, ["Fewer", "More"], "hpat", "hp_count", "holes", hpat_box))
	hpat_rows.append(_make_row("Spacing", 3.0, 200.0, 0.5, ["Closer", "Further apart"], "hpat", "hp_gap", "mm", hpat_box))
	hpat_rows.append(_make_row("Radius", 3.0, 200.0, 0.5, ["Smaller", "Bigger"], "hpat", "hp_rad", "mm", hpat_box))
	hpat_rows.append(_make_row("Rows", 2.0, 10.0, 1.0, ["Fewer", "More"], "hpat", "hp_rows", "holes", hpat_box))
	hpat_rows.append(_make_row("Columns", 2.0, 10.0, 1.0, ["Fewer", "More"], "hpat", "hp_cols", "holes", hpat_box))
	for r in hpat_rows:   # three sliders to a line, no words under them: the panel stays low
		(r["words"] as Control).visible = false
		(r["box"] as Control).custom_minimum_size = Vector2(225, 0)


## the hole's round sketch while the chips are up on a single round hole (a screw, hollow or lid is not copied); {} if not
func _hpat_sketch() -> Dictionary:
	if hole_mode in ["hollow", "lid", "fingers", "fill"] or hole_mode.begins_with("screw") or hole_id == "":
		return {}
	var sk := Part.feature(_rec(), hole_id)
	if String(sk.get("t", "")) != "sketch":
		return {}
	var ents: Array = sk.get("ents", [])
	if ents.is_empty() or String(ents[0].get("k", "")) != "circle":
		return {}
	return sk


## the centres a pattern puts its holes at (sketch mm)
static func hpat_centres(h: Dictionary) -> Array:
	var out: Array = []
	var cx := float(h.get("hx", 0.0))
	var cy := float(h.get("hy", 0.0))
	var gap := float(h.get("gap", 20.0))
	match String(h.get("kind", "")):
		"row":
			var n := int(h.get("n", 3))
			for i in n:
				out.append(Vector2(cx + (float(i) - float(n - 1) * 0.5) * gap, cy))
		"grid":
			var rs := int(h.get("rows", 2))
			var cs := int(h.get("cols", 3))
			for r in rs:
				for c in cs:
					out.append(Vector2(cx + (float(c) - float(cs - 1) * 0.5) * gap, cy + (float(r) - float(rs - 1) * 0.5) * gap))
		"around":
			var n2 := int(h.get("n", 6))
			var px := float(h.get("px", cx))
			var py := float(h.get("py", cy))
			var rad := float(h.get("rad", 20.0))
			for i in n2:
				var a := TAU * float(i) / float(n2)
				out.append(Vector2(px + rad * cos(a), py + rad * sin(a)))
	return out


## the sketch's circles from its pattern: the first circle's size is the Hole size slider's
func _hpat_write(sk: Dictionary) -> void:
	var ents: Array = sk["ents"]
	var r := float(ents[0].get("r", 3.0))
	var out: Array = []
	for c in hpat_centres(sk["hpat"]):
		out.append({"k": "circle", "c": Part.arr2(c), "r": r})
	sk["ents"] = out


## a Hole size slider move (easy_part.gd _apply_tweak): the copies follow the first circle
func _hpat_follow(sk: Dictionary) -> void:
	if sk.has("hpat") and not (sk["ents"] as Array).is_empty():
		_hpat_write(sk)


func _hpat_span(rec: Dictionary, sk: Dictionary) -> Vector2:
	var bb: AABB = Part.replay(rec)["aabb"]
	var s := bb.size / Part.MM
	return Vector2(s.x, s.y) if String(sk.get("plane", "front")) == "front" else Vector2(s.x, s.z)


## the middle of the part on the hole's sketch plane (mm)
func _hpat_middle(rec: Dictionary, sk: Dictionary) -> Vector2:
	var bb: AABB = Part.replay(rec)["aabb"]
	var c := bb.get_center() / Part.MM
	return Vector2(c.x, c.y) if String(sk.get("plane", "front")) == "front" else Vector2(c.x, -c.z)


func _hpat_mode(kind: String) -> void:
	hpat_pick = false
	if not _hole_on() or not Part.available():
		_hpat_sync()
		_say("Press Cut a hole first, then pick Row, Around or Grid")
		return
	var sk0 := _hpat_sketch()
	if sk0.is_empty():
		_hpat_sync()
		_say("Row, Around and Grid copy the round Through hole: press Through first")
		return
	_flush_if_dirty()
	armed = ""
	wall_pick = false
	var snap := _rec().duplicate(true)
	_begin(String(HPAT_WORDS[kind]))
	var rec := _rec()
	var sk := Part.feature(rec, hole_id)
	var why := ""
	var floor_v := float(Part.replay(hole_base)["volume"]) if not hole_base.is_empty() else INF
	if sk.has("hpat") and String(sk["hpat"]["kind"]) == kind:   # the same chip again: the pattern goes, the one hole stays
		sk["ents"] = [(sk["ents"] as Array)[0]]
		sk["ents"][0]["c"] = Part.arr2(Vector2(float(sk["hpat"]["hx"]), float(sk["hpat"]["hy"])))
		sk.erase("hpat")
	else:
		var h: Dictionary = sk["hpat"] if sk.has("hpat") else {}
		if h.is_empty():
			var c0 := Part.v2(sk["ents"][0]["c"])
			var mid := _hpat_middle(rec, sk)
			var span := _hpat_span(rec, sk)
			var d := 2.0 * float(sk["ents"][0].get("r", 3.0))
			var gap := maxf(snappedf(d * 2.5, 1.0), 8.0)
			h = {"hx": c0.x, "hy": c0.y, "px": mid.x, "py": mid.y, "n": 3, "gap": gap, "rows": 2, "cols": 3, "rad": clampf(snappedf(minf(span.x, span.y) * 0.3, 1.0), 3.0, 200.0)}
			if 2.0 * gap > 0.9 * span.x:
				h["gap"] = maxf(snappedf(0.9 * span.x / 2.0, 1.0), 3.0)
		h["kind"] = kind
		if kind == "around":
			h["n"] = maxi(int(h["n"]), 3)
		sk["hpat"] = h
		_hpat_write(sk)
	var res := pu.replay_full(rec)
	var after := float(res["volume"])
	if not (res["errors"].is_empty() and after > 1e-9 and after < floor_v - 1e-12):
		why = "That pattern does not cut the part: nothing was changed"
	if why != "":
		m.S.part = snap
		m._drop_undo()
		_edit_n = -1
		_say(why)
	else:
		_end()
		if sk.has("hpat"):
			_say("%s: %d holes. The sliders set how many and how far apart. Hole size sets their width" % [HPAT_WORDS[kind], hpat_centres(sk["hpat"]).size()])
		else:
			_say("One hole again")
	pu.upto = -1
	pu.sync()
	_rows_sig = ""
	_rows_sync()
	_values_sync()
	_hpat_sync()


func _hpat_pick_press() -> void:
	var sk := _hpat_sketch()
	if sk.is_empty() or not sk.has("hpat") or String(sk["hpat"]["kind"]) != "around":
		hpat_pick = false
		_hpat_sync()
		_say("Pick centre goes with Holes around: press Holes around first")
		return
	hpat_pick = not hpat_pick
	_hpat_sync()
	_say("Click the part where the circle of holes should be centred. Press Pick centre again to stop" if hpat_pick else "Pick centre is off")


## the click that picks the centre (hpat_pick is on): the point on the part under the mouse is the circle's middle (one undo step)
func _hpat_press(p: Vector2) -> void:
	hpat_pick = false
	var fc := _face_hit_at(p)
	var sk0 := _hpat_sketch()
	if fc.is_empty() or not fc.has("hit") or sk0.is_empty() or not sk0.has("hpat"):
		_hpat_sync()
		_say("Click on the part itself to pick the centre. Press Pick centre to try again")
		return
	_flush_if_dirty()
	_begin("Pick the centre")
	var sk := Part.feature(_rec(), hole_id)
	var pt := Part.to_plane(Part.resolve_plane(_rec(), String(sk.get("plane", "front"))), fc["hit"] as Vector3)
	sk["hpat"]["px"] = snappedf(pt.x, 0.1)
	sk["hpat"]["py"] = snappedf(pt.y, 0.1)
	_hpat_write(sk)
	_end()
	pu.upto = -1
	pu.sync()
	_values_sync()
	_hpat_sync()
	_say("The holes go round the point you picked")


## the sliders of the pattern box write the sketch's pattern (kind "hpat" in _set_value); the caller flushes
func _apply_hpat(row: Dictionary, v: float) -> void:
	var sk := Part.feature(_rec(), hole_id)
	if not sk.has("hpat"):
		return
	pu.upto = -1
	var h: Dictionary = sk["hpat"]
	match String(row["key"]):
		"hp_count":
			h["n"] = int(roundf(v))
		"hp_gap":
			h["gap"] = v
		"hp_rad":
			h["rad"] = v
		"hp_rows":
			h["rows"] = int(roundf(v))
		"hp_cols":
			h["cols"] = int(roundf(v))
	_hpat_write(sk)


## the chips and sliders follow the hole's pattern
func _hpat_sync() -> void:
	if hpat_box == null:
		return
	var sk := _hpat_sketch() if _hole_on() else {}
	var kind := "" if sk.is_empty() or not sk.has("hpat") else String(sk["hpat"]["kind"])
	for k in ["row", "around", "grid"]:
		(hpat_btns[k] as Button).set_pressed_no_signal(k == kind)
	(hpat_btns["pick"] as Button).visible = kind == "around"
	(hpat_btns["pick"] as Button).set_pressed_no_signal(hpat_pick and kind == "around")
	hpat_box.visible = kind != ""
	var show := {"row": ["hp_count", "hp_gap"], "around": ["hp_count", "hp_rad"], "grid": ["hp_rows", "hp_cols", "hp_gap"]}
	for r in hpat_rows:
		var on: bool = kind != "" and (show[kind] as Array).has(String(r["key"]))
		(r["box"] as Control).visible = on
		if on and not bool(r.get("held", false)):
			var h: Dictionary = sk["hpat"]
			var v := 0.0
			match String(r["key"]):
				"hp_count":
					v = float(h.get("n", 3))
				"hp_gap":
					v = float(h.get("gap", 20.0))
				"hp_rad":
					v = float(h.get("rad", 20.0))
				"hp_rows":
					v = float(h.get("rows", 2))
				"hp_cols":
					v = float(h.get("cols", 3))
			(r["slider"] as HSlider).set_value_no_signal(v)
			_pill_text(r, v)


## s051 FILL THE FACE (Friday plan 51): after Cut a hole, Fill the face (the chip on the Through page) cuts a whole perforated sheet or grille:
## press it, click a flat face, and the app computes how many holes of the chosen shape (Round / Square / Hex), size, spacing and edge margin
## fit on THAT face and cuts them all through, ONE solid and ONE undo step. It replaces the single hole (the same step: the hole's sketch
## and cut, rebuilt from hole_base), reuses the pattern sketch of Holes: Row / Around / Grid (many shapes in one sketch + the cut through),
## and a slider or a shape chip afterwards rewrites the sketch ("fill": the face and the numbers), one undo step each.
## Every hole stays at least the margin from every edge of the face (a hole's whole outline, not just its middle); the grid is the best of
## four half-step shifts, so the count is the most that fit. Staggered rows are spacing x 0.866 apart (the honeycomb of a grille)
const FILL_MAX := 500        # holes: more than this and the kernel takes minutes
const FILL_WEB := 0.4        # mm: the least material left between two holes
var fill_btn: Button
var fill_shape_btns := {}    # "round" / "square" / "hex" / "stag": the chips
var fill_box: VBoxContainer  # the shape chips and the three sliders (shown while the fill is on)
var fill_rows := []          # Size, Spacing, Margin
var fill_pick := false       # true while Fill the face waits for the click on the face
var fill_shape := "round"
var fill_stag := false
var fill_size := 5.0         # mm across (round: the diameter, square: the side, hex: across the flats)
var fill_gap := 10.0         # mm between the middles of neighbouring holes
var fill_margin := 5.0       # mm of material left between a hole and the edge of the face
var fill_count := 0          # the holes of the last fill
var _fill_cache := {}


func _fill_chips(h: Control) -> void:
	fill_btn = _big_btn("easypart_hole_fill", "Fill the face", "Cut a whole sheet of holes in a flat face: pick the shape, the size, the spacing and the edge margin, then click the face. The app counts how many fit and cuts them all, in one step", _fill_press)
	fill_btn.toggle_mode = true
	fill_btn.custom_minimum_size = Vector2(130, 44)
	h.add_child(fill_btn)
	fill_box = VBoxContainer.new()
	fill_box.name = "easypart_hole_fillbox"
	fill_box.custom_minimum_size = Vector2(700, 0)
	fill_box.add_theme_constant_override("separation", 2)
	fill_box.visible = false
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	fill_box.add_child(chips)
	for sd in [["round", "Round", "Round holes: the size is their width"], ["square", "Square", "Square holes: the size is their side"], ["hex", "Hex", "Six-sided holes in a honeycomb: the size is across the flats"]]:
		var b := _big_btn("easypart_fillshape_" + String(sd[0]), String(sd[1]), String(sd[2]), _fill_shape.bind(String(sd[0])))
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(92, 40)
		chips.add_child(b)
		fill_shape_btns[sd[0]] = b
	var sb := _big_btn("easypart_fillshape_stag", "Staggered", "Every other row is shifted half a step, so the holes pack tighter (a grille)", _fill_stagger)
	sb.toggle_mode = true
	sb.custom_minimum_size = Vector2(120, 40)
	chips.add_child(sb)
	fill_shape_btns["stag"] = sb
	var sl := HFlowContainer.new()
	sl.add_theme_constant_override("h_separation", 12)
	sl.add_theme_constant_override("v_separation", 0)
	fill_box.add_child(sl)
	fill_rows.append(_make_row("Hole size", 1.0, 50.0, 0.5, ["Smaller", "Bigger"], "fill", "fl_size", "mm", sl))
	fill_rows.append(_make_row("Spacing", 2.0, 100.0, 0.5, ["Closer", "Further apart"], "fill", "fl_gap", "mm", sl))
	fill_rows.append(_make_row("Edge margin", 1.0, 50.0, 0.5, ["Closer", "Further in"], "fill", "fl_margin", "mm", sl))
	for r in fill_rows:   # three sliders to a line, no words under them: the panel stays low
		(r["words"] as Control).visible = false
		(r["box"] as Control).custom_minimum_size = Vector2(225, 0)


## the hole's sketch while the face is filled ({} if not)
func _fill_sketch() -> Dictionary:
	if not _hole_on():
		return {}
	var sk := Part.feature(_rec(), hole_id)
	return sk if String(sk.get("t", "")) == "sketch" and sk.has("fill") else {}


func _fill_params() -> Dictionary:
	return {"shape": fill_shape, "stag": fill_stag, "size": fill_size, "gap": fill_gap, "margin": fill_margin}


## the corners of one hole of this shape at c (a circle has none: its radius is size / 2). Hex: flat top and bottom, size across the flats
static func fill_poly(shape: String, c: Vector2, size: float) -> Array:
	var out: Array = []
	if shape == "square":
		var h := size * 0.5
		out = [c + Vector2(-h, -h), c + Vector2(h, -h), c + Vector2(h, h), c + Vector2(-h, h)]
	elif shape == "hex":
		var R := size / sqrt(3.0)
		for i in 6:
			out.append(c + Vector2.from_angle(PI / 3.0 * i) * R)
	return out


## the closest two middles may be so that FILL_WEB of material is left between the holes (mm)
static func fill_least_gap(shape: String, stag: bool, size: float) -> float:
	if shape == "hex":
		return size * 1.1547005 + FILL_WEB
	if shape == "square" and stag:
		return (size + FILL_WEB) / 0.8660254
	return size + FILL_WEB


static func _fill_seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-12:
		return p.distance_to(a)
	return p.distance_to(a + ab * clampf((p - a).dot(ab) / l2, 0.0, 1.0))


static func _fill_in_poly(p: Vector2, poly: Array) -> bool:
	var n := poly.size()
	var pos := false
	var neg := false
	for i in n:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % n]
		var cr := (b - a).cross(p - a)
		if cr > 1e-9:
			pos = true
		elif cr < -1e-9:
			neg = true
	return not (pos and neg)


## the least distance between a segment and a convex polygon (0 when they touch or cross)
static func _fill_seg_poly(a: Vector2, b: Vector2, poly: Array) -> float:
	if _fill_in_poly(a, poly) or _fill_in_poly(b, poly):
		return 0.0
	var best := INF
	var n := poly.size()
	for i in n:
		var p: Vector2 = poly[i]
		var q: Vector2 = poly[(i + 1) % n]
		if Geometry2D.segment_intersects_segment(a, b, p, q) != null:
			return 0.0
		best = minf(best, minf(_fill_seg_dist(p, a, b), minf(_fill_seg_dist(q, a, b), minf(_fill_seg_dist(a, p, q), _fill_seg_dist(b, p, q)))))
	return best


static func _fill_in_tris(p: Vector2, tris: Array) -> bool:
	for t in tris:
		var a: Vector2 = t[0]
		var b: Vector2 = t[1]
		var c: Vector2 = t[2]
		var d1 := (b - a).cross(p - a)
		var d2 := (c - b).cross(p - b)
		var d3 := (a - c).cross(p - c)
		if (d1 >= -1e-7 and d2 >= -1e-7 and d3 >= -1e-7) or (d1 <= 1e-7 and d2 <= 1e-7 and d3 <= 1e-7):
			return true
	return false


## a hole at c is allowed: its middle is on the face and its whole outline keeps the margin from every edge of the face
static func fill_ok(c: Vector2, par: Dictionary, face: Dictionary) -> bool:
	if not _fill_in_tris(c, face["tris"]):
		return false
	var margin := float(par["margin"])
	var size := float(par["size"])
	if String(par["shape"]) == "round":
		var need := margin + size * 0.5 - 1e-6
		for sg in face["segs"]:
			if _fill_seg_dist(c, sg[0], sg[1]) < need:
				return false
		return true
	var poly := fill_poly(String(par["shape"]), c, size)
	for sg in face["segs"]:
		if _fill_seg_poly(sg[0], sg[1], poly) < margin - 1e-6:
			return false
	return true


## the flat face (spec: base plane name, mm along its normal, a world point on it) of the record: its triangles and its edge, in the base
## plane's own mm coordinates. {} if there is no such face
func _fill_face(base: Dictionary, spec: Dictionary) -> Dictionary:
	var key := "%s|%s|%s|%s" % [str(base.hash()), String(spec["base"]), str(spec["mm"]), str(spec.get("hit", []))]
	if String(_fill_cache.get("key", "")) == key:
		return _fill_cache["face"]
	var ax := FACE_BASE.find(String(spec["base"]))
	if ax < 0:
		return {}
	var axis: Vector3 = FACE_N[ax]
	var pl := Part.plane(String(spec["base"]))
	var lvl := float(spec["mm"])
	var tris: Array = []
	for body in Part.body_faces(base, -1):
		var tv: PackedVector3Array = body
		for k in range(0, tv.size() - 2, 3):
			var a := tv[k]
			var b := tv[k + 1]
			var c := tv[k + 2]
			var nrm := (b - a).cross(c - a)
			if nrm.length() < 1e-14 or absf(nrm.normalized().dot(axis)) < 0.9998:
				continue
			if absf(a.dot(axis) / Part.MM - lvl) > 0.02 or absf(b.dot(axis) / Part.MM - lvl) > 0.02 or absf(c.dot(axis) / Part.MM - lvl) > 0.02:
				continue
			tris.append([Part.to_plane(pl, a), Part.to_plane(pl, b), Part.to_plane(pl, c)])
	if tris.is_empty():
		return {}
	# union the triangles that share an edge: the face is the piece the click was on
	var parent := range(tris.size())
	var edge_owner := {}
	var vk := func(v: Vector2) -> String: return "%d,%d" % [roundi(v.x * 1000.0), roundi(v.y * 1000.0)]
	var ek := func(a: Vector2, b: Vector2) -> String:
		var ka: String = vk.call(a)
		var kb: String = vk.call(b)
		return ka + ">" + kb if ka < kb else kb + ">" + ka
	var find := func(i: int) -> int:
		while parent[i] != i:
			parent[i] = parent[parent[i]]
			i = parent[i]
		return i
	var edge_n := {}
	for i in tris.size():
		var t: Array = tris[i]
		for e in 3:
			var key_e: String = ek.call(t[e], t[(e + 1) % 3])
			edge_n[key_e] = int(edge_n.get(key_e, 0)) + 1
			if edge_owner.has(key_e):
				parent[find.call(i)] = find.call(int(edge_owner[key_e]))
			else:
				edge_owner[key_e] = i
	var pick := -1
	if spec.has("hit") and (spec["hit"] as Array).size() == 3:
		var hw := Vector3(float(spec["hit"][0]), float(spec["hit"][1]), float(spec["hit"][2]))
		var q := Part.to_plane(pl, hw)
		for i in tris.size():
			if _fill_in_tris(q, [tris[i]]):
				pick = int(find.call(i))
				break
	if pick < 0:   # no hit point: the biggest piece
		var area := {}
		for i in tris.size():
			var t2: Array = tris[i]
			var r: int = find.call(i)
			area[r] = float(area.get(r, 0.0)) + absf((t2[1] - t2[0]).cross(t2[2] - t2[0])) * 0.5
		var best := -1.0
		for r in area:
			if float(area[r]) > best:
				best = float(area[r])
				pick = int(r)
	var mine: Array = []
	var segs: Array = []
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in tris.size():
		if int(find.call(i)) != pick:
			continue
		var t3: Array = tris[i]
		mine.append(t3)
		for e in 3:
			var p0: Vector2 = t3[e]
			var p1: Vector2 = t3[(e + 1) % 3]
			lo = lo.min(p0)
			hi = hi.max(p0)
			if int(edge_n[ek.call(p0, p1)]) == 1:
				segs.append([p0, p1])
	var face := {"tris": mine, "segs": segs, "lo": lo, "hi": hi}
	_fill_cache = {"key": key, "face": face}
	return face


## the holes that fit: {"why": "" or why not, "centres": the middles (mm on the base plane), "count"}
func _fill_calc(base: Dictionary, spec: Dictionary, par: Dictionary) -> Dictionary:
	var size := float(par["size"])
	var gap := float(par["gap"])
	var shape := String(par["shape"])
	var least := fill_least_gap(shape, bool(par["stag"]), size)
	if gap < least - 1e-9:
		return {"why": "The spacing is too small: %s mm between the middles leaves almost no material between the holes. Make it at least %s mm" % [_plain_num(gap), _plain_num(snappedf(least + 0.049, 0.1))], "centres": [], "count": 0}
	var face := _fill_face(base, spec)
	if face.is_empty():
		return {"why": "I could not find that flat face. Press Fill the face and click it again", "centres": [], "count": 0}
	var lo: Vector2 = face["lo"]
	var hi: Vector2 = face["hi"]
	var stag := bool(par["stag"])
	var dy := gap * 0.8660254 if stag else gap
	var ni := int(ceil((hi.x - lo.x) / gap)) + 2
	var nj := int(ceil((hi.y - lo.y) / dy)) + 2
	if ni * nj > 60000:
		return {"why": "That would be far too many holes: make the spacing bigger", "centres": [], "count": 0}
	var mid := (lo + hi) * 0.5
	var best: Array = []
	for ox in [0.0, gap * 0.5]:
		for oy in [0.0, dy * 0.5]:
			var pts: Array = []
			for j in range(-nj, nj + 1):
				var y: float = mid.y + float(oy) + float(j) * dy
				if y < lo.y or y > hi.y:
					continue
				var rowoff := 0.0
				if stag:
					rowoff = 0.25 * gap if posmod(j, 2) == 1 else -0.25 * gap
				for i in range(-ni, ni + 1):
					var x: float = mid.x + float(ox) + rowoff + float(i) * gap
					if x < lo.x or x > hi.x:
						continue
					var c := Vector2(snappedf(x, 0.0001), snappedf(y, 0.0001))
					if fill_ok(c, par, face):
						pts.append(c)
			if pts.size() > best.size():
				best = pts
	if best.is_empty():
		return {"why": "That face is too small for even one %s mm hole with a %s mm margin: pick a bigger face, or make the hole or the margin smaller. Nothing was changed" % [_plain_num(size), _plain_num(float(par["margin"]))], "centres": [], "count": 0}
	if best.size() > FILL_MAX:
		return {"why": "That would be %d holes, more than %d: make the spacing or the holes bigger" % [best.size(), FILL_MAX], "centres": [], "count": 0}
	return {"why": "", "centres": best, "count": best.size()}


## the sketch entities of the holes (the pattern's way: one entity per circle, a square is a rectangle, a hex six lines)
func _fill_ents(centres: Array, par: Dictionary) -> Array:
	var shape := String(par["shape"])
	var size := float(par["size"])
	var out: Array = []
	for c in centres:
		if shape == "round":
			out.append({"k": "circle", "c": Part.arr2(c), "r": size * 0.5})
		elif shape == "square":
			out.append({"k": "rect", "a": Part.arr2(c - Vector2(size, size) * 0.5), "b": Part.arr2(c + Vector2(size, size) * 0.5)})
		else:
			var pts := fill_poly("hex", c, size)
			for i in 6:
				out.append({"k": "line", "a": Part.arr2(pts[i]), "b": Part.arr2(pts[(i + 1) % 6])})
	return out


func _fill_words(par: Dictionary, n: int) -> String:
	return "Fill the face: %d %s holes, %s mm wide, %s mm apart%s, %s mm from the edge. Hole size, Spacing and Edge margin change them; Through puts one hole back" % [n, String(par["shape"]), _plain_num(float(par["size"])), _plain_num(float(par["gap"])), ", staggered" if bool(par["stag"]) else "", _plain_num(float(par["margin"]))]


func _fill_press() -> void:
	if not _hole_on() or not Part.available() or hole_base.is_empty():
		fill_pick = false
		_hole_sync()
		_say("Press Cut a hole first, then Fill the face")
		return
	if fill_pick and _fill_sketch().is_empty():   # a second press before the click: off
		fill_pick = false
		_hole_sync()
		_say("Fill the face is off")
		return
	armed = ""
	wall_pick = false
	hpat_pick = false
	set("bulge_pick", false)   # one pick mode at a time: a Bulge pick left on would take the face click (declared further down the chain)
	var bb: Variant = get("bulge_btn")
	if bb != null:
		(bb as Button).set_pressed_no_signal(false)
	fill_pick = true
	_hole_sync()
	_say("Click the flat face you want to fill. First set the shape, Hole size, Spacing and Edge margin below")


## the click on the face (fill_pick is on): cut the holes there (one undo step), or say why not and change nothing
func _fill_click(p: Vector2) -> void:
	var fc := _face_hit(p)
	if fc.is_empty() or not fc.has("base"):
		_hole_sync()
		_say("Click on a flat face of the part. Press Fill the face to try again")
		fill_pick = false
		return
	fill_pick = false
	var spec := {"base": String(fc["base"]), "mm": float(fc["mm"]), "out": int(fc.get("out", 1))}
	if fc.has("hit"):
		var hv: Vector3 = fc["hit"]
		spec["hit"] = [hv.x, hv.y, hv.z]
	_flush_if_dirty()
	fill_cache_reset()
	var base: Dictionary = hole_base.duplicate(true)
	var par := _fill_params()
	var calc := _fill_calc(base, spec, par)
	if String(calc["why"]) != "":
		fill_pick = true   # still waiting: change the numbers below, then click the face again
		_hole_sync()
		_say(String(calc["why"]))
		return
	var snap := _rec().duplicate(true)
	_begin("Fill the face")
	var rec: Dictionary = base.duplicate(true)
	m.S.part = rec
	var bb: AABB = Part.replay(base)["aabb"]
	var reach := maxf(maxf(absf(bb.position.x), absf(bb.end.x)), maxf(maxf(absf(bb.position.y), absf(bb.end.y)), maxf(absf(bb.position.z), absf(bb.end.z)))) / Part.MM
	var fspec := spec.duplicate(true)
	fspec.merge(par, true)
	fspec["count"] = int(calc["count"])
	var sk := Part.new_feature(rec, "sketch", {"plane": String(spec["base"]), "ents": _fill_ents(calc["centres"], par), "dims": [], "fill": fspec})
	rec["features"].append(sk)
	rec["features"].append(Part.new_feature(rec, "extrude", {"sketch": sk["id"], "dist": snappedf(2.0 * (reach + 10.0), 1.0), "both": true, "op": "cut"}))
	var before := float(Part.replay(base)["volume"])
	var res := pu.replay_full(rec)
	var after := float(res["volume"])
	if not (res["errors"].is_empty() and after > 1e-9 and after < before - 1e-12):
		m.S.part = snap
		m._drop_undo()
		_edit_n = -1
		_say("Those holes do not cut the part: nothing was changed")
		fill_pick = true
	else:
		_end()
		hole_mode = "fill"
		hole_id = String(sk["id"])
		tweak = {}
		fill_count = int(calc["count"])
		_say(_fill_words(par, fill_count))
	pu.upto = -1
	pu.sync()
	_rows_sig = ""
	_rows_sync()
	_values_sync()
	_hole_sync()


func fill_cache_reset() -> void:
	_fill_cache = {}


## rewrite the filled sketch with the current numbers (a slider or a chip); "" or why not (the sketch is left as it was)
func _fill_redo(sk: Dictionary) -> String:
	var spec: Dictionary = sk["fill"]
	var par := _fill_params()
	var calc := _fill_calc(hole_base, spec, par)
	if String(calc["why"]) != "":
		return String(calc["why"])
	sk["ents"] = _fill_ents(calc["centres"], par)
	spec.merge(par, true)
	spec["count"] = int(calc["count"])
	fill_count = int(calc["count"])
	return ""


## the sliders: Hole size, Spacing, Edge margin (kind "fill" in _set_value). Before a face is filled they only set the numbers
func _apply_fill(row: Dictionary, v: float) -> void:
	var old := _fill_params()
	match String(row["key"]):
		"fl_size":
			fill_size = v
		"fl_gap":
			fill_gap = v
		"fl_margin":
			fill_margin = v
	var sk := _fill_sketch()
	if sk.is_empty():
		return
	pu.upto = -1
	var why := _fill_redo(sk)
	if why != "":
		fill_size = float(old["size"])
		fill_gap = float(old["gap"])
		fill_margin = float(old["margin"])
		_say(why)
	else:
		_say(_fill_words(_fill_params(), fill_count))


func _fill_shape(shape: String) -> void:
	fill_shape = shape
	if shape == "hex":
		fill_stag = true   # a honeycomb packs in staggered rows (Staggered turns it off again)
	_fill_change("Fill: " + shape)


func _fill_stagger() -> void:
	fill_stag = not fill_stag
	_fill_change("Fill: staggered" if fill_stag else "Fill: in a grid")


func _fill_change(label: String) -> void:
	var sk0 := _fill_sketch()
	if sk0.is_empty():
		_fill_sync()
		return
	_flush_if_dirty()
	var snap := _rec().duplicate(true)
	var old := (sk0["fill"] as Dictionary).duplicate(true)
	_begin(label)
	var sk := Part.feature(_rec(), hole_id)
	var why := _fill_redo(sk)
	if why == "":
		var res := pu.replay_full(_rec())
		if not (res["errors"].is_empty() and float(res["volume"]) > 1e-9):
			why = "Those holes do not cut the part: nothing was changed"
	if why != "":
		m.S.part = snap
		m._drop_undo()
		_edit_n = -1
		fill_shape = String(old["shape"])
		fill_stag = bool(old["stag"])
		_say(why)
	else:
		_end()
		_say(_fill_words(_fill_params(), fill_count))
	pu.upto = -1
	pu.sync()
	_rows_sig = ""
	_rows_sync()
	_values_sync()
	_fill_sync()


## the chips and sliders follow the fill
func _fill_sync() -> void:
	if fill_box == null:
		return
	var sk := _fill_sketch()
	if not sk.is_empty():
		var f: Dictionary = sk["fill"]
		fill_shape = String(f.get("shape", fill_shape))
		fill_stag = bool(f.get("stag", fill_stag))
		fill_size = float(f.get("size", fill_size))
		fill_gap = float(f.get("gap", fill_gap))
		fill_margin = float(f.get("margin", fill_margin))
		fill_count = int(f.get("count", fill_count))
	if not _hole_on():
		fill_pick = false
	if not sk.is_empty():
		hole_mode = "fill"   # (also after a Redo)
	elif hole_mode == "fill":
		hole_mode = "through"   # an Undo took the fill back to the single hole
	fill_btn.set_pressed_no_signal(fill_pick or not sk.is_empty())
	fill_box.visible = _hole_on() and (fill_pick or not sk.is_empty())
	for k in ["round", "square", "hex"]:
		(fill_shape_btns[k] as Button).set_pressed_no_signal(k == fill_shape)
	(fill_shape_btns["stag"] as Button).set_pressed_no_signal(fill_stag)
	for r in fill_rows:
		if bool(r.get("held", false)):
			continue
		var v := 0.0
		match String(r["key"]):
			"fl_size":
				v = fill_size
			"fl_gap":
				v = fill_gap
			"fl_margin":
				v = fill_margin
		(r["slider"] as HSlider).set_value_no_signal(v)
		_pill_text(r, v)


## p195generative MAKE IT LIGHTER (Friday plan 195): the Make it lighter chip in the Cut a hole row, with a Held and a Pushed chip beside it (a side each,
## the bottom and the top at first) and the "How much lighter" slider. A rule of thumb, NOT a stress simulation: see scripts/build/lighter.gd. The holes
## replace the Cut a hole step (one undo step); the slider and the two chips change the same step's holes
var lighter_held := "bottom"
var lighter_push := "top"
var lighter_level := 0.7
var lighter_held_btn: Button
var lighter_push_btn: Button


func _lighter_chip(h: Container) -> void:
	var lb := _big_btn("easypart_hole_lighter", "Make it lighter", "Take material out where it is not needed: round holes away from the line between the held side and the pushed side, a solid rim left round the edges. A rule of thumb, not a stress test", _hole_mode.bind("lighter"))
	lb.toggle_mode = true
	lb.icon = Icons.tex("part_shell")
	lb.custom_minimum_size = Vector2(150, 44)
	h.add_child(lb)
	hole_btns["lighter"] = lb
	lighter_held_btn = _big_btn("easypart_lighter_held", "", "Where the part is held (it does not move). Press to pick the next side", _lighter_pick.bind(true))
	lighter_push_btn = _big_btn("easypart_lighter_push", "", "Where the part is pushed (the load). Press to pick the next side", _lighter_pick.bind(false))
	for b in [lighter_held_btn, lighter_push_btn]:
		(b as Button).custom_minimum_size = Vector2(150, 44)
		(b as Button).visible = false
		h.add_child(b)
	_lighter_sync()


func _lighter_sync() -> void:
	if lighter_held_btn == null:
		return
	var on := hole_mode == "lighter" and _hole_on()
	lighter_held_btn.visible = on
	lighter_push_btn.visible = on
	lighter_held_btn.text = "Held: " + Lighter.side_word(lighter_held)
	lighter_push_btn.text = "Pushed: " + Lighter.side_word(lighter_push)


## a Held / Pushed press: the next side that is not the other chip's; the holes are made again (one undo step)
func _lighter_pick(held: bool) -> void:
	var cur := lighter_held if held else lighter_push
	var other := lighter_push if held else lighter_held
	var i := Lighter.SIDES.find(cur)
	for k in range(1, Lighter.SIDES.size() + 1):
		var nx: String = Lighter.SIDES[(i + k) % Lighter.SIDES.size()]
		if nx != other:
			if held:
				lighter_held = nx
			else:
				lighter_push = nx
			break
	_hole_mode("lighter", false, true)


func _lighter(rec: Dictionary) -> String:
	var res := Part.replay(rec)
	if int(res["bodies"]) == 0:
		return "Nothing solid to make lighter yet. Press Pull it up first"
	if int(res["bodies"]) > 1:
		return "Make it lighter works on one solid: press Stick together to make the pieces one solid first"
	var bb: AABB = res["aabb"]
	var sz := bb.size / Part.MM
	if sz.z > minf(sz.x, sz.y) + 1e-6:
		return "Make it lighter works on a flat part seen from the front (thin front to back). Turn it flat first"
	var lt := {"x0": bb.position.x / Part.MM, "y0": bb.position.y / Part.MM, "w": sz.x, "h": sz.y, "held": lighter_held, "push": lighter_push}
	var pl := Lighter.plan(lt, lighter_level)
	if int(pl["n"]) == 0:
		return "Too small to make lighter: it needs room for a hole with a solid rim round it. Pull it up bigger, then press Make it lighter again"
	var before := float(res["volume"])
	var n0: int = rec["features"].size()
	var seq0 := int(rec.get("seq", 0))
	var s := Part.new_feature(rec, "sketch", {"plane": "front", "ents": pl["ents"], "dims": [], "lt": lt, "light": lighter_level})
	rec["features"].append(s)
	rec["features"].append(Part.new_feature(rec, "extrude", {"sketch": s["id"], "dist": snappedf(2.0 * (maxf(absf(bb.position.z), absf(bb.end.z)) / Part.MM + 10.0), 1.0), "both": true, "op": "cut"}))
	var rr := pu.replay_full(rec)
	var after := float(rr["volume"])
	if not (after < before - 1e-12 and after > 1e-9) or int(rr["bodies"]) != 1:
		rec["features"].resize(n0)
		rec["seq"] = seq0
		return "The holes would not leave one solid: nothing was cut. Press Make it lighter again after a bigger pull"
	tweak = {"id": s["id"], "field": "light", "label": "How much lighter", "unit": "pct", "lo": 20.0, "hi": 100.0, "step": 10.0, "scale": 0.01, "words": ["A little", "A lot"]}
	_say("Lighter: %d round holes, a %d mm rim left round every edge and %d mm between holes. A rule of thumb, not a stress test. Held %s, pushed %s" % [int(pl["n"]), int(Lighter.MARGIN), int(Lighter.RIB), Lighter.side_word(lighter_held), Lighter.side_word(lighter_push)])
	return ""


## the slider moved: the holes of the sketch are made again at the new lightness (called from _apply_tweak)
func _lighter_follow(sk: Dictionary) -> void:
	if not sk.has("lt"):
		return
	lighter_level = clampf(float(sk.get("light", lighter_level)), 0.0, 1.0)
	var pl := Lighter.plan(sk["lt"], lighter_level)
	if int(pl["n"]) > 0:
		sk["ents"] = pl["ents"]


## the Fill the face shapes and sliders are up (waiting for the face, or the face is filled)
func _fill_open() -> bool:
	return fill_box != null and _hole_on() and (fill_pick or not _fill_sketch().is_empty())


## s202 SMART TOLERANCES (Friday plan 202): "How should it fit?" One chip on the Cut a hole panel cycles Tight (0.0 mm) / Snug (0.1) /
## Slides (0.2, the default) / Loose (0.4): the clearance on each side between a hole and what goes in it. A Through hole is its size
## (the Hole size slider, the peg) + the clearance on every side; a lid's lip sits that far inside the box's opening. The choice is
## remembered per part (rec["fit_mm"]); changing it is ONE undo step and re-cuts the hole / lid on the screen at the new fit
const SMARTFIT_NAMES := ["Tight", "Snug", "Slides", "Loose"]
const SMARTFIT_MM := [0.0, 0.1, 0.2, 0.4]
const SMARTFIT_DEFAULT := 0.2
var smartfit_btn: Button = null


func _fit_of(rec: Dictionary) -> float:
	return float(rec.get("fit_mm", SMARTFIT_DEFAULT))


func _fit_index(fit: float) -> int:
	for i in SMARTFIT_MM.size():
		if absf(float(SMARTFIT_MM[i]) - fit) < 0.005:
			return i
	return 2


func _smartfit_chip(h: Control) -> void:
	smartfit_btn = _big_btn("easypart_hole_fit", "", "How should it fit? The gap on each side between a hole and what goes in it: Tight 0.0 mm, Snug 0.1, Slides 0.2, Loose 0.4. Press to change it; the hole or lid on the screen is made again", _smartfit_press)
	smartfit_btn.custom_minimum_size = Vector2(150, 44)
	h.add_child(smartfit_btn)
	_smartfit_sync()


func _smartfit_sync() -> void:
	if smartfit_btn != null:
		smartfit_btn.text = "Fit: " + String(SMARTFIT_NAMES[_fit_index(_fit_of(_rec()))])


func _smartfit_press() -> void:
	var cur := _fit_index(_fit_of(_rec()))
	var nxt := (cur + 1) % SMARTFIT_NAMES.size()
	var nf := float(SMARTFIT_MM[nxt])
	var nm := String(SMARTFIT_NAMES[nxt])
	var words := "%s: %s mm on each side" % [nm, _mm_words(nf)]
	if _hole_on() and Part.available() and hole_mode == "lid":
		_hole_mode("lid", _rec_has_lip(), true, nf)   # the lid is made again at the new fit (one undo step)
		_smartfit_sync()
		_say("%s. The lid's lip sits that far inside the box" % words)
		return
	_flush_if_dirty()
	var sk: Dictionary = Part.feature(_rec(), String(tweak.get("id", ""))) if not tweak.is_empty() else {}
	var is_hole := _hole_on() and hole_mode == "through" and Part.available() and sk.has("fit") and tweak.has("ent")
	_begin("Change fit")
	var rec := _rec().duplicate(true)
	rec["fit_mm"] = nf
	if is_hole:   # the hole on the screen keeps the size the user gave it: its radius moves by the change of fit only
		var hk := Part.feature(rec, String(tweak["id"]))
		var old := float(hk.get("fit", 0.0))
		hk["ents"][int(tweak["ent"])]["r"] = float(hk["ents"][int(tweak["ent"])]["r"]) - old + nf
		hk["fit"] = nf
		_hpat_follow(hk)
		tweak["add"] = nf
	m.S.part = rec
	_end()
	if is_hole:
		pu.upto = -1
		pu.sync()
		_rows_sig = ""
		_rows_sync()
		_values_sync()
	_smartfit_sync()
	_say("%s. %s" % [words, "The hole is made again" if is_hole else "The next hole and lid use it"])
