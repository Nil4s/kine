## godot --headless --path . -s tests/layer_test.gd     (round 43, GATES YY9)
## ONE ADDITIVE LAYER over a whole scene (Scene.layer / layer_w / add_layer). Bars:
##   1 weight 0 = the scene byte for byte: 30 times of walk_bat play to the same angles as with no layer, and a scene
##     without a layer saves with no "layer" key (every scenes/*.json loads with none).
##   2 weight 1 = base + offset per joint: at 30 times every layered joint is the cards' angle + its offset (1e-4, where
##     the sum is inside the joint's limits; the cases at a limit are counted and printed), the legs unchanged (the arms re-grip the
##     bat after the layer: a held weapon wins).
##   3 weight 0.5 = base + half the offset (same check).
##   4 the cards are never written: walk_bat's cards are identical before and after playing with the layer.
##   5 save / load: to_dict -> JSON -> from_dict gives the same layer and weight, and plays bit for bit the same.
##   6 Mirror's list: the mirrored layer is what Body.mirror_pose makes of the same angles (0.02 deg), on the twin joint.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func open() -> Scene:
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/walk_bat.json")))
	return S


func play(S: Scene, B: Body) -> Array:
	var out := []
	for i in 30:
		S.apply(B, S.length() * i / 29.0)
		out.append(B.ang.duplicate())
	return out


func check_w(S: Scene, B: Body, base: Array, w: float) -> Array:
	S.layer_w = w
	var got := play(S, B)
	var worst := 0.0
	var at_limit := 0
	var others := true
	for i in 30:
		for j in base[i]:
			if S.layer.has(j):
				var want: Vector3 = (base[i][j] as Vector3) + (S.layer[j] as Vector3) * w
				if B.clamp_ang(j, want) != want:
					at_limit += 1
					continue
				worst = maxf(worst, ((got[i][j] as Vector3) - want).length())
			elif j.begins_with("thigh") or j.begins_with("calf") or j.begins_with("foot") or j.begins_with("ball"):   # the legs (the arms re-grip the bat)
				others = others and got[i][j] == base[i][j]
	return [worst, at_limit, others]


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var S := open()
	var cards0 := JSON.stringify(S.cards)
	var base := play(S, B)
	S.layer = {"spine_02": Vector3(8, 0, 0), "spine_03": Vector3(6, 0, 3), "head": Vector3(-5, 4, 0), "neck_01": Vector3(0, 0, 10)}
	S.layer_w = 0.0
	var w0 := play(S, B)
	var none := []
	var n := 0
	for f in DirAccess.get_files_at("res://scenes"):
		if f.ends_with(".json"):
			var d = JSON.parse_string(FileAccess.get_file_as_string("res://scenes/" + f))
			if d is Dictionary and d.has("cards"):
				var X := Scene.new()
				X.from_dict(d)
				n += 1
				if not X.layer.is_empty() or d.has("layer") or X.to_dict(B).has("layer"):
					none.append(f)
	ok(w0 == base and none.is_empty() and n > 5, "1 weight 0: 30 times byte for byte %s; %d scenes load and save with no layer %s" % [w0 == base, n, none])
	var r1 := check_w(S, B, base, 1.0)
	ok(r1[0] < 1e-4 and r1[2], "2 weight 1: layered joints = cards + offset, worst %.6f deg (%d joint-times at a limit, skipped); the rest unchanged %s" % r1)
	var r5 := check_w(S, B, base, 0.5)
	ok(r5[0] < 1e-4 and r5[2], "3 weight 0.5: cards + half the offset, worst %.6f deg (%d at a limit); the rest unchanged %s" % r5)
	ok(JSON.stringify(S.cards) == cards0, "4 the cards are never written by the layer")
	S.layer_w = 0.75
	var a := play(S, B)
	var d2 := S.to_dict(B)
	var S2 := Scene.new()
	S2.from_dict(JSON.parse_string(JSON.stringify(d2)))
	var b := play(S2, B)
	ok(S2.layer == S.layer and S2.layer_w == 0.75 and a == b and d2.has("layer") and d2.has("layer_w"),
		"5 save / load: layer %s weight %.2f, plays the same %s" % [S2.layer, S2.layer_w, a == b])
	var M := Body.new()
	M.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var mir := Scene.mirror_layer({"upperarm_r": [10, 20, 30], "spine_03": [5, 6, 7]}, M)
	var ua: Array = mir.get("upperarm_l", [])
	var sp: Array = mir.get("spine_03", [])
	# the reference: what Body.mirror_pose (Mirror's own card rule) makes of the same angles on a resting body
	var R := Body.new()
	R.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	R.ang["upperarm_r"] = Vector3(10, 20, 30)
	R.ang["spine_03"] = Vector3(5, 6, 7)
	R.fk()
	R.mirror_pose()
	var flip := func(x: Array, y: Vector3) -> bool:
		return x.size() == 3 and absf(float(x[0]) - y.x) < 0.02 and absf(float(x[1]) - y.y) < 0.02 and absf(float(x[2]) - y.z) < 0.02
	ok(Scene.MIRROR_SCENE.has("layer") and Scene.MIRROR_SCENE.has("layer_w") and flip.call(ua, R.ang["upperarm_l"]) and flip.call(sp, R.ang["spine_03"]) and not mir.has("upperarm_r"),
		"6 Mirror: upperarm_r (10, 20, 30) -> upperarm_l %s (mirror_pose: %s); spine_03 (5, 6, 7) -> %s (%s)" % [ua, R.ang["upperarm_l"], sp, R.ang["spine_03"]])
	print("LAYER TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
