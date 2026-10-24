## godot --headless --path . -s tools/bench_solve.gd -- [--only id,id] [--write]
## KINE-BENCH REFERENCE SOLUTIONS AND START SCENES (N024; the grader: scripts/kine_bench.gd). Every task in bench/tasks gets
##   bench/solutions/<id>.json  a scene that solves it, built here with Kine's own operations only, and
##   bench/start/<id>.json      the scene the agent starts from: the solution's first card (the guard / stance) and, when the
##                              task has one, fighter 2 (a standing target, or the attacker of a two-fighter task).
## Nothing is hand-written into a scene: a card is the body posed by joint angles (Body.set_ang_safe, what serve's set= step
## and the joint panel do) and added as a card (Scene.add, the card strip's +); the feet are re-planted by Scene.pin_cards (the
## pin every scene plays with); steps are a card's "steps" entry (what text_blocking and the walk template write); timing is
## the card's move / hold (the timeline's number entry); a weapon strike is TextBlocking.build (type a move, get blocking);
## walks are the committed templates (tools/make_templates.gd); a second fighter is the Actor op's entry (Scene.actors).
## TARGETS ARE PLACED FROM THE REFERENCE: a target's spot (fighter 2's pos on the floor, facing the hero) is found by bisection
## so the reference's striking part just touches the named target point at the contact time (gap -GAP_IN, BodyAssert's own gap).
## So every task is solvable by construction, at a real reach; an agent must still build a move that gets there on time.
## Without --write it only prints each grade (KineBench.grade on the built scene and on the start scene).
extends SceneTree



const GAP_IN := 0.005   # m: the reference's part ends this far inside the target's surface at the contact frame (a touch)
const SOL := "res://bench/solutions/"
const START := "res://bench/start/"

var m: Node
var A: AgentTools
var B: Body
var S: Scene
var start_cards := []   # a task may start from more than the first card (a repair task: the whole raw move): its cards, saved form


func _init() -> void:
	var a := Array(OS.get_cmdline_user_args())
	var write := "--write" in a
	var only := []
	var k := a.find("--only")
	if k >= 0 and k + 1 < a.size():
		only = String(a[k + 1]).split(",")
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	A = AgentTools.new(m)
	var fails := 0
	for t in KineBench.tasks(true):
		var id := String(t["id"])
		if not only.is_empty() and not id in only:
			continue
		if not has_method("t_" + id):
			print("NO BUILDER for ", id)
			fails += 1
			continue
		await A.request(1, "new", {})
		start_cards = []
		S = m.S
		B = m.B
		await call("t_" + id)
		await process_frame
		var sol := SOL + id + ".json"
		var st := START + id + ".json"
		var tmp := "user://bench_tmp_%s.json" % id
		A.write_scene(tmp, "bench/solutions (tools/bench_solve.gd)")
		KineBench.open_scene(m, tmp)
		var g := KineBench.grade(m, A, t)
		print("\n=== %s  score %d  solved %s  (%d cards, %.2f s)" % [id, g["score"], g["solved"], g["cards"], g["length_s"]])
		for l in g["lines"]:
			print("   ", l["say"])
		for b in g["bars"]:
			print("   ", b["say"])
		# the start: the first card (+ fighter 2)
		var sd: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(tmp))
		var sd0 := sd.duplicate(true)
		sd0["cards"] = [sd["cards"][0]] if start_cards.is_empty() else start_cards
		sd0["scene"] = "start_" + id
		sd0["plan"] = "bench/start (tools/bench_solve.gd): the first card of the reference%s" % (" and fighter 2" if sd.has("actors") else "")
		for x in ["asserts", "bad_frames", "length_s"]:
			sd0.erase(x)
		var tmp0 := "user://bench_tmp_start_%s.json" % id
		m._write(tmp0, sd0)
		KineBench.open_scene(m, tmp0)
		var g0 := KineBench.grade(m, A, t)
		print("   start scene: score %d" % g0["score"])
		if write:
			sd["scene"] = id
			m._write(sol, sd)
			m._write(st, sd0)
			print("   wrote ", sol, " and ", st)
		if g["score"] < 80 or g0["score"] >= 30:
			fails += 1
	quit(1 if fails > 0 else 0)


# ------------------------------------------------------------------------------------------------ building blocks

## the scene starts from a committed scene's cards (its first n, or all)
func base(path: String, n := -1) -> void:
	if not KineBench.open_scene(m, path):
		print("   OPEN %s failed" % path)
	S = m.S
	B = m.B
	if n > 0:
		S.cards = S.cards.slice(0, n)
	S.actors = []


## a new card: card `from`'s pose (1-based; 0 = the last card), the joints in `sets` set ({joint: [bend, side, twist]}, absolute),
## the hips moved by `off` (m), then added at the end with its move / hold (s)
func key(nm: String, from: int, sets: Dictionary, move: float, hold: float, off := Vector3.ZERO, extra := {}) -> void:
	var i := (from - 1) if from > 0 else S.cards.size() - 1
	Scene.put(B, Moves._flat(S.cards[i]["pose"]))
	B.offset += off
	B.fk()
	for j in sets:
		var v: Array = sets[j]
		B.set_ang_safe(j, Vector3(v[0], v[1], v[2]))
	S.add(nm, B.to_dict())
	S.cards[-1]["move"] = move
	S.cards[-1]["hold"] = hold
	for x in extra:
		S.cards[-1][x] = extra[x]


## card ci (1-based) re-posed: the joints in `sets` set in order (set_ang_safe: a turn into another part stops, and is printed)
func repose(ci: int, nm: String, sets: Array) -> void:
	Scene.put(B, Moves._flat(S.cards[ci - 1]["pose"]))
	for jv in sets:
		var v := Vector3(jv[1], jv[2], jv[3])
		B.last_stop = {}
		B.set_ang_safe(jv[0], v)
		if not (B.ang[jv[0]] as Vector3).is_equal_approx(v):
			print("   STOP %s -> %s reached %s (%s)" % [jv[0], v, B.ang[jv[0]], B.last_stop])
	S.cards[ci - 1]["pose"] = B.to_dict()
	if nm != "":
		S.cards[ci - 1]["name"] = nm


