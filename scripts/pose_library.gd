## pose_library.gd - THE POSE LIBRARY (docs/GAP_ANALYSIS.md row 8; what it matches of Blender's Pose Library and Maya's
## Studio Library: docs/research/POSE_LIBRARY.md).
## A panel with every saved pose as a THUMBNAIL in a grid. On a thumbnail:
##   click            = apply the pose (one undo step)
##   drag right       = BLEND: the body mixes from the pose it had at the press toward the library pose, 0..100 % live
##                      (160 px = 100 %); release = one undo step; right-click while dragging = cancel
##   Ctrl (or the Flipped box) = the pose MIRRORED left <-> right (Body.pose_paste's reflection)
##   right-click      = Apply / Apply flipped / Blend 50 % / Select the parts it moves / Remake the thumbnail
## The Blend slider does the same on the picked thumbnail. "Only the selected parts" = only the parts selected in the
## view (Ctrl+click for more); every other joint and the hips are left bit for bit.
## What moves: the joints' angles (per joint SLERP, Breakdowner.slerp_ang) and, on a whole-body apply, the hips'
## offset (lerped). The weapon stays in the hand it is in (Blender's library applies bone transforms only).
## THUMBNAILS: rendered off screen (a SubViewport with its own world: a clean mannequin, no weapon, no props, the same
## camera every time), saved next to the pose as <name>.png, and remade when the pose file changes (its md5 differs
## from the one the picture was made from, or the .json is newer than the .png). Under a test script the pictures are
## only kept in memory unless the pose lives in user:// (tests never write poses/ or moves/).
class_name PoseLibrary
extends PanelContainer

const DIRS := ["res://poses/lib", "res://poses", "res://moves"]
const THUMB := Vector2i(160, 200)        # the picture as rendered and saved (px)
const CELL := Vector2(92, 115)           # as shown in the grid
const BLEND_PX := 160.0                  # a drag this far to the right = 100 %
const BG := Color(0.23, 0.24, 0.27)      # the picture's backdrop: content (saved in the file, the same in both themes)
const SKIN := Color(0.78, 0.72, 0.64)    # the mannequin's skin, as main's
const CAM_AT := Vector3(0.0, 0.98, 0.0)  # the camera looks here (m, the body's space)
const CAM_FROM := Vector3(1.9, 1.55, 3.6)
const CAM_SIZE := 2.35                   # orthographic height (m): a raised arm (2.2 m) still fits

var m: Node
var dirs: Array = DIRS.duplicate()
var entries: Array = []        # [{"path", "name", "mine"}]
var picked := ""               # the picked pose's path
var mood := ""                 # the mood chip lit ("" = All): the grid shows the poses whose measured body meets it (scripts/pose_mood.gd)
var tex := {}                  # path -> ImageTexture (its thumbnail)
var made := {}                 # path -> md5 of the pose file the thumbnail was made from
var renders := 0               # thumbnails rendered this session (the test reads it)
var flip_box: CheckBox
var only_box: CheckBox
var slider: HSlider
var readout: Label
var grid: HFlowContainer
var menu: PopupMenu
var cells := {}                # path -> its cell
var _queue: Array = []
var _busy := false
var _vp: SubViewport
var _sk: Skeleton3D
var _idx := {}
var _tb: Body
var _poll := 0.0
var _sig := ""                 # the listing the cells were built from
# a blend in progress (one undo step): the body as it was at the press, the target, the scope
var _base := {}
var _lock := {}
var _clip := {}
var _flip := false
var _only: Array = []
var _f := 0.0
var _press := {}
var _slider_drag := false


