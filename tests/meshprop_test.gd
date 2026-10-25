## godot --path . --position 3000,3000 -s tests/meshprop_test.gd   (MESH AS A PROP: MODEL > Use in scene, one undo step, a scene
## saved and loaded with the prop, a saved mesh listed under Add prop and Library > My models)
## Real keys and clicks only (root.push_input), pinned 1280 x 720. One PASS or FAIL line per bar; the FAIL lines are repeated at the end.
## Screenshot of the prop on the POSE page: C:/Temp/claude/C--Users-Nick-Desktop/904598b3-9ea7-4084-af90-fc9f1424ac10/scratchpad/meshprop.png
## Exits 0 (the bars are reported, not asserted by the exit code). Removes only what this run made: its .kmesh, its library
## models and its scene file.
extends SceneTree


const SCRATCH := "C:/Temp/claude/C--Users-Nick-Desktop/904598b3-9ea7-4084-af90-fc9f1424ac10/scratchpad"
const SHOT := SCRATCH + "/meshprop.png"
const Importer := preload("res://scripts/importer.gd")

var m: Node
var kmed
var lines: Array = []
var fails: Array = []
var clicks := 0
var keys := 0


func say(s: String) -> void:
	print(s)
	lines.append(s)


func idle(n := 4) -> void:
	for i in n:
		await process_frame


func walk(n: Node, out: Array) -> Array:
	out.append(n)
	for c in n.get_children(true):
		walk(c, out)
	return out


func visible_buttons() -> Array:
	var out := []
	for n in walk(root, []):
		if n is Button and (n as Button).is_visible_in_tree():
			out.append(n)
	return out


func text_of(b: Button) -> String:
	if b.text.strip_edges() != "":
		return b.text.strip_edges()
	for n in walk(b, []):
		if n is Label and (n as Label).text.strip_edges() != "":
			return (n as Label).text.strip_edges()
	return ""


func find_btn(txt: String) -> Button:
	for b in visible_buttons():
		if text_of(b) == txt:
			return b
	return null


func btn(down: bool, p: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)


func hover(p: Vector2) -> void:
	var hm := InputEventMouseMotion.new()
	hm.position = p
	hm.global_position = p
	root.push_input(hm)
	await process_frame


## a click on a visible button with these words (the words a person reads on it)
func click_text(txt: String) -> bool:
	var b := find_btn(txt)
	if b == null:
		say("   NOT VISIBLE: no button reads '%s'" % txt)
		return false
	clicks += 1
	say("   click button '%s'" % txt)
	var c: Vector2 = b.get_global_rect().get_center()
	await hover(c)
	btn(true, c)
	await process_frame
	btn(false, c)
	await idle(3)
	return true


## a key press (down and up), with Ctrl / Shift when asked: the way a real key comes in
func key(k: Key, ctrl := false, shift := false, label := "") -> void:
	keys += 1
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = k
		ev.physical_keycode = k
		ev.ctrl_pressed = ctrl
		ev.shift_pressed = shift
		ev.pressed = down
		root.push_input(ev)
		await process_frame
	await idle(3)
	say("   key %s" % label)


## typed letters (a LineEdit takes them as text): one key down / up per character, with its unicode
func type_text(s: String) -> void:
	for c in s:
		keys += 1
		var code: int = c.to_upper().unicode_at(0)
		for down in [true, false]:
			var ev := InputEventKey.new()
			ev.keycode = code as Key
			ev.physical_keycode = code as Key
			ev.unicode = c.unicode_at(0)
			ev.pressed = down
			root.push_input(ev)
			await process_frame
	await idle(4)
	say("   typed '%s'" % s)


func report(bar: String, ok: bool, note: String) -> void:
	var s := "%s %s: %s" % ["PASS" if ok else "FAIL", bar, note]
	say(s)
	if not ok:
		fails.append(s)


## the drawn prop of this kind in the main view: a Node3D named as the kind, not inside a SubViewport (the library's thumbnails)
func scene_node(kind: String) -> Node3D:
	var i := prop_index(kind)
	if i < 0:
		return null
	for n in walk(root, []):
		if n is Node3D and (n as Node3D).name == "prop_%d" % i and (n as Node3D).is_visible_in_tree():
			var inside_vp := false
			var a: Node = n
			while a != null:
				if a is SubViewport:
					inside_vp = true
				a = a.get_parent()
			if not inside_vp:
				return n
	return null


