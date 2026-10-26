## SAFETY SHEET panel (ROADMAP I28; the judges and the page: scripts/safety_sheet.gd). One list for the whole scene, every fighter: real contacts
## and their speed, weapon tips near a head, falls, rushed strikes. A click on an item moves the playhead to it. "Export page" writes the
## printable HTML (thumbnails inline) to scenes/_safety/<scene>_safety.html. Each thumbnail is the whole scene at the item's frame from one
## fixed 3/4 camera (the same offset every time), drawn off screen in a SubViewport of its own; a red ball marks where it happens.
class_name SafetyUI
extends RefCounted

const DIR := "res://scenes/_safety"
const THUMB := Vector2i(320, 180)
const CAM_OFF := Vector3(2.3, 1.5, 2.6)   # the fixed 3/4 offset from the pair's middle
const CAM_UP := 0.9                         # m above the pair's middle point of the pelvis that the camera looks at

var m: Node
var rep: Dictionary = {}
var pics: Array = []        # PNG bytes per item (after an export or render_thumbs)
var imgs: Array = []
var last_path := ""
var forced: Dictionary = {}   # {"scenes", "names", "xfs"}: report on these instead of the open scene (a test's synthetic fighters)
var _vp: SubViewport
var _cam: Camera3D
var _mens: Array = []       # [{"node", "skel", "idx", "wep"}]
var _mark: MeshInstance3D


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Safety sheet", "", show, "stunt crew pre-shoot report safety contact speed weapon tip head face fall breakfall rushed strike thumbnail html print",
		false, "one pre-shoot report over the whole scene: real contacts and their speed, weapon tips near a head, falls, rushed strikes; click an item to jump to it; Export page writes a printable HTML sheet with a picture of each item")


## the fighters of the open scene: {"scenes", "names", "xfs"}
func gather() -> Dictionary:
	if not forced.is_empty():
		return forced
	m._actors_sync()
	var sc := []
	var nm := []
	var xs := []
	if m.actors_rt.size() >= 2:
		for k in m.actors_rt.size():
			sc.append(m.actors_rt[k]["S"])
			nm.append("the hero" if k == 0 else String(m.actors_rt[k]["name"]))
			xs.append(m.actors_rt[k]["xf"])
	else:
		sc.append(m._hero_scene())
		nm.append("the hero")
		xs.append(Transform3D.IDENTITY)
	return {"scenes": sc, "names": nm, "xfs": xs}


func compute() -> void:
	var g := gather()
	var S: Scene = g["scenes"][0]
	rep = SafetySheet.analyze(g["scenes"], g["names"], g["xfs"], maxi(1, S.fps))
	pics = []
	imgs = []


func show() -> void:
	if m.S.cards.is_empty():
		m._say("the safety sheet needs a scene with cards: add a pose card first (or open a scene from the list)")
		return
	compute()
	_panel()


func _title() -> String:
	return String((gather()["scenes"][0] as Scene).name)


func _line(it: Dictionary) -> String:
	return "%s  %.2f s  f%d  %s  -  %s" % [String(it["sev"]).to_upper(), float(it["t"]), int(it["frame"]), " / ".join(it["who"]), String(it["text"])]


