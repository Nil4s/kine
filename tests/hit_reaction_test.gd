## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/hit_reaction_test.gd     (round 52, ROADMAP 14; a window)
## AUTOMATIC HIT REACTIONS (scripts/hit_reaction.gd, the command "Hits: make the struck fighter react"). Bars, written
## before the numbers were read:
##   1 SPEED: a bat hit to the head from the right (contact on the head's right side, the bat moving to the left at v):
##     the head moves LEFT (+x in the body's space: the hero's left) at its peak, and the peak angular speed at 2v is
##     within 15% of 2x the peak at v (the impulse is linear in v; no joint stop may be reached, or this fails).
##   2 SHOVE: a hit to the chest: the pelvis moves along the blow at J/M within 10% over the first 1/240 s
##     (J = m_eff x v, M = the body's mass from its pieces).
##   3 LIMITS: at every 240 Hz step no reacting joint is past its limits (Body.clamp_ang).
##   4 REPLAY: the baked cards, played back by Scene.apply, reproduce the simulated joint angles within 1 deg at every
##     240 Hz step (both hits).
##   5 UNDO: the command in the app (two fighters, the hero's bat hitting fighter 2's head): ONE undo step; fighter 2's cards
##     change; Ctrl+Z puts them back exactly.
##   6 SCREENSHOT: a frame mid-reaction of that command, saved to the job's tmp folder (a window's picture).
extends SceneTree

var fails := 0
var m: Node
const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/hit_reaction.png"

func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1

func idle(n := 2) -> void:
	for i in n:
		await process_frame

func stand_body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	b.ground()
	return b

## a scene that holds the standing pose (two cards, as the other tests' fixtures)
func stand_scene(b: Body) -> Scene:
	var pose := b.to_dict()
	var s := Scene.new()
	s.from_dict({"scene": "zz_hit_stand", "fps": 30, "cards": [{"name": "a", "pose": pose, "move": -1.0, "hold": 2.0},
		{"name": "b", "pose": pose, "move": 0.5, "hold": 3.0}]})
	return s

## the striker: a body with its bat (the bat's data is what the effective mass reads)
func striker() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.fk()
	return b

## a hit row as Dummy.fighter_hits gives it, in the victim's own space (the hero's space = its space for this test)
func hit_on(B: Body, part: String, side: float, v: float) -> Dictionary:
	var a: Array = B.cap(part)
	var mid := ((a[0] as Vector3) + (a[1] as Vector3)) * 0.5
	var r: float = float(B.rad[part])
	return {"t": 1.0, "kind": "hit", "zone": "X", "part": "bat_barrel", "on": part, "by": "hero", "vs": 1, "u": 0.6,
		"depth": 0.01, "speed": v, "at": mid + Vector3(side * r, 0, 0), "vec": Vector3(v, 0, 0)}

## the body at one card frame's pose (the reaction's own pose, from its dense rows)
func pose_at(r: Dictionary, k: int, which: String) -> Body:
	var B := stand_body()
	var row: Dictionary = (r[which] as Array)[k]
	var A: Dictionary = (row["ang"] as Dictionary).duplicate()
	if which == "dense":
		var base: Dictionary = (r["base"] as Array)[k]["ang"]
		A = base.duplicate()
		for j in (row["ang"] as Dictionary):
			A[j] = row["ang"][j]
		B.ang = A
		B.offset = row["off"]
	else:
		B.ang = A
		B.offset = row["off"]
	B.fk()
	return B

func head_x(r: Dictionary, k: int) -> float:
	var B := pose_at(r, k, "dense")
	var a: Array = B.cap("head")
	return (((a[0] as Vector3) + (a[1] as Vector3)) * 0.5).x

func test_head() -> Dictionary:
	var B := stand_body()
	var h1 := hit_on(B, "head", -1.0, 12.0)
	return HitReaction.react(stand_scene(B), B, Transform3D.IDENTITY, h1, striker())

