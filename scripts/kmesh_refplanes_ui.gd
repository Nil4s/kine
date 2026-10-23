class_name KMeshRefPlanesUI
extends Node
## REFERENCE IMAGES ON PLANES in the model preview (ROADMAP_400 B21): the planes as nodes under the mesh's view, the
## "Reference images" panel (bottom left of the clear view) and the two-point clicks. Data + maths: scripts/kmesh_refplanes.gd.
## LOADING: "Model: add a reference image" (S box) opens the file dialog; or drop a picture on the window while the model
##   preview is open (main._on_drop). It becomes a textured plane on the panel's axis, behind the mesh, its bottom on the
##   mesh's bottom, as tall as the mesh.
## PANEL (per plane, the list picks which): axis front / side / top, opacity 0-100 %, offset right / up / depth (cm),
##   height ("180", "180 cm", "1.8 m" + Enter: the picture is that tall), TWO POINTS (click two points on the picture,
##   then type their real distance + Enter), flip, lock (placement and size frozen), only in its view (front only while
##   the camera looks down -Z within 10 deg, side down -X, top down -Y), remove.
## PICKS: the planes are drawn only. The mesh's pick never sees them, so a click goes through to the mesh; only the two
##   clicks of TWO POINTS go to the picture (and only while armed: Esc disarms).
## Planes are saved with the mesh (.kmesh "refplanes": the picture's path + SHA-256, never the pixels).

var ui   # KMeshEditUI
var panel: PanelContainer
var cur := -1                 # the plane the panel edits
var nodes: Array = []         # MeshInstance3D per entry, children of ui.view
var two: Array = []           # the two-point clicks so far: picture uv
var armed := false
var shown := false            # the panel was opened by the op with no plane yet
var _view: Node3D
var _mesh: KMesh
var _tex := {}                # path -> Texture2D (null = could not load)
var _sync := false
var _list: OptionButton
var _axis: OptionButton
var _op: HSlider
var _op_lb: Label
var _off: Array = []          # SpinBox x3 (cm)
var _h: LineEdit
var _dist: LineEdit
var _two_bt: Button
var _flip: CheckBox
var _lock: CheckBox
var _only: CheckBox
var _locked_boxes: Array = []


func setup(edit_ui) -> void:
	ui = edit_ui
	_build_panel()


func planes() -> Array:
	return KMeshRefPlanes.list(ui.mesh) if ui != null and ui.mesh != null else []


func _process(_dt: float) -> void:
	var live: bool = ui != null and ui.on and ui.view != null and is_instance_valid(ui.view)
	if not live:
		if panel.visible:
			panel.visible = false
		nodes = []
		_view = null
		_mesh = null
		armed = false
		shown = false
		return
	if ui.view != _view or ui.mesh != _mesh or nodes.size() != planes().size():
		_view = ui.view
		_mesh = ui.mesh
		rebuild()
	_update_visibility()
	var want := not planes().is_empty() or shown
	if panel.visible != want:
		panel.visible = want
		if want:
			_refresh()
	if panel.visible:
		place()


## the planes' nodes from the mesh's list (after an open, a reopen, a load)
func rebuild() -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()
	nodes = []
	var l := planes()
	var warn := []
	for i in l.size():
		var e: Dictionary = l[i]
		var mi := MeshInstance3D.new()
		mi.name = "refplane_%d" % i
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		mi.mesh = q
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_override = _material(e)
		mi.transform = KMeshRefPlanes.xform(e)
		ui.view.add_child(mi)
		nodes.append(mi)
		if _tex.get(e["path"]) == null:
			warn.append("%s is missing (a grey plane holds its place)" % String(e["path"]).get_file())
		elif e["hash"] != "" and KMeshRefPlanes.hash_of(e["path"]) != e["hash"]:
			warn.append("%s changed since it was placed (its SHA-256 differs)" % String(e["path"]).get_file())
	cur = clampi(cur, -1, l.size() - 1)
	if cur < 0 and not l.is_empty():
		cur = 0
	if not warn.is_empty():
		ui.m._say("Model: reference images: " + "; ".join(warn))
	_refresh()


