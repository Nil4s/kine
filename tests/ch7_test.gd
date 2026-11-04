## godot --headless --path . -s tests/ch7_test.gd     (CH7: the chained parkour run, Parkour + ParkourPlan)
## BARS, written before the numbers were read (the reference they answer to is docs/CH7_REFERENCE.md):
##   1 HAND PLANTS (speed vault, kong, cat leap catch and push): the palm point is within 2 cm of an edge of the obstacle's top face
##     for the whole plant, and slides no more than 1 cm from where it landed
##   2 SPEED: the pelvis's horizontal (z) speed over the 0.15 s before each move ends, against the 0.15 s after the next one starts:
##     never a drop over 15 %. (The mean over a whole move is REPORTED, not barred: a cat leap's catch is a stop by definition.)
##   3 LANDINGS: knee flexion at each landing rises with the drop height (monotone over the landings sorted by drop) and the
##     least-squares slope is within 20 % of the published 30.8 deg per m (docs/CH7_REFERENCE.md)
##   3b the same slope bar read at the landing ABSORPTION PEAK: the first local maximum of knee flexion after touchdown (before the
##     knee extends again), not the maximum over a window; same 30.8 +- 20 % target and monotone rule (added after run 1 showed the
##     0.25 s window of bar 3 also catches the next stride's knee fold; bar 3 is kept as written)
##   4 FOOT SKATE: a stance foot's toe base slides under 1 cm over each roof contact
##   5 NO PENETRATION: no body part more than 1 cm into any solid of the course, on every frame
##   6 the scene is 8 s at 30 fps, and playing it back reproduces the solved pose; C++ and GDScript give the same penetration
##   7 CONTROLS: each bar's function fails on a planted wrong series
extends SceneTree

var fails := 0
const SLIDE_MAX := 0.01
const EDGE_MAX := 0.02
const SPEED_DROP_MAX := 0.15
const SKATE_MAX := 0.01
const PEN_MAX := 0.01
const REF_SLOPE := 30.8       # deg per m of drop: Zhang et al. 2025 PeerJ 13:e19490, knee-dominant, 30 to 60 cm (docs/CH7_REFERENCE.md)
const SLOPE_TOL := 0.20


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	call_deferred("_run")


# ---- the bar functions (each also run on a planted wrong series: bar 7)

## the distance from point (x, z) to the nearest edge line of the rectangle (lo, hi) in the xz plane; 0 on an edge, > 0 either side
static func edge_dist(p: Vector3, lo: Vector3, hi: Vector3) -> float:
	var dx := minf(absf(p.x - lo.x), absf(p.x - hi.x))
	var dz := minf(absf(p.z - lo.z), absf(p.z - hi.z))
	var inx := p.x >= lo.x - 1e-6 and p.x <= hi.x + 1e-6
	var inz := p.z >= lo.z - 1e-6 and p.z <= hi.z + 1e-6
	var d := INF
	if inx:
		d = minf(d, dz)
	if inz:
		d = minf(d, dx)
	return d if d < INF else Vector2(minf(dx, 9.0), minf(dz, 9.0)).length()


static func slide_of(pts: Array) -> float:
	var w := 0.0
	for p in pts:
		w = maxf(w, (p as Vector3).distance_to(pts[0]))
	return w


static func speed_drop(exit_v: float, entry_v: float) -> float:
	return (exit_v - entry_v) / maxf(exit_v, 1e-6)


## slope (deg per m) of the least-squares line through (drop, flex), and whether the flex rises with the drop when sorted
## the first local maximum of a knee-flexion series at or after index k0 (the landing absorption peak); the last value if it only rises
static func first_peak(series: Array, k0: int) -> float:
	for k in range(k0, series.size() - 1):
		if float(series[k + 1]) < float(series[k]):
			return float(series[k])
	return float(series[series.size() - 1])


