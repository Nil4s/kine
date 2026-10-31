class_name BuildStarters
extends RefCounted
## The three starter buildings of the chooser's "From a template" card (B1). Each one is a sentence for BuildWords, so the record
## is exactly what the words path makes: nothing is stored on disk. A starter opened on BUILD is a normal building: "Save house"
## puts it in My houses. The texts are mouse-only words (no key names).

const LIST := [
	{"id": "cottage", "name": "Cottage", "say": "One floor, a front door, 2 windows, a pitched roof.",
		"text": "a cottage 6 x 4 m with a front door and 2 windows and a gable roof"},
	{"id": "flat", "name": "Two-floor flat", "say": "Two floors, one room on each, a front door, 2 windows, a flat roof.",
		"text": "a 2-floor flat 8 x 6 m with a front door and 2 windows and a flat roof"},
	{"id": "shop", "name": "Shop front", "say": "One floor, a front door, 2 windows, a flat roof, 8 m wide.",
		"text": "a building 8 x 5 m with a front door and 2 windows and a flat roof"},
	# P145 SCENE LIBRARY: a room and an outdoor set (a yard), added after the houses so the houses keep their list places
	{"id": "room", "name": "Room", "say": "One room 4 x 3 m, a front door, 1 window, a flat roof.",
		"text": "a building 4 x 3 m with a front door and 1 window and a flat roof"},
	{"id": "yard", "name": "Yard", "say": "An open yard 6 x 4 m: a low edge, a fence along the back, a table and 2 benches. No door, no roof.",
		"text": "a building 6 x 4 m with a fence along the back wall and a table and 2 benches in the middle", "outdoor": true},
]


## the starter with that id ({} when there is none)
static func by_id(id: String) -> Dictionary:
	for s in LIST:
		if String(s["id"]) == id:
			return s
	return {}


## a new record of the starter (each call builds it again); {} for an unknown id or a sentence that does not parse
static func build(id: String) -> Dictionary:
	var s := by_id(id)
	if s.is_empty():
		return {}
	var P := BuildWords.parse(String(s["text"]))
	if not bool(P.get("ok", false)) or not P.has("plan"):
		return {}
	var rec: Dictionary = BuildWords.make_building_full(P["plan"], String(s["name"]))["b"]
	return _outdoor(rec) if bool(s.get("outdoor", false)) else rec


## P145: an outdoor set keeps its room as a 30 cm edge (not a wall), with no door, window or roof
static func _outdoor(b: Dictionary) -> Dictionary:
	for r in b["rooms"]:
		r["height"] = 0.3
	b["openings"] = []
	b.erase("roof")
	return b
