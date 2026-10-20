## say_it.gd - SAY IT, SEE IT (ROADMAP Innovations I5): type a pose in words, get the pose. Fully local: a small hand-built
## grammar + vocabulary, no cloud, no LLM. "low guard, weight on back foot, bat cocked over right shoulder".
## A sentence is phrases (split at "," ";" "and" "then" "while"). Each phrase is read by the matchers below; a matcher claims
## the words it understands and adds CONSTRAINTS to a plan; a word nobody claims is reported back, never ignored. The plan is
## then solved with the app's own solvers, in this order (each step keeps what the one before placed):
##   library   a phrase whose every content word is in a saved pose's name (poses/, poses/lib/) starts from that pose
##   legs      stance width / stagger / crouch / lunge: both feet planted by Body.plant (IK, limits), the pelvis lowered until the
##             legs reach (a crouch drops the hips by a fraction of the standing hip height, the hips go back a third of it)
##   trunk     lean / twist: Body.back_bend (shared over the spine)
##   arms      guard (hands in the chest's frame), hand on/at/over/near a landmark, the weapon's hand: LimbIK.solve (two-bone IK
##             with an elbow pole, joint limits clamp); a weapon cocked over/behind/across a landmark: the grip from the app's
##             standard grip file, Body.aim_weapon turns the hand and rolls the arm so the shaft points from the grip to a point
##             beside the landmark
##   joints    "left knee bent 90", "elbow 90": the angle itself (Body.set_ang_safe: limits and contacts stop it, and the report
##             says what was reached); PoseWords' verbs ("raise the right arm 90") are the fallback
##   weight    "weight on back foot": the centre of mass (Balance.com, de Leva) moved over that foot by shifting the pelvis and
##             re-planting the feet; WITHOUT a weight phrase a pose whose centre of mass is outside its feet is brought inside
##   look      LookAt.solve toward a point (left, right, down, the hand, the bat...)
## Every constraint is CHECKED afterwards on the finished pose; the report has one line per phrase: "placed",
## "partly placed (why)" or "not understood". Nothing here writes a file; the caller makes it one undo step (main._say_it).
## apply(B, text) -> {ok, lines: [String], items: [{phrase, status, why}], unknown: [word], start: String, ms}
class_name SayIt
extends RefCounted

const FILLER := ["the", "a", "an", "his", "her", "my", "your", "their", "is", "are", "be", "with", "of", "it", "that", "please",
	"degrees", "degree", "deg", "slightly", "bit", "little", "pose", "position", "stand", "standing", "stay", "keep", "put", "get", "make", "has", "have", "while"]
const PREP := ["on", "at", "over", "near", "onto", "to", "in", "by", "behind", "across", "above", "up", "down", "from", "toward", "towards", "against", "beside", "under", "into", "out"]
const WEAPONS := {"bat": "metal_bat", "club": "metal_bat", "weapon": "", "sword": "sword", "longsword": "longsword", "katana": "katana", "spear": "spear", "staff": "staff", "bo": "staff",
	"axe": "long_axe", "hammer": "long_hammer", "dagger": "dagger", "knife": "dagger"}
const MODE_WORDS := ["cocked", "cock", "ready", "raised", "held", "resting", "rested", "slung", "carried", "poised", "drawn", "lifted"]
const HANDS := ["hand", "hands", "fist", "fists", "palm", "palms"]
## landmark word -> [kind, where]; where() is _landmark
const LANDMARKS := ["head", "chin", "face", "mouth", "forehead", "ear", "chest", "belly", "stomach", "hip", "hips", "shoulder", "shoulders",
	"knee", "knees", "waist", "back", "neck", "eyes", "eye"]
const JOINT_NUM := {"knee": "calf", "elbow": "lowerarm", "hip": "thigh", "wrist": "hand", "ankle": "foot"}
const STANDING_HIP := 0.0   # (unused: the standing height is read from the body each time)

# ---- the stance numbers (m). Sources are in the comments; the rest is mine and is checked by tests/i5_test.gd ----
const SPREAD_DEFAULT := 0.16     # half the feet's distance apart for an athletic stance: ~ shoulder width 0.38 m (ANSUR II male biacromial/2 ~ 0.2) -> feet a bit under it
const SPREAD_WIDE := 0.30
const SPREAD_NARROW := 0.05
const STAGGER := 0.18            # half the front-back distance of a ready stance (a boxer's lead foot is ~ 0.35-0.45 m ahead)
const LUNGE_HALF := 0.42         # a lunge step is ~ 0.85 m (leg length ~ 0.9 m)
const CROUCH_DEFAULT := 0.30     # fraction of the standing hip height the hips drop
const CROUCH_DEEP := 0.42
const CROUCH_LIGHT := 0.15
const GUARD_Z := 0.30            # wrists this far in front of the chest base, along the chest's forward
const GUARD_X := 0.17
const WEIGHT_TOWARD := 0.12      # "weight on the back foot": the centre of mass this share of the way from that foot to the other


static func _err(msg: String) -> Dictionary:
	return {"ok": false, "error": msg}


# ------------------------------------------------------------------------------------------------ reading the sentence
static func split(text: String) -> Array:
	var t := text.to_lower().replace("°", " ").replace(";", ",").replace(" and ", ",").replace(" then ", ",").replace(" while ", ",").replace(" plus ", ",")
	var out := []
	for p in t.split(",", false):
		var toks := []
		for w: String in p.strip_edges().split(" ", false):
			w = w.strip_edges().trim_suffix(".").trim_suffix("!").trim_suffix("?")
			if w != "":
				toks.append(w)
		if not toks.is_empty():
			out.append({"text": p.strip_edges(), "toks": toks, "used": []})
	for ph in out:
		ph["used"] = []
		for i in ph["toks"].size():
			ph["used"].append(false)
	return out


static func _has(ph: Dictionary, words: Array) -> int:
	for i in ph["toks"].size():
		if not ph["used"][i] and ph["toks"][i] in words:
			return i
	return -1


static func _claim(ph: Dictionary, words: Array) -> String:
	var i := _has(ph, words)
	if i < 0:
		return ""
	ph["used"][i] = true
	return ph["toks"][i]


static func _claim_all(ph: Dictionary, words: Array) -> void:
	for i in ph["toks"].size():
		if ph["toks"][i] in words:
			ph["used"][i] = true


static func _num(ph: Dictionary) -> float:
	for i in ph["toks"].size():
		if not ph["used"][i] and String(ph["toks"][i]).is_valid_float():
			ph["used"][i] = true
			return float(ph["toks"][i])
	return NAN


static func _side(ph: Dictionary) -> String:
	var s := _claim(ph, ["left", "right"])
	return "" if s == "" else ("_l" if s == "left" else "_r")


## front/back words -> "front" | "back" | ""
static func _fb(ph: Dictionary) -> String:
	var w := _claim(ph, ["front", "forward", "lead", "leading", "forwards", "back", "rear", "trail", "trailing", "backward", "backwards"])
	if w == "":
		return ""
	return "front" if w in ["front", "forward", "forwards", "lead", "leading"] else "back"


