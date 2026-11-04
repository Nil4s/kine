## part_warn_ui.gd - the WARNINGS panel of the Part workspace (item 221). A level toggle (Off / Look / Print / Engineering), then one row per warning:
## a plain badge (LOOK / PRINT / ENG), the sentence, and the mutes ("Mute" this warning on this part, "Part" every warning of this part, "Kind" this
## warning on every part). The list is PartWarn.report(rec)["warnings"], the very list agent_tools "part_warn" answers. Every toggle (a level, a mute, an unmute)
## is ONE undo step: the level and the mutes live in the part record (rec["warn_level"], rec["warn_mute"]).
class_name PartWarnUI
extends PanelContainer

const W := 290.0
const MAX_ROWS_H := 250.0
const GIZMO_W := 150.0   # the view cube and its buttons own the top-right corner: the panel stands left of them
const TOP_Y := 80.0
const BADGE_COL := {"look": Color(0.30, 0.62, 0.38), "print": Color(0.76, 0.52, 0.14), "engineering": Color(0.30, 0.46, 0.80)}

var m: Node
var pu: Object
var box: VBoxContainer
var body: VBoxContainer          # C49b: help, status, rows, mutes (hidden in the narrow form)
var lv_btns := {}
var help: Label
var scroll: ScrollContainer
var rows_box: VBoxContainer
var muted_box: HFlowContainer
var muted_title: Label
var status: Label
var shown := {}                  # the last report shown
var _key := ""
var _t := 0
var narrow := false              # C49b: no clear spot for the full panel: the four level buttons alone, short words (tooltips carry the rest)
var places := 0                  # C49b: how many times the strip was placed (a layout change, never a frame)
var _pkey := ""
var _wired := false
var _placing := false


func build(parent: Node) -> void:
	name = "partwarn_panel"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(W, 0)
	size = Vector2(W, 10)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.11, 0.14, 0.94)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(8)
	sb.border_color = Color(0.3, 0.33, 0.4)
	sb.set_border_width_all(1)
	add_theme_stylebox_override("panel", sb)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	add_child(box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	box.add_child(top)
	var grp := ButtonGroup.new()
	for lv in PartWarn.LEVELS:
		var b := Button.new()
		b.name = "partwarn_lv_" + lv
		b.text = PartWarn.LEVEL_WORDS[lv]
		b.tooltip_text = String(PartWarn.LEVEL_HELP[lv])
		b.toggle_mode = true
		b.button_group = grp
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 12)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_pick.bind(lv))
		top.add_child(b)
		lv_btns[lv] = b
	body = VBoxContainer.new()
	body.name = "partwarn_body"
	body.add_theme_constant_override("separation", 5)
	box.add_child(body)
	help = Label.new()
	help.name = "partwarn_help"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(W - 20, 0)
	help.add_theme_font_size_override("font_size", 11)
	help.add_theme_color_override("font_color", Color(0.7, 0.74, 0.8))
	body.add_child(help)
	status = Label.new()
	status.name = "partwarn_status"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(W - 20, 0)
	status.add_theme_font_size_override("font_size", 12)
	body.add_child(status)
	scroll = ScrollContainer.new()
	scroll.name = "partwarn_scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(W - 20, 0)
	body.add_child(scroll)
	rows_box = VBoxContainer.new()
	rows_box.name = "partwarn_rows"
	rows_box.add_theme_constant_override("separation", 6)
	rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows_box)
	muted_title = Label.new()
	muted_title.add_theme_font_size_override("font_size", 11)
	muted_title.add_theme_color_override("font_color", Color(0.7, 0.74, 0.8))
	body.add_child(muted_title)
	muted_box = HFlowContainer.new()
	muted_box.name = "partwarn_muted"
	muted_box.add_theme_constant_override("h_separation", 4)
	muted_box.add_theme_constant_override("v_separation", 3)
	body.add_child(muted_box)
	parent.add_child(self)
	resized.connect(_place)


func _rec() -> Dictionary:
	return m.S.part


