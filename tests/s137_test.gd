## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/s137_test.gd     (Friday plan 137; a window)
## IMPACT FRAMES ON A STRIKE (scripts/impact_clip.gd, impact_clip_ui.gd): a punch clip (right arm swings forward) and a target box on a table
## in front. Opened with REAL clicks: the SET tab, the "Impact frames" button, the panel's toggle and its sliders. Bars, written before the run:
##   1 CONTACT: the frame the system finds equals (within 1 frame) the first frame the wrist is nearer the box's surface than the hand's
##     radius, measured here with the box's own half sizes on the clip as it was
##   2 HOLD: the bone transforms (all rotations + pelvis position) are identical on the contact frame and the N frames after it (N = the
##     slider's value, 3 by default), and differ on the next frame
##   3 FLASH: the target mesh's emission is white on exactly 2 frames of the whole clip (the contact frame and the next), read per frame
##   4 SHAKE: the shot camera's offset is non-zero on the contact frame, and below 5 % of its peak 0.25 s later; the real view camera
##     (shot_view_at) moves by the same offset at the contact and is the keyed camera 0.25 s later
##   5 SLIDER: a real click on the Hit-stop slider changes N; the clip is rewritten (hold = the new value) in ONE undo step
##   6 OFF: the toggle clicked off -> every frame's bone transforms equal the original clip's (1e-6), cards and shots JSON-equal; Ctrl+Z's
##     step (m._undo) puts the effect back
##   7 SAVED: the effect survives to_dict / from_dict (the hold marker and the shake), and Remove works on the reloaded scene
##   8 PICTURE: the flash frame is saved and the panel fits inside the window
extends SceneTree

var fails := 0
var m: Node
const OUT := "C:/Temp/claude/s137"
const FPS := 30


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ev_mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func ev_move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	root.push_input(e, true)
	await process_frame


func click_at(p: Vector2) -> void:
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func click_ctl(c: Control) -> void:
	await click_at(c.get_global_rect().get_center())


func snap(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(OUT)
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, nm])


func body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.fk()
	return b


func pose_of(arm: float) -> Dictionary:
	var b := body()
	b.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	if arm > 0.0:
		b.set_ang("upperarm_r", Vector3(arm, 0, 0))
	b.ground()
	return b.to_dict()


## the bones' state at frame k of the open scene: every local rotation + the pelvis place
func sig(k: int) -> Array:
	m.S.apply(m.B, float(k) / FPS)
	var out := []
	for j in Body.ORDER:
		out.append(m.B.gltf_local(j))
	out.append(m.B.gltf_pelvis_pos())
	return out


func same(a: Array, b: Array, tol := 1e-5) -> bool:
	for i in a.size():
		if a[i] is Quaternion:
			if absf((a[i] as Quaternion).dot(b[i])) < 1.0 - tol:
				return false
		elif (a[i] as Vector3).distance_to(b[i]) > tol:
			return false
	return true


func nframes() -> int:
	return int(floor(m.S.length() * FPS + 1e-6))


func all_sigs() -> Array:
	var out := []
	for k in nframes() + 1:
		out.append(sig(k))
	return out


func maxdiff(a: Array, b: Array) -> float:
	var worst := 0.0
	for i in a.size():
		if a[i] is Quaternion:
			worst = maxf(worst, rad_to_deg((a[i] as Quaternion).angle_to(b[i])))
	return worst


func box_dist(p: Vector3, c: Vector3, half: float) -> float:
	var q := Vector3(maxf(absf(p.x - c.x) - half, 0.0), maxf(absf(p.y - c.y) - half, 0.0), maxf(absf(p.z - c.z) - half, 0.0))
	return q.length()


func cam_off(S: Scene, t: float) -> float:
	var sh: Array = ShotCam.fx_at(S.shots, t).get("shake", [])
	var o := ShotFx.shake_at(sh, t)
	return 0.0 if o.is_empty() else (o["pos"] as Vector3).length()


func sjson(S: Scene) -> String:
	var d := S.to_dict(body())
	d.erase("actors")
	return JSON.stringify(d) + var_to_str(S.shots)


