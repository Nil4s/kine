## godot --headless --path . -s tests/layer_fix_test.gd     (round 49, GATES NA2, UPGRADES_300 #255)
## FIX ON A LAYER (scripts/layer_fix.gd) on the first HEAD QUIET finding with a kept fix in the real scenes:
##   1 the scene's cards are byte for byte the same after LayerFix.make; at least one layer comes back
##   2 at every changed card's ARRIVAL the layered scene plays the FIXED scene (Fixer.apply on a copy) within 0.5 deg,
##     every joint the fix changed (worst printed); anti-vacuity: the unlayered scene is > 0.5 deg away there
##   3 "w" 0 on every fix layer = the scene as it was, byte for byte at 30 times; "w" 0.5 = half the change at the card
##   4 a TIMING fix (TIP SPEED: more move time) is refused with the reason, no layer made
##   (reported, not barred: whether Check still finds HEAD QUIET on the layered scene)
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func load_scene(path: String) -> Scene:
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string(path)))
	return S


func play(S: Scene, B: Body) -> Array:
	var out := []
	for i in 30:
		S.apply(B, S.length() * i / 29.0)
		out.append(B.ang.duplicate())
	return out


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var done := false
	var timing_done := false
	for path in ["res://scenes/combo3.json", "res://scenes/bo_spin.json", "res://scenes/thrust.json", "res://scenes/_wip/combo3_detail.json"]:
		if done and timing_done:
			break
		var S0 := load_scene(path)
		var sm := Rulebook.sample(S0, B)
		for f in Rulebook.check(S0, B, sm):
			if f["rule"] == "HEAD QUIET" and f["card"] > 0 and not done:
				var S := load_scene(path)
				var cards0 := JSON.stringify(S.cards)
				var r := LayerFix.make(f, S, B, sm)
				if not r["ok"]:
					print("     %s %s card %d: %s" % [path.get_file(), f["rule"], f["card"] + 1, r["msg"]])
					continue
				done = true
				ok(JSON.stringify(S.cards) == cards0 and r["layers"].size() > 0, "1 %s HEAD QUIET card %d: cards byte for byte the same; %d layer(s): %s" % [path.get_file(), f["card"] + 1, r["layers"].size(), r["msg"]])
				var F := load_scene(path)
				Fixer.apply(f, F, B, sm)
				S.layers = r["layers"]
				var ts := S.times()
				var worst := 0.0
				var away := 0.0
				for L in r["layers"]:
					var c := int(String(L["name"]).get_slice(" c", 1)) - 1
					var t: float = ts[c][1]
					var PL := Body.new()
					PL.load_files("res://data/skeleton.json", "res://data/body_limits.json")
					S.apply(PL, t)
					var PF := Body.new()
					PF.load_files("res://data/skeleton.json", "res://data/body_limits.json")
					F.apply(PF, t)
					var keep: Array = S.layers
					S.layers = []
					S.apply(B, t)
					S.layers = keep
					for j in L["v"].keys().filter(func(x): return x != "offset"):
						worst = maxf(worst, ((PL.ang[j] as Vector3) - (PF.ang[j] as Vector3)).length())
						away = maxf(away, ((B.ang[j] as Vector3) - (PF.ang[j] as Vector3)).length())
				var L1: Dictionary = r["layers"][0]
				var wk1: Array = L1["wk"]
				var fw := 0.0
				var fj := ""
				var lw := 0.0
				var lj := ""
				for k in wk1:
					var PL := Body.new()
					PL.load_files("res://data/skeleton.json", "res://data/body_limits.json")
					S.apply(PL, float(k[0]))
					var PF := Body.new()
					PF.load_files("res://data/skeleton.json", "res://data/body_limits.json")
					F.apply(PF, float(k[0]))
					for j in PL.ang:
						var e := ((PL.ang[j] as Vector3) - (PF.ang[j] as Vector3)).length()
						if L1["v"].has(j) and e > lw:   # (the offset is no joint: PL.ang has none)
							lw = e
							lj = "%s at %.3f s" % [j, k[0]]
						if not L1["v"].has(j) and e > fw:
							fw = e
							fj = "%s at %.3f s" % [j, k[0]]
				var hl := 0.0
				var hb := 0.0
				for k in wk1:
					var PL := Body.new()
					PL.load_files("res://data/skeleton.json", "res://data/body_limits.json")
					S.apply(PL, float(k[0]))
					var PF := Body.new()
					PF.load_files("res://data/skeleton.json", "res://data/body_limits.json")
					F.apply(PF, float(k[0]))
					var keep3: Array = S.layers
					S.layers = []
					S.apply(B, float(k[0]))
					S.layers = keep3
					hl = maxf(hl, ((PL.P["head"] as Vector3) - (PF.P["head"] as Vector3)).length() * 100.0)
					hb = maxf(hb, ((B.P["head"] as Vector3) - (PF.P["head"] as Vector3)).length() * 100.0)
				print("     reported: the head over the window is at most %.1f cm from the fixed scene's with the layer, %.1f cm without; layer holds %s" % [hl, hb, L1["v"].keys()])
				print("     every frame of the window (%d, %.3f..%.3f s): the layer's joints worst %.4f deg (%s); joints it does not hold (the hips' position the fix also moved re-plants the legs) worst %.4f deg (%s)" % [wk1.size(), wk1[0][0], wk1[-1][0], lw, lj, fw, fj])
				ok(worst <= 0.5 and away > 0.5, "2 at each changed card's arrival the layered scene plays the fixed one: worst %.4f deg (bar 0.5); without the layer it is %.3f deg away" % [worst, away])
				var keep2: Array = S.layers
				S.layers = []
				var base := play(S, B)
				S.layers = keep2
				for L in S.layers:
					L["w"] = 0.0
				var w0 := var_to_str(play(S, B)) == var_to_str(base)
				var L0: Dictionary = S.layers[0]
				L0["w"] = 0.5
				var c0 := int(String(L0["name"]).get_slice(" c", 1)) - 1
				var jj: String = L0["v"].keys().filter(func(x): return x != "offset")[0]
				S.apply(B, float(ts[c0][1]))
				var half: Vector3 = B.ang[jj]
				L0["w"] = 0.0
				S.apply(B, float(ts[c0][1]))
				var none: Vector3 = B.ang[jj]
				var want: Vector3 = B.clamp_ang(jj, none + (L0["v"][jj] as Vector3) * 0.5)
				ok(w0 and (half - want).length() < 1e-3, "3 w 0 on the fix layers = the scene as it was, byte for byte at 30 times (%s); w 0.5 = half the change on %s (off %.5f deg)" % [w0, jj, (half - want).length()])
				for L in S.layers:
					L["w"] = 1.0
				var still := Rulebook.check(S, B).filter(func(x): return Fixer._same_finding(f, x))
				print("     reported: HEAD QUIET on card %d after the layer: %s" % [f["card"] + 1, "still found" if not still.is_empty() else "gone"])
			elif f["rule"] in ["TIP SPEED", "FIST SPEED"] and not timing_done:
				var S := load_scene(path)
				var r := LayerFix.make(f, S, B, sm)
				if String(r["msg"]).contains("not kept"):
					continue
				timing_done = true
				ok(not r["ok"] and r["layers"].is_empty() and String(r["msg"]).contains("timing"), "4 a %s fix on %s card %d is refused: %s" % [f["rule"], path.get_file(), f["card"] + 1, r["msg"]])
	ok(done and timing_done, "a HEAD QUIET layer case and a timing case were both found in the real scenes (%s, %s)" % [done, timing_done])
	print("LAYER FIX TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
