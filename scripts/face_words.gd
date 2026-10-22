## face_words.gd - words to a FACE (ROADMAP I20): "tired and angry", "a little surprised", "smiling but in pain".
## A phrase is emotions (a vocabulary of FACS action-unit sets), each with an optional intensity word, joined by "and" / "but".
## The words become a FACS AU mix, and the AU mix becomes the channels the face rig has (Face.EXPR_AU's: brow, squint, widen,
## blink, press, jaw, shape), then the keyed channels (Face.CHANNELS) the caller keys at the playhead (main._pose_words).
##
## FACS (Ekman & Friesen, Facial Action Coding System, 1978; Ekman, Friesen & Hager 2002). Intensity letters as face.gd reads
## them: A 0.15, B 0.3, C 0.5, D 0.8, E 1.0. Prototype AU sets are EMFACS's (Friesen & Ekman 1983, "EMFACS-7"): happiness 6+12,
## sadness 1+4+15, surprise 1+2+5+26, fear 1+2+4+5+20+25, anger 4+5+7+23, disgust 9/10 (+15), contempt R12+R14. Pain: Prkachin 1992
## (4, 6/7, 9/10, 43). Fatigue: drooping, closing lids AU41/43 (Sundelin et al. 2013, "Cues of fatigue"). Boredom: lid closure and a
## slack jaw (Craig et al. 2008, "Emotions during learning"). Concentration / confusion / worry: Rozin & Cohen 2003 (AU4 brow
## furrow with AU24 lip press; AU4+7; AU1+4). Intensities here are from memory of those sources, not re-checked against them.
##
## AU -> RIG CHANNEL (what the rig can draw; an AU with no channel is listed in the table and ignored):
##   brow   = max(AU1, AU2) - AU4        both brows (+ raise, - lower)
##   squint = max(AU6, AU7)              cheek raiser / lid tightener
##   widen  = AU5                        upper lid raiser
##   blink  = AU43                       eyes closed / drooping lids
##   press  = max(AU23, AU24)            lips tightened / pressed
##   jaw    = max(AU25, AU26, AU27)      lips part / jaw drop (fraction of Face.JAW_MAX_DEG)
##   shape  = "E" from AU9 / AU10 / AU12 / AU20 (lip corner pulled, bared teeth: the wide mouth), "O" from AU26 / AU27; kept at 0.5+
## No channel: AU14 (dimpler), AU15 (corner depressor), AU16, AU17 (chin raiser): ignored.
##
## BLENDING. "and": the parts add (clamped to the channel's range). Conflicting AUs are averaged instead of added: raising and
## lowering the brows (AU1/2 vs AU4), pressing the lips and opening the jaw (AU23/24 vs AU25-27). "but" weights the second part
## more: the first part counts BUT_FIRST (0.6) against 1.0 for the second.
class_name FaceWords
extends RefCounted

const BUT_FIRST := 0.6
## the weights: how many of the words' intensity a part carries (1.0 = the full prototype)
const INTENSITY := {"slightly": 0.25, "faintly": 0.25, "little": 0.35, "bit": 0.4, "kindof": 0.5, "sortof": 0.5, "half": 0.5, "somewhat": 0.6,
	"fairly": 0.7, "quite": 0.8, "very": 1.0, "really": 1.0, "so": 1.0, "completely": 1.0, "extremely": 1.3, "utterly": 1.3}
## words that carry no AU: "look angry", "feeling tired", "in pain", "with effort"
const FILLER := ["look", "looks", "looking", "feel", "feels", "feeling", "face", "expression", "a", "an", "the", "in", "with", "is", "being", "get",
	"gets", "getting", "he", "she", "they", "it", "looked", "seems", "seem", "his", "her", "of"]
