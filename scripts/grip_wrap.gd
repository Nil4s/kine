## THE WRAP (round 47, GATES CC1, UPGRADES_300 #338; docs/GRIP_RESEARCH.md). A hand already placed on a handle closes
## its fingers round it the way Buchholz & Armstrong 1992 (J Biomech 25:149, doi 10.1016/0021-9290(92)90272-3) predict
## a power grasp: each finger, joint by joint from the knuckle out, bends until that segment (or one beyond it) touches
## the handle's surface, or stops at its limit. Nothing about a weapon is typed in: the handle is a segment and a radius,
## so a thinner handle simply needs more turn before each segment touches (Lee & Rim 1991; Lee & Jung 2015).
##   gap(segment) = distance(segment axis, handle axis) - finger radius - handle radius   (> 0 = apart, < 0 = inside)
class_name GripWrap
extends RefCounted

const LONG := ["index", "middle", "ring", "pinky"]
const TOUCH := 0.001   # within 1 mm = touching (contacts() treats under 1 mm as touching, not inside)
const STEP := 2.0      # deg per step while closing; the touch is then found by halving inside the last step
const HALVE := 6


## the gap of one finger segment from the handle (m)
static func gap(B: Body, j: String, a: Vector3, b: Vector3, r: float) -> float:
	var c: Array = B.cap(j)
	return Body.seg_seg(c[0], c[1], a, b) - float(B.rad[j]) - r


## the smallest gap of a joint's segment and every segment beyond it on the same finger
static func gap_from(B: Body, chain: Array, k: int, a: Vector3, b: Vector3, r: float) -> float:
	var g := INF
	for i in range(k, chain.size()):
		g = minf(g, gap(B, chain[i], a, b, r))
	return g


## the joints close TOGETHER, not one after another: real grasps are synergies (Gulke 2010, 48 hands round cylinders:
## mean flexion MCP 28, PIP 43, DIP 26 deg), so each step turns every still-free joint by its share of that ratio. When
## a segment touches the handle, it and every joint before it stop (that segment is held); the joints beyond it keep
## closing until their own segments touch or reach their limits (Buchholz & Armstrong 1992's contact rule).
const RATIO := [28.0 / 43.0, 1.0, 26.0 / 43.0]   # MCP : PIP : DIP (thumb: its two joints take the first two)


## close one finger (chain = its joints, knuckle first) round the handle. Returns per joint: [bend, gap of its segment,
## "touch" (its segment or one beyond held it) / "limit" / "inside" (already in the handle with the finger straight)]
static func close_finger(B: Body, chain: Array, a: Vector3, b: Vector3, r: float, settle := true) -> Array:
	for j in chain:
		var v: Vector3 = B.ang[j]
		B.ang[j] = B.clamp_ang(j, Vector3(0.0, v.y, v.z))
	B.fk_some(chain)
	var n := chain.size()
	var state := []   # "" free, "touch", "limit", "inside"
	for k in n:
		state.append("")
	for k in n:
		if gap(B, chain[k], a, b, r) <= TOUCH:
			for q in k + 1:
				if state[q] == "":
					state[q] = "inside"
	var guard := 0
	while state.has("") and guard < 400:
		guard += 1
		var keep := {}
		for k in n:
			keep[chain[k]] = B.ang[chain[k]]
		var moved := false
		for k in n:
			if state[k] != "":
				continue
			var j: String = chain[k]
			var v: Vector3 = B.ang[j]
			var hi: float = (B.lim[j]["bend"] as Vector2).y
			var nv := minf(v.x + STEP * float(RATIO[k]), hi)
			if nv <= v.x + 1e-6:
				state[k] = "limit"
				continue
			B.ang[j] = B.clamp_ang(j, Vector3(nv, v.y, v.z))
			moved = true
		if not moved:
			break
		B.fk_some(chain)
		var first := -1
		for k in n:
			if gap(B, chain[k], a, b, r) <= TOUCH:
				first = k
				break
		if first < 0:
			continue
		# a segment reached the surface inside this step: halve the step back to the touch, then hold it
		var after := {}
		for k in n:
			after[chain[k]] = B.ang[chain[k]]
		var lo := 0.0
		var up := 1.0
		for it in HALVE:
			var mid := (lo + up) * 0.5
			for k in n:
				var j: String = chain[k]
				B.ang[j] = (keep[j] as Vector3).lerp(after[j], mid)
			B.fk_some(chain)
			if gap_from(B, chain, 0, a, b, r) <= TOUCH:
				up = mid
			else:
				lo = mid
		for k in n:
			var j: String = chain[k]
			B.ang[j] = (keep[j] as Vector3).lerp(after[j], up)
		B.fk_some(chain)
		for k in n:
			if gap(B, chain[k], a, b, r) <= TOUCH:
				for q in k + 1:
					if state[q] == "":
						state[q] = "touch"
	if settle:
		_settle(B, chain, a, b, r)
	var out := []
	for k in n:
		var g := gap(B, chain[k], a, b, r)
		out.append([(B.ang[chain[k]] as Vector3).x, g, "touch" if g <= TOUCH + 0.002 else (state[k] if state[k] not in ["", "touch"] else "limit")])
	return out