## the panel on main m: made on first use, shown / hidden after
static func toggle(main: Node) -> void:
	var p: PoseLibrary = main.get_meta("pose_library") if main.has_meta("pose_library") else null
	if p == null:
		p = PoseLibrary.new()
		p.m = main
		p.name = "pose_library"
		main.ui_root.add_child(p)
		main.set_meta("pose_library", p)
		p.visible = true
	else:
		p.visible = not p.visible
	if p.visible:
		p.refresh()
		main._say("the pose library: click a picture to apply it, drag right on it to blend 0-100 %, Ctrl = flipped, right-click = more")
	else:
		main._say("pose library closed: Pose library (POSE tab) opens it again")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var st: StyleBox = m.ui_find_box if m.get("ui_find_box") != null else null
	if st == null:
		var f := StyleBoxFlat.new()
		f.bg_color = Tok.c("float")
		f.set_corner_radius_all(8)
		f.set_content_margin_all(10)
		st = f
	add_theme_stylebox_override("panel", st)
	# ROADMAP 96: Library > Imported (the packs read in) is one more folder of poses, the library's own (a test's too)
	var imp_dir: String = String(m.library).path_join(PosePack.IMPORTED)
	if not dirs.has(imp_dir):
		dirs.append(imp_dir)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := Label.new()
	title.text = "POSE LIBRARY"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Tok.c("heading"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_btn("Close", func(): PoseLibrary.toggle(m)))
	# ROADMAP 96: the asset store: a pack (*.kinepack) read, checked and put in Library > Imported
	var imp := _btn("Import pack...", func(): PosePack.import_ask(m, func(): refresh()))
	imp.name = "button_import_pack"
	imp.tooltip_text = "read a pose pack (.kinepack) someone shared: checked first, then added to Library > Imported"
	head.add_child(imp)
	head.move_child(imp, 1)   # before Close
	var opts := HBoxContainer.new()
	v.add_child(opts)
	flip_box = CheckBox.new()
	flip_box.name = "check_flipped"
	flip_box.text = "Flipped"
	flip_box.focus_mode = Control.FOCUS_NONE
	flip_box.tooltip_text = "apply and blend the poses mirrored left <-> right (or hold Ctrl)"
	opts.add_child(flip_box)
	only_box = CheckBox.new()
	only_box.name = "check_selected_only"
	only_box.text = "Only the selected parts"
	only_box.focus_mode = Control.FOCUS_NONE
	only_box.tooltip_text = "apply and blend on the parts selected in the view only (Ctrl+click parts for more); the rest keep their pose"
	opts.add_child(only_box)
	v.add_child(_mood_row())
	var row := HBoxContainer.new()
	v.add_child(row)
	var bl := Label.new()
	bl.text = "Blend"
	row.add_child(bl)
	slider = HSlider.new()
	slider.name = "slider_blend"
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.focus_mode = Control.FOCUS_NONE
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.tooltip_text = "mix the body toward the picked pose: 0 = as it is, 100 = the library pose; release keeps it (one Ctrl+Z)"
	slider.value_changed.connect(_slider_value)
	slider.drag_started.connect(_slider_start)
	slider.drag_ended.connect(_slider_end)
	row.add_child(slider)
	readout = Label.new()
	readout.custom_minimum_size = Vector2(44, 0)
	readout.text = "0 %"
	row.add_child(readout)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size = Vector2(0, 200)
	v.add_child(sc)
	grid = HFlowContainer.new()
	grid.name = "pose_grid"
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	sc.add_child(grid)
	var hint := Label.new()
	hint.text = "click = apply   drag right = blend   Ctrl = flipped   right-click = more"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Tok.dim(0.6))
	v.add_child(hint)
	menu = PopupMenu.new()
	menu.name = "pose_library_menu"
	menu.id_pressed.connect(_menu)
	add_child(menu)
	_place()