## PIVOT: card ci's (1-based) hips slid along the floor until foot sd's toe base is back where it stood on card 1, then that leg
## planted there (Body.plant, the leg alone) pointing where the turned hips point it: a foot that pivots on its ball
## (hips = Vector2(x, z): the hips put there instead, e.g. over the standing foot)
func pivot(ci: int, sd: String, hips: Variant = null) -> void:
	Scene.put(B, Moves._flat(S.cards[0]["pose"]))
	var b0: Vector3 = B.foot_state(sd)[0]
	Scene.put(B, Moves._flat(S.cards[ci - 1]["pose"]))
	if hips is Vector2:
		B.offset = Vector3(hips.x, B.offset.y, hips.y)
		B.fk()
	else:
		for it in 3:
			var d: Vector3 = (B.P["ball" + sd] as Vector3) - b0
			B.offset -= Vector3(d.x, 0.0, d.z)
			B.fk()
	var miss := B.plant(sd, b0, B.foot_heading(sd), true)
	S.cards[ci - 1]["pose"] = B.to_dict()
	print("   pivot card %d on %s: hips at %s, the toe base misses by %.4f m" % [ci, sd, B.offset, miss])


## the feet put back where they stood (Scene.pin_cards: the pin every scene plays with)
func pin() -> void:
	S.pin_cards(B)


## the scene saved and opened again (what the grader sees: a card's "steps" become the played travel on open)
func reload() -> void:
	var tmp := "user://bench_reload.json"
	A.write_scene(tmp, "reload")
	KineBench.open_scene(m, tmp)
	S = m.S
	B = m.B


## fighter 2: a still copy of a pose (2 cards, the same pose), facing the hero (yaw 180) at (x, z)
func target(pose0: Dictionary, x: float, z: float, hold := 3.0) -> void:
	var pose := pose0.duplicate(true)
	if pose.has("offset"):   # the pose's own floor travel dropped (a walk's first card stands 3.85 m back): fighter 2 stands at (x, z)
		pose["offset"] = [0.0, float(pose["offset"][1]), 0.0]
	var S2 := Scene.new()
	S2.name = "target"
	S2.add("stand", pose.duplicate(true))
	S2.add("stand", pose.duplicate(true))
	S2.cards[0]["hold"] = hold
	S2.cards[1]["move"] = 0.2
	S2.cards[1]["hold"] = 0.0
	S2.on_floor = S.on_floor
	S.actors = [{"name": "fighter 2", "xf": {"pos": [x, z], "yaw": 180.0}, "scene": S2}]


## the gap (m) between hero thing `a` and fighter-2 thing `b` at time t, with fighter 2 where it stands now (BodyAssert's own gap)
func gap_at(a: String, b: String, t: float) -> float:
	var qa := BodyAssert.thing(a)
	var qb := BodyAssert.thing(b)
	var S2: Scene = S.actors[0]["scene"]
	var B2 := Body.new()
	B2.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	S.apply_true(B, t)
	S2.apply_true(B2, t)
	var X := Constraints.actor_xf(S.actors[0]["xf"])
	return BodyAssert.gap(BodyAssert.shapes(qa, B, Transform3D.IDENTITY), BodyAssert.shapes(qb, B2, X))


## place fighter 2 so hero thing `a` touches fighter-2 thing `b` at time t: x lined up with a's point, then z by bisection
## (two POINTS, a weapon tip on a landmark, cannot overlap: their gap is >= 0, so they are walked in to a gap of +GAP_IN, inside the
## 1 cm touch bar)
func place(a: String, b: String, t: float, dx := 0.0) -> void:
	var thr := -GAP_IN
	if a.begins_with("weapon") and not ["head", "hips", "pelvis", "hand", "fist", "forearm", "thigh", "shin", "foot"].has(b.get_slice(" ", b.get_slice_count(" ") - 1)):
		thr = GAP_IN
	S.apply_true(B, t)
	var pa := BodyAssert.point(BodyAssert.thing(a), B, Transform3D.IDENTITY)
	var S2: Scene = S.actors[0]["scene"]
	var B2 := Body.new()
	B2.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	S2.apply_true(B2, t)
	var pb := BodyAssert.point(BodyAssert.thing(b), B2, Transform3D.IDENTITY)   # in fighter 2's own space; yaw 180 flips x and z
	S.actors[0]["xf"]["pos"][0] = pa.x + pb.x + dx
	# the gap is not monotone in the distance (a target point passes through the part and out the back), so the target walks in
	# from 3 m in 1 cm steps until it first touches, then the last 1 cm is bisected
	var z := 3.0
	S.actors[0]["xf"]["pos"][1] = z
	while z > 0.2 and gap_at(a, b, t) > thr:
		z -= 0.01
		S.actors[0]["xf"]["pos"][1] = z
	var lo := z
	var hi := z + 0.01
	for it in 30:
		var mid := (lo + hi) * 0.5
		S.actors[0]["xf"]["pos"][1] = mid
		if gap_at(a, b, t) > thr:
			hi = mid
		else:
			lo = mid
	S.actors[0]["xf"]["pos"][1] = snappedf(lo, 0.0001)
	S.actors[0]["xf"]["pos"][0] = snappedf(float(S.actors[0]["xf"]["pos"][0]), 0.0001)
	var lm := []
	for w in ["chin", "face", "neck", "chest", "belly"]:
		lm.append("%s %.3f" % [w, SayIt.landmark(B2, w, "", "_r").y])
	print("   place %s -> %s at %.3f s: part at %s, target point (own space) %s, fighter 2 at %s, gap %.4f m; target heights %s" % [a, b, t, pa, pb, S.actors[0]["xf"]["pos"], gap_at(a, b, t), ", ".join(lm)])


## where the reference's part is fastest within [t0, t1] (the contact frame of a strike): the time
func fastest(a: String, t0: float, t1: float) -> float:
	var q := BodyAssert.thing(a)
	var best := -1.0
	var at := t0
	var h := 1.0 / float(S.fps)
	var t := t0
	while t <= t1 + 1e-9:
		S.apply_true(B, maxf(0.0, t - h))
		var p0 := BodyAssert.point(q, B, Transform3D.IDENTITY)
		S.apply_true(B, t + h)
		var p1 := BodyAssert.point(q, B, Transform3D.IDENTITY)
		var v := (p1 - p0).length() / (2.0 * h)
		if v > best:
			best = v
			at = t
		t += h
	return at


## the time in [t0, t1] where hero thing `a` is farthest along his front (+z): where a straight strike is fully out
func farthest(a: String, t0: float, t1: float) -> float:
	var q := BodyAssert.thing(a)
	var best := -INF
	var at := t0
	var t := t0
	while t <= t1 + 1e-9:
		S.apply_true(B, t)
		var z := BodyAssert.point(q, B, Transform3D.IDENTITY).z
		if z > best:
			best = z
			at = t
		t += 1.0 / float(S.fps)
	return snappedf(at, 0.0001)


