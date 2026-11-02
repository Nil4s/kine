class_name HallWords
extends RefCounted
## hall_words.gd - s222 WORDS FOR MORE THAN HOUSES. Nick 11-01: "the word build is insane, never saw it anywhere". The hall challenge (hall_compare/kine2/hall_driver.gd)
## needed about 860 lines of calls; every element of it is now ONE sentence on the PART on screen (m.S.part, mm, X right, Y up, Z toward the viewer).
## No AI, no network: regexes + a lexicon, in the style of BuildWords. Each sentence is built on a COPY of the record, replayed (a step that fails builds nothing)
## and then committed as ONE undo step. The words that are not understood are LISTED; a word that looks like a typo of a known one asks ("did you mean columns?").
## It only maps words onto features that exist: Part.prim (229), pattern linear/circular/route/grid (228), roof (226), pipe3d (215), ornament (227, PartOrnament),
## appear / PieceLook (231), TempleLight (232), nature (225: NatureWords), PartAssert (220) and PartWarn (221) for the CHECK sentences, TradeWords for shop names.
## THE SENTENCES (each builds what it says):
##   a ground 120 x 120 m                         a platform 21 x 14 m, 1.3 m high         a hall 18 x 10 m, 5 m tall with a door 2.4 m wide
##   a stair of 9 steps up the front, 4 m wide    6 red columns 0.5 wide along the front   5 bays of 3.6 m with columns       16 columns around the hall
##   a double roof with upturned corners          a gable roof                              a wall around it, 2 m high, 0.4 m thick
##   a path 3 m wide, 20 m long                   2 chiwen on the ridge ends (ornament)     make the columns red / paint the roof gold
##   a tube 30 mm through 0,0,0 then 0,0,500 then 300,0,500 / through these points         repeat it 12 times around / repeat it 5 times along x 600 mm
##   a 2x4 1.2 m long, a 4x8 sheet of 3/4 ply, an M6 x 16 bolt, 1/4-20 bolt, caibro, SC1  (TradeWords: the reply says the translation)
##   light it at 4 pm                              2 ginkgo trees 13 m tall, a box hedge 0.8 m high (nature words)
##   check the pistons fit the bores / check body 1 touches body 2 clearance 0-0.2 mm / check there are no overlaps / check the part
## run_on(rec, text, ctx) -> {"ok", "kind", "say", "error", "did", "ignored", "notes", "rec"}; run(m, text, ctx) does it on the main node with ONE undo step.

const FILLER := ["a", "an", "the", "with", "and", "of", "on", "at", "in", "to", "it", "its", "that", "has", "have", "i", "want", "need", "please", "build", "make", "create", "give",
	"me", "us", "some", "just", "also", "then", "now", "would", "like", "can", "you", "could", "for", "is", "be", "are", "new", "up", "out", "from", "by", "each", "every", "all",
	"this", "these", "those", "my", "our", "add", "put", "place", "over", "into", "so", "as", "too", "one", "there", "no", "not", "any", "than", "side", "sides", "both", "inside", "same"]
const UNITS := ["m", "mm", "cm", "ft", "in", "x", "metres", "meters", "metre", "meter", "feet", "foot", "inch", "inches", "pm", "am", "deg", "degrees"]
const SHAPE := ["wide", "long", "deep", "high", "tall", "height", "thick", "thickness", "across", "diameter", "apart", "spacing", "gap", "big", "large", "small", "round", "square",
	"front", "back", "rear", "left", "right", "middle", "centre", "center", "corner", "corners", "around", "along", "through", "points", "point", "ground", "top", "twice", "times", "time",
	"step", "steps", "stair", "stairs", "staircase", "stairway", "column", "columns", "pillar", "pillars", "post", "posts", "bay", "bays", "platform", "terrace", "plinth", "podium", "base",
	"hall", "house", "temple", "pavilion", "building", "door", "doorway", "roof", "roofs", "double", "upturned", "curved", "chinese", "xieshan", "hip", "hipped", "gable", "gabled", "pyramid",
	"shed", "flat", "wall", "walls", "compound", "enclose", "surround", "path", "paths", "lawn", "plaza", "courtyard", "tube", "pipe", "rod", "solid", "hollow", "repeat", "copies", "copy",
	"grid", "row", "axis", "check", "verify", "confirm", "test", "fit", "fits", "touch", "touches", "overlap", "overlaps", "clearance", "least", "most", "exactly", "count", "bodies", "body",
	"part", "warnings", "light", "sun", "sunset", "sunrise", "noon", "morning", "afternoon", "evening", "paint", "colour", "color", "turn", "stand", "standing", "sag", "lift", "corners",
	"overhang", "ridge", "ends", "end", "named", "called", "bolt", "screw", "sheet", "ply", "plywood", "plank", "board", "stud", "piece", "pieces", "lumber", "timber", "key", "blank", "lock",
	"degrees", "tile", "tiles", "gold", "golden", "stone", "wood", "marble", "lacquer", "glazed", "dark", "light", "pale", "bright", "deeper", "wall", "wide", "thin", "tight", "gate", "bend", "radius"]
const COLORS := {"red": [0.72, 0.12, 0.1], "gold": [0.85, 0.65, 0.15], "golden": [0.85, 0.65, 0.15], "yellow": [0.92, 0.8, 0.2], "green": [0.2, 0.5, 0.25], "blue": [0.2, 0.35, 0.75],
	"grey": [0.55, 0.56, 0.58], "gray": [0.55, 0.56, 0.58], "white": [0.93, 0.93, 0.9], "black": [0.08, 0.08, 0.09], "brown": [0.4, 0.26, 0.14], "orange": [0.9, 0.5, 0.12],
	"teal": [0.1, 0.5, 0.5], "pink": [0.9, 0.55, 0.65], "purple": [0.5, 0.25, 0.6], "stone": [0.62, 0.6, 0.56], "wooden": [0.5, 0.33, 0.18]}
## the words the typo check asks about (a known word within 1-2 letters of an unknown one)
const VOCAB := ["columns", "column", "pillars", "platform", "terrace", "stairs", "staircase", "double", "upturned", "roof", "hedges", "hedge", "compound", "repeat", "around", "tube", "check",
	"bays", "overlaps", "touches", "clearance", "diameter", "chinese", "curved", "ground", "through", "points", "times", "afternoon", "morning", "sunset", "pipe", "colour", "paint", "path",
	"temple", "pavilion", "wall", "walls", "steps", "hall", "high", "wide", "thick", "front", "back", "left", "right", "ridge", "bodies", "fits", "along", "gable", "hipped", "sheet", "plywood"]
## the words only this file knows: a typo of one of these claims a sentence for it (the house words stay BuildWords')
const HALL_ONLY := ["columns", "column", "bays", "upturned", "double", "repeat", "tube", "check", "compound", "terrace", "xieshan", "chinese", "overlaps", "clearance", "plywood"]
const BLOCKS := {"ground": "ground", "lawn": "ground", "plaza": "ground", "courtyard": "ground", "platform": "platform", "terrace": "platform", "plinth": "platform", "podium": "platform",
	"base": "platform", "hall": "hall", "house": "hall", "temple": "hall", "pavilion": "hall", "building": "hall"}
const TYPES := {"gable": "gable", "gabled": "gable", "hip": "hip", "hipped": "hip", "xieshan": "xieshan", "pyramid": "pyramid", "shed": "shed", "flat": "flat"}
const LIGHT_WORDS := {"sunrise": 6.5, "morning": 9.0, "noon": 12.0, "midday": 12.0, "afternoon": 15.0, "evening": 18.0, "sunset": 18.5, "dusk": 19.0}
const SKIP_WALL_THICK := 400.0


