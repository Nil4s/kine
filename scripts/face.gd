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
##   squint, widen, press  0..1  lids tight (AU6/7), upper lid raised (AU5), lips pressed (AU23/24): the same three the expression
##                           cards use (EXPR_AU), keyed here by the words box (scripts/face_words.gd, ROADMAP I20).
##   vis_M/A/O/E      0..1   visemes: M = closed (M, B, P: lips shut), A = open, O = round, E = wide (E, I). The same four
##                           shapes LipSync emits (lip_sync.gd: S shows as E). Each viseme opens the jaw by VIS_JAW x its weight.
## LIP SYNC: when Scene.lip has a channel, it DRIVES the jaw and the visemes at the playhead (LipSync.jaw_at, shape_at), and the
## face keys for jaw and visemes are ignored there. The brows, eyes and blink still come from the keys.
## EXPRESSIONS (round 2, R22): neutral, pain, effort, anger, surprise, keyed on a CARD (card["expr"], Scene.expr_at blends the
##   weights between cards) and built from FACS action units (Ekman & Friesen, Facial Action Coding System, 1978; Ekman, Friesen &
##   Hager 2002), each AU drawn by the brows / eyes / mouth the rig has. EXPR_AU holds the table. Prototypes, FACS pain (Prkachin
##   1992, "The consistency of facial expressions of pain"): brow lowering AU4, orbit tightening AU6/7, levator contraction AU9/10,
##   eyes closed AU43. Effort: AU4+7+24 (brows down, lids tight, lips pressed). Anger: AU4+5+7+23. Surprise: AU1+2+5+26.
## MIRROR: L/R swap (brow_l <-> brow_r) and the eye yaw negated. Twice is the original (Face.mirror_file, scene mirror).
class_name Face
extends RefCounted

const CHANNELS := ["brow_l", "brow_r", "jaw", "eye_yaw", "eye_pitch", "blink", "vis_M", "vis_A", "vis_O", "vis_E", "squint", "widen", "press"]
const VISEMES := ["M", "A", "O", "E"]
const JAW_MAX_DEG := 27.5     # deg: the jaw at jaw = 1.0 (middle of the cited 25-30 deg)
const EYE_YAW_MAX := 45.0     # deg: the eye at eye_yaw = +-1 (the cited horizontal gaze range)
const EYE_PITCH_MAX := 30.0   # deg: the eye at eye_pitch = +-1
const VIS_JAW := {"M": 0.0, "A": 1.0, "O": 0.7, "E": 0.45}   # the jaw factor per viseme (the same as LipSync.JAW_K)
const SHOW := 0.05            # a viseme weight at or above this is the mouth shape

