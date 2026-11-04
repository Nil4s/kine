extends SceneTree
## CH12 video: the footbridge in plan with a phase-locking crowd, deck sway exaggerated, amplitude-vs-time plot with N marked (locked crowd, random-phase control, retrofit).
## godot --position -30000,-30000 --audio-driver Dummy --resolution 1280x720 --path . -s tools/ch12_video.gd -- <outdir> [exaggeration=40] [n_over_nc=8] [seconds=20]
## Real time: 20 s of the locked run at 20 frames per second. Encode: ffmpeg -y -framerate 20 -i <outdir>/frames/f%05d.png -c:v libx264 -pix_fmt yuv420p <outdir>/ch12_sway.mp4
const BR := preload("res://scripts/build/ch12_bridge.gd")

var S := 40.0


class View:
	extends Control
	var br: Dictionary
	var snaps: Array
	var th: Array            # per frame, per walker: lean sign
	var xs: PackedFloat64Array
	var ts: PackedFloat64Array
	var tr: Array            # traces [{name, color, t, a}]
	var cur := 0
	var info := ""
	var nc := 0.0
	var nn := 0
	var S := 40.0
	var members: Array

	func _draw() -> void:
		var f := ThemeDB.fallback_font
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.13, 0.15, 0.19))
		var L := 144.0
		var x0 := 70.0
		var sc := (size.x - 140.0) / (L + 0.0)
		var yc := 190.0
		var sn: PackedFloat64Array = snaps[cur]
		var nseg: int = br["nseg"]
		# river
		draw_rect(Rect2(x0, yc - 60, L * sc, 120), Color(0.16, 0.26, 0.36, 0.55))
		draw_string(f, Vector2(x0 + 6, yc - 46), "PLAN VIEW: lateral sway x%d, deck 4 m wide" % int(S), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.8, 0.85, 0.9))
		# abutments
		for m in members:
			if m["kind"] == "support":
				var b: Array = m["box_m"]
				draw_rect(Rect2(x0 + b[0] * sc, yc + b[2] * sc * 2.2, (b[3] - b[0]) * sc, (b[5] - b[2]) * sc * 2.2), Color(0.55, 0.52, 0.47))
		# deck as polygon of the two girders warped by the lateral displacement (plan scale in z is stretched 2.2x for legibility)
		var zst := sc * 2.2
		var top := PackedVector2Array()
		var bot := PackedVector2Array()
		var mid := PackedVector2Array()
		for s in nseg + 1:
			var x := x0 + s * (L / nseg) * sc
			for k in 3:
				var uz: float = sn[(s * 3 + k) * 6 + 2] * S
				var y := yc + ((k - 1) * 1.9 + uz) * zst
				if k == 0:
					top.append(Vector2(x, y))
				elif k == 1:
					mid.append(Vector2(x, y))
				else:
					bot.append(Vector2(x, y))
		var poly := PackedVector2Array()
		for p in top:
			poly.append(p)
		for i in range(bot.size() - 1, -1, -1):
			poly.append(bot[i])
		draw_colored_polygon(poly, Color(0.42, 0.44, 0.48))
		draw_polyline(top, Color(0.75, 0.78, 0.82), 3.0)
		draw_polyline(bot, Color(0.75, 0.78, 0.82), 3.0)
		draw_polyline(mid, Color(1, 1, 1, 0.18), 1.0)
		# undeflected reference
		draw_line(Vector2(x0, yc), Vector2(x0 + L * sc, yc), Color(1, 1, 0.4, 0.35), 1.0)
		# walkers: a head and a body leaning with the sign of the lateral force
		var lean: PackedFloat64Array = th[cur]
		var n := xs.size()
		for i in n:
			var xx := xs[i]
			var seg := L / nseg
			var s2 := mini(int(xx / seg), nseg - 1)
			var w := xx / seg - s2
			var uz2: float = (1.0 - w) * sn[(s2 * 3 + 1) * 6 + 2] + w * sn[((s2 + 1) * 3 + 1) * 6 + 2]
			var zoff := (float((i * 7) % 5) - 2.0) * 0.55
			var px := x0 + xx * sc
			var py := yc + (zoff + uz2 * S) * zst
			var l := lean[i]
			var c := Color(1.0, 0.55, 0.2) if l > 0.0 else Color(0.35, 0.85, 1.0)
			draw_line(Vector2(px, py + 3), Vector2(px + 0.0, py - 5 + 0.0) + Vector2(0, 0), c, 2.0)
			draw_circle(Vector2(px, py - 7), 2.2, c)
		draw_string(f, Vector2(x0, yc + 78), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
		draw_string(f, Vector2(x0, yc + 98), "walkers: orange = pushing +z, blue = pushing -z (lateral force sign, 25 N amplitude); N = %d, critical N_c = %.0f" % [n, nc], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.8, 0.85, 0.9))


