extends SceneTree
## godot --headless --path . -s tests/s262_test.gd   (s262 EXPLODED VIEW: scripts/build/explode_view.gd)
## Bars (written before the first run), fixture: backplate, plate, 4 screws through both (head side 2 mm below, tip 1 mm above), axis Y, gap 10 mm:
##   1 ORDER    every screw leaves before the plate and before the backplate
##   2 CLEAR    check(): zero collisions over the whole out + in run (>= 400 samples)
##   3 CONTROL  the naive given order (backplate first) is reported as a collision (>= 1), and check() is not vacuous
##   4 GAP      final boxes of different layers are >= gap apart along the axis OR separated sideways
##   5 LAYERS   level_layers groups the 4 screws into one layer (3 layers); the plan over layers also has 0 collisions
##   6 KEYS     keys: out and in keys per moving layer, smoothstep midpoint = half the distance
##   7 STUCK    a box wrapped in a closed shell with one_way cannot leave: flagged stuck (the planner does not lie)
var fails := 0
func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1
func _init() -> void:
	var mm := 0.001
	var boxes: Array = [AABB(Vector3(0, 0, 0) * mm, Vector3(60, 2, 40) * mm), AABB(Vector3(0, 2, 0) * mm, Vector3(60, 2, 40) * mm)]
	for p in [Vector2(4, 4), Vector2(52, 4), Vector2(4, 32), Vector2(52, 32)]:
		boxes.append(AABB(Vector3(p.x, -2, p.y) * mm, Vector3(4, 7, 4) * mm))
	var pl := ExplodeView.plan(boxes, [], Vector3.UP, 10 * mm)
	var sc := ExplodeView.schedule(pl, 1.0, 0.4, 0.5)
	print("order ", pl["order"], " sign ", pl["sign"], " dist ", pl["dist"], " anchor ", pl["anchor"], " stuck ", pl["stuck"])
	var pos := {}
	for j in (pl["order"] as Array).size():
		pos[pl["order"][j]] = j
	var scr_ok := true
	for s in [2, 3, 4, 5]:
		scr_ok = scr_ok and (not pos.has(0) or pos[s] < pos[0]) and (not pos.has(1) or pos[s] < pos[1])
	ok(scr_ok and pos.size() >= 5, "1 ORDER screws out before plate and backplate: " + ExplodeView.words(pl, ["Backplate", "Plate", "S1", "S2", "S3", "S4"]))
	var ck := ExplodeView.check(pl, sc)
	ok(bool(ck["ok"]) and int(ck["samples"]) >= 400, "2 CLEAR %d collisions in %d samples" % [(ck["collisions"] as Array).size(), ck["samples"]])
	var ns := ExplodeView.naive_schedule(pl, 1.0, 0.4, 0.5)
	var nk := ExplodeView.check(pl, ns)
	ok(not bool(nk["ok"]) and (nk["collisions"] as Array).size() >= 1, "3 CONTROL naive order reported: %d collisions, first %s" % [(nk["collisions"] as Array).size(), str((nk["collisions"] as Array)[0]) if not (nk["collisions"] as Array).is_empty() else "none"])
	var fin := ExplodeView.boxes_at(pl, sc, sc["out_total"])
	var gap_ok := true
	for i in fin.size():
		for j in range(i + 1, fin.size()):
			var a: AABB = fin[i]
			var b: AABB = fin[j]
			var sep_axis: float = maxf(b.position.y - (a.position.y + a.size.y), a.position.y - (b.position.y + b.size.y))
			var side := not (a.position.x < b.end.x - 1e-6 and b.position.x < a.end.x - 1e-6 and a.position.z < b.end.z - 1e-6 and b.position.z < a.end.z - 1e-6)
			if not side and sep_axis < 10 * mm - 1e-6:
				gap_ok = false
	ok(gap_ok, "4 GAP final boxes >= 10 mm apart or side by side")
	var lay := ExplodeView.level_layers(boxes, Vector3.UP)
	ok(lay.size() == 3, "5a LAYERS %d layers: %s" % [lay.size(), str(lay)])
	var p2 := ExplodeView.plan(boxes, lay, Vector3.UP, 10 * mm)
	var s2 := ExplodeView.schedule(p2)
	var c2 := ExplodeView.check(p2, s2)
	print(p2["order"], p2["sign"], p2["dist"], p2["anchor"], (c2["collisions"] as Array).slice(0, 3))
	ok(bool(c2["ok"]), "5b LAYERS plan over layers has no collision")
	var u0: int = pl["order"][0]
	var kk: Array = ExplodeView.keys(pl, sc)[u0]
	var mid := ExplodeView.dist_at(pl, sc, u0, (float(sc["out_start"][u0]) + float(sc["out_end"][u0])) * 0.5)
	ok(kk.size() == 6 and absf(mid - float(pl["dist"][u0]) * 0.5) < 1e-9 and kk[2]["kind"] == "out" and kk[4]["kind"] == "in", "6 KEYS out/in keys, smoothstep mid = half (%.4f of %.4f)" % [mid, pl["dist"][u0]])
	var stk: Array = [AABB(Vector3(0, 0, 0), Vector3(1, 1, 1)), AABB(Vector3(0, 1, 0), Vector3(1, 1, 1)), AABB(Vector3(0, 2, 0), Vector3(1, 1, 1))]
	var p3 := ExplodeView.plan(stk, [], Vector3.UP, 0.1, {"anchor": 2, "one_way": true})
	ok(not (p3["stuck"] as Array).is_empty(), "7 STUCK anchor on top, one way up: the bottom two cannot leave, flagged " + str(p3["stuck"]))
	print("FAILS ", fails)
	quit(1 if fails > 0 else 0)
