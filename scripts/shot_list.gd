## SHOT LIST (Friday plan 150, p150shotlist): a beginner types a short story, one shot per line or sentence, and Kine makes a
## shot card for each: a camera (size, lens, height, side) read from the words, and the move read from the verbs. Pure functions:
## parse() reads the words, cards_for() puts the camera keys in the scene's shot list (the same shot format as Auto camera, so the
## shots play, export and show on the timeline like any other). The panel is scripts/shot_list_ui.gd.
##
## WORDS (first match wins, plain English; nothing else is needed):
##   SIZE   close, close-up, closeup, face, head      -> close-up: 85 mm, 2.0 m, 30 deg off the front, centred on the chest (1.5 m)
##          wide, far, full, long                     -> wide: 28 mm, 5.0 m, straight on, centred on the body
##          (none, medium, mid)                       -> medium: 50 mm, 5.0 m, 15 deg off the front, centred on the body
##   HEIGHT low, low angle, from below                -> camera 12 deg below the subject (looks up: power)
##          high, high angle, from above, bird       -> camera 12 deg above the subject (looks down)
##   SIDE   side, profile                             -> 80 deg off the front
##   MOVE   the first verb of the list in the line, in any form (walk, run, jump, strike, punch, kick, hit, block, wave, raise, turn, sit,
##          stand, fall, point, look, fight); none = "hold"
## A line with no words at all still makes a shot (medium, hold): nothing typed is lost.
## Card i starts at i x SHOT_GAP seconds on a whole frame (the first at 0 s: a scene's first shot always starts there); a frame that
## already has a shot is skipped and named (nothing is overwritten).
class_name ShotList
extends RefCounted

const SHOT_GAP := 2.0          # s between the cards of the story (a beginner's default; the shot's cut can be dragged after)
const FR := Rect2i(0, 0, 1280, 720)
const CENTRE_Y := 1.0          # m: the body's middle (a medium and a wide frame it whole)
const CHEST_Y := 1.5           # m: a close-up's middle (head, chest and the hands)
const SIZE_WORDS := {"close": "close", "close-up": "close", "closeup": "close", "face": "close", "head": "close",
	"wide": "wide", "far": "wide", "full": "wide", "long": "wide", "medium": "medium", "mid": "medium"}
const MOVE_WORDS := ["walk", "run", "jump", "strike", "punch", "kick", "hit", "block", "wave", "raise", "turn", "sit", "stand", "fall", "point", "look", "fight"]
const SIZES := {
	"close": {"f": 85.0, "d": 2.8, "theta": 30.0, "y": CHEST_Y, "word": "Close-up"},
	"wide": {"f": 28.0, "d": 5.0, "theta": 0.0, "y": CENTRE_Y, "word": "Wide"},
	"medium": {"f": 50.0, "d": 5.0, "theta": 15.0, "y": CENTRE_Y, "word": "Medium"},
}
const LOW_DEG := 12.0


## the story -> one card per line or sentence: [{"text", "size", "word", "lens", "dist", "pitch", "theta", "move", "label"}]
static func parse(story: String) -> Array:
	var out := []
	var parts := story.replace(".", "\n").replace("!", "\n").replace("?", "\n").split("\n")
	for raw in parts:
		var line := String(raw).strip_edges()
		if line == "":
			continue
		var words := _words(line)
		var size := "medium"
		var pitch := 0.0
		var theta := -1.0
		var move := "hold"
		for w in words:
			if SIZE_WORDS.has(w):
				size = SIZE_WORDS[w]
				break
		var spec: Dictionary = SIZES[size]
		var pitch_word := ""
		for w in words:
			if w == "low" or w == "below" or w == "upward":
				pitch_word = "low"
				break
			if w == "high" or w == "above" or w == "bird":
				pitch_word = "high"
				break
		if pitch_word == "low":
			pitch = LOW_DEG
		elif pitch_word == "high":
			pitch = -LOW_DEG
		if words.has("side") or words.has("profile"):
			theta = 80.0
		for w in words:   # a verb in any form: "walks", "raises", "striking" (the stem starts the word)
			var hit := ""
			for mv in MOVE_WORDS:
				if w.begins_with(mv):
					hit = mv
					break
			if hit != "":
				move = hit
				break
		var cam := String(spec["word"])
		if pitch_word == "low":
			cam += " low angle"
		elif pitch_word == "high":
			cam += " high angle"
		out.append({"text": line, "size": size, "word": cam, "lens": float(spec["f"]), "dist": float(spec["d"]),
			"pitch": pitch, "theta": theta if theta >= 0.0 else float(spec["theta"]), "y": float(spec["y"]), "move": move,
			"label": "%s %d mm: %s" % [cam, roundi(float(spec["f"])), move]})
	return out


static func _words(line: String) -> Array:
	var w := []
	for t in line.to_lower().replace(",", " ").replace(";", " ").replace(":", " ").split(" ", false):
		w.append(String(t).strip_edges())
	return w


## the camera key of one card, in the hero's space (the same frame as Auto camera and every shot): {"pos", "aim", "f"}
static func key_for(card: Dictionary) -> Dictionary:
	var centre := Vector3(0.0, float(card["y"]), 0.0)
	var dirv := Basis(Vector3.UP, deg_to_rad(float(card["theta"]))) * Vector3(0, 0, 1)
	var k := AutoCam._place(centre, dirv, float(card["dist"]), float(card["lens"]), float(card["pitch"]), centre, 0.0)
	return {"pos": k["pos"], "aim": k["aim"], "f": float(card["lens"])}


## writes the cards into `shots` (the scene's list): returns {"added": n, "skipped": [names]} and changes nothing for a skipped card
static func write(shots: Array, cards: Array, fps: int) -> Dictionary:
	var added := 0
	var skipped := []
	for i in cards.size():
		var card: Dictionary = cards[i]
		var fr := roundi(float(i) * SHOT_GAP * float(fps))
		var t := float(fr) / float(fps)
		var clash := false
		for sh in shots:
			if roundi(float(sh["t"]) * float(fps)) == fr:
				clash = true
				break
		if clash:
			skipped.append("shot %d at %.1f s" % [i + 1, t])
			continue
		var key := key_for(card)
		key["t"] = t
		shots.insert(ShotCam.insert_index(shots, t), {"t": t, "name": "%s: %s" % [card["label"], card["text"]], "keys": [key]})
		added += 1
	return {"added": added, "skipped": skipped}
