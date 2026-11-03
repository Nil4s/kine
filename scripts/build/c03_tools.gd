## C03 (complaints #235, #508, #323): three small opt-in tools for Part / Easy. Pure helpers (no scene tree); the chips are in scripts/easy_part_c03.gd.
##   1 JOIN / NEW BODY   rec["pull_new"] = true: the next Pull it up makes its own body instead of joining (default false: a pull joins as it always did).
##                       set_op(rec, f, "new"|"join") flips a pull step that is already made.
##   2 MIRROR ANYWHERE   a mirror step's "plane" may be a plane step's id: a face plane (Draw on a face) or an angle plane (angle_plane: the middle plane
##                       turned about the upright axis). part.gd resolves it with resolve_plane; the three base planes behave as before.
##   3 PRINTER PRESETS   PRESETS: a printer's name and its clearance in mm. apply(rec, i) writes rec["fit_mm"] (read by holes, lids, fasteners) and
##                       rec["printer_preset"] (the name), so every fit and clearance feature takes the printer's gap.
extends RefCounted

const Part := preload("res://scripts/build/part.gd")

const PRESETS := [
	{"name": "Resin", "clear": 0.1},
	{"name": "Bambu PLA", "clear": 0.15},
	{"name": "Prusa PETG", "clear": 0.2},
	{"name": "Ender FDM", "clear": 0.3},
]


# ---------------------------------------------------------------- 1 join / new body

static func pull_new(rec: Dictionary) -> bool:
	return bool(rec.get("pull_new", false))


## the Pull rule (scripts/easy_part_pull.gd _pull_rule) with the user's choice applied: "New body" makes the pull its own solid
static func ruled(rec: Dictionary, rule: Dictionary) -> Dictionary:
	if not pull_new(rec) or String(rule.get("op", "")) == "cut":
		return rule
	var r := rule.duplicate(true)
	r["op"] = "new"
	r["sits_on"] = false
	return r


## flips the op of an already-made pull step; a cut stays a cut. Returns "" or why not
static func set_op(f: Dictionary, op: String) -> String:
	if String(f.get("t", "")) != "extrude" or String(f.get("op", "")) == "cut":
		return "only a pull that adds material can be a new body"
	f["op"] = op
	if op == "new":
		f.erase("into")
	return ""


## the newest extrude step that adds material ({} = none)
static func last_pull(rec: Dictionary) -> Dictionary:
	var feats: Array = rec.get("features", [])
	for i in range(feats.size() - 1, -1, -1):
		var f: Dictionary = feats[i]
		if String(f.get("t", "")) == "extrude":
			return f if String(f.get("op", "")) != "cut" else {}
	return {}


# ---------------------------------------------------------------- 2 mirror anywhere

## a plane through the middle, turned deg about the upright axis (0 = the usual left/right mirror). Added to rec; returns its id
static func angle_plane(rec: Dictionary, deg: float, mm := 0.0) -> String:
	var pf := Part.new_feature(rec, "plane", {"from": "angle", "base": "right", "edge": "y", "deg": deg, "mm": mm})
	rec["features"].append(pf)
	return String(pf["id"])


## the id of the newest plane step that lies on a face (Draw on a face makes one); "" = none
static func face_plane(rec: Dictionary) -> String:
	var feats: Array = rec.get("features", [])
	for i in range(feats.size() - 1, -1, -1):
		var f: Dictionary = feats[i]
		if String(f.get("t", "")) == "plane" and f.has("out"):
			return String(f["id"])
	return ""


## a mirror step across plane_id (a base plane's name or a plane step's id); added to rec; returns it
static func mirror_across(rec: Dictionary, plane_id: String) -> Dictionary:
	var f := Part.new_feature(rec, "mirror", {"plane": plane_id, "op": "join"})
	rec["features"].append(f)
	return f


# ---------------------------------------------------------------- 3 printer presets

static func index_of(rec: Dictionary) -> int:
	var nm := String(rec.get("printer_preset", ""))
	for i in PRESETS.size():
		if String(PRESETS[i]["name"]) == nm:
			return i
	return -1


static func apply(rec: Dictionary, i: int) -> void:
	var p: Dictionary = PRESETS[clampi(i, 0, PRESETS.size() - 1)]
	rec["fit_mm"] = float(p["clear"])
	rec["printer_preset"] = String(p["name"])


## the next preset after the part's current one (the first when none is set)
static func next_index(rec: Dictionary) -> int:
	return (index_of(rec) + 1) % PRESETS.size()


static func words(rec: Dictionary) -> String:
	var i := index_of(rec)
	if i < 0:
		return "Printer: none"
	return "Printer: %s %s mm" % [PRESETS[i]["name"], str(PRESETS[i]["clear"])]
