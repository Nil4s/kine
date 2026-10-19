class_name TipVideo
extends Node
## TOOLTIP VIDEOS (ROADMAP 49): hovering a ribbon button for DELAY seconds shows a panel that loops a 2 s silent clip of the
## tool at work (15 fps, 320x200) with the button's name and hint under it. The clips are made by the app itself
## (tools/make_tip_clips.gd drives it and captures the view); each is one PNG frame sheet (a grid of frames) plus the
## index assets/tips/tips.json. A button with no clip keeps the plain text tooltip. Leaving the button hides the panel.
## The hint in the status bar (main.gd `_hover_hints`) is untouched and appears at once.

const DIR := "res://assets/tips/"
const DELAY := 0.6

var main: Node
var manifest := {}          # tips.json
var by_button := {}         # a button's label -> clip id
var hovered: Control = null
var t_enter := 0.0
var shown_id := ""
var frame := 0              # the frame of the clip on screen now (tests read it)
var t_show := 0.0
var panel: PanelContainer
var rect: TextureRect
var title: Label
var body: Label
var _sf := {}               # id -> SpriteFrames


## the index (empty when the folder has none: then every button keeps text only)
static func load_manifest(dir := DIR) -> Dictionary:
	var f := dir + "tips.json"
	if not FileAccess.file_exists(f):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(f))
	return d if d is Dictionary and d.has("clips") else {}


## a clip as a SpriteFrames (one animation "loop" at the clip's fps, one AtlasTexture per frame of the sheet)
static func sprite_frames(man: Dictionary, id: String, dir := DIR) -> SpriteFrames:
	var c: Dictionary = man["clips"][id]
	var path: String = dir + String(c["sheet"])
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
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


## the bytes of everything in the folder (the budget is 6 MB)
static func dir_bytes(dir := DIR) -> int:
	var n := 0
	for fn in DirAccess.get_files_at(dir):
		var fa := FileAccess.open(dir + fn, FileAccess.READ)
		if fa != null:
			n += int(fa.get_length())
	return n


func attach_all(m: Node, root: Node) -> void:
	main = m
	manifest = load_manifest()
	if manifest.is_empty():
		return
	for id in manifest["clips"]:
		for lb in manifest["clips"][id].get("buttons", []):
			by_button[lb] = id
	_build()
	for b in root.find_children("*", "Button", true, false):
		var lb: String = m.label_of(b)
		if by_button.has(lb):
			b.mouse_entered.connect(_enter.bind(b))
			b.mouse_exited.connect(_exit.bind(b))
			b.pressed.connect(_hide)
	set_process(true)


func _build() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	panel = PanelContainer.new()
	panel.name = "tip_video"
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Tok.c("float")
	sb.border_color = Tok.c("accent")
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
	title.add_theme_color_override("font_color", Tok.c("heading"))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(title)
	body = Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = float(manifest["w"])
	body.add_theme_color_override("font_color", Tok.c("text"))
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(body)
	layer.add_child(panel)


func _enter(b: Control) -> void:
	hovered = b
	t_enter = Time.get_ticks_msec() / 1000.0
	# the engine's own text tooltip would pop up at 0.5 s on top of ours: while the mouse is really on a button that
	# has a clip, its text is parked (the panel shows it); synthetic enters (tests) leave it alone
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


func _words(b: Control) -> Array:
	var t: String = main.label_of(b)
	var full: String = String(b.get_meta("tip_text", b.tooltip_text))
	return [t, full.trim_prefix(t + "\n").trim_prefix(t).strip_edges()]


func _show(b: Control) -> void:
	var id: String = by_button[main.label_of(b)]
	if not _sf.has(id):
		_sf[id] = sprite_frames(manifest, id)
	if _sf[id] == null:
		return
	shown_id = id
	t_show = Time.get_ticks_msec() / 1000.0
	frame = 0
	var w := _words(b)
	title.text = w[0]
	body.text = w[1]
	body.visible = w[1] != ""
	rect.texture = (_sf[id] as SpriteFrames).get_frame_texture("default", 0)
	panel.visible = true
	panel.reset_size()
	var vs := b.get_viewport().get_visible_rect().size
	var r := b.get_global_rect()
	var sz := panel.get_combined_minimum_size()
	var x := clampf(r.position.x + r.size.x * 0.5 - sz.x * 0.5, 4.0, vs.x - sz.x - 4.0)
	var y := r.end.y + 8.0
	if y + sz.y > vs.y - 4.0:
		y = maxf(4.0, r.position.y - sz.y - 8.0)
	panel.position = Vector2(x, y)


func _process(_dt: float) -> void:
	if manifest.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if hovered != null and not is_instance_valid(hovered):
		hovered = null
	if hovered != null and not hovered.is_visible_in_tree():   # a tab change took the button away
		hovered = null
		_hide()
	if hovered != null and shown_id == "" and now - t_enter >= DELAY:
		_show(hovered)
	if shown_id != "":
		var sf: SpriteFrames = _sf[shown_id]
		var n := sf.get_frame_count("default")
		frame = int((now - t_show) * float(manifest["fps"])) % n
		rect.texture = sf.get_frame_texture("default", frame)
