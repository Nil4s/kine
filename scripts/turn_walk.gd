## turn_walk.gd - TURN ON THE SPOT (Easy's "turn around", "turn left", "turn right").
## A real person turns on the spot in 2-4 steps: ONE foot moves per step (it swings round the other, which stays put on
## its mark), the hips lead the turn by about half a step, the knees stay slightly bent, the body never crouches. The
## stance foot is pinned to its ball mark for the whole step, so no foot is ever set down in a new place while the other
## is moving: the planted-to-planted lerp that tipped the old turn's stance foot (scripts/scene.gd) has nothing to tip.
## Each card is built the way scripts/path_walk.gd builds its walk: the donor pose (the stand) turned about the pelvis to
## the card's heading, the hips over the feet, then each foot PLANTED on its mark (ball on the floor, toes on the heading).
## Numbers: a step turns the body 45 deg (a 90 is two steps, a 180 four); a step-turn swings the moving foot on an arc of
## the stance width, so its ball rises SWING_LIFT at most; both feet end where they began, side by side (the stance width
## the donor stands with); the feet square up on their balls after the last step.
## Tests: tests/turn_test.gd (the bars). Build: tools/make_turns.gd.
class_name TurnWalk
extends RefCounted

const DONOR := "res://poses/stand.json"
const STEP_DEG := 45.0        # the turn per step (a step-turn pivots on the stance foot: 45 deg a step is the usual)
const PIVOTS := 2             # double-support cards before each step: the hips lead by LEAD of a step
const LEAD := 0.5
const SWING := 0.7            # the share of a step the moving foot is in the air
const STEP_T := 0.55          # s a step takes
const SWING_LIFT := 0.05      # m: the moving ball's rise at mid swing
const HIP_BACK := 0.115       # m: the hips sit this far behind the feet's midpoint (path_walk's value)
const HOLD_START := 0.4
const HOLD_END := 0.6


static func _fwd(H: float) -> Vector3:
	return Quaternion(Vector3.UP, H) * Vector3(0, 0, 1)


static func _lat(H: float) -> Vector3:
	return Quaternion(Vector3.UP, H) * Vector3(1, 0, 0)


## one card: the donor turned to heading H (pelvis), hips over the feet, both feet planted on their marks
static func _card(B: Body, donor: Dictionary, H: float, pb: Dictionary, fh: Dictionary, name: String, steps: Dictionary,
		move: float, hold: float, arrive: float) -> Dictionary:
	B.from_dict(donor)
	B.turn_world("pelvis", Quaternion(Vector3.UP, H))
	var mid: Vector3 = (pb["_l"] + pb["_r"]) * 0.5
	var o: Vector3 = mid - _fwd(H) * HIP_BACK
	B.offset = Vector3(o.x, B.offset.y, o.z)
	B.fk()
	for sd in ["_l", "_r"]:
		var ball: Vector3 = pb[sd]
		ball.y = (B.p0["ball" + sd] as Vector3).y
		B.plant(sd, ball, float(fh[sd]), true)
	B.fk()
	var card := {"name": name, "pose": B.to_dict(), "move": move, "hold": hold,
		"arrive_s": snappedf(arrive, 0.01), "leave_s": snappedf(arrive + hold, 0.01)}
	if not steps.is_empty():
		card["steps"] = steps
		card["lift"] = SWING_LIFT
	card["walk"] = true
	return card


## the turn: {"ok", "scene" (Scene.to_dict, as make_templates bakes it), "cards", "length_s"}; total_deg > 0 turns left
static func build(nm: String, total_deg: float, B: Body = null) -> Dictionary:
	if B == null:
		B = Body.new()
		B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var donor: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DONOR))
	B.from_dict(donor)
	B.fk()
	var pb := {}
	var fh := {}
	for sd in ["_l", "_r"]:
		var b: Vector3 = B.P["ball" + sd]
		pb[sd] = Vector3(b.x, 0.0, b.z)
		fh[sd] = B.foot_heading(sd)
	var W: float = (pb["_l"] - pb["_r"]).length()   # the stance width the donor stands with (ball to ball)
	var fwd0: Vector3 = B.G["pelvis"] * Vector3(0, 0, 1)
	var H := atan2(fwd0.x, fwd0.z)
	var cards := []
	var arrive := 0.0
	cards.append(_card(B, donor, H, pb, fh, "stand", {}, -1.0, HOLD_START, 0.0))
	arrive = HOLD_START
	var n := maxi(2, int(round(absf(total_deg) / STEP_DEG)))
	var d := deg_to_rad(total_deg / float(n))   # the turn per step (rad, + = left)
	var first := "_r" if total_deg > 0.0 else "_l"   # the foot on the side of the turn moves first (the other pivots)
	for k in range(1, n + 1):
		var m := first if k % 2 == 1 else ("_l" if first == "_r" else "_r")
		var s := "_r" if m == "_l" else "_l"
		for j in PIVOTS:   # the hips lead: the pelvis turns LEAD of a step while both feet stay on their marks
			arrive += (1.0 - SWING) * STEP_T / PIVOTS
			var h_j: float = H + d * LEAD * float(j + 1) / float(PIVOTS)
			cards.append(_card(B, donor, h_j, pb, fh, "pivot %d.%d" % [k, j + 1], {}, (1.0 - SWING) * STEP_T / PIVOTS, 0.0, arrive))
		var H_new := H + d
		var old: Vector3 = pb[m]
		var side := 1.0 if m == "_l" else -1.0
		var newb: Vector3 = (pb[s] as Vector3) + _lat(H_new) * (W * side)
		newb.y = 0.0
		var off := newb - old
		off.y = 0.0
		pb[m] = newb
		fh[m] = H_new
		arrive += SWING * STEP_T
		cards.append(_card(B, donor, H_new, pb, fh, "step %s %d" % ["L" if m == "_l" else "R", k], {m: [off.x, 0.0, off.z]},
			SWING * STEP_T, 0.0, arrive))
		H = H_new
	# square up: both feet pivot on their balls to the final heading, the hips with them
	arrive += 0.5 * STEP_T
	for sd in ["_l", "_r"]:
		fh[sd] = H
	cards.append(_card(B, donor, H, pb, fh, "square", {}, 0.5 * STEP_T, HOLD_END, arrive))
	arrive += HOLD_END
	var S := Scene.new()
	S.name = nm
	for c in cards:
		S.add(c["name"], c["pose"])
		var cd: Dictionary = S.cards[-1]
		cd["move"] = float(c["move"])
		cd["hold"] = float(c["hold"])
		cd["steps"] = c.get("steps", {})
		if c.has("lift"):
			cd["lift"] = float(c["lift"])
		cd["walk"] = true
	var out := S.to_dict(B)
	out["plan"] = "templates/%s (tools/make_turns.gd: scripts/turn_walk.gd, %.0f deg in %d steps)" % [nm, total_deg, n]
	out["note"] = "TURN (%s): %.0f deg on the spot in %d steps, one foot moves per step, the other pivots on its mark; the hips lead." % [nm, total_deg, n]
	return {"ok": true, "scene": out, "cards": cards, "length_s": arrive, "steps": n, "width": W}
