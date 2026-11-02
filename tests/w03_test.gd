extends SceneTree
func rec_make(w: float, rim := false) -> Dictionary:
	var r := Part.make("w03")
	var F: Array = r["features"]
	F.append({"t":"sketch","id":"f1","name":"S1","plane":"front","ents":[{"k":"rect","a":[0,0],"b":[w,30]}],"dims":[{"id":"d1","ent":0,"kind":"w","mm":w}]})
	F.append({"t":"extrude","id":"f2","name":"E1","sketch":"f1","dist":20.0,"both":false,"op":"new"})
	F.append({"t":"sketch","id":"f3","name":"S2","plane":"front","ents":[{"k":"circle","c":[10,15],"r":4}],"dims":[]})
	F.append({"t":"extrude","id":"f4","name":"Hole","sketch":"f3","dist":-20.0,"both":false,"op":"cut"})
	return r
func edge_of(res: Dictionary, p: Array) -> Dictionary:
	var best := {}
	var bd := 1e9
	for e in res["edges"]:
		var c: Vector3 = e["c"] / Part.MM
		var d := c.distance_to(Vector3(p[0], p[1], p[2]))
		if d < bd:
			bd = d
			best = e
	return best
func centroid_after(rec: Dictionary, fid: String) -> Variant:
	# replay with the fillet and report the picked edge by replaying up to just before it and calling match_edge
	var i := Part.index_of(rec, fid)
	var KC = Part
	var res := Part.replay(rec, i - 1, {"edges": true})
	var f: Dictionary = rec["features"][i]
	var out := []
	for want in f["edges"]:
		var best := -1
		var bs := 1e9
		for k in res["edges"].size():
			var e: Dictionary = res["edges"][k]
			var bb: AABB = res["aabb"]
			var q: Vector3 = e["q"]
			var qv := Vector3(want["q"][0], want["q"][1], want["q"][2])
			var s := q.distance_to(qv) + 0.5 * (1.0 - absf((e["d"] as Vector3).dot(Vector3(want["d"][0], want["d"][1], want["d"][2]))))
			if s < bs:
				bs = s
				best = k
		out.append((res["edges"][best]["c"] / Part.MM) if best >= 0 else null)
	return out
var fails := 0
func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1
## godot --headless --path . -s tests/w03_test.gd   (W03: box, hole, fillet, pattern, hinge = 7 steps; step-1 width 40 -> 60; needs the CAD DLL)
## Bars (written first): replay errors 0; fillet edge centroid within 0.5 mm of (60,30,10); hinge pivot within 0.5 mm of (60,0,0);
## CONTROL: the same hinge without "oq" is >= 19 mm off (the bar can fail); a vanished body names "step 7".
func _init() -> void:
	var r := rec_make(40.0)
	var res := Part.replay(r, -1, {"edges": true})
	var A := edge_of(res, [40, 30, 10])
	(r["features"] as Array).append({"t":"fillet","id":"f5","name":"Fillet1","body":0,"r":1.0,"edges":[Part.describe(A)]})
	(r["features"] as Array).append({"t":"pattern","id":"f6","name":"P","body":0,"kind":"linear","count":2,"mm":40.0,"dir":"z","op":"new"})
	r["seq"] = 6   # the hand-built steps above used f1..f6
	# the real creation path: PartFx.append (the agent / feature call; Easy and Expert end in the same replay)
	var made := PartFx.append(r, "hinge", {"body":0,"o":[40,0,0],"axis":[0,0,1],"track":[[0,0],[1,30]]})
	var hid := String(made["id"])
	ok(r["features"].size() == 7 and hid == "f7", "7 steps (hinge %s)" % hid)
	ok(r["features"][6].has("oq"), "creation wrote oq without any pin call")
	var q: Array = r["features"][6]["oq"]
	ok(absf(q[0] - 1.0) < 1e-4 and absf(q[1]) < 1e-4, "oq = right/front edge of the box (%s)" % str(q))
	var r2 := r.duplicate(true)
	r2["features"][0]["ents"][0]["b"] = [60.0, 30]
	r2["features"][0]["dims"][0]["mm"] = 60.0
	var rr := Part.replay(r2, -1, {})
	ok(rr["errors"].is_empty(), "replay errors 0 (%s)" % str(rr["errors"]))
	var cs = centroid_after(r2, "f5")
	var dfil: float = (cs[0] as Vector3).distance_to(Vector3(60, 30, 10))
	ok(dfil < 0.5, "fillet lands on the corner: %.3f mm" % dfil)
	var pv = PartRefs.hinge_pivot(r2, "f7")
	var dh: float = (pv as Vector3).distance_to(Vector3(60, 0, 0))
	ok(dh < 0.5, "hinge pivot follows the box: %.3f mm (pivot %s)" % [dh, str(pv)])
	var r3 := r2.duplicate(true)
	(r3["features"][6] as Dictionary).erase("oq")
	var dc: float = (PartRefs.hinge_pivot(r3, "f7") as Vector3).distance_to(Vector3(60, 0, 0))
	ok(dc >= 19.0, "CONTROL: unpinned hinge is %.1f mm off" % dc)
	var r4 := r.duplicate(true)
	r4["features"][6]["body"] = 9
	var e = PartRefs.hinge_pivot(r4, "f7")
	ok(e is Dictionary and String(e["err"]).begins_with("step 7"), "vanished body names the step: %s" % str(e))
	print("W03 ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(fails)
