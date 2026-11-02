class_name MaterialWords
extends RefCounted
## MATERIAL WORDS (Friday plan 223): "dark oak", "red lacquer, a bit worn", "brushed steel, rougher", "orange glazed tile",
## "white marble with grey veins", "#ff8800", "darker" -> a material SPEC (scripts/material_maker.gd). No AI model: a lexicon and numbers,
## the BuildWords style. A word the lexicon does not know is LISTED in "unknown", never guessed.
##   parse(line, base := {}) -> {"ok": bool, "spec": {...}, "unknown": [words], "said": "plain words for what was understood"}
## ok = the line named a material or a colour, or (with a base spec) changed one. With a base, "rougher" / "darker" / "more worn" edit it.

## the 140 HTML colour names (name -> html). Grey spellings are aliases in GREY_ALIASES
const COLOURS := {
	"aliceblue": "f0f8ff", "antiquewhite": "faebd7", "aqua": "00ffff", "aquamarine": "7fffd4", "azure": "f0ffff", "beige": "f5f5dc",
	"bisque": "ffe4c4", "black": "000000", "blanchedalmond": "ffebcd", "blue": "0000ff", "blueviolet": "8a2be2", "brown": "a52a2a",
	"burlywood": "deb887", "cadetblue": "5f9ea0", "chartreuse": "7fff00", "chocolate": "d2691e", "coral": "ff7f50",
	"cornflowerblue": "6495ed", "cornsilk": "fff8dc", "crimson": "dc143c", "cyan": "00ffff", "darkblue": "00008b", "darkcyan": "008b8b",
	"darkgoldenrod": "b8860b", "darkgray": "a9a9a9", "darkgreen": "006400", "darkkhaki": "bdb76b", "darkmagenta": "8b008b",
	"darkolivegreen": "556b2f", "darkorange": "ff8c00", "darkorchid": "9932cc", "darkred": "8b0000", "darksalmon": "e9967a",
	"darkseagreen": "8fbc8f", "darkslateblue": "483d8b", "darkslategray": "2f4f4f", "darkturquoise": "00ced1", "darkviolet": "9400d3",
	"deeppink": "ff1493", "deepskyblue": "00bfff", "dimgray": "696969", "dodgerblue": "1e90ff", "firebrick": "b22222",
	"floralwhite": "fffaf0", "forestgreen": "228b22", "fuchsia": "ff00ff", "gainsboro": "dcdcdc", "ghostwhite": "f8f8ff",
	"gold": "ffd700", "goldenrod": "daa520", "gray": "808080", "green": "008000", "greenyellow": "adff2f", "honeydew": "f0fff0",
	"hotpink": "ff69b4", "indianred": "cd5c5c", "indigo": "4b0082", "ivory": "fffff0", "khaki": "f0e68c", "lavender": "e6e6fa",
	"lavenderblush": "fff0f5", "lawngreen": "7cfc00", "lemonchiffon": "fffacd", "lightblue": "add8e6", "lightcoral": "f08080",
	"lightcyan": "e0ffff", "lightgoldenrodyellow": "fafad2", "lightgray": "d3d3d3", "lightgreen": "90ee90", "lightpink": "ffb6c1",
	"lightsalmon": "ffa07a", "lightseagreen": "20b2aa", "lightskyblue": "87cefa", "lightslategray": "778899", "lightsteelblue": "b0c4de",
	"lightyellow": "ffffe0", "lime": "00ff00", "limegreen": "32cd32", "linen": "faf0e6", "magenta": "ff00ff", "maroon": "800000",
	"mediumaquamarine": "66cdaa", "mediumblue": "0000cd", "mediumorchid": "ba55d3", "mediumpurple": "9370db", "mediumseagreen": "3cb371",
	"mediumslateblue": "7b68ee", "mediumspringgreen": "00fa9a", "mediumturquoise": "48d1cc", "mediumvioletred": "c71585",
	"midnightblue": "191970", "mintcream": "f5fffa", "mistyrose": "ffe4e1", "moccasin": "ffe4b5", "navajowhite": "ffdead",
	"navy": "000080", "oldlace": "fdf5e6", "olive": "808000", "olivedrab": "6b8e23", "orange": "ffa500", "orangered": "ff4500",
	"orchid": "da70d6", "palegoldenrod": "eee8aa", "palegreen": "98fb98", "paleturquoise": "afeeee", "palevioletred": "db7093",
	"papayawhip": "ffefd5", "peachpuff": "ffdab9", "peru": "cd853f", "pink": "ffc0cb", "plum": "dda0dd", "powderblue": "b0e0e6",
	"purple": "800080", "red": "ff0000", "rosybrown": "bc8f8f", "royalblue": "4169e1", "saddlebrown": "8b4513", "salmon": "fa8072",
	"sandybrown": "f4a460", "seagreen": "2e8b57", "seashell": "fff5ee", "sienna": "a0522d", "silver": "c0c0c0", "skyblue": "87ceeb",
	"slateblue": "6a5acd", "slategray": "708090", "snow": "fffafa", "springgreen": "00ff7f", "steelblue": "4682b4", "tan": "d2b48c",
	"teal": "008080", "thistle": "d8bfd8", "tomato": "ff6347", "turquoise": "40e0d0", "violet": "ee82ee", "wheat": "f5deb3",
	"white": "ffffff", "whitesmoke": "f5f5f5", "yellow": "ffff00", "yellowgreen": "9acd32",
}
## "grey" -> "gray" (applied to every word before the table is read)