# ------------------------------------------------------------------------------------------------ the matchers
## Each adds items to the plan. An item: {phrase: index, kind, ...}. kind in: crouch, stance, lunge, weight, guard, hand, weapon,
## joint, look, lean, twist, kick, words (PoseWords ops).
static func _read(phs: Array) -> Dictionary:
	var plan := {"items": [], "weapon_word": false}
	for pi in phs.size():
		var ph: Dictionary = phs[pi]
		var n0: int = plan["items"].size()
		_m_weapon(ph, pi, plan)
		_m_hand(ph, pi, plan)
		_m_guard(ph, pi, plan)
		_m_crouch(ph, pi, plan)
		_m_lunge(ph, pi, plan)
		_m_stance(ph, pi, plan)
		_m_weight(ph, pi, plan)
		_m_kick(ph, pi, plan)
		_m_look(ph, pi, plan)
		_m_lean(ph, pi, plan)
		_m_joint(ph, pi, plan)
		if plan["items"].size() == n0 or _left(ph).size() > 0:
			_m_words(ph, pi, plan, plan["items"].size() == n0)
	return plan


static func _left(ph: Dictionary) -> Array:
	var out := []
	for i in ph["toks"].size():
		var w: String = ph["toks"][i]
		if not ph["used"][i] and not (w in FILLER) and not (w in PREP):
			out.append(w)
	return out


static func _m_weapon(ph: Dictionary, pi: int, plan: Dictionary) -> void:
	var i := _has(ph, WEAPONS.keys())
	if i < 0:
		return
	var w: String = ph["toks"][i]
	ph["used"][i] = true
	var it := {"phrase": pi, "kind": "weapon", "wkind": WEAPONS[w], "mode": "ready", "land": "", "lside": "", "hand": "", "low": false}
	plan["weapon_word"] = true
	_claim_all(ph, ["in"])
	var mode := _claim(ph, MODE_WORDS)
	if mode != "":
		it["mode"] = "cock" if mode in ["cocked", "cock", "drawn", "poised"] else "ready"
	var prep := _claim(ph, ["over", "behind", "across", "above", "on", "at", "against", "beside", "near"])
	if prep != "":
		it["prep"] = prep
	var lowhi := _claim(ph, ["low", "high", "down", "up"])
	if lowhi != "":
		it["vert"] = lowhi
	var sd := _side(ph)
	var lm := _claim(ph, LANDMARKS)
	if lm == "":
		# "bat in right hand"
		if _claim(ph, HANDS) != "":
			it["hand"] = sd
			sd = ""
	it["lside"] = sd
	it["land"] = lm
	plan["items"].append(it)


static func _m_hand(ph: Dictionary, pi: int, plan: Dictionary) -> void:
	var i := _has(ph, HANDS)
	if i < 0:
		return
	# "hands on hips", "right hand near chin", "left hand over the face"; no landmark: "hands up" is a high guard (matcher below)
	var save_used: Array = ph["used"].duplicate()
	ph["used"][i] = true
	var hsd := ""
	var lside := ""
	# a side before the hand word is the hand's, a side after the preposition is the landmark's
	for k in ph["toks"].size():
		if ph["toks"][k] in ["left", "right"] and not ph["used"][k]:
			if k < i:
				hsd = "_l" if ph["toks"][k] == "left" else "_r"
				ph["used"][k] = true
	var prep := _claim(ph, ["on", "at", "over", "near", "against", "beside", "to", "by"])
	lside = _side(ph)
	var lm := _claim(ph, LANDMARKS)
	if lm == "":
		ph["used"] = save_used
		return
	plan["items"].append({"phrase": pi, "kind": "hand", "hand": hsd, "land": lm, "lside": lside, "prep": prep if prep != "" else "on"})


static func _m_guard(ph: Dictionary, pi: int, plan: Dictionary) -> void:
	var g := _has(ph, ["guard", "guarding", "block", "blocking"])
	var hu := _has(ph, HANDS)
	var it := {"phrase": pi, "kind": "guard", "height": "mid"}
	if g >= 0:
		ph["used"][g] = true
		var h := _claim(ph, ["low", "high", "mid", "middle", "up", "down"])
		if h in ["low", "down"]:
			it["height"] = "low"
		elif h in ["high", "up"]:
			it["height"] = "high"
		_claim_all(ph, ["fists", "fist", "hands", "hand", "boxing", "fighting", "ready"])
		plan["items"].append(it)
	elif hu >= 0:
		# "hands up" / "hands down" / "hands low" (no landmark: that is _m_hand's)
		for k in ph["toks"].size():
			if ph["toks"][k] in ["up", "high", "down", "low"] and not ph["used"][k]:
				it["height"] = "high" if ph["toks"][k] in ["up", "high"] else "low"
				ph["used"][k] = true
				ph["used"][hu] = true
				plan["items"].append(it)
				return


static func _m_crouch(ph: Dictionary, pi: int, plan: Dictionary) -> void:
	var c := _has(ph, ["crouch", "crouching", "crouched", "squat", "squatting", "duck", "ducking", "sink", "sunk", "hunker", "hunched"])
	var stance_low := _has(ph, ["stance"]) >= 0 and _has(ph, ["low", "deep"]) >= 0
	var getlow := _has(ph, ["get", "go", "stay"]) >= 0 and _has(ph, ["low"]) >= 0
	if c < 0 and not stance_low and not getlow:
		return
	var frac := CROUCH_DEFAULT
	if c >= 0:
		ph["used"][c] = true
	var m := _claim(ph, ["deep", "low", "deeply", "lower", "slight", "slightly", "little", "light", "half"])
	if m in ["deep", "low", "deeply", "lower"]:
		frac = CROUCH_DEEP
	elif m in ["slight", "slightly", "little", "light", "half"]:
		frac = CROUCH_LIGHT
	_claim_all(ph, ["get", "go", "stay"])
	var nm := _num(ph)
	if not is_nan(nm) and nm > 0.0 and nm < 100.0:
		frac = nm / 100.0   # "crouch 40" = the hips drop 40 % of their standing height
	plan["items"].append({"phrase": pi, "kind": "crouch", "frac": frac})


static func _m_lunge(ph: Dictionary, pi: int, plan: Dictionary) -> void:
	if _has(ph, ["lunge", "lunging", "lunged"]) < 0:
		return
	_claim(ph, ["lunge", "lunging", "lunged"])
	var sd := _side(ph)
	_claim_all(ph, ["forward", "forwards", "step"])
	plan["items"].append({"phrase": pi, "kind": "lunge", "lead": sd})