## AIM: card ci's (1-based) joint angle on one axis (0 bend / 1 side / 2 twist) set by bisection in [lo, hi] so that hero
## thing `a` is at height y at time t (the arm raised or lowered until the fist meets the target's height)
func aim(ci: int, j: String, axis: int, lo: float, hi: float, a: String, t: float, y: float, comp := 1) -> float:
	var q := BodyAssert.thing(a)
	var f := func(v: float) -> float:
		Scene.put(B, Moves._flat(S.cards[ci - 1]["pose"]))
		var ang: Vector3 = B.ang[j]
		ang[axis] = v
		B.set_ang(j, ang)
		B.fk()
		S.cards[ci - 1]["pose"] = B.to_dict()
		S.apply_true(B, t)
		return BodyAssert.point(q, B, Transform3D.IDENTITY)[comp] - y
	var flo: float = f.call(lo)
	if (flo > 0.0) == ((f.call(hi) as float) > 0.0):
		print("   AIM card %d %s axis %d: no sign change in [%.1f, %.1f] (%.3f, %.3f m off)" % [ci, j, axis, lo, hi, flo, f.call(hi)])
	for it in 30:
		var mid := (lo + hi) * 0.5
		var fm: float = f.call(mid)
		if (fm > 0.0) == (flo > 0.0):
			lo = mid
			flo = fm
		else:
			hi = mid
	var v := snappedf((lo + hi) * 0.5, 0.01)
	f.call(v)
	return v


## the target's landmark height (m) in its pose
func land_y(pose: Dictionary, w: String) -> float:
	var B2 := Body.new()
	B2.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	Scene.put(B2, Moves._flat(pose))
	return SayIt.landmark(B2, w, "", "_r").y


# ------------------------------------------------------------------------------------------------ the tasks
## STRIKES. The guard and the cross are the punch template's (templates/punch.json: tools/make_templates.gd, its numbers cited there)

func t_strike_cross_chin() -> void:
	await base("res://templates/punch.json")
	var g: Dictionary = S.cards[0]["pose"]
	print("   cross aimed: upperarm_r bend %.2f" % aim(3, "upperarm_r", 1, -20.0, 45.0, "right fist", 0.8, land_y(g, "chin")))
	print("   fist farthest at %.3f s" % farthest("right fist", 0.6, 1.0))
	target(g, 0.0, 1.0)
	place("right fist", "fighter 2 chin", 0.8)


## a left jab from the punch template's guard: the arm's numbers are the template's cross arm on the left side. The legs and hips
## are the guard's, so nothing is re-planted (pin_cards plants a card's feet where the card before PLAYS them, 1.7 cm up here)
func t_strike_jab_chin() -> void:
	await base("res://templates/punch.json", 1)
	var g: Dictionary = S.cards[0]["pose"]
	S.cards[0]["hold"] = 0.35
	key("JAB", 1, {"upperarm_l": [88, -6, 0], "lowerarm_l": [4, 0, 0], "clavicle_l": [0, 22, 0], "spine_01": [4, 0, -6],
		"spine_02": [6, 0, -6], "spine_03": [6, 0, -6], "neck_01": [8, 0, 6]}, 0.15, 0.0)
	key("recover", 1, {}, 0.25, 0.4)
	print("   jab aimed: upperarm_l bend %.2f" % aim(2, "upperarm_l", 1, -20.0, 45.0, "left fist", 0.5, land_y(g, "chin")))
	print("   fist farthest at %.3f s" % farthest("left fist", 0.3, 0.8))
	target(g, 0.0, 1.0)
	place("left fist", "fighter 2 chin", 0.5)


## a right hook: the punch template's cross with the arm bent 90 at the elbow and swung across at head height (hips and feet
## are the cross's: already pivoted and planted by the template)
func t_strike_hook_head() -> void:
	await base("res://templates/punch.json")
	var g: Dictionary = S.cards[0]["pose"]
	repose(3, "HOOK", [["upperarm_r", 55, 0, 0], ["lowerarm_r", 95, 0, 0]])
	print("   hook aimed: upperarm_r side %.2f" % aim(3, "upperarm_r", 1, -30.0, 85.0, "right fist", 0.8, land_y(g, "face")))
	print("   fist farthest at %.3f s" % farthest("right fist", 0.6, 1.0))
	target(g, 0.0, 1.0)
	place("right fist", "fighter 2 head", 0.8)


## a right uppercut: the cross's hips and feet, the arm low and bent, the fist rising to the chin
func t_strike_uppercut_chin() -> void:
	await base("res://templates/punch.json")
	var g: Dictionary = S.cards[0]["pose"]
	repose(2, "dip", [["upperarm_r", 20, -70, 0], ["lowerarm_r", 100, 0, 0]])
	repose(3, "UPPERCUT", [["upperarm_r", 60, 10, 0], ["lowerarm_r", 100, 0, 0]])
	print("   uppercut aimed: upperarm_r side %.2f" % aim(3, "upperarm_r", 1, -40.0, 85.0, "right fist", 0.8, land_y(g, "chin") - 0.03))
	print("   fist farthest at %.3f s" % farthest("right fist", 0.6, 1.0))
	target(g, 0.0, 1.0)
	place("right fist", "fighter 2 head", 0.8)


# KICKS. From the punch template's guard (orthodox: left foot ahead, the right leg kicks). The standing (left) leg keeps the
# guard's angles while the hips do not move, so its foot stays planted; where the hips turn, pin_cards re-plants it.

## a right front kick (teep): chamber, extend into the belly, re-chamber, back to the guard
func t_kick_front_belly() -> void:
	await base("res://templates/punch.json", 1)
	var g: Dictionary = S.cards[0]["pose"]
	S.cards[0]["hold"] = 0.3
	key("chamber", 1, {"thigh_r": [95, 5, 0], "calf_r": [110, 0, 0], "foot_r": [-20, 0, 0], "spine_01": [0, 0, -3]}, 0.25, 0.0)
	key("KICK", 2, {"thigh_r": [80, 5, 0], "calf_r": [10, 0, 0], "foot_r": [-25, 0, 0], "spine_01": [-5, 0, -3], "spine_02": [0, 0, -3]}, 0.15, 0.05)
	key("re-chamber", 2, {}, 0.15, 0.0)
	key("guard", 1, {}, 0.3, 0.3)
	print("   kick aimed: thigh_r bend %.2f" % aim(3, "thigh_r", 0, 40.0, 115.0, "right foot", 0.7, land_y(g, "belly")))
	print("   foot farthest at %.3f s" % farthest("right foot", 0.5, 0.9))
	target(g, 0.0, 1.2)
	place("right foot", "fighter 2 belly", 0.7)


