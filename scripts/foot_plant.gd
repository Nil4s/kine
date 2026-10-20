## foot_plant.gd - FOOT PLANTING OVER A TIME RANGE (docs/ROADMAP.md item 8; docs/COMPLAINTS.md: foot sliding is the
## animators' #2 complaint). A PLANT is {"foot": "foot_l" / "foot_r", "t0": s, "t1": s} in Scene.plants (scene file key
## "plants", written only when there is one). Over [t0, t1] the foot's SOLE stays where it was at t0: the ankle's world
## point, the foot's world turn and the ball's (toe joint's) world turn are those of the played pose at t0, held every
## frame. The leg is re-solved with LimbIK.solve (the closed form, the pole taken from the pose at t0, so the knee keeps
## its side); the pelvis is never touched (on flat ground). The pose at t0 is the scene as it plays there with the plants OFF (IK
## pins and cards included), so plants do not read each other.
## TOES (ROADMAP 93): a ground plant whose toes are past the edge of its surface bends them down (toe_bend), the ball joint's
## bend, within its limit; the ball contact stays on the surface.
## GROUND (ROADMAP 93): with a set in the scene, a planted sole stands on the surface under it (ground_ref: a tread, a ramp's
## slope) and the hips drop, never rise, so no ground-planted leg is stretched (_lower_for_reach). With no props, or a plant
## grounded on bare floor, neither runs: the plant is exactly as before.
##
## EDGES: the weight ramps 0 -> 1 (smoothstep) over BLEND frames BEFORE t0 and 1 -> 0 AFTER t1, at the scene's fps. The
## release ramp is OUT frames long, adapted per plant by out_frames (below; BLEND at least). Between the leg's free motion
## and its planted one the joint angles are mixed by that weight (the same mix LimbIK.play uses for IK weight), so
## nothing pops at a range edge.
##
## ORDER in Scene.apply (write it here and in Scene.apply): the cards, layers, breathing, drivers, the IK pass, THEN the
## plants (after the IK pass: a planted foot holds the place it had at t0, over a pin on the same foot), THEN the
## constraints (which still have the last word on what they drive). The plant reference is read first, from a second
## apply at t0 with the plants off, so the pose at t0 is exactly what plays there.
##
## A LEG THAT CANNOT REACH: the closed form stretches the leg toward the pin and the miss stays on the frame. play()
## reports it per plant (the miss, m); scan() lists the frames over the range whose miss is above MISS_BAR. Never hidden.
class_name FootPlant
extends RefCounted

const BLEND := 3          # frames, at the scene's fps, over which a plant eases on before t0 and off after t1 (the least)
const OUT_MAX := 48       # frames: the longest release ramp (out_frames)
const NEAR_S := 0.5       # s either side of t1 over which the scene's own largest foot step is read (out_frames)
const SMOOTH_SLOPE := 1.5 # the smoothstep's steepest slope: its per-frame step is SMOOTH_SLOPE * distance / frames at most
const MISS_BAR := 0.001   # m: a frame whose ankle is more than this from its pin is reported by scan()
const FEET := ["foot_l", "foot_r"]


## the plant list as read from a file: valid entries only (a known foot, t1 > t0), sorted by t0
static func from_file(d: Variant) -> Array:
	var out := []
	if not d is Array:
		return out
	for p in d:
		if not (p is Dictionary and String(p.get("foot", "")) in FEET and p.has("t0") and p.has("t1")):
			continue
		var t0 := float(p["t0"])
		var t1 := float(p["t1"])
		if t1 > t0:
			var q := {"foot": String(p["foot"]), "t0": t0, "t1": t1}
			if bool(p.get("reach", false)):
				q["reach"] = true
			if p.has("dend"):
				q["dend"] = float(p["dend"])
			if p.has("th") and float(p["th"]) > t0 and float(p["th"]) < t1:
				q["th"] = float(p["th"])
				if p.has("tf") and float(p["tf"]) > t0 and float(p["tf"]) < t1:
					q["tf"] = float(p["tf"])
			if p.has("tt") and float(p["tt"]) > t0 and float(p["tt"]) < t1:
				q["tt"] = float(p["tt"])   # R14c: toe pivot, the toe tip is held from tt
			out.append(q)
	out.sort_custom(func(a, b): return float(a["t0"]) < float(b["t0"]))
	return out