static func _m_stance(ph: Dictionary, pi: int, plan: Dictionary) -> void:
	var st := _has(ph, ["stance", "feet", "foot", "legs", "feet.", "footed"])
	var wide := _has(ph, ["wide", "wider", "apart", "broad"])
	var nar := _has(ph, ["narrow", "narrower", "together", "close", "closed"])
	if wide < 0 and nar < 0:
		return
	if st < 0 and _has(ph, ["weight"]) >= 0:
		return
	var it := {"phrase": pi, "kind": "stance", "spread": SPREAD_WIDE if wide >= 0 else SPREAD_NARROW, "stagger": 0.0}
	if wide >= 0:
		ph["used"][wide] = true
	if nar >= 0:
		ph["used"][nar] = true
	if st >= 0:
		ph["used"][st] = true
	_claim_all(ph, ["fighting", "boxing", "ready", "athletic"])
	plan["items"].append(it)


static func _m_weight(ph: Dictionary, pi: int, plan: Dictionary) -> void:
	if _has(ph, ["weight", "weighted", "balance", "balanced", "load", "loaded"]) < 0:
		return
	var w := _claim(ph, ["weight", "weighted", "balance", "balanced", "load", "loaded"])
	var sd := _side(ph)
	var fb := _fb(ph)
	_claim_all(ph, ["foot", "leg", "side", "heel", "heels", "toes", "ball", "shifted", "shift", "centered", "centred", "centre", "center", "even", "evenly"])
	if sd == "" and fb == "":
		if _has(ph, ["even", "evenly", "centered", "centre", "center"]) >= 0 or w in ["balanced", "balance"]:
			plan["items"].append({"phrase": pi, "kind": "weight", "foot": "even", "fb": "", "side": ""})
			return
		return   # "weight" alone: left to the leftovers
	plan["items"].append({"phrase": pi, "kind": "weight", "foot": "side" if sd != "" else "fb", "fb": fb, "side": sd})


static func _m_kick(ph: Dictionary, pi: int, plan: Dictionary) -> void:
	if _has(ph, ["kick", "kicking", "knee"]) < 0:
		return
	var k := _has(ph, ["kick", "kicking"])
	if k < 0:
		return
	ph["used"][k] = true
	var h := _claim(ph, ["low", "high", "mid", "middle"])
	var sd := _side(ph)
	var fb := _fb(ph)
	var side_kick := _claim(ph, ["side", "sidekick"]) != ""
	plan["items"].append({"phrase": pi, "kind": "kick", "height": h if h != "" else "mid", "side": sd if sd != "" else "_r", "back": fb == "back", "sidekick": side_kick})


static func _m_look(ph: Dictionary, pi: int, plan: Dictionary) -> void:
	var l := _has(ph, ["look", "looking", "gaze", "gazing", "watch", "watching", "stare", "staring", "eyes", "eye", "face", "facing"])
	if l < 0:
		return
	# "face" is a landmark for hands ("hand over face"); only a look word starts a look
	var lw := _has(ph, ["look", "looking", "gaze", "gazing", "watch", "watching", "stare", "staring"])
	if lw < 0:
		return
	ph["used"][lw] = true
	_claim_all(ph, ["eyes", "eye"])
	var tgt := _claim(ph, ["left", "right", "down", "up", "ahead", "forward", "straight", "floor", "ground", "sky", "ceiling", "hand", "hands", "bat", "weapon", "tip", "back", "behind"])
	if tgt in ["hand", "hands"]:
		var sd := _side(ph)
		plan["items"].append({"phrase": pi, "kind": "look", "at": "hand", "side": sd if sd != "" else "_r"})
		return
	if tgt == "":
		return
	_claim_all(ph, ["at"])
	plan["items"].append({"phrase": pi, "kind": "look", "at": tgt})


static func _m_lean(ph: Dictionary, pi: int, plan: Dictionary) -> void:
	var l := _has(ph, ["lean", "leaning", "leaned", "tilt", "bend", "bent", "hunch"])
	var t := _has(ph, ["twist", "twisted", "twisting", "rotate", "rotated", "turn", "turned"])
	if l >= 0 and _has(ph, JOINT_NUM.keys()) >= 0:
		return   # "bend the knee 30" is a joint
	if l >= 0 and _has(ph, ["head", "neck", "arm", "elbow", "knee", "hand", "wrist", "leg", "foot", "hip", "shoulder", "ankle"]) >= 0:
		return
	if t >= 0 and _has(ph, ["head", "neck", "arm", "elbow", "knee", "hand", "wrist", "leg", "foot", "hip", "shoulder", "ankle", "body", "hips", "pelvis"]) >= 0:
		return
	if l >= 0:
		ph["used"][l] = true
		var d := _claim(ph, ["forward", "forwards", "back", "backward", "backwards", "left", "right"])
		if d == "":
			return   # "lean" alone: left to the leftovers (not understood: which way?)
		_claim_all(ph, ["chest", "torso", "body", "spine", "trunk"])
		var n := _num(ph)
		plan["items"].append({"phrase": pi, "kind": "lean", "dir": d, "deg": 15.0 if is_nan(n) else n})
	elif t >= 0:
		ph["used"][t] = true
		var d2 := _claim(ph, ["left", "right"])
		if d2 == "":
			return
		_claim_all(ph, ["chest", "torso", "body", "spine", "trunk", "shoulders"])
		var n2 := _num(ph)
		plan["items"].append({"phrase": pi, "kind": "twist", "dir": d2, "deg": 30.0 if is_nan(n2) else n2})


static func _m_joint(ph: Dictionary, pi: int, plan: Dictionary) -> void:
	var j := _has(ph, JOINT_NUM.keys())
	if j < 0:
		return
	var stem: String = JOINT_NUM[ph["toks"][j]]
	var nm := -1
	for k in ph["toks"].size():
		if not ph["used"][k] and String(ph["toks"][k]).is_valid_float():
			nm = k
	if nm < 0:
		return   # a verb phrase ("straighten the right elbow") is PoseWords'
	ph["used"][j] = true
	ph["used"][nm] = true
	var sd := _side(ph)
	_claim_all(ph, ["bent", "bend", "flexed", "flex", "flexion", "at", "angle", "of"])
	plan["items"].append({"phrase": pi, "kind": "joint", "stem": stem, "side": sd, "deg": float(ph["toks"][nm]), "word": ph["toks"][j]})


static func _m_words(ph: Dictionary, pi: int, plan: Dictionary, whole: bool) -> void:
	# the fallback: PoseWords' verbs ("raise the right arm 90"). Only when the phrase has no item of ours, or leftovers remain
	if not whole:
		return
	var r := PoseWords.parse(ph["text"])
	if not r["ok"]:
		return
	for k in ph["toks"].size():
		ph["used"][k] = true
	plan["items"].append({"phrase": pi, "kind": "words", "ops": r["ops"]})


# ------------------------------------------------------------------------------------------------ geometry helpers
static func _torso(B: Body) -> Dictionary:
	var q: Quaternion = B.G["spine_03"]
	return {"base": B.P["spine_03"], "mid": ((B.P["spine_03"] as Vector3) + (B.E["spine_03"] as Vector3)) * 0.5, "fwd": q * Vector3(0, 0, 1), "up": q * Vector3(0, 1, 0), "left": q * Vector3(1, 0, 0)}


