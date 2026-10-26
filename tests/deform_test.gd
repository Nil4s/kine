## godot --path . -s tests/deform_test.gd     (ROADMAP_400 F14, "Will this deform?": scripts/deform_check.gd; needs a window)
## One click before rigging: every major joint swept through its range on the skin as weighted, a verdict and the 3 worst spots.
## Bars, written before measuring:
##  (1) the mannequin as shipped (a game linear-blend skin): the sweep runs every joint (the pose count = the one worked out
##      here from body_limits.json), 3 spots from 3 different joint families, each with a sentence; it does NOT break
##      (worst < BREAKS 1.0): ordinary linear-blend volume loss, not torn weights
##  (2) a known bad joint: the same skin with every forearm vertex of the LEFT arm weighted 100% to the upper arm (the forearm
##      no longer follows the elbow). The verdict is WILL BREAK, the worst spot is the left elbow, it scores at least 2x the
##      shipped skin's left elbow, and its vertex is on the left forearm (within 6 cm of the elbow-wrist segment at rest)
##  (3) CONTROL: the untouched RIGHT elbow of the bad skin scores what the shipped one does (to 1e-5): the corruption stays local
##  (4) reading changes nothing: the body's angles, the skeleton's bone rotations, the real skin's weights and the undo list
##  (5) PLACEMENT: the command (Check: will this deform?) on the real body draws 3 dots; each is within 25 cm of the joint its
##      spot names (in the pose the body stands in), inside the 3D view and clear of the findings panel; clicking spot 1 turns
##      the view's centre onto its dot (within 2 cm); screenshot deform.png
extends SceneTree

var fails := 0
const OUT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/deform.png"
const FAM_JOINT := {"shoulder": "upperarm", "elbow": "lowerarm", "wrist": "hand", "hip": "thigh", "knee": "calf", "spine": "spine_02", "neck": "neck_01"}


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


## the worst score of one swept joint ({} entry id -> sev), from res["all"]
func worst_of(res: Dictionary, entry: String) -> float:
	var w := 0.0
	for c in res["all"]:
		if c["entry"] == entry:
			w = maxf(w, float(c["sev"]))
	return w


func _dseg(p: Vector3, a: Vector3, b: Vector3) -> float:
	return DeformCheck._dseg(p, a, b)


