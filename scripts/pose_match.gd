## POSE MATCHING ON CLIP TRANSITIONS (ROADMAP 84). When clip B follows clip A on the timeline, B's start is chosen and aligned
## so the body does not pop at the seam. The maths of playback is in scripts/clips.gd (match, align, yaw_sign); this file
## chooses the match:
##   1 START FRAME: the grid frame (1/60 s) of B's source within its first WINDOW s whose pose is closest to A's pose at the
##     seam. distance = sum_j m_j |angle difference_j| / sum_j m_j over the joints B drives (m_j = Balance.MASS, a joint not
##     listed weighs MASS_DEFAULT; the pelvis's twist is left out: step 2 turns it), + HEIGHT_W x |hips height difference| (m).
##     Ties go to the earlier frame. A's pose is the scene's own pose at the seam with B muted and A held into it.
##   2 ROOT: B's walk is moved on the floor and turned so its hips at the chosen frame sit at A's hips (x, z), and its pelvis
##     twist is A's (yaw). The match stores lt0, pa, pb, yaw (clips.gd match_norm).
##   3 BLEND: B's blend in (bin) is at least BLEND s, and A holds its last pose into the seam: A's blend out is set to 0 and
##     its extrapolation to hold_forward, so B's weight rises from A's last pose rather than from the cards.
## One undo step (clips_ui.match_pose). A clip with no match plays exactly as before.
class_name PoseMatch
extends RefCounted

const WINDOW := 0.5          # s: B's first part searched for its start frame (ROADMAP 84: "within its first 0.5 s")
const FRAME := 1.0 / 60.0    # s: the search grid
const BLEND := 0.2           # s: the default blend in across the seam
const HEIGHT_W := 100.0      # deg per metre of hips height difference (1 cm = 1 deg)
const MASS_DEFAULT := 0.5    # kg: a joint Balance.MASS does not list


static func weight(j: String) -> float:
	return float(Balance.MASS.get(j, MASS_DEFAULT))


## the pose distance between target A and candidate Q on the joints B drives (see the header); root = B moves the hips
static func distance(A: Body, Q: Body, joints: Array, root: bool) -> float:
	var s := 0.0
	var tot := 0.0
	for j in joints:
		if not A.ang.has(j) or not Q.ang.has(j):
			continue
		var d: Vector3 = Scene._d(A.ang[j], Q.ang[j], j)
		if j == "pelvis":
			d.z = 0.0   # the twist is the heading: the root step turns it, so it is not a pose difference
		var m := weight(j)
		s += m * d.length()
		tot += m
	var out := s / tot if tot > 0.0 else 0.0
	if root:
		out += HEIGHT_W * absf(Q.offset.y - A.offset.y)
	return out


static func fresh_body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.fk()
	return b


## the grid frame of source e (mirrored if asked) closest to target: {"lt": s, "d": distance}. Brute force over the grid
static func search(e: Dictionary, mirror: bool, target: Body, joints: Array, root: bool) -> Dictionary:
	var Q := fresh_body()
	var best := {"lt": 0.0, "d": INF}
	var n := int(floor(minf(WINDOW, float(e["len"])) / FRAME + 1e-9))
	for i in range(n + 1):
		var lt := minf(i * FRAME, float(e["len"]))
		Clips._pose_src(e, lt, mirror, Q)
		var d := distance(target, Q, joints, root)
		if d < float(best["d"]):
			best = {"lt": lt, "d": d}
	return best


## the seconds a clip's strip ends at (its source's length from the source file); -INF when the source cannot be read
static func end_of(c: Dictionary) -> float:
	var e := Clips.source(String(c["src"]))
	if e.is_empty():
		return -INF
	return float(c["start"]) + Clips.length_of(c, float(e["len"]))


## the match for clip k of scene S. {"err": why} when it cannot be made (the reason names the next step), else
## {"A": index of the clip before, "A2": that clip held into the seam, "B2": clip k matched, "d", "lt0", "yaw"}
static func plan(S: Scene, k: int) -> Dictionary:
	var B: Dictionary = S.clips[k]
	if B["type"] != "replace":
		return {"err": "NOT MATCHED: a matched clip replaces the pose (blend: replace); an add clip has no seam to match. Edit the clip to replace"}
	var eB := Clips.source(String(B["src"]))
	if eB.is_empty():
		return {"err": "NOT MATCHED: %s cannot be read as a pose or move" % B["src"]}
	var s0 := float(B["start"])
	var ia := -1
	var ea := -INF
	for j in S.clips.size():
		if j == k or bool((S.clips[j] as Dictionary).get("mute", false)):
			continue
		var ej := end_of(S.clips[j])
		if ej <= s0 + FRAME * 0.5 and ej > ea:
			ea = ej
			ia = j
	if ia < 0:
		return {"err": "NOT MATCHED: no clip ends at or before %.2f s: place the clip to match after the one it follows, then match it" % s0}
	var A: Dictionary = S.clips[ia]
	var A2 := A.duplicate(true)
	A2["bout"] = 0.0   # A holds into the seam: no fade out under B
	if A2["extra"] == "nothing":
		A2["extra"] = "hold_forward"
	# A's pose at the seam: the scene with B muted and A held (a copy of the clip list, put back at once)
	var Bm := B.duplicate(true)
	Bm["mute"] = true
	var mod: Array = S.clips.duplicate(true)
	mod[ia] = A2
	mod[k] = Bm
	var saved: Array = S.clips
	S.clips = mod
	var Tb := fresh_body()
	S.apply(Tb, s0)
	S.clips = saved
	var mirror := bool(B.get("mirror", false))
	var joints := Clips.mask_joints(String(B["mask"]))
	var root := Clips.mask_root(String(B["mask"]))
	var best := search(eB, mirror, Tb, joints, root)
	var lt0 := snappedf(float(best["lt"]), 0.0001)
	var Q := fresh_body()
	Clips._pose_src(eB, lt0, mirror, Q)
	var mt := Clips.match_norm({"lt0": lt0, "pa": [Tb.offset.x, Tb.offset.z], "pb": [Q.offset.x, Q.offset.z],
		"yaw": wrapf(float(Tb.ang["pelvis"].z) - float(Q.ang["pelvis"].z), -180.0, 180.0)})
	var B2 := B.duplicate(true)
	B2["match"] = mt
	B2["bin"] = maxf(float(B["bin"]), BLEND)
	return {"A": ia, "A2": A2, "B2": Clips.clean(B2), "d": float(best["d"]), "lt0": lt0, "yaw": float(mt["yaw"])}
