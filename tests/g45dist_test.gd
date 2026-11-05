extends SceneTree
## godot --path . -s tests/g45dist_test.gd     (G45DIST: KCad.distance, the kernel's solid-to-solid minimum distance (OCCT BRepExtrema_DistShapeShape,
## KineCAD 6), and the G33 build-stage support check on it (scripts/build/assembly_stage.gd). Bars committed before the first run; every bar has a
## planted control (a "CONTROL" line that must be caught):
##   a DISTANCE   two 10 mm cubes 1.000 mm apart along x: d = 1e-3 m to 1e-9 m, witness points on the facing faces (x = 5 mm and 6 mm to 1e-9 m,
##                y and z inside the 10 mm face); spheres r 10 mm and r 20 mm: d = |c1 - c2| - r1 - r2 to 1e-9 m (|c| from the float32 move as
##                passed), witness point on sphere 1 at r1 along the centre line to 1e-9 m. CONTROL: two cubes overlapping by 5 mm give d = 0, and a
##                5 mm sphere wholly inside a cube (no boundary crossing: its boundary distance is 2.5 mm) gives 0 with "inner"
##   b SAME       AssemblyStage.check with the distance touch test gives the identical verdict to the old seven-boolean test (opts touch "overlap")
##                on every g33stage support fixture (tower, same-stage chain, roof before walls, floating pair, 1 mm / 0.05 mm over the base,
##                0.05 mm / 1 mm beside a wall, sunk 2 mm, resting, sunk 0.001 mm) and on CH15 as stages (53 of 53 supported) and CH15 dome-first
##                (the Shield dome unsupported at its stage): the same unsupported (id, stage), the same collisions (id, with, mm3 exactly) and the
##                same support kind per part. CONTROL: the comparison tells the tower from roof-before-walls (their verdicts differ), and the two
##                runs really took the two paths (touch "dist" with distance calls; touch "overlap" with none)
##   c SPEED      the CH15 support check (whole AssemblyStage.check, ms) with the distance path is at least 5x faster than with the old path (the
##                new one runs FIRST, so it pays any cold cache). CONTROL: the new path asks at least 5x fewer booleans than the old one
##   d SUITE      the g33stage suite still passes all 28 bars with the new path (checked by the same wtest run, not in this file)
const KCad := preload("res://scripts/kcad.gd")
const S15 := preload("res://scripts/build/ch15_site.gd")
const GREY := [0.7, 0.7, 0.7]
var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func ctl(c: bool, w: String) -> void:
	ok(c, "CONTROL " + w)


func idle(n := 3) -> void:
	for i in n:
		await process_frame


