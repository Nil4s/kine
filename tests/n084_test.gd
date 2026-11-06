## godot --headless --path . -s tests/n084_test.gd     (suite n084:h)   N084 BLEND MATRIX (docs/INNOVATIONS.md N084; scripts/blend_matrix.gd, native/src/kine_blend_native.cpp)
## For a moveset of N clips: every clip-to-clip crossfade (the end of A into the start of B over the blend time) is checked at its blend time for
## limit breaks, self-clash and foot skate, plus the pose distance at the seam; an NxN matrix with a verdict per cell and a ranked bad-pair list.
##
## THE BLEND (the definition both the module and this test follow; the test recomputes it with Body directly, not through the module):
##   dt = 1/60 s, m = max(2, round(blend_s x 60)) steps, T = m dt, LA = (nA-1)/fpsA, LB = (nB-1)/fpsB, t0A = max(LA - T, 0).
##   sample k = 0..m: tA = min(t0A + k dt, LA), tB = min(k dt, LB), w = smoothstep(k / m). A and B are read at those times (the two nearest
##   frames, linearly; the pelvis twist by the shorter way round), the joint angles are a + (b - a) w (UNCLAMPED: the engine clamps afterwards,
##   this reports what it would have to clamp), the hips are lerp(offsetA(tA), offsetB'(tB), w) with B moved on the floor so its hips at t = 0 sit
##   at A's hips at t0A (x, z); the height is each clip's own.
## METRICS per cell:
##   limit_deg   the most any joint axis (bend / side / twist) sits past its range in data/body_limits.json over the m + 1 samples; the joint and the axis
##   clash_mm    the deepest capsule pair past its allowance by more than 1 mm (Body.pairs, the touching_parts test; weapons out), over the samples; the pair
##   skate_mm    a foot planted at the start of the blend (sole under MocapMetrics.SOLE_H = 25 mm, ball under SOLE_V = 0.6 m/s in A's own motion) slides
##               over the floor while it stays down; the same backwards from the end (planted in B); planted at BOTH ends: the distance between the two
##   seam        PoseMatch's distance between A's last pose and B's first (mass-weighted mean joint difference in degrees + 100 deg per metre of hips height)
## BARS of the verdict: limit 1 deg, clash 10 mm, skate 25 mm = bad; half of a bar, or seam over 25 = warn; else ok.
##
## Bars, written BEFORE the implementation:
##  1 a clip into itself (the loop) at its loop point reads clean: idle, breath, edge, crouch_ok -> verdict ok, limit < 0.1, clash < 1, skate < 5
##  2 PLANTED skate: idle into a deep crouch (feet end up ~25 cm forward of the hips) with a 2-frame blend: skate_mm > 100, verdict bad, "skate" in why.
##    Controls: the matched crouch (feet stay under the hips) over 0.2 s skates < 25 mm; the idle into itself skates < 5 mm
##  3 PLANTED limit: a pose built 15 deg past upperarm_l's side limit: idle -> hyper flags upperarm_l / side at 15 +- 0.1 deg; hyper -> idle too;
##    control: edge (1 deg inside the limit) reads < 0.1 deg
##  4 PLANTED clash: the deepest of a few built poses (legs crossed, knees folded into the chest...) reads on the cell as the Body's own depth (+- 0.1 mm)
##    and is bad when it is over 10 mm; the idle into idle reads 0
##  5 the matrix equals the test's own recompute within 0.1 mm / 0.1 deg, native and GDScript twin, 6 clips x 6 at 0.2 s and at 2 frames
##  6 a 12-clip moveset matrix (144 cells) finishes in under 2 s native; the GDScript twin's time is printed
##  7 the JSON round-trips (cells, verdicts, bad list); the bad list is ranked high to low, holds exactly the bad cells, and idle -> idle is not in it
extends SceneTree

