## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/splineik_shot.gd     (needs a window; SPLINEIK_SHOT=<png>, default C:/Temp/claude/l28/spline.png)
## The L28 contact sheet: a 10-bone tail on a 4-handle curve in 4 poses (keep length, keep length bent hard, stretch to fit, stretch + volume + twist),
## and a stretched arm (target 1.3x reach, stretch on, orange) beside the old solver (grey, stops short). Drawn with the same bone mesh as the bone editor.
extends SceneTree

const W := 640
const H := 400

var cam: Camera3D
var holder: Node3D
var cap: Label


func _mat(c: Color, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


const FAT := 3.0   # the bones are drawn this much wider than the bone editor draws them, to be seen at this size


func bone(xf: Transform3D, L: float, c: Color, fat := FAT) -> void:
	var n := MeshInstance3D.new()
	n.mesh = BoneEditUI._make_octa()
	n.material_override = _mat(c)
	n.transform = Transform3D(xf.basis * Basis.from_scale(Vector3(fat, 1.0, fat) * L), xf.origin)
	holder.add_child(n)


func ball(p: Vector3, r: float, c: Color) -> void:
	var n := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	n.mesh = sm
	n.material_override = _mat(c, true)
	n.position = p
	holder.add_child(n)


func line(pts: PackedVector3Array, c: Color) -> void:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pts
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP, arr)
	var n := MeshInstance3D.new()
	n.mesh = am
	n.material_override = _mat(c, true)
	holder.add_child(n)


func clear() -> void:
	for ch in holder.get_children():
		ch.queue_free()


func tail_panel(ctrl: Array, mode: String, tw1: float, vol: bool, label: String, look: Vector3, dist: float) -> void:
	clear()
	var lens := []
	for i in 10:
		lens.append(0.1)
	var o := {"kind": "catmull", "mode": mode, "tw0": 0.0, "tw1": tw1, "volume": vol, "rest_y": Vector3.UP, "rest_x": Vector3.RIGHT}
	var r := SplineChain.solve(ctrl[0], lens, ctrl, o)
	var poly := PackedVector3Array()
	for i in 61:
		poly.append(SplineChain.curve_point(ctrl, "catmull", 3.0 * float(i) / 60.0))
	line(poly, Color(1, 1, 1))
	for i in 10:
		var b: Basis = r["axes"][i]
		var cr: float = r["cross"][i]
		var sc: float = r["scale"][i]
		var col := Color.from_hsv(0.55 - 0.45 * float(i) / 9.0, 0.55, 0.95) if i % 2 == 0 else Color.from_hsv(0.55 - 0.45 * float(i) / 9.0, 0.35, 0.75)
		bone(Transform3D(Basis(b.x * cr, b.y * sc, b.z * cr), r["joints"][i]), 0.1, col)
	for i in ctrl.size():
		ball(ctrl[i], 0.03, Color(1.0, 0.55, 0.1))
	cap.text = "%s   chain %.2f m on a %.2f m curve   bone scale %.2f" % [label, r["chain_len"], r["curve_len"], r["scale"][0]]
	cam.position = look + Vector3(0.3, 0.15, dist)
	cam.look_at(look)


