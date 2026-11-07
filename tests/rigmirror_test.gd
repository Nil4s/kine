## godot --path . -s tests/rigmirror_test.gd     (ROADMAP_400 L17 + L18, lane L91 RIGMIRROR; scripts/rig_anim.gd, scripts/rig_mirror.gd, scripts/rig_anim_serve.gd)
## L17 animation tools on a user-built (custom) rig, L18 mirror animation on it. The rig is built HERE (a 31-bone quadruped with a tail,
## exactly mirror-symmetric); no mannequin joint name is used by any of these tools: they go through the rig's own bone list.
## Bars, written and committed BEFORE the implementation; none is edited after. Every bar has a planted control that must FAIL.
##   1 KEY       key_bones(rig, frame, bones) keys exactly the listed bones (part key) and nothing else; all-bones key = the whole pose.
##      Values come back to 1e-6 deg. Control: an unknown bone name refuses (ok=false), writes no key.
##   2 BREAKDOWN breakdown(rig, 5, 0.5) between keys 0 and 10 = independent axis-angle slerp midpoint within 1e-4 deg on every keyed bone
##      (the mannequin breakdowner bar); factor 0 = the key before, 1 = the key after (1e-4 deg). Control: a frame with no key after it refuses.
##   3 RETIME    retime_shift(rig, 10, +5, ripple) on keys 0/10/20 gives frames [0, 15, 25] with the rows and root position keys moved
##      unchanged (exact); the pose at 7.5 is the slerp midpoint of the first two keys; without ripple only that key moves; moving onto
##      another key refuses and changes nothing.
##   4 GRAPH     curve(rig, bone, 0, 20, 1) has 21 samples; at the key frames the angle equals the key (1e-4 deg); every sample equals the
##      independent slerp (1e-4 deg); key_frames lists exactly the frames the bone is keyed on. Control: a sample of another bone differs.
##   5 NAMES     pairs() on the named rig finds 18 of 18 lateral bones by name (patterns _l/_r, .L/.R, Left/Right), 13 centre bones, no
##      unmatched; every pair's rest positions are mirrors within 1 mm.
##   6 POSITION  on the same rig with unnamed bones, shuffled (root plane at x = 0.25) the fallback pairs 18 of 18, each within 1 mm of
##      its mirror, and each equals the true partner; the plane is found within 1 mm.
##   7 MIRROR    mirror_pose: every paired bone's WORLD position is the mirror (about the plane) of its partner's old position within
##      1e-5 m, centre bones too; mirroring twice is byte-identical (var_to_str of keys and pose). A centre bone's twist (Z) and side
##      swing (Y) flip sign and its pitch (X) does not; a left leg turned about X gives the right the same turn.
##   8 CONTROL   a bone with no partner (horn_l alone) is reported unmatched, never paired, its pose is left alone; on the unnamed rig a
##      pair with one bone moved 20 mm is reported (both bones), not paired.
##   9 UNDO      key, breakdown, retime, mirror_pose and mirror_keys are each ONE undo step that restores state byte-identically;
##      a refused action leaves no step.
##  10 TOOL      the rig_anim agent tool (serve) answers key / breakdown / retime / curve / pairs / mirror on a scene's own rig, one
##      m._push_undo per change, and is listed in agent_tools.gd, poser_mcp.py and tools/run_all.sh. The mannequin pose of scenes/walk_bat.json
##      at 0.5 is identical before and after (0.0).
extends SceneTree

var fails := 0
const MX := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## ---- the fixture: [canonical name, parent canonical name, local transform]
func mir(t: Transform3D) -> Transform3D:
	return Transform3D(MX * t.basis * MX, Vector3(-t.origin.x, t.origin.y, t.origin.z))


