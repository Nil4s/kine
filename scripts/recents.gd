## RECENT SCENES WITH PICTURES (ROADMAP_400 P13): the start panel. A grid of the last N scenes opened or saved:
## a picture of the 3D view as it was at save time (256x144, user://thumbs/<sha256 of the path>.png, no UI in it), the
## name, "2 h ago" and the card count; a click opens it. A file that moved or was deleted is greyed and says so, with
## a button that takes it off the list. The list itself (paths) is main.gd's [recent] scenes in the settings file; the
## time, card count and length of each live in [recent] meta (a dictionary path -> {t, cards, len, name}).
## The panel shows at start only when the settings file has recents and [look] recents_start is on (default on), and
## never in a test (a test that wants it calls show_panel).
class_name Recents
extends RefCounted

const N := 12
const THUMB := Vector2i(256, 144)
const DIR := "user://thumbs"
const COLS := 5

var m: Node                 # the app (main.gd)
var busy := 0               # pictures being taken (tests wait on it)
var panel: PanelContainer
var tiles := {}             # path -> its tile button
var removes := {}           # path -> its "remove from the list" button (missing files only)
var new_tile: Button


func _init(app: Node) -> void:
	m = app


static func thumb_path(path: String) -> String:
	return "%s/%s.png" % [DIR, path.sha256_text()]


## "2 h ago" from two unix times
static func ago(t: int, now: int) -> String:
	var s := maxi(0, now - t)
	if s < 60:
		return "just now"
	if s < 3600:
		return "%d min ago" % (s / 60)
	if s < 86400:
		return "%d h ago" % (s / 3600)
	return "%d d ago" % (s / 86400)


## the meta of every listed scene (path -> {t, cards, len, name})
func meta_all() -> Dictionary:
	var cf := ConfigFile.new()
	cf.load(m.settings)
	var d: Variant = cf.get_value("recent", "meta", {})
	return d if d is Dictionary else {}


## called by main._recent_note inside its settings write: this scene's line, and only the listed scenes keep theirs
static func put_meta(cf: ConfigFile, path: String, sc: Scene, keep: Array) -> void:
	var d: Dictionary = cf.get_value("recent", "meta", {})
	d[path] = {"t": int(Time.get_unix_time_from_system()), "cards": sc.cards.size(), "len": snappedf(sc.length(), 0.01), "name": sc.name}
	for k in d.keys():
		if not keep.has(k):
			d.erase(k)
	cf.set_value("recent", "meta", d)


func start_on() -> bool:
	var cf := ConfigFile.new()
	cf.load(m.settings)
	return bool(cf.get_value("look", "recents_start", true))


func set_start(on: bool) -> void:
	var cf := ConfigFile.new()
	cf.load(m.settings)
	cf.set_value("look", "recents_start", on)
	cf.save(m.settings)


## a path leaves the list (and its picture goes); the panel is redrawn
func remove(path: String) -> void:
	var cf := ConfigFile.new()
	cf.load(m.settings)
	var l: Array = Array(cf.get_value("recent", "scenes", [])).filter(func(p): return String(p) != path)
	cf.set_value("recent", "scenes", l)
	var d: Dictionary = cf.get_value("recent", "meta", {})
	d.erase(path)
	cf.set_value("recent", "meta", d)
	cf.save(m.settings)
	if FileAccess.file_exists(thumb_path(path)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(thumb_path(path)))
	m._recent_changed()
	m._say("%s left the recent list" % path.get_file())


## the 3D view as it is now, 256x144, with none of the interface: a second camera on the app's own world
func capture(path: String) -> void:
	if m.cam == null or not m.is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	busy += 1
	var vp := SubViewport.new()
	vp.size = THUMB
	vp.world_3d = m.get_viewport().world_3d
	vp.transparent_bg = false
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var c := Camera3D.new()
	c.fov = m.cam.fov
	c.near = m.cam.near
	c.far = m.cam.far
	vp.add_child(c)
	m.add_child(vp)
	c.global_transform = m.cam.global_transform
	c.current = true
	var tree := m.get_tree()
	await tree.process_frame
	await RenderingServer.frame_post_draw
	if is_instance_valid(vp) and vp.is_inside_tree():
		var img := vp.get_texture().get_image()
		if img != null and not img.is_empty():
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
			img.save_png(ProjectSettings.globalize_path(thumb_path(path)))
		vp.queue_free()
	busy -= 1
	if panel != null and panel.visible:
		fill()


