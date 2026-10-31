extends SceneTree
## godot --path . --position 3000,3000 -s tests/p141walkcycles_test.gd   (FRIDAY 141: WALK CYCLES WITH SLIDERS, Easy mode, real clicks)
## A beginner: clicks Walk, then Walk style, then drags the three sliders (Speed, Swagger, Bounce) to their ends with the mouse, then Done and Undo.
## Every number is read from the built clip (S.cards: move, hold, pose joints) or from the slider the mouse moved, never from the code's variables.
## Bars (written before the code; each must FAIL with no Walk style button):
##   1 BUTTON  after a Walk, a "Walk style" button shows and its box lies inside the 1280 x 720 window
##   2 PANEL   a click on it opens the panel with the Speed, Swagger and Bounce sliders, each at 100 %
##   3 SPEED   a drag to the end: the slider reaches 195 % or more, and the clip is 100 / v of its built length (3 %)
##   4 UNDO    Done, then Undo once: the clip is back to its built length (one undo step for the whole drag)
##   5 SWAY0   Swagger dragged to 0 %: the pelvis of every middle card is level (under 0.05 deg)
##   6 SWAY    Swagger dragged to the end: the pelvis side of the middle card is 3 deg x v / 100 (0.5 deg)
##   7 BOUNCE  Bounce dragged to the end: the spine_02 bend of the middle card is 2 deg x v / 100 (0.3 deg)
## Shots: C:/Temp/claude/p141walkcycles/s1/NN_name.png
const OUT := "C:/Temp/claude/p141walkcycles/s1/"

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


func _init() -> void:
	EasyMode.start_fresh = true
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(10)
	var is_easy: bool = m.easy.on
	ok(is_easy, "0 start: Easy mode is on from a fresh start")
	# a beginner builds a walk from the Walk card
	await click_text("Walk")
	await idle(60)
	var cards0: Array = m.S.cards.duplicate(true)
	var L0 := clip_len(cards0)
	ok(cards0.size() >= 2, "0 built: a walk clip with %d cards, %.2f s" % [cards0.size(), L0])
	await shot("walk_built")

	# 1 BUTTON
	var wb := find_btn("Walk style")
	var vp := get_root().get_visible_rect()
	var fit := wb != null and vp.encloses(wb.get_global_rect())
	ok(fit, "1 BUTTON Walk style shows after a Walk, inside the 1280 x 720 window (%s)" % (str(wb.get_global_rect()) if wb != null else "not visible"))

	# 2 PANEL
	if wb != null:
		await click_ctl(wb)
	await idle(6)
	var home = m.easy.home
	var sl: Dictionary = home._ws_sliders
	var vals := []
	for k in ["speed", "bounce", "swagger"]:
		vals.append(float(sl[k].value) if sl.has(k) else -1.0)
	ok(sl.size() == 3 and vals == [100.0, 100.0, 100.0], "2 PANEL three sliders, each at 100 %% [%s]" % str(vals))
	await shot("panel_open")

	# 3 SPEED: the speed slider dragged to its end
	await drag_slider(sl["speed"], 1.0)
	var v := float(sl["speed"].value)
	var L1 := clip_len(m.S.cards)
	ok(v >= 195.0 and absf(L1 / L0 - 100.0 / v) <= 0.03 * 100.0 / v,
		"3 SPEED slider at %.0f %%: the clip is %.2f s, built %.2f s (ratio %.3f, want %.3f)" % [v, L1, L0, L1 / L0, 100.0 / v])
	await shot("speed_end")

	# 4 UNDO: Done closes the panel; one Undo takes back the whole drag
	await click_text("Done")
	await idle(4)
	await click_text("Undo")
	await idle(20)
	var L2 := clip_len(m.S.cards)
	ok(absf(L2 - L0) < 0.001, "4 UNDO one Undo takes the whole drag back: %.3f s (built %.3f s)" % [L2, L0])

	# 5 SWAY0 and 6 SWAY: swagger on the middle card's pelvis (card 2 sways the other way to card 1)
	await click_text("Walk style")
	await idle(6)
	await drag_slider(sl["swagger"], -1.0)
	var side0 := _joint(m.S.cards, 2, "pelvis", "side")
	ok(absf(side0) < 0.05 and float(sl["swagger"].value) < 0.5, "5 SWAY0 swagger at 0 %%: the pelvis is level (%.3f deg)" % side0)
	await drag_slider(sl["swagger"], 1.0)
	var sv := float(sl["swagger"].value)
	var side1 := _joint(m.S.cards, 2, "pelvis", "side")
	ok(absf(absf(side1) - 3.0 * sv / 100.0) <= 0.5 and sv >= 195.0,
		"6 SWAY swagger at %.0f %%: the pelvis sways %.2f deg (want %.2f)" % [sv, side1, 3.0 * sv / 100.0])
	await shot("swagger_end")

	# 7 BOUNCE
	await drag_slider(sl["bounce"], 1.0)
	var bv := float(sl["bounce"].value)
	var bend := _joint(m.S.cards, 2, "spine_02", "bend") - _joint(cards0, 2, "spine_02", "bend")   # the change from the walk as built (its chest is bent 4 deg already)
	ok(absf(absf(bend) - 2.0 * bv / 100.0) <= 0.3 and bv >= 195.0,
		"7 BOUNCE bounce at %.0f %%: the chest moves %.2f deg from the built walk (want %.2f)" % [bv, bend, 2.0 * bv / 100.0])
	await shot("bounce_end")

	print("p141walkcycles: %d fail, %d clicks" % [fails, clicks])
	quit(1 if fails > 0 else 0)


func _joint(cards: Array, i: int, joint: String, ax: String) -> float:
	var p: Dictionary = cards[i]["pose"]
	if not p.has("joints") or not p["joints"].has(joint):
		return 0.0
	return float(p["joints"][joint][ax])
