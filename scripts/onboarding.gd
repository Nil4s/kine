class_name Onboarding
extends Node
## ONBOARDING (docs/ROADMAP.md R25): the first launch is a 3-step guide over the real pages.
##   1 BODY    pick a body        (done when the body's proportions change: a percentile button, a slider, a character)
##   2 POSE    drag a body part   (done when a real drag of a part lets go with the pose changed)
##   3 ANIMATE clip this pose twice, then press play   (done when two cards were added and the scene plays)
## Each step is a small callout anchored to the real control (an arrow and one sentence). It moves on by the real action,
## never by a Next button; Skip is always there. Done or skipped writes look/onboarded = true, and it never shows again.
## The callout sits BESIDE its target (never over it) and inside the window, at every UI size.
## A test (and a scripted shot) never starts it by itself: it calls begin() on its own settings file.

const CFG := "look"
const KEY := "onboarded"
const STEPS := [
	["Pick a body", "Press 50th, 95th or 5th to choose who you pose, or move a slider."],
	["Drag a body part", "Press a hand or a foot of the body and drag it. The limb follows."],
	["Clip it twice, then play", "Clip this pose, change it, clip again (Enter does it), then press Play."],
]
const GAP := 30.0      # the arrow's room between the callout and its target
const MARGIN := 8.0

var m: Node
var step := -1               # -1 = not showing
var pending := false         # due on this launch (main starts it once the recover offer is out of the way)
var card: PanelContainer
var arrow: Control
var _title: Label
var _text: Label
var _snap := {}
var _armed := false
var _moved := false
var _tip := Vector2.ZERO
var _from := Vector2.ZERO


static func is_due(cf: ConfigFile) -> bool:
	return not cf.has_section_key(CFG, KEY)


func build(root: Control) -> void:
	card = PanelContainer.new()
	card.name = "onboard_card"
	card.visible = false
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE   # never takes a click meant for the body; its Skip button still does
	var st := StyleBoxFlat.new()
	st.bg_color = Tok.c("accent")
	st.set_corner_radius_all(8)
	st.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", st)
	var v := VBoxContainer.new()
	card.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 16)
	_title.add_theme_color_override("font_color", Tok.c("on_accent"))
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(_title)
	var skip := Button.new()
	skip.name = "onboard_skip"
	skip.text = "Skip"
	skip.focus_mode = Control.FOCUS_NONE
	skip.tooltip_text = "close the guide; it will not show again"
	skip.pressed.connect(finish.bind(true))
	h.add_child(skip)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(250, 0)
	_text.add_theme_font_size_override("font_size", 14)
	_text.add_theme_color_override("font_color", Tok.c("on_accent"))
	v.add_child(_text)
	arrow = Control.new()
	arrow.name = "onboard_arrow"
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow.visible = false
	arrow.draw.connect(_draw_arrow)
	root.add_child(arrow)
	root.add_child(card)


## main: at the start, before the other tours decide. auto = a real launch (not a test or a scripted shot)
func prepare(cf: ConfigFile, auto: bool) -> void:
	pending = auto and is_due(cf)


## main, after the UI is built: wait for the recover offer, then begin
func start_when_clear() -> void:
	if not pending:
		return
	await get_tree().process_frame
	while m.ui_recover != null and m.ui_recover.visible:
		await m.ui_recover.visibility_changed
	if is_inside_tree() and pending and step < 0:
		begin()


func begin() -> void:
	pending = false
	if m.easy != null and m.easy.on:
		m.easy.set_on(false, false)   # the guide points at the pages: Expert for this run (the saved mode is untouched)
	_go(0)


func _go(k: int) -> void:
	if k >= STEPS.size():
		finish(false)
		return
	step = k
	_armed = false
	_moved = false
	_snap = {"body": JSON.stringify(m.S.body), "pose": JSON.stringify(m.B.state()), "cards": m.S.cards.size()}
	m._page_set(["BODY", "POSE", "ANIMATE"][k], false)
	_title.text = "%d of %d:  %s" % [k + 1, STEPS.size(), STEPS[k][0]]
	_text.text = STEPS[k][1]
	card.visible = true
	arrow.visible = true
	card.reset_size()
	set_process(true)
	_place()


func finish(skipped: bool, save := true) -> void:
	step = -1
	pending = false
	set_process(false)
	if card != null:
		card.visible = false
		arrow.visible = false
	if save and m != null:
		var cf := ConfigFile.new()
		cf.load(m.settings)
		cf.set_value(CFG, KEY, true)
		cf.save(m.settings)
		m._say("Guide skipped. Help: show the tour shows the other tour." if skipped else "Guide done: you picked a body, posed it and played a clip.")


# ---------------------------------------------------------------- what each step points at