func _btn(t: String, f: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(f)
	return b


## to the left of the inspector, from under the ribbon to over the cards
func _place() -> void:
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	offset_right = -float(m.rw()) - 12.0
	offset_left = offset_right - 440.0
	offset_top = 86.0
	offset_bottom = -268.0


func _process(dt: float) -> void:
	if not visible:
		return
	_place()
	_poll += dt
	if _poll > 1.5 and _base.is_empty():
		_poll = 0.0
		refresh()


# ------------------------------------------------------------------ the list and its thumbnails

## the poses in dirs (scenes skipped, as main's Poses list does)
func list_poses() -> Array:
	var out := []
	for dir in dirs:
		var d := DirAccess.open(dir)
		if d == null:
			continue
		var files := Array(d.get_files())
		files.sort()
		for f in files:
			if not f.ends_with(".json"):
				continue
			var path: String = dir.trim_suffix("/") + "/" + f
			var txt := FileAccess.get_file_as_string(path)
			if txt.contains("\"keys\"") or txt.contains("\"cards\"") or not txt.contains("\"joints\""):
				continue
			out.append({"path": path, "name": f.get_basename().replace("_", " "), "mine": not dir.begins_with("res://poses"),
				"imported": dir.ends_with("/" + PosePack.IMPORTED)})
	return out


## the listing again; cells rebuilt when it changed; stale thumbnails queued
func refresh() -> void:
	entries = list_poses()
	if mood != "":
		entries = entries.filter(func(e): return mood in PoseMood.tags_of_file(e["path"]))
	var sig := ",".join(entries.map(func(e): return e["path"]))
	if sig != _sig:
		_sig = sig
		_build_cells()
	for e in entries:
		if stale(e["path"]) and not _queue.has(e["path"]):
			_queue.append(e["path"])
	_pump()


static func thumb_path(path: String) -> String:
	return path.get_basename() + ".png"


## may a thumbnail be written next to this pose? Always in the app; under a test script only in user://
static func may_write(path: String) -> bool:
	return path.begins_with("user://") or Engine.get_main_loop().get_script() == null


## does the pose's picture need making? (in memory: the md5 it was made from; on disk: the .png missing or older)
func stale(path: String) -> bool:
	var md5 := FileAccess.get_md5(path)
	if made.has(path):
		return made[path] != md5
	var png := thumb_path(path)
	if FileAccess.file_exists(png) and FileAccess.get_modified_time(png) >= FileAccess.get_modified_time(path):
		var img := Image.load_from_file(ProjectSettings.globalize_path(png))
		if img != null and not img.is_empty():
			tex[path] = ImageTexture.create_from_image(img)
			made[path] = md5
			_show(path)
			return false
	return true


func _pump() -> void:
	if _busy:
		return
	_busy = true
	while not _queue.is_empty():
		var path: String = _queue.pop_front()
		if FileAccess.file_exists(path):
			await render(path)
	_busy = false


## wait until every queued thumbnail is made (tests)
func settle() -> void:
	refresh()
	while _busy or not _queue.is_empty():
		await get_tree().process_frame


func _stage() -> void:
	if _vp != null:
		return
	_vp = SubViewport.new()
	_vp.name = "thumb_stage"
	_vp.size = THUMB
	_vp.own_world_3d = true
	_vp.transparent_bg = false
	_vp.msaa_3d = Quality.thumb_msaa() as Viewport.MSAA
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.45
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 35, 0)
	key.light_energy = 1.1
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, -140, 0)
	fill.light_energy = 0.35
	_vp.add_child(fill)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = CAM_SIZE
	cam.near = 0.05
	cam.far = 20.0
	_vp.add_child(cam)
	cam.look_at_from_position(CAM_AT + (CAM_FROM - CAM_AT), CAM_AT)
	cam.current = true
	var floor_m := StandardMaterial3D.new()
	floor_m.albedo_color = BG.darkened(0.25)
	floor_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.45
	cyl.bottom_radius = 0.45
	cyl.height = 0.004
	disc.mesh = cyl
	disc.material_override = floor_m
	disc.position = Vector3(0, -0.002, 0)
	_vp.add_child(disc)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = SKIN
	skin.roughness = 0.55
	var mq := Overlays.mannequin(_vp, skin)
	_sk = mq[1]
	_idx = mq[2]
	_tb = Body.new()
	_tb.load_files("res://data/skeleton.json", "res://data/body_limits.json")


## the pose's thumbnail: posed on the clean mannequin, rendered once, kept (and written next to the pose when allowed)
func render(path: String) -> void:
	_stage()
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary) or not (d as Dictionary).has("joints"):
		return
	var md5 := FileAccess.get_md5(path)
	_tb.from_dict(d)
	Overlays.pose_skeleton(_sk, _idx, _tb)
	await get_tree().process_frame
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	if img == null or img.is_empty():
		return
	tex[path] = ImageTexture.create_from_image(img)
	made[path] = md5
	renders += 1
	if may_write(path):
		img.save_png(ProjectSettings.globalize_path(thumb_path(path)))
	_show(path)


