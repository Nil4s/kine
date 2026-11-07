## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/pagewire_test.gd   (lane L108: P06 / P07 / P18 wired into the real app)
## Bars written BEFORE the wiring (scripts/main.gd, scripts/hotkeys.gd). The real main scene boots; keys and the toast click are pushed as events.
##   KEYS    Ctrl+Alt+J is bound globally to X and on sculpt to Y. On sculpt the real key runs Y (X 0 times); on animate it runs X; on model it runs X.
##           Planted: with the sculpt binding removed, the key on sculpt runs X.
##   SPACE   MODEL: the part browser is docked right and the timeline closed (the layouts dialog's own drop / set_open). Switch to ANIMATE, reset the
##           working layout there (factory), switch back: the browser's solved rect equals the moved one within 1 px and the timeline is still closed.
##           Planted: with the page store off (m.pg_spaces = null) the same steps leave the browser more than 1 px from the moved rect.
##   TOAST   a keyless command run 10 times through the S palette (real Enter): the toast "learn_toast" is visible and offers Accept and Dismiss.
##           A real click on Dismiss, then 10 more runs: no toast. A second keyless command still gets its toast (the dismissal is per command).
##   EDITOR  the hotkey editor has a scope dropdown (hk_scope: Global + the pages); with sculpt chosen, capturing a key binds it on sculpt only.
##   SAVE    _pw_save, free main, boot a fresh main: the scoped bindings, the dismissal, the run counts and the model page layout are back
##           (the layout after a reset in the fresh main, switched in from another page, within 1 px). 10 more runs there: no toast.
##   CONTROL with no scoped bindings, 20 existing keys pressed for real: each key's learn count moves for exactly the command that holds the key
##           (diff == {id: 1}) and dispatch lets main's own match run it as before. Planted: with a scoped binding on one of the keys, that key fires the
##           scoped command instead.
## Only user:// is written (wtest gives each run its own APPDATA).
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