static func _head_c(B: Body) -> Vector3:
	return ((B.P["head"] as Vector3) + (B.E["head"] as Vector3)) * 0.5


static func _chin_y(B: Body) -> float:
	return (B.P["head"] as Vector3).y


## a body landmark (world). sd = "_l" / "_r" for paired ones ("" = the hand's own side, given by `own`)
static func landmark(B: Body, name: String, sd: String, own: String) -> Vector3:
	var s := sd if sd != "" else own
	var sg := 1.0 if s == "_l" else -1.0   # +x = his left
	var T := _torso(B)
	var hq: Quaternion = B.G["head"]
	var hc := _head_c(B)
	match name:
		"head":
			return B.E["head"] as Vector3
		"chin":
			return hc - hq * Vector3(0, 0.10, 0) + hq * Vector3(0, 0, 0.09)
		"face", "mouth":
			return hc - hq * Vector3(0, 0.05, 0) + hq * Vector3(0, 0, 0.10)
		"eyes", "eye":
			return hc + hq * Vector3(0, 0.02, 0.10)
		"forehead":
			return hc + hq * Vector3(0, 0.05, 0.10)
		"ear":
			return hc + hq * Vector3(sg * 0.09, 0, 0)
		"neck":
			return (B.P["neck_01"] as Vector3) + (T["fwd"] as Vector3) * 0.05
		"chest":
			return (T["mid"] as Vector3) + (T["fwd"] as Vector3) * 0.11
		"belly", "stomach", "waist":
			var q1: Quaternion = B.G["spine_01"]
			return (B.P["spine_01"] as Vector3) + q1 * Vector3(0, 0.05, 0.11)
		"hip", "hips":
			return (B.P["thigh" + s] as Vector3) + Vector3(sg * 0.10, 0.05, 0.0)
		"shoulder", "shoulders":
			return (B.P["upperarm" + s] as Vector3) + Vector3(sg * 0.03, 0.02, 0.0)
		"knee", "knees":
			return (B.P["calf" + s] as Vector3) + Vector3(0, 0, 0.07)
		"back":
			return (T["mid"] as Vector3) - (T["fwd"] as Vector3) * 0.11
	return B.P["spine_03"]


## the way "out" from a landmark (for on / at / over / near)
static func _out_dir(B: Body, name: String, sd: String, own: String) -> Vector3:
	var T := _torso(B)
	var s := sd if sd != "" else own
	var sg := 1.0 if s == "_l" else -1.0
	match name:
		"ear":
			return Vector3(sg, 0, 0)
		"hip", "hips", "shoulder", "shoulders":
			return Vector3(sg, 0.3, 0).normalized()
		"head":
			return Vector3.UP
		"back":
			return -(T["fwd"] as Vector3)
	return T["fwd"]


# ------------------------------------------------------------------------------------------------ solving
static func _feet_state(B: Body) -> Dictionary:
	var out := {}
	for sd in ["_l", "_r"]:
		var fs: Array = B.foot_state(sd)
		if fs[2]:
			out[sd] = {"ball": fs[0], "head": fs[1], "heel_up": not fs[3]}
	return out


static func _leg_len(B: Body, sd: String) -> float:
	return ((B.P["calf" + sd] as Vector3) - (B.P["thigh" + sd] as Vector3)).length() + ((B.P["foot" + sd] as Vector3) - (B.P["calf" + sd] as Vector3)).length()


## a lighter Body.plant: the foot flat (or heel up), the ankle reached onto its mark, the knee over the toes, twice (plant runs five
## rounds to 0.01 mm; two are within a millimetre or two here and the sentence has 200 ms). Returns the miss of the toe base (m).
static func _plant(B: Body, sd: String, f: Dictionary) -> float:
	var ball: Vector3 = f["ball"]
	var flat: bool = not f["heel_up"]
	for i in 2:
		if flat:
			B.flat_foot(sd)
		var d: Vector3 = (B.P["ball" + sd] as Vector3) - (B.P["foot" + sd] as Vector3)
		B.reach("foot" + sd, ball - d)
		var hf: Vector3 = (B.G["pelvis"] as Quaternion) * Vector3(0, 0, 1)
		B.knee_over_toes(sd, f["head"] if flat else atan2(hf.x, hf.z))
		if ((B.P["ball" + sd] as Vector3) - ball).length() < 0.003:
			break
	if f["heel_up"]:
		B.toes_flat(sd)
	return ((B.P["ball" + sd] as Vector3) - ball).length()


## plant the feet on `feet` (sd -> {ball, head, heel_up}); the pelvis goes down until the legs reach. Returns the worst miss (m).
static func _legs(B: Body, feet: Dictionary) -> float:
	var worst := 0.0
	var was_fast := B.fast
	B.fast = true   # limits only while the legs are solved (no contact bisection per bend: ~4x faster); the pose is checked after
	for it in 5:
		B.fk()
		worst = 0.0
		for sd in feet:
			worst = maxf(worst, _plant(B, sd, feet[sd]))
		if worst < 0.004:
			break
		# too far to reach (the hip is higher than the leg allows): lower the pelvis by what is missing
		var lower := 0.0
		for sd in feet:
			var f2: Dictionary = feet[sd]
			var ank: Vector3 = (f2["ball"] as Vector3) - ((B.P["ball" + sd] as Vector3) - (B.P["foot" + sd] as Vector3))
			var d := ank.distance_to(B.P["thigh" + sd])
			lower = maxf(lower, d - _leg_len(B, sd))
		if lower <= 0.0:
			break   # in reach: what is left is the foot's own tilt, not the pelvis
		B.offset.y -= lower * 1.2 + 0.004
	B.fast = was_fast
	return worst


static func _com_xz(B: Body) -> Vector2:
	var c := Balance.com(B)
	return Vector2(c.x, c.z)


static func _foot_c(B: Body, sd: String) -> Vector2:
	var a: Vector3 = B.P["foot" + sd]
	var b: Vector3 = B.P["ball" + sd]
	return Vector2((a.x + b.x) * 0.5, (a.z + b.z) * 0.5)


## lead side for stagger: given, else the foot opposite the weapon hand (a right-hander leads with the left), else left
static func _lead(B: Body, plan: Dictionary, given: String) -> String:
	if given != "":
		return given
	var wh := ""
	if B.wep_on and B.wep_hand != "":
		wh = B.wep_hand.right(2)
	for it in plan["items"]:
		if it["kind"] == "weapon":
			wh = it["hand"] if it["hand"] != "" else (it["lside"] if it["lside"] != "" else "_r")
	return "_l" if wh != "_l" else "_r"


