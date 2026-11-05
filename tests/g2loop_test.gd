extends SceneTree
## godot --path . -s tests/g2loop_test.gd     (G2LOOP: kinematic joints with CLOSED loops in an Assembly, gap G2 of docs/CHALLENGE_FEEDBACK.md;
## scripts/build/assembly_loop.gd, used by assembly_motion.gd check_motion and the Check motion panel). Bars committed before the first run;
## every bar has a planted control (a "CONTROL" line that must be caught):
##   a SLIDER-CRANK  r 25, l 90 (hand numbers): the piston at 36 crank angles (every 10 deg) equals x = r cos t + sqrt(l^2 - (r sin t)^2) to 1e-6 mm.
##                   The solver works in doubles (GDScript float) and the piston is measured in doubles (AssemblyLoop.world_mm), so the G4 float32
##                   limit (~1e-5 mm at 100 mm) does not apply to it; the posed Transform3D the screen gets is held to G4's 1e-4 mm.
##                   CONTROL: the same mechanism with r and l swapped (crank 90, rod 25) is caught: it locks, or misses the closed form by > 1 mm
##   b FOUR-BAR      Grashof crank-rocker, ground 100, crank 40, coupler 120, rocker 80 (hand: s + l = 160 <= p + q = 180, the crank shortest):
##                   the rocker angle at 36 crank angles equals Freudenstein's closed form (one branch throughout: one assembly mode) to 1e-6 rad.
##                   CONTROL: the non-Grashof set crank 70 (s + l = 190 > 180, a triple rocker), started at 180 deg, is NOT solved through its
##                   toggle positions: exactly 2 locks, at 180 -+ acos((70^2 + 100^2 - 40^2) / (2 70 100)) = 161.805 / 198.195 deg (1e-3 deg), the
##                   Jacobian's rank below 6 at each, and the steps 170, 180, 190 have no pose
##   c ENGINE        the CH13 engine as an Assembly record with a drive and 5 joints (ch13_parts.loop_assembly) reproduces ch13_parts.pose_of() for all
##                   7 parts at 36 crank angles: the part origin and 100 mm along each of its axes, worst distance <= 1e-6 mm.
##                   CONTROL: pose_of with the rod left unturned (skip_rod_turn) is > 1 mm from the solved poses
##   d CLASHES       check_motion on the engine record (36 angles, every 10 deg) finds no clash, as bar j's second run. On the geometry bar j's FIRST run
##                   swept (tests/assets/g2loop/ch13_parts_9a9522ca.gd) with bar j's threshold (0.001 mm3), the joint-driven sweep finds exactly the
##                   overlaps bar j's own pose_of + place loop finds on the same geometry (same pairs, same angles, volumes within 1e-3 mm3 + 1e-6 rel),
##                   and they are bar j's three overlap faults: rod x piston (every angle), rod x cylinder, rod x crankcase; bar j's fourth fault (crown
##                   to head gap 5.10 mm, not 0.50) is a gap, not an overlap, so piston x head is not among them.
##                   CONTROL: a rod 2 mm longer (record and joints) puts the piston into the head at 0 deg
##   e CONVERGENCE   the engine at 361 crank angles (360 steps of 1 deg), each from the last: at most 5 Newton iterations at any step, mean <= 4,
##                   total <= 1000 ms (bound stated before the run). CONTROL: cold steps (each from the record's zero guess, no continuation) need
##                   more iterations on average
##   f UI            the engine record with 4 joints (no piston slide) in the Assembly screen: Check motion opens from the S box; the scrub says NOT
##                   SOLVED (a degree of freedom left); Add joint (piston, Slide along Y, to Ground) is ONE undo step; then the scrub at 90 and 180 deg
##                   puts the piston mesh at x - 34 mm (1e-4 mm, float32) and turns the rod by the closed-form angle (1e-3 deg); Run lists no clash;
##                   Ctrl+Z gives back the identical record and the piston at its record place. Shots C:/Temp/claude/g2loop/scrub90.png, undone.png.
##                   CONTROL: before the joint, the piston mesh did not follow the crank (it stayed at its record place)
##   g OLD           tests/assets/g1motion/old_assembly.json (no drives) and tests/assets/g2loop/drive_199.json (a #199 drive record, written by the #199
##                   code before this branch) load and save back equal; the #199 record's Check motion gives exactly what #199 gave (one line "Lid and
##                   Ceiling: from 70 deg, worst 184.0 mm3 at 70 deg", 13 kernel calls, 10 skipped) and takes no loop path.
##                   CONTROL: the #199 record with a joint saved does not compare equal
const KCad := preload("res://scripts/kcad.gd")
const AM := preload("res://scripts/build/assembly_motion.gd")
const AL := preload("res://scripts/build/assembly_loop.gd")
const P := preload("res://scripts/build/ch13_parts.gd")
const OLDP := preload("res://tests/assets/g2loop/ch13_parts_9a9522ca.gd")
const SHOT := "C:/Temp/claude/g2loop"
const OLD := "res://tests/assets/g1motion/old_assembly.json"
const D199 := "res://tests/assets/g2loop/drive_199.json"
const OV_EPS_MM3 := 0.001   # bar j's threshold
var fails := 0
var m: Node
var A: AssemblyUI


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func ctl(c: bool, w: String) -> void:
	ok(c, "CONTROL " + w)


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func dist(a: Array, b: Array) -> float:
	return sqrt((a[0] - b[0]) * (a[0] - b[0]) + (a[1] - b[1]) * (a[1] - b[1]) + (a[2] - b[2]) * (a[2] - b[2]))


