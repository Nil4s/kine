## blueprint_ui.gd - the BLUEPRINT sheet view of BUILD (docs/BUILD_PLAN.md phase 1g): the "Blueprint" ribbon button opens a full-window sheet
## with tabs (Floor 1 / Floor 2 / Front / Side), Export SVG / PNG / DXF and Close. All mouse. The drawing is Blueprint's entity list
## (scripts/build/blueprint.gd) painted by BlueprintView, the same painter the 300 dpi PNG export uses in a SubViewport.
class_name BlueprintUI
extends RefCounted

var b: BuildUI
var m: Node
var root: Control
var tab_row: HBoxContainer
var area: Control
var view: BlueprintView
var status: Label
var tab := ""
var pick := {}          # the paper and scale of the whole set (Blueprint.choose)
var sheet := {}
var last_path := ""
var _group: ButtonGroup


func setup(build_ui: BuildUI) -> void:
	b = build_ui
	m = b.m
	root = Control.new()
	root.name = "blueprint_overlay"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.z_index = 60
	root.visible = false
	m.ui_root.add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.1, 0.98)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 12
	vb.offset_right = -12
	vb.offset_top = 8
	vb.offset_bottom = -8
	vb.add_theme_constant_override("separation", 6)
	root.add_child(vb)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	vb.add_child(top)
	var title := Label.new()
	title.text = "Blueprint"
	title.add_theme_font_size_override("font_size", 18)
	top.add_child(title)
	tab_row = HBoxContainer.new()
	tab_row.name = "blueprint_tabs"
	tab_row.add_theme_constant_override("separation", 4)
	top.add_child(tab_row)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	for e in [["SVG", "scale-exact vector drawing, millimetres"], ["PNG", "a picture at 300 dpi"], ["DXF", "CAD lines, arcs and text (R12), millimetres"]]:
		var btn: Button = m._button("Export " + e[0], _export.bind(String(e[0]).to_lower()), "Export this sheet as %s: %s. One file per click, in %s" % [e[0], e[1], Blueprint.dir])
		btn.name = "blueprint_export_" + String(e[0]).to_lower()
		top.add_child(btn)
	var cl: Button = m._button("Close", close, "back to the building")
	cl.name = "blueprint_close"
	top.add_child(cl)
	area = Control.new()
	area.name = "blueprint_area"
	area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	area.clip_contents = true
	area.resized.connect(_layout)
	vb.add_child(area)
	view = BlueprintView.new()
	view.name = "blueprint_view"
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area.add_child(view)
	status = Label.new()
	status.name = "blueprint_status"
	status.add_theme_color_override("font_color", Color(0.75, 0.82, 0.9))
	vb.add_child(status)


func is_open() -> bool:
	return root.visible


func open() -> void:
	var bd: Dictionary = b._bld()
	var ts := Blueprint.tabs(bd)
	if ts.is_empty():
		m._say("Blueprint: draw a room first")
		return
	pick = Blueprint.choose(bd)
	for c in tab_row.get_children():
		c.queue_free()
		tab_row.remove_child(c)
	_group = ButtonGroup.new()
	for i in ts.size():
		var tb: Button = m._button(String(ts[i]), _pick_tab.bind(String(ts[i])), "%s: %s" % [ts[i], Blueprint.title_of(String(ts[i]))])
		tb.toggle_mode = true
		tb.button_group = _group
		tb.name = "blueprint_tab_%d" % i
		tab_row.add_child(tb)
	root.visible = true
	_pick_tab(String(ts[0]))
	m._say("Blueprint: %s at 1:%d on %s. Pick a tab, then Export" % [bd.get("name", "house"), int(pick["denom"]), pick["paper"]])


func close() -> void:
	root.visible = false


func _pick_tab(t: String) -> void:
	tab = t
	for c in tab_row.get_children():
		(c as Button).set_pressed_no_signal((c as Button).text == t)
	sheet = Blueprint.sheet(b._bld(), t, pick)
	view.sheet = sheet
	status.text = "%s  -  %s, 1:%d, dimensions in metres" % [sheet["title"], sheet["paper"], int(sheet["denom"])]
	_layout()


func _layout() -> void:
	if sheet.is_empty() or area == null:
		return
	var sz := Vector2(float(sheet["w"]), float(sheet["h"]))
	var ppm := minf(area.size.x / sz.x, area.size.y / sz.y)
	if ppm <= 0.0:
		return
	view.ppm = ppm
	view.size = sz * ppm
	view.position = (area.size - view.size) * 0.5
	view.queue_redraw()


## Export SVG / PNG / DXF of the open tab: one file each, the path said in the status line
func _export(kind: String) -> void:
	if sheet.is_empty():
		return
	var bd: Dictionary = b._bld()
	var path := ""
	match kind:
		"svg":
			path = Blueprint.save_text(bd, tab, "svg", Blueprint.to_svg(sheet))
		"dxf":
			path = Blueprint.save_text(bd, tab, "dxf", Blueprint.to_dxf(sheet))
		_:
			path = await export_png()
	last_path = path
	if path == "":
		status.text = "Could not write the %s file" % kind.to_upper()
		m._say("Blueprint: could not write the %s file" % kind.to_upper())
	else:
		status.text = "Saved %s" % ProjectSettings.globalize_path(path)
		m._say("Blueprint: saved %s" % path)


## the open sheet as a 300 dpi PNG: BlueprintView painted in a SubViewport of exactly the paper's pixels ("" on failure)
func export_png() -> String:
	var px := Blueprint.png_size(sheet)
	var vp := SubViewport.new()
	vp.size = px
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var v := BlueprintView.new()
	v.sheet = sheet
	v.ppm = 300.0 / 25.4
	v.size = Vector2(px)
	vp.add_child(v)
	m.add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Blueprint.dir))
	var path := "%s/%s" % [Blueprint.dir, Blueprint.file_name(b._bld(), tab, "png")]
	return path if img.save_png(path) == OK else ""