# ---------------------------------------------------------------- reading the sentence

static func _clean(text: String) -> Array:
	var t := BuildWords.tokens(text)
	var out := []
	for w in t:
		var x := String(w)
		x = {"metres": "m", "metre": "m", "meters": "m", "meter": "m", "feet": "ft", "foot": "ft", "inch": "in", "inches": "in", "millimetres": "mm", "millimeters": "mm",
			"centimetres": "cm", "centimeters": "cm"}.get(x, x)
		out.append(x)
	return out


static func _is_num(w: String) -> bool:
	return w != "" and w.is_valid_float()


static func _known(w: String) -> bool:
	return FILLER.has(w) or UNITS.has(w) or SHAPE.has(w) or COLORS.has(w) or _is_num(w) or w == "," or w.begins_with("ord") or BLOCKS.has(w) or TYPES.has(w) \
		or PieceLook.NOUNS.has(w) or LIGHT_WORDS.has(w)


static func did_you_mean(w: String) -> String:
	if w.length() < 4 or _is_num(w):
		return ""
	var best := ""
	var best_d := (2 if w.length() > 5 else 1) + 1
	for v in VOCAB:
		var d := EasyHome.levenshtein(w, String(v))
		if d > 1 and BuildWords._swapped(w, String(v)):
			d = 1
		if d < best_d:
			best_d = d
			best = String(v)
	return best


## the first word of the sentence that is a slip of a known word ({"word", "did"}) or {}
static func typo_in(toks: Array) -> Dictionary:
	for w in toks:
		var x := String(w)
		if _known(x) or x.length() < 4:
			continue
		var d := did_you_mean(x)
		if d != "":
			return {"word": x, "did": d}
	return {}


static func _unknown_words(toks: Array, used: Array) -> Array:
	var out := []
	for w in toks:
		var x := String(w)
		if not _known(x) and not used.has(x) and not out.has(x) and x.length() > 1:
			out.append(x)
	return out


static func _mm(num: String, unit: String, def_unit := "m") -> float:
	var u := unit if unit != "" else def_unit
	var f: float = float({"mm": 1.0, "cm": 10.0, "m": 1000.0, "ft": 304.8, "in": 25.4}.get(u, 1000.0))
	return float(num) * f


const NUM := "(\\d+(?:\\.\\d+)?)"
const UNIT := "(?: (mm|cm|m|ft|in))?"


## "0.5 wide", "3 m long", "height 5 m": the first size beside one of the words, in mm; -1 when none
static func _attr(s: String, words: Array, def_unit := "m") -> float:
	var alt := "|".join(PackedStringArray(words))
	var re := RegEx.create_from_string(NUM + UNIT + " (?:" + alt + ")\\b")
	var m := re.search(s)
	if m != null:
		return _mm(m.get_string(1), m.get_string(2), def_unit)
	re = RegEx.create_from_string("\\b(?:" + alt + ") " + NUM + UNIT)
	m = re.search(s)
	if m != null:
		return _mm(m.get_string(1), m.get_string(2), def_unit)
	return -1.0


## "21 x 14 m" / "21 x 14 x 5 m": [w, d, h or -1] in mm, or []
static func _dims(s: String, def_unit := "m") -> Array:
	var re := RegEx.create_from_string(NUM + UNIT + " x " + NUM + UNIT + "(?: x " + NUM + UNIT + ")?")
	var m := re.search(s)
	if m == null:
		return []
	var u := m.get_string(2)
	if u == "":
		u = m.get_string(4)
	if u == "":
		u = m.get_string(6)
	var h := -1.0
	if m.get_string(5) != "":
		h = _mm(m.get_string(5), u, def_unit)
	return [_mm(m.get_string(1), u, def_unit), _mm(m.get_string(3), u, def_unit), h]


static func _count(s: String, nouns: Array, def := 1) -> int:
	var re := RegEx.create_from_string("(\\d+) (?:[a-z]+ ){0,3}?(?:" + "|".join(PackedStringArray(nouns)) + ")\\b")
	var m := re.search(s)
	if m != null:
		return int(m.get_string(1))
	return def


static func _color_of(toks: Array) -> String:
	for w in toks:
		if COLORS.has(String(w)):
			return String(w)
	return ""


static func _side(toks: Array, def := "front") -> String:
	for w in toks:
		match String(w):
			"front":
				return "front"
			"back", "rear":
				return "back"
			"left":
				return "left"
			"right":
				return "right"
	return def


static func _has(toks: Array, ws: Array) -> bool:
	for w in toks:
		if ws.has(String(w)):
			return true
	return false


static func _g(v: float) -> String:
	return ("%.2f" % v).rstrip("0").rstrip(".")


static func _m(v: float) -> String:
	return _g(v / 1000.0) + " m"


# ---------------------------------------------------------------- the record (what the earlier sentences left)

static func _nbodies(rec: Dictionary) -> int:
	return int(Part.replay(rec).get("bodies", 0))


## the blocks the sentences built, newest last: {"kind", "name", "x0".."z1"} (mm)
static func blocks(rec: Dictionary) -> Array:
	var out := []
	for f in rec.get("features", []):
		if (f as Dictionary).has("hw_box"):
			var b: Array = f["hw_box"]
			out.append({"kind": String(f.get("hw", "")), "name": String(f.get("name", "")), "x0": float(b[0]), "y0": float(b[1]), "z0": float(b[2]), "x1": float(b[3]), "y1": float(b[4]), "z1": float(b[5])})
	return out


static func _last(rec: Dictionary, kinds: Array) -> Dictionary:
	var bs := blocks(rec)
	for i in range(bs.size() - 1, -1, -1):
		if kinds.is_empty() or kinds.has(String(bs[i]["kind"])):
			return bs[i]
	return {}


static func _host(rec: Dictionary, toks: Array) -> Dictionary:
	for w in toks:
		if BLOCKS.has(String(w)):
			var h := _last(rec, [String(BLOCKS[w])])
			if not h.is_empty():
				return h
	var h2 := _last(rec, ["hall"])
	return h2 if not h2.is_empty() else _last(rec, ["platform", "ground"] if false else [])


static func _stamp(f: Dictionary, kind: String, b: Dictionary) -> void:
	f["hw"] = kind
	f["hw_box"] = [b["x0"], b["y0"], b["z0"], b["x1"], b["y1"], b["z1"]]


static func _name_body(rec: Dictionary, idx: int, label: String) -> void:
	(rec["features"] as Array).append(Part.new_feature(rec, "bname", {"name": "Name %s" % label, "body": idx, "called": label}))


## a box (mm, world corners); returns the new body index. op new: a body of its own (named); join: into body `into`
static func _box(rec: Dictionary, nm: String, x0: float, y0: float, z0: float, x1: float, y1: float, z1: float, nb: int, op := "new", into := -1, stamp := "") -> int:
	var f := {"x": minf(x0, x1), "y": minf(y0, y1), "z": minf(z0, z1), "w": absf(x1 - x0), "h": absf(y1 - y0), "d": absf(z1 - z0), "name": nm, "op": op}
	if into >= 0:
		f["into"] = into
	var id := Part.prim(rec, "box", f)
	if stamp != "":
		_stamp(Part.feature(rec, id), stamp, {"x0": x0, "y0": y0, "z0": z0, "x1": x1, "y1": y1, "z1": z1})
	if op == "new":
		_name_body(rec, nb, nm.split(" ")[0] if nm.begins_with("Column") or nm.begins_with("Stair") else nm)
		return nb + 1
	return nb