func key(code: Key, ctrl := false, alt := false, shift := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.ctrl_pressed = ctrl
		e.alt_pressed = alt
		e.shift_pressed = shift
		e.pressed = down
		root.push_input(e)
		await process_frame
	await idle(2)


func click(p: Vector2) -> void:
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.position = p
		e.global_position = p
		e.pressed = down
		root.push_input(e)
		await process_frame
	await idle(2)


func boot() -> Node:
	var n: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(n)
	await idle(4)
	n.tour_step = -1
	if n.ui_tour != null:
		n.ui_tour.visible = false
	return n


func cmd(id: String) -> Dictionary:
	for c in m.ui_cmd.commands:
		if c["id"] == id:
			return c
	return {}


## wrap a command's run so the test counts how often the app ran it (the same dictionary the dispatch reads)
func counter(id: String, box: Array) -> void:
	var c := cmd(id)
	var f: Callable = c["run"]
	c["run"] = func():
		box[0] += 1
		f.call()


func toast() -> Control:
	var t := m.find_child("learn_toast", true, false)
	return t as Control if t != null and (t as Control).is_visible_in_tree() else null


func palette_run(name: String, n: int) -> void:
	for i in n:
		m.ui_cmd.open_with(name)
		await idle(2)
		if not m.ui_cmd.box.has_focus():
			m.ui_cmd.box.grab_focus()
			await idle(1)
		if i < 2:
			print("   palette run %d: focus %s, first row %s" % [i, m.ui_cmd.box.has_focus(), String(m.ui_cmd.shown[0]["name"]) if m.ui_cmd.shown.size() > 0 else "-"])
		await key(KEY_ENTER)


func rect_of(mm: Node, page: String, id: String) -> Rect2:
	var ws: WorkLayouts = mm.bld.shell.ws
	var vs: Vector2 = mm.get_viewport().get_visible_rect().size
	var P: Dictionary = ws.cur["pages"][page]
	var r := WorkLayouts.solve(P, page, vs, WorkLayouts.area_for(vs, int(P["rail_w"])), WorkLayouts.chrome_px(vs, int(P["rail_w"])))
	return r["rects"].get(id, Rect2())


func close_to(a: Rect2, b: Rect2) -> bool:
	return a.size != Vector2.ZERO and absf(a.position.x - b.position.x) <= 1.0 and absf(a.position.y - b.position.y) <= 1.0 \
		and absf(a.size.x - b.size.x) <= 1.0 and absf(a.size.y - b.size.y) <= 1.0


func _init() -> void:
	CommandSearch.user_files_off = true
	m = await boot()
	ok(String(m.settings).begins_with("user://poser_test_"), "0 the test saves to its own config (%s)" % m.settings)
	await control_bars()
	await keys_bars()
	await space_bars()
	await toast_bars()
	await editor_bars()
	await save_bars()
	print("pagewire: %d fail" % fails)
	quit(1 if fails > 0 else 0)


const KJ := "Ctrl+Alt+J"
const XID := "scene_hide_cost_per_character"
const YID := "scene_show_cost_per_character"


func control_bars() -> void:
	# 20 existing keys, no scoped binding anywhere
	var cands := ["1", "2", "3", "4", "5", "Shift+1", "Shift+2", "Shift+3", "Shift+4", "Shift+5", "Shift+6", "R", "K", "Ctrl+Z", "Ctrl+Y", "Tab", "Tab", "Space", "Space", "F6"]
	ok(m.hk.scoped.items.is_empty(), "CONTROL no scoped bindings at the start")
	var pressed := 0
	var good := 0
	var first_keyed := ""
	for combo in cands:
		var holder := Hotkeys.holder(m.ui_cmd.commands, combo)
		if holder.is_empty():
			print("note: %s holds no command" % combo)
			continue
		var before: Dictionary = m.hk.learn.counts.duplicate()
		var code: Key = OS.find_keycode_from_string(String(combo).split("+")[-1])
		await key(code, "Ctrl+" in combo, "Alt+" in combo, "Shift+" in combo)
		var diff := {}
		for k in m.hk.learn.counts:
			var d: int = int(m.hk.learn.counts[k]) - int(before.get(k, 0))
			if d != 0:
				diff[k] = d
		pressed += 1
		var want := {String(holder["id"]): 1}
		var same: bool = JSON.stringify(diff) == JSON.stringify(want)
		good += 1 if same else 0
		if first_keyed == "":
			first_keyed = String(holder["id"])
		if not same:
			print("   %s fired %s, wanted %s" % [combo, diff, want])
		await idle(1)
	ok(pressed >= 20 and good == pressed, "CONTROL %d of %d existing keys fire exactly the command that holds them" % [good, pressed])
	m._page_set("POSE", false)
	await idle(2)
	# dispatch still lets main's own match run a built-in key (false), exactly as before
	var e := InputEventKey.new()
	e.keycode = KEY_1
	e.pressed = true
	ok(m.hk.dispatch(e) == false, "CONTROL a built-in key that still belongs to its command falls through to main (dispatch false)")
	# planted: a scoped binding on key 1 for pose changes what fires
	var hit := [0]
	counter(XID, hit)
	m.hk.scoped.bind("1", XID, "pose")
	m._page_set("POSE", false)
	await idle(2)
	await key(KEY_1)
	ok(hit[0] == 1, "CONTROL planted: a scoped binding on the 1 key fires its command (%d)" % hit[0])
	m.hk.scoped.unbind("1", "pose")


func keys_bars() -> void:
	var cmds: Array = m.ui_cmd.commands
	ok(Hotkeys.holder(cmds, KJ).is_empty() and Hotkeys.built_in(cmds, KJ).is_empty(), "KEYS %s is free in the registry" % KJ)
	var xs := [0]
	var ys := [0]
	counter(XID, xs)
	counter(YID, ys)
	ok(m.hk.scoped.bind(KJ, XID)["ok"] and m.hk.scoped.bind(KJ, YID, "sculpt")["ok"], "KEYS bound: global X, sculpt Y")
	m._page_set("SCULPT", false)
	await idle(2)
	await key(KEY_J, true, true)
	ok(ys[0] == 1 and xs[0] == 0, "KEYS on sculpt the real key runs Y (Y %d, X %d)" % [ys[0], xs[0]])
	m._page_set("ANIMATE", false)
	await idle(2)
	await key(KEY_J, true, true)
	ok(xs[0] == 1 and ys[0] == 1, "KEYS on animate the same key runs X (X %d, Y %d)" % [xs[0], ys[0]])
	m._page_set("MODEL", false)
	await idle(2)
	await key(KEY_J, true, true)
	ok(xs[0] == 2 and ys[0] == 1, "KEYS on model it runs X (the global one) (X %d, Y %d)" % [xs[0], ys[0]])
	m.hk.scoped.unbind(KJ, "sculpt")
	m._page_set("SCULPT", false)
	await idle(2)
	await key(KEY_J, true, true)
	ok(xs[0] == 3 and ys[0] == 1, "KEYS planted: without the sculpt binding, sculpt runs X (X %d, Y %d)" % [xs[0], ys[0]])
	m.hk.scoped.bind(KJ, YID, "sculpt")


func space_bars() -> void:
	var ws: WorkLayouts = m.bld.shell.ws
	m._page_set("MODEL", false)
	await idle(2)
	var lu = m.bld.shell.layouts_ui
	lu.open_dialog()   # builds the dialog's status line (drop() writes to it)
	await idle(2)
	var base := rect_of(m, "part", "browser")
	lu.drop("part", "browser", "right", Vector2(900, 300))
	ws.set_open("part", "timeline", false)
	var moved := rect_of(m, "part", "browser")
	ok(moved.size != Vector2.ZERO and not close_to(base, moved), "SPACE the browser moved on the model page (%s -> %s)" % [base, moved])
	m._page_set("ANIMATE", false)
	await idle(2)
	ws.reset()
	await idle(1)
	ok(not close_to(rect_of(m, "part", "browser"), moved), "SPACE the reset changed the working layout in between")
	m._page_set("MODEL", false)
	await idle(2)
	var back := rect_of(m, "part", "browser")
	ok(close_to(back, moved), "SPACE model panel rect restored within 1 px (%s vs %s)" % [back, moved])
	ok(not bool(ws.cur["pages"]["part"]["panels"]["timeline"]["open"]), "SPACE the closed timeline is still closed")
	# planted: the page store off
	var store = m.pg_spaces
	m.pg_spaces = null
	m._page_set("ANIMATE", false)
	await idle(2)
	ws.reset()
	lu.drop("part", "browser", "right", Vector2(900, 300))
	var moved2 := rect_of(m, "part", "browser")
	ws.reset()
	m._page_set("MODEL", false)
	await idle(2)
	ok(not close_to(rect_of(m, "part", "browser"), moved2), "SPACE planted: without the store the same steps do not bring the rect back")
	m.pg_spaces = store
	# leave the moved layout in place for the SAVE bar
	m._page_set("ANIMATE", false)
	await idle(2)
	ws.reset()
	m._page_set("MODEL", false)
	await idle(2)
	lu.drop("part", "browser", "right", Vector2(900, 300))
	ws.set_open("part", "timeline", false)
	m._page_set("ANIMATE", false)
	await idle(2)


var moved_final := Rect2()


func toast_bars() -> void:
	m.bld.shell.layouts_ui.close_dialog()
	m._page_set("POSE", false)
	await idle(2)
	var name_a := "hide cost per character"
	var id_a := "scene_hide_cost_per_character"
	m.hk.scoped.items.clear()   # the keyless commands must stay keyless for the learn bars
	ok(toast() == null, "TOAST none before any run")
	await palette_run(name_a, 10)
	var t := toast()
	ok(m.hk.learn.runs(id_a) >= 10, "TOAST the palette counted the runs (%d)" % m.hk.learn.runs(id_a))
	ok(t != null and t.find_child("learn_accept", true, false) != null and t.find_child("learn_dismiss", true, false) != null, "TOAST appears after 10 runs with Accept and Dismiss")
	if t != null:
		var b: Button = t.find_child("learn_dismiss", true, false)
		await click(b.get_global_rect().get_center())
	ok(toast() == null and m.hk.learn.is_dismissed(id_a), "TOAST a real click on Dismiss closes it and remembers it")
	await palette_run(name_a, 10)
	ok(toast() == null, "TOAST 10 more runs: no toast")
	await palette_run("show cost per character", 4)
	ok(toast() != null, "TOAST another command still gets its toast")
	if toast() != null:
		await click((toast().find_child("learn_dismiss", true, false) as Button).get_global_rect().get_center())


func editor_bars() -> void:
	m.hk.open_editor()
	await idle(2)
	var dd := m.hk.ui.find_child("hk_scope", true, false) as OptionButton
	ok(dd != null and dd.get_item_text(0) == "Global" and dd.item_count == 1 + Hotkeys.scope_pages().size(), "EDITOR a scope dropdown with Global and %d pages" % (dd.item_count - 1 if dd != null else -1))
	if dd == null:
		return
	var si := -1
	for i in dd.item_count:
		if dd.get_item_text(i).to_lower() == "sculpt":
			si = i
	ok(si > 0, "EDITOR the dropdown lists sculpt")
	dd.select(si)
	dd.item_selected.emit(si)
	await idle(1)
	var id := "help_forget_my_command_habits"
	m.hk.begin_capture(id)
	await key(KEY_K, true, true)
	ok(m.hk.scoped.resolve("Ctrl+Alt+K", "sculpt") == id and m.hk.scoped.resolve("Ctrl+Alt+K", "animate") == "", "EDITOR with sculpt chosen the captured key binds on sculpt only")
	dd.select(0)
	dd.item_selected.emit(0)
	await idle(1)
	m.hk.close_editor()


func save_bars() -> void:
	m.hk.scoped.bind(KJ, XID)
	m.hk.scoped.bind(KJ, YID, "sculpt")
	var ws: WorkLayouts = m.bld.shell.ws
	m._page_set("MODEL", false)
	await idle(2)
	moved_final = rect_of(m, "part", "browser")
	m._page_set("ANIMATE", false)
	await idle(2)
	var runs_before: int = m.hk.learn.runs("scene_hide_cost_per_character")
	m._pw_save()
	m.queue_free()
	await idle(6)
	m = await boot()
	ok(m.hk.scoped.resolve(KJ, "sculpt") == YID and m.hk.scoped.resolve(KJ, "animate") == XID, "SAVE the scoped bindings are back after a restart")
	ok(m.hk.scoped.resolve("Ctrl+Alt+K", "sculpt") == "help_forget_my_command_habits", "SAVE the editor's binding is back too")
	ok(m.hk.learn.is_dismissed("scene_hide_cost_per_character") and m.hk.learn.is_dismissed("scene_show_cost_per_character"), "SAVE the dismissals are back")
	ok(m.hk.learn.runs("scene_hide_cost_per_character") >= runs_before and runs_before >= 20, "SAVE the run counts are back (%d)" % m.hk.learn.runs("scene_hide_cost_per_character"))
	m.bld.shell.ws.reset()
	m._page_set("ANIMATE", false)
	await idle(2)
	m._page_set("MODEL", false)
	await idle(2)
	var back := rect_of(m, "part", "browser")
	ok(close_to(back, moved_final), "SAVE the model page layout is back within 1 px (%s vs %s)" % [back, moved_final])
	m.hk.scoped.items.clear()
	await palette_run("hide cost per character", 10)
	ok(toast() == null, "SAVE 10 more runs in the fresh app: no toast for a dismissed command")
