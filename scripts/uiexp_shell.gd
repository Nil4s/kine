class_name UiExpShell
extends Node
## UIEXP SHELL (lane L2, docs/UIEXP_DESIGN.md): the Expert Part / Assembly / Engineering screens on a wide window.
##   RAIL     a tool rail on the left, icons grouped by task (SKETCH, CREATE, MODIFY, CHECK on a Part; ASSEMBLE, CHECK, DELIVER on an
##            Assembly), the common tools shown, the rarer ones under the group's "more" menu. Every rail button is a PROXY of the
##            tool button the ribbon / panel has always had: it presses that button (so names, meta, undo steps and keys are the old ones).
##   WIDE     the rail replaces the ribbon's tool buttons only when the window is at least WIDE (1600 x 900). Below that the old
##            compact ribbon and panel rows stay as they were (tests, 1280 x 720 and 1366 x 768 keep their layout).
##   START    fit_window(): the first window is never bigger than the usable screen and never off it.
## Colours and fonts are the app's own (Tok); the icons are scripts/uiexp_icons.gd.

const WIDE := Vector2(1600, 900)
const LABELLED := Vector2(1920, 1080)   # L15: from this window size each rail button carries its tool's name beside the icon; below it icons only
const LABEL_PX := 11
const BTN := Vector2(40, 36)
const ICON_PX := 22
const PAD := 6.0
const RAIL_W := 2.0 * 40.0 + 2.0 * 6.0 + 4.0   # two columns of buttons + the panel's margins
const ICON_OF := {"Check motion": "motion", "Move": "move", "Turn": "turn", "Add part": "add_part", "Edit part": "edit_part", "Finish sketch": "finish_sketch",
	"Done": "done", "Fits": "fits", "BOM": "bom", "Stages": "stages", "STL": "stl", "GLB": "glb", "STEP": "step", "Video": "video", "Drawing": "drawing",
	"Schematic": "schematic", "Open": "open", "Save": "save", "New": "new", "Remove": "remove"}
const SHOWN := 1   # a group's "primary" flag value in GROUPS

## [group id, caption, [[label, primary?], ...]]: a label is the tool button's own name (Part: tool_btns key; Assembly: ASM_NAMES)
const PART_GROUPS := [
	["g_sketch", "SKETCH", [["Line", 1], ["Rectangle", 1], ["Circle", 1], ["Dimension", 1], ["Arc", 0], ["Spline", 0], ["Constrain", 0], ["Finish sketch", 1]]],
	["g_create", "CREATE", [["Extrude", 1], ["Revolve", 1], ["Mirror", 1], ["Loft", 1], ["Sweep", 0], ["Offset plane", 0], ["Split", 0], ["Canvas", 0], ["Pattern", 0], ["Combine", 0], ["Primitive", 0], ["Ornament", 0], ["Roof shell", 0], ["Hinge", 0]]],
	["g_modify", "MODIFY", [["Fillet", 1], ["Chamfer", 1], ["Shell", 1], ["Appearance", 0], ["Offset face", 0], ["Draft", 0]]],
	["g_check", "CHECK", [["Measure", 1], ["Section", 1]]],
]
const ASM_GROUPS := [
	["g_assemble", "ASSEMBLE", [["Add part", 1], ["Move", 1], ["Turn", 1], ["Edit part", 1], ["Remove", 1], ["Open", 0], ["Save", 0], ["New", 0]]],
	["g_check", "CHECK", [["Check motion", 1], ["Fits", 1], ["BOM", 1], ["Stages", 1]]],
	["g_deliver", "DELIVER", [["STL", 1], ["GLB", 1], ["STEP", 1], ["Video", 0], ["Drawing", 0], ["Schematic", 0], ["Done", 1]]],
]
const ASM_NAMES := {"Add part": "asm_add", "Open": "asm_open", "Save": "asm_save", "New": "asm_new", "Check motion": "asm_motion", "BOM": "asm_bom",
	"Stages": "asm_stages", "Fits": "asm_fits", "Move": "asm_mode_move", "Turn": "asm_mode_turn", "Edit part": "asm_edit", "Remove": "asm_remove",
	"STL": "asm_export_stl", "GLB": "asm_export_glb", "STEP": "asm_export_step", "Video": "asm_export_video", "Done": "asm_done",
	"Drawing": "asm_export_drawing", "Schematic": "asm_export_schematic"}