static func _paint(rec: Dictionary, color: String, kind: String) -> int:
	if color == "" or kind == "":
		return 0
	var res := Part.replay(rec)
	var r := PieceLook.parse(color + " " + _kind_noun(kind))
	if bool(r.get("ok", false)) and String(r.get("kind", "")) == kind and not (r.get("spec", {}) as Dictionary).is_empty():
		return PieceLook.apply(rec, res, kind, r["spec"])
	var c: Array = COLORS[color]
	var bs := PieceLook.bodies_of(res, kind)
	for bi in bs:
		(rec["features"] as Array).append(Part.new_feature(rec, "appear", {"name": "Appearance%d" % (Part.count_of(rec, "appear") + 1), "body": int(bi), "preset": "Paint", "color": c.duplicate()}))
	return bs.size()


static func _kind_noun(kind: String) -> String:
	return {"column": "columns", "roof": "roof", "platform": "platform", "stair": "stairs", "wall": "walls", "ground": "ground", "paving": "path", "beam": "beams", "rail": "rails", "door": "doors"}.get(kind, kind)


# ---------------------------------------------------------------- the entry points

static func _refuse(error: String, did := "") -> Dictionary:
	return {"ok": false, "kind": "refuse", "say": "", "error": error, "did": did, "ignored": [], "notes": [], "rec": {}}


## true when HallWords should take this sentence (the UI asks before BuildWords): a check, a trade name, repeat, tube, columns / bays, a roof with a style,
## a wall around, a typo of one of those words, or any hall noun when a part is on screen
## true when the part on screen was made by these words (a feature carries "hw"/"hw_box"): a house's Part is not ours
static func _is_hall_rec(rec: Dictionary) -> bool:
	for f in rec.get("features", []):
		if f is Dictionary and (f.has("hw") or f.has("hw_box")):
			return true
	return false


static func claims(text: String, rec: Dictionary) -> bool:
	var raw := text.strip_edges().to_lower()
	if raw == "":
		return false
	var toks := _clean(raw)
	if toks.is_empty():
		return false
	var first := String(toks[0])
	if first in ["check", "verify", "confirm", "repeat"] or raw.begins_with("make sure"):
		return true
	var tr := TradeWords.find_all(raw)
	if not (tr["items"] as Array).is_empty() or not (tr["unknown"] as Array).is_empty():
		return true
	if _has(toks, ["column", "columns", "bay", "bays", "tube", "xieshan", "compound", "upturned", "repeat"]):
		return true
	if _has(toks, ["roof"]) and _has(toks, ["double", "curved", "chinese", "upturned", "xieshan", "hip", "hipped", "pyramid"]):
		return true
	if _has(toks.slice(0, 4), ["wall", "walls"]) and _has(toks, ["around", "surround", "enclose"]):
		return true   # a sentence that STARTS with the wall ("a wall around the platform"); "pillars around the room ... by the wall" is a house
	if _has(toks, ["sunset", "afternoon", "morning", "noon", "evening"]) and _has(toks, ["light"]):
		return true
	var ty := typo_in(toks)
	if not ty.is_empty() and HALL_ONLY.has(String(ty["did"])):
		return true
	if _is_hall_rec(rec) and _has(toks, ["platform", "terrace", "stair", "stairs", "steps", "roof", "path", "hall", "ground", "wall", "walls", "paint"]):
		return true
	return false


## the sentence done to a COPY of rec (the caller commits it): see the header. ctx: {"points": [[x, y, z] mm]} for "through these points"
static func run_on(rec0: Dictionary, text: String, ctx := {}) -> Dictionary:
	var raw := text.strip_edges()
	if raw == "":
		return _refuse("Nothing to build yet. Say a thing, like: a platform 21 x 14 m, 1.3 m high")
	if not Part.available():
		return _refuse(Part.why_not())
	var low := raw.to_lower()
	# trade names first: they are cut out of the sentence (the reply says the translation)
	var tr := TradeWords.find_all(low)
	var items: Array = tr["items"]
	var s_text := String(tr["rest"]) if (not items.is_empty() or not (tr["unknown"] as Array).is_empty()) else low
	var toks := _clean(s_text)
	var ty := typo_in(toks) if not (toks.size() > 0 and String(toks[0]) in ["check", "verify", "confirm", "test"]) else {}
	if not ty.is_empty():
		return _refuse("Kine doesn't know '%s' here - did you mean %s?" % [ty["word"], ty["did"]], String(ty["did"]))
	var rec := rec0.duplicate(true) if not rec0.is_empty() else Part.make("Part")
	var s := " ".join(PackedStringArray(toks.map(func(x): return String(x))))
	var out := {"ok": false, "kind": "build", "say": "", "error": "", "did": "", "ignored": [], "notes": [], "rec": rec, "translations": items.map(func(i): return String(i["say"])), "unknown_trade": tr["unknown"]}
	var first := String(toks[0]) if not toks.is_empty() else ""
	var r: Dictionary
	if first in ["check", "verify", "confirm", "test"] or s.begins_with("make sure"):
		return _check(rec, s, raw, out)
	elif not items.is_empty() or not (tr["unknown"] as Array).is_empty():
		r = _trade(rec, items, tr["unknown"], s, toks)
	elif first == "repeat" or _has(toks, ["repeat"]):
		r = _repeat(rec, s, toks)
	elif _has(toks, ["tube", "pipe", "rod"]) and (_has(toks, ["through", "points", "point"]) or raw.contains(",")):
		r = _tube(rec, s, low, ctx)
	elif first in ["paint", "colour", "color"] or (first in ["make", "turn"] and not s.contains(" 0") and RegEx.create_from_string("\\d").search(s) == null and _color_of(toks) != ""):
		r = _look(rec, toks)
	elif _has(toks, ["light", "sun"]) or _has(toks, LIGHT_WORDS.keys()) or RegEx.create_from_string("\\d (am|pm)\\b").search(s) != null:
		var h := _light_time(s, toks)
		if h < 0.0:
			return _refuse("Light it when? Say a time, like: light it at 4 pm, or: light it at sunset.")
		out["ok"] = true
		out["kind"] = "light"
		out["time"] = h
		out["say"] = "Light: the sun at %s o'clock." % _g(h)
		return out
	elif PartOrnament.parse(raw)["ok"] and not _has(toks, ["roof"]) or (PartOrnament.parse(raw)["ok"] and _has(toks, ["ridge"])):
		var w := PartOrnament.from_words(raw, rec)
		if not bool(w["ok"]):
			return _refuse(String(w["why"]))
		(rec["features"] as Array).append(Part.new_feature(rec, "ornament", w["fields"]))
		r = {"ok": true, "say": "Added %s." % String(w["said"]), "used": []}
	elif _has(toks, ["roof", "roofs"]):
		r = _roof(rec, s, toks)
	elif _has(toks, ["stair", "stairs", "step", "steps", "staircase", "stairway"]):
		r = _stair(rec, s, toks)
	elif _has(toks, ["column", "columns", "pillar", "pillars", "bay", "bays", "post", "posts"]):
		r = _columns(rec, s, toks)
	elif _has(toks, ["wall", "walls"]) and _has(toks, ["around", "surround", "enclose", "compound"]):
		r = _wall(rec, s, toks)
	elif _has(toks, ["path", "paths"]):
		r = _path(rec, s, toks)
	elif _has(toks, BLOCKS.keys()):
		r = _block(rec, s, toks)
	else:
		var unk := _unknown_words(toks, [])
		return _refuse("Kine does not know how to build that yet%s. Try: a platform 21 x 14 m, 1.3 m high; a hall 18 x 10 m; 6 red columns 0.5 wide; a double roof with upturned corners; a wall around it; a tube 30 mm through 0,0,0 then 0,0,500; repeat it 12 times around; check the pistons fit the bores." % ((" (not understood: " + ", ".join(unk) + ")") if not unk.is_empty() else ""))
	if not bool(r.get("ok", false)):
		return _refuse(String(r.get("error", "not understood")))
	var res := Part.replay(rec)
	var errs: Dictionary = res.get("errors", {})
	if not errs.is_empty():
		return _refuse("That would not build: " + String(errs[errs.keys()[0]]))
	out["ok"] = true
	out["say"] = String(r["say"])
	out["notes"] = r.get("notes", [])
	out["ignored"] = _unknown_words(toks, r.get("used", []))
	out["bodies"] = int(res.get("bodies", 0))
	if not (out["translations"] as Array).is_empty():
		out["say"] = " ".join(PackedStringArray(out["translations"])) + " " + String(out["say"])
	return out