func _texture(path: String) -> Texture2D:
	if not _tex.has(path):
		var img := Image.load_from_file(path) if FileAccess.file_exists(path) else null
		_tex[path] = ImageTexture.create_from_image(img) if img != null and not img.is_empty() else null
	return _tex[path]


func _material(e: Dictionary) -> StandardMaterial3D:
	var mt := StandardMaterial3D.new()
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.cull_mode = BaseMaterial3D.CULL_DISABLED
	mt.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	var t := _texture(e["path"])
	mt.albedo_texture = t
	mt.albedo_color = Color(1, 1, 1, float(e["opacity"])) if t != null else Color(0.5, 0.5, 0.5, float(e["opacity"]) * 0.5)
	if bool(e["flip"]):
		mt.uv1_scale = Vector3(-1, 1, 1)
		mt.uv1_offset = Vector3(1, 0, 0)
	return mt


func _apply(i: int) -> void:
	var l := planes()
	if i < 0 or i >= l.size() or i >= nodes.size():
		return
	var e: Dictionary = l[i]
	var mi: MeshInstance3D = nodes[i]
	mi.transform = KMeshRefPlanes.xform(e)
	mi.material_override = _material(e)
	_update_visibility()


func _update_visibility() -> void:
	var cam: Camera3D = ui.m.cam
	var fwd := -cam.global_transform.basis.z
	var l := planes()
	for i in mini(l.size(), nodes.size()):
		var e: Dictionary = l[i]
		(nodes[i] as Node3D).visible = not bool(e["only_view"]) or KMeshRefPlanes.matches(e["axis"], fwd, ui.view.global_transform.basis.orthonormalized())


# ---------------------------------------------------------------- the edits (each returns what it said)

## a picture as a new plane on `axis` (the panel's axis when ""), behind the mesh
func add(path: String, axis := "") -> String:
	if not ui.on:
		return ""
	var t := _texture(path)
	if t == null:
		_tex.erase(path)
		return _say("could not read %s as a picture. Pick a .png, .jpg, .webp, .bmp or .tga file" % path.get_file())
	if axis == "":
		axis = KMeshRefPlanes.AXES[maxi(_axis.selected, 0)]
	var e := KMeshRefPlanes.entry(path, axis, Vector2(t.get_width(), t.get_height()), _box())
	var l := planes().duplicate()
	l.append(e)
	KMeshRefPlanes.store(ui.mesh, l)
	cur = l.size() - 1
	rebuild()
	panel.visible = true
	return _say("%s on a %s plane behind the mesh, %.1f cm tall, %d %% opaque. The panel sets its size, place and opacity; it is saved with the mesh" % [path.get_file(), axis, float(e["height"]) * 100.0, roundi(float(e["opacity"]) * 100.0)])


func remove(i := cur) -> String:
	var l := planes().duplicate()
	if i < 0 or i >= l.size():
		return _say("no reference image to remove")
	var nm := String(l[i]["path"]).get_file()
	l.remove_at(i)
	KMeshRefPlanes.store(ui.mesh, l)
	cur = mini(i, l.size() - 1)
	rebuild()
	return _say("removed %s" % nm)


func _box() -> AABB:
	var vs: PackedVector3Array = ui.mesh.verts
	if vs.is_empty():
		return AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)
	var b := AABB(vs[0], Vector3.ZERO)
	for v in vs:
		b = b.expand(v)
	return b


func _e(i: int) -> Dictionary:
	var l := planes()
	return l[i] if i >= 0 and i < l.size() else {}


func _locked(e: Dictionary) -> bool:
	return not e.is_empty() and bool(e["lock"])


func set_opacity(pct: float, i := cur) -> String:
	var e := _e(i)
	if e.is_empty():
		return ""
	e["opacity"] = clampf(pct / 100.0, 0.0, 1.0)
	_apply(i)
	_refresh()
	return _say("%s %d %% opaque" % [String(e["path"]).get_file(), roundi(float(e["opacity"]) * 100.0)])