class Plot:
	extends Control
	var tr: Array
	var cur_t := 0.0
	var nc_text := ""
	var ymax := 0.1
	var tmax := 20.0

	func _draw() -> void:
		var f := ThemeDB.fallback_font
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.08, 0.10))
		var p := Rect2(64, 26, size.x - 90, size.y - 52)
		draw_rect(p, Color(0.12, 0.13, 0.16))
		var xm := func(t: float) -> float: return p.position.x + p.size.x * t / tmax
		var ym := func(v: float) -> float: return p.end.y - p.size.y * v / ymax
		for k in 5:
			var vv := ymax * k / 4.0
			draw_line(Vector2(p.position.x, ym.call(vv)), Vector2(p.end.x, ym.call(vv)), Color(1, 1, 1, 0.12), 1.0)
			draw_string(f, Vector2(6, ym.call(vv) + 4), "%.0f mm" % (vv * 1000.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.8, 0.8))
		for tc in tr:
			var pts := PackedVector2Array()
			var ts: PackedFloat64Array = tc["t"]
			var am: PackedFloat64Array = tc["a"]
			for i in ts.size():
				if ts[i] > cur_t:
					break
				pts.append(Vector2(xm.call(ts[i]), ym.call(minf(am[i], ymax))))
			if pts.size() > 1:
				draw_polyline(pts, tc["color"], 2.2)
		draw_line(Vector2(xm.call(cur_t), p.position.y), Vector2(xm.call(cur_t), p.end.y), Color(1, 1, 1, 0.7), 1.5)
		draw_string(f, Vector2(8, 17), "mid-span lateral amplitude per cycle (mm, real, not exaggerated)", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
		var x := 540.0
		for tc in tr:
			draw_string(f, Vector2(x, 17), tc["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, tc["color"])
			x += 250.0 if x < 700 else 200.0
		draw_string(f, Vector2(p.position.x, size.y - 6), "0 s", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.8, 0.8))
		draw_string(f, Vector2(p.end.x - 30, size.y - 6), "%.0f s" % tmax, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.8, 0.8))


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var outdir: String = args[0] if args.size() > 0 else "C:/Users/Nick/tools/kine_workers/out/ch12"
	if args.size() > 1:
		S = float(args[1])
	var fac := float(args[2]) if args.size() > 2 else 8.0
	var secs := float(args[3]) if args.size() > 3 else 20.0
	DirAccess.make_dir_recursive_absolute(outdir + "/frames")
	var br := BR.build()
	var lat := BR.mode(br, "lat")
	var nc := BR.n_paper(BR.ZETA, lat["f"], lat["mgen"])
	var n := int(round(fac * nc))
	var dt := 0.025
	var base := {"T": secs, "dt": dt, "amp0": 0.006}
	var o1 := base.duplicate()
	o1.merge({"n": n, "kind": "locked", "snap_every": 2})
	var r1 := BR.run(br, lat, o1)
	var o2 := base.duplicate()
	o2.merge({"n": n, "kind": "random"})
	var r2 := BR.run(br, lat, o2)
	var o3 := base.duplicate()
	o3.merge({"n": n, "kind": "locked", "retrofit": true})
	var r3 := BR.run(br, lat, o3)
	var t1 := TAU / float(lat["omega"])
	var traces: Array = []
	var peak := 0.0
	for pr in [[r1, "locked crowd, N = %d (%.1f N_c)" % [n, fac], Color(1.0, 0.45, 0.3)], [r2, "random-phase control, same N", Color(0.6, 0.65, 0.7)], [r3, "retrofit dampers (zeta 5 pct), same N", Color(0.4, 0.9, 0.5)]]:
		var r: Dictionary = pr[0]
		var u: PackedFloat64Array = r["rec_u"].slice(0, int(r["ns"]) + 1)
		var env := BR.envelope(u, dt, t1)
		for a in env["a"]:
			peak = maxf(peak, a)
		traces.append({"name": pr[1], "color": pr[2], "t": env["t"], "a": env["a"]})
	print("N_c %.1f, N %d, peak amplitude of locked run %.1f mm; control end %.2f mm; retrofit end %.2f mm" % [nc, n, 1000.0 * peak, 1000.0 * float(traces[1]["a"][traces[1]["a"].size() - 1]), 1000.0 * float(traces[2]["a"][traces[2]["a"].size() - 1])])
	# walkers re-integrated from the snapshots for the figures (same equation, v by finite difference of the snapshots)
	var cr := BR.crowd(br, n, lat["omega"], "locked")
	var xs := PackedFloat64Array()
	for i in n:
		xs.append((i + 0.5) / n * BR.L)
	var snaps: Array = r1["snaps"]
	var th: PackedFloat64Array = cr["theta0"].duplicate()
	var leans: Array = []
	var om: PackedFloat64Array = cr["omega"]
	var n1: PackedInt32Array = cr["n1"]
	var n2: PackedInt32Array = cr["n2"]
	var cw: PackedFloat64Array = cr["w"]
	var cp: float = cr["cp"]
	var sdt := 2.0 * dt
	for k in snaps.size():
		var lean := PackedFloat64Array()
		lean.resize(n)
		for i in n:
			var vi := 0.0
			if k > 0:
				var a0: PackedFloat64Array = snaps[k - 1]
				var a1: PackedFloat64Array = snaps[k]
				vi = ((1.0 - cw[i]) * (a1[n1[i] * 6 + 2] - a0[n1[i] * 6 + 2]) + cw[i] * (a1[n2[i] * 6 + 2] - a0[n2[i] * 6 + 2])) / sdt
				th[i] += sdt * (om[i] + cp * vi * cos(th[i]))
			lean[i] = sin(th[i])
		leans.append(lean)
	var root := get_root()
	root.size = Vector2i(1280, 720)
	var cl := CanvasLayer.new()
	root.add_child(cl)
	var title := Label.new()
	title.text = "CH12: a footbridge that sways (Millennium Bridge 2000): 144 m span, f1 = %.2f Hz, phase-locking crowd (Dallard et al. 2001)" % lat["f"]
	title.position = Vector2(14, 8)
	title.add_theme_font_size_override("font_size", 18)
	cl.add_child(title)
	var view := View.new()
	view.position = Vector2(0, 40)
	view.size = Vector2(1280, 360)
	view.br = br
	view.snaps = snaps
	view.th = leans
	view.xs = xs
	view.nc = nc
	view.S = S
	view.members = BR.members()
	cl.add_child(view)
	var plot := Plot.new()
	plot.position = Vector2(0, 410)
	plot.size = Vector2(1280, 310)
	plot.tr = traces
	plot.tmax = secs
	plot.ymax = maxf(0.02, snappedf(peak * 1.15, 0.01))
	cl.add_child(plot)
	await process_frame
	await process_frame
	for k in snaps.size():
		var sn: PackedFloat64Array = snaps[k]
		var mid: float = sn[BR.nid(BR.NSEG / 2, 1) * 6 + 2]
		view.cur = k
		view.info = "t = %5.2f s    mid-span lateral displacement %+6.1f mm (drawn x%d = %+.2f m)" % [k * 2.0 * dt, mid * 1000.0, int(S), mid * S]
		plot.cur_t = k * 2.0 * dt
		view.queue_redraw()
		plot.queue_redraw()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/frames/f%05d.png" % [outdir, k])
	print("frames done: ", snaps.size())
	quit(0)
