## godot --path . -s tests/face_test.gd     (ROADMAP 74: the face rig. Needs a window for the shot: run it as :w)
## Bars written before the first run. Sources: jaw 25-30 deg of rotation at the hinge (Okeson, Management of
## Temporomandibular Disorders and Occlusion, ch. 2) and 40-55 mm of incisal opening (Agerberg 1974); eye yaw +-45 deg
## horizontal gaze (Leigh & Zee, The Neurology of Eye Movements, ch. 2); blink 0.1-0.4 s (Doughty 2001). Figures from memory of
## those sources, not re-checked against the papers here.
##  (1) jaw at 1.0 = 27.5 deg: within 2 deg of the cited 25-30 (|27.5 - the midpoint| <= 2 and 25 <= value <= 30)
##  (2) eye look clamps at the cited range: yaw 2.0 -> 45 deg, yaw -3.0 -> -45 deg, pitch 5.0 -> 30 deg; a KEY written at 3.0
##      reads back 45 deg (the clamp is at the key too)
##  (3) L/R mirror: mirror(mirror(face)) == face within 0.01 on every key of every channel (file form); one mirror swaps the
##      brows (brow_l of the mirror = brow_r of the original, within 0.01) and negates the eye yaw
##  (4) lip sync drives the jaw on a synthetic clip (16 kHz, 16 bit in memory, the LipSync pipeline): the middle of each
##      vowel opens the jaw > 10 deg for A and O, > 5 deg for E (E is a close vowel: LipSync's JAW_K 0.45 gives ~6.75 deg;
##      stated before the run, the bar for E was never 10), the middle of a silence (M, B, P: lips shut) < 3 deg, and the
##      visemes read A / O / E / M at those times
##  (5) one undo step: keying the face at the playhead pushes ONE undo step; Ctrl+Z takes the keys back (S.face empty again)
##  (6) the file: a keyed face saves under "face" and reads back (JSON round trip) within 1e-4; a scene with no face keys
##      writes no "face" key (old scenes byte-for-byte as before)
##  (7) a screenshot of four expressions (neutral, surprise, anger, vowel A) when FACE_SHOT is set (a path); with it, the whole
##      body from the front (<path>_body.png) and a close-up of the head (<path>_head.png)
## PLACEMENT (round "facefix": the first face was drawn from the head CAPSULE's centre and sat on the chin / neck, 4-6 cm off the
## skin; the old bars only read angles and sizes, never where the face was). Measured on the RENDERED app: the nodes' global
## positions, the skinned head mesh (CPU skinning of the head piece with the skeleton's pose), the camera's projection.
##  (8) every feature (brows, eyes, irises, mouth): inside the head capsule's volume + 1 cm (distance from the capsule's axis
##      <= radius + 0.01) and on its FRONT half (dot of the offset from the capsule's centre with the head's forward > 0)
##  (9) the eye midpoint is within 2 cm of half the head height above the chin (vertex to chin measured on the skinned mesh;
##      Farkas 1994: the eyes are halfway between the top of the head and the chin); the eye spacing is 63 +/- 5 mm (Dodgson
##      2004); the mouth is within 1 cm of 0.20 of the head height above the chin (stomion, Farkas 1994)
## (10) every feature sits on the skin: the offset from the skinned head's front surface (ray along the head's forward, the
##      mesh the screen shows) is within [-2 mm, +12 mm] (the eyes' centres are 2 mm proud, the irises 4-7 mm)
## (11) a view that frames the WHOLE body (dist 4.6): each feature's screen position is inside the screen silhouette of the head
##      capsule (hull of its projected surface points) AND inside the hull of the projected head mesh
## (12) the head turned 40 deg (its twist): the head's frame turns 40 +/- 0.5 deg, and every feature is within 1 mm of the
##      rotated position (the point that was at head-local p is now at P + G * p)
extends SceneTree

var fails := 0
var m: Node
const SHOT_DIR := "user://"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


