## build_stage.gd - THE HOUSE ON STAGE (docs/BUILD_PLAN.md phase 1d, section 5). "Use in a scene" makes the building a SET: a prop
## kind "building:<name>" registered from the record (Props.register_building: solids = Building.collision_boxes, so the walls
## block, the floor slab holds the feet and the DOORWAY IS OPEN), one prop {"kind", identity} in the scene, and a NAMED POINT per
## door ("front door": Building.anchors) that a walk can target. The kind is re-registered from the record on load
## (Scene.from_dict) and after every BUILD edit (BuildUI.sync), so the set follows the house.
class_name BuildStage
extends RefCounted

const WALK_SPEED := 1.3          # m/s: the speed PathWalk's walk is measured at
const OUTSIDE := 1.8             # m: the walk starts this far outside the door ...
const INSIDE := 1.6              # ... and ends this far inside


static func kind_of_building(b: Dictionary) -> String:
	return "building:" + String(b.get("name", "Untitled"))


## register (or refresh) the house's kind from its record; returns the kind ("" for no record / a read-only newer one)
static func register(b: Dictionary) -> String:
	if b.is_empty() or bool(b.get("readonly", false)) or b.get("rooms", []).is_empty():
		return ""
	var kind := kind_of_building(b)
	var pc := BuildPieces.collision_all(b)   # 1f: the pieces: boxes + tops, and the stairs' ramps
	Props.register_building(kind, Building.collision_boxes(b) + pc["boxes"], Building.supports(b) + pc["supports"], pc["ramps"])
	return kind


## a file's prop names this kind: register it when the record is the house it names
static func register_named(b: Dictionary, kind: String) -> void:
	if not b.is_empty() and kind == kind_of_building(b):
		register(b)


## the index of the house's prop in a scene's props, -1 when it is not in the set
static func prop_index(S: Scene) -> int:
	if S.building.is_empty():
		return -1
	var kind := kind_of_building(S.building)
	for i in S.props.size():
		if String(S.props[i]["kind"]) == kind:
			return i
	return -1


## after a BUILD edit: the house's prop (if the scene has one) follows the record. true when it did
static func refresh(S: Scene) -> bool:
	if prop_index(S) < 0:
		return false
	return register(S.building) != ""


## put the house in the set (once): registers the kind and adds the prop at the origin. Returns the kind ("" when there is no house)
static func use(S: Scene) -> String:
	var kind := register(S.building)
	if kind == "":
		return ""
	if prop_index(S) < 0:
		S.props.append(Props.make(kind, Transform3D.IDENTITY))
	return kind


## the walk through a named point: the points of the path, from outside to inside, straight through the door's middle
static func walk_points(b: Dictionary, name: String) -> Array:
	var a := Building.anchor(b, name)
	if a.is_empty():
		return []
	var pos: Vector3 = a["pos"]
	var out: Vector3 = a["out"]
	return [pos + out * OUTSIDE, pos, pos - out * INSIDE]


## "Walk through the front door": PathWalk's walk cards through the point, as a scene dictionary that carries the house (its
## record and its prop) and the kind; {"ok": false, "why"} when there is no such point
static func walk_scene(S: Scene, B: Body, name: String) -> Dictionary:
	var pts := walk_points(S.building, name)
	if pts.is_empty():
		return {"ok": false, "why": "there is no point called \"%s\": put a door in the house first" % name}
	var r := PathWalk.build(pts, WALK_SPEED)
	if not r["ok"]:
		return r
	var cur := S.to_dict(B, false)
	var d: Dictionary = r["scene"]
	d["kind"] = S.kind
	d["building"] = cur.get("building", {})
	d["props"] = cur.get("props", [])
	d["scene"] = "walk through the %s" % name
	r["scene"] = d
	return r


## the points a fighter walks through, for the STAGE panel: [[name, "outside -> inside" text]]
static func door_names(b: Dictionary) -> Array:
	return Building.anchors(b).map(func(a): return String(a["name"]))
