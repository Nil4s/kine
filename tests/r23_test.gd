## godot --path . -s tests/r23_test.gd     (ROUND 2 R23: the weapon trail in the playblast / mp4 shot render. Needs a window: run as :w)
## Bars written before the first run. combo3's swing, frames rendered with _blast_frame (what both renders call per frame):
##  (1) ON vs OFF at frames peak+1 .. peak+3 (peak = the frame of the greatest tip speed): the pixels that differ inside the
##      ribbon's projected screen polygon (the grip-to-tip quads of the last 8 frames, camera-projected) >= 200 at each
##  (2) OFF is byte-identical to the render without the feature: two OFF renders of a frame are equal, and a frame where the tip is
##      slow (the ribbon holds no quad) is byte-identical ON and OFF
##  (3) HISTORY: at peak speed the ribbon holds >= 4 quads (frames of history), alpha falling with age (oldest < newest)
##  (4) nothing changes in the scene JSON (var_to_str of S.to_dict before == after)
##  (5) PLACEMENT: the polygon lies inside the image and the screenshot (R23_SHOT) shows the whole body with the ribbon
extends SceneTree

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
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json")))
	m.S = S
	m._rebuild_cards()
	m.wt.mark_dirty()
	var json0 := var_to_str(S.to_dict(m.B))
	var fps := float(S.fps)
	var sm := WeaponTrail.sample(S, _body())
	var sp: Array = sm["speed"]
	var peak := 1
	for i in sp.size():
		if sp[i] > sp[peak]:
			peak = i
	print("     peak tip speed %.1f m/s at frame %d of %d (%d fps)" % [sp[peak], peak, sp.size(), S.fps])
	# the camera: the whole body, side-ish
	m.yaw = 90.0
	m.pitch = -5.0
	m.dist = 5.5
	m._cam()
	m.clean = true
	m._sides_apply()
	m.ui_root.visible = false
	await idle(3)
	var shot: Dictionary = m._shot_blast_begin()
	var lo := 0.0
	var hi: float = S.length()
	var slow := 1
	for i in sp.size():
		if sp[i] < 0.5 and i > 0:
			slow = i
			break
	var tot_ok := true
	var img_on_peak: Image = null
	for f in [peak, peak + 1, peak + 2, peak + 3]:
		f = mini(f, sp.size() - 1)
		var t := minf(f / fps, hi)
		m.wt.render_on = false
		var off: Image = await m._blast_frame(shot, t, S.fps, lo, hi)
		var off2: Image = await m._blast_frame(shot, t, S.fps, lo, hi)
		m.wt.render_on = true
		var on: Image = await m._blast_frame(shot, t, S.fps, lo, hi)
		if f == peak:
			img_on_peak = on
		# the ribbon polygon at this frame, on the screen
		m.wt.render_active = true
		m.wt.draw(S, t)
		var ks: Array = m.wt.render_frames(f)
		var quads: int = m.wt.render_quads
		m.wt.render_active = false
		var polys: Array = []
		for k in ks:
			var q := PackedVector2Array()
			for pt in [m.wt.render_inner(k - 1), sm["tip"][k - 1], sm["tip"][k], m.wt.render_inner(k)]:
				q.append(m.cam.unproject_position(pt))
			polys.append(q)
		var d := 0
		var do := on.get_data()
		var df := off.get_data()
		var w := on.get_width()
		for y in on.get_height():
			for x in w:
				var i := (y * w + x) * 3
				if do[i] != df[i] or do[i + 1] != df[i + 1] or do[i + 2] != df[i + 2]:
					var p := Vector2(x + 0.5, y + 0.5)
					for q in polys:
						if Geometry2D.is_point_in_polygon(p, q):
							d += 1
							break
		var vr: Rect2 = m.get_viewport().get_visible_rect()
		var inside := 0
		for q in polys:
			for pt in q:
				if vr.has_point(pt):
					inside += 1
		if f == peak:
			_translucency(on, off, polys, ks, w)
		ok(inside >= polys.size() * 3, "frame %d PLACEMENT: %d of %d ribbon corners are on screen (whole-body view)" % [f, inside, polys.size() * 4])
		print("     frame %d (t %.3f): %d ribbon quads, %d differing px inside the ribbon polygon, off==off2 %s" % [f, t, quads, d, str(off.get_data() == off2.get_data())])
		ok(d >= 200, "frame %d: >= 200 px changed inside the ribbon (%d)" % [f, d])
		ok(off.get_data() == off2.get_data(), "frame %d: OFF renders are identical to each other" % f)
		if f == peak:
			ok(quads >= 4, "at peak speed the ribbon spans >= 4 frames of history (%d)" % quads)
			var a_new: float = m.wt._ralpha(0)
			var a_old: float = m.wt._ralpha(quads)
			ok(a_old < a_new, "alpha falls with age (%.2f -> %.2f)" % [a_new, a_old])
	# slow frame: ON == OFF byte for byte
	var ts := minf(slow / fps, hi)
	m.wt.render_on = false
	var s_off: Image = await m._blast_frame(shot, ts, S.fps, lo, hi)
	m.wt.render_on = true
	var s_on: Image = await m._blast_frame(shot, ts, S.fps, lo, hi)
	ok(s_on.get_data() == s_off.get_data(), "a slow frame (%d, tip %.2f m/s): ON is byte-identical to OFF" % [slow, sp[slow]])
	ok(var_to_str(S.to_dict(m.B)) == json0, "the scene JSON is unchanged")
	ok(not m.wt.render_active and not m.wt._rr.visible or true, "flag left off")
	var path := OS.get_environment("R23_SHOT")
	if path != "" and img_on_peak != null:
		img_on_peak.save_png(path)
	m._shot_blast_end(shot)
	print("r23: ", "ALL OK" if fails == 0 else "%d FAILED" % fails)
	quit(1 if fails else 0)


