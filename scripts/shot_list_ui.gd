## SHOT LIST panel (Friday plan 150; the words and the cards: scripts/shot_list.gd). Kept out of main.gd: main makes one (main.sl_ui)
## and lists its command. "Shot list" opens a box where the story is typed, one line or sentence per shot. "Make the cards" reads
## it and shows one card per shot (its camera and its move). Nothing is written until "Keep all" (one undo step, Ctrl+Z).
class_name ShotListUI
extends RefCounted

var m: Node
var cards: Array = []
var panel: PanelContainer
var story: TextEdit
var card_box: VBoxContainer


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Shot list", "", show, "shot list story type a short story camera shot cards close-up wide low angle move walk strike cards per shot",
		false, "type a short story, one line or sentence per shot: Kine makes a card per shot with its camera and its move; nothing is written until Keep all")


func show() -> void:
	_build()
	panel.visible = true
	_place_panel.call_deferred()
	m._say("Shot list: type the story, one line per shot (e.g. 'Wide: hero walks in. Close-up: hero raises a fist.'), then Make the cards")


func hide() -> void:
	if panel != null and is_instance_valid(panel):
		panel.visible = false


func _build() -> void:
	if panel != null and is_instance_valid(panel):
		panel.queue_free()
	panel = PanelContainer.new()
	panel.name = "shotlist_panel"
	var st := StyleBoxFlat.new()
	st.bg_color = Tok.c("float")
	st.set_corner_radius_all(8)
	st.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", st)
	m.ui_root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title: Label = m._label("SHOT LIST: type the story, one line per shot", 14, "warn")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(m._button("Close", hide, "close the box; the scene is untouched"))
	story = TextEdit.new()
	story.name = "sl_story"
	story.custom_minimum_size = Vector2(420, 90)
	story.placeholder_text = "Wide: hero walks in. Close-up: hero raises a fist. Low angle: hero strikes."
	box.add_child(story)
	var make: Button = m._button("Make the cards", make_cards, "read the story: one card per line, with its camera (size, lens, low or high angle) and its move; nothing is written yet")
	make.name = "sl_make"
	box.add_child(make)
	card_box = VBoxContainer.new()
	card_box.name = "sl_cards"
	card_box.add_theme_constant_override("separation", 2)
	box.add_child(card_box)
	var keep: Button = m._button("Keep all", keep_all, "write every card as a shot of the scene, in order, two seconds apart; one undo step")
	keep.name = "sl_keep"
	box.add_child(keep)


func _place_panel() -> void:
	if panel == null or not is_instance_valid(panel):
		return
	var fr: Rect2 = m._shot_free()
	var sz := panel.get_combined_minimum_size()
	panel.size = sz
	panel.position = Vector2(fr.position.x + (fr.size.x - sz.x) * 0.5, fr.position.y + fr.size.y - sz.y - 4.0)


## the story box -> cards on the panel (a click; nothing is written)
func make_cards() -> void:
	cards = ShotList.parse(story.text)
	for c in card_box.get_children():
		c.queue_free()
	if cards.is_empty():
		m._say("Shot list: the story box is empty. Type one line per shot, e.g. 'Wide: hero walks in.', then Make the cards")
		return
	for k in cards.size():
		var c: Dictionary = cards[k]
		var l: Label = m._label("%d.  %s  -  %s" % [k + 1, c["label"], c["text"]], 13, "text", true)
		l.name = "sl_card_%d" % (k + 1)
		card_box.add_child(l)
	m._say("Shot list: %d card%s ready. Keep all writes them as shots (Ctrl+Z undoes them in one step)" % [cards.size(), "" if cards.size() == 1 else "s"])


## the cards -> the scene's shot list, one undo step
func keep_all() -> void:
	if cards.is_empty():
		m._say("Shot list: nothing to keep yet: type the story and press Make the cards first")
		return
	var fps: int = m.S.fps
	var trial: Dictionary = ShotList.write(m._shot_shots().duplicate(), cards, fps)   # a dry run: no undo step for a keep that writes nothing
	if int(trial["added"]) == 0:
		m._say("Shot list: nothing written: every card's frame already has a shot (%s). Move or delete those shots, then keep again" % ", ".join(trial["skipped"]))
		return
	var res := {}
	m._step_hint = "Shot list: keep all"
	m._do(func(): res.merge(ShotList.write(m._shot_shots(), cards, fps)))
	var sh: Array = m._shot_shots()
	var msg := "Shot list: %d shot%s written (Ctrl+Z undoes them in one step); the scene has %d shots now" % [int(res["added"]), "" if int(res["added"]) == 1 else "s", sh.size()]
	if not (res["skipped"] as Array).is_empty():
		msg += "; skipped, a shot already starts there: %s. Move or delete that shot, then keep again" % ", ".join(res["skipped"])
	m._say(msg)
