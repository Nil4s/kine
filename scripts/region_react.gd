## region_react.gd - N042: the HIT REACTION PICKED BY BODY REGION. pick(tag, y, head_y) maps a KMeshAnatomy tag (+ the hit's height as a fraction of
## body height, and for the face its height within the head) to a region; react(region, impulse, side) gives the joint deltas (bend, side, twist deg;
## + side = tilt to his left) of that region's anatomy: liver folds to the hit side with a DELAYED drop; chin snaps the head and BOTH knees buckle;
## thigh buckles only the hit leg; solar plexus folds forward the most with both hands to the belly. Amplitude = 1 - exp(-J / J_REF), strictly
## increasing in the impulse J (N s); the pattern is scaled by it, so it stays inside data/body_limits.json (also clamped to it). Patterns are ours
## (sports-medicine direction); J_REF is a tuning constant. Joint -> Vector3 deltas from the animation, to be added on the hit frame.
class_name RegionReact
extends RefCounted

const J_REF := 60.0
const PATTERNS := {
	"liver": {"delay": 0.3, "side": true, "j": {"spine_01": Vector3(16, 7, 0), "spine_02": Vector3(14, 7, 0), "calf_r": Vector3(30, 0, 0), "calf_l": Vector3(30, 0, 0)}},
	"ribs": {"delay": 0.1, "side": true, "j": {"spine_01": Vector3(10, 7, 0), "spine_02": Vector3(8, 7, 0)}},
	"chin": {"delay": 0.1, "side": false, "j": {"head": Vector3(-25, 0, 30), "neck_01": Vector3(-30, 0, 25), "calf_r": Vector3(45, 0, 0), "calf_l": Vector3(45, 0, 0)}},
	"head": {"delay": 0.0, "side": false, "j": {"head": Vector3(-20, 0, 25), "neck_01": Vector3(-20, 0, 20)}},
	"thigh": {"delay": 0.0, "side": false, "j": {"HITCALF": Vector3(40, 0, 0), "HITTHIGH": Vector3(25, 0, 0)}},
	"solar_plexus": {"delay": 0.15, "side": false, "j": {"spine_01": Vector3(20, 0, 0), "spine_02": Vector3(20, 0, 0), "head": Vector3(15, 0, 0),
		"upperarm_r": Vector3(30, 0, 0), "upperarm_l": Vector3(30, 0, 0), "calf_r": Vector3(30, 0, 0), "calf_l": Vector3(30, 0, 0)}},
}


static func pick(tag: String, y := 0.5, head_y := 0.5) -> String:
	var stem := KMeshAnatomy.stem_of(tag)
	var side := tag.right(1) if tag.ends_with("_l") or tag.ends_with("_r") else ""
	match stem:
		"face":
			return "chin" if head_y < 0.5 else "head"
		"skull":
			return "head"
		"obliques":
			return "liver" if side == "r" else "ribs"
		"abdominals":
			return "solar_plexus" if y >= 0.6 else "body"
		"quadriceps", "hamstrings", "adductors", "hip":
			return "thigh"
	return "body"


static func amp_of(impulse: float) -> float:
	return 1.0 - exp(-maxf(impulse, 0.0) / J_REF)


## side = the struck side ("l" / "r"): the fold goes toward it, the thigh pattern hits that leg
static func react(region: String, impulse: float, side := "r") -> Dictionary:
	if not PATTERNS.has(region):
		return {"region": region, "amp": 0.0, "joints": {}, "drop_delay_s": 0.0}
	var P: Dictionary = PATTERNS[region]
	var a := amp_of(impulse)
	var lim: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/body_limits.json"))
	var out := {}
	for j in P["j"]:
		var v: Vector3 = (P["j"][j] as Vector3) * a
		var jn: String = j
		if j == "HITCALF":
			jn = "calf_" + side
		elif j == "HITTHIGH":
			jn = "thigh_" + side
		if bool(P["side"]) and v.y != 0.0:
			v.y = v.y * (1.0 if side == "l" else -1.0)
		var key := jn.replace("_l", "_r") if jn.ends_with("_l") else jn
		var L: Dictionary = lim.get(key, {})
		if not L.is_empty():
			v.x = clampf(v.x, L["bend"][0], L["bend"][1])
			v.y = clampf(v.y, L["side"][0], L["side"][1])
			v.z = clampf(v.z, L["twist"][0], L["twist"][1])
		out[jn] = v
	return {"region": region, "amp": a, "impulse": impulse, "side": side, "joints": out, "drop_delay_s": float(P["delay"])}


static func to_json(r: Dictionary) -> Dictionary:
	var o := r.duplicate(true)
	var js := {}
	for j in r["joints"]:
		var v: Vector3 = r["joints"][j]
		js[j] = [v.x, v.y, v.z]
	o["joints"] = js
	return o
