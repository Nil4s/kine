class_name WalkStyle
extends RefCounted
## WALK STYLE (Friday plan 141, walk cycles with sliders): three sliders on a built walk, in plain words.
## Speed = how fast the steps go: every card's move and hold, so 200 % is twice as fast (the clip's timing).
## Swagger = the hips sway side to side: each middle card's pelvis tips SWAY_DEG at 100 %, one way on a step and back on the next.
## Bounce = the chest dips and lifts on each step: each middle card's spine_02 bends BOB_DEG at 100 %, the same alternating way.
## Each value is a percent of the clip as it was when the panel opened (100 = as built; 0 = no sway / no bob).
## The first and last cards stay (the clip starts and ends where it did). Nothing here writes the scene: styled() returns the cards.
## The panel and the one undo step live in easy_home.gd. The joints are read on the card as built and clamped by Body.from_dict.

const SPEED_MIN := 50.0     # %
const SPEED_MAX := 200.0    # %
const AMOUNT_MAX := 200.0   # % for Swagger and Bounce (0 = none)
const SWAY_DEG := 3.0       # deg of pelvis side at 100 % Swagger
const BOB_DEG := 2.0        # deg of spine_02 bend at 100 % Bounce


## the cards with the three values applied to a copy of the base cards (the clip as it was). base is never changed
static func styled(base: Array, B: Body, props: Array, speed: float, swagger: float, bounce: float) -> Array:
	var out := base.duplicate(true)
	if out.size() < 2:
		return out
	var kt := 100.0 / clampf(speed, SPEED_MIN, SPEED_MAX)   # 200 % speed: every move and hold half as long
	for i in range(out.size()):
		if i > 0:
			out[i]["move"] = snappedf(maxf(EasyTweak.MIN_MOVE, float(base[i]["move"]) * kt), 0.001)
		out[i]["hold"] = snappedf(float(base[i]["hold"]) * kt, 0.001)
	var keep := B.state()
	for i in range(1, out.size() - 1):
		var d: Dictionary = base[i]["pose"]
		if d.is_empty() or not d.has("joints"):
			continue
		var sign_i := 1.0 if i % 2 == 1 else -1.0   # one step, then the other: the sway and the bob go the other way each step
		var nd := d.duplicate(true)
		var j: Dictionary = nd["joints"]
		if j.has("pelvis"):
			j["pelvis"]["side"] = float(j["pelvis"]["side"]) + sign_i * SWAY_DEG * swagger / 100.0
		if j.has("spine_02"):
			j["spine_02"]["bend"] = float(j["spine_02"]["bend"]) - sign_i * BOB_DEG * bounce / 100.0
		var standing := absf(_floor_shift(B, d)) < EasyTweak.STAND_M   # read on the card as it was
		B.from_dict(nd)
		nd = B.to_dict()   # limits clamped, the joints' cached fields refreshed
		if standing:
			nd = FloorSnap.snapped_pose(B, nd, props)
		out[i]["pose"] = nd
	B.set_state(keep)
	return out


static func _floor_shift(B: Body, d: Dictionary) -> float:
	B.from_dict(d)
	return B.floor_shift()
