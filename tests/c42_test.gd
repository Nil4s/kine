extends SceneTree
## godot --path . --position 4000,4000 -s tests/c42_test.gd     (C42: "Stay in place" export toggle S#7, lightmap UV1 readback S#28)
## BARS, written before any number was read (scene scenes/walk_bat.json):
##  A DEFAULT   the switch is off at start, its checkbox "chk_stay_in_place" exists in the Export dialog's extras and sits inside the 1280 x 720
##              window; with it off the pelvis keys of GltfExport.build equal Body.gltf_pelvis_pos at every frame within 1e-6 (the old keys); words() = "".
##  B TRAVEL    off: the written pelvis keys travel (horizontal, world, max from the first key) >= 0.20 m (the scene has something to remove).
##              on (set by a REAL click on the checkbox): horizontal range of the written pelvis keys <= 1e-4 m at every frame; the vertical (Y) keys and
##              every rotation key equal the off ones within 1e-6; the before number in words() equals the off travel within 1e-4.
##              CONTROL: a build with the switch off reads > 0.20 m on the same reader, so a switch that did nothing fails.
##  C FEET      both files written (glb) and read back with GLTFDocument, the clip sampled at 3 times: foot_l/foot_r position minus the pelvis position
##              (skeleton space) is the same on and off within 1e-4 m, and the pelvis' horizontal place is the start place at every sample (<= 1e-3).
##              CONTROL: the off file's pelvis at the last sample is >= 0.20 m from its start.
##  D FBX       through FbxExport.write: the .fbx bytes differ on vs off (the cache key carries the switch), and off bytes equal off bytes again.
##  E UV1       a sphere written with the lightmap switch, read back in Blender 4.5 headless: 2 UV layers, every UV1 inside [0,1], and UV1 differs from UV0 on
##              >= 50 pct of loops; a plain mesh reads 1 layer. The padding is LightmapUV.PAD (0.004). An FBX of the scene reads back with NO mesh object
##              (FbxExport writes the skeleton only), which the report states. CONTROL: the plain file has no UV1 layer.
const DIR := "user://zz_c42"
const BLENDER := "C:/Program Files/Blender Foundation/Blender 4.5/blender.exe"
const SHOT := "C:/Users/Nick/tools/kine_workers/out/c42"
var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func _watchdog() -> void:
	await create_timer(500.0).timeout
	print("FAIL watchdog: the test did not finish in 500 s")
	quit(1)


func click(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	var mv := InputEventMouseMotion.new()
	mv.position = p
	mv.global_position = p
	root.push_input(mv, true)
	await process_frame
	for d in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = d
		e.position = p
		e.global_position = p
		if d:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e, true)
		await process_frame
	await idle(2)


func _clip(man: Node3D) -> Animation:
	var ap: AnimationPlayer = man.find_children("*", "AnimationPlayer", true, false)[0]
	return ap.get_animation(ap.get_animation_list()[0])


func pelvis_keys(man: Node3D) -> Array:
	var A := _clip(man)
	var out := []
	for t in A.get_track_count():
		if A.track_get_type(t) == Animation.TYPE_POSITION_3D and String(A.track_get_path(t)).ends_with(":pelvis"):
			for k in A.track_get_key_count(t):
				out.append(A.track_get_key_value(t, k))
	return out


func rot_keys(man: Node3D) -> Array:
	var A := _clip(man)
	var out := []
	for t in A.get_track_count():
		if A.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			for k in A.track_get_key_count(t):
				out.append(A.track_get_key_value(t, k))
	return out


func hz(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


## the world-space horizontal range of the keys (root_rot undone as the exporter does)
func world_range(B: Body, keys: Array) -> float:
	var r := 0.0
	for k in keys:
		r = maxf(r, hz(B.root_rot * (k as Vector3) - B.root_rot * (keys[0] as Vector3)).length())
	return r


func build_keys(S, B) -> Dictionary:
	var keep: Dictionary = B.state()
	var man := GltfExport.build(S, B, "c42", false)
	var d := {"pel": pelvis_keys(man), "rot": rot_keys(man)}
	man.free()
	B.set_state(keep)
	return d


## the GLB read back: the clip sampled at t, the skeleton-space positions of pelvis, foot_l, foot_r
func sample(path: String, t: float) -> Dictionary:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(path), st) != OK:
		return {}
	var n: Node = doc.generate_scene(st)
	var sk: Skeleton3D = n.find_children("*", "Skeleton3D", true, false)[0]
	var ap: AnimationPlayer = n.find_children("*", "AnimationPlayer", true, false)[0]
	ap.play(ap.get_animation_list()[0])
	ap.seek(t, true)
	sk.force_update_all_bone_transforms()
	var out := {}
	for b in ["pelvis", "foot_l", "foot_r"]:
		var i := sk.find_bone(b)
		out[b] = sk.get_bone_global_pose(i).origin if i >= 0 else Vector3(1e9, 0, 0)
	n.free()
	return out


