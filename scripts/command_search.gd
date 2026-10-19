## S = COMMAND SEARCH (round 7, Fusion 360's "S" box). Type a few letters: the commands whose name has them all show,
## with their shortcut; Enter or a click runs one. Nothing to remember: every tool is one word away.
## The commands are main's own (main._commands()): each runs exactly what its button or key runs.
## ROADMAP 52: typed words also find the saved poses, scenes and moves (main._search_files), each row with its kind's icon;
## "pose:" / "scene:" / "command:" in front keeps one kind.
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
## ROADMAP 52: the saved files as rows {"name", "kind" ("pose" / "scene"), "also", "desc", "run"}; main's files_provider
## lists them each time the box opens (not per keystroke). KINDS: the words a "kind:" prefix may start with
const KINDS := ["command", "pose", "scene", "macro"]   # ROADMAP 81: "macro:" lists the recorded macros
var files_provider: Callable
var files: Array = []
var box: LineEdit
var list: Tree
var shown: Array = []   # the rows in the list now, in order


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
	files = files_provider.call() if files_provider.is_valid() else []
	_filter()
	box.grab_focus()


## the box opened with text already in it (ROADMAP 81: "Play macro..." opens it on "macro:" to list the macros)
func open_with(text: String) -> void:
	open()
	box.text = text
	box.caret_column = text.length()
	_filter()


func close() -> void:
	visible = false
	box.release_focus()


## every word typed must be in the name (or its other words, the "also" field). A NAME hit always outranks a hit only in
## the other words: name whole word 12 > name SYNONYM 9 (+1 per further synonym) > name word start 8 > name typo 7 >
## name substring 4 > other-words hit (start 3, synonym 2, substring/typo 1). The best source counts for each word
func score(c: Dictionary, q: String) -> int:
	return _score(c, _query_words(q))


func _score(c: Dictionary, qwords: PackedStringArray) -> int:
	if not c.has("_name"):   # read once per row: the lowercase name and other words, and their words (the search runs per keystroke)
		c["_name"] = String(c["name"]).to_lower()
		c["_also"] = String(c.get("also", "")).to_lower()
		c["_name_w"] = _words_of(c["_name"])
		c["_also_w"] = _words_of(c["_also"])
	var name: String = c["_name"]
	var also: String = c["_also"]
	var s := 0
	for w in qwords:
		var best := _word_score(name, c["_name_w"], w, true)
		if best < 12:
			best = maxi(best, _word_score(also, c["_also_w"], w, false))
		if best <= 0:
			return -1
		s += best
	return s


## how well word w matches text (a name or the other words): 0 = not at all. In the name the tiers sit above the other words'
func _word_score(text: String, words: PackedStringArray, w: String, is_name: bool) -> int:
	var best := 0
	var at := text.find(w)
	if at >= 0:
		if w in words:
			best = 12 if is_name else 3
		elif at == 0 or text[at - 1] in " (/-":
			best = 8 if is_name else 3
		else:
			best = 4 if is_name else 1
	var syns := 0
	var syn_of = SYNONYMS.get(w)
	if syn_of != null:
		for syn in syn_of:
			if text.find(syn) >= 0:
				syns += 1
	if syns > 0:
		best = maxi(best, (8 + syns) if is_name else 2)
	if best == 0 and w.length() >= 4:
		for word in words:
			if typo1(w, word) or (word.length() > w.length() and typo1(w, word.left(w.length()))):
				best = 7 if is_name else 1
				break
	return best


## the words a name / other-words text is read as (a bracket, slash, dash, colon or space ends one). Kept on the row
## (score) so each keystroke does not split the names again (ROADMAP 52: the search runs over every item per keystroke)
static func _words_of(text: String) -> PackedStringArray:
	return text.replace("(", " ").replace(")", " ").replace("/", " ").replace("-", " ").replace(":", " ").split(" ", false)


var _q_last := ""
var _q_words := PackedStringArray()


func _query_words(q: String) -> PackedStringArray:
	if q != _q_last:
		_q_last = q
		_q_words = q.to_lower().split(" ", false)
	return _q_words


