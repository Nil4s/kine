class_name BuildWords
extends RefCounted
## build_words.gd - BUILD from WORDS (docs/BUILD_PLAN.md phase 1e): a sentence -> a PLAN -> the building record. No network, no model:
## a lexicon and a few patterns, in the style of text_blocking.gd (a phrase -> cards, unknown words listed back, not guessed) and
## mesh_words.gd (numbers + units, every edit ONE undo step and the reply says what was done).
##   "a 2-floor house 8 x 6 m with a door and 4 windows"     sizes ("8 x 6", "8 by 6 m", "4 metres wide", "6 long"), floors
##        ("2-floor", "two storeys", "bungalow"), floor height ("3 m floors"), doors / windows with a count and walls ("a door on the
##        back", "2 windows on each side", "windows on the left and right"), the roof ("flat roof", "no roof", "0.6 m overhang"), a
##        "garage" (a second room beside the house, with its wide door)
##   edits on a building that exists: "move the door to the left", "make the second floor taller", "add a window on the back",
##        "remove the roof", "add a garage", "add a floor", "make the roof flat", "remove the door", "make the door wider"
## parse(text, building) -> {"ok", "kind": "plan" | "edit", "plan" | "edit", "notes": [], "ignored": [], "defaults": {}, "error", "did"}.
## A plan is plain data (below); make_building(plan) is the only thing that turns it into a record, so the cards the user edits
## and the house that is built can never disagree. Nothing here touches the scene: the UI (build_ui.gd) takes the undo step.
## The words that are not understood are LISTED ("ignored"), never guessed; a word that looks like a typo of a known one refuses:
## "Kine doesn't know 'hosue' in a building sentence. Did you mean: house?" Sizes snap to the 0.5 m grid and say so (8.3 became 8.5).
## PLAN: {"w", "d" (outer, m), "floors", "floor_h", "door_n", "door_walls" ([] = default), "door_at" ("centre" | "left" | "right"),
##   "door_w", "win_n", "win_walls" ([] = spread), "win_each" (n per wall), "roof" ("gable" | "flat" | "shed" | "none"), "overhang",
##   "garage" ("" | "left" | "right"), "garage_w"}. "left" / "right" are seen from OUTSIDE, facing the wall.

const GRID := 0.5
const MIN_SIDE := 2.0
const MAX_SIDE := 40.0
const MAX_FLOORS := 6
const DEF_W := 6.0
const DEF_D := 4.0
const DEF_FLOOR_H := 2.8
const DEF_OVERHANG := 0.45
const DEF_DOOR_W := 0.9
const GARAGE_W := 3.5
const GARAGE_DOOR_W := 2.4
const EDGE := 0.2   # m: a garage overlaps the house by the wall thickness, so the two share one wall
const DID_MAX := 2
const WALLS := ["front", "right", "back", "left"]
const DOOR_ORDER := ["front", "back", "right", "left"]
const WIN_ORDER := ["front", "left", "right", "front", "back", "back", "left", "right"]   # 4 windows = 2 front, 1 each side
const NUMBERS := {"one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
	"eleven": 11, "twelve": 12, "single": 1}
const UNITS := {"m": 1.0, "metre": 1.0, "metres": 1.0, "meter": 1.0, "meters": 1.0, "cm": 0.01, "mm": 0.001, "ft": 0.3048, "feet": 0.3048, "foot": 0.3048}
const DOORW := ["door", "doors", "doorway", "doorways", "entrance"]
const WINW := ["window", "windows"]
const FLOORW := ["floor", "floors", "storey", "storeys", "story", "stories", "level", "levels"]
const WALLW := {"front": "front", "back": "back", "rear": "back", "left": "left", "right": "right"}
const HOUSEW := ["house", "home", "building", "cottage", "cabin", "villa", "bungalow", "hut", "place", "residence", "dojo", "hall", "arena", "gym", "barn", "warehouse", "studio", "temple"]
const ROOFKIND := {"gable": "gable", "gabled": "gable", "pitched": "gable", "peaked": "gable", "pointed": "gable", "triangular": "gable",
	"flat": "flat", "shed": "shed", "sloped": "shed", "sloping": "shed", "slanted": "shed", "lean": "shed",
	"hip": "hip", "hipped": "hip", "pyramid": "pyramid", "pyramidal": "pyramid", "xieshan": "xieshan", "chinese": "curved", "curved": "curved", "upturned": "curved"}   # s226: the shell roofs
const FILLER := ["a", "an", "the", "with", "and", "of", "on", "at", "in", "to", "it", "that", "has", "have", "having", "i", "want", "need", "please",
	"build", "make", "create", "give", "me", "us", "some", "just", "also", "plus", "each", "every", "all", "both", "side", "sides", "wall", "walls",
	"upstairs", "downstairs", "then", "now", "would", "like", "can", "you", "could", "for", "its", "is", "be", "new", "ground", "upper", "first", "total",
	"each.", "has", "along", "centre", "center", "middle", "one", "per", "four", "everywhere", "throughout", "my", "our", "this", "up"]
const EDIT_VERBS := ["move", "shift", "slide", "make", "add", "put", "remove", "delete", "take", "change", "set", "raise", "lower", "insert", "get", "drop", "turn", "swap", "place", "rotate"]
const LEAD := ["please", "now", "then", "just", "also", "can", "you", "could", "and"]
## every word the sentences use (the typo check looks here)
const VOCAB := ["house", "home", "building", "cottage", "cabin", "villa", "bungalow", "door", "doors", "window", "windows", "floor", "floors",
	"storey", "storeys", "story", "roof", "gable", "gabled", "flat", "shed", "sloped", "garage", "wide", "long", "deep", "front", "back", "left", "right",
	"overhang", "taller", "shorter", "higher", "lower", "wider", "narrower", "move", "remove", "delete", "add", "make", "centre", "second", "third",
	"first", "metres", "meters", "sides", "walls", "build", "pitched", "floor", "level", "levels",
	"stairs", "table", "bench", "crate", "pillar", "fence", "ramp", "platform", "corner", "around", "benches", "pillars", "crates", "staircase", "tables",
	"columns", "column", "bays"]   # s222: HallWords nouns, so a slip of one asks


# ---------------------------------------------------------------- the sentence

## the words of a sentence, lower case: numbers and units split ("8x6m" -> 8 x 6 m), "2nd" -> "ord2", "," kept, other marks gone
static func tokens(text: String) -> Array:
	var s := text.to_lower().replace("×", " x ").replace("*", " x ").replace("-", " ").replace("’", "'")
	for ch in [";", ":", "!", "?", "\"", "(", ")", "/", "+"]:
		s = s.replace(ch, " ")
	s = s.replace(",", " , ")
	var re := RegEx.new()
	re.compile("(?<!\\d)\\.|\\.(?!\\d)")
	s = re.sub(s, " ", true)
	re.compile("(\\d+)(st|nd|rd|th)\\b")
	s = re.sub(s, " ord$1 ", true)
	re.compile("(\\d)\\s*x\\s*(\\d)")
	s = re.sub(s, "$1 x $2", true)
	re.compile("(\\d)([a-z])")
	s = re.sub(s, "$1 $2", true)
	var out := []
	for w in s.split(" ", false):
		var t := String(w)
		if NUMBERS.has(t) and t != "single":
			t = str(NUMBERS[t])
		out.append(t)
	return out


static func _at(t: Array, i: int) -> String:
	return String(t[i]) if i >= 0 and i < t.size() else ""


static func _is_num(w: String) -> bool:
	return w != "" and w.is_valid_float() and not w.begins_with("-")


## the closest vocabulary word within DID_MAX edits ("hosue" -> "house"); "" = none
static func did_you_mean(w: String) -> String:
	if w.length() < 4 or _is_num(w) or w.begins_with("ord"):
		return ""
	var best := ""
	var best_d := (DID_MAX if w.length() > 4 else 1) + 1
	for v in VOCAB:
		var d := EasyHome.levenshtein(w, String(v))
		if d > 1 and _swapped(w, String(v)):
			d = 1   # two letters the wrong way round ("doro", "hosue") is one slip
		if d < best_d:
			best_d = d
			best = String(v)
	return best


