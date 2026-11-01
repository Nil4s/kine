## pose_mood.gd - POSE MOODS (Friday plan 140): tired, proud, scared, happy, angry, sad, calm, excited.
## A pose's moods are MEASURED from its body (the joint angles and the joint positions stored in the pose file), never
## from a hand list or from its name. Each rule below is a set of joint angles / distances with a number; the number's
## source is named beside it. The pose is read, never written. PoseTags (the Poses search) appends these tags, and the
## Pose library's mood chips filter by them, so the search, the chips and the test all use measure() and RULES.
##
## Joint conventions are data/body_limits.json's "say": spine bend + = flexion (lean forward); neck / head bend + = chin
## down; clavicle bend + = shrug up, side + = shoulder forward; calf bend + = knee flexion; lowerarm bend + = elbow flexion.
## Facing = (left shoulder - right shoulder) x up, as PoseTags. Angles in degrees, distances in metres.
##
## REFERENCES (the thresholds are conservative readings of these; quoted from memory, not re-fetched; see the test):
##   Coulson M. 2004, J Nonverbal Behav 28:117 - static postures read as emotion: sadness = head bent forward, trunk
##     collapsed, arms hanging; fear = head back, arms raised and bent in front of the body, knees bent (weight back);
##     anger = trunk and shoulders forward, elbows bent; happiness = arms raised, head up.
##   Wallbott H.G. 1998, Eur J Soc Psychol 28:879 - posture and movement coding: pride = erect, expanded chest, head back,
##     shoulders back; sadness / boredom = collapsed upper body, head down; hot anger = arms forward, fists, shoulders up.
##   Tracy J.L., Robins R.W. 2007, Psychol Sci 18:194 - the pride display: head tilted back, expanded chest, shoulders back.
##   Landis C., Hunt W.A. 1939 (The Startle Pattern) - startle: head forward and down, shoulders raised, elbows bent, knees bent.
##   Fon G.T. 1980 / Boyle 1999 - thoracic kyphosis 20-45 deg is normal; a slump adds 15 or more to it (spine_curl below is
##     the ADDED flexion over the rest posture, which already holds the normal curve).
class_name PoseMood
extends RefCounted

const MOODS := ["tired", "proud", "scared", "happy", "angry", "sad", "calm", "excited"]
## words people type for a mood (read as the mood, like PoseTags.SYN)
const SYN := {
	"exhausted": "tired", "sleepy": "tired", "weary": "tired", "drained": "tired", "fatigued": "tired", "drowsy": "tired",
	"confident": "proud", "pride": "proud", "triumphant": "proud", "smug": "proud", "dignified": "proud",
	"afraid": "scared", "frightened": "scared", "fear": "scared", "terrified": "scared", "fearful": "scared", "cowering": "scared",
	"joyful": "happy", "glad": "happy", "cheerful": "happy", "joy": "happy", "delighted": "happy",
	"mad": "angry", "furious": "angry", "rage": "angry", "irate": "angry",
	"unhappy": "sad", "gloomy": "sad", "miserable": "sad", "sorrow": "sad", "depressed": "sad",
	"relaxed": "calm", "peaceful": "calm", "serene": "calm",
	"thrilled": "excited", "eager": "excited", "elated": "excited", "pumped": "excited", "hyped": "excited",
}