## a and b one edit apart: one letter changed, added, dropped, or two neighbours swapped
static func typo1(a: String, b: String) -> bool:
	if a == b or absi(a.length() - b.length()) > 1:
		return false
	# (code units, no new strings: this runs for every word of every item on each keystroke)
	if a.length() == b.length():
		var n := 0
		var d0 := -1
		var d1 := -1
		for i in a.length():
			if a.unicode_at(i) != b.unicode_at(i):
				n += 1
				if n == 1:
					d0 = i
				elif n == 2:
					d1 = i
				else:
					return false
		if n == 1:
			return true
		return d1 == d0 + 1 and a.unicode_at(d0) == b.unicode_at(d1) and a.unicode_at(d1) == b.unicode_at(d0)
	# one letter added or dropped: the longer one with one letter taken out is the shorter one
	var lo := a if a.length() < b.length() else b
	var hi := b if lo == a else a
	var i := 0
	var j := 0
	var skipped := false
	while i < hi.length() and j < lo.length():
		if hi.unicode_at(i) == lo.unicode_at(j):
			j += 1
		elif skipped:
			return false
		else:
			skipped = true
		i += 1
	return true


## the box's rows (ROADMAP 52): the commands, then the saved files (poses, scenes, moves: files_provider). A typed
## "pose:" / "scene:" / "command:" in front keeps one kind and the words after it search that kind. The empty search
## lists the commands (recent first, #74); typed words search the commands AND the files
## what the box holds: [kind, words]. "pose: bat" = ["pose", "bat"]; a kind word that is not a kind is just words
static func parse_box(raw_text: String) -> Array:
	var raw := raw_text.strip_edges()
	var colon := raw.find(":")
	if colon > 0 and raw.left(colon).strip_edges().to_lower() in KINDS:
		return [raw.left(colon).strip_edges().to_lower(), raw.substr(colon + 1).strip_edges()]
	return ["", raw]


## the rows that answer a search (no words: every row of the kind, or the commands): better hits first, a tie keeps the
## pool's order (commands, then files). kind "" = any kind; q = the words after the "kind:" prefix. No drawing here
func matches(kind: String, q: String) -> Array:
	var pool: Array = []
	if kind == "" or kind == "command":
		pool.append_array(commands)
	if kind != "command" and (q != "" or kind != ""):
		pool.append_array(files.filter(func(c): return kind == "" or c["kind"] == kind))
	var qwords := _query_words(q)
	var hits := []   # [score, pool index, row]
	for i in pool.size():
		var s := 0
		if q != "":
			s = _score(pool[i], qwords)
			if s < 0:
				continue
		hits.append([s, i, pool[i]])
	if q != "":
		# a tie: the row with a shortcut first (the common action: "flip" wants Shift+M's pose mirror, not the scene mirrors), then pool order
		hits.sort_custom(func(a, b):
			if a[0] != b[0]:
				return a[0] > b[0]
			var ka: bool = String(a[2].get("keys", "")) != ""
			var kb: bool = String(b[2].get("keys", "")) != ""
			if ka != kb:
				return ka
			return a[1] < b[1])
	return hits.map(func(h): return h[2])


func _filter() -> void:
	var typed := parse_box(box.text)
	var kind: String = typed[0]
	var q: String = typed[1]
	shown = matches(kind, q)
	if q == "" and kind == "":   # the empty search: the recent ones first (#74)
		var top := []
		for n in recent:
			for c in shown:
				if c["name"] == n:
					top.append(c)
		shown = top + shown.filter(func(c): return not c["name"] in recent)
	if q != "" and kind == "" and pose_by_words.is_valid() and PoseWords.parse(q)["ok"]:
		shown.push_front({"name": "Pose: " + q, "keys": "words", "words": true, "run": pose_by_words.bind(q),
			"desc": "turn the joints as the words say (scripts/pose_words.gd): one undo step"})
	list.clear()
	var root := list.create_item()
	for c in shown:
		var it := list.create_item(root)
		var k: String = c.get("kind", "command")
		it.set_text(0, c["name"])
		it.set_icon(0, Icons.small("kind_" + k))   # the kind's icon (scripts/icons.gd), tinted like the headings
		it.set_icon_modulate(0, Tok.c("heading"))
		if k == "command":
			it.set_text(1, ("recent   " if q == "" and kind == "" and c["name"] in recent else "") + c.get("keys", ""))
		else:
			it.set_text(1, k)   # a file row's tag: its kind
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
	if c.get("kind", "command") == "command" and not c.get("words", false):   # a typed pose or a file is not a command to list again
		recent.erase(c["name"])
		recent.push_front(c["name"])
		recent = recent.slice(0, RECENT_N)
	close()
	running.emit(c["name"])
	(c["run"] as Callable).call()
	ran.emit(c["name"])