var fails := 0
var B: Body
const DT := 1.0 / 60.0
const SOLE_H := 0.025
const SOLE_V := 0.6
const AXES := ["bend", "side", "twist"]


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func control(claim: bool, what: String) -> void:
	print(("ok   control caught: " if not claim else "FAIL control NOT caught: ") + what)
	if claim:
		fails += 1


func body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.fk()
	return b


# ------------------------------------------------------------------ fixtures

func lowest(b: Body) -> float:
	return minf(b.foot_sole_low("_l"), b.foot_sole_low("_r"))


## the foot bend (deg) that makes the sole flat for these leg angles
func flat_bend(ov: Dictionary) -> float:
	var best := 0.0
	var bs := 1e9
	for fb in range(-60, 61):
		B.ang = {}
		for j in Body.ORDER:
			B.ang[j] = Vector3.ZERO
		for j in ov:
			B.ang[j] = ov[j]
		B.ang["foot_l"] = Vector3(fb, 0, 0)
		B.ang["foot_r"] = Vector3(fb, 0, 0)
		B.offset = Vector3.ZERO
		B.fk()
		var ys := [(B.P["foot_l"] as Vector3).y - (B.p0["foot_l"] as Vector3).y, (B.P["ball_l"] as Vector3).y - (B.p0["ball_l"] as Vector3).y,
			(B.E["ball_l"] as Vector3).y - (B.e0["ball_l"] as Vector3).y]
		var sc := (ys.max() as float) - (ys.min() as float)
		if sc < bs:
			bs = sc
			best = float(fb)
	return best


## a clip from joint overrides: n frames at 30 fps, a sway on spine_02 (a loop: the last frame is one step before the first), hips on the floor
func pose_clip(cname: String, ov: Dictionary, sway := 0.0, flat := false, n := 31, ground := true) -> Dictionary:
	var ovx := ov.duplicate()
	if flat:
		var fb := flat_bend(ov)
		ovx["foot_l"] = Vector3(fb, 0, 0)
		ovx["foot_r"] = Vector3(fb, 0, 0)
	var angs := []
	var offs := []
	for k in n:
		var a := {}
		for j in Body.ORDER:
			a[j] = Vector3.ZERO
		for j in ovx:
			a[j] = ovx[j]
		if sway != 0.0:
			a["spine_02"] = Vector3(sway * sin(TAU * float(k) / float(n)), 0, 0)
		B.ang = a.duplicate()
		B.offset = Vector3.ZERO
		B.fk()
		offs.append(Vector3(0, -lowest(B) if ground else 0.0, 0))
		angs.append(a)
	return BlendMatrix.make_clip(cname, 30.0, angs, offs)


func walk_clip() -> Dictionary:
	var angs := []
	var offs := []
	for k in 31:
		var ph := TAU * float(k) / 30.0
		var a := {}
		for j in Body.ORDER:
			a[j] = Vector3.ZERO
		a["thigh_l"] = Vector3(25.0 * sin(ph), 0, 0)
		a["thigh_r"] = Vector3(-25.0 * sin(ph), 0, 0)
		a["calf_l"] = Vector3(maxf(0.0, 40.0 * sin(ph + 1.2)), 0, 0)
		a["calf_r"] = Vector3(maxf(0.0, -40.0 * sin(ph + 1.2)), 0, 0)
		B.ang = a.duplicate()
		B.offset = Vector3.ZERO
		B.fk()
		offs.append(Vector3(0.03 * float(k) / 30.0 * 10.0, -lowest(B), 0))
		angs.append(a)
	return BlendMatrix.make_clip("walk_a", 30.0, angs, offs)


func limit_hi(j: String, ax: String) -> float:
	return (B.lim[j][ax] as Vector2).y


