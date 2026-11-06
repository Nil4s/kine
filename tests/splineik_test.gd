## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/splineik_test.gd     (GAP_AUDIT_1106 animation item 5:
## SPLINE IK for any bone chain + STRETCHY limbs; scripts/spline_chain.gd, native/src/kine_spline_native.cpp, LimbIK.solve's stretch)
## Golden: SPLINEIK_GEN=1 writes tests/splineik_golden.txt (made on the base, BEFORE the code). Picture: tests/splineik_shot.gd.
## Bars, written before measuring (each has a PLANTED control: the same check on a deliberately broken input must FAIL):
##   1 ON THE CURVE: keep-length mode, a 10-bone chain on a 4-handle Catmull and a 5-handle Bezier curve whose length equals the chain's:
##     every joint within 1 mm of the curve (an independent fine scan with the test's own Bezier evaluator). Planted: one joint 5 mm off.
##   2 STRETCH TO FIT: chain 0.6 and 1.5 times the curve: total chain length (sum of the posed bone lengths) = the curve's arc length
##     +-0.5 %, the end joint on the curve's end within 1 mm. Planted: a 2 % short chain.
##   3 TWIST: root -10 deg, tip +50 deg: measured from the posed frames (parallel transport of the rest frame, independent of the solver)
##     strictly rising bone to bone, the last bone at the tip twist within 0.1 deg. Planted: the tip set 1 deg short.
##   4 STRETCHY LIMB: hand_l target at 1.2x the arm's reach, stretch on (max 1.5): hand within 1 mm; the elbow stays on the shoulder-target
##     line (straight); stretch off: stops at full reach and the angles + tip are the OLD solver's, equal to the golden made on the base
##     (also in reach with stretch on). Planted: stretch off must miss by > 5 cm.
##   5 VOLUME: s * c * c = 1 +-1 % for every bone of the spline chain (volume on) and the limb. Planted: volume off gives a product off by > 1 %.
##   6 DEFAULT OFF: pose bytes (angles and positions) of the library scenes at 5 times each equal the golden made on the base. Planted: a golden
##     line with one digit changed must differ.
##   7 NATIVE = GDSCRIPT: C++ and the GDScript fallback agree within 1e-9 on joints, axes, scales. Planted: a 1e-6 nudge is caught.
##   8 SAVE / LOAD / UNDO: make a chain on 4 extruded bones (one undo step), move a handle (one step), toggle stretch (one step); the scene file
##     has "spline_chains" with "v": 1 and validates; file -> load -> file is byte-identical; Ctrl+Z x3 gives back exactly the chain list before.
##     A scene with no chain has no "spline_chains" key. The bones drawn sit on the solved joints within 1 mm. Planted: one word changed in the file.
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


# ---- independent measuring tools (not the solver's code)

func _bez(a: Vector3, b: Vector3, c: Vector3, d: Vector3, t: float) -> Vector3:
	var ab := a.lerp(b, t)
	var bc := b.lerp(c, t)
	var cd := c.lerp(d, t)
	return ab.lerp(bc, t).lerp(bc.lerp(cd, t), t)


## the curve as a fine polyline from the control points, built by the test's own rules (Catmull as piecewise Bezier / one Bezier)
func ref_poly(ctrl: Array, kind: String, n_per := 2000) -> PackedVector3Array:
	var out := PackedVector3Array()
	var k := ctrl.size()
	if kind == "bezier":
		for i in n_per * (k - 1) + 1:
			var t := float(i) / float(n_per * (k - 1))
			var pts := ctrl.duplicate()
			while pts.size() > 1:
				var nx := []
				for j in pts.size() - 1:
					nx.append((pts[j] as Vector3).lerp(pts[j + 1], t))
				pts = nx
			out.append(pts[0])
		return out
	for s in k - 1:
		var p0: Vector3 = ctrl[s]
		var p1: Vector3 = ctrl[s + 1]
		var m0: Vector3 = (ctrl[1] - ctrl[0]) if s == 0 else (ctrl[s + 1] - ctrl[s - 1]) * 0.5
		var m1: Vector3 = (ctrl[k - 1] - ctrl[k - 2]) if s == k - 2 else (ctrl[s + 2] - ctrl[s]) * 0.5
		for i in n_per + (1 if s == k - 2 else 0):
			out.append(_bez(p0, p0 + m0 / 3.0, p1 - m1 / 3.0, p1, float(i) / n_per))
	return out