static func _solve_legs(B: Body, plan: Dictionary, rep: Dictionary) -> void:
	var crouch = null
	var stance = null
	var lunge = null
	var weight = null
	for it in plan["items"]:
		match it["kind"]:
			"crouch":
				crouch = it
			"stance":
				stance = it
			"lunge":
				lunge = it
			"weight":
				weight = it
	var need_stagger: bool = weight != null and weight["foot"] == "fb"
	if crouch == null and stance == null and lunge == null and not need_stagger:
		return
	B.fk()
	var h0: float = (B.P["pelvis"] as Vector3).y
	var feet := _feet_state(B)
	var bl: Vector3 = B.P["ball_l"]
	var br: Vector3 = B.P["ball_r"]
	var y_ball: float = (B.p0["ball_l"] as Vector3).y + 0.0
	var zc := (bl.z + br.z) * 0.5
	var xc := (bl.x + br.x) * 0.5
	var spread := absf(bl.x - br.x) * 0.5
	var stagger := (bl.z - br.z) * 0.5   # + = left foot ahead
	var spread_set := false
	if stance != null:
		spread = stance["spread"]
		spread_set = true
	if (crouch != null or lunge != null or need_stagger) and not spread_set:
		spread = maxf(spread, SPREAD_DEFAULT)
	var heel_up := {"_l": false, "_r": false}
	var lead := ""
	if need_stagger or lunge != null:
		var given: String = lunge["lead"] if lunge != null else ""
		lead = _lead(B, plan, given)
		var half: float = LUNGE_HALF if lunge != null else STAGGER
		if lunge == null and absf(stagger) >= STAGGER * 0.9:
			half = absf(stagger)
			if (stagger > 0.0) != (lead == "_l"):
				lead = "_l" if stagger > 0.0 else "_r"   # already staggered: keep who leads
		stagger = half if lead == "_l" else -half
		if lunge != null:
			heel_up["_r" if lead == "_l" else "_l"] = true
	var tl := Vector3(xc + spread, y_ball, zc + stagger)
	var tr := Vector3(xc - spread, y_ball, zc - stagger)
	var drop := 0.0
	var back_shift := 0.0
	if lunge != null:
		drop = (crouch["frac"] if crouch != null else 0.22) * h0
	elif crouch != null:
		drop = crouch["frac"] * h0
	back_shift = 0.33 * drop if lunge == null else 0.0
	var targets := {"_l": {"ball": tl, "head": 0.0, "heel_up": heel_up["_l"]}, "_r": {"ball": tr, "head": 0.0, "heel_up": heel_up["_r"]}}
	# the pelvis over the middle of the feet (a lunge: a little toward the front foot), lowered by the drop
	var mid := Vector2((tl.x + tr.x) * 0.5, (tl.z + tr.z) * 0.5)
	if lunge != null:
		mid.y += (0.12 if lead == "_l" else -0.12) * 0.0 + 0.0
	B.offset.x = mid.x - (B.p0["pelvis"] as Vector3).x
	B.offset.z = mid.y - back_shift - (B.p0["pelvis"] as Vector3).z
	B.offset.y -= drop
	B.fk()
	_legs(B, targets)
	rep["feet"] = targets
	rep["lead"] = lead
	rep["h0"] = h0
	rep["spread"] = spread
	# a crouch leans the trunk forward to keep the chest over the feet (hips went back): a third of the hip drop in degrees * 100
	if crouch != null and lunge == null:
		B.back_bend("bend", clampf(drop / h0 * 70.0, 0.0, 35.0))
		B.fk()


static func _solve_trunk(B: Body, plan: Dictionary) -> void:
	for it in plan["items"]:
		if it["kind"] == "lean":
			var d: String = it["dir"]
			var deg: float = it["deg"]
			if d in ["forward", "forwards"]:
				B.back_bend("bend", B.back_of("bend") + deg)
			elif d in ["back", "backward", "backwards"]:
				B.back_bend("bend", B.back_of("bend") - deg)
			elif d == "left":
				B.back_bend("side", B.back_of("side") + deg)
			else:
				B.back_bend("side", B.back_of("side") - deg)
		elif it["kind"] == "twist":
			B.back_bend("twist", B.back_of("twist") + (it["deg"] if it["dir"] == "left" else -it["deg"]))


static func _pole(B: Body, sd: String, target: Vector3, out_amt := 0.3) -> Vector3:
	var sh: Vector3 = B.P["upperarm" + sd]
	var sg := 1.0 if sd == "_l" else -1.0
	return (sh + target) * 0.5 + Vector3(sg * out_amt, -0.45, -0.1)


static func _arm_to(B: Body, sd: String, target: Vector3, out_amt := 0.3, rot = null) -> float:
	var r := LimbIK.solve(B, "hand" + sd, target, _pole(B, sd, target, out_amt), rot)
	return r["miss"]


static func _guard_target(B: Body, sd: String, height: String, weapon_hand: bool) -> Vector3:
	var T := _torso(B)
	var sg := 1.0 if sd == "_l" else -1.0
	var y := 0.0
	match height:
		"low":
			y = 0.0
		"high":
			y = (_chin_y(B) + 0.06) - (T["base"] as Vector3).y
		_:
			y = ((_chin_y(B) - 0.10) - (T["base"] as Vector3).y)
	return (T["base"] as Vector3) + (T["left"] as Vector3) * (sg * GUARD_X) + (T["up"] as Vector3) * y + (T["fwd"] as Vector3) * GUARD_Z


