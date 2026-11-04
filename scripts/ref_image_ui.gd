## REFERENCE IMAGE: the nodes, the file dialog, the panel and the Match command (the maths is scripts/ref_image.gd).
## "View: reference image..." loads a PNG / JPG as an overlay on the 3D view (camera mode) or as a plane behind the body
## (front / side / free). The entry lives in the scene file (Scene.refimgs); the picture itself is never copied: the entry
## holds its path, relative to the scene file when it could be. Every change is one undo step (the scene's snapshot holds
## "refimgs"). MATCH runs tools/see_image.py (plain python, a separate process, polled each frame: the window keeps working) on
## the one picture; with no detector in the environment it falls back to a 2-point fit: click the head top, then the heel.
class_name RefImageUI
extends RefCounted

const LAYER := -1       # canvas layer: under every panel, over the 3D world
var m: Node
var python := "python"   # the interpreter with mediapipe + opencv (tests point it at a stub)
var tool := "res://tools/see_image.py"
var last := {}           # the last fit: {"method", "res_px", "n", "scale", "offset"}
var win: Window = null
var picking := 0         # 0 not picking, 1 head top next, 2 heel next
var layer: CanvasLayer = null
var _picker: Control = null
var _pick0 := Vector2.ZERO
var _sig := ""
var _nodes := []         # per drawn entry: {"i", "node", "size"}
var _tex := {}           # absolute path -> {"tex", "size", "mtime"}
var _pid := -1
var _out := ""
var _warned := ""
var _dragging := false
var _panel_busy := false
var _ctl := {}


func _init(main: Node) -> void:
	m = main


# ---------------------------------------------------------------- paths and textures

func scene_dir() -> String:
	return "" if m.scene_path == "" else ProjectSettings.globalize_path(m.scene_path).get_base_dir()


func abs_path(e: Dictionary) -> String:
	return ProjectSettings.globalize_path(RefImage.resolve(String(e["path"]), scene_dir()))


## the picture of a path: {"tex", "size"}, cached until the file changes; {} when it cannot be read
func texture_of(p: String) -> Dictionary:
	if not FileAccess.file_exists(p):
		return {}
	var mt := FileAccess.get_modified_time(p)
	if _tex.has(p) and _tex[p]["mtime"] == mt:
		return _tex[p]
	var img := Image.load_from_file(p)
	if img == null or img.is_empty():
		return {}
	_tex[p] = {"tex": ImageTexture.create_from_image(img), "size": Vector2(img.get_width(), img.get_height()), "mtime": mt}
	return _tex[p]


func view_rect() -> Rect2:
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var top := float(m.TOP_H)
	return Rect2(m.lw(), top, vs.x - m.lw() - m.rw(), vs.y - top - float(m.bottom_h) - 6.0 - float(m.LINE_H))


func list() -> Array:
	return m.S.refimgs


func active() -> int:
	return list().size() - 1


# ---------------------------------------------------------------- the nodes

## makes the nodes match the scene's list (rebuilt when it changes, laid out every call). Cheap when there is none
func sync() -> void:
	var L: Array = list()
	if L.is_empty() and _nodes.is_empty():
		_sig = ""
		return
	var sig := JSON.stringify(L) + "|" + scene_dir()
	if sig != _sig:
		_sig = sig
		_rebuild(L)
	layout_all()


func _rebuild(L: Array) -> void:
	for n in _nodes:
		if is_instance_valid(n["node"]):
			(n["node"] as Node).get_parent().remove_child(n["node"])
			(n["node"] as Node).queue_free()
	_nodes = []
	for i in L.size():
		var e: Dictionary = L[i]
		var t := texture_of(abs_path(e))
		if t.is_empty():
			if _warned != String(e["path"]):
				_warned = String(e["path"])
				m._say("reference image not found: %s. Load it again with View: reference image..., or remove it in the reference panel" % String(e["path"]))
			continue
		if String(e["mode"]) == "camera":
			if layer == null:
				layer = CanvasLayer.new()
				layer.layer = LAYER
				layer.name = "RefImgLayer"
				m.add_child(layer)
			var tr := TextureRect.new()
			tr.name = "RefImg%d" % i
			tr.texture = t["tex"]
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_SCALE
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			layer.add_child(tr)
			_nodes.append({"i": i, "node": tr, "size": t["size"]})
		else:
			var mi := MeshInstance3D.new()
			mi.name = "RefPlane%d" % i
			var q := QuadMesh.new()
			mi.mesh = q
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.albedo_texture = t["tex"]
			mi.material_override = mat
			var par: Node = m.skel.get_parent() if m.skel != null and m.skel.get_parent() != null else m
			par.add_child(mi)
			_nodes.append({"i": i, "node": mi, "size": t["size"]})


