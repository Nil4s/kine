## face_pain.gd - I13 EFFORT FACE FROM TORQUE and I14 PAIN FACE FROM HIT FORCE (L75). Pure helpers on the face rig (scripts/face.gd): the AUs are
## computed per frame, then keyed onto Scene.face channels (Face.key / PartKeys.put) so they ride the clip like any other face key.
##
## EFFORT (I13): the torque signal is ForceView's ratio (joint torque / the joint's limit), the WORST joint per frame. Effort E = g(torque) with
## g(x) = 0 at or under REST_RATIO, else 1 - exp(-(x - REST_RATIO) / E_SCALE): strictly increasing, so E has no plateau and its peak frame is the torque's
## peak frame minus the onset lead. The face LEADS the load by LEAD frames (a lifter braces before the load arrives; 3 frames = 100 ms at 30 fps, inside
## the 2-4 asked): E(f) = g(torque(f + LEAD)). AUs (FACS, Ekman & Friesen): AU4 brow lowerer, AU7 lid tightener, AU24 lip pressor, AU38 nostril
## wing, and a jaw clench. The weights are mine; AU4 / AU7 / AU24 match face.gd EXPR_AU "effort" (brow -0.5, squint 0.6, press 0.9 at E = 1).
## The rig has no nostril or clench channel: AU38 and clench are reported in the AU record only, and the clench is folded into press.
##
## PAIN (I14): a hit of impulse J (N s) has amplitude a = RegionReact.amp_of(J) (0 for J <= 0). The face starts REFLEX seconds after contact (nociceptive
## withdrawal reflex ~100-150 ms; mine: 0.11 s), rises over RISE and decays with TAU. AUs (Prkachin & Solomon 2008 pain set): AU4, AU6, AU7, AU9, AU10, AU43
## at the weights of face.gd EXPR_AU "pain" (0.8, 0.8, 0.8, 0.6, 0.6, 0.6) x a x envelope. PSPI = 5 (AU4 + max(AU6, AU7) + max(AU9, AU10)) + AU43 (0..16
## with the AUs at 0..1: the published scale is AU 0-5 and AU43 0/1, so the 0-1 AUs here are the same scale / 5, and the sum is x5).
class_name FacePain
extends RefCounted

const LEAD := 3            # frames the effort face leads the torque peak
const REST_RATIO := 0.30   # torque / limit at or under which there is no effort face (mine; a standing body holds well under it)
const E_SCALE := 0.35
const W_AU7 := 0.8
const W_AU24 := 0.9
const W_AU38 := 0.6
const W_CLENCH := 0.7
const REFLEX := 0.11       # s from contact to the first pain AU
const RISE := 0.06         # s from onset to the peak
const TAU := 0.5           # s decay time constant
const PAIN_W := {"AU4": 0.8, "AU6": 0.8, "AU7": 0.8, "AU9": 0.6, "AU10": 0.6, "AU43": 0.6}
const AU_ON := 0.02


static func g(x: float) -> float:
	return 0.0 if x <= REST_RATIO else 1.0 - exp(-(x - REST_RATIO) / E_SCALE)


## per-frame worst torque ratio -> effort AUs. torque: PackedFloat32Array, one value per frame.
static func effort_from_torque(torque: PackedFloat32Array, fps: int) -> Dictionary:
	var n := torque.size()
	var out := {"ok": n > 0, "fps": fps, "n": n, "lead": LEAD, "E": [], "au": [], "torque": torque, "torque_peak": 0.0, "torque_peak_frame": 0}
	if n == 0:
		out["msg"] = "no torque"
		return out
	var tp := 0
	for i in n:
		if torque[i] > torque[tp]:
			tp = i
	out["torque_peak"] = torque[tp]
	out["torque_peak_frame"] = tp
	for f in n:
		var e := g(torque[mini(f + LEAD, n - 1)])
		(out["E"] as Array).append(e)
		(out["au"] as Array).append({"AU4": e, "AU7": W_AU7 * e, "AU24": W_AU24 * e, "AU38": W_AU38 * e, "clench": W_CLENCH * e})
	return out


## the clip's effort face: ForceView torque per frame (worst joint), then effort_from_torque
static func effort_scene(S: Scene, B: Body, fps := 30) -> Dictionary:
	var sm := ForceView.sample(S, B)
	if sm.is_empty() or int(sm.get("n", 0)) < 2:
		return {"ok": false, "msg": "the clip is too short for torque", "au": [], "E": []}
	var nf := int(ceil(S.length() * fps)) + 1
	var m := PackedFloat32Array()
	m.resize(nf)
	var ns: int = sm["n"]
	for f in nf:
		var i := clampi(roundi(float(f) / fps * ForceView.HZ), 0, ns - 1)
		var w := 0.0
		for j in sm["ratio"]:
			w = maxf(w, float(sm["ratio"][j][i]))
		m[f] = w
	return effort_from_torque(m, fps)


static func _put(face: Dictionary, f: int, fps: int, vals: Dictionary) -> void:
	Face.key(face, float(f) / fps, vals)


