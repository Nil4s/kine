## stance_fit.gd - STANCES THAT FIT THE BODY (N070): boxer, karate (zenkutsu-dachi) and fencing (en garde) stances sized from THIS
## body's leg length (hip joint to ankle along the bones) and shoulder width (the two shoulder joints apart), not one size.
## Each stance is two numbers: the feet's lateral gap (width) and fore-aft gap (length), each ratio x a basis ("shoulder" or "leg").
## SOURCES: the ratios are the textbook rules of thumb (boxing: feet about shoulder width, a half-leg step; karate zenkutsu: about
## shoulder width wide and a long step forward; fencing: feet about a shoulder width and a half apart along the line). They are
## UNVERIFIED (from memory): a PubMed search for stance-width ratios in these three sports found no paper giving them, so no
## PMID or DOI is claimed. What IS tested is that the stance scales with the body by the stated ratio (tests/partfirst_test.gd).
class_name StanceFit
extends RefCounted

const BALL_Y := 0.0152   # m: the ball of the foot's height on the floor (strike_blocking STANCE)
const UNV := "UNVERIFIED (from memory): textbook rule of thumb, no PMID/DOI checked"
## id -> {name, w: [basis, ratio], l: [basis, ratio], rear (heading of the rear foot, rad), src}
const TABLE := {
	"boxer": {"name": "Boxer stance", "w": ["shoulder", 1.0], "l": ["leg", 0.55], "rear": -0.35, "src": UNV},
	"karate": {"name": "Karate zenkutsu-dachi", "w": ["shoulder", 1.0], "l": ["leg", 0.9], "rear": -0.35, "src": UNV},
	"fencing": {"name": "Fencing en garde", "w": ["shoulder", 0.6], "l": ["shoulder", 1.6], "rear": -0.7, "src": UNV},
}
const ORDER := ["boxer", "karate", "fencing"]


static func leg_length(B: Body) -> float:
	return ((B.P["calf_l"] - B.P["thigh_l"]) as Vector3).length() + ((B.P["foot_l"] - B.P["calf_l"]) as Vector3).length()


static func shoulder_width(B: Body) -> float:
	return absf(float((B.P["upperarm_l"] as Vector3).x) - float((B.P["upperarm_r"] as Vector3).x))


## {"width", "length", "leg", "shoulder"} in metres for this body (read from the body standing straight)
static func sizes(B: Body, id: String) -> Dictionary:
	var keep := B.state()
	for j in B.ang:
		B.ang[j] = Vector3.ZERO
	B.offset = Vector3.ZERO
	B.fk()
	var leg := leg_length(B)
	var sh := shoulder_width(B)
	B.set_state(keep)
	var T: Dictionary = TABLE[id]
	return {"width": float(T["w"][1]) * (sh if T["w"][0] == "shoulder" else leg), "length": float(T["l"][1]) * (sh if T["l"][0] == "shoulder" else leg),
		"leg": leg, "shoulder": sh}


## the body takes the stance: straight limbs, the hips dropped just enough that both feet reach, the left foot ahead (orthodox)
static func apply(B: Body, id: String) -> Dictionary:
	var sz := sizes(B, id)
	var T: Dictionary = TABLE[id]
	var w: float = sz["width"]
	var ln: float = sz["length"]
	var err := INF
	for drop in [0.0, 0.03, 0.06, 0.09, 0.12, 0.16, 0.2, 0.25]:
		for j in B.ang:
			B.ang[j] = Vector3.ZERO
		B.offset = Vector3(0, -drop, 0)
		B.fk()
		var e1 := B.plant("_l", Vector3(w * 0.5, BALL_Y, ln * 0.5), 0.0, true)
		var e2 := B.plant("_r", Vector3(-w * 0.5, BALL_Y, -ln * 0.5), float(T["rear"]), true)
		err = maxf(e1, e2)
		if err < 0.004:
			break
	return {"error": err, "width": w, "length": ln}
