## THUMBNAIL PICKER (ROADMAP_400 K29): the most READABLE frame of a clip, chosen from the geometry alone (no rendering).
## Every sampled frame (each 1/15 s) is posed on a scratch body and scored from a camera's view (its right and up vectors):
##   HULL  area of the convex hull of the projected joints (head top, hands, balls of the feet included), divided by the body
##         height squared. A pose that spreads into the picture reads; one folded into a column does not. The body height is the
##         sum of the bone lengths pelvis -> head top plus the leg (pose independent, so a raised foot does not change the unit).
##   SEP   limb separation: the smallest screen distance of the two hands and the two feet to the TORSO AXIS (pelvis -> neck),
##         over the height. A hand in front of the chest or a foot behind the standing leg merges with the torso in a silhouette
##         (the animators' silhouette test, Disney "staging" / Thomas & Johnston 1981, ch. Staging), so the smallest one counts.
##   LOA   line of action (scripts/line_of_action.gd, current_line): head centre -> neck -> spine -> pelvis -> support knee -> ankle,
##         projected; its strength is the largest screen distance of those points from the chord head -> ankle, over the height
##         (a straight stick has none; a C or S curve has some).
## Each term is scaled by a reference to 0..1 (REF_*) and the score is the weighted sum (W_*). The picked frame is the maximum;
## frames within TIE of it tie, and the tie goes to the frame closest in time to a KEY CARD (the time a card is reached).
class_name ThumbPick
extends RefCounted

const STEP := 1.0 / 15.0
const REF_HULL := 0.55    # hull / H^2 at which the term is full (a T-pose measures about 0.5, a column about 0.1)
const REF_SEP := 0.25     # H: a hand or foot this far from the torso axis is clearly apart
const REF_LOA := 0.12     # H: a line of action bowed this far off its chord is a strong one
const W_HULL := 0.5
const W_SEP := 0.3
const W_LOA := 0.2
const TIE := 1e-4
const BODY_CHAIN := ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head"]
const HULL_JOINTS := ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head", "clavicle_l", "upperarm_l", "lowerarm_l", "hand_l",
	"clavicle_r", "upperarm_r", "lowerarm_r", "hand_r", "thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r", "ball_r"]


static func _p2(v: Vector3, right: Vector3, up: Vector3) -> Vector2:
	return Vector2(v.dot(right), v.dot(up))


## the body's height unit: bone lengths along the spine and one leg to the head top (does not change when a limb moves)
static func height(B: Body) -> float:
	var h := 0.0
	for i in BODY_CHAIN.size() - 1:
		h += (B.P[BODY_CHAIN[i + 1]] as Vector3).distance_to(B.P[BODY_CHAIN[i]])
	h += (B.E["head"] as Vector3).distance_to(B.P["head"])
	h += (B.P["calf_l"] as Vector3).distance_to(B.P["thigh_l"]) + (B.P["foot_l"] as Vector3).distance_to(B.P["calf_l"]) + 0.08
	return h


static func hull_area(pts: Array) -> float:
	var p: Array = pts.duplicate()
	p.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	if p.size() < 3:
		return 0.0
	var h: Array = []
	for pass_i in 2:
		var start := h.size()
		for q in p:
			while h.size() >= start + 2 and ((h[-1] - h[-2]) as Vector2).cross((q as Vector2) - (h[-2] as Vector2)) <= 0.0:
				h.pop_back()
			h.append(q)
		h.pop_back()
		p.reverse()
	var a := 0.0
	for i in h.size():
		a += (h[i] as Vector2).cross(h[(i + 1) % h.size()])
	return absf(a) * 0.5


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	var u := 0.0 if l2 < 1e-12 else clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * u)


## the score of the pose B is in, seen with the screen axes right / up: {"score", "hull", "sep", "loa"} (the raw terms, in H units)
static func score(B: Body, right: Vector3, up: Vector3) -> Dictionary:
	var H := height(B)
	var pts: Array = []
	for j in HULL_JOINTS:
		pts.append(_p2(B.P[j], right, up))
	for j in ["head", "hand_l", "hand_r", "ball_l", "ball_r"]:
		pts.append(_p2(B.E[j], right, up))
	var hull := hull_area(pts) / (H * H)
	var a := _p2(B.P["pelvis"], right, up)
	var b := _p2(B.P["neck_01"], right, up)
	var sep := INF
	for p in [_p2(B.E["hand_l"], right, up), _p2(B.E["hand_r"], right, up), _p2(B.E["ball_l"], right, up), _p2(B.E["ball_r"], right, up)]:
		sep = minf(sep, _seg_dist(p, a, b))
	sep /= H
	var line: Array = LineOfAction.current_line(B)
	var l2: Array = []
	for v in line:
		l2.append(_p2(v, right, up))
	var c0: Vector2 = l2[0]
	var c1: Vector2 = l2[-1]
	var dev := 0.0
	var cd := c1 - c0
	if cd.length() > 1e-6:
		var nrm := Vector2(-cd.y, cd.x).normalized()
		for q in l2:
			dev = maxf(dev, absf(((q as Vector2) - c0).dot(nrm)))
	var loa := dev / H
	var s := W_HULL * clampf(hull / REF_HULL, 0.0, 1.0) + W_SEP * clampf(sep / REF_SEP, 0.0, 1.0) + W_LOA * clampf(loa / REF_LOA, 0.0, 1.0)
	return {"score": s, "hull": hull, "sep": sep, "loa": loa}


## the best frame of the scene S seen with right / up. B is a scratch body (it is posed). Returns {"t", "frame", "score", "terms",
## "ts", "scores", "tied"}: ts / scores = every sampled time and its score; tied = how many frames tied at the maximum
static func best(S: Scene, B: Body, right: Vector3, up: Vector3, step := STEP) -> Dictionary:
	var L := S.length()
	var n := int(floor(L / step + 1e-6))
	var ts: Array = []
	for k in n + 1:
		ts.append(float(k) * step)
	if L - float(ts[-1]) > 1e-6:
		ts.append(L)
	var scores: Array = []
	var terms: Array = []
	var top := -INF
	for t in ts:
		S.apply(B, t)
		var r := score(B, right, up)
		scores.append(float(r["score"]))
		terms.append(r)
		top = maxf(top, float(r["score"]))
	var keys: Array = []
	var tm: Array = S.times()
	for i in tm.size():
		keys.append(float((tm[i] as Array)[1]))
	var pick := -1
	var pd := INF
	var tied := 0
	for i in ts.size():
		if float(scores[i]) >= top - TIE:
			tied += 1
			var d := INF
			for k in keys:
				d = minf(d, absf(float(ts[i]) - float(k)))
			if d < pd - 1e-9:
				pd = d
				pick = i
	if pick < 0:
		pick = 0
	return {"t": float(ts[pick]), "frame": int(round(float(ts[pick]) * S.fps)), "score": float(scores[pick]), "terms": terms[pick],
		"ts": ts, "scores": scores, "tied": tied}