static func fit(rows: Array) -> Dictionary:
	var r := rows.duplicate()
	r.sort_custom(func(a, b): return a[0] < b[0])
	var n := float(r.size())
	var mx := 0.0
	var my := 0.0
	for q in r:
		mx += q[0]
		my += q[1]
	mx /= n
	my /= n
	var sxy := 0.0
	var sxx := 0.0
	for q in r:
		sxy += (q[0] - mx) * (q[1] - my)
		sxx += (q[0] - mx) * (q[0] - mx)
	var mono := true
	for i in range(1, r.size()):
		if r[i][1] <= r[i - 1][1]:
			mono = false
	return {"slope": sxy / maxf(sxx, 1e-9), "mono": mono}


func _palm(B: Body, sd: String) -> Vector3:
	return B.palm_point("hand" + sd)


func _run() -> void:
	var P := ParkourPlan.build()
	var t_build := Time.get_ticks_msec()
	var R := Parkour.build(P)
	print("build %.1f s, native %s" % [(Time.get_ticks_msec() - t_build) / 1000.0, str(Parkour.native_on())])
	var S := Scene.new()
	S.from_dict(R["scene"])
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var props: Array = S.props
	var boxes := Parkour.boxes_of(props)
	var fps := float(Parkour.FPS)
	var nfr := int(round(float(P["length"]) * fps)) + 1
	ok(absf(float(P["length"]) - 8.0) < 1e-6 and int(S.fps) == 30 and S.cards.size() == nfr, "6 the run is %.1f s at %d fps, %d cards (bar 8.0 s, 30 fps)" % [P["length"], S.fps, S.cards.size()])
	# one pass over the played scene: the numbers every bar reads
	var pel := []
	var palm := {"_l": [], "_r": []}
	var ball := {"_l": [], "_r": []}
	var ankle := {"_l": [], "_r": []}
	var knee := {"_l": [], "_r": []}
	var pen_worst := 0.0
	var pen_where := ""
	var pen_frame := -1
	var back := 0.0
	for k in nfr:
		var t := float(k) / fps
		S.apply(B, t)
		pel.append(B.P["pelvis"])
		for sd in ["_l", "_r"]:
			palm[sd].append(_palm(B, sd))
			ball[sd].append(B.P["ball" + sd])
			ankle[sd].append(B.P["foot" + sd])
			knee[sd].append(float(B.ang["calf" + sd].x))
		var d := Parkour.deepest(B, boxes)
		if float(d["d"]) > pen_worst:
			pen_worst = float(d["d"])
			pen_where = String(d["where"])
			pen_frame = k
		if k % 40 == 7:
			var rt := Parkour.root_at(P, t)
			back = maxf(back, absf(float((pel[k] as Vector3).z) - float(rt["z"])))
	ok(back < 0.01, "6 playing the scene back reproduces the solved pelvis path to %.1f mm at sampled frames (bar 10 mm)" % (back * 1000.0))
	# ---- 1 hand plants
	var obs := {}
	for o in P["obstacles"]:
		obs[o["name"]] = o
	var plants := [["speed vault", "_r", 1.08, 1.26, "boxSpeed"], ["kong L", "_l", 2.30, 2.55, "boxKong"], ["kong R", "_r", 2.30, 2.55, "boxKong"],
		["cat catch L", "_l", 5.30, 5.50, "ledge"], ["cat catch R", "_r", 5.30, 5.50, "ledge"], ["mantle L", "_l", 5.60, 5.80, "ledge"], ["mantle R", "_r", 5.60, 5.80, "ledge"]]
	for pl in plants:
		var sd: String = pl[1]
		var o: Dictionary = obs[pl[4]]
		var top_lo: Vector3 = o["lo"]
		var top_hi: Vector3 = o["hi"]
		var edge := 9.0
		var pts := []
		for k in range(int(ceil((float(pl[2]) + 0.04) * fps)), int(floor((float(pl[3]) - 0.02) * fps)) + 1):
			var pp: Vector3 = palm[sd][k]
			edge = minf(edge, 99.0)
			pts.append(pp)
		var worst_edge := 0.0
		for pp in pts:
			worst_edge = maxf(worst_edge, edge_dist(pp, top_lo, top_hi))
		var sl := slide_of(pts)
		ok(worst_edge <= EDGE_MAX and sl <= SLIDE_MAX, "1 %s hand plant: palm %.1f cm from the edge (bar 2), slides %.1f cm (bar 1)" % [pl[0], worst_edge * 100.0, sl * 100.0])
	# ---- 2 speed
	var mv := ParkourPlan.moves()
	var zf := func(t: float) -> float: return (pel[clampi(int(round(t * fps)), 0, nfr - 1)] as Vector3).z
	var vwin := func(a: float, b: float) -> float: return (zf.call(b) - zf.call(a)) / (b - a)
	var worst_drop := -9.0
	var line := ""
	for i in range(mv.size() - 1):
		var ex: float = vwin.call(float(mv[i]["t1"]) - 0.15, float(mv[i]["t1"]))
		var en: float = vwin.call(float(mv[i + 1]["t0"]), float(mv[i + 1]["t0"]) + 0.15)
		var dr := speed_drop(ex, en)
		worst_drop = maxf(worst_drop, dr)
		line += " %s>%s %.2f>%.2f" % [mv[i]["name"], mv[i + 1]["name"], ex, en]
	ok(worst_drop <= SPEED_DROP_MAX, "2 speed at the move boundaries (m/s):%s; worst drop %.1f %% (bar 15)" % [line, worst_drop * 100.0])
	var means := ""
	for m in mv:
		means += " %s %.2f" % [m["name"], float(vwin.call(float(m["t0"]), float(m["t1"])))]
	print("info mean horizontal speed over each move (m/s, not barred):" + means)
	# ---- 3 landings: [name, foot (the first to touch), t_touch, t_apex_start]
	var lands := [["speed vault", "_r", 1.48, 1.00], ["kong", "_l", 2.84, 2.16], ["wall run exit", "_r", 4.30, 4.15], ["ledge drop", "_l", 6.58, 6.04]]
	var rows := []
	var rows2 := []
	var txt := ""
	var txt2 := ""
	for ld in lands:
		var sd: String = ld[1]
		var kt := int(round(float(ld[2]) * fps))
		var k0 := int(round(float(ld[3]) * fps))
		# the drop: the lowest ankle at the start of the flight, less the ankle at touchdown
		var a0 := minf(float((ankle["_l"][k0] as Vector3).y), float((ankle["_r"][k0] as Vector3).y))
		var a1: float = (ankle[sd][kt] as Vector3).y
		var apex := a0
		for k in range(k0, kt + 1):
			apex = maxf(apex, minf(float((ankle["_l"][k] as Vector3).y), float((ankle["_r"][k] as Vector3).y)))
		var drop := apex - a1
		var flex := 0.0
		for k in range(kt, mini(kt + int(0.25 * fps), nfr - 1) + 1):
			flex = maxf(flex, float(knee[sd][k]))
		rows.append([drop, flex])
		var pk := first_peak(knee[sd], kt)
		rows2.append([drop, pk])
		txt2 += " %s drop %.2f m peak %.0f deg;" % [ld[0], drop, pk]
		txt += " %s drop %.2f m flex %.0f deg;" % [ld[0], drop, flex]
	var f := fit(rows)
	ok(bool(f["mono"]) and absf(float(f["slope"]) - REF_SLOPE) <= SLOPE_TOL * REF_SLOPE, "3 landing knee flex vs drop:%s monotone %s, slope %.1f deg/m (bar %.0f +- 20 %%)" % [txt, str(f["mono"]), f["slope"], REF_SLOPE])
	var f2 := fit(rows2)
	ok(bool(f2["mono"]) and absf(float(f2["slope"]) - REF_SLOPE) <= SLOPE_TOL * REF_SLOPE, "3b landing absorption peak (first local max after touchdown) vs drop:%s monotone %s, slope %.1f deg/m (bar %.1f +- 20 %%)" % [txt2, str(f2["mono"]), f2["slope"], REF_SLOPE])
	# ---- 4 foot skate on the roof contacts
	var worst_sk := 0.0
	var nstance := 0
	for sd in ["_l", "_r"]:
		var keys: Array = P["feet"]["foot" + sd]
		for i in keys.size() - 1:
			var a: Dictionary = keys[i]
			var b: Dictionary = keys[i + 1]
			if bool(a.get("c", false)) and bool(b.get("c", false)) and (a["v"] as Vector3).is_equal_approx(b["v"]):
				var pts := []
				for k in range(int(ceil(float(a["t"]) * fps)), int(floor(float(b["t"]) * fps)) + 1):
					pts.append(ball[sd][k])
				if pts.size() >= 2:
					nstance += 1
					worst_sk = maxf(worst_sk, slide_of(pts))
	ok(worst_sk < SKATE_MAX and nstance >= 15, "4 %d stance contacts, worst toe-base slide %.1f mm (bar 10 mm)" % [nstance, worst_sk * 1000.0])
	# ---- 5 penetration
	ok(pen_worst <= PEN_MAX, "5 deepest body part in a solid: %.1f mm (%s, frame %d) (bar 10 mm)" % [pen_worst * 1000.0, pen_where, pen_frame])
	# ---- 6 native == GDScript
	var same := true
	var nat := Parkour.native_on()
	for k in [0, 40, 75, 130, 170, 200, 235]:
		S.apply(B, float(k) / fps)
		var g := Parkour.deepest_gd(B, boxes)
		if nat:
			var n := Parkour.deepest(B, boxes)
			if absf(float(g["d"]) - float(n["d"])) > 1e-4:
				same = false
	ok(same, "6 C++ and GDScript penetration agree at 7 frames (native %s)" % str(nat))
	# ---- 7 controls: each bar's function fails on a wrong series
	var o: Dictionary = obs["boxSpeed"]
	ok(edge_dist(Vector3(0, 0, 5.3), o["lo"], o["hi"]) > EDGE_MAX, "7a control: a palm 30 cm in from the edge fails bar 1 (%.0f cm)" % (edge_dist(Vector3(0, 0, 5.3), o["lo"], o["hi"]) * 100.0))
	ok(slide_of([Vector3.ZERO, Vector3(0.03, 0, 0)]) > SLIDE_MAX, "7b control: a 3 cm slide fails the slide bar")
	ok(speed_drop(4.2, 3.0) > SPEED_DROP_MAX and speed_drop(4.2, 3.7) <= SPEED_DROP_MAX, "7c control: 4.2 -> 3.0 m/s fails bar 2, 4.2 -> 3.7 passes")
	var flat := fit([[0.6, 60.0], [1.0, 60.0], [1.4, 60.0]])
	var steep := fit([[0.6, 40.0], [1.0, 90.0], [1.4, 140.0]])
	ok(not bool(flat["mono"]) and absf(float(steep["slope"]) - REF_SLOPE) > SLOPE_TOL * REF_SLOPE, "7d control: a flat landing (slope %.0f) and a 125 deg/m one fail bar 3" % flat["slope"])
	ok(first_peak([10.0, 40.0, 70.0, 60.0, 130.0], 0) == 70.0 and first_peak([10.0, 40.0, 70.0, 60.0, 130.0], 3) == 130.0, "7f control: first_peak picks the first local maximum (70, not the later 130)")
	S.apply(B, 1.2)
	var wrong := boxes.duplicate(true)
	wrong.append({"c": (B.P["pelvis"] as Vector3), "h": Vector3(0.3, 0.3, 0.3), "kind": "planted"})
	ok(float(Parkour.deepest(B, wrong)["d"]) > PEN_MAX, "7e control: a box planted through the pelvis fails bar 5 (%.0f mm)" % (float(Parkour.deepest(B, wrong)["d"]) * 1000.0))
	print("CH7 TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	print("ch7: %d fail" % fails)
	TestFiles.cleanup()
	quit(fails)