## material words -> [kind, tweaks]. Tweaks are spec numbers set when the word is used
const KINDS := {
	"oak": ["oak", {}], "wood": ["oak", {}], "wooden": ["oak", {}], "pine": ["pine", {}], "plywood": ["plywood", {}], "ply": ["plywood", {}],
	"steel": ["steel", {}], "stainless": ["steel", {}], "metal": ["steel", {}], "aluminium": ["aluminium", {}], "aluminum": ["aluminium", {}], "alu": ["aluminium", {}], "nickel": ["nickel", {}], "nickelled": ["nickel", {}], "iron": ["iron", {}], "copper": ["copper", {}],
	"brass": ["brass", {}], "lacquer": ["lacquer", {}], "lacquered": ["lacquer", {}], "paint": ["lacquer", {}], "painted": ["lacquer", {}],
	"enamel": ["lacquer", {}], "tile": ["tile", {}], "tiles": ["tile", {}], "tiled": ["tile", {}], "terracotta": ["terracotta", {}],
	"granite": ["granite", {}], "marble": ["marble", {}], "concrete": ["concrete", {}], "cement": ["concrete", {}], "brick": ["brick", {}],
	"bricks": ["brick", {}], "plaster": ["plaster", {}], "stucco": ["plaster", {}], "grass": ["grass", {}], "lawn": ["grass", {}],
	"gravel": ["gravel", {}], "pebbles": ["gravel", {}], "fabric": ["fabric", {}], "cloth": ["fabric", {}], "cotton": ["fabric", {}],
	"leather": ["leather", {}], "rubber": ["rubber", {}], "glass": ["glass", {}], "plastic": ["plastic", {}],
	"slabs": ["slabs", {}], "slab": ["slabs", {}], "flagstone": ["slabs", {}], "flagstones": ["slabs", {}], "paving": ["slabs", {}], "paved": ["slabs", {}],   # s231
	"caihua": ["caihua", {}], "gilded": ["brass", {}], "gilt": ["brass", {}], "gilding": ["brass", {}],
}
## words that change a number: word -> [what, amount]. what: dark (+ lighter / - darker), warm, wear, gloss, brushed
const MODS := {
	"dark": ["dark", -0.28], "darker": ["dark", -0.28], "deep": ["dark", -0.18], "light": ["dark", 0.28], "lighter": ["dark", 0.28],
	"pale": ["dark", 0.3], "bright": ["dark", 0.15], "warm": ["warm", 1.0], "warmer": ["warm", 1.0], "cool": ["warm", -1.0], "cooler": ["warm", -1.0],
	"worn": ["wear", 0.5], "old": ["wear", 0.5], "weathered": ["wear", 0.6], "scratched": ["wear", 0.4], "aged": ["wear", 0.5], "rusty": ["wear", 0.7],
	"new": ["wear", -2.0], "clean": ["wear", -2.0], "pristine": ["wear", -2.0], "unworn": ["wear", -2.0],
	"rough": ["gloss", -0.35], "rougher": ["gloss", -0.35], "coarse": ["gloss", -0.35], "matte": ["gloss_set", 0.12], "dull": ["gloss", -0.3],
	"smooth": ["gloss", 0.25], "smoother": ["gloss", 0.25], "glossy": ["gloss_set", 0.88], "glossier": ["gloss", 0.25], "shiny": ["gloss_set", 0.9],
	"polished": ["polish", 0.9], "glazed": ["gloss_set", 0.9], "brushed": ["brushed", 1.0],
}
## strength words: "a bit worn" = half, "very worn" = twice
const STRENGTH := {"bit": 0.5, "slightly": 0.5, "little": 0.5, "somewhat": 0.7, "very": 1.8, "much": 1.8, "really": 1.8, "extra": 1.8, "more": 1.3, "less": -1.0}
const FILLER := ["a", "an", "the", "with", "and", "of", "in", "on", "is", "it", "its", "some", "that", "this", "plain", "simple", "roof", "cast",
	"colour", "color", "finish", "material", "made", "like", "looks", "look", "slightly", "bit", "make"]