## the control (or the body) the step is about, in window coordinates
func target_rect() -> Rect2:
	match step:
		0:
			var q: Node = m.ui_body.find_child("quick_50", true, false)
			if q is Control and (q as Control).is_visible_in_tree():
				var r := (q as Control).get_global_rect()
				return r.merge((m.ui_body.find_child("quick_5", true, false) as Control).get_global_rect()).merge((m.ui_body.find_child("quick_95", true, false) as Control).get_global_rect())
			return m.ui_body.get_global_rect()
		1:
			return body_rect()
		2:
			var play: Control = m.ui_play
			if int(_snap.get("cards", 0)) + 2 > m.S.cards.size():
				var c: Node = m.ui_cards.find_child("start_clip", true, false)
				if c is Control and (c as Control).is_visible_in_tree():
					return (c as Control).get_global_rect()
				return m.ui_cards.get_global_rect() if m.ui_cards.is_visible_in_tree() else play.get_global_rect()
			return play.get_global_rect()
	return Rect2()


## the body as drawn: every part's capsule ends, projected
func body_rect() -> Rect2:
	var r := Rect2()
	var first := true
	for j in Body.ORDER:
		for p in m.B.cap(j):
			var s: Vector2 = m.cam.unproject_position(p)
			if first:
				r = Rect2(s, Vector2.ZERO)
				first = false
			else:
				r = r.expand(s)
	return r.grow(10.0)


func _sides() -> Array:
	match step:
		0: return ["right", "below", "above", "left"]
		1: return ["right", "left", "below", "above"]
	return ["above", "left", "right", "below"]


## the callout beside the target: the first side where it fits inside the window and clear of the target plus the arrow's gap
func _place() -> void:
	if card == null or step < 0:
		return
	var win: Rect2 = get_viewport().get_visible_rect()
	var t := target_rect()
	var sz := card.get_combined_minimum_size()
	var best := Rect2()
	var best_side := ""
	for side in _sides():
		var p := Vector2.ZERO
		var c := t.get_center()
		match side:
			"right": p = Vector2(t.end.x + GAP, c.y - sz.y * 0.5)
			"left": p = Vector2(t.position.x - GAP - sz.x, c.y - sz.y * 0.5)
			"below": p = Vector2(c.x - sz.x * 0.5, t.end.y + GAP)
			_: p = Vector2(c.x - sz.x * 0.5, t.position.y - GAP - sz.y)
		p = Vector2(clampf(p.x, MARGIN, win.size.x - sz.x - MARGIN), clampf(p.y, MARGIN, win.size.y - sz.y - MARGIN))
		var r := Rect2(p, sz)
		if not r.intersects(t.grow(GAP - 4.0)):
			best = r
			best_side = side
			break
	if best_side == "":   # nothing is clear (a huge target): the corner farthest from the target's centre
		var far := Rect2(MARGIN, MARGIN, sz.x, sz.y)
		for corner in [Vector2(MARGIN, MARGIN), Vector2(win.size.x - sz.x - MARGIN, MARGIN), Vector2(MARGIN, win.size.y - sz.y - MARGIN), win.size - sz - Vector2(MARGIN, MARGIN)]:
			var r2 := Rect2(corner, sz)
			if r2.get_center().distance_to(t.get_center()) > far.get_center().distance_to(t.get_center()) or far.intersects(t):
				far = r2
		best = far
	card.position = best.position
	card.size = sz
	# the arrow: from the callout's edge to a point on the target's edge, 4 px short of it
	var cc := best.get_center()
	var tip := Vector2(clampf(cc.x, t.position.x, t.end.x), clampf(cc.y, t.position.y, t.end.y))
	var from := Vector2(clampf(tip.x, best.position.x, best.end.x), clampf(tip.y, best.position.y, best.end.y))
	var dir := (tip - from).normalized() if tip.distance_to(from) > 1.0 else Vector2.RIGHT
	_tip = tip - dir * 4.0
	_from = from
	arrow.position = Vector2.ZERO
	arrow.size = win.size
	arrow.queue_redraw()


func _draw_arrow() -> void:
	var col := Tok.c("accent")
	var d := _tip - _from
	if d.length() < 2.0:
		return
	var n := d.normalized()
	var side := Vector2(-n.y, n.x)
	var head := minf(14.0, d.length())
	var base := _tip - n * head
	arrow.draw_line(_from, base, col, 3.0)
	arrow.draw_colored_polygon(PackedVector2Array([_tip, base + side * 8.0, base - side * 8.0]), col)


## the arrow's tip, for the test (always short of the target)
func arrow_tip() -> Vector2:
	return _tip


# ---------------------------------------------------------------- the real actions move it on

func _process(_dt: float) -> void:
	if step < 0 or m == null:
		set_process(false)
		return
	_place()
	if JSON.stringify(m.B.state()) != _snap["pose"]:
		_moved = true
	match step:
		0:
			if JSON.stringify(m.S.body) != _snap["body"]:
				_go(1)
		1:
			if m.dragging == "joint":
				_armed = true
			elif _armed and m.dragging == "":
				if _moved:
					_go(2)
				else:
					_armed = false   # a click without a drag is not it
		2:
			if m.S.cards.size() >= int(_snap["cards"]) + 2 and m.playing:
				finish(false)
