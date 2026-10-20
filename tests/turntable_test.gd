## godot --path . -s tests/turntable_test.gd     (ROADMAP_400 K08, the command "Deliver: turntable video of this pose"; needs a window: it renders)
## A standing body holding a bat in the right hand is delivered as a turntable through the command's own function (defaults:
## 6 s, 30 fps, 1280x720) into user://turntables/ (never scenes/, poses/, data/).
##   1 FRAME COUNT = seconds * fps (180 at the defaults); a short run (1 s at 12 fps) gives 12
##   2 the camera yaw of the first and the last frame (read from each frame's camera) differs by 360 * (n-1) / n degrees
##   3 PLACEMENT, in the frames at 0, 90, 180, 270 deg: the body's pelvis projects within 10% of the image centre (per axis),
##     and the head top, both soles and the bat's tip project INSIDE the frame (the whole body is visible); each frame is the
##     requested size and shows something (not a flat colour)
##   4 the .avi exists, is > 0 bytes and starts with RIFF....AVI ; the playback state comes back (panels visible, playhead)
##   5 only user:// was written: the result paths are under user://turntables/, and the file counts of scenes/, poses/, data/ are unchanged
## Screenshot: the 4-up (0/90/180/270 deg) goes to OUT.
extends SceneTree

var fails := 0
var m: Node
const OUT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/turntable.png"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func count_files(d: String) -> int:
	var tot := 0
	for f in DirAccess.get_files_at(d):
		tot += 1
	for sub in DirAccess.get_directories_at(d):
		tot += count_files(d + "/" + sub)
	return tot


func frac(r: Dictionary, k: int, p: Vector3) -> Vector2:
	m.cam.transform = r["cams"][k]
	m.cam.h_offset = 0.0
	m.cam.v_offset = 0.0
	var rc: Rect2i = r["crop"]
	var s: Vector2 = m.cam.unproject_position(p)
	return Vector2((s.x - rc.position.x) / rc.size.x, (s.y - rc.position.y) / rc.size.y)