static func _swapped(a: String, b: String) -> bool:
	if a.length() != b.length():
		return false
	for i in a.length() - 1:
		if a.substr(0, i) + a[i + 1] + a[i] + a.substr(i + 2) == b:
			return true
	return false


static func _refuse(error: String, did := "") -> Dictionary:
	return {"ok": false, "kind": "refuse", "error": error, "did": did, "notes": [], "ignored": [], "defaults": {}}


static func _unknown(w: String, did: String) -> Dictionary:
	var r := _refuse("Kine doesn't know '%s' in a building sentence. Did you mean: %s?" % [w, did], did)
	r["word"] = w
	return r


const SAY_EX := "Say a size, floors, doors, windows or a roof, like: a 2-floor house 8 x 6 m with a door and 4 windows."


## the words -> a plan or an edit (b = the building record now: edit phrases need one)
static func parse(text: String, b := {}) -> Dictionary:
	var sv := _save_phrase(text, b)
	if not sv.is_empty():
		return sv
	var t := tokens(text)
	while not t.is_empty() and LEAD.has(String(t[0])):
		t.pop_front()
	if t.is_empty():
		return _refuse("Nothing to build yet. " + SAY_EX)
	if _is_edit(t):
		var ed := _parse_edit(t, b)
		if b.is_empty() or b.get("rooms", []).is_empty():
			if bool(ed["ok"]):
				return _refuse("Nothing is built yet to change. Build first: a 2-floor house 8 x 6 m with a door and 4 windows.")
			if String(ed["did"]) == "":
				return _refuse("Kine doesn't know '%s' as a building yet. %s" % [" ".join(t), SAY_EX])
		return ed
	var pl := _parse_build(t)
	if bool(pl["ok"]) and bool(pl.get("pieces_only", false)) and not b.is_empty() and not b.get("rooms", []).is_empty():
		# only pieces were said and a building stands: they go ON it ("stairs in the corner"), the house is not rebuilt
		return {"ok": true, "kind": "edit", "edit": {"op": "add_pieces", "specs": (pl["plan"]["pieces"] as Array).duplicate(true), "text": " ".join(t)},
			"notes": pl["notes"], "ignored": pl["ignored"], "defaults": {}, "error": "", "did": ""}
	return pl


## "save it as Dojo": the house under that name (My houses). The name keeps its capitals, so this reads the typed text, not the tokens
static func _save_phrase(text: String, b: Dictionary) -> Dictionary:
	var re := RegEx.new()
	re.compile("(?i)^\\s*(?:(?:please|now|then|and|ok|okay)\\s+)*save\\s+(?:(?:it|this|that|the\\s+house|my\\s+house|house)\\s+)?(?:as|to|under|called|named)\\s+(.+?)\\s*$")
	var m := re.search(text)
	if m == null:
		return {}
	var nm := m.get_string(1).strip_edges().trim_prefix("\"").trim_suffix("\"").trim_prefix("'").trim_suffix("'").trim_suffix(".").strip_edges()
	if nm == "":
		return _refuse("Save it as what? Say a name: 'save it as Dojo'.")
	if nm.length() > 60:
		return _refuse("That name is too long: 60 letters at most.")
	if b.is_empty() or b.get("rooms", []).is_empty():
		return _refuse("Nothing is built yet to save. Build first: a 2-floor house 8 x 6 m with a door and 4 windows.")
	return {"ok": true, "kind": "edit", "edit": {"op": "save", "name": nm, "text": text.strip_edges()}, "notes": [], "ignored": [], "defaults": {}, "error": "", "did": ""}


## an edit starts with a verb and names no house and no size pair ("make a house 8 x 6" builds)
static func _is_edit(t: Array) -> bool:
	if not EDIT_VERBS.has(String(t[0])):
		return false
	for i in t.size():
		var w := String(t[i])
		if HOUSEW.has(w) and w != "place" and not (w == "building" and _at(t, i - 1) == "the"):
			return false
		if (w == "x" or w == "by") and _is_num(_at(t, i - 1)) and _is_num(_at(t, i + 1)):
			return false
	return true


# ---------------------------------------------------------------- build sentences

static func _snap_size(v: float, notes: Array, what: String) -> float:
	var s := snappedf(v, GRID)
	if absf(s - v) > 0.001:
		notes.append("%s %s became %s" % [what, _n(v), _n(s)])
	return s


static func _n(v: float) -> String:
	var s := "%.2f" % v
	return s.rstrip("0").rstrip(".") if s.contains(".") else s


