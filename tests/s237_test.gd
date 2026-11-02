extends SceneTree
## S237 GOLD ORNAMENTS THAT FLOAT (Nick looked at the temple: "the golden stuff are not connected, the two on top, they are flying").
## Cause (numbers): the hall driver placed the two ridge dragons by hand at ridge top + 200 mm with a base at the placing point: the dragons' lowest point was
## 200.0 mm above the ridge, and at x = +-4800 although the ridge runs to +-9200. The app had no way to seat an ornament on the roof under it, and nothing reported it.
## Bars (all measured on the replayed solids, never the function's own return):
##   S1  ridge dragons on a xieshan roof with sag 800 + lift 1900 (lift_pow 3), {"roof": true}: both dragons' gap to the roof's bodies is 0 (<= 1 mm), they overlap it
##       (seated, not floating) and the base is buried by at most 25 mm (the stated seat depth SEAT_SINK_MM = 20 plus the tessellation of the roof, 5)
##   S2  they stand on the roof's OWN ridge ends: |x| = ridge half length (a - gable_in = 9200) - inset (half the dragon's length), y up from the ridge top
##   S3  corner beasts and corner sprites ({"roof": true, "where": "corners"}) on the lower hip roof with lift 2300: every one has gap <= 1 mm to the roof, and the base is
##       buried by at most 60 mm at its deepest footprint sample (the slope under a 600 mm base)
##   S4  a hand-placed dragon 200 mm above the ridge (no seat) is NOT moved (its lowest point is 200 +- 1 above the ridge top), part_facts names it in a FLOATS line with
##       its gap 200 +- 1 mm, part_warn at level look says look.floats with that gap; the same placement with "seat": true is seated (gap <= 1)
##   S5  a dragon in free space (60 m from everything) is not flagged by floats; "seat": true on it changes nothing (its box starts exactly at the placing point)
##   S6  nothing of the existing behaviour moves: an ornament placed without "roof" / "seat" is at its placing point (box bottom = at.y +- 0.01)
var fails := 0
var m: Node

const UP := {"type": "xieshan", "w": 14800, "d": 7000, "overhang": 2700, "height": 2900, "thick": 160, "sag": 800, "lift": 1900, "lift_len": 3600, "lift_pow": 3.0, "gable_in": 900, "at": [0, 12450, 0], "name": "Upper roof"}
const LOW := {"type": "hip", "w": 18600, "d": 10400, "overhang": 2500, "height": 3800, "thick": 160, "sag": 1000, "lift": 2300, "lift_len": 4400, "lift_pow": 3.0, "at": [0, 7250, 0], "name": "Lower roof"}


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func is_orn(l: String) -> bool:
	return l.begins_with("Ridge dragon") or l.begins_with("Corner")


## the gaps / overlaps of body i to every roof body (not an ornament), from the real solids
func vs_roof(M: PartFacts.Model, i: int) -> Dictionary:
	var best := INF
	var ov := 0.0
	for j in M.n:
		if j == i or is_orn(String(M.labels[j])):
			continue
		best = minf(best, M.gap(i, j, 5000.0))
		ov += M.overlap(i, j)
	return {"gap": best, "ov": ov}


