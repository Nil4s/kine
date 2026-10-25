## godot --headless --path . -s tests/prop_check_test.gd     (GATES TT1, TT4; headless is fine)
## THE SET IN CHECK. A right arm swings up through a pillar standing in its path: Check FAILs THROUGH A PROP naming
## the part, the pillar and the cm. The pillar moved 2 m away: nothing. Feet standing ON a box: nothing (resting).
## No props: sample() has no set keys and Check finds nothing about props. FLOATS: a seated body held 6 cm over a
## chair with its feet off the ground -> a WARN with the cm; the same body resting on the seat -> nothing.
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


func of(fs: Array, rule: String) -> Array:
	return fs.filter(func(f): return f["rule"] == rule)


func _init() -> void:
	Props.register("zz pillar", AABB(Vector3(-0.15, 0, -0.15), Vector3(0.3, 2.0, 0.3)), "", 1.0)
	# an arm swinging forward and up: card a at rest, card b with the right upper arm raised in front
	var B := body()
	var S := Scene.new()
	S.name = "zz_prop_check"
	S.add("a", B.to_dict())
	B.set_ang("upperarm_r", Vector3(-80, 0, 0))
	B.fk()
	var front: Vector3 = B.P["hand_r"]
	B.set_ang("upperarm_r", Vector3(0, 0, 0))
	B.fk()
	var down: Vector3 = B.P["hand_r"]
	B.set_ang("upperarm_r", Vector3(-80, 0, 0))
	B.fk()
	S.add("b", B.to_dict())
	ok(front.distance_to(down) > 0.3, "the fixture swings the right hand %.2f m (from %s to %s)" % [front.distance_to(down), down, front])
	var mid := (front + down) / 2.0
	var pillar := Props.make("zz pillar", Props.xf_at(Vector3(mid.x, 0, mid.z), 0.0))
	S.props = [pillar]
	var fs := Rulebook.check(S, body())
	var th := of(fs, "THROUGH A PROP")
	var fl := th.filter(func(f): return f["sev"] == "FAIL")
	ok(not fl.is_empty() and fl.any(func(f): return String(f["msg"]).contains("right") and String(f["msg"]).contains("zz pillar") and String(f["msg"]).contains(" cm into")),
		"the arm through a pillar: Check FAILs THROUGH A PROP (%d findings; '%s')" % [th.size(), String(th[0]["msg"]).left(90) if not th.is_empty() else "-"])
	ok(not th.is_empty() and th.all(func(f): return f.has("t1") and f["card"] >= 0), "  each with its time span and card")
	S.props = [Props.make("zz pillar", Props.xf_at(Vector3(mid.x + 2.0, 0, mid.z), 0.0))]
	ok(of(Rulebook.check(S, body()), "THROUGH A PROP").is_empty(), "the pillar moved 2 m away: nothing")
	S.props = []
	var sm := Rulebook.sample(S, body())
	ok(not sm.has("prop_hits") and not sm.has("seat_gap") and of(Rulebook.check(S, body(), sm), "THROUGH A PROP").is_empty(), "no props: sample() has no set keys, Check says nothing about props")
	# standing on a box: resting, not through
	B = body()
	var m2 := ((B.P["ball_l"] as Vector3) + (B.P["ball_r"] as Vector3) + (B.P["foot_l"] as Vector3) + (B.P["foot_r"] as Vector3)) / 4.0
	var S2 := Scene.new()
	S2.name = "zz_prop_check"
	S2.props = [Props.make("box", Props.xf_at(Vector3(m2.x, 0, m2.z), 0.0))]
	S2.add("a", B.to_dict())
	B.set_ang("upperarm_l", Vector3(-40, 0, 0))
	B.fk()
	S2.add("b", B.to_dict())
	var f2 := Rulebook.check(S2, body())
	ok(of(f2, "THROUGH A PROP").is_empty(), "feet standing ON a box: resting, no THROUGH A PROP (%d findings in all)" % f2.size())
	# FLOATS: a seated body over a chair, feet off the ground (on_floor off: the card is where it is)
	for gap in [0.06, 0.0]:
		B = body()
		for sd in ["_l", "_r"]:
			B.set_ang("thigh" + sd, Vector3(90, 0, 0))
			B.set_ang("calf" + sd, Vector3(90, 0, 0))
		B.fk()
		var c := B.cap("hips_wide")
		var lo := minf((c[0] as Vector3).y, (c[1] as Vector3).y) - float(B.rad["hips_wide"])
		B.offset.y += 0.45 + gap - lo
		B.fk()
		var S3 := Scene.new()
		S3.name = "zz_prop_check"
		S3.on_floor = false
		S3.props = [Props.make("chair", Props.xf_at(Vector3(0, 0, 0.03), 0.0))]
		S3.add("a", B.to_dict())
		S3.add("b", B.to_dict())
		var f3 := Rulebook.check(S3, body())
		var w := of(f3, "FLOATS")
		if gap > 0.0:
			ok(w.size() == 1 and w[0]["sev"] == "WARN" and absf(float(w[0]["v"]) - 0.06) < 0.005 and String(w[0]["msg"]).contains("6.0 cm"),
				"hips 6 cm over the chair, feet off the ground: WARN FLOATS ('%s')" % (String(w[0]["msg"]).left(80) if not w.is_empty() else "-"))
		else:
			ok(w.is_empty() and of(f3, "THROUGH A PROP").is_empty(), "the same body resting on the seat: no FLOATS, nothing through the chair")
	print("PROP CHECK TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
