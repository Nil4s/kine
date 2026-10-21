## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/rigword_test.gd     (ROADMAP J24, RIG FROM WORDS; scripts/rig_words.gd)
## Picture (whole body, side view, tail + ears + cape): RIGWORD_SHOT=<png>, default C:/Users/Nick/.claude/jobs/9afc22db/tmp/rigword.png
## Bars, written before measuring:
##   1 TAIL: "add a tail with 8 bones" makes exactly 8 joints (8 bones, 8 angle pairs, 9 points with the tip); the chain's first point is
##     within 3 cm of the sacrum point (pelvis joint + pelvis rotation * (0,0,-0.09)); total length = 0.40 x stature within 1 mm.
##   2 LENGTH: "add a 60 cm tail with 5 bones" -> 5 joints, 0.600 m within 1 mm, and it REPLACES the first tail (one tail).
##   3 FOLLOW: turning the pelvis 40 deg about its twist keeps the root within 3 cm of the (new) sacrum point; the rig is on the body.
##   4 EARS / CAPE: "add 2 ears" -> 2 chains on the head, each 6.3 cm within 1 mm, left and right of the midline (x of the roots of
##     opposite sign, |x| in 5..10 cm); "add a cape with 3x4 bones" -> 3 chains x 4 bones = 12 joints, each 0.90 m, spread 0.40 m across.
##   5 SAVE: to_dict -> a file in user:// -> a new Scene.from_dict keeps the rig exactly (var_to_str equal); a scene without a rig has no "rigx" key.
##   6 REMOVE: "remove the tail" removes only the tail (ears and cape stay); "remove the rig" empties it; removing what is not there is an error with a next step.
##   7 UNDO: each command (add x4, pose, remove x2) is exactly ONE undo step, and Ctrl+Z restores the rig as it was (var_to_str equal);
##     a bad command ("add a tail with 99 bones", "remove the tail" with none) pushes none and changes nothing.
##   8 DRAWN: with the tail (8 bones) the app shows 8 capsules and 8 joint dots (visible nodes), coloured by Tok tokens.
##   9 POSE: "curl the tail 40" raises the tip by > 5 cm and leaves the joint count at 8; "wag the tail left 30" moves the tip to +x (his left) by > 5 cm.
##  10 PLACEMENT: in a whole-body side view, every screen point of the tail lies on the back side of the pelvis (screen dot with the
##     body's forward direction <= 0), the first point is within 12 cm (in the world) of the pelvis joint in height, and the picture shows it.
extends SceneTree

var fails := 0
var m: Node
var B: Body


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func sacrum() -> Vector3:
	return B.P["pelvis"] + (B.G["pelvis"] as Quaternion) * RigWords.SACRUM


func chains(kind: String) -> Array:
	return m.S.rigx.filter(func(c): return c["kind"] == kind)


func say(t: String) -> Dictionary:
	var n0: int = m.undo.size()
	var r: Dictionary = m._pose_words(t)
	r["steps"] = m.undo.size() - n0
	return r