static func _parse_build(t: Array) -> Dictionary:
	var P := {"w": 0.0, "d": 0.0, "floors": 0, "floor_h": 0.0, "door_n": -1, "door_walls": [], "door_at": "", "door_w": 0.0,
		"win_n": -1, "win_walls": [], "win_each": false, "roof": "", "overhang": -1.0, "garage": "", "garage_w": GARAGE_W, "pieces": []}
	var seen := {"size": false, "house": false, "door": false, "window": false, "roof": false, "garage": false, "floors": false, "piece": false}
	var pst := BuildWordsPieces.new_state()
	var plural := {"door": false, "window": false}
	var notes := []
	var ignored := []
	var raw := {}   # what was typed before snapping
	var ctx := ""
	var n := t.size()
	var i := 0
	while i < n:
		var w := String(t[i])
		var nx := _at(t, i + 1)
		# ---- pieces ("4 pillars around the room", "a crate by the door", "stairs to the second floor")
		var used := BuildWordsPieces.feed(t, i, pst, ctx == "piece")
		if used > 0:
			if pst.has("error"):
				return _refuse(String(pst["error"]))
			seen["piece"] = true
			ctx = "piece"
			i += used
			continue
		# ---- numbers
		if _is_num(w):
			var val := float(w)
			var j := i + 1
			var f := 1.0
			var had_unit := false
			if UNITS.has(_at(t, j)):
				f = float(UNITS[_at(t, j)])
				had_unit = true
				j += 1
			var tj := _at(t, j)
			if (tj == "x" or tj == "by") and _is_num(_at(t, j + 1)):
				var v2 := float(_at(t, j + 1))
				var k := j + 2
				var f2 := 1.0
				if UNITS.has(_at(t, k)):
					f2 = float(UNITS[_at(t, k)])
					k += 1
				var fu := f2 if f2 != 1.0 else f
				raw["w"] = val * fu
				raw["d"] = v2 * fu
				seen["size"] = true
				i = k
				continue
			if ["wide", "across", "width"].has(tj):
				raw["w"] = val * f
				seen["size"] = true
				i = j + 1
				continue
			if ["long", "deep", "length", "depth"].has(tj):
				raw["d"] = val * f
				seen["size"] = true
				i = j + 1
				continue
			if ["overhang", "overhanging", "eaves"].has(tj):
				P["overhang"] = val * f
				seen["roof"] = true
				i = j + 1
				continue
			var kk := j
			if WALLW.has(_at(t, kk)) and (DOORW + WINW).has(_at(t, kk + 1)):
				kk += 1
			var tk := _at(t, kk)
			if DOORW.has(tk):
				seen["door"] = true
				ctx = "door"
				if had_unit:
					P["door_w"] = val * f
				else:
					P["door_n"] = int(val)
					if kk > j:
						_add_wall(P["door_walls"], String(WALLW[_at(t, j)]))
				i = kk + 1
				continue
			if WINW.has(tk):
				seen["window"] = true
				ctx = "window"
				if had_unit:
					ignored.append("%s %s window size (change it in the Opening panel)" % [_n(val), _at(t, i + 1)])
				else:
					P["win_n"] = int(val)
					if kk > j:
						_add_wall(P["win_walls"], String(WALLW[_at(t, j)]))
				i = kk + 1
				continue
			if FLOORW.has(tk):
				seen["floors"] = true
				if had_unit:
					P["floor_h"] = val * f
				else:
					if absf(val - roundf(val)) > 0.001:
						return _refuse("Floors come in whole numbers: '%s %s' is not one. Say 1, 2 or 3 floors." % [w, tk])
					P["floors"] = int(roundf(val))
					if int(P["floors"]) < 1 or int(P["floors"]) > MAX_FLOORS:
						return _refuse("%d floors is not possible here: a house has 1 to %d floors." % [int(P["floors"]), MAX_FLOORS])
				i = kk + 1
				continue
			if ["tall", "high", "height"].has(tj):
				if FLOORW.has(_at(t, j + 1)):
					P["floor_h"] = val * f
					seen["floors"] = true
					i = j + 2
					continue
				ignored.append("%s %s %s (the whole height is not a number here: say '3 m floors')" % [w, "m" if had_unit else "", tj])
				i = j + 1
				continue
			ignored.append(w + (" " + _at(t, i + 1) if had_unit else ""))
			i = j
			continue
		# ---- words
		if w == "no" or w == "without" or w == "zero":
			var k := i + 1
			while ["a", "an", "the", "any"].has(_at(t, k)):
				k += 1
			var tk := _at(t, k)
			if DOORW.has(tk):
				P["door_n"] = 0
				seen["door"] = true
			elif WINW.has(tk):
				P["win_n"] = 0
				seen["window"] = true
			elif tk == "roof":
				P["roof"] = "none"
				seen["roof"] = true
			elif tk == "garage":
				seen["garage"] = true
			else:
				i += 1
				continue
			i = k + 1
			continue
		if w == "roofless":
			P["roof"] = "none"
			seen["roof"] = true
		elif WALLW.has(w) and (DOORW + WINW + ["garage"]).has(nx) and ctx != "piece":
			ctx = "door" if DOORW.has(nx) else ("window" if WINW.has(nx) else "garage")
			_attach(P, ctx, String(WALLW[w]))
		elif WALLW.has(w):
			if ctx == "door" or ctx == "window" or ctx == "garage":
				_attach(P, ctx, String(WALLW[w]))
			else:
				ignored.append(w)
		elif w == "side" or w == "sides":
			var pv := _at(t, i - 1)
			if ctx != "door" and ctx != "window":
				pass
			elif ["each", "every", "all"].has(pv):
				for ww in WALLS:
					_attach(P, ctx, ww)
				P["win_each" if ctx == "window" else "door_each"] = true
			else:
				_attach(P, ctx, "left")
				_attach(P, ctx, "right")
		elif ["each", "every", "all"].has(w) and ["wall", "walls", "four"].has(nx) and (ctx == "door" or ctx == "window"):
			for ww in WALLS:
				_attach(P, ctx, ww)
			P["win_each" if ctx == "window" else "door_each"] = true
		elif DOORW.has(w):
			seen["door"] = true
			ctx = "door"
			plural["door"] = w.ends_with("s")
		elif WINW.has(w):
			seen["window"] = true
			ctx = "window"
			plural["window"] = w.ends_with("s")
		elif w == "roof":
			seen["roof"] = true
			ctx = "roof"
		elif ROOFKIND.has(w):
			P["roof"] = ROOFKIND[w]
			seen["roof"] = true
			ctx = "roof"
		elif w == "overhang":
			if _is_num(nx):
				var k := i + 2
				var f := 1.0
				if UNITS.has(_at(t, k)):
					f = float(UNITS[_at(t, k)])
					k += 1
				P["overhang"] = float(nx) * f
				seen["roof"] = true
				i = k
				continue
		elif w == "garage":
			seen["garage"] = true
			ctx = "garage"
			if String(P["garage"]) == "":
				P["garage"] = "right"
		elif w == "single" and FLOORW.has(nx):
			P["floors"] = 1
			seen["floors"] = true
		elif w == "bungalow":
			seen["house"] = true
			if int(P["floors"]) == 0:
				P["floors"] = 1
		elif HOUSEW.has(w):
			seen["house"] = true
			ctx = ""
		elif FLOORW.has(w) or FILLER.has(w) or w == "," or w == "room" or w == "rooms":
			pass
		elif w.begins_with("ord") or w == "x" or w == "by":
			ignored.append(w.trim_prefix("ord"))
		elif UNITS.has(w):
			pass
		else:
			var did := did_you_mean(w)
			if did != "":
				return _unknown(w, did)
			ignored.append(w)
		i += 1
	var known := false
	for k in seen:
		known = known or bool(seen[k])
	if not known:
		var shown := " ".join(t)
		if shown.length() > 40:
			shown = shown.substr(0, 37) + "..."
		return _refuse("Kine doesn't know '%s' as a building yet. %s" % [shown, SAY_EX])
	P["pieces"] = pst["specs"]
	var only := bool(seen["piece"])
	for k2 in seen:
		if k2 != "piece" and bool(seen[k2]):
			only = false
	var fin := _finish(P, seen, plural, raw, notes, ignored)
	fin["pieces_only"] = only
	return fin


static func _add_wall(list: Array, wall: String) -> void:
	if not list.has(wall):
		list.append(wall)


## a wall word after a door / window / garage: the walls of that kind (the garage takes a side)
static func _attach(P: Dictionary, ctx: String, wall: String) -> void:
	match ctx:
		"door":
			_add_wall(P["door_walls"], wall)
		"window":
			_add_wall(P["win_walls"], wall)
		"garage":
			if wall == "left" or wall == "right":
				P["garage"] = wall


## the typed numbers -> a checked, snapped plan with its defaults and notes
static func _finish(P: Dictionary, seen: Dictionary, plural: Dictionary, raw: Dictionary, notes: Array, ignored: Array) -> Dictionary:
	var dflt := {}
	if raw.has("w"):
		P["w"] = float(raw["w"])
	if raw.has("d"):
		P["d"] = float(raw["d"])
	dflt["w"] = not raw.has("w")
	dflt["d"] = not raw.has("d")
	if not raw.has("w"):
		P["w"] = DEF_W
	if not raw.has("d"):
		P["d"] = DEF_D
	for k in ["w", "d"]:
		var v := float(P[k])
		if v < MIN_SIDE - 0.001 or v > MAX_SIDE + 0.001:
			return _refuse("A house %s m %s is not possible here: sides run from %s to %s m." % [_n(v), "wide" if k == "w" else "deep", _n(MIN_SIDE), _n(MAX_SIDE)])
	if raw.has("w"):
		P["w"] = _snap_size(float(P["w"]), notes, "")
	if raw.has("d"):
		P["d"] = _snap_size(float(P["d"]), notes, "")
	P["w"] = clampf(float(P["w"]), MIN_SIDE, MAX_SIDE)
	P["d"] = clampf(float(P["d"]), MIN_SIDE, MAX_SIDE)
	dflt["floors"] = int(P["floors"]) == 0
	if int(P["floors"]) == 0:
		P["floors"] = 1
	if int(P["floors"]) < 1 or int(P["floors"]) > MAX_FLOORS:
		return _refuse("%d floors is not possible here: a house has 1 to %d floors." % [int(P["floors"]), MAX_FLOORS])
	var stairs_note := ""
	for ps in P["pieces"]:
		if String(ps["kind"]) == "stairs" or String(ps["kind"]) == "stairs_l":
			var need := maxi(2, maxi(int(ps.get("to_floor", 0)), int(ps.get("storey", -1)) + 2))
			if bool(dflt["floors"]) and int(P["floors"]) < need:
				P["floors"] = need
				dflt["floors"] = false
				stairs_note = "Stairs go up, so the house has %d floors." % need
	dflt["floor_h"] = float(P["floor_h"]) <= 0.0
	if float(P["floor_h"]) <= 0.0:
		P["floor_h"] = DEF_FLOOR_H
	elif float(P["floor_h"]) < 2.0 or float(P["floor_h"]) > 5.0:
		return _refuse("Floors %s m tall are not possible here: a floor is 2 to 5 m." % _n(float(P["floor_h"])))
	P["floor_h"] = snappedf(float(P["floor_h"]), 0.1)
	# doors
	dflt["door_n"] = int(P["door_n"]) < 0
	if int(P["door_n"]) < 0:
		P["door_n"] = 2 if plural["door"] else 1
	dflt["door_at"] = true
	P["door_at"] = "centre"
	dflt["door_wall"] = (P["door_walls"] as Array).is_empty()
	dflt["door_w"] = float(P["door_w"]) <= 0.0
	if float(P["door_w"]) <= 0.0:
		P["door_w"] = DEF_DOOR_W
	elif float(P["door_w"]) < 0.4 or float(P["door_w"]) > 4.0:
		return _refuse("A door %s m wide is not possible here: 0.4 to 4 m." % _n(float(P["door_w"])))
	if int(P["door_n"]) > 8:
		return _refuse("%d doors is too many for one house here (up to 8)." % int(P["door_n"]))
	# windows
	dflt["win_n"] = int(P["win_n"]) < 0
	dflt["win_spread"] = (P["win_walls"] as Array).is_empty()
	if int(P["win_n"]) < 0:
		P["win_n"] = 1 if bool(P["win_each"]) or not (P["win_walls"] as Array).is_empty() else (4 if bool(seen["window"]) else 0)
	if int(P["win_n"]) > 24:
		return _refuse("%d windows is too many for one house here (up to 24)." % int(P["win_n"]))
	# roof
	dflt["roof"] = String(P["roof"]) == ""
	if String(P["roof"]) == "":
		P["roof"] = "gable"
	dflt["overhang"] = float(P["overhang"]) < 0.0
	if float(P["overhang"]) < 0.0:
		P["overhang"] = DEF_OVERHANG
	elif float(P["overhang"]) > 3.0:
		return _refuse("An overhang of %s m is not possible here: 0 to 3 m." % _n(float(P["overhang"])))
	dflt["garage"] = false
	P.erase("door_each")
	var out := {"ok": true, "kind": "plan", "plan": P, "notes": [], "ignored": ignored, "defaults": dflt, "error": "", "did": ""}
	var rounding := []
	for s in notes:
		rounding.append(String(s).strip_edges())
	if not rounding.is_empty():
		out["notes"].append("Sizes round to the %.1f m grid (%s)." % [GRID, ", ".join(rounding)])
	if String(P["garage"]) != "" and (P["win_walls"] as Array).has(P["garage"]):
		out["notes"].append("No windows on the %s wall: the garage is there." % P["garage"])
	if stairs_note != "":
		out["notes"].append(stairs_note)
	if not ignored.is_empty():
		out["notes"].append("Not understood, left out: %s." % ", ".join(ignored))
	return out