func yaw_deg(t: Transform3D) -> float:
	return rad_to_deg(t.basis.get_euler().y)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var S := Scene.new()
	S.name = "zz_turntable"
	S.fps = 24
	var R := Body.new()
	R.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	R.set_ang("upperarm_r", Vector3(0, 0, 60))
	R.set_ang("thigh_l", Vector3(20, 0, 0))
	R.fk()
	S.add("c0", R.to_dict())
	S.add("c1", R.to_dict())
	m.S = S
	m._rebuild_cards()
	m.sel_card = 0
	m.playhead = 0.0
	m._refresh()
	m.B.wep_on = true
	m.B.weapon_to_hand("hand_r")
	m._refresh()
	await idle(3)
	var counts0 := [count_files("res://scenes"), count_files("res://poses"), count_files("res://data")]
	var ph: float = m.playhead

	# a short run first: 1 s at 12 fps -> 12 frames, size 640x360
	var rs: Dictionary = await m._export_turntable(1.0, 12, Vector2i(640, 360))
	ok(rs.get("frames", -1) == 12 and rs.get("cams", []).size() == 12, "1 short run: 1 s x 12 fps = %d frames (want 12)" % rs.get("frames", -1))

	# the defaults: 6 s x 30 fps at 1280x720
	var t0 := Time.get_ticks_msec()
	var r: Dictionary = await m._export_turntable()
	print("     default render took %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	var n: int = r.get("frames", 0)
	ok(n == 180 and r.get("cams", []).size() == 180, "1 defaults: 6 s x 30 fps = %d frames (want 180), size %s" % [n, r.get("size")])
	if n == 0:
		quit(1)
		return
	var cams: Array = r["cams"]
	var dy := fposmod(yaw_deg(cams[n - 1]) - yaw_deg(cams[0]) + 180.0, 360.0) - 180.0
	var want := fposmod(360.0 * (n - 1) / n + 180.0, 360.0) - 180.0
	print("     first yaw %.3f, last yaw %.3f, difference %.3f (want %.3f = 360 * %d / %d, wrapped)" % [yaw_deg(cams[0]), yaw_deg(cams[n - 1]), dy, want, n - 1, n])
	ok(absf(dy - want) < 0.01, "2 last yaw - first yaw = %.3f deg, want 360*(n-1)/n = %.3f (wrapped), bar 0.01" % [dy, want])
	var step_ok := true
	for k in range(1, n):
		var ds := fposmod(yaw_deg(cams[k]) - yaw_deg(cams[k - 1]) + 180.0, 360.0) - 180.0
		if absf(ds - fposmod(360.0 / n + 180.0, 360.0) + 180.0) > 0.01 and absf(ds - 360.0 / n) > 0.01:
			step_ok = false
	ok(step_ok, "2b every step is %.2f deg (a uniform orbit)" % (360.0 / n))

	# 3 placement at 0, 90, 180, 270
	var Bd: Body = m.B
	var tip: Vector3 = Bd.wep_point(Bd.wep_len)
	var head: Vector3 = Bd.E["head"]
	var soles := [Bd.E["ball_l"], Bd.E["ball_r"], Bd.P["foot_l"], Bd.P["foot_r"]]
	var quarters: Dictionary = r["quarters"]
	var keys := quarters.keys()
	keys.sort()
	ok(keys == [0, n / 4, n / 2, 3 * n / 4], "3 the quarter frames are %s" % [keys])
	for k in keys:
		var c := frac(r, k, Bd.P["pelvis"])
		var pts := {"head top": head, "bat tip": tip, "sole_l": soles[0], "sole_r": soles[1], "heel_l": soles[2], "heel_r": soles[3]}
		var inside := true
		var worst := 1.0
		for nm in pts:
			var f := frac(r, k, pts[nm])
			worst = minf(worst, minf(minf(f.x, 1.0 - f.x), minf(f.y, 1.0 - f.y)))
			if f.x < 0.0 or f.x > 1.0 or f.y < 0.0 or f.y > 1.0:
				inside = false
		ok(absf(c.x - 0.5) < 0.1 and absf(c.y - 0.5) < 0.1, "3 yaw %3.0f: pelvis at (%.3f, %.3f) of the frame (bar: within 0.1 of 0.5)" % [fposmod(yaw_deg(cams[k]), 360.0), c.x, c.y])
		ok(inside, "  head top, soles, bat tip all inside the frame (nearest edge margin %.3f of the frame)" % worst)
		var img: Image = quarters[k]
		var px := img.get_pixel(img.get_width() / 2, img.get_height() / 2)
		var flat := true
		for q in 40:
			if img.get_pixel(int(img.get_width() * (q + 1) / 41.0), int(img.get_height() * 0.5)) != px:
				flat = false
		ok(img.get_size() == r["size"] and not flat, "  the image is %s and not a flat colour" % [img.get_size()])

	# 4 the file
	var avi: String = r.get("avi", "")
	var fa := FileAccess.open(avi, FileAccess.READ) if avi != "" else null
	var sz := fa.get_length() if fa != null else 0
	var hb := fa.get_buffer(12) if fa != null else PackedByteArray()
	var head4 := (hb.slice(0, 4).get_string_from_ascii() + hb.slice(8, 12).get_string_from_ascii()) if hb.size() == 12 else ""
	ok(sz > 0 and head4 == "RIFFAVI ", "4 the video %s is %d bytes, header '%s'" % [avi.get_file(), sz, head4])
	ok(m.ui_root.visible and not m.clean and absf(m.playhead - ph) < 1e-9, "4 the app comes back (panels visible, playhead %.2f)" % m.playhead)

	# 5 only user://
	ok(avi.begins_with("user://turntables/") and (r.get("mp4", "") == "" or String(r["mp4"]).begins_with("user://turntables/")), "5 written under user://turntables/ only (%s)" % avi.get_base_dir())
	var counts1 := [count_files("res://scenes"), count_files("res://poses"), count_files("res://data")]
	ok(counts0 == counts1, "5 file counts of scenes/, poses/, data/ unchanged: %s -> %s" % [counts0, counts1])

	# the 4-up screenshot
	var sheet := Image.create(1280, 720, false, Image.FORMAT_RGB8)
	for i in 4:
		var q: Image = quarters[keys[i]].duplicate()
		q.resize(640, 360, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(q, Rect2i(0, 0, 640, 360), Vector2i((i % 2) * 640, (i / 2) * 360))
	sheet.save_png(OUT)
	print("     4-up saved: %s" % OUT)
	print("TURNTABLE: %s" % ("PASS" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails > 0 else 0)
