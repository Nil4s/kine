class_name KeyTips
extends RefCounted
## P100 THE KEYBOARD SHORTCUTS CARD (Friday plan 100): Easy Part teaches ONE shortcut at a time. A button clicked three times that has a key
## shows a small card at the bottom-left ("Tip: Ctrl+Z does Undo", with Got it). One card at a time, each key taught once ever (user settings:
## the [keytips] section of main.settings, so it survives a restart), at most one card per two minutes, never while a shape is being dragged or
## drawn. Pressing the key counts as learned and takes its card away. The list of every key is the Shortcuts button in the Easy button's popup.
## Nothing here touches the part: a card and a list are not undo steps.

const CLICKS := 3             # clicks of one button before its key is taught
const GAP_MS := 120000        # at most one card per two minutes
const SECTION := "keytips"

## id, the key as shown, what it does (the card says "does <name>"), the key code, Ctrl needed, what the list says
const LIST := [
	{"id": "undo", "keys": "Ctrl+Z", "name": "Undo", "code": KEY_Z, "ctrl": true, "long": "takes the last change back"},
	{"id": "redo", "keys": "Ctrl+Y", "name": "Redo", "code": KEY_Y, "ctrl": true, "long": "puts back what Undo took back"},
	{"id": "draw", "keys": "D", "name": "Draw shape", "code": KEY_D, "ctrl": false, "long": "then drag on the grid"},
	{"id": "pull", "keys": "P", "name": "Pull it up", "code": KEY_P, "ctrl": false, "long": "makes the newest shape a solid"},
	{"id": "hole", "keys": "H", "name": "Cut a hole", "code": KEY_H, "ctrl": false, "long": "opens the hole choices"},
	{"id": "mirror", "keys": "M", "name": "Mirror that", "code": KEY_M, "ctrl": false, "long": "adds a mirror copy"},
	{"id": "delete", "keys": "Delete", "name": "Take out the newest piece", "code": KEY_DELETE, "ctrl": false, "long": "takes out the picked piece, or the newest"},
	{"id": "cancel", "keys": "Esc", "name": "Cancel a shape", "code": KEY_ESCAPE, "ctrl": false, "long": "stops a shape you are drawing"},
	{"id": "search", "keys": "S", "name": "Search every command", "code": KEY_S, "ctrl": false, "long": "opens the search box"},
	{"id": "front", "keys": "1", "name": "Front view", "code": KEY_1, "ctrl": false, "long": "looks at the part from the front"},
	{"id": "left", "keys": "2", "name": "Left view", "code": KEY_2, "ctrl": false, "long": "looks at the part from the left"},
	{"id": "top", "keys": "3", "name": "Top view", "code": KEY_3, "ctrl": false, "long": "looks down on the part"},
]

var host              # the EasyPart
var parent: Control   # where the card lives (the Easy Part root)
var card: PanelContainer
var tip_l: Label
var ok_btn: Button
var list_box: PanelContainer
var taught := {}      # id -> true once its card has been shown (or its key pressed first): never taught again
var learned := {}     # id -> true once its key was pressed
var counts := {}      # id -> clicks this session
var shown_id := ""    # the card on screen ("" none)
var open := false     # a card is up (it is only drawn while no shape is being dragged or drawn)
var last_ms := -1     # when the last card was shown
var fake_ms := -1     # a test's own clock (-1 = the real one)
var _path := ""


func setup(h, p: Control) -> void:
	host = h
	parent = p
	card = PanelContainer.new()
	card.name = "easypart_keytip"
	card.add_theme_stylebox_override("panel", host._style(Color(0.1, 0.11, 0.14, 0.96), 10, 8))
	card.visible = false
	card.z_index = 40
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	card.add_child(hb)
	tip_l = Label.new()
	tip_l.name = "easypart_keytip_text"
	tip_l.add_theme_font_size_override("font_size", 15)
	tip_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(tip_l)
	ok_btn = Button.new()
	ok_btn.name = "easypart_keytip_ok"
	ok_btn.text = "Got it"
	ok_btn.focus_mode = Control.FOCUS_NONE
	ok_btn.custom_minimum_size = Vector2(70, 30)
	ok_btn.add_theme_font_size_override("font_size", 14)
	ok_btn.pressed.connect(dismiss)
	hb.add_child(ok_btn)
	parent.add_child(card)
	_sync_path()