## a right knee strike: the knee driven up into the belly over the planted left leg, the hands kept up
func t_kick_knee_belly() -> void:
	await base("res://templates/punch.json", 1)
	var g: Dictionary = S.cards[0]["pose"]
	S.cards[0]["hold"] = 0.3
	key("KNEE", 1, {"thigh_r": [110, 0, 0], "calf_r": [125, 0, 0], "foot_r": [-30, 0, 0], "spine_02": [8, 0, -3]}, 0.25, 0.05)
	key("guard", 1, {}, 0.3, 0.3)
	print("   knee aimed: thigh_r bend %.2f" % aim(2, "thigh_r", 0, 60.0, 120.0, "right knee", 0.55, land_y(g, "belly") - 0.02))
	print("   thigh farthest at %.3f s" % farthest("right thigh", 0.4, 0.8))
	target(g, 0.0, 1.0)
	place("right thigh", "fighter 2 belly", 0.55)


## a right roundhouse: the hips turn left over the left foot, which pivots on its ball (each card "steps" it 0 m with no lift, so
## playback turns its heading with the hips: a pin would hold the guard's heading and the leg cannot twist 75 deg, the hip's
## twist range being +-40); the hips tip back (pelvis bend) to lift the leg round at hip height (Kine's hip abducts 45 deg at most, so the leg is level
## only when the pelvis tips 45 too: a mid roundhouse to the hips / short ribs, not a high one). The guard is held as a MOVE
## between two guard cards: in the first card's own hold no foot is pinned and the leading hips (natural timing) would lift it
func t_kick_roundhouse() -> void:
	await base("res://templates/punch.json", 1)
	var g: Dictionary = S.cards[0]["pose"]
	S.cards[0]["hold"] = 0.0
	key("guard", 1, {}, 0.3, 0.0)
	key("chamber", 1, {"pelvis": [-15, 0, 35], "thigh_r": [60, 40, 0], "calf_r": [110, 0, 0], "foot_r": [-30, 0, 0], "spine_01": [0, -5, -10], "spine_02": [0, -5, -10]}, 0.2, 0.0)
	key("KICK", 3, {"pelvis": [-45, 0, 75], "thigh_r": [25, 45, 0], "calf_r": [15, 0, 0], "foot_r": [-30, 0, 0], "spine_01": [0, -7, -17], "spine_02": [0, -7, -17], "spine_03": [0, -7, -15]}, 0.15, 0.05)
	key("re-chamber", 3, {}, 0.2, 0.0)
	key("guard", 1, {}, 0.3, 0.3)
	pivot(3, "_l", Vector2(0.06, 0.12))
	pivot(4, "_l", Vector2(0.10, 0.20))
	pivot(5, "_l", Vector2(0.06, 0.12))
	for ci in [3, 4, 5, 6]:
		S.cards[ci - 1]["steps"] = {"_l": [0.0, 0.0, 0.0]}
		S.cards[ci - 1]["lift"] = 0.0
	print("   roundhouse aimed: pelvis bend %.2f" % aim(4, "pelvis", 0, -60.0, 0.0, "right shin", 0.7, 0.85))
	pivot(4, "_l", Vector2(0.10, 0.20))
	print("   shin farthest at %.3f s" % farthest("right shin", 0.5, 0.9))
	target(g, 0.0, 1.2)
	place("right shin", "fighter 2 hips", 0.7)


# WEAPONS. Type a move, get blocking (TextBlocking.build: Nick's saved strikes retrieved and adapted, ROADMAP 22)

## the phrase blocked out and opened as the scene (as "Block out a move from words..." does) -> the build's report
func blocking(text: String) -> Dictionary:
	var W := Body.new()
	W.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var r: Dictionary = TextBlocking.build(text, W)
	if not r["ok"]:
		print("   BLOCKING '%s' failed: %s" % [text, r["error"]])
		return r
	var tmp := "user://bench_block_%s.json" % TextBlocking.slug(text)
	var d: Dictionary = (r["scene"] as Scene).to_dict(W)
	d["plan"] = "Block out a move from words '%s': %s" % [text, r["status"]]
	m._write(tmp, d)
	await base(tmp)
	print("   blocking '%s': %d cards, %.2f s, peak %.1f m/s at %.3f s, strike card %d, must-fix %d; %s" % [text, S.cards.size(), S.length(), r["peak"], r["peak_t"], int(r["strike_card"]) + 1, r["must_fix"], r["status"]])
	return r


## WeaponTorque's own fix (the WEAPON judge's fix button: a wind-up card, an overshoot past contact, the swing slowed until the arm can
## supply the torque), applied until every swing reads fine (at most 3 rounds)
func weapon_fix(rounds := 3) -> void:
	for it in rounds:
		var bad := {}
		for sw in WeaponTorque.swings(S, B):
			var r := WeaponTorque.analyze(S, B, int(sw["card"]))
			if not bool(r["ok"]):
				bad = r
				break
		if bad.is_empty():
			return
		var p := WeaponTorque.fix(S, B, bad)
		print("   weapon fix: %s" % p["msg"])
		if not bool(p["ok"]):
			return
		S.cards = (p["scene"] as Scene).cards
		# the fix slows the wind-up, strike and overshoot; the cards after it keep their old speed, and a recovery 5x faster than the swing
		# reads as a SEQUENCE must-fix in Check: they are slowed by the same factor
		for q in range(int(p["card"]) + 2, S.cards.size()):
			S.cards[q]["move"] = snappedf(S.move_time(q) * float(p["factor"]), 0.001)


