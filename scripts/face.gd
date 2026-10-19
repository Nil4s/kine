## face.gd - THE FACE (ROADMAP 74: brows, jaw, eyes, visemes). Pure helpers: no node, no scene.
## The scene keeps Scene.face = {"<channel>": [{"t", "v": Vector3(x, 0, 0)}]}: the same key shape as Scene.part_keys, so
## PartKeys.put / PartKeys.at / PartKeys.to_file / from_file carry it (x is the value; y, z stay 0). Saved only when keyed
## ("face" in the file; a scene without it writes no such key). Drawn on the hero's head by main.gd _face_draw.
##
## CHANNELS (the slider's range in the value, the head's reading in degrees or metres):
##   brow_l, brow_r  -1..1   raise (+) / furrow (-) of each brow. Left = the hero's +X side (data/skeleton.json: +X = LEFT).
##                           FACS: AU1 inner brow raiser, AU2 outer brow raiser, AU4 brow lowerer (Ekman & Friesen 1978).
##   jaw              0..1   fraction of the full opening. 1.0 = JAW_MAX_DEG. Range cited: maximal voluntary jaw rotation
##                           about 25-30 deg (the hinge opening of the mandible; clinical texts: Okeson, Management of Temporomandibular
##                           Disorders and Occlusion, ch. 2) and maximal incisal opening about 40-55 mm (Agerberg 1974, maximal
##                           mandibular movements in young adults). JAW_MAX_DEG is the middle of 25-30 deg.
##   eye_yaw         -1..1   look left (+, the hero's LEFT) / right; 1.0 = EYE_YAW_MAX (+-45 deg, the horizontal range of human
##                           gaze with the head still: Leigh & Zee, The Neurology of Eye Movements, ch. 2). Clamped there.
##   eye_pitch       -1..1   look up (+) / down; 1.0 = EYE_PITCH_MAX (30 deg; the vertical range is smaller than the horizontal).
##   blink            0..1   lid closure (1 = shut). A human blink lasts about 0.1-0.4 s (Doughty 2001, Blink rate and duration).
##   vis_M/A/O/E      0..1   visemes: M = closed (M, B, P: lips shut), A = open, O = round, E = wide (E, I). The same four
##                           shapes LipSync emits (lip_sync.gd: S shows as E). Each viseme opens the jaw by VIS_JAW x its weight.
## LIP SYNC: when Scene.lip has a channel, it DRIVES the jaw and the visemes at the playhead (LipSync.jaw_at, shape_at), and the
## face keys for jaw and visemes are ignored there. The brows, eyes and blink still come from the keys.
## MIRROR: L/R swap (brow_l <-> brow_r) and the eye yaw negated. Twice is the original (Face.mirror_file, scene mirror).
class_name Face
extends RefCounted

const CHANNELS := ["brow_l", "brow_r", "jaw", "eye_yaw", "eye_pitch", "blink", "vis_M", "vis_A", "vis_O", "vis_E"]
const VISEMES := ["M", "A", "O", "E"]
const JAW_MAX_DEG := 27.5     # deg: the jaw at jaw = 1.0 (middle of the cited 25-30 deg)
const EYE_YAW_MAX := 45.0     # deg: the eye at eye_yaw = +-1 (the cited horizontal gaze range)
const EYE_PITCH_MAX := 30.0   # deg: the eye at eye_pitch = +-1
const VIS_JAW := {"M": 0.0, "A": 1.0, "O": 0.7, "E": 0.45}   # the jaw factor per viseme (the same as LipSync.JAW_K)
const SHOW := 0.05            # a viseme weight at or above this is the mouth shape


## the clamp of each channel: [lo, hi]
static func range_of(ch: String) -> Vector2:
	if ch.begins_with("brow") or ch.begins_with("eye_"):
		return Vector2(-1.0, 1.0)
	return Vector2(0.0, 1.0)


## the raw value of each channel at t (0 where no key); the keys' curve is PartKeys.at, clamped to the channel's range
static func values_at(face: Dictionary, t: float) -> Dictionary:
	var out := {}
	for ch in CHANNELS:
		var v := 0.0
		if face.has(ch) and not (face[ch] as Array).is_empty():
			v = PartKeys.at(face[ch], t).x
		var r := range_of(ch)
		out[ch] = clampf(v, r.x, r.y)
	return out