static func _solve_arms(B: Body, plan: Dictionary, rep: Dictionary) -> void:
	var targets := {}   # sd -> wrist target
	var outs := {}
	for it in plan["items"]:
		if it["kind"] == "guard":
			for sd in ["_l", "_r"]:
				targets[sd] = _guard_target(B, sd, it["height"], false)
		elif it["kind"] == "hand":
			var sds: Array = [it["hand"]] if it["hand"] != "" else ["_l", "_r"]
			for sd in sds:
				var ls: String = it["lside"] if it["lside"] != "" else ""
				var lm: Vector3 = landmark(B, it["land"], ls, sd)
				var off: float = {"on": 0.03, "at": 0.03, "against": 0.03, "over": 0.10, "near": 0.14, "beside": 0.12, "to": 0.03, "by": 0.12}.get(it["prep"], 0.03)
				var spot: Vector3 = lm + _out_dir(B, it["land"], ls, sd) * off
				if it["hand"] == "" and it["land"] in ["chin", "face", "mouth", "forehead", "head", "neck", "chest", "belly", "stomach", "waist", "eyes", "eye"]:
					spot.x += (0.05 if sd == "_l" else -0.05)   # two hands do not share one point
				it["spot_" + sd] = spot
				var dir := (spot - (B.P["upperarm" + sd] as Vector3)).normalized()
				targets[sd] = spot - dir * 0.08   # the wrist stops short: the palm's centre is ~8 cm past it
				outs[sd] = 0.45 if it["land"] in ["head", "ear", "face", "forehead", "chin", "mouth"] else 0.3
	for it in plan["items"]:
		if it["kind"] != "weapon":
			continue
		var h: String = it["hand"] if it["hand"] != "" else (it["lside"] if it["lside"] != "" else (B.wep_hand.right(2) if B.wep_on and B.wep_hand != "" else "_r"))
		it["hand"] = h
		var kind: String = it["wkind"]
		if kind == "" and not B.wep_on:
			kind = "metal_bat"
		if not B.wep_on or B.wep_hand != "hand" + h or (kind != "" and kind != B.wep_kind):
			B.grip = false
			if kind != "" and kind != B.wep_kind:
				B.set_kind(kind)
			if B.wep_on:
				B.unlock_weapon()
			B.weapon_to_hand("hand" + h)
			B.grip = false   # one-handed unless the words say two; the free hand goes where the guard puts it
			B.fk()
		# the hand's place: the guard's if the sentence has one, else beside the shoulder
		var T := _torso(B)
		var sg := 1.0 if h == "_l" else -1.0
		var land_default: Vector3 = (B.P["upperarm" + h] as Vector3) + (T["fwd"] as Vector3) * 0.22 + (T["up"] as Vector3) * 0.04
		var H: Vector3 = targets.get(h, land_default)
		it["grip_at"] = H
		# where the tip goes: beside the landmark (over = above it, behind = behind it, across = over the other side)
		var lm_name: String = it["land"] if it["land"] != "" else "shoulder"
		var ls2: String = it["lside"] if it["lside"] != "" else h
		var L: Vector3 = landmark(B, lm_name, ls2, h)
		var prep: String = it.get("prep", "over")
		var tip_to: Vector3 = L
		var back: Vector3 = -(T["fwd"] as Vector3)
		match prep:
			"over", "above", "on":
				tip_to = L + (T["up"] as Vector3) * 0.22 + back * 0.30
			"behind":
				tip_to = L + back * 0.45 + (T["up"] as Vector3) * 0.08
			"across":
				tip_to = L + (T["left"] as Vector3) * (-sg * 0.40) + (T["fwd"] as Vector3) * 0.15 + (T["up"] as Vector3) * 0.1
			_:
				tip_to = L + (T["up"] as Vector3) * 0.30 + back * 0.15
		if it.get("vert", "") in ["down", "low"]:
			tip_to = L + (T["fwd"] as Vector3) * 0.2 - (T["up"] as Vector3) * 0.6
		it["tip_to"] = tip_to
		var dir_w := (tip_to - H).normalized()
		it["dir"] = dir_w
		_arm_to(B, h, H, 0.3)
		for k in 2:
			B.aim_weapon(dir_w)
			var Rh: Quaternion = B.G["hand" + h]
			_arm_to(B, h, H, 0.3, Rh)
			if rad_to_deg(B.wep_axis().angle_to(dir_w)) < 3.0:
				break
		targets.erase(h)   # the bat hand is placed
	for sd in targets:
		_arm_to(B, sd, targets[sd], outs.get(sd, 0.3))
	B.fk()


static func _solve_joints(B: Body, plan: Dictionary, rep: Dictionary) -> void:
	for it in plan["items"]:
		match it["kind"]:
			"joint":
				var sds: Array = [it["side"]] if it["side"] != "" else ["_l", "_r"]
				it["got"] = {}
				for sd in sds:
					var j: String = it["stem"] + sd
					var v: Vector3 = B.ang[j]
					B.last_stop = {}
					B.set_ang_safe(j, Vector3(it["deg"], v.y, v.z))
					it["got"][j] = (B.ang[j] as Vector3).x
					if not B.last_stop.is_empty():
						it["stop"] = B.last_stop.duplicate(true)
				B.fk()
			"words":
				it["got"] = []
				for op in it["ops"]:
					var j2: String = op["joint"]
					var v2: Vector3 = B.ang[j2]
					var want := v2
					want[op["axis"]] = op["deg"] if op["mode"] == "to" else v2[op["axis"]] + op["deg"]
					B.set_ang_safe(j2, want)
					it["got"].append([j2, op["axis"], want[op["axis"]], (B.ang[j2] as Vector3)[op["axis"]]])
				B.fk()
			"kick":
				var sd2: String = it["side"]
				var h: String = it["height"]
				var th := 35.0 if h == "low" else (110.0 if h == "high" else 75.0)
				var tj := "thigh" + sd2
				var v3: Vector3 = B.ang[tj]
				if it["sidekick"]:
					B.set_ang_safe(tj, Vector3(v3.x, th * 0.8, v3.z))
				elif it["back"]:
					B.set_ang_safe(tj, Vector3(-minf(th, 40.0), v3.y, v3.z))
				else:
					B.set_ang_safe(tj, Vector3(th, v3.y, v3.z))
				var cj := "calf" + sd2
				var cv: Vector3 = B.ang[cj]
				B.set_ang_safe(cj, Vector3(5.0 if not it["back"] else 70.0, cv.y, cv.z))
				it["got_th"] = (B.ang[tj] as Vector3)
				B.fk()


## the pelvis moved so the centre of mass sits over the target (xz), the feet that are down re-planted. Returns the final miss (m)
static func _shift_com(B: Body, target: Vector2, feet: Dictionary) -> float:
	var err := Vector2.ZERO
	for it in 3:
		err = target - _com_xz(B)
		if err.length() < 0.012:
			break
		B.offset.x += err.x
		B.offset.z += err.y
		B.fk()
		_legs(B, feet)
	return (target - _com_xz(B)).length()


static func _solve_weight(B: Body, plan: Dictionary, rep: Dictionary) -> void:
	B.fk()
	var feet := _feet_state(B)
	if feet.is_empty():
		return
	var w = null
	for it in plan["items"]:
		if it["kind"] == "weight":
			w = it
	if w != null and w["foot"] != "even" and feet.size() == 2:
		var sd := ""
		if w["foot"] == "side":
			sd = w["side"]
		else:
			var zl: float = (B.P["ball_l"] as Vector3).z
			var zr: float = (B.P["ball_r"] as Vector3).z
			var front := "_l" if zl >= zr else "_r"
			sd = front if w["fb"] == "front" else ("_r" if front == "_l" else "_l")
		var other := "_r" if sd == "_l" else "_l"
		var target := _foot_c(B, sd).lerp(_foot_c(B, other), WEIGHT_TOWARD)
		w["target_foot"] = sd
		_shift_com(B, target, feet)
		return
	if w != null and w["foot"] == "even" and feet.size() == 2:
		_shift_com(B, _foot_c(B, "_l").lerp(_foot_c(B, "_r"), 0.5), feet)
		return
	# nothing said about weight: only fix a centre of mass that is outside (or at the edge of) the feet
	var bal := Balance.read(B)
	if float(bal["margin"]) < Balance.MARGIN_RES and not (bal["down"] as Array).is_empty():
		var pts := PackedVector2Array()
		for sd2 in feet:
			pts.append(_foot_c(B, sd2))
		var c := Vector2.ZERO
		for p in pts:
			c += p
		c /= pts.size()
		var before := _com_xz(B)
		var miss := _shift_com(B, c, feet)
		rep["auto_balance"] = before.distance_to(_com_xz(B))
		rep["auto_miss"] = miss


