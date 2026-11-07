## part_first.gd - PART-FIRST ACTIONS (N068): click a body part, get the moves it can do. A fist or hand throws a punch and blocks,
## a foot or shin kicks, a knee strikes, an elbow strikes, the head butts. Picking one builds the move with that part as the striker
## from ROADMAP 22's text-to-blocking (TextBlocking.build: the closest saved segment or StrikeBlocking's generated key poses),
## the words carrying the part's side ("right front kick"). Knee strike, elbow strike, headbutt and block are OFFERED but not built:
## text-to-blocking has no generator for them yet, and the status says so (no undo step, nothing changed).
class_name PartFirst
extends RefCounted

## id -> [label, the words for text-to-blocking with {s} the side ("left" / "right"); "" = not built yet]
const MOVES := {
	"punch": ["Punch", "{s} punch"],
	"block": ["Block", ""],
	"kick": ["Kick", "{s} front kick"],
	"roundhouse": ["Roundhouse", "{s} roundhouse kick"],
	"knee": ["Knee strike", ""],
	"elbow": ["Elbow strike", ""],
	"headbutt": ["Headbutt", ""],
}


static func side_of(j: String) -> String:
	return "left" if j.ends_with("_l") else ("right" if j.ends_with("_r") else "")


## the kind of body part a joint belongs to: hand, arm, foot, shin, thigh, head or ""
static func kind_of(j: String) -> String:
	if j.begins_with("hand") or j in Body.FINGERS:
		return "hand"
	if j.begins_with("lowerarm") or j.begins_with("upperarm"):
		return "arm"
	if j.begins_with("foot") or j.begins_with("ball"):
		return "foot"
	if j.begins_with("calf"):
		return "shin"
	if j.begins_with("thigh"):
		return "thigh"
	if j == "head" or j.begins_with("neck"):
		return "head"
	return ""


## the move ids this part can do, in ring order
static func offers(j: String) -> Array:
	match kind_of(j):
		"hand":
			return ["punch", "block"]
		"arm":
			return ["elbow", "block"]
		"foot":
			return ["kick", "roundhouse"]
		"shin":
			return ["roundhouse", "kick"]
		"thigh":
			return ["knee"]
		"head":
			return ["headbutt"]
	return []


## the words to give text-to-blocking for move `id` from part `j`; "" = no generator yet
static func words(j: String, id: String) -> String:
	return String(MOVES[id][1]).replace("{s}", side_of(j))


## the striking part of a clip, MEASURED: the hand or foot (ball) whose point reaches the highest speed in the clip -> "hand_r" / "foot_l" ...
static func striker_of(S: Scene, B: Body) -> String:
	var keep := B.state()
	var best := ""
	var top := -1.0
	for pt in ["hand_l", "hand_r", "ball_l", "ball_r"]:
		var pk := 0.0
		for v in StrikeBlocking.point_speed(S, B, pt):
			pk = maxf(pk, float(v))
		if pk > top:
			top = pk
			best = pt
	B.set_state(keep)
	return best.replace("ball_", "foot_")


## agent tools (read-only): weight_split {} -> the open body's split; part_moves {part} -> the moves it offers and the words each builds from;
## stance_fit {id?, body?} -> the stance sizes for the open body (or a given body dict), with the ratios and their source
static func serve(tool: String, m: Variant, p: Dictionary) -> Dictionary:
	var B: Body = m.B
	if tool == "weight_split":
		var r := WeightSplit.read(B)
		return {"ok": true, "result": {"shown": r["shown"], "left": r["l"], "right": r["r"]}}
	if tool == "part_moves":
		var j := String(p.get("part", ""))
		if j == "" or not B.P.has(j):
			return {"ok": false, "error": "part: a joint name (hand_r, foot_l, thigh_r, head ...)"}
		var out := []
		for id in offers(j):
			out.append({"id": id, "label": MOVES[id][0], "words": words(j, id), "built": words(j, id) != ""})
		return {"ok": true, "result": {"part": j, "moves": out}}
	if tool == "stance_fit":
		var b := B
		if p.has("body"):
			b = Body.new()
			b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
			b.set_proportions(p["body"])
			b.fk()
		var ids: Array = [String(p["id"])] if p.has("id") else StanceFit.ORDER
		var res := []
		for id in ids:
			if not StanceFit.TABLE.has(id):
				return {"ok": false, "error": "id: boxer, karate or fencing"}
			var sz := StanceFit.sizes(b, id)
			res.append({"id": id, "width_m": sz["width"], "length_m": sz["length"], "leg_m": sz["leg"], "shoulder_m": sz["shoulder"],
				"ratios": {"w": StanceFit.TABLE[id]["w"], "l": StanceFit.TABLE[id]["l"]}, "src": StanceFit.TABLE[id]["src"]})
		return {"ok": true, "result": {"stances": res}}
	return {"ok": false, "error": "unknown tool"}