func arm_panel() -> void:
	clear()
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	for j in B.ang.keys():
		B.ang[j] = Vector3.ZERO
	B.fk()
	var sh: Vector3 = B.P["upperarm_l"]
	var reach: float = (B.p0["lowerarm_l"] - B.p0["upperarm_l"]).length() + (B.p0["hand_l"] - B.p0["lowerarm_l"]).length()
	var tgt: Vector3 = sh + ((B.p0["hand_l"] as Vector3) - (B.p0["upperarm_l"] as Vector3)).normalized() * reach * 1.3
	var chain_j := ["upperarm_l", "lowerarm_l", "hand_l"]
	# the old solver (grey)
	var B0 := Body.new()
	B0.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B0.fk()
	LimbIK.solve(B0, "hand_l", tgt, tgt + Vector3(0, 0, 1))
	var miss0 := (B0.P["hand_l"] as Vector3).distance_to(tgt)
	for i in 2:
		var a: Vector3 = B0.P[chain_j[i]]
		var b: Vector3 = B0.P[chain_j[i + 1]]
		bone(Transform3D(Basis(Quaternion(Vector3.UP, (b - a).normalized())), a), a.distance_to(b), Color(0.75, 0.75, 0.8), FAT * 1.8)
	# the stretched arm (orange)
	LimbIK.solve(B, "hand_l", tgt, tgt + Vector3(0, 0, 1), null, 1.5, true)
	var miss1 := (B.P["hand_l"] as Vector3).distance_to(tgt)
	for i in 2:
		var a: Vector3 = B.P[chain_j[i]]
		var b: Vector3 = B.P[chain_j[i + 1]]
		var c: float = B.stretch_cross.get(chain_j[i + 1], 1.0)
		var q := Quaternion(Vector3.UP, (b - a).normalized())
		bone(Transform3D(Basis(q) * Basis.from_scale(Vector3(c, 1, c)), a), a.distance_to(b), Color(1.0, 0.55, 0.15))
	ball(tgt, 0.03, Color(1, 0.1, 0.1))
	ball(sh, 0.025, Color(0.2, 0.9, 0.3))
	cap.text = "stretched arm (orange) hand %.1f mm from the target; old solver (grey) stops %.0f cm short; stretch x%.2f, thickness x%.2f" % [miss1 * 1000.0, miss0 * 100.0, B.stretch.get("lowerarm_l", 1.0), B.stretch_cross.get("lowerarm_l", 1.0)]
	var mid := (sh + tgt) * 0.5
	cam.position = mid + Vector3(0.0, 0.1, 1.6)
	cam.look_at(mid)


func _init() -> void:
	root.size = Vector2i(W, H)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.13, 0.14, 0.17)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	root.add_child(sun)
	cam = Camera3D.new()
	cam.fov = 50
	root.add_child(cam)
	holder = Node3D.new()
	root.add_child(holder)
	var cl := CanvasLayer.new()
	cap = Label.new()
	cap.position = Vector2(8, 6)
	cap.add_theme_font_size_override("font_size", 14)
	cl.add_child(cap)
	root.add_child(cl)
	_run()


func _run() -> void:
	await process_frame
	await process_frame
	var shots := []
	var A := [Vector3(0, 0, 0), Vector3(0.0, 0.35, 0), Vector3(0.0, 0.7, 0.0), Vector3(0.0, 1.0, 0.0)]
	var Bc := [Vector3(0, 0, 0), Vector3(0.45, 0.3, 0), Vector3(0.5, 0.75, 0.2), Vector3(0.1, 1.0, 0.35)]
	var Cc := [Vector3(0, 0, 0), Vector3(-0.4, 0.45, 0), Vector3(-0.6, 1.0, -0.2), Vector3(-0.15, 1.6, -0.4)]
	var D := [Vector3(0, 0, 0), Vector3(0.5, 0.2, 0.2), Vector3(0.9, 0.55, 0.0), Vector3(1.2, 1.1, -0.2)]
	var calls := [
		func(): tail_panel(A, "keep", 0.0, false, "1 straight, keep length", Vector3(0, 0.55, 0), 2.2),
		func(): tail_panel(Bc, "keep", 40.0, false, "2 bent, keep length, twist 40", Vector3(0.25, 0.55, 0.1), 2.2),
		func(): tail_panel(Cc, "stretch", 0.0, false, "3 stretch to fit", Vector3(-0.25, 0.8, -0.1), 2.6),
		func(): tail_panel(D, "stretch", 90.0, true, "4 stretch + volume + twist 90", Vector3(0.6, 0.55, 0.0), 2.6),
		func(): arm_panel(),
	]
	for c in calls:
		c.call()
		await process_frame
		await process_frame
		await process_frame
		shots.append(root.get_texture().get_image())
	var sheet := Image.create(W * 3, H * 2, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.05, 0.05, 0.06))
	for i in shots.size():
		var im: Image = shots[i]
		im.convert(Image.FORMAT_RGB8)
		im.resize(W, H, Image.INTERPOLATE_LANCZOS)   # the window is not W x H: scale the whole frame into its cell
		sheet.blit_rect(im, Rect2i(0, 0, im.get_width(), im.get_height()), Vector2i((i % 3) * W, (i / 3) * H))
	var out := OS.get_environment("SPLINEIK_SHOT")
	if out == "":
		out = "C:/Temp/claude/l28/spline.png"
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	print("sheet saved: %s %s" % [out, sheet.save_png(out)])
	quit(0)