func fixtures() -> Dictionary:
	var hi := limit_hi("upperarm_l", "side")
	var out := {}
	out["idle"] = pose_clip("idle", {}, 3.0)
	out["breath"] = pose_clip("breath", {"upperarm_l": Vector3(0, hi * 0.3, 0)}, 6.0)
	out["crouch_deep"] = pose_clip("crouch_deep", {"thigh_l": Vector3(110, 0, 0), "thigh_r": Vector3(110, 0, 0), "calf_l": Vector3(130, 0, 0), "calf_r": Vector3(130, 0, 0)}, 0.0, true)
	out["crouch_ok"] = pose_clip("crouch_ok", {"thigh_l": Vector3(20, 0, 0), "thigh_r": Vector3(20, 0, 0), "calf_l": Vector3(40, 0, 0), "calf_r": Vector3(40, 0, 0)}, 0.0, true)
	out["hyper"] = pose_clip("hyper", {"upperarm_l": Vector3(0, hi + 15.0, 0)})
	out["edge"] = pose_clip("edge", {"upperarm_l": Vector3(0, hi - 1.0, 0)})
	out["fold"] = pose_clip("fold", fold_pose())
	out["reach_up"] = pose_clip("reach_up", {"upperarm_r": Vector3(140, 0, 0), "lowerarm_r": Vector3(20, 0, 0)})
	out["lunge"] = pose_clip("lunge", {"thigh_l": Vector3(60, 0, 0), "thigh_r": Vector3(-20, 0, 0), "calf_l": Vector3(70, 0, 0)}, 0.0, false)
	out["kick"] = pose_clip("kick", {"thigh_r": Vector3(70, 0, 0), "calf_r": Vector3(10, 0, 0)})
	out["walk_a"] = walk_clip()
	out["guard"] = pose_clip("guard", {"upperarm_l": Vector3(60, 0, 0), "upperarm_r": Vector3(60, 0, 0), "lowerarm_l": Vector3(90, 0, 0), "lowerarm_r": Vector3(90, 0, 0)}, 2.0)
	return out


func own_depth(b: Body) -> float:
	var worst := 0.0
	for pr in b.pairs:
		if pr[0] in Body.WEAPON or pr[1] in Body.WEAPON or pr[0] in Body.WEAPON2 or pr[1] in Body.WEAPON2:
			continue
		var d := b.depth(pr[0], pr[1]) - float(b.allow.get(pr[0] + "|" + pr[1], 0.0))
		if d > 0.001:
			worst = maxf(worst, d)
	return worst


var _fold: Dictionary = {}


## the deepest of a handful of built poses (legs crossed both ways, knees to the chest, a hand to the face): the planted clash
func fold_pose() -> Dictionary:
	if not _fold.is_empty():
		return _fold
	var cands := []
	for a in [-45.0, 45.0]:
		for b2 in [-45.0, 45.0]:
			cands.append({"thigh_l": Vector3(0, a, 0), "thigh_r": Vector3(0, b2, 0)})
	cands.append({"thigh_l": Vector3(120, 0, 0), "thigh_r": Vector3(120, 0, 0), "calf_l": Vector3(150, 0, 0), "calf_r": Vector3(150, 0, 0),
		"spine_01": Vector3(50, 0, 0), "spine_02": Vector3(40, 0, 0)})
	cands.append({"upperarm_r": Vector3(150, 0, 0), "lowerarm_r": Vector3(150, 0, 0)})
	cands.append({"upperarm_l": Vector3(90, 40, 0), "lowerarm_l": Vector3(140, 0, 0), "upperarm_r": Vector3(90, -40, 0), "lowerarm_r": Vector3(140, 0, 0)})
	cands.append({"thigh_l": Vector3(90, 0, 0), "thigh_r": Vector3(90, 0, 0), "spine_01": Vector3(60, 0, 0), "spine_02": Vector3(50, 0, 0)})
	var best := -1.0
	for c in cands:
		B.ang = {}
		for j in Body.ORDER:
			B.ang[j] = Vector3.ZERO
		for j in c:
			B.ang[j] = c[j]
		B.offset = Vector3.ZERO
		B.fk()
		var d := own_depth(B)
		if d > best:
			best = d
			_fold = c
	print("     planted clash pose depth %.1f mm" % (best * 1000.0))
	return _fold


