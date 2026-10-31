extends SceneTree
## godot --path . -s tests/s142_test.gd   (FRIDAY 142: STYLE SLIDER realistic <-> cartoon, Easy mode, real drags)
## Bars (numbers read from the built clip's cards and the posed body):
##   1 ROW    after a Walk the Style slider shows, inside the 1280 x 720 window, at 1.00x
##   2 K1     ClipStyle at 1.0: every joint equals the clip within 0.01 deg
##   3 BIG    slider dragged up (v): the biggest arm joint's range of motion is v x the original within 5%
##   4 FEET   at that v the planted feet are within 1 cm of where the clip planted them (every card)
##   5 LEN    the clip length is unchanged
##   6 UNDO   one Undo = the original cards (one step per drag)
##   7 SMALL  slider dragged down (v about 0.5): the same arm joint's range is v x the original within 5%
##   8 SAFE   at 2.0 feet still within 1 cm and no sole below the floor (> 1 cm)
const OUT := "C:/Temp/claude/s142/"

var m: Node
var n_shot := 0
var fails := 0
var clicks := 0


func say(s: String) -> void:
	print(s)


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 4) -> void:
	for i in n:
		await process_frame


func walk(n: Node, out: Array) -> Array:
	out.append(n)
	for c in n.get_children():
		walk(c, out)
	return out


func visible_buttons() -> Array:
	var out := []
	for n in walk(root, []):
		if n is Button and (n as CanvasItem).is_visible_in_tree():
			out.append(n)
	return out


func text_of(b: Button) -> String:
	if b.text.strip_edges() != "":
		return b.text.strip_edges()
	for n in walk(b, []):
		if n is Label and (n as Label).text.strip_edges() != "":
			return (n as Label).text.strip_edges()
	return ""


func find_btn(txt: String) -> Button:
	for b in visible_buttons():
		if text_of(b) == txt:
			return b
	return null


func btn(down: bool, p: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)


func move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)


func hover(p: Vector2) -> void:
	var hm := InputEventMouseMotion.new()
	hm.position = p
	hm.global_position = p
	root.push_input(hm)
	await process_frame


## a real click on a Control: the mouse goes down and up on its middle
func click_ctl(c: Control) -> bool:
	var p := srect(c).get_center()
	await hover(p)
	var under := get_root().get_viewport().gui_get_hovered_control()
	var inside := under != null and (under == c or c.is_ancestor_of(under))
	btn(true, p)
	await process_frame
	btn(false, p)
	await idle(3)
	clicks += 1
	return inside


func click_text(txt: String) -> bool:
	var b := find_btn(txt)
	if b == null:
		say("   NOT VISIBLE: no button reads '%s'" % txt)
		return false
	return await click_ctl(b)


## a real drag on a slider: the press at the track's far end (or its middle), the pointer moves in steps, and lets go there
func drag_slider(s: HSlider, to_end: float) -> void:
	var r := srect(s)
	var y := r.get_center().y
	var x0 := r.get_center().x
	var x1 := r.end.x - 2.0 if to_end > 0.5 else r.position.x + 2.0   # to_end > 0: the right end (the top), < 0: the left end (0 %)
	await hover(Vector2(x0, y))
	btn(true, Vector2(x0, y))
	await process_frame
	for i in 6:
		move(Vector2(lerpf(x0, x1, float(i + 1) / 6.0), y))
		await process_frame
	btn(false, Vector2(x1, y))
	await idle(4)
	clicks += 1


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(OUT)
	n_shot += 1
	root.get_texture().get_image().save_png("%s%02d_%s.png" % [OUT, n_shot, nm])


## a control's rect on the screen: a popup panel is its own window, so its own rect is measured from the screen transform
func srect(c: Control) -> Rect2:
	var t := c.get_screen_transform()
	return Rect2(t.origin, c.size * t.get_scale())


## the clip's length from its cards (the same sum the strip shows)
func clip_len(cards: Array) -> float:
	var t := 0.0
	for i in cards.size():
		if i > 0:
			t += float(cards[i]["move"])
		t += float(cards[i]["hold"])
	return t



func rom(cards: Array, j: String, ax: String) -> float:
	var lo := INF
	var hi := -INF
	for c in cards:
		var p: Dictionary = c["pose"]
		if not p.has("joints") or not p["joints"].has(j):
			continue
		var v := float(p["joints"][j][ax])
		lo = minf(lo, v)
		hi = maxf(hi, v)
	return hi - lo if hi >= lo else 0.0


## the arm joint + axis with the widest swing in the clip
func swing(cards: Array) -> Array:
	var best := ["", "", 0.0]
	for j in ["upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r"]:
		for ax in ["bend", "side", "twist"]:
			var r := rom(cards, j, ax)
			if r > float(best[2]):
				best = [j, ax, r]
	return best


## ball places of the planted feet per card: {card index: {side: Vector3}} for a clip's cards
func planted(cards: Array) -> Dictionary:
	var out := {}
	var keep: Dictionary = m.B.state()
	m.B.props = m.S.solid_props()
	for i in cards.size():
		var d: Dictionary = cards[i]["pose"]
		if d.is_empty() or not d.has("joints"):
			continue
		m.B.from_dict(d)
		if absf(m.B.floor_shift()) >= 0.01:
			continue
		for sd in ["_l", "_r"]:
			var fs: Array = m.B.foot_state(sd)
			if bool(fs[2]):
				if not out.has(i):
					out[i] = {}
				out[i][sd] = fs[0]
	m.B.set_state(keep)
	return out


