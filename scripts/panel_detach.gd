class_name PanelDetach
extends Node
## DETACH (lane L37, GAP_AUDIT_1106 UI/UX item 4): a panel (the timeline, the graph editor, the second 3D view) moves into its own OS window, for a second
## monitor, and comes back. The SAME node moves (reparented, never copied), so its signals, callbacks, selection and undo stay main's: nothing is shared by
## copying. The window holds a thin header with a "Re-dock" button above the panel; closing the window re-docks too. What the dock held (parent, child
## index, anchors, offsets, size flags, stretch ratio, minimum size, visibility) is remembered and put back exactly.
## Windows are native OS windows (Window.force_native) where the display driver can make them, embedded in the main window otherwise (--headless).
## `rects()` is what a saved layout keeps (scripts/work_layouts.gd "detached": id -> [x, y, w, h]); `apply(d)` makes the windows match such a dict.
## A saved rect on no screen (the second monitor was unplugged) is moved onto the primary screen (`rescue`).

signal changed

const MIN_WIN := Vector2i(160, 100)

var native := true          # native OS windows when the display driver supports them
var rescue := true          # move a rect that lies on no screen onto the primary one
var layouts: WorkLayouts = null   # the store the shell keeps in step (shell.sync_detached)
var applying := false       # apply() is running: `changed` is sent once at its end

var _reg := {}              # id -> {"get": Callable, "title": String}
var _live := {}             # id -> {"win", "ctrl", "parent", "index", "keep": Dictionary, "box"}


static func in_window(c: Node) -> bool:
	var n := c.get_parent()
	while n != null:
		if n is Window and n != c.get_tree().root:
			return true
		n = n.get_parent()
	return false


static func can_native() -> bool:
	return DisplayServer.get_name() != "headless" and DisplayServer.has_feature(DisplayServer.FEATURE_SUBWINDOWS)


func register(id: String, getter: Callable, title: String) -> void:
	_reg[id] = {"get": getter, "title": title}


func has(id: String) -> bool:
	return _reg.has(id)


func is_detached(id: String) -> bool:
	return _live.has(id)


func window_of(id: String) -> Window:
	return _live[id]["win"] if _live.has(id) else null


func redock_button(id: String) -> Button:
	return _live[id]["btn"] if _live.has(id) else null


func toggle(id: String) -> void:
	if is_detached(id):
		redock(id)
	else:
		detach(id)


func _screen_rects() -> Array:
	var out := []
	if DisplayServer.get_name() == "headless":
		return out
	for i in DisplayServer.get_screen_count():
		out.append(Rect2i(DisplayServer.screen_get_usable_rect(i)))
	return out


## at least a 64 x 32 piece of the rect lies on a screen
func on_a_screen(r: Rect2i) -> bool:
	for s in _screen_rects():
		var c: Rect2i = (s as Rect2i).intersection(r)
		if c.size.x >= 64 and c.size.y >= 32:
			return true
	return false


func _rescued(r: Rect2i) -> Rect2i:
	var scr := _screen_rects()
	if scr.is_empty() or on_a_screen(r):
		return r
	var s: Rect2i = Rect2i(DisplayServer.screen_get_usable_rect(DisplayServer.get_primary_screen()))
	var sz := Vector2i(clampi(r.size.x, MIN_WIN.x, maxi(MIN_WIN.x, s.size.x - 120)), clampi(r.size.y, MIN_WIN.y, maxi(MIN_WIN.y, s.size.y - 120)))
	return Rect2i(s.position + Vector2i(60, 60), sz)


