class_name StartExamples
extends RefCounted
## THE EXAMPLES of the start screen (bug7): finished 3D BUILDING parts (and a room) a beginner can open to see what Kine makes. Every one is made
## by the app's OWN builders (PartTemplates for the parts, BuildStarters for the room), written as a scene file of kind "building" in
## res://scenes/examples/ by tools/gen_start_examples.gd, and opened as a COPY (Main._open_example: no path, "<name>_mine"). Nothing here is a
## hand-typed solid: change a builder and run the tool again. The animation examples stay Main.EXAMPLES; examples() lists both.
## Pictures: StartExampleThumbs draws each file's real geometry (Nice picture for a part, the house picture for the room).

const DIR := "res://scenes/examples"
## id, the plain name, the builder: {"t": a PartTemplates id, "p": its numbers} or {"star": diameter mm, "thick": mm} or {"house": a BuildStarters id}
const LIST := [
	{"id": "arduino_uno_box", "name": "Arduino Uno box", "t": "bc_uno"},
	{"id": "phone_stand", "name": "Phone stand", "t": "phone"},
	{"id": "shelf_bracket", "name": "Shelf bracket", "t": "shelf"},
	{"id": "chair", "name": "Chair", "t": "chair"},
	{"id": "pipe_elbow", "name": "Pipe elbow", "t": "elbow"},
	{"id": "pipe_tee", "name": "Pipe T-piece", "t": "tee"},
	{"id": "gear", "name": "Gear", "t": "gear"},
	{"id": "star", "name": "Star", "star": 120.0, "thick": 12.0},
	{"id": "box_with_lid", "name": "Box with lid", "t": "lidbox"},
	{"id": "threaded_rod", "name": "Threaded rod", "t": "rod"},
	{"id": "hinge", "name": "Hinge", "t": "hinge"},
	{"id": "mug", "name": "Mug", "t": "mug"},
	{"id": "crate", "name": "Crate", "t": "crate"},
	{"id": "sword", "name": "Sword", "t": "sword"},
	{"id": "room", "name": "Room", "house": "room"},
]


static func path_of(id: String) -> String:
	return "%s/%s.json" % [DIR, id]


static func entry(id: String) -> Dictionary:
	for e in LIST:
		if String(e["id"]) == id:
			return e
	return {}


## the entry a scene file belongs to ({} for a file that is not one of these)
static func entry_of_path(path: String) -> Dictionary:
	if path.get_base_dir() != DIR:
		return {}
	return entry(path.get_file().get_basename())


## the Part record the builder makes for this entry ({} for the room)
static func part_record(e: Dictionary) -> Dictionary:
	if e.has("t"):
		return PartTemplates.make(String(e["t"]), e.get("p", {}))
	if e.has("star"):
		var rec := Part.make(String(e["name"]))
		var fs: Array = []
		var r := float(e["star"]) * 0.5
		var ents: Array = []
		var pts: Array = []
		for k in 10:   # the same ten points Easy Part's Star quick shape draws (easy_part_layout _quick_pts)
			pts.append(Vector2.from_angle(PI * 0.5 + k * PI / 5.0) * (r if k % 2 == 0 else r * 0.4))
		for i in pts.size():
			ents.append({"k": "line", "a": Part.arr2(pts[i]), "b": Part.arr2(pts[(i + 1) % pts.size()])})
		PartTemplates._ex(fs, PartTemplates._sk(fs, "front", ents), "extrude", float(e["thick"]), "new")
		(fs[0] as Dictionary)["quick"] = "star"
		rec["features"] = fs
		rec["seq"] = fs.size()
		return rec
	return {}


## the scene dictionary of one entry: kind building, the part (or the room) in it
static func scene_dict(e: Dictionary, B: Body) -> Dictionary:
	var S := Scene.new()
	S.kind = "building"
	S.name = String(e["name"])
	if e.has("house"):
		S.building = BuildStarters.build(String(e["house"]))
	else:
		S.part = part_record(e)
	var d: Dictionary = S.to_dict(B, false)
	d["name"] = String(e["name"])
	return d


## writes every example file; returns how many were written (the tool prints it)
static func write_all(B: Body) -> int:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var n := 0
	for e in LIST:
		var d := scene_dict(e, B)
		var f := FileAccess.open(path_of(String(e["id"])), FileAccess.WRITE)
		if f == null:
			continue
		f.store_string(JSON.stringify(d, "\t"))
		f.close()
		n += 1
	return n


## [path, kind] of every example the start screen lists: the animation ones of Main.EXAMPLES, then these (a file that is missing is left out)
static func examples(m: Node) -> Array:
	var out: Array = []
	if m != null:
		for e in m.EXAMPLES:
			out.append(String(e[1]))
	for e in LIST:
		var p := path_of(String(e["id"]))
		if FileAccess.file_exists(p):
			out.append(p)
	return out
