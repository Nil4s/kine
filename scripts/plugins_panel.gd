## THE PLUGINS PANEL (ROADMAP 100): every plugin found, its manifest in words, and an enable switch. Opened from the S box
## ("Plugins: enable or disable plugins"). It states plainly what a plugin can do: GDScript cannot be sandboxed, so a
## plugin runs with the app's permissions. A plugin that fails shows its message in its row, and its switch is off.
class_name PluginsPanel
extends PanelContainer

const W := 640

var plugins: Plugins
var say_fn: Callable
var _body: VBoxContainer
var _where: Label


func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(W, 0)
	var st := StyleBoxFlat.new()
	st.bg_color = Tok.c("float")
	st.set_corner_radius_all(8)
	st.set_content_margin_all(14)
	add_theme_stylebox_override("panel", st)
	var outer := VBoxContainer.new()
	add_child(outer)
	var head := HBoxContainer.new()
	outer.add_child(head)
	var t := _label("PLUGINS", 18, "heading")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var x := Button.new()
	x.text = "Close"
	x.pressed.connect(close)
	head.add_child(x)
	var warn := _label("Plugins run with the app's permissions; only enable plugins you trust. GDScript cannot be sandboxed: "
		+ "a plugin can do anything this app can. The plugin API is the documented door (it cannot reach the app's scene "
		+ "code or write outside its own data folder), but it is not a wall.", 14, "warn")
	warn.custom_minimum_size = Vector2(W - 40, 0)
	outer.add_child(warn)
	var scr := ScrollContainer.new()
	scr.custom_minimum_size = Vector2(W - 28, 380)
	scr.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scr)
	_body = VBoxContainer.new()
	_body.custom_minimum_size = Vector2(W - 44, 0)
	scr.add_child(_body)
	_where = _label("", 12, "text:0.7")
	_where.custom_minimum_size = Vector2(W - 40, 0)
	outer.add_child(_where)
	rebuild()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	rebuild()
	visible = true
	reset_size()
	var vp := get_viewport_rect().size
	position = ((vp - size) / 2.0).floor()


func close() -> void:
	visible = false


## one row per plugin found: the switch, the manifest's words, the commands, and any message
func rebuild() -> void:
	if _body == null:
		return
	var shown := PackedStringArray()   # the folders as this Plugins object searches them (not as they were at start)
	for r in plugins.roots:
		shown.append(ProjectSettings.globalize_path(String(r)))
	_where.text = "Folders: " + ", ".join(shown)
	for ch in _body.get_children():
		_body.remove_child(ch)
		ch.queue_free()
	if plugins.found.is_empty():
		_body.add_child(_label("No plugins found. A plugin is a folder with manifest.json and plugin.gd. Put it in %s and open this panel again. The example is in examples/plugins/." % ProjectSettings.globalize_path("user://plugins"), 15, "text"))
		return
	for i in plugins.found.size():
		var rec: Dictionary = plugins.found[i]
		var m: Dictionary = rec["manifest"]
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		_body.add_child(row)
		var top := HBoxContainer.new()
		row.add_child(top)
		var sw := CheckBox.new()
		sw.name = "enable_" + rec["folder"]
		sw.button_pressed = rec["enabled"]
		sw.text = "On" if rec["enabled"] else "Off"
		sw.toggled.connect(_switched.bind(i))
		top.add_child(sw)
		var title: String = String(m.get("name", rec["folder"])) if not m.is_empty() else String(rec["folder"])
		var tl := _label("%s   v%s   by %s   api %s   (%s)" % [title, m.get("version", "?"), m.get("author", "?"),
			str(int(m["api"])) if m.has("api") else "?", rec["source"]], 16, "text")
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(tl)
		if not m.is_empty():
			var names := PackedStringArray()
			for c in m["commands"]:
				names.append(String(c.get("name", c.get("id", "?"))))
			row.add_child(_label("Adds to the S box: " + ", ".join(names), 14, "say"))
			if m.has("description"):
				row.add_child(_label(String(m["description"]), 13, "text:0.8"))
		if rec["error"] != "" or rec["fault"] != "":
			var el := _label(String(rec["error"]) + String(rec["fault"]), 14, "fail")
			el.custom_minimum_size = Vector2(W - 60, 0)
			row.add_child(el)
		row.add_child(HSeparator.new())


func _switched(on: bool, i: int) -> void:
	var why := plugins.set_enabled(i, on)
	if why != "" and say_fn.is_valid():
		say_fn.call(why)
	rebuild()


func _label(t: String, size: int, color: String) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	var key := color.split(":")
	var c: Color = Tok.c(key[0])
	if key.size() > 1:
		c = Color(c, float(key[1]))
	l.add_theme_color_override("font_color", c)
	return l
