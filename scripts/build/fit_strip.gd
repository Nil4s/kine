class_name FitStrip
extends RefCounted
## W16 TEST PRINT: TOLERANCE / FIT STRIP. Two plates in ONE part, printed flat: a plate of PEGS and a plate of HOLES, one cell per clearance
## (default 0.1 .. 0.5 mm in steps of 0.1; the maker can change lo / hi / step). The clearance is the gap on EACH SIDE, as the app's Fit presets
## (PipeParts.FIT_NAMES / FIT_MM: Tight 0.0, Snug 0.1, Slides 0.2, Loose 0.4) mean it: hole diameter = peg diameter + 2 x clearance. Every cell has
## its value cut into the plate under the peg / hole (PartText font outlines), so a printed strip needs no key. Pure data: build() answers a Part
## record (replayed by Part, exported by MeshExport) and the closed-form volumes the test holds the kernel to.
## Sketch coordinates are mm on the top plane (u = x, v = -z), the strip's low corner at 0,0.

const PText := preload("res://scripts/build/part_text.gd")
const PEG_D := 8.0
const PEG_H := 5.0
const PLATE_T := 3.0
const PLATE_W := 24.0          # plate depth (v)
const GAP_MM := 6.0            # between the two plates
const SIDE_GAP := 5.0          # between neighbouring cells, beyond the widest hole
const LABEL_H := 3.5           # engraved digit height
const LABEL_V := 6.0           # label centre, from the plate's front edge
const PEG_V := 17.0            # peg / hole centre, from the plate's front edge
const ENGRAVE := 0.6
const MAX_CELLS := 12


## the clearances of a range: lo, lo+step, ... up to hi (inclusive within 1e-6), rounded to 0.001
static func values(lo: float, hi: float, step: float) -> Array:
	var out: Array = []
	if step <= 0.0 or hi < lo:
		return out
	var n := int(floor((hi - lo) / step + 1e-6)) + 1
	for i in mini(n, MAX_CELLS):
		out.append(snappedf(lo + step * i, 0.001))
	return out


## the app's preset word for a clearance ("Snug"), or "" when it is none of them
static func preset_of(c: float) -> String:
	for i in PipeParts.FIT_MM.size():
		if absf(float(PipeParts.FIT_MM[i]) - c) < 0.005:
			return String(PipeParts.FIT_NAMES[i])
	return ""


static func label(c: float) -> String:
	return "%.1f" % c if absf(c * 10.0 - roundf(c * 10.0)) < 1e-6 else "%.2f" % c


static func _circle(cx: float, cy: float, r: float) -> Dictionary:
	return {"k": "circle", "c": [cx, cy], "r": r}


