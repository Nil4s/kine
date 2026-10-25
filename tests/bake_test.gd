## godot --headless --path . -s tests/bake_test.gd     (round 48, GATES DD4, UPGRADES_300 #250)
## BAKE (scripts/bake.gd): the scene's cards + part keys + modifier stacks flattened into cards at a rate.
##   1 a made scene: 3 cards (different arms), part keys on the right forearm with a limits AND a noise modifier, the floor
##     and pins on. Baked at its own fps: played through Scene.apply (the floor, pins and all) at every frame, every joint
##     of the baked scene within 0.5 deg of the original (bar), the hips' offset within 1 mm; the part keys are gone, the
##     card count is ceil(length x rate) + 1, the length the same within 1 ms
##   2 the same at 10 cards a second: reported (between the cards a straight line stands in for the curve), not barred
##   3 Nick's swing_fore (read from scenes/, never written) given the same part keys and baked at its fps: within 0.5 deg
##     at every frame (bar): the floor and pins act on the baked cards as on the original
##   4 the baked file has no "part_keys" and saves / loads to the same play (within the file's 0.01 deg)
##   5 the command: "Bake to cards" in the registry bakes the open scene in ONE undo step and says what it turned off;
##     Ctrl+Z gives the cards, the part keys and the floor / pin switches back (the saved scene byte for byte)
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func keyed(S: Scene) -> void:
	S.part_keys = {"lowerarm_r": [
		{"t": 0.0, "v": Vector3(20, 0, 0)}, {"t": 0.4, "v": Vector3(95, 3, -10)}, {"t": 0.9, "v": Vector3(40, 0, 5)}]}
	PartKeys.add_mod(S.part_keys, "lowerarm_r", {"type": "limits", "ch": 0, "min": 25.0, "max": 85.0, "mix": 1.0})
	PartKeys.add_mod(S.part_keys, "lowerarm_r", {"type": "noise", "ch": -1, "strength": 6.0, "scale": 0.2, "seed": 3, "mix": 1.0})


## every frame through Scene.apply: [[{joint: Vector3}, offset], ...]
func play(S: Scene, B: Body) -> Array:
	var out := []
	var n := int(ceilf(S.length() * S.fps))
	for f in n + 1:
		S.apply(B, minf(float(f) / S.fps, S.length()))
		out.append([B.ang.duplicate(), B.offset])
	return out


func worst(a: Array, b: Array) -> Array:
	var wa := 0.0
	var wj := ""
	var wo := 0.0
	for f in mini(a.size(), b.size()):
		for j in a[f][0]:
			var d: float = ((a[f][0][j] as Vector3) - (b[f][0][j] as Vector3)).abs()[((a[f][0][j] as Vector3) - (b[f][0][j] as Vector3)).abs().max_axis_index()]
			if d > wa:
				wa = d
				wj = "%s @ frame %d" % [j, f]
		wo = maxf(wo, ((a[f][1] as Vector3) - (b[f][1] as Vector3)).length())
	return [wa, wj, wo]


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	# 1 a made scene
	var S := Scene.new()
	S.name = "zz_bake"
	S.fps = 30
	var a := B.to_dict()
	B.ang["upperarm_r"] = Vector3(40, 30, 0)
	B.ang["upperarm_l"] = Vector3(-20, 10, 0)
	B.fk()
	var b := B.to_dict()
	B.ang["upperarm_r"] = Vector3(-10, 60, 20)
	B.fk()
	var c := B.to_dict()
	S.add("a", a)
	S.add("b", b)
	S.add("c", c)
	S.cards[1]["move"] = 0.45
	S.cards[2]["move"] = 0.4
	keyed(S)
	var orig := play(S, B)
	var L0 := S.length()
	var S1 := S.clone()
	var r := Bake.bake(S1, B, S.fps)
	var w := worst(orig, play(S1, B))
	var want_n := int(ceilf(L0 * S.fps - 1e-6)) + 1
	ok(float(w[0]) <= 0.5 and float(w[2]) <= 0.001 and S1.part_keys.is_empty() and r["cards"] == want_n and absf(S1.length() - L0) < 0.001,
		"1 baked at %d fps: %d cards (want %d) from %d; worst joint %.4f deg (%s; bar 0.5), hips %.5f m (bar 0.001); part keys left %d; length %.3f vs %.3f s" % [S.fps, r["cards"], want_n, r["was"], w[0], w[1], w[2], S1.part_keys.size(), S1.length(), L0])
	# 2 a lower rate
	var S2 := S.clone()
	Bake.bake(S2, B, 10.0)
	var w2 := worst(orig, play(S2, B))
	print("     2 baked at 10 cards/s: %d cards, worst joint %.3f deg (%s), hips %.4f m (reported, not barred)" % [S2.cards.size(), w2[0], w2[1], w2[2]])
	# 3 Nick's swing_fore
	var sf := Scene.new()
	sf.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/swing_fore.json")))
	keyed(sf)
	var o3 := play(sf, B)
	var sf1 := sf.clone()
	var r3 := Bake.bake(sf1, B, sf.fps)
	var w3 := worst(o3, play(sf1, B))
	ok(float(w3[0]) <= 0.5, "3 Nick's swing_fore (pin %s, floor %s) + the same part keys, baked at %d fps (%d cards): worst joint %.4f deg (%s; bar 0.5), hips %.5f m; turned off: %s" % [sf.pin, sf.on_floor, sf.fps, sf1.cards.size(), w3[0], w3[1], w3[2], r3["off"]])
	# 4 file
	var txt := JSON.stringify(S1.to_dict(B))
	var S4 := Scene.new()
	S4.from_dict(JSON.parse_string(txt))
	var w4 := worst(play(S1, B), play(S4, B))
	ok(not txt.contains("\"part_keys\"") and float(w4[0]) <= 0.05, "4 the baked file: 'part_keys' in it %s; saved and loaded it plays within %.4f deg of itself (bar 0.05: the file keeps 0.01)" % [txt.contains("\"part_keys\""), w4[0]])
	# 5 the command
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 6:
		await process_frame
	m.tour_step = -1
	var S5 := S.clone()
	m.S = S5
	m._rebuild_cards()
	m._refresh()
	var before := JSON.stringify(S5.to_dict(m.B))
	var u0: int = m.undo.size()
	for cmd in m._commands():
		if cmd["id"] == "bake_to_cards":
			cmd["run"].call()
	var said: String = m.ui_status.text if m.get("ui_status") != null else ""
	var baked_ok: bool = S5.cards.size() == want_n and S5.part_keys.is_empty() and not S5.pin and not S5.on_floor
	var one: bool = m.undo.size() == u0 + 1
	m._undo()
	var back := JSON.stringify(S5.to_dict(m.B)) == before
	ok(baked_ok and one and back, "5 'Bake to cards' from the registry: %d cards, keys gone, pin / floor off %s; one undo step %s; Ctrl+Z gives the scene back byte for byte %s (pin %s, floor %s, %d cards, keys on %d parts). Said: %s" % [S5.cards.size() if not back else want_n, baked_ok, one, back, S5.pin, S5.on_floor, S5.cards.size(), S5.part_keys.size(), said.left(160)])
	m.queue_free()
	print("BAKE TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