# ------------------------------------------------------------------ the test's own recompute (Body directly)

func samp(c: Dictionary, t: float) -> Dictionary:
	var n: int = c["n"]
	var f := clampf(t * float(c["fps"]), 0.0, float(n - 1))
	var i0 := int(floor(f))
	var i1 := mini(i0 + 1, n - 1)
	var u := f - float(i0)
	var J: int = Body.ORDER.size()
	var a := {}
	for ji in J:
		var j: String = Body.ORDER[ji]
		var va: Vector3 = (c["ang"] as PackedVector3Array)[i0 * J + ji]
		var vb: Vector3 = (c["ang"] as PackedVector3Array)[i1 * J + ji]
		a[j] = va + Scene._d(va, vb, j) * u
	var oa: Vector3 = (c["off"] as PackedVector3Array)[i0]
	var ob: Vector3 = (c["off"] as PackedVector3Array)[i1]
	return {"ang": a, "off": oa + (ob - oa) * u}


func put(b: Body, ang: Dictionary, off: Vector3) -> void:
	for j in Body.ORDER:
		b.ang[j] = ang[j]
	b.offset = off
	b.fk()


func xz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func ref_cell(ca: Dictionary, cb: Dictionary, blend_s: float) -> Dictionary:
	var m := maxi(2, int(round(blend_s * 60.0)))
	var T := float(m) * DT
	var LA := float(int(ca["n"]) - 1) / float(ca["fps"])
	var LB := float(int(cb["n"]) - 1) / float(cb["fps"])
	var t0A := maxf(LA - T, 0.0)
	var ref_a := xz(samp(ca, t0A)["off"])
	var b0 := xz(samp(cb, 0.0)["off"])
	var bb := body()
	var low_d := {"_l": [], "_r": []}
	var ball := {"_l": [], "_r": []}
	var lim_x := 0.0
	var lim_j := ""
	var lim_ax := ""
	var clash := 0.0
	var cl_a := ""
	var cl_b := ""
	for k in m + 1:
		var tA := minf(t0A + float(k) * DT, LA)
		var tB := minf(float(k) * DT, LB)
		var w := smoothstep(0.0, 1.0, float(k) / float(m))
		var sa := samp(ca, tA)
		var sb := samp(cb, tB)
		var ang := {}
		for j in Body.ORDER:
			var va: Vector3 = sa["ang"][j]
			var vb: Vector3 = sb["ang"][j]
			var r := va + Scene._d(va, vb, j) * w
			if j == "pelvis":
				r.z = wrapf(r.z, -180.0, 180.0)
			ang[j] = r
		var oa: Vector3 = sa["off"]
		var ob: Vector3 = sb["off"]
		var obx := Vector3(ob.x - b0.x + ref_a.x, ob.y, ob.z - b0.y + ref_a.y)
		put(bb, ang, oa.lerp(obx, w))
		for j in Body.ORDER:
			var v: Vector3 = ang[j]
			for ai in 3:
				var rg: Vector2 = bb.lim[j][AXES[ai]]
				var x := maxf(maxf(rg.x - v[ai], v[ai] - rg.y), 0.0)
				if x > lim_x:
					lim_x = x
					lim_j = j
					lim_ax = AXES[ai]
		for pr in bb.pairs:
			if pr[0] in Body.WEAPON or pr[1] in Body.WEAPON or pr[0] in Body.WEAPON2 or pr[1] in Body.WEAPON2:
				continue
			var d := bb.depth(pr[0], pr[1]) - float(bb.allow.get(pr[0] + "|" + pr[1], 0.0))
			if d > 0.001 and d > clash:
				clash = d
				cl_a = pr[0]
				cl_b = pr[1]
		for sd in ["_l", "_r"]:
			(low_d[sd] as Array).append(bb.foot_sole_low(sd))
			(ball[sd] as Array).append(xz(bb.P["ball" + sd]))
	# the speeds of the planted feet in each clip's own motion
	var tA0 := t0A
	var tAo := tA0 + DT if tA0 + DT <= LA else tA0 - DT
	var tBm := minf(T, LB)
	var tBo := tBm + DT if tBm + DT <= LB else tBm - DT
	var pa := speed_pair(bb, ca, tA0, tAo, Vector2.ZERO, false)
	var pbv := speed_pair(bb, cb, tBm, tBo, ref_a - b0, true)
	var skate := 0.0
	var sk_foot := ""
	for sd in ["_l", "_r"]:
		var lw: Array = low_d[sd]
		var bl: Array = ball[sd]
		var sp: bool = float(pa[sd]) < SOLE_V and float(lw[0]) < SOLE_H
		var ep: bool = float(pbv[sd]) < SOLE_V and float(lw[m]) < SOLE_H
		var s := 0.0
		if sp:
			for k in range(1, m + 1):
				if lw[k] >= SOLE_H:
					break
				s = maxf(s, (bl[k] as Vector2).distance_to(bl[0]))
		if ep:
			for k in range(m - 1, -1, -1):
				if lw[k] >= SOLE_H:
					break
				s = maxf(s, (bl[k] as Vector2).distance_to(bl[m]))
		if sp and ep:
			s = maxf(s, (bl[m] as Vector2).distance_to(bl[0]))
		if s > skate:
			skate = s
			sk_foot = "foot" + sd
	# the seam
	var qa := samp(ca, LA)
	var qb := samp(cb, 0.0)
	var tot := 0.0
	var sm := 0.0
	for j in Body.ORDER:
		var d3: Vector3 = Scene._d(qa["ang"][j], qb["ang"][j], j)
		if j == "pelvis":
			d3.z = 0.0
		var mm := PoseMatch.weight(j)
		sm += mm * d3.length()
		tot += mm
	var seam := sm / tot + PoseMatch.HEIGHT_W * absf((qb["off"] as Vector3).y - (qa["off"] as Vector3).y)
	return {"limit_deg": lim_x, "limit_joint": lim_j, "limit_axis": lim_ax, "clash_mm": clash * 1000.0, "clash_a": cl_a, "clash_b": cl_b,
		"skate_mm": skate * 1000.0, "skate_foot": sk_foot, "seam": seam}