## the sentence on the main node: ONE undo step per building sentence (checks and the sun change no record)
static func run(m: Node, text: String, ctx := {}) -> Dictionary:
	var raw := text.strip_edges()
	var low := raw.to_lower()
	var rec: Dictionary = m.S.part
	var toks := _clean(low)
	# nature words (225) when it is a tree / hedge / grass sentence
	if NatureWords.looks_natural(low) and not (_has(toks, ["path", "paths"]) and not rec.is_empty() and not _has(toks, ["tree", "trees", "hedge", "hedges", "shrub", "shrubs", "bush", "bushes", "grass", "flower", "flowers", "rock", "rocks"])) and not _has(toks, ["check", "repeat"]):
		var r2 := NatureWords.parse(raw, m.S.building)
		if not bool(r2["ok"]):
			return {"ok": false, "kind": "refuse", "error": String(r2["error"]), "say": "", "ignored": r2["ignored"]}
		m._step_hint = "Words: " + String(r2["say"])
		m._push_undo()
		if m.S.building.is_empty():
			m.S.building = Building.make("Untitled")
		NatureWords.apply(m.S.building, raw)
		if m.bld != null:
			m.bld.sync()
		return {"ok": true, "kind": "nature", "say": "Planted: %s." % String(r2["say"]), "ignored": r2["ignored"], "count": (r2["items"] as Array).size()}
	var r := run_on(rec, raw, ctx)
	if not bool(r["ok"]):
		return r
	if String(r["kind"]) == "check":
		return r
	if String(r["kind"]) == "light":
		TempleLight.serve(m, {"on": true, "time": float(r["time"])})
		return r
	m._step_hint = "Words: " + String(r["say"]).left(70)
	m._push_undo()
	m.S.part = r["rec"]
	if m.has_method("_fit_top"):
		m._fit_top.call_deferred()
	return r


# ---------------------------------------------------------------- blocks, stairs, columns, roofs, walls

static func _block(rec: Dictionary, s: String, toks: Array) -> Dictionary:
	var kind := "platform"
	var word := "platform"
	for w in toks:
		if BLOCKS.has(String(w)):
			kind = String(BLOCKS[w])
			word = String(w)
			break
	var notes := []
	var dm := _dims(s)
	var defw: float = {"ground": 60000.0, "platform": 21000.0, "hall": 18000.0}[kind]
	var defd: float = {"ground": 60000.0, "platform": 14000.0, "hall": 10000.0}[kind]
	var w := defw
	var d := defd
	var h := _attr(s, ["high", "tall", "height", "thick", "thickness"])
	if not dm.is_empty():
		w = float(dm[0])
		d = float(dm[1])
		if float(dm[2]) > 0.0 and h < 0.0:
			h = float(dm[2])
	else:
		notes.append("no size given: %s x %s" % [_m(w), _m(d)])
	if h < 0.0:
		h = {"ground": 100.0, "platform": 1000.0, "hall": 5000.0}[kind]
	var cx := 0.0
	var cz := 0.0
	var y0 := 0.0
	var host := _last(rec, ["platform"]) if kind == "hall" else {}
	if kind == "hall" and not host.is_empty() and not _has(toks, ["ground"]):
		y0 = float(host["y1"])
		cx = (float(host["x0"]) + float(host["x1"])) * 0.5
		cz = (float(host["z0"]) + float(host["z1"])) * 0.5
	elif kind == "ground":
		y0 = -h
	var mx := RegEx.create_from_string("at x (-?\\d+(?:\\.\\d+)?)(?: z (-?\\d+(?:\\.\\d+)?))?").search(s)
	if mx != null:
		cx = float(mx.get_string(1)) * 1000.0
		if mx.get_string(2) != "":
			cz = float(mx.get_string(2)) * 1000.0
	var nb := _nbodies(rec)
	var nm := word.capitalize() if kind != "hall" else "Hall wall"
	if kind == "ground":
		nm = "Ground"
	if kind == "platform":
		nm = "Platform"
	var bb := {"x0": cx - w * 0.5, "y0": y0, "z0": cz - d * 0.5, "x1": cx + w * 0.5, "y1": y0 + h, "z1": cz + d * 0.5}
	var say := ""
	if kind == "hall":
		var t := _attr(s, ["thick", "thickness"])
		var th := minf(maxf(t, 100.0) if t > 0.0 else 400.0, minf(w, d) * 0.4)
		# four walls, ONE body (a hollow hall); the door is a cut through the front wall
		var first := nb
		nb = _box(rec, nm, bb["x0"], y0, bb["z0"], bb["x1"], y0 + h, bb["z0"] + th, nb, "new", -1, "hall")
		var f0 := Part.feature(rec, (rec["features"][(rec["features"] as Array).size() - 2] as Dictionary)["id"])
		_stamp(f0, "hall", bb)
		_box(rec, nm, bb["x0"], y0, bb["z0"], bb["x0"] + th, y0 + h, bb["z1"], nb, "join", first)   # sides before the back: a join must touch what it joins
		_box(rec, nm, bb["x1"] - th, y0, bb["z0"], bb["x1"], y0 + h, bb["z1"], nb, "join", first)
		_box(rec, nm, bb["x0"], y0, bb["z1"] - th, bb["x1"], y0 + h, bb["z1"], nb, "join", first)
		say = "Built a hall %s x %s, %s tall, walls %s thick" % [_m(w), _m(d), _m(h), _m(th)]
		if _has(toks, ["door", "doorway"]):
			var dw := _attr(s, ["door", "doorway"])
			var m2 := RegEx.create_from_string("door(?:way)? " + NUM + UNIT + "|" + NUM + UNIT + " (?:wide )?door").search(s)
			dw = 2400.0
			if m2 != null:
				var num := m2.get_string(1) if m2.get_string(1) != "" else m2.get_string(3)
				var un := m2.get_string(2) if m2.get_string(1) != "" else m2.get_string(4)
				dw = _mm(num, un)
			dw = minf(dw, w - 2.0 * th)
			_box(rec, "Door", cx - dw * 0.5, y0, bb["z1"] - th - 1.0, cx + dw * 0.5, y0 + minf(3200.0, h * 0.7), bb["z1"] + 1.0, nb, "cut", first)
			say += ", a door %s wide in the front" % _m(dw)
	else:
		_box(rec, nm, bb["x0"], y0, bb["z0"], bb["x1"], y0 + h, bb["z1"], nb, "new", -1, kind)
		say = "Built a %s %s x %s, %s %s" % [word, _m(w), _m(d), _m(h), "thick" if kind == "ground" else "high"]
	var col := _color_of(toks)
	if col != "":
		_paint(rec, col, {"hall": "wall", "platform": "platform", "ground": "ground"}[kind])
	return {"ok": true, "say": say + ".", "notes": notes, "used": []}