# ---------------------------------------------------------------- the plan -> the building

## where the plan's doors and windows go: {"doors": [{"wall", "at"}], "windows": [{"wall", "storey", "at"}]}; at = m from the wall's middle
static func layout(P: Dictionary) -> Dictionary:
	var w := float(P["w"])
	var d := float(P["d"])
	var nf := int(P["floors"])
	var gar := String(P.get("garage", ""))
	var dw: Array = P.get("door_walls", [])
	var doors := []
	var dn := int(P["door_n"])
	var perw := {}
	if dn > 0:
		var walls := dw.duplicate() if not dw.is_empty() else (["front"] if dn == 1 else DOOR_ORDER.duplicate())
		walls = walls.filter(func(x): return x != gar)
		if walls.is_empty():
			walls = ["front"]
		var total := maxi(dn, walls.size())
		for i in total:
			var wl := String(walls[i % walls.size()])
			perw[wl] = int(perw.get(wl, 0)) + 1
		for wl in perw:
			var len := w if wl == "front" or wl == "back" else d
			var ats := _spread(int(perw[wl]), len)
			if int(perw[wl]) == 1 and String(P["door_at"]) != "centre":
				ats = [snappedf(_left_sign(wl) * (1.0 if P["door_at"] == "left" else -1.0) * len * 0.25, GRID)]
			for a in ats:
				doors.append({"wall": wl, "at": float(a)})
	var wins := []
	var wn := int(P["win_n"])
	if wn > 0:
		var ww: Array = P.get("win_walls", [])
		var counts := {}
		if ww.is_empty():
			for i in wn:
				var wl := String(WIN_ORDER[i % WIN_ORDER.size()])
				if wl == gar:
					wl = "back" if gar == "" else String(WIN_ORDER[(i + 1) % WIN_ORDER.size()])
				counts[wl] = int(counts.get(wl, 0)) + 1
		else:
			var use: Array = ww.filter(func(x): return x != gar)
			if use.is_empty():
				use = ["front"]
			if bool(P.get("win_each", false)):
				for wl in use:
					counts[wl] = wn
			else:
				var total := maxi(wn, use.size())
				for i in total:
					var wl := String(use[i % use.size()])
					counts[wl] = int(counts.get(wl, 0)) + 1
		for wl in counts:
			var has_door := false
			for dd in doors:
				has_door = has_door or dd["wall"] == wl
			var lo := 1 if (has_door and nf > 1) else 0
			var c := int(counts[wl])
			var per := {}
			for i in c:
				var s := lo + (i % (nf - lo))
				per[s] = int(per.get(s, 0)) + 1
			var len := w if wl == "front" or wl == "back" else d
			for s in per:
				var ats := _spread(int(per[s]), len)
				for a in ats:
					var at := float(a)
					if s == 0:
						at = _clear_of_doors(at, wl, doors, len)
					wins.append({"wall": wl, "storey": int(s), "at": at})
	return {"doors": doors, "windows": wins}


## n evenly spread places on a wall of this length, m from its middle, on the grid
static func _spread(n: int, len: float) -> Array:
	var out := []
	for k in n:
		out.append(snappedf((float(k) + 0.5) / float(n) * len - len * 0.5, GRID))
	return out


## +1 when "left" (seen from outside, facing the wall) is toward +X / +Z of the wall's own "at"
static func _left_sign(wall: String) -> float:
	return {"front": 1.0, "back": -1.0, "left": -1.0, "right": 1.0}.get(wall, 1.0)


## a ground floor window keeps 1.5 m from a door's middle on its wall (the door 0.9 + the window 1.2 wide, half each, and a gap)
static func _clear_of_doors(at: float, wall: String, doors: Array, len: float) -> float:
	var bad := func(a: float) -> bool:
		for dd in doors:
			if dd["wall"] == wall and absf(float(dd["at"]) - a) < 1.5:
				return true
		return false
	if not bad.call(at):
		return at
	var lim := len * 0.5 - 1.0
	for k in range(1, 40):
		for sgn in [1.0, -1.0]:
			var a: float = at + sgn * float(k) * GRID
			if absf(a) <= lim and not bad.call(a):
				return a
	return at


## the record. name = the building's name
static func make_building(P: Dictionary, nm := "Untitled") -> Dictionary:
	return make_building_full(P, nm)["b"]


## the record and what the placing of the plan's pieces said: {"b", "res": [{"placed", "ids", "why"}] per piece spec}
static func make_building_full(P: Dictionary, nm := "Untitled") -> Dictionary:
	var b := Building.make(nm)
	var pr: Dictionary = b["params"]
	pr["floor_height"] = clampf(float(P["floor_h"]), Building.PARAMS["floor_height"][1], Building.PARAMS["floor_height"][2])
	pr["wall_height"] = maxf(float(pr["floor_height"]) - 0.1, 1.0)
	pr["door_width"] = clampf(float(P["door_w"]), Building.PARAMS["door_width"][1], Building.PARAMS["door_width"][2])
	pr["roof_overhang"] = clampf(float(P["overhang"]), 0.0, 3.0)
	Building.add_room(b, 0.0, 0.0, float(P["w"]), float(P["d"]))
	for i in int(P["floors"]) - 1:
		Building.add_floor(b)
	var lay := layout(P)
	for dd in lay["doors"]:
		Building.add_opening(b, _room_on(b, 0), String(dd["wall"]), "door", float(dd["at"]))
	for ww in lay["windows"]:
		Building.add_opening(b, _room_on(b, int(ww["storey"])), String(ww["wall"]), "window", float(ww["at"]))
	if String(P.get("garage", "")) != "":
		add_garage(b, String(P["garage"]), float(P.get("garage_w", GARAGE_W)))
	var pres := []
	if not (P.get("pieces", []) as Array).is_empty():
		pres = BuildWordsPieces.place(b, P["pieces"])["res"]
	var rk := String(P["roof"])
	if rk != "none":
		Building.set_roof(b, rk)
	return {"b": b, "res": pres}


## the id of the room on a floor (the first one)
static func _room_on(b: Dictionary, storey: int) -> String:
	for r in b["rooms"]:
		if int(r.get("storey", 0)) == storey and String(r["id"]) != "garage":
			return String(r["id"])
	return ""