## key the effort curve onto face channels (brows lowered, lids tight, lips pressed); nothing is written when no frame has effort
static func effort_keys(cv: Dictionary, face: Dictionary) -> void:
	var E: Array = cv.get("E", [])
	var first := -1
	var last := -1
	for f in E.size():
		if float(E[f]) > 0.0:
			if first < 0:
				first = f
			last = f
	if first < 0:
		return
	var fps: int = cv["fps"]
	for f in range(maxi(first - 1, 0), mini(last + 2, E.size())):
		var a: Dictionary = cv["au"][f]
		_put(face, f, fps, {"brow_l": -0.5 * a["AU4"], "brow_r": -0.5 * a["AU4"], "squint": 0.75 * a["AU7"], "press": maxf(a["AU24"], a["clench"])})


static func pspi(au: Dictionary) -> float:
	return 5.0 * (float(au["AU4"]) + maxf(float(au["AU6"]), float(au["AU7"])) + maxf(float(au["AU9"]), float(au["AU10"]))) + float(au["AU43"])


static func envelope(dt: float) -> float:
	if dt <= REFLEX:
		return 0.0
	if dt < REFLEX + RISE:
		return (dt - REFLEX) / RISE
	return exp(-(dt - REFLEX - RISE) / TAU)


## the pain face of a hit of `impulse` N s at `contact` s, frames 0..length s at fps
static func pain_curve(impulse: float, contact: float, length: float, fps: int) -> Dictionary:
	var a := RegionReact.amp_of(impulse)
	var frames := []
	var peak_p := 0.0
	var peak_au := {}
	for k in PAIN_W:
		peak_au[k] = 0.0
	var onset := -1.0
	for f in int(floor(length * fps)) + 1:
		var t := float(f) / fps
		var e := a * envelope(t - contact)
		var au := {}
		for k in PAIN_W:
			au[k] = clampf(float(PAIN_W[k]) * e, 0.0, 1.0)
			peak_au[k] = maxf(float(peak_au[k]), au[k])
		var p := pspi(au)
		peak_p = maxf(peak_p, p)
		if onset < 0.0 and float(au["AU4"]) > AU_ON:
			onset = t - contact
		frames.append({"t": t, "au": au, "pspi": p})
	return {"ok": true, "fps": fps, "impulse": impulse, "amp": a, "contact": contact, "frames": frames, "peak_pspi": peak_p, "peak_au": peak_au, "onset_s": onset}


static func pain_from_react(r: Dictionary, contact: float, length: float, fps: int) -> Dictionary:
	return pain_curve(float(r.get("impulse", 0.0)), contact, length, fps)


static func pain_keys(cv: Dictionary, face: Dictionary) -> void:
	var fr: Array = cv["frames"]
	var first := -1
	var last := -1
	for f in fr.size():
		if float(fr[f]["pspi"]) > 0.0:
			if first < 0:
				first = f
			last = f
	if first < 0:
		return
	var fps: int = cv["fps"]
	for f in range(maxi(first - 1, 0), mini(last + 2, fr.size())):
		var a: Dictionary = fr[f]["au"]
		_put(face, f, fps, {"brow_l": -float(a["AU4"]), "brow_r": -float(a["AU4"]), "squint": maxf(a["AU6"], a["AU7"]), "blink": a["AU43"],
			"jaw": 0.25 * maxf(a["AU9"], a["AU10"]), "vis_E": maxf(a["AU9"], a["AU10"])})


static func serve(tool: String, m: Node, p: Dictionary) -> Dictionary:
	match tool:
		"pain_face":
			if not p.has("impulse"):
				return {"ok": false, "error": "pain_face needs {impulse: N s, contact?: s (1.0), length?: s (4), fps?: 30}"}
			var cv := pain_curve(float(p["impulse"]), float(p.get("contact", 1.0)), float(p.get("length", 4.0)), int(p.get("fps", 30)))
			var fc := {}
			pain_keys(cv, fc)
			return {"ok": true, "result": {"impulse": cv["impulse"], "amp": cv["amp"], "peak_pspi": cv["peak_pspi"], "peak_au": cv["peak_au"], "onset_s": cv["onset_s"],
				"reflex_s": REFLEX, "channels_keyed": fc.keys()}}
		"effort_face":
			var fps := int(p.get("fps", 30))
			var S: Scene = null
			if p.has("clip"):
				var path := AgentTools.res(String(p["clip"]))
				if not FileAccess.file_exists(path):
					return {"ok": false, "error": "effort_face: no such scene file '%s'" % p["clip"]}
				var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
				if not d is Dictionary:
					return {"ok": false, "error": "effort_face: '%s' is not a scene file" % p["clip"]}
				S = Scene.new()
				S.from_dict(d)
			elif m != null:
				S = m.S
			else:
				return {"ok": false, "error": "effort_face needs {clip: a scene file, fps?: 30} (or a live scene)"}
			var B := Body.new()
			B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
			B.fk()
			var cv := effort_scene(S, B, fps)
			if not bool(cv.get("ok", false)):
				return {"ok": false, "error": "effort_face: " + String(cv.get("msg", "no result"))}
			var E: Array = cv["E"]
			var pf := 0
			var act := 0
			for f in E.size():
				if float(E[f]) > float(E[pf]):
					pf = f
				if float(E[f]) > 0.0:
					act += 1
			return {"ok": true, "result": {"peak_au4": float(E[pf]), "peak_frame": pf, "torque_peak": cv["torque_peak"], "torque_peak_frame": cv["torque_peak_frame"],
				"lead_frames": LEAD, "active_frames": act, "frames": E.size()}}
	return {"ok": false, "error": "unknown tool"}