# ------------------------------------------------------------------ records
func box_rec(nm: String, x0: float, y0: float, z0: float, x1: float, y1: float, z1: float) -> Dictionary:
	var fs: Array = []
	var pl := "front"
	if z0 != 0.0:
		fs.append({"t": "plane", "id": "f1", "name": "Plane1", "from": "front", "mm": z0})
		pl = "f1"
	var sk := "f%d" % (fs.size() + 1)
	fs.append({"t": "sketch", "id": sk, "name": "Sketch", "plane": pl, "ents": [{"k": "rect", "a": [x0, y0], "b": [x1, y1]}], "dims": []})
	fs.append({"t": "extrude", "id": "f%d" % (fs.size() + 1), "name": "Extrude", "sketch": sk, "dist": z1 - z0, "both": false, "op": "new"})
	var rec := Part.make(nm)
	rec["features"] = fs
	rec["seq"] = fs.size()
	return rec


func part(id: String, nm: String, rec: Dictionary, pos: Array, rot := [0.0, 0.0, 0.0]) -> Dictionary:
	return {"id": id, "name": nm, "src": "", "rec": rec, "pos": pos, "rot": rot}


func asm_of(nm: String, parts: Array) -> Dictionary:
	var a := Assembly.make(nm)
	a["parts"] = parts
	a["seq"] = parts.size()
	return a


func tens(n := 36) -> Array:
	var v: Array = []
	for k in n:
		v.append(10.0 * k)
	return v


# ------------------------------------------------------------------ a
## crank (p1) of radius r about z at the origin, rod (p2) of length l, piston (p3) sliding along y; TDC at 0 deg
func slider_crank(r: float, l: float) -> Dictionary:
	var a := asm_of("Slider-crank", [
		part("p1", "Crank", box_rec("Crank", -4, -4, 0, 4, r + 4, 5), [0.0, 0.0, 0.0]),
		part("p2", "Rod", box_rec("Rod", -3, -3, 0, 3, l + 3, 5), [0.0, r, 10.0]),
		part("p3", "Piston", box_rec("Piston", -10, -10, 0, 10, 10, 20), [0.0, r + l, 20.0])])
	AM.set_drive(a, AM.make_drive("Crank", "p1", "rotate", Vector3.BACK, Vector3.ZERO, 0.0, 360.0))
	var Z := [0.0, 0.0, 1.0]
	AL.add_joint(a, AL.make_joint("revolute", "p1", "ground", Z, [0.0, 0.0, 0.0]))
	AL.add_joint(a, AL.make_joint("revolute", "p2", "p1", Z, [0.0, 0.0, 0.0], [0.0, r, 0.0]))
	AL.add_joint(a, AL.make_joint("revolute", "p3", "p2", Z, [0.0, 0.0, 0.0], [0.0, l, 0.0]))
	AL.add_joint(a, AL.make_joint("slider", "p3", "ground", [0.0, 1.0, 0.0], [0.0, 0.0, 0.0]))
	return a


func x_closed(r: float, l: float, t: float) -> float:
	return r * cos(t) + sqrt(l * l - (r * sin(t)) * (r * sin(t)))


