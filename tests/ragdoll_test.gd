## godot --headless --path . -s tests/ragdoll_test.gd     (round 53, ROADMAP 27: ragdoll to keys with pins; scripts/ragdoll.gd)
## Bars, written before the numbers were read:
##   1 FREE FALL: a body lifted 1 m (no contact yet): the COM falls 0.5 g t^2 within 2 % up to 0.25 s.
##   2 REST: a knockout fall from the standing pose comes to rest on the floor; at the end no part is below the floor
##     (> -5 mm) and no joint is past its limit (Body.clamp_ang, 0.01 deg).
##   3 PIN: the right hand is pinned at its start position; after the fall, in the baked pose, the hand is within 1 cm.
##   4 DETERMINISM: the same input gives bit-identical solver positions and identical baked cards.
##   5 REPLAY: the baked cards, played back by Scene.apply, reproduce the solver's joint angles within 2 deg at each card.
##   6 SCREENSHOT: the body at rest after a knockout fall in the app (cards set on the open scene in memory, nothing written).
extends SceneTree

const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/ragdoll.png"

var fails := 0

func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1

func fresh_body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	b.ground()
	return b

func _init() -> void:
	# 1 FREE FALL: the standing body, lifted 1 m
	var b1 := fresh_body()
	b1.offset.y += 1.0
	b1.fk()
	var r1 := Ragdoll.new()
	r1.setup(b1, [])
	r1.run(0.25)
	var k := int(round(0.25 * Ragdoll.HZ))
	var c0: Vector3 = r1.com[0]
	var ck: Vector3 = r1.com[k]
	var t := float(k) * Ragdoll.DT
	var fall := c0.y - ck.y
	var want := 0.5 * 9.81 * t * t
	var err := absf(fall - want) / want
	print("free fall: %.4f m in %.3f s, 0.5 g t^2 = %.4f m, error %.2f %%, first contact %.3f s" % [fall, t, want, err * 100.0, r1.t_contact])
	ok(err < 0.02 and (r1.t_contact < 0.0 or r1.t_contact > 0.25), "free fall of the COM matches 0.5 g t^2 within 2 %% before first contact (%.2f %%)" % (err * 100.0))

	# 2 REST: the standing body goes limp and falls
	var b2 := fresh_body()
	var r2 := Ragdoll.new()
	r2.setup(b2, [])
	r2.run(4.0)
	var keep2 := b2.ang.duplicate()
	var cards2 := r2.bake(keep2, Ragdoll.CARD_FPS)
	var last := r2.rec_A.size() - 1
	print("knockout: %d substeps (%.2f s), contact at %.3f s, at rest at %.3f s, %d cards" % [last, float(last) * Ragdoll.DT, r2.t_contact, r2.t_rest, cards2.size()])
	ok(r2.t_rest > 0.0, "the body comes to rest on the floor within 4 s")
	# the final pose (the last card) read back through fk
	var lowest := INF
	var worst_lim := 0.0
	var lo_name := ""
	var fb := b2
	var lastpose: Dictionary = cards2[-1]["pose"]
	fb.from_dict(lastpose)
	fb.fk()
	for j in Body.ORDER:
		if j.begins_with("thumb") or j.begins_with("index") or j.begins_with("middle") or j.begins_with("ring") or j.begins_with("pinky"):
			continue
		if not fb.rad.has(j):
			continue
		var rj: float = float(fb.rad[j])
		var lowj := minf((fb.P[j] as Vector3).y, (fb.E[j] as Vector3).y) - rj
		if lowj < lowest:
			lowest = lowj
			lo_name = j
	ok(lowest > -0.005, "no part below the floor at rest (lowest %s at %.1f mm)" % [lo_name, lowest * 1000.0])
	for j in Ragdoll.NAMES:
		if not Ragdoll.is_sim(j):
			continue
		var a: Vector3 = fb.ang[j]
		var cl: Vector3 = fb.clamp_ang(j, a)
		var over := (cl - a).length()
		worst_lim = maxf(worst_lim, over)
	ok(worst_lim < 0.01, "no simulated joint past its limit at rest (worst %.4f deg)" % worst_lim)

	# 3 PIN: the right hand pinned at its start, falling from the standing body
	var b3 := fresh_body()
	var r3 := Ragdoll.new()
	r3.setup(b3, ["hand_r"])
	var pin0: Vector3 = r3.pins[r3.nm.find("hand_r")]   # the held position (after setup's lift)
	r3.run(4.0)
	var cards3 := r3.bake(b3.ang.duplicate(), Ragdoll.CARD_FPS)
	fb.from_dict(cards3[-1]["pose"])
	fb.fk()
	var hand_err: float = (fb.P["hand_r"] as Vector3).distance_to(pin0)
	print("pinned hand: %.2f mm from its pin after the fall (contact %.3f s, rest %.3f s)" % [hand_err * 1000.0, r3.t_contact, r3.t_rest])
	ok(hand_err < 0.01, "the pinned hand stays within 1 cm of its pin (%.2f mm)" % (hand_err * 1000.0))

	# 4 DETERMINISM: a second run from the same input
	var b4 := fresh_body()
	var r4 := Ragdoll.new()
	r4.setup(b4, [])
	r4.run(4.0)
	var same_pos := r4.rec_X.size() == r2.rec_X.size()
	var same_cards := true
	if same_pos:
		for s in r2.rec_X.size():
			if r2.rec_X[s] != r4.rec_X[s]:
				same_pos = false
				break
	var cards4 := r4.bake(b4.ang.duplicate(), Ragdoll.CARD_FPS)
	same_cards = JSON.stringify(cards2) == JSON.stringify(cards4)
	ok(same_pos, "same input, bit-identical solver positions (%d substeps)" % r4.rec_X.size())
	ok(same_cards, "same input, identical baked cards (%d cards)" % cards4.size())

	# 5 REPLAY: the cards played back reproduce the solver's angles within 2 deg
	var S := Scene.new()
	S.from_dict({"scene": "zz_ragdoll_test", "fps": Ragdoll.CARD_FPS, "cards": cards2})
	S.on_floor = false   # the solver is the floor and the feet: playback must not re-ground or re-plant them
	S.pin = false
	var bp := fresh_body()
	var worst_deg := 0.0
	var ts := S.times()
	var stride := int(round(float(Ragdoll.HZ) / float(Ragdoll.CARD_FPS)))
	for c in cards2.size():
		var tc: float = ts[c][1]
		S.apply(bp, tc)
		var want_ang: Dictionary = r2.angles_at(c * stride if c < cards2.size() - 1 else r2.rec_A.size() - 1)
		for j in want_ang:
			var d: float = ((bp.ang[j] as Vector3) - (want_ang[j] as Vector3)).length()
			worst_deg = maxf(worst_deg, d)
	print("replay: worst joint angle difference %.3f deg over %d cards" % [worst_deg, cards2.size()])
	ok(worst_deg <= 2.0, "the baked cards replay the solver's angles within 2 deg (%.3f)" % worst_deg)

	print("rest threshold %.4f m/s (g*DT), for %.1f s; floor friction MU %.2f + KF %.2f, joint damping KD %.2f per substep" % [Ragdoll.REST_V, Ragdoll.REST_S, Ragdoll.MU, Ragdoll.KF, Ragdoll.KD])

	# 6 SCREENSHOT: the app, the body at rest after the fall
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 4:
		await process_frame
	m._load_scene("res://scenes/combo3.json")   # read only
	m._rebuild_cards()
	m.B.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	m.B.ground()
	var rs := Ragdoll.new()
	rs.setup(m.B, [])
	rs.run(4.0)
	m.S.cards = rs.bake(m.B.ang.duplicate(), Ragdoll.CARD_FPS)
	m.S.on_floor = false
	m.S.pin = false
	m._rebuild_cards()
	m.playhead = float(m.S.times()[-1][1])
	m._ps().apply(m.B, m.playhead)
	m.dummy_on = false
	m.yaw = 90.0   # from the body's side: it lies along z
	m.pitch = -20.0
	m.dist = 3.2
	m.target = (m.B.P["pelvis"] as Vector3) + (m.B.P["head"] as Vector3 - m.B.P["pelvis"]) * 0.5
	m._refresh()
	m._cam()
	for i in 6:
		await process_frame
	DirAccess.make_dir_recursive_absolute(SHOT.get_base_dir())
	# under --headless the dummy renderer has no viewport texture: skip the screenshot, do not fail
	var tex: Texture2D = m.get_viewport().get_texture()
	if tex == null or tex.get_image() == null:
		print("screenshot skipped (headless)")
	else:
		var e: int = tex.get_image().save_png(SHOT)
		ok(e == OK, "screenshot of the body at rest saved (%s)" % SHOT)

	print("ragdoll: %d FAIL" % fails)
	quit(1 if fails > 0 else 0)
