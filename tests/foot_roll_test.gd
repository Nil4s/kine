## godot --headless --path . -s tests/foot_roll_test.gd     (GATES XX5; headless is fine)
## FOOT ROLL (round 42, UPGRADES #270). One value per foot, in degrees: < 0 rocks on the heel, 0 .. 55 rolls on the ball
## (heel up, toes flat, the toe joint extends by the roll), > 55 goes up onto the toe tip. The pivot point stays put.
## REAL PEOPLE (abstracts read on PubMed 2026-10-17; the lecture PDF read in full):
##  - ankle at heel strike: NEUTRAL (Guthrie, "Review of normal and pathologic gait", UW CME 2015,
##    https://uw.cloud-cme.com/assets/uw/Presentations/1140/Mon_845_Guthrie.pdf : "neutral position (90 degrees) at heel strike")
##  - ankle plantarflexion at push-off: -5 to -20 deg, commonly 15-20 (secondary: patent texts, e.g.
##    https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/9572395 ; UNVERIFIED in a primary gait paper: I
##    could not open one, so the bar is the brief's 15-20)
##  - first MTP extension in walking: 44 +- 5 deg in healthy controls (Miana et al 2021, J Foot Ankle Surg,
##    PMID 34649787, doi 10.1053/j.jfas.2021.09.016) and about 65 deg required for normal walking (Hopson, McPoil &
##    Cornwall 1995, J Am Podiatr Med Assoc, PMID 7738816, doi 10.7547/87507315-85-4-198). Bar: 39 .. 65.
## The skeleton has a toe joint (ball_l / ball_r), so the toe extends.
extends SceneTree

var fails := 0
var nok := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if c:
		nok += 1
	else:
		fails += 1


func body(th: float, ca: float) -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	for sd in ["_l", "_r"]:
		B.set_ang("thigh" + sd, Vector3(th, 0, 0))
		B.set_ang("calf" + sd, Vector3(ca, 0, 0))
		B.flat_foot(sd)
	B.fk()
	B.ground()
	return B


## the foot's lowest sole point above its rest height (heel, toe joint, toe tip)
func low(B: Body, sd: String) -> float:
	return minf(FootRoll.heel_point(B, sd).y, minf((B.P["ball" + sd] as Vector3).y - (B.p0["ball" + sd] as Vector3).y,
		(B.E["ball" + sd] as Vector3).y - (B.e0["ball" + sd] as Vector3).y))