## the file form: times to 0.1 ms, in the order kept
static func to_file(plants: Array) -> Array:
	return plants.map(func(p):
		var q := {"foot": String(p["foot"]), "t0": snappedf(float(p["t0"]), 0.0001), "t1": snappedf(float(p["t1"]), 0.0001)}
		if bool(p.get("reach", false)):
			q["reach"] = true
		if p.has("th"):
			q["th"] = snappedf(float(p["th"]), 0.0001)
		if p.has("tf"):
			q["tf"] = snappedf(float(p["tf"]), 0.0001)
		if p.has("dend"):
			q["dend"] = snappedf(float(p["dend"]), 0.0001)
		if p.has("tt"):
			q["tt"] = snappedf(float(p["tt"]), 0.0001)
		return q)


## MIRROR (Scene.MIRROR_SCENE "plants"), on the file form: each plant to its twin foot, the times as they were
static func mirror_file(plants: Array) -> Array:
	return plants.map(func(p): return {"foot": "foot_r" if String(p["foot"]) == "foot_l" else "foot_l", "t0": p["t0"], "t1": p["t1"]})


## ADD a plant: a plant of the same foot that overlaps its range is taken off first (one plant per foot at a time)
static func add(plants: Array, p: Dictionary) -> Array:
	var out := []
	for q in plants:
		if String(q["foot"]) == String(p["foot"]) and float(q["t0"]) < float(p["t1"]) and float(q["t1"]) > float(p["t0"]):
			continue
		out.append(q)
	out.append(p)
	out.sort_custom(func(a, b): return float(a["t0"]) < float(b["t0"]))
	return out


## the plants of a foot covering t (its range, the blend not counted): the list with them taken off
static func remove_at(plants: Array, foot: String, t: float) -> Array:
	var out := []
	for q in plants:
		if String(q["foot"]) == foot and t >= float(q["t0"]) - 1e-6 and t <= float(q["t1"]) + 1e-6:
			continue
		out.append(q)
	return out


## THE RELEASE RAMP (ROADMAP 8 fix). A release while the body moves: the sole is held at its t0 place and the free sole is
## D away at t1, so the blend carries it D over its ramp. Over BLEND frames that pops up to 25 mm a frame. So the ramp is
## made long enough that its step stays within the scene's own largest per-frame foot step near t1:
##   n = ceil(SMOOTH_SLOPE * D / S_max), clamped to [BLEND, OUT_MAX].
## D = the planted sole (heel, ball) at t1 against where it was held at t0 (the larger of the two); S_max = the largest
## per-frame step of either sole (heel, ball, both feet) over NEAR_S either side of t1, read with the plants off. The cap is
## OUT_MAX: a longer ramp would ease a slide the eye reads as the foot sliding, so a D too big for the cap is left (the
## test prints both numbers). The poses are read once per scene state and cached on S (_plant_out), keyed on what they
## depend on.
static func out_frames(S: Scene, B: Body, idx: int) -> int:
	var p: Dictionary = S.plants[idx]
	var sig := hash(var_to_str([S.cards, S.part_keys, S.ik, S.layers, S.fps, S.pin, S.on_floor, String(p["foot"]), float(p["t0"]), float(p["t1"])]))
	var c: Dictionary = S._plant_out.get(idx, {})
	if c.get("sig", 0) == sig:
		return int(c["n"])
	var fps := maxi(S.fps, 1)
	var sd := String(p["foot"]).right(2)
	var t1 := float(p["t1"])
	var nw := int(round(NEAR_S * fps))
	S._plants_off = true
	S.apply(B, ref_time(p))
	var held := [FootRoll.heel_point(B, sd), B.P["ball" + sd]]   # the sole where the plant holds it
	var d := 0.0
	var s_max := 0.0
	var prev := []
	for k in range(-nw, nw + 1):
		S.apply(B, clampf(t1 + float(k) / fps, 0.0, S.length()))
		var now := []
		for s in ["_l", "_r"]:
			for q in [FootRoll.heel_point(B, s), B.P["ball" + s]]:
				now.append(q)
		if k == 0:   # the free sole at t1 (heel, ball of this foot) against the held one
			var base := 0 if sd == "_l" else 2
			d = maxf(d, maxf((now[base] as Vector3).distance_to(held[0]), (now[base + 1] as Vector3).distance_to(held[1])))
		if not prev.is_empty():
			for i in now.size():
				s_max = maxf(s_max, (now[i] as Vector3).distance_to(prev[i]))
		prev = now
	S._plants_off = false
	var n := BLEND
	if s_max > 1e-7 and d > 0.0:
		n = clampi(int(ceil(SMOOTH_SLOPE * d / (0.5 * s_max))), BLEND, OUT_MAX)   # half the free step: the free sole's own motion adds to the ramp's
	S._plant_out[idx] = {"sig": sig, "n": n}
	return n