# ------------------------------------------------------------------ the grid

func _build_cells() -> void:
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	cells = {}
	for e in entries:
		var path: String = e["path"]
		var cell := PanelContainer.new()
		cell.name = "pose_" + path.get_file().get_basename()
		cell.custom_minimum_size = CELL + Vector2(8, 26)
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		cell.tooltip_text = "%s%s\nclick: apply   drag right: blend   Ctrl: flipped   right-click: more" % [e["name"], "  (Library > Imported)" if e["imported"] else ("  (yours)" if e["mine"] else "")]
		cell.gui_input.connect(_cell_input.bind(path))
		var v := VBoxContainer.new()
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_theme_constant_override("separation", 2)
		cell.add_child(v)
		var tr := TextureRect.new()
		tr.name = "thumb"
		tr.custom_minimum_size = CELL
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(tr)
		var l := Label.new()
		l.name = "label"
		l.text = e["name"]
		l.clip_text = true
		l.custom_minimum_size = Vector2(CELL.x, 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 11)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(l)
		grid.add_child(cell)
		cells[path] = cell
		_show(path)
	_lit()


func _show(path: String) -> void:
	if cells.has(path) and tex.has(path):
		(cells[path].find_child("thumb", true, false) as TextureRect).texture = tex[path]


## the picked cell framed in the accent colour
func _lit() -> void:
	for p in cells:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Tok.c("card_sel") if p == picked else Tok.c("card")
		sb.set_corner_radius_all(6)
		sb.set_content_margin_all(4)
		if p == picked:
			sb.set_border_width_all(2)
			sb.border_color = Tok.c("accent")
		(cells[p] as PanelContainer).add_theme_stylebox_override("panel", sb)


func pick(path: String) -> void:
	picked = path
	_lit()


func _cell_input(ev: InputEvent, path: String) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			pick(path)
			_press = {"path": path, "x": mb.position.x, "moved": false, "ctrl": mb.ctrl_pressed}
		elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed and not _press.is_empty():
			var was := _press
			_press = {}
			if was["moved"]:
				end_blend()
			else:
				apply(path, flip_box.button_pressed or mb.ctrl_pressed)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if not _base.is_empty():
				_press = {}
				cancel_blend()
			else:
				pick(path)
				_open_menu(mb.global_position)
		accept_event()
	elif ev is InputEventMouseMotion and not _press.is_empty():
		var mm := ev as InputEventMouseMotion
		var dx: float = mm.position.x - float(_press["x"])
		if not _press["moved"] and absf(dx) > 4.0:
			_press["moved"] = true
			begin_blend(path, flip_box.button_pressed or bool(_press["ctrl"]) or mm.ctrl_pressed)
		if _press["moved"]:
			blend_to(clampf(dx / BLEND_PX, 0.0, 1.0))
		accept_event()


func _open_menu(at: Vector2) -> void:
	menu.clear()
	menu.add_item("Apply", 0)
	menu.add_item("Apply flipped", 1)
	menu.add_item("Blend 50 %", 2)
	menu.add_item("Select the parts it moves", 3)
	menu.add_item("Remake the thumbnail", 4)
	menu.add_item("Share as a pack...", 5)   # ROADMAP 96: the pose as one .kinepack file (no server)
	menu.position = Vector2i(at)
	menu.reset_size()
	menu.popup()


## the picture of a pose as PNG bytes (the one on screen, else the saved one; empty when neither is there)
func thumb_png(path: String) -> PackedByteArray:
	if tex.has(path):
		var img: Image = (tex[path] as Texture2D).get_image()
		if img != null and not img.is_empty():
			return img.save_png_to_buffer()
	var png := thumb_path(path)
	return FileAccess.get_file_as_bytes(png) if FileAccess.file_exists(png) else PackedByteArray()