func now() -> int:
	return fake_ms if fake_ms >= 0 else Time.get_ticks_msec()


## the settings file the state lives in: main's (a test's own file is the one used, never the user's); read again when it changes
func _sync_path() -> void:
	var p := String(host.m.settings)
	if p == _path:
		return
	_path = p
	taught = {}
	learned = {}
	var cf := ConfigFile.new()
	if cf.load(_path) == OK:
		for id in cf.get_value(SECTION, "taught", PackedStringArray()):
			taught[String(id)] = true
		for id in cf.get_value(SECTION, "learned", PackedStringArray()):
			learned[String(id)] = true


## the state from disk again (a restart): what was taught stays taught, the click counts start over
func reload() -> void:
	_path = ""
	counts = {}
	open = false
	shown_id = ""
	last_ms = -1
	if card != null:
		card.visible = false
	_sync_path()


func _save() -> void:
	var cf := ConfigFile.new()
	cf.load(_path)   # keeps the app's other sections
	cf.set_value(SECTION, "taught", PackedStringArray(taught.keys()))
	cf.set_value(SECTION, "learned", PackedStringArray(learned.keys()))
	cf.save(_path)


## a shape is being dragged or drawn, or the mouse is down on the view: no card now
func busy() -> bool:
	return not host._drag.is_empty() or not host._draft.is_empty() or not host._edge.is_empty() or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


## a click on a button that has a key (the button's own press has already run)
func clicked(id: String) -> void:
	if card == null or not host.active():
		return
	_sync_path()
	if taught.has(id):
		return
	counts[id] = int(counts.get(id, 0)) + 1
	if int(counts[id]) < CLICKS or open or busy():
		return
	if last_ms >= 0 and now() - last_ms < GAP_MS:
		return   # the next card waits: a click after the two minutes shows it
	var at: Variant = spot()
	if at == null:
		return   # no free place for a card: not taught, it comes on a later click
	taught[id] = true
	_save()
	last_ms = now()
	shown_id = id
	open = true
	var e: Dictionary = entry(id)
	tip_l.text = "Tip: %s does %s" % [e["keys"], e["name"]]
	card.visible = true
	card.reset_size()
	parent.move_child(card, -1)   # last in the tree: its Got it takes the click
	place()


func entry(id: String) -> Dictionary:
	for e in LIST:
		if String(e["id"]) == id:
			return e
	return {}


func dismiss() -> void:
	open = false
	shown_id = ""
	if card != null:
		card.visible = false


## every key press goes past here (EasyPart._input): a listed key pressed is learned; its card goes
func key_seen(k: InputEventKey) -> void:
	if card == null or not k.pressed or k.echo or not host.active():
		return
	_sync_path()
	for e in LIST:
		if int(e["code"]) == int(k.keycode) and bool(e["ctrl"]) == k.ctrl_pressed and not k.alt_pressed and (k.ctrl_pressed or not k.shift_pressed):
			var id := String(e["id"])
			if not learned.has(id) or not taught.has(id):
				learned[id] = true
				taught[id] = true
				_save()
			counts[id] = 0
			if shown_id == id:
				dismiss()
			return


## the Easy screen went away or came back: a card only shows while the screen does
func on_visible(on: bool) -> void:
	if card != null and not on:
		card.visible = false
	elif card != null and on:
		place()


## the card's place, called with every layout: bottom-left, above the one sentence at the bottom, off every visible control and the part
func place() -> void:
	if card == null:
		return
	var want: bool = open and bool(host.active()) and not busy()
	if not want:
		card.visible = false
		return
	var at: Variant = spot()
	if at == null:
		card.visible = false
		return
	card.visible = true
	card.reset_size()
	card.position = at


func obstacles() -> Array:
	var out := []
	var vp: Rect2 = host.get_viewport().get_visible_rect()
	for c in parent.get_children():
		if not (c is Control) or c == card or not (c as Control).visible:
			continue
		var r := (c as Control).get_global_rect()
		if r.size.x * r.size.y > vp.size.x * vp.size.y * 0.4 or r.size.x < 1.0:
			continue   # the full-window layers (the dots) are not controls the card can sit on
		out.append(r)
	var part := part_rect()
	if part.size != Vector2.ZERO:
		out.append(part)
	return out


