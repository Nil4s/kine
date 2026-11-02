class_name NatureView
extends Node3D
## nature_view.gd - FRIDAY 225: the nature items of a building record (scripts/build/nature.gd) as nodes. One child per item, named "nat_<id>"; an item is rebuilt only
## when its own record (or, for a lawn / flowers / scatter, the rooms and paths it keeps off) changed. Wood is an ArrayMesh, leaves and blades are MultiMeshes.

const LEAF_SHADER := preload("res://scripts/build/nature_leaf.gdshader")
const GRASS_SHADER := preload("res://scripts/build/nature_grass.gdshader")

static var part_mesh: Mesh = null   # a scatter "of": "part" repeats this mesh (the caller sets it)
var nodes := {}   # id -> {"sig": String, "node": Node3D}
var last_ms := 0.0


# ---------------------------------------------------------------- the record -> nodes

func sync(bd: Dictionary) -> void:
	var items: Array = bd.get("nature", []) if not bool(bd.get("readonly", false)) else []
	var msig := JSON.stringify(Nature.mask_of(bd))
	var keep := {}
	var t0 := Time.get_ticks_usec()
	for it in items:
		var id := String(it["id"])
		keep[id] = true
		var sig := JSON.stringify(it)
		if ["grass", "flowers", "scatter"].has(String(it["kind"])):
			sig += msig
		if nodes.has(id) and nodes[id]["sig"] == sig:
			continue
		if nodes.has(id):
			(nodes[id]["node"] as Node).queue_free()
		var n := node_for(it, bd)
		n.name = "nat_" + id
		add_child(n)
		nodes[id] = {"sig": sig, "node": n}
	for id in nodes.keys():
		if not keep.has(id):
			(nodes[id]["node"] as Node).queue_free()
			nodes.erase(id)
	last_ms = float(Time.get_ticks_usec() - t0) / 1000.0


static func node_for(it: Dictionary, bd: Dictionary = {}) -> Node3D:
	match String(it["kind"]):
		"tree":
			return tree_node(it)
		"hedge":
			return hedge_node(it)
		"shrub":
			return shrub_node(it)
		"grass":
			return grass_node(it, bd)
		"flowers":
			return flowers_node(it, bd)
		"path":
			return path_node(it)
		"scatter":
			return scatter_node(it, bd)
	return Node3D.new()


# ---------------------------------------------------------------- mesh pieces

static func array_mesh(d: Dictionary) -> ArrayMesh:
	var am := ArrayMesh.new()
	if (d["verts"] as PackedVector3Array).is_empty():
		return am
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = d["verts"]
	arr[Mesh.ARRAY_NORMAL] = d["norms"]
	arr[Mesh.ARRAY_COLOR] = d["cols"]
	arr[Mesh.ARRAY_INDEX] = d["idx"]
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am


static var _card: ArrayMesh = null
static var _blade: ArrayMesh = null
static var _flower: ArrayMesh = null


static func card_mesh() -> ArrayMesh:
	if _card == null:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 1, 0), Vector3(-0.5, 1, 0)])
		arr[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
		arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
		_card = ArrayMesh.new()
		_card.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return _card


static func blade_mesh() -> ArrayMesh:
	if _blade == null:
		var v := PackedVector3Array([Vector3(-0.012, 0, 0), Vector3(0.012, 0, 0), Vector3(-0.009, 0.5, 0.03), Vector3(0.009, 0.5, 0.03), Vector3(0, 1.0, 0.12)])
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
		arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 0.5), Vector2(1, 0.5), Vector2(0.5, 1)])
		arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 3, 0, 3, 2, 2, 3, 4])
		_blade = ArrayMesh.new()
		_blade.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return _blade