# ------------------------------------------------------------------ a
func bars_distance() -> void:
	var a: int = KCad.box(0.01, 0.01, 0.01)
	var b0: int = KCad.box(0.01, 0.01, 0.01)
	var b: int = KCad.translate(b0, Vector3(0.011, 0.0, 0.0))
	var r := KCad.distance(a, b)
	var pa: PackedFloat64Array = r.get("pa64", PackedFloat64Array([0, 0, 0]))
	var pb: PackedFloat64Array = r.get("pb64", PackedFloat64Array([0, 0, 0]))
	var d := float(r.get("d", -1.0))
	var on_faces: bool = absf(pa[0] - 0.005) < 1e-9 and absf(pb[0] - 0.006) < 1e-9 and absf(pa[1]) <= 0.005 + 1e-12 and absf(pa[2]) <= 0.005 + 1e-12 and absf(pb[1]) <= 0.005 + 1e-12 and absf(pb[2]) <= 0.005 + 1e-12
	ok(bool(r.get("ok", false)) and absf(d - 1e-3) < 1e-9 and on_faces, "a cubes 1.000 mm apart: d = %.12f m (err %s m); pa %s pb %s (faces x = 0.005 / 0.006)" % [d, str(absf(d - 1e-3)), str(pa), str(pb)])
	var s1: int = KCad.sphere(0.01)
	var s20: int = KCad.sphere(0.02)
	var c := Vector3(0.03, 0.04, 0.012)
	var s2: int = KCad.translate(s20, c)
	var rs := KCad.distance(s1, s2)
	var cl := sqrt(float(c.x) * float(c.x) + float(c.y) * float(c.y) + float(c.z) * float(c.z))
	var hand := cl - 0.03
	var ds := float(rs.get("d", -1.0))
	var q: PackedFloat64Array = rs.get("pa64", PackedFloat64Array([0, 0, 0]))
	var qv := Vector3(q[0], q[1], q[2])
	var qlen := sqrt(q[0] * q[0] + q[1] * q[1] + q[2] * q[2])
	var along := absf(q[0] - float(c.x) / cl * 0.01) < 1e-9 and absf(q[1] - float(c.y) / cl * 0.01) < 1e-9 and absf(q[2] - float(c.z) / cl * 0.01) < 1e-9
	ok(bool(rs.get("ok", false)) and absf(ds - hand) < 1e-9 and absf(qlen - 0.01) < 1e-9 and along, "a spheres r 10 / 20 mm, centres %s m apart: d = %.12f m vs hand %.12f (err %s); witness on sphere 1 at r %.12f, along the centre line %s (%s, off it by %s m)" % [str(cl), ds, hand, str(absf(ds - hand)), qlen, str(along), str(qv), str(maxf(absf(q[0] - float(c.x) / cl * 0.01), maxf(absf(q[1] - float(c.y) / cl * 0.01), absf(q[2] - float(c.z) / cl * 0.01))))])
	var o: int = KCad.translate(b0, Vector3(0.005, 0.0, 0.0))
	var ro := KCad.distance(a, o)
	var inside: int = KCad.sphere(0.005)
	var mid: int = KCad.box(0.015, 0.015, 0.015)   # faces 7.5 mm from the centre: 2.5 mm from the sphere, nothing crosses
	var ri := KCad.distance(mid, inside)
	ctl(bool(ro.get("ok", false)) and float(ro["d"]) == 0.0 and bool(ri.get("ok", false)) and float(ri["d"]) == 0.0 and bool(ri.get("inner", false)), "a cubes overlapping 5 mm: d = %s; a 5 mm sphere inside a 15 mm cube (boundary gap 2.5 mm): d = %s, inner %s" % [str(ro.get("d")), str(ri.get("d")), str(ri.get("inner"))])
	for id in [a, b0, b, s1, s20, s2, o, inside, mid]:
		KCad.release(int(id))


# ------------------------------------------------------------------ fixtures (copied from tests/g33stage_test.gd)
func box_rec(nm: String, w: float, h: float, d: float, col: Array) -> Dictionary:
	return {"version": 1, "name": nm, "seq": 2, "features": [
		{"t": "prim", "id": "f1", "name": "Prim1", "kind": "box", "op": "new", "x": 0.0, "y": 0.0, "z": 0.0, "w": w, "h": h, "d": d},
		{"t": "appear", "id": "f2", "name": "Appear2", "body": 0.0, "color": col, "metal": 0.0, "rough": 0.8, "preset": "Custom"}]}


func put(asm: Dictionary, nm: String, rec: Dictionary, pos: Vector3) -> String:
	asm["seq"] = int(asm["seq"]) + 1
	var id := "p%d" % int(asm["seq"])
	asm["parts"].append({"id": id, "name": nm, "src": "", "rec": rec, "pos": [pos.x, pos.y, pos.z], "rot": [0.0, 0.0, 0.0]})
	return id


func tower() -> Dictionary:
	var asm := Assembly.make("Block tower")
	put(asm, "Base", box_rec("Base", 100, 20, 100, GREY), Vector3.ZERO)
	put(asm, "Wall A", box_rec("Wall A", 10, 60, 100, GREY), Vector3(0, 20, 0))
	put(asm, "Wall B", box_rec("Wall B", 10, 60, 100, GREY), Vector3(90, 20, 0))
	put(asm, "Roof", box_rec("Roof", 100, 10, 100, GREY), Vector3(0, 80, 0))
	return asm


func staged(asm: Dictionary, st: Array) -> Dictionary:
	var c := asm.duplicate(true)
	c["stages"] = []
	for s in st:
		(c["stages"] as Array).append({"name": s[0], "parts": s[1], "dur": 1.0})
	return c


