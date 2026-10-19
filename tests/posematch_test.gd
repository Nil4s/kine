## godot --path . -s tests/posematch_test.gd [-- --shot=C:/x.png]   (ROADMAP 84 POSE MATCHING ON CLIP TRANSITIONS; needs a window)
## scripts/pose_match.gd (the choice) and scripts/clips.gd (match, align, yaw_sign: the playback). Three seams: clip A = walk_bat
## at 0 s, clip B = walk_bat placed at A's end: B mirrored (the deliberate mismatch: the other half of the gait, the other side
## of the hips), B plain, B at 1.5x speed. Nothing is written: the source files are read only.
## BARS, stated before any number was read:
##   1 start frame: the frame PoseMatch chose equals the brute-force minimum over the same 1/60 s grid in [0, 0.5 s], the
##     brute force using its own distance code. Bar: 3 of 3 seams equal
##   2 pelvis jump at the seam, in cm: the second difference of the hips across the seam sample (a jump, not the walk's
##     motion). A HARD CUT with no match: X (bar: X >= 5 cm on the mirrored seam, the mismatch is real). The matched seam with
##     its blend: Y. Bar: Y < 1 cm on all 3 seams
##   3 worst joint jump per frame at the seam (any joint, any axis, deg, frames 1/60 s, the seam window = the blend +- 0.1 s)
##     <= the worst per-frame joint jump inside A AND inside B (each clip alone, its own motion). Bar: 3 of 3 seams
##   4 root: B alone at the seam (blend off): its hips in x, z within 0.1 mm of A's hips at the seam, its pelvis twist within
##     0.01 deg of A's. Bar: 3 of 3 seams
##   5 turn: a walk turned by yaw turns its hips' velocity by the same signed angle as its pelvis's facing turns (the sign of
##     PoseMatch's turn). Bar: |velocity angle - facing angle| < 1 deg and the same sign
##   6 undo: the match is ONE undo step; Ctrl+Z restores both clips bit for bit (var_to_str); Ctrl+Y matches again. Bar: +1,
##     equal, matched again
##   7 old files: a clip with no match writes no "match" key; scenes/walk_bat.json and moves/bo_guard.json are byte-identical
##     after the test (md5 before and after). Bar: 0 keys, same md5
extends SceneTree

const SRC := "scenes/walk_bat.json"
const H := 1.0 / 60.0
const BLEND := 0.2
var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## the host: one resting card; the clips play over it
func host() -> Scene:
	var R := PoseMatch.fresh_body()
	R.wep_on = false
	R.fk()
	var S := Scene.new()
	S.add("rest", R.to_dict())
	return S


func pose_at(S: Scene, t: float) -> Body:
	var B := PoseMatch.fresh_body()
	S.apply(B, t)
	return B


## the hips' second difference across the sample at t, cm: a jump shows, the walk's own smooth motion does not
func kink_cm(S: Scene, t: float) -> float:
	var a := pose_at(S, t - H).offset
	var b := pose_at(S, t).offset
	var c := pose_at(S, t + H).offset
	return ((c - b) - (b - a)).length() * 100.0


## the worst per-frame joint change (deg, any joint, any axis) over the frames t0..t1 at 1/60 s
func worst_jump(S: Scene, t0: float, t1: float) -> float:
	var w := 0.0
	var prev := {}
	var t := t0
	while t <= t1 + 1e-9:
		var B := pose_at(S, t)
		if not prev.is_empty():
			for j in Body.ORDER:
				var d: Vector3 = Scene._d(prev[j], B.ang[j], j)
				w = maxf(w, maxf(absf(d.x), maxf(absf(d.y), absf(d.z))))
		prev = B.ang.duplicate(true)
		t += H
	return w


## the test's own distance (not PoseMatch's code): the same definition written out again
func brute_d(A: Body, Q: Body, joints: Array) -> float:
	var s := 0.0
	var tot := 0.0
	for j in joints:
		var d: Vector3 = Q.ang[j] - A.ang[j]
		if j == "pelvis":
			d.z = 0.0
		var m := float(Balance.MASS.get(j, 0.5))
		s += m * d.length()
		tot += m
	return s / tot + 100.0 * absf(Q.offset.y - A.offset.y)