static func _stair(rec: Dictionary, s: String, toks: Array) -> Dictionary:
	var host := _last(rec, ["platform"])
	if host.is_empty():
		host = _last(rec, [])
	if host.is_empty():
		return {"ok": false, "error": "A stair goes up to something. Build a platform first: a platform 21 x 14 m, 1.3 m high"}
	var n := _count(s, ["step", "steps", "stair", "stairs", "stairway", "staircase"], 9)
	n = clampi(n, 2, 40)
	var side := _side(toks)
	var h := float(host["y1"]) - float(host["y0"])
	var top := float(host["y1"])
	var run := _attr(s, ["run", "tread", "deep"])
	if run < 0.0:
		run = 300.0
	var span := (float(host["x1"]) - float(host["x0"])) if side in ["front", "back"] else (float(host["z1"]) - float(host["z0"]))
	var wd := _attr(s, ["wide", "width"])
	if wd < 0.0:
		wd = minf(3000.0, span / 3.0)
	var cx := (float(host["x0"]) + float(host["x1"])) * 0.5
	var cz := (float(host["z0"]) + float(host["z1"])) * 0.5
	var nb := _nbodies(rec)
	var first := nb
	for k in range(1, n + 1):
		var hk := top * float(n - k + 1) / float(n)
		var a := float(k - 1) * run
		var b := float(k) * run
		var x0 := 0.0
		var x1 := 0.0
		var z0 := 0.0
		var z1 := 0.0
		match side:
			"front":
				x0 = cx - wd * 0.5
				x1 = cx + wd * 0.5
				z0 = float(host["z1"]) + a
				z1 = float(host["z1"]) + b
			"back":
				x0 = cx - wd * 0.5
				x1 = cx + wd * 0.5
				z0 = float(host["z0"]) - b
				z1 = float(host["z0"]) - a
			"right":
				z0 = cz - wd * 0.5
				z1 = cz + wd * 0.5
				x0 = float(host["x1"]) + a
				x1 = float(host["x1"]) + b
			_:
				z0 = cz - wd * 0.5
				z1 = cz + wd * 0.5
				x0 = float(host["x0"]) - b
				x1 = float(host["x0"]) - a
		if k == 1:
			nb = _box(rec, "Stair", x0, 0.0, z0, x1, hk, z1, nb, "new")
		else:
			_box(rec, "Stair", x0, 0.0, z0, x1, hk, z1, nb, "join", first)
	var col := _color_of(toks)
	if col != "":
		_paint(rec, col, "stair")
	return {"ok": true, "say": "Built a stair of %d steps up the %s of the %s, %s wide, each step %s deep and %s high." % [n, side, "platform" if String(host["kind"]) == "platform" else String(host["kind"]), _m(wd), _m(run), _m(top / float(n))], "used": []}


static func _columns(rec: Dictionary, s: String, toks: Array) -> Dictionary:
	var host := _host(rec, toks)
	if host.is_empty():
		host = {"kind": "platform", "x0": -10500.0, "y0": 0.0, "z0": -7000.0, "x1": 10500.0, "y1": 1000.0, "z1": 7000.0}
	var bays := _count(s, ["bay", "bays"], 0)
	var n := _count(s, ["column", "columns", "pillar", "pillars", "post", "posts"], 0)
	var dia := _attr(s, ["wide", "diameter", "across", "thick"])
	if dia < 0.0:
		dia = 500.0
	var r := dia * 0.5
	var on_hall := String(host["kind"]) == "hall"
	var y0 := float(host["y0"]) if on_hall else float(host["y1"])
	var hgt := _attr(s, ["tall", "high", "height"])
	if hgt < 0.0:
		hgt = (float(host["y1"]) - float(host["y0"])) if on_hall else 4000.0
	var side := _side(toks)
	var around := _has(toks, ["around", "round", "surround"])
	var off := r + 300.0 if on_hall else maxf(r + 600.0, 1000.0)
	var bay_w := -1.0
	var bm := RegEx.create_from_string("bays? (?:of )?" + NUM + UNIT + "|bays? " + NUM + UNIT + " (?:each|apart)|" + NUM + UNIT + " bays?").search(s)
	var mb := RegEx.create_from_string("bays? (?:of |at )?" + NUM + UNIT).search(s)
	if mb != null:
		bay_w = _mm(mb.get_string(1), mb.get_string(2))
	if bays > 0:
		n = bays + 1
	if n <= 0:
		n = 1 if (_has(toks, ["column", "pillar", "post"]) and not _has(toks, ["columns", "pillars", "posts"])) else 6
	n = clampi(n, 1, 64)
	var nb := _nbodies(rec)
	var say := ""
	if around:
		var x0 := float(host["x0"]) - off if on_hall else float(host["x0"]) + off
		var x1 := float(host["x1"]) + off if on_hall else float(host["x1"]) - off
		var z0 := float(host["z0"]) - off if on_hall else float(host["z0"]) + off
		var z1 := float(host["z1"]) + off if on_hall else float(host["z1"]) - off
		var id := Part.prim(rec, "cylinder", {"x": x0, "y": y0, "z": z0, "r": r, "len": hgt, "axis": "y", "name": "Column", "op": "new"})
		_name_body(rec, nb, "Column")
		if n > 1:
			var pts := [[x0, y0, z0], [x1, y0, z0], [x1, y0, z1], [x0, y0, z1]]
			(rec["features"] as Array).append(Part.new_feature(rec, "pattern", {"kind": "route", "body": nb, "op": "new", "pts": pts, "closed": true, "count": maxi(n, 2), "fit": true, "follow": false, "hold": true, "name": "Columns round the %s" % String(host["kind"])}))
		say = "Built %d columns %s wide, %s tall, spaced round the %s." % [n, _m(dia), _m(hgt), String(host["kind"])]
	else:
		var along_x := side in ["front", "back"]
		var lo := (float(host["x0"]) if along_x else float(host["z0"])) + (r if on_hall else maxf(r + 600.0, 1000.0))
		var hi := (float(host["x1"]) if along_x else float(host["z1"])) - (r if on_hall else maxf(r + 600.0, 1000.0))
		var sp := bay_w if bay_w > 0.0 else ((hi - lo) / float(n - 1) if n > 1 else 0.0)
		var start := lo if bay_w <= 0.0 else (lo + hi) * 0.5 - sp * float(n - 1) * 0.5
		var fixed := 0.0
		match side:
			"front":
				fixed = float(host["z1"]) + off if on_hall else float(host["z1"]) - off
			"back":
				fixed = float(host["z0"]) - off if on_hall else float(host["z0"]) + off
			"right":
				fixed = float(host["x1"]) + off if on_hall else float(host["x1"]) - off
			_:
				fixed = float(host["x0"]) - off if on_hall else float(host["x0"]) + off
		var px := start if along_x else fixed
		var pz := fixed if along_x else start
		Part.prim(rec, "cylinder", {"x": px, "y": y0, "z": pz, "r": r, "len": hgt, "axis": "y", "name": "Column", "op": "new"})
		_name_body(rec, nb, "Column")
		if n > 1:
			(rec["features"] as Array).append(Part.new_feature(rec, "pattern", {"kind": "linear", "body": nb, "count": n, "mm": sp, "dir": "x" if along_x else "z", "op": "new", "name": "Column row"}))
		say = "Built %d columns %s wide, %s tall, along the %s%s." % [n, _m(dia), _m(hgt), side, (", " + str(n - 1) + " bays of " + _m(sp)) if n > 1 else ""]
	var col := _color_of(toks)
	if col != "":
		_paint(rec, col, "column")
		say += " Painted %s." % col
	return {"ok": true, "say": say, "used": []}


