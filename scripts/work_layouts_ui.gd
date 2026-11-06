class_name WorkLayoutsUI
extends PanelContainer
## THE LAYOUTS DIALOG (lane L20; Expert / Engineering only): the saved layouts (Save, Load, Rename, Delete, Reset to the factory default), and for the page
## picked on its tabs a DOCK MAP: a small picture of the window with the page's panels as chips. Drag a chip onto the left, right or bottom zone to dock
## it there, onto the middle to float it; or use the Dock menu beside each panel's name. Open / closed and the rail width are on the same rows.
## Every change goes through scripts/work_layouts.gd and then UiExpShell.ws_changed(), which re-places the live panels (the limits are kept there).

const MAP := Vector2(520, 300)
const CHIP_PAD := 2.0

var sh: UiExpShell
var ws: WorkLayouts
var page := "part"
var dock_map: DockMap
var name_edit: LineEdit
var list: ItemList
var status: Label
var rows: VBoxContainer
var rail_slider: HSlider
var tabs: Dictionary = {}
var _picked := ""


## the picture of the window: the solved rects of the page's open panels, scaled to the control; drag a chip to dock it
class DockMap extends Control:
	var ui: WorkLayoutsUI
	var page := "part"
	var grab := ""
	var _hot := ""

	func _init() -> void:
		custom_minimum_size = WorkLayoutsUI.MAP
		size = WorkLayoutsUI.MAP
		mouse_filter = Control.MOUSE_FILTER_STOP
		name = "dock_map"

	func window() -> Vector2:
		return ui.sh.m.get_viewport().get_visible_rect().size

	func k() -> float:
		return size.x / window().x

	func solved() -> Dictionary:
		var P: Dictionary = ui.ws.cur["pages"][page]
		var w := window()
		return WorkLayouts.solve(P, page, w, WorkLayouts.area_for(w, int(P["rail_w"])), WorkLayouts.chrome_px(w, int(P["rail_w"])))

	func chip(id: String) -> Rect2:
		var r: Dictionary = solved()["rects"]
		if not r.has(id):
			return Rect2()
		var q: Rect2 = r[id]
		return Rect2(q.position * k(), q.size * k())

	func panel_center(id: String) -> Vector2:
		var c := chip(id)
		return c.get_center() if c.size != Vector2.ZERO else Vector2.ZERO

	func zone_center(z: String) -> Vector2:
		return {"left": Vector2(size.x * 0.12, size.y * 0.4), "right": Vector2(size.x * 0.88, size.y * 0.4), "bottom": Vector2(size.x * 0.5, size.y * 0.9), "float": Vector2(size.x * 0.5, size.y * 0.42)}[z]

	func zone_at(p: Vector2) -> String:
		if p.y > size.y * 0.78:
			return "bottom"
		if p.x < size.x * 0.25:
			return "left"
		if p.x > size.x * 0.75:
			return "right"
		return "float"

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			var e := ev as InputEventMouseButton
			if e.pressed:
				grab = ""
				var r: Dictionary = solved()["rects"]
				for id in r:
					if chip(id).has_point(e.position):
						grab = id
						break
				_hot = zone_at(e.position) if grab != "" else ""
			elif grab != "":
				var z := zone_at(e.position)
				var id := grab
				grab = ""
				_hot = ""
				ui.drop(page, id, z, e.position / k())
			queue_redraw()
		elif ev is InputEventMouseMotion and grab != "":
			_hot = zone_at((ev as InputEventMouseMotion).position)
			queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Tok.c("say_bg"), true)
		draw_rect(Rect2(Vector2.ZERO, size), Tok.c("info"), false, 1.0)
		var w := window()
		var P: Dictionary = ui.ws.cur["pages"][page]
		var s := solved()
		var kk := k()
		var f := ThemeDB.fallback_font
		# the fixed chrome: the ribbon bar, the rail, the page bar
		draw_rect(Rect2(0, 0, size.x, WorkLayouts.TOP * kk), Color(Tok.c("panel"), 0.9), true)
		draw_rect(Rect2(0, WorkLayouts.TOP * kk, float(P["rail_w"]) * kk, WorkLayouts.RAIL_H_EST * kk), Color(Tok.c("panel"), 0.9), true)
		draw_rect(Rect2(0, size.y - WorkLayouts.PAGEBAR * kk, size.x, WorkLayouts.PAGEBAR * kk), Color(Tok.c("panel"), 0.9), true)
		draw_string(f, Vector2(4, 12), "ribbon", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Tok.c("text"))
		draw_string(f, Vector2(size.x * 0.45, size.y * 0.42), "3D view", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(Tok.c("text"), 0.5))
		if grab != "":
			for z in ["left", "right", "bottom", "float"]:
				var zr := {"left": Rect2(0, 0, size.x * 0.25, size.y * 0.78), "right": Rect2(size.x * 0.75, 0, size.x * 0.25, size.y * 0.78), "bottom": Rect2(0, size.y * 0.78, size.x, size.y * 0.22), "float": Rect2(size.x * 0.25, 0, size.x * 0.5, size.y * 0.78)}[z] as Rect2
				draw_rect(zr, Color(Tok.c("accent"), 0.30 if z == _hot else 0.08), true)
		var defs: Dictionary = WorkLayouts.PANEL_DEFS[page]
		for id in s["rects"]:
			var q: Rect2 = s["rects"][id]
			var c := Rect2(q.position * kk, q.size * kk)
			draw_rect(c, Color(Tok.c("focus"), 0.55 if id != grab else 0.9), true)
			draw_rect(c, Tok.c("text"), false, 1.0)
			draw_string(f, c.position + Vector2(4, 13), String(defs[id]["title"]), HORIZONTAL_ALIGNMENT_LEFT, c.size.x - 6.0, 11, Tok.c("text"))