## a weapon task: the phrase blocked out, the weight fixed, then fighter 2 put where the tip lands at its fastest moment of the strike
func weapon(text: String, at: String, rounds := 3, over_k := 0.0, arrive := false, antic_k := 0.0, aims := ["spine_01", "spine_02"]) -> void:
	await blocking(text)
	weapon_fix(rounds)
	if over_k > 0.0:   # the overshoot pushed further past contact (WeaponTorque._extrapolate: the strike pose away from the card before it);
		# a strike followed straight by its recovery gets a new overshoot card
		for i in range(2, S.cards.size()):
			if String(S.cards[i - 1]["name"]).to_upper().begins_with("STRIKE"):
				var over := WeaponTorque._extrapolate(B, S.cards[i - 1]["pose"], S.cards[i - 2]["pose"], over_k)
				var nm := String(S.cards[i]["name"]).to_lower()
				if nm.begins_with("overshoot") or nm.begins_with("follow"):
					S.cards[i]["pose"] = over
					S.cards[i]["move"] = maxf(S.move_time(i), 0.3)   # a heavy thing does not stop in a frame: the further overshoot gets time
				else:
					S.cards.insert(i, {"name": "overshoot", "pose": over, "move": 0.3, "hold": 0.0})
				print("   overshoot card %d pushed %.0f%% past contact over %.2f s" % [i + 1, over_k * 100.0, S.move_time(i)])
				break
	if antic_k > 0.0:   # the wind-up pushed further back, away from the strike
		for i in range(1, S.cards.size() - 1):
			if String(S.cards[i + 1]["name"]).to_upper().begins_with("STRIKE"):
				S.cards[i]["pose"] = WeaponTorque._extrapolate(B, S.cards[i]["pose"], S.cards[i + 1]["pose"], antic_k)
				print("   wind-up card %d pushed %.0f%% further back" % [i + 1, antic_k * 100.0])
				break
	if over_k > 0.0 or antic_k > 0.0:
		for q in WeaponTorque.swings(S, B):
			print("   after the push: %s" % WeaponTorque.describe(WeaponTorque.analyze(S, B, int(q["card"]))))
	pin()
	var ts := S.times()
	var k := 0
	for i in S.cards.size():
		if String(S.cards[i]["name"]).to_upper().begins_with("STRIKE"):
			k = i
	var t := snappedf(fastest("weapon tip", float(ts[k - 1][1]), float(ts[k][1])), 1.0 / 30.0)   # contact = the tip at its fastest in the strike
	if arrive:   # a thrust lands at full reach: 2 frames before the strike card arrives
		t = snappedf(float(ts[k][1]) - 2.0 / 30.0, 1.0 / 30.0)
	var cs := []
	for i in S.cards.size():
		cs.append("%s @%.2f" % [String(S.cards[i]["name"]).get_slice(":", 0), float(ts[i][1])])
	print("   contact at %.3f s (the tip at its fastest in the strike), clip %.2f s, cards %s" % [t, S.length(), ", ".join(cs)])
	target(S.cards[0]["pose"], 0.0, 1.5)
	if at == "":   # the target landmark of fighter 2 nearest the tip's height at contact (fighter 2 only slides on the floor)
		S.apply_true(B, t)
		var ty := BodyAssert.point(BodyAssert.thing("weapon tip"), B, Transform3D.IDENTITY).y
		var best := INF
		for w in ["head", "chin", "neck", "chest", "belly", "hips"]:
			var y := land_y(S.cards[0]["pose"], w)
			if absf(y - ty) < best:
				best = absf(y - ty)
				at = "fighter 2 " + w
		print("   tip at %.3f m at contact: target %s" % [ty, at])
		# the strike card's trunk lean (spine_01 + spine_02 bend, both hands go with it) set so the tip meets the landmark's height
		var y := land_y(S.cards[0]["pose"], at.trim_prefix("fighter 2 "))
		for j in aims:
			Scene.put(B, Moves._flat(S.cards[k]["pose"]))
			var cur: float = (B.ang[j] as Vector3).x
			var r: Vector2 = B.lim[j]["bend"]
			var v := aim(k + 1, j, 0, maxf(r.x, cur - 30.0), minf(r.y, cur + 30.0), "weapon tip", t, y)
			S.apply_true(B, t)
			var off := BodyAssert.point(BodyAssert.thing("weapon tip"), B, Transform3D.IDENTITY).y - y
			print("   aimed %s bend %.1f -> %.2f: the tip %.3f m off the height" % [j, cur, v, off])
			if absf(off) < 0.003:
				break
		# the aim changed the strike: read the weight again (one fix round, the time of contact re-read: slowing scales the strike's
		# time, the tip's path stays)
		weapon_fix(1)
		ts = S.times()
		for i in S.cards.size():
			if String(S.cards[i]["name"]).to_upper().begins_with("STRIKE"):
				k = i
		t = snappedf(fastest("weapon tip", float(ts[k - 1][1]), float(ts[k][1])), 1.0 / 30.0)
		if arrive:
			t = snappedf(float(ts[k][1]) - 2.0 / 30.0, 1.0 / 30.0)
		print("   contact re-read at %.3f s" % t)
	place("weapon tip", at, t)


func t_weapon_bat_forehand() -> void:
	await weapon("forehand bat swing", "fighter 2 head")


func t_weapon_dagger_thrust() -> void:
	await weapon("dagger thrust", "", 1, 0.8, true, 0.0, ["upperarm_r", "upperarm_l", "spine_01"])


## a REPAIR task: the start is the raw blocked swing (33 m/s at the tip: weightless, WEAPON flags 336 N m at the wrist), the agent
## must give the bat its weight; the reference is WeaponTorque's own fix of it
func t_weapon_bat_weight() -> void:
	await blocking("forehand bat swing")
	var raw := "user://bench_raw_weight.json"
	A.write_scene(raw, "raw")
	start_cards = (JSON.parse_string(FileAccess.get_file_as_string(raw)) as Dictionary)["cards"]
	weapon_fix()
	pin()
	var ts := S.times()
	var k := 0
	for i in S.cards.size():
		if String(S.cards[i]["name"]).to_upper().begins_with("STRIKE"):
			k = i
	var t := snappedf(fastest("weapon tip", float(ts[k - 1][1]), float(ts[k][1])), 1.0 / 30.0)
	print("   contact at %.3f s, clip %.2f s" % [t, S.length()])
	target(S.cards[0]["pose"], 0.0, 1.5)
	place("weapon tip", "fighter 2 head", t)


# FALLS. The whole body is grounded on its lowest point (floor_body, as the get-up scenes play: tools/getup.gd), the pelvis
# tipped past -90 to lie (body_limits widened it for that). Breakfall's rules (scripts/breakfall.gd) are the judge.

## the Breakfall check's own lines for each fall of the scene
func say_falls() -> void:
	var rep := Breakfall.analyze(S)
	print("   breakfall: %s" % rep["msg"])
	for f in rep["falls"]:
		for ln in BreakfallUI.lines(f):
			print("     %s %s" % [ln[0], ln[1]])


## Breakfall's own fixes (the buttons under a fall in the breakfall panel), picked as JudgeSuite's fix picks them: the first rule of
## `order` that is not ok (a head -> tuck, b arm -> slap, c spread -> roll, d speed -> lower), until the landing is clean (at most 6 rounds)
func breakfall_fix(order := ["a", "b", "c", "d"]) -> void:
	for it in 6:
		var rep := Breakfall.analyze(S)
		if rep["falls"].is_empty() or int(rep["bad"]) == 0:
			return
		var f: Dictionary = rep["falls"][0]
		var kind := ""
		for r in order:
			if String(f[r]) != "ok":
				kind = {"a": "tuck", "b": "slap", "c": "roll", "d": "lower"}[r]
				break
		if kind == "":
			return
		var p: Dictionary
		match kind:
			"tuck": p = Breakfall.tuck(S, f)
			"slap": p = Breakfall.slap(S, f)
			"roll": p = Breakfall.roll(S, f)
			_: p = Breakfall.lower(S, f)
		if not bool(p.get("ok", false)):
			print("   breakfall fix %s: %s" % [kind, p.get("why", "")])
			return
		print("   breakfall fix %s: %s -> %s" % [kind, p.get("msg", ""), (p.get("rep", {}) as Dictionary).get("msg", "")])
		S.cards = (p["scene"] as Scene).cards
		S.plants = (p["scene"] as Scene).plants


