class_name BuildWordsUI
extends RefCounted
## The WORDS tool of the BUILD page (build_words.png): a box "Say what to build" with a "Build it" button, the chips "Then just say:",
## and the PLAN as numbered cards on the right whose numbers are chips you edit. The sentence is parsed live (BuildWords.parse, no
## network); NOTHING is built until Build it (or Enter). Build it replaces the record with the plan's building: ONE undo step. An edit
## sentence ("move the door to the left") on a building that exists changes the record: ONE undo step each, and the reply says what
## was done. A sentence Kine does not understand is refused plainly (with "Did you mean" when a word looks like a typo); the words it
## ignored are listed in the plan, never silently dropped. The parsing and the building are build_words.gd; this is only the page.

const PLAN_W := 330.0
const AMBER := Color("#ffc233")
const SKY := Color("#73BFFF")
const SAY_CHIPS := ["move the door to the left", "make the second floor taller", "add a garage"]
const HINT := "Say what to build, like: a 2-floor house 8 x 6 m with a door and 4 windows."

var ui: BuildUI
var m: Node
var box: PanelContainer
var edit: LineEdit
var go: Button
var say_row: HBoxContainer
var plan_panel: PanelContainer
var cards_box: VBoxContainer
var title: Label
var foot: Label
var did_btn: Button
var res := {}               # the last parse (live) of the box
var plan := {}              # the plan the cards show and edit (a copy of res["plan"])
var defaults := {}
var parsed_text := "<unparsed>"   # the sentence res / plan came from
var chip_notes := []        # what a chip's number did (rounded, refused): shown in the footer until the next sentence
var _render_queued := false


func setup(owner: BuildUI) -> void:
	ui = owner
	m = owner.m
	box = PanelContainer.new()
	box.name = "build_words_box"
	box.add_theme_stylebox_override("panel", _sb(Color(0.08, 0.09, 0.12, 0.96), AMBER, 2, 12, 10))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	box.add_child(vb)
	var cap := Label.new()
	cap.text = "Say what to build"
	cap.add_theme_font_size_override("font_size", 13)
	cap.modulate = Color(1, 1, 1, 0.6)
	vb.add_child(cap)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	edit = LineEdit.new()
	edit.name = "build_words_edit"
	edit.placeholder_text = "a 2-floor house 8 x 6 m with a door and 4 windows"
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.add_theme_font_size_override("font_size", 22)
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0, 0, 0, 0)
	for st in ["normal", "focus", "read_only"]:
		edit.add_theme_stylebox_override(st, flat)
	edit.text_changed.connect(_typed)
	edit.text_submitted.connect(func(_t): submit())
	hb.add_child(edit)
	go = Button.new()
	go.name = "build_words_go"
	go.text = "Build it"
	go.focus_mode = Control.FOCUS_NONE
	go.custom_minimum_size = Vector2(110, 38)
	go.add_theme_font_size_override("font_size", 18)
	go.add_theme_stylebox_override("normal", _sb(AMBER, AMBER, 0, 10, 6))
	go.add_theme_stylebox_override("hover", _sb(AMBER.lightened(0.15), AMBER, 0, 10, 6))
	go.add_theme_stylebox_override("pressed", _sb(AMBER.darkened(0.15), AMBER, 0, 10, 6))
	go.add_theme_stylebox_override("disabled", _sb(AMBER.darkened(0.5), AMBER, 0, 10, 6))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		go.add_theme_color_override(c, Color(0.08, 0.07, 0.04))
	go.tooltip_text = "builds what the plan says (one undo step); nothing is built until you press this"
	go.pressed.connect(func(): submit())
	hb.add_child(go)
	vb.add_child(hb)
	box.visible = false
	m.ui_root.add_child(box)
	say_row = HBoxContainer.new()
	say_row.name = "build_words_say"
	say_row.add_theme_constant_override("separation", 8)
	var sl := Label.new()
	sl.text = "Then just say:"
	sl.modulate = Color(1, 1, 1, 0.65)
	say_row.add_child(sl)
	for i in SAY_CHIPS.size():
		var cb := Button.new()
		cb.name = "build_words_chip_%d" % i
		cb.text = SAY_CHIPS[i]
		cb.focus_mode = Control.FOCUS_NONE
		cb.add_theme_font_size_override("font_size", 13)
		cb.add_theme_stylebox_override("normal", _sb(Color(0.17, 0.18, 0.23), Color(0, 0, 0, 0), 0, 14, 5))
		cb.add_theme_stylebox_override("hover", _sb(Color(0.24, 0.26, 0.32), Color(0, 0, 0, 0), 0, 14, 5))
		cb.add_theme_stylebox_override("pressed", _sb(Color(0.3, 0.32, 0.4), Color(0, 0, 0, 0), 0, 14, 5))
		cb.tooltip_text = "puts these words in the box; press Build it to do it"
		cb.pressed.connect(_say_chip.bind(SAY_CHIPS[i]))
		say_row.add_child(cb)
	say_row.visible = false
	m.ui_root.add_child(say_row)
	plan_panel = PanelContainer.new()
	plan_panel.name = "build_words_plan"
	plan_panel.custom_minimum_size.x = PLAN_W
	plan_panel.add_theme_stylebox_override("panel", _sb(Color(0.1, 0.11, 0.14, 0.94), Color(0, 0, 0, 0), 0, 10, 10))
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 6)
	plan_panel.add_child(pv)
	var th := HBoxContainer.new()
	title = Label.new()
	title.name = "build_words_title"
	title.add_theme_font_size_override("font_size", 19)
	th.add_child(title)
	var sub := Label.new()
	sub.text = "  tap any card to change it"
	sub.add_theme_font_size_override("font_size", 12)
	sub.modulate = Color(1, 1, 1, 0.55)
	sub.name = "build_words_sub"
	th.add_child(sub)
	pv.add_child(th)
	cards_box = VBoxContainer.new()
	cards_box.name = "build_words_cards"
	cards_box.add_theme_constant_override("separation", 6)
	pv.add_child(cards_box)
	var fp := PanelContainer.new()
	fp.add_theme_stylebox_override("panel", _sb(Color(0.1, 0.11, 0.14, 0.9), Color(1, 1, 1, 0.18), 1, 10, 8))
	foot = Label.new()
	foot.name = "build_words_foot"
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.custom_minimum_size.x = PLAN_W - 44.0
	foot.add_theme_font_size_override("font_size", 13)
	fp.add_child(foot)
	pv.add_child(fp)
	plan_panel.visible = false
	m.ui_root.add_child(plan_panel)
	_render()