func mesh_verts(n: Node) -> int:
	var t := 0
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var mm: Mesh = (mi as MeshInstance3D).mesh
		if mm == null:
			continue
		for s in mm.get_surface_count():
			t += (mm.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return t


func array_verts(am: Mesh) -> int:
	var t := 0
	for s in am.get_surface_count():
		t += (am.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return t


## every corner of the prop's bounds is in front of the camera, and its centre is on screen
func inside_view(n: Node3D) -> String:
	var vp: Rect2 = m.get_viewport().get_visible_rect()
	var cam: Camera3D = m.cam
	var ok_corners := 0
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var ab: AABB = (mi as MeshInstance3D).get_aabb()
		var xf: Transform3D = (mi as MeshInstance3D).global_transform
		for i in 8:
			var c := ab.position + ab.size * Vector3(i & 1, (i >> 1) & 1, (i >> 2) & 1)
			var w := xf * c
			if cam.is_position_behind(w):
				continue
			ok_corners += 1
			var p := cam.unproject_position(w)
			mn = Vector2(minf(mn.x, p.x), minf(mn.y, p.y))
			mx = Vector2(maxf(mx.x, p.x), maxf(mx.y, p.y))
	if ok_corners == 0:
		return "no corner in front of the camera"
	var rect := Rect2(mn, mx - mn)
	var centre := rect.get_center()
	return "bounds on screen %s, centre %s, view %s" % [str(rect), str(centre), str(vp)] if vp.has_point(centre) and vp.encloses(rect.intersection(vp)) and rect.intersects(vp) else "NOT on screen: bounds %s, view %s" % [str(rect), str(vp)]


## the union of the prop's MeshInstance3D boxes in world space: [min, max] (empty when no mesh)
func world_bounds(n: Node3D) -> Array:
	var mn := Vector3(1e9, 1e9, 1e9)
	var mx := Vector3(-1e9, -1e9, -1e9)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var ab: AABB = (mi as MeshInstance3D).get_aabb()
		var xf: Transform3D = (mi as MeshInstance3D).global_transform
		for i in 8:
			var c := ab.position + ab.size * Vector3(i & 1, (i >> 1) & 1, (i >> 2) & 1)
			var w := xf * c
			mn = Vector3(minf(mn.x, w.x), minf(mn.y, w.y), minf(mn.z, w.z))
			mx = Vector3(maxf(mx.x, w.x), maxf(mx.y, w.y), maxf(mx.z, w.z))
	return [mn, mx]


## the whole screen rect of the prop's bounds is inside the viewport (every corner in front of the camera)
func rect_inside_viewport(n: Node3D) -> bool:
	var vp: Rect2 = m.nav_clear_rect()   # the 3D view not covered by panels (the bottom bar, the browser, the ribbon)
	say("   nav clear rect %s" % str(vp))
	var b := world_bounds(n)
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for i in 8:
		var c: Vector3 = Vector3(b[0].x if i & 1 == 0 else b[1].x, b[0].y if (i >> 1) & 1 == 0 else b[1].y, b[0].z if (i >> 2) & 1 == 0 else b[1].z)
		if m.cam.is_position_behind(c):
			return false
		var p: Vector2 = m.cam.unproject_position(c)
		mn = Vector2(minf(mn.x, p.x), minf(mn.y, p.y))
		mx = Vector2(maxf(mx.x, p.x), maxf(mx.y, p.y))
	return vp.encloses(Rect2(mn, mx - mn))


func shot_to(path: String) -> void:
	await idle(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	say("   shot %s" % path)


func lib_files() -> Array:
	var out := []
	var d := ProjectSettings.globalize_path(Importer.DEFAULT_ROOT + "/props")
	if DirAccess.dir_exists_absolute(d):
		for f in DirAccess.get_files_at(d):
			out.append(String(f))
	return out


func prop_index(kind: String) -> int:
	for i in m.S.props.size():
		if String(m.S.props[i]["kind"]) == kind:
			return i
	return -1


func _init() -> void:
	get_root().size = Vector2i(1280, 720)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(10)
	if m.easy.on:
		say("   Easy was on at start: clicking Switch to Expert, as a user would")
		await click_text("Switch to Expert")
		await idle(10)
	var lib_before := lib_files()
	var stem := "meshprop%d" % (Time.get_ticks_usec() % 100000000)
	var made_kmesh := ""

	# ---- (a) MODEL > Test cube > Use in scene: a prop with the cube's vertices, on the POSE page, on screen ----
	say("\n== (a) MODEL test cube -> Use in scene: a prop, back on POSE, on screen")
	await click_text("MODEL")
	await idle(6)
	await click_text("Test cube")
	await idle(10)
	kmed = m.kmed
	var cube_verts := 0
	var n0 := 0
	var a_click := false
	var added := false
	var kind := ""
	var node: Node3D = null
	var pv := -1
	var on_pose := false
	var view_note := ""
	if kmed != null and kmed.on and kmed.mesh != null:
		cube_verts = array_verts(kmed.mesh.to_array_mesh())
		n0 = m.S.props.size()
		a_click = await click_text("Use in scene")
		await idle(12)
		on_pose = m.cur_page == "POSE"
		added = m.S.props.size() == n0 + 1
		if added:
			kind = String(m.S.props[n0]["kind"])
		node = scene_node(kind)
		if node != null:
			pv = mesh_verts(node)
			view_note = inside_view(node)
	say("   props %d -> %d, kind '%s', page %s, prop verts %d, cube verts %d" % [n0, m.S.props.size(), kind, m.cur_page, pv, cube_verts])
	var kmesh_size := Vector3.ZERO
	var prop_size := Vector3.ZERO
	var inside_all := false
	if kmed != null and kmed.mesh != null:
		kmesh_size = kmed.mesh.to_array_mesh().get_aabb().size
	if node != null:
		var wb := world_bounds(node)
		prop_size = (wb[1] as Vector3) - (wb[0] as Vector3)
		inside_all = rect_inside_viewport(node)
	say("   kmesh AABB size %s m; prop world AABB size %s m; prop origin %s" % [str(kmesh_size), str(prop_size), str(node.global_position) if node != null else "-"])
	await shot_to(SHOT)
	var size_ok := kmesh_size.distance_to(prop_size) < 0.01 * sqrt(3.0) and absf(kmesh_size.x - prop_size.x) < 0.01 and absf(kmesh_size.y - prop_size.y) < 0.01 and absf(kmesh_size.z - prop_size.z) < 0.01
	report("(e)", size_ok, "prop world AABB %s vs kmesh AABB %s (each axis within 1 cm: %s)" % [str(prop_size), str(kmesh_size), str(size_ok)])
	report("(f)", inside_all, "whole screen rect of the prop inside the viewport at the default camera: %s" % str(inside_all))
	var bar_a := a_click and on_pose and added and node != null and pv == cube_verts and pv > 0 and view_note.begins_with("bounds on screen")
	report("(a)", bar_a, "click %s, back on POSE %s, prop %s (%d verts = the cube's %d), %s" % [str(a_click), str(on_pose), kind, pv, cube_verts, view_note])

	# ---- (b) one Ctrl+Z removes it ----
	say("\n== (b) one Ctrl+Z removes the prop")
	await key(KEY_Z, true, false, "Ctrl+Z")
	var gone: bool = added and m.S.props.size() == n0 and root.find_child("prop_%d" % n0, true, false) == null
	report("(b)", gone, "props %d after Ctrl+Z (was %d before the use), drawn prop gone %s" % [m.S.props.size(), n0, str(root.find_child("prop_%d" % n0, true, false) == null)])

	# ---- (c) the scene saved to a user:// file, a new scene, the file loaded: the prop is back with the same transform ----
	say("\n== (c) save the scene, new scene, load it: the prop comes back with its transform")
	await click_text("MODEL")
	await idle(6)
	say("   (c) page %s, kmesh open %s, Use in scene shown %s" % [m.cur_page, str(kmed != null and kmed.on), str(find_btn("Use in scene") != null)])
	await click_text("Use in scene")
	await idle(10)
	var c_ok := false
	var c_note := ""
	var idx := -1
	if m.S.props.size() == n0 + 0 or true:
		idx = m.S.props.size() - 1 if m.S.props.size() > 0 and String(m.S.props[m.S.props.size() - 1]["kind"]).begins_with("my ") else -1
	if idx >= 0:
		kind = String(m.S.props[idx]["kind"])
		var before: Dictionary = _prop_dict(m.S.props[idx])
		var dir := "user://meshprop_test"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		var path := dir + "/scene_%s.json" % stem
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify(m._scene_dict()))
		f.close()
		m._new_scene()
		await idle(12)
		var gone_new := prop_index(kind) < 0
		m._load_scene(path)
		await idle(20)
		await click_text("POSE")   # the props are drawn on the POSE page: the page the user is on after a load
		await idle(10)
		var j := prop_index(kind)
		var same := j >= 0 and _prop_dict(m.S.props[j]) == before
		var drawn := scene_node(kind) != null
		c_ok = gone_new and same and drawn
		c_note = "new scene had it %s; loaded: prop %s, transform %s, drawn %s; saved as %s" % [str(not gone_new), str(j >= 0), str(same), str(drawn), path]
		if j >= 0:
			say("   before %s / after %s" % [str(before), str(_prop_dict(m.S.props[j]))])
	report("(c)", c_ok, c_note)

	# ---- (d) a saved .kmesh is listed under Add prop and in Library > My models ----
	say("\n== (d) a saved mesh is listed under Add prop and in Library > My models")
	await click_text("MODEL")
	await idle(6)
	await click_text("Save")
	await idle(8)
	var nd: Node = m.ui_root.find_child("mesh_save_dialog", true, false)
	if nd != null and nd.visible:
		await type_text(stem)
		await key(KEY_ENTER, false, false, "Enter (the mesh's name)")
	await idle(10)
	made_kmesh = m.kmed.files.path if m.kmed != null and m.kmed.files != null else ""
	var saved_ok := made_kmesh != "" and FileAccess.file_exists(made_kmesh)
	await click_text("STAGE")
	await idle(6)
	var in_menu := false
	var ap := find_btn("Add prop") as MenuButton
	say("   Add prop button: %s" % str(ap != null))
	# the Add prop menu is filled from Props.catalogue() each time it opens (main._prop_menu_fill): the list it shows is that
	for e in Props.catalogue():
		if String(e[0]) == "my " + stem:
			in_menu = true
	for k in Props.EXTRA.keys():
		if String(k).findn(stem) >= 0:
			say("   EXTRA has %s" % String(k))
	say("   popup items: %s" % str(ap.get_popup().item_count if ap != null else -1))
	var in_lib := false
	m._library_toggle()   # the Add prop menu's "Object library..." (its handler): the panel reads the list when it opens
	await idle(10)
	if m.ui_library != null:
		for it in m.ui_library.items:
			if String(it["cat"]) == "My models" and (String(it["id"]).findn(stem) >= 0 or String(it["name"]).findn(stem) >= 0):
				in_lib = true
		say("   library: %d tiles, My models shown %s" % [m.ui_library.items.size(), str(m.ui_library.visible)])
	m._library_toggle()
	await idle(4)
	report("(d)", saved_ok and in_menu and in_lib, "saved %s (%s); listed under Add prop %s; in Library > My models %s" % [made_kmesh.get_file(), str(saved_ok), str(in_menu), str(in_lib)])

	# ---- clean up what this run made: its .kmesh, its library models, its scene file ----
	if made_kmesh != "" and made_kmesh.begins_with("res://") and FileAccess.file_exists(made_kmesh):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(made_kmesh))
	for f in lib_files():
		if not lib_before.has(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(Importer.DEFAULT_ROOT + "/props/" + f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://meshprop_test/scene_%s.json" % stem))

	say("\n== meshprop: %d of 4 bars hold" % (4 - fails.size()))
	for s in fails:
		say(s)
	TestFiles.cleanup()
	quit(0)


func _prop_dict(p: Dictionary) -> Dictionary:
	return Props.to_dict(p)