var bu: BuildUI
var m: Node
var rail: PanelContainer
var vb: VBoxContainer
var kind := ""              # "" | "part" | "asm": what the rail was built for
var proxies := {}           # label -> {"rail": Button | null, "src": Button, "more": bool}
var hidden_rows: Array = [] # the asm panel's rows that hold only proxied buttons
var _was_on := false
var _lab := false           # the rail was built with labels
var _rail_w := RAIL_W       # the rail's current width (RAIL_W icons only; wider with labels)
var ws: WorkLayouts         # L20: the named workspace layouts (scripts/work_layouts.gd); the factory one leaves every panel where the app puts it
var layouts_ui: WorkLayoutsUI   # L20: the layouts dialog (View: workspace layouts)
var _live := false          # a non-factory layout is in use
var _ws_hold := {}          # control instance id -> true: hidden by the layout (closed), shown again when it opens or the layout is the factory one


func setup(b: BuildUI) -> void:
	bu = b
	m = b.m
	rail = PanelContainer.new()
	rail.name = "uiexp_rail"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Tok.c("panel")
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(5)
	rail.add_theme_stylebox_override("panel", sb)
	rail.visible = false
	rail.mouse_filter = Control.MOUSE_FILTER_STOP
	m.ui_root.add_child(rail)
	m.ui_root.add_child(self)
	ws = WorkLayouts.new()
	layouts_ui = WorkLayoutsUI.new(self)
	m.ui_root.add_child(layouts_ui)
	_live = not ws.is_factory()


## the wide layout is on for this window
func wide() -> bool:
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	return vs.x >= WIDE.x and vs.y >= WIDE.y


## the labelled layout is on for this window
func labelled() -> bool:
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	return vs.x >= LABELLED.x and vs.y >= LABELLED.y


func screen_kind() -> String:
	if bu == null or bu.part == null or bu.easy_ui():
		return ""
	if bu.asm != null and bu.asm.on:
		return "asm"
	if bu.part.on and bu.part.chrome():
		return "part"
	return ""


## true while the rail stands in for the ribbon / panel tool buttons
func active() -> bool:
	return wide() and screen_kind() != ""


## the room the rail takes on the left (nav_clear_rect adds it, so the browser, the panels and the timeline start right of it)
func inset() -> float:
	return (rail_w() + PAD + 2.0) if active() else 0.0


## the rail's width: its own (icons or labels), at least the layout's rail width when a saved layout is in use
func rail_w() -> float:
	var pg := page_name()
	if _live and pg != "":
		return maxf(_rail_w, float(ws.cur["pages"][pg]["rail_w"]))
	return _rail_w


# ---------------------------------------------------------------- L20: workspace layouts

## the workspace page of the screen shown now ("" = not an Expert Part / Assembly screen)
func page_name() -> String:
	match screen_kind():
		"part":
			return "part"
		"asm":
			return "engineering" if bu.asm.fits.is_open() else "assembly"
	return ""


## a saved (non-factory) layout places the panels; the factory layout leaves the app's own placement alone
func ws_live() -> bool:
	return _live and active()


## the layout in `ws` changed (loaded, edited, reset): re-place everything
func ws_changed() -> void:
	_live = not ws.is_factory()
	if not _live:
		_unhide()
	m._fit_top.call_deferred()
	bu.sync.call_deferred()


## the panels of a page the layout can place: id -> control
func dock_controls(page: String) -> Dictionary:
	if bu == null:
		return {}
	match page:
		"part":
			return {"browser": bu.part.browser, "inspector": bu.part.side, "timeline": bu.part.tl}
		"assembly":
			return {"parts": bu.asm.src_panel, "inspector": bu.asm.panel}
		"engineering":
			return {"parts": bu.asm.src_panel, "inspector": bu.asm.panel, "fits": bu.asm.fits.panel}
	return {}


func _unhide() -> void:
	for pg in ["part", "assembly", "engineering"]:
		var ctr := dock_controls(pg)
		for id in ctr:
			if is_instance_valid(ctr[id]) and _ws_hold.get(str(ctr[id].get_instance_id()), false):
				(ctr[id] as Control).visible = true
				_ws_hold.erase(str(ctr[id].get_instance_id()))


