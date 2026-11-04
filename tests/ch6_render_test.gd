## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/ch6_render_test.gd     (CH6 renders; not a bar test)
## Env CH6_OUT=<dir>. Runs the tie once, then writes 30 fps PNG sequences:
##   <dir>/seq/f00000.png ...   the hand ties the bowline, the hand lets go, the knot seats and is loaded (camera fixed on the knot)
##   <dir>/turn/t000.png ...    a close-up turntable of the dressed knot (end of the seating hold)
##   <dir>/still_*.png          stills: end of tying, dressed, loaded
## The picture: rope = chain of spheres coloured along its length (S0 blue ... W red), peg = grey cylinder, the right arm and
## hand = the Kine rig's capsules (Body.cap), so what is drawn is what the rope collided with.
extends SceneTree

var cam: Camera3D
var rope_mm: MultiMeshInstance3D
var caps: Array = []
var peg_mi: MeshInstance3D
var B: Body
var R: Dictionary
var W := 960
var H := 540


func _init() -> void:
	var out := OS.get_environment("CH6_OUT")
	if out == "":
		out = "C:/Users/Nick/tools/kine_workers/out/ch6"
	DirAccess.make_dir_recursive_absolute(out + "/seq")
	DirAccess.make_dir_recursive_absolute(out + "/turn")
	root.size = Vector2i(W, H)
	var tie := Ch6Tie.new()
	R = tie.run({})
	B = tie.B
	print("render: run done, %d frames, native=%s" % [R["frames"].size(), str(R["native"])])
	build_scene()
	await process_frame
	var ph: Dictionary = R["phase"]
	var nf: int = R["frames"].size()
	var ctr := Ch6Tie.O + Vector3(-0.02, -0.06, 0.0)
	for f in nf:
		pose(f)
		# the camera follows the work: close on the knot while the hand ties, wide when the rope is pulled long
		if f < int(ph["hand_end"]):
			look(ctr + Vector3(0.0, 0.0, 0.0), Vector3(0.10, 0.07, 0.42), 0.0)
		else:
			var P: PackedVector3Array = R["frames"][f]
			var c := centre_of_knot(P) + Ch6Tie.O
			look(c, Vector3(0.06, 0.05, 0.30), 0.0)
		await process_frame
		await process_frame
		root.get_viewport().get_texture().get_image().save_png("%s/seq/f%05d.png" % [out, f])
	# stills and turntable at the dressed state
	var fd: int = int(ph["seat_end"])
	pose(fd)
	var cd := centre_of_knot(R["frames"][fd]) + Ch6Tie.O
	for k in 120:
		var a := TAU * float(k) / 120.0
		look(cd, Vector3(0.20 * sin(a), 0.06, 0.20 * cos(a)), 0.0)
		await process_frame
		await process_frame
		root.get_viewport().get_texture().get_image().save_png("%s/turn/t%03d.png" % [out, k])
	var P2: PackedVector3Array = R["frames"][int(ph["tie_end"])]
	pose(int(ph["tie_end"]))
	look(Ch6Tie.O + Vector3(-0.03, -0.05, 0.0), Vector3(0.0, 0.03, 0.30), 0.0)
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/still_tied.png")
	pose(fd)
	look(cd, Vector3(0.0, 0.03, 0.22), 0.0)
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/still_dressed.png")
	look(cd, Vector3(0.0, 0.03, -0.22), 0.0)   # from behind
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/still_dressed_back.png")
	pose(nf - 1)
	look(cd, Vector3(0.0, 0.03, 0.30), 0.0)
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/still_loaded.png")
	print("render: done")
	quit(0)


func centre_of_knot(P: PackedVector3Array) -> Vector3:
	var c = Ch6Knot.knot_centre(P)
	if c == null:
		return Vector3(-0.03, -0.05, 0.0)
	return c


func look(target: Vector3, off: Vector3, roll: float) -> void:
	cam.position = target + off
	cam.look_at(target, Vector3.UP)


func build_scene() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.93, 0.94, 0.96)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.77, 0.82)
	e.ambient_light_energy = 0.9
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 25, 0)
	sun.light_energy = 1.1
	root.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 200, 0)
	fill.light_energy = 0.5
	root.add_child(fill)
	cam = Camera3D.new()
	cam.fov = 35
	cam.near = 0.01
	cam.far = 20.0
	root.add_child(cam)
	cam.make_current()
	# rope
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var sph := SphereMesh.new()
	sph.radius = Ch6Knot.R_ROPE
	sph.height = Ch6Knot.R_ROPE * 2.0
	sph.radial_segments = 12
	sph.rings = 6
	mm.mesh = sph
	mm.instance_count = R["n"]
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.6
	sph.material = mat
	rope_mm = MultiMeshInstance3D.new()
	rope_mm.multimesh = mm
	root.add_child(rope_mm)
	for i in R["n"]:
		var t := float(i) / float(R["n"] - 1)
		mm.set_instance_color(i, Color.from_hsv(0.62 - 0.62 * t, 0.85, 0.95))
	# peg
	var cyl := CylinderMesh.new()
	cyl.top_radius = Ch6Knot.PEG_R
	cyl.bottom_radius = Ch6Knot.PEG_R
	cyl.height = 0.4
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.45, 0.45, 0.5)
	cyl.material = pm
	peg_mi = MeshInstance3D.new()
	peg_mi.mesh = cyl
	peg_mi.position = Ch6Tie.O + Ch6Knot.PEG
	peg_mi.rotation_degrees = Vector3(90, 0, 0)
	root.add_child(peg_mi)
	# hand and arm capsules
	var names: Array = []
	for fg in Ch6Tie.FINGERS:
		for k in 3:
			names.append("%s_0%d_r" % [fg, k + 1])
	names.append_array(["hand_r", "lowerarm_r", "upperarm_r"])
	for j in names:
		var cm := CapsuleMesh.new()
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = Color(0.93, 0.74, 0.62)
		cmat.roughness = 0.7
		cm.material = cmat
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		root.add_child(mi)
		caps.append([j, mi])


func pose(f: int) -> void:
	var xs: PackedVector3Array = R["frames"][f]
	var mm: MultiMesh = rope_mm.multimesh
	for i in xs.size():
		mm.set_instance_transform(i, Transform3D(Basis(), xs[i] + Ch6Tie.O))
	var snap: Dictionary = R["hand"][f]
	for j in snap:
		B.ang[j] = snap[j]
	B.fk()
	for c in caps:
		var seg: Array = B.cap(c[0])
		var a: Vector3 = seg[0]
		var b: Vector3 = seg[1]
		var mi: MeshInstance3D = c[1]
		var cm: CapsuleMesh = mi.mesh
		var rad := float(B.rad[c[0]])
		var l := a.distance_to(b)
		cm.radius = rad
		cm.height = l + 2.0 * rad
		var up := (b - a).normalized() if l > 1e-6 else Vector3.UP
		var basis := Basis()
		if up.dot(Vector3.UP) < -0.9999:
			basis = Basis(Vector3.RIGHT, PI)
		else:
			basis = Basis(Quaternion(Vector3.UP, up))
		mi.transform = Transform3D(basis, (a + b) * 0.5)