## offset right / up / depth from where it was placed, in cm
func set_offset(cm: Vector3, i := cur) -> String:
	var e := _e(i)
	if e.is_empty() or _locked(e):
		return _say("that reference image is locked: untick Lock to move it") if _locked(e) else ""
	var h0 := float(e["height"]) * 0.5 if e["axis"] != "top" else 0.0
	e["offset"] = [cm.x / 100.0, cm.y / 100.0 + h0, cm.z / 100.0]
	_apply(i)
	_refresh()
	return ""


func offset_cm(i := cur) -> Vector3:
	var e := _e(i)
	if e.is_empty():
		return Vector3.ZERO
	var h0 := float(e["height"]) * 0.5 if e["axis"] != "top" else 0.0
	return Vector3(float(e["offset"][0]), float(e["offset"][1]) - h0, float(e["offset"][2])) * 100.0


## "180" / "180 cm" / "1.8 m": the picture is that tall (its bottom edge stays)
func set_height_text(s: String, i := cur) -> String:
	var e := _e(i)
	if e.is_empty():
		return ""
	if _locked(e):
		return _say("that reference image is locked: untick Lock to size it")
	var h := KMeshRefPlanes.parse_len(s)
	if is_nan(h):
		return _say("'%s' is not a length: type 180 (cm), 180 cm or 1.8 m" % s)
	KMeshRefPlanes.set_height(e, h)
	_apply(i)
	_refresh()
	return _say("%s is %.1f cm tall now" % [String(e["path"]).get_file(), float(e["height"]) * 100.0])


func set_axis(axis: String, i := cur) -> String:
	var e := _e(i)
	if e.is_empty() or not axis in KMeshRefPlanes.AXES:
		return ""
	if _locked(e):
		_refresh()
		return _say("that reference image is locked: untick Lock to turn it")
	var n := KMeshRefPlanes.entry(e["path"], axis, Vector2(float(e["aspect"]), 1.0), _box())
	for k in ["hash", "opacity", "flip", "lock", "only_view"]:
		n[k] = e[k]
	KMeshRefPlanes.set_height(n, float(e["height"]))
	e.merge(n, true)
	_apply(i)
	_refresh()
	return _say("%s on the %s plane" % [String(e["path"]).get_file(), axis])


func set_flag(flag: String, v: bool, i := cur) -> String:
	var e := _e(i)
	if e.is_empty() or not flag in ["flip", "lock", "only_view"]:
		return ""
	if flag == "flip" and _locked(e):
		_refresh()
		return _say("that reference image is locked: untick Lock to flip it")
	e[flag] = v
	_apply(i)
	_refresh()
	match flag:
		"flip": return _say("%s %s" % [String(e["path"]).get_file(), "mirrored" if v else "as the file is"])
		"lock": return _say("%s %s" % [String(e["path"]).get_file(), "locked: its place and size stay" if v else "unlocked"])
	return _say("%s %s" % [String(e["path"]).get_file(), ("drawn only in the %s view (looking down %s)" % [e["axis"], {"front": "-Z", "side": "-X", "top": "-Y"}[e["axis"]]]) if v else "drawn in every view"])


## TWO POINTS: the next two clicks on the picture mark two points; then type their real distance
func arm_two_points() -> String:
	var e := _e(cur)
	if e.is_empty():
		return _say("add a reference image first (drop a picture on the window)")
	if _locked(e):
		return _say("that reference image is locked: untick Lock to scale it")
	armed = true
	two = []
	return _say("click two points on %s whose real distance you know (Esc cancels)" % String(e["path"]).get_file())


func apply_two_points(s: String) -> String:
	var e := _e(cur)
	if e.is_empty() or two.size() < 2:
		return _say("press Two points and click two points on the picture first")
	if _locked(e):
		return _say("that reference image is locked: untick Lock to scale it")
	var d := KMeshRefPlanes.parse_len(s)
	if is_nan(d):
		return _say("'%s' is not a length: type 50 (cm), 50 cm or 0.5 m" % s)
	KMeshRefPlanes.set_height(e, KMeshRefPlanes.height_for(e, two[0], two[1], d))
	_apply(cur)
	_refresh()
	return _say("%s scaled: the two points are %.1f cm apart, the picture %.1f cm tall" % [String(e["path"]).get_file(), d * 100.0, float(e["height"]) * 100.0])