const VEIN_WORDS := ["vein", "veins", "veined", "streak", "streaks"]


static func colour_names() -> Array:
	return COLOURS.keys()


## html colour of a colour word ("darkred", "grey") or "#ff8800"; "" when the word is none
static func colour_of(w: String) -> String:
	if w.begins_with("#") and w.substr(1).is_valid_hex_number() and w.length() in [4, 7]:
		var h := w.substr(1)
		if h.length() == 3:
			h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2]
		return "#" + h
	w = w.replace("grey", "gray")
	return "#" + String(COLOURS[w]) if COLOURS.has(w) else ""


static func _tokens(line: String) -> Array:
	var s := line.to_lower()
	for ch in [",", ";", "/", "&", "+", "(", ")", "."]:
		s = s.replace(ch, " ")
	var out := []
	for t in s.split(" ", false):
		out.append(String(t).replace("grey", "gray") if not String(t).begins_with("#") else String(t))
	return out


static func parse(line: String, base := {}) -> Dictionary:
	var toks := _tokens(line)
	var kind := ""
	var tweak := {}
	var colour := ""
	var vein := ""
	var unknown := []
	var ops := []   # [what, amount] in order
	var strength := 1.0
	var said := []
	var i := 0
	while i < toks.size():
		var w: String = toks[i]
		# a colour of two or three words glued ("dark red" -> "darkred", "sky blue" -> "skyblue")
		var glued := ""
		var take := 0
		for k in [3, 2]:
			if i + k <= toks.size():
				var j := "".join(toks.slice(i, i + k))
				if COLOURS.has(j):
					glued = j
					take = k
					break
		if glued != "":
			var is_vein: bool = i + take < toks.size() and VEIN_WORDS.has(toks[i + take])
			if is_vein:
				vein = colour_of(glued)
				said.append("%s veins" % glued)
				i += take + 1
			else:
				colour = colour_of(glued)
				said.append(glued)
				i += take
			continue
		var c := colour_of(w)
		if c != "":
			if i + 1 < toks.size() and VEIN_WORDS.has(toks[i + 1]):
				vein = c
				said.append("%s veins" % w)
				i += 2
				continue
			colour = c
			said.append(w)
			i += 1
			continue
		if STRENGTH.has(w):
			strength = float(STRENGTH[w])
			i += 1
			continue
		if KINDS.has(w):
			kind = String(KINDS[w][0])
			said.append(kind)
			strength = 1.0
			i += 1
			continue
		if MODS.has(w):
			var m: Array = MODS[w]
			ops.append([String(m[0]), float(m[1]), strength])
			said.append(w if strength == 1.0 else "%s (x%s)" % [w, snappedf(absf(strength), 0.1)])
			strength = 1.0
			i += 1
			continue
		if VEIN_WORDS.has(w) or FILLER.has(w):
			i += 1
			continue
		unknown.append(w)
		i += 1
	var res := {"ok": false, "spec": {}, "unknown": unknown, "said": ", ".join(said)}
	var from_base := not (base as Dictionary).is_empty()
	if kind == "" and colour == "" and ops.is_empty() and vein == "":
		return res
	if kind == "" and colour == "" and not from_base and vein == "":
		# only modifiers and nothing to change: a bare "worn" has no material to wear
		res["ok"] = false
		return res
	var sp: Dictionary
	if kind != "":
		sp = {"kind": kind}
		if from_base and String(base.get("kind", "")) == kind:
			sp = (base as Dictionary).duplicate()   # "oak" again keeps what the oak already had, then the words edit it
	elif from_base:
		sp = (base as Dictionary).duplicate()
	else:
		sp = {"kind": "plastic"}   # a colour alone: plain plastic in that colour
	var ns := MaterialMaker.norm(sp)
	if ns.is_empty():
		return res
	if colour != "":
		ns["color"] = colour
	if vein != "":
		if ns["kind"] == "marble":
			ns["vein"] = vein
		elif colour == "":
			ns["color"] = vein
	for op in ops:
		var what: String = op[0]
		var amt: float = op[1]
		var st: float = op[2]
		match what:
			"dark":
				ns["color"] = _lighten(String(ns["color"]), amt * st)
			"warm":
				ns["color"] = _warm(String(ns["color"]), amt * st)
			"wear":
				if amt < -1.0:
					ns["wear"] = 0.0
				else:
					ns["wear"] = clampf(float(ns["wear"]) + amt * st, 0.0, 1.0)
			"gloss":
				ns["gloss"] = clampf(float(ns["gloss"]) + amt * st, 0.0, 1.0)
			"gloss_set":
				ns["gloss"] = float(amt)
			"polish":
				ns["gloss"] = float(amt)
				ns["brushed"] = 0
			"brushed":
				ns["brushed"] = 1
	var out := MaterialMaker.norm(ns)
	res["ok"] = true
	res["spec"] = out
	return res


## mix toward white (amt > 0) or black (amt < 0)
static func _lighten(html: String, amt: float) -> String:
	var c := Color(html)
	var t := Color.WHITE if amt > 0.0 else Color.BLACK
	return "#" + c.lerp(t, absf(amt)).to_html(false)


## warmer: red up, blue down; cooler: the other way
static func _warm(html: String, amt: float) -> String:
	var c := Color(html)
	c.r = clampf(c.r + 0.1 * amt, 0.0, 1.0)
	c.b = clampf(c.b - 0.1 * amt, 0.0, 1.0)
	return "#" + c.to_html(false)


## a spec in plain words ("oak, #a9794a, gloss 35%, wear 0%")
static func describe(spec: Dictionary) -> String:
	var s := MaterialMaker.norm(spec)
	if s.is_empty():
		return "no material"
	var d := "%s, %s, gloss %d%%" % [String(MaterialMaker.DEFS[s["kind"]]["label"]).to_lower(), s["color"], roundi(float(s["gloss"]) * 100.0)]
	if float(s["wear"]) > 0.0:
		d += ", worn %d%%" % roundi(float(s["wear"]) * 100.0)
	return d