func layout_all() -> void:
	var L: Array = list()
	var view := view_rect()
	for n in _nodes:
		if n["i"] >= L.size() or not is_instance_valid(n["node"]):
			continue
		var e: Dictionary = L[n["i"]]
		var sz: Vector2 = n["size"]
		if n["node"] is TextureRect:
			var tr := n["node"] as TextureRect
			var r := RefImage.layout(view, sz, e)
			tr.position = r.position
			tr.size = r.size
			tr.flip_h = bool(e["flip"])
			tr.modulate = Color(1, 1, 1, float(e["opacity"]))
		else:
			var mi := n["node"] as MeshInstance3D
			var h := RefImage.BASE_H * float(e["scale"])
			(mi.mesh as QuadMesh).size = Vector2(h * sz.x / sz.y, h)
			mi.transform = Transform3D(RefImage.plane_basis(e), RefImage.plane_centre(e))
			var mat := mi.material_override as StandardMaterial3D
			mat.albedo_color = Color(1, 1, 1, float(e["opacity"]))
			mat.uv1_scale = Vector3(-1.0 if bool(e["flip"]) else 1.0, 1, 1)
			mat.uv1_offset = Vector3(1.0 if bool(e["flip"]) else 0.0, 0, 0)


## the node drawn for entry i (the tests read it): TextureRect or MeshInstance3D, null when none
func node_of(i: int) -> Node:
	for n in _nodes:
		if n["i"] == i:
			return n["node"]
	return null


func size_of(i: int) -> Vector2:
	for n in _nodes:
		if n["i"] == i:
			return n["size"]
	return Vector2.ZERO


# ---------------------------------------------------------------- the commands (each one undo step)