func fixture(x0: float, with_horn: bool) -> Array:
	var rows := []
	var add := func(n: String, p: String, o: Vector3, e: Vector3):
		rows.append([n, p, Transform3D(Basis.from_euler(e), o)])
	var pair := func(nl: String, nr: String, pl: String, pr: String, o: Vector3, e: Vector3):
		var t := Transform3D(Basis.from_euler(e), o)
		rows.append([nl, pl, t])
		rows.append([nr, pr, mir(t)])
	add.call("root", "", Vector3(x0, 0.5, 0), Vector3(0, 0, 0))
	add.call("hips", "root", Vector3(0, 0.05, 0), Vector3(0.1, 0, 0))
	add.call("spine_1", "hips", Vector3(0, 0, 0.15), Vector3(-0.05, 0, 0))
	add.call("spine_2", "spine_1", Vector3(0, 0, 0.15), Vector3(0.04, 0, 0))
	add.call("spine_3", "spine_2", Vector3(0, 0, 0.15), Vector3(0, 0, 0))
	add.call("neck", "spine_3", Vector3(0, 0.03, 0.12), Vector3(0.3, 0, 0))
	add.call("head", "neck", Vector3(0, 0, 0.1), Vector3(-0.2, 0, 0))
	add.call("jaw", "head", Vector3(0, -0.03, 0.06), Vector3(0.5, 0, 0))
	pair.call("fore_upper.L", "fore_upper.R", "spine_3", "spine_3", Vector3(0.08, -0.05, 0.0), Vector3(1.4, 0.0, 0.1))
	pair.call("fore_lower.L", "fore_lower.R", "fore_upper.L", "fore_upper.R", Vector3(0, 0, 0.2), Vector3(-0.5, 0.0, 0.0))
	pair.call("fore_paw.L", "fore_paw.R", "fore_lower.L", "fore_lower.R", Vector3(0, 0, 0.2), Vector3(0.4, 0.02, 0.0))
	pair.call("hind_upper_l", "hind_upper_r", "hips", "hips", Vector3(0.09, -0.05, 0.0), Vector3(1.3, 0.0, 0.1))
	pair.call("hind_lower_l", "hind_lower_r", "hind_upper_l", "hind_upper_r", Vector3(0, 0, 0.22), Vector3(0.6, 0.0, 0.0))
	pair.call("hind_paw_l", "hind_paw_r", "hind_lower_l", "hind_lower_r", Vector3(0, 0, 0.2), Vector3(0.3, 0.03, 0.0))
	pair.call("LeftEar", "RightEar", "head", "head", Vector3(0.05, 0.04, 0.02), Vector3(-0.3, 0.0, 0.2))
	pair.call("LeftEarTip", "RightEarTip", "LeftEar", "RightEar", Vector3(0.0, 0.0, 0.07), Vector3(0.1, 0.05, 0.0))
	pair.call("eye_L", "eye_R", "head", "head", Vector3(0.03, 0.02, 0.05), Vector3(0.0, 0.0, 0.0))
	var prev := "hips"
	for i in range(1, 6):
		add.call("tail_%d" % i, prev, Vector3(0, 0, -0.1 if i == 1 else -0.08), Vector3(0.15 + 0.02 * i, 0.0, 0.0))
		prev = "tail_%d" % i
	if with_horn:
		add.call("horn_l", "head", Vector3(0.04, 0.09, 0.03), Vector3(0.2, 0.0, 0.0))
	return rows


## a rig dictionary from rows; ren: canonical name -> shown name (empty = canonical)
func build(rows: Array, ren := {}) -> Dictionary:
	var names := []
	var parent := []
	var rest := []
	for r in rows:
		names.append(String(ren.get(r[0], r[0])))
		var pi := -1
		for k in rows.size():
			if rows[k][0] == r[1]:
				pi = k
		parent.append(pi)
		rest.append(r[2])
	return {"ok": true, "why": "", "names": names, "parent": parent, "rest": rest, "pose": {}, "keys": {}, "fps": 30.0, "core_matched": 0, "human": false}


## the independent slerp: axis-angle of the relative rotation, scaled
func islerp(a: Quaternion, b: Quaternion, f: float) -> Quaternion:
	var d := a.inverse() * b
	if d.w < 0.0:
		d = Quaternion(-d.x, -d.y, -d.z, -d.w)
	var ang := 2.0 * atan2(Vector3(d.x, d.y, d.z).length(), d.w)
	if ang < 1e-12:
		return a
	var ax := Vector3(d.x, d.y, d.z).normalized()
	return a * Quaternion(ax, ang * f)