## a backward fall (ushiro ukemi): from the guard sink into a deep squat, then roll back over the rounded back with the knees to
## the chest, the arms reaching to slap about 45 deg from the trunk (Breakfall.SLAP_DEG), then lie. MEASURED while building: with the
## trunk upright when the hips land the impact is the tailbone alone (SPREAD fail), so the hips only reach the floor in the roll,
## as the back does; a 0.3 s roll landed the upper back at 5.5 m/s, a 0.5 s one at 2.3 (SPEED_OK 2.5). The chin tuck is Breakfall.tuck.
func t_fall_back() -> void:
	await fall_back(false)
	await breakfall_fix(["a", "b", "d"])
	say_falls()


## the backward fall's cards; bad = the same fall with the head carried upright (neck and head at 0) and the hands kept in the
## guard (no slap): what an untrained faller does
func fall_back(bad: bool) -> void:
	await base("res://templates/punch.json", 1)
	S.floor_body = true
	S.cards[0]["hold"] = 0.0
	var head := {"neck_01": [0, 0, 0], "head": [0, 0, 0]} if bad else {"neck_01": [26, 0, 0], "head": [14, 0, 0]}
	key("guard", 1, {}, 0.3, 0.0)
	var sink := {"pelvis": [10, 0, 0], "thigh_l": [85, 8, 0], "thigh_r": [85, 8, 0], "calf_l": [115, 0, 0], "calf_r": [115, 0, 0]}
	if not bad:
		sink.merge({"upperarm_l": [60, -40, 0], "upperarm_r": [60, -40, 0], "lowerarm_l": [30, 0, 0], "lowerarm_r": [30, 0, 0]})
	sink.merge(head)
	key("sink", 1, sink, 0.25, 0.0)
	key("squat", 2, {"pelvis": [20, 0, 0], "thigh_l": [115, 8, 0], "thigh_r": [115, 8, 0], "calf_l": [140, 0, 0], "calf_r": [140, 0, 0],
		"spine_01": [15, 0, 0], "spine_02": [15, 0, 0]}, 0.15, 0.0)
	var roll := {"pelvis": [-100, 0, 0], "thigh_l": [100, 8, 0], "thigh_r": [100, 8, 0], "calf_l": [110, 0, 0], "calf_r": [110, 0, 0],
		"spine_01": [0, 0, 0], "spine_02": [0, 0, 0], "spine_03": [0, 0, 0]}
	if not bad:
		roll.merge({"upperarm_l": [-25, -45, 0], "upperarm_r": [-25, -45, 0], "lowerarm_l": [35, 0, 0], "lowerarm_r": [35, 0, 0]})
	key("ROLL BACK" if bad else "ROLL BACK (slap)", 3, roll, 0.5, 0.0)
	key("lie", 0, {"pelvis": [-92, 0, 0], "thigh_l": [40, 8, 0], "thigh_r": [40, 8, 0], "calf_l": [40, 0, 0], "calf_r": [40, 0, 0]}, 0.35, 0.5)
	pin()


## a REPAIR task: the start is the backward fall done untrained (bad = true above: the head upright, the hands in the guard); the
## reference is the trained one (t_fall_back: the chin tucked, the arms slapping), checked by Breakfall
func t_fall_repair() -> void:
	await fall_back(true)
	say_falls()
	var raw := "user://bench_raw_fall.json"
	A.write_scene(raw, "raw")
	start_cards = (JSON.parse_string(FileAccess.get_file_as_string(raw)) as Dictionary)["cards"]
	await fall_back(false)
	await breakfall_fix(["a", "b", "d"])
	say_falls()


## a side fall (yoko ukemi): from the squat the body rolls back and over onto its RIGHT side (pelvis side -40 / -45 deg: measured at the
## end, the right hip joint lies 10 cm under the left), the arm reaching out, the hips landing on their side (Breakfall's "hip side")
func t_fall_side() -> void:
	await base("res://templates/punch.json", 1)
	S.floor_body = true
	S.cards[0]["hold"] = 0.0
	key("guard", 1, {}, 0.3, 0.0)
	key("sink", 1, {"pelvis": [10, 0, 0], "thigh_l": [85, 8, 0], "thigh_r": [85, 8, 0], "calf_l": [115, 0, 0], "calf_r": [115, 0, 0],
		"neck_01": [26, 0, 0], "head": [14, 0, 0]}, 0.25, 0.0)
	key("squat", 2, {"pelvis": [20, 0, 0], "thigh_l": [115, 8, 0], "thigh_r": [115, 8, 0], "calf_l": [140, 0, 0], "calf_r": [140, 0, 0],
		"spine_01": [15, 0, 0], "spine_02": [15, 0, 0]}, 0.15, 0.0)
	key("ROLL TO THE SIDE (slap)", 3, {"pelvis": [-80, -40, 0], "thigh_l": [70, 8, 0], "thigh_r": [100, 8, 0], "calf_l": [90, 0, 0], "calf_r": [110, 0, 0],
		"spine_01": [0, 0, 0], "spine_02": [0, 0, 0], "spine_03": [0, 0, 0],
		"upperarm_l": [-20, -50, 0], "lowerarm_l": [35, 0, 0], "upperarm_r": [70, -10, 0], "lowerarm_r": [110, 0, 0]}, 0.5, 0.0)
	key("lie on the side", 0, {"pelvis": [-88, -45, 0]}, 0.35, 0.5)
	pin()
	await breakfall_fix(["a", "b", "d"])
	say_falls()
	S.apply_true(B, S.length())
	print("   lying: hip joints y left %.3f right %.3f, hands y left %.3f right %.3f" % [(B.P["thigh_l"] as Vector3).y, (B.P["thigh_r"] as Vector3).y, (B.P["hand_l"] as Vector3).y, (B.P["hand_r"] as Vector3).y])


# WALKS AND STEPS. The walk and run are the committed templates (tools/make_templates.gd, their numbers cited in each file's note);
# a step is a card's "steps" entry (each foot's floor displacement on that card, what the walk template writes)

## walk up to a person and stop in front of him: the walk template (five 0.70 m steps), fighter 2 standing 0.9 m past where the
## hero's head stops (a conversational distance; HEURISTIC, no table)
func t_walk_to_mark() -> void:
	await base("res://templates/walk.json")
	reload()
	S.apply_true(B, S.length())
	var h: Vector3 = B.P["head"]
	print("   walk ends: head at %s, clip %.2f s" % [h, S.length()])
	target(S.cards[0]["pose"], h.x, h.z + 0.9, 6.0)