## called by the Part / Assembly screens right after they place their panels: with a saved layout in use, the layout moves them. Returns {"free": the
## middle the docks leave to the 3D view} (empty when the app's own placement stands)
func dock_apply(page: String, cl: Rect2) -> Dictionary:
	if not ws_live() or page != page_name():
		return {}
	var ctr := dock_controls(page)
	var P: Dictionary = ws.cur["pages"][page]
	var only := []
	var mins := {}
	var wants := {}
	for id in ctr:
		var c: Control = ctr[id]
		var held: bool = _ws_hold.get(str(c.get_instance_id()), false)
		if not (c.visible or held):
			continue
		only.append(id)
		var cm := c.get_combined_minimum_size()
		var df: Dictionary = WorkLayouts.PANEL_DEFS[page][id]
		mins[id] = Vector2(maxf((df["min"] as Vector2).x, minf(cm.x, 520.0)), maxf((df["min"] as Vector2).y, minf(cm.y, cl.size.y * 0.45)))   # the content's own least height (a dialog), so a bottom dock is never shorter than what it holds
		wants[id] = Vector2(c.size.x, maxf(c.size.y, cm.y if held else 0.0))
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var chrome := (WorkLayouts.TOP + WorkLayouts.PAGEBAR) * vs.x + minf(rail_w(), 400.0) * WorkLayouts.RAIL_H_EST
	var r := WorkLayouts.solve(P, page, vs, cl, chrome, only, mins, wants)
	var rects: Dictionary = r["rects"]
	var free := Rect2(cl.position.x + WorkLayouts.GAP, cl.position.y, cl.size.x - 2.0 * WorkLayouts.GAP, cl.size.y)
	for id in only:
		var c: Control = ctr[id]
		var key := str(c.get_instance_id())
		if rects.has(id):
			if _ws_hold.get(key, false):
				c.visible = true
				_ws_hold.erase(key)
			var q: Rect2 = rects[id]
			c.size = q.size
			c.position = q.position
			var dk := String(P["panels"][id]["dock"])
			if dk == "left":
				free = Rect2(maxf(free.position.x, q.end.x + WorkLayouts.GAP), free.position.y, free.end.x - maxf(free.position.x, q.end.x + WorkLayouts.GAP), free.size.y)
			elif dk == "right":
				free.size.x = minf(free.end.x, q.position.x - WorkLayouts.GAP) - free.position.x
		else:
			c.visible = false
			_ws_hold[key] = true
	return {"free": free, "closed": r["closed"]}


## the top of the room under the ribbon: the Part and Assembly screens start below the ribbon bar's own bottom edge (its tools and
## captions are 81 px tall, TOP_H is 74), so no panel overlaps the bar
func top_y(y0: float) -> float:
	if screen_kind() == "" or m.ui_top_bar == null:
		return y0
	return maxf(y0, m.ui_top_bar.get_global_rect().end.y - 3.0)


## main's ribbon asks: is this tool button's job done by the rail?
func hides(b: Node) -> bool:
	if not active():
		return false
	for k in proxies:
		if proxies[k]["src"] == b:
			return true
	return b is VSeparator and bu.part.my_seps.has(b)


func _src_of(label: String) -> Button:
	if kind == "part":
		if label == "Finish sketch":
			return bu.part.finish_btn
		return bu.part.tool_btns.get(label, null)
	var nm: String = ASM_NAMES.get(label, "")
	return bu.asm.panel.find_child(nm, true, false) as Button if nm != "" else null


func _icon_btn(label: String, src: Button) -> Button:
	var b := Button.new()
	b.name = "rail_" + UiExpIcons.id_of(label)
	b.custom_minimum_size = BTN
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = src.toggle_mode
	b.icon = UiExpIcons.tex(ICON_OF.get(label, UiExpIcons.id_of(label)), ICON_PX)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.expand_icon = false
	b.tooltip_text = _tip(label, src)
	b.set_meta("icon_id", ICON_OF.get(label, UiExpIcons.id_of(label)))
	b.set_meta("label", label)
	b.pressed.connect(_press.bind(label))
	if _lab:
		_label_btn(b, label)
	return b


