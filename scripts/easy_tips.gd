class_name EasyTips
extends Node
## EASY PART TOOLTIP CLIPS (Friday plan 94): hovering a MAKE button for DELAY seconds shows a small panel beside the button: a
## looping clip (200 x 120, 14 frames, 12 fps) of that action on a sample part, under it the button's own tooltip words.
## The clips are made by the app itself (tools/make_easy_tips.gd) into assets/tips/easy/<id>.png (one 7 x 2 sheet per button) with
## tips.json. Leaving the button hides the panel at once. Hovering touches no part and no undo step.

const DIR := "res://assets/tips/easy/"
const DELAY := 0.6

var ep: Node
var manifest := {}
var hovered: Control = null
var t_enter := 0.0
var shown_id := ""
var frame := 0
var t_show := 0.0
var panel: PanelContainer
var rect: TextureRect
var title: Label
var body: Label
var _sf := {}
var _pre := 0               # clips decoded so far in the background (one per idle frame, so no hover pays for the PNG)


static func load_manifest(dir := DIR) -> Dictionary:
	var f := dir + "tips.json"
	if not FileAccess.file_exists(f):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(f))
	return d if d is Dictionary and d.has("clips") else {}


static func dir_bytes(dir := DIR) -> int:
	var n := 0
	for fn in DirAccess.get_files_at(dir):
		var fa := FileAccess.open(dir + fn, FileAccess.READ)
		if fa != null:
			n += int(fa.get_length())
	return n


static func sprite_frames(man: Dictionary, id: String, dir := DIR) -> SpriteFrames:
	var c: Dictionary = man["clips"][id]
	var img := Image.load_from_file(ProjectSettings.globalize_path(dir + String(c["sheet"])))
	if img == null or img.is_empty():
		return null
	var tex := ImageTexture.create_from_image(img)
	var w := int(man["w"])
	var h := int(man["h"])
	var cols := int(c["cols"])
	var sf := SpriteFrames.new()
	sf.set_animation_loop("default", true)
	sf.set_animation_speed("default", float(man["fps"]))
	for i in int(c["frames"]):
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2((i % cols) * w, (i / cols) * h, w, h)
		sf.add_frame("default", at)
	return sf


## the buttons of Easy Part's MAKE row that have a clip get the hover
func attach(easy_part: Node, layer_parent: Node) -> void:
	ep = easy_part
	manifest = load_manifest()
	if manifest.is_empty():
		return
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	_build(layer)
	layer_parent.add_child(self)
	for id in manifest["clips"]:
		if not ep.make_btns.has(id):
			continue
		var b: Button = ep.make_btns[id]
		b.mouse_entered.connect(_enter.bind(b))
		b.mouse_exited.connect(_exit.bind(b))
		b.pressed.connect(_hide)


func _build(layer: Node) -> void:
	panel = PanelContainer.new()
	panel.name = "easy_tip"
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.11, 0.14, 0.97)
	sb.border_color = Color(0.45, 0.6, 0.9)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(v)
	rect = TextureRect.new()
	rect.custom_minimum_size = Vector2(float(manifest["w"]), float(manifest["h"]))
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(rect)
	title = Label.new()
	title.add_theme_font_size_override("font_size", 15)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(title)
	body = Label.new()
	body.add_theme_font_size_override("font_size", 13)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = float(manifest["w"])
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(body)
	layer.add_child(panel)
	set_process(true)


func _enter(b: Control) -> void:
	hovered = b
	t_enter = Time.get_ticks_msec() / 1000.0
	# the engine's own text tooltip would pop up on top of ours: while the pointer is really on the button its text is parked
	if b.tooltip_text != "" and b is BaseButton and (b as BaseButton).is_hovered():
		b.set_meta("tip_text", b.tooltip_text)
		b.tooltip_text = ""


func _exit(b: Control) -> void:
	if b.has_meta("tip_text"):
		b.tooltip_text = String(b.get_meta("tip_text"))
		b.remove_meta("tip_text")
	if hovered == b:
		hovered = null
		_hide()


func _hide() -> void:
	shown_id = ""
	if panel != null:
		panel.visible = false


func _id_of(b: Control) -> String:
	for k in ep.make_btns:
		if ep.make_btns[k] == b:
			return String(k)
	return ""


func _show(b: Control) -> void:
	var id := _id_of(b)
	if id == "" or not manifest["clips"].has(id):
		return
	if not _sf.has(id):
		_sf[id] = sprite_frames(manifest, id)
	if _sf[id] == null:
		return
	shown_id = id
	t_show = Time.get_ticks_msec() / 1000.0
	frame = 0
	title.text = b.text
	var words := String(b.get_meta("tip_text", b.tooltip_text))
	body.text = words
	body.visible = words != ""
	rect.texture = (_sf[id] as SpriteFrames).get_frame_texture("default", 0)
	panel.visible = true
	panel.reset_size()
	var vs := b.get_viewport().get_visible_rect().size
	var r := b.get_global_rect()
	var sz := panel.get_combined_minimum_size()
	var x := clampf(r.position.x + r.size.x * 0.5 - sz.x * 0.5, 4.0, vs.x - sz.x - 4.0)
	var y := r.end.y + 6.0
	if y + sz.y > vs.y - 4.0:
		y = maxf(4.0, r.position.y - sz.y - 6.0)
	panel.position = Vector2(x, y)


func _process(_dt: float) -> void:
	if manifest.is_empty():
		return
	var ids: Array = manifest["clips"].keys()
	if _pre < ids.size() and hovered == null:
		var pid: String = ids[_pre]
		_pre += 1
		if not _sf.has(pid):
			_sf[pid] = sprite_frames(manifest, pid)
	var now := Time.get_ticks_msec() / 1000.0
	if hovered != null and not is_instance_valid(hovered):
		hovered = null
	if hovered != null and not hovered.is_visible_in_tree():
		hovered = null
		_hide()
	if hovered != null and shown_id == "" and now - t_enter >= DELAY:
		_show(hovered)
	if shown_id != "":
		var sf: SpriteFrames = _sf[shown_id]
		frame = int(maxf(0.0, now - t_show) * float(manifest["fps"])) % sf.get_frame_count("default")
		rect.texture = sf.get_frame_texture("default", frame)