func _panel() -> void:
	var L: VBoxContainer = m.ui_find_list
	for c in L.get_children():
		L.remove_child(c)
		c.queue_free()
	var items: Array = rep.get("items", [])
	var head := HBoxContainer.new()
	L.add_child(head)
	var title: Label = m._label("SAFETY SHEET  -  %s" % String(rep.get("msg", "")), 14, "fail" if int(rep.get("red", 0)) > 0 else ("warn" if items.size() > 0 else "heading"), true)
	title.name = "sf_title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var eb: Button = m._button("Export page", export_page, "write the printable sheet to scenes/_safety/<scene>_safety.html, a picture of each item inline")
	eb.name = "sf_export"
	head.add_child(eb)
	head.add_child(m._button("Close", m._close_findings))
	L.add_child(m._label("Click an item to jump the playhead to it. Red: a contact from %.0f m/s up, a weapon tip under %.0f cm from a head, a failed landing. Amber: the rest. The %.0f cm and %.0f m/s limits are heuristics, not a standard." % [
		SafetySheet.CONTACT_RED, SellHit.SAFE * 100.0, SafetySheet.TIP_NEAR * 100.0, SafetySheet.CONTACT_RED], 13, "text:0.6", true))
	for k in items.size():
		var it: Dictionary = items[k]
		var row := HBoxContainer.new()
		if k < imgs.size() and imgs[k] != null:
			var tr := TextureRect.new()
			tr.name = "sf_pic_%d" % k
			tr.texture = ImageTexture.create_from_image(imgs[k])
			tr.custom_minimum_size = Vector2(96, 54)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			row.add_child(tr)
		var b: Button = m._button(_line(it), jump.bind(k), "jump the playhead to %.2f s" % float(it["t"]))
		b.name = "sf_item_%d" % k
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(300, 0)
		b.add_theme_color_override("font_color", Tok.of("fail" if it["sev"] == "red" else "warn"))
		row.add_child(b)
		L.add_child(row)
	(m.ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(440, clampf(120.0 + 60.0 * items.size(), 200.0,
		minf(520.0, m.get_viewport().get_visible_rect().size.y - m.bottom_h - 82 - (m.TOP_H + 12) - 26)))
	m.ui_find.visible = true
	m._say("safety sheet: " + String(rep.get("msg", "")) + (".  Click an item to jump to it; 'Export page' writes the printable sheet" if not items.is_empty() else ""))


func jump(k: int) -> void:
	var items: Array = rep.get("items", [])
	if k < 0 or k >= items.size():
		m._say("pick an item in the safety sheet list first")
		return
	var it: Dictionary = items[k]
	m.playing = false
	m.playhead = maxf(float(it["t"]), 0.0)
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	m._say("safety sheet: %.2f s (frame %d), %s" % [float(it["t"]), int(it["frame"]), String(it["text"])])


## ---- thumbnails ----

func _stage(host: Node, n: int) -> void:
	if _vp == null or not is_instance_valid(_vp):
		_vp = SubViewport.new()
		_vp.name = "safety_stage"
		_vp.size = THUMB
		_vp.own_world_3d = true
		_vp.msaa_3d = Quality.thumb_msaa() as Viewport.MSAA
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		host.add_child(_vp)
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = PoseLibrary.BG
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(1, 1, 1)
		env.ambient_light_energy = 0.5
		var we := WorldEnvironment.new()
		we.environment = env
		_vp.add_child(we)
		var key := DirectionalLight3D.new()
		key.rotation_degrees = Vector3(-45, 30, 0)
		key.light_energy = 1.1
		_vp.add_child(key)
		_cam = Camera3D.new()
		_cam.fov = 50.0
		_cam.near = 0.05
		_cam.far = 40.0
		_vp.add_child(_cam)
		_cam.current = true
		var fl := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(14, 14)
		fl.mesh = pm
		var fm := StandardMaterial3D.new()
		fm.albedo_color = Color(0.32, 0.34, 0.38)
		fl.material_override = fm
		_vp.add_child(fl)
		_mark = MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 0.07
		sp.height = 0.14
		_mark.mesh = sp
		var mm := StandardMaterial3D.new()
		mm.albedo_color = Color(0.95, 0.15, 0.12)
		mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mm.no_depth_test = true
		_mark.material_override = mm
		_vp.add_child(_mark)
	while _mens.size() < n:
		var skin := StandardMaterial3D.new()
		skin.albedo_color = [PoseLibrary.SKIN, Color(0.45, 0.62, 0.9), Color(0.5, 0.8, 0.55), Color(0.9, 0.5, 0.45)][_mens.size() % 4]
		skin.roughness = 0.6
		var root := Node3D.new()
		_vp.add_child(root)
		var mq := Overlays.mannequin(root, skin)
		var wm := MeshInstance3D.new()
		var cy := CylinderMesh.new()
		cy.top_radius = 0.02
		cy.bottom_radius = 0.02
		wm.mesh = cy
		var wmat := StandardMaterial3D.new()
		wmat.albedo_color = Color(0.85, 0.85, 0.9)
		wm.material_override = wmat
		root.add_child(wm)
		_mens.append({"node": root, "skel": mq[1], "idx": mq[2], "wep": wm})


## draw the scene at time t from the fixed 3/4 camera. g = gather(); at = the marker (hero space) or null. Returns an Image (null on failure)
func draw(host: Node, g: Dictionary, bodies: Array, t: float, at: Variant) -> Image:
	var sc: Array = g["scenes"]
	_stage(host, sc.size())
	var mid := Vector3.ZERO
	for k in sc.size():
		(sc[k] as Scene).apply(bodies[k], t)
		var men: Dictionary = _mens[k]
		var xf: Transform3D = g["xfs"][k]
		(men["node"] as Node3D).transform = xf
		(men["node"] as Node3D).visible = true
		Overlays.pose_skeleton(men["skel"], men["idx"], bodies[k])
		var wm: MeshInstance3D = men["wep"]
		wm.visible = (bodies[k] as Body).wep_on
		if wm.visible:
			var a: Vector3 = bodies[k].wep_point(0.0)
			var b: Vector3 = bodies[k].wep_point(bodies[k].wep_len)
			var up := (b - a).normalized()
			var ax := up.cross(Vector3.RIGHT) if absf(up.dot(Vector3.RIGHT)) < 0.95 else up.cross(Vector3.FORWARD)
			ax = ax.normalized()
			var bas := Basis(ax.cross(up).normalized(), up, ax)
			wm.transform = Transform3D(bas, (a + b) * 0.5)
			(wm.mesh as CylinderMesh).height = a.distance_to(b)
		mid += xf * (bodies[k].P["pelvis"] as Vector3)
	for k in range(sc.size(), _mens.size()):
		(_mens[k]["node"] as Node3D).visible = false
	mid /= float(sc.size())
	mid.y = 0.0
	_cam.look_at_from_position(mid + CAM_OFF, mid + Vector3(0, CAM_UP, 0))
	_mark.visible = at is Vector3
	if at is Vector3:
		_mark.position = at
	await (Engine.get_main_loop() as SceneTree).process_frame
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	return img


## the thumbnails of all items (png bytes into pics, images into imgs)
func render_thumbs(host: Node) -> void:
	var g := gather()
	var bodies := []
	for k in g["scenes"].size():
		bodies.append(DistanceKeeper.new_body())
	var sc2 := []
	for s in g["scenes"]:
		sc2.append((s as Scene).clone())
	var g2 := {"scenes": sc2, "names": g["names"], "xfs": g["xfs"]}
	pics = []
	imgs = []
	for it in rep.get("items", []):
		var img := await draw(host, g2, bodies, float(it["t"]), it["at"])
		if img != null and not img.is_empty():
			imgs.append(img)
			pics.append(img.save_png_to_buffer())
		else:
			imgs.append(null)
			pics.append(PackedByteArray())
	if _vp != null and is_instance_valid(_vp):
		_vp.queue_free()
	_vp = null
	_mens = []
	m._actors_sync()
	m._ps().apply(m.B, m.playhead)


## write the page. dir: where (scenes/_safety by default; a test passes user://...). Returns the path ("" on failure)
func write_page(host: Node, dir0 := DIR) -> String:
	var dir := UserPaths.w(dir0)   # an exported build: the user's folder
	if rep.is_empty():
		compute()
	if pics.size() != rep.get("items", []).size():
		await render_thumbs(host)
	var nm := _title().validate_filename().replace(" ", "_")
	var abs := ProjectSettings.globalize_path(dir)
	DirAccess.make_dir_recursive_absolute(abs)
	var path := "%s/%s_safety.html" % [abs, nm]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(SafetySheet.to_html(rep, _title(), pics))
	f.close()
	last_path = path
	return path


func export_page() -> void:
	if rep.is_empty():
		compute()
	m._say("safety sheet: drawing the pictures and writing the page...")
	var p := await write_page(m)
	if p == "":
		m._say("could not write the safety page: check that the scenes folder is writable, then press Export page again")
		return
	_panel()
	m._say("safety sheet written to %s (open it in a browser, print from there)" % p)
