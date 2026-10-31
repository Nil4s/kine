class_name ClipStyle
extends RefCounted
## CLIP STYLE (Friday plan 142): one slider, realistic <-> cartoon, on ANY clip (the cards in Scene.cards: a built move, a
## copied video, an imported file, all the same cards). k = 0.5 .. 2.0, 1.0 = the clip as it is.
## Every joint's bend, side and twist moves from the clip's MEAN pose (its average over the cards) by k of its own distance,
## so a swinging arm's range of motion (largest minus smallest value over the clip) is exactly k times as wide (until a joint
## limit clamps it: Body.from_dict does). Timing is never touched, so the clip is exactly as long as it was.
## FEET: a card whose sole stands on the floor is put back on it (FloorSnap's rule: the root moves, only in height), then each
## foot that was planted on that card is IK-solved back to the world place, heading and flatness it had (Body.plant: the leg
## alone; if the hip is too high to reach it, the hips drop a little and it is solved again, never rise). The root's walk
## (offset x and z) is not scaled. Cards in the air keep their height.
## k = 1.0 hands back an exact copy (no rounding, nothing re-solved). Nothing here writes the scene: styled() returns the cards.
## The slider, the one undo step per drag and the say line live in easy_home.gd.

const K_MIN := 0.5
const K_MAX := 2.0
const STAND_M := 0.01      # m: a card whose lowest sole is this close to the floor is standing on it (EasyTweak.STAND_M)
const MISS_OK := 0.002     # m: a planted foot closer than this to its place needs no hip drop
const DROP_STEP := 0.01    # m: one hip drop
const DROP_TRIES := 8


## the cards with the style applied to a copy of the base cards (the clip as it was). base is never changed
static func styled(base: Array, B: Body, props: Array, k: float) -> Array:
	var out := base.duplicate(true)
	k = clampf(k, K_MIN, K_MAX)
	if out.size() < 1 or absf(k - 1.0) < 1e-6:
		return out
	var mean := mean_pose(base)
	if mean.is_empty():
		return out
	var keep := B.state()
	var keep_props = B.props
	B.props = props
	for i in range(out.size()):
		var d: Dictionary = base[i]["pose"]
		if d.is_empty() or not d.has("joints"):
			continue
		B.from_dict(d)
		var standing := absf(B.floor_shift()) < STAND_M   # read on the card as it was
		var feet := []   # [side, ball place, heading, flat?] for each planted foot
		if standing:
			for sd in ["_l", "_r"]:
				var fs: Array = B.foot_state(sd)
				if bool(fs[2]):
					feet.append([sd, fs[0], float(fs[1]), bool(fs[3])])
		var nd := d.duplicate(true)
		for j in nd["joints"]:
			if not mean.has(j):
				continue
			var x: Dictionary = nd["joints"][j]
			for ax in ["bend", "side", "twist"]:
				if x.has(ax) and mean[j].has(ax):
					x[ax] = _mix(float(mean[j][ax]), float(x[ax]), k)
		B.from_dict(nd)   # joint limits clamp here
		if standing:
			B.offset.y -= B.floor_shift()
			B.fk()
			_plant_feet(B, feet)
		out[i]["pose"] = B.to_dict()   # the joints' cached fields refreshed
	B.props = keep_props
	B.set_state(keep)
	return out


## the legs solved back onto the planted feet's places; when a leg cannot reach, the hips drop DROP_STEP and it is solved again
static func _plant_feet(B: Body, feet: Array) -> void:
	if feet.is_empty():
		return
	for t in DROP_TRIES:
		var worst := 0.0
		for f in feet:
			worst = maxf(worst, B.plant(f[0], f[1], f[2], f[3]))
		if worst <= MISS_OK:
			return
		B.offset.y -= DROP_STEP
		B.fk()
	for f in feet:
		B.plant(f[0], f[1], f[2], f[3])


## the clip's mean pose: {joint: {"bend", "side", "twist": the average over the cards that have the joint}}
static func mean_pose(cards: Array) -> Dictionary:
	var sum := {}
	var n := {}
	for c in cards:
		var d: Dictionary = c["pose"]
		if d.is_empty() or not d.has("joints"):
			continue
		for j in d["joints"]:
			var x: Dictionary = d["joints"][j]
			if not sum.has(j):
				sum[j] = {"bend": 0.0, "side": 0.0, "twist": 0.0}
				n[j] = 0
			for ax in ["bend", "side", "twist"]:
				sum[j][ax] += float(x.get(ax, 0.0))
			n[j] += 1
	for j in sum:
		for ax in ["bend", "side", "twist"]:
			sum[j][ax] = float(sum[j][ax]) / float(n[j])
	return sum


static func _mix(mean: float, v: float, k: float) -> float:
	return mean + k * (v - mean)