## each foot's ball speed (m/s over the floor) in one clip's own motion between times t and t2 (B's hips moved by `shift` in x, z)
func speed_pair(bb: Body, c: Dictionary, t: float, t2: float, shift: Vector2, _is_b: bool) -> Dictionary:
	var out := {}
	var pos := []
	for tt in [t, t2]:
		var s := samp(c, tt)
		var o: Vector3 = s["off"]
		put(bb, s["ang"], Vector3(o.x + shift.x, o.y, o.z + shift.y))
		pos.append({"_l": xz(bb.P["ball_l"]), "_r": xz(bb.P["ball_r"])})
	for sd in ["_l", "_r"]:
		out[sd] = (pos[0][sd] as Vector2).distance_to(pos[1][sd]) / DT if absf(t - t2) > 1e-9 else 0.0
	return out


func near(a: float, b: float, tol := 0.1) -> bool:
	return absf(a - b) <= tol


## a module cell against the recompute: every number within 0.1, the joint/axis/pair/foot names equal where the number is above its noise floor
func cell_equal(c: Dictionary, r: Dictionary) -> String:
	for k in ["limit_deg", "clash_mm", "skate_mm", "seam"]:
		if not near(float(c[k]), float(r[k])):
			return "%s %.3f vs %.3f" % [k, float(c[k]), float(r[k])]
	if float(r["limit_deg"]) > 0.2 and (c["limit_joint"] != r["limit_joint"] or c["limit_axis"] != r["limit_axis"]):
		return "limit joint %s/%s vs %s/%s" % [c["limit_joint"], c["limit_axis"], r["limit_joint"], r["limit_axis"]]
	if float(r["clash_mm"]) > 1.2 and not (c["clash_a"] == r["clash_a"] and c["clash_b"] == r["clash_b"]):
		return "clash pair %s|%s vs %s|%s" % [c["clash_a"], c["clash_b"], r["clash_a"], r["clash_b"]]
	if float(r["skate_mm"]) > 0.2 and c["skate_foot"] != r["skate_foot"] and absf(float(c["skate_mm"]) - float(r["skate_mm"])) < 0.01:
		return "skate foot %s vs %s" % [c["skate_foot"], r["skate_foot"]]
	return ""