func poly_len(p: PackedVector3Array) -> float:
	var L := 0.0
	for i in p.size() - 1:
		L += p[i].distance_to(p[i + 1])
	return L


func dist_poly(p: PackedVector3Array, q: Vector3) -> float:
	var best := INF
	for i in p.size() - 1:
		var c := Geometry3D.get_closest_point_to_segment(q, p[i], p[i + 1])
		best = minf(best, c.distance_to(q))
	return best


func max_off_curve(r: Dictionary, poly: PackedVector3Array) -> float:
	var w := 0.0
	for j in r["joints"]:
		w = maxf(w, dist_poly(poly, j))
	return w


func chain_len(r: Dictionary) -> float:
	var L := 0.0
	var j: Array = r["joints"]
	for i in j.size() - 1:
		L += (j[i] as Vector3).distance_to(j[i + 1])
	return L


## the twist of each bone about its own axis against a reference frame carried down the joints by smallest swings
func twists(r: Dictionary, x0: Vector3, y0: Vector3) -> Array:
	var out := []
	var j: Array = r["joints"]
	var ref := x0
	var yp := y0
	for i in r["axes"].size():
		var y: Vector3 = ((j[i + 1] as Vector3) - (j[i] as Vector3)).normalized()
		ref = Quaternion(yp, y) * ref
		yp = y
		ref = (ref - y * ref.dot(y)).normalized()
		var x: Vector3 = (r["axes"][i] as Basis).x
		x = (x - y * x.dot(y)).normalized()
		out.append(rad_to_deg(atan2(ref.cross(x).dot(y), ref.dot(x))))
	return out


func tail_lens(n: int, each: float) -> Array:
	var a := []
	for i in n:
		a.append(each)
	return a


const C4 := [Vector3(0, 0, 0), Vector3(0.25, 0.3, 0), Vector3(0.6, 0.45, 0.2), Vector3(0.95, 0.2, 0.35)]
const C5 := [Vector3(0, 0, 0), Vector3(0.2, 0.35, 0), Vector3(0.5, 0.5, 0.15), Vector3(0.75, 0.3, 0.3), Vector3(1.0, 0.0, 0.2)]


func opts(kind: String, mode: String, tw0 := 0.0, tw1 := 0.0, vol := false) -> Dictionary:
	return {"kind": kind, "mode": mode, "tw0": tw0, "tw1": tw1, "volume": vol, "rest_y": Vector3.UP, "rest_x": Vector3.RIGHT}


# ---- the checks (each is run on the real result and on a planted-broken one)

func chk_on_curve(r: Dictionary, poly: PackedVector3Array) -> bool:
	return max_off_curve(r, poly) < 0.001


func chk_fit(r: Dictionary, poly: PackedVector3Array) -> bool:
	return absf(chain_len(r) / poly_len(poly) - 1.0) <= 0.005 and (r["joints"][r["joints"].size() - 1] as Vector3).distance_to(poly[poly.size() - 1]) < 0.001


func chk_twist(tw: Array, want_tip: float) -> bool:
	for i in range(1, tw.size()):
		if not (tw[i] > tw[i - 1] + 1e-6):
			return false
	return absf(tw[tw.size() - 1] - want_tip) < 0.1


func chk_vol(r: Dictionary) -> bool:
	for i in r["scale"].size():
		var p: float = float(r["scale"][i]) * float(r["cross"][i]) * float(r["cross"][i])
		if absf(p - 1.0) > 0.01:
			return false
	return true


func chk_same(a: Dictionary, b: Dictionary, tol: float) -> bool:
	for i in a["joints"].size():
		if (a["joints"][i] as Vector3).distance_to(b["joints"][i]) > tol:
			return false
	for i in a["axes"].size():
		var x: Basis = a["axes"][i]
		var y: Basis = b["axes"][i]
		if x.x.distance_to(y.x) > tol or x.y.distance_to(y.y) > tol or x.z.distance_to(y.z) > tol or absf(float(a["scale"][i]) - float(b["scale"][i])) > tol:
			return false
	return true


# ---- golden

func scene_files() -> Array:
	var out := []
	for f in DirAccess.get_files_at("res://scenes"):
		if f.ends_with(".json"):
			out.append("res://scenes/" + f)
	out.sort()
	return out


