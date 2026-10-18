## godot --headless --path . -s tests/layer_merge_test.gd     (round 49, GATES NA3, UPGRADES_300 #256)
## MERGE DOWN (scripts/layer_merge.gd) on walk_bat with three layers: the YY9 first layer (spine_02 +4), an additive
## {spine_03 (6, 3, 0)} and an override {head (10, -6, 0)} at weight 0.5.
##   1 after the merge, at every card's arrival the scene (no layers now) plays what the layered one did: worst <= 0.5 deg
##     on every joint; the layers are gone; anti-vacuity: just deleting the layers misses by > 0.5 deg there
##   2 every frame: the worst miss is printed with where (the tolerance), and the bar the registration gave it: printed
##   3 a KEYED weight (0 at the start, 1 at the end): the arrivals still within 0.5; the every-frame number printed
##   4 through main: "Layer: merge down (into the cards)" is one undo step; Ctrl+Z gives the cards and layers back byte
##     for byte; a locked layer refuses (said LOCKED, nothing changed)
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
	S.layers = [{"name": "A", "mode": "add", "w": 1.0, "wk": [], "mute": false, "solo": false, "lock": false, "v": {"spine_03": Vector3(6, 3, 0)}},
		{"name": "B", "mode": "over", "w": 0.5, "wk": [], "mute": false, "solo": false, "lock": false, "v": {"head": Vector3(10, -6, 0)}}]
	return S


func at_arrivals(S: Scene, B: Body) -> Array:
	var out := []
	for x in S.times():
		S.apply(B, float(x[1]))
		out.append(B.ang.duplicate())
	return out


func worst(a: Array, b: Array) -> float:
	var w := 0.0
	for i in a.size():
		for j in a[i]:
			w = maxf(w, ((a[i][j] as Vector3) - (b[i][j] as Vector3)).length())
	return w


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	# 1 + 2
	var S := open()
	var want := at_arrivals(S, B)
	var D := open()
	D.layer = {}
	D.layers = []
	var dropped := worst(want, at_arrivals(D, B))
	var r := LayerMerge.merge(S)
	var got := at_arrivals(S, B)
	var w := worst(want, got)
	ok(w <= 0.5 and dropped > 0.5 and S.layer.is_empty() and S.layers.is_empty(), "1 merged: at the %d arrivals worst %.4f deg (bar 0.5) after %d passes, %d cards re-posed; deleting the layers instead misses by %.3f; layers gone" % [want.size(), w, r["iters"], r["cards"], dropped])
	print("     2 every frame: the merged scene within %.4f deg of the layered one (%s)" % [r["every_frame"], r["frame_at"]])
	# 3 keyed weight
	var K := open()
	K.layers[0]["wk"] = [[0.0, 0.0], [K.length(), 1.0]]
	var want_k := at_arrivals(K, B)
	var rk := LayerMerge.merge(K)
	var wk := worst(want_k, at_arrivals(K, B))
	ok(wk <= 0.5, "3 a keyed weight 0 -> 1: at the arrivals worst %.4f deg (%d passes); every frame within %.4f deg (%s)" % [wk, rk["iters"], rk["every_frame"], rk["frame_at"]])
	# 4 main
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 6:
		await process_frame
	var S2 := open()
	S2.name = "zz_layer_merge"
	m.S = S2
	m._rebuild_cards()
	var cmd := {}
	for c in m._commands():
		if c["id"] == "layer_merge_down_into_the_cards":
			cmd = c
	S2.layers[1]["lock"] = true
	var before := JSON.stringify(S2.to_dict(m.ov.GB))
	var u0: int = m.undo.size()
	if not cmd.is_empty():
		cmd["run"].call()
	var said: String = m.ui_status.text
	var locked_ok: bool = said.contains("LOCKED") and m.undo.size() == u0 and JSON.stringify(S2.to_dict(m.ov.GB)) == before
	S2.layers[1]["lock"] = false
	before = JSON.stringify(S2.to_dict(m.ov.GB))
	if not cmd.is_empty():
		cmd["run"].call()
	var merged: bool = S2.layers.is_empty() and m.undo.size() == u0 + 1
	m._undo()
	var back := JSON.stringify(S2.to_dict(m.ov.GB)) == before
	ok(not cmd.is_empty() and locked_ok and merged and back, "4 the command (found %s): locked refuses %s; merges in one undo step %s; Ctrl+Z gives cards and layers back byte for byte %s" % [not cmd.is_empty(), locked_ok, merged, back])
	m.queue_free()
	print("LAYER MERGE TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
