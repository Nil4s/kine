## build_piece_kinds.gd - a BUILD piece (scripts/build/build_pieces.gd) as a free-standing prop kind "piece:<kind>", so the object
## library can put one in the set like any other prop (main._prop_add): its solids are the piece's boxes at their default numbers,
## its supports their tops, a ramp is a wedge. The kind is registered on first use, and again when a scene that names one loads
## (scene.gd). "piece": true keeps it out of the Add prop menu and out of "My models".
class_name BuildPieceKinds
extends RefCounted

const PREFIX := "piece:"


static func kind_of(piece: String) -> String:
	return PREFIX + piece


static func is_piece_kind(kind: String) -> bool:
	return kind.begins_with(PREFIX) and BuildPieces.DEFS.has(kind.trim_prefix(PREFIX))


## register the kind when it is not yet (a piece with default numbers, on the floor of a house of the default floor height);
## returns the kind, "" for an unknown piece
static func ensure(piece: String) -> String:
	var kind := PREFIX + piece
	if Props.EXTRA.has(kind):
		return kind
	if not BuildPieces.DEFS.has(piece):
		return ""
	var b := Building.make("piece")
	var p := BuildPieces.make("p1", piece, 0.0, 0.0)
	var solids := []
	var supports := []
	var wedges := []
	if piece == "ramp":
		var w := BuildPieces.value(p, "w")
		var d := BuildPieces.value(p, "d")
		var h := BuildPieces.value(p, "h")
		wedges.append([Vector3(0, h * 0.5, 0), Vector3(w, h, d)])   # the library's own ramp: a wedge rising toward +Z
	else:
		for bx in BuildPieces.local_boxes(b, p):
			var a: AABB = bx
			solids.append([a.get_center(), a.size])
			supports.append([a.end.y, Vector2(a.get_center().x, a.get_center().z), Vector2(a.size.x, a.size.z)])
	var def: Dictionary = BuildPieces.DEFS[piece]
	var e := {"label": "%s (from BUILD)" % String(def["label"]), "solids": solids, "supports": supports, "piece": true}
	if not wedges.is_empty():
		e["wedges"] = wedges
	Props.EXTRA[kind] = e
	return kind