const CONNECT := ["and", "but", "then", ",", ";"]
## emotion -> {"au": {AU: intensity}}. anger / surprise / pain / effort are Face.EXPR_AU's own four (the test holds them to it)
const EMOTIONS := {
	"neutral": {},
	"happy": {"AU6": 0.5, "AU12": 0.8},
	"sad": {"AU1": 0.6, "AU4": 0.4, "AU15": 0.5},
	"angry": {"AU4": 0.9, "AU5": 0.6, "AU7": 0.4, "AU23": 0.8},
	"surprised": {"AU1": 0.9, "AU2": 0.9, "AU5": 1.0, "AU26": 0.7},
	"scared": {"AU1": 0.8, "AU2": 0.5, "AU4": 0.3, "AU5": 0.9, "AU20": 0.6, "AU25": 0.4},
	"disgusted": {"AU9": 0.8, "AU10": 0.6, "AU4": 0.4, "AU7": 0.4, "AU15": 0.5},
	"smug": {"AU12": 0.4, "AU14": 0.4, "AU7": 0.3, "AU2": 0.2},
	"tired": {"AU43": 0.5, "AU4": 0.2, "AU26": 0.15},
	"bored": {"AU43": 0.3, "AU26": 0.1, "AU15": 0.3},
	"focused": {"AU4": 0.4, "AU7": 0.4, "AU24": 0.3},
	"determined": {"AU4": 0.6, "AU7": 0.3, "AU24": 0.5},
	"pain": {"AU4": 0.8, "AU7": 0.8, "AU10": 0.7, "AU25": 0.2, "AU43": 0.6},
	"effort": {"AU4": 0.5, "AU7": 0.6, "AU24": 0.9},
	"worried": {"AU1": 0.5, "AU4": 0.4, "AU5": 0.2},
	"confused": {"AU4": 0.4, "AU7": 0.2},
}
## a synonym -> [emotion, scale of its intensity]
const ALIAS := {"smile": ["happy", 1.0], "smiling": ["happy", 1.0], "smiles": ["happy", 1.0], "glad": ["happy", 1.0], "joyful": ["happy", 1.0],
	"pleased": ["happy", 0.7], "cheerful": ["happy", 0.9], "grin": ["happy", 1.0], "grinning": ["happy", 1.0],
	"upset": ["sad", 1.0], "unhappy": ["sad", 1.0], "sorrowful": ["sad", 1.2],
	"mad": ["angry", 1.0], "furious": ["angry", 1.3], "enraged": ["angry", 1.3], "annoyed": ["angry", 0.4], "irritated": ["angry", 0.5], "cross": ["angry", 0.5],
	"surprise": ["surprised", 1.0], "shocked": ["surprised", 1.0], "startled": ["surprised", 0.8], "amazed": ["surprised", 0.9], "astonished": ["surprised", 1.2],
	"afraid": ["scared", 1.0], "frightened": ["scared", 1.0], "terrified": ["scared", 1.3], "fearful": ["scared", 1.0], "anxious": ["scared", 0.5],
	"nervous": ["scared", 0.5], "fear": ["scared", 1.0],
	"disgust": ["disgusted", 1.0], "grossed": ["disgusted", 0.9],
	"sleepy": ["tired", 0.8], "exhausted": ["tired", 1.3], "drowsy": ["tired", 0.8], "weary": ["tired", 1.0], "fatigued": ["tired", 1.2],
	"uninterested": ["bored", 1.0], "concentrating": ["focused", 1.0], "attentive": ["focused", 0.7],
	"hurt": ["pain", 1.0], "hurting": ["pain", 1.0], "painful": ["pain", 1.0], "straining": ["effort", 1.0], "strain": ["effort", 1.0], "exertion": ["effort", 1.0],
	"worry": ["worried", 1.0], "concerned": ["worried", 0.7], "puzzled": ["confused", 1.0], "confusion": ["confused", 1.0],
	"calm": ["neutral", 1.0], "relaxed": ["neutral", 1.0], "blank": ["neutral", 1.0]}
## the conflicting pairs, as rig channels: (a raised, a lowered brow) and (lips pressed, jaw open)
const PRESS_JAW_MIN := 0.3
const NUMERIC := ["brow", "squint", "widen", "blink", "press", "jaw"]


## every word the phrase can use, for the "not a word I know" message
static func known() -> Array:
	var out := []
	for k in EMOTIONS:
		out.append(k)
	for k in ALIAS:
		if not k in out:
			out.append(k)
	return out


static func _is_face_word(w: String) -> bool:
	return EMOTIONS.has(w) or ALIAS.has(w)


## the words as segments [{"conn": the connector before it ("and" first), "words": [...]}]; "a little" etc. made one word first
static func _segments(text: String) -> Array:
	var t := " " + text.to_lower().replace(",", " , ").replace(";", " ; ") + " "
	t = t.replace(" a little ", " little ").replace(" a bit ", " bit ").replace(" kind of ", " kindof ").replace(" sort of ", " sortof ")
	var segs := []
	var cur := {"conn": "and", "words": []}
	for w: String in t.split(" ", false):
		if w in CONNECT:
			if not (cur["words"] as Array).is_empty():
				segs.append(cur)
			cur = {"conn": "but" if w == "but" else "and", "words": []}
		else:
			(cur["words"] as Array).append(w)
	if not (cur["words"] as Array).is_empty():
		segs.append(cur)
	return segs


## the phrase split into the part that is a face and the part that is a pose: {"face": "...", "pose": "..."} (either may be "").
## A segment is the face's when it names an emotion (or says look / feel / face); the face segments keep their connectors
static func route(text: String) -> Dictionary:
	var face := ""
	var pose := []
	for s in _segments(text):
		var ws: Array = s["words"]
		var is_face := false
		for w in ws:
			if _is_face_word(w) or w in ["look", "looks", "looking", "feel", "feeling", "feels", "expression"]:
				is_face = true
		if is_face:
			face += ("" if face == "" else (" but " if s["conn"] == "but" else " and ")) + " ".join(ws)
		else:
			pose.append(" ".join(ws))
	return {"face": face, "pose": ", ".join(pose)}


## the AU set of one emotion at an intensity: {AU: 0..1}
static func aus(emotion: String, k: float) -> Dictionary:
	var out := {}
	var src: Dictionary = EMOTIONS[emotion]
	for au in src:
		out[au] = clampf(float(src[au]) * k, 0.0, 1.0)
	return out