## a garage: a ground floor room beside the house (sharing its wall), the house's depth, with a wide door in its front wall
static func add_garage(b: Dictionary, side: String, gw := GARAGE_W) -> String:
	var home := Building.room_of(b, _room_on(b, 0))
	if home.is_empty():
		return ""
	var t := Building.num(b, home.get("thickness"), 0.2)
	var x := float(home["x"]) + float(home["w"]) - t if side == "right" else float(home["x"]) - gw + t
	b["rooms"].append({"id": "garage", "x": x, "z": float(home["z"]), "w": gw, "d": float(home["d"]), "yaw": 0.0,
		"height": "wall_height", "thickness": "wall_thickness", "floor": true})
	var oid := Building.add_opening(b, "garage", "front", "door", 0.0)
	for o in b["openings"]:
		if String(o["id"]) == oid:
			o["w"] = minf(GARAGE_DOOR_W, gw - 0.8)
	return "garage"


## "8.0 x 6.0 m, 2 floors, 1 door, 4 windows" (the reply after Build it)
static func summary(P: Dictionary) -> String:
	var lay := layout(P)
	var nd: int = lay["doors"].size()
	var nw: int = lay["windows"].size()
	var s := "%s x %s m, %d floor%s, %d door%s, %d window%s" % [_n(float(P["w"])), _n(float(P["d"])), int(P["floors"]), "" if int(P["floors"]) == 1 else "s",
		nd, "" if nd == 1 else "s", nw, "" if nw == 1 else "s"]
	if String(P["roof"]) != "none":
		s += ", %s roof" % P["roof"]
	if String(P.get("garage", "")) != "":
		s += ", a garage on the " + String(P["garage"])
	if not (P.get("pieces", []) as Array).is_empty():
		s += ", " + BuildWordsPieces.summary(P["pieces"])
	return s


# ---------------------------------------------------------------- the cards

## the plan as numbered cards for the UI: [{"n", "title", "tag", "chips": [{"key", "text", "kind": "num" | "cycle", "value"}], "tail": ""}]
static func cards(P: Dictionary, dflt: Dictionary) -> Array:
	var out := []
	var lay := layout(P)
	out.append({"title": "Room", "tag": "default: %s x %s" % [_m(DEF_W), _m(DEF_D)] if bool(dflt.get("w", false)) and bool(dflt.get("d", false)) else "",
		"chips": [_num("w", float(P["w"])), {"text": "x", "kind": "text"}, _num("d", float(P["d"]))]})
	out.append({"title": "Floors", "tag": "default: 1" if bool(dflt.get("floors", false)) else "",
		"chips": [{"key": "floors", "text": str(int(P["floors"])), "kind": "num", "value": float(P["floors"])}, {"text": "floors, each" if int(P["floors"]) != 1 else "floor, each", "kind": "text"}, _num("floor_h", float(P["floor_h"]))]})
	var dn: int = lay["doors"].size()
	var dwalls := []
	for dd in lay["doors"]:
		if not dwalls.has(dd["wall"]):
			dwalls.append(dd["wall"])
	var door_chips := []
	if dn != 1:
		door_chips.append({"key": "door_n", "text": str(dn), "kind": "num", "value": float(dn)})
		door_chips.append({"text": "doors:" if dn != 0 else "doors", "kind": "text"})
	if dn > 0:
		door_chips.append({"key": "door_wall", "text": " + ".join(dwalls) + " wall" + ("s" if dwalls.size() > 1 else ""), "kind": "cycle", "value": 0.0})
		door_chips.append({"key": "door_at", "text": String(P["door_at"]), "kind": "cycle", "value": 0.0})
		door_chips.append(_num("door_w", float(P["door_w"])))
	out.append({"title": "Door" if dn == 1 else "Doors", "tag": "default: centre" if dn > 0 and bool(dflt.get("door_at", false)) and String(P["door_at"]) == "centre" else ("default: none" if dn == 0 and bool(dflt.get("door_n", false)) else ""),
		"chips": door_chips})
	var nw: int = lay["windows"].size()
	var split := {}
	for ww in lay["windows"]:
		split[ww["wall"]] = int(split.get(ww["wall"], 0)) + 1
	var parts := []
	var up := {}
	for ww in lay["windows"]:
		if int(ww["storey"]) > 0:
			up[ww["wall"]] = int(up.get(ww["wall"], 0)) + 1
	for wl in ["front", "back"]:
		if split.has(wl):
			parts.append("%d %s%s" % [int(split[wl]), wl, " upstairs" if int(up.get(wl, 0)) == int(split[wl]) else ""])
	if split.has("left") and split.has("right") and int(split["left"]) == int(split["right"]):
		parts.append("%d each side" % int(split["left"]))
	else:
		for wl in ["left", "right"]:
			if split.has(wl):
				parts.append("%d %s" % [int(split[wl]), wl])
	out.append({"title": "Windows", "tag": "default: evenly spread" if nw > 0 and bool(dflt.get("win_spread", false)) else ("default: none" if nw == 0 and bool(dflt.get("win_n", false)) else ""),
		"chips": [{"key": "win_n", "text": str(int(P["win_n"])), "kind": "num", "value": float(P["win_n"])}],
		"tail": ", ".join(parts) if nw > 0 else "no windows"})
	if String(P["roof"]) == "none":
		out.append({"title": "Roof", "tag": "", "chips": [{"key": "roof", "text": "none", "kind": "cycle", "value": 0.0}]})
	else:
		out.append({"title": "Roof", "tag": "default: gable" if bool(dflt.get("roof", false)) else "",
			"chips": [{"key": "roof", "text": String(P["roof"]), "kind": "cycle", "value": 0.0}, {"text": "overhang", "kind": "text"}, _num("overhang", float(P["overhang"]))]})
	if String(P.get("garage", "")) != "":
		out.append({"title": "Garage", "tag": "", "chips": [{"key": "garage", "text": "on the " + String(P["garage"]), "kind": "cycle", "value": 0.0},
			_num("garage_w", float(P.get("garage_w", GARAGE_W))), {"text": "wide", "kind": "text"}]})
	if not (P.get("pieces", []) as Array).is_empty():
		out.append_array(BuildWordsPieces.cards(P["pieces"], make_building_full(P)["res"]))
	for i in out.size():
		out[i]["n"] = i + 1
	return out


## a length as the cards show it: 8.0 m, 2.8 m, 0.45 m
static func _m(v: float) -> String:
	return ("%.1f m" if absf(v * 10.0 - roundf(v * 10.0)) < 0.001 else "%.2f m") % v


static func _num(key: String, v: float) -> Dictionary:
	return {"key": key, "text": _m(v), "kind": "num", "value": v}


## a chip's typed number put into the plan (the card's own rules: sizes on the grid, counts whole, ranges kept); a note says what changed.
## Returns "" when it took, else why not
static func set_chip(P: Dictionary, key: String, v: float) -> String:
	if key.begins_with("pc"):
		return BuildWordsPieces.set_chip(P["pieces"], key, v)
	match key:
		"w", "d":
			if v < MIN_SIDE or v > MAX_SIDE:
				return "A side runs from %s to %s m." % [_n(MIN_SIDE), _n(MAX_SIDE)]
			P[key] = snappedf(v, GRID)
		"floors":
			if int(roundf(v)) < 1 or int(roundf(v)) > MAX_FLOORS:
				return "A house has 1 to %d floors." % MAX_FLOORS
			P["floors"] = int(roundf(v))
		"floor_h":
			if v < 2.0 or v > 5.0:
				return "A floor is 2 to 5 m."
			P["floor_h"] = snappedf(v, 0.1)
		"door_n":
			if int(roundf(v)) < 0 or int(roundf(v)) > 8:
				return "0 to 8 doors."
			P["door_n"] = int(roundf(v))
		"door_w":
			if v < 0.4 or v > 4.0:
				return "A door is 0.4 to 4 m wide."
			P["door_w"] = snappedf(v, 0.05)
		"win_n":
			if int(roundf(v)) < 0 or int(roundf(v)) > 24:
				return "0 to 24 windows."
			P["win_n"] = int(roundf(v))
			P["win_each"] = false
		"overhang":
			if v < 0.0 or v > 3.0:
				return "An overhang is 0 to 3 m."
			P["overhang"] = snappedf(v, 0.05)
		"garage_w":
			if v < 2.5 or v > 8.0:
				return "A garage is 2.5 to 8 m wide."
			P["garage_w"] = snappedf(v, GRID)
		_:
			return "no such number"
	return ""