## a labelled rail button: icon, then the tool's own name, one line, 11 px, nothing clipped
func _label_btn(b: Button, text: String) -> void:
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT   # a centred icon sat on top of the name (seen in the first screenshot)
	b.clip_text = false
	b.add_theme_font_size_override("font_size", LABEL_PX)
	b.custom_minimum_size = Vector2(0, BTN.y - 6.0)


## one width for the whole labelled column: the widest button (icon + name + the theme's margins) so no name is cut. Run every frame while the
## labels are on (the theme's fonts reach the buttons a frame after they are built); true when the width changed
func _fit_labels() -> bool:
	if not _lab or vb == null:
		return false
	var btns: Array = []
	var wmax := 0.0
	for g2 in vb.get_children():
		for c in g2.get_children():
			if c is Button:
				(c as Button).custom_minimum_size.x = 0.0
				btns.append(c)
	for c in btns:
		wmax = maxf(wmax, maxf((c as Button).get_minimum_size().x, _need(c as Button)))
	for c in btns:
		(c as Button).custom_minimum_size.x = wmax
	var nw := wmax + 2.0 * 6.0 + 4.0
	var changed := not is_equal_approx(nw, _rail_w)
	_rail_w = nw
	return changed


## the width a labelled button needs: its style's margins + the icon (capped by the theme's icon_max_width) + the gap + the name in its own font
func _need(b: Button) -> float:
	var sb: StyleBox = b.get_theme_stylebox("normal")
	var w := sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT)
	if b.icon != null:
		var mx := b.get_theme_constant("icon_max_width")
		w += (minf(float(b.icon.get_width()), float(mx)) if mx > 0 else float(b.icon.get_width())) + float(b.get_theme_constant("h_separation"))
	return w + b.get_theme_font("font").get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size("font_size")).x + 2.0


func _tip(label: String, src: Button) -> String:
	var t := TooltipFit.source_of(src).get_slice("\n[", 0)
	return label if t == "" else label + "\n" + t


func _press(label: String) -> void:
	var src: Button = proxies[label]["src"]
	if src == null or not is_instance_valid(src) or src.disabled:
		return
	if src.toggle_mode:
		src.set_pressed(not src.button_pressed)
	src.pressed.emit()


func _more_pick(id: int, group: String) -> void:
	for k in proxies:
		if proxies[k]["more"] and int(proxies[k]["id"]) == id and proxies[k]["group"] == group:
			_press(k)
			return


func _rebuild() -> void:
	if vb != null:
		rail.remove_child(vb)
		vb.queue_free()
	proxies = {}
	_lab = labelled()
	_rail_w = RAIL_W
	vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	rail.add_child(vb)
	var groups: Array = PART_GROUPS if kind == "part" else ASM_GROUPS
	var gi := 0
	for g in groups:
		var cap := Label.new()
		cap.text = String(g[1])
		cap.add_theme_font_size_override("font_size", 12)
		cap.add_theme_color_override("font_color", Tok.c("info"))
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if gi > 0:
			var sp := Control.new()
			sp.custom_minimum_size.y = 4
			vb.add_child(sp)
		vb.add_child(cap)
		var grid := GridContainer.new()
		grid.columns = 1 if _lab else 2
		grid.add_theme_constant_override("h_separation", 2)
		grid.add_theme_constant_override("v_separation", 2)
		vb.add_child(grid)
		var more_ids: Array = []
		var more_menu: MenuButton = null
		for t in g[2]:
			var label := String(t[0])
			var src := _src_of(label)
			if src == null:
				continue
			if int(t[1]) == SHOWN:
				var b := _icon_btn(label, src)
				grid.add_child(b)
				proxies[label] = {"rail": b, "src": src, "more": false, "group": g[0]}
			else:
				if more_menu == null:
					more_menu = MenuButton.new()
					more_menu.name = "rail_more_" + String(g[0])
					more_menu.custom_minimum_size = BTN
					more_menu.focus_mode = Control.FOCUS_NONE
					more_menu.flat = false
					more_menu.icon = UiExpIcons.tex("more", ICON_PX)
					if _lab:
						_label_btn(more_menu, "More")
					more_menu.tooltip_text = "More %s tools" % String(g[1]).to_lower()
					more_menu.set_meta("icon_id", "more")
					more_menu.get_popup().id_pressed.connect(_more_pick.bind(String(g[0])))
					more_menu.get_popup().add_theme_font_size_override("font_size", 14)
					grid.add_child(more_menu)
				var id := more_ids.size()
				more_ids.append(label)
				var pm := more_menu.get_popup()
				pm.add_icon_item(UiExpIcons.tex(ICON_OF.get(label, UiExpIcons.id_of(label)), 18), label, id)
				proxies[label] = {"rail": null, "src": src, "more": true, "group": g[0], "id": id}
		gi += 1
	_fit_labels()
	_hide_asm_rows()
	rail.reset_size()