func _menu(id: int) -> void:
	if picked == "":
		return
	match id:
		0:
			apply(picked, false)
		1:
			apply(picked, true)
		2:
			begin_blend(picked, flip_box.button_pressed)
			blend_to(0.5)
			end_blend()
		3:
			select_parts(picked)
		4:
			made.erase(picked)
			_queue.append(picked)
			_pump()
		5:
			PosePack.share_ask(m, picked, thumb_png(picked))


# ------------------------------------------------------------------ the slider

func _slider_value(v: float) -> void:
	readout.text = "%d %%" % roundi(v)
	if picked == "":
		if v > 0.0:
			slider.set_value_no_signal(0)
			readout.text = "0 %"
			m._say("pick a pose in the library first (click its picture), then drag the Blend slider")
		return
	if _slider_drag:
		blend_to(v / 100.0)
	elif Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):   # a press on the track: the drag starts here
		_slider_drag = true
		begin_blend(picked, flip_box.button_pressed)
		blend_to(v / 100.0)
	else:   # the keyboard: one step each
		begin_blend(picked, flip_box.button_pressed)
		blend_to(v / 100.0)
		end_blend()


func _slider_start() -> void:
	if picked == "" or _slider_drag:
		return
	_slider_drag = true
	begin_blend(picked, flip_box.button_pressed)


func _slider_end(_changed: bool) -> void:
	if not _slider_drag:
		return
	_slider_drag = false
	end_blend()


# ------------------------------------------------------------------ apply / blend (the edits)

## the pose file as a clip: the joints' angles (clamped as Body.from_dict does) and the hips' offset
func clip_of(path: String) -> Dictionary:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var ang := {}
	for j in Body.ORDER:
		ang[j] = Vector3.ZERO
	var off := Vector3.ZERO
	if d is Dictionary:
		var js: Dictionary = (d as Dictionary).get("joints", {})
		for j in js:
			if m.B.lim.has(j):
				var x: Dictionary = js[j]
				ang[j] = m.B.clamp_ang(j, Vector3(x["bend"], x["side"], x["twist"]))
		var o: Array = (d as Dictionary).get("offset", [0, 0, 0])
		off = Vector3(o[0], o[1], o[2])
	return {"ang": ang, "offset": off}


## the joint's target in the clip: as saved, or mirrored (the twin's turn reflected through the middle plane, as
## Body.pose_paste and Body.mirror_pose reflect it)
static func target(b: Body, clip: Dictionary, j: String, flipped: bool) -> Vector3:
	var src: Dictionary = clip["ang"]
	if not flipped:
		return src[j]
	var q := b.compose(Body.twin(j), src[Body.twin(j)])
	return b.clamp_ang(j, b.decompose(j, Quaternion(q.x, -q.y, -q.z, q.w)))


## body b (at base) mixed toward the clip by f: each joint in `only` ([] = all) slerped from its base angle to the
## target; the hips' offset lerped when the whole body moves. f = 0 is the base, f = 1 the library pose exactly
static func mix(b: Body, clip: Dictionary, flipped: bool, only: Array, f: float, base_ang: Dictionary, base_off: Vector3) -> void:
	for j in Body.ORDER:
		if not only.is_empty() and not j in only:
			continue
		var t := target(b, clip, j, flipped)
		if f >= 1.0:
			b.ang[j] = t
		elif f > 0.0:
			b.ang[j] = b.clamp_ang(j, Breakdowner.slerp_ang(b, j, base_ang[j], t, f))
		else:
			b.ang[j] = base_ang[j]
	if only.is_empty():
		var o: Vector3 = clip["offset"]
		var to := Vector3(-o.x, o.y, o.z) if flipped else o
		b.offset = base_off.lerp(to, clampf(f, 0.0, 1.0))
	b.fk()


## the parts an apply touches now: the selected ones when "Only the selected parts" is on, else all ([])
func scope() -> Array:
	if only_box != null and only_box.button_pressed:
		return m.group().filter(func(j): return j in Body.ORDER)
	return []


func _nm(path: String) -> String:
	return path.get_file().get_basename().replace("_", " ")