## a jog: the run template (170 steps/min, 0.78 m steps, 0.10 s flights). MEASURED: its "flights" lift the balls only 4-7 cm off
## the floor in playback, and SpinCheck finds no flight in it (Balance.read keeps a foot down), so the SPIN judge has nothing to judge
## here and the task does not ask for it; the hips' speed is measured instead
func t_run_jog() -> void:
	await base("res://templates/run.json")
	print("   run: %d cards, %.2f s" % [S.cards.size(), S.length()])


## step back out of range: from the guard the rear (right) foot steps back 30 cm, then the front (left) foot follows 30 cm, the guard
## kept; fighter 2 stands in front at the guard's striking range (1.0 m, head to head)
func t_step_back() -> void:
	await base("res://templates/punch.json", 1)
	S.cards[0]["hold"] = 0.3
	key("step back R", 1, {}, 0.3, 0.0, Vector3(0, 0, -0.15), {"steps": {"_r": [0.0, 0.0, -0.3]}, "lift": 0.04})   # the hips go half way with the first foot
	key("step back L", 1, {}, 0.3, 0.4, Vector3(0, 0, -0.3), {"steps": {"_l": [0.0, 0.0, -0.3]}, "lift": 0.04})
	reload()
	S.apply_true(B, 0.0)
	var h0: Vector3 = B.P["head"]
	S.apply_true(B, S.length())
	print("   step back: head %s -> %s" % [h0, B.P["head"]])
	target(S.cards[0]["pose"], h0.x, h0.z + 1.0)


# COMBOS. Two blows on one target: the jab and the cross of the strikes above on one clip, the target placed by the cross and the
# jab's reach fitted to it (its elbow), so both land

## REACH: card ci's (1-based) joint angle on one axis set by bisection in [lo, hi] so hero thing a just touches thing b at t
## (gap -GAP_IN): the arm bent or opened until the blow lands on a target already placed
func reach(ci: int, j: String, axis: int, lo: float, hi: float, a: String, b: String, t: float) -> float:
	var f := func(v: float) -> float:
		Scene.put(B, Moves._flat(S.cards[ci - 1]["pose"]))
		var ang: Vector3 = B.ang[j]
		ang[axis] = v
		B.set_ang(j, ang)
		B.fk()
		S.cards[ci - 1]["pose"] = B.to_dict()
		return gap_at(a, b, t) + GAP_IN
	var flo: float = f.call(lo)
	var fhi: float = f.call(hi)
	if (flo > 0.0) == (fhi > 0.0):
		print("   REACH card %d %s axis %d: no sign change in [%.1f, %.1f] (%.3f, %.3f m)" % [ci, j, axis, lo, hi, flo, fhi])
	for it in 30:
		var mid := (lo + hi) * 0.5
		var fm: float = f.call(mid)
		if (fm > 0.0) == (flo > 0.0):
			lo = mid
			flo = fm
		else:
			hi = mid
	var v := snappedf((lo + hi) * 0.5, 0.01)
	f.call(v)
	return v


## the card of the jab (the strike_jab_chin arm on card 1's guard) inserted at index i
func jab_card(i: int, move: float) -> void:
	Scene.put(B, Moves._flat(S.cards[0]["pose"]))
	for jv in [["upperarm_l", 88, -6, 0], ["lowerarm_l", 4, 0, 0], ["clavicle_l", 0, 22, 0], ["spine_01", 4, 0, -6], ["spine_02", 6, 0, -6],
			["spine_03", 6, 0, -6], ["neck_01", 8, 0, 6]]:
		B.set_ang_safe(jv[0], Vector3(jv[1], jv[2], jv[3]))
	S.cards.insert(i, {"name": "JAB", "pose": B.to_dict(), "move": move, "hold": 0.0})


## a one-two: jab to the head (lands 0.5 s), back to the guard, then the template's load, the cross to the chin (1.03 s) and recovery.
## The target is placed by the cross; the straight jab then went 8 cm INTO the head, so its elbow is bent until it just lands
func t_combo_jab_cross() -> void:
	await base("res://templates/punch.json")
	var g: Dictionary = S.cards[0]["pose"]
	S.cards[0]["hold"] = 0.35
	jab_card(1, 0.15)
	S.cards.insert(2, {"name": "guard", "pose": g.duplicate(true), "move": 0.2, "hold": 0.0})
	var ts := S.times()
	var tj := snappedf(float(ts[1][1]), 1.0 / 30.0)
	var tc := snappedf(float(ts[4][1]) - 1.0 / 30.0, 1.0 / 30.0)
	print("   jab lands %.3f, cross %.3f; cards %s" % [tj, tc, str(S.cards.map(func(c): return c["name"]))])
	print("   cross aimed: upperarm_r side %.2f" % aim(5, "upperarm_r", 1, -20.0, 45.0, "right fist", tc, land_y(g, "chin")))
	target(g, 0.0, 1.0)
	place("right fist", "fighter 2 chin", tc)
	print("   jab aimed: upperarm_l side %.2f" % aim(2, "upperarm_l", 1, -20.0, 45.0, "left fist", tj, land_y(g, "face")))
	print("   jab fitted: lowerarm_l bend %.2f" % reach(2, "lowerarm_l", 0, 0.0, 90.0, "left fist", "fighter 2 head", tj))
	print("   jab gap %.4f, cross gap %.4f" % [gap_at("left fist", "fighter 2 head", tj), gap_at("right fist", "fighter 2 chin", tc)])


## the double jab and cross: jab, back, jab again, back, then the cross (the one-two's cards with a second jab; both jabs fitted
## to the head the same way)
func t_combo_double_jab() -> void:
	await base("res://templates/punch.json")
	var g: Dictionary = S.cards[0]["pose"]
	S.cards[0]["hold"] = 0.35
	jab_card(1, 0.15)
	S.cards.insert(2, {"name": "guard", "pose": g.duplicate(true), "move": 0.2, "hold": 0.0})
	jab_card(3, 0.15)
	S.cards.insert(4, {"name": "guard", "pose": g.duplicate(true), "move": 0.2, "hold": 0.0})
	# the lead foot as it plays the cross (2.8 cm of slide measured without it, over the 2.5 cm bar): held for the whole clip
	S.plants = FootPlant.add(S.plants, {"foot": "foot_l", "t0": 0.0, "t1": S.length()})
	var ts := S.times()
	var tj1 := snappedf(float(ts[1][1]), 1.0 / 30.0)
	var tj2 := snappedf(float(ts[3][1]), 1.0 / 30.0)
	var tc := snappedf(float(ts[6][1]) - 1.0 / 30.0, 1.0 / 30.0)
	print("   jabs land %.3f, %.3f, cross %.3f; cards %s" % [tj1, tj2, tc, str(S.cards.map(func(c): return c["name"]))])
	print("   cross aimed: upperarm_r side %.2f" % aim(7, "upperarm_r", 1, -20.0, 45.0, "right fist", tc, land_y(g, "chin")))
	target(g, 0.0, 1.0)
	place("right fist", "fighter 2 chin", tc)
	for row in [[2, tj1], [4, tj2]]:
		aim(row[0], "upperarm_l", 1, -20.0, 45.0, "left fist", row[1], land_y(g, "face"))
		print("   jab card %d fitted: lowerarm_l bend %.2f" % [row[0], reach(row[0], "lowerarm_l", 0, 0.0, 90.0, "left fist", "fighter 2 head", row[1])])