## the Assembly panel's rows that hold only buttons the rail now carries
func _hide_asm_rows() -> void:
	hidden_rows = []
	if kind != "asm":
		return
	for k in proxies:
		var s: Control = (proxies[k]["src"] as Control).get_parent() as Control
		if s is HBoxContainer and not hidden_rows.has(s):
			hidden_rows.append(s)


func _row_all_proxied(row: Control) -> bool:
	for c in row.get_children():
		if c is Button:
			var found := false
			for k in proxies:
				if proxies[k]["src"] == c:
					found = true
					break
			if not found:
				return false
	return true


func _process(_dt: float) -> void:
	if bu == null or m == null:
		return
	var k := screen_kind() if wide() else ""
	if k != kind or (k != "" and labelled() != _lab):
		_restore_rows()
		kind = k
		if k != "":
			_rebuild()
		m._fit_top.call_deferred()
		bu.sync.call_deferred()
	var on := k != ""
	if on != _was_on:
		_was_on = on
		m._fit_top.call_deferred()
	rail.visible = on
	if not on:
		return
	if _fit_labels():
		m._fit_top.call_deferred()
	var cl: Rect2 = m.nav_clear_rect()
	rail.position = Vector2(PAD, cl.position.y + 4.0)
	rail.size = Vector2(rail_w(), minf(rail.get_combined_minimum_size().y, cl.size.y - 8.0))
	for row in hidden_rows:
		if is_instance_valid(row):
			(row as Control).visible = false
	for lab in proxies:
		var p: Dictionary = proxies[lab]
		var src: Button = p["src"]
		if not is_instance_valid(src):
			continue
		if p["rail"] != null:
			var rb: Button = p["rail"]
			rb.disabled = src.disabled
			if rb.toggle_mode:
				rb.set_pressed_no_signal(src.button_pressed)
			var tip := _tip(lab, src)
			if rb.tooltip_text != tip and not rb.has_meta("tip_wrapped"):
				rb.tooltip_text = tip
		else:
			var grp: String = p["group"]
			var mb := vb.find_child("rail_more_" + grp, true, false) as MenuButton
			if mb != null:
				mb.get_popup().set_item_disabled(int(p["id"]), src.disabled)


func _restore_rows() -> void:
	for row in hidden_rows:
		if is_instance_valid(row):
			(row as Control).visible = true
	hidden_rows = []


# ---------------------------------------------------------------- the window

## the first window rect (outer, decorations included) inside the usable screen: size = the wanted client size, shrunk to fit, the
## position pulled in. Pure: usable (the screen's usable rect), pos / want (the window now), deco (title bar + borders: outer - client)
static func start_rect(usable: Rect2i, pos: Vector2i, want: Vector2i, deco: Vector2i) -> Rect2i:
	var client := Vector2i(mini(want.x, maxi(usable.size.x - deco.x, 320)), mini(want.y, maxi(usable.size.y - deco.y, 240)))
	var outer := client + deco
	var p := Vector2i(clampi(pos.x, usable.position.x, maxi(usable.end.x - outer.x, usable.position.x)), clampi(pos.y, usable.position.y, maxi(usable.end.y - outer.y, usable.position.y)))
	return Rect2i(p, outer)


## applied once at the start of a real run (never in a test: its window sits off-screen on purpose)
static func fit_window(win: Window) -> void:
	if win.mode != Window.MODE_WINDOWED:
		return
	var usable := DisplayServer.screen_get_usable_rect(win.current_screen)
	var deco := win.get_size_with_decorations() - win.size
	var r := start_rect(usable, win.position, win.size, deco)
	var client := r.size - deco
	win.min_size = Vector2i(mini(win.min_size.x, client.x), mini(win.min_size.y, client.y))
	win.size = client
	win.position = r.position