func body() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	for j in B.ang.keys():
		B.ang[j] = Vector3.ZERO
	B.fk()
	return B


func limb_hash(b: Body, r: Dictionary) -> String:
	return (var_to_str(b.ang["upperarm_l"]) + var_to_str(b.ang["lowerarm_l"]) + var_to_str(b.P["hand_l"]) + var_to_str(r["miss"])).md5_text()


func golden_lines() -> Dictionary:
	var g := {}
	var B := body()
	for path in scene_files():
		var S := Scene.new()
		S.from_dict(JSON.parse_string(FileAccess.get_file_as_string(path)))
		var L := S.length()
		for k in 5:
			S.apply(B, L * float(k) / 4.0)
			g["%s@%d" % [path.get_file(), k]] = (var_to_str(B.ang) + var_to_str(B.P) + var_to_str(B.offset)).md5_text()
	# the old solver on the left arm: out of reach (1.2x) and in reach (0.8x), stretch not asked for
	for f in [1.2, 0.8]:
		var b := body()
		var sh: Vector3 = b.P["upperarm_l"]
		var reach: float = (b.p0["lowerarm_l"] - b.p0["upperarm_l"]).length() + (b.p0["hand_l"] - b.p0["lowerarm_l"]).length()
		var tgt: Vector3 = sh + Vector3(0.3, -0.5, 0.4).normalized() * reach * f
		var r := LimbIK.solve(b, "hand_l", tgt, tgt + Vector3(0, 0, 1))
		g["limb_%.1f" % f] = limb_hash(b, r)
	return g


func _init() -> void:
	if OS.get_environment("SPLINEIK_GEN") == "1":
		var g := golden_lines()
		var f := FileAccess.open("res://tests/splineik_golden.txt", FileAccess.WRITE)
		var ks := g.keys()
		ks.sort()
		for k in ks:
			f.store_line("%s %s" % [k, g[k]])
		f.close()
		print("golden written: %d lines" % ks.size())
		quit(0)
		return
	_main()