static func _solve_look(B: Body, plan: Dictionary) -> void:
	for it in plan["items"]:
		if it["kind"] != "look":
			continue
		B.fk()
		var eye := LookAt.eye_point(B)
		var T := _torso(B)
		var pt := eye
		match it["at"]:
			"left":
				pt = eye + (T["left"] as Vector3) * 3.0 + (T["fwd"] as Vector3) * 0.5
			"right":
				pt = eye - (T["left"] as Vector3) * 3.0 + (T["fwd"] as Vector3) * 0.5
			"down", "floor", "ground":
				pt = eye + (T["fwd"] as Vector3) * 1.2 - Vector3(0, 1.0, 0)
			"up", "sky", "ceiling":
				pt = eye + (T["fwd"] as Vector3) * 1.0 + Vector3(0, 1.5, 0)
			"hand":
				pt = (B.P["hand" + it["side"]] as Vector3) + ((B.E["hand" + it["side"]] as Vector3) - (B.P["hand" + it["side"]] as Vector3)) * 0.5
			"bat", "weapon", "tip":
				pt = B.wep_point(B.wep_len) if B.wep_on else eye + (T["fwd"] as Vector3) * 3.0
			"back", "behind":
				pt = eye - (T["fwd"] as Vector3) * 3.0
			_:
				pt = eye + (T["fwd"] as Vector3) * 3.0
		it["res"] = LookAt.solve(B, pt)
		it["point"] = pt


# ------------------------------------------------------------------------------------------------ the library start
## a saved pose whose NAME holds every content word of a phrase (poses/*.json, poses/lib/*.json). No weapon unless the sentence has one.
static func _library(B: Body, phs: Array, plan: Dictionary) -> String:
	for ph in phs:
		var words := []
		for i in ph["toks"].size():
			var w: String = ph["toks"][i]
			if not (w in FILLER) and not (w in PREP):
				words.append(w)
		if words.is_empty():
			continue
		for dir in ["res://poses", "res://poses/lib"]:
			var d := DirAccess.open(dir)
			if d == null:
				continue
			for f in d.get_files():
				if not f.ends_with(".json"):
					continue
				var toks: PackedStringArray = f.get_basename().to_lower().split("_", false)
				var all := true
				for w in words:
					if not (w in toks):
						all = false
						break
				if not all:
					continue
				var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir + "/" + f))
				if not (data is Dictionary):
					continue
				var wep: Dictionary = (data as Dictionary).get("weapon", {})
				if bool(wep.get("on", false)) and not plan["weapon_word"]:
					continue
				var js: Dictionary = (data as Dictionary).get("joints", {})
				for j in js:
					if B.lim.has(j):
						var x: Dictionary = js[j]
						B.ang[j] = B.clamp_ang(j, Vector3(x["bend"], x["side"], x["twist"]))
				var o: Array = (data as Dictionary).get("offset", [0, 0, 0])
				B.offset = Vector3(o[0], o[1], o[2])
				B.fk()
				for k in ph["toks"].size():
					ph["used"][k] = true
				plan["lib_phrase"] = ph["text"]
				return dir.get_slice("//", 1) + "/" + f
	return ""


# ------------------------------------------------------------------------------------------------ checking
static func _fmt_cm(m: float) -> String:
	return "%.0f cm" % (m * 100.0)


static func _check(B: Body, it: Dictionary, rep: Dictionary) -> Array:
	match it["kind"]:
		"crouch":
			var drop: float = (rep["h0"] - (B.P["pelvis"] as Vector3).y) / rep["h0"]
			it["drop"] = drop
			if drop >= it["frac"] - 0.03:
				return ["placed", "hips down %.0f%%" % (drop * 100.0)]
			return ["partly placed", "the hips dropped %.0f%% of the %.0f%% asked: the knees stop it" % [drop * 100.0, it["frac"] * 100.0]]
		"stance":
			var dx := absf((B.P["ball_l"] as Vector3).x - (B.P["ball_r"] as Vector3).x)
			it["feet_apart"] = dx
			if absf(dx * 0.5 - it["spread"]) < 0.04:
				return ["placed", "feet %s apart" % _fmt_cm(dx)]
			return ["partly placed", "feet are %s apart, not the %s asked (the legs could not reach)" % [_fmt_cm(dx), _fmt_cm(it["spread"] * 2.0)]]
		"lunge":
			var dz := absf((B.P["ball_l"] as Vector3).z - (B.P["ball_r"] as Vector3).z)
			it["step"] = dz
			if dz > 0.6:
				return ["placed", "step %s" % _fmt_cm(dz)]
			return ["partly placed", "the step is %s: the legs reach no further" % _fmt_cm(dz)]
		"weight":
			if it["foot"] == "even":
				var d0 := _com_xz(B).distance_to(_foot_c(B, "_l").lerp(_foot_c(B, "_r"), 0.5))
				return ["placed" if d0 < 0.06 else "partly placed", "centre of mass %s from the middle of the feet" % _fmt_cm(d0)]
			var sd: String = it.get("target_foot", "")
			if sd == "":
				return ["partly placed", "there is no second foot on the floor to carry the weight from"]
			var width := _foot_c(B, "_l").distance_to(_foot_c(B, "_r"))
			var dd := _com_xz(B).distance_to(_foot_c(B, sd))
			it["com_dist"] = dd
			it["width"] = width
			if dd <= 0.3 * width:
				return ["placed", "centre of mass %s from that foot (%.0f%% of the %s stance)" % [_fmt_cm(dd), dd / width * 100.0, _fmt_cm(width)]]
			return ["partly placed", "centre of mass is %s (%.0f%% of the stance) from that foot: the legs stop the pelvis short" % [_fmt_cm(dd), dd / width * 100.0]]
		"guard":
			var bad := []
			var T := _torso(B)
			for sd2 in ["_l", "_r"]:
				var hp: Vector3 = B.P["hand" + sd2]
				var want := _guard_target(B, sd2, it["height"], false)
				var rel := hp - (T["base"] as Vector3)
				if hp.distance_to(want) > 0.05 and not (B.wep_on and B.wep_hand == "hand" + sd2):
					bad.append("%s hand %s off" % ["left" if sd2 == "_l" else "right", _fmt_cm(hp.distance_to(want))])
			if bad.is_empty():
				return ["placed", "hands in front of the chest, %s" % it["height"]]
			return ["partly placed", "; ".join(bad) + " (a limit or the body stops the arm)"]
		"hand":
			var sds: Array = [it["hand"]] if it["hand"] != "" else ["_l", "_r"]
			var worst := 0.0
			for sd3 in sds:
				var pc: Vector3 = ((B.P["hand" + sd3] as Vector3) + (B.E["hand" + sd3] as Vector3)) * 0.5
				worst = maxf(worst, pc.distance_to(it["spot_" + sd3]))
			it["miss"] = worst
			if worst <= 0.06:
				return ["placed", "hand within %s of the %s" % [_fmt_cm(worst), it["land"]]]
			return ["partly placed", "the hand stops %s from the %s (arm length or a joint limit)" % [_fmt_cm(worst), it["land"]]]
		"weapon":
			var tip := B.wep_point(B.wep_len)
			var knob := B.wep_point(0.0)
			var ax := (tip - knob).normalized()
			var err := rad_to_deg(ax.angle_to(it["dir"]))
			it["tip"] = tip
			it["aim_err"] = err
			var lm: Vector3 = landmark(B, it["land"] if it["land"] != "" else "shoulder", it["lside"] if it["lside"] != "" else it["hand"], it["hand"])
			var prep: String = it.get("prep", "over")
			var ok := true
			var why := ""
			if prep in ["over", "above", "on"] and not (tip.y > lm.y):
				ok = false
				why = "the tip is %s below the %s" % [_fmt_cm(lm.y - tip.y), it["land"] if it["land"] != "" else "shoulder"]
			if prep in ["over", "above", "on", "behind"] and it["mode"] == "cock" and not (tip.z < lm.z):
				ok = false
				why = "the tip is %s in front of the %s" % [_fmt_cm(tip.z - lm.z), it["land"] if it["land"] != "" else "shoulder"]
			if err > 12.0:
				ok = false
				why += ("; " if why != "" else "") + "the wrist and arm turn the shaft only to within %.0f deg of the wanted line" % err
			if ok:
				return ["placed", "tip %s above, %s behind the %s" % [_fmt_cm(tip.y - lm.y), _fmt_cm(lm.z - tip.z), it["land"] if it["land"] != "" else "shoulder"]]
			return ["partly placed", why]
		"joint":
			var bad2 := []
			for j in it["got"]:
				if absf(it["got"][j] - it["deg"]) > 1.0:
					bad2.append("%s reached %.0f of %.0f deg" % [j, it["got"][j], it["deg"]])
			if bad2.is_empty():
				return ["placed", "%s %.0f deg" % [it["word"], it["deg"]]]
			var st: Dictionary = it.get("stop", {})
			return ["partly placed", "%s (%s)" % ["; ".join(bad2), "the joint's limit" if st.get("kind", "") == "limit" else "parts meet"]]
		"words":
			var bad3 := []
			for g in it["got"]:
				if absf(g[3] - g[2]) > 0.5:
					bad3.append("%s %s reached %.0f of %.0f deg" % [g[0], PoseWords.AXES[g[1]], g[3], g[2]])
			if bad3.is_empty():
				return ["placed", "joints turned"]
			return ["partly placed", "; ".join(bad3)]
		"kick":
			return ["placed", "leg lifted (support foot carries the weight)"]
		"look":
			var r: Dictionary = it.get("res", {})
			if float(r.get("error", 99.0)) <= 2.0:
				return ["placed", "gaze on it (head turned %.0f deg)" % r.get("head_deg", 0.0)]
			return ["partly placed", "the gaze ends %.0f deg off: the neck turns no further" % r.get("error", 0.0)]
		"lean", "twist":
			var got: float = B.back_of("bend" if it["kind"] == "lean" and it["dir"] in ["forward", "forwards", "back", "backward", "backwards"] else ("side" if it["kind"] == "lean" else "twist"))
			return ["placed", "back turned"]
	return ["placed", ""]