## {"worst" (mm, doubles), "worst_xf" (mm, the Transform3D), "off_axis", "locks", "unsolved"}
func piston_vs_closed(asm: Dictionary, r: float, l: float) -> Dictionary:
	var sw := AL.sweep(asm, "Crank", tens())
	var worst := 0.0
	var worst_xf := 0.0
	var off := 0.0
	for st in sw["steps"]:
		if not bool(st["ok"]):
			worst = INF
			continue
		var t := deg_to_rad(float(st["v"]))
		var pw: Array = AL.world_mm(asm, st["states"], "p3", [0.0, 0.0, 0.0])
		worst = maxf(worst, absf(pw[1] - x_closed(r, l, t)))
		off = maxf(off, absf(pw[0]))
		var xf: Transform3D = (st["moves"]["p3"] as Transform3D) * Assembly.xf_of(asm["parts"][2])
		worst_xf = maxf(worst_xf, absf(xf.origin.y / Assembly.MM - x_closed(r, l, t)))
	return {"worst": worst, "worst_xf": worst_xf, "off_axis": off, "locks": sw["locks"], "unsolved": sw["unsolved"], "sw": sw}


func bars_slider_crank() -> void:
	var r := 25.0
	var l := 90.0
	var res := piston_vs_closed(slider_crank(r, l), r, l)
	ok(float(res["worst"]) <= 1e-6 and float(res["off_axis"]) <= 1e-6 and (res["unsolved"] as Array).is_empty(), "a slider-crank r 25 l 90, 36 angles: piston vs r cos t + sqrt(l^2 - (r sin t)^2) worst %s mm (doubles), off the axis %s mm; %d iterations, %.2f ms" % [String.num_scientific(float(res["worst"])), String.num_scientific(float(res["off_axis"])), int(res["sw"]["iters_total"]), float(res["sw"]["ms"])])
	ok(float(res["worst_xf"]) <= 1e-4, "a the posed Transform3D (float32, G4) is within %s mm of the closed form (bar 1e-4)" % String.num_scientific(float(res["worst_xf"])))
	var sw_ := piston_vs_closed(slider_crank(l, r), r, l)
	var locks: Array = sw_["locks"]
	ctl(not locks.is_empty() or float(sw_["worst"]) > 1.0, "a r and l swapped (crank 90, rod 25): %d locks %s, %d steps with no pose, worst vs the true closed form %s mm" % [locks.size(), str(locks.map(func(x): return snappedf(float(x["at"]), 0.001))), (sw_["unsolved"] as Array).size(), str(sw_["worst"])])


# ------------------------------------------------------------------ b
## crank p1 (a, pivot at the origin), coupler p2 (b), rocker p3 (c, pivot at (d, 0)); the crank starts at th0 deg; the coupler pin above the ground line
func four_bar(a: float, b: float, c: float, d: float, th0: float) -> Dictionary:
	var t0 := deg_to_rad(th0)
	var ax := a * cos(t0)
	var ay := a * sin(t0)
	var dx := d - ax
	var dy := -ay
	var s := sqrt(dx * dx + dy * dy)
	var aa := (b * b - c * c + s * s) / (2.0 * s)
	var h := sqrt(b * b - aa * aa)
	var px := ax + aa * dx / s
	var py := ay + aa * dy / s
	var b1 := [px - h * dy / s, py + h * dx / s]
	var b2 := [px + h * dy / s, py - h * dx / s]
	var B: Array = b1 if b1[1] >= b2[1] else b2
	var th3 := atan2(B[1] - ay, B[0] - ax)
	var th4 := atan2(B[1], B[0] - d)
	var asm := asm_of("Four-bar", [
		part("p1", "Crank", box_rec("Crank", 0, -3, 0, a, 3, 5), [0.0, 0.0, 0.0], [0.0, 0.0, rad_to_deg(t0)]),
		part("p2", "Coupler", box_rec("Coupler", 0, -3, 0, b, 3, 5), [ax, ay, 5.0], [0.0, 0.0, rad_to_deg(th3)]),
		part("p3", "Rocker", box_rec("Rocker", 0, -3, 0, c, 3, 5), [d, 0.0, 10.0], [0.0, 0.0, rad_to_deg(th4)])])
	AM.set_drive(asm, AM.make_drive("Crank", "p1", "rotate", Vector3.BACK, Vector3.ZERO, 0.0, 360.0))
	var Z := [0.0, 0.0, 1.0]
	AL.add_joint(asm, AL.make_joint("revolute", "p1", "ground", Z, [0.0, 0.0, 0.0]))
	AL.add_joint(asm, AL.make_joint("revolute", "p2", "p1", Z, [0.0, 0.0, 0.0], [a, 0.0, 0.0]))
	AL.add_joint(asm, AL.make_joint("revolute", "p3", "p2", Z, [c, 0.0, 0.0], [b, 0.0, 0.0]))
	AL.add_joint(asm, AL.make_joint("revolute", "p3", "ground", Z, [0.0, 0.0, 0.0]))
	return asm


