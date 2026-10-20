## live_layer.gd - LIVE LAYER: record only some body parts from the webcam ONTO a clip you already have (Nick 2026-10-20:
## "an way to track moves while recording, so u got an partial move, like mocap irl").
## The clip plays from the playhead while you act; the parts you picked follow you, everything else stays the clip.
## Stop keeps the take as PART KEYS (scripts/part_keys.gd) on just those joints, so the cards are untouched and deleting the
## part keys gives the clip back exactly. One webcam reads arms and torso well and the legs' depth badly, so the usual use
## is: keep hand-keyed legs, act the arms / head / upper body live.
## Keys: one every DT (the in-betweens come from part keys' monotone PCHIP curve, as the gaze director's do), each the
## take's frame NEAREST that time (no blend of two frames: a twist near +-180 deg would blend the long way round).
## Within the recorded span a layered joint's earlier part keys are replaced; keys outside the span stay.
class_name LiveLayer
extends RefCounted

const DT := 1.0 / 15.0   # s between keys
const GROUPS := {
	"arms": ["clavicle_l", "upperarm_l", "lowerarm_l", "hand_l", "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r"],
	"head": ["neck_01", "head"],
	"upper body": ["spine_01", "spine_02", "spine_03", "neck_01", "head",
		"clavicle_l", "upperarm_l", "lowerarm_l", "hand_l", "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r"],
	"legs": ["thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r", "ball_r"],
}


## the take (LivePuppet frames {"t" unix s, "ang"}) -> {joint: [{"t", "v"}]} on the clip's clock: the take's first frame
## lands at t0; nothing past t_end (the clip's end). {} for a take of under two frames
static func keys_from_take(take: Array, joints: Array, t0: float, t_end: float) -> Dictionary:
	var out := {}
	if take.size() < 2:
		return out
	var ts0 := float(take[0]["t"])
	var span := minf(float(take[-1]["t"]) - ts0, t_end - t0)
	if span <= 0.0:
		return out
	var n := int(floor(span / DT))
	var times := []
	for k in n + 1:
		times.append(k * DT)
	if span - n * DT > DT * 0.25:
		times.append(span)   # the last moment of the take is a key too
	for j in joints:
		out[j] = []
	var i := 0
	for s in times:
		while i + 1 < take.size() and absf(float(take[i + 1]["t"]) - ts0 - s) <= absf(float(take[i]["t"]) - ts0 - s):
			i += 1
		var ang: Dictionary = take[i]["ang"]
		for j in joints:
			if ang.has(j):
				(out[j] as Array).append({"t": snappedf(t0 + s, 0.0001), "v": ang[j]})
	return out


## writes the keys into S.part_keys: per joint, the old keys inside the new span are dropped, the rest kept, sorted by t.
## Returns the number of keys written
static func apply(S: Scene, keys: Dictionary) -> int:
	var n := 0
	for j in keys:
		var nk: Array = keys[j]
		if nk.is_empty():
			continue
		var a := float(nk[0]["t"])
		var b := float(nk[-1]["t"])
		var kept := []
		for k in S.part_keys.get(j, []):
			if float(k["t"]) < a - 1e-6 or float(k["t"]) > b + 1e-6:
				kept.append(k)
		kept.append_array(nk.duplicate(true))
		kept.sort_custom(func(x, y): return float(x["t"]) < float(y["t"]))
		S.part_keys[j] = kept
		n += nk.size()
	return n


## a two-handed weapon after a layer: at every 0.05 s where both hands hold it, is the second hand on it (within the
## clip's own worst miss before the layer, + 2 mm)? {"n": times held two-handed, "off": times it cannot reach, "worst": m}.
## Where the acted arm swings the weapon out of the other arm's reach no solve can close it, so the status line says so
static func grip_report(S: Scene, B: Body, base := -1.0) -> Dictionary:
	if base < 0.0:
		var pk: Dictionary = S.part_keys
		S.part_keys = {}
		base = _worst_grip(S, B)[1]
		S.part_keys = pk
	var r := _worst_grip(S, B, base + 0.002)
	return {"n": r[0], "off": r[2], "worst": r[1], "base": base}


static func _worst_grip(S: Scene, B: Body, bar := INF) -> Array:
	var keep := B.state()
	var n := 0
	var off := 0
	var worst := 0.0
	var t := 0.0
	while t <= S.length():
		S.apply_true(B, t)
		if B.wep_on and B.grip:
			n += 1
			var m := B.grip_miss()
			worst = maxf(worst, m)
			if m > bar:
				off += 1
		t += 0.05
	B.set_state(keep)
	return [n, worst, off]


## A TWO-HANDED WEAPON: after apply(), the free arm's keys are re-made so its hand holds the weapon the way the cards hold
## it (Scene.regrip_layered with the WHOLE arm searched, not playback's quick fit: the acted weapon hand can roll the
## weapon further than the wrist turns, Nick 10-20 "it flips to the opposite side"). At each key time held in two hands
## the free arm's 4 joints get the searched angles; elsewhere the webcam's stay. Returns the number of times re-made
static func bake_grip(S: Scene, B: Body, keys: Dictionary) -> int:
	var keep := B.state()
	var arms := {"_l": ["clavicle_l", "upperarm_l", "lowerarm_l", "hand_l"], "_r": ["clavicle_r", "upperarm_r", "lowerarm_r", "hand_r"]}
	var ref := ""
	for j in keys:
		ref = j
		break
	if ref == "":
		return 0
	var n := 0
	for i in (keys[ref] as Array).size():
		var t := float(keys[ref][i]["t"])
		S.apply_true(B, t)
		if not (B.wep_on and B.grip and B.wep_hand != ""):
			continue
		var o := "hand_l" if B.wep_hand == "hand_r" else "hand_r"
		var sd: String = o.right(2)
		var wf := B.fast
		B.fast = false
		S.regrip_layered(B, t, true)   # from the card's arm, whatever the webcam's keys did with it
		B.fast = wf
		for j in arms[sd]:
			if keys.has(j) and i < (keys[j] as Array).size():
				keys[j][i]["v"] = B.ang[j]
		n += 1
	B.set_state(keep)
	if n > 0:
		apply(S, keys)
	return n