## the rig channels of an AU set: {brow, squint, widen, blink, press, jaw, shape, shape_w}
static func channels(a: Dictionary) -> Dictionary:
	var g := func(n: String) -> float: return float(a.get(n, 0.0))
	var d := {"brow": clampf(maxf(g.call("AU1"), g.call("AU2")) - g.call("AU4"), -1.0, 1.0),
		"squint": maxf(g.call("AU6"), g.call("AU7")), "widen": g.call("AU5"), "blink": g.call("AU43"),
		"press": maxf(g.call("AU23"), g.call("AU24")), "jaw": maxf(maxf(g.call("AU25"), g.call("AU26")), g.call("AU27")),
		"shape": "", "shape_w": 0.0}
	for au in ["AU9", "AU10", "AU12", "AU20"]:
		if g.call(au) >= 0.5 and g.call(au) > float(d["shape_w"]):
			d["shape"] = "E"
			d["shape_w"] = g.call(au)
	for au in ["AU26", "AU27"]:
		if g.call(au) >= 0.5 and g.call(au) > float(d["shape_w"]):
			d["shape"] = "O"
			d["shape_w"] = g.call(au)
	return d


## two parts' channels blended with weights wa, wb (the "and" / "but" rule above)
static func blend(a: Dictionary, b: Dictionary, wa: float, wb: float) -> Dictionary:
	var out := {}
	var pj: bool = (float(a["press"]) > PRESS_JAW_MIN and float(b["jaw"]) > PRESS_JAW_MIN) or (float(b["press"]) > PRESS_JAW_MIN and float(a["jaw"]) > PRESS_JAW_MIN)
	for ch in NUMERIC:
		var x := float(a[ch])
		var y := float(b[ch])
		var avg: bool = (ch == "brow" and x * y < 0.0) or (pj and ch in ["press", "jaw"])
		out[ch] = (wa * x + wb * y) / (wa + wb) if avg else wa * x + wb * y
		out[ch] = clampf(float(out[ch]), -1.0 if ch == "brow" else 0.0, 1.0)
	var sa := float(a["shape_w"]) * wa
	var sb := float(b["shape_w"]) * wb
	out["shape"] = a["shape"] if sa >= sb else b["shape"]
	out["shape_w"] = maxf(sa, sb)
	if out["shape"] == "":
		out["shape_w"] = 0.0
	return out


## parse() -> {"ok": true, "mix": channels, "parts": [{"emotion", "k", "weight"}]} or {"ok": false, "error": "... what to type"}
static func parse(text: String) -> Dictionary:
	var parts := []   # [{"emotion", "k", "conn"}]
	var pend := 1.0
	var have_pend := ""
	for s in _segments(text):
		var first := true
		for w: String in s["words"]:
			if w in FILLER:
				continue
			if INTENSITY.has(w):
				pend = float(INTENSITY[w])
				have_pend = w
			elif _is_face_word(w):
				var em: String = w if EMOTIONS.has(w) else String(ALIAS[w][0])
				var sc: float = 1.0 if EMOTIONS.has(w) else float(ALIAS[w][1])
				parts.append({"emotion": em, "k": pend * sc, "conn": s["conn"] if first else "and"})
				first = false
				pend = 1.0
				have_pend = ""
			else:
				return {"ok": false, "error": "'%s' is not a face word I know. Try one of: %s. Intensity: %s. Join with 'and' / 'but', e.g. 'tired and angry' or 'a little surprised but smiling'" % [
					w, ", ".join(known()), ", ".join(INTENSITY.keys())]}
	if have_pend != "":
		return {"ok": false, "error": "'%s' needs an emotion after it: try '%s angry'" % [have_pend, have_pend]}
	if parts.is_empty():
		return {"ok": false, "error": "no face in that: try 'tired and angry', 'a little surprised' or 'smiling but in pain'"}
	var acc := channels(aus(parts[0]["emotion"], parts[0]["k"]))
	var wt := 1.0
	for i in range(1, parts.size()):
		var nxt := channels(aus(parts[i]["emotion"], parts[i]["k"]))
		var but: bool = parts[i]["conn"] == "but"
		acc = blend(acc, nxt, BUT_FIRST if but else 1.0, 1.0)
	for p in parts:
		p.erase("conn")
	return {"ok": true, "mix": acc, "parts": parts}


## the keyed channel values of a mix (Face.CHANNELS; the gaze is left alone, so it is not here)
static func values(mix: Dictionary) -> Dictionary:
	var v := {"brow_l": float(mix["brow"]), "brow_r": float(mix["brow"]), "squint": float(mix["squint"]), "widen": float(mix["widen"]),
		"blink": float(mix["blink"]), "press": float(mix["press"]), "jaw": float(mix["jaw"]),
		"vis_M": 0.0, "vis_A": 0.0, "vis_O": 0.0, "vis_E": 0.0}
	if String(mix["shape"]) != "":
		v["vis_" + String(mix["shape"])] = float(mix["shape_w"])
	return v