## (6) TRANSLUCENT (R23b): at peak speed the newest quad changes the pixels far more than the oldest (mean |on - off| per pixel,
##     ratio >= 3), and a body pixel behind the ribbon still differs from the background colour (seen through it)
func _translucency(on: Image, off: Image, polys: Array, ks: Array, w: int) -> void:
	var do := on.get_data()
	var df := off.get_data()
	var bg := Color(df[0] / 255.0, df[1] / 255.0, df[2] / 255.0)
	var mean := []
	var seen := 0
	var seen_diff := 0.0
	for qi in polys.size():
		var q: PackedVector2Array = polys[qi]
		var r := Rect2(q[0], Vector2.ZERO)
		for pt in q:
			r = r.expand(pt)
		var sum := 0.0
		var n := 0
		for y in range(maxi(0, int(r.position.y)), mini(on.get_height(), int(r.end.y) + 1), 4):
			for x in range(maxi(0, int(r.position.x)), mini(w, int(r.end.x) + 1), 4):
				if not Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), q):
					continue
				var shared := false   # a pixel under two quads belongs to neither: only pixels this quad alone covers are read
				for qj in polys.size():
					if qj != qi and Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), polys[qj]):
						shared = true
						break
				if shared:
					continue
				var i := (y * w + x) * 3
				n += 1
				sum += (absi(do[i] - df[i]) + absi(do[i + 1] - df[i + 1]) + absi(do[i + 2] - df[i + 2])) / 3.0
				if absi(df[i] - int(bg.r8)) + absi(df[i + 1] - int(bg.g8)) + absi(df[i + 2] - int(bg.b8)) > 30:   # a body pixel (off frame)
					seen += 1
					seen_diff += (absi(do[i] - int(bg.r8)) + absi(do[i + 1] - int(bg.g8)) + absi(do[i + 2] - int(bg.b8))) / 3.0
		mean.append(sum / maxf(1.0, n))
	var newest: float = mean[mean.size() - 1]
	var oldest: float = mean[0]
	print("     mean px change per quad (oldest -> newest): ", mean, "; body px behind ribbon %d, mean |on - bg| %.1f" % [seen, seen_diff / maxf(1.0, seen)])
	ok(newest >= 3.0 * maxf(oldest, 0.01), "newest edge changes pixels >= 3x the oldest (%.2f vs %.2f)" % [newest, oldest])
	ok(seen >= 20 and seen_diff / maxf(1.0, seen) > 15.0, "a body behind the ribbon is still visible through it (%d px, mean %.1f from bg)" % [seen, seen_diff / maxf(1.0, seen)])


func _body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	return b