## the part on the screen (its box's corners through the camera), a little wider
func part_rect() -> Rect2:
	var cam: Camera3D = host.m.cam
	var res: Dictionary = host.pu.res
	if cam == null or res.is_empty():
		return Rect2()
	var bb: AABB = res.get("aabb", AABB())
	if bb.size.length() < 1e-4:
		return Rect2()
	var r := Rect2()
	var first := true
	for i in 8:
		var q := bb.get_endpoint(i)
		if cam.is_position_behind(q):
			return Rect2()
		var sp := cam.unproject_position(q)
		r = Rect2(sp, Vector2.ZERO) if first else r.expand(sp)
		first = false
	return r.grow(8.0)


## the first free place for the card, from the bottom-left corner up and then right; null when none is free
func spot() -> Variant:
	card.reset_size()
	var sz := card.get_combined_minimum_size()
	var vp: Rect2 = host.get_viewport().get_visible_rect()
	var cl: Rect2 = host._cl if host._cl.size.x > 0.0 else vp
	var obs := obstacles()
	var bottom: float = host.status.get_global_rect().position.y - 6.0 if host.status.visible else cl.end.y - 40.0
	var x0 := cl.position.x + 12.0
	var y := bottom - sz.y
	var top := cl.position.y + 90.0
	while y >= top:
		var x := x0
		while x + sz.x <= vp.end.x - 8.0:
			var r := Rect2(Vector2(x, y), sz)
			var hit := false
			for o in obs:
				if (o as Rect2).intersects(r):
					hit = true
					x = maxf(x + 8.0, (o as Rect2).end.x + 4.0)   # skip past what is in the way
					break
			if not hit:
				return Vector2(x, y)
		y -= 8.0
	return null


# ---------------------------------------------------------------- the list of every key

func list_build() -> void:
	if list_box != null:
		return
	list_box = PanelContainer.new()
	list_box.name = "easypart_keys_list"
	list_box.add_theme_stylebox_override("panel", host._style(Color(0.1, 0.11, 0.14, 0.97), 10, 12))
	list_box.visible = false
	list_box.z_index = 70
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	list_box.add_child(vb)
	var cap := Label.new()
	cap.text = "Shortcuts"
	cap.add_theme_font_size_override("font_size", 18)
	vb.add_child(cap)
	var g := GridContainer.new()
	g.name = "easypart_keys_grid"
	g.columns = 3
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 3)
	vb.add_child(g)
	for e in LIST:
		var kl := Label.new()
		kl.name = "key_" + String(e["id"])
		kl.text = String(e["keys"])
		kl.add_theme_font_size_override("font_size", 15)
		kl.add_theme_color_override("font_color", Color(0.55, 0.78, 1.0))
		kl.custom_minimum_size.x = 70.0
		g.add_child(kl)
		var nl := Label.new()
		nl.text = "%s: %s" % [e["name"], e["long"]]
		nl.add_theme_font_size_override("font_size", 15)
		g.add_child(nl)
		var tl := Label.new()
		tl.name = "tick_" + String(e["id"])
		tl.add_theme_font_size_override("font_size", 14)
		g.add_child(tl)
	var close := Button.new()
	close.name = "easypart_keys_close"
	close.text = "Close"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(0, 32)
	close.pressed.connect(func(): list_box.visible = false)
	vb.add_child(close)
	parent.add_child(list_box)


func list_toggle() -> void:
	list_build()
	_sync_path()
	list_box.visible = not list_box.visible
	if not list_box.visible:
		return
	for e in LIST:
		var tl := list_box.find_child("tick_" + String(e["id"]), true, false) as Label
		if tl != null:
			tl.text = "learned" if learned.has(String(e["id"])) else ""
	parent.move_child(list_box, -1)
	list_box.reset_size()
	var vp: Rect2 = host.get_viewport().get_visible_rect()
	var cl: Rect2 = host._cl if host._cl.size.x > 0.0 else vp
	list_box.position = Vector2(cl.position.x + 40.0, cl.position.y + 100.0)
