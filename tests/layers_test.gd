## godot --headless --path . -s tests/layers_test.gd     (round 49, GATES NA1, UPGRADES_300 #254)
## SEVERAL LAYERS (Scene.layers, Maya's animation layers / Blender's NLA blending), on walk_bat (its own YY9 layer: none,
## so one is added: spine_02 +4 deg). Layer A additive {spine_03: (6, 3, 0)}, layer B override {spine_02: (12, 2, 5)}.
## Joints on the spine and head (the bat's grip re-solves the arms after any layer: a held weapon wins, YY9).
##   1 weight 0 and MUTE = the scene without the layer, byte for byte, at 30 times (each of A and B)
##   2 additive at w 0.5 = what plays below + 0.5 x offset (clamped by the joint's limits), 0.0001 deg, 30 times
##   3 override at w 0.5 and 1 = lerp(below, angle, w), 0.0001 deg, 30 times
##   4 SOLO B: plays exactly as a scene whose only layer is B (the YY9 layer and A silent)
##   5 KEYED weight on A ([0, 0], [L, 1]): at L/2 the weight is 0.5 and the joint = below + 0.5 x offset
##   6 LOCK: main's "Layer: keep this change" on a locked layer changes nothing and says LOCKED; unlocked, an override
##     take makes the scene play the body at the playhead (0.05 deg); one undo step brings the layers back
##   7 file: save -> load plays bit for bit the same; a scene with no further layer writes no "layers" key; Mirror
##     reflects each layer's angles to the twin joint (as Scene.mirror_layer does)
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func open() -> Scene:
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/walk_bat.json")))
	S.layer = {"spine_02": Vector3(4, 0, 0)}
	return S


func lay(name: String, mode: String, v: Dictionary) -> Dictionary:
	return {"name": name, "mode": mode, "w": 1.0, "wk": [], "mute": false, "solo": false, "lock": false, "v": v}


func play(S: Scene, B: Body) -> Array:
	var out := []
	for i in 30:
		S.apply(B, S.length() * i / 29.0)
		out.append(B.ang.duplicate())
	return out


func same(a: Array, b: Array) -> bool:
	return var_to_str(a) == var_to_str(b)


