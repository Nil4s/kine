## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/graph_range_test.gd   (round 52, GATES GE5; a window)
## GRAPH EDITOR GE5 (scripts/part_keys.gd range_weight / set_range / clear_range; scripts/graph_editor.gd shape, _range_item).
## A made scene (never a file of Nick's), as graph_editor_test does.
##   1 RANGE, NOISE: a Noise on [1, 2] s with blend_in 0.5 changes NOTHING outside [1, 2] (every sampled time, bit for bit
##     against the same keys with no modifier); inside it the change is the full noise times the blend ramp (w = (t - 1) / 0.5,
##     linear, within 1e-6), full strength from 1.5 s on, and blend_out 0.25 ramps it down to 2 s
##   2 RANGE, FILE: the range is stored with the modifier only when set (to_file has no range fields without one); it survives
##     the save and the load; set_range / clear_range put it on and take it off
##   3 SHAPE, CHANNELS: 3 selected keys in 2 channels (bend keys 1, 2; side key 1) of one part reshape by the Shape tool
##     (scale_neighbor, f 0.5): exactly those 3 change, to the expected values, every other key of every channel is bit for bit
##     the same, and the Shape is ONE undo step (begin called once)
##   4 RANGE, MENU: the Mods menu's range items (start / end at the playhead, blend, clear) set and clear the last modifier's
##     range, one undo step each
extends SceneTree

var fails := 0
var m: Node
var ge: GraphEditor


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func same(a: Vector3, b: Vector3) -> bool:   # bit for bit (Vector3 == is approximate in Godot)
	return a.x == b.x and a.y == b.y and a.z == b.z


func near3(a: Vector3, b: Vector3, tol := 1e-6) -> bool:
	return absf(a.x - b.x) <= tol and absf(a.y - b.y) <= tol and absf(a.z - b.z) <= tol


func noise_keys(mod: Dictionary) -> Array:
	var ks := [{"t": 0.0, "v": Vector3(10, 0, 0)}, {"t": 1.0, "v": Vector3(40, 20, -5)}, {"t": 3.0, "v": Vector3(-10, 5, 8)}]
	if not mod.is_empty():
		ks[0]["mods"] = [mod.duplicate()]
	return ks