## {"ok", "why", "rec", "cells": [{"c", "preset", "label", "peg_d", "hole_d", "x"}], "peg_body", "hole_body" (index in the replayed bodies),
##  "exp_peg_mm3", "exp_hole_mm3" (closed form), "length", "text_area_peg", "text_area_hole"}
## rec_in: add the strip to this part (its steps are appended; body0 = the bodies it already has, so the "into" of the strip points at its own two);
## origin: where the strip's low corner goes on the top plane (mm)
static func build(lo := 0.1, hi := 0.5, step := 0.1, peg_d := PEG_D, rec_in := {}, body0 := 0, origin := Vector2.ZERO) -> Dictionary:
	var cs := values(lo, hi, step)
	if cs.is_empty():
		return {"ok": false, "why": "The range needs a first value, a last value above it and a step above 0"}
	if lo < 0.0 or peg_d < 2.0:
		return {"ok": false, "why": "Clearances start at 0 and the peg needs a diameter of 2 mm or more"}
	var widest := peg_d + 2.0 * float(cs[cs.size() - 1])
	var pitch := widest + SIDE_GAP
	var length := pitch * cs.size()
	var rec: Dictionary = rec_in if not rec_in.is_empty() else Part.make("Fit strip")
	var cells: Array = []
	var peg_polys: Array = []
	var hole_polys: Array = []
	var v_hole := origin.y - (PLATE_W + GAP_MM)   # the hole plate's front edge
	var circles_pegs: Array = []
	var holes_ents: Array = [{"k": "rect", "a": [origin.x, v_hole], "b": [origin.x + length, v_hole + PLATE_W]}]
	var area_pegs := 0.0
	var area_holes := 0.0
	var pegs_vol := 0.0
	var holes_vol := 0.0
	for i in cs.size():
		var c: float = cs[i]
		var cx := origin.x + pitch * (i + 0.5)
		var txt := label(c)
		var rw := PText.raw(txt)
		if not bool(rw["ok"]):
			return {"ok": false, "why": String(rw["why"])}
		var bb: Rect2 = rw["bb"]
		var sc := LABEL_H / maxf(bb.size.y, 0.001)
		if bb.size.x * sc > pitch - 2.0:
			sc = (pitch - 2.0) / bb.size.x
		for side in 2:
			var v0 := origin.y if side == 0 else v_hole
			var polys := PText.polygons(rw, sc, bb.get_center(), Vector2(cx, v0 + LABEL_V), false)
			if side == 0:
				peg_polys.append_array(polys)
				area_pegs += PText.area_of(polys)
			else:
				hole_polys.append_array(polys)
				area_holes += PText.area_of(polys)
		circles_pegs.append(_circle(cx, origin.y + PEG_V, peg_d * 0.5))
		holes_ents.append(_circle(cx, v_hole + PEG_V, peg_d * 0.5 + c))
		pegs_vol += PI * pow(peg_d * 0.5, 2) * PEG_H
		holes_vol += PI * pow(peg_d * 0.5 + c, 2) * PLATE_T
		cells.append({"c": c, "preset": preset_of(c), "label": txt, "peg_d": peg_d, "hole_d": peg_d + 2.0 * c, "x": cx})
	var F: Array = rec["features"]
	# body 0: the peg plate, pegs joined on top, values cut in
	var s1 := Part.new_feature(rec, "sketch", {"plane": "top", "ents": [{"k": "rect", "a": [origin.x, origin.y], "b": [origin.x + length, origin.y + PLATE_W]}], "dims": []})
	F.append(s1)
	F.append(Part.new_feature(rec, "extrude", {"sketch": s1["id"], "dist": PLATE_T, "both": false, "op": "new"}))
	var pl := Part.new_feature(rec, "plane", {"from": "top", "mm": PLATE_T, "out": 1})
	F.append(pl)
	var s2 := Part.new_feature(rec, "sketch", {"plane": pl["id"], "ents": circles_pegs, "dims": []})
	F.append(s2)
	F.append(Part.new_feature(rec, "extrude", {"sketch": s2["id"], "dist": PEG_H, "both": false, "op": "join", "into": body0}))
	var s3 := Part.new_feature(rec, "sketch", {"plane": pl["id"], "ents": PText.ents_of(peg_polys), "dims": []})
	F.append(s3)
	F.append(Part.new_feature(rec, "extrude", {"sketch": s3["id"], "dist": -ENGRAVE, "both": false, "op": "cut", "into": body0}))
	# body 1: the hole plate, values cut in
	var s4 := Part.new_feature(rec, "sketch", {"plane": "top", "ents": holes_ents, "dims": []})
	F.append(s4)
	F.append(Part.new_feature(rec, "extrude", {"sketch": s4["id"], "dist": PLATE_T, "both": false, "op": "new"}))
	var s5 := Part.new_feature(rec, "sketch", {"plane": pl["id"], "ents": PText.ents_of(hole_polys), "dims": []})
	F.append(s5)
	F.append(Part.new_feature(rec, "extrude", {"sketch": s5["id"], "dist": -ENGRAVE, "both": false, "op": "cut", "into": body0 + 1}))
	var plate := length * PLATE_W * PLATE_T
	return {"ok": true, "why": "", "rec": rec, "cells": cells, "length": length, "pitch": pitch,
		"peg_body": body0, "hole_body": body0 + 1,
		"exp_peg_mm3": plate + pegs_vol - area_pegs * ENGRAVE,
		"exp_hole_mm3": plate - holes_vol - area_holes * ENGRAVE,
		"text_area_peg": area_pegs, "text_area_hole": area_holes}
