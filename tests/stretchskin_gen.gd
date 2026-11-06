## godot --path . -s tests/stretchskin_gen.gd     (L33 STRETCH-SKIN: writes tests/stretchskin_golden.txt)
## Made on the BASE, before any L33 code. For every scene in scenes/ at 5 times, the app (main.tscn) poses the figure and one md5
## covers (a) every bone's local pose in the skeleton and (b) the vertex arrays of every piece mesh the viewport skins with: the whole
## input of the skin. tests/stretchskin_test.gd bar C recomputes it with the same procedure (this file is its twin) and compares.
extends SceneTree

var m: Node


func idle(n := 2) -> void:
	for i in n:
		await process_frame


## the skin's input hash for the figure as it stands now
static func skin_hash(mm: Node) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	var sk: Skeleton3D = mm.skel
	for i in sk.get_bone_count():
		ctx.update(var_to_str([sk.get_bone_pose_position(i), sk.get_bone_pose_rotation(i), sk.get_bone_pose_scale(i)]).to_utf8_buffer())
	var keys: Array = mm.pieces.keys()
	keys.sort()
	for k in keys:
		var mi: MeshInstance3D = mm.pieces[k]
		var am := mi.mesh as ArrayMesh
		for si in am.get_surface_count():
			ctx.update((am.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array).to_byte_array())
	return ctx.finish().hex_encode()


static func scene_files() -> Array:
	var out := []
	for f in DirAccess.get_files_at("res://scenes"):
		if f.ends_with(".json"):
			out.append("res://scenes/" + f)
	out.sort()
	return out


## the library: {"<file>@<k>": hash}
static func golden(mm: Node, tree: SceneTree) -> Dictionary:
	var g := {}
	for path in scene_files():
		mm._load_scene(path)
		for i in 3:
			await tree.process_frame
		var S: Scene = mm.S
		var L := S.length()
		for k in 5:
			mm.playhead = L * float(k) / 4.0
			S.apply(mm.B, mm.playhead)
			mm.B.fk()
			mm._refresh()
			g["%s@%d" % [path.get_file(), k]] = skin_hash(mm)
	return g


func _init() -> void:
	_run()


func _run() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	var g: Dictionary = await golden(m, self)
	var f := FileAccess.open("res://tests/stretchskin_golden.txt", FileAccess.WRITE)
	var ks := g.keys()
	ks.sort()
	for k in ks:
		f.store_line("%s %s" % [k, g[k]])
	f.close()
	print("golden written: %d lines" % ks.size())
	quit(0)
