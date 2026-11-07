## impact_align.gd - N034: IMPACT ALIGNMENT at the contact frame. A punch wants a straight wrist (bend / deviation under WRIST_DEV), a wrist
## bent past WRIST_LOAD is past the safe load line, a kick wants a knee that is not locked (calf bend over KNEE_MIN), and a punch that MISSES
## must not snap the elbow straight (ELBOW_MIN). The bars are ours (sports-medicine direction: hand/wrist injury at a bent wrist on impact,
## knee hyperextension on a kick that lands straight; no cutoff read from a primary source). Angles are Body.ang (bend, side, twist) in degrees.
## Each flag: {rule, joint, axis, deg, bar, msg, fix: {joint: Vector3}} where fix is the pose to key instead.
class_name ImpactAlign
extends RefCounted

const WRIST_DEV := 15.0
const WRIST_LOAD := 35.0
const KNEE_MIN := 8.0
const KNEE_FIX := 15.0
const ELBOW_MIN := 8.0
const ELBOW_FIX := 20.0


static func _g(ang: Dictionary, j: String) -> Vector3:
	var v: Variant = ang.get(j, Vector3.ZERO)
	return v if v is Vector3 else Vector3.ZERO


static func check(ang: Dictionary, kind: String, side: String, miss := false) -> Dictionary:
	var flags := []
	var s := "_" + side
	if kind == "punch":
		var w := _g(ang, "hand" + s)
		var dev := maxf(absf(w.x), absf(w.y))
		var axis := "bend" if absf(w.x) >= absf(w.y) else "side"
		var fix := {"hand" + s: Vector3(0, 0, w.z)}
		if dev > WRIST_DEV:
			flags.append({"rule": "WRIST BENT", "joint": "hand" + s, "axis": axis, "deg": dev, "bar": WRIST_DEV, "fix": fix,
				"msg": "wrist %s %.0f deg at contact (bar %.0f): straighten it so the force goes through the forearm bones" % [axis, dev, WRIST_DEV]})
		if absf(w.x) > WRIST_LOAD:
			flags.append({"rule": "WRIST LOAD", "joint": "hand" + s, "axis": "bend", "deg": absf(w.x), "bar": WRIST_LOAD, "fix": fix,
				"msg": "wrist bend %.0f deg is past the safe load line (%.0f)" % [absf(w.x), WRIST_LOAD]})
		var e := _g(ang, "lowerarm" + s)
		if miss and e.x < ELBOW_MIN:
			flags.append({"rule": "ELBOW SNAP", "joint": "lowerarm" + s, "axis": "bend", "deg": e.x, "bar": ELBOW_MIN,
				"fix": {"lowerarm" + s: Vector3(ELBOW_FIX, 0, 0)},
				"msg": "a miss with the elbow straight (%.0f deg) snaps it: stop at %.0f deg" % [e.x, ELBOW_FIX]})
	elif kind == "kick":
		var k := _g(ang, "calf" + s)
		if k.x < KNEE_MIN:
			flags.append({"rule": "KNEE LOCKED", "joint": "calf" + s, "axis": "bend", "deg": k.x, "bar": KNEE_MIN,
				"fix": {"calf" + s: Vector3(KNEE_FIX, 0, 0)},
				"msg": "knee %.0f deg at the landing (bar %.0f): keep it soft, bend to %.0f" % [k.x, KNEE_MIN, KNEE_FIX]})
	return {"kind": kind, "side": side, "miss": miss, "flags": flags, "ok": flags.is_empty()}


## the contact frame of a scene: the active frame with the highest tip speed, judged on the body as posed there
static func scene_check(S: Scene, fps := 30) -> Dictionary:
	if S.cards.size() < 2:
		return {"ok": false, "error": "impact_align needs a scene of 2+ cards"}
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	B.ground()
	var fd := FrameData.analyze(S, B, fps)
	if fd.is_empty() or int(fd["first"]) < 0:
		return {"ok": true, "frame": -1, "flags": [], "msg": "no active strike in the scene"}
	var best := int(fd["first"])
	for f in fd["frames"]:
		if f["active"] and float(f["speed"]) > float(fd["frames"][best]["speed"]):
			best = int(f["f"])
	S.apply(B, float(best) / float(fps))
	var key: String = String(fd["striker"])
	var kind := "kick" if key.begins_with("foot") else "punch"
	var side := key.right(1)
	var r := check(B.ang, kind, side, false)
	r["ok"] = true
	r["frame"] = best
	r["striker"] = key
	return r


static func to_json(r: Dictionary) -> Dictionary:
	var o := r.duplicate(true)
	var fl := []
	for f in o.get("flags", []):
		var fx := {}
		for j in f["fix"]:
			var v: Vector3 = f["fix"][j]
			fx[j] = [v.x, v.y, v.z]
		f["fix"] = fx
		fl.append(f)
	o["flags"] = fl
	return o