## WHERE THE FEATURES SIT (measured on the visible head mesh, not on the contact capsule: the capsule is a proxy that runs from
## the neck into the skull, its centre is NOT the middle of the face). Proportions, adult head, vertex to chin (menton) = H:
##   eye line   H * 0.5 above the chin: the eyes are halfway between the top of the head and the chin (Farkas, Anthropometry of the
##              Head and Face, 2nd ed. 1994; the artists' rule agrees).
##   IPD        63 mm, the adult mean between the pupils (Dodgson 2004, Variation and extrema of human interpupillary distance).
##   stomion    the mouth line: the nose base (subnasale) is about 0.30 H above the chin and the mouth 1/3 of the way down from it
##              to the chin, so about 0.20 H above the chin (Farkas 1994: subnasale-menton ~ 70 mm and stomion-menton ~ 45 mm
##              in a ~ 230 mm head).
##   brow       the brow line about 0.09 H above the eye line (~ 2.2 cm in an adult).
##   mouth      about 50 mm wide, corner to corner (Farkas 1994, cheilion-cheilion); LipSync.mouth_size is half that, so it is
##              drawn MOUTH_W_K times wider.
## Figures are from memory of those sources, not re-checked against the papers here.
const EXPRESSIONS := ["neutral", "pain", "effort", "anger", "surprise"]
## per expression, the AU intensities (FACS A-E scale as 0..1: B 0.3, C 0.5, D 0.8, E 1.0) turned into this rig's channels:
##   brow  both brows (+ raise: AU1+2, - lower: AU4)    squint  lids tight (AU6/7)      widen  upper lid raised (AU5)
##   blink eyes shut (AU43)    press  lips pressed / tightened (AU23/24)    jaw  mouth opened (AU26/27, fraction of JAW_MAX_DEG)
##   shape  the mouth shape that expression shows once it is at 0.5 or more (AU9/10 bared teeth = the wide E shape; AU26 = round O)
const EXPR_AU := {
	"neutral": {"au": "none", "brow": 0.0, "squint": 0.0, "widen": 0.0, "blink": 0.0, "press": 0.0, "jaw": 0.0, "shape": ""},
	"pain": {"au": "AU4+6/7+9/10+43", "brow": -0.8, "squint": 0.8, "widen": 0.0, "blink": 0.6, "press": 0.0, "jaw": 0.2, "shape": "E"},
	"effort": {"au": "AU4+7+24", "brow": -0.5, "squint": 0.6, "widen": 0.0, "blink": 0.0, "press": 0.9, "jaw": 0.0, "shape": ""},
	"anger": {"au": "AU4+5+7+23", "brow": -0.9, "squint": 0.4, "widen": 0.6, "blink": 0.0, "press": 0.8, "jaw": 0.0, "shape": ""},
	"surprise": {"au": "AU1+2+5+26", "brow": 0.9, "squint": 0.0, "widen": 1.0, "blink": 0.0, "press": 0.0, "jaw": 0.7, "shape": "O"}}
const HIT_WORDS := ["hit", "reaction", "react", "flinch", "struck"]


## the expression a card of this name should wear by default: pain for a hit / reaction card, else "" (no suggestion)
static func suggest(card_name: String) -> String:
	var n := card_name.to_lower()
	for w in HIT_WORDS:
		if n.begins_with(w) or n.contains(" " + w) or n.contains("_" + w):
			return "pain"
	return ""


## the weighted sum of the AU channels for a weights dict {name: 0..1} (neutral adds nothing)
static func expr_delta(w: Dictionary) -> Dictionary:
	var d := {"brow": 0.0, "squint": 0.0, "widen": 0.0, "blink": 0.0, "press": 0.0, "jaw": 0.0, "shape": "", "shape_w": 0.0}
	for nm in w:
		if not EXPR_AU.has(nm) or nm == "neutral":
			continue
		var k := clampf(float(w[nm]), 0.0, 1.0)
		var e: Dictionary = EXPR_AU[nm]
		for ch in ["brow", "squint", "widen", "blink", "press", "jaw"]:
			d[ch] = float(d[ch]) + k * float(e[ch])
		if String(e["shape"]) != "" and k >= 0.5 and k > float(d["shape_w"]):
			d["shape"] = e["shape"]
			d["shape_w"] = k
	return d


const IPD := 0.063
const EYE_LINE := 0.5
const BROW_ABOVE := 0.09
const MOUTH_LINE := 0.20
const MOUTH_W_K := 2.0
const EYE_SIZE := Vector3(0.028, 0.016, 0.008)   # m: the white of the eye (palpebral fissure ~ 28-30 mm wide)
const IRIS_D := 0.012                             # m: the visible iris ~ 12 mm
const BROW_SIZE := Vector3(0.046, 0.006, 0.006)


## the surface of the mesh in FRONT at (x, y): the largest z where a ray along -z meets one of the triangles. pts = the corners,
## three per triangle (rest space, +Z = the hero's front). -INF if the line misses the mesh.
static func surface_z(pts: PackedVector3Array, x: float, y: float) -> float:
	var best := -INF
	for t in range(0, pts.size() - 2, 3):
		var h: Variant = Geometry3D.ray_intersects_triangle(Vector3(x, y, 1.0), Vector3(0, 0, -1), pts[t], pts[t + 1], pts[t + 2])
		if h != null:
			best = maxf(best, (h as Vector3).z)
	return best


