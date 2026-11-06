extends SceneTree
## L57 PART CHECKPOINTS (11-06): Part.replay of a part of many joined steps was O(n^2) (256 joined boxes: 15.4 s; editing only the LAST step: 16.3 s).
## Per-step checkpoints (the state after each step, keyed by the hash of steps 0..i) so an edit at step k replays from checkpoint k-1, and a run of
## plain `prim` joins fused in ONE boolean (union_many) instead of one growing re-intersection per step.
## Run: WT_MAX=8 bash /c/Users/Nick/tools/kine_workers/wtest.sh partckpt     (PCK_GOLDEN=1 prints the geometry strings of the OLD replay)
## BARS (stated before the code; medians; the call is exactly the one tests/perfscout_test.gd times: Part.replay(rec, -1, {"effects": true})):
##   a1 full replay of 256 joined boxes, median of 5 fresh parts          <= 3000 ms   (before: 15400 ms)
##   a2 edit of only the LAST step at 256 (each rep a new value), median of 5 <= 500 ms   (before: 16300 ms)
##   a3 full replay of 1000 joined boxes, median of 3 fresh parts          <= 12000 ms  (before: minutes)
##   a4 edit of the last step at 1000, median of 5                         <= 1500 ms
##   a5 exponent from 50 to 256 on the full replay (log t256/t50 / log 256/50) <= 1.2   (before 1.83)
##   b1 the geometry string (bodies, volume, area, faces, edges, box) of the new replay equals the one of the old code (GOLDEN, measured before the change)
##   b2 ... and equals a replay with checkpoints off (want ckpt=false) on chains of 16/64/256, a random 3D-overlap pile of 40, and a chain broken by cuts
##   b3 an edit at step k (first, middle, last) from the cache equals a cold replay of the edited record
##   b4 the effects list (what each step did) is identical with and without checkpoints
##   c  undo/redo exact: the record before the edit gives the geometry string of before, the edited one that of after, again from the cache
##   d  PLANTED FAILS: (1) the string of an edited record differs from the original (the hash can tell); (2) a stale answer (what a cache keyed
##      without the edited step would return) differs from the fresh one, so b3 / c would catch a wrong key
const KCad := preload("res://scripts/kcad.gd")
var fails := 0
const G16 := "b1|v0.000049000003|a0.015100001|f126|e252|-0.00000,-0.00000,-0.00000,0.24500,0.01000,0.02000"
const G64 := "b1|v0.000193000009|a0.058300003|f510|e1020|-0.00000,-0.00000,-0.00000,0.96500,0.01000,0.02000"
const G256 := "b1|v0.000769000055|a0.231100017|f2046|e4092|-0.00000,-0.00000,-0.00000,3.84500,0.01000,0.02000"
const GPILE := "GOLDENPILE"
const GCUT := "GOLDENCUT"


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func chain(n: int) -> Dictionary:
	var rec := Part.make("pck")
	for i in n:
		Part.prim(rec, "box", {"x": i * 15.0, "y": 0.0, "z": 0.0, "w": 20.0, "h": 10.0, "d": 20.0, "op": "join" if i > 0 else "new"})
	return rec


func pile(n: int) -> Dictionary:
	var rec := Part.make("pckp")
	var s := 12345
	for i in n:
		var v: Array = []
		for k in 6:
			s = (s * 1103515245 + 12345) & 0x7fffffff
			v.append(float(s % 1000) / 1000.0)
		Part.prim(rec, "box", {"x": v[0] * 60.0, "y": v[1] * 40.0, "z": v[2] * 60.0, "w": 8.0 + v[3] * 14.0, "h": 8.0 + v[4] * 14.0, "d": 8.0 + v[5] * 14.0, "op": "join" if i > 0 else "new"})
	return rec


func cutchain(n: int) -> Dictionary:
	var rec := Part.make("pckc")
	for i in n:
		if i > 0 and i % 9 == 0:
			Part.prim(rec, "cylinder", {"x": i * 15.0 - 5.0, "y": -1.0, "z": 10.0, "axis": "y", "r": 3.0, "len": 14.0, "op": "cut"})
		else:
			Part.prim(rec, "box", {"x": i * 15.0, "y": 0.0, "z": 0.0, "w": 20.0, "h": 10.0, "d": 20.0, "op": "join" if i > 0 else "new"})
	return rec


## bodies | volume | area | faces | edges | box, from the kernel shapes themselves (not from the mesh)
func geo(rec: Dictionary, upto := -1, extra := {}) -> String:
	var w := {"effects": true, "keep": true}
	w.merge(extra)
	var res := Part.replay(rec, upto, w)
	var ids: Array = res.get("ids", [])
	var area := 0.0
	var faces := 0
	var edges := 0
	for b in ids:
		area += KCad.area(int(b))
		faces += KCad.face_count(int(b))
		edges += KCad.edge_count(int(b))
	var bb: AABB = res["aabb"]
	var s := "b%d|v%.12f|a%.9f|f%d|e%d|%.5f,%.5f,%.5f,%.5f,%.5f,%.5f" % [ids.size(), float(res["volume"]), area, faces, edges, bb.position.x, bb.position.y, bb.position.z, bb.end.x, bb.end.y, bb.end.z]
	for b in ids:
		KCad.release(int(b))
	return s


func fxs(rec: Dictionary, extra := {}) -> String:
	var w := {"effects": true}
	w.merge(extra)
	return str(JSON.stringify(Part.replay(rec, -1, w).get("effects", [])).hash())


