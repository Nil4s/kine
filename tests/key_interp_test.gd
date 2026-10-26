## godot --headless --path . -s tests/key_interp_test.gd     (GATES XX1, UPGRADES_300 #241 #242 #247; headless is fine)
## KEY INTERPOLATION on part keys (scripts/part_keys.gd): per-key interpolation (bezier / constant / linear), bezier handle
## types (auto_clamped = the default, auto, vector, aligned, free) and per-joint INFINITY (hold / linear / cycle /
## cycle_offset). Checked by numbers, each printed beside its bar:
##   - OLD KEYS SAMPLE IDENTICALLY: round 41's at() is copied below verbatim as the reference; on 6 key sets (uneven times,
##     a zig-zag, a step, two keys, one key, 3 angles at once) 3000+ times each, PartKeys.at() == the reference BIT FOR BIT
##     (and the same after a save / load of the old file form);
##   - auto-clamped never overshoots on a step-like set (control: AUTO handles overshoot on the same set, so the check can fail);
##   - constant holds the value until the next key's time; linear is a straight line (1e-6);
##   - cycle repeats with period = last - first key time (1e-6, laps both ways), cycle_offset adds last - first each lap;
##     linear infinity continues the end slope (1e-6) and is continuous at the end key;
##   - handle types: vector on both ends of a segment is a straight line, free / aligned handles reproduce a hand-worked
##     bezier midpoint, freezing handles (auto_clamped -> free) does not move the curve, aligned keeps the slopes equal;
##   - the file: defaults are NOT written, non-defaults are, the round trip samples the same (the file's 0.01 deg), the
##     validator passes it and refuses a wrong word, mirror keeps the fields, clone / duplicate(true) (undo's copy) keep them.
## REFERENCE: no body numbers (curves only). The option set follows Blender's F-curve options (interpolation Constant /
##   Linear / Bezier; handle types Free, Aligned, Vector, Automatic, Auto Clamped; extrapolation Constant / Linear; Cycles
##   modifier "Repeat with Offset") from memory of https://docs.blender.org/manual/en/latest/editors/graph_editor/fcurves/
##   properties.html and .../editing.html. UNVERIFIED: those pages were fetched in round 42 but came back as navigation
##   text only, so the names are not confirmed against the page. Our auto-handle formulas are NOT Blender's: PCHIP
##   (Fritsch & Carlson 1980) for auto_clamped, the central difference for auto.
## NOTE: Vector3 is float32 (one ulp is 7.6e-6 at 100 deg), so the 1e-6 bars use keys of a few degrees.
extends SceneTree

var fails := 0
var nok := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	nok += 1
	if not c:
		fails += 1


func K(pairs: Array) -> Array:
	var out := []
	for p in pairs:
		out.append({"t": float(p[0]), "v": p[1]})
	return out


## round 41's PartKeys.at / _slope, copied verbatim (the reference for "old part keys sample identically")
static func ref_slope(keys: Array, k: int) -> Vector3:
	if k <= 0 or k >= keys.size() - 1:
		return Vector3.ZERO
	var hl: float = maxf(1e-6, float(keys[k]["t"]) - float(keys[k - 1]["t"]))
	var hr: float = maxf(1e-6, float(keys[k + 1]["t"]) - float(keys[k]["t"]))
	var y: Vector3 = keys[k]["v"]
	var dl: Vector3 = (y - (keys[k - 1]["v"] as Vector3)) / hl
	var dr: Vector3 = ((keys[k + 1]["v"] as Vector3) - y) / hr
	var w1 := 2.0 * hr + hl
	var w2 := hr + 2.0 * hl
	var m := Vector3.ZERO
	for c in 3:
		if dl[c] * dr[c] > 0.0:
			m[c] = (w1 + w2) / (w1 / dl[c] + w2 / dr[c])
	return m