func vis(prefix: String) -> int:
	var n := 0
	for c in (m._rigx_root as Node3D).get_children():
		if (c as Node3D).visible and String(c.name).begins_with(prefix):
			n += 1
	return n


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	m._load_scene("res://scenes/combo3.json")
	await idle(3)
	B = m.B
	for j in B.ang.keys():
		B.ang[j] = Vector3.ZERO
	B.fk()
	m._refresh()
	await idle(2)
	var H := RigWords.stature(B)

	# 1
	var r := say("add a tail with 8 bones")
	var t: Dictionary = chains("tail")[0] if chains("tail").size() == 1 else {}
	ok(r["ok"] and r["steps"] == 1 and not t.is_empty(), "1 tail made, one chain, one undo step (%d)" % r["steps"])
	var pts := RigWords.points(B, t)
	ok((t["bones"] as Array).size() == 8 and (t["ang"] as Array).size() == 8 and pts.size() == 9, "1 exactly 8 joints (bones %d, angle pairs %d, points %d incl. the tip)" % [(t["bones"] as Array).size(), (t["ang"] as Array).size(), pts.size()])
	var d0 := pts[0].distance_to(sacrum())
	ok(d0 < 0.03, "1 the chain starts %.1f mm from the sacrum point (bar 30 mm)" % (d0 * 1000.0))
	var L := RigWords.length(t)
	ok(absf(L - 0.40 * H) < 0.001, "1 total length %.4f m = 0.40 x stature %.3f = %.4f (bar 1 mm)" % [L, H, 0.40 * H])
	# the length is the sum of the point-to-point distances too
	var s := 0.0
	for i in 8:
		s += pts[i].distance_to(pts[i + 1])
	ok(absf(s - L) < 0.001, "1 the drawn polyline is %.4f m long (stated %.4f)" % [s, L])

	# 8 drawn
	await idle(2)
	ok(vis("bone_") == 8 and vis("joint_") == 8, "8 drawn: %d capsules and %d joint dots visible (bar 8 and 8)" % [vis("bone_"), vis("joint_")])
	ok((m._rigx_mat as StandardMaterial3D).albedo_color.is_equal_approx(Tok.c("s_hips")) and (m._rigx_dot_mat as StandardMaterial3D).albedo_color.is_equal_approx(Tok.c("focus")), "8 the capsules and dots take Tok s_hips / focus")

	# 9 pose
	var tip0: Vector3 = RigWords.points(B, chains("tail")[0])[8]
	r = say("curl the tail 40")
	var tip1: Vector3 = RigWords.points(B, chains("tail")[0])[8]
	ok(r["ok"] and r["steps"] == 1 and tip1.y - tip0.y > 0.05 and (chains("tail")[0]["bones"] as Array).size() == 8, "9 curl the tail 40: tip up %.1f cm (bar > 5), still 8 joints" % ((tip1.y - tip0.y) * 100.0))
	r = say("wag the tail left 30")
	var tip2: Vector3 = RigWords.points(B, chains("tail")[0])[8]
	ok(r["ok"] and r["steps"] == 1 and tip2.x - tip1.x > 0.05, "9 wag the tail left 30: tip moved %.1f cm toward his left +x (bar > 5)" % ((tip2.x - tip1.x) * 100.0))
	m._undo()
	m._undo()

	# 2 replace + length
	r = say("add a 60 cm tail with 5 bones")
	t = chains("tail")[0]
	ok(r["ok"] and chains("tail").size() == 1 and (t["bones"] as Array).size() == 5 and absf(RigWords.length(t) - 0.6) < 0.001, "2 60 cm tail, 5 joints, length %.4f m, still one tail" % RigWords.length(t))

	# 3 follow
	B.ang["pelvis"] = Vector3(0, 0, 40)
	B.fk()
	var d3 := RigWords.points(B, chains("tail")[0])[0].distance_to(sacrum())
	ok(d3 < 0.03 and sacrum().distance_to(B.P["pelvis"] + Vector3(0, 0, -0.09)) > 0.02, "3 pelvis turned 40 deg: root %.1f mm from the new sacrum point, and that point did move" % (d3 * 1000.0))
	B.ang["pelvis"] = Vector3.ZERO
	B.fk()

	# 4 ears and cape
	r = say("add 2 ears")
	var ears := chains("ears")
	var okears := ears.size() == 2
	var xs := []
	for e in ears:
		okears = okears and absf(RigWords.length(e) - 0.063) < 0.001 and e["parent"] == "head"
		xs.append(float((e["root"] as Array)[0]))
	ok(r["ok"] and r["steps"] == 1 and okears and xs[0] * xs[1] < 0.0 and absf(xs[0]) > 0.05 and absf(xs[0]) < 0.10, "4 2 ears on the head, 6.3 cm each, roots at x %s" % str(xs))
	r = say("add a cape with 3x4 bones")
	var cape := chains("cape")
	var joints := 0
	var okc := cape.size() == 3
	var cx := []
	for c in cape:
		joints += (c["bones"] as Array).size()
		okc = okc and absf(RigWords.length(c) - 0.9) < 0.001
		cx.append(float((c["root"] as Array)[0]))
	ok(r["ok"] and r["steps"] == 1 and okc and joints == 12 and absf(absf(cx[0] - cx[2]) - 0.40) < 0.001, "4 cape 3x4: %d chains, %d joints, 0.90 m each, spread %.2f m" % [cape.size(), joints, absf(cx[0] - cx[2])])

	# 5 save
	var key_before := var_to_str(m.S.rigx)
	var d: Dictionary = m.S.to_dict(B)
	var f := FileAccess.open("user://rigword_tmp.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	var back: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://rigword_tmp.json"))
	var S2 := Scene.new()
	S2.from_dict(back)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://rigword_tmp.json"))
	ok(back.has("rigx") and var_to_str(S2.rigx) == key_before, "5 saved to user:// and read back: %d chains kept exactly" % S2.rigx.size())
	var S3 := Scene.new()
	ok(not S3.to_dict(B).has("rigx"), "5 a scene without a rig has no rigx key")

	# 6 remove
	var before := var_to_str(m.S.rigx)
	r = say("remove the tail")
	ok(r["ok"] and r["steps"] == 1 and chains("tail").is_empty() and chains("ears").size() == 2 and chains("cape").size() == 3, "6 remove the tail: tail gone, ears %d and cape %d chains stay" % [chains("ears").size(), chains("cape").size()])
	m._undo()
	ok(var_to_str(m.S.rigx) == before, "7 Ctrl+Z puts the tail back exactly")
	r = say("remove the rig")
	ok(r["ok"] and r["steps"] == 1 and m.S.rigx.is_empty(), "6 remove the rig: empty")
	m._undo()
	ok(var_to_str(m.S.rigx) == before, "7 Ctrl+Z puts the whole rig back exactly")
	# bad commands
	var n0: int = m.undo.size()
	var ra := say("add a tail with 99 bones")
	var rb := say("remove the whale")
	for k in ["ears", "cape", "tail"]:
		say("remove the " + k)
		m._undo()
	m.S.rigx = []
	var rc := say("remove the tail")
	var rd := say("curl the tail 30")
	ok(not ra["ok"] and not rb["ok"] and not rc["ok"] and not rd["ok"] and ra["steps"] == 0 and rc["steps"] == 0 and rd["steps"] == 0, "7 bad commands push no undo step and say what to type (%s)" % str(ra.get("error", "")).left(60))

	# 7 every add was one step, undo of an add removes it
	m.S.rigx = []
	n0 = m.undo.size()
	say("add a tail with 8 bones")
	m._undo()
	ok(m.S.rigx.is_empty() and m.undo.size() == n0, "7 Ctrl+Z of 'add a tail' removes it (undo depth back to %d)" % n0)
	say("add a tail with 8 bones")
	say("add 2 ears")
	say("add a cape with 3x4 bones")

	# 10 placement, picture
	var shot := OS.get_environment("RIGWORD_SHOT")
	if shot == "":
		shot = "C:/Users/Nick/.claude/jobs/9afc22db/tmp/rigword.png"
	if m.ui_toast != null:
		m.ui_toast.visible = false
	if m.dummy_on:
		m._dummy_toggle()
	m.hover_part = ""
	m.hit_tag.visible = false
	m.tag.visible = false
	m._turn_to(90.0, -5.0, 3.3, Vector3(0, 1.0, 0), false)
	await idle(4)
	m.hit_tag.visible = false
	m.tag.visible = false
	var cam: Camera3D = m.cam
	var fwd: Vector3 = (B.G["pelvis"] as Quaternion) * Vector3(0, 0, 1)
	var pp := cam.unproject_position(B.P["pelvis"])
	var fs := cam.unproject_position(B.P["pelvis"] + fwd) - pp
	var worst := -INF
	for p in RigWords.points(B, chains("tail")[0]):
		worst = maxf(worst, (cam.unproject_position(p) - pp).dot(fs.normalized()))
	var p0: Vector3 = RigWords.points(B, chains("tail")[0])[0]
	ok(worst <= 0.0 and absf(p0.y - B.P["pelvis"].y) < 0.12, "10 placement: the tail's furthest screen point is %.1f px on the pelvis's back side of the pelvis (bar <= 0); starts %.1f cm from the pelvis in height" % [worst, absf(p0.y - B.P["pelvis"].y) * 100.0])
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(shot)
	print("   (picture: %s)" % shot)
	print("rigword_test: %s (%d failing)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