func ask() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.bmp ; pictures"])
	fd.use_native_dialog = true
	fd.title = "Reference image: a photo or video frame of a person"
	fd.file_selected.connect(func(p): load_path(p); fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	m.add_child(fd)
	fd.popup_centered(Vector2i(800, 500))


func load_path(path: String, mode := "camera") -> bool:
	if not FileAccess.file_exists(path):
		m._say("could not read %s: no such file; pick a PNG or JPG with View: reference image..." % path.get_file())
		return false
	var t := texture_of(path)
	if t.is_empty():
		m._say("could not read %s as a picture; pick a PNG or JPG with View: reference image..." % path.get_file())
		return false
	m._push_undo()
	m.S.refimgs.append(RefImage.entry(RefImage.store_path(path, scene_dir()), mode))
	sync()
	_panel_sync()
	m._say("reference image %s on the view at %d %%: View: reference panel changes opacity, size, offset and flip; Match fits the body to it (Ctrl+Z takes it away)" % [path.get_file(), 50])
	return true


## change fields of the active entry as ONE undo step
func set_fields(f: Dictionary) -> bool:
	if list().is_empty():
		m._say("no reference image yet: load one with View: reference image...")
		return false
	m._push_undo()
	_apply(f)
	return true


func _apply(f: Dictionary) -> void:
	var e: Dictionary = list()[active()]
	for k in f:
		e[k] = f[k]
	m.S.refimgs = RefImage.clean(m.S.refimgs)
	sync()
	_panel_sync()


func remove() -> void:
	if list().is_empty():
		m._say("no reference image to remove: load one with View: reference image...")
		return
	m._push_undo()
	m.S.refimgs.pop_back()
	sync()
	_panel_sync()
	m._say("reference image removed (Ctrl+Z puts it back)")


# ---------------------------------------------------------------- MATCH

func match_body() -> void:
	if VideoAddon.gate("matching a picture") != "":   # C78
		m._say(VideoAddon.gate("matching a picture"))
		return
	if list().is_empty():
		m._say("nothing to match yet: load a picture of a person with View: reference image...")
		return
	if _pid >= 0:
		m._say("still looking for the person in the picture; try again when it arrives")
		return
	var e: Dictionary = list()[active()]
	var dir := OS.get_user_data_dir().path_join("refimg")
	DirAccess.make_dir_recursive_absolute(dir)
	_out = dir.path_join("landmarks.json")
	if FileAccess.file_exists(_out):
		DirAccess.remove_absolute(_out)
	_pid = OS.create_process(python, PackedStringArray([ProjectSettings.globalize_path(tool), abs_path(e), _out]))
	Children.add(_pid)
	if _pid < 0:
		_no_detector("the interpreter \"%s\" did not start" % python)
		return
	m._say("finding the person in the picture...")


func poll(_dt: float) -> void:
	if not _nodes.is_empty():
		layout_all()
	if _pid < 0 or OS.is_process_running(_pid):
		return
	Children.done(_pid)
	_pid = -1
	var d = JSON.parse_string(FileAccess.get_file_as_string(_out)) if FileAccess.file_exists(_out) else null
	if not d is Dictionary or not (d as Dictionary).has("image"):
		_no_detector("the detector found no person, or mediapipe / opencv is not installed (tools/see_image.py)")
		return
	apply_landmarks(d["image"])


func _no_detector(why: String) -> void:
	m._say("no pose detector (%s): the 2-point fit instead. Click the person's HEAD TOP on the picture, then the HEEL" % why)
	begin_pick()


func _proj(p: Vector3) -> Vector2:
	return m.cam.unproject_position(p)


## fit the picture from 33 detected landmarks [[x, y, visibility]] (normalised to the picture). One undo step
func apply_landmarks(lms: Array) -> Dictionary:
	if list().is_empty():
		return {"ok": false}
	var e: Dictionary = list()[active()]
	var sz := size_of(active())
	if sz == Vector2.ZERO:
		m._say("the reference picture is not loaded: load it again with View: reference image...")
		return {"ok": false}
	var r := RefImage.fit_landmarks(m.B, lms, sz, e, view_rect(), _proj)
	return _land(r, "detector", sz)


func _land(r: Dictionary, method: String, sz: Vector2) -> Dictionary:
	if not r["ok"] or int(r["n"]) < 2:
		m._say("the fit needs at least 2 visible points on the person: use a picture where the whole body shows, or the 2-point fit")
		return {"ok": false}
	m._push_undo()
	_apply({"scale": r["scale"], "offset": r["offset"]})
	var e: Dictionary = list()[active()]
	last = {"method": method, "res_px": r["res_px"], "n": r["n"], "scale": r["scale"], "offset": r["offset"], "ok": true}
	m._say("matched the body to the picture (%s): scale %.2f, mean residual %.1f px over %d points (Ctrl+Z takes it back)" % [method, float(r["scale"]), float(r["res_px"]), int(r["n"])])
	return last


## the 2-point fit: s0 = the head top and s1 = the heel, as clicked on the view (screen px). Camera mode
func apply_two_point(s0: Vector2, s1: Vector2) -> Dictionary:
	if list().is_empty():
		return {"ok": false}
	var e: Dictionary = list()[active()]
	var sz := size_of(active())
	if String(e["mode"]) != "camera" or sz == Vector2.ZERO:
		m._say("the 2-point fit works on the camera overlay: set the reference to Camera in the reference panel, then Match again")
		return {"ok": false}
	var view := view_rect()
	var heel: Vector3 = VideoImport.heel(m.B, "_l")
	var hr: Vector3 = VideoImport.heel(m.B, "_r")
	if hr.y < heel.y:
		heel = hr
	var pts := [[RefImage.screen_to_uv(view, sz, e, s0), m.B.E["head"]], [RefImage.screen_to_uv(view, sz, e, s1), heel]]
	var r := RefImage.fit_pairs(pts, sz, e, view, _proj)
	return _land(r, "2-point", sz)


func begin_pick() -> void:
	picking = 1
	if _picker == null:
		var cl := CanvasLayer.new()
		cl.layer = 100
		cl.name = "RefImgPick"
		m.add_child(cl)
		_picker = Control.new()
		_picker.set_anchors_preset(Control.PRESET_FULL_RECT)
		_picker.mouse_filter = Control.MOUSE_FILTER_STOP
		_picker.mouse_default_cursor_shape = Control.CURSOR_CROSS
		_picker.gui_input.connect(_pick_input)
		cl.add_child(_picker)
		_picker.set_meta("cl", cl)
	_picker.visible = true


func _pick_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
		_end_pick()
		m._say("2-point fit cancelled: Match starts it again")
		return
	if not (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT):
		return
	if picking == 1:
		_pick0 = ev.position
		picking = 2
		m._say("now click the HEEL (the bottom of the foot) of the same person")
	elif picking == 2:
		var s1: Vector2 = ev.position
		_end_pick()
		apply_two_point(_pick0, s1)


func _end_pick() -> void:
	picking = 0
	if _picker != null:
		_picker.visible = false


# ---------------------------------------------------------------- the panel

func open_panel() -> void:
	if win != null and is_instance_valid(win):
		win.popup_centered()
		_panel_sync()
		return
	win = Window.new()
	win.title = "Reference image"
	win.size = Vector2i(360, 380)
	win.exclusive = false
	win.transient = true
	win.close_requested.connect(func(): win.hide())
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 10
	box.offset_right = -10
	box.offset_top = 10
	box.offset_bottom = -10
	win.add_child(box)
	var mode := OptionButton.new()
	for md in [["Camera overlay", "camera"], ["Plane: front", "front"], ["Plane: side", "side"], ["Plane: free", "free"]]:
		mode.add_item(md[0])
	mode.tooltip_text = "an overlay on the view, or a plane behind the body (front view, his right view, or free)"
	mode.item_selected.connect(func(i): if not _panel_busy: set_fields({"mode": RefImage.MODES[i]}))
	box.add_child(mode)
	_ctl["mode"] = mode
	for sp in [["opacity", "Opacity", 0.0, 1.0, 0.01], ["scale", "Scale", 0.1, 4.0, 0.01], ["ox", "Offset across", -1.5, 1.5, 0.005], ["oy", "Offset up/down", -1.5, 1.5, 0.005]]:
		var row := HBoxContainer.new()
		var lb := Label.new()
		lb.text = sp[1]
		lb.custom_minimum_size = Vector2(110, 0)
		row.add_child(lb)
		var sl := HSlider.new()
		sl.min_value = sp[2]
		sl.max_value = sp[3]
		sl.step = sp[4]
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.drag_started.connect(func(): _dragging = true; if not list().is_empty(): m._push_undo())
		sl.drag_ended.connect(func(_c): _dragging = false)
		sl.value_changed.connect(_slider.bind(sp[0]))
		row.add_child(sl)
		box.add_child(row)
		_ctl[sp[0]] = sl
	var fl := CheckBox.new()
	fl.text = "Flip left-right"
	fl.toggled.connect(func(on): if not _panel_busy: set_fields({"flip": on}))
	box.add_child(fl)
	_ctl["flip"] = fl
	var bm := Button.new()
	bm.text = "Match: fit the body to the reference"
	bm.tooltip_text = "finds the person in the picture and scales + moves it so their height and hips line up with the body as this camera sees it; says the residual in pixels"
	bm.pressed.connect(match_body)
	box.add_child(bm)
	var b2 := Button.new()
	b2.text = "2-point fit (click head top, heel)"
	b2.pressed.connect(begin_pick)
	box.add_child(b2)
	var br := Button.new()
	br.text = "Remove the reference"
	br.pressed.connect(remove)
	box.add_child(br)
	m.add_child(win)
	win.popup_centered()
	_panel_sync()


func _slider(v: float, key: String) -> void:
	if _panel_busy or list().is_empty():
		return
	if not _dragging:
		m._push_undo()   # a keyboard step: its own undo step
	var e: Dictionary = list()[active()]
	match key:
		"opacity", "scale":
			_apply({key: v})
		"ox":
			_apply({"offset": [v, e["offset"][1]]})
		"oy":
			_apply({"offset": [e["offset"][0], v]})


func _panel_sync() -> void:
	if win == null or not is_instance_valid(win) or _ctl.is_empty() or list().is_empty():
		return
	_panel_busy = true
	var e: Dictionary = list()[active()]
	(_ctl["mode"] as OptionButton).select(RefImage.MODES.find(String(e["mode"])))
	(_ctl["opacity"] as HSlider).value = float(e["opacity"])
	(_ctl["scale"] as HSlider).value = float(e["scale"])
	(_ctl["ox"] as HSlider).value = float(e["offset"][0])
	(_ctl["oy"] as HSlider).value = float(e["offset"][1])
	(_ctl["flip"] as CheckBox).button_pressed = bool(e["flip"])
	_panel_busy = false
