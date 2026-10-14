## S = COMMAND SEARCH (round 7, Fusion 360's "S" box). Type a few letters: the commands whose name has them all show,
## with their shortcut; Enter or a click runs one. Nothing to remember: every tool is one word away.
## The commands are main's own (main._commands()): each runs exactly what its button or key runs.
class_name CommandSearch
extends PanelContainer

signal ran(name: String)

const W := 560
const ROWS := 9
const ROW_H := 33

## each: {"name": String, "keys": String, "run": Callable, "also": String (extra words it answers to)}
var commands: Array = []
var box: LineEdit
var list: Tree
var shown: Array = []   # the commands in the list now, in order


func _ready() -> void:
	visible = false
	anchor_left = 0.5
	anchor_right = 0.5
	offset_left = -W / 2.0
	offset_right = W / 2.0
	var v := VBoxContainer.new()
	add_child(v)
	box = LineEdit.new()
	box.placeholder_text = "type: mirror, trail, check, staff...   Enter runs, Esc closes"
	box.add_theme_font_size_override("font_size", 18)
	box.text_changed.connect(func(_t): _filter())
	box.gui_input.connect(_box_keys)
	v.add_child(box)
	list = Tree.new()
	list.columns = 2
	list.hide_root = true
	list.select_mode = Tree.SELECT_ROW
	list.focus_mode = Control.FOCUS_NONE
	list.set_column_expand(1, false)
	list.set_column_custom_minimum_width(1, 150)
	list.custom_minimum_size = Vector2(W, ROWS * ROW_H)
	list.add_theme_font_size_override("font_size", 16)
	list.item_mouse_selected.connect(func(_p, _b): _run(_row_of(list.get_selected())))
	v.add_child(list)


func open() -> void:
	visible = true
	box.text = ""
	_filter()
	box.grab_focus()


func close() -> void:
	visible = false
	box.release_focus()


## every word typed must be in the name (or its other words); a hit at the start of a word ranks higher
func score(c: Dictionary, q: String) -> int:
	var hay := (String(c["name"]) + " " + String(c.get("also", ""))).to_lower()
	var s := 0
	for w in q.to_lower().split(" ", false):
		var at := hay.find(w)
		if at < 0:
			return -1
		s += 3 if at == 0 or hay[at - 1] in " (/-" else 1
	return s


func _filter() -> void:
	var q := box.text.strip_edges()
	shown = []
	for c in commands:
		if q == "" or score(c, q) >= 0:
			shown.append(c)
	if q != "":
		# better hits first; a tie keeps the list's own order (sort_custom is not stable, so the order is the tiebreak)
		var at := {}
		for i in commands.size():
			at[commands[i]["name"]] = i
		shown.sort_custom(func(a, b):
			var sa := score(a, q)
			var sb := score(b, q)
			return sa > sb or (sa == sb and at[a["name"]] < at[b["name"]]))
	list.clear()
	var root := list.create_item()
	for c in shown:
		var it := list.create_item(root)
		it.set_text(0, c["name"])
		it.set_text(1, c.get("keys", ""))
		it.set_custom_color(1, Color(0.6, 0.78, 1.0))
	if shown.size() > 0:
		root.get_first_child().select(0)
	# only as tall as the hits (an empty list over the body hides the body for nothing)
	list.custom_minimum_size.y = clampi(shown.size(), 1, ROWS) * ROW_H + 6
	list.scroll_vertical_enabled = shown.size() > ROWS
	reset_size()


func _row_of(it: TreeItem) -> int:
	return -1 if it == null else it.get_index()


func _box_keys(ev: InputEvent) -> void:
	if not (ev is InputEventKey and ev.pressed):
		return
	var k := ev as InputEventKey
	var i := _row_of(list.get_selected())
	match k.keycode:
		KEY_ESCAPE:
			close()
		KEY_ENTER, KEY_KP_ENTER:
			_run(maxi(i, 0))
		KEY_DOWN, KEY_UP:
			var n := shown.size()
			if n > 0:
				var j := wrapi(i + (1 if k.keycode == KEY_DOWN else -1), 0, n)
				var it := list.get_root().get_child(j)
				it.select(0)
				list.scroll_to_item(it)
		_:
			return
	box.accept_event()


## close first (the box gives up the keyboard, so a command that reads keys or focus sees the view), then run
func _run(i: int) -> void:
	if i < 0 or i >= shown.size():
		return
	var c: Dictionary = shown[i]
	close()
	(c["run"] as Callable).call()
	ran.emit(c["name"])
