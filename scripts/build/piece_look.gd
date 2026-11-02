class_name PieceLook
extends RefCounted
## s231 TEMPLE LOOK (Friday plan 231): the materials of a building's PIECES. Item 223 made the material library (scripts/material_maker.gd);
## this file says which material a piece of a building wears BY DEFAULT and lets the user change it by piece kind, in words or on chips.
##
## A PIECE KIND is what a body is in a building: roof, ridge (ridge beasts and ornaments), column, beam (the bracket band), platform, stair,
## rail (balustrade), paving, wall, plaque, plaque_letters, door, lattice, and the garden (ground, hedge, trunk, canopy), wall_base, wall_cap.
## A body has a kind when (1) the step that made it said so (a roof step's shell is a roof, its ridge trims are ridges; an ornament is a
## ridge piece: look key "hint"), else (2) its NAME says so ("Column 3", "Lower brackets", "Stair rail": kind_of_name).
##
## DEFAULTS BY STYLE. A Part record may carry "style": "temple" | "none". With no "style" a part is a temple when its name says so (temple,
## pagoda, pavilion, Chinese, shrine) or it has a xieshan roof. In a temple every body that no one painted wears its kind's material
## (DEFAULTS); a body with an appear step (any colour or material the user chose, a Custom paint of a script) keeps that. A part with no
## style keeps its old look exactly: finish() does nothing, so ordinary houses are unchanged.
##
## CHANGING IT. apply() adds one appear step per body of the kind (the caller makes ONE undo step of them); parse() reads "red lacquer
## columns", "glazed green tiles", "white marble rails", "teal beams" into {kind, spec}. The appear steps are in the record: saved, replayed.

const TEMPLE_WORDS := ["temple", "pagoda", "pavilion", "chinese", "shrine", "xieshan", "dougong"]
const KINDS := ["roof", "ridge", "column", "beam", "platform", "stair", "rail", "paving", "wall", "plaque", "plaque_frame", "plaque_letters", "door", "lattice",
	"ground", "hedge", "trunk", "canopy", "wall_base", "wall_cap"]
const LABELS := {"roof": "Roof tiles", "ridge": "Ridge beasts", "column": "Columns", "beam": "Beams and brackets", "platform": "Platform",
	"stair": "Stairs", "rail": "Rails", "paving": "Paving", "wall": "Walls", "plaque": "Plaque", "plaque_frame": "Plaque border", "plaque_letters": "Plaque letters", "door": "Doors",
	"lattice": "Lattice", "ground": "Ground", "hedge": "Hedges", "trunk": "Trunks", "canopy": "Leaves", "wall_base": "Wall base", "wall_cap": "Wall cap"}
## the chips on the Materials page: [kind, label]
const CHIPS := [["roof", "Roof"], ["ridge", "Ridge"], ["column", "Columns"], ["beam", "Beams"], ["platform", "Platform"], ["rail", "Rails"],
	["stair", "Stairs"], ["paving", "Paving"], ["wall", "Walls"], ["plaque", "Plaque"], ["door", "Doors"]]