func one_block(pos: Vector3, sz := Vector3(20, 10, 20)) -> Dictionary:
	var t := tower()
	put(t, "Block", box_rec("Block", sz.x, sz.y, sz.z, GREY), pos)
	return staged(t, [["Base", ["p1"]], ["Walls", ["p2", "p3"]], ["Block", ["p5"]]])


func ch15_staged(dome_first: bool) -> Dictionary:
	var asm := S15.assembly()
	var by_name := {}
	for p in asm["parts"]:
		by_name[String(p["name"])] = String(p["id"])
	for p in asm["parts"]:
		var h: Array = []
		for sp in p["sup"]:
			if String(sp[1]) == "hang" and by_name.has(String(sp[0])):
				h.append(by_name[String(sp[0])])
		if not h.is_empty():
			p["hang"] = h
	asm["stages"] = []
	for s in S15.stages({"dome_first": dome_first}):
		(asm["stages"] as Array).append({"name": s["name"], "parts": (s["parts"] as Array).map(func(n): return by_name.get(String(n), "?" + String(n))), "dur": 1.0})
	asm["stage_opts"] = {"tol": S15.TOL * 1000.0, "ground": 0.0}
	return asm


func fixtures() -> Array:
	var t := tower()
	var fl := tower()
	put(fl, "Low", box_rec("Low", 20, 10, 20, GREY), Vector3(40, 21, 40))
	put(fl, "High", box_rec("High", 20, 10, 20, GREY), Vector3(40, 31, 40))
	return [
		["tower", staged(t, [["Base", ["p1"]], ["Walls", ["p2", "p3"]], ["Roof", ["p4"]]])],
		["chain", staged(t, [["Base", ["p1"]], ["Walls and roof", ["p4", "p2", "p3"]]])],
		["roof first", staged(t, [["Base", ["p1"]], ["Roof", ["p4"]], ["Walls", ["p2", "p3"]]])],
		["floating pair", staged(fl, [["Base", ["p1"]], ["Pair", ["p5", "p6"]]])],
		["1 mm over", one_block(Vector3(40, 21, 40))],
		["0.05 mm over", one_block(Vector3(40, 20.05, 40))],
		["0.05 mm beside", one_block(Vector3(100.05, 40, 40), Vector3(10, 10, 10))],
		["1 mm beside", one_block(Vector3(101, 40, 40), Vector3(10, 10, 10))],
		["sunk 2 mm", one_block(Vector3(40, 18, 40), Vector3(20, 20, 20))],
		["resting", one_block(Vector3(40, 20, 40), Vector3(20, 20, 20))],
		["sunk 0.001 mm", one_block(Vector3(40, 19.999, 40), Vector3(20, 20, 20))],
	]


## the verdict: unsupported (id, stage), collisions (id, with, mm3 to the last bit), support kind per part
func sig(r: Dictionary) -> String:
	var u: Array = (r["unsupported"] as Array).map(func(x): return "%s@%d" % [x["id"], int(x["stage"])])
	var c: Array = (r["collisions"] as Array).map(func(x): return "%s~%s:%s" % [x["id"], x["with"], var_to_str(float(x["mm3"]))])
	var ks: Array = (r["support"] as Dictionary).keys()
	ks.sort()
	var s: Array = ks.map(func(k): return "%s=%s" % [k, r["support"][k]["by"]])
	return "U%s C%s S%s" % [str(u), str(c), str(s)]


func on_diffs(r0: Dictionary, r1: Dictionary) -> int:
	var n := 0
	for k in r0["support"]:
		if not (r1["support"] as Dictionary).has(k) or String(r0["support"][k]["on"]) != String(r1["support"][k]["on"]):
			n += 1
	return n