func settle() -> void:
	while busy > 0:
		await Engine.get_main_loop().process_frame


## ---- the panel
func show_panel() -> void:
	if panel == null:
		panel = PanelContainer.new()
		panel.name = "recents_panel"
		panel.set_anchors_preset(Control.PRESET_CENTER)
		panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		panel.grow_vertical = Control.GROW_DIRECTION_BOTH
		var st := StyleBoxFlat.new()
		st.bg_color = Tok.c("panel")
		st.border_color = Tok.c("accent")
		st.set_border_width_all(2)
		st.set_corner_radius_all(10)
		st.set_content_margin_all(14)
		panel.add_theme_stylebox_override("panel", st)
		m.ui_root.add_child(panel)
	panel.visible = true
	fill()


func hide_panel() -> void:
	if panel != null:
		panel.visible = false


func fill() -> void:
	for c in panel.get_children():
		panel.remove_child(c)
		c.queue_free()
	tiles.clear()
	removes.clear()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t: Label = m._label("Recent scenes", 20, "heading")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var cb := CheckBox.new()
	cb.text = "show at start"
	cb.focus_mode = Control.FOCUS_NONE
	cb.button_pressed = start_on()
	cb.tooltip_text = "show this panel when Kine starts (remembered). File: recent scenes opens it any time"
	cb.toggled.connect(set_start)
	head.add_child(cb)
	var x: Button = m._button("Close", hide_panel, "close this panel; File: recent scenes brings it back")
	x.name = "recents_close"
	head.add_child(x)
	var g := GridContainer.new()
	g.columns = COLS
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 10)
	v.add_child(g)
	var meta := meta_all()
	var now := int(Time.get_unix_time_from_system())
	var list: Array = m._recent_list()
	for i in mini(list.size(), N):
		g.add_child(_tile(String(list[i]), meta.get(String(list[i]), {}), now))
	new_tile = Button.new()
	new_tile.name = "tile_new"
	new_tile.text = "+  New scene"
	new_tile.focus_mode = Control.FOCUS_NONE
	new_tile.custom_minimum_size = Vector2(184, 152)
	new_tile.add_theme_font_size_override("font_size", 18)
	new_tile.tooltip_text = "start an empty scene (asks first when the open one has unsaved changes)"
	new_tile.pressed.connect(func():
		hide_panel()
		m._new_asked())
	g.add_child(new_tile)


func _tile(path: String, meta: Dictionary, now: int) -> Control:
	var gone := not FileAccess.file_exists(path)
	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", 2)
	var b := Button.new()
	b.name = "tile_%d" % tiles.size()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(184, 152)
	b.disabled = gone
	b.tooltip_text = path if not gone else "%s is not on disk any more (moved or deleted): remove it from the list below" % path.get_file()
	var inner := VBoxContainer.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 4
	inner.offset_top = 4
	inner.offset_right = -4
	inner.offset_bottom = -4
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(inner)
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(176, 99)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tp := thumb_path(path)
	if FileAccess.file_exists(tp):
		var img := Image.load_from_file(tp)
		if img != null and not img.is_empty():
			tr.texture = ImageTexture.create_from_image(img)
	inner.add_child(tr)
	var nm := String(meta.get("name", "")) if String(meta.get("name", "")) != "" else path.get_file().get_basename()
	var l1: Label = m._label(nm.replace("_", " "), 14, "text")
	l1.clip_text = true
	l1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(l1)
	var sub := "moved or deleted" if gone else ""
	if not gone and meta.has("t"):
		sub = "%s  -  %d cards  -  %.1f s" % [ago(int(meta["t"]), now), int(meta.get("cards", 0)), float(meta.get("len", 0.0))]
	var l2: Label = m._label(sub, 12, "info")
	l2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(l2)
	if gone:
		inner.modulate.a = 0.45
	b.pressed.connect(func():
		hide_panel()
		m._open_recent(path))
	cell.add_child(b)
	tiles[path] = b
	if gone:
		var r: Button = m._button("moved or deleted: remove from the list", remove.bind(path), "take %s off the recent list" % path.get_file())
		r.name = "remove_%d" % removes.size()
		r.add_theme_font_size_override("font_size", 11)
		cell.add_child(r)
		removes[path] = r
	return cell
