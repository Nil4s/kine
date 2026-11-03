class_name GuidedPose
extends Node
## C16 (complaint 482): a guided first pose, about ten minutes, six steps, each moved on by the APP STATE (never a Next
## button), Skip always there. It opens ONLY from the palette command "Guided first pose" (or begin()); it never starts by
## itself and never writes the first-launch "onboarded" flag, so the start screen and the existing onboarding are untouched.
const STEPS := [
	["Pick a body", "Press 50th, 95th or 5th (BODY page) or move a slider."],
	["Click a body part", "Click the part you want to move: a hand, a foot or the head."],
	["Drag it", "Drag that part. The limb follows."],
	["Move a second part", "Click and drag a different part. A pose is two or three parts placed well."],
	["Clip the pose", "Press Enter (or Clip this pose) to put it on the timeline."],
	["Press Play", "Press Play: your first pose plays back."],
]
var m: Node
var step := -1
var card: PanelContainer
var _title: Label
var _text: Label
var _snap := {}


func build(root: Control) -> void:
	card = PanelContainer.new()
	card.name = "guided_pose_card"
	card.visible = false
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
	skip.name = "guided_pose_skip"
	skip.text = "Skip"
	skip.focus_mode = Control.FOCUS_NONE
	skip.pressed.connect(finish.bind(true))
	h.add_child(skip)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(260, 0)
	_text.add_theme_color_override("font_color", Tok.c("on_accent"))
	v.add_child(_text)
	root.add_child(card)
	set_process(false)


func begin() -> void:
	_go(0)


func _go(k: int) -> void:
	if k >= STEPS.size():
		finish(false)
		return
	step = k
	_snap = {"body": JSON.stringify(m.S.body), "pose": JSON.stringify(m.B.state()), "cards": m.S.cards.size(), "sel": String(m.sel)}
	_title.text = "%d of %d:  %s" % [k + 1, STEPS.size(), STEPS[k][0]]
	_text.text = STEPS[k][1]
	card.visible = true
	card.reset_size()
	_place()
	set_process(true)


## the card goes where it covers no visible button, label, slider, field or picture: the free spot nearest the top right, else hidden
func _place() -> void:
	var win: Rect2 = card.get_viewport().get_visible_rect()
	var sz := card.get_combined_minimum_size()
	var bl := _blockers()
	var best := Vector2(-1, -1)
	var bd := INF
	var y := 4.0
	while y + sz.y <= win.size.y - 4.0:
		var x := 4.0
		while x + sz.x <= win.size.x - 4.0:
			var r := Rect2(Vector2(x, y), sz).grow(2.0)
			var free := true
			for b in bl:
				if b.intersects(r):
					free = false
					break
			if free:
				var d := Vector2(x + sz.x, y).distance_to(Vector2(win.size.x, 0.0))
				if d < bd:
					bd = d
					best = Vector2(x, y)
			x += 12.0
		y += 12.0
	card.visible = best.x >= 0.0
	if card.visible:
		card.position = best
		card.size = sz


func _blockers() -> Array:
	var out := []
	var st: Array = [m.ui_root]
	while not st.is_empty():
		var n: Node = st.pop_back()
		if n == card:
			continue
		for c in n.get_children():
			st.append(c)
		if n is Control and (n as Control).is_visible_in_tree() and (n is BaseButton or n is Label or n is Range or n is LineEdit or n is TextureRect):
			var r := (n as Control).get_global_rect()
			if r.size.x > 1.0 and r.size.y > 1.0:
				out.append(r)
	return out


func finish(skipped: bool) -> void:
	step = -1
	set_process(false)
	if card != null:
		card.visible = false
	if m != null:
		m._say("Guided pose skipped." if skipped else "Guided pose done: you made a pose, clipped it and played it.")


func done_now() -> bool:
	match step:
		0: return JSON.stringify(m.S.body) != _snap["body"]
		1: return String(m.sel) != _snap["sel"]
		2: return JSON.stringify(m.B.state()) != _snap["pose"]
		3: return String(m.sel) != _snap["sel"] and JSON.stringify(m.B.state()) != _snap["pose"]
		4: return m.S.cards.size() > int(_snap["cards"])
		5: return bool(m.playing)
	return false


var _t := 0


func _process(_d: float) -> void:
	_t += 1
	if step >= 0 and _t % 20 == 0:
		card.reset_size()
		_place()
	if step >= 0 and done_now():
		_go(step + 1)