func ms_of(c: Callable) -> float:
	var t := Time.get_ticks_usec()
	c.call()
	return (Time.get_ticks_usec() - t) / 1000.0


func med(a: Array) -> float:
	a.sort()
	return a[a.size() / 2]


func _init() -> void:
	if not Part.available():
		print("SKIP no KCad")
		print("partckpt: 0 fail")
		quit(0)
		return
	if OS.get_environment("PCK_GOLDEN") != "":
		for n in [16, 64, 256]:
			Part.inc_clear()
			print("GOLDEN%d=%s" % [n, geo(chain(n), -1, {"ckpt": false})])
		print("GOLDENPILE=" + geo(pile(40), -1, {"ckpt": false}))
		print("GOLDENCUT=" + geo(cutchain(45), -1, {"ckpt": false}))
		quit(0)
		return
	var W := {"effects": true}
	# ---- b: equality
	var cases := {"chain16": chain(16), "chain64": chain(64), "chain256": chain(256), "pile40": pile(40), "cut45": cutchain(45)}
	var gold := {"chain16": G16, "chain64": G64, "chain256": G256, "pile40": GPILE, "cut45": GCUT}
	for k in cases:
		Part.inc_clear()
		var new_s := geo(cases[k])
		var again := geo(cases[k])   # second time: from the cache
		Part.inc_clear()
		var off_s := geo(cases[k], -1, {"ckpt": false})
		ok(new_s == String(gold[k]), "b1 %s equals the OLD code's geometry (%s)" % [k, new_s.substr(0, 60)])
		ok(new_s == off_s and again == new_s, "b2 %s: checkpoints on / cached / off all give one geometry" % k)
		Part.inc_clear()
		var fa := fxs(cases[k])
		var fb := fxs(cases[k], {"ckpt": false})
		var fc := fxs(cases[k])
		ok(fa == fb and fc == fa, "b4 %s: the effects list is the same with and without checkpoints" % k)
	# ---- b3: an edit at step k from the cache equals a cold replay
	var base := chain(64)
	Part.inc_clear()
	geo(base)
	for k in [0, 31, 62, 63]:
		var e: Dictionary = base.duplicate(true)
		(e["features"][k] as Dictionary)["h"] = 14.0
		var cached := geo(e)
		Part.inc_clear()
		var cold := geo(e, -1, {"ckpt": false})
		ok(cached == cold, "b3 edit of step %d from the cache equals a cold replay" % k)
		Part.inc_clear()
		geo(base)
	# ---- c: undo / redo exact
	Part.inc_clear()
	var before := geo(base)
	var edited: Dictionary = base.duplicate(true)
	(edited["features"][63] as Dictionary)["w"] = 33.0
	var after := geo(edited)
	var undone := geo(base)
	var redone := geo(edited)
	ok(undone == before and redone == after, "c undo gives the geometry before the edit, redo the one after (from the cache)")
	# ---- d: planted fails (must be detected)
	ok(before != after, "d1 PLANTED: the edited record's geometry string differs from the original (the hash can tell)")
	var stale := before   # what a cache keyed without the edited step would return
	ok(stale != geo(edited), "d2 PLANTED: a stale (wrong-key) answer differs from the fresh one, so a wrong key would be caught by b3 / c")
	# ---- a: speed
	var t50 := []
	var t256 := []
	for r in 5:
		Part.inc_clear()
		var rr := chain(50 + r)   # a fresh part each rep
		t50.append(ms_of(func(): Part.replay(rr, -1, W)))
		Part.inc_clear()
		var r2 := chain(256)
		t256.append(ms_of(func(): Part.replay(r2, -1, W)))
	var m50 := med(t50)
	var m256 := med(t256)
	print("ROW full50=%.0f full256=%.0f" % [m50, m256])
	ok(m256 <= 3000.0, "a1 full replay of 256 joined boxes: %.0f ms <= 3000" % m256)
	var expo := log(m256 / m50) / log(256.0 / 50.0)
	ok(expo <= 1.2, "a5 exponent 50 -> 256: %.2f <= 1.2" % expo)
	var rb := chain(256)
	Part.replay(rb, -1, W)
	var te := []
	for r in 5:
		var e2: Dictionary = rb.duplicate(true)
		(e2["features"][255] as Dictionary)["w"] = 21.0 + r
		te.append(ms_of(func(): Part.replay(e2, -1, W)))
	var me := med(te)
	ok(me <= 500.0, "a2 edit of the LAST step at 256: %.0f ms <= 500" % me)
	var t1000 := []
	for r in 3:
		Part.inc_clear()
		var r3 := chain(1000)
		t1000.append(ms_of(func(): Part.replay(r3, -1, W)))
	var m1000 := med(t1000)
	ok(m1000 <= 12000.0, "a3 full replay of 1000 joined boxes: %.0f ms <= 12000" % m1000)
	var rk := chain(1000)
	Part.replay(rk, -1, W)
	var tk := []
	for r in 5:
		var e3: Dictionary = rk.duplicate(true)
		(e3["features"][999] as Dictionary)["w"] = 21.0 + r
		tk.append(ms_of(func(): Part.replay(e3, -1, W)))
	var mk := med(tk)
	ok(mk <= 1500.0, "a4 edit of the LAST step at 1000: %.0f ms <= 1500" % mk)
	Part.inc_clear()
	print("partckpt: %d fail" % fails)
	quit(1 if fails > 0 else 0)