# TWO FIGHTERS. Fighter 2 is the punch template's attacker (its right cross: tools/make_templates.gd, aimed at the face), facing the hero, placed so
# that the cross would land on the hero's head in the guard (gap -GAP_IN at its contact time): stand still and you are hit

## fighter 2 = the scene at path, facing the hero (yaw 180)
func attacker(path: String) -> void:
	var S2 := Scene.new()
	S2.from_dict(JSON.parse_string(FileAccess.get_file_as_string(path)))
	S2.name = "attacker"
	S.actors = [{"name": "fighter 2", "xf": {"pos": [0.0, 1.5], "yaw": 180.0}, "scene": S2}]


## the hero's guard (2 cards, held) with the attacker placed so his cross lands on the guard's head at its farthest reach -> that time
func guard_vs_cross() -> float:
	# the attacker: the template's cross lands at 1.1 m (a body shot); its arm is raised (upperarm side, as the strikes aim) to the
	# height of the hero's face, then the scene is saved as fighter 2's
	await base("res://templates/punch.json")
	var g: Dictionary = S.cards[0]["pose"]
	print("   attacker's cross aimed at the face: upperarm_r side %.2f" % aim(3, "upperarm_r", 1, -20.0, 60.0, "right fist", 0.8, land_y(g, "face")))
	var atk := "user://bench_attacker.json"
	S.actors = []
	A.write_scene(atk, "fighter 2's cross")
	await base("res://templates/punch.json", 1)
	S.cards[0]["hold"] = 0.45
	key("guard", 1, {}, 0.3, 1.0)
	attacker(atk)
	var S2: Scene = S.actors[0]["scene"]
	var B2 := Body.new()
	B2.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var tf := 0.0
	var zf := -INF
	var f := 0
	while f / 30.0 <= S2.length():
		S2.apply_true(B2, f / 30.0)
		var p := BodyAssert.point(BodyAssert.thing("right fist"), B2, Transform3D.IDENTITY)
		if p.z > zf:
			zf = p.z
			tf = f / 30.0
		f += 1
	S2.apply_true(B2, tf)
	print("   fighter 2's cross is farthest at %.3f s, fist at %s (own space)" % [tf, BodyAssert.point(BodyAssert.thing("right fist"), B2, Transform3D.IDENTITY)])
	place("head", "fighter 2 right fist", tf)
	return tf


## SLIP: the head leaves the cross's line: knees a little bent, the hips dropped 4 cm and shifted 15 cm to the hero's LEFT (+x), the
## spine bent sideways to its stops (spine_01..03 side 7 deg each), arriving 0.05 s before the fist; held, then back to the guard.
## MEASURED: the same slip to the right (-x) still met the fist (-3.1 cm) and put the COM 0.2 cm past the feet; dropping the hips
## 10 cm instead lowered the head INTO the fist (it lands low on the head), so the slip is sideways, not a bob
func t_two_slip() -> void:
	var tf: float = await guard_vs_cross()
	S.cards.pop_back()
	var sl := {"thigh_l": [25, 8, 0], "thigh_r": [25, 8, 0], "calf_l": [35, 0, 0], "calf_r": [35, 0, 0],
		"spine_01": [4, 7, 0], "spine_02": [4, 7, 0], "spine_03": [4, 7, 0], "neck_01": [8, 7, 0]}
	key("SLIP", 1, sl, 0.25, 0.25, Vector3(0.15, -0.04, 0.0))
	key("guard", 1, {}, 0.3, 0.4)
	S.cards[1]["move"] = maxf(0.05, tf - 0.05 - S.cards[0]["hold"])   # the slip arrives 0.05 s before the fist
	# both feet held where they stand: the hips move 12 cm, which pin_cards reads as a step (STEP 0.12 m)
	S.plants = FootPlant.add(S.plants, {"foot": "foot_l", "t0": 0.0, "t1": S.length()})
	S.plants = FootPlant.add(S.plants, {"foot": "foot_r", "t0": 0.0, "t1": S.length()})
	print("   slip: closest the fist comes to the head %.3f m (guard was touching)" % mingap("head", "fighter 2 right fist"))


## the smallest gap between two things over the clip
func mingap(a: String, b: String) -> float:
	var best := INF
	var f := 0
	while f / float(S.fps) <= S.length():
		best = minf(best, gap_at(a, b, f / float(S.fps)))
		f += 1
	return best


## BLOCK: the left forearm raised across the cross's line in front of the face (upperarm_l up and forward, the elbow bent 120), its
## height fitted (upperarm side) so the fist lands on the forearm at 0.8 s
func t_two_block() -> void:
	var tf: float = await guard_vs_cross()
	S.cards.pop_back()
	# the head drawn back 6 cm behind the forearm (the fist, played as cards, does not stop on the arm)
	key("BLOCK", 1, {"upperarm_l": [70, 40, 0], "lowerarm_l": [120, 0, 0], "hand_l": [0, 0, 0], "spine_02": [-5, 0, 0], "spine_03": [-5, 0, 0]}, 0.2, 0.3, Vector3(0, 0, -0.06))
	key("guard", 1, {}, 0.3, 0.4)
	S.cards[1]["move"] = maxf(0.05, tf - 0.08 - S.cards[0]["hold"])
	S.plants = FootPlant.add(S.plants, {"foot": "foot_l", "t0": 0.0, "t1": S.length()})
	S.plants = FootPlant.add(S.plants, {"foot": "foot_r", "t0": 0.0, "t1": S.length()})
	print("   block fitted: upperarm_l bend %.2f" % reach(2, "upperarm_l", 0, 20.0, 110.0, "left forearm", "fighter 2 right fist", tf))
	print("   block: fist to head %.3f m, to forearm at %.3f s %.3f m" % [mingap("head", "fighter 2 right fist"), tf, gap_at("left forearm", "fighter 2 right fist", tf)])