# ---- the thresholds (deg unless said), one line each: what it means and where it comes from
const HEAD_DOWN_TIRED := 15.0     # head's long axis pitched forward of vertical (Coulson 2004 sadness / Wallbott boredom: "head bent")
const CURL_TIRED := 15.0          # spine_01..03 bends added: flexion over the rest curve (Fon 1980: a slump adds >= 15)
const TIRED_KNEE_MAX := 30.0      # soft knees only: a deep knee bend is a crouch / cower, not tiredness; and no fists (slack hands)
const SHOULDER_FWD := 5.0         # clavicle forward (side) mean, 1/5 of its 25 deg range
const SHOULDER_DROP := -5.0       # clavicle bend mean at or below this = dropped (range -10..30)
const CURL_PROUD := -6.0          # spine extension: chest up (range of the three bends is -21 at most)
const LEAN_PROUD := 3.0           # trunk (pelvis -> neck base) not leaning forward by more than this
const CHIN_UP_PROUD := -8.0       # head axis tilted back (Tracy & Robins 2007: head tilted back, ~20 deg in their display)
const SHOULDER_BACK := -5.0       # clavicle side mean at or below this = shoulders back
const FACE_REACH := 0.40          # a hand within this of the face centre = arm raised toward the face (forearm + glove length)
const ELBOW_GUARD := 60.0         # that arm's elbow flexion at least (a raised, bent arm, Coulson 2004 fear)
const KNEE_SCARED := 15.0         # mean knee flexion at least (Landis & Hunt: knees bend in the startle / flinch)
const HEAD_AWAY := 10.0           # |head pitch| at least: head pulled back (<0) or down (>0)
const HANDS_ABOVE_SHOULDER := 0.05  # happy: both wrists this far above the shoulders
const HANDS_APART := 0.60         # ... and this far apart (open arms, not a clasp)
const HEAD_UP_HAPPY := 5.0        # ... head not pitched down by more than this
const ANGRY_ELBOW := 60.0         # both elbows flexed at least
const ANGRY_FORWARD := 0.15       # both wrists this far in front of the chest (spine_03)
const ANGRY_LEAN := 8.0           # trunk leans forward at least (Coulson: anger = trunk forward)
const ANGRY_FIST := 50.0          # mean knuckle (finger_01) flexion of both hands: a fist (Wallbott: hot anger = fists)
const SAD_LIMP_ELBOW := 40.0      # sad: both elbows flexed less than this (arms hang)
const SAD_CURL := 8.0             # spine flexion at least
const CALM_LEAN := 5.0            # |trunk lean| at most
const CALM_HEAD := 8.0            # |head pitch| at most
const CALM_HANDS_BELOW := 0.25    # both wrists at least this far below the shoulders
const CALM_SHOULDERS := -2.0      # calm: shoulders let down (clavicle bend mean at or below this), which the bare rest stand does not have
const CALM_KNEE := 10.0           # both knees nearly straight
const EXCITED_KNEE := 10.0        # excited: both hands above the head top AND knees bent this much (a bounce)

const RULES := {
	"tired": "head pitched down >= 15 deg, spine flexed >= 15 deg (added over rest), shoulders forward >= 5 deg or dropped >= 5 deg, knees bent < 30 deg, no fists",
	"proud": "spine extended >= 6 deg (chest up), trunk not leaning forward (<= 3 deg), chin up >= 8 deg, shoulders back >= 5 deg",
	"scared": "a hand within 0.40 m of the face with its elbow bent >= 60 deg, knees bent >= 15 deg (mean), head pulled back or down >= 10 deg",
	"happy": "both wrists >= 5 cm above the shoulders and >= 0.60 m apart, head not pitched down more than 5 deg, spine not flexed > 5 deg",
	"angry": "both elbows bent >= 60 deg, both wrists >= 0.15 m in front of the chest, trunk leaning forward >= 8 deg, both hands in a fist (>= 50 deg)",
	"sad": "head pitched down >= 15 deg, spine flexed >= 8 deg, both elbows < 40 deg and both wrists below the hips (arms hang)",
	"calm": "trunk within 5 deg of upright, head within 8 deg, both wrists >= 0.25 m below the shoulders, knees within 10 deg of straight, shoulders let down >= 2 deg",
	"excited": "both wrists above the top of the head and knees bent >= 10 deg (mean)",
}


static func _j(d: Dictionary, n: String) -> Dictionary:
	var x = d.get("joints", {}).get(n)
	return x if x is Dictionary else {}


static func _p(d: Dictionary, n: String) -> Vector3:
	var a = _j(d, n).get("pos", null)
	return Vector3(a[0], a[1], a[2]) if a is Array and a.size() >= 3 else Vector3.ZERO