# ------------------------------------------------------------------ b + c
func bars_same() -> void:
	var same := 0
	var total := 0
	var bad: Array = []
	var paths_ok := true
	var sigs := {}
	for f in fixtures():
		var rn := AssemblyStage.check(f[1])
		var ro := AssemblyStage.check(f[1], {"touch": "overlap"})
		total += 1
		paths_ok = paths_ok and String(rn["touch"]) == "dist" and int(rn["dist_calls"]) > 0 and String(ro["touch"]) == "overlap" and int(ro["dist_calls"]) == 0
		sigs[f[0]] = sig(rn)
		if sig(rn) == sig(ro):
			same += 1
		else:
			bad.append([f[0], sig(rn), sig(ro)])
		print("     %-15s new %s (%d dist, %d booleans, %d gated, %d ms) | old %d booleans %d ms | 'on' differs for %d" % [f[0], sig(rn), int(rn["dist_calls"]), int(rn["kernel_calls"]) - int(rn["dist_calls"]), int(rn["gated"]), int(rn["ms"]), int(ro["kernel_calls"]), int(ro["ms"]), on_diffs(ro, rn)])
	ok(same == total and total == 11, "b g33stage fixtures: %d of %d give the identical verdict on both paths; differ: %s" % [same, total, str(bad)])
	var g := ch15_staged(false)
	var n := (g["parts"] as Array).size()
	var cn := AssemblyStage.check(g)   # the new path FIRST: it pays any cold cache
	var co := AssemblyStage.check(g, {"touch": "overlap"})
	print("     ch15 new: %d ms, %d dist calls, %d booleans, %d gated, %d skipped; old: %d ms, %d booleans, %d skipped; 'on' differs for %d" % [int(cn["ms"]), int(cn["dist_calls"]), int(cn["kernel_calls"]) - int(cn["dist_calls"]), int(cn["gated"]), int(cn["skipped"]), int(co["ms"]), int(co["kernel_calls"]), int(co["skipped"]), on_diffs(co, cn)])
	ok(sig(cn) == sig(co) and n == 53 and (cn["unsupported"] as Array).is_empty() and int(cn["placed"]) == 53, "b CH15 as stages: new %d of %d supported, %d collisions; verdicts identical %s" % [int(cn["placed"]) - (cn["unsupported"] as Array).size(), n, (cn["collisions"] as Array).size(), str(sig(cn) == sig(co))])
	var dn := AssemblyStage.check(ch15_staged(true))
	var dold := AssemblyStage.check(ch15_staged(true), {"touch": "overlap"})
	var dome := (dn["unsupported"] as Array).filter(func(x): return String(x["name"]) == "Shield dome" and String(x["stage_name"]) == "Shield dome")
	ok(sig(dn) == sig(dold) and dome.size() == 1, "b CH15 dome before the walls: new unsupported %s; identical to the old %s (old %d ms, new %d ms)" % [str((dn["unsupported"] as Array).map(func(x): return "%s at %s" % [x["name"], x["stage_name"]])), str(sig(dn) == sig(dold)), int(dold["ms"]), int(dn["ms"])])
	paths_ok = paths_ok and String(cn["touch"]) == "dist" and String(co["touch"]) == "overlap" and int(co["dist_calls"]) == 0 and int(cn["dist_calls"]) > 0
	ctl(String(sigs["tower"]) != String(sigs["roof first"]) and paths_ok, "b the comparison tells tower (%s) from roof-before-walls (%s); every run took its path: %s" % [sigs["tower"], sigs["roof first"], str(paths_ok)])
	var tn := float(cn["ms"])
	var to := float(co["ms"])
	ok(tn * 5.0 <= to, "c CH15 support check: old %.1f s, new %.1f s: %.1fx faster (bound >= 5x)" % [to / 1000.0, tn / 1000.0, to / maxf(tn, 1.0)])
	var bn := int(cn["kernel_calls"]) - int(cn["dist_calls"])
	var bo := int(co["kernel_calls"])
	ctl(bn * 5 <= bo, "c booleans on CH15: new %d (+ %d distances), old %d" % [bn, int(cn["dist_calls"]), bo])


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	await idle(2)
	if not Part.available() or not KCad.has_distance():
		ok(false, "the CAD DLL with distance (KineCAD 6) is missing: %s" % KCad.version())
		print("g45dist: %d fail" % fails)
		quit(1)
		return
	print("     %s" % KCad.version())
	bars_distance()
	bars_same()
	print("g45dist: %d fail" % fails)
	quit(1 if fails > 0 else 0)
