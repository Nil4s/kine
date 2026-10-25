## godot --path . -s tests/r3_test.gd     (ROADMAP R3: motion blur in the playblast; needs a window, it renders)
## combo3's fastest swing frame (the frame where the bat tip is fastest, WeaponTrail.sample), rendered through the playblast's
## own frame function main._blast_frame with the blur off and on (8 sub-frames, 180 degree shutter = 1/(2 fps), centred).
## BARS (stated before measuring):
##   1 shutter maths: shutter_time(30) = 1/60 s; the sub-frame times span exactly that, centred on t
##   2 blur OFF is byte-identical to a hand capture of the viewport scrubbed to t (the old path), and off is the default
##   3 SMEAR LENGTH: the bat's footprint (frame with the bat vs the same frame with it hidden) in a band along the tip's path; the
##     edge on the tip's side moves out by half the smear (the shutter is centred), so smear = 2 x that shift, within 30% of
##     (tip screen speed x shutter time). Screen speed = the projected tip's central difference over +-2 ms, independent of the
##     sub-frame times
##   4 STATIC BACKGROUND: every pixel that is the same in all 8 sharp sub-frame renders is exactly the same in the blurred frame
##     (and that is > 50% of the frame); anti-vacuity: > 200 pixels do change
##   5 PLACEMENT: the tip is on screen in the whole-body view, and the smear lies on the tip's path (its extent is found there)
## Screenshot: user path in C:/Users/Nick/.claude/jobs/9afc22db/tmp/r3.png (sharp | blurred, whole frame, then a crop at the tip)
extends SceneTree

var fails := 0
var m: Node
const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/r3.png"
const BAND := 8.0      # px: half-width of the band around the tip's path in which the extent is measured
const DIFF_MIN := 10   # summed |dRGB| (of 765) for a pixel to count as "the bat is here"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func set_weapon_hidden(h: bool) -> void:
	for n in [m.bat_handle, m.bat_barrel, m.bat_knob]:
		(n as VisualInstance3D).layers = 0 if h else 1   # layer 0: not drawn by any camera
	m._refresh()


## the extent (px) along u of the pixels where a and b differ by >= DIFF_MIN, inside the band around the line through c along u,
## and within +-reach of c; returns [min_along, max_along, count]
func extent(a: Image, b: Image, c: Vector2, u: Vector2, reach: float) -> Array:
	var da := a.get_data()
	var db := b.get_data()
	var w := a.get_width()
	var h := a.get_height()
	var step := 4 if a.get_format() == Image.FORMAT_RGBA8 else 3
	var lo := 1e9
	var hi := -1e9
	var cnt := 0
	var x0 := maxi(0, int(c.x - reach - BAND))
	var x1 := mini(w - 1, int(c.x + reach + BAND))
	var y0 := maxi(0, int(c.y - reach - BAND))
	var y1 := mini(h - 1, int(c.y + reach + BAND))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var i := (y * w + x) * step
			var d := absi(int(da[i]) - int(db[i])) + absi(int(da[i + 1]) - int(db[i + 1])) + absi(int(da[i + 2]) - int(db[i + 2]))
			if d < DIFF_MIN:
				continue
			var q := Vector2(x, y) - c
			var along := q.dot(u)
			if absf(q.dot(Vector2(-u.y, u.x))) <= BAND and absf(along) <= reach:
				lo = minf(lo, along)
				hi = maxf(hi, along)
				cnt += 1
	return [lo, hi, cnt]