static func _roof(rec: Dictionary, s: String, toks: Array) -> Dictionary:
	var host := _host(rec, toks)
	var w := 8000.0
	var d := 6000.0
	var y := 0.0
	var cx := 0.0
	var cz := 0.0
	if not host.is_empty():
		w = float(host["x1"]) - float(host["x0"])
		d = float(host["z1"]) - float(host["z0"])
		y = float(host["y1"])
		cx = (float(host["x0"]) + float(host["x1"])) * 0.5
		cz = (float(host["z0"]) + float(host["z1"])) * 0.5
	var dm := _dims(s)
	if not dm.is_empty():
		w = float(dm[0])
		d = float(dm[1])
	var typ := ""
	for t in toks:
		if TYPES.has(String(t)):
			typ = String(TYPES[t])
	var up := _has(toks, ["upturned", "curved", "chinese", "xieshan"])
	var dbl := _has(toks, ["double"])
	if typ == "":
		typ = "hip" if up else "gable"
	var ov := _attr(s, ["overhang"])
	var hh := _attr(s, ["high", "tall", "height"])
	var m0 := minf(w, d)
	var nb0 := _nbodies(rec)
	var say := ""
	var thick := clampf(m0 * 0.014, 40.0, 200.0)
	if dbl:
		var lo := {"type": "hip", "w": w, "d": d, "overhang": ov if ov > 0.0 else maxf(1500.0, d * 0.22), "height": hh if hh > 0.0 else d * 0.55, "thick": thick, "sag": d * 0.08,
			"lift": d * 0.116 if up or true else 0.0, "lift_len": d * 0.375, "hole": [w * 0.785, d * 0.625], "at": [cx, y, cz], "name": "Lower roof", "detail": 6}
		var lof := Part.new_feature(rec, "roof", PartRoof.fields_of(lo))
		_stamp(lof, "roof", {"x0": cx - w * 0.5, "y0": y, "z0": cz - d * 0.5, "x1": cx + w * 0.5, "y1": y + float(lo["height"]), "z1": cz + d * 0.5})
		(rec["features"] as Array).append(lof)
		var uh := d * 0.3
		var up_y := y + float(lo["height"]) * 0.57   # the open top clips the hip at about 0.57 of its height: the upper roof sits on that edge
		var uf := {"type": "xieshan" if typ != "gable" or up else typ, "w": w * 0.8, "d": d * 0.62, "overhang": maxf(1500.0, d * 0.24), "height": uh, "thick": thick, "sag": d * 0.07, "lift": d * 0.1,
			"lift_len": d * 0.3, "gable_in": d * 0.08, "at": [cx, up_y, cz], "name": "Upper roof", "detail": 6}
		var upf := Part.new_feature(rec, "roof", PartRoof.fields_of(uf))
		_stamp(upf, "roof", {"x0": cx - w * 0.4, "y0": up_y, "z0": cz - d * 0.31, "x1": cx + w * 0.4, "y1": up_y + uh, "z1": cz + d * 0.31})
		(rec["features"] as Array).append(upf)
		say = "Built a double roof (lower hip with an open top, upper xieshan) over %s x %s, corners lifted %s." % [_m(w), _m(d), _m(float(lo["lift"]))]
	else:
		var f := {"type": typ, "w": w, "d": d, "overhang": ov if ov > 0.0 else maxf(600.0, m0 * 0.07), "thick": thick, "at": [cx, y, cz], "name": "Roof", "detail": 6}
		if hh > 0.0:
			f["height"] = hh
		if up:
			f["sag"] = m0 * 0.07
			f["lift"] = m0 * 0.1
			f["lift_len"] = m0 * 0.35
		var rf := Part.new_feature(rec, "roof", PartRoof.fields_of(f))
		_stamp(rf, "roof", {"x0": cx - w * 0.5, "y0": y, "z0": cz - d * 0.5, "x1": cx + w * 0.5, "y1": y + (hh if hh > 0.0 else m0 * 0.3), "z1": cz + d * 0.5})
		(rec["features"] as Array).append(rf)
		say = "Built a %s roof over %s x %s%s." % [typ, _m(w), _m(d), ", corners turned up" if up else ""]
	var col := _color_of(toks)
	if col != "":
		_paint(rec, col, "roof")
		say += " Painted %s." % col
	return {"ok": true, "say": say, "used": []}


static func _extent(rec: Dictionary) -> AABB:
	var res := Part.replay(rec)
	if int(res.get("bodies", 0)) > 0 and res.get("aabb") is AABB:
		var bb: AABB = res["aabb"]
		return AABB(bb.position / 0.001, bb.size / 0.001)
	return AABB()


static func _wall(rec: Dictionary, s: String, toks: Array) -> Dictionary:
	var host := {}
	for w in toks:
		if BLOCKS.has(String(w)):
			host = _last(rec, [String(BLOCKS[w])])
			if not host.is_empty():
				break
	var ex := _extent(rec)
	if host.is_empty() and ex.size == Vector3.ZERO:
		return {"ok": false, "error": "A wall around what? Build something first, like: a platform 21 x 14 m"}
	var x0 := float(host["x0"]) if not host.is_empty() else ex.position.x
	var x1 := float(host["x1"]) if not host.is_empty() else ex.end.x
	var z0 := float(host["z0"]) if not host.is_empty() else ex.position.z
	var z1 := float(host["z1"]) if not host.is_empty() else ex.end.z
	var gap := _attr(s, ["out", "away", "clear", "gap", "from"])
	var mg := RegEx.create_from_string(NUM + UNIT + " (?:out|away|from|clear|gap)").search(s)
	gap = _mm(mg.get_string(1), mg.get_string(2)) if mg != null else 4000.0
	var h := _attr(s, ["high", "tall", "height"])
	if h < 0.0:
		h = 2000.0
	var t := _attr(s, ["thick", "thickness"])
	if t < 0.0:
		t = SKIP_WALL_THICK
	x0 -= gap
	x1 += gap
	z0 -= gap
	z1 += gap
	var nb := _nbodies(rec)
	var first := nb
	nb = _box(rec, "Compound wall", x0, 0.0, z0, x1, h, z0 + t, nb, "new", -1)
	_box(rec, "Compound wall", x0, 0.0, z0, x0 + t, h, z1, nb, "join", first)
	_box(rec, "Compound wall", x1 - t, 0.0, z0, x1, h, z1, nb, "join", first)
	_box(rec, "Compound wall", x0, 0.0, z1 - t, x1, h, z1, nb, "join", first)
	var col := _color_of(toks)
	if col != "":
		_paint(rec, col, "wall")
	return {"ok": true, "say": "Built a wall around it: %s x %s, %s high, %s thick, %s out from the %s." % [_m(x1 - x0), _m(z1 - z0), _m(h), _m(t), _m(gap), "hall" if not host.is_empty() else "model"], "used": []}


