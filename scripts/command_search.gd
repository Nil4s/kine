## S = COMMAND SEARCH (round 7, Fusion 360's "S" box). Type a few letters: the commands whose name has them all show,
## with their shortcut; Enter or a click runs one. Nothing to remember: every tool is one word away.
## The commands are main's own (main._commands()): each runs exactly what its button or key runs.
class_name CommandSearch
extends PanelContainer

signal ran(name: String)
signal running(name: String)   # just before a command runs (main names the undo step after it)

const W := 560
const ROWS := 9
const ROW_H := 33

## SYNONYMS (round 11, #73): the words people type for what the poser calls something else. A typed word matches if it,
## or any word it stands for, is in the command's name / other words. ONE table: add a row, every search knows it
const SYNONYMS := {
	"keyframe": ["card", "clip"], "key": ["card", "clip"], "frame": ["card", "clip"], "pose": ["card", "clip"],
	"flip": ["mirror"], "symmetry": ["mirror"], "rewind": ["undo"], "revert": ["undo"], "back": ["undo"],
	"spin": ["turn", "roll", "swing"], "rotate": ["turn", "swing", "roll"], "twist": ["roll"],
	"delete": ["remove", "erase"], "remove": ["delete"], "duplicate": ["copy"], "clone": ["copy"],
	"camera": ["view"], "zoom": ["view"], "lock": ["plant"], "pin": ["plant"], "stick": ["plant"], "slide": ["plant", "foot"],
	"smooth": ["spline", "ease"], "interpolation": ["ease", "spline"], "curve": ["ease", "spline", "graph"],
	"dark": ["theme", "light"], "theme": ["light"], "colour": ["light"], "color": ["light"],
	"weapon": ["bat", "staff", "sword"], "sword": ["weapon", "bat"], "staff": ["bo"], "hammer": ["weapon"], "inbetween": ["tween"], "export": ["save"],
	"render": ["shot"], "screenshot": ["shot"], "ik": ["elbow", "knee", "pull"], "pole": ["elbow", "knee"],
}
const RECENT_N := 5
## words to a pose (round 13, #93): a search that reads as a pose ("raise the right arm 90") offers it first; main sets this
var pose_by_words: Callable
var recent: Array = []   # names of the last commands run, newest first (shown on top of the empty search, #74)

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


## every word typed must be in the name (or its other words); a hit at the start of a word ranks higher. A word that
## is not there may still match through a SYNONYM (2) or as a one-letter typo of a whole word of 4+ letters (1)
func score(c: Dictionary, q: String) -> int:
	var hay := (String(c["name"]) + " " + String(c.get("also", ""))).to_lower()
	var s := 0
	for w in q.to_lower().split(" ", false):
		var at := hay.find(w)
		if at >= 0:
			s += 3 if at == 0 or hay[at - 1] in " (/-" else 1
			continue
		var by := 0
		for syn in SYNONYMS.get(w, []):
			if hay.find(syn) >= 0:
				by = 2
				break
		if by == 0 and w.length() >= 4:
			for word in hay.replace("(", " ").replace(")", " ").replace("/", " ").split(" ", false):
				if typo1(w, word) or (word.length() > w.length() and typo1(w, word.left(w.length()))):
					by = 1
					break
		if by == 0:
			return -1
		s += by
	return s


## a and b one edit apart: one letter changed, added, dropped, or two neighbours swapped
static func typo1(a: String, b: String) -> bool:
	if a == b or absi(a.length() - b.length()) > 1:
		return false
	if a.length() == b.length():
		var diff := []
		for i in a.length():
			if a[i] != b[i]:
				diff.append(i)
		return diff.size() == 1 or (diff.size() == 2 and diff[1] == diff[0] + 1 and a[diff[0]] == b[diff[1]] and a[diff[1]] == b[diff[0]])
	var lo := a if a.length() < b.length() else b
	var hi := b if lo == a else a
	for i in hi.length():
		if hi.left(i) + hi.substr(i + 1) == lo:
			return true
	return false


func _filter() -> void:
	var q := box.text.strip_edges()
	shown = []
	for c in commands:
		if q == "" or score(c, q) >= 0:
			shown.append(c)
	if q == "":   # the empty search: the recent ones first (#74)
		var top := []
		for n in recent:
			for c in shown:
				if c["name"] == n:
					top.append(c)
		shown = top + shown.filter(func(c): return not c["name"] in recent)
	if q != "":
		# better hits first; a tie keeps the list's own order (sort_custom is not stable, so the order is the tiebreak)
		var at := {}
		for i in commands.size():
			at[commands[i]["name"]] = i
		shown.sort_custom(func(a, b):
			var sa := score(a, q)
			var sb := score(b, q)
			return sa > sb or (sa == sb and at[a["name"]] < at[b["name"]]))
	if q != "" and pose_by_words.is_valid() and PoseWords.parse(q)["ok"]:
		shown.push_front({"name": "Pose: " + q, "keys": "words", "words": true, "run": pose_by_words.bind(q),
			"desc": "turn the joints as the words say (scripts/pose_words.gd): one undo step"})
	list.clear()
	var root := list.create_item()
	for c in shown:
		var it := list.create_item(root)
		it.set_text(0, c["name"])
		it.set_text(1, ("recent   " if q == "" and c["name"] in recent else "") + c.get("keys", ""))
		it.set_custom_color(1, Tok.c("heading"))
		it.set_tooltip_text(0, c.get("desc", ""))   # the registry's one-line "what it does" (round 8)
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
	if not c.get("words", false):   # a typed pose is not a command to list again
		recent.erase(c["name"])
		recent.push_front(c["name"])
		recent = recent.slice(0, RECENT_N)
	close()
	running.emit(c["name"])
	(c["run"] as Callable).call()
	ran.emit(c["name"])
