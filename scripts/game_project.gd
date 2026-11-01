class_name GameProject
## EXPORT: PLAYABLE GAME (Friday plan 200, s200). The Export dialog's Godot 4 > "Playable game (Godot project folder)".
## Writes <name>_game/ : project.godot (Godot 4.x), main.tscn, player.gd + npc.gd (two small scripts written for the export,
## nothing of Kine's own), README.txt, meshes/*.tres (each built part's mesh and its trimesh collision shape) and one
## .glb per character. main.tscn holds: the built house and every set prop as a StaticBody3D (mesh + trimesh
## CollisionShape3D), a big Ground StaticBody3D, the hero as a CharacterBody3D (WASD / arrows, Space jumps, Q/E turn the
## camera, third-person follow camera), the other characters as idle NPCs, and the stage's own lights and ambient.
## The characters' .glb files are read when the game starts (GLTFDocument), so the folder runs without an import step.
## Relative paths in main.tscn: Godot loads them from the folder it is in (the editor rewrites them as res:// on save).

const PLAYER_GD := """extends CharacterBody3D
## The hero: WASD or the arrow keys walk (relative to the camera), Space jumps, Q and E turn the camera.
@export var model_file := "hero.glb"
@export var speed := 4.5
@export var jump_speed := 5.5
var cam_yaw := 0.0
var start_pos := Vector3.ZERO
var model: Node3D
@onready var cam: Camera3D = $Camera3D


func _ready() -> void:
	start_pos = global_position
	var keys := {"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN], "move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT], "jump": [KEY_SPACE], "cam_left": [KEY_Q], "cam_right": [KEY_E]}
	for a in keys:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
			for k in keys[a]:
				var ev := InputEventKey.new()
				ev.physical_keycode = k
				InputMap.action_add_event(a, ev)
	model = Node3D.new()
	model.name = "Model"
	add_child(model)
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var path := ProjectSettings.globalize_path((get_script() as Script).resource_path.get_base_dir().path_join(model_file))
	if doc.append_from_file(path, st) == OK:
		var body := doc.generate_scene(st)
		model.add_child(body)
		for ap in body.find_children("*", "AnimationPlayer", true, false):
			var names: PackedStringArray = (ap as AnimationPlayer).get_animation_list()
			if names.size() > 0:
				ap.play(names[0])
				ap.seek(0.0, true)
				ap.pause()
	else:
		push_warning("cannot read " + path)
	cam.top_level = true
	cam.current = true
	_follow(1.0)


func _physics_process(delta: float) -> void:
	cam_yaw += Input.get_axis("cam_left", "cam_right") * 1.8 * delta
	var inp := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := Basis(Vector3.UP, cam_yaw) * Vector3(inp.x, 0.0, inp.y)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if is_on_floor():
		velocity.y = jump_speed if Input.is_action_just_pressed("jump") else 0.0
	else:
		velocity.y -= float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * delta
	move_and_slide()
	if dir.length() > 0.01:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(dir.x, dir.z), minf(1.0, 12.0 * delta))
	if global_position.y < -30.0:
		global_position = start_pos
		velocity = Vector3.ZERO
	_follow(1.0 - exp(-8.0 * delta))


func _follow(k: float) -> void:
	var target := global_position + Vector3(0.0, 1.4, 0.0)
	var want := target + Basis(Vector3.UP, cam_yaw) * Vector3(0.0, 1.6, 5.0)
	cam.global_position = cam.global_position.lerp(want, k)
	cam.look_at(target, Vector3.UP)
"""

const NPC_GD := """extends Node3D
## An idle character: its .glb is read when the game starts and held on its first pose.
@export var model_file := "npc_1.glb"


func _ready() -> void:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var path := ProjectSettings.globalize_path((get_script() as Script).resource_path.get_base_dir().path_join(model_file))
	if doc.append_from_file(path, st) != OK:
		push_warning("cannot read " + path)
		return
	var body := doc.generate_scene(st)
	add_child(body)
	for ap in body.find_children("*", "AnimationPlayer", true, false):
		var names: PackedStringArray = (ap as AnimationPlayer).get_animation_list()
		if names.size() > 0:
			ap.play(names[0])
			ap.seek(0.0, true)
			ap.pause()
"""

