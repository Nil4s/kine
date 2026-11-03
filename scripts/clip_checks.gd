## CLIP IMPORT CHECKS (C04; complaints #266 A-pose vs T-pose, #587/#594 proportion + size warning, #7 stay in place).
## Pure functions. ClipChecks.analyze(src, mapping, B, rt) reads the source rig's rest next to Kine's and returns words for the
## status line; nothing here changes an import. ClipChecks.strip_travel(S) is the opt-in per-clip "stay in place".
## The A-pose "fix" is AnimImport.retarget's rest difference (roff): each bone is turned from the file's rest to Kine's, so the
## arms stay right whatever pose the rig was saved in. This file says so, and names the pose.
class_name ClipChecks

const ARM_T_DEG := 15.0       # an arm rest within this of Kine's counts as a T-pose
const ARM_DOWN_DEG := 60.0    # past this the arms hang at the torso
const SIZE_LO := 0.75         # Kine leg / file leg outside [LO, HI]: warn
const SIZE_HI := 1.33
const PROP_DEV := 0.25        # arm/leg or torso/leg differing by more than this fraction: stylised proportions


## "T-pose" / "A-pose" / "arms at the torso", and the worst arm rest difference in degrees
static func pose_check(rest_deg: Dictionary) -> Dictionary:
	var d := 0.0
	var seen := false
	for j in ["upperarm_l", "upperarm_r"]:
		if rest_deg.has(j):
			d = maxf(d, float(rest_deg[j]))
			seen = true
	if not seen:
		return {"kind": "unknown", "deg": 0.0, "warn": ""}
	if d <= ARM_T_DEG:
		return {"kind": "T-pose", "deg": d, "warn": ""}
	if d < ARM_DOWN_DEG:
		return {"kind": "A-pose", "deg": d, "warn": "the rig was saved in an A-pose (arms %.0f deg from Kine's T); the retarget turns each arm back to Kine's rest, so the motion is kept" % d}
	return {"kind": "arms at the torso", "deg": d, "warn": "the rig was saved with its arms at the torso (%.0f deg from Kine's T); the retarget corrects the rest, but arm-over-chest poses may clip, so check them" % d}


## the leg-length ratio Kine / file; warns when one body is much bigger
static func size_check(ratio: float) -> Dictionary:
	if ratio <= 0.0:
		return {"warn": "", "ratio": ratio}
	if ratio < SIZE_LO or ratio > SIZE_HI:
		var bigger := "smaller" if ratio < 1.0 else "bigger"
		return {"ratio": ratio, "warn": "this body is %.1fx %s than the file's (leg length), so the motion will be technically right but its character will not: a stride or weight made for the other size may need re-authoring after the import" % [maxf(ratio, 1.0 / ratio), bigger]}
	return {"warn": "", "ratio": ratio}


static func _len(pos: Dictionary, chain: Array) -> float:
	var s := 0.0
	for i in chain.size() - 1:
		if not (pos.has(chain[i]) and pos.has(chain[i + 1])):
			return 0.0
		s += (pos[chain[i]] as Vector3).distance_to(pos[chain[i + 1]])
	return s


## arm / leg and torso / leg of a rest, each side averaged: {"arm", "torso"} (0 when not mapped)
static func shape(pos: Dictionary) -> Dictionary:
	var leg := AnimImport._leg(pos)
	var arm := 0.0
	var n := 0
	for sd in ["_l", "_r"]:
		var a := _len(pos, ["upperarm" + sd, "lowerarm" + sd, "hand" + sd])
		if a > 0.0:
			arm += a
			n += 1
	arm = arm / n if n > 0 else 0.0
	var top := "neck_01" if pos.has("neck_01") else "head"
	var torso := _len(pos, ["pelvis", top])
	if leg < 1e-6:
		return {"arm": 0.0, "torso": 0.0}
	return {"arm": arm / leg, "torso": torso / leg}


## the two rests' shapes against each other: warn when arm or torso (to the leg) differ by more than PROP_DEV
static func proportion_check(sp: Dictionary, kp: Dictionary) -> Dictionary:
	var a := shape(sp)
	var b := shape(kp)
	var worst := 0.0
	var what := ""
	for k in ["arm", "torso"]:
		if a[k] > 1e-6 and b[k] > 1e-6:
			var dev := absf(float(a[k]) / float(b[k]) - 1.0)
			if dev > worst:
				worst = dev
				what = k
	if worst > PROP_DEV:
		var rel := float(shape(sp)[what]) / float(b[what])
		return {"dev": worst, "warn": "stylised proportions: the file's %s is %.0f%% %s relative to its legs than Kine's, so hands and shoulders will not land where the original's did; check reaches and offer a fix by editing the cards or the body's proportions" % [what, absf(rel - 1.0) * 100.0, "longer" if rel > 1.0 else "shorter"]}
	return {"dev": worst, "warn": ""}


## everything above for one import. rt = AnimImport.retarget's result (ratio, rest_deg). {"pose","size","prop","warnings"}
static func analyze(src: Dictionary, mapping: Dictionary, B: Body, rt: Dictionary) -> Dictionary:
	var sp := {}
	var rest: Array = src["rest"]
	for j in mapping["map"]:
		sp[j] = (rest[mapping["map"][j]] as Transform3D).origin
	var kp := {}
	for j in Body.ORDER:
		kp[j] = B.p0[j]
	var po := pose_check(rt.get("rest_deg", {}))
	var si := size_check(float(rt.get("ratio", 0.0)))
	var pr := proportion_check(sp, kp)
	var w := []
	for x in [po, si, pr]:
		if String(x["warn"]) != "":
			w.append(x["warn"])
	w.append_array(SideChecks.warnings(sp))   # C08: sides from geometry, facing axis
	return {"pose": po, "size": si, "prop": pr, "warnings": w}


## STAY IN PLACE (opt-in, per clip): every card's hips keep card 0's ground position (x, z); height is kept. Replaces each
## pose whole (a pose is never edited in place). {"cards", "metres": the farthest the hips had travelled}
static func strip_travel(S: Scene) -> Dictionary:
	if S.cards.is_empty():
		return {"cards": 0, "metres": 0.0}
	var o0 := _off(S.cards[0]["pose"])
	var far := 0.0
	var n := 0
	for c in S.cards:
		var p: Dictionary = (c["pose"] as Dictionary).duplicate(true)
		var o := _off(p)
		far = maxf(far, Vector2(o.x - o0.x, o.z - o0.z).length())
		p["offset"] = [o0.x, o.y, o0.z]
		c["pose"] = p
		n += 1
	S._flat_memo.clear()
	return {"cards": n, "metres": far}


static func _off(pose: Dictionary) -> Vector3:
	var v = pose.get("offset", [0, 0, 0])
	if v is Vector3:
		return v
	return Vector3(float(v[0]), float(v[1]), float(v[2]))
