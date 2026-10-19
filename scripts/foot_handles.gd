## foot_handles.gd - THE REVERSE-FOOT HANDLES (ROADMAP item 6). When a foot is picked, three handles show on it:
##   HEEL  the sole under the ankle (FootRoll.heel_point)   BALL  the toe joint (B.P["ball"])   TOE TIP  the toe's end (B.E["ball"])
## A press on a handle and a drag UP rolls the foot about THAT point, through FootRoll.apply (the same roll the foot_roll
## value uses, so the rules are FootRoll's: the pivot stays put within 1 mm, the joints go through their limits and a
## clamped joint is made up by the ankle's reach):
##   heel: drag up rocks the foot back on the heel, toes up (roll < 0)
##   ball: drag up raises the heel, the toes stay flat (0 < roll <= FootRoll.BREAK, the toe joint extends)
##   tip:  drag up lifts the foot onto the toe tip (roll > FootRoll.BREAK)
## Mouse to roll: DEG_PER_PX degrees per pixel of up-drag, measured from the press. Every move restores the pose the drag
## started from, then applies the roll for the total drag, so the roll never compounds. A release keys the leg and the
## toe joint at the playhead (the chain of LimbIK.chain + the ball, as a part drag keys with K); main.gd owns the undo step.
##
## KNOWN: the tip handle is a roll ABOVE the break, and FootRoll puts the pivot on the toe tip only there. So from a flat
## foot the first pixels of an up-drag on the tip lift the foot through the break (the heel comes up 55 deg about the
## ball, then the rest about the tip). That is what "up on the tip" is; it is not hidden.
class_name FootHandles
extends RefCounted

const KINDS := ["heel", "ball", "tip"]
const DEG_PER_PX := 0.5     # deg of roll per pixel of up-drag
const MAX_HEEL := 80.0      # deg: the heel roll stops here (the joints stop it sooner)
const MAX_TIP := 60.0       # deg beyond the break: the tip roll stops here
const PICK_PX := 12.0       # px: a press this close to a handle's point takes it
const SIZE := 0.026         # m: the half edge of a handle's cross
const COLS := {"heel": Color(0.35, 0.65, 1.0), "ball": Color(1.0, 0.8, 0.25), "tip": Color(1.0, 0.45, 0.35)}


## the world point a handle pivots about on the foot of side sd (the pose as it stands)
static func pivot(B: Body, sd: String, kind: String) -> Vector3:
	match kind:
		"heel":
			return FootRoll.heel_point(B, sd)
		"ball":
			return B.P["ball" + sd]
	return B.E["ball" + sd]


## the handle points as they stand: {kind: Vector3}
static func points(B: Body, sd: String) -> Dictionary:
	var out := {}
	for k in KINDS:
		out[k] = pivot(B, sd, k)
	return out


## the roll (deg) a handle's drag gives for `up` px of up-drag (down or none: the start). Zero is "no change".
static func roll_for(kind: String, up: float) -> float:
	var d := maxf(up, 0.0) * DEG_PER_PX
	match kind:
		"heel":
			return -minf(d, MAX_HEEL)
		"ball":
			return minf(d, FootRoll.BREAK)
	return FootRoll.BREAK + 0.5 + minf(d, MAX_TIP)   # past the break (FootRoll: the pivot is the tip there)


## the foot's pose the drag starts from: every joint's angle and the body's offset (restore() puts them back)
static func snapshot(B: Body) -> Dictionary:
	return {"ang": B.ang.duplicate(), "offset": B.offset}


static func restore(B: Body, start: Dictionary) -> void:
	for j in start["ang"]:
		B.ang[j] = start["ang"][j]
	B.offset = start["offset"]
	B.fk()


## the joints a roll changes and a key holds: the leg (thigh, calf, ankle) and the toe joint
static func keys_of(B: Body, sd: String) -> Array:
	var out := LimbIK.chain(B, "foot" + sd)
	out.append("ball" + sd)
	return out


## THE DRAG: the start pose restored, then the roll for `up` px applied about the handle's pivot. Returns FootRoll.apply's
## report ({pivot, err, ankle, toe, miss}) with "roll" (deg, what was reached), "asked" (deg, what the mouse asked) and
## "stopped" added. A roll the leg cannot hold (an ankle at its limit, a straight leg) is cut back to the largest roll
## whose pivot error is within TOL, by bisection: the foot stops where it can no longer turn about that point, and says so.
const TOL := 0.0008   # m: the pivot error a drag may keep (the bar is 1 mm)
const BISECT := 14


static func _at(B: Body, sd: String, kind: String, start: Dictionary, roll: float) -> Dictionary:
	restore(B, start)
	var r := FootRoll.apply(B, sd, roll)
	if r.is_empty():   # roll 0: nothing touched
		return {"err": 0.0, "miss": 0.0, "pivot": pivot(B, sd, kind)}
	return r


## the smallest roll a handle's kind can have (its branch of FootRoll: heel below 0, ball 0..BREAK, tip above BREAK)
static func _min_roll(kind: String) -> float:
	match kind:
		"heel":
			return -0.5
		"ball":
			return 0.5
	return FootRoll.BREAK + 0.5


static func drag(B: Body, sd: String, kind: String, start: Dictionary, up: float) -> Dictionary:
	var want := roll_for(kind, up)
	var r := _at(B, sd, kind, start, want)
	var roll := want
	if float(r["err"]) > TOL and want != 0.0:
		var lo := _min_roll(kind)
		var a := 0.0
		var b := 1.0
		for i in BISECT:
			var f := (a + b) * 0.5
			if float(_at(B, sd, kind, start, lo + f * (want - lo))["err"]) <= TOL:
				a = f
			else:
				b = f
		roll = lo + a * (want - lo)
		r = _at(B, sd, kind, start, roll)
	r["roll"] = roll
	r["asked"] = want
	r["stopped"] = absf(roll - want) > 0.05
	return r


## the handle under a press at `mp`: its kind, or "" (the nearest point within PICK_PX, in front of the camera)
static func hit(cam: Camera3D, mp: Vector2, B: Body, sd: String) -> String:
	var best := ""
	var best_d := PICK_PX
	var pts := points(B, sd)
	for k in KINDS:
		var p: Vector3 = pts[k]
		if cam.is_position_behind(p):
			continue
		var d := cam.unproject_position(p).distance_to(mp)
		if d <= best_d:
			best_d = d
			best = k
	return best


## the handles drawn as small 3-axis crosses into `im` (lines); `active` (a kind, or "") is drawn bright
static func draw(im: ImmediateMesh, B: Body, sd: String, active: String) -> void:
	var pts := points(B, sd)
	for k in KINDS:
		var p: Vector3 = pts[k]
		var c: Color = COLS[k]
		c.a = 1.0 if k == active else 0.7
		var s := SIZE * (1.4 if k == active else 1.0)
		im.surface_begin(Mesh.PRIMITIVE_LINES, Overlays._mat())
		im.surface_set_color(c)
		for ax in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
			im.surface_add_vertex(p - ax * s)
			im.surface_add_vertex(p + ax * s)
		im.surface_end()