## the head's reading of raw channel values: {"brow_l", "brow_r" (-1..1), "eye_yaw_deg", "eye_pitch_deg" (clamped at the
## cited range), "blink" (0..1), "jaw_deg" (0..JAW_MAX_DEG), "vis" {M, A, O, E} (0..1), "mouth" (the shape drawn)}.
## With lip (LipSync channel) and a t: the jaw and visemes come from it instead (the lip sync drives them when present).
static func pose(raw: Dictionary, lip: Dictionary = {}, t := 0.0) -> Dictionary:
	var vis := {}
	var jaw := clampf(float(raw.get("jaw", 0.0)), 0.0, 1.0)
	for v in VISEMES:
		vis[v] = clampf(float(raw.get("vis_" + v, 0.0)), 0.0, 1.0)
	var jaw_f := jaw
	for v in VISEMES:
		jaw_f = maxf(jaw_f, float(vis[v]) * float(VIS_JAW[v]))
	if not lip.is_empty():
		var deg := LipSync.jaw_at(lip, t)
		jaw_f = clampf(deg / JAW_MAX_DEG, 0.0, 1.0)
		var shape := LipSync.shape_at(lip, t)
		for v in VISEMES:
			vis[v] = 1.0 if v == shape else 0.0
	# the mouth shape: the strongest viseme; with none, an open jaw reads as open (A: the lips follow the jaw), else shut
	var mouth := "M"
	var best := SHOW
	for v in VISEMES:
		if float(vis[v]) >= best:
			best = float(vis[v])
			mouth = v
	if mouth == "M" and lip.is_empty() and jaw_f >= SHOW and float(vis["M"]) < SHOW:
		mouth = "A"
	var yaw := clampf(float(raw.get("eye_yaw", 0.0)), -1.0, 1.0)
	var pitch := clampf(float(raw.get("eye_pitch", 0.0)), -1.0, 1.0)
	return {"brow_l": clampf(float(raw.get("brow_l", 0.0)), -1.0, 1.0), "brow_r": clampf(float(raw.get("brow_r", 0.0)), -1.0, 1.0),
		"eye_yaw_deg": yaw * EYE_YAW_MAX, "eye_pitch_deg": pitch * EYE_PITCH_MAX,
		"blink": clampf(float(raw.get("blink", 0.0)), 0.0, 1.0), "jaw_deg": jaw_f * JAW_MAX_DEG, "vis": vis, "mouth": mouth}


## the head's pose at scene time t from a scene's face keys and lip channel
static func at(face: Dictionary, lip: Dictionary, t: float) -> Dictionary:
	return pose(values_at(face, t), lip, t)


## KEY THE FACE: every channel in `values` written at time t (PartKeys.put: a key at the same time is replaced).
## Values are clamped to their ranges first, so an eye look past 45 deg is keyed at 45 deg.
static func key(face: Dictionary, t: float, values: Dictionary) -> void:
	for ch in CHANNELS:
		if not values.has(ch):
			continue
		var r := range_of(ch)
		PartKeys.put(face, ch, t, Vector3(clampf(float(values[ch]), r.x, r.y), 0.0, 0.0))


## the mirror of a set of raw channel values: brows swap, eye yaw negated (the rest as they are)
static func mirror_values(v: Dictionary) -> Dictionary:
	var out := v.duplicate()
	out["brow_l"] = v.get("brow_r", 0.0)
	out["brow_r"] = v.get("brow_l", 0.0)
	out["eye_yaw"] = -float(v.get("eye_yaw", 0.0))
	return out


## the FILE form of a face (Scene.face as saved) mirrored: keys of brow_l and brow_r swap, eye_yaw keys negate their x.
## Each key keeps its time and its other fields. A face with no such keys comes back as it went in.
static func mirror_file(d: Dictionary) -> Dictionary:
	var out := {}
	for ch in d:
		var nm := String(ch)
		if nm == "brow_l":
			nm = "brow_r"
		elif nm == "brow_r":
			nm = "brow_l"
		var ks := []
		for k in d[ch]:
			var e: Dictionary = (k as Dictionary).duplicate(true)
			if String(ch) == "eye_yaw" and e.get("v") is Array and (e["v"] as Array).size() == 3:
				var a: Array = e["v"]
				e["v"] = [-float(a[0]), a[1], a[2]]
			ks.append(e)
		out[nm] = ks
	return out


## the mouth's size in metres for a shape and a jaw opening (LipSync draws it; the gap is 14 mm at JAW_MAX_DEG of lip sync)
static func mouth_size(shape: String, jaw_deg: float) -> Vector3:
	return LipSync.mouth_size(shape, jaw_deg)


## the file form: PartKeys.to_file (generic over the keys; only the channel names differ from joints)
static func to_file(face: Dictionary) -> Dictionary:
	return PartKeys.to_file(face)


## a face read from the file: only the known channels, each key [t, value] in x. Absent or not a dict = {}.
static func from_file(d: Variant) -> Dictionary:
	var out := {}
	if not d is Dictionary:
		return out
	for ch in CHANNELS:
		if not (d as Dictionary).get(ch) is Array:
			continue
		var ks := []
		for k in d[ch]:
			if k is Dictionary and k.has("t") and k.get("v") is Array and (k["v"] as Array).size() == 3:
				var a: Array = k["v"]
				ks.append({"t": float(k["t"]), "v": Vector3(float(a[0]), float(a[1]), float(a[2]))})
		ks.sort_custom(func(x, y): return float(x["t"]) < float(y["t"]))
		if not ks.is_empty():
			out[ch] = ks
	return out