const README := """%s - a playable game made with Kine

1. Open this folder in Godot 4 (Project Manager > Import > pick project.godot).
2. Press F5.

Controls: W A S D or the arrow keys walk (relative to the camera), Space jumps, Q and E turn the camera.
The camera follows the hero from behind. The other characters stand where you put them.

What is in the folder:
  main.tscn        the level: %d built part(s) as static colliders (trimesh collision), the ground, %d character(s), the lights
  player.gd        the hero's walk, jump and follow camera (a small script written for this export)
  npc.gd           loads an idle character
  meshes/          each part's mesh and its collision shape (.tres)
  hero.glb, npc_*.glb   the characters, read when the game starts
Edit anything: it is plain Godot 4 (no add-ons, nothing to import first).
"""


## bakes the transform into a copy of the mesh, so the body can stay unscaled (a scaled collision shape misbehaves)
static func _bake(mi: MeshInstance3D, xf: Transform3D) -> ArrayMesh:
	var src: Mesh = mi.mesh
	var out := ArrayMesh.new()
	var nb := xf.basis.inverse().transposed()
	for s in src.get_surface_count():
		var arr := src.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for i in v.size():
			v[i] = xf * v[i]
		arr[Mesh.ARRAY_VERTEX] = v
		if arr[Mesh.ARRAY_NORMAL] != null:
			var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			for i in n.size():
				n[i] = (nb * n[i]).normalized()
			arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_TANGENT] = null
		out.add_surface_from_arrays(src.surface_get_primitive_type(s) if src is ArrayMesh else Mesh.PRIMITIVE_TRIANGLES, arr)
		var mat: Material = mi.get_active_material(s)
		if mat != null:
			out.surface_set_material(out.get_surface_count() - 1, mat)
	return out