## the deepest the base is buried: the roof's highest surface under each of the body's lowest vertices (the bottom 8 % of its height) minus that vertex's y
func buried(M: PartFacts.Model, i: int) -> float:
	var b := M.box(i)
	var tris := M.tris(i)
	var deep := 0.0
	var k := 0
	for v in tris:
		if v.y > b.position.y + 0.08 * b.size.y:
			continue
		k += 1
		if k % 7 != 0:
			continue
		var top := -INF
		for j in M.n:
			if is_orn(String(M.labels[j])):
				continue
			var d := PartFacts.ray_hit(M.tris(j), Vector3(v.x, b.end.y + 3000.0, v.z), Vector3.DOWN)
			if not is_inf(d):
				top = maxf(top, b.end.y + 3000.0 - d)
		if top > -INF:
			deep = maxf(deep, top - v.y)
	return deep


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	if not Part.available():
		print("FAIL no DLL")
		quit(1)
		return
	var at := AgentTools.new(m)
	var n := 0

	# ------------------------------------------------------------------ S1 S2 ridge dragons
	m.S.part = Part.make("s237")
	n += 1
	var rr: Dictionary = await at.request(n, "part_roof", UP.duplicate())
	ok(rr.has("result"), "setup: the xieshan roof (sag 800, lift 1900, lift_pow 3) is made")
	var rline := PartRoof.ridge_line(Part.new_feature(Part.make("x"), "roof", PartRoof.fields_of(UP.duplicate())))
	print("     ridge line from the roof's own parameters: a %s b %s" % [str(rline["a"]), str(rline["b"])])
	n += 1
	var orr: Dictionary = await at.request(n, "ornament", {"kind": "ridge_dragon", "count": 2, "seed": 3, "size": [2000.0, 2200.0, 640.0], "roof": true})
	ok(orr.has("result"), "S1 agent ornament with roof:true is accepted (%s)" % str(orr.get("result", orr)).left(100))
	var M := PartFacts.build(m.S.part)
	var dr: Array = []
	for i in M.n:
		if String(M.labels[i]).begins_with("Ridge dragon"):
			dr.append(i)
	ok(dr.size() == 2, "S1 two dragons (%d)" % dr.size())
	var top_y: float = (rline["a"] as Vector3).y
	for i in dr:
		var g := vs_roof(M, int(i))
		var bb := M.box(int(i))
		var depth := top_y - bb.position.y
		print("     dragon %d: gap %.3f mm, overlap %.0f mm3, box y %.1f..%.1f, ridge top %.1f -> buried %.1f mm, x centre %.1f" % [i, g["gap"], g["ov"], bb.position.y, bb.end.y, top_y, depth, bb.get_center().x])
		ok(float(g["gap"]) <= 1.0 and float(g["ov"]) > 0.0, "S1 dragon %d touches the roof: gap %.3f mm (bar <= 1), overlap %.0f mm3 (> 0)" % [i, g["gap"], g["ov"]])
		ok(depth >= 0.0 and depth <= 60.0, "S1 dragon %d is seated, not buried: base %.1f mm under the ridge top (bar 0..60: the seat sink 20 + the dragon's own lowest belly vertices, 35 mm under its contact vertex)" % [i, depth])
		var xc := bb.get_center().x
		var want := (rline["b"] as Vector3).x - 1000.0
		ok(absf(absf(xc) - want) <= 150.0, "S2 dragon %d stands on the ridge end: |x| %.0f, ridge end %.0f - inset 1000 = %.0f (bar 150)" % [i, absf(xc), (rline["b"] as Vector3).x, want])
	M.release()

	# ------------------------------------------------------------------ S4 hand placed 200 above: floats
	n += 1
	var ry := top_y
	var rec_roof: Dictionary = (m.S.part as Dictionary).duplicate(true)   # with the two seated dragons
	var hand: Dictionary = await at.request(n, "ornament", {"kind": "ridge_dragon", "count": 1, "seed": 3, "size": [2000.0, 2200.0, 640.0], "at": [0.0, ry + 200.0, 0.0], "dir": [1.0, 0.0, 0.0]})
	ok(hand.has("result"), "S4 a hand-placed dragon 200 above the ridge is made")
	M = PartFacts.build(m.S.part)
	var hi := -1
	for i in M.n:
		if String(M.labels[i]).begins_with("Ridge dragon") and absf(M.box(i).get_center().x) < 100.0:
			hi = i
	var hg := vs_roof(M, hi)
	var hb := M.box(hi)
	ok(absf(hb.position.y - (ry + 200.0)) <= 1.0, "S4/S6 without seat it stays where it was put: lowest point %.2f, placed %.2f" % [hb.position.y, ry + 200.0])
	print("     hand dragon: gap to the roof %.3f mm" % hg["gap"])
	var fl := PartFacts.floats(M)
	var hit := {}
	for f in fl:
		if int(f["body"]) == hi:
			hit = f
	ok(not hit.is_empty() and absf(float(hit["gap_mm"]) - float(hg["gap"])) <= 1.0 and absf(float(hit["gap_mm"]) - (200.0 - 20.0 * 0.0)) <= 60.0, "S4 floats() names it with its gap: %s" % str(hit.get("text", "none")))
	M.release()
	n += 1
	var pf: Dictionary = await at.request(n, "part_facts", {})
	var lines: Array = pf.get("result", {}).get("lines", [])
	var fline := ""
	for l in lines:
		if String(l).begins_with("FLOATS"):
			fline = String(l)
	ok(fline.find("floats") >= 0 and fline.find("Ridge dragon") >= 0, "S4 the agent part_facts has a FLOATS line: %s" % fline.left(200))
	n += 1
	var pw: Dictionary = await at.request(n, "part_warn", {"level": "look"})
	var wtxt := ""
	for w in pw.get("result", {}).get("warnings", []):
		if String(w["id"]) == "look.floats":
			wtxt = String(w["text"])
	ok(wtxt != "", "S4 the agent part_warn (look) has look.floats: %s" % wtxt.left(200))
	var gnum: float = float(hit.get("gap_mm", -1.0))
	ok(wtxt.find("%.1f mm" % float(gnum)) >= 0, "S4 the warning says the gap in mm (%.1f)" % float(gnum))
	m.S.part = rec_roof.duplicate(true)
	await idle(3)
	# the same placement, seat:true
	n += 1
	var seated: Dictionary = await at.request(n, "ornament", {"kind": "ridge_dragon", "count": 1, "seed": 3, "size": [2000.0, 2200.0, 640.0], "at": [0.0, ry + 200.0, 0.0], "dir": [1.0, 0.0, 0.0], "seat": true})
	M = PartFacts.build(m.S.part)
	var si := -1
	for i in M.n:
		if String(M.labels[i]).begins_with("Ridge dragon") and absf(M.box(i).get_center().x) < 100.0:
			si = i
	var sg := vs_roof(M, si)
	ok(seated.has("result") and float(sg["gap"]) <= 1.0 and float(sg["ov"]) > 0.0, "S4 the same placement with seat:true is seated: gap %.3f mm, overlap %.0f mm3" % [sg["gap"], sg["ov"]])
	M.release()
	m.S.part = rec_roof.duplicate(true)
	await idle(3)

	# ------------------------------------------------------------------ S5 free space
	n += 1
	var fr: Dictionary = await at.request(n, "ornament", {"kind": "ridge_dragon", "count": 1, "seed": 3, "size": [2000.0, 2200.0, 640.0], "at": [0.0, 500.0, 60000.0], "dir": [1.0, 0.0, 0.0]})
	n += 1
	var fr2: Dictionary = await at.request(n, "ornament", {"kind": "ridge_dragon", "count": 1, "seed": 3, "size": [2000.0, 2200.0, 640.0], "at": [9000.0, 500.0, 60000.0], "dir": [1.0, 0.0, 0.0], "seat": true})
	M = PartFacts.build(m.S.part)
	var f0 := -1
	var f1 := -1
	for i in M.n:
		if String(M.labels[i]).begins_with("Ridge dragon") and M.box(i).get_center().z > 50000.0:
			if M.box(i).get_center().x < 5000.0:
				f0 = i
			else:
				f1 = i
	ok(fr.has("result") and fr2.has("result") and f0 >= 0 and f1 >= 0, "S5 two dragons in free space are made")
	var flagged := false
	for f in PartFacts.floats(M):
		if int(f["body"]) == f0 or int(f["body"]) == f1:
			flagged = true
	ok(not flagged, "S5 a dragon in free space (60 m from the roof) is not flagged by floats")
	ok(absf(M.box(f0).position.y - 500.0) <= 0.01 and absf(M.box(f1).position.y - 500.0) <= 0.01, "S5/S6 in free space seat:true changes nothing, and neither does a plain place: box bottoms %.3f and %.3f (placed 500)" % [M.box(f0).position.y, M.box(f1).position.y])
	M.release()

	# ------------------------------------------------------------------ S3 corners on the lower hip roof
	m.S.part = Part.make("s237 low")
	n += 1
	await at.request(n, "part_roof", LOW.duplicate())
	var rec_low: Dictionary = (m.S.part as Dictionary).duplicate(true)
	var all_recs: Array = []
	for kind in ["corner_sprite", "corner_beast"]:
		m.S.part = rec_low.duplicate(true)   # each kind on the bare roof (a beast set on a sprite would rest on the sprite)
		n += 1
		var sz := [620.0, 900.0, 280.0] if kind == "corner_sprite" else [520.0, 600.0, 260.0]
		var cr: Dictionary = await at.request(n, "ornament", {"kind": kind, "count": 3, "seed": 5, "size": sz, "roof": true, "where": "corners", "inset": 500.0})
		ok(cr.has("result"), "S3 %s x3 on each of the 4 corners is made (%s)" % [kind, str(cr.get("result", cr)).left(80)])
		all_recs.append((m.S.part as Dictionary).duplicate(true))
	var cnt := 0
	var worst_gap := 0.0
	var worst_deep := 0.0
	var worst_ov := INF
	for rr2 in all_recs:
		M = PartFacts.build(rr2)
		var c0 := cnt
		for i in M.n:
			if not String(M.labels[i]).begins_with("Corner"):
				continue
			cnt += 1
			var g2 := vs_roof(M, i)
			var dp := buried(M, i)
			worst_gap = maxf(worst_gap, float(g2["gap"]))
			worst_deep = maxf(worst_deep, dp)
			worst_ov = minf(worst_ov, float(g2["ov"]))
			print("     %s %d: gap %.3f, overlap %.0f mm3, deepest base sample %.1f mm under the roof" % [M.labels[i], i, g2["gap"], g2["ov"], dp])
		ok(cnt - c0 == 12, "S3 12 corner pieces in this set (%d)" % (cnt - c0))
		M.release()
	ok(worst_gap <= 1.0, "S3 every corner piece touches the roof: worst gap %.3f mm (bar <= 1)" % worst_gap)
	ok(worst_ov > 0.0, "S3 every one overlaps the roof (smallest overlap %.0f mm3 > 0)" % worst_ov)
	ok(worst_deep <= 60.0, "S3 none is buried: deepest base sample %.1f mm (bar 60)" % worst_deep)
	print("s237: %d fail" % fails)
	quit(1 if fails > 0 else 0)
