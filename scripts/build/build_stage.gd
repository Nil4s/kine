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
const CLEAR_MARGIN := 0.05       # m: a doorway must stand this far over the fighter's height (the walk is refused below it)
const CLEAR_EPS := 0.0005        # m: float slack (half a millimetre), so a door exactly CLEAR_MARGIN over the body passes


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


## a saved record becomes the scene's house. A different house's prop in the set goes (a scene has one house); the same house's stays
static func swap_in(S: Scene, rec: Dictionary) -> void:
	var i := prop_index(S)
	if i >= 0 and kind_of_building(S.building) != kind_of_building(rec):
		S.props.remove_at(i)
	S.building = rec


## put the house in the set (once): registers the kind and adds the prop at the origin. Returns the kind ("" when there is no house).
## With a Part record: the part is put in the set as a prop of its own (one per call), made from its tessellation; "" when it has no solid
static func use(S: Scene, part := {}) -> String:
	if not part.is_empty():
		var res := Part.replay(part)
		if res["mesh"] == null:
			return ""
		var pk := "part:%s#%s" % [String(part.get("name", "Part")), str(hash(JSON.stringify(part)))]
		Props.register_part(pk, res["mesh"])
		var pp := Props.make(pk, Transform3D.IDENTITY)
		pp["part_rec"] = part.duplicate(true)
		S.props.append(pp)
		return pk
	var kind := register(S.building)
	if kind == "":
		return ""
	if prop_index(S) < 0:
		S.props.append(Props.make(kind, Transform3D.IDENTITY))
	return kind


## a Part prop of a scene file (scene.gd): its kind is made again from its record; "" when it has no solid (the prop is skipped)
static func restore_part(kind: String, rec: Dictionary) -> String:
	var res := Part.replay(rec)
	if res["mesh"] == null:
		return ""
	Props.register_part(kind, res["mesh"])
	return kind


## the walk through a named point: the points of the path, from outside to inside, straight through the door's middle
static func walk_points(b: Dictionary, name: String) -> Array:
	var a := Building.anchor(b, name)
	if a.is_empty():
		return []
	var pos: Vector3 = a["pos"]
	var out: Vector3 = a["out"]
	return [pos + out * OUTSIDE, pos, pos - out * INSIDE]


## the fighter's height (m) from the scene's body: the default body when it has no stature of its own
static func stature_of(B: Body) -> float:
	return float(B.body.get("stature", Proportions.DEFAULT_STATURE))


## does the fighter fit under the named doorway with CLEAR_MARGIN to spare? {"ok", "gap_cm" (the doorway's height less the
## fighter's, cm: negative = too low), "why" (plain words, "" when it fits)}. A name with no doorway fits (the walk refuses it anyway)
static func clearance(b: Dictionary, name: String, stature: float) -> Dictionary:
	var a := Building.anchor(b, name)
	if a.is_empty():
		return {"ok": true, "gap_cm": 0.0, "why": ""}
	var gap := float(a["clear"]) - stature
	var ok := gap >= CLEAR_MARGIN - CLEAR_EPS
	var why := ""
	if not ok:
		var short := "%.0f cm shorter than the fighter" % (-gap * 100.0) if gap < 0.0 else "only %.0f cm over the fighter's head, %.0f cm is needed" % [gap * 100.0, CLEAR_MARGIN * 100.0]
		why = "The %s is %.2f m high and the fighter is %.2f m tall: %s. Make the door taller in BUILD (Door height), then walk again" % [
			name, float(a["clear"]), stature, short]
	return {"ok": ok, "gap_cm": gap * 100.0, "why": why}


## "Walk through the front door": PathWalk's walk cards through the point, as a scene dictionary that carries the house (its
## record and its prop) and the kind; {"ok": false, "why"} when there is no such point, or the fighter does not fit under it
static func walk_scene(S: Scene, B: Body, name: String) -> Dictionary:
	var pts := walk_points(S.building, name)
	if pts.is_empty():
		return {"ok": false, "why": "there is no point called \"%s\": put a door in the house first" % name}
	var fit := clearance(S.building, name, stature_of(B))
	if not bool(fit["ok"]):
		return {"ok": false, "why": String(fit["why"])}
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