## Freudenstein: K1 cos th4 - K2 cos th2 + K3 = cos(th2 - th4); the two roots th4 = alpha +- acos(C / R)
func freudenstein(a: float, b: float, c: float, d: float, th2: float, branch: int) -> float:
	var k1 := d / a
	var k2 := d / c
	var k3 := (a * a - b * b + c * c + d * d) / (2.0 * a * c)
	var pp := k1 - cos(th2)
	var qq := -sin(th2)
	var cc := k2 * cos(th2) - k3
	var rr := sqrt(pp * pp + qq * qq)
	return atan2(qq, pp) + branch * acos(clampf(cc / rr, -1.0, 1.0))


func wrap_pi(x: float) -> float:
	return wrapf(x, -PI, PI)


func bars_four_bar() -> void:
	var a := 40.0
	var b := 120.0
	var c := 80.0
	var d := 100.0
	var asm := four_bar(a, b, c, d, 0.0)
	var sw := AL.sweep(asm, "Crank", tens())
	var branch := 0
	var worst := 0.0
	var solved := 0
	for st in sw["steps"]:
		if not bool(st["ok"]):
			worst = INF
			continue
		solved += 1
		var th2 := deg_to_rad(float(st["v"]))
		var tip: Array = AL.world_mm(asm, st["states"], "p3", [c, 0.0, 0.0])
		var th4 := atan2(tip[1], tip[0] - d)
		if branch == 0:
			branch = 1 if absf(wrap_pi(th4 - freudenstein(a, b, c, d, th2, 1))) < absf(wrap_pi(th4 - freudenstein(a, b, c, d, th2, -1))) else -1
		worst = maxf(worst, absf(wrap_pi(th4 - freudenstein(a, b, c, d, th2, branch))))
	ok(solved == 36 and (sw["locks"] as Array).is_empty() and worst <= 1e-6, "b four-bar 100/40/120/80 (Grashof crank-rocker: 40 + 120 = 160 <= 180): rocker vs Freudenstein (branch %+d throughout) worst %s rad at %d/36 angles, %d locks, %d iterations, %.2f ms" % [branch, String.num_scientific(worst), solved, (sw["locks"] as Array).size(), int(sw["iters_total"]), float(sw["ms"])])
	# the non-Grashof control
	var a2 := 70.0
	var lim := rad_to_deg(acos((a2 * a2 + d * d - (b - c) * (b - c)) / (2.0 * a2 * d)))
	var want := [180.0 - lim, 180.0 + lim]
	var nb := four_bar(a2, b, c, d, 180.0)
	var sn := AL.sweep(nb, "Crank", tens())
	var ls: Array = []
	var ranks: Array = []
	for l in sn["locks"]:
		ls.append(float(l["at"]))
		ranks.append(int(l["rank"]))
	ls.sort()
	var near := ls.size() == 2 and absf(float(ls[0]) - want[0]) <= 1e-3 and absf(float(ls[1]) - want[1]) <= 1e-3
	var rank_lost := ranks.size() == 2 and int(ranks[0]) < 6 and int(ranks[1]) < 6
	var un: Array = sn["unsolved"]
	ctl(near and rank_lost and un == [170.0, 180.0, 190.0], "b non-Grashof 100/70/120/80 (70 + 120 = 190 > 180) from 180 deg: locks at %s deg (hand %.4f / %.4f), Jacobian rank %s of 6, no pose at %s; %d iterations, %.1f ms" % [str(ls.map(func(x): return snappedf(x, 0.0001))), want[0], want[1], str(ranks), str(un), int(sn["iters_total"]), float(sn["ms"])])


# ------------------------------------------------------------------ c
const PTS := [[0.0, 0.0, 0.0], [100.0, 0.0, 0.0], [0.0, 100.0, 0.0], [0.0, 0.0, 100.0]]


## the worst distance (mm) between the solved poses and pose_of(th, opts) over 36 angles, every part, 4 points each
func engine_vs_pose_of(asm: Dictionary, sw: Dictionary, opts := {}) -> Dictionary:
	var worst := 0.0
	var at := ""
	for st in sw["steps"]:
		if not bool(st["ok"]):
			return {"worst": INF, "at": "no pose at %s" % str(st["v"])}
		var po: Dictionary = P.pose_of(float(st["v"]), opts)
		for i in P.NAMES.size():
			var nm: String = P.NAMES[i]
			for l in PTS:
				var e := dist(AL.world_mm(asm, st["states"], "p%d" % (i + 1), l), AL.pose_mm(po[nm], l))
				if e > worst:
					worst = e
					at = "%s at %s deg" % [nm, str(st["v"])]
	return {"worst": worst, "at": at}