## worst |got - want| on joint j over the 30 times, where want = f(below angle, B)
func worst(got: Array, below: Array, j: String, B: Body, f: Callable) -> float:
	var w := 0.0
	for i in got.size():
		var want: Vector3 = B.clamp_ang(j, f.call(below[i][j] as Vector3))
		w = maxf(w, ((got[i][j] as Vector3) - want).length())
	return w


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var S := open()
	var A := lay("A", "add", {"spine_03": Vector3(6, 3, 0)})
	var Bl := lay("B", "over", {"spine_02": Vector3(12, 2, 5)})
	var base := play(S, B)   # the YY9 layer only
	# 1 weight 0 / mute
	var r := []
	for L in [A, Bl]:
		S.layers = [L]
		L["w"] = 0.0
		var z := same(play(S, B), base)
		L["w"] = 1.0
		var on := same(play(S, B), base)
		L["mute"] = true
		var mu := same(play(S, B), base)
		L["mute"] = false
		r.append([z, mu, on])
	S.layers = []
	ok(r == [[true, true, false], [true, true, false]], "1 each layer alone: [weight 0 = base, muted = base, at weight 1 it differs (control)] byte for byte at 30 times: %s" % [r])
	# 2 additive at 0.5
	A["w"] = 0.5
	S.layers = [A]
	var got := play(S, B)
	var wa := worst(got, base, "spine_03", B, func(x): return x + Vector3(6, 3, 0) * 0.5)
	ok(wa < 1e-4, "2 additive w 0.5: spine_03 = below + 0.5 x offset, worst %.6f deg over 30 times" % wa)
	A["w"] = 1.0
	# 3 override
	var wo := []
	for w in [0.5, 1.0]:
		Bl["w"] = w
		S.layers = [Bl]
		got = play(S, B)
		wo.append(worst(got, base, "spine_02", B, func(x): return x.lerp(Vector3(12, 2, 5), w)))
	var vac := worst(got, base, "spine_02", B, func(x): return x + Vector3(12, 2, 5))   # anti-vacuity: an ADD would differ
	ok(wo[0] < 1e-4 and wo[1] < 1e-4 and vac > 1.0, "3 override: spine_02 = lerp(below, (12,2,5), w), worst %.6f (w 0.5) / %.6f (w 1) deg; an add would be off by %.2f deg (below varies: %s..)" % [wo[0], wo[1], vac, base[0]["spine_02"]])
	Bl["w"] = 1.0
	# 4 solo
	S.layers = [A, Bl]
	Bl["solo"] = true
	var solo := play(S, B)
	Bl["solo"] = false
	var keep_l := S.layer
	S.layer = {}
	S.layers = [Bl]
	var only_b := play(S, B)
	S.layer = keep_l
	ok(same(solo, only_b), "4 SOLO B plays exactly as a scene whose only layer is B (the first layer and A silent)")
	# 5 keyed weight
	var L := S.length()
	A["wk"] = [[0.0, 0.0], [L, 1.0]]
	S.layers = [A]
	S.apply(B, L * 0.5)
	var at: Vector3 = B.ang["spine_03"]
	S.layers = []
	S.apply(B, L * 0.5)
	var want: Vector3 = B.clamp_ang("spine_03", (B.ang["spine_03"] as Vector3) + Vector3(6, 3, 0) * 0.5)
	ok(absf(Scene.layer_weight(A, L * 0.5) - 0.5) < 1e-6 and (at - want).length() < 1e-4, "5 keyed weight [0,0]..[L,1]: weight %.4f at L/2, spine_03 off by %.6f deg" % [Scene.layer_weight(A, L * 0.5), (at - want).length()])
	A["wk"] = []
	# 6 lock + take, through main
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 6:
		await process_frame
	var S2 := open()
	S2.name = "zz_layers"
	S2.layers = [lay("Over", "over", {})]
	m.S = S2
	m._rebuild_cards()
	m.layer_on = 0
	m.playhead = S2.length() * 0.4
	m._ps().apply(m.B, m.playhead)
	m.B.ang["spine_02"] = (m.B.ang["spine_02"] as Vector3) + Vector3(8, 0, 4)
	m.B.fk()
	var want_head: Vector3 = m.B.ang["spine_02"]
	S2.layers[0]["lock"] = true
	var before := var_to_str(S2.layers)
	m._do(m._layer_take)
	var said: String = m.ui_status.text
	var locked_ok: bool = var_to_str(S2.layers) == before and said.contains("LOCKED")
	S2.layers[0]["lock"] = false
	S2.layers[0]["w"] = 0.5
	var u0: int = m.undo.size()
	m.B.ang["spine_02"] = want_head
	m.B.fk()
	m._do(m._layer_take)
	var PB := Body.new()
	PB.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	S2.apply(PB, m.playhead)
	var off := ((PB.ang["spine_02"] as Vector3) - want_head).length()
	m._undo()
	var back: bool = (S2.layers[0]["v"] as Dictionary).is_empty()
	ok(locked_ok and off < 0.05 and back, "6 locked: unchanged and said LOCKED %s; unlocked override take at w 0.5 plays the posed spine_02 within %.4f deg; Ctrl+Z empties it again %s" % [locked_ok, off, back])
	m.queue_free()
	# 7 file
	S.layers = [A, Bl]
	Bl["wk"] = [[0.1, 0.25], [0.5, 1.0]]
	Bl["mute"] = false
	A["solo"] = false
	var d := S.to_dict(B)
	var S3 := Scene.new()
	S3.from_dict(JSON.parse_string(JSON.stringify(d)))
	var rt := same(play(S, B), play(S3, B))
	S.layers = []
	var none: bool = not S.to_dict(B).has("layers")
	var M := Body.new()
	M.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var mir := Scene.mirror_layer({"spine_03": [6, 3, 0]}, M)
	ok(rt and none and Scene.MIRROR_SCENE.has("layers") and mir.has("spine_03"), "7 save/load plays bit for bit the same %s; no further layer writes no \"layers\" %s; Mirror's list names \"layers\"" % [rt, none])
	print("LAYERS TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