## a click on a word chip: the next choice
static func cycle(P: Dictionary, key: String) -> void:
	if key.begins_with("pc"):
		BuildWordsPieces.cycle(P["pieces"], key)
		return
	match key:
		"door_wall":
			var cur := String(((P["door_walls"] as Array)[0] if not (P["door_walls"] as Array).is_empty() else "front"))
			P["door_walls"] = [WALLS[(WALLS.find(cur) + 1) % 4]]
			if int(P["door_n"]) > 1:
				P["door_n"] = 1
		"door_at":
			P["door_at"] = {"centre": "left", "left": "right", "right": "centre"}.get(String(P["door_at"]), "centre")
		"roof":
			var kinds := ["gable", "flat", "shed", "none"]
			P["roof"] = kinds[(kinds.find(String(P["roof"])) + 1) % 4]
		"garage":
			P["garage"] = "left" if String(P["garage"]) == "right" else "right"


# ---------------------------------------------------------------- edit sentences

const ORD := {"first": 0, "ground": 0, "second": 1, "third": 2, "fourth": 3, "top": -2, "upper": -2, "last": -2, "lower": 0, "bottom": 0, "main": 0}
const WALL_PHR := ["wall", "side", "front", "back", "rear"]


static func _ordinal(t: Array) -> int:
	for i in t.size():
		var w := String(t[i])
		if w.begins_with("ord") and w.substr(3).is_valid_int():
			return int(w.substr(3)) - 1
		if ORD.has(w) and (FLOORW + ["door", "window", "doors", "windows"]).has(_at(t, i + 1)):
			return int(ORD[w])
		if w == "ground" or w == "top":
			return int(ORD[w])
	return -1


static func _amount(t: Array) -> Dictionary:
	for i in t.size():
		if _is_num(String(t[i])):
			var f := 1.0
			var j := i + 1
			if UNITS.has(_at(t, j)):
				f = float(UNITS[_at(t, j)])
				j += 1
			var prev := _at(t, i - 1)
			return {"v": float(t[i]) * f, "by": prev == "by" or prev == "another" or ["more", "less", "extra"].has(_at(t, j)), "idx": i, "end": j}
	return {}


static func _find_noun(t: Array, nouns: Array) -> String:
	for w in t:
		if nouns.has(String(w)):
			return String(w)
	return ""


static func _walls_in(t: Array) -> Array:
	var out := []
	for w in t:
		if WALLW.has(String(w)):
			_add_wall(out, String(WALLW[w]))
	return out


static func _parse_edit(t: Array, b: Dictionary) -> Dictionary:
	var verb := String(t[0])
	var amt := _amount(t)
	var walls := _walls_in(t)
	var ord := _ordinal(t)
	var door := _find_noun(t, DOORW) != ""
	var win := _find_noun(t, WINW) != ""
	var roof := t.has("roof")
	var garage := t.has("garage")
	var floor_w := _find_noun(t, FLOORW) != "" or t.has("storey")
	var e := {}
	var say := ""
	var more := func(words: Array) -> bool:
		for w in words:
			if t.has(w):
				return true
		return false
	# which words are left over (a typo refuses, an odd word is listed)
	var known := EDIT_VERBS + FILLER + VOCAB + DOORW + WINW + FLOORW + WALLW.keys() + UNITS.keys() + ORD.keys() + ["x", ",", "taller", "shorter", "bigger", "smaller", "higher", "wider", "narrower",
		"centre", "center", "middle", "another", "extra", "more", "less", "by", "all", "way", "corner", "other", "same", "no", "roof", "garage", "away", "off", "out", "of", "from", "onto", "into", "over", "under", "mine"] + BuildWordsPieces.WORDS.keys() + BuildWordsPieces.KNOWN
	var ignored := []
	for w in t:
		var ws := String(w)
		if known.has(ws) or _is_num(ws) or ws.begins_with("ord") or ROOFKIND.has(ws):
			continue
		var did := did_you_mean(ws)
		if did != "":
			return _unknown(ws, did)
		ignored.append(ws)
	if BuildWordsPieces.has_noun(t):
		return _piece_edit(t, verb, ignored)
	if more.call(["taller", "higher", "shorter", "lower", "bigger", "smaller"]) and not door and not win and not roof and not garage and not (more.call(["wider", "narrower"])):
		var up: bool = not more.call(["shorter", "lower", "smaller"])
		var all: bool = ord < 0 and (not floor_w or more.call(["floors", "storeys", "stories", "levels"]) or more.call(["house", "walls", "building", "ceilings", "ceiling"]))
		if not all and ord == -1:
			ord = -2
		e = {"op": "taller", "storey": -1 if all else ord, "by": 0.5 if up else -0.5, "abs": -1.0}
		if not amt.is_empty():
			if bool(amt["by"]) or more.call(["more", "less", "extra"]):
				e["by"] = absf(float(amt["v"])) * (1.0 if up else -1.0)
			else:
				e["abs"] = float(amt["v"])
	elif more.call(["wider", "narrower", "bigger", "smaller"]) and (door or win):
		var wide: bool = more.call(["wider", "bigger"])
		e = {"op": "opening_size", "kind": "door" if door else "window", "by": (0.3 if wide else -0.3) if amt.is_empty() else absf(float(amt["v"])) * (1.0 if wide else -1.0)}
	elif verb in ["move", "shift", "slide", "put", "swap", "turn"] and (door or win):
		var kind := "door" if door else "window"
		var dir := ""
		var to_wall := ""
		for w in t:
			if ["centre", "center", "middle"].has(String(w)):
				dir = "centre"
		var wi := -1
		for i in t.size():
			if WALLW.has(String(t[i])):
				wi = i
		if dir == "" and wi >= 0:
			var ww := String(WALLW[t[wi]])
			var after_to := false
			for i in range(0, wi):
				if ["to", "onto", "into"].has(String(t[i])):
					after_to = true
			var explicit_wall := ["wall", "side"].has(_at(t, wi + 1)) or ww == "front" or ww == "back"
			if after_to and (ww == "left" or ww == "right") and not explicit_wall:
				dir = ww
			elif after_to and explicit_wall:
				to_wall = ww
			elif ww == "left" or ww == "right":
				dir = ww
		if dir == "" and to_wall == "":
			return _refuse("Move it where? Say left, right, centre, or another wall: 'move the door to the left', 'move the door to the back wall'.")
		e = {"op": "move_opening", "kind": kind, "dir": dir, "to_wall": to_wall, "by": 1.0, "far": more.call(["way", "corner", "end"])}
		if not amt.is_empty():
			e["by"] = absf(float(amt["v"]))
		# which one: "the front door" names the wall it is on (only when the wall word is not the destination)
		var src := ""
		for i in t.size():
			if WALLW.has(String(t[i])) and (DOORW + WINW).has(_at(t, i + 1)):
				src = String(WALLW[t[i]])
		e["from_wall"] = src
		e["nth"] = ord if (ord >= 0 and (_at(t, t.find("door") - 1).begins_with("ord") or ["first", "second", "third"].has(_at(t, t.find("door") - 1)))) else -1
	elif roof and (verb in ["remove", "delete", "take", "drop", "get"] or more.call(["off", "away"]) and verb in ["take", "get"]):
		e = {"op": "roof", "kind": "none"}
	elif roof and verb in ["add", "put", "insert", "make", "change", "set", "turn", "swap"]:
		var kind := "gable"
		for w in t:
			if ROOFKIND.has(String(w)):
				kind = String(ROOFKIND[w])
		e = {"op": "roof", "kind": kind}
	elif garage and verb in ["remove", "delete", "take", "drop", "get"]:
		e = {"op": "remove_garage"}
	elif garage:
		e = {"op": "garage", "side": String(walls[0]) if not walls.is_empty() and (walls[0] == "left" or walls[0] == "right") else "right"}
	elif (door or win) and verb in ["add", "put", "insert", "make"]:
		var cnt := 1
		if not amt.is_empty() and not bool(amt["by"]) and int(amt["idx"]) < t.size() and not UNITS.has(_at(t, int(amt["idx"]) + 1)):
			cnt = int(float(amt["v"]))
		e = {"op": "add_opening", "kind": "door" if door else "window", "n": clampi(cnt, 1, 8), "wall": String(walls[0]) if not walls.is_empty() else "front", "storey": ord}
	elif (door or win) and verb in ["remove", "delete", "take", "drop", "get"]:
		e = {"op": "remove_opening", "kind": "door" if door else "window", "wall": String(walls[0]) if not walls.is_empty() else "", "all": more.call(["windows", "doors", "all"])}
	elif floor_w and verb in ["add", "put", "insert", "make"]:
		e = {"op": "add_floor"}
	elif floor_w and verb in ["remove", "delete", "take", "drop", "get"]:
		e = {"op": "remove_floor"}
	if e.is_empty():
		var shown := " ".join(t)
		return _refuse("Kine doesn't know '%s' as a change to a building yet. Try: move the door to the left, make the second floor taller, add a window on the back, remove the roof, add a garage." % shown)
	e["text"] = " ".join(t)
	return {"ok": true, "kind": "edit", "edit": e, "notes": [], "ignored": ignored, "defaults": {}, "error": "", "did": ""}