static func ref_at(keys: Array, t: float) -> Vector3:
	var n := keys.size()
	if t <= float(keys[0]["t"]) or n == 1:
		return keys[0]["v"]
	if t >= float(keys[n - 1]["t"]):
		return keys[n - 1]["v"]
	var i := 0
	while i < n - 2 and t >= float(keys[i + 1]["t"]):
		i += 1
	var t0: float = keys[i]["t"]
	var h: float = maxf(1e-6, float(keys[i + 1]["t"]) - t0)
	var a: Vector3 = keys[i]["v"]
	var b: Vector3 = keys[i + 1]["v"]
	var ma := ref_slope(keys, i)
	var mb := ref_slope(keys, i + 1)
	var s := clampf((t - t0) / h, 0.0, 1.0)
	var s2 := s * s
	var s3 := s2 * s
	return (2 * s3 - 3 * s2 + 1) * a + (s3 - 2 * s2 + s) * h * ma + (-2 * s3 + 3 * s2) * b + (s3 - s2) * h * mb


func body() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	return B


func sci(x: float) -> String:
	return String.num_scientific(x)


func maxabs(v: Vector3) -> float:
	return maxf(absf(v.x), maxf(absf(v.y), absf(v.z)))


func _init() -> void:
	# 1 OLD KEYS: bit for bit against round 41's code
	var sets := {
		"uneven": K([[0.0, Vector3(0, 0, 0)], [0.37, Vector3(40, -10, 5)], [1.1, Vector3(90, 20, -30)], [1.2, Vector3(85, 25, -35)], [3.0, Vector3(10, 0, 60)]]),
		"zigzag": K([[0.0, Vector3(0, 0, 0)], [0.3, Vector3(50, 5, 0)], [0.9, Vector3(-20, -5, 10)], [1.0, Vector3(60, 30, 10)], [2.5, Vector3(0, 0, 0)]]),
		"step": K([[0.0, Vector3(0, 0, 0)], [1.0, Vector3(0, 0, 0)], [1.1, Vector3(100, 50, -50)], [2.0, Vector3(100, 50, -50)]]),
		"two": K([[0.5, Vector3(10, 20, 30)], [1.7, Vector3(-40, 5, 0)]]),
		"one": K([[0.5, Vector3(1, 2, 3)]]),
		"dense": K([[0.0, Vector3(0, 0, 0)], [0.05, Vector3(3, 1, 0)], [0.1, Vector3(9, 2, 1)], [0.4, Vector3(30, 8, 4)], [0.41, Vector3(31, 8, 5)], [2.0, Vector3(120, 40, 80)]])}
	var nbad := 0
	var total := 0
	for nm in sets:
		var ks: Array = sets[nm]
		var t0: float = ks[0]["t"]
		var tl: float = ks[ks.size() - 1]["t"]
		for f in 3001:
			var t := t0 - 0.5 + (tl - t0 + 1.0) * f / 3000.0
			total += 1
			if PartKeys.at(ks, t) != ref_at(ks, t):
				nbad += 1
	ok(total == 6 * 3001 and nbad == 0, "old part keys: %d samples over 6 key sets, %d differ from round 41's at() (bar 0, exact ==)" % [total, nbad])
	# the same after the old file form is read and written
	var pk_old := {"hand_l": (sets["uneven"] as Array).duplicate(true), "head": (sets["zigzag"] as Array).duplicate(true)}
	var fm := PartKeys.to_file(pk_old)
	var txt := JSON.stringify(fm)
	ok(not (txt.contains("interp") or txt.contains("handle") or txt.contains("hin") or txt.contains("hout") or txt.contains("inf")), "old keys: the file has none of the new fields (%s...)" % txt.substr(0, 70))
	var back := PartKeys.from_file(JSON.parse_string(txt))
	var bd := 0.0
	for j in back:
		for f in 1000:
			var t := 3.0 * f / 999.0
			bd = maxf(bd, maxabs(PartKeys.at(back[j], t) - PartKeys.at(pk_old[j], t)))
	ok(bd < 0.011, "  and read back samples the same to the file's precision: max diff %.5f deg (bar 0.011: angles keep 0.01)" % bd)

	# 2 AUTO-CLAMPED never overshoots; control: AUTO does
	var stp := K([[0.0, Vector3(0, 0, 0)], [1.0, Vector3(0, 0, 0)], [1.2, Vector3(1, 1, 1)], [2.2, Vector3(1, 1, 1)], [2.4, Vector3(0, 0, 0)]])
	var over_c := 0.0
	var over_a := 0.0
	var auto_keys: Array = stp.duplicate(true)
	var pkA := {"j": auto_keys}
	for i in auto_keys.size():
		PartKeys.set_handle_type(pkA, "j", i, "auto")
	for f in 2401:
		var t := f / 1000.0
		var v := PartKeys.at(stp, t)
		over_c = maxf(over_c, maxf(maxf(-v.x, v.x - 1.0), maxf(-v.y, v.y - 1.0)))
		var w := PartKeys.at(auto_keys, t)
		over_a = maxf(over_a, maxf(maxf(-w.x, w.x - 1.0), maxf(-w.z, w.z - 1.0)))
	ok(over_c < 1e-6, "auto-clamped on a step-like set (0,0,1,1,0 deg, 0.2 s ramps): max excursion outside [0,1] = %s deg (bar 1e-6)" % sci(over_c))
	ok(over_a > 0.05, "  control: AUTO handles on the same set DO overshoot: %.4f deg (bar > 0.05)" % over_a)

	# 3 CONSTANT holds until the next key's time
	var cs := K([[0.0, Vector3(10, 0, 0)], [1.0, Vector3(50, 0, 0)], [2.0, Vector3(20, 0, 0)]])
	var pkc := {"j": cs}
	PartKeys.set_interp(pkc, "j", 0, "constant")
	var at_just := PartKeys.at(cs, 1.0 - 1e-6).x
	var at_key := PartKeys.at(cs, 1.0).x
	var mid := PartKeys.at(cs, 0.5).x
	ok(mid == 10.0 and at_just == 10.0 and at_key == 50.0, "constant: 10 at 0.5 s (%.1f), 10 at 0.999999 s (%.1f), 50 at the key time 1.0 s (%.1f) (bar exact)" % [mid, at_just, at_key])
	ok(absf(PartKeys.at(cs, 1.5).x - 50.0) > 5.0 and PartKeys.at(cs, 1.5).x > 20.0, "  the second segment (still bezier) is not held: %.2f at 1.5 s (between its keys 50 and 20)" % PartKeys.at(cs, 1.5).x)

	# 4 LINEAR is a straight line
	var ls := K([[0.0, Vector3(0, 0, 0)], [0.8, Vector3(4, -0.8, 0.4)], [2.0, Vector3(1, 2, -2.6)]])
	var pkl := {"j": ls}
	PartKeys.set_interp(pkl, "j", 0, "linear")
	PartKeys.set_interp(pkl, "j", 1, "linear")
	var lerr := 0.0
	for f in 2001:
		var t := 2.0 * f / 2000.0
		var i := 0 if t < 0.8 else 1
		var a: Dictionary = ls[i]
		var b: Dictionary = ls[i + 1]
		var want: Vector3 = (a["v"] as Vector3).lerp(b["v"], (t - float(a["t"])) / (float(b["t"]) - float(a["t"])))
		lerr = maxf(lerr, maxabs(PartKeys.at(ls, t) - want))
	ok(lerr < 1e-6, "linear: 2001 samples on two linear segments, max distance from the straight line %s deg (bar 1e-6)" % sci(lerr))

	# 5 CYCLE: period = last - first
	var cy := K([[0.5, Vector3(0, 0, 0)], [1.0, Vector3(2, 0.5, -0.5)], [1.9, Vector3(0.75, -1, 1.5)], [2.5, Vector3(0.5, 0.25, 0.25)]])
	var pcy := {"j": cy}
	PartKeys.set_inf(pcy, "j", "cycle")
	var P := 2.5 - 0.5
	var cerr := 0.0
	for f in range(1, 1000):   # strictly inside the lap: on the last key itself the value is the last key's, as keyed
		var t := 0.5 + P * f / 1000.0
		for lap in [-3, -1, 1, 2, 5]:
			cerr = maxf(cerr, maxabs(PartKeys.at(cy, t + lap * P) - PartKeys.at(cy, t)))
	ok(cerr < 1e-6, "cycle: period %.2f s (last - first key time), 999 phases (first, last) x 5 laps (both ways), max |v(t + k P) - v(t)| = %s deg (bar 1e-6)" % [P, sci(cerr)])
	var held_before := PartKeys.at(cy, 0.2)
	ok(held_before.distance_to(PartKeys.at(cy, 2.2)) < 1e-6 and held_before.distance_to(cy[0]["v"]) > 0.5, "  before the first key: the lap before (v(0.2) = v(2.2) = %s), not the held first value %s" % [held_before, cy[0]["v"]])
	# smooth where it wraps: with last value = first value the speed just before the last key equals the one just after
	var sm := K([[0.5, Vector3(0, 0, 0)], [1.0, Vector3(2, 0.5, -0.5)], [1.9, Vector3(0.75, -1, 1.5)], [2.5, Vector3(0, 0, 0)]])
	var psm := {"j": sm}
	PartKeys.set_inf(psm, "j", "cycle")
	var e := 1e-3
	var s_before: Vector3 = (PartKeys.at(sm, 2.5 - e) - PartKeys.at(sm, 2.5 - 2 * e)) / e
	var s_after: Vector3 = (PartKeys.at(sm, 2.5 + 2 * e) - PartKeys.at(sm, 2.5 + e)) / e
	var psm_h := {"j": K([[0.5, Vector3(0, 0, 0)], [1.0, Vector3(2, 0.5, -0.5)], [1.9, Vector3(0.75, -1, 1.5)], [2.5, Vector3(0, 0, 0)]])}
	var s_hold: Vector3 = (PartKeys.at(psm_h["j"], 2.5 + 2 * e) - PartKeys.at(psm_h["j"], 2.5 + e)) / e
	ok((s_before - s_after).length() < 0.1 and s_hold.length() < 1e-3, "  smooth at the seam: speed before %s, after %s (bar: within 0.1 deg/s); control, the same keys on hold are flat after: %s" % [s_before, s_after, s_hold])

	# 6 CYCLE WITH OFFSET
	var co := K([[0.0, Vector3(0, 0, 0)], [0.7, Vector3(0.3, -0.05, 0.12)], [1.5, Vector3(0.5, 0.2, 0.4)]])
	var pco := {"j": co}
	PartKeys.set_inf(pco, "j", "cycle_offset")
	var delta: Vector3 = co[2]["v"] - co[0]["v"]
	var oerr := 0.0
	for f in 1001:
		var t := 1.5 * f / 1000.0
		for lap in [-2, -1, 1, 3]:
			oerr = maxf(oerr, maxabs(PartKeys.at(co, t + lap * 1.5) - PartKeys.at(co, t) - lap * delta))
	ok(oerr < 1e-6, "cycle with offset: delta per lap %s, max |v(t + k P) - v(t) - k delta| = %s deg (bar 1e-6)" % [delta, sci(oerr)])
	ok(PartKeys.at(co, 3.0).distance_to(co[2]["v"] + delta) < 1e-6, "  two laps on, the first key's value plus 2 deltas: %s (want %s)" % [PartKeys.at(co, 3.0), co[0]["v"] + 2.0 * delta])

	# 7 LINEAR infinity
	var li := K([[1.0, Vector3(0, 0, 0)], [2.0, Vector3(0.5, 1, 1.5)], [3.0, Vector3(1.5, 1, 0)]])
	var pli := {"j": li}
	PartKeys.set_interp(pli, "j", 0, "linear")
	PartKeys.set_interp(pli, "j", 1, "linear")
	PartKeys.set_inf(pli, "j", "linear")
	var d_hi: Vector3 = PartKeys.at(li, 5.0) - li[2]["v"]
	var d_lo: Vector3 = PartKeys.at(li, -1.0) - li[0]["v"]
	ok(d_hi.distance_to(Vector3(1, 0, -1.5) * 2.0) < 1e-6 and d_lo.distance_to(Vector3(0.5, 1, 1.5) * -2.0) < 1e-6, "linear infinity (linear segments): 2 s past the end adds %s (want (2,0,-3)), 2 s before the start adds %s (want (-1,-2,-3))" % [d_hi, d_lo])
	var cont := PartKeys.at(li, 3.0 + 1e-7).distance_to(PartKeys.at(li, 3.0))
	ok(cont < 1e-4, "  continuous at the last key: jump %s deg over 1e-7 s (bar 1e-4)" % sci(cont))
	var bz := K([[0.0, Vector3(0, 0, 0)], [1.0, Vector3(3, 0, 0)], [2.0, Vector3(4, 0, 0)]])
	var pbz := {"j": bz}
	PartKeys.set_inf(pbz, "j", "linear")
	var sl_end: float = PartKeys.at(bz, 4.0).x - PartKeys.at(bz, 3.0).x
	var sl_in: float = (PartKeys.at(bz, 2.0).x - PartKeys.at(bz, 2.0 - 1e-3).x) / 1e-3
	ok(absf(sl_end - 1.0) < 1e-5 and absf(sl_end - sl_in) < 0.02, "  bezier ends: the extrapolated slope %.5f deg/s is the last secant 1.0 (bar 1e-5) and the curve's slope arriving at the key is %.4f (bar within 0.02; flat would be 0)" % [sl_end, sl_in])

	# 8 HANDLE TYPES
	var vk := K([[0.0, Vector3(0, 0, 0)], [1.0, Vector3(3, 0, 0)], [2.0, Vector3(0, 1.5, 0)]])
	var pv := {"j": vk}
	PartKeys.set_handle_type(pv, "j", 0, "vector")
	PartKeys.set_handle_type(pv, "j", 1, "vector")
	var verr := 0.0
	for f in 1001:
		var t := f / 1000.0
		verr = maxf(verr, maxabs(PartKeys.at(vk, t) - Vector3(3 * t, 0, 0)))
	ok(verr < 1e-6, "vector handles at both ends of a segment: the segment is a straight line, max distance %s deg (bar 1e-6)" % sci(verr))
	# hand-worked free bezier: P0 (0,0), P1 (0.25, 40), P2 (0.75, 40), P3 (1, 0): at u = 0.5 x = 0.5, y = (3*40 + 3*40)/8 = 30
	var fk := K([[0.0, Vector3(0, 0, 0)], [1.0, Vector3(0, 0, 0)]])
	var pf := {"j": fk}
	PartKeys.set_handle_type(pf, "j", 0, "free")
	PartKeys.set_handle_type(pf, "j", 1, "free")
	PartKeys.set_handle(pf, "j", 0, "out", Vector4(0.25, 40, 0, 0))
	PartKeys.set_handle(pf, "j", 1, "in", Vector4(-0.25, 40, 0, 0))
	ok(handle_type(fk, 0) == "free" and handle_type(fk, 1) == "free", "free handles stay free when moved (%s, %s)" % [handle_type(fk, 0), handle_type(fk, 1)])
	var fmid := PartKeys.at(fk, 0.5).x
	ok(absf(fmid - 30.0) < 1e-6, "free handles, bezier (0,0)-(0.25,40)-(0.75,40)-(1,0): the midpoint is %.6f (worked by hand 30, bar 1e-6)" % fmid)
	# freezing: auto_clamped -> free changes nothing
	var fz := (sets["uneven"] as Array).duplicate(true)
	var fz0 := (sets["uneven"] as Array).duplicate(true)
	var pfz := {"j": fz}
	for i in fz.size():
		PartKeys.set_handle_type(pfz, "j", i, "free")
	var ferr := 0.0
	for f in 3001:
		var t := 3.0 * f / 3000.0
		ferr = maxf(ferr, maxabs(PartKeys.at(fz, t) - PartKeys.at(fz0, t)))
	ok(ferr < 5e-5, "auto_clamped frozen into free handles: same curve, max diff %s deg (bar 5e-5: values to 90 deg in float32, one ulp is 7.6e-6)" % sci(ferr))
	# aligned: moving one handle turns the other to the same slope per angle, its length kept
	var al := K([[0.0, Vector3(0, 0, 0)], [1.0, Vector3(10, 0, 0)], [2.0, Vector3(0, 0, 0)]])
	var pal := {"j": al}
	PartKeys.set_handle(pal, "j", 1, "out", Vector4(0.4, 8, -4, 2))
	var hi: Vector4 = al[1]["hin"]
	var ho: Vector4 = al[1]["hout"]
	var s_out := Vector3(ho.y, ho.z, ho.w) / ho.x
	var s_in := Vector3(hi.y, hi.z, hi.w) / hi.x
	ok(al[1]["handle"] == "aligned" and s_out.distance_to(s_in) < 1e-5, "moving a handle on an auto key makes it aligned; slopes out %s / in %s (bar equal 1e-5)" % [s_out, s_in])
	# the default is the default: setting it back removes the fields
	PartKeys.set_handle_type(pal, "j", 1, "auto_clamped")
	PartKeys.set_interp(pal, "j", 0, "constant")
	PartKeys.set_interp(pal, "j", 0, "bezier")
	PartKeys.set_inf(pal, "j", "cycle")
	PartKeys.set_inf(pal, "j", "hold")
	ok(al[0].size() == 2 and al[1].size() == 2 and al[2].size() == 2, "setting the defaults back leaves plain keys: field counts %d, %d, %d (bar 2: t, v)" % [al[0].size(), al[1].size(), al[2].size()])

	# 9 FILE: written only when not default; round trip; validator; mirror; clone / undo copy
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json")))
	var B := body()
	S.part_keys = {}
	PartKeys.put(S.part_keys, "hand_l", 0.0, Vector3(0, 0, 0))
	PartKeys.put(S.part_keys, "hand_l", 0.6, Vector3(30, 10, -5))
	PartKeys.put(S.part_keys, "hand_l", 1.4, Vector3(-20, 0, 15))
	PartKeys.put(S.part_keys, "head", 0.0, Vector3(0, 0, 0))
	PartKeys.put(S.part_keys, "head", 1.0, Vector3(10, 5, 0))
	var D0 := S.to_dict(B)
	var s0 := JSON.stringify(D0["part_keys"])
	ok(not (s0.contains("interp") or s0.contains("handle") or s0.contains("\"inf\"") or s0.contains("hin")), "default keys in a scene: no new field in the file")
	PartKeys.set_interp(S.part_keys, "hand_l", 0, "constant")
	PartKeys.set_handle_type(S.part_keys, "hand_l", 1, "aligned")
	PartKeys.set_handle(S.part_keys, "hand_l", 1, "out", Vector4(0.3, 12, 3, -4))
	PartKeys.set_inf(S.part_keys, "hand_l", "cycle_offset")
	PartKeys.set_interp(S.part_keys, "head", 0, "linear")
	var D1 := S.to_dict(B)
	var f1: Array = D1["part_keys"]["hand_l"]
	ok(f1[0].get("interp") == "constant" and f1[0].get("inf") == "cycle_offset" and f1[1].get("handle") == "aligned" and f1[1].has("hin") and f1[1].has("hout") and not f1[2].has("handle") and not f1[2].has("interp") and D1["part_keys"]["head"][0].get("interp") == "linear",
		"non-default keys are written: key0 %s, key1 %s, key2 %s" % [str(f1[0]), str(f1[1]).substr(0, 80), str(f1[2])])
	var R := Scene.new()
	R.from_dict(JSON.parse_string(JSON.stringify(D1)))
	var rd := 0.0
	for j in S.part_keys:
		for f in 800:
			var t := -1.0 + 4.0 * f / 799.0
			rd = maxf(rd, maxabs(PartKeys.at(R.part_keys[j], t) - PartKeys.at(S.part_keys[j], t)))
	ok(rd < 0.2, "saved and loaded: max sample diff over -1..3 s (cycle with offset included) %.4f deg (bar 0.2: keys written to 0.01, handles to 0.01, 3 laps of offset)" % rd)
	var pth := "user://zz_key_interp.json"
	var fw := FileAccess.open(pth, FileAccess.WRITE)
	fw.store_string(JSON.stringify(D1, " "))
	fw.close()
	var errs: Array = Validate.file(pth)
	ok(errs.is_empty(), "the validator passes the saved file (%d errors%s)" % [errs.size(), (": " + str(errs[0])) if not errs.is_empty() else ""])
	D1["part_keys"]["hand_l"][0]["interp"] = "smooth"
	fw = FileAccess.open(pth, FileAccess.WRITE)
	fw.store_string(JSON.stringify(D1, " "))
	fw.close()
	errs = Validate.file(pth)
	ok(errs.size() >= 1, "  and refuses a wrong interpolation word: %d error(s) %s" % [errs.size(), str(errs[0]) if not errs.is_empty() else ""])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(pth))
	var junk := PartKeys.from_file({"hand_l": [{"t": 0.0, "v": [0, 0, 0], "interp": "smooth", "handle": "free", "inf": "nonsense"}, {"t": 1.0, "v": [1, 1, 1]}]})
	ok(junk["hand_l"][0].size() == 2, "a file with unknown words (or free without handles) reads as the defaults: key fields %s" % str(junk["hand_l"][0].keys()))

	var M := body()
	var mf := PartKeys.mirror_file(PartKeys.to_file(S.part_keys), M)
	var mk0: Dictionary = mf["hand_r"][0]
	var mk1: Dictionary = mf["hand_r"][1]
	ok(mk0.get("interp") == "constant" and mk0.get("inf") == "cycle_offset" and mk1.get("handle") == "aligned" and mk1.get("hout") is Array and (mk1["hout"] as Array).size() == 4 and float(mk1["hout"][0]) == 0.3,
		"mirror keeps the fields on the twin: %s / %s" % [str(mk0), str(mk1).substr(0, 90)])
	var C := S.clone()
	var dup: Dictionary = S.part_keys.duplicate(true)
	ok(var_to_str(C.part_keys) == var_to_str(S.part_keys) and var_to_str(dup) == var_to_str(S.part_keys) and C.part_keys["hand_l"][1]["hout"] is Vector4,
		"clone() and duplicate(true) (the undo copy) keep every field, handles as Vector4")
	# through Scene.sample: a keyed joint follows its key curve incl. infinity
	var Tn := S.length()
	var smp := S.sample(Tn + 5.0)
	ok((smp["ang"]["hand_l"] as Vector3).distance_to(PartKeys.at(S.part_keys["hand_l"], Tn + 5.0)) < 1e-6, "Scene.sample 5 s past the end: hand_l is its cycle-with-offset value %s" % smp["ang"]["hand_l"])
	# put() before the first key: infinity moves to the new first key
	var pm := {"j": K([[1.0, Vector3(1, 0, 0)], [2.0, Vector3(2, 0, 0)]])}
	PartKeys.set_inf(pm, "j", "cycle")
	PartKeys.put(pm, "j", 0.5, Vector3(0, 0, 0))
	ok(pm["j"][0].get("inf") == "cycle" and not pm["j"][1].has("inf") and PartKeys.inf_of(pm["j"]) == "cycle", "put() before the first key: infinity moved to the new first key")

	print("%d ok" % (nok - fails))
	print("KEY INTERP TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)


func handle_type(keys: Array, i: int) -> String:
	return PartKeys.handle_of(keys[i])
