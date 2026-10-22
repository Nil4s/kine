## godot --path . -s tests/wbroke_test.gd     (ROADMAP_400 H24, "Check: weights broke here": scripts/weight_break.gd; needs a window)
## Bars, written before measuring:
##  (1) clean mannequin + scenes/combo3.json (read only): the command runs, reports a worst vertex with numbers (frame, time, vertex,
##      bone, score), and the frame is inside the scene
##  (2) SPEED: a 140-frame scan (combo3 played on, wrapped) takes under 10 s
##  (3) PLANT (in memory only): one forearm vertex set 60% to the spine, 40% forearm. It is #1, at the frame where the arm is farthest from
##      the spine (the frame that maximises |forearm-skinned - spine-skinned| of that vertex), with a score at least 2x the clean scene's worst.
##      CONTROL: the arm-to-spine distance varies over the animation by at least 5 cm (else "the farthest frame" is vacuous), and the clean
##      worst vertex is not the planted one
##  (4) the report names the vertex, the forearm, and "60% from the spine"; the button opens Weight paint with the spine bone picked, Subtract
##  (5) PLACEMENT: the playhead is at that frame; the marker is within 3 cm of the vertex's skinned position (computed by the test), the camera
##      is on it (target within 1 cm), and in the whole-body view the marker is within 3 cm (in pixels at that depth) of the vertex on screen
##  (6) reading changes nothing: cards byte-identical, no undo step, the sidecar file never written. Screenshot wbroke.png
extends SceneTree