static func _path(rec: Dictionary, s: String, toks: Array) -> Dictionary:
	var ex := _extent(rec)
	var wd := _attr(s, ["wide", "width"])
	if wd < 0.0:
		wd = 3000.0
	var ln := _attr(s, ["long", "length"])
	if ln < 0.0:
		ln = 20000.0
	var cx := ex.position.x + ex.size.x * 0.5 if ex.size != Vector3.ZERO else 0.0
	var zs := ex.end.z if ex.size != Vector3.ZERO else 0.0
	var zb := -INF   # the front of what stands (the ground slab does not count), and of a stair
	for bk in blocks(rec):
		if String(bk["kind"]) != "ground":
			zb = maxf(zb, float(bk["z1"]))
	for f in rec.get("features", []):
		if String((f as Dictionary).get("name", "")) == "Stair" and String(f.get("t", "")) == "prim":
			zb = maxf(zb, float(f["z"]) + float(f["d"]))
	if zb > -INF:
		zs = zb
	var nb := _nbodies(rec)
	_box(rec, "Path", cx - wd * 0.5, 0.0, zs, cx + wd * 0.5, 60.0, zs + ln, nb, "new", -1)
	var col := _color_of(toks)
	if col != "":
		_paint(rec, col, "paving")
	return {"ok": true, "say": "Built a path %s wide and %s long straight out from the front (z %s to %s)." % [_m(wd), _m(ln), _m(zs), _m(zs + ln)], "used": []}


# ---------------------------------------------------------------- looks, light, repeat, tube

static func _look(rec: Dictionary, toks: Array) -> Dictionary:
	var col := _color_of(toks)
	var kind := ""
	for t in toks:
		if PieceLook.NOUNS.has(String(t)):
			kind = String(PieceLook.NOUNS[t])
			break
	if col == "" or kind == "":
		return {"ok": false, "error": "Paint what, in what colour? Like: make the columns red, or: paint the roof gold."}
	var n := _paint(rec, col, kind)
	if n == 0:
		return {"ok": false, "error": "There are no %s in this part to paint." % _kind_noun(kind)}
	return {"ok": true, "say": "Painted %d %s %s." % [n, _kind_noun(kind), col], "used": []}


static func _light_time(s: String, toks: Array) -> float:
	for t in toks:
		if LIGHT_WORDS.has(String(t)):
			return float(LIGHT_WORDS[t])
	var m := RegEx.create_from_string("(\\d+)(?: : ?(\\d+))? ?(am|pm)?").search(s)
	var re := RegEx.create_from_string("(\\d+(?:\\.\\d+)?) (am|pm)\\b").search(s)
	if re != null:
		var h := fmod(float(re.get_string(1)), 12.0)
		return h + (12.0 if re.get_string(2) == "pm" else 0.0)
	var m24 := RegEx.create_from_string("\\bat (\\d+(?:\\.\\d+)?)\\b").search(s)
	if m24 != null and float(m24.get_string(1)) <= 24.0:
		return float(m24.get_string(1))
	return -1.0


static func _repeat(rec: Dictionary, s: String, toks: Array) -> Dictionary:
	var nb := _nbodies(rec)
	if nb == 0:
		return {"ok": false, "error": "Nothing to repeat yet. Build a piece first."}
	var target := nb - 1
	var res := Part.replay(rec)
	var names: Array = res.get("body_names", [])
	for w in toks:
		var x := String(w).trim_suffix("s")
		if x in ["it", "repeat", "the", "times", "time", "around", "along", "x", "y", "z", "a", "grid", "row"] or _is_num(x) or x.length() < 3:
			continue
		for i in range(names.size() - 1, -1, -1):
			if String(names[i]).to_lower().contains(x):
				target = i
				break
	var mc := RegEx.create_from_string("(\\d+) (?:times|copies|more)|(?:times|copies of) (\\d+)").search(s)
	var n := int(mc.get_string(1)) if mc != null and mc.get_string(1) != "" else (int(mc.get_string(2)) if mc != null else 0)
	var grid := RegEx.create_from_string("(\\d+) by (\\d+)|(\\d+) x (\\d+) grid|grid (\\d+) x (\\d+)").search(s)
	var f := {}
	var say := ""
	var sp := _attr(s, ["apart", "spacing", "gap", "each"], "mm")
	var msp := RegEx.create_from_string(NUM + UNIT + " apart|apart " + NUM + UNIT).search(s)
	if msp != null:
		sp = _mm(msp.get_string(1) if msp.get_string(1) != "" else msp.get_string(3), msp.get_string(2) if msp.get_string(1) != "" else msp.get_string(4), "mm")
	var ax := "y"
	var along := RegEx.create_from_string("along ([xyz])").search(s)
	if along != null:
		ax = along.get_string(1)
	if n <= 0:
		return {"ok": false, "error": "Repeat it how many times? Like: repeat it 12 times around"}
	n = clampi(n, 2, 64)
	if _has(toks, ["around"]) or (along == null and sp < 0.0):
		var axr := RegEx.create_from_string("(?:the |about )([xyz]) axis").search(s)
		var a2 := axr.get_string(1) if axr != null else "y"
		f = {"kind": "circular", "body": target, "count": n, "axis": a2, "deg": 360.0, "op": "new", "name": "Repeat around"}
		say = "Repeated %s %d times around the %s axis through the origin (%d in all, 360 degrees)." % [String(names[target]) if target < names.size() else "it", n, a2, n]
	else:
		if sp < 0.0:
			sp = 600.0
		f = {"kind": "linear", "body": target, "count": n, "mm": sp, "dir": ax, "op": "new", "name": "Repeat along"}
		say = "Repeated %s %d times along %s, %s apart (%d in all)." % [String(names[target]) if target < names.size() else "it", n, ax, _m(sp), n]
	(rec["features"] as Array).append(Part.new_feature(rec, "pattern", f))
	return {"ok": true, "say": say, "used": []}


static func _tube(rec: Dictionary, s: String, low: String, ctx: Dictionary) -> Dictionary:
	var pts: Array = []
	var re := RegEx.create_from_string("(-?\\d+(?:\\.\\d+)?)\\s*,\\s*(-?\\d+(?:\\.\\d+)?)\\s*,\\s*(-?\\d+(?:\\.\\d+)?)")
	for m in re.search_all(low):
		pts.append([float(m.get_string(1)), float(m.get_string(2)), float(m.get_string(3))])
	if pts.is_empty() and s.contains("these points"):
		pts = (ctx.get("points", []) as Array).duplicate(true)
		if pts.size() < 2:
			return {"ok": false, "error": "Which points? Pick at least two, or type them: a tube 30 mm through 0,0,0 then 0,0,500 then 300,0,500"}
	if pts.size() < 2:
		return {"ok": false, "error": "A tube needs at least two points, like: a tube 30 mm through 0,0,0 then 0,0,500"}
	var md := RegEx.create_from_string("(?:tube|pipe|rod) " + NUM + UNIT + "|" + NUM + UNIT + " (?:tube|pipe|rod|diameter|wide)").search(s)
	var dia := 30.0
	if md != null:
		dia = _mm(md.get_string(1) if md.get_string(1) != "" else md.get_string(3), md.get_string(2) if md.get_string(1) != "" else md.get_string(4), "mm")
	var wall := _attr(s, ["wall"], "mm")
	if _has(s.split(" "), ["solid", "rod"]):
		wall = 0.0
	elif wall < 0.0:
		wall = maxf(1.5, dia * 0.1)
	var bend := _attr(s, ["bend", "radius"], "mm")
	var f := {"pts": pts, "r": dia * 0.5, "wall": wall, "bend": maxf(bend, 0.0), "op": "new", "name": "Tube"}
	var nb := _nbodies(rec)
	(rec["features"] as Array).append(Part.new_feature(rec, "pipe3d", f))
	_name_body(rec, nb, "Tube")
	return {"ok": true, "say": "Built a tube %s mm across (outside), wall %s mm, through %d points." % [_g(dia), _g(wall), pts.size()], "used": []}