func seam(mirror: bool, speed: float) -> Dictionary:
	var e := Clips.source(SRC)
	var L := float(e["len"])
	var A := Clips.make(SRC, 0.0)
	var Bc := Clips.make(SRC, L, {"mirror": mirror, "speed": speed})
	var s0 := L
	# the cut: no match, B hard in (blend 0)
	var cut := host()
	cut.clips = [A.duplicate(true), Bc.duplicate(true)]
	# the match, as the app makes it
	var S := host()
	S.clips = [A.duplicate(true), Bc.duplicate(true)]
	var r := PoseMatch.plan(S, 1)
	if r.has("err"):
		print("     plan refused: %s" % r["err"])
		return {}
	S.clips[0] = r["A2"]
	S.clips[1] = r["B2"]
	# A's own hold pose at the seam (the target), B alone (for the root and the joint jumps)
	var a_alone := host()
	a_alone.clips = [r["A2"].duplicate(true)]
	var b_alone := host()
	b_alone.clips = [(r["B2"] as Dictionary).duplicate(true)]
	(b_alone.clips[0] as Dictionary)["bin"] = 0.0
	(b_alone.clips[0] as Dictionary)["bout"] = 0.0
	var b_cut := host()
	b_cut.clips = [Bc.duplicate(true)]
	return {"e": e, "L": L, "s0": s0, "mirror": mirror, "cut": cut, "S": S, "r": r, "a_alone": a_alone, "b_alone": b_alone,
		"A": A, "Bc": Bc, "Bm": r["B2"]}


func pair_checks(name: String, mirror: bool, speed: float, want_x: bool) -> void:
	var z := seam(mirror, speed)
	if z.is_empty():
		ok(false, "%s: the match was refused" % name)
		return
	var e: Dictionary = z["e"]
	var s0: float = z["s0"]
	var mt: Dictionary = (z["Bm"] as Dictionary)["match"]
	# 1 start frame vs brute force
	var target := pose_at(z["a_alone"], s0)
	var joints := Clips.mask_joints("all")
	var best_i := -1
	var best_d := INF
	for i in range(31):
		var Q := PoseMatch.fresh_body()
		Clips._pose_src(e, minf(i * H, float(e["len"])), mirror, Q)
		var d := brute_d(target, Q, joints)
		if d < best_d:
			best_d = d
			best_i = i
	ok(absf(float(mt["lt0"]) - best_i * H) < 1e-4,
		"1 %s: start frame lt0 %.4f s, brute-force minimum %.4f s (distance %.2f deg)" % [name, mt["lt0"], best_i * H, best_d])
	# 2 the pelvis jump
	var X := kink_cm(z["cut"], s0)
	var Y := kink_cm(z["S"], s0)
	if want_x:
		ok(X >= 5.0, "2 %s: hard cut, no match: the hips jump %.2f cm at the seam" % [name, X])
	ok(Y < 1.0, "2 %s: matched, blend %.2f s: the hips jump %.3f cm at the seam (was %.2f cm)" % [name, BLEND, Y, X])
	# 3 the joints
	var seam_w := worst_jump(z["S"], s0 - 0.1, s0 + BLEND + 0.1)
	var inA := worst_jump(z["a_alone"], H, s0 - H)
	var inB := worst_jump(z["b_alone"], s0, s0 + float(z["L"]) / speed - H)
	ok(seam_w <= minf(inA, inB), "3 %s: worst joint jump at the seam %.2f deg/frame; inside A %.2f, inside B %.2f" % [name, seam_w, inA, inB])
	# 4 the root: B alone at the seam, blend off
	var b0 := pose_at(z["b_alone"], s0)
	var a0 := pose_at(z["a_alone"], s0)
	var dxz := Vector2(b0.offset.x - a0.offset.x, b0.offset.z - a0.offset.z).length()
	var dtw := absf(wrapf(float(b0.ang["pelvis"].z) - float(a0.ang["pelvis"].z), -180.0, 180.0))
	ok(dxz < 1e-4 and dtw < 0.01, "4 %s: B's hips %.4f mm and twist %.4f deg from A's at the seam" % [name, dxz * 1000.0, dtw])