## C49b: the strip stands where it covers nothing: not the side dialog, the browser, the timeline, the view cube. Full panel first, then the narrow form (levels only).
## Called on a layout change (resize, a dialog or browser opening, closing or resizing, the report changing), not per frame.
func _place() -> void:
	if _placing or not visible:
		return
	var vp: Vector2 = get_viewport_rect().size
	var obs := _obstacles()
	var k := "%s|%s" % [str(vp), str(obs)]   # the content changing clears _pkey itself (_fill)
	if k == _pkey:
		return
	_pkey = k
	_placing = true
	var was_nar := narrow
	var was_pos := position
	var spot := Vector2(-1, -1)
	for form in [false, true]:
		_apply_form(form)
		spot = _free_spot(vp, obs)
		if spot.x >= 0.0:
			break
	if spot.x < 0.0:
		spot = Vector2(maxf(vp.x - size.x - GIZMO_W, 8.0), TOP_Y)
	position = spot
	if narrow != was_nar or not position.is_equal_approx(was_pos):
		places += 1   # counted when the strip actually moved or changed form: a side dialog whose width flaps by a scrollbar does not move it
	_placing = false


func _apply_form(nar: bool) -> void:
	narrow = nar
	for lv in lv_btns:
		var b: Button = lv_btns[lv]
		b.add_theme_font_size_override("font_size", 11 if nar else 12)
		for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			if nar:
				var sb := b.get_theme_stylebox(st).duplicate() as StyleBox
				sb.content_margin_left = 4
				sb.content_margin_right = 4
				b.add_theme_stylebox_override(st, sb)
			else:
				b.remove_theme_stylebox_override(st)
		b.text = ("Eng" if lv == "engineering" else String(PartWarn.LEVEL_WORDS[lv])) if nar else String(PartWarn.LEVEL_WORDS[lv])
	body.visible = not nar
	custom_minimum_size = Vector2(0.0 if nar else W, 0)
	reset_size()


## rects (view space) the strip must keep clear of; a panel that is not there is skipped
func _obstacles() -> Array:
	var out: Array = []
	if pu == null:
		return out
	var nodes: Array = [pu.get("side"), pu.get("browser"), m.get("ui_cube"), m.get("ui_timeline")]
	for n in nodes:
		if n is Control and (n as Control).is_visible_in_tree():
			var c := n as Control
			var r := c.get_global_rect().grow(2.0)
			if n != m.get("ui_timeline"):   # a column: the strip stands on the top row, and the browser's height changes every frame on its own (a height that flaps must not re-place the strip)
				r.size.y = 100000.0
			out.append(r)
	return out


## the first top-row spot (left of the side dialog, right of the browser, left of the cube) that clears every obstacle, or (-1, -1)
func _free_spot(vp: Vector2, obs: Array) -> Vector2:
	var want := get_combined_minimum_size()
	var xs: Array = [vp.x - want.x - GIZMO_W]
	for r in obs:
		xs.append((r as Rect2).position.x - want.x - 4.0)
		xs.append((r as Rect2).end.x + 4.0)
	xs.sort()
	xs.reverse()
	if position.y == TOP_Y:   # a spot that is still clear stays (a dialog whose edge flaps by a scrollbar does not walk the strip)
		xs.push_front(position.x)
	for x in xs:
		if x < 8.0 or x + want.x > vp.x - 8.0:
			continue
		var me := Rect2(Vector2(x, TOP_Y), want)
		var clear := true
		for r in obs:
			if me.intersects(r):
				clear = false
				break
		if clear:
			return Vector2(x, TOP_Y)
	return Vector2(-1, -1)


## watch the panels the strip must keep clear of; each change re-places once
func _wire() -> void:
	if _wired or pu == null:
		return
	_wired = true
	for n in [pu.get("side"), pu.get("browser"), m.get("ui_cube"), m.get("ui_timeline")]:
		if n is Control:
			(n as Control).resized.connect(_place)
			(n as Control).visibility_changed.connect(_place)
			(n as Control).item_rect_changed.connect(_place)
	get_viewport().size_changed.connect(_place)


func _process(_dt: float) -> void:
	var on: bool = pu != null and pu.chrome() and not _rec().is_empty()   # the Expert chrome; Easy keeps its own screen
	if on != visible:
		visible = on
		if on:
			_wire()
			_pkey = ""
			_place()
	if not on:
		return
	refresh(false)


## re-read the report when the part (or the level / mutes) changed; at most every 300 ms while the mouse is down (a slider drag replays the part every frame)
func refresh(force: bool) -> void:
	var rec := _rec()
	var k := "%s|%s|%s|%s|%s|%s|%s" % [PartWarn.level_of(rec), str(hash(JSON.stringify(rec.get("features", [])))), str(rec.get("warn_mute", [])), str(rec.get("body_names", [])), str(rec.get("material", "")), str(rec.get("load_n", "")), str(rec.get("name", ""))]
	if k == _key and not force:
		return
	var now := Time.get_ticks_msec()
	if not force and not shown.is_empty() and (now - _t < 300 or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)):
		return
	_key = k
	_t = now
	shown = PartWarn.report(rec)
	_fill()


