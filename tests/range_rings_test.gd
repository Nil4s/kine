## godot --headless --path . -s tests/range_rings_test.gd     (ROADMAP 38: scripts/range_rings.gd, the distance-to-opponent rings)
## Two fighters, both the mannequin in rest pose; the picked one at the origin, the other moved along +x until its nearest
## body part is at a known floor distance d. Bars, written before measuring:
##   1 RADII: the arm ring equals upper arm + forearm + hand, the weapon ring equals arm + wep_len (the bat held, 0.84 m),
##     and the step-in ring equals the weapon reach + 0.4 x the body height, each within 1 cm of the same sum taken here
##     straight from the joints (this test's own sums, not RangeRings' code path).
##   2 GAP: the report's nearest-part gap equals this test's own sampled gap (capsule points, 20 per part) within 1 cm.
##   3 FLAGS: at 5 distances (arm -0.03, arm +0.03, weapon -0.03, weapon +0.03, step-in -0.03 m) each ring's inside flag
##     is right: 15 of 15 (a ring is inside when the nearest part is at or within its radius).
##   4 LABEL: the rings' node reads "<gap> m to <name>" with the report's gap (2 decimals), and it hides with one fighter.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.fk()
	return b


## the reach from the joints themselves: each arm's three bones, averaged over the two sides
func arm_sum(B: Body) -> float:
	var t := 0.0
	for s in ["_l", "_r"]:
		t += (B.P["lowerarm" + s] as Vector3).distance_to(B.P["upperarm" + s] as Vector3)
		t += (B.P["hand" + s] as Vector3).distance_to(B.P["lowerarm" + s] as Vector3)
		t += (B.E["hand" + s] as Vector3).distance_to(B.P["hand" + s] as Vector3)
	return t * 0.5


## this test's own gap: the least horizontal distance from c to the other body's capsule points, minus each radius
func sampled_gap(c: Vector3, B: Body, W: Transform3D) -> float:
	var best := INF
	for part in Choreo.body_parts(B):
		var seg: Array = B.cap(part)
		for k in 21:
			var p: Vector3 = W * (seg[0] as Vector3).lerp(seg[1] as Vector3, float(k) / 20.0)
			var d := Vector2(p.x - c.x, p.z - c.z).length() - float(B.rad[part])
			best = minf(best, d)
	return best


func _init() -> void:
	var P1 := body()
	var P2 := body()
	P1.wep_on = true   # the bat held: its length is what the weapon ring adds (wep_len, 0.84 m default)
	var ctr := (P1.P["upperarm_l"] as Vector3).lerp(P1.P["upperarm_r"] as Vector3, 0.5)
	ctr.y = 0.0
	var arm := arm_sum(P1)
	var weapon := arm + P1.wep_len
	var h := RangeRings.height_of(P1)
	var step_in := weapon + 0.4 * h

	# 1 RADII
	var R := RangeRings.reaches(P1)
	ok(absf(float(R["arm"]) - arm) < 0.01, "1a arm ring %.3f m = upper arm + forearm + hand %.3f m (within 1 cm)" % [float(R["arm"]), arm])
	ok(absf(float(R["weapon"]) - weapon) < 0.01, "1b weapon ring %.3f m = arm + bat %.2f m = %.3f m (within 1 cm)" % [float(R["weapon"]), P1.wep_len, weapon])
	ok(absf(float(R["step_in"]) - step_in) < 0.01, "1c step-in ring %.3f m = weapon + 0.4 x %.3f m height = %.3f m (within 1 cm)" % [float(R["step_in"]), h, step_in])

	var cases := [["arm -3 cm", arm - 0.03], ["arm +3 cm", arm + 0.03], ["weapon -3 cm", weapon - 0.03],
		["weapon +3 cm", weapon + 0.03], ["step-in -3 cm", step_in - 0.03]]
	var fl_ok := 0
	var gap_ok := 0
	for cs in cases:
		var target: float = cs[1]
		# place the other fighter: scan its x offset in 5 mm steps for the sampled gap nearest the target
		var best_dx := 0.5
		var best_err := INF
		var dx := 0.5
		while dx <= 4.5:
			var W := Transform3D(Basis(), Vector3(dx, 0, 0))
			var e := absf(sampled_gap(ctr, P2, W) - target)
			if e < best_err:
				best_err = e
				best_dx = dx
			dx += 0.005
		var WO := Transform3D(Basis(), Vector3(best_dx, 0, 0))
		var rep := RangeRings.report(P1, Transform3D.IDENTITY, [{"name": "opponent", "B": P2, "W": WO}])
		var g_here := sampled_gap(ctr, P2, WO)
		var g_rep := float(rep["near"]["gap"])
		if absf(g_rep - g_here) < 0.01:
			gap_ok += 1
		print("     %-13s target %.3f m, sampled %.3f m, report %.3f m (x offset %.3f)" % [cs[0], target, g_here, g_rep, best_dx])
		var want := [arm, weapon, step_in]
		var got: Array = rep["rings"].map(func(r): return bool(r["inside"]))
		var expect := [target <= want[0] + 0.0, target <= want[1], target <= want[2]]
		var row_ok := true
		for i in 3:
			if bool(got[i]) != bool(expect[i]):
				row_ok = false
		if row_ok:
			fl_ok += 3
		else:
			print("       flags %s, expected %s" % [got, expect])
	ok(gap_ok == cases.size(), "2 GAP: the report's gap = the sampled gap within 1 cm at %d of %d distances" % [gap_ok, cases.size()])
	ok(fl_ok == 15, "3 FLAGS: inside/outside right for arm, arm + weapon and step-in at 5 distances: %d of 15" % fl_ok)

	# 4 LABEL and hiding
	var rings := RangeRings.new()
	get_root().add_child(rings)
	rings.setup()
	rings.on = true
	var WO := Transform3D(Basis(), Vector3(arm + 0.5, 0, 0))
	rings.update(P1, Transform3D.IDENTITY, [{"name": "opponent", "B": P2, "W": WO}])
	var g := float(rings.last["near"]["gap"])
	ok(rings._label.text == "%s to opponent" % Units.len(g), "4a label reads \"%s\" (the report's gap in cm, Units.len)" % rings._label.text)
	ok(rings._mesh.visible, "4b the rings show with two fighters")
	rings.update(P1, Transform3D.IDENTITY, [])
	ok(not rings._mesh.visible and not rings._label.visible, "4c the rings and label hide with one fighter")
	rings.free()

	print("RANGE RINGS TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(1 if fails > 0 else 0)
