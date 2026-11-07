## rig_anim.gd - ANIMATION TOOLS ON A CUSTOM RIG (ROADMAP_400 L17, lane L91). Key, part keys, breakdown, retime (with ripple), graph read and
## undo for a user-built rig (scripts/custom_rig.gd). Nothing here names a mannequin joint: every tool goes through the rig's own bone list
## (rig["names"]). A refused call changes nothing and says why. Pure data; the scene undo is the caller's m._push_undo (see rig_anim_serve.gd),
## run() keeps a history of its own for use without a scene.
class_name RigAnim
extends RefCounted

const HIST := "_hist"


static func _fail(why: String) -> Dictionary:
	return {"ok": false, "why": why}


static func _unknown(rig: Dictionary, bones: Array) -> String:
	for b in bones:
		if not (rig["names"] as Array).has(String(b)):
			return String(b)
	return ""


## KEY: bones = [] keys every posed bone, else only the listed ones (a part key); the other rows of that frame are kept
static func key_bones(rig: Dictionary, frame: int, bones: Array) -> Dictionary:
	var bad := _unknown(rig, bones)
	if bad != "":
		return _fail("no bone named %s on this rig" % bad)
	var row: Dictionary = (rig["keys"].get(frame, {}) as Dictionary).duplicate()
	var keyed := []
	var src: Array = bones if not bones.is_empty() else (rig["pose"] as Dictionary).keys()
	for b in src:
		var q: Quaternion = (rig["pose"] as Dictionary).get(b, Quaternion.IDENTITY)
		row[b] = q
		keyed.append(b)
	rig["keys"][frame] = row
	if not rig.has("pkeys"):
		rig["pkeys"] = {}
	rig["pkeys"][frame] = rig.get("pos", Vector3.ZERO)
	return {"ok": true, "keyed": keyed, "frame": frame}


## BREAKDOWN: a key at `frame` between the key frame before and the one after it, factor 0 = before, 1 = after (slerp), on the listed bones
## (none listed = every bone in both neighbouring keys)
static func breakdown(rig: Dictionary, frame: int, f: float, bones: Array) -> Dictionary:
	var bad := _unknown(rig, bones)
	if bad != "":
		return _fail("no bone named %s on this rig" % bad)
	var prev := -1000000
	var next := 1000000
	for k in (rig["keys"] as Dictionary):
		if k < frame and k > prev:
			prev = k
		if k > frame and k < next:
			next = k
	if prev == -1000000 or next == 1000000:
		return _fail("a breakdown needs a key before and a key after frame %d" % frame)
	var ra: Dictionary = rig["keys"][prev]
	var rb: Dictionary = rig["keys"][next]
	var which: Array = bones.duplicate()
	if which.is_empty():
		for b in ra:
			if rb.has(b):
				which.append(b)
	var row: Dictionary = (rig["keys"].get(frame, {}) as Dictionary).duplicate()
	for b in which:
		var a: Quaternion = ra.get(b, Quaternion.IDENTITY)
		var c: Quaternion = rb.get(b, Quaternion.IDENTITY)
		var q := a.slerp(c, f).normalized()
		row[b] = q
		rig["pose"][b] = q
	rig["keys"][frame] = row
	if not rig.has("pkeys"):
		rig["pkeys"] = {}
	var pk: Dictionary = rig["pkeys"]
	if pk.has(prev) and pk.has(next):
		rig["pkeys"][frame] = (pk[prev] as Vector3).lerp(pk[next], f)
	return {"ok": true, "n": which.size(), "frame": frame, "between": [prev, next]}