func blender(file: String, out: String) -> Array:
	var o := []
	DirAccess.remove_absolute(ProjectSettings.globalize_path(out))
	OS.execute(BLENDER, ["-b", "--factory-startup", "--python", ProjectSettings.globalize_path("res://tools/c42_uvcheck.py"), "--", ProjectSettings.globalize_path(file), ProjectSettings.globalize_path(out)], o, true)
	if not FileAccess.file_exists(out):
		return []
	return JSON.parse_string(FileAccess.get_file_as_string(out))


func _init() -> void:
	_watchdog()
	DirAccess.make_dir_recursive_absolute(SHOT)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	await idle(4)
	m._load_scene("res://scenes/walk_bat.json")
	await idle(3)
	var S = m.S
	var B: Body = m.B
	# --- A
	ok(not StayInPlace.on, "A switch is off at start")
	ok(StayInPlace.words() == "", "A words() empty when off")
	var off := build_keys(S, B)
	var keep: Dictionary = B.state()
	var n_bad := 0
	var K: int = (off["pel"] as Array).size()
	for k in K:
		S.apply(B, minf(float(k) / float(S.fps), S.length()))
		if ((off["pel"][k] as Vector3) - B.gltf_pelvis_pos()).length() > 1e-6:
			n_bad += 1
	B.set_state(keep)
	ok(K > 5 and n_bad == 0, "A off: %d pelvis keys equal gltf_pelvis_pos (bad %d)" % [K, n_bad])
	var travel_off := world_range(B, off["pel"])
	ok(travel_off >= 0.20, "B off travel %.3f m >= 0.20 (control: there is travel to remove)" % travel_off)
	# the dialog + a real click
	m._export_dialog_open()
	await idle(6)
	var chk := m.export_ui.find_child("chk_stay_in_place", true, false) as CheckBox
	ok(chk != null, "A checkbox exists")
	if chk == null:
		print("c42: %d fail" % fails)
		quit(1)
		return
	var sc := chk.get_window().find_child("export_opts_scroll", true, false) as ScrollContainer
	if sc != null:
		sc.ensure_control_visible(chk)
		await idle(3)
	var rc := chk.get_global_rect()
	ok(Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(rc), "A checkbox inside 1280x720 %s" % str(rc))
	ok(not chk.button_pressed, "A checkbox starts unticked")
	root.get_texture().get_image().save_png(SHOT + "/dialog_off.png")
	await click(chk)
	ok(chk.button_pressed and StayInPlace.on, "B a real click turned it on")
	root.get_texture().get_image().save_png(SHOT + "/dialog_on.png")
	var on := build_keys(S, B)
	var w := StayInPlace.words()
	print("c42 words: ", w)
	var rng_on := world_range(B, on["pel"])
	ok(rng_on <= 1e-4, "B on: horizontal range of written pelvis keys %.6f m <= 1e-4" % rng_on)
	var ydiff := 0.0
	for k in K:
		ydiff = maxf(ydiff, absf((on["pel"][k] as Vector3).y - (off["pel"][k] as Vector3).y))
	ok(ydiff <= 1e-6, "B on: pelvis height keys unchanged (max diff %.2e)" % ydiff)
	var rdiff := 0.0
	for k in (off["rot"] as Array).size():
		rdiff = maxf(rdiff, ((on["rot"][k] as Quaternion) - (off["rot"][k] as Quaternion)).length())
	ok(rdiff <= 1e-6 and (on["rot"] as Array).size() == (off["rot"] as Array).size(), "B on: every rotation key unchanged (max diff %.2e)" % rdiff)
	ok(w.contains("travel %.2f m -> 0.00 m" % float(StayInPlace.last["before"])), "B words() has before and after: " + w)
	ok(absf(float(StayInPlace.last["before"]) - travel_off) <= 1e-4, "B before %.4f equals the off travel %.4f" % [float(StayInPlace.last["before"]), travel_off])
	# --- C files
	var p_on := DIR + "/on.glb"
	var p_off := DIR + "/off.glb"
	var keep2: Dictionary = B.state()
	ok(GltfExport.write(S, B, p_on) == OK, "C on file written")
	StayInPlace.on = false
	ok(GltfExport.write(S, B, p_off) == OK, "C off file written")
	B.set_state(keep2)
	var L: float = S.length()
	var worst := 0.0
	var pel0_on: Vector3 = sample(p_on, 0.0).get("pelvis", Vector3.ZERO)
	var pel0_off: Vector3 = sample(p_off, 0.0).get("pelvis", Vector3.ZERO)
	var pel_stay := 0.0
	for f in [0.25, 0.6, 1.0]:
		var t := L * f
		var a := sample(p_on, t)
		var b := sample(p_off, t)
		if a.is_empty() or b.is_empty():
			ok(false, "C sample read back at %.2f" % t)
			continue
		for foot in ["foot_l", "foot_r"]:
			var da: Vector3 = (a[foot] as Vector3) - (a["pelvis"] as Vector3)
			var db: Vector3 = (b[foot] as Vector3) - (b["pelvis"] as Vector3)
			worst = maxf(worst, (da - db).length())
		pel_stay = maxf(pel_stay, hz((a["pelvis"] as Vector3) - pel0_on).length())
	ok(worst <= 1e-4, "C foot-minus-pelvis same on and off, worst %.2e m" % worst)
	ok(pel_stay <= 1e-3, "C on: pelvis horizontal place held at 3 samples (%.2e)" % pel_stay)
	var last_off: Vector3 = sample(p_off, L)["pelvis"]
	var moved := hz(last_off - pel0_off).length()
	ok(moved >= 0.20, "C control: the off file's pelvis moved %.3f m by the end" % moved)
	# --- D FBX
	var fa := DIR + "/a.fbx"
	var fb := DIR + "/b.fbx"
	var fc := DIR + "/c.fbx"
	StayInPlace.on = false
	FbxExport.write(S, B, fa)
	FbxExport.write(S, B, fc)
	StayInPlace.on = true
	FbxExport.write(S, B, fb)
	StayInPlace.on = false
	var ba := FileAccess.get_file_as_bytes(fa)
	var bb := FileAccess.get_file_as_bytes(fb)
	var bc := FileAccess.get_file_as_bytes(fc)
	ok(ba.size() > 100 and ba != bb, "D fbx on differs from off (%d / %d bytes)" % [ba.size(), bb.size()])
	ok(ba == bc, "D fbx off twice is byte-identical")
	# --- E UV1 in Blender
	var sph := SphereMesh.new()
	sph.radial_segments = 16
	sph.rings = 8
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sph.get_mesh_arrays())
	var objs := [{"name": "ball", "mesh": am, "xf": Transform3D.IDENTITY}]
	var wl := LightmapUV.apply_list(objs)
	ok(GltfExport.write_meshes(wl, DIR + "/lm.glb") == OK, "E lightmap glb written")
	ok(GltfExport.write_meshes(objs, DIR + "/plain.glb") == OK, "E plain glb written")
	if FileAccess.file_exists(BLENDER):
		var r1 := blender(DIR + "/lm.glb", DIR + "/lm.json")
		var r0 := blender(DIR + "/plain.glb", DIR + "/plain.json")
		ok(r1.size() == 1 and (r1[0]["layers"] as Array).size() == 2, "E Blender: lightmap file has 2 UV layers %s" % str(r1))
		if r1.size() == 1 and (r1[0]["layers"] as Array).size() == 2:
			var mn: Array = r1[0]["uv1_min"]
			var mx: Array = r1[0]["uv1_max"]
			ok(float(mn[0]) >= 0.0 and float(mn[1]) >= 0.0 and float(mx[0]) <= 1.0 and float(mx[1]) <= 1.0, "E UV1 inside 0-1: %s .. %s (pad %s)" % [str(mn), str(mx), str(LightmapUV.PAD)])
			ok(float(r1[0]["differs"]) >= 0.5 * float(r1[0]["loops"]), "E UV1 differs from UV0 on %d of %d loops" % [int(r1[0]["differs"]), int(r1[0]["loops"])])
		ok(r0.size() == 1 and (r0[0]["layers"] as Array).size() == 1, "E control: the plain file has 1 UV layer %s" % str(r0))
		var rf := blender(fa, DIR + "/fbx.json")
		ok(rf.size() == 0, "E FBX reads back with no mesh object (skeleton only; no UV1 possible): %s" % str(rf))
	else:
		ok(false, "E Blender 4.5 not found")
	print("c42: %d fail" % fails)
	quit(1 if fails > 0 else 0)