static func flower_mesh() -> ArrayMesh:
	if _flower == null:
		var v := PackedVector3Array([Vector3(-0.004, 0, 0), Vector3(0.004, 0, 0), Vector3(0.004, 0.28, 0), Vector3(-0.004, 0.28, 0)])
		var uv := PackedVector2Array([Vector2(0, 0), Vector2(0, 0), Vector2(0, 1), Vector2(0, 1)])
		var idx := PackedInt32Array([0, 1, 2, 0, 2, 3])
		var c := Vector3(0, 0.29, 0)
		v.append(c)
		uv.append(Vector2(1, 1))
		for i in 8:
			var a := TAU * float(i) / 8.0
			v.append(c + Vector3(cos(a) * 0.045, 0.012, sin(a) * 0.045))
			uv.append(Vector2(1, 1))
		for i in 8:
			idx.append_array(PackedInt32Array([4, 5 + (i + 1) % 8, 5 + i]))
		var nrm := PackedVector3Array()
		for i in v.size():
			nrm.append(Vector3.UP)
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = nrm
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_INDEX] = idx
		_flower = ArrayMesh.new()
		_flower.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return _flower


static func multimesh_node(nm: String, mesh: Mesh, xf: Array, col: PackedColorArray, mat: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_color(i, col[i])
	var mi := MultiMeshInstance3D.new()
	mi.name = nm
	mi.multimesh = mm
	mi.material_override = mat
	return mi


static func wood_material() -> StandardMaterial3D:
	var mt := StandardMaterial3D.new()
	mt.vertex_color_use_as_albedo = true
	mt.roughness = 0.95
	return mt


static func body_material() -> StandardMaterial3D:
	var mt := StandardMaterial3D.new()
	mt.vertex_color_use_as_albedo = true
	mt.roughness = 0.9
	mt.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mt


static func leaf_material(shape: int, crown_h: float, soft := 0.55) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = LEAF_SHADER
	sm.set_shader_parameter("shape", shape)
	sm.set_shader_parameter("crown_h", crown_h)
	sm.set_shader_parameter("soft", soft)
	return sm


# ---------------------------------------------------------------- the kinds

static func tree_node(it: Dictionary) -> Node3D:
	var t := Nature.make_tree(it)
	var n := Node3D.new()
	n.position = Vector3(float(it.get("x", 0.0)), 0, float(it.get("z", 0.0)))
	var wm := MeshInstance3D.new()
	wm.name = "wood"
	wm.mesh = array_mesh(t["mesh"])
	wm.material_override = wood_material()
	n.add_child(wm)
	if int(t["leaf_n"]) > 0:
		var ch := float(t["height"]) * (0.6 if t["species"] != "pine" else 0.5)
		n.add_child(multimesh_node("leaves", card_mesh(), t["leaf_xf"], t["leaf_col"], leaf_material(int(t["shape"]), ch, 0.35 if t["species"] == "palm" else 0.6)))
	n.set_meta("tree", {"branches": t["branches"], "leaf_n": t["leaf_n"], "height": t["height"], "crown": t["crown"]})
	return n


static func hedge_node(it: Dictionary) -> Node3D:
	var h := Nature.make_hedge(it)
	var n := Node3D.new()
	var bm := MeshInstance3D.new()
	bm.name = "body"
	bm.mesh = array_mesh(h["mesh"])
	bm.material_override = body_material()
	n.add_child(bm)
	n.add_child(multimesh_node("leaves", card_mesh(), h["leaf_xf"], h["leaf_col"], leaf_material(5, 0.5, 0.5)))
	n.set_meta("length", h["length"])
	return n


static func shrub_node(it: Dictionary) -> Node3D:
	var s := Nature.make_shrub(it)
	var n := Node3D.new()
	n.position = Vector3(float(it.get("x", 0.0)), 0, float(it.get("z", 0.0)))
	var bm := MeshInstance3D.new()
	bm.name = "body"
	bm.mesh = array_mesh(s["mesh"])
	bm.material_override = body_material()
	n.add_child(bm)
	n.add_child(multimesh_node("leaves", card_mesh(), s["leaf_xf"], s["leaf_col"], leaf_material(int(s["shape"]), float(s["height"]) * 0.5, 0.7)))
	return n


static func grass_node(it: Dictionary, bd: Dictionary) -> Node3D:
	var g := Nature.make_grass(it, bd)
	var n := Node3D.new()
	var gm := MeshInstance3D.new()
	gm.name = "ground"
	gm.mesh = array_mesh(g["ground"])
	gm.material_override = body_material()
	gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(gm)
	var sm := ShaderMaterial.new()
	sm.shader = GRASS_SHADER
	var mi := multimesh_node("blades", blade_mesh(), g["xf"], g["col"], sm)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mi)
	n.set_meta("blades", g["blades"])
	return n