func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	await idle()
	var skel: Skeleton3D = m.skel
	var idx: Dictionary = m.bone_idx
	var restore := func(): Overlays.pose_skeleton(skel, idx, m.B)
	ok(not m.wp.is_empty(), "the mannequin has a skin (%d surfaces)" % m.wp["surfs"].size())

	# what reading must not change
	var ang0: Dictionary = m.B.ang.duplicate()
	var rot0 := []
	for b in skel.get_bone_count():
		rot0.append(skel.get_bone_pose_rotation(b))
	var w0 := []
	for s in m.wp["surfs"]:
		w0.append([(s["bones"] as PackedInt32Array).duplicate(), (s["w"] as PackedFloat32Array).duplicate()])
	var u0: int = m.undo.size()

	# (1) the shipped skin
	var good := SkinPaint.read(m.pieces.values(), skel)
	var rg := DeformCheck.run(good, skel, idx, restore, m.B.body)
	var lim: Dictionary = m.B.lim
	var expect := 0
	for e in DeformCheck.entries():
		for axis in ["bend", "side", "twist"]:
			var r: Vector2 = lim[e["bones"][0]][axis]
			for ext in [r.x, r.y]:
				if absf(ext) >= 5.0:
					expect += DeformCheck.FRACS.size()
	print("shipped: %d poses in %d ms over %d vertices, worst %.3f, %s" % [rg["poses"], rg["ms"], rg["verts"], rg["worst"], DeformCheck.verdict(rg)])
	for sp in rg["spots"]:
		print("  spot %s %s sev %.3f: %s" % [sp["entry"], sp["kind"], sp["sev"], sp["text"]])
	var fams := {}
	var texts := true
	for sp in rg["spots"]:
		fams[sp["fam"]] = true
		texts = texts and str(sp["text"]).length() > 10
	ok(rg["poses"] == expect, "(1) every joint swept: %d poses (%d worked out from body_limits.json)" % [rg["poses"], expect])
	ok(rg["spots"].size() == 3 and fams.size() == 3 and texts, "(1) 3 spots from %d different joint families, each with a sentence" % fams.size())
	ok(not rg["breaks"], "(1) the shipped skin does not break: worst %.3f < %.1f (%s)" % [rg["worst"], DeformCheck.BREAKS, DeformCheck.headline(rg)])

	# (2) the known bad joint: every vertex mostly on the left forearm goes 100% to the left upper arm
	var bad := SkinPaint.read(m.pieces.values(), skel)
	var skin: Skin = bad["skin"]
	var k_fa := -1
	var k_ua := -1
	for k in skin.get_bind_count():
		var bn := skel.get_bone_name(SkinPaint.bind_bone(skin, skel, k))
		if bn == skel.get_bone_name(int(idx["lowerarm_l"])):
			k_fa = k
		if bn == skel.get_bone_name(int(idx["upperarm_l"])):
			k_ua = k
	var moved := 0
	var bad_rest := []   # [surface, vertex] of the moved vertices
	for si in bad["surfs"].size():
		var s: Dictionary = bad["surfs"][si]
		var per: int = s["per"]
		var bb: PackedInt32Array = s["bones"]
		var ww: PackedFloat32Array = s["w"]
		for i in (s["verts"] as PackedVector3Array).size():
			if SkinPaint._w_of(bb, ww, per, i, k_fa) >= 0.5:
				for q in per:
					bb[i * per + q] = k_ua if q == 0 else 0
					ww[i * per + q] = 1.0 if q == 0 else 0.0
				moved += 1
				bad_rest.append([si, i])
		s["bones"] = bb
		s["w"] = ww
	ok(k_fa >= 0 and k_ua >= 0 and moved > 50, "(2) the left forearm skin moved onto the upper arm: %d vertices" % moved)
	var rb := DeformCheck.run(bad, skel, idx, restore, m.B.body)
	print("bad elbow: worst %.3f, %s" % [rb["worst"], DeformCheck.verdict(rb)])
	for sp in rb["spots"]:
		print("  spot %s %s sev %.3f: %s" % [sp["entry"], sp["kind"], sp["sev"], sp["text"]])
	var top: Dictionary = rb["spots"][0] if not rb["spots"].is_empty() else {}
	ok(rb["breaks"], "(2) the verdict is WILL BREAK (worst %.3f >= %.1f)" % [rb["worst"], DeformCheck.BREAKS])
	ok(not top.is_empty() and top["fam"] == "elbow" and top["side"] == "left", "(2) the worst spot is the left elbow (%s)" % (str(top.get("entry", "-"))))
	var gl := worst_of(rg, "lowerarm_l")
	var bl := worst_of(rb, "lowerarm_l")
	ok(bl >= 2.0 * gl, "(2) the bad left elbow scores %.3f, %.1fx the shipped one's %.3f (>= 2x)" % [bl, bl / maxf(gl, 1e-6), gl])
	if not top.is_empty():
		# where the worst vertex is at rest, on the shipped skin, against the left forearm's bone
		SkinPaint.refresh(good)
		var pr: Vector3 = (good["surfs"][top["surf"]]["pos"] as PackedVector3Array)[top["i"]]
		var gt := skel.global_transform
		var el := gt * skel.get_bone_global_pose(int(idx["lowerarm_l"])).origin
		var wr := gt * skel.get_bone_global_pose(int(idx["hand_l"])).origin
		var dd := _dseg(pr, el, wr)
		ok(dd <= 0.06, "(2) its vertex is on the left forearm: %.1f cm from the elbow-wrist segment (<= 6)" % (dd * 100.0))
	# (3) the right elbow, untouched
	var gr := worst_of(rg, "lowerarm_r")
	var br := worst_of(rb, "lowerarm_r")
	ok(absf(gr - br) <= 1e-5 and gr > 0.0, "(3) CONTROL the right elbow scores %.5f on both skins (shipped %.5f)" % [br, gr])

	# (4) nothing read was changed
	var same_rot := true
	for b in skel.get_bone_count():
		same_rot = same_rot and (skel.get_bone_pose_rotation(b) as Quaternion).is_equal_approx(rot0[b])
	var same_w := true
	for si in m.wp["surfs"].size():
		var s: Dictionary = m.wp["surfs"][si]
		same_w = same_w and s["bones"] == w0[si][0] and s["w"] == w0[si][1]
	ok(m.B.ang == ang0 and same_rot and same_w and m.undo.size() == u0, "(4) body angles, bone rotations, the real skin's weights and the undo list unchanged")

	# (5) the command on the real body, drawn
	m._turn_to(0.0, -8.0, 5.0, Vector3(-0.8, 0.95, 0), false)   # the whole body, shifted right so the panel on the left clears it
	await idle(2)
	m._deform_check()
	await idle(5)
	var img := root.get_texture().get_image()
	if img.save_png(OUT) != OK:   # off Nick's machine the picture goes to the user folder
		img.save_png("user://deform.png")
		print("screenshot: ", ProjectSettings.globalize_path("user://deform.png"))
	var marks: Array = m.deform_marks
	var spots: Array = m.deform_res["spots"]
	ok(marks.size() == 3 and m.deform_view != null and m.deform_view.visible and m.ui_find.visible, "(5) the command drew 3 dots and opened its panel")
	var cam: Camera3D = m.get_viewport().get_camera_3d()
	var vp: Vector2 = m.get_viewport().get_visible_rect().size
	var panel: Rect2 = m.ui_find.get_global_rect()
	for k in marks.size():
		var sp: Dictionary = spots[k]
		var jn: String = FAM_JOINT[sp["fam"]]
		if sp["side"] != "":
			jn += "_l" if sp["side"] == "left" else "_r"
		var jp: Vector3 = m.B.P[jn]
		var d: float = (marks[k] as Vector3).distance_to(jp)
		var px: Vector2 = cam.unproject_position(marks[k])
		print("  dot %d %s: %.1f cm from %s, screen %s (panel %s, view %s)" % [k + 1, sp["entry"], d * 100.0, jn, px, panel, vp])
		ok(d <= 0.25, "(5) PLACEMENT dot %d is %.1f cm from the %s it names (<= 25)" % [k + 1, d * 100.0, jn])
		ok(Rect2(Vector2.ZERO, vp).has_point(px) and not panel.has_point(px), "(5) dot %d is inside the view and clear of the panel" % (k + 1))
	var b1: Button = m.ui_find_list.find_child("deform_1", true, false)
	if b1 != null and marks.size() > 0:
		b1.pressed.emit()
		await idle(60)
		ok((m.target as Vector3).distance_to(marks[0]) <= 0.02, "(5) clicking spot 1 turns the view onto its dot (%.1f cm off)" % ((m.target as Vector3).distance_to(marks[0]) * 100.0))
	else:
		ok(false, "(5) the panel has a button for spot 1")
	m._close_findings()
	ok(not m.deform_view.visible, "(5) closing the panel hides the dots")
	print("DEFORM RESULT: ", "PASS" if fails == 0 else "FAIL %d" % fails)
	TestFiles.cleanup()
	quit(fails)