func _init() -> void:
	# ---- 1 RANGE on noise (pure part keys)
	var base_mod := {"type": "noise", "ch": -1, "strength": 6.0, "scale": 0.3, "phase": 0.0, "seed": 5, "mix": 1.0}
	var bare := noise_keys({})
	var full := noise_keys(base_mod)
	var rm := base_mod.duplicate()
	rm["range_start"] = 1.0
	rm["range_end"] = 2.0
	rm["blend_in"] = 0.5
	var ranged := noise_keys(rm)
	var outside_bad := 0
	var n_out := 0
	var tt := [0.0, 0.25, 0.999, 0.9999, 2.0001, 2.001, 2.5, 3.0]
	for i in 301:
		tt.append(3.0 * float(i) / 300.0)
	for t in tt:
		if t < 1.0 or t > 2.0:
			n_out += 1
			if not same(PartKeys.value_at(ranged, t), PartKeys.value_at(bare, t)):
				outside_bad += 1
	ok(outside_bad == 0 and n_out > 200, "1a outside [1, 2] s the ranged noise is the bare keys, bit for bit: %d times checked, %d differ" % [n_out, outside_bad])
	var inside_diff := (PartKeys.value_at(full, 1.6) - PartKeys.value_at(bare, 1.6)).length()
	ok(inside_diff > 0.5, "1b the noise is really there (unranged, at 1.6 s it moves the curve by %.2f deg)" % inside_diff)
	var ramp_bad := 0.0
	var ramp_pts := []
	for t in [1.0, 1.1, 1.25, 1.4, 1.5, 1.75, 2.0]:
		var base := PartKeys.at(bare, t)
		var want := PartKeys.value_at(full, t) - base
		var got := PartKeys.value_at(ranged, t) - base
		var w := clampf((t - 1.0) / 0.5, 0.0, 1.0) if t <= 2.0 else 0.0
		ramp_bad = maxf(ramp_bad, (got - want * w).length())
		ramp_pts.append(snappedf(t, 0.01))
	ok(ramp_bad < 1e-4, "1c blend in: the change is the full noise times (t - 1) / 0.5, linear, at %s s; worst error %.9f deg (bar 0.0001: float32 on ~50 deg values; the noise is ~1.9 deg)" % [ramp_pts, ramp_bad])
	var rb := base_mod.duplicate()
	rb["range_start"] = 1.0
	rb["range_end"] = 2.0
	rb["blend_out"] = 0.25
	var out_keys := noise_keys(rb)
	var wo := absf(PartKeys.value_at(out_keys, 1.9)[0] - PartKeys.at(bare, 1.9)[0])
	var wf := absf(PartKeys.value_at(full, 1.9)[0] - PartKeys.at(bare, 1.9)[0])
	ok(absf(wo - 0.4 * wf) < 1e-6, "1d blend out: at 1.9 s with 0.25 s out the change is 0.4 of the full noise (%.4f of %.4f)" % [wo, wf])

	# ---- 2 RANGE stored / loaded / set / cleared
	var pk := {"upperarm_r": noise_keys(rm)}
	var saved := PartKeys.to_file(pk)
	var mods_saved: Array = saved["upperarm_r"][0]["mods"]
	ok(mods_saved[0].has("range_start") and mods_saved[0].has("range_end") and mods_saved[0].has("blend_in") and not mods_saved[0].has("blend_out"), "2a the file keeps the range and writes only the blend that is set: %s" % [mods_saved[0]])
	var bare_saved := PartKeys.to_file({"upperarm_r": noise_keys(base_mod)})
	ok(not (bare_saved["upperarm_r"][0]["mods"][0] as Dictionary).has("range_start"), "2b a modifier with no range is written with no range fields")
	var back := PartKeys.from_file(saved)
	var rk: Array = back["upperarm_r"]
	var rmb: Dictionary = PartKeys.mods_of(rk)[0]
	ok(absf(float(rmb["range_start"]) - 1.0) < 1e-9 and absf(float(rmb["range_end"]) - 2.0) < 1e-9 and absf(float(rmb["blend_in"]) - 0.5) < 1e-9, "2c loaded back: range 1..2, blend in 0.5")
	var pk2 := {"upperarm_r": noise_keys(base_mod)}
	ok(PartKeys.set_range(pk2, "upperarm_r", 0, 1.0, 2.0, 0.5, 0.0), "2d set_range accepts the stack's first modifier")
	ok(PartKeys.set_range(pk2, "upperarm_r", 0, 1.0, 2.0, 0.5, 0.0) and near3(PartKeys.value_at(pk2["upperarm_r"], 1.4), PartKeys.at(bare, 1.4) + (PartKeys.value_at(full, 1.4) - PartKeys.at(bare, 1.4)) * 0.8), "2e set_range: the stack reads the range (blend 0.5 at 1.4 s is 0.8 of the noise)")
	PartKeys.clear_range(pk2, "upperarm_r", 0)
	ok(not (PartKeys.mods_of(pk2["upperarm_r"])[0] as Dictionary).has("range_start") and same(PartKeys.value_at(pk2["upperarm_r"], 1.4), PartKeys.value_at(full, 1.4)), "2f clear_range: no range fields left and the noise is everywhere again")

	# ---- 3 & 4 need the editor: a made scene in main, as graph_editor_test does
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var B0 := Body.new()
	B0.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B0.fk()
	var S := Scene.new()
	S.name = "zz_graph_range"
	S.fps = 24
	for n in ["a", "b", "c", "d", "e", "f"]:
		S.add(n, B0.to_dict())
	for c in S.cards:
		c["move"] = 0.6
		c["hold"] = 0.0
	S.part_keys = {
		"upperarm_r": [{"t": 0.2, "v": Vector3(60, 30, 0)}, {"t": 0.6, "v": Vector3(90, 45, 10)}, {"t": 1.0, "v": Vector3(70, 35, 5)}],
		"upperarm_l": [{"t": 0.0, "v": Vector3(-40, 15, -10)}, {"t": 0.5, "v": Vector3(-20, 20, -5)}, {"t": 1.2, "v": Vector3(-30, 18, -15)}]}
	m.S = S
	m._rebuild_cards()
	m.sel = "upperarm_r"
	m.sel_card = 0
	m.playhead = 0.5
	m._refresh()
	await idle(2)
	for c in m._commands():
		if c["id"] == "graph_editor_every_keyed_part_channels":
			c["run"].call()
	await idle(4)
	ge = m.ui_curve as GraphEditor
	ok(ge != null and ge.multi and ge.chans().size() == 6, "0 the channels view is open with 6 channels")

	# ---- 3 SHAPE on 3 selected keys in 2 channels
	var before_keys := {}
	for j in S.part_keys:
		before_keys[j] = []
		for k in S.part_keys[j]:
			before_keys[j].append({"t": k["t"], "v": k["v"]})
	ge.msel = [["upperarm_r", 0, 1], ["upperarm_r", 0, 2], ["upperarm_r", 1, 1]]
	var begins := [0]
	var old_begin: Callable = ge.begin
	ge.begin = func():
		begins[0] += 1
		old_begin.call()
	var r: Dictionary = ge.shape("scale_neighbor", 0.5)
	ge.begin = old_begin
	var ur: Array = S.part_keys["upperarm_r"]
	var moved := []
	for j in S.part_keys:
		for i in (S.part_keys[j] as Array).size():
			for c in 3:
				var was: float = (before_keys[j][i]["v"] as Vector3)[c]
				var now: float = (S.part_keys[j][i]["v"] as Vector3)[c]
				if was != now:
					moved.append("%s:%d:%d" % [j, i, c])
	var want := ["upperarm_r:1:0", "upperarm_r:2:0", "upperarm_r:1:1"]
	moved.sort()
	want.sort()
	ok(moved == want, "3a exactly the 3 selected dots changed: %s (want %s)" % [moved, want])
	ok(absf((ur[1]["v"] as Vector3).x - 75.0) < 1e-6 and absf((ur[2]["v"] as Vector3).x - 65.0) < 1e-6 and absf((ur[1]["v"] as Vector3).y - 37.5) < 1e-6, "3b the values are the scale about the left neighbour (bend 90 -> 75, 70 -> 65; side 45 -> 37.5)")
	ok(begins[0] == 1 and int(r["changed"]) == 3 and r["skipped"] == 0, "3c one undo step (begin called %d time), changed %d, skipped %d" % [begins[0], r["changed"], r["skipped"]])
	ok(ge.msel.size() == 3, "3d the selection is kept")

	# ---- 4 RANGE menu items on the picked part's last modifier
	S.part_keys["upperarm_r"] = [{"t": 0.2, "v": Vector3(60, 30, 0)}, {"t": 0.6, "v": Vector3(90, 45, 10)}, {"t": 1.0, "v": Vector3(70, 35, 5)}]
	ge.msel = []
	var base_id := GraphEditor.MOD_ITEMS.size()
	ge.mod_item(0)   # Add noise on every channel of the picked part
	m.playhead = 0.5
	ge.playhead = 0.5
	begins[0] = 0
	ge.begin = func():
		begins[0] += 1
		old_begin.call()
	var idx := ge.mod_item(base_id + 1)   # start at the playhead
	var md: Dictionary = PartKeys.mods_of(S.part_keys["upperarm_r"])[idx]
	ok(idx >= 0 and absf(float(md.get("range_start", -1.0)) - 0.5) < 1e-9 and absf(float(md.get("range_end", -1.0)) - 1.0) < 1e-9, "4a start at the playhead: range %s .. %s (the end defaults to the keyed span's last key)" % [md.get("range_start"), md.get("range_end")])
	ge.playhead = 0.8
	ge.mod_item(base_id + 2)   # end at the playhead
	ok(absf(float(md["range_end"]) - 0.8) < 1e-9, "4b end at the playhead: %s" % md["range_end"])
	ge.mod_item(base_id + 3)   # blend 0.25 s in and out
	ok(absf(float(md["blend_in"]) - 0.25) < 1e-9 and absf(float(md["blend_out"]) - 0.25) < 1e-9, "4c blend 0.25 s in and out")
	ge.mod_item(base_id + 4)   # clear
	ok(not md.has("range_start") and not md.has("range_end") and not md.has("blend_in") and not md.has("blend_out"), "4d clear: no range fields are left (none stored when not set)")
	ge.begin = old_begin
	ok(begins[0] == 4, "4e one undo step per range item (begin called %d times for 4)" % begins[0])

	print("GRAPH RANGE: %d failed" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