func _init(shell: UiExpShell) -> void:
	sh = shell
	ws = shell.ws
	name = "layouts_ui"
	visible = false
	var st := StyleBoxFlat.new()
	st.bg_color = Tok.c("float")
	st.set_corner_radius_all(8)
	st.set_content_margin_all(14)
	add_theme_stylebox_override("panel", st)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _build() -> void:
	if get_child_count() > 0:
		return
	var v := VBoxContainer.new()
	add_child(v)
	v.add_child(sh.m._label("WORKSPACE LAYOUTS  (Expert and Engineering screens)", 16, "heading"))
	var tb := HBoxContainer.new()
	v.add_child(tb)
	for pg in WorkLayouts.PAGES:
		var b := Button.new()
		b.name = "lay_tab_" + pg
		b.text = String(pg).capitalize()
		b.toggle_mode = true
		b.pressed.connect(set_page.bind(pg))
		tb.add_child(b)
		tabs[pg] = b
	var mid := HBoxContainer.new()
	v.add_child(mid)
	var left := VBoxContainer.new()
	mid.add_child(left)
	dock_map = DockMap.new()
	dock_map.ui = self
	left.add_child(dock_map)
	left.add_child(sh.m._label("Drag a panel onto the left, right or bottom edge to dock it, onto the middle to float it.", 12, "text:0.7"))
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 380
	mid.add_child(right)
	rows = VBoxContainer.new()
	right.add_child(rows)
	var rr := HBoxContainer.new()
	right.add_child(rr)
	rr.add_child(sh.m._label("Rail width", 13, "text"))
	rail_slider = HSlider.new()
	rail_slider.name = "lay_rail"
	rail_slider.min_value = WorkLayouts.RAIL_MIN
	rail_slider.max_value = WorkLayouts.RAIL_MAX
	rail_slider.step = 2
	rail_slider.custom_minimum_size.x = 220
	rail_slider.value_changed.connect(_rail_changed)
	rr.add_child(rail_slider)
	right.add_child(sh.m._label("Saved layouts", 13, "heading"))
	list = ItemList.new()
	list.name = "lay_list"
	list.custom_minimum_size = Vector2(360, 110)
	list.item_selected.connect(func(i): pick_name(list.get_item_text(i)))
	right.add_child(list)
	name_edit = LineEdit.new()
	name_edit.name = "lay_name"
	name_edit.placeholder_text = "layout name"
	right.add_child(name_edit)
	var br := HBoxContainer.new()
	right.add_child(br)
	for pair in [["Save", save_pressed], ["Load", load_pressed], ["Rename", rename_pressed], ["Delete", delete_pressed], ["Reset to factory", reset_pressed]]:
		var b2 := Button.new()
		b2.name = "lay_" + String(pair[0]).to_lower().replace(" ", "_")
		b2.text = pair[0]
		b2.pressed.connect(pair[1])
		br.add_child(b2)
	status = sh.m._label("", 13, "say")
	status.custom_minimum_size.x = 880
	v.add_child(status)
	var cb := Button.new()
	cb.name = "lay_close"
	cb.text = "Close"
	cb.pressed.connect(close_dialog)
	v.add_child(cb)


