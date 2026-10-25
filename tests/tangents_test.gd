## godot --path . -s tests/tangents_test.gd     (ROADMAP 65: TANGENT WEIGHTS in the graph editor; needs a window: real mouse events)
## Part keys (scripts/part_keys.gd) get per-key in / out tangent handles with an ANGLE and a LENGTH (the weight: how long
## the curve keeps its slope), dragged in the curve editor (scripts/curve_editor.gd); Unify / Break buttons. Weighted cubic
## Bezier in time: x(u) is solved for the time asked, and both inner control points sit inside the key interval.
## BARS (stated before measuring):
##   1 DEFAULT: combo3 sampled at every frame (141) with a part's keys on the default / vector / auto / free(file) paths:
##     the hash of every float32 equals the one recorded on the code before this round (bit for bit)
##   2 WEIGHT: keys (0 s, 0 deg) -> (1 s, 40 deg), flat start slope. Out-handle 0.9 s long vs 0.1 s: the value at 25 % of
##     the interval is lower with the long one (it keeps the flat start longer): v_long < v_default < v_short, each gap >= 0.5 deg
##   3 MONOTONE IN TIME: for short, default, long and crossing (both 0.9 s) handles, x(u) strictly increasing on 1001 samples
##   4 UNIFY / BREAK: unified, the slope just before the key equals the slope just after (|diff| < 6 deg/s on a 2 ms step);
##     broken with out slope 200 and in slope 0 deg/s, the difference is >= 150 deg/s
##   5 DRAG: a real mouse drag of a handle's end to (+0.2 s, -20 deg) sets the out handle to that within one frame / 1.5 px of
##     degrees; the key turns aligned (in slope == out slope); ONE undo step; Ctrl+Z restores the keys exactly
##   6 FILE: default keys save with no handle field; after the drag the file holds hin / hout; saved-and-loaded samples differ
##     < 0.2 deg; mirror (twin, then back) returns the handle lengths and the angles within 0.05
extends SceneTree

const BASELINE := "1859f6b4b7a64dadc972a73f6737a4fb1afc56b5b7d7e8f9e7fc7a95ad10fcc5"
var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func mouse(p: Vector2, down: bool, motion := false, held := false) -> void:
	var e: InputEvent
	if motion:
		var mm := InputEventMouseMotion.new()
		mm.position = p
		mm.global_position = p
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
		e = mm
	else:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = down
		mb.position = p
		mb.global_position = p
		if down:
			mb.button_mask = MOUSE_BUTTON_MASK_LEFT
		e = mb
	root.push_input(e)
	await process_frame


func click_at(p: Vector2) -> void:
	await mouse(p, true)
	await mouse(p, false)
	await idle(2)


func drag(a: Vector2, b: Vector2) -> void:
	await mouse(a, true)
	for i in range(1, 6):
		await mouse(a.lerp(b, float(i) / 5.0), false, true, true)
	await mouse(b, false)
	await idle(2)


func K2(v1: float) -> Dictionary:
	return {"j": [{"t": 0.0, "v": Vector3(0, 0, 0)}, {"t": 1.0, "v": Vector3(v1, 0, 0)}]}


## out handle of key 0 flat (slope 0) with this length; the in handle of key 1 too when in_len > 0
func weighted(len: float, in_len := -1.0) -> Dictionary:
	var pk := K2(40.0)
	PartKeys.set_tangent(pk, "j", 0, "out", 0, len, 0.0)
	if in_len > 0.0:
		PartKeys.set_tangent(pk, "j", 1, "in", 0, in_len, 0.0)
	return pk


func slope_pair(pk: Dictionary, idx: int) -> Array:
	var ks: Array = pk["j"]
	var t: float = ks[idx]["t"]
	var e := 2e-3
	var v0: float = PartKeys.at(ks, t)[0]
	return [(v0 - PartKeys.at(ks, t - e)[0]) / e, (PartKeys.at(ks, t + e)[0] - v0) / e]


func three() -> Dictionary:
	return {"j": [{"t": 0.0, "v": Vector3(0, 0, 0)}, {"t": 1.0, "v": Vector3(50, 0, 0)}, {"t": 2.0, "v": Vector3(0, 0, 0)}]}


