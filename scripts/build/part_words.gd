class_name PartWords
extends RefCounted
## p085typetobuil (Friday plan 85, Nick: monkey-brain easy): type a part in words. "a box 20 by 10 by 5 cm, hollow, 2 mm walls, lid" is read
## here into sizes (mm), a hollow with its wall, and a lid. Pure: no scene, no kernel; Easy Part builds it (easy_part.gd, Parts > Type it).
## parse() never guesses past the words: a sentence it cannot read says what to type instead, in plain words.

const EXAMPLE := "a box 20 by 10 by 5 cm, hollow, 2 mm walls, lid"
const SIDE_MIN := 50.0     # mm: the box template's sides (5 cm to 100 cm)
const SIDE_MAX := 1000.0
const WALL_MIN := 1.0      # mm: the Wall slider's range
const WALL_MAX := 10.0
const WALL_DEF := 3.0      # mm: the wall a hollow starts with when no wall is typed (Hollow inside's own)


## the sentence read into {"ok", "why", "w", "d", "h" (mm: long, wide, tall), "hollow", "wall" (mm), "lid"}. Sizes with no unit are cm
static func parse(text: String) -> Dictionary:
	var t := text.to_lower().strip_edges()
	var out := {"ok": false, "why": "", "w": 0.0, "d": 0.0, "h": 0.0, "hollow": false, "wall": WALL_DEF, "lid": false}
	if t == "":
		out["why"] = "Type a box to build, like: " + EXAMPLE
		return out
	if t.find("box") < 0:
		out["why"] = "Kine types a box for now. Try: " + EXAMPLE
		return out
	var num := "(\\d+(?:\\.\\d+)?)"
	var dims := RegEx.create_from_string(num + "\\s*(?:x|by|×)\\s*" + num + "\\s*(?:x|by|×)\\s*" + num + "\\s*(mm|cm|m)?\\b")
	var md := dims.search(t)
	if md == null:
		out["why"] = "Give the three sizes long by wide by tall, like: " + EXAMPLE
		return out
	var unit := md.get_string(4)
	var f: float = 1.0 if unit == "mm" else (1000.0 if unit == "m" else 10.0)
	var sides := [float(md.get_string(1)) * f, float(md.get_string(2)) * f, float(md.get_string(3)) * f]
	for s in sides:
		if s < SIDE_MIN or s > SIDE_MAX:
			out["why"] = "Each side must be 5 to 100 cm. Try: " + EXAMPLE
			return out
	out["w"] = sides[0]
	out["d"] = sides[1]
	out["h"] = sides[2]
	# walls: "2 mm walls" or "walls 2 mm" (a wall implies a hollow); lid: the word lid
	var wall_mm := -1.0
	var mw := RegEx.create_from_string(num + "\\s*(mm|cm)?\\s*walls?\\b").search(t)
	if mw != null:
		wall_mm = float(mw.get_string(1)) * (10.0 if mw.get_string(2) == "cm" else 1.0)
	else:
		mw = RegEx.create_from_string("walls?\\s*(?:of\\s*)?" + num + "\\s*(mm|cm)?").search(t)
		if mw != null:
			wall_mm = float(mw.get_string(1)) * (10.0 if mw.get_string(2) == "cm" else 1.0)
	if wall_mm >= 0.0 and (wall_mm < WALL_MIN or wall_mm > WALL_MAX):
		out["why"] = "Walls are 1 to 10 mm thick. Type a wall like: 2 mm walls"
		return out
	if wall_mm >= 0.0:
		out["wall"] = wall_mm
	out["lid"] = RegEx.create_from_string("\\blid\\b").search(t) != null
	out["hollow"] = t.find("hollow") >= 0 or wall_mm >= 0.0 or bool(out["lid"])
	out["ok"] = true
	return out