func foot_report(c0: Array, c1: Array) -> Array:
	var a := planted(c0)
	var worst := 0.0
	var n := 0
	var keep: Dictionary = m.B.state()
	for i in a:
		m.B.props = m.S.solid_props()
		m.B.from_dict(c1[i]["pose"])
		for sd in a[i]:
			var b: Vector3 = m.B.foot_state(sd)[0]
			worst = maxf(worst, (b - (a[i][sd] as Vector3)).length())
			n += 1
	m.B.set_state(keep)
	return [worst, n]


func low_sole(cards: Array) -> float:
	var lo := INF
	var keep: Dictionary = m.B.state()
	for c in cards:
		m.B.from_dict(c["pose"])
		lo = minf(lo, minf(m.B.foot_sole_low("_l"), m.B.foot_sole_low("_r")))
	m.B.set_state(keep)
	return lo


func maxdiff(a: Array, b: Array) -> float:
	var w := 0.0
	for i in a.size():
		var pa: Dictionary = a[i]["pose"]
		var pb: Dictionary = b[i]["pose"]
		if not pa.has("joints"):
			continue
		for j in pa["joints"]:
			for ax in ["bend", "side", "twist"]:
				w = maxf(w, absf(float(pa["joints"][j][ax]) - float(pb["joints"][j][ax])))
	return w


func slider_x(s: HSlider, v: float) -> float:
	var r := srect(s)
	var f := (v - s.min_value) / (s.max_value - s.min_value)
	return r.position.x + 8.0 + f * (r.size.x - 16.0)


## a real drag: press at the current value's x, move in steps to the x of `v`, let go
func drag_to(s: HSlider, v: float) -> void:
	var y := srect(s).get_center().y
	var x0 := slider_x(s, s.value)
	var x1 := slider_x(s, v)
	await hover(Vector2(x0, y))
	btn(true, Vector2(x0, y))
	await process_frame
	for i in 6:
		move(Vector2(lerpf(x0, x1, float(i + 1) / 6.0), y))
		await process_frame
	btn(false, Vector2(x1, y))
	await idle(4)
	clicks += 1


func _init() -> void:
	EasyMode.start_fresh = true
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(10)
	await click_text("Walk")
	await idle(60)
	var c0: Array = m.S.cards.duplicate(true)
	var L0 := clip_len(c0)
	var sw := swing(c0)
	print("walk: %d cards, %.2f s, widest arm swing %s %s %.1f deg, planted cards %s" % [c0.size(), L0, sw[0], sw[1], sw[2], str(planted(c0).keys())])
	var s: HSlider = m.easy.home._cs_slider
	var vp := get_root().get_visible_rect()
	ok(s.is_visible_in_tree() and vp.encloses(s.get_global_rect()) and absf(s.value - 1.0) < 0.001, "1 ROW Style slider shows at %.2fx, box %s" % [s.value, str(s.get_global_rect())])
	await shot("walk_built")
	ok(float(sw[2]) > 5.0 and planted(c0).size() > 0, "0 FIXTURE the walk swings an arm %.1f deg and has %d planted cards" % [sw[2], planted(c0).size()])

	var k1 := ClipStyle.styled(c0, m.B, m.S.solid_props(), 1.0)
	var d1 := maxdiff(c0, k1)
	s.value = 1.0
	ok(d1 < 0.01 and absf(s.value - 1.0) < 0.001, "2 K1 at 1.0 every joint equals the clip: max diff %.5f deg" % d1)

	await drag_to(s, 1.5)
	var v := float(s.value)
	var c1: Array = m.S.cards
	var r1 := rom(c1, sw[0], sw[1])
	ok(v > 1.4 and absf(r1 / float(sw[2]) / v - 1.0) <= 0.05, "3 BIG slider %.2fx: %s %s range %.1f -> %.1f deg (x%.3f, want x%.3f)" % [v, sw[0], sw[1], sw[2], r1, r1 / float(sw[2]), v])
	var fr := foot_report(c0, c1)
	ok(fr[1] > 0 and fr[0] <= 0.01, "4 FEET at %.2fx: %d planted feet, worst drift %.2f mm (bar 10)" % [v, fr[1], fr[0] * 1000.0])
	ok(absf(clip_len(c1) - L0) < 0.0005, "5 LEN length %.3f s (was %.3f)" % [clip_len(c1), L0])
	await shot("cartoon_1_5")
	await click_text("Undo")
	await idle(20)
	var d6 := maxdiff(c0, m.S.cards)
	ok(d6 < 0.011 and absf(m.easy.home._cs_slider.value - 1.0) < 0.001, "6 UNDO one Undo: clip back (max diff %.4f deg), slider %.2fx" % [d6, m.easy.home._cs_slider.value])

	await drag_to(s, 0.5)
	v = float(s.value)
	var r7 := rom(m.S.cards, sw[0], sw[1])
	ok(v < 0.56 and absf(r7 / float(sw[2]) / v - 1.0) <= 0.05, "7 SMALL slider %.2fx: range %.1f -> %.1f deg (x%.3f, want x%.3f)" % [v, sw[2], r7, r7 / float(sw[2]), v])
	var fr7 := foot_report(c0, m.S.cards)
	print("   at %.2fx planted drift %.2f mm over %d feet" % [v, fr7[0] * 1000.0, fr7[1]])
	await shot("calm_0_5")

	await drag_to(s, 2.0)
	v = float(s.value)
	var fr8 := foot_report(c0, m.S.cards)
	var low := low_sole(m.S.cards)
	ok(v > 1.95 and fr8[0] <= 0.01 and low > -0.01, "8 SAFE at %.2fx: drift %.2f mm, lowest sole %.1f mm" % [v, fr8[0] * 1000.0, low * 1000.0])
	await shot("cartoon_2_0")

	print("s142: %d fail" % fails)
	quit(1 if fails > 0 else 0)