## main's unhandled input, while the preview is open: only the two-point clicks (and Esc while armed) are taken
func input(ev: InputEvent) -> bool:
	if not armed:
		return false
	if ev is InputEventKey and ev.pressed and (ev as InputEventKey).keycode == KEY_ESCAPE:
		armed = false
		two = []
		_say("two points cancelled")
		return true
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if not ev.pressed:
			return true
		var e := _e(cur)
		var cam: Camera3D = ui.m.cam
		var p: Vector2 = (ev as InputEventMouseButton).position
		var inv: Transform3D = ui.view.global_transform.affine_inverse()
		var uv = KMeshRefPlanes.ray_uv(e, inv * cam.project_ray_origin(p), inv.basis * cam.project_ray_normal(p))
		if uv == null:
			_say("that is not on the picture: click on %s" % String(e["path"]).get_file())
			return true
		two.append(uv)
		if two.size() >= 2:
			armed = false
			_dist.grab_focus()
			_say("two points marked: type their real distance (180, 50 cm, 0.5 m) in the panel and press Enter")
		else:
			_say("first point marked: click the second")
		return true
	return false


func _say(s: String) -> String:
	ui.m._say("Model: " + s)
	return "Model: " + s


## the S box op (mesh_tools.gd): open the file dialog (the panel shows)
func open_dialog() -> String:
	shown = true
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.bmp, *.tga ; pictures"])
	fd.use_native_dialog = true
	fd.title = "Reference image: a picture file"
	fd.file_selected.connect(func(p): add(p); fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	ui.m.add_child(fd)
	fd.popup_centered(Vector2i(800, 500))
	return _say("pick a picture (or drop one on the window): it goes on the %s plane behind the mesh" % KMeshRefPlanes.AXES[maxi(_axis.selected, 0)])


# ---------------------------------------------------------------- the panel

func _build_panel() -> void:
	panel = PanelContainer.new()
	panel.name = "refplanes_panel"
	panel.visible = false
	var vb := VBoxContainer.new()
	var title := Label.new()
	title.text = "Reference images"
	vb.add_child(title)
	var r1 := HBoxContainer.new()
	_list = OptionButton.new()
	_list.name = "rp_list"
	_list.custom_minimum_size.x = 150
	_list.clip_text = true
	_list.item_selected.connect(func(i): cur = i; _refresh())
	r1.add_child(_list)
	r1.add_child(_btn("rp_add", "Add", "pick a picture: a new plane on the axis below, behind the mesh", func(): open_dialog()))
	r1.add_child(_btn("rp_remove", "Remove", "remove this reference image", func(): remove()))
	vb.add_child(r1)
	var g := GridContainer.new()
	g.columns = 2
	g.add_child(_lb("Axis"))
	_axis = OptionButton.new()
	_axis.name = "rp_axis"
	for a in KMeshRefPlanes.AXES:
		_axis.add_item(a)
	_axis.tooltip_text = "front: seen looking down -Z; side: down -X; top: down -Y"
	_axis.item_selected.connect(func(i): if not _sync: set_axis(KMeshRefPlanes.AXES[i]))
	g.add_child(_axis)
	g.add_child(_lb("Opacity"))
	var oh := HBoxContainer.new()
	_op = HSlider.new()
	_op.name = "rp_opacity"
	_op.min_value = 0
	_op.max_value = 100
	_op.step = 1
	_op.custom_minimum_size.x = 100
	_op.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_op.value_changed.connect(func(v): if not _sync: set_opacity(v))
	oh.add_child(_op)
	_op_lb = Label.new()
	_op_lb.custom_minimum_size.x = 40
	oh.add_child(_op_lb)
	g.add_child(oh)
	g.add_child(_lb("Offset cm"))
	var ofh := HBoxContainer.new()
	for k in 3:
		var sb := SpinBox.new()
		sb.name = "rp_off_%s" % ["x", "y", "z"][k]
		sb.min_value = -1000
		sb.max_value = 1000
		sb.step = 0.1
		sb.allow_greater = true
		sb.allow_lesser = true
		sb.custom_minimum_size.x = 64
		sb.tooltip_text = ["right", "up", "toward the camera (depth)"][k]
		sb.value_changed.connect(func(_v): if not _sync: set_offset(Vector3(_off[0].value, _off[1].value, _off[2].value)))
		_off.append(sb)
		_locked_boxes.append(sb)
		ofh.add_child(sb)
	g.add_child(ofh)
	g.add_child(_lb("Height"))
	_h = LineEdit.new()
	_h.name = "rp_height"
	_h.placeholder_text = "180 cm"
	_h.tooltip_text = "how tall the picture is in real life: 180, 180 cm or 1.8 m, then Enter"
	_h.text_submitted.connect(func(t): set_height_text(t))
	_locked_boxes.append(_h)
	g.add_child(_h)
	_two_bt = _btn("rp_two", "Two points", "click two points on the picture, then type their real distance", func(): arm_two_points())
	_locked_boxes.append(_two_bt)
	g.add_child(_two_bt)
	_dist = LineEdit.new()
	_dist.name = "rp_dist"
	_dist.placeholder_text = "their distance"
	_dist.tooltip_text = "the two points' real distance: 50, 50 cm or 0.5 m, then Enter"
	_dist.text_submitted.connect(func(t): apply_two_points(t))
	_locked_boxes.append(_dist)
	g.add_child(_dist)
	vb.add_child(g)
	var r3 := HBoxContainer.new()
	_flip = _chk("rp_flip", "Flip", "mirror the picture left-right", func(v): set_flag("flip", v))
	_lock = _chk("rp_lock", "Lock", "freeze its place and size", func(v): set_flag("lock", v))
	_only = _chk("rp_only", "Only in its view", "drawn only while the camera looks along its axis (front: down -Z)", func(v): set_flag("only_view", v))
	_locked_boxes.append(_flip)
	for c in [_flip, _lock, _only]:
		r3.add_child(c)
	vb.add_child(r3)
	panel.add_child(vb)
	ui.m.ui_root.add_child(panel)


func _lb(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l


func _btn(nm: String, t: String, tip: String, f: Callable) -> Button:
	var b := Button.new()
	b.name = nm
	b.text = t
	b.tooltip_text = tip
	b.pressed.connect(f)
	return b


func _chk(nm: String, t: String, tip: String, f: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.name = nm
	c.text = t
	c.tooltip_text = tip
	c.toggled.connect(func(v): if not _sync: f.call(v))
	return c


## the panel's fields from the picked plane
func _refresh() -> void:
	if panel == null:
		return
	_sync = true
	var l := planes()
	_list.clear()
	for i in l.size():
		_list.add_item("%s: %s" % [l[i]["axis"], String(l[i]["path"]).get_file()])
	var e := _e(cur)
	if not e.is_empty():
		_list.select(cur)
		_axis.select(KMeshRefPlanes.AXES.find(e["axis"]))
		_op.value = roundf(float(e["opacity"]) * 100.0)
		_op_lb.text = "%d %%" % roundi(float(e["opacity"]) * 100.0)
		var o := offset_cm()
		for k in 3:
			_off[k].value = o[k]
		if not _h.has_focus():
			_h.text = "%.1f cm" % (float(e["height"]) * 100.0)
		_flip.button_pressed = bool(e["flip"])
		_lock.button_pressed = bool(e["lock"])
		_only.button_pressed = bool(e["only_view"])
	var lk := _locked(e) or e.is_empty()
	for c in _locked_boxes:
		if c is SpinBox:
			(c as SpinBox).editable = not lk
		elif c is LineEdit:
			(c as LineEdit).editable = not lk
		elif c is BaseButton:
			(c as BaseButton).disabled = lk
	_axis.disabled = lk
	for c in [_op, _lock, _only]:
		if c is BaseButton:
			(c as BaseButton).disabled = e.is_empty()
		else:
			(c as Range).editable = not e.is_empty()
	_sync = false


## bottom left of the clear view, above the say-line; never past the clear view's top
func place() -> void:
	var cl: Rect2 = ui.m.nav_clear_rect()
	panel.reset_size()
	var sz := panel.get_combined_minimum_size()
	panel.size = sz
	panel.position = Vector2(cl.position.x + 12.0, maxf(cl.position.y, cl.end.y - sz.y - 12.0))