func detach(id: String, rect := Rect2i()) -> bool:
	if _live.has(id) or not _reg.has(id):
		return false
	var c: Control = _reg[id]["get"].call()
	if c == null or not is_instance_valid(c) or c.get_parent() == null:
		return false
	var par: Node = c.get_parent()
	var keep := {"ax": [c.anchor_left, c.anchor_top, c.anchor_right, c.anchor_bottom], "off": [c.offset_left, c.offset_top, c.offset_right, c.offset_bottom],
		"fh": c.size_flags_horizontal, "fv": c.size_flags_vertical, "ratio": c.size_flags_stretch_ratio, "min": c.custom_minimum_size, "vis": c.visible,
		"pos": c.position, "size": c.size}
	var idx := c.get_index()
	var want_size := Vector2i(maxi(MIN_WIN.x, int(c.size.x)), maxi(MIN_WIN.y, int(c.size.y)) + 30)
	if rect.size.x <= 0 or rect.size.y <= 0:
		var spot := Vector2i(c.get_global_rect().position) + Vector2i(40, 40)
		rect = Rect2i(spot, want_size)
	if rescue:
		rect = _rescued(rect)
	rect.size = Vector2i(maxi(rect.size.x, MIN_WIN.x), maxi(rect.size.y, MIN_WIN.y))
	var w := Window.new()
	w.visible = false   # force_native cannot change on a shown window
	w.title = "Kine - " + String(_reg[id]["title"])
	w.force_native = native and can_native()
	w.wrap_controls = false
	w.min_size = MIN_WIN
	w.exclusive = false
	w.transient = false
	w.name = "detach_" + id
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var head := HBoxContainer.new()
	var lab := Label.new()
	lab.text = String(_reg[id]["title"])
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(lab)
	var btn := Button.new()
	btn.text = "Re-dock"
	btn.name = "redock_" + id
	btn.focus_mode = Control.FOCUS_NONE
	btn.tooltip_text = "put this panel back where it was in the main window (closing the window does the same)"
	btn.pressed.connect(redock.bind(id))
	head.add_child(btn)
	box.add_child(head)
	w.add_child(box)
	add_child(w)
	w.position = rect.position
	w.size = rect.size
	par.remove_child(c)
	box.add_child(c)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.size_flags_stretch_ratio = 1.0
	c.custom_minimum_size = Vector2(minf(c.custom_minimum_size.x, 120.0), minf(c.custom_minimum_size.y, 80.0))
	c.visible = true
	var db := c.find_child("detach_" + id, true, false)
	if db is Control:
		(db as Control).visible = false
	w.close_requested.connect(redock.bind(id))
	w.visible = true
	w.position = rect.position
	w.size = rect.size
	_live[id] = {"win": w, "ctrl": c, "parent": par, "index": idx, "keep": keep, "box": box, "btn": btn}
	if not applying:
		changed.emit()
	return true


func redock(id: String) -> bool:
	if not _live.has(id):
		return false
	var L: Dictionary = _live[id]
	_live.erase(id)
	var c: Control = L["ctrl"]
	var w: Window = L["win"]
	var par: Node = L["parent"]
	var k: Dictionary = L["keep"]
	if is_instance_valid(c):
		if c.get_parent() != null:
			c.get_parent().remove_child(c)
		if is_instance_valid(par):
			par.add_child(c)
			par.move_child(c, mini(int(L["index"]), par.get_child_count() - 1))
		else:
			add_child(c)
			c.visible = false
		var a: Array = k["ax"]
		var o: Array = k["off"]
		c.anchor_left = a[0]
		c.anchor_top = a[1]
		c.anchor_right = a[2]
		c.anchor_bottom = a[3]
		c.offset_left = o[0]
		c.offset_top = o[1]
		c.offset_right = o[2]
		c.offset_bottom = o[3]
		c.size_flags_horizontal = k["fh"]
		c.size_flags_vertical = k["fv"]
		c.size_flags_stretch_ratio = k["ratio"]
		c.custom_minimum_size = k["min"]
		c.visible = k["vis"] and is_instance_valid(par)
		var db := c.find_child("detach_" + id, true, false)
		if db is Control:
			(db as Control).visible = true
	if is_instance_valid(w):
		w.hide()
		w.queue_free()
	if not applying:
		changed.emit()
	return true


func redock_all() -> void:
	var was := applying
	applying = true
	for id in _live.keys():
		redock(id)
	applying = was
	if not was:
		changed.emit()


## id -> [x, y, w, h] of every detached window as it is now (the user may have moved or resized it)
func rects() -> Dictionary:
	var out := {}
	for id in _live:
		var w: Window = _live[id]["win"]
		out[id] = [w.position.x, w.position.y, w.size.x, w.size.y]
	return out


## make the windows match d (id -> [x, y, w, h]): ids in d are detached at their rect (or moved there), the others come back
func apply(d: Dictionary) -> void:
	applying = true
	for id in _live.keys():
		if not d.has(id):
			redock(id)
	for id in d:
		if not _reg.has(id) or not (d[id] is Array) or (d[id] as Array).size() != 4:
			continue
		var a: Array = d[id]
		var r := Rect2i(int(a[0]), int(a[1]), int(a[2]), int(a[3]))
		if rescue:
			r = _rescued(r)
		if _live.has(id):
			var w: Window = _live[id]["win"]
			w.position = r.position
			w.size = r.size
		else:
			detach(id, r)
	applying = false
	changed.emit()