## the material of a kind in a temple: MaterialMaker specs (norm() fills the rest)
const DEFAULTS := {
	"roof": {"kind": "tile", "color": "#bd5418", "scale": 1100.0, "gloss": 0.88, "wear": 0.1, "seed": 3},                        # glazed terracotta tile, ribs and rows
	"ridge": {"kind": "tile", "color": "#d6921a", "scale": 440.0, "gloss": 0.92, "wear": 0.05, "seed": 5},                      # the same glaze, golden
	"column": {"kind": "lacquer", "color": "#a3140f", "scale": 160.0, "gloss": 0.7, "wear": 0.16, "seed": 7},                   # red lacquer, a slight sheen, slight wear
	"beam": {"kind": "caihua", "color": "#1b6f73", "scale": 400.0, "gloss": 0.5, "seed": 2},                                    # teal paint with gold lines
	"platform": {"kind": "marble", "color": "#d9d7d0", "scale": 900.0, "gloss": 0.75, "seed": 4},
	"stair": {"kind": "marble", "color": "#d4d2cb", "scale": 700.0, "gloss": 0.7, "seed": 6},
	"rail": {"kind": "marble", "color": "#efeeea", "scale": 500.0, "gloss": 0.8, "seed": 8},
	"paving": {"kind": "slabs", "color": "#bcb9b0", "scale": 2400.0, "gloss": 0.3, "seed": 2},
	"wall": {"kind": "plaster", "color": "#9b2c22", "scale": 700.0, "gloss": 0.07, "wear": 0.12, "seed": 9},                    # red plaster
	"plaque": {"kind": "lacquer", "color": "#1a110c", "scale": 160.0, "gloss": 0.85, "seed": 11},                               # dark lacquer
	"plaque_letters": {"kind": "brass", "color": "#e0aa22", "scale": 120.0, "gloss": 0.6, "metal": 0.55, "seed": 12},           # gilt (metal 0.55: gold leaf on a board, not a mirror)
	"plaque_frame": {"kind": "brass", "color": "#e0aa22", "scale": 120.0, "gloss": 0.6, "metal": 0.55, "seed": 12},
	"door": {"kind": "lacquer", "color": "#6b1511", "scale": 160.0, "gloss": 0.6, "wear": 0.1, "seed": 13},
	"lattice": {"kind": "oak", "color": "#4d2c1d", "scale": 120.0, "gloss": 0.3, "warp": 0.0, "seed": 14},
	"ground": {"kind": "grass", "color": "#5a9a30", "scale": 500.0, "gloss": 0.1, "seed": 15},
	"hedge": {"kind": "grass", "color": "#2d5e2a", "scale": 300.0, "gloss": 0.1, "seed": 16},
	"trunk": {"kind": "oak", "color": "#5b3f26", "scale": 300.0, "gloss": 0.15, "warp": 0.5, "seed": 17},
	"canopy": {"kind": "grass", "color": "#d9a21b", "scale": 250.0, "gloss": 0.1, "seed": 18},                                  # golden leaves
	"wall_base": {"kind": "granite", "color": "#9a9892", "scale": 500.0, "gloss": 0.4, "seed": 19},
	"wall_cap": {"kind": "tile", "color": "#bd5418", "scale": 700.0, "gloss": 0.88, "seed": 20},
	"other": {"kind": "plaster", "color": "#d6cdbd", "scale": 600.0, "gloss": 0.07, "seed": 21},                                # a body of no known kind: a plain warm plaster, never a flat colour
}
## words -> kind, for the user's sentence (a piece noun, singular and plural). A noun is taken OUT of the sentence before the rest is read as a material
const NOUNS := {
	"column": "column", "columns": "column", "pillar": "column", "pillars": "column", "post": "column", "posts": "column",
	"roof": "roof", "roofs": "roof", "tile": "roof", "tiles": "roof",
	"ridge": "ridge", "ridges": "ridge", "beast": "ridge", "beasts": "ridge", "ornament": "ridge", "ornaments": "ridge", "finial": "ridge", "finials": "ridge",
	"beam": "beam", "beams": "beam", "bracket": "beam", "brackets": "beam", "corbel": "beam", "corbels": "beam", "band": "beam",
	"platform": "platform", "platforms": "platform", "terrace": "platform", "plinth": "platform", "podium": "platform",
	"stair": "stair", "stairs": "stair", "step": "stair", "steps": "stair", "staircase": "stair",
	"rail": "rail", "rails": "rail", "railing": "rail", "railings": "rail", "balustrade": "rail", "balustrades": "rail",
	"paving": "paving", "pavement": "paving", "path": "paving", "paths": "paving", "courtyard": "paving", "floor": "paving",
	"wall": "wall", "walls": "wall", "hall": "wall",
	"plaque": "plaque", "plaques": "plaque", "signboard": "plaque", "sign": "plaque",
	"letters": "plaque_letters", "door": "door", "doors": "door", "gate": "door", "gates": "door",
	"lattice": "lattice", "window": "lattice", "windows": "lattice",
	"hedge": "hedge", "hedges": "hedge", "shrub": "hedge", "shrubs": "hedge", "bush": "hedge", "bushes": "hedge",
	"trunk": "trunk", "trunks": "trunk", "canopy": "canopy", "foliage": "canopy", "leaves": "canopy",
}
## a noun that is also a material word stays in the sentence ("glazed green tiles" is the material tile, and it is the roof's)
const KEEP_AS_MATERIAL := ["tile", "tiles"]

static var _fields := {}   # spec json -> appear fields (the look numbers of a spec, made once)


# ---------------------------------------------------------------- style and kind