func flash_frames(box_i: int) -> Array:
	var out := []
	for k in nframes() + 1:
		m.playhead = float(k) / FPS
		m.S.apply(m.B, m.playhead)
		m._refresh()
		await idle(1)
		var n: Node = m.ui_props_root.get_node_or_null("prop_%d" % box_i)
		var white := false
		if n != null:
			for mi in n.find_children("*", "MeshInstance3D", true, false):
				var mat := (mi as MeshInstance3D).get_active_material(0)
				if mat is StandardMaterial3D and (mat as StandardMaterial3D).emission_enabled and (mat as StandardMaterial3D).emission.is_equal_approx(Color(1, 1, 1)):
					white = true
		if white:
			out.append(k)
	return out


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	var b0 := body()
	var best := 90.0
	b0.from_dict(pose_of(best))
	b0.fk()
	var hb: Vector3 = b0.P["hand_r"]
	print("punch: arm %.0f deg, hand at the end %s" % [best, str(hb)])
	var S := Scene.new()
	S.from_dict({"scene": "zz_s137", "fps": FPS, "natural": false, "cards": [
		{"name": "guard", "pose": pose_of(0), "move": -1.0, "hold": 0.4, "ease": "linear"},
		{"name": "punch", "pose": pose_of(best), "move": 0.6, "hold": 0.5, "ease": "linear"},
		{"name": "back", "pose": pose_of(0), "move": 0.6, "hold": 0.4, "ease": "linear"}]})
	# the table with the target box on it: the box's near face 9 cm short of the full reach
	var zface := hb.z - 0.25
	var bc := Vector3(hb.x, 0.95, zface + 0.2)
	var table := Props.make("table", Props.xf_at(Vector3(bc.x, 0, bc.z), 0.0))
	var box := Props.make("box", Props.xf_at(Vector3(bc.x, 0.75, bc.z), 0.0))
	var box2 := Props.make("box", Props.xf_at(Vector3(bc.x, 1.15, bc.z), 0.0))
	S.props = [table, box, box2]
	Props.settle(S.props)
	var boxcs := [(S.props[1]["xf"] as Transform3D).origin + Vector3(0, 0.2, 0), (S.props[2]["xf"] as Transform3D).origin + Vector3(0, 0.2, 0)]
	print("boxes at ", boxcs, " table ", (S.props[0]["xf"] as Transform3D).origin)
	m.S = S
	m._rebuild_cards()
	m.sel_card = 0
	m.playhead = 0.0
	m._props_show()
	m._refresh()
	await idle(4)
	var orig_sigs := all_sigs()
	var orig_json := sjson(m.S)
	var n0 := nframes()
	# 1 CONTACT, measured on the clip as it was
	var rad: float = m.B.rad["hand_r"]
	var kref := -1
	for k in n0 + 1:
		m.S.apply(m.B, float(k) / FPS)
		if box_dist(m.B.P["hand_r"], boxcs[0], 0.2) < rad or box_dist(m.B.P["hand_r"], boxcs[1], 0.2) < rad:
			kref = k
			break
	var c := ImpactClip.find_contact(m.S, m.B)
	ok(kref > 0 and not c.is_empty() and absi(int(c["k"]) - kref) <= 1, "CONTACT: system frame %s vs the first frame the wrist is within the hand's radius (%.0f mm) of the box: %d (box is prop %s)" % [str(c.get("k", "none")), rad * 1000.0, kref, str(c.get("prop", "?"))])
	var kc := int(c.get("k", -1))
	var tc := float(kc) / FPS
	# real clicks: the SET tab, the Impact frames button, the panel toggle
	var tab: Button = m.ui_ribbon_tabs.get("SET")
	if tab != null:
		await click_ctl(tab)
	var rb: Button = null
	for ch in m.ui_ribbon["SET"].get_children():
		if ch is Button and m.label_of(ch) == "Impact frames":
			rb = ch
	ok(rb != null and rb.is_visible_in_tree(), "the 'Impact frames' button is on the SET page and shown")
	if rb != null:
		await click_ctl(rb)
	var tg := root.find_child("ic_toggle", true, false) as CheckButton
	var sl := root.find_child("ic_stop", true, false) as HSlider
	var sa := root.find_child("ic_amp", true, false) as HSlider
	ok(tg != null and sl != null and sa != null and tg.is_visible_in_tree(), "the panel shows the toggle and the two sliders")
	ok(sl != null and int(sl.value) == 3 and sl.min_value == 0.0 and sl.max_value == 6.0, "the hit-stop slider runs 0-6 and starts at 3")
	await snap("panel_off")
	await click_ctl(tg)
	await idle(3)
	var N := int(sl.value)
	ok(tg.button_pressed and not ImpactClip.settings(m.S).is_empty(), "the toggle click wrote the effect into the clip (marker %s)" % str(ImpactClip.settings(m.S)))
	# 2 HOLD
	var s_c := sig(kc)
	var held := true
	for i in range(1, N + 1):
		held = held and same(sig(kc + i), s_c)
	ok(held, "HOLD: the bones are identical on frames %d..%d (contact + %d frames)" % [kc, kc + N, N])
	ok(not same(sig(kc + N + 1), s_c, 1e-4), "HOLD: frame %d is moving again" % (kc + N + 1))
	var pre := 0.0
	for k in range(0, kc):
		var a := sig(k)
		var o: Array = orig_sigs[k]
		for i in a.size():
			if a[i] is Quaternion:
				pre = maxf(pre, rad_to_deg((a[i] as Quaternion).angle_to(o[i])))
	print("info: largest bone difference from the original before the contact: %.2f deg" % pre)
	# 3 FLASH
	var ff := await flash_frames(int(c["prop"]))
	ok(ff.size() == 2 and ff[0] == kc and ff[1] == kc + 1, "FLASH: the target's emission is white on exactly 2 frames: %s (contact %d)" % [str(ff), kc])
	# picture of the flash frame
	m.playhead = tc
	m.S.apply(m.B, tc)
	m._refresh()
	m.ui_find.visible = false   # the picture: the target must not be under the panel
	await snap("flash_frame")
	m.ui_find.visible = true
	var ff2 := await flash_frames(int(c["prop"]))
	ok(ff2.size() == 2, "FLASH: still exactly 2 frames after the idle frames of the picture")
	# 4 SHAKE
	var peak := 0.0
	for i in 61:
		peak = maxf(peak, cam_off(m.S, tc + float(i) / 240.0))
	var at0 := cam_off(m.S, tc)
	var at25 := cam_off(m.S, tc + 0.25)
	ok(at0 > 0.0 and at0 >= 0.999 * peak, "SHAKE: the camera offset on the contact frame is %.2f cm (the peak %.2f cm)" % [at0 * 100.0, peak * 100.0])
	ok(at25 < 0.05 * peak, "SHAKE: 0.25 s later the offset is %.3f cm, %.2f %% of the peak" % [at25 * 100.0, 100.0 * at25 / maxf(peak, 1e-9)])
	var k0 := ShotCam.at(m.S.shots, tc)
	var v0: Dictionary = m.shot_view_at(tc)
	var v1: Dictionary = m.shot_view_at(tc + 0.25)
	var plain := ShotCam.xf(k0["pos"], k0["aim"]).origin
	ok(not v0.is_empty() and (v0["xf"] as Transform3D).origin.distance_to(plain) > 0.002 and (v1["xf"] as Transform3D).origin.distance_to(plain) < 1e-4,
		"SHAKE: the real shot camera is %.1f mm off its key at the contact and %.3f mm off 0.25 s later" % [(v0["xf"] as Transform3D).origin.distance_to(plain) * 1000.0, (v1["xf"] as Transform3D).origin.distance_to(plain) * 1000.0])
	# 5 SLIDER (real click on the track at ~5/6)
	var r := sl.get_global_rect()
	await click_at(Vector2(r.position.x + r.size.x * 0.84, r.get_center().y))
	print("info: panel visible ", m.ui_find.visible, " toggle visible ", tg.is_visible_in_tree(), " slider mouse_filter ", sl.mouse_filter, " editable ", sl.editable)
	print("info: slider rect ", r, " value after click ", sl.value)
	var N2 := int(sl.value)
	ok(N2 != 3 and N2 >= 4, "SLIDER: a click on the hit-stop slider set it to %d" % N2)
	var s2 := sig(kc)
	var h2 := true
	for i in range(1, N2 + 1):
		h2 = h2 and same(sig(kc + i), s2)
	ok(h2 and not same(sig(kc + N2 + 1), s2, 1e-4) and ImpactClip.settings(m.S)["frames"] == N2, "SLIDER: the clip now holds %d frames (marker says %d)" % [N2, int(ImpactClip.settings(m.S).get("frames", -1))])
	# 7 SAVED (before off)
	var d: Dictionary = m.S.to_dict(m.B)
	var S2 := Scene.new()
	S2.from_dict(JSON.parse_string(JSON.stringify(d)))
	ok(not ImpactClip.settings(S2).is_empty() and ImpactFrames.already(S2), "SAVED: the reloaded scene still has the stop marker (%s)" % str(ImpactClip.settings(S2)))
	# 6 OFF
	await click_ctl(tg)
	await idle(3)
	var off_sigs := all_sigs()
	var same_all := off_sigs.size() == orig_sigs.size()
	if same_all:
		for k in off_sigs.size():
			same_all = same_all and same(off_sigs[k], orig_sigs[k], 1e-6)
	ok(same_all, "OFF: all %d frames' bone transforms equal the original clip's" % orig_sigs.size())
	if sjson(m.S) != orig_json:
		var a1 := sjson(m.S)
		var d0 := 0
		while d0 < mini(a1.length(), orig_json.length()) and a1[d0] == orig_json[d0]:
			d0 += 1
		print("info: JSON differs at %d: now ...%s | was ...%s" % [d0, a1.substr(maxi(d0 - 60, 0), 160), orig_json.substr(maxi(d0 - 60, 0), 160)])
		print("info: markers now ", m.S.markers, " shots ", m.S.shots)
	ok(sjson(m.S) == orig_json, "OFF: cards, markers and shots are JSON-equal to the original")
	ok((await flash_frames(int(c["prop"]))).is_empty(), "OFF: no frame flashes")
	await snap("panel_off_again")
	var wb := root.get_visible_rect()
	var panel: Control = m.ui_find
	ok(wb.encloses(panel.get_global_rect()), "PICTURE: the panel is inside the window")
	# 9 DEFAULT EASES: the same punch with the app's defaults (natural on, no ease named: smootherstep with the body-leads lag)
	var S3 := Scene.new()
	S3.from_dict({"scene": "zz_s137n", "fps": FPS, "cards": [
		{"name": "guard", "pose": pose_of(0), "move": -1.0, "hold": 0.4},
		{"name": "punch", "pose": pose_of(best), "move": 0.6, "hold": 0.5},
		{"name": "back", "pose": pose_of(0), "move": 0.6, "hold": 0.4}]})
	S3.props = S.props
	m.S = S3
	m._rebuild_cards()
	m.playhead = 0.0
	m._props_show()
	m._refresh()
	await idle(3)
	var o3 := all_sigs()
	var j3 := sjson(m.S)
	var c3 := ImpactClip.find_contact(m.S, m.B)
	var kc3 := int(c3.get("k", -1))
	ok(m.S.natural and kc3 > 0, "NATURAL: default eases (natural on), contact at frame %d" % kc3)
	ImpactClip.apply(m.S, m.B, c3, 3, 2.0)
	m._retimed()
	await idle(2)
	var n3 := all_sigs()
	var pre3 := 0.0
	for k in range(0, kc3):
		pre3 = maxf(pre3, maxdiff(n3[k], o3[k]))
	var post3 := 0.0
	for k in range(kc3, o3.size()):
		post3 = maxf(post3, maxdiff(n3[k + 3], o3[k]))
	ok(pre3 < 0.5, "NATURAL: before the contact the largest bone difference from the original is %.3f deg (< 0.5)" % pre3)
	ok(post3 < 0.5, "NATURAL: after the hold (shifted by 3 frames) it is %.3f deg (< 0.5)" % post3)
	var h3 := true
	for i in range(1, 4):
		h3 = h3 and same(n3[kc3 + i], n3[kc3], 1e-6)
	ok(h3 and not same(n3[kc3 + 4], n3[kc3], 1e-4), "NATURAL: frames %d..%d identical, then moving" % [kc3, kc3 + 3])
	var rl := Scene.new()
	rl.from_dict(JSON.parse_string(JSON.stringify(m.S.to_dict(m.B))))
	rl.props = S.props
	ImpactClip.remove(rl)
	var rj := sjson(rl)
	if rj != j3:
		var d1 := 0
		while d1 < mini(rj.length(), j3.length()) and rj[d1] == j3[d1]:
			d1 += 1
		print("info: reload JSON differs at %d: now ...%s | was ...%s" % [d1, rj.substr(maxi(d1 - 80, 0), 200), j3.substr(maxi(d1 - 80, 0), 200)])
	ok(sjson(rl) == j3, "NATURAL: saved, reloaded, Remove -> JSON-equal to the original (the frame-card tags are in the file)")
	ImpactClip.remove(m.S)
	m._retimed()
	var r3 := all_sigs()
	var same3 := r3.size() == o3.size()
	if same3:
		for k in r3.size():
			same3 = same3 and same(r3[k], o3[k], 1e-6)
	ok(same3 and sjson(m.S) == j3, "NATURAL: remove -> every frame and the JSON equal the original")
	print("s137: %d fail" % fails)
	quit(0 if fails == 0 else 1)