func _main() -> void:
	# 1 ON THE CURVE
	for case in [["catmull", C4], ["bezier", C5]]:
		var kind: String = case[0]
		var ctrl: Array = case[1]
		var poly := ref_poly(ctrl, kind)
		var L := poly_len(poly)
		var r := SplineChain.solve(ctrl[0], tail_lens(10, L / 10.0 * 0.99), ctrl, opts(kind, "keep"))
		ok(chk_on_curve(r, poly), "1 %s: 11 joints on the curve, worst %.3f mm (curve %.3f m, chain %.3f m)" % [kind, max_off_curve(r, poly) * 1000.0, L, chain_len(r)])
		var bl := true
		for i in 10:
			bl = bl and absf(((r["joints"][i + 1] as Vector3) - r["joints"][i]).length() - L / 10.0 * 0.99) < 1e-4
		ok(bl, "1 %s: every bone kept its rest length (0.1 mm)" % kind)
		var bad := r.duplicate(true)
		bad["joints"][5] = (bad["joints"][5] as Vector3) + Vector3(0.005, 0, 0)
		ok(not chk_on_curve(bad, poly), "1 PLANTED %s: a joint 5 mm off the curve is caught" % kind)
	# 2 STRETCH TO FIT
	for case in [["catmull", C4, 0.6], ["catmull", C4, 1.5], ["bezier", C5, 0.7]]:
		var kind: String = case[0]
		var ctrl: Array = case[1]
		var poly := ref_poly(ctrl, kind)
		var L := poly_len(poly)
		var r := SplineChain.solve(ctrl[0], tail_lens(10, L * case[2] / 10.0), ctrl, opts(kind, "stretch"))
		var sc: float = r["scale"][3]
		ok(chk_fit(r, poly) and chk_on_curve(r, poly), "2 %s chain %.1fx the curve: length %.4f of %.4f m (%.3f %%), scale %.3f, joints on the curve %.3f mm" % [kind, case[2], chain_len(r), L, (chain_len(r) / L - 1.0) * 100.0, sc, max_off_curve(r, poly) * 1000.0])
		var bad := r.duplicate(true)
		for i in bad["joints"].size():
			bad["joints"][i] = (bad["joints"][i] as Vector3) * 0.98
		ok(not chk_fit(bad, poly), "2 PLANTED %s: a chain 2 %% short is caught" % kind)
	var polyk := ref_poly(C4, "catmull")
	var rk := SplineChain.solve(C4[0], tail_lens(10, poly_len(polyk) * 0.6 / 10.0), C4, opts("catmull", "keep"))
	ok(chain_len(rk) / poly_len(polyk) < 0.61 and rk["scale"][3] == 1.0, "2 keep-length does NOT stretch: a 0.6x chain stays 0.6x (%.3f)" % (chain_len(rk) / poly_len(polyk)))
	# 3 TWIST
	var poly3 := ref_poly(C4, "catmull")
	var r3 := SplineChain.solve(C4[0], tail_lens(10, poly_len(poly3) / 10.0 * 0.99), C4, opts("catmull", "keep", -10.0, 50.0))
	var tw := twists(r3, Vector3.RIGHT, Vector3.UP)
	ok(chk_twist(tw, 50.0), "3 twist rises from %.2f to %.3f deg over %d bones (set -10 -> 50)" % [tw[0], tw[tw.size() - 1], tw.size()])
	ok(not chk_twist(tw, 49.0), "3 PLANTED: a tip 1 deg off is caught")
	var r3b := SplineChain.solve(C4[0], tail_lens(10, poly_len(poly3) / 10.0 * 0.99), C4, opts("catmull", "keep", 0.0, 0.0))
	var tw0 := twists(r3b, Vector3.RIGHT, Vector3.UP)
	ok(not chk_twist(tw0, 50.0), "3 PLANTED: a chain with no twist set does not pass the twist check (tip %.2f)" % tw0[tw0.size() - 1])
	# 5 VOLUME (spline)
	var r5 := SplineChain.solve(C4[0], tail_lens(10, poly_len(poly3) * 0.6 / 10.0), C4, opts("catmull", "stretch", 0, 0, true))
	ok(chk_vol(r5) and r5["scale"][0] > 1.5, "5 spline volume on: s*c*c = 1 for 10 bones (stretch %.2f, cross %.3f)" % [r5["scale"][0], r5["cross"][0]])
	var r5b := SplineChain.solve(C4[0], tail_lens(10, poly_len(poly3) * 0.6 / 10.0), C4, opts("catmull", "stretch", 0, 0, false))
	ok(not chk_vol(r5b), "5 PLANTED: volume off leaves the product off 1 by > 1 %% (%.3f)" % (float(r5b["scale"][0]) * float(r5b["cross"][0]) * float(r5b["cross"][0])))
	# 7 NATIVE = GDSCRIPT
	var native_on: bool = ClassDB.class_exists("KineSplineNative") or NativeExt.ensure("kine_native", "KineSplineNative")
	ok(native_on, "7 the C++ class KineSplineNative is loaded")
	var rn := SplineChain.solve(C5[0], tail_lens(12, 0.11), C5, opts("bezier", "keep", 5.0, 70.0, true))
	var rg := SplineChain.solve_gd(C5[0], tail_lens(12, 0.11), C5, opts("bezier", "keep", 5.0, 70.0, true))
	ok(bool(rn["native"]) and not bool(rg["native"]) and chk_same(rn, rg, 1e-9), "7 native %s, GDScript fallback %s, same within 1e-9" % [rn["native"], rg["native"]])
	var rn2 := SplineChain.solve(C4[0], tail_lens(10, 0.1), C4, opts("catmull", "stretch", 0, 30, false))
	var rg2 := SplineChain.solve_gd(C4[0], tail_lens(10, 0.1), C4, opts("catmull", "stretch", 0, 30, false))
	ok(chk_same(rn2, rg2, 1e-9), "7 stretch mode: native = GDScript within 1e-9")
	var nud := rg.duplicate(true)
	nud["joints"][4] = (nud["joints"][4] as Vector3) + Vector3(1e-6, 0, 0)
	ok(not chk_same(rn, nud, 1e-9), "7 PLANTED: a 1e-6 nudge is caught")
	# 6 DEFAULT OFF (the golden of the base)
	var gold := {}
	for line in FileAccess.get_file_as_string("res://tests/splineik_golden.txt").split("\n"):
		var p := line.split(" ")
		if p.size() == 2:
			gold[p[0]] = p[1]
	var now := golden_lines()
	var diff := 0
	for k in gold:
		if not now.has(k) or now[k] != gold[k]:
			diff += 1
			print("   differs: " + k)
	ok(gold.size() >= 52 and diff == 0, "6 default OFF: %d pose hashes (library scenes x5 times + the old limb solve) equal the base golden (%d differ)" % [gold.size(), diff])
	var k0: String = gold.keys()[0]
	var h0: String = gold[k0]
	var h1 := h0.substr(0, 5) + ("0" if h0[5] != "0" else "1") + h0.substr(6)
	ok(h1 != now[k0], "6 PLANTED: a golden hash with one digit changed differs from the real one")
	# 4 STRETCHY LIMB
	var B := body()
	var sh: Vector3 = B.P["upperarm_l"]
	var reach: float = (B.p0["lowerarm_l"] - B.p0["upperarm_l"]).length() + (B.p0["hand_l"] - B.p0["lowerarm_l"]).length()
	var dir := Vector3(0.3, -0.5, 0.4).normalized()
	var tgt: Vector3 = sh + dir * reach * 1.2
	var r4 := LimbIK.solve(B, "hand_l", tgt, tgt + Vector3(0, 0, 1), null, 1.5, false)
	var miss_on := (B.P["hand_l"] as Vector3).distance_to(tgt)
	var el: Vector3 = B.P["lowerarm_l"]
	var off_line := (el - sh - dir * (el - sh).dot(dir)).length()
	ok(miss_on < 0.001, "4 stretch on, target 1.2x reach: hand %.4f mm off (reported miss %.4f mm), scales %s" % [miss_on * 1000.0, float(r4["miss"]) * 1000.0, str(B.stretch)])
	ok(off_line < 0.002, "4 the elbow lies on the shoulder-target line (%.3f mm): a straight stretched arm" % (off_line * 1000.0))
	var B2 := body()
	var r4b := LimbIK.solve(B2, "hand_l", tgt, tgt + Vector3(0, 0, 1))
	var miss_off := (B2.P["hand_l"] as Vector3).distance_to(tgt)
	ok(absf(miss_off - 0.2 * reach) < 0.01 and B2.stretch.is_empty() and limb_hash(B2, r4b) == gold["limb_1.2"], "4 stretch off: stops at full reach (short by %.1f cm of the 20 %%) and equals the old solver's golden" % (miss_off * 100.0))
	ok(miss_off > 0.05, "4 PLANTED: the same target with stretch off misses by > 5 cm (%.1f cm), so the 1 mm bar can fail" % (miss_off * 100.0))
	var B3 := body()
	var tin: Vector3 = sh + dir * reach * 0.8
	var r3c := LimbIK.solve(B3, "hand_l", tin, tin + Vector3(0, 0, 1), null, 1.5, false)
	ok(B3.stretch.is_empty() and limb_hash(B3, r3c) == gold["limb_0.8"], "4 stretch on but the target in reach: nothing stretches, bytes equal the old solver's golden")
	# 5 VOLUME (limb)
	var B5 := body()
	LimbIK.solve(B5, "hand_l", tgt, tgt + Vector3(0, 0, 1), null, 1.5, true)
	var s_ok := not B5.stretch.is_empty()
	for j in B5.stretch:
		var pr: float = float(B5.stretch[j]) * float(B5.stretch_cross[j]) * float(B5.stretch_cross[j])
		s_ok = s_ok and absf(pr - 1.0) <= 0.01 and float(B5.stretch[j]) > 1.0
	ok(s_ok, "5 limb volume on: scale product 1 for %s (stretch %s)" % [str(B5.stretch_cross.keys()), str(B5.stretch)])
	ok(B.stretch_cross.is_empty(), "5 PLANTED: volume off keeps the cross scales empty, so the product check has nothing to pass on")
	# 8 SAVE / LOAD / UNDO (the app)
	await _app_part()
	print("splineik: %d fail" % fails)
	quit(1 if fails > 0 else 0)