func tip_px(S: Scene, t: float) -> Vector2:
	S.apply(m.B, t)
	return m.cam.unproject_position(m.B.wep_point(m.B.wep_len))


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
	var fps: int = S.fps
	var sm := WeaponTrail.sample(S, m.B)
	var sp: Array = sm["speed"]
	var fbest := 1
	for i in range(1, sp.size() - 1):
		if sp[i] > sp[fbest]:
			fbest = i
	var t0: float = sm["t"][fbest]
	var length := S.length()
	print("     combo3: %d fps, fastest tip frame %d (t %.4f s) at %.2f m/s" % [fps, fbest, t0, sp[fbest]])

	# 1 shutter maths
	var st := PlayblastExport.shutter_time(fps)
	var ts := PlayblastExport.shutter_times(t0, fps, 8, 0.0, length)
	ok(absf(st - 1.0 / (2.0 * fps)) < 1e-12 and absf(PlayblastExport.shutter_time(24) - 1.0 / 48.0) < 1e-12, "1 a 180 degree shutter is 1/(2 fps): %.5f s at %d fps, 1/48 s at 24 fps" % [st, fps])
	ok(ts.size() == 8 and absf((ts[7] - ts[0]) - st) < 1e-9 and absf((ts[0] + ts[7]) * 0.5 - t0) < 1e-9, "  8 sub-frame times span %.5f s centred on t (%.4f .. %.4f)" % [ts[7] - ts[0], ts[0], ts[7]])
	ok(m.blast_blur == false, "  motion blur is off by default")

	m.wt.render_on = false   # R23 draws a weapon-trail ribbon in renders by default; this test is about blur alone, so the ribbon is off (r3 compares against a bare viewport capture)
	# the clean whole-body view, as the playblast renders it
	m.clean = true
	m._sides_apply()
	m.ui_root.visible = false
	var shot := {}
	m.dist = 8.0   # the swing goes overhead: back off so the whole body and the bat are in the frame
	m.target = Vector3(0, 1.4, 0)
	m._refresh()
	m._cam()
	await idle(3)
	var tpx := tip_px(S, t0)
	var vp := root.get_viewport().get_visible_rect().size
	ok(tpx.x > 40 and tpx.y > 40 and tpx.x < vp.x - 40 and tpx.y < vp.y - 40, "5 placement: the tip is on screen in the whole-body view at %s (window %s)" % [tpx, vp])

	# 2 blur off == the old path (a hand capture)
	var sharp: Image = await m._blast_frame(shot, t0, fps, 0.0, length)
	m.playhead = t0
	m._ps().apply(m.B, t0)
	m._refresh()
	await process_frame
	await RenderingServer.frame_post_draw
	var hand: Image = root.get_viewport().get_texture().get_image()
	ok(sharp.get_data() == hand.get_data() and sharp.get_size() == hand.get_size(), "2 blur off is byte-identical to the viewport scrubbed there by hand (%d bytes)" % hand.get_data().size())

	# screen speed of the tip, independent of the sub-frame times
	var h := 0.002   # s: the instantaneous speed at the peak frame (the +-1/fps central difference averages the peak away)
	var pa := tip_px(S, t0 - h)
	var pb := tip_px(S, t0 + h)
	var v_px := (pb - pa).length() / (2.0 * h)
	var expect := v_px * st
	var u := (pb - pa).normalized()
	print("     tip screen speed %.0f px/s -> expected smear %.1f px (speed x %.4f s)" % [v_px, expect, st])

	# the sharp sub-frames (for the static-background set) and the bat's own width on the sharp frame
	var subs := []
	for tt in ts:
		subs.append(await m._blast_frame(shot, tt, fps, 0.0, length))
	set_weapon_hidden(true)
	var sharp_nb: Image = await m._blast_frame(shot, t0, fps, 0.0, length)
	set_weapon_hidden(false)
	var e0 := extent(sharp, sharp_nb, tpx, u, expect * 3.0 + 40.0)

	# blur on, with and without the bat
	m.blast_blur = true
	var blur: Image = await m._blast_frame(shot, t0, fps, 0.0, length)
	set_weapon_hidden(true)
	var blur_nb: Image = await m._blast_frame(shot, t0, fps, 0.0, length)
	set_weapon_hidden(false)
	m.blast_blur = false
	var e1 := extent(blur, blur_nb, tpx, u, expect * 3.0 + 40.0)
	var w0: float = e0[1] - e0[0] if e0[2] > 0 else 0.0
	var w1: float = e1[1] - e1[0] if e1[2] > 0 else 0.0
	print("     lo/hi sharp %.1f/%.1f blurred %.1f/%.1f; chord ends along u %.1f / %.1f" % [e0[0], e0[1], e1[0], e1[1], (tip_px(S, ts[0]) - tpx).dot(u), (tip_px(S, ts[7]) - tpx).dot(u)])
	# the bat's body also sweeps, so only the edge on the TIP's side is read: the sharp mask's end nearest the tip's own pixel.
	# The shutter is centred on t, so that edge moves out by half the tip's travel on that side: smear = 2 x the shift
	var lo_side: bool = absf(e0[0]) < absf(e0[1])
	var shift: float = absf(float(e1[0]) - float(e0[0])) if lo_side else absf(float(e1[1]) - float(e0[1]))
	var smear := 2.0 * shift
	print("     tip band extent: sharp %.1f px (%d px), blurred %.1f px (%d px); tip-side (%s) edge shifts %.1f px -> smear %.1f px" % [w0, e0[2], w1, e1[2], "trailing" if lo_side else "leading", shift, smear])
	ok(e1[2] > 0 and absf(smear - expect) <= 0.3 * expect, "3 smear length %.1f px vs speed x shutter %.1f px: off by %.0f%% (bar 30%%)" % [smear, expect, 100.0 * absf(smear - expect) / maxf(expect, 1e-6)])

	# 4 static background
	var bg := 0
	var moved := 0
	var bad := 0
	var d_blur := blur.get_data()
	var fmt_step := 4 if blur.get_format() == Image.FORMAT_RGBA8 else 3
	var datas := []
	for im in subs:
		(im as Image).convert(blur.get_format())
		datas.append((im as Image).get_data())
	var npx := blur.get_width() * blur.get_height()
	for p in npx:
		var i := p * fmt_step
		var same := true
		for k in range(1, datas.size()):
			if datas[k][i] != datas[0][i] or datas[k][i + 1] != datas[0][i + 1] or datas[k][i + 2] != datas[0][i + 2]:
				same = false
				break
		if same:
			bg += 1
			if d_blur[i] != datas[0][i] or d_blur[i + 1] != datas[0][i + 1] or d_blur[i + 2] != datas[0][i + 2]:
				bad += 1
		elif d_blur[i] != datas[0][i] or d_blur[i + 1] != datas[0][i + 1] or d_blur[i + 2] != datas[0][i + 2]:
			moved += 1
	ok(bg > npx / 2 and bad == 0, "4 static background: %d of %d pixels are identical in all 8 sub-frames, %d of them changed by the blur (bar 0)" % [bg, npx, bad])
	ok(moved > 200, "  anti-vacuity: %d moving pixels differ from the sharp frame (> 200)" % moved)

	# screenshot: sharp | blurred, then a crop at the tip
	var sw := 640
	var shh := int(vp.y * sw / vp.x)
	var a2 := sharp.duplicate() as Image
	var b2 := blur.duplicate() as Image
	a2.convert(Image.FORMAT_RGB8)
	b2.convert(Image.FORMAT_RGB8)
	var cr := Rect2i(int(tpx.x) - 160, int(tpx.y) - 120, 320, 240).intersection(Rect2i(Vector2i.ZERO, a2.get_size()))
	var ca := a2.get_region(cr)
	var cb := b2.get_region(cr)
	ca.resize(cr.size.x * 2, cr.size.y * 2, Image.INTERPOLATE_NEAREST)
	cb.resize(cr.size.x * 2, cr.size.y * 2, Image.INTERPOLATE_NEAREST)
	a2.resize(sw, shh)
	b2.resize(sw, shh)
	var out := Image.create(sw * 2, shh + cr.size.y * 2, false, Image.FORMAT_RGB8)
	out.fill(Color.BLACK)
	out.blit_rect(a2, Rect2i(0, 0, sw, shh), Vector2i(0, 0))
	out.blit_rect(b2, Rect2i(0, 0, sw, shh), Vector2i(sw, 0))
	out.blit_rect(ca, Rect2i(Vector2i.ZERO, ca.get_size()), Vector2i(0, shh))
	out.blit_rect(cb, Rect2i(Vector2i.ZERO, cb.get_size()), Vector2i(sw, shh))
	out.save_png(SHOT)
	print("     screenshot: " + SHOT)

	m.ui_root.visible = true
	m.clean = false
	m._sides_apply()
	print("r3: %d FAILS" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