func turn_check() -> void:
	var e := Clips.source(SRC)
	var t := 0.5
	var Q := PoseMatch.fresh_body()
	Clips._pose_src(e, t, false, Q)
	var v0 := Vector2(0, 0)
	var Q2 := PoseMatch.fresh_body()
	Clips._pose_src(e, t + H, false, Q2)
	v0 = Vector2(Q2.offset.x - Q.offset.x, Q2.offset.z - Q.offset.z)
	var f0: Vector3 = Q.G["pelvis"] * Vector3.RIGHT
	# the same walk, its pelvis turned 30 deg, and the match's own turn (align with pa = pb = 0)
	var mt := {"lt0": t, "pa": [0.0, 0.0], "pb": [Q.offset.x, Q.offset.z], "yaw": 30.0}
	var off1 := Clips.align(Vector3(Q2.offset.x, Q2.offset.y, Q2.offset.z), mt)
	var off0 := Clips.align(Vector3(Q.offset.x, Q.offset.y, Q.offset.z), mt)
	var v1 := Vector2(off1.x - off0.x, off1.z - off0.z)
	var Qt := PoseMatch.fresh_body()
	Clips._pose_src(e, t, false, Qt)
	Qt.ang["pelvis"] = Qt.ang["pelvis"] + Vector3(0, 0, 30)
	Qt.fk()
	var f1: Vector3 = Qt.G["pelvis"] * Vector3.RIGHT
	var ang_v := atan2(v0.x * v1.y - v0.y * v1.x, v0.dot(v1))
	var a_f0 := Vector2(f0.x, f0.z)
	var a_f1 := Vector2(f1.x, f1.z)
	var ang_f := atan2(a_f0.x * a_f1.y - a_f0.y * a_f1.x, a_f0.dot(a_f1))
	ok(absf(rad_to_deg(ang_v) - rad_to_deg(ang_f)) < 1.0 and signf(ang_v) == signf(ang_f) and absf(rad_to_deg(ang_v)) > 5.0,
		"5 the hips' velocity turns %.2f deg, the pelvis facing %.2f deg (the same sign: the walk turns with the body)" % [rad_to_deg(ang_v), rad_to_deg(ang_f)])


func app_part() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 3:
		await process_frame
	var e := Clips.source(SRC)
	var L := float(e["len"])
	m.S = host()
	m.S.add("end", m.S.cards[0]["pose"])   # a second card: the trail runs over the whole scene, past both strips
	m.S.cards[1]["move"] = L + 2.0         # so the scene runs past both strips and the timeline and playhead reach the seam
	m.scene_path = ""
	m._rebuild_cards()
	m._card_pick(0)
	m.undo.clear()
	var k0: int = m.clips_ui.place(SRC, 0.0, {})
	var k1: int = m.clips_ui.place(SRC, L, {"mirror": true})
	var before := var_to_str(m.S.clips)
	var u0: int = m.undo.size()
	m.clips_ui.match_pose(k1)
	ok(m.undo.size() == u0 + 1 and m.S.clips[k1].has("match"), "6 the match is ONE undo step (%d)" % (m.undo.size() - u0))
	var after := var_to_str(m.S.clips)
	m._undo()
	ok(var_to_str(m.S.clips) == before, "6 Ctrl+Z restores both clips bit for bit")
	m._redo()
	ok(m.S.clips[k1].has("match") and var_to_str(m.S.clips) == after, "6 Ctrl+Y matches again, the same clips")
	# the picture: the seam, the onion skin on, the hips' trail, the playhead on the seam
	m.playhead = L + 0.1
	m.ov.trail_on = true
	m.S.apply(m.B, m.playhead)
	m._refresh()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			for i in 4:
				await process_frame
			await RenderingServer.frame_post_draw
			var img: Image = root.get_viewport().get_texture().get_image()
			img.save_png(a.substr(7))
			print("     shot: %s" % a.substr(7))
	m.queue_free()
	await process_frame


func _init() -> void:
	var md_walk := FileAccess.get_md5("res://" + SRC)
	var md_bo := FileAccess.get_md5("res://moves/bo_guard.json")
	pair_checks("mirrored", true, 1.0, true)
	pair_checks("plain", false, 1.0, false)
	pair_checks("fast 1.5x", false, 1.5, false)
	turn_check()
	var plain := Clips.make(SRC, 0.0)
	ok(not Clips.to_file([plain])[0].has("match"), "7 a clip with no match writes no \"match\" key")
	await app_part()
	ok(FileAccess.get_md5("res://" + SRC) == md_walk and FileAccess.get_md5("res://moves/bo_guard.json") == md_bo,
		"7 scenes/walk_bat.json and moves/bo_guard.json unchanged (md5)")
	print("POSEMATCH TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