## "add 4 pillars around the room", "remove the crate", "turn the table", "move the stairs to the left wall"
static func _piece_edit(t: Array, verb: String, ignored: Array) -> Dictionary:
	var st := BuildWordsPieces.new_state()
	var i := 1
	var on := false
	while i < t.size():
		var used := BuildWordsPieces.feed(t, i, st, on)
		if used > 0:
			if st.has("error"):
				return _refuse(String(st["error"]))
			on = true
			i += used
		else:
			i += 1
	var specs: Array = st["specs"]
	if specs.is_empty():
		return _refuse("Kine doesn't know '%s' as a change to a building yet. Try: add 4 pillars around the room, remove the crate, turn the table, move the stairs to the left wall." % " ".join(t))
	var e := {}
	var first: Dictionary = specs[0]
	if verb in ["remove", "delete", "take", "drop", "get"]:
		e = {"op": "remove_piece", "kind": String(first["kind"]), "all": t.has("all") or int(first["n"]) > 1 or BuildWordsPieces.PLURAL.has(String(t[t.size() - 1])) or t.any(func(w): return BuildWordsPieces.PLURAL.has(String(w)))}
	elif verb in ["turn", "rotate", "swap"]:
		e = {"op": "turn_piece", "kind": String(first["kind"])}
	elif verb in ["move", "shift", "slide"]:
		if String(first["at"]) == "" and String(first["wall"]) == "":
			return _refuse("Move it where? Say a place: 'move the %s to the left wall', 'to the middle', 'to the corner', 'by the door'." % BuildWordsPieces.label(String(first["kind"]), 1))
		e = {"op": "move_piece", "kind": String(first["kind"]), "at": BuildWordsPieces.eff_at(first), "wall": String(first["wall"])}
	else:
		e = {"op": "add_pieces", "specs": specs}
	e["text"] = " ".join(t)
	return {"ok": true, "kind": "edit", "edit": e, "notes": [], "ignored": ignored, "defaults": {}, "error": "", "did": ""}


## one edit on the record. {"ok", "say"} | {"ok": false, "error"}. The caller takes ONE undo step before this
static func apply_edit(b: Dictionary, e: Dictionary) -> Dictionary:
	var fail := func(s: String) -> Dictionary:
		return {"ok": false, "error": s}
	match String(e["op"]):
		"move_opening":
			var list := _openings(b, String(e["kind"]), String(e.get("from_wall", "")))
			if list.is_empty():
				return fail.call("There is no %s%s to move." % [e["kind"], " on the %s wall" % e["from_wall"] if String(e.get("from_wall", "")) != "" else ""])
			var nth := int(e.get("nth", -1))
			if nth > list.size() - 1:
				return fail.call("There is no %s number %d: the house has %d." % [e["kind"], nth + 1, list.size()])
			var o: Dictionary = list[maxi(nth, 0)]
			var r := Building.room_of(b, String(o["room"]))
			if String(e["to_wall"]) != "":
				if String(o["wall"]) == String(e["to_wall"]):
					return fail.call("The %s is already on the %s wall." % [e["kind"], e["to_wall"]])
				if not Building.WALLS.has(String(o["wall"])):
					return fail.call("That one is in an inner wall: move it with the Opening tool.")
				o["wall"] = String(e["to_wall"])
				o["at"] = 0.0
				return {"ok": true, "say": "Moved the %s to the %s wall, in the middle" % [e["kind"], e["to_wall"]]}
			var wall := String(o["wall"])
			var len := float(r["w"]) if wall == "front" or wall == "back" else float(r["d"])
			var t := Building.num(b, r.get("thickness"), 0.2)
			var ow := Building.num(b, o.get("w"), 0.9)
			var lim := maxf(len * 0.5 - t - ow * 0.5, 0.0)
			var at0 := float(o["at"])
			var at1 := 0.0
			match String(e["dir"]):
				"left":
					at1 = lim * _left_sign(wall) if bool(e["far"]) else at0 + _left_sign(wall) * float(e["by"])
				"right":
					at1 = -lim * _left_sign(wall) if bool(e["far"]) else at0 - _left_sign(wall) * float(e["by"])
				"centre":
					at1 = 0.0
			at1 = clampf(snappedf(at1, GRID), -lim, lim)
			if absf(at1 - at0) < 0.001:
				return fail.call("The %s is already %s." % [e["kind"], "in the middle" if String(e["dir"]) == "centre" else "as far %s as the wall allows" % e["dir"]])
			o["at"] = at1
			return {"ok": true, "say": "Moved the %s %s on the %s wall: now %.1f m from the middle" % [e["kind"], "to the " + String(e["dir"]) if String(e["dir"]) != "centre" else "to the middle", wall, at1]}
		"taller":
			return _taller(b, e)
		"opening_size":
			var key := "door_width" if String(e["kind"]) == "door" else "window_width"
			var old := float(b["params"][key])
			var nv: float = clampf(old + float(e["by"]), Building.PARAMS[key][1], Building.PARAMS[key][2])
			if absf(nv - old) < 0.001:
				return fail.call("The %s is already as %s as it can be." % [String(e["kind"]), "wide" if float(e["by"]) > 0 else "narrow"])
			b["params"][key] = snappedf(nv, 0.05)
			return {"ok": true, "say": "%s: %.2f -> %.2f m (every %s follows)" % [key.capitalize().replace("_", " "), old, nv, e["kind"]]}
		"add_opening":
			return _add_opening(b, e)
		"remove_opening":
			var list2 := _openings(b, String(e["kind"]), String(e["wall"]))
			if list2.is_empty():
				return fail.call("There is no %s%s to remove." % [e["kind"], " on the %s wall" % e["wall"] if String(e["wall"]) != "" else ""])
			if list2.size() > 1 and not bool(e["all"]) and String(e["wall"]) == "":
				return fail.call("Which %s? There are %d. Say 'remove the front %s' (or 'remove all the %ss')." % [e["kind"], list2.size(), e["kind"], e["kind"]])
			var gone := list2 if (bool(e["all"]) or String(e["wall"]) != "") else [list2[0]]
			for o2 in gone:
				b["openings"].erase(o2)
			return {"ok": true, "say": "Removed %d %s%s (the wall fills the hole)" % [gone.size(), e["kind"], "" if gone.size() == 1 else "s"]}
		"roof":
			if String(e["kind"]) == "none":
				if b.get("roof", {}).is_empty():
					return fail.call("There is no roof to remove.")
				b.erase("roof")
				return {"ok": true, "say": "Roof: taken off"}
			if String(b.get("roof", {}).get("kind", "")) == String(e["kind"]):
				return fail.call("The roof is already %s." % e["kind"])
			Building.set_roof(b, String(e["kind"]))
			return {"ok": true, "say": "Roof: %s, overhang %.2f m" % [e["kind"], Building.num(b, b["roof"].get("overhang"), 0.45)]}
		"garage":
			if not Building.room_of(b, "garage").is_empty():
				return fail.call("There is a garage already: 'remove the garage' first.")
			add_garage(b, String(e["side"]))
			return {"ok": true, "say": "Added a garage on the %s: %.1f m wide, sharing the house's wall, with a wide door in front" % [e["side"], GARAGE_W]}
		"remove_garage":
			var g := Building.room_of(b, "garage")
			if g.is_empty():
				return fail.call("There is no garage to remove.")
			b["rooms"].erase(g)
			for o3 in b["openings"].duplicate():
				if String(o3["room"]) == "garage":
					b["openings"].erase(o3)
			return {"ok": true, "say": "Garage: removed"}
		"add_floor":
			if Building.storey_count(b) >= MAX_FLOORS:
				return fail.call("A house here has up to %d floors." % MAX_FLOORS)
			var n := Building.add_floor(b)
			return {"ok": true, "say": "Floor %d added: the same footprint, a floor slab between" % (n + 1)}
		"remove_floor":
			if not Building.remove_top_floor(b):
				return fail.call("The last floor stays.")
			return {"ok": true, "say": "The top floor is gone"}
		"add_pieces", "remove_piece", "turn_piece", "move_piece":
			return BuildWordsPieces.apply(b, e)
		"save":
			return fail.call("Saving is done by the page (the file and its picture), not on the record.")
	return fail.call("Kine cannot do '%s' yet." % e.get("text", ""))


