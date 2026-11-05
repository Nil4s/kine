extends RefCounted
## CH15: the plant as a 3D scene for the construction SECTION video. build(parent, asm, section): one MeshInstance3D per assembly part; with section on, every
## part that has a "cut" plane is split there by Kine's own Split feature (keep the far half, z < cut) and the parts wholly on the near side are hidden, so the
## camera on +z looks into the reactor building and along the turbine hall. show_stage(sc, k): stages 0..k built, stage k's new parts in its own flat colour.
const S := preload("res://scripts/build/ch15_site.gd")
const PALETTE := [Color(1, 1, 0), Color(0, 1, 1), Color(1, 0, 1), Color(0, 1, 0), Color(0, 0.4, 1), Color(1, 0.55, 0), Color(0.6, 0, 1), Color(0.55, 1, 0.2),
	Color(0, 0.6, 0.5), Color(1, 0.6, 0.8)]


static func stage_color(k: int) -> Color:
	return PALETTE[k % PALETTE.size()]


static func _section_rec(p: Dictionary) -> Dictionary:
	var r: Dictionary = (p["rec"] as Dictionary).duplicate(true)
	# not Split: its half-space is a 20 m box (Part._half), so at plant scale it bites a 20 m hole instead of cutting the building in two
	var at := (float(p["cut"]) * 1000.0 - float(p["pos"][2]))
	(r["features"] as Array).append({"t": "prim", "id": "fcut", "name": "Section", "kind": "box", "op": "cut", "into": 0, "x": -1.0e6, "y": -2.0e5, "z": at, "w": 2.0e6, "h": 5.0e5, "d": 1.0e6})
	return r


static func build(parent: Node, asm: Dictionary, section: bool) -> Dictionary:
	var root := Node3D.new()
	root.name = "Plant"
	parent.add_child(root)
	var nodes := {}
	for p in asm["parts"]:
		var rec: Dictionary = p["rec"]
		var wb := S.world_aabb(p)
		var hide := false
		if section and p.get("cut", null) != null:
			var cz := float(p["cut"])
			if wb.position.z >= cz - 1e-6:
				hide = true
			elif wb.end.z > cz and absf(float(p["rot"][1])) < 1e-9:
				rec = _section_rec(p)
		elif section and absf(float(p["rot"][1])) > 1e-9 and wb.get_center().z > 0.0:
			hide = true
		var mi := MeshInstance3D.new()
		mi.name = String(p["name"]).replace(" ", "_")
		mi.mesh = S.built(rec)["mesh"]
		mi.transform = Assembly.xf_of(p)
		mi.visible = false
		root.add_child(mi)
		nodes[p["name"]] = {"mi": mi, "hide": hide}
	var sea := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(900, 0.5, 400)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.16, 0.30, 0.42)
	sm.material = smat
	sea.mesh = sm
	sea.position = Vector3(80, -0.6, 460)
	root.add_child(sea)
	var cam := Camera3D.new()
	cam.fov = 42.0
	cam.far = 4000.0
	root.add_child(cam)
	cam.look_at_from_position(Vector3(-120, 140, 250), Vector3(35, 5, -15), Vector3.UP)
	cam.current = true
	var sun := DirectionalLight3D.new()
	root.add_child(sun)
	sun.look_at_from_position(Vector3(-200, 400, 300), Vector3.ZERO, Vector3.UP)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 1500.0
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.86, 0.90, 0.95)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.85, 0.9)
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var hl := []
	for k in PALETTE.size():
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = PALETTE[k]
		hl.append(m)
	return {"root": root, "nodes": nodes, "cam": cam, "stages": S.stages(), "shown": -1, "hl": hl}


static func show_stage(sc: Dictionary, k: int) -> void:
	var st: Array = sc["stages"]
	for i in st.size():
		for nm in st[i]["parts"]:
			var n: Dictionary = sc["nodes"][nm]
			var mi: MeshInstance3D = n["mi"]
			mi.visible = i <= k and not bool(n["hide"])
			mi.material_override = sc["hl"][i % PALETTE.size()] if i == k else null
	sc["shown"] = k


static func shown_stage(sc: Dictionary) -> int:
	return int(sc["shown"])


## the camera square on to the reactor building's section plane, from plant south (+z); the highlight is cleared so the parts show their own colours
static func camera_section(sc: Dictionary) -> void:
	for nm in sc["nodes"]:
		var mi: MeshInstance3D = sc["nodes"][nm]["mi"]
		mi.material_override = null
		if String(nm) in ["Auxiliary building", "Fuel building", "Diesel building 1", "Diesel building 2", "Outfall structure", "Seawater intake"]:
			mi.visible = false   # the buildings between this camera and the cut: a section view shows the building it cuts
	(sc["cam"] as Camera3D).look_at_from_position(Vector3(30, 30, 125), Vector3(0, 18, 0), Vector3.UP)   # past the auxiliary building's corner (x <= 6 at z 39.5..84.5)