static func _e(d: Dictionary, n: String) -> Vector3:
	var a = _j(d, n).get("end", null)
	return Vector3(a[0], a[1], a[2]) if a is Array and a.size() >= 3 else _p(d, n)


static func _a(d: Dictionary, n: String, k: String) -> float:
	return float(_j(d, n).get(k, 0.0))


## the forward tilt (deg, + = forward) of vector v from vertical, in the facing plane
static func _tilt(v: Vector3, fwd: Vector3) -> float:
	return rad_to_deg(atan2(v.dot(fwd), v.y))


## the named numbers of a pose (a parsed pose file): every rule above reads these and only these
static func measure(d: Dictionary) -> Dictionary:
	var r := {}
	if _j(d, "pelvis").is_empty():
		return r
	var sl := _p(d, "upperarm_l")
	var sr := _p(d, "upperarm_r")
	var fwd := (sl - sr).cross(Vector3.UP)
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.001 else Vector3.BACK
	var pel := _p(d, "pelvis")
	var head_c := (_p(d, "head") + _e(d, "head")) * 0.5
	var chest := _p(d, "spine_03")
	r["head_down"] = _tilt(_e(d, "head") - _p(d, "head"), fwd)
	r["trunk_lean"] = _tilt(_p(d, "neck_01") - pel, fwd)
	r["spine_curl"] = _a(d, "spine_01", "bend") + _a(d, "spine_02", "bend") + _a(d, "spine_03", "bend")
	r["shoulder_fwd"] = (_a(d, "clavicle_l", "side") + _a(d, "clavicle_r", "side")) * 0.5
	r["shoulder_up"] = (_a(d, "clavicle_l", "bend") + _a(d, "clavicle_r", "bend")) * 0.5
	r["knee_flex"] = (_a(d, "calf_l", "bend") + _a(d, "calf_r", "bend")) * 0.5
	r["elbow_l"] = _a(d, "lowerarm_l", "bend")
	r["elbow_r"] = _a(d, "lowerarm_r", "bend")
	var hl := _p(d, "hand_l")
	var hr := _p(d, "hand_r")
	r["face_l"] = hl.distance_to(head_c)
	r["face_r"] = hr.distance_to(head_c)
	r["wrist_above_shoulder_l"] = hl.y - sl.y
	r["wrist_above_shoulder_r"] = hr.y - sr.y
	r["wrist_above_hips_l"] = hl.y - pel.y
	r["wrist_above_hips_r"] = hr.y - pel.y
	r["wrist_above_head_l"] = hl.y - _e(d, "head").y
	r["wrist_above_head_r"] = hr.y - _e(d, "head").y
	r["hands_apart"] = hl.distance_to(hr)
	r["wrist_fwd_l"] = (hl - chest).dot(fwd)
	r["wrist_fwd_r"] = (hr - chest).dot(fwd)
	var fist := 0.0
	var n := 0
	for s in ["l", "r"]:
		for f in ["index", "middle", "ring", "pinky"]:
			fist += _a(d, "%s_01_%s" % [f, s], "bend")
			n += 1
	r["fist"] = fist / maxf(1, n)
	return r