## the time the plant's sole is read at: t0, or tf (HEEL PIVOT: the sole is flat from tf on, and that is the place it is held)
static func ref_time(p: Dictionary) -> float:
	return float(p.get("tf", p["t0"]))


## the plant's weight at t, 0..1: 1 over [t0, t1], smoothstep over BLEND frames before t0, over p.out (out_frames, BLEND
## if not read yet) frames after t1, 0 further out
static func weight(p: Dictionary, t: float, fps: int) -> float:
	var f := float(maxi(fps, 1))
	var b := float(BLEND) / f
	var bo := float(int(p.get("out", BLEND))) / f
	var t0 := float(p["t0"])
	var t1 := float(p["t1"])
	if t < t0 - b or t > t1 + bo:
		return 0.0
	var u := 1.0
	if t < t0:
		u = clampf((t - (t0 - b)) / b, 0.0, 1.0)
	elif t > t1:
		u = clampf(((t1 + bo) - t) / bo, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


## THE REFERENCE of each plant live at t (weight > 0): the sole as it plays at the plant's t0, read by Scene.apply with the
## plants off. Returns {index: {"P": ankle, "G": foot turn, "Gb": ball turn, "pole": the knee's pole}}. B is left posed
## at the last reference; the caller poses it at t afterwards (Scene.apply does)
static func refs(S: Scene, B: Body, t: float) -> Dictionary:
	var out := {}
	for i in S.plants.size():
		var p: Dictionary = S.plants[i]
		if t > float(p["t1"]) and t <= float(p["t1"]) + float(OUT_MAX) / maxi(S.fps, 1) + 1e-9:
			p["out"] = out_frames(S, B, i)   # the release ramp of this plant (its poses cached on S)
		if weight(p, t, S.fps) <= 0.0:
			continue
		var r: Dictionary = PoseCache.plant_ref(S, B, i)   # the same values, cached while the scene's inputs are unchanged (pose_cache.gd)
		if not S.props.is_empty():
			r = ground_ref(S.solid_props(), r)   # ROADMAP 93: on a surface that is not the floor, the sole goes onto it
		if bool(p.get("reach", false)):
			r = r.duplicate()
			r["reach"] = true   # R14: a video plant's hips drop (never rise) until the leg reaches its pin, on bare floor too
			r = snap_to_floor(r)
		out[i] = r
	return out


## R14c SNAP: a video fit holds a heel strike's sole a few cm above the floor. A video plant's held sole is brought DOWN onto the
## floor (y = 0) when its lowest contact (heel, ball, toe tip) is within SNAP_H of it: the ankle target moves down by that height and
## the leg is solved onto it (LimbIK.solve in play), so the planted foot stands on the ground rather than in the air. A sole already
## below the floor, or higher than SNAP_H (a foot in the air, not a held fit error), is left as it was.
const SNAP_H := 0.04   # m: the most a held sole is snapped down

static func snap_to_floor(r: Dictionary) -> Dictionary:
	if not r.has("BP"):
		return r
	var P: Vector3 = r["P"]
	var G: Quaternion = r["G"]
	var Gb: Quaternion = r["Gb"]
	var low := minf(minf((P - G * Vector3(0, float(r["h"]), 0)).y, ((r["BP"] as Vector3) - Gb * Vector3(0, float(r["rb"]), 0)).y),
		((r["BE"] as Vector3) - Gb * Vector3(0, float(r["re"]), 0)).y)
	if low <= 1e-4 or low > SNAP_H:
		return r
	var q := r.duplicate()
	q["P"] = P - Vector3(0, low, 0)
	q["BP"] = (r["BP"] as Vector3) - Vector3(0, low, 0)   # the ball and toe tip holds (heel-off, toe pivot) read these: they go down with the ankle
	q["BE"] = (r["BE"] as Vector3) - Vector3(0, low, 0)
	return q


## THE GROUND REFERENCE (ROADMAP 93): a planted sole stands on the surface under it (a step's tread, a ramp), not on y = 0.
## The reference's sole (heel = ankle minus its rest height along the foot's own up, the ball, the toe tip) is read where
## the plant starts. On a surface that is not the floor the foot is turned flat onto that surface's normal (about the ankle,
## the heading kept: the sole parallel to the slope), then the whole foot moves so its lowest sole point touches the surface
## under it. The ankle is the leg's target (LimbIK.solve) and the foot's turn the reference's. A plant with no surface under
## it but the floor is returned as it was (byte for byte): no "ground" flag, nothing moved.
static func ground_ref(props: Array, r: Dictionary) -> Dictionary:
	if not r.has("BP"):
		return r
	var P: Vector3 = r["P"]
	var G: Quaternion = r["G"]
	var Gb: Quaternion = r["Gb"]
	var h := float(r["h"])
	var rb := float(r["rb"])
	var re := float(r["re"])
	# the three sole contacts: the heel is the ankle minus its rest height along the foot's up; the ball and the toe tip are
	# their joint points minus their rest heights along the ball's up (at rest each contact is on the floor, as the body's
	# own grounding measures them: Body.foot_sole_low)
	var contacts := [P - G * Vector3(0, h, 0), (r["BP"] as Vector3) - Gb * Vector3(0, rb, 0), (r["BE"] as Vector3) - Gb * Vector3(0, re, 0)]
	# the gate: a sole with a surface other than the floor under it, or a sole off its surface (in the air or in it). A
	# sole on bare floor and touching it is returned as it was, so a plant on bare floor is unchanged
	var off := false
	var lowest := INF
	for q in contacts:
		var g := Props.surface_below(props, q as Vector3)
		if float(g["y"]) != 0.0 or (g["n"] as Vector3) != Vector3.UP:
			off = true   # a surface other than the floor under this contact
		lowest = minf(lowest, (q as Vector3).y - float(g["y"]))
	if absf(lowest) > 0.001:
		off = true   # the lowest contact is in the air or in the floor: the foot is not on its ground
	if not off:
		return r
	var n_cur := G * Vector3.UP   # the sole's normal now (a flat foot: up)
	var n_s: Vector3 = Props.surface_below(props, ((contacts[0] as Vector3) + (contacts[1] as Vector3)) * 0.5)["n"]
	var q_arc := _arc(n_cur, n_s)
	var G2 := (q_arc * G).normalized()
	var Gb2 := (q_arc * Gb).normalized()
	var BP2: Vector3 = P + q_arc * ((r["BP"] as Vector3) - P)
	var BE2: Vector3 = P + q_arc * ((r["BE"] as Vector3) - P)
	var pts := [P - G2 * Vector3(0, h, 0), BP2 - Gb2 * Vector3(0, rb, 0), BE2 - Gb2 * Vector3(0, re, 0)]
	var c := INF
	for q in pts:
		c = minf(c, (q as Vector3).y - float(Props.surface_below(props, q as Vector3)["y"]))
	return {"P": P + Vector3(0, -c, 0), "G": G2, "Gb": Gb2, "pole": r["pole"], "ground": true, "rb": rb, "re": re}


## the shortest turn that takes unit direction a onto b (identity when they are the same)
static func _arc(a: Vector3, b: Vector3) -> Quaternion:
	a = a.normalized()
	b = b.normalized()
	var d := clampf(a.dot(b), -1.0, 1.0)
	if d > 1.0 - 1e-9:
		return Quaternion.IDENTITY
	if d < -1.0 + 1e-9:
		var ax := a.cross(Vector3.RIGHT)
		if ax.length() < 1e-6:
			ax = a.cross(Vector3.BACK)
		return Quaternion(ax.normalized(), PI)
	return Quaternion(a.cross(b).normalized(), acos(d))


## GROUND REACH (ROADMAP 93): a leg planted on a surface must reach its ankle target; the hips DROP (never rise) until no
## ground-planted leg is stretched past LEG_SLACK of its length. Lowering the hips shortens every hip-to-ankle distance (the
## ankles are world points, the hips above them), so the stance legs share the drop: a foot on a step and one on the floor
## below it pull the pelvis down to where both reach. Scaled by the plant's weight, so the drop eases in with the plant.
const LEG_SLACK := 0.995   # the stance leg may reach this fraction of its length (a knee never locks straight)
const REACH_SLACK := 0.98  # R14d: a video plant keeps its leg this fraction of its length at most: the solver misses 3 mm on a leg stretched to 99.5 %
const DROP_STEPS := 24     # rounds of the drop (each lowers the hips by the worst overstretch)
const REACH_SHIFT := 0.05   # m: R14d, a video plant's hips slide sideways toward the held foot by this much at most BEFORE they drop (weight eases it over BLEND)
const REACH_DROP := 0.029   # m: a video plant ("reach") lowers the hips by this much at most; past it the miss shows and reachable() ends the plant

static func _lower_for_reach(B: Body, plants: Array, refs_: Dictionary, t: float, fps: int) -> void:
	var any_ground := false
	var wmax := 0.0
	for i in refs_:
		if bool(refs_[i].get("ground", false)) or bool(refs_[i].get("reach", false)):
			any_ground = true
			wmax = maxf(wmax, weight(plants[i], t, fps))
	if not any_ground or wmax <= 0.0:
		return
	B.fk()
	var cap := 1e9   # the drop a "reach" plant may take (ground plants on a surface are not capped: ROADMAP 93)
	var y0: float = B.offset.y
	var holding := false   # R14c: a plant in its hold (not its release ramp) needs the whole drop: a released one's dend must not starve it
	for i in refs_:
		if t <= float(plants[i]["t1"]):
			holding = true
	for i in refs_:
		if not bool(refs_[i].get("ground", false)):
			var c := REACH_DROP
			if t > float(plants[i]["t1"]) and not holding:
				c = minf(c, float(plants[i].get("dend", c)))   # the release keeps the drop the plant ended on: no pop at t1
			cap = minf(cap, c)
	# R14d: a video plant the leg cannot reach (the locked root follows the tracker's foot, the pin holds the fitted one) first moves the
	# hips HORIZONTALLY toward the worst pin, up to REACH_SHIFT, then the drop below takes what is left. wmax eases it in and out.
	var h0: Vector3 = B.offset
	var any_reach := false
	for i in refs_:
		if bool(refs_[i].get("reach", false)) and not bool(refs_[i].get("ground", false)):
			any_reach = true
	if any_reach:
		for _k in DROP_STEPS:
			# the pull of every leg that is over its reach, summed (two feet pulling opposite ways settle between them)
			var pull := Vector3.ZERO
			for i in refs_:
				if not bool(refs_[i].get("reach", false)):
					continue
				var foot2 := String(plants[i]["foot"])
				var ch2 := LimbIK.chain(B, foot2)
				var reach2 := (B.p0[ch2[1]] as Vector3).distance_to(B.p0[ch2[0]] as Vector3) + (B.p0[foot2] as Vector3).distance_to(B.p0[ch2[1]] as Vector3)
				var d3: Vector3 = (refs_[i]["P"] as Vector3) - (B.P[ch2[0]] as Vector3)
				var o2 := d3.length() - reach2 * REACH_SLACK
				if o2 <= 1e-6:
					continue
				var dh := Vector3(d3.x, 0.0, d3.z)
				pull += dh.normalized() * o2 / clampf(dh.length() / maxf(d3.length(), 1e-6), 0.3, 1.0)
			if pull.length() < 1e-5:
				break
			var room := REACH_SHIFT * wmax - Vector2(B.offset.x - h0.x, B.offset.z - h0.z).length()
			if room <= 1e-6:
				break
			B.offset += pull.normalized() * minf(pull.length() * wmax * 0.5, room)
			B.fk()
	for _k in DROP_STEPS:
		var over := 0.0
		for i in refs_:
			if not (bool(refs_[i].get("ground", false)) or bool(refs_[i].get("reach", false))):
				continue
			var foot := String(plants[i]["foot"])
			var ch := LimbIK.chain(B, foot)
			var reach := (B.p0[ch[1]] as Vector3).distance_to(B.p0[ch[0]] as Vector3) + (B.p0[foot] as Vector3).distance_to(B.p0[ch[1]] as Vector3)
			over = maxf(over, (B.P[ch[0]] as Vector3).distance_to(refs_[i]["P"] as Vector3) - reach * (LEG_SLACK if bool(refs_[i].get("ground", false)) else REACH_SLACK))
		if over <= 1e-6:
			break
		B.offset.y = maxf(B.offset.y - over * wmax, y0 - cap * wmax)
		B.fk()
		if B.offset.y <= y0 - cap * wmax + 1e-9:
			break


## HEEL-OFF (R14): a plant with "th" holds the whole sole until th, then only the BALL (a foot rolling over its toes in the last
## part of a stance: the ankle rises and moves on, so a flat hold cannot reach). From th the ankle target is the ball's place at t0
## plus the played pose's own ankle-from-ball offset, the foot's and the ball's turns are the played ones (the roll is kept), eased in
## over BLEND frames. B is the free pose at t here. Returns refs_ with those plants' P, G, Gb replaced (the rest as they were)
static func _heel_off(B: Body, plants: Array, refs_: Dictionary, t: float, fps: int) -> Dictionary:
	var out := refs_
	for i in refs_:
		var p: Dictionary = plants[i]
		if not p.has("th") or not refs_[i].has("BP"):
			continue
		var f := float(maxi(fps, 1))
		var m := clampf((t - float(p["th"])) * f / float(BLEND) + 0.5, 0.0, 1.0)
		m = m * m * (3.0 - 2.0 * m)
		if m <= 0.0:
			continue
		if out == refs_:
			out = refs_.duplicate()
		var foot := String(p["foot"])
		var ball := "ball" + foot.right(2)
		var r: Dictionary = (refs_[i] as Dictionary).duplicate()
		var tgt: Vector3 = (r["BP"] as Vector3) + ((B.P[foot] as Vector3) - (B.P[ball] as Vector3))
		r["P"] = (r["P"] as Vector3).lerp(tgt, m)
		r["G"] = (r["G"] as Quaternion).slerp(B.G[foot], m)
		r["Gb"] = (r["Gb"] as Quaternion).slerp(B.G[ball], m)
		out[i] = r
	return out


## TOE PIVOT (R14c): a plant with "tt" ends in the toe-off. From tt the foot has rolled up onto its toes: only the TOE TIP is held, the
## ankle target being the toe tip's place at the reference time plus the played pose's own ankle-from-toe-tip offset (the ball hold's
## sibling, one contact further on); the played turns are kept, eased in over BLEND frames about tt. B is the free pose at t here.
static func _toe_off(B: Body, plants: Array, refs_: Dictionary, t: float, fps: int) -> Dictionary:
	var out := refs_
	for i in refs_:
		var p: Dictionary = plants[i]
		if not p.has("tt") or not refs_[i].has("BE"):
			continue
		var f := float(maxi(fps, 1))
		var m := clampf((t - float(p["tt"])) * f / float(BLEND) + 0.5, 0.0, 1.0)
		m = m * m * (3.0 - 2.0 * m)
		if m <= 0.0:
			continue
		if out == refs_:
			out = refs_.duplicate()
		var foot := String(p["foot"])
		var ball := "ball" + foot.right(2)
		var r: Dictionary = (refs_[i] as Dictionary).duplicate()
		var tgt: Vector3 = (r["BE"] as Vector3) + ((B.P[foot] as Vector3) - (B.E[ball] as Vector3))
		r["P"] = (r["P"] as Vector3).lerp(tgt, m)
		r["G"] = (r["G"] as Quaternion).slerp(B.G[foot], m)
		r["Gb"] = (r["Gb"] as Quaternion).slerp(B.G[ball], m)
		out[i] = r
	return out


## HEEL PIVOT (R14b): a plant with "tf" starts at a heel strike, the heel on the floor and the toes still up, so no whole-sole hold
## can pin it (the sole is not flat yet). The sole is read at tf, where it is flat (ref_time). Until tf only the HEEL is held: the
## ankle target is the heel's place at tf plus the played pose's own ankle-from-heel offset, the foot's and the ball's turns are
## the played ones (the foot falls flat about the heel), eased into the flat hold over BLEND frames about tf. The mirror of
## _heel_off. B is the free pose at t here. Returns refs_ with those plants' P, G, Gb replaced (the rest as they were)
static func _heel_pivot(B: Body, plants: Array, refs_: Dictionary, t: float, fps: int) -> Dictionary:
	var out := refs_
	for i in refs_:
		var p: Dictionary = plants[i]
		if not p.has("tf"):
			continue
		var f := float(maxi(fps, 1))
		var m := clampf((t - float(p["tf"])) * f / float(BLEND) + 0.5, 0.0, 1.0)
		m = 1.0 - m * m * (3.0 - 2.0 * m)   # 1 while the foot falls about its heel, 0 once it is flat
		if m <= 0.0:
			continue
		if out == refs_:
			out = refs_.duplicate()
		var foot := String(p["foot"])
		var ball := "ball" + foot.right(2)
		var r: Dictionary = (refs_[i] as Dictionary).duplicate()
		var heel_ref: Vector3 = (r["P"] as Vector3) - (r["G"] as Quaternion) * Vector3(0, (B.p0[foot] as Vector3).y, 0)
		var tgt: Vector3 = heel_ref + ((B.P[foot] as Vector3) - FootRoll.heel_point(B, foot.right(2)))
		r["P"] = (r["P"] as Vector3).lerp(tgt, m)
		r["G"] = (r["G"] as Quaternion).slerp(B.G[foot], m)
		r["Gb"] = (r["Gb"] as Quaternion).slerp(B.G[ball], m)
		out[i] = r
	return out


## THE PLANT PASS (Scene.apply, after the IK pass): each live plant's leg solved onto its reference, mixed with the
## played angles by its weight. Returns {index: {"foot", "w", "miss" (m: the ankle to its pin), "ball_turn" (deg: the
## ball's turn off its pin), "clamped": joints a limit changed, "inline"}}. B.offset is never written (a ground plant lowers it, _lower_for_reach)
static func play(B: Body, plants: Array, refs_: Dictionary, t: float, fps: int, props: Array = []) -> Dictionary:
	var out := {}
	refs_ = _heel_off(B, plants, refs_, t, fps)
	refs_ = _toe_off(B, plants, refs_, t, fps)
	refs_ = _heel_pivot(B, plants, refs_, t, fps)
	_lower_for_reach(B, plants, refs_, t, fps)
	for i in refs_:
		var p: Dictionary = plants[i]
		var w := weight(p, t, fps)
		var foot := String(p["foot"])
		var ball := "ball" + foot.right(2)
		var ref: Dictionary = refs_[i]
		var ground := bool(ref.get("ground", false))   # ROADMAP 93: a sole on a surface that is not the floor
		var joints := LimbIK.chain(B, foot)
		joints.append(ball)
		var was := {}
		for j in joints:
			was[j] = B.ang[j]
		# the leg (hip, knee) is solved with the limits as ever; the foot and the ball are NOT clamped on the floor: a plant is a
		# hold, like a pin, and the subtalar roll (-8..25 deg, ROADMAP 7) cannot take the roll a flat foot needs when the hips move
		# far from it (20 cm sideways asks 26 deg of eversion, the limit is 8), so a clamp left the sole 165 mm and 57 deg off its
		# place. A joint the hold took past its range is listed in "clamped" (never hidden). ROADMAP 93: a sole on a step or a ramp
		# keeps its ankle and ball inside their limits (the residual tilt then shows in the test, never hidden)
		var r := LimbIK.solve(B, foot, ref["P"], ref["pole"])
		B.fk()
		var vf := B.decompose(foot, ((B.G[LimbIK.chain(B, foot)[1]] as Quaternion).inverse() * (ref["G"] as Quaternion)).normalized())
		var of: Vector3 = B.ang[foot]
		while vf.z - of.z > 180.0:
			vf.z -= 360.0
		while vf.z - of.z < -180.0:
			vf.z += 360.0
		if (B.clamp_ang(foot, vf) - vf).length() > 1e-4:
			r["clamped"].append(foot)   # reported whether or not the ground takes it off the limit (a sole on a slope needs its ankle)
		if ground:
			vf = B.clamp_ang(foot, vf)
		B.ang[foot] = vf
		B.fk()
		# the ball (toe joint) keeps its world turn: the sole stays flat where it was at t0
		var vb := B.decompose(ball, ((B.G[foot] as Quaternion).inverse() * (ref["Gb"] as Quaternion)).normalized())
		if (B.clamp_ang(ball, vb) - vb).length() > 1e-4:
			r["clamped"].append(ball)
		if ground:
			vb = B.clamp_ang(ball, vb)
		B.ang[ball] = vb
		B.fk()
		var bent := 0.0
		if ground and not props.is_empty():
			bent = toe_bend(B, ball, props, float(ref["rb"]), float(ref["re"]))   # ROADMAP 93: the toes follow an edge they overhang
		if w < 1.0:
			for j in joints:
				B.ang[j] = (was[j] as Vector3).lerp(B.ang[j], w)
			B.fk()
		var turn := rad_to_deg(((B.G[ball] as Quaternion).inverse() * (ref["Gb"] as Quaternion)).normalized().get_angle())
		out[i] = {"foot": foot, "w": w, "miss": ((B.P[foot] as Vector3) - (ref["P"] as Vector3)).length(),
			"ball_turn": turn, "clamped": r["clamped"], "inline": r["inline"], "toe_bend": bent}
	return out


## TOE BEND (ROADMAP 93): a forefoot whose toes are past the edge of the surface it stands on (the ball on the tread, the toe
## tip over the drop) bends its toes DOWN, the ball joint's bend (Body.lim: negative is toes down), half a degree at a time,
## until the toe tip is on the surface under it, the ball contact would leave its surface (more than TOE_BALL), or the ball's
## limit (-30 deg, data/body_limits.json) stops it. Returns the degrees bent (0 when the toe is on its surface already).
## The ball contact stays where it was (only the toes move); the toe tip is the one the edge takes.
const TOE_STEP := 0.5    # deg per step
const TOE_BALL := 0.003  # m: the ball contact must stay on its surface within this
const TOE_TIP := 0.003   # m: the toe tip is on its surface when it is within this

static func toe_bend(B: Body, ball: String, props: Array, rb: float, re: float) -> float:
	var start: float = (B.ang[ball] as Vector3).x
	for _k in 200:
		var gb: Quaternion = B.G[ball]
		var tc: Vector3 = (B.E[ball] as Vector3) - gb * Vector3(0, re, 0)
		if tc.y - float(Props.surface_below(props, tc)["y"]) <= TOE_TIP:
			break
		var a: Vector3 = B.ang[ball]
		var nxt := B.clamp_ang(ball, a - Vector3(TOE_STEP, 0.0, 0.0))
		if nxt.is_equal_approx(a):
			break   # at the ball's limit
		B.ang[ball] = nxt
		B.fk()
		var bc: Vector3 = (B.P[ball] as Vector3) - (B.G[ball] as Quaternion) * Vector3(0, rb, 0)
		if absf(bc.y - float(Props.surface_below(props, bc)["y"])) > TOE_BALL:
			B.ang[ball] = a   # the ball would leave its surface: the last step is taken back
			B.fk()
			break
	return maxf(0.0, start - (B.ang[ball] as Vector3).x)   # ang is in degrees already


## the sole's floor outline under a planted foot posed on B (heel, ball, toe tip, floor y = 0): a small footprint. [] when
## the foot is not planted at t (weight 0). Used by main.gd to draw it
static func footprint(B: Body, plants: Array, t: float, fps: int) -> Array:
	var out := []
	for p in plants:
		if weight(p, t, fps) <= 0.0:
			continue
		var foot := String(p["foot"])
		var sd := foot.right(2)
		var ball := "ball" + sd
		var pts := [FootRoll.heel_point(B, sd), B.P[ball], B.E[ball]]
		var line := []
		for q in pts:
			line.append(Vector3(q.x, 0.002, q.z))
		out.append({"foot": foot, "w": weight(p, t, fps), "pts": line})
	return out


## THE CHECK over a plant's range [t0, t1] at the scene's fps (B is left posed at the last frame; the caller re-poses):
## {"frames": n, "bad": [[t, miss_m], ...] the frames whose ankle is more than MISS_BAR off its pin, "worst": the largest
## miss (m), "turn_worst": the largest ball turn off its pin (deg)}
static func scan(S: Scene, B: Body, p: Dictionary, step := 0.0) -> Dictionary:
	var dt := step if step > 0.0 else 1.0 / float(maxi(S.fps, 1))
	var idx := S.plants.find(p)
	var t0 := float(p["t0"])
	var t1 := float(p["t1"])
	var n := int(floor((t1 - t0) / dt + 1e-6)) + 1
	var bad := []
	var worst := 0.0
	var turn_worst := 0.0
	for k in n:
		var t := minf(t0 + k * dt, t1)
		S.apply(B, t)
		var r: Dictionary = S.plant_last.get(idx, {})
		if r.is_empty():
			continue
		worst = maxf(worst, float(r["miss"]))
		turn_worst = maxf(turn_worst, float(r["ball_turn"]))
		if float(r["miss"]) > MISS_BAR:
			bad.append([t, float(r["miss"])])
	return {"frames": n, "bad": bad, "worst": worst, "turn_worst": turn_worst}
