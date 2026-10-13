extends SceneTree
## TRANSITION TABLE between the standard poses (poses/lib). Two clean poses can still have a bad path between them:
## the in-betweens blend angles, which can sweep the bat or an arm through the body. For each pair A -> B this plays
## the move exactly as the poser does (Scene, natural timing, feet planted) and takes the deepest contact over every
## frame. A pair whose path is clean is "direct"; otherwise every other library pose is tried as a VIA (A -> V -> B)
## and the cleanest is kept. Result: data/transitions.json  {"a>b": {"via": "" or "<pose>", "worst_mm": n}, ...}
##   godot --headless --path . -s tools/transitions.gd
## Each path is judged AFTER Scene.clear() (the pass-by repair every cook runs), so "direct" means the poser's own
## in-betweens handle it; a via is only needed where that repair can't.
## Clean = no frame deeper than CLEAN_MM (in the poses' own allowance terms: Body.contacts already subtracts it).

const CLEAN_MM := 2.0


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var names := []
	var poses := {}
	for f in DirAccess.get_files_at("res://poses/lib"):
		if f.ends_with(".json"):
			var n := f.get_basename()
			names.append(n)
			poses[n] = JSON.parse_string(FileAccess.get_file_as_string("res://poses/lib/" + f))
	names.sort()
	var out := {}
	var n_direct := 0
	var n_via := 0
	var n_none := 0
	for a in names:
		for b in names:
			if a == b:
				continue
			var w := worst(B, [poses[a], poses[b]])
			if w <= CLEAN_MM:
				out[a + ">" + b] = {"via": "", "worst_mm": w}
				n_direct += 1
				continue
			var best_v := ""
			var best_w := w
			for v in names:
				if v == a or v == b:
					continue
				var wv := worst(B, [poses[a], poses[v], poses[b]])
				if wv < best_w:
					best_w = wv
					best_v = v
			out[a + ">" + b] = {"via": best_v, "worst_mm": best_w, "direct_mm": w}
			if best_w <= CLEAN_MM:
				n_via += 1
			else:
				n_none += 1
			print("%-18s -> %-18s direct %5.0f mm   best via %-18s %5.0f mm%s" % [a, b, w, best_v if best_v != "" else "-", best_w,
				"" if best_w <= CLEAN_MM else "   STILL BAD"])
	FileAccess.open("res://data/transitions.json", FileAccess.WRITE).store_string(JSON.stringify(out, " "))
	print("TRANSITIONS: %d direct, %d via one pose, %d still bad (of %d)" % [n_direct, n_via, n_none, out.size()])
	quit()


## the deepest contact (mm) over every frame of the move through these poses
static func worst(B: Body, ps: Array, repair := true) -> float:
	var S := Scene.new()
	for i in ps.size():
		S.add("k%d" % i, ps[i])
		S.cards[-1]["hold"] = 0.0
	if repair:
		S.clear(B)   # the pass-by repair the cook runs: the path the poser really plays
	var w := 0.0
	for fr in S.check(B):
		for c in fr[2]:
			w = maxf(w, float(c[2]) * 1000.0)
	return snappedf(w, 0.1)
