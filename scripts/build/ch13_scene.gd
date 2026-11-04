extends RefCounted
## CH13: the engine assembly as a 3D scene (metres; the parts are in mm) for the contact sheet and the section view.
## build(parent) -> sc; pose(sc, theta_deg) moves the parts; set_cut(sc, on) swaps in SectionLook's cut material (a plane through the cylinder axis, the front half removed).
const P := preload("res://scripts/build/ch13_parts.gd")
const MM := 0.001


static func build(parent: Node) -> Dictionary:
	var sc := {"nodes": {}, "recs": {}, "cut": false}
	var root := Node3D.new()
	root.name = "Engine"
	parent.add_child(root)
	sc["root"] = root
	for nm in P.NAMES:
		var rec: Dictionary = P.record(nm)
		var mi := MeshInstance3D.new()
		mi.name = nm
		mi.mesh = Assembly.built(rec)["mesh"]
		root.add_child(mi)
		sc["nodes"][nm] = mi
		sc["recs"][nm] = rec
	var cam := Camera3D.new()
	cam.fov = 32.0
	root.add_child(cam)
	cam.position = Vector3(0.21, 0.13, 0.40)
	cam.look_at_from_position(cam.position, Vector3(0.0, 0.055, 0.039), Vector3.UP)
	cam.current = true
	var sun := DirectionalLight3D.new()
	root.add_child(sun)
	sun.look_at_from_position(Vector3(0.5, 1.0, 1.0), Vector3(0, 0, 0), Vector3.UP)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.93, 0.94, 0.96)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	return sc


static func pose(sc: Dictionary, th_deg: float) -> void:
	var po := P.pose_of(th_deg)
	for nm in P.NAMES:
		(sc["nodes"][nm] as MeshInstance3D).transform = Assembly.xf_of(po[nm])


## on: every part gets the section shader (flat, cap colours per body), the half of the engine at z > the cylinder axis is cut away; off: the painted meshes again
static func set_cut(sc: Dictionary, on: bool) -> void:
	var i := 0
	for nm in P.NAMES:
		var mi: MeshInstance3D = sc["nodes"][nm]
		var rec: Dictionary = sc["recs"][nm]
		if not on:
			mi.mesh = Assembly.built(rec)["mesh"]
			continue
		var res := Part.replay(rec, -1, {})
		var mesh := (res["mesh"] as ArrayMesh).duplicate() as ArrayMesh
		var looks: Array = res["looks"]
		var cut := {"n": Vector3(0, 0, 1), "w": P.ZC * MM}
		var mats := SectionLook.materials(looks, mesh.get_surface_count(), cut, [], false)
		# each part gets its own cap colour: the section look picks the first colour far from the body's own; rotate the list per part so the seven read as seven
		for s in mesh.get_surface_count():
			var m: ShaderMaterial = mats[s]
			m.set_shader_parameter("cap", SectionLook.CAPS[i % SectionLook.CAPS.size()])
			mesh.surface_set_material(s, m)
		mi.mesh = mesh
		i += 1
	sc["cut"] = on