func gap_deg(a: Quaternion, b: Quaternion) -> float:
	var d := a.inverse() * b
	return rad_to_deg(2.0 * atan2(Vector3(d.x, d.y, d.z).length(), absf(d.w)))


func qa(axis: Vector3, deg: float) -> Quaternion:
	return Quaternion(axis.normalized(), deg_to_rad(deg))


func wpos(rig: Dictionary, name: String) -> Vector3:
	var g := CustomRig.globals(rig, rig["pose"], rig.get("pos", Vector3.ZERO))
	return (g[(rig["names"] as Array).find(name)] as Transform3D).origin


func rest_pos(rig: Dictionary) -> Array:
	return CustomRig.globals(rig, {}).map(func(t): return t.origin)


func state(rig: Dictionary) -> String:
	return var_to_str(rig["keys"]) + var_to_str(rig["pose"]) + var_to_str(rig.get("pkeys", {})) + var_to_str(rig.get("pos", Vector3.ZERO))


class Stub extends RefCounted:
	var S
	var pushes := 0
	func _push_undo() -> void:
		pushes += 1


class Holder extends RefCounted:
	var own_rig := {}


## a rig with keys at 0 / 10 / 20 on 8 bones and root position keys
func keyed_rig(rows: Array) -> Dictionary:
	var rig := build(rows)
	var bones := ["tail_1", "tail_2", "tail_3", "hind_upper_l", "hind_lower_r", "LeftEar", "fore_paw.R", "spine_2"]
	var axes := [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 1, 0), Vector3(0, 1, 1), Vector3(1, 0, 1), Vector3(1, 2, 3), Vector3(1, 0, 0)]
	for fi in 3:
		for k in bones.size():
			CustomRig.set_pose(rig, bones[k], qa(axes[k], 25.0 * (fi + 1) * (1.0 if k % 2 == 0 else -1.0)))
		rig["pos"] = Vector3(0.1 * fi, 0.02 * fi, 0.3 * fi)
		CustomRig.key(rig, 10 * fi)
	return rig