## a blend starts: ONE undo step is pushed here, whatever the drag does after
func begin_blend(path: String, flipped: bool) -> void:
	if not _base.is_empty():
		end_blend()
	m._step_hint = "Pose library: %s" % _nm(path)
	m._push_undo()
	_base = m.B.state()
	_lock = m._lock_snap()
	_clip = clip_of(path)
	_flip = flipped
	_only = scope()
	_f = 0.0
	picked = path
	_lit()


func blend_to(f: float) -> void:
	if _base.is_empty():
		return
	_f = clampf(f, 0.0, 1.0)
	m.B.set_state(_base)
	mix(m.B, _clip, _flip, _only, _f, _base["ang"], _base["offset"])
	m._lock_keep(_lock)
	m._after_edit()
	readout.text = "%d %%" % roundi(_f * 100.0)
	slider.set_value_no_signal(_f * 100.0)


## the release: the blend is kept as the one undo step it pushed (a 0 % blend changed nothing: its step is dropped)
func end_blend() -> void:
	if _base.is_empty():
		return
	var f := _f
	_base = {}
	slider.set_value_no_signal(0)
	readout.text = "0 %"
	var what := "'%s'%s%s" % [_nm(picked), " flipped" if _flip else "", "" if _only.is_empty() else " on %d selected part%s" % [_only.size(), "" if _only.size() == 1 else "s"]]
	if f <= 0.0:
		m._drop_undo()
		m._say("blend 0 %%: nothing changed. Drag further right on %s's picture to mix it in" % _nm(picked))
		return
	if f >= 1.0:
		m._say("the body is now in pose %s.  Ctrl+Z undoes; Update keeps it on the card" % what)
	else:
		m._say("blended %d %% toward pose %s.  Ctrl+Z undoes; Update keeps it on the card" % [roundi(f * 100.0), what])


## right-click while dragging: the body back as it was, no undo step left
func cancel_blend() -> void:
	if _base.is_empty():
		return
	m.B.set_state(_base)
	_base = {}
	m._drop_undo()
	m._after_edit()
	slider.set_value_no_signal(0)
	readout.text = "0 %"
	m._say("blend cancelled: the body is as it was. Drag on a picture again to blend")


## apply the library pose (flipped = mirrored): one undo step
func apply(path: String, flipped := false) -> void:
	begin_blend(path, flipped)
	blend_to(1.0)
	end_blend()


## Blender's "Select Pose Bones": the parts this pose turns (any angle over 0.5 deg) become the selection
func select_parts(path: String) -> void:
	var c := clip_of(path)
	var js := Body.ORDER.filter(func(j): return (c["ang"][j] as Vector3).length() > 0.5)
	if js.is_empty():
		m._say("'%s' turns no part (it is the rest pose): pick another pose to select its parts" % _nm(path))
		return
	m.sel = js[0]
	m.sel_more = js.slice(1)
	m._refresh()
	only_box.button_pressed = true
	m._say("selected the %d parts '%s' turns; Only the selected parts is on, so a blend moves just them" % [js.size(), _nm(path)])


## Friday plan 140: the MOOD chips (All, then one per mood), over the grid. A chip shows only the poses whose body MEASURES that
## mood (PoseMood: head, spine, shoulder, arm and knee angles read off the pose file); All shows every pose
func _mood_row() -> HFlowContainer:
	var row := HFlowContainer.new()
	row.name = "mood_row"
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 2)
	var group := ButtonGroup.new()
	for md in ["all"] + PoseMood.MOODS:
		var b := Button.new()
		b.name = "mood_" + md
		b.text = md.capitalize()
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = md == "all"
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 12)
		b.tooltip_text = "every pose in the library" if md == "all" else "only the poses that look %s: %s" % [md, PoseMood.RULES[md]]
		b.pressed.connect(_mood_pick.bind(md))
		row.add_child(b)
	return row


func _mood_pick(md: String) -> void:
	mood = "" if md == "all" else md
	refresh()
	if mood == "":
		m._say("every pose in the library. Click a picture to apply it")
	elif entries.is_empty():
		m._say("no pose in the library looks %s yet: click All to see every pose" % mood)
	else:
		m._say("%d %s pose%s: click a picture to apply it, or All for every pose" % [entries.size(), mood, "" if entries.size() == 1 else "s"])
