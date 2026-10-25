## godot --headless --path . -s tests/carry_form_test.gd     (GATES UU5; headless is fine)
## CARRY FORM, against real people. The REFERENCE carry (Anderson et al. 2007; Snook 1978; NIOSH): upper arms hanging
## at the sides, elbows bent 90 deg, forearms along the box's sides, the box against the belly at elbow height. Built
## on the body, picked up in both hands and walked 50 cm: its numbers are printed beside the bars, Check says nothing
## about the carry and nothing goes through the box. The pose of round 39's first screenshot (hands reached out at
## chest height, arms nearly straight) carried the same way: WARN CARRY FORM naming the upper arms.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func body() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	return B


func hands_mid(B: Body) -> Vector3:
	return ((B.cap("hand_l")[0] as Vector3) + (B.cap("hand_l")[1] as Vector3) + (B.cap("hand_r")[0] as Vector3) + (B.cap("hand_r")[1] as Vector3)) / 4.0


## a scene: B holds a box (between its hands, its bottom 10 cm under them, pushed forward until nothing but the
## holding arms touches it) on card 1 and walks 50 cm forward on card 2
func carry(B: Body) -> Scene:
	B.ground()
	var hm := hands_mid(B)
	var box := Props.make("box", Props.xf_at(Vector3(hm.x, hm.y - 0.10, hm.z), 0.0))
	for k in 40:
		var hit := Rulebook.prop_hits([box], B, {0: ["hand_l", "hand_r", "lowerarm_l", "lowerarm_r"]})
		if hit.is_empty():
			break
		var xf: Transform3D = box["xf"]
		xf.origin.z += 0.01
		box["xf"] = xf
	var S := Scene.new()
	S.name = "zz_carry_form"
	S.props = [box]
	S.add("take", B.to_dict())
	B.offset.z += 0.5
	B.fk()
	S.add("walk", B.to_dict())
	S.cards[0]["take"] = {"prop": 0, "hands": ["_l", "_r"]}
	return S


func _init() -> void:
	# the reference carry
	var B := body()
	for sd in ["_l", "_r"]:
		B.set_ang("upperarm" + sd, Vector3(0, -80, 0))
		B.set_ang("lowerarm" + sd, Vector3(90, 0, 0))
	B.fk()
	var D := body()   # this body's own knuckle and elbow heights: arms hanging straight, standing on the floor
	for sd in ["_l", "_r"]:
		D.set_ang("upperarm" + sd, Vector3(0, -80, 0))
	D.fk()
	D.ground()
	var knuckle: float = (D.E["hand_l"] as Vector3).y
	var elbow: float = (D.P["lowerarm_l"] as Vector3).y
	var S := carry(B)
	var M := body()
	S.apply(M, S.times()[1][1])
	var cf := Rulebook.carry_form(S, S.times()[1][1], M)
	if cf.is_empty():
		ok(false, "the reference carry is measured at all (carry_form returned nothing)")
		print("CARRY FORM TEST FAIL %d" % fails)
		TestFiles.cleanup()
		quit(fails)
		return
	var box: Transform3D = S.props[0]["xf"]
	var ankles := ((M.P["foot_l"] as Vector3) + (M.P["foot_r"] as Vector3)) / 2.0
	print("REFERENCE vs OURS: upper arms from hanging: people ~0-20 deg, bar %.0f -> ours %.1f | elbows: people ~90, bar %s -> ours %.1f / %.1f | hands in front of the ankles: NIOSH 25 cm ideal, bar %.0f -> ours %.1f cm | box bottom: people between knuckle and elbow height (this body: %.2f-%.2f m) -> ours %.2f m" % [
		Rulebook.CARRY_UP, cf["up"], Rulebook.CARRY_FLEX, cf["flex"][0], cf["flex"][1], Rulebook.CARRY_H * 100.0, float(cf["h"]) * 100.0, knuckle, elbow, box.origin.y])
	ok(float(cf["up"]) < 20.0 and absf(float(cf["flex"][0]) - 90.0) < 10.0 and float(cf["h"]) < 0.35 and box.origin.y > knuckle - 0.03 and box.origin.y < elbow + 0.03,
		"the reference carry measures as people carry (arms down, elbows ~90, hands close, box at knuckle-to-elbow height)")
	var fs := Rulebook.check(S, body())
	ok(fs.filter(func(f): return f["rule"] == "CARRY FORM").is_empty(), "  Check: no CARRY FORM on it")
	var thr := fs.filter(func(f): return f["rule"] == "THROUGH A PROP")
	ok(thr.is_empty(), "  nothing through the box %s" % [thr.map(func(f): return String(f["msg"]).left(80))])
	# round 39's first screenshot: hands reached out to a box at chest height
	B = body()
	var c := Vector3(0.0, 1.1, 0.38)
	B.reach("hand_l", c + Vector3(0.22, 0, 0))
	B.reach("hand_r", c + Vector3(-0.22, 0, 0))
	B.fk()
	S = carry(B)
	S.apply(M, S.times()[1][1])
	var bad := Rulebook.carry_form(S, S.times()[1][1], M)
	fs = Rulebook.check(S, body())
	var w := fs.filter(func(f): return f["rule"] == "CARRY FORM")
	print("THE OLD SCREENSHOT POSE: upper arms %.1f deg, elbows %.1f / %.1f, hands %.1f cm in front" % [bad["up"], bad["flex"][0], bad["flex"][1], float(bad["h"]) * 100.0])
	ok(w.size() == 1 and w[0]["sev"] == "WARN" and String(w[0]["msg"]).contains("the upper arms are 52° out"), "the old screenshot's carry: WARN CARRY FORM ('%s')" % (String(w[0]["msg"]).left(150) if not w.is_empty() else "-"))
	# one hand: not this rule's business (a bag, a bucket hang on a straight arm)
	S.cards[0]["take"] = {"prop": 0, "hands": ["_r"]}
	ok(Rulebook.check(S, body()).filter(func(f): return f["rule"] == "CARRY FORM").is_empty(), "the same held in one hand: not graded by CARRY FORM")
	print("CARRY FORM TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
