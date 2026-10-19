## DRAG ANY PART (ROADMAP 41): a plain left drag on a body part does the natural thing, with no axis or mode to choose.
## The press grabs a HANDLE: the point of the part's capsule under the mouse (fraction t from the joint to its end).
## Each move then pulls that handle toward the mouse IN THE VIEW PLANE (the plane through the handle, square to the camera;
## the part keeps its length from its joint, so it swings toward the mouse rather than stretching to it):
##   limbs (arms, legs, collarbones)  swing from their parent joint, the handle landing on the mouse ray (view plane)
##   head / neck                      LOOK: the neck takes 40 % of the turn, the head the rest
##   spine / chest                    BEND: the turn is spread evenly over the three vertebrae
##   pelvis                           MOVE the body; both feet stay where they were (leg IK; the move stops where a leg is straight)
##   hands / feet                     the existing IK reach (main.gd); this class is not used for them
## Every turn goes through Body.turn_world -> set_ang_safe, so joint limits and body contacts still stop it.
class_name PartDrag
extends RefCounted

const NECK_SHARE := 0.4        # the neck's part of a look turn (the head takes the rest)
const SPINE := ["spine_01", "spine_02", "spine_03"]
const FEET := ["foot_l", "foot_r"]
const RESID := 0.0003         # m: the handle is "on the ray" within 0.3 mm; the rounds stop there
const ROUNDS := 6              # a hinge cannot take the whole turn in one go; a few rounds close the rest


## the press: the handle on the part's capsule under the ray. Returns {part, t, plane_d, feet, ...}
static func begin(B: Body, part: String, ray_o: Vector3, ray_d: Vector3) -> Dictionary:
	var a: Vector3 = B.P[part]
	var b: Vector3 = B.E[part]
	# the point on the part's own joint-to-end line nearest the ray, kept 15 % inside the ends
	var u := b - a
	var w := ray_o - a
	var den := ray_d.dot(ray_d) * u.dot(u) - ray_d.dot(u) * ray_d.dot(u)
	var t := 0.5
	if den > 1e-9:
		t = (ray_d.dot(ray_d) * u.dot(w) - ray_d.dot(u) * ray_d.dot(w)) / den
	t = clampf(t, 0.15, 0.85)
	var d := {"part": part, "t": t}
	var h := a + u * t
	d["plane_n"] = ray_d
	d["plane_p"] = h
	var den0 := ray_d.dot(ray_d)
	d["off"] = (ray_o + ray_d * ((h - ray_o).dot(ray_d) / den0)) - h   # the press point vs the handle: no jump on the first move
	if part == "pelvis":
		d["feet"] = {}
		for f in FEET:
			d["feet"][f] = {"p": B.P[f], "g": B.G[f]}
	return d


static func handle(B: Body, d: Dictionary) -> Vector3:
	var a: Vector3 = B.P[d["part"]]
	return a + (B.E[d["part"]] - a) * float(d["t"])


## which kind of drag this part gets
static func kind(part: String) -> String:
	if part == "head" or part == "neck_01":
		return "look"
	if part in SPINE:
		return "bend"
	if part == "pelvis":
		return "move"
	return "swing"


## the mouse in the plane through h square to the view, less the grab offset: where the handle is being pulled to
static func cursor(d: Dictionary, h: Vector3, o: Vector3, dir: Vector3) -> Vector3:
	var n: Vector3 = d["plane_n"]
	var den := dir.dot(n)
	if absf(den) < 1e-6:
		return h
	return o + dir * ((h - o).dot(n) / den) - (d["off"] as Vector3)


## turn joint j (about pivot, its own joint) so the handle hf swings toward the mouse; share = how much of the turn it
## takes. The goal is the cursor's DIRECTION from the pivot at the handle's own length. Returns how far the handle was
## from its goal before the turn (m). A turn the body stops (a limit, a contact) leaves its reason in d["stop"]
static func _turn(B: Body, d: Dictionary, j: String, pivot: Vector3, hf: Callable, o: Vector3, dir: Vector3, share: float) -> float:
	var h: Vector3 = hf.call()
	var r := (h - pivot).length()
	if r < 1e-4:
		return 0.0
	var q := cursor(d, h, o, dir) - pivot
	if q.length() < 1e-4:
		return 0.0
	var goal := pivot + q.normalized() * r
	var resid := h.distance_to(goal)
	if resid < RESID:
		return resid   # there already: turning again would only add the drift a shortest-arc turn leaves in the twist
	var r1 := (h - pivot).normalized()
	var r2 := q.normalized()
	var ax := r1.cross(r2)
	if ax.length() < 1e-9:
		return resid
	B.last_stop = {}
	B.turn_world(j, Quaternion(ax.normalized(), r1.angle_to(r2) * share))
	if not B.last_stop.is_empty():
		d["stop"] = B.last_stop   # why it stopped short (a limit, a contact): the status line says it
	return resid