## "temple" or "" for a part record: its own "style" when it has one, else what its name and roofs say
static func style_of(rec: Dictionary) -> String:
	var st := String(rec.get("style", ""))
	if st == "none":
		return ""
	if st != "":
		return st
	var nm := String(rec.get("name", "")).to_lower()
	for w in TEMPLE_WORDS:
		if nm.contains(String(w)):
			return "temple"
	for f in rec.get("features", []):
		if String((f as Dictionary).get("t", "")) == "roof" and String((f as Dictionary).get("type", "")) == "xieshan":
			return "temple"
	return ""


## the kind a body NAME says ("Column 3", "Stair rail", "Plaque letters 2"), "" when it says none
static func kind_of_name(nm: String) -> String:
	var toks := []
	var cur := ""
	for ch in nm.to_lower():
		if ch >= "a" and ch <= "z":
			cur += ch
		else:
			if cur != "":
				toks.append(cur)
			cur = ""
	if cur != "":
		toks.append(cur)
	if toks.is_empty():
		return ""
	var has := func(ws: Array) -> bool:
		for w in ws:
			if toks.has(w):
				return true
		return false
	if has.call(["letters", "letter", "characters"]):
		return "plaque_letters"
	if has.call(["frame", "border"]) and has.call(["plaque", "plaques", "signboard"]):
		return "plaque_frame"   # the gilded border of a plaque
	if has.call(["plaque", "plaques", "signboard"]):
		return "plaque"
	if has.call(["cap", "coping"]):
		return "wall_cap"
	if toks.has("wall") and toks.has("base"):
		return "wall_base"
	if has.call(["rail", "rails", "railing", "railings", "balustrade", "handrail"]):
		return "rail"
	if has.call(["ridge", "beast", "beasts", "chiwen", "finial", "dragon", "ornament", "ornaments", "lotus", "lion"]):
		return "ridge"
	if has.call(["bracket", "brackets", "beam", "beams", "corbel", "corbels", "dougong", "architrave", "band", "purlin"]):
		return "beam"
	if has.call(["roof", "roofs", "tile", "tiles", "rib", "ribs", "hip", "eave", "eaves"]):
		return "roof"
	if has.call(["column", "columns", "pillar", "pillars", "post"]):
		return "column"
	if has.call(["stair", "stairs", "step", "steps", "staircase"]):
		return "stair"
	if has.call(["platform", "terrace", "plinth", "podium", "foundation"]):
		return "platform"
	if has.call(["paving", "pavement", "path", "slab", "slabs", "courtyard", "flagstones"]):
		return "paving"
	if has.call(["door", "doors", "gate"]):
		return "door"
	if has.call(["lattice", "window", "windows", "screen"]):
		return "lattice"
	if has.call(["wall", "walls", "hall"]):
		return "wall"
	if has.call(["hedge", "shrub", "bush"]):
		return "hedge"
	if has.call(["trunk", "bark"]):
		return "trunk"
	if has.call(["canopy", "leaves", "foliage"]):
		return "canopy"
	if has.call(["grass", "lawn", "ground"]):
		return "ground"
	return ""


## the kind of body bi from the looks a replay keeps: the step's hint, else its name
static func kind_at(looks: Array, bi: int) -> String:
	if bi < 0 or bi >= looks.size() or looks[bi] == null:
		return ""
	var l: Dictionary = looks[bi]
	var h := String(l.get("hint", ""))
	if h != "":
		return h
	var nm := String(l.get("name", ""))
	return kind_of_name(nm) if nm != "" else ""


## the kinds a roof step's bodies are: the shell is the roof; the ridge and hip trims are ridge pieces; the eave edge is roof
static func roof_hints(f: Dictionary, count: int) -> Array:
	var out := ["roof"]
	var want_eave := bool(f.get("eave", false))
	for k in range(1, count):
		out.append("roof" if (want_eave and k == count - 1) else "ridge")
	return out


## step 1 of a replay arm: every body the step just made (from index `from`) gets the kind its step says. looks is padded to bodies.
static func stamp(looks: Array, from: int, kinds: Array) -> void:
	for k in kinds.size():
		var bi := from + k
		if bi >= looks.size():
			break
		var l: Dictionary = looks[bi] if looks[bi] != null else Part.look_at(looks, bi).duplicate()
		if String(l.get("hint", "")) != String(kinds[k]):
			l = l.duplicate()
			l["hint"] = String(kinds[k])
			looks[bi] = l


# ---------------------------------------------------------------- the defaults

## the default material spec of a kind in a style ({} when the style has none: an ordinary house keeps its old look)
static func default_spec(style: String, kind: String) -> Dictionary:
	if style != "temple":
		return {}
	return (DEFAULTS[kind] as Dictionary).duplicate() if DEFAULTS.has(kind) else (DEFAULTS["other"] as Dictionary).duplicate()


