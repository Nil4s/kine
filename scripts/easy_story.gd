class_name EasyStory
extends RefCounted
## p199storymode (Friday plan 199, Story mode): Kine's own loop build -> act -> film, one guided card for a beginner.
## Easy's More menu has "Make a story": a card with three steps, each one button that runs the app's own action:
##   1 Build a prop      Open BUILD: draw a shape on the grid and pull it up (Easy Part, the page does the work)
##   2 Give it to the fighter   the part he holds in his hand (give_part_weapon: one undo step; with no solid it names the next step)
##   3 Film it           Save video: the playblast of the clips he has (EasyHome.save_video names the next step with no clip)
## Each step's word reads To do or Done from the built state: a solid body on the part, the part in his hand, a saved video.
## The card's last line names the next step. Nothing here changes the scene by itself: every press is one action.
## Closing the card keeps the work. Icons: none (the three words are the labels).

const STEPS := [
	["Build a prop", "Open BUILD", "Open the build page: draw a shape on the grid and pull it up into one solid part"],
	["Give it to the fighter", "Give it", "He holds the part you built, with its size and weight (one undo step)"],
	["Film it", "Save video", "Save a video of the clips he has, in your Videos folder (Kine)"],
]
const NEXT_WORDS := [
	"Next: draw a shape and pull it up (press Open BUILD).",
	"Next: press Give it to give him the part.",
	"Next: press Save video. He needs a move first: click Walk on the start panel.",
]
const ALL_DONE := "All three are done: your video is in Videos/Kine."

var m: Node
var easy: Node
var card: PanelContainer
var _words: Array = []    # the three status Labels (To do / Done)
var _next: Label


## the card, added last to the Easy root (over the view, hidden until its More entry is picked)
func build(root: Control, e: Node) -> void:
	easy = e
	m = e.m
	card = PanelContainer.new()
	card.name = "easy_story"
	card.visible = false
	card.z_index = 20
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Tok.c("panel")
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(14)
	card.add_theme_stylebox_override("panel", sb)
	root.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	card.add_child(v)
	var t := Label.new()
	t.text = "Make a story: build a prop, give it to the fighter, film a scene"
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(460, 0)
	t.add_theme_font_size_override("font_size", 17)
	v.add_child(t)
	for i in STEPS.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		v.add_child(row)
		var w := Label.new()
		w.name = "story_status_%d" % (i + 1)
		w.custom_minimum_size = Vector2(64, 0)
		w.add_theme_font_size_override("font_size", 15)
		row.add_child(w)
		_words.append(w)
		var nm := Label.new()
		nm.text = "%d. %s" % [i + 1, String(STEPS[i][0])]
		nm.custom_minimum_size = Vector2(200, 0)
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nm.tooltip_text = String(STEPS[i][2])
		nm.add_theme_font_size_override("font_size", 15)
		row.add_child(nm)
		var b := Button.new()
		b.name = "story_step_%d" % (i + 1)
		b.text = String(STEPS[i][1])
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(150, 40)
		b.tooltip_text = String(STEPS[i][2])
		b.pressed.connect(_press.bind(i))
		row.add_child(b)
	_next = Label.new()
	_next.name = "story_next"
	_next.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_next.custom_minimum_size = Vector2(460, 0)
	_next.add_theme_font_size_override("font_size", 15)
	v.add_child(_next)
	var close := Button.new()
	close.name = "story_close"
	close.text = "Close"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(110, 36)
	close.tooltip_text = "close the card: the work stays"
	close.pressed.connect(func(): card.visible = false)
	v.add_child(close)


## More > Make a story: the card, its words read from the built state now
func show_card() -> void:
	refresh()
	card.get_parent().move_child(card, -1)   # over the panels added after it (the clip's save strip took the clicks of the card's buttons)
	var vw: Vector2 = easy.get_viewport().get_visible_rect().size
	card.position = Vector2(maxf(8.0, (vw.x - 500.0) * 0.5), 110.0)
	card.visible = true


## the three words and the next line, from the built state (no step is kept in this card)
func refresh() -> void:
	var done := [_built(), _given(), _filmed()]
	var left := ""
	for i in STEPS.size():
		var d: bool = done[i]
		(_words[i] as Label).text = "Done" if d else "To do"
		(_words[i] as Label).add_theme_color_override("font_color", Tok.c("accent") if d else Tok.c("text"))
		if not d and left == "":
			left = NEXT_WORDS[i]
	_next.text = ALL_DONE if left == "" else left
	_next.add_theme_color_override("font_color", Tok.c("text"))


## step 1: a solid body on the part being edited (the same count the BUILD page shows)
func _built() -> bool:
	if m.bld == null or m.bld.part == null:
		return false
	return int(m.bld.part.res.get("bodies", 0)) >= 1


## step 2: he holds a part (the Give action set his weapon to one)
func _given() -> bool:
	return PartWeapon.is_part(String(m.B.wep_kind))


## step 3: a video was saved this session
func _filmed() -> bool:
	return not easy.home.last_video.is_empty()


func _press(i: int) -> void:
	match i:
		0:
			_open_build()
		1:
			m._step_hint = "Give it to the fighter"
			m.give_part_weapon(m.S.part)   # one undo step; with no solid part the app says what to draw first
		2:
			easy.home.save_video()   # names the next step itself when there is no clip
	refresh()


## step 1: BUILD is the page of a 3D building project only (main.gd _page_set), so an animation scene starts one the way the
## start screen's building card does (_start_kind): a new scene, the blank part open on BUILD. Unsaved work is asked about first
## (Save / Don't save / Cancel), as the start screen does (_unsaved, not _clean != _doc_key: that key always differs from "[]").
func _open_build() -> void:
	if m.S.kind != "building" and m._unsaved():
		card.visible = false
		m._ask_save(m._scene_label(), _build_now)
		return
	_build_now()


func _build_now() -> void:
	if m.S.kind != "building":
		m._new_scene()
		m.S.kind = "building"
	card.visible = false
	m._page_set("BUILD")
	m.bld.reset_view()
	m.bld.part.open_blank(easy.on)
	m._refresh()