## the rule of each mood on measure()'s numbers: true / false
static func holds(mood: String, r: Dictionary) -> bool:
	if r.is_empty():
		return false
	match mood:
		"tired":
			return r["head_down"] >= HEAD_DOWN_TIRED and r["spine_curl"] >= CURL_TIRED \
				and (r["shoulder_fwd"] >= SHOULDER_FWD or r["shoulder_up"] <= SHOULDER_DROP) 				and r["knee_flex"] < TIRED_KNEE_MAX and r["fist"] < ANGRY_FIST
		"proud":
			return r["spine_curl"] <= CURL_PROUD and r["trunk_lean"] <= LEAN_PROUD and r["head_down"] <= CHIN_UP_PROUD \
				and r["shoulder_fwd"] <= SHOULDER_BACK
		"scared":
			var guard: bool = (r["face_l"] <= FACE_REACH and r["elbow_l"] >= ELBOW_GUARD) or (r["face_r"] <= FACE_REACH and r["elbow_r"] >= ELBOW_GUARD)
			return guard and r["knee_flex"] >= KNEE_SCARED and absf(r["head_down"]) >= HEAD_AWAY
		"happy":
			return r["wrist_above_shoulder_l"] >= HANDS_ABOVE_SHOULDER and r["wrist_above_shoulder_r"] >= HANDS_ABOVE_SHOULDER \
				and r["hands_apart"] >= HANDS_APART and r["head_down"] <= HEAD_UP_HAPPY and r["spine_curl"] <= 5.0
		"angry":
			return r["elbow_l"] >= ANGRY_ELBOW and r["elbow_r"] >= ANGRY_ELBOW and r["wrist_fwd_l"] >= ANGRY_FORWARD \
				and r["wrist_fwd_r"] >= ANGRY_FORWARD and r["trunk_lean"] >= ANGRY_LEAN and r["fist"] >= ANGRY_FIST
		"sad":
			return r["head_down"] >= HEAD_DOWN_TIRED and r["spine_curl"] >= SAD_CURL and r["elbow_l"] < SAD_LIMP_ELBOW \
				and r["elbow_r"] < SAD_LIMP_ELBOW and r["wrist_above_hips_l"] < 0.0 and r["wrist_above_hips_r"] < 0.0
		"calm":
			return absf(r["trunk_lean"]) <= CALM_LEAN and absf(r["head_down"]) <= CALM_HEAD \
				and r["wrist_above_shoulder_l"] <= -CALM_HANDS_BELOW and r["wrist_above_shoulder_r"] <= -CALM_HANDS_BELOW \
				and r["knee_flex"] <= CALM_KNEE and r["shoulder_up"] <= CALM_SHOULDERS
		"excited":
			return r["wrist_above_head_l"] >= 0.0 and r["wrist_above_head_r"] >= 0.0 and r["knee_flex"] >= EXCITED_KNEE
	return false


## the moods of one pose (a parsed pose file), in MOODS order
static func tags_of(d: Dictionary) -> Array:
	var r := measure(d)
	var out := []
	for md in MOODS:
		if holds(md, r):
			out.append(md)
	return out


## the mood a typed word means ("exhausted" -> "tired"), or "" when it is not a mood word
static func canon(word: String) -> String:
	var w := word.to_lower().strip_edges()
	if w in MOODS:
		return w
	if SYN.has(w):
		return String(SYN[w])
	if w.length() >= 4:   # one slip forgiven ("tird", "scarred", "prould"): a mood word only, never a pose name
		for md in MOODS:
			if _within_one(w, md):
				return md
	return ""


## true when a and b differ by one letter added, dropped, changed or two neighbours swapped
static func _within_one(a: String, b: String) -> bool:
	if a == b:
		return true
	var la := a.length()
	var lb := b.length()
	if absi(la - lb) > 1:
		return false
	if la == lb:
		var diff := []
		for i in la:
			if a[i] != b[i]:
				diff.append(i)
		return diff.size() == 1 or (diff.size() == 2 and diff[1] == diff[0] + 1 and a[diff[0]] == b[diff[1]] and a[diff[1]] == b[diff[0]])
	var s := a if la < lb else b
	var l := b if la < lb else a
	for i in l.length():
		if l.substr(0, i) + l.substr(i + 1) == s:
			return true
	return false


## the moods of a pose FILE, remembered by (path, modified time) so a grid of chips does not parse the library again
static var _memo := {}


static func tags_of_file(path: String) -> Array:
	var mt := FileAccess.get_modified_time(path)
	var hit = _memo.get(path)
	if hit is Array and hit[0] == mt:
		return hit[1]
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	var t: Array = tags_of(d) if d is Dictionary else []
	_memo[path] = [mt, t]
	return t