## the look (Part look numbers + the spec) of a spec, made once per spec
static func look_for(spec: Dictionary, hint: String, name: String) -> Dictionary:
	var key := JSON.stringify(spec, "", true)
	if not _fields.has(key):
		_fields[key] = MaterialMaker.appear_fields(spec)
	var f: Dictionary = _fields[key]
	if f.is_empty():
		return {}
	var c: Array = f["color"]
	var l := {"c": Color(float(c[0]), float(c[1]), float(c[2])), "rough": float(f["rough"]), "metal": float(f["metal"]), "alpha": float(f["alpha"]),
		"preset": "Style", "mat": f["mat"]}
	if hint != "":
		l["hint"] = hint
	if name != "":
		l["name"] = name
	return l


## the end of a replay: in a temple every body no one painted wears its kind's material. looks: one entry per body (null = default)
static func finish(rec: Dictionary, looks: Array) -> void:
	var style := style_of(rec)
	if style == "":
		return
	for bi in looks.size():
		var l: Variant = looks[bi]
		if l != null and not (String((l as Dictionary).get("preset", "Default")) in ["Default", "Style"]):
			continue   # painted by a step: the user's (or a script's) choice stands
		var kind := kind_at(looks, bi)
		var spec := default_spec(style, kind)
		var nl := look_for(spec, kind, name_of(looks, bi))
		if not nl.is_empty():
			looks[bi] = nl


static func name_of(looks: Array, bi: int) -> String:
	if bi >= 0 and bi < looks.size() and looks[bi] != null:
		return String((looks[bi] as Dictionary).get("name", ""))
	return ""


## how many bodies of a replay result have no made material (a plain albedo-only look): the count a temple wants at 0
static func plain_count(res: Dictionary) -> int:
	var n := 0
	for l in res.get("body_looks", []):
		var m: Variant = (l as Dictionary).get("mat", null)
		if not (m is Dictionary) or (m as Dictionary).is_empty():
			n += 1
	return n


# ---------------------------------------------------------------- changing it

## the bodies of a replay result that are of this kind
static func bodies_of(res: Dictionary, kind: String) -> Array:
	var out := []
	var ks: Array = res.get("body_kinds", [])
	for i in ks.size():
		if String(ks[i]) == kind:
			out.append(i)
	return out


## one appear step per body of the kind, appended to the record (the caller takes ONE undo step, then replays). Returns how many bodies
static func apply(rec: Dictionary, res: Dictionary, kind: String, spec: Dictionary) -> int:
	var fields := MaterialMaker.appear_fields(spec)
	if fields.is_empty():
		return 0
	var bs := bodies_of(res, kind)
	for bi in bs:
		var f := fields.duplicate(true)
		f["name"] = "Appearance%d" % (Part.count_of(rec, "appear") + 1)
		f["body"] = int(bi)
		(rec["features"] as Array).append(Part.new_feature(rec, "appear", f))
	return bs.size()


## the style set on the record ("temple" | "none" | "" = by the name): the caller takes the undo step
static func set_style(rec: Dictionary, style: String) -> void:
	if style == "":
		rec.erase("style")
	else:
		rec["style"] = style


## "red lacquer columns", "glazed green tiles", "white marble rails" -> {"ok", "kind" ("" = no piece named), "spec", "unknown", "said"}.
## The piece noun is taken out; the rest is read by MaterialWords with the piece's default material as the thing it edits ("red columns" =
## the column lacquer, red; "worn roof" = the roof tile, worn)
static func parse(line: String) -> Dictionary:
	var toks := []
	var s := line.to_lower()
	for ch in [",", ";", "/", "&", "+", "(", ")", "."]:
		s = s.replace(ch, " ")
	for t in s.split(" ", false):
		toks.append(String(t))
	var kind := ""
	var rest := []
	for t in toks:
		var w := String(t)
		if NOUNS.has(w) and kind == "":
			kind = String(NOUNS[w])
			if KEEP_AS_MATERIAL.has(w):
				rest.append(w)
			continue
		rest.append(w)
	var base := {}
	if kind != "":
		base = (DEFAULTS[kind] as Dictionary).duplicate() if DEFAULTS.has(kind) else {}
	var r := MaterialWords.parse(" ".join(rest), MaterialMaker.norm(base) if not base.is_empty() else {})
	r["kind"] = kind
	return r