## one mouse move: the handle follows the ray (o, dir). The caller refreshes
static func move(B: Body, d: Dictionary, o: Vector3, dir: Vector3, after := Callable()) -> void:
	var part: String = d["part"]
	B.last_stop = {}
	match kind(part):
		"swing":
			var hf := func(): return handle(B, d)
			for i in ROUNDS:
				d["stop"] = {}
				var res := _turn(B, d, part, B.P[part], hf, o, dir, 1.0)
				if after.is_valid():
					after.call()   # an upper arm brings its collarbone along: the next round puts the handle back on the ray
				elif res < RESID:
					break
			if after.is_valid():
				_turn(B, d, part, B.P[part], hf, o, dir, 1.0)   # the last follow moved the handle: one more turn
		"look":
			var hf := func(): return _head_handle(B, d)
			for i in ROUNDS:
				d["stop"] = {}
				_turn(B, d, "neck_01", B.P["neck_01"], hf, o, dir, NECK_SHARE)
				if _turn(B, d, "head", B.P["head"], hf, o, dir, 1.0) < RESID:
					break
		"bend":
			var hf := func(): return handle(B, d)
			for i in ROUNDS:
				d["stop"] = {}
				var res := 0.0
				for k in SPINE.size():
					res = _turn(B, d, SPINE[k], B.P["spine_01"], hf, o, dir, 1.0 / float(SPINE.size() - k))
				if res < RESID:
					break
		"move":
			_move_body(B, d, o, dir)
	if d.has("stop") and not (d["stop"] as Dictionary).is_empty():
		B.last_stop = d["stop"]


static func _head_handle(B: Body, d: Dictionary) -> Vector3:
	if d["part"] == "head":
		return handle(B, d)
	return B.E["head"]   # a neck drag aims the head's far end


## pelvis: the handle goes to the ray's point in the plane it was grabbed in; the feet are put back (position and
## orientation). If a leg cannot reach, the move is cut back (bisection) to the most that keeps every foot within 0.5 mm
static func _move_body(B: Body, d: Dictionary, o: Vector3, dir: Vector3) -> void:
	var n: Vector3 = d["plane_n"]
	var den := dir.dot(n)
	if absf(den) < 1e-6:
		return
	var hit := o + dir * (((d["plane_p"] as Vector3) - o).dot(n) / den)
	var want := hit - (d["off"] as Vector3) - handle(B, d)
	var base: Vector3 = B.offset
	var ang0 := B.ang.duplicate()
	var lo := 0.0
	var hi := 1.0
	var best := 0.0
	if _try(B, d, base, ang0, want, 1.0):
		best = 1.0
	else:
		for i in 10:
			var m := (lo + hi) * 0.5
			if _try(B, d, base, ang0, want, m):
				lo = m
				best = m
			else:
				hi = m
	_try(B, d, base, ang0, want, best)
	d["plane_p"] = (d["plane_p"] as Vector3) if best >= 1.0 else handle(B, d)


## offset the body by want*f from `base`, put both feet back; true if every foot is within 0.5 mm and its orientation held
static func _try(B: Body, d: Dictionary, base: Vector3, ang0: Dictionary, want: Vector3, f: float) -> bool:
	for j in ang0:
		B.ang[j] = ang0[j]
	B.offset = base + want * f
	B.fk()
	var worst := 0.0
	for fl in FEET:
		var st: Dictionary = d["feet"][fl]
		B.reach(fl, st["p"])
		# the foot keeps its world turn: its own angles from the shin's turn now
		var gc: Quaternion = B.G[B.parent[fl]]
		var a_new := gc.inverse() * (st["g"] as Quaternion)
		var v := B.decompose(fl, a_new.normalized())
		var old: Vector3 = B.ang[fl]
		while v.z - old.z > 180.0:
			v.z -= 360.0
		while v.z - old.z < -180.0:
			v.z += 360.0
		B.set_ang(fl, v)
		worst = maxf(worst, ((B.P[fl] as Vector3) - (st["p"] as Vector3)).length())
	return worst < 0.0005