## RETIME: move the key at `frame` by delta frames; ripple = every later key moves with it. A move onto or past another key, or to a frame
## before 0, is refused and changes nothing. The root position keys go with the rows.
static func retime_shift(rig: Dictionary, frame: int, delta: int, ripple: bool) -> Dictionary:
	if not (rig["keys"] as Dictionary).has(frame):
		return _fail("no key at frame %d" % frame)
	if delta == 0:
		return _fail("a shift of 0 frames does nothing")
	var fr := CustomRig.key_frames(rig)
	var target: int = frame + delta
	if target < 0:
		return _fail("it would go before frame 0")
	for k in fr:
		if k == frame or (ripple and k > frame):
			continue
		if ripple:
			if delta < 0 and k < frame and k >= target:
				return _fail("it would reach the key at frame %d" % k)
		else:
			if k >= mini(frame, target) and k <= maxi(frame, target):
				return _fail("it would reach the key at frame %d" % k)
	var move := func(d: Dictionary) -> Dictionary:
		var out := {}
		for k in d:
			var moving: bool = (k == frame) or (ripple and k > frame)
			out[k + delta if moving else k] = d[k]
		return out
	rig["keys"] = move.call(rig["keys"])
	if rig.has("pkeys"):
		rig["pkeys"] = move.call(rig["pkeys"])
	return {"ok": true, "frames": CustomRig.key_frames(rig)}


## GRAPH READ: one bone's curve sampled over from..to: angle from rest (deg), euler (deg) and the frames the bone is keyed on
static func curve(rig: Dictionary, bone: String, from: int, to: int, step := 1) -> Dictionary:
	if not (rig["names"] as Array).has(bone):
		return _fail("no bone named %s on this rig" % bone)
	if step < 1 or to < from:
		return _fail("from..to must run forward with a step of at least 1")
	var frames := []
	var ang := []
	var eul := []
	var f := from
	while f <= to:
		var q: Quaternion = CustomRig.pose_at(rig, float(f)).get(bone, Quaternion.IDENTITY)
		var e := Basis(q).get_euler()
		frames.append(f)
		ang.append(rad_to_deg(q.get_angle()))
		eul.append([rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z)])
		f += step
	var kf := []
	for k in CustomRig.key_frames(rig):
		if (rig["keys"][k] as Dictionary).has(bone):
			kf.append(k)
	return {"ok": true, "bone": bone, "frames": frames, "angle_deg": ang, "euler_deg": eul, "key_frames": kf}


## ---- undo (own history, for use without a scene)
static func _snap(rig: Dictionary) -> Dictionary:
	return {"keys": (rig["keys"] as Dictionary).duplicate(true), "pose": (rig["pose"] as Dictionary).duplicate(true),
		"pkeys": (rig["pkeys"] as Dictionary).duplicate(true) if rig.has("pkeys") else null, "pos": rig["pos"] if rig.has("pos") else null}


static func _restore(rig: Dictionary, s: Dictionary) -> void:
	rig["keys"] = s["keys"]
	rig["pose"] = s["pose"]
	if s["pkeys"] == null:
		rig.erase("pkeys")
	else:
		rig["pkeys"] = s["pkeys"]
	if s["pos"] == null:
		rig.erase("pos")
	else:
		rig["pos"] = s["pos"]


static func history_size(rig: Dictionary) -> int:
	return (rig.get(HIST, []) as Array).size()


static func undo(rig: Dictionary) -> bool:
	var h: Array = rig.get(HIST, [])
	if h.is_empty():
		return false
	_restore(rig, h.pop_back())
	rig[HIST] = h
	return true


## one action = one undo step; a refused action leaves no step. actions: key, breakdown, retime, mirror_pose, mirror_keys
static func run(rig: Dictionary, action: String, a: Dictionary, record := true) -> Dictionary:
	var snap := _snap(rig)
	var r: Dictionary
	match action:
		"key":
			r = key_bones(rig, int(a.get("frame", 0)), a.get("bones", []))
		"breakdown":
			r = breakdown(rig, int(a.get("frame", 0)), float(a.get("factor", 0.5)), a.get("bones", []))
		"retime":
			r = retime_shift(rig, int(a.get("frame", 0)), int(a.get("delta", 0)), bool(a.get("ripple", true)))
		"mirror_pose":
			r = RigMirror.mirror_pose(rig)
		"mirror_keys":
			r = RigMirror.mirror_keys(rig)
		_:
			r = _fail("unknown action %s" % action)
	if not bool(r.get("ok", false)):
		_restore(rig, snap)
	elif record:
		var h: Array = rig.get(HIST, [])
		h.append(snap)
		rig[HIST] = h
	return r