static func _sb(bg: Color, line: Color, bw: int, r: int, pad: int, padx := -1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = line
	s.set_border_width_all(bw)
	s.set_corner_radius_all(r)
	s.set_content_margin_all(pad)
	if padx >= 0:
		s.content_margin_left = padx
		s.content_margin_right = padx
	return s


func is_on() -> bool:
	return ui.on and ui.tool == "Words"


func focus() -> void:
	edit.grab_focus()
	edit.caret_column = edit.text.length()


func layout(cl: Rect2) -> void:
	var on: bool = is_on() and m.S.kind == "building"
	box.visible = on
	say_row.visible = on
	plan_panel.visible = on
	if not on:
		return
	var px := cl.end.x - PLAN_W - 8.0
	plan_panel.reset_size()
	plan_panel.position = Vector2(px, cl.position.y + 6.0)
	box.custom_minimum_size.x = clampf(px - cl.position.x - 28.0, 300.0, 760.0)
	box.reset_size()
	box.position = Vector2(cl.position.x + 12.0, cl.position.y + 6.0)
	say_row.reset_size()
	say_row.position = Vector2(cl.position.x + 12.0, box.position.y + box.size.y + 6.0)


# ---------------------------------------------------------------- the sentence

func _typed(t: String) -> void:
	_parse(t, false)
	_render()


func _say_chip(t: String) -> void:
	edit.text = t
	_parse(t, false)
	_render()
	focus()


## the live parse: a plan or an edit shows at once; a refusal waits for Enter / Build it (a half-typed word is not a typo yet)
func _parse(t: String, final: bool) -> void:
	chip_notes = []
	parsed_text = t
	if t.strip_edges() == "":
		res = {}
		plan = {}
		return
	var r := BuildWords.parse(t, ui._bld())
	if not bool(r["ok"]) and not final:
		res = {"ok": false, "kind": "typing"}
		plan = {}
		return
	res = r
	plan = (r["plan"] as Dictionary).duplicate(true) if r.has("plan") else {}
	defaults = r["defaults"]


## Enter / Build it: the plan is built, an edit is done, a refusal is said
func submit() -> void:
	var t := edit.text
	if t.strip_edges() == "":
		res = {}
		plan = {}
		m._say("Words: say what to build first. " + HINT)
		_render()
		return
	if t != parsed_text or String(res.get("kind", "")) == "typing":
		_parse(t, true)
	if not res.has("ok") or not bool(res["ok"]):
		var err := String(res.get("error", ""))
		_render()
		m._say(err)
		return
	if bool(ui._bld().get("readonly", false)):
		m._say("Words: this building was saved by a newer Kine and is read only here")
		return
	if String(res["kind"]) == "edit":
		_do_edit(res["edit"])
	else:
		_do_build()
	_render()


func _do_build() -> void:
	var nm := String(ui._bld().get("name", "")) if not ui._bld().is_empty() else (String(m.S.name) if String(m.S.name) != "" else "Untitled")
	var nb := BuildWords.make_building(plan, nm if nm != "" else "Untitled")
	if not ui._bld().is_empty() and JSON.stringify(Building.to_file(nb)) == JSON.stringify(Building.to_file(ui._bld())):
		m._say("Words: that is built already, nothing changed")
		return
	var sm := BuildWords.summary(plan)
	m._step_hint = "Words: build %s" % sm
	m._push_undo()
	m.S.building = nb
	ui.sync()
	ui._frame_house()
	var said := "Built: %s. Every part is editable." % sm
	if not (res["ignored"] as Array).is_empty():
		said += " Left out (not understood): %s." % ", ".join(res["ignored"])
	m._say(said)
	m._toast(said)


func _do_edit(e: Dictionary) -> void:
	var trial: Dictionary = (ui._bld() as Dictionary).duplicate(true)
	var r := BuildWords.apply_edit(trial, e)
	if not bool(r["ok"]):
		res = {"ok": false, "kind": "refuse", "error": String(r["error"]), "did": "", "ignored": [], "notes": [], "defaults": {}}
		m._say(String(r["error"]))
		return
	m._step_hint = "Words: %s" % BuildWords.describe_edit(e)
	m._push_undo()
	BuildWords.apply_edit(ui._bld(), e)
	edit.text = ""
	parsed_text = ""
	res = {"ok": true, "kind": "done", "say": String(r["say"])}
	plan = {}
	ui.sync()
	m._say(String(r["say"]))
	m._toast(String(r["say"]))


# ---------------------------------------------------------------- the cards

func _queue_render() -> void:
	if not _render_queued:
		_render_queued = true
		_render.call_deferred()


func _render() -> void:
	_render_queued = false
	for c in cards_box.get_children():
		cards_box.remove_child(c)
		c.queue_free()
	did_btn = null
	var kind := String(res.get("kind", ""))
	var lines := []
	if kind == "plan" and not plan.is_empty():
		title.text = "Here is the plan"
		for c in BuildWords.cards(plan, defaults):
			cards_box.add_child(_card(c))
		lines.append("Nothing is built until you press Build it.")
		for n in res.get("notes", []):
			lines.append(String(n))
		lines.append_array(chip_notes)
		if not ui._bld().is_empty() and not ui._bld().get("rooms", []).is_empty():
			if _is_built():
				lines.append("This is the building now. Change a card and press Build it again.")
			else:
				lines.append("This replaces the building you have (Undo brings it back).")
	elif kind == "edit":
		title.text = "Here is the change"
		cards_box.add_child(_text_card("1", "Change", BuildWords.describe_edit(res["edit"]), ""))
		lines.append("Nothing changes until you press Build it. One undo step.")
		if not (res.get("ignored", []) as Array).is_empty():
			lines.append("Not understood, left out: %s." % ", ".join(res["ignored"]))
	elif kind == "done":
		title.text = "Done"
		cards_box.add_child(_text_card("✓", "Changed", String(res["say"]), ""))
		lines.append("Say another change, or Undo to take it back.")
	elif kind == "refuse" or (kind == "" and false):
		title.text = "Not understood"
		cards_box.add_child(_text_card("!", "Kine can't build that", String(res["error"]), ""))
		if String(res.get("did", "")) != "":
			did_btn = Button.new()
			did_btn.name = "build_words_did"
			did_btn.text = "Did you mean: %s?" % res["did"]
			did_btn.focus_mode = Control.FOCUS_NONE
			did_btn.add_theme_stylebox_override("normal", _sb(Color(0.17, 0.18, 0.23), AMBER, 1, 10, 6))
			did_btn.pressed.connect(_did_pressed)
			cards_box.add_child(did_btn)
		lines.append("Nothing was built or changed.")
	else:
		title.text = "Here is the plan"
		cards_box.add_child(_text_card("1", "Say it", HINT, ""))
		lines.append("The plan shows here as you type. Nothing is built until you press Build it.")
	foot.text = "\n".join(lines)
	plan_panel.reset_size()
	_toast_clear_of_plan()


## the plan just changed its height (its size is known two frames later): the toast keeps clear of it
func _toast_clear_of_plan() -> void:
	for i in 2:
		await m.get_tree().process_frame
	if m.ui_toast != null and is_instance_valid(m.ui_toast) and m.ui_toast.visible and plan_panel.visible:
		ui.place_toast(m.ui_toast)


## the plan is exactly what stands in the record
func _is_built() -> bool:
	var nb := BuildWords.make_building(plan, String(ui._bld().get("name", "Untitled")))
	return JSON.stringify(Building.to_file(nb)) == JSON.stringify(Building.to_file(ui._bld()))


func _did_pressed() -> void:
	var word := String(res.get("word", ""))
	var did := String(res.get("did", ""))
	if word != "" and did != "":
		edit.text = " ".join(Array(edit.text.split(" ", false)).map(func(w): return did if String(w).strip_edges().to_lower().trim_suffix(",") == word else w))
	_parse(edit.text, false)
	_render()
	focus()


func _badge(txt: String) -> PanelContainer:
	var b := PanelContainer.new()
	b.add_theme_stylebox_override("panel", _sb(AMBER, AMBER, 0, 14, 2))
	var l := Label.new()
	l.text = txt
	l.add_theme_color_override("font_color", Color(0.08, 0.07, 0.04))
	l.add_theme_font_size_override("font_size", 14)
	l.custom_minimum_size = Vector2(20, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_child(l)
	return b


func _tag(txt: String) -> PanelContainer:
	var b := PanelContainer.new()
	b.add_theme_stylebox_override("panel", _sb(Color(0, 0, 0, 0), AMBER, 1, 10, 2, 8))
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", AMBER)
	b.add_child(l)
	return b


func _text_card(badge: String, ttl: String, body: String, tag: String) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.name = "build_words_card_text"
	pc.add_theme_stylebox_override("panel", _sb(Color(0.15, 0.16, 0.2), Color(0, 0, 0, 0), 0, 10, 8))
	var v := VBoxContainer.new()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.add_child(_badge(badge))
	var t := Label.new()
	t.text = ttl
	t.add_theme_font_size_override("font_size", 16)
	h.add_child(t)
	v.add_child(h)
	var l := Label.new()
	l.name = "build_words_card_body"
	l.text = body
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = PLAN_W - 52.0
	l.add_theme_font_size_override("font_size", 14)
	v.add_child(l)
	pc.add_child(v)
	return pc


func _card(c: Dictionary) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.name = "build_words_card_%d" % int(c["n"])
	pc.add_theme_stylebox_override("panel", _sb(Color(0.15, 0.16, 0.2), Color(0, 0, 0, 0), 0, 10, 8))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.add_child(_badge(str(int(c["n"]))))
	var t := Label.new()
	t.text = String(c["title"])
	t.add_theme_font_size_override("font_size", 16)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	if String(c["tag"]) != "":
		var tg := _tag(String(c["tag"]))
		tg.name = "build_words_tag_%d" % int(c["n"])
		h.add_child(tg)
	v.add_child(h)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 4)
	for ch in c["chips"]:
		row.add_child(_chip(ch))
	if String(c.get("tail", "")) != "":
		var tl := Label.new()
		tl.text = String(c["tail"])
		tl.modulate = Color(1, 1, 1, 0.65)
		tl.add_theme_font_size_override("font_size", 14)
		row.add_child(tl)
	v.add_child(row)
	pc.add_child(v)
	return pc


func _chip(ch: Dictionary) -> Control:
	var kind := String(ch["kind"])
	if kind == "text":
		var l := Label.new()
		l.text = String(ch["text"])
		l.modulate = Color(1, 1, 1, 0.65)
		l.add_theme_font_size_override("font_size", 14)
		return l
	if kind == "cycle":
		var b := Button.new()
		b.name = "build_words_cycle_" + String(ch["key"])
		b.text = String(ch["text"])
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 14)
		b.add_theme_color_override("font_color", SKY)
		b.add_theme_stylebox_override("normal", _sb(Color(0.08, 0.1, 0.15), SKY, 2, 8, 4, 9))
		b.add_theme_stylebox_override("hover", _sb(Color(0.12, 0.16, 0.24), SKY, 2, 8, 4, 9))
		b.add_theme_stylebox_override("pressed", _sb(Color(0.16, 0.22, 0.32), SKY, 2, 8, 4, 9))
		b.tooltip_text = "click for the next choice"
		b.pressed.connect(_cycle.bind(String(ch["key"])))
		return b
	var le := LineEdit.new()
	le.name = "build_words_chip_" + String(ch["key"])
	le.text = String(ch["text"])
	le.alignment = HORIZONTAL_ALIGNMENT_CENTER
	le.custom_minimum_size = Vector2(maxf(48.0, 10.0 * String(ch["text"]).length() + 30.0), 0)
	le.add_theme_font_size_override("font_size", 14)
	le.add_theme_color_override("font_color", SKY)
	for st in ["normal", "focus", "read_only"]:
		le.add_theme_stylebox_override(st, _sb(Color(0.08, 0.1, 0.15), SKY if st != "focus" else Color.WHITE, 2, 8, 3))
	le.tooltip_text = "type a number and press Enter"
	le.select_all_on_focus = true
	le.text_submitted.connect(func(t): _chip_done(le, String(ch["key"]), t))
	le.focus_exited.connect(func(): _chip_done(le, String(ch["key"]), le.text))
	return le