## STAIRS: the straight stairs of the house, [[piece id, label]] for the STAGE panel's "Walk up the stairs"
static func stairs_list(b: Dictionary) -> Array:
	var out := []
	for p in b.get("pieces", []):
		if String(p["kind"]) == "stairs":
			out.append(String(p["id"]))
	return out


## the height of the stairs' slope under a floor point (the line through the nosings, the floor before the first riser, the floor above after
## the last): the surface a walk's feet are planted on
static func stairs_height(b: Dictionary, p: Dictionary, v: Vector3) -> float:
	var xf := BuildPieces.frame(b, p)
	var l := xf.affine_inverse() * Vector3(v.x, xf.origin.y, v.z)
	var s := BuildPieces.stairs_numbers(b, p)
	var u: float = l.z + float(s["len"]) * 0.5
	if u < 0.0 or absf(l.x) > float(s["w"]) * 0.5 + 0.05:
		return xf.origin.y
	return xf.origin.y + minf(float(s["r"]) + float(s["r"]) / float(s["t"]) * u, float(s["rise"]))


## the walk up the stairs: from OUTSIDE m before the first riser, up the flight's middle, INSIDE m past the head (floor points)
static func stairs_points(b: Dictionary, p: Dictionary) -> Array:
	var xf := BuildPieces.frame(b, p)
	var half := float(BuildPieces.stairs_numbers(b, p)["len"]) * 0.5
	var back := OUTSIDE
	var front := INSIDE
	var inner := BuildPieces.room_inner(b, p)
	if inner.size != Vector2.ZERO:   # the walk stays inside the room: the run-up and the run-out are what the walls leave (less a body's width)
		var dir := xf.basis * Vector3(0, 0, 1)
		var bot := Vector2(xf.origin.x, xf.origin.z) - Vector2(dir.x, dir.z) * half
		var top := Vector2(xf.origin.x, xf.origin.z) + Vector2(dir.x, dir.z) * half
		back = clampf(_room_run(inner, bot, -Vector2(dir.x, dir.z)) - 0.3, 0.3, OUTSIDE)
		front = clampf(_room_run(inner, top, Vector2(dir.x, dir.z)) - 0.3, 0.3, INSIDE)
	return [xf * Vector3(0, 0, -half - back), xf * Vector3(0, 0, -half), xf * Vector3(0, 0, half + front)]


## how far a point can go along an axis direction before it leaves the rectangle
static func _room_run(r: Rect2, from: Vector2, d: Vector2) -> float:
	if absf(d.x) > absf(d.y):
		return r.end.x - from.x if d.x > 0.0 else from.x - r.position.x
	return r.end.y - from.y if d.y > 0.0 else from.y - r.position.y


## "Walk up the stairs": PathWalk's cards with the feet on the slope, as a scene that carries the house (like walk_scene)
static func stairs_scene(S: Scene, B: Body, pid: String) -> Dictionary:
	var p := Building.piece_of(S.building, pid)
	if p.is_empty() or String(p["kind"]) != "stairs":
		return {"ok": false, "why": "there are no straight stairs to walk up: put stairs in the house first"}
	var r := PathWalk.build(stairs_points(S.building, p), WALK_SPEED, PathWalk.HEIGHT, func(v: Vector3): return stairs_height(S.building, p, v))
	if not r["ok"]:
		return r
	var cur := S.to_dict(B, false)
	var d: Dictionary = r["scene"]
	d["kind"] = S.kind
	d["building"] = cur.get("building", {})
	d["props"] = cur.get("props", [])
	d["scene"] = "walk up the stairs"
	r["scene"] = d
	return r


## the points a fighter walks through, for the STAGE panel: [[name, "outside -> inside" text]]
static func door_names(b: Dictionary) -> Array:
	return Building.anchors(b).map(func(a): return String(a["name"]))