func cell_of(M: Dictionary, a: String, b: String) -> Dictionary:
	var names: Array = M["names"]
	return M["cells"][names.find(a)][names.find(b)]


func _init() -> void:
	B = body()
	var fx := fixtures()
	var names6 := ["idle", "crouch_deep", "crouch_ok", "hyper", "edge", "fold"]
	var clips6 := []
	for nme in names6:
		clips6.append(fx[nme])
	ok(BlendMatrix.native_ok(), "0 the native class KineBlendNative is there (native/bin built)")
	var M := BlendMatrix.matrix(clips6, 0.2)
	ok(bool(M.get("ok", false)) and int(M["n"]) == 6 and (M["cells"] as Array).size() == 6, "0 a 6-clip matrix: 6 x 6 cells, engine %s, %.1f ms" % [M.get("engine", "?"), float(M.get("ms", -1.0))])
	# 1 loops
	for nme in ["idle", "breath", "edge", "crouch_ok"]:
		var Ml := BlendMatrix.matrix([fx[nme]], 0.2)
		var c: Dictionary = Ml["cells"][0][0]
		print("     loop %-10s limit %.3f clash %.3f skate %.3f seam %.2f -> %s" % [nme, c["limit_deg"], c["clash_mm"], c["skate_mm"], c["seam"], c["verdict"]])
		ok(c["verdict"] == "ok" and float(c["limit_deg"]) < 0.1 and float(c["clash_mm"]) < 1.0 and float(c["skate_mm"]) < 5.0, "1 %s into itself at the loop point reads clean" % nme)
	# 2 skate
	var M2 := BlendMatrix.matrix([fx["idle"], fx["crouch_deep"]], 2.0 / 60.0)
	var cd: Dictionary = M2["cells"][0][1]
	print("     idle -> crouch_deep, 2 frames: skate %.1f mm (%s) clash %.1f limit %.2f seam %.1f -> %s: %s" % [cd["skate_mm"], cd["skate_foot"], cd["clash_mm"], cd["limit_deg"], cd["seam"], cd["verdict"], cd["why"]])
	ok(float(cd["skate_mm"]) > 100.0 and cd["verdict"] == "bad" and "skate" in String(cd["why"]), "2 idle into a deep crouch over 2 frames: skate %.0f mm > 100, bad, the words say skate" % float(cd["skate_mm"]))
	var M2b := BlendMatrix.matrix([fx["idle"], fx["crouch_ok"]], 0.2)
	var co: Dictionary = M2b["cells"][0][1]
	print("     idle -> crouch_ok, 0.2 s: skate %.1f mm limit %.2f clash %.1f seam %.1f -> %s" % [co["skate_mm"], co["limit_deg"], co["clash_mm"], co["seam"], co["verdict"]])
	ok(float(co["skate_mm"]) < 25.0, "2 control: the matched crouch over 0.2 s skates %.1f mm < 25" % float(co["skate_mm"]))
	control(float(co["skate_mm"]) > 100.0, "2b the matched crouch is not read as the bad one")
	ok(float((M2b["cells"][0][0] as Dictionary)["skate_mm"]) < 5.0, "2 control: idle into itself skates %.2f mm < 5" % float((M2b["cells"][0][0] as Dictionary)["skate_mm"]))
	# 3 limits
	var M3 := BlendMatrix.matrix([fx["idle"], fx["hyper"], fx["edge"]], 0.2)
	var ch: Dictionary = M3["cells"][0][1]
	var chi: Dictionary = M3["cells"][1][0]
	var ce: Dictionary = M3["cells"][0][2]
	ok(ch["limit_joint"] == "upperarm_l" and ch["limit_axis"] == "side" and near(float(ch["limit_deg"]), 15.0), "3 idle -> hyper: %s / %s at %.2f deg (15 planted)" % [ch["limit_joint"], ch["limit_axis"], float(ch["limit_deg"])])
	ok(chi["limit_joint"] == "upperarm_l" and chi["limit_axis"] == "side" and near(float(chi["limit_deg"]), 15.0) and ch["verdict"] == "bad", "3 hyper -> idle: the same joint at %.2f deg; idle -> hyper is bad" % float(chi["limit_deg"]))
	ok(float(ce["limit_deg"]) < 0.1 and ce["verdict"] != "bad", "3 control: idle -> edge (1 deg inside the limit) reads %.3f deg, not bad" % float(ce["limit_deg"]))
	control(ch["limit_joint"] == "thigh_l", "3b the hyper pair does not name the wrong joint")
	# 4 clash
	var Mc := BlendMatrix.matrix([fx["idle"], fx["fold"]], 0.2)
	var cf: Dictionary = Mc["cells"][0][1]
	var want := fold_depth_mm(fx["fold"])
	print("     idle -> fold: clash %.1f mm (%s | %s), the Body's own depth of the pose %.1f mm -> %s" % [cf["clash_mm"], cf["clash_a"], cf["clash_b"], want, cf["verdict"]])
	ok(near(float(cf["clash_mm"]), want) and want > 10.0 and cf["verdict"] == "bad", "4 the planted clash reads the Body's own depth %.1f mm (> 10) and is bad" % want)
	ok(float((Mc["cells"][0][0] as Dictionary)["clash_mm"]) < 0.1, "4 control: idle into idle clashes 0")
	# 5 equality, native and the twin, at 0.2 s and at 2 frames
	var worst := 0.0
	var bad_cells := []
	for bs in [0.2, 2.0 / 60.0]:
		var Mn := BlendMatrix.matrix(clips6, bs, {"native": true})
		var Mg := BlendMatrix.matrix(clips6, bs, {"native": false})
		ok(Mn["engine"] == "native" and Mg["engine"] == "gd", "5 engines: %s and %s" % [Mn["engine"], Mg["engine"]])
		var cmp_n := 0
		var cmp_g := 0
		for i in 6:
			for j in 6:
				var r := ref_cell(clips6[i], clips6[j], bs)
				var e1 := cell_equal(Mn["cells"][i][j], r)
				var e2 := cell_equal(Mg["cells"][i][j], r)
				if e1 == "":
					cmp_n += 1
				else:
					bad_cells.append("native %s>%s %s" % [names6[i], names6[j], e1])
				if e2 == "":
					cmp_g += 1
				else:
					bad_cells.append("gd %s>%s %s" % [names6[i], names6[j], e2])
				for k in ["limit_deg", "clash_mm", "skate_mm", "seam"]:
					worst = maxf(worst, absf(float(Mn["cells"][i][j][k]) - float(r[k])))
		ok(cmp_n == 36 and cmp_g == 36, "5 blend %.3f s: native %d / 36 and GDScript twin %d / 36 cells equal the recompute within 0.1" % [bs, cmp_n, cmp_g])
	for s in bad_cells.slice(0, 6):
		print("     DIFF " + s)
	print("     worst native-vs-recompute difference %.4f" % worst)
	# 6 the 12-clip moveset
	var clips12 := []
	for nme in fx:
		clips12.append(fx[nme])
	ok(clips12.size() == 12, "6 the moveset has 12 clips")
	var t0 := Time.get_ticks_usec()
	var M12 := BlendMatrix.matrix(clips12, 0.2, {"native": true})
	var ms_n := float(Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	var M12g := BlendMatrix.matrix(clips12, 0.2, {"native": false})
	var ms_g := float(Time.get_ticks_usec() - t0) / 1000.0
	print("     12 clips: native %.0f ms, GDScript twin %.0f ms, %d bad cells" % [ms_n, ms_g, (M12["bad"] as Array).size()])
	ok(M12["engine"] == "native" and ms_n < 2000.0 and (M12["cells"] as Array).size() == 12, "6 12-clip moveset (144 cells): %.0f ms native < 2000" % ms_n)
	var diff12 := 0.0
	for i in 12:
		for j in 12:
			for k in ["limit_deg", "clash_mm", "skate_mm", "seam"]:
				diff12 = maxf(diff12, absf(float(M12["cells"][i][j][k]) - float(M12g["cells"][i][j][k])))
	ok(diff12 < 0.1, "6 native and the GDScript twin agree over all 144 cells: worst %.4f" % diff12)
	# 7 json, ranking
	var js := BlendMatrix.to_json(M12)
	var back := BlendMatrix.from_json(js)
	var same: bool = back.get("names", []) == M12["names"] and (back["cells"] as Array).size() == 12 and (back["bad"] as Array).size() == (M12["bad"] as Array).size()
	var worst_rt := 0.0
	if same:
		for i in 12:
			for j in 12:
				var c1: Dictionary = M12["cells"][i][j]
				var c2: Dictionary = back["cells"][i][j]
				for k in ["verdict", "why", "limit_joint", "limit_axis", "clash_a", "clash_b", "skate_foot"]:
					if c1[k] != c2[k]:
						same = false
				for k in ["limit_deg", "clash_mm", "skate_mm", "seam", "score"]:
					worst_rt = maxf(worst_rt, absf(float(c1[k]) - float(c2[k])))
	ok(same and worst_rt < 1e-3, "7 the JSON round-trips: %d bytes, cells, verdicts and the bad list equal, worst number difference %s" % [js.length(), str(worst_rt)])
	var bad: Array = M12["bad"]
	var sorted := true
	for i in range(1, bad.size()):
		if float(bad[i]["score"]) > float(bad[i - 1]["score"]):
			sorted = false
	var n_bad := 0
	var names12: Array = M12["names"]
	for i in 12:
		for j in 12:
			if M12["cells"][i][j]["verdict"] == "bad":
				n_bad += 1
	var has_idle_idle := false
	var has_planted := false
	for e in bad:
		if e["a"] == "idle" and e["b"] == "idle":
			has_idle_idle = true
		if e["a"] == "idle" and e["b"] == "hyper":
			has_planted = true
	ok(sorted and bad.size() == n_bad and n_bad > 0 and has_planted, "7 the ranked list: %d bad pairs, high to low, exactly the bad cells, idle -> hyper in it" % bad.size())
	control(has_idle_idle, "7b idle -> idle is listed as a bad pair")
	if not bad.is_empty():
		print("     worst pair: %s -> %s  %s" % [bad[0]["a"], bad[0]["b"], bad[0]["why"]])
	print("N084 TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	print("n084: %d fail" % fails)
	quit(fails)


func fold_depth_mm(c: Dictionary) -> float:
	var ang := {}
	for j in Body.ORDER:
		ang[j] = (c["ang"] as PackedVector3Array)[j_index(j)]
	put(B, ang, (c["off"] as PackedVector3Array)[0])
	return own_depth(B) * 1000.0


func j_index(j: String) -> int:
	return Body.ORDER.find(j)