func _init() -> void:
	# ---- 1 DEFAULT
	var S1 := Scene.new()
	S1.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json")))
	var T: float = S1.times()[-1][2]
	S1.part_keys = {"lowerarm_r": [
		{"t": 0.0, "v": Vector3(10, 0, 0)},
		{"t": 0.4, "v": Vector3(70, 5, -3), "handle": "vector"},
		{"t": 0.9, "v": Vector3(30, 9, 2), "handle": "auto"},
		{"t": 1.5, "v": Vector3(60, -4, 8), "handle": "free", "hin": Vector4(-0.2, 3, 1, 0), "hout": Vector4(0.3, -9, 2, 1)},
		{"t": 2.2, "v": Vector3(20, 0, 0), "interp": "linear"}]}
	var acc := PackedFloat32Array()
	var n := int(T * S1.fps) + 1
	for f in n:
		var s := S1.sample(float(f) / S1.fps)
		var names: Array = (s["ang"] as Dictionary).keys()
		names.sort()
		for j in names:
			var v: Vector3 = s["ang"][j]
			acc.append(v.x)
			acc.append(v.y)
			acc.append(v.z)
		var o: Vector3 = s["offset"]
		acc.append(o.x)
		acc.append(o.y)
		acc.append(o.z)
	var hs: String = acc.to_byte_array().hex_encode().sha256_text()
	ok(n == 141 and hs == BASELINE, "1 combo3, %d frames, no tangent set: hash %s (recorded before this round %s)" % [n, hs.left(12), BASELINE.left(12)])

	# ---- 2 WEIGHT
	var tq := 0.25
	var vs: float = PartKeys.at(weighted(0.1)["j"], tq)[0]
	var vd: float = PartKeys.at(K2(40.0)["j"], tq)[0]
	var vl: float = PartKeys.at(weighted(0.9)["j"], tq)[0]
	ok(vl < vd - 0.5 and vd < vs - 0.5, "2 value at 25 %% of the interval: long handle %.3f < default %.3f < short %.3f deg (bar: each gap >= 0.5)" % [vl, vd, vs])
	var pa := K2(40.0)
	PartKeys.set_tangent(pa, "j", 0, "out", 0, 0.3, 30.0)
	var ho: Vector4 = PartKeys.handles_of(pa["j"], 0)[1]
	ok(absf(ho.x - 0.3) < 1e-6 and absf(ho.y - 30.0) < 1e-5 and pa["j"][0]["handle"] == "aligned", "  set by length 0.3 s, rise 30 deg: handle %s, key turned %s" % [str(ho), pa["j"][0]["handle"]])
	var clamp_pk := K2(40.0)
	PartKeys.set_tangent(clamp_pk, "j", 0, "out", 0, 5.0, 0.0)
	ok(absf(PartKeys.handles_of(clamp_pk["j"], 0)[1].x - 1.0) < 1e-6 and not PartKeys.set_tangent(clamp_pk, "j", 0, "in", 0, 0.2, 0.0), "  a length past the interval is held at the interval (1.0 s); the first key has no in handle (refused)")

	# ---- 3 MONOTONE
	var sets := {"short": weighted(0.05, 0.05), "default": K2(40.0), "long": weighted(0.9, 0.2), "crossing": weighted(0.9, 0.9)}
	for nm in sets:
		var ks: Array = sets[nm]["j"]
		var prev := -1.0
		var bad := 0
		var fin := true
		for i in 1001:
			var x := PartKeys.bezier_x(ks, 0, float(i) / 1000.0)
			if x <= prev:
				bad += 1
			prev = x
			fin = fin and is_finite(PartKeys.value_at(ks, float(i) / 1000.0)[0])
		ok(bad == 0 and fin, "3 %s handles: x(u) strictly increasing on 1001 samples (%d not), values finite" % [nm, bad])

	# ---- 4 UNIFY / BREAK
	var pu := three()
	PartKeys.unify(pu, "j", 1)
	PartKeys.set_tangent(pu, "j", 1, "out", 0, 0.4, 80.0)   # 200 deg/s
	var su := slope_pair(pu, 1)
	var hu: Array = PartKeys.handles_of(pu["j"], 1)
	var su_h := [hu[0].y / hu[0].x, hu[1].y / hu[1].x]
	ok(absf(su[0] - su[1]) < 6.0 and absf(su_h[0] - su_h[1]) < 1e-3 and absf(su_h[1] - 200.0) < 1e-2, "4 UNIFIED, out slope 200: slopes before / after the key %.1f / %.1f deg/s (bar |diff| < 6); handles %.2f / %.2f" % [su[0], su[1], su_h[0], su_h[1]])
	var pb := three()
	PartKeys.break_handles(pb, "j", 1)
	PartKeys.set_tangent(pb, "j", 1, "out", 0, 0.4, 80.0)
	PartKeys.set_tangent(pb, "j", 1, "in", 0, 0.4, 0.0)
	var sb := slope_pair(pb, 1)
	ok(pb["j"][1]["handle"] == "free" and absf(sb[0] - sb[1]) >= 150.0, "  BROKEN, out 200 / in 0: slopes %.1f / %.1f deg/s (bar |diff| >= 150)" % [sb[0], sb[1]])
	PartKeys.unify(pb, "j", 1)
	var sr := slope_pair(pb, 1)
	ok(pb["j"][1]["handle"] == "aligned" and absf(sr[0] - sr[1]) < 6.0, "  Unify again: the in handle turns to the out slope, %.1f / %.1f deg/s" % [sr[0], sr[1]])

	# ---- 5 DRAG in the curve editor (real mouse)
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
	S.name = "zz_tangents"
	S.add("a", B0.to_dict())
	S.add("b", B0.to_dict())
	S.cards[0]["move"] = 0.5
	S.cards[1]["move"] = 0.5
	m.S = S
	m._rebuild_cards()
	m.sel = "lowerarm_r"
	m.sel_card = 0
	S.part_keys = {"lowerarm_r": [{"t": 0.0, "v": Vector3(10, 0, 0)}, {"t": 0.5, "v": Vector3(70, 0, 0)}, {"t": 1.0, "v": Vector3(30, 0, 0)}]}
	m._refresh()
	await idle(2)
	for c in m._commands():
		if c["id"] == "curve_editor":
			c["run"].call()
	await idle(3)
	var ce: CurveEditor = m.ui_curve
	ce.frame_all()
	await idle(2)
	var org: Vector2 = ce.get_global_rect().position
	var plain := JSON.stringify(S.to_dict(m.B))
	ok(not plain.contains("handle") and not plain.contains("hout"), "6 default keys save no handle field")
	await click_at(org + ce.key_pos(0, 1))
	ok(ce.sel_i == 1 and not ce.pick_handle(ce.handle_pos(0, 1, "out")).is_empty(), "5 picking the middle key shows its handles (grabbable: %s)" % str(ce.pick_handle(ce.handle_pos(0, 1, "out"))))
	var before := var_to_str(S.part_keys)
	var u0: int = m.undo.size()
	var to := org + Vector2(ce.t_to_x(0.7), ce.v_to_y(50.0))
	await drag(org + ce.handle_pos(0, 1, "out"), to)
	var k1: Dictionary = S.part_keys["lowerarm_r"][1]
	var hd: Array = PartKeys.handles_of(S.part_keys["lowerarm_r"], 1)
	var dpp: float = (ce.v1 - ce.v0) / ce.plot().size.y
	var so: float = hd[1].y / hd[1].x
	var si: float = hd[0].y / hd[0].x
	ok(absf(hd[1].x - 0.2) <= 1.0 / S.fps and absf(hd[1].y + 20.0) <= dpp * 1.5, "5 dragged to (+0.2 s, -20 deg): out handle %s (bars: 1 frame, 1.5 px = %.2f deg)" % [str(hd[1]), dpp * 1.5])
	ok(k1.get("handle") == "aligned" and absf(so - si) < 1e-3 and m.undo.size() == u0 + 1, "  key turned %s, in slope %.2f == out slope %.2f, undo steps added %d (bar 1)" % [k1.get("handle"), si, so, m.undo.size() - u0])
	var saved := JSON.stringify(S.to_dict(m.B))
	var R := Scene.new()
	R.from_dict(JSON.parse_string(saved))
	var rd := 0.0
	for f in 300:
		var t := float(f) / 299.0
		rd = maxf(rd, absf(PartKeys.at(R.part_keys["lowerarm_r"], t).x - PartKeys.at(S.part_keys["lowerarm_r"], t).x))
	ok(saved.contains("hout") and saved.contains("aligned") and rd < 0.2, "6 saved after the drag: hout in the file, loaded back within %.4f deg (bar 0.2)" % rd)
	var mf1 := PartKeys.mirror_file(PartKeys.to_file(S.part_keys), B0)
	var mf2 := PartKeys.mirror_file(mf1, B0)
	var a0: Array = PartKeys.to_file(S.part_keys)["lowerarm_r"][1]["hout"]
	var a2: Array = mf2["lowerarm_r"][1]["hout"]
	ok(absf(float(a0[0]) - float(a2[0])) < 1e-6 and absf(float(a0[1]) - float(a2[1])) < 0.05 and mf1.has("lowerarm_l"), "  mirrored to the twin and back: handle %s -> %s (bar 0.05)" % [str(a0), str(a2)])
	var u1: int = m.undo.size()
	ce._break.pressed.emit()
	await idle(2)
	ok(S.part_keys["lowerarm_r"][1]["handle"] == "free" and m.undo.size() == u1 + 1, "  Break button: key is free, one undo step")
	ce._unify.pressed.emit()
	await idle(2)
	ok(S.part_keys["lowerarm_r"][1]["handle"] == "aligned" and m.undo.size() == u1 + 2, "  Unify button: key is aligned, one undo step")
	m._undo()
	m._undo()
	m._undo()
	await idle(2)
	ok(var_to_str(m.S.part_keys) == before, "  three Ctrl+Z (Unify, Break, the drag) bring the keys back exactly")
	print("TANGENTS TEST %s %d" % ["FAIL" if fails > 0 else "PASS", fails])
	TestFiles.cleanup()
	quit(fails)