## the transform of node n relative to root (root's own transform left out)
static func _rel(n: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var c: Node = n
	while c != null and c != root:
		if c is Node3D:
			t = (c as Node3D).transform * t
		c = c.get_parent()
	return t


static func _t(x: Variant) -> String:
	return var_to_str(x)


## writes the game folder under dir (the dialog's exports folder). Returns the project.godot path, or "" with the reason said in words.
static func write(m: Node, dir: String) -> String:
	dir = UserPaths.w(dir)
	var S: Scene = m.S
	if S.cards.size() < 2:
		m._say_plain("NOT NOW: a game needs at least 2 cards (a move) for its characters. Make a move on the Walk card first, then export")
		return ""
	var nm: String = m.safe_file(S.name) if S.name != "" else "scene"
	var acts: Array = m._export_actors()
	if acts.is_empty():
		acts = [{"name": "hero", "S": S, "B": m.B, "xf": Transform3D.IDENTITY}]
	var proj: String = dir + "/" + nm + "_game"
	var pabs: String = ProjectSettings.globalize_path(proj) if proj.begins_with("res://") or proj.begins_with("user://") else proj
	DirAccess.make_dir_recursive_absolute(pabs + "/meshes")
	for f in DirAccess.get_files_at(pabs + "/meshes"):
		DirAccess.remove_absolute(pabs + "/meshes/" + f)
	var ext := []      # [type, path, id]
	var body_lines := PackedStringArray()
	var sub := PackedStringArray()
	var seq := [0]
	var add_ext := func(type: String, path: String) -> String:
		seq[0] += 1
		var id := "e%d" % seq[0]
		ext.append([type, path, id])
		return id
	var n_parts := 0

	# ---- the built parts: the house, then each prop of the set: StaticBody3D > MeshInstance3D + CollisionShape3D (trimesh)
	var parts := []   # [{name, xf, meshes: [ArrayMesh]}]
	if not S.building.is_empty():
		var hm := Building.to_array_mesh(S.building)
		if hm.get_surface_count() > 0:
			var hmat := StandardMaterial3D.new()
			hmat.albedo_color = Color(0.82, 0.79, 0.74)
			hmat.roughness = 0.9
			hm.surface_set_material(0, hmat)
			var hmi := MeshInstance3D.new()
			hmi.mesh = hm
			parts.append({"name": "house", "xf": Transform3D.IDENTITY, "meshes": [_bake(hmi, Transform3D.IDENTITY)]})
			hmi.free()
	var pi := 0
	for p in S.props:
		pi += 1
		var pr := Props.mesh(p)
		var meshes := []
		var sc := Transform3D(Basis.from_scale(Vector3.ONE * Props.scale_of(p)), Vector3.ZERO)
		for mi in pr.find_children("*", "MeshInstance3D", true, false):
			if (mi as MeshInstance3D).mesh != null and (mi as MeshInstance3D).mesh.get_surface_count() > 0:
				meshes.append(_bake(mi, sc * _rel(mi, pr)))
		pr.free()
		if meshes.is_empty():
			continue
		var pxf: Transform3D = p["xf"]
		pxf.basis = pxf.basis.orthonormalized()
		parts.append({"name": "%s_%d" % [String(p["kind"]).validate_node_name(), pi], "xf": pxf, "meshes": meshes})
	var k := 0
	for part in parts:
		k += 1
		var bname := "part_%02d_%s" % [k, String(part["name"])]
		body_lines.append("[node name=\"%s\" type=\"StaticBody3D\" parent=\".\"]\ntransform = %s\n" % [bname, _t(part["xf"])])
		var j := 0
		for mesh in part["meshes"]:
			j += 1
			var mrel := "meshes/part_%02d_%d.tres" % [k, j]
			var srel := "meshes/part_%02d_%d_shape.tres" % [k, j]
			if ResourceSaver.save(mesh, pabs + "/" + mrel) != OK:
				m._say_plain("NOT DONE: cannot write %s" % mrel)
				return ""
			var shape: ConcavePolygonShape3D = (mesh as ArrayMesh).create_trimesh_shape()
			if ResourceSaver.save(shape, pabs + "/" + srel) != OK:
				m._say_plain("NOT DONE: cannot write %s" % srel)
				return ""
			var mid: String = add_ext.call("ArrayMesh", mrel)
			var sid: String = add_ext.call("ConcavePolygonShape3D", srel)
			body_lines.append("[node name=\"Mesh%d\" type=\"MeshInstance3D\" parent=\"%s\"]\nmesh = ExtResource(\"%s\")\n" % [j, bname, mid])
			body_lines.append("[node name=\"Collision%d\" type=\"CollisionShape3D\" parent=\"%s\"]\nshape = ExtResource(\"%s\")\n" % [j, bname, sid])
		n_parts += 1

	# ---- the ground: a big slab whose top is y = 0 (the floor of every Kine scene), drawn a hair lower than the house floor
	sub.append("[sub_resource type=\"BoxShape3D\" id=\"ground_shape\"]\nsize = Vector3(400, 1, 400)\n")
	sub.append("[sub_resource type=\"StandardMaterial3D\" id=\"ground_mat\"]\nalbedo_color = Color(0.36, 0.40, 0.34, 1)\nroughness = 1.0\n")
	sub.append("[sub_resource type=\"BoxMesh\" id=\"ground_mesh\"]\nsize = Vector3(400, 1, 400)\nmaterial = SubResource(\"ground_mat\")\n")
	body_lines.append("[node name=\"Ground\" type=\"StaticBody3D\" parent=\".\"]\ntransform = %s\n" % _t(Transform3D(Basis.IDENTITY, Vector3(0, -0.5, 0))))
	body_lines.append("[node name=\"Mesh\" type=\"MeshInstance3D\" parent=\"Ground\"]\ntransform = %s\nmesh = SubResource(\"ground_mesh\")\n" % _t(Transform3D(Basis.IDENTITY, Vector3(0, -0.02, 0))))
	body_lines.append("[node name=\"Collision\" type=\"CollisionShape3D\" parent=\"Ground\"]\nshape = SubResource(\"ground_shape\")\n")

	# ---- the characters: one .glb each (its own move), the hero a CharacterBody3D, the others idle
	var pid: String = add_ext.call("Script", "player.gd")
	var nid: String = add_ext.call("Script", "npc.gd")
	sub.append("[sub_resource type=\"CapsuleShape3D\" id=\"hero_shape\"]\nradius = 0.3\nheight = 1.8\n")
	var ai := 0
	var npc_n := 0
	for a in acts:
		var one := {"name": a["name"], "S": a["S"], "B": a["B"], "xf": Transform3D.IDENTITY}
		var gname := "hero.glb" if ai == 0 else "npc_%d.glb" % ai
		var err := GltfExport.write_actors([one], pabs + "/" + gname)
		if err != OK:
			m._say_plain("NOT DONE: %s could not be written (%s)" % [gname, error_string(err)])
			return ""
		if ai == 0:
			body_lines.append("[node name=\"Player\" type=\"CharacterBody3D\" parent=\".\"]\ntransform = %s\nscript = ExtResource(\"%s\")\nmodel_file = \"%s\"\n" % [_t(Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 0))), pid, gname])
			body_lines.append("[node name=\"Collision\" type=\"CollisionShape3D\" parent=\"Player\"]\ntransform = %s\nshape = SubResource(\"hero_shape\")\n" % _t(Transform3D(Basis.IDENTITY, Vector3(0, 0.9, 0))))
			body_lines.append("[node name=\"Camera3D\" type=\"Camera3D\" parent=\"Player\"]\ntop_level = true\ncurrent = true\nfov = 65.0\n")
		else:
			npc_n += 1
			var nxf: Transform3D = a["xf"]
			body_lines.append("[node name=\"NPC_%d_%s\" type=\"Node3D\" parent=\".\"]\ntransform = %s\nscript = ExtResource(\"%s\")\nmodel_file = \"%s\"\n" % [ai, String(a["name"]).validate_node_name(), _t(nxf), nid, gname])
		ai += 1

	# ---- the stage's own lighting
	var env_text := "[sub_resource type=\"Environment\" id=\"env\"]\nbackground_mode = 1\nbackground_color = Color(0.55, 0.62, 0.72, 1)\nambient_light_source = 2\nambient_light_color = Color(0.7, 0.7, 0.7, 1)\nambient_light_energy = 0.6\n"
	var we = m.world_env
	if we is Environment:
		var e := we as Environment
		env_text = "[sub_resource type=\"Environment\" id=\"env\"]\nbackground_mode = 1\nbackground_color = %s\nambient_light_source = 2\nambient_light_color = %s\nambient_light_energy = %s\n" % [_t(e.background_color), _t(e.ambient_light_color), _t(e.ambient_light_energy)]
	sub.append(env_text)
	body_lines.append("[node name=\"WorldEnvironment\" type=\"WorldEnvironment\" parent=\".\"]\nenvironment = SubResource(\"env\")\n")
	var lights := [["KeyLight", m.light_key, true], ["FillLight", m.light_fill, false], ["RimLight", m.light_rim, false]]
	var n_lights := 0
	for l in lights:
		var L = l[1]
		if L is DirectionalLight3D:
			var tx: Transform3D = (L as DirectionalLight3D).global_transform if (L as Node).is_inside_tree() else (L as DirectionalLight3D).transform
			tx.origin = Vector3.ZERO
			body_lines.append("[node name=\"%s\" type=\"DirectionalLight3D\" parent=\".\"]\ntransform = %s\nlight_color = %s\nlight_energy = %s\nshadow_enabled = %s\n" % [l[0], _t(tx), _t((L as DirectionalLight3D).light_color), _t((L as DirectionalLight3D).light_energy), "true" if l[2] else "false"])
			n_lights += 1
	if n_lights == 0:
		body_lines.append("[node name=\"KeyLight\" type=\"DirectionalLight3D\" parent=\".\"]\ntransform = %s\nshadow_enabled = true\n" % _t(Transform3D(Basis.from_euler(Vector3(deg_to_rad(-50), deg_to_rad(30), 0)), Vector3.ZERO)))

	# ---- main.tscn
	var tscn := "[gd_scene load_steps=%d format=3]\n\n" % (ext.size() + sub.size() + 1)
	for e in ext:
		tscn += "[ext_resource type=\"%s\" path=\"%s\" id=\"%s\"]\n" % [e[0], e[1], e[2]]
	tscn += "\n" + "\n".join(sub) + "\n"
	tscn += "[node name=\"Main\" type=\"Node3D\"]\n\n" + "\n".join(body_lines)
	var files := {"main.tscn": tscn, "player.gd": PLAYER_GD, "npc.gd": NPC_GD,
		"README.txt": README % [nm, n_parts, ai],
		"project.godot": "; Engine configuration file (written by Kine; Godot 4)\nconfig_version=5\n\n[application]\n\nconfig/name=\"%s\"\nrun/main_scene=\"res://main.tscn\"\nconfig/features=PackedStringArray(\"4.2\")\n\n[display]\n\nwindow/size/viewport_width=1280\nwindow/size/viewport_height=720\n" % nm.replace("\"", "")}
	for fname in files:
		var f := FileAccess.open(pabs + "/" + fname, FileAccess.WRITE)
		if f == null:
			m._say_plain("NOT DONE: cannot write %s (%s)" % [fname, error_string(FileAccess.get_open_error())])
			return ""
		f.store_string(files[fname])
		f.close()
	m._say_plain("exported %s_game/: %d built part(s) as static colliders, %d character(s) (the hero walks: WASD / arrows, Space jumps), the lights. Open the folder in Godot 4 and press F5" % [nm, n_parts, ai])
	return pabs + "/project.godot"