func open_dialog() -> void:
	_build()
	var pg := sh.page_name()
	page = pg if pg != "" else page
	if get_parent() == null:
		sh.m.ui_root.add_child(self)
	visible = true
	status.text = ""
	set_page(page)
	reset_size()
	position = ((sh.m.get_viewport().get_visible_rect().size - size) / 2.0).floor()


func close_dialog() -> void:
	visible = false


func set_page(pg: String) -> void:
	page = pg
	dock_map.page = pg
	for k in tabs:
		(tabs[k] as Button).set_pressed_no_signal(k == pg)
	refresh()


func refresh() -> void:
	if rows == null:
		return
	for c in rows.get_children():
		rows.remove_child(c)
		c.queue_free()
	var P: Dictionary = ws.cur["pages"][page]
	var defs: Dictionary = WorkLayouts.PANEL_DEFS[page]
	var ids := defs.keys()
	ids.sort_custom(func(a, b): return int(defs[a]["order"]) < int(defs[b]["order"]) or (int(defs[a]["order"]) == int(defs[b]["order"]) and String(a) < String(b)))
	for id in ids:
		var row := HBoxContainer.new()
		rows.add_child(row)
		var cb := CheckBox.new()
		cb.name = "lay_open_" + id
		cb.text = String(defs[id]["title"])
		cb.button_pressed = bool(P["panels"][id]["open"])
		cb.custom_minimum_size.x = 190
		cb.toggled.connect(func(on): ws.set_open(page, id, on); _changed())
		row.add_child(cb)
		var ob := OptionButton.new()
		ob.name = "lay_dock_" + id
		for i in WorkLayouts.DOCKS.size():
			ob.add_item(String(WorkLayouts.DOCKS[i]).capitalize(), i)
		ob.selected = WorkLayouts.DOCKS.find(String(P["panels"][id]["dock"]))
		ob.item_selected.connect(func(i): menu_dock(page, id, WorkLayouts.DOCKS[i]))
		row.add_child(ob)
	rail_slider.set_value_no_signal(float(P["rail_w"]))
	list.clear()
	for n in ws.names():
		list.add_item(n)
		if n == _picked:
			list.select(list.item_count - 1)
	dock_map.queue_redraw()
	if status.text == "":
		status.text = "layout: %s" % (ws.active if ws.active != "" else ("factory default" if ws.is_factory() else "unsaved changes"))


func _changed() -> void:
	sh.ws_changed()
	refresh()


func _rail_changed(v: float) -> void:
	ws.set_rail(page, int(v))
	_changed()


## a dock chosen from a panel's Dock menu (or by the dock map's drop)
func menu_dock(pg: String, id: String, dock: String) -> void:
	ws.set_dock(pg, id, dock)
	status.text = "%s: %s is now %s" % [pg.capitalize(), String(WorkLayouts.PANEL_DEFS[pg][id]["title"]), "floating" if dock == "float" else "docked " + dock]
	_changed()


func drop(pg: String, id: String, zone: String, at_window: Vector2) -> void:
	if zone == "float":
		var fl: Array = ws.cur["pages"][pg]["panels"][id]["float"]
		ws.cur["pages"][pg]["panels"][id]["float"] = [int(at_window.x - fl[2] * 0.5), int(at_window.y - fl[3] * 0.5), fl[2], fl[3]]
	menu_dock(pg, id, zone)


func pick_name(n: String) -> void:
	_picked = n
	if name_edit != null:
		name_edit.text = n


func save_pressed() -> void:
	var n := name_edit.text.strip_edges()
	status.text = ("saved as '%s'" % n) if ws.save_as(n) else "that name cannot be used (blank, 'Factory', or over 40 characters)"
	_picked = n
	refresh()


func load_pressed() -> void:
	var n := _picked if _picked != "" else name_edit.text.strip_edges()
	status.text = ("loaded '%s'" % n) if ws.load_named(n) else "no layout called '%s'" % n
	_changed()


## the name typed is the new name of the picked layout
func rename_pressed() -> void:
	var n := name_edit.text.strip_edges()
	if _picked != "" and ws.rename(_picked, n):
		status.text = "'%s' is now '%s'" % [_picked, n]
		_picked = n
	else:
		status.text = "cannot rename: pick a layout, then type a new name that no other layout has"
	refresh()


func delete_pressed() -> void:
	if _picked != "" and ws.delete(_picked):
		status.text = "deleted '%s'" % _picked
		_picked = ""
		name_edit.text = ""
	else:
		status.text = "pick a saved layout to delete"
	refresh()


func reset_pressed() -> void:
	ws.reset()
	status.text = "back to the factory layout"
	_changed()
