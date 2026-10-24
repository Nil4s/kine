## godot --path . -s tests/easybar_test.gd     (EASY BAR: at most 7 visible buttons; every action reachable by its text in at most 2 clicks; needs a window)
## The bar: 7 buttons at most (More counts). Each action that was on the old 13-button bar is found by its text: on the
## bar = 1 click, under More = 2 clicks (More, then the entry). Every bar button and More entry has a tooltip, and every
## action is still wired. MEASURES only: it does not run the actions (Save scene and Open would open dialogs).
## --bar-shot=<png> (after --): saves the viewport picture of the bar, for the screenshot in the task log.
extends SceneTree

const BAR_MAX := 7
# the old bar's 13 actions, by the label they had -> the label they have now (Export video is Save video; Save is Save scene)
const OLD13 := {
	"Pose (drag parts)": "Pose (drag parts)", "Key this pose": "Key this pose", "Play / Stop": "Play / Stop",
	"Undo": "Undo", "Redo": "Redo", "New scene": "New scene", "Open": "Open", "Save": "Save scene",
	"Mirror pose": "Mirror pose", "Floor (snap feet)": "Floor (snap feet)", "Export video": "Save video",
	"Library": "Library", "Switch to Expert": "Switch to Expert",
}

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 4) -> void:
	for i in n:
		await process_frame


## the visible buttons on the bar (the More menu is a PopupMenu, not a Button)
func bar_buttons() -> Array:
	var out := []
	for n in m.easy.bar.find_children("*", "Button", true, false):
		if (n as Button).is_visible_in_tree():
			out.append(n)
	return out


func bar_button(label: String) -> Button:
	for b in bar_buttons():
		if String(b.get_meta("label", "")) == label:
			return b
	return null


## the clicks to reach an action by its text: 1 on the bar; More, then its entry = 2. -1 = not reachable.
## The More entry is found by its text in the open menu, and must be wired; its action is not run here.
func clicks_to(label: String) -> int:
	if bar_button(label) != null:
		return 1
	var more: PopupMenu = m.easy._more
	more.hide()
	(m.easy.button("More") as Button).pressed.emit()   # click 1: More opens the menu
	var shown := more.visible
	var found := -1
	for i in more.item_count:
		if more.get_item_text(i) == label:
			found = i
	var wired: bool = found >= 0 and (m.easy._more_acts[found][2] as Callable).is_valid()
	more.hide()                                           # click 2 (the entry) is counted, not run
	return 2 if (shown and wired) else -1


func _init() -> void:
	var shot := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--bar-shot="):
			shot = a.substr(11)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	m.easy.set_on(true, false)
	await idle(8)

	# 1. the bar: at most 7 visible buttons, the seven named ones, each with a tooltip and wired
	var bb := bar_buttons()
	var labels := bb.map(func(b): return String(b.get_meta("label", "")))
	ok(m.easy.bar.visible and bb.size() <= BAR_MAX and bb.size() == BAR_MAX,
		"the Easy bar shows %d buttons (at most %d): %s" % [bb.size(), BAR_MAX, str(labels)])
	var no_tip := []
	var unwired := []
	for b in bb:
		if (b as Button).tooltip_text.strip_edges() == "":
			no_tip.append(b.get_meta("label", ""))
		if (b as Button).pressed.get_connections().is_empty():
			unwired.append(b.get_meta("label", ""))
	ok(no_tip.is_empty() and unwired.is_empty(), "every bar button has a tooltip and an action (no tip: %s, unwired: %s)" % [str(no_tip), str(unwired)])

	# 2. More: one button, its menu holds the rest, each entry with a tooltip
	var more: PopupMenu = m.easy._more
	var mtips := []
	for i in more.item_count:
		if more.get_item_tooltip(i).strip_edges() == "":
			mtips.append(more.get_item_text(i))
	ok(bar_button("More") != null and more.item_count == 8 and mtips.is_empty(),
		"More holds %d entries, each with a tooltip (no tip: %s)" % [more.item_count, str(mtips)])

	# 3. every action that was on the old bar: found by its text, reached in at most 2 clicks
	for old in OLD13.keys():
		var now: String = OLD13[old]
		var c := clicks_to(now)
		ok(c >= 1 and c <= 2, "%s (was: %s): reached in %d click%s" % [now, old, c, "" if c == 1 else "s"] if c >= 1 else "%s (was: %s): NOT reachable by its text" % [now, old])

	# 4. a screenshot of the bar (only when asked: the caller gives --bar-shot=<png>)
	if shot != "":
		await idle(3)
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var err := img.save_png(shot)
		ok(err == OK, "the bar's picture is saved to %s (error %d)" % [shot, err])

	print("EASY BAR %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