const OUT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/wbroke.png"
var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.wp_key = "wbroke_test"
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle()
	var n: int = roundi(m.S.length() * m.S.fps) + 1
	var cards0 := JSON.stringify(m.S.cards)
	var u0: int = m.undo.size()
	m._weights_broke()
	var clean: Array = m.wb_top.duplicate()
	print("clean: %d frames, %d ms; %s" % [n, m.wb_ms, m.wb_report])
	for k in mini(3, clean.size()):
		print("  #%d frame %d vertex %d %s score %.2f kind %s stretch %.2f pop %.1f cm" % [k + 1, clean[k]["frame"], clean[k]["id"], clean[k]["bone_name"], clean[k]["score"], clean[k]["kind"], clean[k]["stretch"], clean[k]["pop_cm"]])
	ok(clean.size() > 0 and clean[0]["frame"] >= 0 and clean[0]["frame"] < n and m.wb_report.contains("vertex") and clean[0]["score"] > 0.0,
		"(1) clean mannequin on combo3 (%d frames): worst is frame %d, vertex %d, score %.2f" % [n, clean[0]["frame"], clean[0]["id"], clean[0]["score"]])
	var clean_score: float = clean[0]["score"]
	var clean_id: int = clean[0]["id"]

	# (2) 140 frames
	var sk: Skeleton3D = m.skel
	var res := WeightBreak.scan(m.wp, 140, func(f: int):
		m._ps().apply(m.B, float(f % n) / m.S.fps)
		Overlays.pose_skeleton(sk, m.bone_idx, m.B))
	print("140 frames: %d ms (%d of %d vertices skinned, %d edges)" % [res["ms"], res["active"], res["verts"], res["edges"]])
	ok(res["ms"] < 10000, "(2) a 140-frame scan took %.1f s (< 10)" % (res["ms"] / 1000.0))

	# (3) plant: a forearm vertex 60% to the spine
	var fa: int = m._wp_bind_of("lowerarm_l")
	var sp: int = m._wp_bind_of("spine_02")
	var pick_s := -1
	var pick_i := -1
	var wp: Dictionary = m.wp
	for si in wp["surfs"].size():
		var s0: Dictionary = wp["surfs"][si]
		var per0: int = s0["per"]
		for i in (s0["verts"] as PackedVector3Array).size():
			if SkinPaint._w_of(s0["bones"], s0["w"], per0, i, fa) >= 0.999 and pick_i < 0:
				pick_s = si
				pick_i = i
	ok(pick_i >= 0, "a rigid left-forearm vertex exists (surface %d, vertex %d)" % [pick_s, pick_i])
	var s: Dictionary = wp["surfs"][pick_s]
	var per: int = s["per"]
	var nb: PackedInt32Array = s["bones"]
	var nw: PackedFloat32Array = s["w"]
	for q in per:
		nb[pick_i * per + q] = 0
		nw[pick_i * per + q] = 0.0
	nb[pick_i * per] = fa
	nw[pick_i * per] = 0.4
	nb[pick_i * per + 1] = sp
	nw[pick_i * per + 1] = 0.6
	s["bones"] = nb
	s["w"] = nw
	var off := 0
	for si in pick_s:
		off += (wp["surfs"][si]["verts"] as PackedVector3Array).size()
	var vid := off + pick_i
	# the frame the arm is farthest from the spine, measured by the test
	var v: Vector3 = (s["verts"] as PackedVector3Array)[pick_i]
	var skin: Skin = wp["skin"]
	var far_f := -1
	var far_d := -1.0
	var lo := INF
	for f in n:
		m._ps().apply(m.B, float(f) / m.S.fps)
		Overlays.pose_skeleton(sk, m.bone_idx, m.B)
		var a: Transform3D = sk.get_bone_global_pose(SkinPaint.bind_bone(skin, sk, fa)) * skin.get_bind_pose(fa)
		var b: Transform3D = sk.get_bone_global_pose(SkinPaint.bind_bone(skin, sk, sp)) * skin.get_bind_pose(sp)
		var d := (a * v).distance_to(b * v)
		lo = minf(lo, d)
		if d > far_d:
			far_d = d
			far_f = f
	ok(far_d - lo >= 0.05, "CONTROL: the planted vertex's arm-to-spine gap runs %.1f..%.1f cm over the animation (>= 5 cm spread), farthest at frame %d" % [lo * 100.0, far_d * 100.0, far_f])
	m._weights_broke()
	var top: Array = m.wb_top
	for k in mini(3, top.size()):
		print("  #%d frame %d vertex %d %s score %.2f kind %s stretch %.2f" % [k + 1, top[k]["frame"], top[k]["id"], top[k]["bone_name"], top[k]["score"], top[k]["kind"], top[k]["stretch"]])
	print("planted: ", m.wb_report)
	ok(top[0]["id"] == vid, "(3) the planted vertex %d is #1 (found %d)" % [vid, top[0]["id"]])
	ok(top[0]["frame"] == far_f, "(3) at the frame the arm is farthest from the spine: found %d, measured %d" % [top[0]["frame"], far_f])
	ok(top[0]["score"] >= 2.0 * clean_score and clean_id != vid, "(3) score %.2f >= 2 x the clean worst %.2f" % [top[0]["score"], clean_score])
	ok(m.wb_report.contains("vertex #%d" % vid) and m.wb_report.contains("forearm") and m.wb_report.contains("60%") and m.wb_report.contains("spine"),
		"(4) the report names the vertex, the forearm and 60%% from the spine: " + m.wb_report)

	var far_e := {"kind": "far", "frame": 3, "id": 7, "bone_name": "lowerarm_l", "far": 2.0, "pull_bone": sp, "pull_w": 0.6, "pull_name": "spine_02", "sum_off": 0.0}
	ok(WeightBreak.report(far_e, 30.0).contains("40 cm from it"), "(4) a far-bone report gives the distance: " + WeightBreak.report(far_e, 30.0))

	# (5) placement
	SkinPaint.refresh(wp)
	var truth: Vector3 = (s["pos"] as PackedVector3Array)[pick_i]
	ok(absf(m.playhead - float(far_f) / m.S.fps) < 1e-4, "(5) the playhead is at frame %d (%.3f s)" % [far_f, m.playhead])
	ok(m.wb_mark.distance_to(truth) <= 0.03, "(5) the marker is %.2f cm from the vertex's skinned position (<= 3)" % (m.wb_mark.distance_to(truth) * 100.0))
	ok(m.target.distance_to(truth) <= 0.01, "(5) the camera target is %.2f cm from the vertex (<= 1)" % (m.target.distance_to(truth) * 100.0))
	await idle(3)
	var cam: Camera3D = m.get_viewport().get_camera_3d()
	var vp: Vector2 = m.get_viewport().get_visible_rect().size
	ok(Rect2(Vector2.ZERO, vp).has_point(cam.unproject_position(truth)) and m.wb_view.visible, "(5) framed: the vertex is on screen (%s) and the marker is drawn" % cam.unproject_position(truth))
	m._turn_to(0.0, -8.0, 5.0, Vector3(-0.8, 0.95, 0), false)   # the whole body, shifted so the panel on the left clears the arm
	await idle(5)
	root.get_texture().get_image().save_png(OUT)
	var pm: Vector2 = cam.unproject_position(m.wb_mark)
	var pv: Vector2 = cam.unproject_position(truth)
	var px3: float = pv.distance_to(cam.unproject_position(truth + cam.global_transform.basis.x * 0.03))
	print("whole body: marker %s vertex %s, 3 cm = %.1f px" % [pm, pv, px3])
	ok(pm.distance_to(pv) <= px3, "(5) PLACEMENT in the whole-body view: marker %.1f px from the vertex (3 cm = %.1f px)" % [pm.distance_to(pv), px3])

	# (4) the button
	m._wb_open_paint()
	ok(m.wp_on and m.wp_bind == sp and m.wp_mode == "subtract", "(4) the button opened Weight paint on bind %d (spine %d) in Subtract" % [m.wp_bind, sp])
	m._wp_toggle()

	# (6)
	ok(JSON.stringify(m.S.cards) == cards0 and m.undo.size() == u0, "(6) cards byte-identical, no undo step (%d)" % m.undo.size())
	ok(not FileAccess.file_exists(SkinPaint.path("wbroke_test")), "(6) no sidecar written")
	print("WBROKE RESULT: ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(fails)
