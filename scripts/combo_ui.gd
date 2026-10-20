## MY COMBOS panel (ROADMAP I23; the mining: scripts/combo_mine.gd). Kept out of main.gd like StyleUI.
##   "My combos" lists the card sequences found repeated in Nick's own clips, each named in plain words with its rhythm and how often.
##   Click "Insert after card N" on one: a blue ghost shows the combo's last strike on the card picked on the timeline (nothing is written);
##   Enter writes the cards (his own poses, his mean move and hold; mirrored when the picked card is on the other side) as ONE undo step,
##   Esc or picking another card drops the ghost.
class_name ComboUI
extends RefCounted

var m: Node
var data: Dictionary = {}                # ComboMine.mined's result ({} = not read yet)
var cache := ComboMine.CACHE             # a test points this at its own file under user://
var dirs: Array = ["res://scenes/"]      # read-only
var pv: Scene = null                     # the scene with the combo inserted (the ghost)
var pv_t := 0.0
var pv_k := -1                           # the combo previewed
var pv_after := -1
var pv_cards: Array = []
var pv_n := 0


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("My combos", "", show, "my combos repeat sequence jab cross hook wind-up strike recover phrase insert ghost mined clips",
		false, "the card sequences you repeat in your own clips, named with your rhythm; click one to see it as a ghost after the picked card, Enter inserts it (one undo step)")


func halt() -> void:
	pv = null


func ensure(force := false) -> Dictionary:
	if force or data.is_empty():
		if force and FileAccess.file_exists(cache):
			DirAccess.remove_absolute(cache)
		var keep: Dictionary = m.B.state()   # mining poses the body at other times: put it back EXACTLY (a re-pose differs from the live body)
		data = ComboMine.mined(dirs, m.B, cache)
		m.B.set_state(keep)
	return data


func show() -> void:
	ensure()
	_panel()


func _panel() -> void:
	var L: VBoxContainer = m.ui_find_list
	for c in L.get_children():
		L.remove_child(c)
		c.queue_free()
	var combos: Array = data.get("combos", [])
	var head := HBoxContainer.new()
	L.add_child(head)
	var title: Label = m._label("MY COMBOS  -  %d found in %d of your clips" % [combos.size(), int(data.get("clips", 0))], 14, "heading" if not combos.is_empty() else "warn", true)
	title.name = "combo_title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var rb: Button = m._button("Mine again", func(): ensure(true); _panel(), "read your clips again (the result is kept until a clip changes)")
	rb.name = "combo_again"
	head.add_child(rb)
	head.add_child(m._button("Close", m._close_findings))
	L.add_child(m._label("Sequences you use twice or more in scenes/ (never changed). Pick a card on the timeline, click Insert: a ghost shows it, Enter writes it (Ctrl+Z undoes).", 13, "text:0.6", true))
	var rows := 0
	for i in combos.size():
		var c: Dictionary = combos[i]
		var r := HBoxContainer.new()
		var t: Label = m._label(String(c["text"]), 13, "text:0.85", true)
		t.name = "combo_row_%d" % i
		t.custom_minimum_size = Vector2(300, 0)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(t)
		var b: Button = m._button("Insert", pick.bind(i), "show it as a ghost after the picked card; Enter writes it")
		b.name = "combo_pick_%d" % i
		b.focus_mode = Control.FOCUS_NONE   # so Enter reaches the app, not the button
		r.add_child(b)
		L.add_child(r)
		rows += 1
	if combos.is_empty():
		L.add_child(m._label("No sequence repeats yet (a combo needs 2 or more cards, used twice or more). Save more clips, then Mine again.", 13, "warn", true))
	(m.ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(440, clampf(170.0 + 40.0 * rows, 230.0,
		minf(520.0, m.get_viewport().get_visible_rect().size.y - m.bottom_h - 82 - (m.TOP_H + 12) - 26)))
	m.ui_find.visible = true
	m._say("my combos: %d found%s; pick a card, then Insert" % [combos.size(), " (kept from last time)" if bool(data.get("cached", false)) else ""])


## preview combo i after the picked card
func pick(i: int) -> void:
	var combos: Array = data.get("combos", [])
	if i < 0 or i >= combos.size():
		return
	if m.S.cards.is_empty() or m.sel_card < 0:
		m._say("pick a card first: click one on the timeline, the combo goes after it")
		return
	var c: Dictionary = combos[i]
	var after: int = m.sel_card
	var cards := ComboMine.cards_for(c, ComboMine.side_of(m.S, m.B, after))
	m._ps().apply(m.B, m.playhead)
	if cards.is_empty():
		m._say("that combo's clip changed: press Mine again, then pick it")
		return
	pv = ComboMine.with_inserted(m.S, after, cards)
	pv_cards = cards
	pv_k = i
	pv_after = after
	pv_n = m.S.cards.size()
	var ts := pv.times()
	var at := after + 1 + (int(c["strikes"][0]) if not (c["strikes"] as Array).is_empty() else cards.size() - 1)   # the first strike of the combo
	pv_t = float(ts[at][1])
	m.playhead = float(m.S.times()[after][1])
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	m._say("PREVIEW (blue ghost): %s, after card %d.  Enter inserts it (Ctrl+Z undoes), Esc drops it" % [c["text"], after + 1])


## Enter writes the previewed combo: ONE undo step
func commit() -> bool:
	if pv == null:
		return false
	var cards := pv_cards
	var after := pv_after
	var name: String = (data["combos"][pv_k] as Dictionary)["name"]
	pv = null
	m._step_hint = "My combo: " + name
	m._push_undo()
	ComboMine.insert(m.S, after, cards)
	m.sel_card = after + cards.size()
	m.sel_end = -1
	m.playhead = m.S.times()[m.sel_card][1]
	m._rebuild_cards()
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	m._say("inserted %s: %d cards after card %d, your poses and timing.  Ctrl+Z takes them back" % [name, cards.size(), after + 1])
	return true


func key(k: InputEventKey) -> bool:
	if pv == null or k.echo or k.ctrl_pressed or k.alt_pressed or k.shift_pressed:
		return false
	if k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
		return commit()
	if k.keycode == KEY_ESCAPE:
		pv = null
		m._refresh()
		m._say("combo preview dropped")
		return true
	return false


## the preview is dropped when the picked card or the cards change under it
func tick(_dt: float) -> void:
	if pv != null and (m.sel_card != pv_after or m.S.cards.size() != pv_n):
		pv = null
		m._refresh()