func _fill() -> void:
	var rec := _rec()
	var lv := String(shown.get("level", "off"))
	for l in lv_btns:
		(lv_btns[l] as Button).set_pressed_no_signal(l == lv)
	help.text = String(PartWarn.LEVEL_HELP[lv])
	for c in rows_box.get_children():
		rows_box.remove_child(c)
		c.queue_free()
	for c in muted_box.get_children():
		muted_box.remove_child(c)
		c.queue_free()
	var ws: Array = shown.get("warnings", [])
	if lv == "off":
		status.text = ""
	elif not bool(shown.get("ok", true)):
		status.text = "Cannot check: " + String(shown.get("error", ""))
	elif ws.is_empty():
		status.text = "No warnings at %s." % PartWarn.LEVEL_WORDS[lv]
	else:
		status.text = "Warnings: %d" % ws.size()
	status.visible = status.text != ""
	var n := 0
	for w in ws:
		rows_box.add_child(_row(w, n))
		n += 1
	scroll.visible = n > 0
	scroll.custom_minimum_size = Vector2(W - 20, MAX_ROWS_H if n > 2 else (0.0 if n == 0 else 110.0 * n))
	var mu: Array = shown.get("muted", [])
	var keys: Array = rec.get("warn_mute", [])
	muted_title.visible = not keys.is_empty()
	muted_title.text = "Muted (%d hidden now, %d mute%s):" % [mu.size(), keys.size(), "" if keys.size() == 1 else "s"]
	var i := 0
	for k in keys:
		var b := Button.new()
		b.name = "partwarn_unmute_%d" % i
		b.text = "Unmute %s" % String(k)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 11)
		b.pressed.connect(_mute.bind(String(k), false))
		muted_box.add_child(b)
		i += 1
	_pkey = ""
	reset_size()
	_place()


func _row(w: Dictionary, n: int) -> Control:
	var hb := HBoxContainer.new()
	hb.name = "partwarn_row_%d" % n
	hb.add_theme_constant_override("separation", 6)
	var chip := PanelContainer.new()
	chip.name = "partwarn_badge_%d" % n
	var cs := StyleBoxFlat.new()
	cs.bg_color = BADGE_COL.get(String(w["level"]), Color(0.4, 0.4, 0.4))
	cs.set_corner_radius_all(4)
	cs.content_margin_left = 5
	cs.content_margin_right = 5
	cs.content_margin_top = 1
	cs.content_margin_bottom = 1
	chip.add_theme_stylebox_override("panel", cs)
	chip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var bl := Label.new()
	bl.text = String(w["badge"])
	bl.add_theme_font_size_override("font_size", 10)
	bl.add_theme_color_override("font_color", Color(1, 1, 1))
	chip.add_child(bl)
	hb.add_child(chip)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 2)
	hb.add_child(vb)
	var tx := Label.new()
	tx.name = "partwarn_text_%d" % n
	tx.text = String(w["text"])
	tx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tx.custom_minimum_size = Vector2(W - 70, 0)
	tx.add_theme_font_size_override("font_size", 12)
	vb.add_child(tx)
	var bb := HBoxContainer.new()
	bb.add_theme_constant_override("separation", 3)
	vb.add_child(bb)
	var part := String(w["part"])
	var opts := [["Mute", "%s@%s" % [w["id"], part]], ["Mute kind", "%s@*" % w["id"]]]
	if part != "":
		opts.insert(1, ["Mute part", "*@%s" % part])
	var k := 0
	for o in opts:
		var b := Button.new()
		b.name = "partwarn_mute_%d_%d" % [n, k]
		b.text = String(o[0])
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 10)
		b.pressed.connect(_mute.bind(String(o[1]), true))
		bb.add_child(b)
		k += 1
	return hb


## one undo step: the level of the part's warnings
func _pick(lv: String) -> void:
	set_level(lv)


func set_level(lv: String) -> void:
	var rec := _rec()
	if rec.is_empty() or PartWarn.level_of(rec) == lv:
		return
	m._push_undo()
	PartWarn.set_level(m.S.part, lv)
	refresh(true)


## one undo step: a mute or an unmute ("<id>@<part>", "<id>@*", "*@<part>")
func _mute(key: String, on: bool) -> void:
	set_mute(key, on)


func set_mute(key: String, on: bool) -> void:
	var rec := _rec()
	if rec.is_empty():
		return
	m._push_undo()
	PartWarn.set_mute(m.S.part, key, on)
	refresh(true)