# ------------------------------------------------------------------------------------------------ the entry point
static func apply(B: Body, text: String, use_library := true) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var phs := split(text)
	if phs.is_empty():
		return _err("nothing to pose: type a pose such as 'low guard, weight on back foot, bat cocked over right shoulder' or 'crouch'")
	var plan := _read(phs)
	var rep := {}
	var start := ""
	if use_library:
		# a library start is for a sentence we otherwise could not place (a phrase our own matchers do not read)
		var used_items := {}
		for it in plan["items"]:
			used_items[it["phrase"]] = true
		var unplaced := []
		for pi in phs.size():
			if not used_items.has(pi):
				unplaced.append(phs[pi])
		if not unplaced.is_empty():
			start = _library(B, unplaced, plan)
	B.fk()
	var tm := {}
	var tt := Time.get_ticks_usec()
	_solve_legs(B, plan, rep)
	tm["legs"] = (Time.get_ticks_usec() - tt) / 1000.0
	tt = Time.get_ticks_usec()
	var was_fast := B.fast
	B.fast = true   # the arms are aimed on limits alone (the contact bisection per turn costs ~100 ms); contacts are read once at the end
	_solve_trunk(B, plan)
	_solve_arms(B, plan, rep)
	B.fast = was_fast
	tm["arms"] = (Time.get_ticks_usec() - tt) / 1000.0
	tt = Time.get_ticks_usec()
	_solve_joints(B, plan, rep)
	tm["joints"] = (Time.get_ticks_usec() - tt) / 1000.0
	tt = Time.get_ticks_usec()
	_solve_weight(B, plan, rep)
	tm["weight"] = (Time.get_ticks_usec() - tt) / 1000.0
	B.fast = true
	_solve_look(B, plan)
	B.fast = was_fast
	rep["ms_by_step"] = tm
	B.fk()
	# the report: one line per phrase
	var lines := []
	var items := []
	var unknown := []
	for pi in phs.size():
		var ph: Dictionary = phs[pi]
		var status := "placed"
		var whys := []
		var found := false
		for it in plan["items"]:
			if it["phrase"] != pi:
				continue
			found = true
			var c := _check(B, it, rep)
			if c[0] != "placed":
				status = "partly placed"
				whys.append(c[1])
			elif c[1] != "":
				whys.append(c[1])
		var left := _left(ph)
		if start != "" and plan.get("lib_phrase", "") == ph["text"]:
			found = true
			whys.append("started from the saved pose %s" % start)
		for w in left:
			unknown.append(w)
		if not found:
			status = "not understood"
			whys = ["no rule for " + ", ".join(left.map(func(x): return "'%s'" % x))] if not left.is_empty() else ["no rule for this phrase"]
		elif not left.is_empty():
			status = "partly placed"
			whys.append("did not understand " + ", ".join(left.map(func(x): return "'%s'" % x)))
		var line := "%s: %s" % [ph["text"], status]
		if status == "placed" and not whys.is_empty():
			line += " (%s)" % "; ".join(whys)
		elif status != "placed":
			line += " (%s)" % "; ".join(whys)
		lines.append(line)
		items.append({"phrase": ph["text"], "status": status, "why": "; ".join(whys)})
	var deep := 0.0
	var deep_pair := []
	for c in B.contacts():
		if float(c[2]) > deep:
			deep = float(c[2])
			deep_pair = [c[0], c[1]]
	rep["deepest_overlap"] = deep
	if deep > 0.02:
		lines.append("note: %s and %s overlap by %s: move one of them" % [deep_pair[0], deep_pair[1], _fmt_cm(deep)])
	if rep.has("auto_balance") and float(rep["auto_balance"]) > 0.005:
		lines.append("balance: the centre of mass was outside the feet, the hips moved %s to bring it inside" % _fmt_cm(rep["auto_balance"]))
	return {"ok": true, "lines": lines, "items": items, "unknown": unknown, "start": start, "plan": plan, "rep": rep,
		"ms": (Time.get_ticks_usec() - t0) / 1000.0}