func steps(f: Callable) -> int:
	var n0: int = m.undo.size()
	f.call()
	return m.undo.size() - n0


func key(k: Key, ctrl := false) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.pressed = true
	e.ctrl_pressed = ctrl
	m._unhandled_input(e)


func _app_part() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	m._load_scene("res://scenes/combo3.json")
	await idle(3)
	var B: Body = m.B
	for j in B.ang.keys():
		B.ang[j] = Vector3.ZERO
	B.fk()
	m._refresh()
	await idle(2)
	m._turn_to(0.0, -5.0, 3.2, Vector3(0, 1.0, 0), false)
	var bare: Dictionary = m._scene_dict()
	ok(not bare.has("spline_chains"), "8 a scene with no chain has no spline_chains key")
	m._bone_ui().start()
	m.bed.pick("hand_r")
	var b1: String = m.bed.extrude()
	m.bed.extrude()
	m.bed.extrude()
	m.bed.extrude()
	var nb: int = m.S.bones.size()
	var s1 := steps(func(): m._spline_make(b1))
	ok(nb == 4 and s1 == 1 and m.S.spline_chains.size() == 1 and (m.S.spline_chains[0]["bones"] as Array).size() == 4, "8 spline IK on a 4-bone chain: %d step, %d chain" % [s1, m.S.spline_chains.size()])
	var h1: Vector3 = (m.S.spline_chains[0]["ctrl"] as Array)[2]
	var s2 := steps(func(): m._spline_handle(0, 2, h1 + Vector3(0.15, 0.12, 0.0)))
	var h2: Vector3 = (m.S.spline_chains[0]["ctrl"] as Array)[2]
	ok(s2 == 1 and h2.distance_to(h1 + Vector3(0.15, 0.12, 0.0)) < 1e-4, "8 moving a handle is one step (moved %.1f cm)" % (h2.distance_to(h1) * 100.0))
	var s3 := steps(func(): m._spline_set(0, "mode", "stretch"))
	ok(s3 == 1 and m.S.spline_chains[0]["mode"] == "stretch", "8 stretch to fit is one step")
	m._refresh()
	await idle(2)
	var ch: Dictionary = m.S.spline_chains[0]
	var pz: Dictionary = SplineChain.pose(m.B, m.S.bones, ch)
	var worst := 0.0
	var any := false
	for n in ch["bones"]:
		var nd: Node3D = m.bed.nodes.get(n)
		if nd != null:
			any = true
			worst = maxf(worst, nd.transform.origin.distance_to((pz[n] as Transform3D).origin))
	ok(any and worst < 0.001, "8 the drawn bones sit on the solved joints (worst %.3f mm)" % (worst * 1000.0))
	var tipb: String = (ch["bones"] as Array)[3]
	var cs: Array = ch["ctrl"]
	var end_pt: Vector3 = (pz[tipb] as Transform3D).origin + (pz[tipb] as Transform3D).basis.y * BoneEdit.length(m.B, m.S.bones, tipb)
	ok(end_pt.distance_to(cs[cs.size() - 1]) < 0.002, "8 stretch mode: the last bone's tail reaches the last handle (%.2f mm)" % (end_pt.distance_to(cs[cs.size() - 1]) * 1000.0))
	var path := "user://splineik_tmp.json"
	var d1: Dictionary = m._scene_dict()
	m._write(path, d1)
	var errs := Validate.file(path)
	ok(d1.has("spline_chains") and int(d1["spline_chains"]["v"]) == 1 and errs.is_empty(), "8 the file has spline_chains v1 and validates %s" % str(errs))
	var txt1 := FileAccess.get_file_as_string(path)
	m._load_scene(path)
	await idle(2)
	var path2 := "user://splineik_tmp2.json"
	m._write(path2, m._scene_dict())
	var txt2 := FileAccess.get_file_as_string(path2)
	ok(txt1 == txt2 and txt1.length() > 100, "8 save -> load -> save is byte-identical (%d bytes)" % txt1.length())
	var bad := txt1.replace("\"stretch\"", "\"keep\"")
	ok(bad != txt1 and bad != txt2, "8 PLANTED: a changed word in the file is not byte-identical")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path2))
	var before := var_to_str(m.S.spline_chains)
	var u1 := steps(func(): m._spline_handle(0, 1, (m.S.spline_chains[0]["ctrl"] as Array)[1] + Vector3(0.05, 0, 0.05)))
	var u2 := steps(func(): m._spline_set(0, "volume", true))
	var u3 := steps(func(): m._spline_off(0))
	ok(u1 == 1 and u2 == 1 and u3 == 1 and m.S.spline_chains.is_empty(), "8 three more edits, one step each; off removes the chain")
	key(KEY_Z, true)
	key(KEY_Z, true)
	key(KEY_Z, true)
	await idle(2)
	ok(var_to_str(m.S.spline_chains) == before, "8 Ctrl+Z x3 gives the chain list back exactly (var_to_str equal)")
