## godot --headless --path . -s tests/floor_fade_test.gd     (GATES EE1, UPGRADES #45)
## THE FLOOR FADES: every vertex of the grid mesh has alpha = its colour's alpha x clamp((2 - r) / 1, 0, 1), r its
## distance from the middle in the floor (computed here); every line piece is at most 0.1 m; there are vertices at
## full, faded and (at the edge) zero alpha. THE ORIGIN HAS AXES: the axis mesh holds a red line from the origin
## toward +X (his left), a green one up +Y, a blue one toward +Z (where he faces), each with two arrowhead strokes at
## its tip; the letters X / Y / Z stand by them. The grid material blends alpha (else the fade would not show).
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## a mesh stores vertex colours in 8 bits: 0.9 comes back 0.898
func same(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) <= 0.005 and absf(a.g - b.g) <= 0.005 and absf(a.b - b.b) <= 0.005 and absf(a.a - b.a) <= 0.005


func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 4:
		await process_frame
	var g: ImmediateMesh = m.grid_mesh
	var arr := g.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var c: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var worst := 0.0
	var longest := 0.0
	var full := 0
	var part := 0
	var zero := 0
	for i in v.size():
		var r := Vector2(v[i].x, v[i].z).length()
		var want := clampf((2.0 - r) / 1.0, 0.0, 1.0)
		var base := Tok.c("grid_major") if absf(c[i].r - Tok.c("grid_major").r) < 1e-3 else Tok.c("grid")
		worst = maxf(worst, absf(c[i].a - base.a * want))
		if want >= 1.0:
			full += 1
		elif want > 0.0:
			part += 1
		else:
			zero += 1
		if i % 2 == 1:
			longest = maxf(longest, v[i].distance_to(v[i - 1]))
	ok(worst <= 0.01 and longest <= 0.1 + 1e-6 and full > 100 and part > 100 and zero > 0,
		"1 the grid: %d vertices, each alpha = the fade rule (worst off %.4f), pieces at most %.3f m; full %d, fading %d, zero at the edge %d" % [v.size(), worst, longest, full, part, zero])
	var gi: MeshInstance3D = null
	for mi in m.stage_root.find_children("*", "MeshInstance3D", false, false):   # TC4: the floor lives under the stage
		if (mi as MeshInstance3D).mesh == g:
			gi = mi
	ok(gi != null and (gi.material_override as StandardMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "2 the grid's material blends alpha")
	var a := (m.axis_mesh as ImmediateMesh).surface_get_arrays(0)
	var av: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var ac: PackedColorArray = a[Mesh.ARRAY_COLOR]
	var found := {}
	for dir in [[Vector3.RIGHT, "X", "r"], [Vector3.UP, "Y", "g"], [Vector3.BACK, "Z", "b"]]:
		var axis := -1
		for i in range(0, av.size(), 2):
			var d := av[i + 1] - av[i]
			if av[i].length() < 0.01 and d.length() > 0.2 and d.normalized().dot(dir[0]) > 0.99:
				axis = i
		if axis < 0:
			continue
		var col := ac[axis]
		var strongest: String = "r" if col.r >= maxf(col.g, col.b) else ("g" if col.g >= col.b else "b")
		var tip := av[axis + 1]
		var heads := 0
		for i in range(0, av.size(), 2):
			if i != axis and av[i].distance_to(tip) < 1e-4 and av[i + 1].distance_to(tip) < 0.1 and same(ac[i], col):
				heads += 1
		var lab: Label3D = m.stage_root.get_node_or_null("axis_" + String(dir[1]))
		var lab_ok := lab != null and lab.text.begins_with(dir[1]) and lab.position.distance_to(tip) < 0.2 and same(lab.modulate, col)
		found[dir[1]] = [strongest == dir[2], heads, lab_ok]
	ok(found.size() == 3 and found.values().all(func(f): return f[0] and f[1] == 2 and f[2]),
		"3 the origin's axes: %s (each: its colour right, 2 arrowhead strokes, its letter beside its tip in its colour)" % found)
	print("FLOOR FADE: %d failed" % fails)
	quit(1 if fails > 0 else 0)