# ---------------------------------------------------------------- trade names

static func _trade(rec: Dictionary, items: Array, unknown: Array, s: String, toks: Array) -> Dictionary:
	if not unknown.is_empty() and items.is_empty():
		return {"ok": false, "error": "Kine does not know '%s' (not guessed). It knows lumber like 2x4, 4x8 sheet, 3/4 ply, M6 x 16, 1/4-20, keys SC1 SC4 KW1 and caibro, ripa, sarrafo, viga, pontalete." % "', '".join(PackedStringArray(unknown))}
	var ln := _attr(s, ["long", "length"])
	var lm := RegEx.create_from_string(NUM + UNIT + " (?:long|length)|(?:long|length) " + NUM + UNIT).search(s)
	var nb := _nbodies(rec)
	var ex := _extent(rec)
	var x := (ex.end.x + 300.0) if ex.size != Vector3.ZERO else 0.0
	var made: Array = []
	var cnt := maxi(_count(s, ["pieces", "piece", "studs", "stud", "planks", "boards", "bolts", "sheets"], 1), 1)
	for it in items:
		var mm: Dictionary = it["mm"]
		match String(it["kind"]):
			"lumber", "br":
				var L := ln if ln > 0.0 else 2400.0
				if ln < 0.0 and lm == null:
					L = 2400.0
				for k in cnt:
					nb = _box(rec, String(it["term"]), x, 0.0, 0.0, x + float(mm["t"]), L, float(mm["w"]), nb, "new")
					x += float(mm["t"]) + 100.0
				made.append("%d x %s, %s long" % [cnt, it["term"], _m(L)])
			"sheet":
				var th := 18.3
				for o in items:
					if String(o["kind"]) == "ply":
						th = float((o["mm"] as Dictionary)["t"])
				nb = _box(rec, "Sheet 4x8", x, 0.0, 0.0, x + float(mm["w"]), th, float(mm["l"]), nb, "new")
				made.append("a 4x8 sheet %s mm thick" % _g(th))
			"ply":
				if not items.any(func(o): return String(o["kind"]) == "sheet"):
					nb = _box(rec, "Plywood", x, 0.0, 0.0, 1219.2, float(mm["t"]), 2438.4, nb, "new")
					made.append("a 1219.2 x 2438.4 mm sheet of ply %s mm thick (the 4x8 size, said by default)" % _g(float(mm["t"])))
			"bolt":
				var d := float(mm["d"])
				var Lb := (ln if ln > 0.0 else float(mm["len"]))
				var nm := "Bolt %s" % String(it["term"]).replace(" ", "")
				Part.prim(rec, "cylinder", {"x": x + 20.0, "y": 0.0, "z": 20.0, "r": d * 0.5, "len": Lb, "axis": "y", "name": nm, "op": "new"})
				_name_body(rec, nb, nm)
				Part.prim(rec, "cylinder", {"x": x + 20.0, "y": Lb, "z": 20.0, "r": float(mm["head_af"]) * 0.5, "len": float(mm["head_k"]), "axis": "y", "name": nm + " head", "op": "join", "into": nb})
				nb += 1
				x += float(mm["head_af"]) + 20.0
				made.append("%s with a round head drawn at its width across flats" % nm)
			"key":
				made.append("%s named only" % it["term"])
	var say := ("Built " + ", ".join(PackedStringArray(made)) + ".") if not made.is_empty() else ""
	if not unknown.is_empty():
		say += " Left out (not known, not guessed): %s." % ", ".join(PackedStringArray(unknown))
	return {"ok": true, "say": say, "used": []}


# ---------------------------------------------------------------- CHECK sentences (220 / 221)

static func _sing(w: String) -> String:
	return w.trim_suffix("es") if w.ends_with("ches") or w.ends_with("shes") else (w.trim_suffix("s") if w.ends_with("s") and not w.ends_with("ss") else w)


static func _check(rec: Dictionary, s: String, raw: String, out: Dictionary) -> Dictionary:
	if rec0_empty(rec):
		return _refuse("There is no part to check yet.")
	var toks := s.split(" ", false)
	var body: Array = []
	for t in toks:
		if not (String(t) in ["check", "verify", "confirm", "test", "that", "make", "sure", "if", "whether", "the"]):
			body.append(String(t))
	var line := " ".join(PackedStringArray(body))
	out["kind"] = "check"
	out["ok"] = true
	# "the pistons fit the bores": the ISO 286 fits (221)
	var mf := RegEx.create_from_string("^(?:(?:a|an|all) )?([a-z0-9 ]+?) (?:fits?|fit in|sits? in|goes? in) (?:in )?(?:(?:a|an|the|all) )?([a-z0-9 ]+)$").search(line)
	if mf != null or line in ["fits", "the fits", "fit"]:
		var shaft := _sing(mf.get_string(1).strip_edges()) if mf != null else ""
		var hole := _sing(mf.get_string(2).strip_edges()) if mf != null else ""
		var rep := PartWarn.report(rec, {"level": "engineering"})
		if not bool(rep.get("ok", true)):
			return _refuse(String(rep.get("error", "the check failed")))
		var says := []
		for ft in rep["fits"]:
			var a := String(ft["shaft"]).to_lower()
			var b := String(ft["hole"]).to_lower()
			if (shaft == "" or a.contains(shaft)) and (hole == "" or b.contains(hole)):
				says.append(String(ft["text"]))
		out["pass"] = not says.is_empty() and not says.any(func(t): return String(t).contains("not a standard"))
		out["say"] = " ".join(PackedStringArray(says)) if not says.is_empty() else "No round %s sits in a round %s in this part, so there is no fit to judge." % [shaft if shaft != "" else "shaft", hole if hole != "" else "hole"]
		out["fits"] = rep["fits"]
		return out
	# the part's warnings
	if line in ["part", "it", "the part", "warnings", "everything", "all", "model"] or line == "":
		var lvl := "print" if _has(toks, ["print", "printing", "printable"]) else ("engineering" if _has(toks, ["engineering"]) else "look")   # Print / Engineering tessellate every body: minutes on a hall
		var rp := PartWarn.report(rec, {"level": lvl})
		out["pass"] = (rp["warnings"] as Array).is_empty()
		out["say"] = ("Nothing to warn about at %s level." % lvl.capitalize()) if (rp["warnings"] as Array).is_empty() else "\n".join(PackedStringArray(rp["lines"]))
		return out
	# a part assertion (220): the line as it is, then with the plural names made singular
	var tries := [line, " ".join(PackedStringArray(body.map(func(w): return w if String(w) in ["touches", "overlaps", "bodies", "ends", "reaches", "fins", "ribs", "ridges"] else _sing(String(w)))))]
	var best: Dictionary = {}
	for ln2 in tries:
		var r := PartAssert.run(rec, [String(ln2)])
		if int(r.get("unread", 0)) == 0:
			best = r
			break
		if best.is_empty():
			best = r
	if int(best.get("unread", 0)) > 0:
		out["ok"] = false
		out["error"] = "Kine could not read that check. " + "\n".join(PackedStringArray(PartAssert.GRAMMAR))
		out["kind"] = "refuse"
		return out
	out["pass"] = bool(best["pass"])
	out["say"] = "\n".join(PackedStringArray((best["results"] as Array).map(func(x): return String(x["say"]))))
	return out


static func rec0_empty(rec: Dictionary) -> bool:
	return rec.is_empty() or (rec.get("features", []) as Array).is_empty()
