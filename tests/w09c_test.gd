extends SceneTree
## W09c (triage): the pick list's maker-feature lookup records each body's feature during ONE replay (was one replay per feature).
## Bars, written before measuring:
##   A temple part (tests/fixtures/w09c_temple_part.json): PickStack.names_for opens (median of 5, warm) in < 50 ms
##   B its labels/tips equal the old per-feature lookup's, body for body (the old code is kept below as the control)
##   C control: the old lookup, same warm cache, takes more than 50 ms on this part (so bar A can fail)
##   D a planted wrong maker (a label changed) is caught by the comparison in B
var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func old_names(rec: Dictionary, nb: int) -> Array:
	var res := Part.replay(rec, -1, {"inc": true})
	var feats: Array = rec.get("features", [])
	var made := []
	made.resize(nb)
	made.fill(-1)
	var seen := 0
	for i in feats.size():
		if seen >= nb:
			break
		if bool((feats[i] as Dictionary).get("off", false)):
			continue
		var c := int(Part.replay(rec, i, {"inc": true}).get("bodies", 0))
		while seen < mini(c, nb):
			made[seen] = i
			seen += 1
	var out := []
	for bi in nb:
		var nm := Part.body_name(res, bi)
		var named := nm != "Body%d" % (bi + 1)
		var fe := ""
		if int(made[bi]) >= 0:
			fe = PickStack.feat_label(feats[int(made[bi])])
		out.append({"label": nm if named else (fe if fe != "" else PickStack.name_of(bi)), "tip": ("Made by %s" % fe) if fe != "" else "Body %d" % (bi + 1)})
	return out


func _init() -> void:
	var rec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/w09c_temple_part.json"))
	var nb := int(Part.replay(rec, -1, {}).get("bodies", 0))
	print("temple: %d features, %d bodies" % [rec["features"].size(), nb])
	var tc0 := Time.get_ticks_usec()
	var shown := Part.replay(rec, -1, {"inc": true})   # what the view (PartUI.res) holds once the part is shown
	print("the view's own replay: %.0f ms" % ((Time.get_ticks_usec() - tc0) / 1000.0))
	var tf0 := Time.get_ticks_usec()
	var fb := PickStack.names_for(rec, nb)   # no `shown`: the fallback runs ONE incremental replay (cache warm)
	print("fallback names_for (one warm replay): %.0f ms" % ((Time.get_ticks_usec() - tf0) / 1000.0))
	var ts := []
	var nw := []
	for r in 5:
		var t := Time.get_ticks_usec()
		nw = PickStack.names_for(rec, nb, shown)
		ts.append((Time.get_ticks_usec() - t) / 1000.0)
	ts.sort()
	ok(ts[2] < 50.0, "A names_for median %.1f ms (runs %s) < 50" % [ts[2], ts])
	var t0 := Time.get_ticks_usec()
	var od := old_names(rec, nb)   # warm cache too (the view's replay and the new lookup already ran)
	var oms := (Time.get_ticks_usec() - t0) / 1000.0
	ok(oms > 50.0, "C control: the old lookup, same warm cache, takes %.1f ms (> 50)" % oms)
	var diff := 0
	ok(JSON.stringify(fb) == JSON.stringify(nw), "B2 the fallback (one replay) gives the same list as reading the view's result")
	for i in nb:
		if nw[i]["label"] != od[i]["label"] or nw[i]["tip"] != od[i]["tip"]:
			diff += 1
			if diff < 4:
				print("  differs body %d: new %s old %s" % [i, nw[i], od[i]])
	ok(nw.size() == nb and diff == 0, "B labels and tips equal the old lookup's on %d bodies (%d differ)" % [nb, diff])
	var bad: Array = od.duplicate(true)
	if nb > 0:
		bad[nb - 1]["label"] = "planted"
	var d2 := 0
	for i in nb:
		if nw[i]["label"] != bad[i]["label"]:
			d2 += 1
	ok(d2 == 1, "D the comparison catches a planted wrong label (%d differ)" % d2)
	print("w09c: %d fail" % fails)
	quit(1 if fails > 0 else 0)
