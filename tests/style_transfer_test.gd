## godot --headless --path . -s tests/style_transfer_test.gd     (ROADMAP 25, top-25 #12; numbers and sources: docs/research/STYLES.md)
## STYLE TRANSFER (scripts/style_transfer.gd) on scenes/walk_bat.json, READ ONLY (nothing under scenes/, poses/, data/ is written;
## the results go to user://style_transfer_results.json). Bars:
##   1 0 % = the same file, bit for bit (every style): JSON of the output equals JSON of the input
##   2 OLDER 100 %: the walk's speed is in the older band (0.9-1.1 m/s, Bohannon & Andrews 2011) and not faster than the source;
##     walk_bat walks at 0.95 m/s, so its speed is kept (the style slows only a faster walk)
##   3 OLDER 100 %: the trunk flexes forward by the sum of OLDER_TRUNK (5 deg, +-1), measured as the lean of the walk
##   4 TIRED 100 %: the peak hand speed is LOWER than the source's
##   5 ANGRY 100 %: the peak hand acceleration is HIGHER than the source's
##   6 HEAVY 100 %: the stance knees bend more (the calf's offset is applied) and the holds are longer
##   7 the default Check (Rulebook.check) has no new MUST FIX (FAIL) in any style at 100 % against walk_bat's own count
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	var src: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scenes/walk_bat.json"))
	var S0 := Scene.new()
	S0.from_dict(src)
	var m0 := StyleTransfer.measure(S0)
	var B0 := Body.new()
	B0.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var must0 := Rulebook.check(S0, B0).filter(func(f): return f["sev"] == "FAIL").size()
	var res := {"source": {"speed": m0["speed"], "lean": m0["lean"], "hand_v": m0["hand_v"], "hand_a": m0["hand_a"], "must_fix": must0}}

	# 1 zero is the same file, for every style
	var same := true
	for st in StyleTransfer.STYLES:
		same = same and JSON.stringify(StyleTransfer.make(src, st, 0.0)) == JSON.stringify(src)
	ok(same, "1 0 %% = the same file for %s" % str(StyleTransfer.STYLES))

	var out := {}
	for st in StyleTransfer.STYLES:
		out[st] = StyleTransfer.make(src, st, 100.0)
	var S := {}
	var m := {}
	var new_must := {}
	for st in StyleTransfer.STYLES:
		S[st] = Scene.new()
		S[st].from_dict(out[st])
		m[st] = StyleTransfer.measure(S[st])
		var B := Body.new()
		B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
		new_must[st] = Rulebook.check(S[st], B).filter(func(f): return f["sev"] == "FAIL").size() - must0
		res[st] = {"speed": m[st]["speed"], "lean": m[st]["lean"], "hand_v": m[st]["hand_v"], "hand_a": m[st]["hand_a"], "new_must_fix": new_must[st]}

	var sp: float = m["older"]["speed"]
	ok(sp >= 0.9 and sp <= 1.1 and sp <= m0["speed"] + 0.001,
		"2 OLDER 100 %%: walk %.3f m/s (source %.3f; the older band 0.9-1.1, slowed only when faster)" % [sp, m0["speed"]])
	var dl: float = m["older"]["lean"] - m0["lean"]
	var want := 0.0
	for j in StyleTransfer.OLDER_TRUNK:
		want += StyleTransfer.OLDER_TRUNK[j]
	ok(absf(dl - want) <= 1.0, "3 OLDER 100 %%: trunk flexion +%.2f deg (source %.2f -> %.2f), want +%.1f +- 1" % [dl, m0["lean"], m["older"]["lean"], want])
	ok(m["tired"]["hand_v"] < m0["hand_v"], "4 TIRED 100 %%: peak hand speed %.3f m/s < source %.3f" % [m["tired"]["hand_v"], m0["hand_v"]])
	ok(m["angry"]["hand_a"] > m0["hand_a"], "5 ANGRY 100 %%: peak hand acceleration %.2f m/s2 > source %.2f" % [m["angry"]["hand_a"], m0["hand_a"]])
	var holds0 := 0.0
	var holds1 := 0.0
	for c in src["cards"]:
		holds0 += float(c["hold"])
	for c in out["heavy"]["cards"]:
		holds1 += float(c["hold"])
	var calf_layer := 0.0
	for L in out["heavy"].get("layers", []):
		calf_layer += float(L["v"].get("calf_r", [0, 0, 0])[0])
	ok(holds1 > holds0 and calf_layer > 0.0, "6 HEAVY 100 %%: holds %.2f s -> %.2f s, the stance knee +%.1f deg (calf_r layer)" % [holds0, holds1, calf_layer])
	var worst := 0
	for st in StyleTransfer.STYLES:
		worst = maxi(worst, new_must[st])
	ok(worst <= 0, "7 the default Check: new MUST FIX per style %s (walk_bat has %d)" % [str(new_must), must0])

	var f := FileAccess.open("user://style_transfer_results.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(res, "  "))
		f.close()
	print("STYLE TRANSFER TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