## a clip in memory: silence / vowel segments (mono, 16 kHz). Each segment: [seconds, freq Hz (0 = silence)]
func segments(rate: int, segs: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for sg in segs:
		var n := int(round(float(sg[0]) * rate))
		var f := float(sg[1])
		for i in n:
			var v := 0.0
			if f > 0.0:
				v = 0.6 * sin(TAU * f * float(i) / rate)
			out.append(v)
	return out


## the time of the middle of segment k (s), from the segment list
func mid_of(segs: Array, k: int) -> float:
	var t := 0.0
	for i in k:
		t += float(segs[i][0])
	return t + float(segs[k][0]) * 0.5


## the head piece's triangles, skinned by the skeleton's pose now: corner points in world space, three per triangle
func skinned_head(mm: Node) -> PackedVector3Array:
	var sk: Skeleton3D = mm.skel
	var pc: MeshInstance3D = mm.pieces["head"]
	var sn: Skin = pc.skin
	var out := PackedVector3Array()
	for si in pc.mesh.get_surface_count():
		var arr := pc.mesh.surface_get_arrays(si)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bo: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var wt: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var per := bo.size() / vs.size()
		var cache := {}
		for i in ix:
			if not cache.has(i):
				var p := Vector3.ZERO
				for q in per:
					var w := wt[i * per + q]
					if w <= 0.0:
						continue
					var bi := bo[i * per + q]
					var bn: int = sn.get_bind_bone(bi) if sn.get_bind_bone(bi) >= 0 else bi
					p += w * ((sk.global_transform * sk.get_bone_global_pose(bn) * sn.get_bind_pose(bi)) * vs[i])
				cache[i] = p
			out.append(cache[i])
	return out


## how far in front of the skinned surface a point is, measured along `fwd` (m): + = proud of the skin, - = sunk in it.
## The ray starts 10 cm in front of the point; the hit nearest the front counts.
func surf_offset(tris: PackedVector3Array, w: Vector3, fwd: Vector3) -> float:
	var best := -INF
	for t in range(0, tris.size() - 2, 3):
		var h: Variant = Geometry3D.ray_intersects_triangle(w + fwd * 0.1, -fwd, tris[t], tris[t + 1], tris[t + 2])
		if h != null:
			best = maxf(best, ((h as Vector3) - w).dot(fwd))
	return -best if best > -INF else 9.0


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	m._load_scene("res://scenes/combo3.json")
	await idle(3)
	m._commands()   # the commands (and the face panel) are built

	# (1) the jaw at full
	var p1 := Face.pose({"jaw": 1.0})
	ok(absf(float(p1["jaw_deg"]) - 27.5) <= 2.0 and float(p1["jaw_deg"]) >= 25.0 and float(p1["jaw_deg"]) <= 30.0,
		"1 jaw 100 %% = %.2f deg (cited 25-30; within 2 of 27.5)" % float(p1["jaw_deg"]))
	ok(absf(float(Face.pose({"jaw": 0.5})["jaw_deg"]) - 13.75) < 0.01, "1 jaw 50 %% = half of it (%.2f deg)" % float(Face.pose({"jaw": 0.5})["jaw_deg"]))

	# (2) eye look clamps
	var yaw_hi := float(Face.pose({"eye_yaw": 2.0})["eye_yaw_deg"])
	var yaw_lo := float(Face.pose({"eye_yaw": -3.0})["eye_yaw_deg"])
	var pitch_hi := float(Face.pose({"eye_pitch": 5.0})["eye_pitch_deg"])
	ok(absf(yaw_hi - 45.0) < 0.01 and absf(yaw_lo + 45.0) < 0.01 and absf(pitch_hi - 30.0) < 0.01,
		"2 eye look clamps: yaw 2.0 -> %.2f, yaw -3.0 -> %.2f (45 cited), pitch 5.0 -> %.2f (30)" % [yaw_hi, yaw_lo, pitch_hi])
	var kf := {}
	Face.key(kf, 0.0, {"eye_yaw": 3.0})
	ok(absf(float(Face.at(kf, {}, 0.0)["eye_yaw_deg"]) - 45.0) < 0.01, "2 a key written at 3.0 reads back at 45 deg (the clamp holds in the key)")

	# (3) L/R mirror round trip on the file form
	var f3 := {}
	Face.key(f3, 0.2, {"brow_l": 0.8, "brow_r": -0.3, "eye_yaw": 0.6, "eye_pitch": -0.4, "jaw": 0.25, "blink": 0.1, "vis_A": 0.7})
	Face.key(f3, 1.1, {"brow_l": -0.9, "brow_r": 0.5, "eye_yaw": -1.0, "eye_pitch": 0.2, "jaw": 0.0, "blink": 1.0, "vis_O": 1.0})
	var file3 := Face.to_file(f3)
	var mm := Face.mirror_file(Face.mirror_file(file3))
	var rt_err := 0.0
	for ch in file3:
		var a: Array = file3[ch]
		var b: Array = mm.get(ch, [])
		for k in a.size():
			for i in 3:
				rt_err = maxf(rt_err, absf(float((a[k]["v"] as Array)[i]) - float((b[k]["v"] as Array)[i])))
	ok(rt_err <= 0.01 and mm.keys().size() == file3.keys().size(), "3 mirror twice == the face (largest key error %.4f, bar 0.01)" % rt_err)
	var once := Face.mirror_file(file3)
	var brow_ok := absf(float(once["brow_l"][0]["v"][0]) - (-0.3)) < 0.01 and absf(float(once["brow_r"][0]["v"][0]) - 0.8) < 0.01
	var yaw_neg := absf(float(once["eye_yaw"][0]["v"][0]) + 0.6) < 0.01
	ok(brow_ok and yaw_neg, "3 one mirror: brow_l takes brow_r's value (-0.3), brow_r takes brow_l's (0.8), eye yaw negated (-0.6)")

	# (4) lip sync drives the jaw and the visemes on a test clip
	var rate := 16000
	var segs := [[0.3, 0.0], [0.8, 220.0], [0.3, 0.0], [0.8, 120.0], [0.3, 0.0], [0.8, 1000.0], [0.3, 0.0]]
	var mono := segments(rate, segs)
	var A := LipSync.analyse(LipSync.windows(mono, rate))
	var total := float(mono.size()) / rate
	var lip := LipSync.bake(A, 60, 0.0, total)
	var mid_a := mid_of(segs, 1)
	var mid_o := mid_of(segs, 3)
	var mid_e := mid_of(segs, 5)
	var mid_m := mid_of(segs, 2)
	var pa := Face.pose({}, lip, mid_a)
	var po := Face.pose({}, lip, mid_o)
	var pe := Face.pose({}, lip, mid_e)
	var pm := Face.pose({}, lip, mid_m)
	var pm0 := Face.pose({}, lip, mid_of(segs, 0))
	ok(float(pa["jaw_deg"]) > 10.0, "4 vowel A (220 Hz) opens the jaw %.2f deg (bar > 10)" % float(pa["jaw_deg"]))
	ok(float(po["jaw_deg"]) > 10.0, "4 vowel O (120 Hz) opens the jaw %.2f deg (bar > 10)" % float(po["jaw_deg"]))
	ok(float(pe["jaw_deg"]) > 5.0, "4 vowel E (1000 Hz) opens the jaw %.2f deg (bar > 5: E is a close vowel)" % float(pe["jaw_deg"]))
	ok(float(pm["jaw_deg"]) < 3.0 and float(pm0["jaw_deg"]) < 3.0, "4 silence (M, B, P) keeps the jaw %.2f / %.2f deg (bar < 3)" % [float(pm["jaw_deg"]), float(pm0["jaw_deg"])])
	ok(pa["mouth"] == "A" and po["mouth"] == "O" and pe["mouth"] == "E" and pm["mouth"] == "M",
		"4 visemes read A, O, E, M at those times (got %s %s %s %s)" % [pa["mouth"], po["mouth"], pe["mouth"], pm["mouth"]])
	ok(float(pa["vis"]["A"]) == 1.0 and float(pa["vis"]["O"]) == 0.0, "4 the lip sync sets the viseme weights (A = 1, the rest 0)")

	# (5) one undo step, Ctrl+Z takes the keys back
	m.S.face = {}
	m.playhead = 0.6
	var u0: int = m.undo.size()
	m.face_ui.key(0.6, {"brow_l": 0.5, "brow_r": 0.5, "jaw": 1.0, "eye_yaw": 0.3, "eye_pitch": 0.0, "blink": 0.0,
		"vis_M": 0.0, "vis_A": 0.0, "vis_O": 0.0, "vis_E": 0.0})
	await idle(2)
	var keyed: bool = not (m.S.face as Dictionary).is_empty() and absf(float(Face.at(m.S.face, {}, 0.6)["jaw_deg"]) - 27.5) < 0.01
	ok(keyed and m.undo.size() == u0 + 1, "5 keying the face at the playhead: one undo step (%d), jaw reads 27.5 deg at 0.6 s" % (m.undo.size() - u0))
	m._undo()
	await idle(2)
	ok(m.S.face.is_empty(), "5 Ctrl+Z takes the face keys back (S.face empty)")
	m._redo()
	await idle(2)
	ok(not m.S.face.is_empty(), "5 Ctrl+Y puts them back")

	# (6) the file form
	m.S.face = {}
	m.face_ui.key(0.6, {"brow_l": 0.5, "jaw": 0.4, "eye_yaw": -0.25})
	var d: Dictionary = m.S.to_dict(m.B)
	var back := Face.from_file(JSON.parse_string(JSON.stringify(d.get("face", {}))))
	var same: bool = back.keys().size() == m.S.face.keys().size()
	for ch in m.S.face:
		for k in (m.S.face[ch] as Array).size():
			same = same and absf(float(back[ch][k]["t"]) - float(m.S.face[ch][k]["t"])) < 1e-4 and absf((back[ch][k]["v"] as Vector3).x - (m.S.face[ch][k]["v"] as Vector3).x) < 1e-4
	ok(d.has("face") and same, "6 a keyed face saves under \"face\" and reads back within 1e-4")
	m.S.face = {}
	ok(not (m.S.to_dict(m.B)).has("face"), "6 a scene with no face keys writes no \"face\" key")

	# (8)..(12) WHERE the face is, on the rendered app
	m.S.face = {}
	Face.key(m.S.face, 0.6, {"brow_l": 0.0, "brow_r": 0.0, "jaw": 0.0, "eye_yaw": 0.0, "eye_pitch": 0.0, "blink": 0.0})
	m.playhead = 0.6
	m._refresh()
	await idle(2)
	var B: Body = m.B
	var feats := {"brow_l": m.face_brow[0], "brow_r": m.face_brow[1], "eye_l": m.face_eye[0], "eye_r": m.face_eye[1],
		"iris_l": m.face_pupil[0], "iris_r": m.face_pupil[1], "mouth": m.mouth_mi}
	var skin := skinned_head(m)   # triangle corners, three per triangle, world space, the pose now
	var cp: Array = B.cap("head")
	var rad := float(B.rad["head"])
	var cmid: Vector3 = ((cp[0] as Vector3) + (cp[1] as Vector3)) * 0.5
	var fwd: Vector3 = (B.G["head"] as Quaternion) * Vector3(0, 0, 1)
	var worst_in := -9.0
	var worst_front := 9.0
	var worst_lo := 9.0
	var worst_hi := -9.0
	for k in feats:
		var w: Vector3 = (feats[k] as Node3D).global_position
		var cl := Geometry3D.get_closest_point_to_segment(w, cp[0], cp[1])
		worst_in = maxf(worst_in, w.distance_to(cl) - (rad + 0.01))
		worst_front = minf(worst_front, (w - cmid).dot(fwd))
		var off := surf_offset(skin, w, fwd)
		worst_lo = minf(worst_lo, off)
		worst_hi = maxf(worst_hi, off)
		print("   %s: %.1f mm from the capsule's wall bar, %.1f mm in front of the centre, %.1f mm off the skin" % [k, (w.distance_to(cl) - (rad + 0.01)) * 1000.0, (w - cmid).dot(fwd) * 1000.0, off * 1000.0])
	ok(worst_in <= 0.0, "8 all %d features inside the head capsule + 1 cm (worst margin %.1f mm past the bar, <= 0)" % [feats.size(), worst_in * 1000.0])
	ok(worst_front > 0.0, "8 and on the front half of the head (smallest forward offset from the capsule centre %.1f mm, > 0)" % (worst_front * 1000.0))
	ok(worst_lo >= -0.002 and worst_hi <= 0.012, "10 every feature sits on the skin: offsets from the head's front surface %.1f .. %.1f mm (bar -2 .. +12)" % [worst_lo * 1000.0, worst_hi * 1000.0])

	var up: Vector3 = (B.G["head"] as Quaternion) * Vector3(0, 1, 0)
	var lf: Vector3 = (B.G["head"] as Quaternion) * Vector3(1, 0, 0)
	var top_h := -9.0
	var zf := -9.0
	for v in skin:
		top_h = maxf(top_h, v.dot(up))
		zf = maxf(zf, v.dot(fwd))
	var chin_h := 9.0
	var hp: Vector3 = B.P["head"]
	for v in skin:
		if absf((v - hp).dot(lf)) < 0.005 and v.dot(fwd) > zf - 0.04:
			chin_h = minf(chin_h, v.dot(up))
	var hh := top_h - chin_h
	var e_l: Vector3 = (feats["eye_l"] as Node3D).global_position
	var e_r: Vector3 = (feats["eye_r"] as Node3D).global_position
	var eye_mid := (e_l + e_r) * 0.5
	var eye_err := eye_mid.dot(up) - (chin_h + 0.5 * hh)
	ok(hh > 0.2 and hh < 0.32 and absf(eye_err) <= 0.02, "9 head %.1f cm (vertex to chin); the eyes %.1f cm above the chin, half is %.1f: off by %.1f mm (bar 20)" % [hh * 100.0, (eye_mid.dot(up) - chin_h) * 100.0, hh * 50.0, eye_err * 1000.0])
	var ipd := e_l.distance_to(e_r)
	ok(absf(ipd - 0.063) <= 0.005, "9 eye spacing %.1f mm (63 +/- 5, Dodgson 2004)" % (ipd * 1000.0))
	var mo: Vector3 = (feats["mouth"] as Node3D).global_position
	var mo_err := mo.dot(up) - (chin_h + 0.20 * hh)
	ok(absf(mo_err) <= 0.01, "9 the mouth %.1f cm above the chin, 0.20 of the head is %.1f: off by %.1f mm (bar 10)" % [(mo.dot(up) - chin_h) * 100.0, hh * 20.0, mo_err * 1000.0])

	# (11) the whole body in view: each feature inside the head's silhouette on the screen
	m._turn_to(0.0, -5.0, 4.6, Vector3(0, 0.95, 0), false)
	await idle(3)
	var cap_pts := PackedVector2Array()
	for e in 2:
		var ce: Vector3 = cp[e]
		for la in range(0, 13):
			var th := PI * la / 12.0
			for lo in 24:
				var ph := TAU * lo / 24.0
				cap_pts.append(m.cam.unproject_position(ce + rad * Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))))
	var hull_c := Geometry2D.convex_hull(cap_pts)
	var mesh_pts := PackedVector2Array()
	for v in skin:
		mesh_pts.append(m.cam.unproject_position(v))
	var hull_m := Geometry2D.convex_hull(mesh_pts)
	var in_c := 0
	var in_m := 0
	for k in feats:
		var w2: Vector3 = (feats[k] as Node3D).global_position
		var sp: Vector2 = m.cam.unproject_position(w2)
		if not m.cam.is_position_behind(w2) and Geometry2D.is_point_in_polygon(sp, hull_c):
			in_c += 1
		if Geometry2D.is_point_in_polygon(sp, hull_m):
			in_m += 1
	var hb := Rect2(hull_c[0], Vector2.ZERO)
	for q in hull_c:
		hb = hb.expand(q)
	print("   head's screen box %s" % hb)
	ok(in_c == feats.size() and in_m == feats.size(), "11 whole body in view: %d of %d features inside the head capsule's screen outline, %d of %d inside the head mesh's (head is %.0f x %.0f px)" % [in_c, feats.size(), in_m, feats.size(), hb.size.x, hb.size.y])

	# (12) the head turned 40 deg: the features turn with it
	var before := {}
	var g0: Quaternion = B.G["head"]
	var p0h: Vector3 = B.P["head"]
	for k in feats:
		before[k] = g0.inverse() * ((feats[k] as Node3D).global_position - p0h)
	var ang0: Vector3 = B.ang["head"]
	B.ang["head"] = Vector3(ang0.x, ang0.y, ang0.z + 40.0)
	B.fk()
	m._refresh()
	await idle(2)
	var g1: Quaternion = B.G["head"]
	var turned := rad_to_deg((g0.inverse() * g1).get_angle())
	var worst_follow := 0.0
	for k in feats:
		var want: Vector3 = (B.P["head"] as Vector3) + g1 * (before[k] as Vector3)
		worst_follow = maxf(worst_follow, ((feats[k] as Node3D).global_position).distance_to(want))
	ok(absf(turned - 40.0) <= 0.5 and worst_follow <= 0.001, "12 head turned %.2f deg (40 +/- 0.5); the features follow within %.3f mm of the rotated positions (bar 1)" % [turned, worst_follow * 1000.0])
	var skin2 := skinned_head(m)
	var fwd2: Vector3 = g1 * Vector3(0, 0, 1)
	var lo2 := 9.0
	var hi2 := -9.0
	for k in feats:
		var off2 := surf_offset(skin2, (feats[k] as Node3D).global_position, fwd2)
		lo2 = minf(lo2, off2)
		hi2 = maxf(hi2, off2)
	ok(lo2 >= -0.002 and hi2 <= 0.012, "12 and still on the turned head's skin: offsets %.1f .. %.1f mm (bar -2 .. +12)" % [lo2 * 1000.0, hi2 * 1000.0])
	B.ang["head"] = ang0
	B.fk()
	m._refresh()
	await idle(2)
	m.S.face = {}
	m._refresh()


	# (7) the shot: four expressions, cropped round the head (only with FACE_SHOT set; the run needs a window)
	var shot := OS.get_environment("FACE_SHOT")
	if shot != "":
		m.playhead = 0.6
		Face.key(m.S.face, 0.6, {"vis_A": 1.0})
		m._refresh()
		var hc: Vector3 = m.face_at(m.face_geo["eye_l"]) * 0.5 + m.face_at(m.face_geo["eye_r"]) * 0.5 - Vector3(0, 0.03, 0)   # the middle of the face
		# the whole body from the front, the face on the head; then a close-up of the head (the Redo toast would sit on the head)
		if m.ui_toast != null:
			m.ui_toast.visible = false
		if m.dummy_on:
			m._dummy_toggle()   # the Target dummy stands 1.5 m in FRONT of the hero (seen from the front) and hides the face
		m._turn_to(0.0, -5.0, 4.6, Vector3(0, 0.95, 0), false)
		await idle(3)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(shot.get_basename() + "_body.png")
		m._turn_to(0.0, -5.0, 0.7, hc, false)   # the hero faces +Z: look at the face from the front
		await idle(3)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(shot.get_basename() + "_head.png")
		var exps := [
			{"name": "neutral", "v": {}},
			{"name": "surprise", "v": {"brow_l": 1.0, "brow_r": 1.0, "jaw": 0.6, "eye_pitch": 0.5}},
			{"name": "anger", "v": {"brow_l": -1.0, "brow_r": -1.0, "eye_yaw": 0.5, "jaw": 0.1}},
			{"name": "vowel A", "v": {"vis_A": 1.0, "jaw": 0.0, "blink": 0.0}},
		]
		var tiles := []
		for e in exps:
			m.S.face = {}
			var vals := {"brow_l": 0.0, "brow_r": 0.0, "jaw": 0.0, "eye_yaw": 0.0, "eye_pitch": 0.0, "blink": 0.0,
				"vis_M": 0.0, "vis_A": 0.0, "vis_O": 0.0, "vis_E": 0.0}
			for k in e["v"]:
				vals[k] = e["v"][k]
			Face.key(m.S.face, 0.6, vals)
			m.playhead = 0.6
			m._face_draw()
			await idle(2)
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			var sp: Vector2 = m.cam.unproject_position(hc)   # the middle of the face
			var r := Rect2i(int(sp.x) - 150, int(sp.y) - 150, 300, 300).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
			var tile := img.get_region(r)
			tile.convert(Image.FORMAT_RGBA8)
			tiles.append(tile)
			print("shot %s at %s" % [e["name"], sp])
		var sheet := Image.create(300 * tiles.size(), 300, false, Image.FORMAT_RGBA8)
		for i in tiles.size():
			sheet.blit_rect(tiles[i], Rect2i(Vector2i.ZERO, tiles[i].get_size()), Vector2i(300 * i, 0))
		sheet.save_png(shot)
		ok(FileAccess.file_exists(shot), "7 the four expressions saved to %s" % shot)
	m.S.face = {}
	print("FACE TEST %s" % ["PASS" if fails == 0 else "FAIL %d" % fails])
	quit(fails)
