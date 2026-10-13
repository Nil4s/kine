## moves.gd - a move (an animation, or a transition between two poses) = key poses at times. The math, in MATH.md:
##   between key i (time t0) and key i+1 (time t1), at time t:  u = (t - t0) / (t1 - t0),  e = u*u*(3 - 2u)  (ease in+out)
##   every joint angle = lerp(angle_i, angle_i+1, e);  the hips' offset the same way.
## Angles are blended, not rotations: each angle stays between two legal values, so EVERY in-between frame is inside the
## body's ranges by construction. Contacts can still happen in between: check() lists those frames, it never hides them.
class_name Moves
extends RefCounted

var keys := []     # [{"t": seconds, "pose": Body.to_dict() result}], kept sorted by t
var name := "move"
var fps := 30


func add_key(t: float, pose: Dictionary) -> int:
	for k in keys.size():
		if absf(keys[k]["t"] - t) < 0.001:
			keys[k]["pose"] = pose
			return k
	keys.append({"t": t, "pose": pose})
	keys.sort_custom(func(a, b): return a["t"] < b["t"])
	for k in keys.size():
		if keys[k]["pose"] == pose:
			return k
	return -1


func length() -> float:
	return keys[-1]["t"] if not keys.is_empty() else 0.0


## the pose at time t, as angles: {"offset": Vector3, "ang": {joint: Vector3}}
func sample(t: float) -> Dictionary:
	if keys.is_empty():
		return {}
	if t <= keys[0]["t"] or keys.size() == 1:
		return _flat(keys[0]["pose"])
	if t >= keys[-1]["t"]:
		return _flat(keys[-1]["pose"])
	var i := 0
	while keys[i + 1]["t"] < t:
		i += 1
	var a := _flat(keys[i]["pose"])
	var b := _flat(keys[i + 1]["pose"])
	var u: float = (t - keys[i]["t"]) / maxf(1e-6, keys[i + 1]["t"] - keys[i]["t"])
	var e := u * u * (3.0 - 2.0 * u)
	var ang := {}
	for j in a["ang"]:
		ang[j] = (a["ang"][j] as Vector3).lerp(b["ang"].get(j, a["ang"][j]), e)
	# the bat: in the same hand in both keys -> its place in the hand blends (lerp + slerp); otherwise key i's state holds
	var w: Dictionary = a["weapon"].duplicate()
	var wb: Dictionary = b["weapon"]
	if not w.is_empty() and not wb.is_empty() and w.get("hand", "") == wb.get("hand", ""):
		var key := "local_" if w.get("hand", "") != "" else ""
		w[key + "pos"] = (w[key + "pos"] as Vector3).lerp(wb[key + "pos"], e)
		w[key + "rot"] = (w[key + "rot"] as Quaternion).slerp(wb[key + "rot"], e)
	return {"offset": (a["offset"] as Vector3).lerp(b["offset"], e), "ang": ang, "weapon": w}


static func _flat(p: Dictionary) -> Dictionary:
	var ang := {}
	for j in p["joints"]:
		var x: Dictionary = p["joints"][j]
		ang[j] = Vector3(x["bend"], x["side"], x["twist"])
	var o: Array = p.get("offset", [0, 0, 0])
	var w := {}
	var pw: Dictionary = p.get("weapon", {})
	if not pw.is_empty():
		var r: Array = pw["rot"]
		var lr: Array = pw.get("local_rot", [0, 0, 0, 1])
		var lp: Array = pw.get("local_pos", [0, 0, 0])
		var k: Array = pw["knob"]
		w = {"hand": pw.get("hand", ""), "pos": Vector3(k[0], k[1], k[2]), "rot": Quaternion(r[0], r[1], r[2], r[3]),
			"local_pos": Vector3(lp[0], lp[1], lp[2]), "local_rot": Quaternion(lr[0], lr[1], lr[2], lr[3]),
			"length": float(pw.get("length", 0.84)), "grip": bool(pw.get("two_hand_grip", false)), "grip_m": float(pw.get("grip_m", 0.18))}
	return {"offset": Vector3(o[0], o[1], o[2]), "ang": ang, "weapon": w}


## play every frame through the body: [[frame, time, contacts], ...] for frames where parts sink into each other
func check(B: Body) -> Array:
	var bad := []
	var n := int(ceil(length() * fps))
	for f in n + 1:
		var t := float(f) / fps
		apply(B, t)
		var c := B.contacts()
		if not c.is_empty():
			bad.append([f, snappedf(t, 0.001), c.map(func(x): return [x[0], x[1], snappedf(x[2], 0.001)])])
	return bad


func apply(B: Body, t: float) -> void:
	var s := sample(t)
	if s.is_empty():
		return
	B.offset = s["offset"]
	for j in s["ang"]:
		B.ang[j] = B.clamp_ang(j, s["ang"][j])
	B.fk()
	var w: Dictionary = s["weapon"]
	B.wep_on = not w.is_empty()
	if B.wep_on:
		B.set_weapon_len(w["length"])
		B.wep_hand = w["hand"]
		B.wep_pos = w["pos"]
		B.wep_rot = w["rot"]
		B.wep_lpos = w["local_pos"]
		B.wep_lrot = w["local_rot"]
		B.grip = w["grip"]
		B.grip_u = w["grip_m"]


func to_dict(B: Body) -> Dictionary:
	var bad := check(B)
	return {"name": name, "fps": fps, "length": length(), "keys": keys, "bad_frames": bad,
		"note": "keys = poses (angles, quaternions, positions: see a pose file) at t seconds; in-betweens = each angle eased between keys, e = u*u*(3-2u) (MATH.md). bad_frames = frames where body parts sink into each other."}


func from_dict(d: Dictionary) -> void:
	name = d.get("name", "move")
	fps = int(d.get("fps", 30))
	keys = d.get("keys", [])