func _init() -> void:
	# 1 SPEED and direction (the head, from the right: its right side is -x)
	var r1 := test_head()
	var B := stand_body()
	var h2 := hit_on(B, "head", -1.0, 24.0)
	var r2 := HitReaction.react(stand_scene(B), B, Transform3D.IDENTITY, h2, striker())
	ok(bool(r1["ok"]) and bool(r2["ok"]), "the head hit reacts at 12 and 24 m/s (%s %s)" % [r1["why"], r2["why"]])
	var ratio: float = float(r2["peak"]) / maxf(float(r1["peak"]), 1e-9)
	print("     head: m_eff %.3f kg, J %.2f kg m/s, peak %.0f deg/s at 12 m/s, %.0f deg/s at 24 m/s (ratio %.3f), %d chain joints" % [
		float(r1["m_eff"]), (r1["J"] as Vector3).length(), rad_to_deg(float(r1["peak"])), rad_to_deg(float(r2["peak"])), ratio, (r1["joints"] as Array).size()])
	ok(absf(ratio - 2.0) <= 0.15 * 2.0, "2x speed -> %.3fx peak, within 15 percent of 2 (speed is linear in the impulse)" % ratio)
	var dx := -1e9
	for k in (r1["dense"] as Array).size():
		dx = maxf(dx, head_x(r1, k) - head_x(r1, 0))
	ok(dx > 0.005, "the head moves to the LEFT (+x) at its peak: %.1f mm (the bat came from the right)" % (dx * 1000.0))

	# 2 SHOVE (the chest, from the right)
	var Bc := stand_body()
	var hc := hit_on(Bc, "spine_03", -1.0, 12.0)
	var rc := HitReaction.react(stand_scene(Bc), Bc, Transform3D.IDENTITY, hc, striker())
	ok(bool(rc["ok"]), "the chest hit reacts (%s)" % rc["why"])
	# the first 240 Hz step (the spring's damping takes 2 zeta w dt = 5.5% of the speed in it; a whole card frame takes 13%)
	var nsub: int = ((rc["dense"] as Array).size() - 1) * 4
	var hstep: float = (float(rc["t1"]) - float(rc["t0"])) / float(nsub)
	var dpel: Vector3 = ((rc["fine"] as Array)[0]["off"] as Vector3) - ((rc["base"] as Array)[0]["off"] as Vector3)
	var dcard: Vector3 = ((rc["dense"] as Array)[1]["off"] as Vector3) - ((rc["base"] as Array)[1]["off"] as Vector3)
	var J: Vector3 = rc["J"]
	var expect: float = J.length() / float(rc["M"])
	var got: float = dpel.length() / hstep
	print("     chest: J %.2f kg m/s, M %.1f kg, J/M %.4f m/s; pelvis %.4f m/s over the first 1/240 s (%.1f%%), %.4f m/s averaged over the first card frame" % [
		J.length(), float(rc["M"]), expect, got, 100.0 * (got / maxf(expect, 1e-9) - 1.0), dcard.length() / ((float(rc["t1"]) - float(rc["t0"])) / float((rc["dense"] as Array).size() - 1))])
	ok(absf(got - expect) <= 0.10 * expect and dpel.dot(J) > 0.0, "the pelvis is shoved along the blow at J/M within 10 percent (first 1/240 s)")

	# 3 LIMITS (every 240 Hz step of both reactions)
	var worst := 0.0
	var bl := stand_body()
	for rr in [r1, r2, rc]:
		for row in rr["fine"]:
			for j in rr["joints"]:
				var a: Vector3 = (row["ang"] as Dictionary)[j]
				var cl: Vector3 = bl.clamp_ang(j, a)
				worst = maxf(worst, maxf(absf(a.x - cl.x), maxf(absf(a.y - cl.y), absf(a.z - cl.z))))
	ok(worst < 1e-3, "no reacting joint past its limits at any 240 Hz step (worst %.6f deg)" % worst)

	# 4 REPLAY: the baked cards against the simulation, at every 240 Hz step
	for rr in [r1, rc]:
		var S2 := Scene.new()
		S2.from_dict({"scene": "zz_hit_replay", "fps": 30, "cards": []})
		S2.cards = rr["cards"]
		var B2 := stand_body()
		var err := 0.0
		for row in rr["fine"]:
			S2.apply(B2, float(row["t"]))
			for j in rr["joints"]:
				var a: Vector3 = (row["ang"] as Dictionary)[j]
				var g: Vector3 = B2.ang[j]
				err = maxf(err, maxf(absf(a.x - g.x), maxf(absf(a.y - g.y), absf(a.z - g.z))))
		print("     replay: %d cards, worst difference %.3f deg" % [(rr["cards"] as Array).size(), err])
		ok(err <= 1.0, "the baked cards replay the simulated reaction within 1 deg (%.3f)" % err)
	ok(bool(r1["ok"]), "the hit reactions finished (the window %.2f s)" % (float(r1["t1"]) - float(r1["t0"])))

	# 5 UNDO and 6 SCREENSHOT, in the app
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m._load_scene("res://scenes/combo3.json")   # read only: nothing is written to scenes/
	m._rebuild_cards()
	await idle()
	var B2s := stand_body()
	m.S.actors.append({"name": "fighter 2", "xf": {"pos": [0.0, 1.2], "yaw": 180.0}, "scene": stand_scene(B2s)})
	m._actors_sync()
	m._refresh()
	await idle()
	ok(m._fighters_on() and m.actors_rt.size() == 2, "two fighters in the app")
	var vrow: Dictionary = m.actors_rt[1]
	var xf2: Transform3D = vrow["xf"]
	var hit := hit_on(vrow["B"], "head", -1.0, 12.0)
	hit["at"] = xf2 * (hit["at"] as Vector3)
	hit["vec"] = xf2.basis * (hit["vec"] as Vector3)
	m.fighter_hits = [hit]
	var n0: int = m.undo.size()
	var before := JSON.stringify(vrow["S"].cards)
	m._hit_react()
	ok(m.undo.size() == n0 + 1, "the command is ONE undo step (%d -> %d)" % [n0, m.undo.size()])
	var mid := JSON.stringify(m.actors_rt[1]["S"].cards)
	ok(mid != before, "fighter 2's cards change (the reaction is baked on its scene)")
	m._undo()
	ok(JSON.stringify(m.actors_rt[1]["S"].cards) == before and m.undo.size() == n0, "Ctrl+Z puts fighter 2's cards back exactly")
	m.fighter_hits = [hit]   # the report is measured again after an undo (it was cleared): the same contact
	m._hit_react()
	m.playhead = 1.0 + 0.15
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	await idle(6)
	var img: Image = m.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(SHOT.get_base_dir())
	var e := img.save_png(SHOT)
	ok(e == OK and img.get_width() > 0, "a reaction frame saved to %s (error %d, %dx%d)" % [SHOT, e, img.get_width(), img.get_height()])
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)