func _init() -> void:
	# the sign: a + ankle bend lifts the toe joint (toes up), as body_limits.json says
	var B0 := body(0, 0)
	var y0: float = B0.P["ball_l"].y
	B0.set_ang("foot_l", Vector3(10, 0, 0))
	ok(B0.P["ball_l"].y > y0, "+ ankle bend lifts the toe joint (%.4f -> %.4f)" % [y0, B0.P["ball_l"].y])
	# roll 0: bit for bit
	var B1 := body(10, 25)
	var a0: Dictionary = B1.ang.duplicate(true)
	var p0: Dictionary = B1.P.duplicate(true)
	var r0 := FootRoll.apply(B1, "_l", 0.0)
	B1.fk()
	ok(r0.is_empty() and a0.hash() == B1.ang.hash() and p0.hash() == B1.P.hash(), "roll 0 leaves every angle and joint position bit for bit")
	# the pivot holds across the range (trailing leg: thigh forward 10, knee 25: the shank leans 15 deg forward, room left at the ankle)
	var worst := 0.0
	var worst_at := 0.0
	var below := 0.0
	var rolls := [-20.0, -15.0, -10.0, -5.0, 5.0, 10.0, 20.0, 30.0, 40.0, 50.0, 55.0, 60.0, 65.0, 70.0, 80.0]
	for sd in ["_l", "_r"]:
		for r in rolls:
			var B := body(10, 25)
			var rest := low(B, sd)
			var d := FootRoll.apply(B, sd, r)
			if float(d["err"]) > worst:
				worst = d["err"]
				worst_at = r
			below = minf(below, low(B, sd) - rest)
	print("PIVOT: worst drift %.3f mm at roll %.0f over %d rolls x 2 feet (bar 1 mm); lowest sole point vs before %.3f mm (bar >= -1)" % [worst * 1000.0, worst_at, rolls.size(), below * 1000.0])
	ok(worst < 0.001, "the pivot (heel / ball / toe tip) stays within 1 mm")
	ok(below > -0.001, "no part of the foot sinks below where the sole stood")
	# the three pivots are the ones named
	var Bh := body(25, 5)
	var Bb := body(10, 25)
	var Bt := body(10, 25)
	var h0 := FootRoll.heel_point(Bh, "_l")
	FootRoll.apply(Bh, "_l", -12.0)
	ok(FootRoll.heel_point(Bh, "_l").distance_to(h0) < 0.001 and (Bh.P["ball_l"] as Vector3).y > (Bb.P["ball_l"] as Vector3).y + 0.02, "roll -12: heel fixed, toes lifted %.1f cm" % (((Bh.P["ball_l"] as Vector3).y - (Bb.P["ball_l"] as Vector3).y) * 100.0))
	var b0: Vector3 = Bb.P["ball_l"]
	var d1 := FootRoll.apply(Bb, "_l", 30.0)
	ok((Bb.P["ball_l"] as Vector3).distance_to(b0) < 0.001 and (Bb.P["foot_l"] as Vector3).y > B1.P["foot_l"].y + 0.03 and absf(float(d1["toe"]) - 30.0) < 1.0,
		"roll 30: toe joint fixed, ankle up %.1f cm, toe extension %.1f deg (= the roll, toes flat)" % [((Bb.P["foot_l"] as Vector3).y - (B1.P["foot_l"] as Vector3).y) * 100.0, d1["toe"]])
	var t0: Vector3 = Bt.E["ball_l"]
	var d2 := FootRoll.apply(Bt, "_l", 62.0)
	ok((Bt.E["ball_l"] as Vector3).distance_to(t0) < 0.001 and float(d2["toe"]) > 45.0 and float(d2["toe"]) < 56.0,
		"roll 62: toe tip fixed, toe extension stops at the break (%.1f deg, break %.0f)" % [d2["toe"], FootRoll.BREAK])
	# HEEL STRIKE: leading leg (thigh forward 25, knee 5): the roll that brings the ankle to neutral
	var hs_r := 0.0
	var hs_a := 999.0
	var hs_err := 0.0
	var r := -0.5
	while r >= -30.0:
		var B := body(25, 5)
		var d := FootRoll.apply(B, "_l", r)
		if absf(float(d["ankle"])) < absf(hs_a):
			hs_a = d["ankle"]
			hs_r = r
			hs_err = d["err"]
		r -= 0.5
	print("HEAL STRIKE: REFERENCE ankle neutral (0 deg; Guthrie 2015) | OURS roll %.1f -> ankle %.2f deg, pivot drift %.3f mm" % [hs_r, hs_a, hs_err * 1000.0])
	ok(absf(hs_a) <= 2.0, "heel strike: the ankle reaches neutral (%.2f deg, bar +-2) at a rocked-back roll (%.1f)" % [hs_a, hs_r])
	ok(hs_r < -1.0 and hs_err < 0.001, "  with the roll a real heel rock-back (< -1) and the heel held (%.3f mm)" % (hs_err * 1000.0))
	# PUSH-OFF: trailing leg, shank leaning forward: the roll that gives 17.5 deg of plantarflexion (middle of 15-20)
	var po_r := 0.0
	var po_a := 999.0
	var po_t := 0.0
	var po_err := 0.0
	r = 5.0
	while r <= 80.0:
		var B := body(10, 25)
		var d := FootRoll.apply(B, "_l", r)
		if absf(float(d["ankle"]) + 17.5) < absf(po_a + 17.5):
			po_a = d["ankle"]
			po_r = r
			po_t = d["toe"]
			po_err = d["err"]
		r += 0.5
	print("PUSH-OFF: REFERENCE ankle -15..-20 plantarflexion (patents, UNVERIFIED primary), MTP 44 +- 5 (Miana 2021) / ~65 needed (Hopson 1995) | OURS roll %.1f -> ankle %.2f deg, toe %.2f deg, pivot drift %.3f mm" % [po_r, po_a, po_t, po_err * 1000.0])
	ok(po_a <= -15.0 and po_a >= -20.0, "push-off: the ankle plantarflexes %.2f deg (bar -15 .. -20)" % po_a)
	ok(po_t >= 39.0 and po_t <= 65.0, "push-off: the toe extends %.2f deg (bar 39 .. 65, Miana 44 +- 5 to Hopson 65)" % po_t)
	ok(po_err < 0.001, "  with the toe (ball) held (%.3f mm)" % (po_err * 1000.0))
	# mirror: the same roll on _l and on _r gives the same joint angles
	var Ba := body(10, 25)
	var Bm := body(10, 25)
	var da := FootRoll.apply(Ba, "_l", 35.0)
	var dm := FootRoll.apply(Bm, "_r", 35.0)
	print("MIRROR: left ankle %.3f toe %.3f | right ankle %.3f toe %.3f" % [da["ankle"], da["toe"], dm["ankle"], dm["toe"]])
	ok(absf(float(da["ankle"]) - float(dm["ankle"])) < 0.01 and absf(float(da["toe"]) - float(dm["toe"])) < 0.01, "left and right roll the same")
	print("FOOT ROLL TEST %s %d (ok %d)" % ["PASS" if fails == 0 else "FAIL", fails, nok])
	TestFiles.cleanup()
	quit(fails)