func _cycle(key: String) -> void:
	BuildWords.cycle(plan, key)
	chip_notes = []
	_queue_render()


func _chip_done(le: LineEdit, key: String, t: String) -> void:
	if not is_instance_valid(le) or not le.is_inside_tree() or plan.is_empty():
		return
	var s := t.strip_edges().to_lower().replace(",", ".")
	for suf in ["metres", "meters", "m"]:
		s = s.trim_suffix(suf).strip_edges()
	var old: float = _value_of(key)
	if not s.is_valid_float():
		le.text = _fmt(key, old)
		return
	var v := float(s)
	if absf(v - old) < 0.0001:
		le.text = _fmt(key, old)
		return
	var err := BuildWords.set_chip(plan, key, v)
	chip_notes = []
	if err != "":
		chip_notes.append(err)
		m._say("Plan: " + err)
	elif key in ["w", "d", "garage_w"] and absf(float(plan[key]) - v) > 0.001:
		chip_notes.append("Sizes round to the %.1f m grid (%s became %s)." % [BuildWords.GRID, BuildWords._n(v), BuildWords._n(float(plan[key]))])
	_queue_render()


func _value_of(key: String) -> float:
	match key:
		"door_n":
			return float(BuildWords.layout(plan)["doors"].size())
		"win_n":
			return float(plan["win_n"])
	return float(plan.get(key, 0.0))


func _fmt(key: String, v: float) -> String:
	return str(int(v)) if key in ["floors", "door_n", "win_n"] else BuildWords._m(v)