## the doors (kind "door": doors and arches) or windows of the building, on a wall when given; ground floor first
static func _openings(b: Dictionary, kind: String, wall: String) -> Array:
	var out := []
	for o in b.get("openings", []):
		var k := String(o.get("kind", ""))
		if (kind == "window") != (k == "window"):
			continue
		if wall != "" and String(o.get("wall", "")) != wall:
			continue
		out.append(o)
	return out


static func _taller(b: Dictionary, e: Dictionary) -> Dictionary:
	var nf := Building.storey_count(b)
	var s := int(e["storey"])
	var pr: Dictionary = b["params"]
	if s == -2:
		s = nf - 1
	if s >= nf:
		return {"ok": false, "error": "There is no floor %d: the house has %d." % [s + 1, nf]}
	if s == -1 or nf == 1 and s == 0 and false:
		var fh0 := float(pr["floor_height"])
		var target := float(e["abs"]) if float(e["abs"]) > 0 else fh0 + float(e["by"])
		var fh1 := clampf(snappedf(target, 0.1), Building.PARAMS["floor_height"][1], Building.PARAMS["floor_height"][2])
		if absf(fh1 - fh0) < 0.001:
			return {"ok": false, "error": "The floors are already as %s as they go." % ("tall" if target > fh0 else "short")}
		pr["floor_height"] = fh1
		pr["wall_height"] = clampf(fh1 - 0.1, Building.PARAMS["wall_height"][1], Building.PARAMS["wall_height"][2])
		return {"ok": true, "say": "Every floor: %.1f -> %.1f m" % [fh0, fh1]}
	if s != nf - 1:
		return {"ok": false, "error": "Floor %d has floors above it, so it cannot change alone. Say 'make the floors taller' for all of them, or the top floor." % (s + 1)}
	var cur := 0.0
	for r in b["rooms"]:
		if int(r.get("storey", 0)) == s and String(r["id"]) != "garage":
			cur = Building.num(b, r.get("height"), 2.7)
	var nh := (float(e["abs"]) - 0.1) if float(e["abs"]) > 0 else cur + float(e["by"])
	nh = clampf(snappedf(nh, 0.1), 1.0, 12.0)
	if absf(nh - cur) < 0.001:
		return {"ok": false, "error": "Floor %d is already as %s as it goes." % [s + 1, "tall" if nh >= cur else "short"]}
	for r in b["rooms"]:
		if int(r.get("storey", 0)) == s and String(r["id"]) != "garage":
			r["height"] = nh
	return {"ok": true, "say": "Floor %d: %.1f -> %.1f m tall (a number of its own; the roof follows)" % [s + 1, cur + 0.1, nh + 0.1]}


static func _add_opening(b: Dictionary, e: Dictionary) -> Dictionary:
	var nf := Building.storey_count(b)
	var s := int(e["storey"])
	if s == -2:
		s = nf - 1
	if s < 0:
		s = 0
	if s >= nf:
		return {"ok": false, "error": "There is no floor %d: the house has %d." % [s + 1, nf]}
	if String(e["kind"]) == "door" and s > 0:
		return {"ok": false, "error": "A door goes on the ground floor (stairs come later)."}
	var room := _room_on(b, s)
	var wall := String(e["wall"])
	var r := Building.room_of(b, room)
	var len := float(r["w"]) if wall == "front" or wall == "back" else float(r["d"])
	var gar := Building.room_of(b, "garage")
	if not gar.is_empty() and ((wall == "right" and float(gar["x"]) > 0.0) or (wall == "left" and float(gar["x"]) < 0.0)) and s == 0:
		return {"ok": false, "error": "The %s wall is the garage's: pick another wall." % wall}
	var placed := 0
	for i in int(e["n"]):
		var at: Variant = _free_spot(b, room, wall, String(e["kind"]), len)
		if at == null:
			break
		if Building.add_opening(b, room, wall, String(e["kind"]), float(at)) != "":
			placed += 1
	if placed == 0:
		return {"ok": false, "error": "The %s wall is full: no room for another %s." % [wall, e["kind"]]}
	return {"ok": true, "say": "Added %d %s%s on the %s wall%s%s" % [placed, e["kind"], "" if placed == 1 else "s", wall, " (floor %d)" % (s + 1) if nf > 1 else "",
		"" if placed == int(e["n"]) else " (that is all that fits)"]}


## a place on the wall (m from the middle, on the grid) that clears the openings there: middle first, then outward
static func _free_spot(b: Dictionary, room: String, wall: String, kind: String, len: float) -> Variant:
	var w_new := Building.num(b, "door_width" if kind != "window" else "window_width", 1.0)
	var lim := len * 0.5 - 0.4 - w_new * 0.5
	var busy := []
	for o in b.get("openings", []):
		if String(o["room"]) == room and String(o["wall"]) == wall:
			busy.append([float(o["at"]), Building.num(b, o.get("w"), 0.9)])
	for k in range(0, 80):
		for sgn in ([1.0] if k == 0 else [1.0, -1.0]):
			var a: float = float(k) * GRID * sgn
			if absf(a) > lim:
				continue
			var free := true
			for bz in busy:
				if absf(float(bz[0]) - a) < (float(bz[1]) + w_new) * 0.5 + 0.2:
					free = false
			if free:
				return a
	return null


## a sentence for the plan's footer: what an edit will do, in words (the card before the click)
static func describe_edit(e: Dictionary) -> String:
	match String(e["op"]):
		"move_opening":
			if String(e["to_wall"]) != "":
				return "Move the %s to the %s wall, in the middle" % [e["kind"], e["to_wall"]]
			return "Move the %s to the %s%s" % [e["kind"], e["dir"], "" if String(e["dir"]) == "centre" or bool(e["far"]) else " by %.1f m" % float(e["by"])]
		"taller":
			var which := "every floor" if int(e["storey"]) == -1 else ("the top floor" if int(e["storey"]) == -2 else "floor %d" % (int(e["storey"]) + 1))
			if float(e["abs"]) > 0:
				return "Make %s %.1f m tall" % [which, float(e["abs"])]
			return "Make %s %s by %.1f m" % [which, "taller" if float(e["by"]) > 0 else "shorter", absf(float(e["by"]))]
		"opening_size":
			return "Make every %s %s by %.1f m" % [e["kind"], "wider" if float(e["by"]) > 0 else "narrower", absf(float(e["by"]))]
		"add_opening":
			return "Add %d %s%s on the %s wall" % [int(e["n"]), e["kind"], "" if int(e["n"]) == 1 else "s", e["wall"]]
		"remove_opening":
			return "Remove the %s%s" % [e["kind"] if String(e["wall"]) == "" else "%s %s" % [e["wall"], e["kind"]], "s" if bool(e["all"]) else ""]
		"roof":
			return "Take the roof off" if String(e["kind"]) == "none" else "Make the roof %s" % e["kind"]
		"garage":
			return "Add a garage on the %s" % e["side"]
		"remove_garage":
			return "Remove the garage"
		"add_floor":
			return "Add a floor on top"
		"remove_floor":
			return "Remove the top floor"
		"add_pieces", "remove_piece", "turn_piece", "move_piece":
			return BuildWordsPieces.describe(e)
		"save":
			return "Save this house as \"%s\"" % e["name"]
	return String(e.get("text", ""))
