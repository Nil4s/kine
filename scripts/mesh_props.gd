class_name MeshProps
extends RefCounted
## A MESH AS A PROP (walk-through 6). The mesh the MODEL page has open goes into the scene as a prop (MODEL > Use in scene),
## and every saved mesh (meshes/*.kmesh) is listed under Add prop and in Library > My models. A prop is a kind name plus a
## transform (scripts/props.gd); a model kind is a .glb in the library (user://library/props), registered by Props.register
## at its real size. So a mesh is written there as <stem>.glb, with a note beside it (<stem>.licence.txt) that starts with
## MARK and names the .kmesh it came from. A library file without that note is someone's own: it is never written over.

const Importer := preload("res://scripts/importer.gd")
const MARK := "made from a mesh of the MODEL page: "


## the library's props folder (the same one the importer copies into)
static func props_dir() -> String:
	return Importer.DEFAULT_ROOT + "/props"


## stem, then stem_2, stem_3 ... : the first whose .glb is not in the library yet (a prop placed earlier keeps its model)
static func free_stem(stem: String) -> String:
	var s := stem
	var n := 2
	while FileAccess.file_exists(Importer._abs("%s/%s.glb" % [props_dir(), s])):
		s = "%s_%d" % [stem, n]
		n += 1
	return s


## the mesh written as the library model <stem>.glb and registered as a prop kind ("my <stem>"). Returns the kind, or "" with
## KMesh.last_error set when the file could not be written or read back
static func write_model(k: KMesh, stem: String, source: String) -> String:
	DirAccess.make_dir_recursive_absolute(Importer._abs(props_dir()))
	var glb := "%s/%s.glb" % [props_dir(), stem]
	var err := KMeshVPaint.export_glb(k, Importer._abs(glb), stem)
	if err != OK:
		KMesh.last_error = error_string(err)
		return ""
	var note := FileAccess.open(Importer._abs("%s/%s.licence.txt" % [props_dir(), stem]), FileAccess.WRITE)
	if note != null:
		note.store_string("%s%s\nlicence: the user's own mesh\n" % [MARK, source])
		note.close()
	var info: Dictionary = Importer.inspect(glb)
	if not info.get("ok", false):
		KMesh.last_error = String(info.get("why", "the file did not read back"))
		return ""
	var kind := "my " + stem
	Props.register(kind, info["aabb"], glb, info["scale_factor"])
	return kind


## every saved mesh has its model in the library, so it is listed under Add prop and Library > My models. A model is written
## when it is missing or older than its .kmesh; a model the user made (no note of ours) is left as it is. Returns the count written
static func sync_saved() -> int:
	var n := 0
	for p in KMeshFileUI.list():
		var stem := String(p).get_file().get_basename()
		var glb := "%s/%s.glb" % [props_dir(), stem]
		var note := Importer._abs("%s/%s.licence.txt" % [props_dir(), stem])
		var ours := FileAccess.file_exists(note) and FileAccess.get_file_as_string(note).begins_with(MARK)
		if FileAccess.file_exists(Importer._abs(glb)) and not ours:
			continue
		if ours and FileAccess.get_modified_time(Importer._abs(glb)) >= FileAccess.get_modified_time(p):
			continue
		var k := KMesh.load_file(p)
		if k == null:
			continue
		if write_model(k, stem, p) != "":
			n += 1
	return n