func _init() -> void:
	var G := Body.new()
	G.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/walk_bat.json")))
	S.apply(G, 0.5)
	var base := []
	for j in Body.ORDER:
		base.append(G.P[j])

	var rows := fixture(0.0, false)
	print("fixture: %d bones" % rows.size())

	# ---- 1 KEY
	var r1 := build(rows)
	CustomRig.set_pose(r1, "tail_2", qa(Vector3.RIGHT, 30))
	CustomRig.set_pose(r1, "hind_upper_l", qa(Vector3.UP, 20))
	CustomRig.set_pose(r1, "spine_2", qa(Vector3.FORWARD, 10))
	var kr := RigAnim.key_bones(r1, 7, ["tail_2", "hind_upper_l"])
	var row7: Dictionary = r1["keys"].get(7, {})
	ok(bool(kr["ok"]) and row7.size() == 2 and row7.has("tail_2") and row7.has("hind_upper_l") and not row7.has("spine_2"), "part key: only the 2 listed bones in the key at 7 (%d rows)" % row7.size())
	ok(row7.has("tail_2") and row7.has("hind_upper_l") and gap_deg(row7["tail_2"], qa(Vector3.RIGHT, 30)) < 1e-6 and gap_deg(row7["hind_upper_l"], qa(Vector3.UP, 20)) < 1e-6, "key values come back exactly")
	var kall := RigAnim.key_bones(r1, 9, [])
	ok(bool(kall["ok"]) and (r1["keys"][9] as Dictionary).size() == 3, "no list = every posed bone keyed (%d)" % (r1["keys"][9] as Dictionary).size())
	var before := var_to_str(r1["keys"])
	var kbad := RigAnim.key_bones(r1, 12, ["tail_2", "no_such_bone"])
	ok(not bool(kbad["ok"]) and var_to_str(r1["keys"]) == before and not (r1["keys"] as Dictionary).has(12), "CONTROL unknown bone refuses and writes nothing")

	# ---- 2 BREAKDOWN
	var r2 := keyed_rig(rows)
	var k0: Dictionary = (r2["keys"][0] as Dictionary).duplicate(true)
	var k10: Dictionary = (r2["keys"][10] as Dictionary).duplicate(true)
	var k20: Dictionary = (r2["keys"][20] as Dictionary).duplicate(true)
	var bd := RigAnim.breakdown(r2, 5, 0.5, [])
	var worst := 0.0
	for b in k0:
		worst = maxf(worst, gap_deg(r2["keys"][5][b], islerp(k0[b], k10[b], 0.5)))
	print("BAR breakdown 0.5: worst gap to independent slerp %.7f deg over %d bones (bar 1e-4)" % [worst, k0.size()])
	ok(bool(bd["ok"]) and (r2["keys"][5] as Dictionary).size() == k0.size() and worst < 1e-4, "breakdown 0.5 = slerp midpoint on all %d bones" % k0.size())
	RigAnim.breakdown(r2, 3, 0.0, [])
	RigAnim.breakdown(r2, 15, 1.0, [])
	var w0 := 0.0
	var w1 := 0.0
	for b in k0:
		w0 = maxf(w0, gap_deg(r2["keys"][3][b], k0[b]))
		w1 = maxf(w1, gap_deg(r2["keys"][15][b], k20[b]))
	print("BAR breakdown 0/1: %.7f / %.7f deg (bar 1e-4)" % [w0, w1])
	ok(w0 < 1e-4 and w1 < 1e-4, "factor 0 = key before, 1 = key after")
	var b2 := var_to_str(r2["keys"])
	var bd2 := RigAnim.breakdown(r2, 25, 0.5, [])
	ok(not bool(bd2["ok"]) and var_to_str(r2["keys"]) == b2, "CONTROL no key after frame 25 refuses, changes nothing")
	var bd3 := RigAnim.breakdown(r2, 12, 0.5, ["tail_1", "nope"])
	ok(not bool(bd3["ok"]) and var_to_str(r2["keys"]) == b2, "CONTROL unknown bone in a breakdown refuses")

	# ---- 3 RETIME
	var r3 := keyed_rig(rows)
	var kk0: Dictionary = (r3["keys"][0] as Dictionary).duplicate(true)
	var kk10: Dictionary = (r3["keys"][10] as Dictionary).duplicate(true)
	var kk20: Dictionary = (r3["keys"][20] as Dictionary).duplicate(true)
	var pk10: Vector3 = r3["pkeys"][10]
	var rt := RigAnim.retime_shift(r3, 10, 5, true)
	var frs: Array = CustomRig.key_frames(r3)
	ok(bool(rt["ok"]) and frs == [0, 15, 25], "ripple +5 from 10: frames %s" % str(frs))
	ok(r3["keys"].has(15) and r3["keys"].has(25) and var_to_str(r3["keys"][15]) == var_to_str(kk10) and var_to_str(r3["keys"][25]) == var_to_str(kk20) and var_to_str(r3["keys"][0]) == var_to_str(kk0), "rows moved unchanged, key 0 untouched (exact)")
	ok((r3["pkeys"] as Dictionary).keys().size() == 3 and r3["pkeys"].has(15) and r3["pkeys"][15] == pk10 and not (r3["pkeys"] as Dictionary).has(10), "root position keys move with the rows")
	var pm := CustomRig.pose_at(r3, 7.5)
	var wr := 0.0
	for b in kk0:
		wr = maxf(wr, gap_deg(pm[b], islerp(kk0[b], kk10[b], 0.5)))
	ok(wr < 1e-4, "pose at 7.5 = slerp midpoint of keys 0 and 15 (%.7f deg)" % wr)
	var r3b := keyed_rig(rows)
	var rt2 := RigAnim.retime_shift(r3b, 10, 5, false)
	ok(bool(rt2["ok"]) and CustomRig.key_frames(r3b) == [0, 15, 20], "no ripple: only key 10 moves -> %s" % str(CustomRig.key_frames(r3b)))
	var r3c := keyed_rig(rows)
	var b3 := var_to_str(r3c["keys"]) + var_to_str(r3c["pkeys"])
	var rt3 := RigAnim.retime_shift(r3c, 10, 10, false)
	var rt4 := RigAnim.retime_shift(r3c, 10, -10, true)
	var rt5 := RigAnim.retime_shift(r3c, 7, 2, true)
	ok(not bool(rt3["ok"]) and not bool(rt4["ok"]) and not bool(rt5["ok"]) and var_to_str(r3c["keys"]) + var_to_str(r3c["pkeys"]) == b3, "CONTROL landing on a key, crossing the key before, or no key at the frame all refuse and change nothing")

	# ---- 4 GRAPH
	var r4 := keyed_rig(rows)
	var cv := RigAnim.curve(r4, "tail_2", 0, 20, 1)
	var cw := 0.0
	var ck := 0.0
	var other := 0.0
	var tk0: Quaternion = r4["keys"][0]["tail_2"]
	var tk10: Quaternion = r4["keys"][10]["tail_2"]
	var tk20: Quaternion = r4["keys"][20]["tail_2"]
	var okc: bool = bool(cv["ok"]) and (cv["frames"] as Array).size() == 21 and (cv["angle_deg"] as Array).size() == 21
	if okc:
		for i in 21:
			var f := float(i)
			var ex: Quaternion = islerp(tk0, tk10, f / 10.0) if i <= 10 else islerp(tk10, tk20, (f - 10.0) / 10.0)
			cw = maxf(cw, absf(float(cv["angle_deg"][i]) - rad_to_deg(ex.get_angle())))
		ck = maxf(absf(float(cv["angle_deg"][0]) - rad_to_deg(tk0.get_angle())), maxf(absf(float(cv["angle_deg"][10]) - rad_to_deg(tk10.get_angle())), absf(float(cv["angle_deg"][20]) - rad_to_deg(tk20.get_angle()))))
		var cv2 := RigAnim.curve(r4, "tail_3", 0, 20, 1)
		other = absf(float(cv2["angle_deg"][10]) - float(cv["angle_deg"][10]))
	print("BAR graph: worst sample gap %.7f deg, key gap %.7f deg (bar 1e-4); other bone differs by %.3f deg" % [cw, ck, other])
	ok(okc and cw < 1e-4 and ck < 1e-4, "graph samples = independent slerp, keys exact")
	ok(okc and cv["key_frames"] == [0, 10, 20], "key_frames of the bone = [0, 10, 20]")
	ok(other > 1.0, "CONTROL another bone's curve is not this curve (%.2f deg apart)" % other)
	var cbad := RigAnim.curve(r4, "nope", 0, 20, 1)
	ok(not bool(cbad["ok"]), "CONTROL unknown bone refuses")

	# ---- 5 NAMES
	var rn := build(rows)
	var pn := RigMirror.pairs(rn)
	var lat := 0
	var by_name := 0
	var mirrored := true
	var rp := rest_pos(rn)
	var names: Array = rn["names"]
	for b in pn["pair"]:
		var j: String = pn["pair"][b]
		if j == b:
			continue
		lat += 1
		if pn["how"][b] == "name":
			by_name += 1
		var pa: Vector3 = rp[names.find(b)]
		var d: Vector3 = rp[names.find(j)] - Vector3(-pa.x, pa.y, pa.z)
		if d.length() > 1e-3:
			mirrored = false
	var ncentre := 0
	for b in pn["how"]:
		if pn["how"][b] == "centre":
			ncentre += 1
	print("BAR names: %d lateral bones, %d by name, %d centre, %d unmatched" % [lat, by_name, ncentre, (pn["unmatched"] as Array).size()])
	ok(lat == 18 and by_name == 18 and ncentre == 13 and (pn["unmatched"] as Array).is_empty(), "named rig: 18 of 18 by name, 13 centre, none unmatched")
	ok(mirrored and absf(float(pn["plane_x"])) < 1e-3, "every pair's rest positions mirror within 1 mm; plane x = %.5f" % float(pn["plane_x"]))
	var wrong := 0
	for b in pn["pair"]:
		if pn["pair"][pn["pair"][b]] != b:
			wrong += 1
	ok(wrong == 0, "pairing is mutual (%d not)" % wrong)

	# ---- 6 POSITION
	var rows2 := fixture(0.25, false)
	var perm := range(rows2.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	for i in range(perm.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = perm[i]
		perm[i] = perm[j]
		perm[j] = t
	var ren := {}
	for i in rows2.size():
		ren[rows2[i][0]] = "b%02d" % perm[i]
	var ru := build(rows2, ren)
	var pu := RigMirror.pairs(ru)
	var truth := {}
	for r in rows2:
		var cn: String = r[0]
		var cm := cn
		for pr in [["fore_upper.L", "fore_upper.R"], ["fore_lower.L", "fore_lower.R"], ["fore_paw.L", "fore_paw.R"], ["hind_upper_l", "hind_upper_r"], ["hind_lower_l", "hind_lower_r"], ["hind_paw_l", "hind_paw_r"], ["LeftEar", "RightEar"], ["LeftEarTip", "RightEarTip"], ["eye_L", "eye_R"]]:
			if cn == pr[0]:
				cm = pr[1]
			elif cn == pr[1]:
				cm = pr[0]
		truth[ren[cn]] = ren[cm]
	var un_names: Array = ru["names"]
	var rpu := rest_pos(ru)
	var latu := 0
	var right := 0
	var worstmm := 0.0
	var px := float(pu["plane_x"])
	for b in pu["pair"]:
		var j: String = pu["pair"][b]
		if j == b:
			continue
		latu += 1
		if truth[b] == j:
			right += 1
		var pa: Vector3 = rpu[un_names.find(b)]
		var pb: Vector3 = rpu[un_names.find(j)]
		worstmm = maxf(worstmm, (pb - Vector3(2.0 * px - pa.x, pa.y, pa.z)).length() * 1000.0)
	print("BAR position: %d lateral paired, %d equal the truth, worst gap %.4f mm, plane x %.5f (true 0.25), unmatched %d" % [latu, right, worstmm, px, (pu["unmatched"] as Array).size()])
	ok(latu == 18 and right == 18 and worstmm < 1.0 and absf(px - 0.25) < 1e-3 and (pu["unmatched"] as Array).is_empty(), "unnamed shuffled rig: 18 of 18 by position, all within 1 mm, plane found")
	var how_pos := 0
	for b in pu["how"]:
		if pu["how"][b] == "position":
			how_pos += 1
	ok(how_pos == 18, "they are reported as found by position (%d)" % how_pos)

	# ---- 7 MIRROR
	var rm := build(rows)
	CustomRig.set_pose(rm, "fore_upper.L", qa(Vector3(1, 0, 0), 40))
	CustomRig.set_pose(rm, "hind_lower_r", qa(Vector3(1, 2, 3), 33))
	CustomRig.set_pose(rm, "LeftEarTip", qa(Vector3(0, 0, 1), 25))
	CustomRig.set_pose(rm, "tail_2", qa(Vector3(0, 1, 0), 30))
	CustomRig.set_pose(rm, "tail_4", qa(Vector3(0, 0, 1), 20))
	CustomRig.set_pose(rm, "spine_2", qa(Vector3(1, 0, 0), 25))
	CustomRig.set_pose(rm, "head", qa(Vector3(1, 1, 1), 18))
	rm["pos"] = Vector3(0.12, 0.03, 0.4)
	var oldpos := {}
	for b in names:
		oldpos[b] = wpos(rm, b)
	var oldpose: Dictionary = (rm["pose"] as Dictionary).duplicate(true)
	var mr := RigMirror.mirror_pose(rm)
	var wd := 0.0
	for b in pn["pair"]:
		var pa: Vector3 = oldpos[pn["pair"][b]]
		# the root offset is mirrored too, so the old partner position is mirrored about x = 0 as a whole
		wd = maxf(wd, (wpos(rm, b) - Vector3(-pa.x, pa.y, pa.z)).length())
	print("BAR mirror: worst world position gap to the mirrored partner %.8f m (bar 1e-5), pos %s" % [wd, str(rm["pos"])])
	ok(bool(mr["ok"]) and wd < 1e-5, "all %d bones land on their mirrored partner's old world position" % names.size())
	ok(rm["pos"] == Vector3(-0.12, 0.03, 0.4), "root offset mirrored in x only")
	ok(rm["pose"].has("tail_2") and gap_deg(rm["pose"]["tail_2"], qa(Vector3(0, 1, 0), -30)) < 1e-5, "centre bone: side swing (Y) flips sign")
	ok(rm["pose"].has("tail_4") and gap_deg(rm["pose"]["tail_4"], qa(Vector3(0, 0, 1), -20)) < 1e-5, "centre bone: twist (Z) flips sign")
	ok(rm["pose"].has("spine_2") and gap_deg(rm["pose"]["spine_2"], qa(Vector3(1, 0, 0), 25)) < 1e-5, "centre bone: pitch (X) keeps its sign")
	ok(rm["pose"].has("fore_upper.R") and gap_deg(rm["pose"]["fore_upper.R"], qa(Vector3(1, 0, 0), 40)) < 1e-5 and gap_deg(rm["pose"].get("fore_upper.L", Quaternion.IDENTITY), Quaternion.IDENTITY) < 1e-5, "left leg turned about X: the right gets the same turn, the left is now rest")
	RigMirror.mirror_pose(rm)
	ok(var_to_str(rm["pose"]) + var_to_str(rm["pos"]) == var_to_str(oldpose) + var_to_str(Vector3(0.12, 0.03, 0.4)), "pose mirrored twice is byte-identical to the start")
	var rk := keyed_rig(rows)
	var kstr := var_to_str(rk["keys"]) + var_to_str(rk["pkeys"])
	RigMirror.mirror_keys(rk)
	var mid := var_to_str(rk["keys"]) + var_to_str(rk["pkeys"])
	RigMirror.mirror_keys(rk)
	ok(mid != kstr and var_to_str(rk["keys"]) + var_to_str(rk["pkeys"]) == kstr, "keys mirrored twice are byte-identical (and once they differ)")
	var rku := build(rows2, ren)
	CustomRig.set_pose(rku, ren["hind_upper_l"], qa(Vector3(1, 2, 3), 35))
	CustomRig.set_pose(rku, ren["tail_3"], qa(Vector3(0, 1, 0), 22))
	var s0 := var_to_str(rku["pose"])
	RigMirror.mirror_pose(rku)
	var s1 := var_to_str(rku["pose"])
	RigMirror.mirror_pose(rku)
	ok(s1 != s0 and var_to_str(rku["pose"]) == s0, "unnamed rig: twice is byte-identical too")

	# ---- 8 CONTROL
	var rh := build(fixture(0.0, true))
	CustomRig.set_pose(rh, "horn_l", qa(Vector3(1, 0, 0), 30))
	CustomRig.set_pose(rh, "hind_upper_l", qa(Vector3(0, 0, 1), 15))
	var ph := RigMirror.pairs(rh)
	ok((ph["unmatched"] as Array) == ["horn_l"] and not (ph["pair"] as Dictionary).has("horn_l"), "CONTROL horn_l has no partner: reported unmatched, not paired %s" % str(ph["unmatched"]))
	var hq: Quaternion = rh["pose"]["horn_l"]
	var mh := RigMirror.mirror_pose(rh)
	ok(rh["pose"].has("horn_l") and gap_deg(rh["pose"]["horn_l"], hq) < 1e-9 and (mh["unmatched"] as Array) == ["horn_l"] and rh["pose"].has("hind_upper_r"), "the unmatched bone keeps its pose, the result names it, the rest still mirrors")
	var rb := build(fixture(0.25, false), ren)
	var ix: int = (rb["names"] as Array).find(ren["hind_paw_l"])
	var tr: Transform3D = rb["rest"][ix]
	tr.origin.x += 0.02
	rb["rest"][ix] = tr
	var pb := RigMirror.pairs(rb)
	var un: Array = pb["unmatched"]
	var both: bool = un.has(ren["hind_paw_l"]) and un.has(ren["hind_paw_r"])
	ok(both and not (pb["pair"] as Dictionary).has(ren["hind_paw_l"]) and (pb["pair"] as Dictionary).size() == 29, "CONTROL pair with one bone 20 mm off: both reported (%s), 29 others still paired" % str(un))

	# ---- 9 UNDO
	var ru9 := keyed_rig(rows)
	var acts := [["key", {"frame": 40, "bones": ["tail_1", "tail_2"]}], ["breakdown", {"frame": 5, "factor": 0.5}], ["retime", {"frame": 10, "delta": 5, "ripple": true}], ["mirror_pose", {}], ["mirror_keys", {}]]
	for a in acts:
		var s_before := state(ru9)
		var d0 := RigAnim.history_size(ru9)
		var res := RigAnim.run(ru9, a[0], a[1])
		var d1 := RigAnim.history_size(ru9)
		var s_mid := state(ru9)
		var un_ok := RigAnim.undo(ru9)
		var s_after := state(ru9)
		var good: bool = bool(res["ok"]) and d1 == d0 + 1 and s_mid != s_before and un_ok and s_after == s_before and RigAnim.history_size(ru9) == d0
		ok(good, "undo: %s is one step and restores byte-identically" % a[0])
		RigAnim.run(ru9, a[0], a[1])   # keep the change for the next action
	var d_ref := RigAnim.history_size(ru9)
	var refused := RigAnim.run(ru9, "breakdown", {"frame": 500, "factor": 0.5})
	ok(not bool(refused["ok"]) and RigAnim.history_size(ru9) == d_ref, "CONTROL a refused action leaves no undo step")

	# ---- 10 TOOL
	var st := Stub.new()
	var ho := Holder.new()
	ho.own_rig = keyed_rig(rows)
	st.S = ho
	var t1 := RigAnimServe.serve(st, {"action": "key", "frame": 50, "bones": ["tail_1"]})
	var t2 := RigAnimServe.serve(st, {"action": "breakdown", "frame": 5, "factor": 0.5})
	var t3 := RigAnimServe.serve(st, {"action": "retime", "frame": 10, "delta": 5, "ripple": true})
	var t4 := RigAnimServe.serve(st, {"action": "curve", "bone": "tail_2", "from": 0, "to": 20})
	var t5 := RigAnimServe.serve(st, {"action": "pairs"})
	var t6 := RigAnimServe.serve(st, {"action": "mirror", "what": "keys"})
	var t7 := RigAnimServe.serve(st, {"action": "breakdown", "frame": 900, "factor": 0.5})
	var st2 := Stub.new()
	st2.S = Holder.new()
	var t8 := RigAnimServe.serve(st2, {"action": "pairs"})
	ok(bool(t1["ok"]) and bool(t2["ok"]) and bool(t3["ok"]) and bool(t4["ok"]) and bool(t5["ok"]) and bool(t6["ok"]), "tool: key / breakdown / retime / curve / pairs / mirror all answer ok")
	ok(st.pushes == 4 and not bool(t7["ok"]), "tool: 4 changes = 4 undo pushes (reads and refusals push none): %d" % st.pushes)
	ok(not bool(t8["ok"]), "CONTROL no own rig in the scene: the tool says so")
	ok(bool(t4["ok"]) and bool(t5["ok"]) and (t4["result"]["angle_deg"] as Array).size() == 21 and (t5["result"]["pairs"] as Array).size() == 9, "tool: the curve has 21 samples, 9 pairs")
	var txt_a := FileAccess.get_file_as_string("res://scripts/agent_tools.gd")
	var txt_m := FileAccess.get_file_as_string("res://tools/mcp/poser_mcp.py")
	var txt_r := FileAccess.get_file_as_string("res://tools/run_all.sh")
	ok(txt_a.contains("\"rig_anim\"") and txt_m.contains("\"rig_anim\"") and txt_r.contains("rigmirror:"), "rig_anim listed in agent_tools.gd and poser_mcp.py, rigmirror in run_all.sh")
	var G2 := Body.new()
	G2.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var S2 := Scene.new()
	S2.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/walk_bat.json")))
	S2.apply(G2, 0.5)
	var md := 0.0
	for i in Body.ORDER.size():
		md = maxf(md, (G2.P[Body.ORDER[i]] - base[i]).length())
	ok(md == 0.0, "mannequin walk_bat pose unchanged after all of it (%.1f)" % md)

	print("rigmirror_test: %d fail" % fails)
	quit(1 if fails > 0 else 0)