## the face's anchor points in REST space, read off the head mesh's triangle corners `pts` (the head piece of the mannequin):
## {"top", "chin", "H", "eye_l", "eye_r", "brow_l", "brow_r", "mouth"}. Each point lies ON the front surface of the mesh.
## The chin is the lowest point of the front midline (within 4 cm of the face front), so the neck below it is not counted.
static func anchors(pts: PackedVector3Array) -> Dictionary:
	if pts.is_empty():
		return {}
	var top := -INF
	var zf := -INF
	for v in pts:
		top = maxf(top, v.y)
		zf = maxf(zf, v.z)
	var chin := INF
	for v in pts:
		if absf(v.x) < 0.005 and v.z > zf - 0.04:
			chin = minf(chin, v.y)
	var h := top - chin
	var ey := chin + EYE_LINE * h
	var by := ey + BROW_ABOVE * h
	var my := chin + MOUTH_LINE * h
	var hx := IPD * 0.5
	return {"top": top, "chin": chin, "H": h,
		"eye_l": Vector3(hx, ey, surface_z(pts, hx, ey)), "eye_r": Vector3(-hx, ey, surface_z(pts, -hx, ey)),
		"brow_l": Vector3(hx, by, surface_z(pts, hx, by)), "brow_r": Vector3(-hx, by, surface_z(pts, -hx, by)),
		"mouth": Vector3(0.0, my, surface_z(pts, 0.0, my))}


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
static func pose(raw_in: Dictionary, lip: Dictionary = {}, t := 0.0, expr: Dictionary = {}) -> Dictionary:
	var raw := raw_in
	var ed := expr_delta(expr)
	if not expr.is_empty():
		raw = raw_in.duplicate()
		raw["brow_l"] = float(raw.get("brow_l", 0.0)) + float(ed["brow"])
		raw["brow_r"] = float(raw.get("brow_r", 0.0)) + float(ed["brow"])
		raw["jaw"] = float(raw.get("jaw", 0.0)) + float(ed["jaw"])
		raw["blink"] = float(raw.get("blink", 0.0)) + float(ed["blink"])
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
	if String(ed["shape"]) != "" and mouth in ["M", "A"]:
		mouth = String(ed["shape"])
	var yaw := clampf(float(raw.get("eye_yaw", 0.0)), -1.0, 1.0)
	var pitch := clampf(float(raw.get("eye_pitch", 0.0)), -1.0, 1.0)
	return {"brow_l": clampf(float(raw.get("brow_l", 0.0)), -1.0, 1.0), "brow_r": clampf(float(raw.get("brow_r", 0.0)), -1.0, 1.0),
		"eye_yaw_deg": yaw * EYE_YAW_MAX, "eye_pitch_deg": pitch * EYE_PITCH_MAX,
		"blink": clampf(float(raw.get("blink", 0.0)), 0.0, 1.0), "jaw_deg": jaw_f * JAW_MAX_DEG, "vis": vis, "mouth": mouth,
		"squint": clampf(float(raw.get("squint", 0.0)) + float(ed["squint"]), 0.0, 1.0), "widen": clampf(float(raw.get("widen", 0.0)) + float(ed["widen"]), 0.0, 1.0),
		"press": clampf(float(raw.get("press", 0.0)) + float(ed["press"]), 0.0, 1.0)}


## the head's pose at scene time t from a scene's face keys and lip channel
static func at(face: Dictionary, lip: Dictionary, t: float, expr: Dictionary = {}) -> Dictionary:
	return pose(values_at(face, t), lip, t, expr)


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
	var out := PartKeys.to_file(face)
	for ch in out:   # I08: a generated key keeps its "gen" tag (EyeLife.remove finds it after a reload)
		for i in (out[ch] as Array).size():
			if (face[ch][i] as Dictionary).has("gen"):
				out[ch][i]["gen"] = String(face[ch][i]["gen"])
	return out


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
				if k.get("gen") is String:
					ks[-1]["gen"] = k["gen"]   # I08: the generator's tag
		ks.sort_custom(func(x, y): return float(x["t"]) < float(y["t"]))
		if not ks.is_empty():
			out[ch] = ks
	return out
