## godot --path . -s tests/inspector_test.gd     (GATES RR2; needs a window)
## THE INSPECTOR: the right panel is a small box docked under the bar, as tall as what it shows. For a limb, a hand
## (its pole row) and the hips (their 3 extra sliders), every section folded: at most 300 px tall, at most RIGHT_W 290
## wide, no Label on show longer than 40 characters (the teaching words are tooltips now: the angle's hint is its
## name's tooltip, how to use the part is the title's). A section's header opens it (its rows show, the box grows) and
## folds it. Every control the round-35 panel had is in the box, found by its label, and works: Reset, 90, 45, the two
## mirrors, a finger preset, the weapon in hand, the math. The x folds the box to the PART rail; the rail opens it.
## Picking the weapon opens WEAPON. Clicks are real (pushed into the window) where a button is on show.
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func click(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = p
		e.global_position = p
		if down:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e)
		await process_frame


func pick(j: String) -> void:
	m.sel = j
	m._refresh()
	await idle(4)


## the box's button with this label (its words, or an icon's kept label)
func btn(t: String) -> Button:
	for b in m.ui_insp.find_children("*", "Button", true, false):
		if m.label_of(b) == t:
			return b
	return null


func long_labels() -> Array:
	var out := []
	for l in m.ui_insp.find_children("*", "Label", true, false):
		if (l as Label).is_visible_in_tree() and (l as Label).text.length() > 40:
			out.append((l as Label).text.left(50))
	return out


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	for t in m.ui_secs:
		m._sec_open(t, false)
	for j in ["upperarm_r", "hand_r", "pelvis"]:
		await pick(j)
		var r: Rect2 = m.ui_insp.get_global_rect()
		var ll := long_labels()
		ok(m.ui_insp.is_visible_in_tree() and r.size.y <= 300.0 and r.size.x <= 290.0 and ll.is_empty() and m.nice(j).to_upper() in m.ui_title.text,
			"%s: the box %.0f x %.0f (at most 290 x 300), '%s', long labels %s" % [j, r.size.x, r.size.y, m.ui_title.text, ll])
	await pick("upperarm_r")
	var tip: String = m.ui_rows["bend"]["label"][0].tooltip_text
	ok(tip != "" and m.ui_title.tooltip_text != "", "the words are tooltips: SWING's '%s', the title's '%s'" % [tip.left(40), m.ui_title.tooltip_text.left(40)])
	# a section opens and folds; the box grows to show it
	var h0: float = m.ui_insp.get_global_rect().size.y
	await click(m.ui_secs["HANDS"][0])
	await idle(3)
	var h1: float = m.ui_insp.get_global_rect().size.y
	var fr: Control = m.ui_insp.find_child("fingers_r", true, false)
	ok(fr.is_visible_in_tree() and h1 > h0 + 40.0, "HANDS opened by a click: the finger rows show, the box %.0f -> %.0f" % [h0, h1])
	await click(btn("Fist"))
	await idle()
	ok("right hand: fist" in m.ui_status.text, "  'Fist' clicked: '%s'" % m.ui_status.text.strip_edges().left(40))
	await click(m.ui_secs["HANDS"][0])
	await idle(3)
	ok(not fr.is_visible_in_tree() and absf(m.ui_insp.get_global_rect().size.y - h0) < 2.0, "HANDS folded again: the box back to %.0f" % m.ui_insp.get_global_rect().size.y)
	# the round-35 panel's controls, by label, clicked
	m.B.ang["upperarm_r"] = Vector3(40, 10, 5)
	m.B.fk()
	m._refresh()
	await idle()
	await click(btn("Reset (R)"))
	ok((m.B.ang["upperarm_r"] as Vector3).length() < 1e-3, "'Reset (R)' clicked: the arm back to 0")
	m.B.ang["upperarm_r"] = Vector3(52, 0, 0)
	m.B.fk()
	m._refresh()
	await idle()
	await click(btn("45"))
	ok(is_equal_approx((m.B.ang["upperarm_r"] as Vector3).x, 45.0), "'45' clicked: 52 -> %.0f" % (m.B.ang["upperarm_r"] as Vector3).x)
	await click(btn("Right to left (M)"))
	ok(btn("Left to right (N)") != null and btn("90 (Q)") != null, "the mirrors and 90 are in the box")
	await click(m.ui_secs["NUMBERS"][0])
	await idle(3)
	await click(btn("Show the math (for Claude)"))
	await idle()
	ok(m.ui_math.is_visible_in_tree(), "NUMBERS > 'Show the math' clicked: the numbers show")
	m.ui_math.visible = false
	m._sec_open("NUMBERS", false)
	# the lock: an icon, its label follows
	await click(m.ui_lock_btn)
	await idle()
	ok(m.locked_parts.has("upperarm_r") and m.label_of(m.ui_lock_btn) == "Unlock this part" and m.ui_lock_btn.text == "", "the lock icon clicked: locked, its label '%s'" % m.label_of(m.ui_lock_btn))
	await click(m.ui_lock_btn)
	await idle()
	# the weapon picked: WEAPON opens
	m._sec_open("WEAPON", false)
	if not m.B.wep_on:
		m._kind("metal_bat")
	m.sel = "bat_handle"
	m._refresh()
	await idle(4)
	ok(m.ui_secs["WEAPON"][1].is_visible_in_tree() and btn("In right hand (B)") != null and btn("In right hand (B)").is_visible_in_tree(), "the weapon picked: WEAPON open, 'In right hand (B)' on show")
	# the x folds it; the rail opens it
	await pick("upperarm_r")
	await click(m.ui_fold_btn["right"])
	await idle(4)
	ok(not m.ui_insp.is_visible_in_tree() and m.ui_rails["right"].is_visible_in_tree(), "the x folds the box to the PART rail")
	await click(m.ui_rails["right"].find_child("open_right", true, false))
	await idle(4)
	ok(m.ui_insp.is_visible_in_tree(), "the rail opens it again")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(m.settings))
	print("INSPECTOR TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