## SETTLE: after the closure, every segment is drawn onto the surface together (least squares on the gaps; a segment
## inside the handle costs 25 times one off it), so the proximal and middle phalanges lie on the handle as the tip does
## (Buchholz & Armstrong: every segment in contact in a power grasp). Coordinate descent on the bends, 8 -> 1 deg.
static func _settle(B: Body, chain: Array, a: Vector3, b: Vector3, r: float) -> void:
	var cost := func() -> float:
		var c := 0.0
		for j in chain:
			var g := gap(B, j, a, b, r)
			c += g * g if g > 0.0 else 25.0 * g * g
		return c
	var best: float = cost.call()
	for stp in [8.0, 4.0, 2.0, 1.0]:
		var moved := true
		var rounds := 0
		while moved and rounds < 6:
			moved = false
			rounds += 1
			for k in chain.size():
				var j: String = chain[k]
				for sg in [-1.0, 1.0]:
					var v: Vector3 = B.ang[j]
					var nv := B.clamp_ang(j, v + Vector3(sg * stp, 0, 0))
					if nv == v:
						continue
					B.ang[j] = nv
					B.fk_some(chain.slice(k))
					var c: float = cost.call()
					if c < best - 1e-9:
						best = c
						moved = true
					else:
						B.ang[j] = v
						B.fk_some(chain.slice(k))


## GRIP TYPES (round 47, GATES CC2). Napier 1956 (power vs precision) and Buchholz & Armstrong 1992 (transverse vs
## diagonal volar):
##   power     the handle across the palm, every finger segment wrapped onto it (closure + settle), the thumb closing OVER
##             the fingers until its tip meets the handle or the index / middle finger's middle segment
##   diagonal  the handle along the palm's diagonal (a knife, a dagger held forward): the fingers wrap the same way, the
##             thumb lies straight along the handle
##   precision the handle held by the pads: the fingers close until a fingertip touches and stop there (no settle), the
##             thumb closes to meet them
const TYPES := ["power", "diagonal", "precision"]
## the thumb's two flexing joints close together in the ratio of Nick's hand-fitted bat thumb (18 : 32 deg)
const THUMB_RATIO := [18.0 / 32.0, 1.0]


## close every finger of hand h ("hand_r" / "hand_l") round the handle a-b of radius r, the way grip type `kind` holds
## it (TYPES). Returns {finger: close_finger's rows, "thumb": [[bend, gap, how] x2]}.
static func wrap(B: Body, h: String, a: Vector3, b: Vector3, r: float, kind := "power") -> Dictionary:
	var sd := h.right(2)
	var rep := {}
	for f in LONG:
		rep[f] = close_finger(B, [f + "_01" + sd, f + "_02" + sd, f + "_03" + sd], a, b, r, kind != "precision")
	var th := ["thumb_02" + sd, "thumb_03" + sd]
	for j in th:
		var v: Vector3 = B.ang[j]
		B.ang[j] = B.clamp_ang(j, Vector3(0.0, v.y, v.z))
	B.fk_some(th)
	if kind == "diagonal":
		rep["thumb"] = [[0.0, gap(B, th[0], a, b, r), "along"], [0.0, gap(B, th[1], a, b, r), "along"]]
		return rep
	# power and precision: the thumb closes until its tip meets the handle or a finger (power: the middle segments it
	# folds over; precision: the index and middle fingertips it opposes)
	var meet := ["index_02" + sd, "middle_02" + sd] if kind == "power" else ["index_03" + sd, "middle_03" + sd]
	var tip: String = th[1]
	var hit := func() -> float:
		var c: Array = B.cap(tip)
		var g := gap(B, tip, a, b, r)
		for o in meet:
			var d: Array = B.cap(o)
			g = minf(g, Body.seg_seg(c[0], c[1], d[0], d[1]) - float(B.rad[tip]) - float(B.rad[o]))
		return g
	var how := "limit"
	for it in 60:
		var moved := false
		var keep := [B.ang[th[0]], B.ang[th[1]]]
		for k in 2:
			var v: Vector3 = B.ang[th[k]]
			var hi: float = (B.lim[th[k]]["bend"] as Vector2).y
			var nv := minf(v.x + STEP * float(THUMB_RATIO[k]), hi)
			if nv > v.x + 1e-6:
				B.ang[th[k]] = B.clamp_ang(th[k], Vector3(nv, v.y, v.z))
				moved = true
		if not moved:
			break
		B.fk_some(th)
		if float(hit.call()) <= TOUCH:
			# back to the touch inside this step
			var after := [B.ang[th[0]], B.ang[th[1]]]
			var lo := 0.0
			var up := 1.0
			for q in HALVE:
				var mid := (lo + up) * 0.5
				for k in 2:
					B.ang[th[k]] = (keep[k] as Vector3).lerp(after[k], mid)
				B.fk_some(th)
				if float(hit.call()) <= TOUCH:
					up = mid
				else:
					lo = mid
			for k in 2:
				B.ang[th[k]] = (keep[k] as Vector3).lerp(after[k], up)
			B.fk_some(th)
			how = "touch"
			break
	rep["thumb"] = [[(B.ang[th[0]] as Vector3).x, gap(B, th[0], a, b, r), how], [(B.ang[tip] as Vector3).x, float(hit.call()), how]]
	return rep


## the grip type a weapon kind is held with (KINDS "grip"; power when it does not say)
static func type_of(kind: String) -> String:
	return String(Body.KINDS.get(kind, {}).get("grip", "power"))


## the weapon's handle as a segment + radius, round where hand h holds it now (the whole shaft's grippable part)
static func handle_of(B: Body) -> Array:
	return [B.wep_point(0.0), B.wep_point(B.wep_handle), B.wep_r_handle]