func bars_engine() -> void:
	var asm := P.loop_assembly()
	var sw := AL.sweep(asm, "Crank", tens())
	var r := engine_vs_pose_of(asm, sw)
	ok(float(r["worst"]) <= 1e-6 and (sw["unsolved"] as Array).is_empty(), "c the CH13 engine record (drive + %d joints, %d unknowns, %d equations) vs pose_of(): worst %s mm (%s) over 7 parts x 36 angles; %d iterations, %.2f ms" % [AL.joints(asm).size(), int(sw["n"]), int(sw["m"]), String.num_scientific(float(r["worst"])), r["at"], int(sw["iters_total"]), float(sw["ms"])])
	var rc := engine_vs_pose_of(asm, sw, {"skip_rod_turn": true})
	ctl(float(rc["worst"]) > 1.0, "c pose_of with the rod unturned is %.3f mm from the solved poses (%s)" % [float(rc["worst"]), rc["at"]])


# ------------------------------------------------------------------ d
func pk(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a


## bar j's own loop on module MOD's geometry: pose_of + place + overlap_volume at 36 angles; {"pair|deg": mm3} over the threshold
func barj_ref(MOD) -> Dictionary:
	var local := {}
	var recs := {}
	for nm in P.NAMES:
		recs[nm] = MOD.record(nm)
		local[nm] = MOD.solid(recs[nm])
	var po0: Dictionary = MOD.pose_of(0.0)
	var moving := ["crankshaft", "rod", "piston", "pin"]
	var placed_static := {}
	for nm in P.NAMES:
		if not moving.has(nm):
			placed_static[nm] = MOD.place(int(local[nm]), po0[nm])
	var out := {}
	for k in 36:
		var th := 10.0 * k
		var po: Dictionary = MOD.pose_of(th)
		var placed := placed_static.duplicate()
		for nm in moving:
			placed[nm] = MOD.place(int(local[nm]), po[nm])
		for i in P.NAMES.size():
			for j in range(i + 1, P.NAMES.size()):
				var a: String = P.NAMES[i]
				var b: String = P.NAMES[j]
				if k > 0 and not moving.has(a) and not moving.has(b):
					continue
				var v: float = KCad.overlap_volume(int(placed[a]), int(placed[b])) * 1e9
				if v > OV_EPS_MM3:
					out["%s|%d" % [pk(a, b), int(th)]] = v
		for nm in moving:
			KCad.release(int(placed[nm]))
	for nm in placed_static:
		KCad.release(int(placed_static[nm]))
	for nm in local:
		KCad.release(int(local[nm]))
	return out


func cm_map(res: Dictionary) -> Dictionary:
	var out := {}
	for c in res["clashes"]:
		out["%s|%d" % [pk(String(c["a"]).to_lower(), String(c["b"]).to_lower()), int(roundf(float(c["at"])))]] = float(c["mm3"])
	return out


func with_range(asm: Dictionary, lo: float, hi: float) -> Dictionary:
	var d: Dictionary = AM.drive_of(asm, "Crank").duplicate(true)
	d["range"] = [lo, hi]
	AM.set_drive(asm, d)
	return asm


func pairs_of(mp: Dictionary) -> Array:
	var out: Array = []
	for k in mp:
		var p := String(k).get_slice("|", 0) + "|" + String(k).get_slice("|", 1)
		if not out.has(p):
			out.append(p)
	out.sort()
	return out


func bars_clashes() -> void:
	var now := AM.check_motion(with_range(P.loop_assembly(), 0.0, 350.0), "Crank", 35)
	var lp: Dictionary = now.get("loop", {})
	ok(bool(now["ok"]) and (now["clashes"] as Array).is_empty() and (now["values"] as Array).size() == 36 and lp.has("unsolved") and (lp["unsolved"] as Array).is_empty(), "d the engine record over 36 angles through the joints: %d clashes (bar j second run: none), %d pairs, %d kernel calls, %d skipped, %d ms (loop %.1f ms)" % [(now["clashes"] as Array).size(), int(now["pairs"]), int(now["kernel_calls"]), int(now["skipped"]), int(now["ms"]), float(lp.get("ms", -1.0))])
	var t0 := Time.get_ticks_msec()
	var ref := barj_ref(OLDP)
	var t_ref := Time.get_ticks_msec() - t0
	var old_asm := with_range(P.with_loop(OLDP.assembly(0.0)), 0.0, 350.0)
	var cm := AM.check_motion(old_asm, "Crank", 35, {"hit_mm3": OV_EPS_MM3})
	var got := cm_map(cm)
	var same_keys := ref.size() == got.size()
	var worst := 0.0
	for k in ref:
		if not got.has(k):
			same_keys = false
			continue
		var e := absf(float(got[k]) - float(ref[k]))
		worst = maxf(worst, e)
		same_keys = same_keys and e <= 1e-3 + 1e-6 * absf(float(ref[k]))
	var rp := pairs_of(ref)
	var n_pr := 0
	var worst_by := {}
	for k in ref:
		var p := String(k).get_slice("|", 0) + "|" + String(k).get_slice("|", 1)
		if p == "piston|rod":
			n_pr += 1
		if not worst_by.has(p) or float(ref[k]) > float(worst_by[p][0]):
			worst_by[p] = [snappedf(float(ref[k]), 0.001), String(k).get_slice("|", 2)]
	var angles := {}
	for k in ref:
		var p := String(k).get_slice("|", 0) + "|" + String(k).get_slice("|", 1)
		if not angles.has(p):
			angles[p] = []
		angles[p].append(int(String(k).get_slice("|", 2)))
	for p in angles:
		angles[p].sort()
	print("d  old geometry, bar j's loop: %s (%d ms); worst per pair %s; angles %s" % [str(rp), t_ref, str(worst_by), str(angles)])
	var big: Array = []
	for p in worst_by:
		if float(worst_by[p][0]) > 1.0:
			big.append(p)
	big.sort()
	ok(same_keys and not ref.is_empty(), "d old geometry (9a9522ca), threshold 0.001 mm3: the joint-driven sweep finds the same %d (pair, angle) overlaps as bar j's pose_of loop (%d), worst volume difference %s mm3; at the default 1 mm3 the pairs are %s (loop %.1f ms)" % [got.size(), ref.size(), String.num_scientific(worst), str(big), float(cm.get("loop", {}).get("ms", -1.0))])
	ok(rp == ["crankcase|rod", "cylinder|rod", "piston|rod"] and n_pr == 36 and not rp.has("head|piston"), "d they are bar j's three overlap faults %s (rod x piston at %d/36 angles); piston x head is not one: bar j's 4th fault was a 5.10 mm gap, not an overlap" % [str(rp), n_pr])
	var lr := AM.check_motion(with_range(P.loop_assembly(P.L + 2.0), 0.0, 350.0), "Crank", 35)
	var head_at := -1.0
	var head_mm3 := 0.0
	for c in lr["clashes"]:
		if pk(String(c["a"]).to_lower(), String(c["b"]).to_lower()) == "head|piston" and is_equal_approx(float(c["at"]), 0.0):
			head_at = 0.0
			head_mm3 = float(c["mm3"])
	ctl(head_at == 0.0 and head_mm3 > 1.0, "d a rod 2 mm longer: piston x head at 0 deg, %.3f mm3 (bar j's control: 580 mm3)" % head_mm3)


# ------------------------------------------------------------------ e
func bars_convergence() -> void:
	var asm := P.loop_assembly()
	var vals: Array = []
	for k in 361:
		vals.append(float(k))
	var sw := AL.sweep(asm, "Crank", vals)
	var mean := float(sw["iters_total"]) / 361.0
	var rmin := INF
	for st in sw["steps"]:
		if bool(st["ok"]):
			rmin = minf(rmin, float(st["ratio"]))
	ok((sw["unsolved"] as Array).is_empty() and int(sw["iters_max"]) <= 5 and mean <= 4.0 and float(sw["ms"]) <= 1000.0, "e engine, 360 steps of 1 deg: %d iterations (mean %.2f per step, max %d; bound 5 / mean 4), %.1f ms (bound 1000); smallest pivot ratio %.3g (rank tol %g)" % [int(sw["iters_total"]), mean, int(sw["iters_max"]), float(sw["ms"]), rmin, AL.RANK_TOL])
	var sc := AL.sweep(asm, "Crank", vals, {"warm": false})
	var mc := float(sc["iters_total"]) / 361.0
	ctl(mc > mean or not (sc["unsolved"] as Array).is_empty(), "e cold steps (zero guess, no continuation): mean %.2f iterations (warm %.2f), max %d, %d with no pose, %.1f ms" % [mc, mean, int(sc["iters_max"]), (sc["unsolved"] as Array).size(), float(sc["ms"])])


# ------------------------------------------------------------------ f (the screen)
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


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func key(code: int, uni := 0, ctrl := false) -> void:
	for dn in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.unicode = uni
		e.ctrl_pressed = ctrl
		e.pressed = dn
		root.push_input(e, true)
		await process_frame


func type_in(le: LineEdit, text: String) -> void:
	await click_ctl(le)
	le.select_all()
	for ch in text:
		var c := ch.unicode_at(0)
		var kc := KEY_0 + (c - 48) if (c >= 48 and c <= 57) else (KEY_PERIOD if ch == "." else KEY_MINUS)
		await key(kc, c)
	await key(KEY_ENTER)
	await idle(2)


func shot(nm: String) -> void:
	await idle(4)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func nd(nm: String) -> Node:
	return root.find_child(nm, true, false)


func piston_y_mm() -> float:
	return (A.meshes["p4"] as MeshInstance3D).transform.origin.y / Assembly.MM


func rod_deg() -> float:
	return rad_to_deg((A.meshes["p3"] as MeshInstance3D).transform.basis.get_euler().z)


func bars_ui() -> void:
	var ss: StartScreen = m.start_screen
	ss.dirs_override = ["user://g2loop_test"]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	m.bld.part.set_on(false)
	m.S.part = {}
	await idle(6)
	A = m.bld.asm
	m.build_choose.show_chooser()
	await idle(4)
	await click_ctl(nd("build_choose_assembly") as Button)
	await idle(4)
	A.open_record(P.loop_assembly(P.L, false))
	await idle(6)
	var before := JSON.stringify(A.asm, "", true)
	var y_rec := piston_y_mm()
	m.ui_cmd.open_with("check motion")
	await idle(3)
	var top := String(m.ui_cmd.shown[0]["name"]) if not m.ui_cmd.shown.is_empty() else ""
	await key(KEY_ENTER)
	await idle(4)
	var pnl := nd("asm_motion_panel") as Control
	ok(top == "Assembly: check motion" and pnl != null and pnl.is_visible_in_tree() and A.motion.drive == "Crank", "f the S box finds '%s'; Enter opens Check motion on drive '%s'" % [top, A.motion.drive])
	var sl := nd("asm_motion_scrub") as HSlider
	sl.value = 90.0
	await idle(3)
	var at_free := (nd("asm_motion_at") as Label).text
	var y_free := piston_y_mm()
	ok(at_free.contains("NOT SOLVED") and at_free.contains("degree"), "f with 4 joints the scrub says: '%s'" % at_free)
	ctl(absf(y_free - y_rec) < 1e-6, "f before the slide joint the piston does not follow the crank: %.4f mm at 90 deg (record %.4f)" % [y_free, y_rec])
	await click_ctl(nd("asm_row_3") as Button)
	var jk := nd("asm_motion_jkind") as OptionButton
	jk.select(1)
	(nd("asm_motion_axis") as OptionButton).select(1)
	(nd("asm_motion_jto") as OptionButton).select(0)
	await type_in(nd("asm_motion_ox") as LineEdit, "0")
	await type_in(nd("asm_motion_oy") as LineEdit, "66.7")
	await type_in(nd("asm_motion_oz") as LineEdit, "39.15")
	await click_ctl(nd("asm_motion_jadd") as Button)
	var js := AL.joints(A.asm)
	var jl: Dictionary = js[js.size() - 1] if not js.is_empty() else {}
	ok(js.size() == 5 and String(jl.get("kind", "")) == "slider" and String(jl.get("a", "")) == "p4" and String(jl.get("b", "")) == "ground" and A.asm_undo.size() == 1, "f Add joint (Piston, Slide along Y, Ground): %d joints, %s, %d undo step" % [js.size(), JSON.stringify(jl), A.asm_undo.size()])
	var want: Array = []
	var got: Array = []
	var worst_y := 0.0
	var worst_rod := 0.0
	var texts: Array = []
	for th in [90.0, 180.0]:
		sl.value = th
		await idle(3)
		var t := deg_to_rad(th)
		var wy: float = x_closed(P.R, P.L, t) - P.PIN_Z
		want.append(snappedf(wy, 0.0001))
		got.append(snappedf(piston_y_mm(), 0.0001))
		worst_y = maxf(worst_y, absf(piston_y_mm() - wy))
		worst_rod = maxf(worst_rod, absf(wrapf(rod_deg() - rad_to_deg(P.rod_angle(t)), -180.0, 180.0)))
		texts.append((nd("asm_motion_at") as Label).text)
	ok(worst_y <= 1e-4 and worst_rod <= 1e-3 and not str(texts).contains("NOT SOLVED"), "f the scrub at 90 / 180 deg: piston at %s mm (closed form %s, worst %s mm), rod turn worst %s deg; '%s'" % [str(got), str(want), String.num_scientific(worst_y), String.num_scientific(worst_rod), "', '".join(PackedStringArray(texts))])
	await type_in(nd("asm_motion_steps") as LineEdit, "36")
	await click_ctl(nd("asm_motion_run") as Button)
	await idle(3)
	ok(nd("asm_motion_none") != null and nd("asm_motion_row_0") == null and nd("asm_motion_lock_0") == null, "f Run over 0..360 deg through the joints: no clash, no lock listed")
	sl.value = 90.0
	await idle(3)
	await shot("scrub90")
	m.get_viewport().gui_release_focus()
	await key(KEY_Z, 0, true)
	await idle(4)
	var after := JSON.stringify(A.asm, "", true)
	ok(after == before and AL.joints(A.asm).size() == 4 and absf(piston_y_mm() - y_rec) < 1e-6, "f Ctrl+Z: the record is as before (%s), 4 joints, the piston back at %.4f mm (record %.4f)" % [str(after == before), piston_y_mm(), y_rec])
	await shot("undone")


# ------------------------------------------------------------------ g
func sorted_json(path_or_text: String, is_text := false) -> String:
	var j = JSON.parse_string(path_or_text if is_text else FileAccess.get_file_as_string(path_or_text))
	return JSON.stringify(j, "", true) if j != null else ""


func bars_old() -> void:
	var keep := Assembly.dir
	Assembly.dir = "user://g2loop_old"
	var rec := Assembly.read(OLD)
	var r := AM.check_motion(rec, "anything", 10)
	if A != null:
		A.open_record(rec)
		await idle(4)
		A.motion.open()
		await idle(3)
		A.motion.close()
		await idle(2)
	var p1 := Assembly.save(A.asm if A != null else rec, "old_assembly")
	ok(not rec.is_empty() and not AL.has_joints(rec) and String(r["why"]).contains("no drive") and sorted_json(p1) == sorted_json(OLD), "g old_assembly.json: no joints, Check motion says '%s', saved back from the screen equal" % String(r["why"]))
	var d := Assembly.read(D199)
	var r1 := AM.check_motion(d, "Lid", 10)
	var w := AM.words(d, "Lid", r1)
	var p2 := ""
	if A != null:
		A.open_record(d)
		await idle(4)
		A.motion.open()
		await idle(3)
		A.motion.close()
		await idle(2)
		p2 = Assembly.save(A.asm, "drive_199")
	else:
		p2 = Assembly.save(d, "drive_199")
	ok(w.size() == 1 and w[0] == "Lid and Ceiling: from 70 deg, worst 184.0 mm3 at 70 deg" and int(r1["kernel_calls"]) == 13 and int(r1["skipped"]) == 10 and not r1.has("loop"), "g the #199 drive record: %s, %d kernel calls, %d skipped, loop path: %s (#199 gave the same line, 13, 10)" % [str(w), int(r1["kernel_calls"]), int(r1["skipped"]), str(r1.has("loop"))])
	ok(sorted_json(p2) == sorted_json(D199), "g the #199 record saved back from the screen is equal to the file")
	var dj: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string(D199)) as Dictionary).duplicate(true)
	AL.add_joint(dj, AL.make_joint("revolute", "p2", "ground", [0.0, 0.0, 1.0], [0.0, 0.0, 0.0]))
	var p3 := Assembly.save(dj, "drive_199")
	ctl(sorted_json(p3) != sorted_json(D199), "g the #199 record with a joint saved does not compare equal")
	Assembly.dir = keep


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
	if not Part.available() or not ClassDB.class_has_method("KineCAD", "overlap_volume"):
		ok(false, "the CAD DLL with overlap_volume is missing")
		print("g2loop: %d fail" % fails)
		quit(1)
		return
	bars_slider_crank()
	bars_four_bar()
	bars_engine()
	bars_clashes()
	bars_convergence()
	await bars_ui()
	await bars_old()
	print("g2loop: %d fail" % fails)
	quit(1 if fails > 0 else 0)