static func flowers_node(it: Dictionary, bd: Dictionary) -> Node3D:
	var f := Nature.make_flowers(it, bd)
	var n := Node3D.new()
	var sm := ShaderMaterial.new()
	sm.shader = GRASS_SHADER
	sm.set_shader_parameter("flower", 1.0)
	n.add_child(multimesh_node("flowers", flower_mesh(), f["xf"], f["col"], sm))
	return n


static func path_node(it: Dictionary) -> Node3D:
	var r := Nature.make_ribbon(it["path"], float(it["width"]), 0.012, Color(0.62, 0.58, 0.5))
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = "ribbon"
	mi.mesh = array_mesh(r["mesh"])
	mi.material_override = body_material()
	n.add_child(mi)
	n.set_meta("length", r["length"])
	return n


static func scatter_node(it: Dictionary, bd: Dictionary) -> Node3D:
	var sc := Nature.scatter(it, bd)
	var n := Node3D.new()
	var of := String(it["of"])
	var size := float(it["size"])
	var pts: Array = sc["pts"]
	if of == "flowers" or of == "box" or of == "part":
		var xf: Array = []
		var col := PackedColorArray()
		var rng := RandomNumberGenerator.new()
		rng.seed = int(it["seed"]) + 5
		for p in pts:
			var s := float(p["scale"]) * (size if of != "flowers" else 1.0)
			xf.append(Transform3D(Basis(Vector3.UP, float(p["yaw"])).scaled(Vector3(s, s, s)), Vector3(float(p["x"]), 0, float(p["z"]))))
			col.append(Nature.FLOWER_COLORS.values()[rng.randi() % 7] if of == "flowers" else Color(0.7, 0.62, 0.5))
		if of == "flowers":
			var sm := ShaderMaterial.new()
			sm.shader = GRASS_SHADER
			sm.set_shader_parameter("flower", 1.0)
			n.add_child(multimesh_node("copies", flower_mesh(), xf, col, sm))
		else:
			var m: Mesh = part_mesh
			if m == null:
				var bx := BoxMesh.new()
				bx.size = Vector3.ONE
				for i in xf.size():
					xf[i] = (xf[i] as Transform3D) * Transform3D(Basis(), Vector3(0, 0.5, 0))
				m = bx
			n.add_child(multimesh_node("copies", m, xf, col, body_material()))
	else:
		for i in pts.size():
			var p: Dictionary = pts[i]
			var c: Node3D
			if of == "rock":
				var rk := Nature.make_rock(size, int(it["seed"]) + i)
				c = Node3D.new()
				var mi := MeshInstance3D.new()
				mi.mesh = array_mesh(rk["mesh"])
				mi.material_override = body_material()
				c.add_child(mi)
			elif of == "shrub":
				c = shrub_node({"kind": "shrub", "size": size * float(p["scale"]), "seed": int(it["seed"]) + i, "x": 0.0, "z": 0.0})
			else:
				c = tree_node({"kind": "tree", "species": of.substr(5), "height": size * float(p["scale"]), "seed": int(it["seed"]) + i, "x": 0.0, "z": 0.0, "density": 4, "season": "summer"})
			c.position = Vector3(float(p["x"]), 0, float(p["z"]))
			c.rotation.y = float(p["yaw"])
			n.add_child(c)
	n.set_meta("scatter", {"placed": sc["placed"], "asked": sc["asked"], "why": sc["why"], "pts": pts})
	return n
