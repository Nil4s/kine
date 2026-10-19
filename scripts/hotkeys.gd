class_name Hotkeys
extends RefCounted
## HOTKEYS (docs/ROADMAP.md item 5). Every command in main._commands() that has a key can be rebound.
## - combo_of(event) writes a key the way the registry does ("Ctrl+Shift+S", "Shift+M", "?", "Enter", "Esc").
## - over maps command id -> its key ("" = unbound), applied to the registry by apply(). It is saved under [hotkeys]
##   in the poser's config (the same file as the theme and the scale) and read back at start.
## - dispatch(event) runs a rebound command from main's key handler. A built-in key whose command moved away does
##   nothing ("stolen"); a built-in key that still belongs to its command falls through to main's own match, as before.
## - the cheat sheet (?) is grouped by area (AREA_OF). Holding ? shows it; releasing ? hides it.
## - the editor (Help: edit hotkeys): a search box and one row per command. Click a row, press the key. A key another
##   command has is refused until the same key is pressed again (then that command loses it). Reset clears every change.
## main.gd holds the call sites only. Tests: tests/hotkeys_test.gd (a temp config, never poser.cfg).

const SECTION := "hotkeys"
const RESERVED := ["Esc"]   # closes the panels wherever they are: never rebound
const EVERY_KEY := "every_key_on_one_screen"   # the cheat sheet: held by its key, shown while it is down
const AREAS := ["Pose", "Timeline", "Keys", "Weapon", "View", "File", "Edit", "Help", "Other"]
const AREA_OF := {
	"reset_the_part": "Pose", "snap_the_part_to_90": "Pose", "snap_the_part_to_45": "Pose",
	"copy_right_side_to_left": "Pose", "copy_left_side_to_right": "Pose", "mirror_the_whole_pose": "Pose",
	"copy_pose": "Pose", "paste_pose": "Pose", "paste_pose_mirrored": "Pose", "fingers_next_shape": "Pose",
	"play_pause": "Timeline", "clip_this_pose_add_a_card": "Timeline", "next_marker": "Timeline", "previous_marker": "Timeline",
	"key_the_part_here": "Keys", "breakdowner_slider": "Keys", "push_from_the_in-between": "Keys",
	"relax_to_the_in-between": "Keys", "blend_to_previous_card": "Keys",
	"weapon_in_right_hand": "Weapon", "lock_weapon_to_hand_free_it": "Weapon", "second_hand_on_the_weapon": "Weapon",
	"grip_lower_on_the_weapon": "Weapon", "grip_higher_on_the_weapon": "Weapon", "slide_the_hands_down_the_weapon": "Weapon",
	"slide_the_hands_up_the_weapon": "Weapon", "weapon_shorter": "Weapon", "weapon_longer": "Weapon",
	"front_view": "View", "his_right_view": "View", "top_view": "View", "back_view": "View", "his_left_view": "View",
	"page_pose": "View", "page_animate": "View", "page_stage": "View", "page_check": "View", "page_deliver": "View",
	"big_view_hide_the_panels": "View", "collision_shapes_on_off": "View", "motion_trail_on_off": "View",
	"pin_a_trail_on_the_picked_part": "View", "balance_on_off": "View", "onion_skin_on_off": "View",
	"spacing_ghosts_on_off": "View", "speed_graph_on_off": "View", "dummy_on_off": "View",
	"save_pose": "File", "save_scene": "File",
	"undo": "Edit", "redo": "Edit",
	"every_key_on_one_screen": "Help", "keyboard_the_panels_by_keys": "Help", "help_edit_hotkeys": "Help",
}
const KEY_NAMES := {
	KEY_BRACKETLEFT: "[", KEY_BRACKETRIGHT: "]", KEY_COMMA: ",", KEY_PERIOD: ".", KEY_MINUS: "-", KEY_EQUAL: "=",
	KEY_ESCAPE: "Esc",
}
const MODIFIERS := [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]

var m                       # the poser (main.gd, untyped: its helpers are main's own)
var over := {}              # command id -> key ("" = unbound), only where it differs from the built-in key
var capture := ""           # the command id waiting for its new key ("" = not editing a key)
var pending := ""           # a key that conflicted: the same key again moves it
var synth := ""             # the built-in key of the command being run from a key: main's own match runs it
var hold := -1              # keycode of the ? that is down (the cheat sheet hides when it is released)
var ui: PanelContainer      # the editor (built on first open)
var search: LineEdit
var rows: VBoxContainer
var status: Label


func _init(main) -> void:
	m = main


# ---- keys as text -------------------------------------------------------------------------------------------------

static func combo_of(k: InputEventKey) -> String:
	if k.unicode == 63 and not k.ctrl_pressed and not k.alt_pressed:   # "?" by the character, on any layout
		return "?"
	if k.keycode == 0:
		return ""
	var s := ""
	if k.ctrl_pressed:
		s += "Ctrl+"
	if k.shift_pressed:
		s += "Shift+"
	if k.alt_pressed:
		s += "Alt+"
	return s + key_name(k.keycode)


static func key_name(code: int) -> String:
	if KEY_NAMES.has(code):
		return KEY_NAMES[code]
	return OS.get_keycode_string(code)


static func area_of(c: Dictionary) -> String:
	return AREA_OF.get(String(c["id"]), "Other")


# ---- the registry with the overrides applied (pure, so the test can call it) ------------------------------------

## every command gets its built-in key in "default" and its effective key in "keys"
static func apply(cmds: Array, overrides: Dictionary) -> Array:
	for c in cmds:
		c["default"] = String(c["keys"])
		if overrides.has(c["id"]):
			c["keys"] = String(overrides[c["id"]])
	return cmds


static func holder(cmds: Array, combo: String) -> Dictionary:
	if combo == "":
		return {}
	for c in cmds:
		if String(c["keys"]) == combo:
			return c
	return {}


static func built_in(cmds: Array, combo: String) -> Dictionary:
	if combo == "":
		return {}
	for c in cmds:
		if String(c.get("default", c["keys"])) == combo:
			return c
	return {}


## the cheat sheet's groups: [[area, [command, ...]], ...] for every command that has a key, in AREAS order
static func cheat_groups(cmds: Array) -> Array:
	var out := []
	for a in AREAS:
		var rows_a := cmds.filter(func(c): return String(c["keys"]) != "" and area_of(c) == a)
		if not rows_a.is_empty():
			out.append([a, rows_a])
	return out


# ---- the config file -----------------------------------------------------------------------------------------------

func load_from(path: String) -> void:
	over = {}
	var cf := ConfigFile.new()
	if cf.load(path) != OK or not cf.has_section(SECTION):
		return
	for key in cf.get_section_keys(SECTION):
		over[key] = String(cf.get_value(SECTION, key, ""))


func save_to(path: String) -> void:
	var cf := ConfigFile.new()
	cf.load(path)   # keeps the poser's other sections (theme, scale, ...)
	cf.erase_section(SECTION)
	for key in over:
		cf.set_value(SECTION, key, over[key])
	cf.save(path)


# ---- changing a key -------------------------------------------------------------------------------------------------

## the one way a key changes. Returns {ok, msg} or, when another command holds the key and confirm is false,
## {ok: false, conflict: <its id>, msg}. A confirmed move leaves the other command with no key.
func set_key(id: String, combo: String, confirm := false) -> Dictionary:
	var cmds: Array = m.ui_cmd.commands
	var c := _find(cmds, id)
	if c.is_empty():
		return {"ok": false, "msg": "no command called %s" % id}
	if combo in RESERVED:
		return {"ok": false, "msg": "%s is fixed: it closes the panels, so it cannot be bound" % combo}
	var other := holder(cmds, combo)
	var took := ""
	if not other.is_empty() and String(other["id"]) != id:
		if not confirm:
			return {"ok": false, "conflict": String(other["id"]),
				"msg": "%s is %s's key. Press %s again to move it (%s then has no key), or pick another" % [combo, other["name"], combo, other["name"]]}
		_put(String(other["id"]), "", cmds)
		took = String(other["name"])
	_put(id, combo, cmds)
	refresh()
	var msg := ("%s is now %s" % [c["name"], combo if combo != "" else "(no key)"])
	if took != "":
		msg += "; %s has no key now" % took
	return {"ok": true, "msg": msg}


func reset_all() -> void:
	over.clear()
	pending = ""
	capture = ""
	refresh()
	if status != null:
		status.text = "back to the built-in keys"


func _put(id: String, combo: String, cmds: Array) -> void:
	var c := _find(cmds, id)
	if c.is_empty():
		return
	if combo == String(c["default"]):
		over.erase(id)
	else:
		over[id] = combo
	c["keys"] = combo


func _find(cmds: Array, id: String) -> Dictionary:
	for c in cmds:
		if String(c["id"]) == id:
			return c
	return {}


## rebuild the registry from the overrides, save them, and redraw the editor
func refresh() -> void:
	m.ui_cmd.commands = m._commands()
	save_to(m.settings)
	if ui != null and ui.visible:
		rebuild_rows()


# ---- keys in the poser ----------------------------------------------------------------------------------------------

## main's key handler, first: true when the key was a command's (main stops there)
func dispatch(k: InputEventKey) -> bool:
	var combo := combo_of(k)
	if combo == "" or combo == synth:
		return false
	var cmds: Array = m.ui_cmd.commands
	var c := holder(cmds, combo)
	if c.is_empty():
		return not built_in(cmds, combo).is_empty()   # its key moved away or was unbound: the built-in key does nothing
	if String(c["id"]) == EVERY_KEY:
		m.keys_overlay(true)
		hold = k.keycode
		return true
	if String(c.get("default", c["keys"])) == combo:
		return false   # still its own key: main's own match runs it, as it always did
	m._step_hint = String(c["name"])
	synth = String(c.get("default", c["keys"]))
	(c["run"] as Callable).call()
	synth = ""
	return true


## main's key handler for a release: the cheat sheet hides when its ? comes up
func released(k: InputEventKey) -> void:
	if hold >= 0 and k.keycode == hold:
		hold = -1
		m.keys_overlay(false)


## main's _input: true when the editor took the event (a key for a row being edited, or Esc closing the editor)
func take_input(ev: InputEvent) -> bool:
	if not (ev is InputEventKey) or not ev.pressed or (ev as InputEventKey).echo:
		return false
	var k := ev as InputEventKey
	if capture != "":
		if k.keycode == KEY_ESCAPE:
			capture = ""
			pending = ""
			status.text = "cancelled: the key is unchanged"
		elif not k.keycode in MODIFIERS:
			_capture_key(k)
		return true
	if ui != null and ui.visible and k.keycode == KEY_ESCAPE:
		close_editor()
		return true
	return false


func _capture_key(k: InputEventKey) -> void:
	var combo := combo_of(k)
	var id := capture
	var r := set_key(id, combo, combo == pending and combo != "")
	if r.has("conflict"):
		pending = combo
		status.text = String(r["msg"])
		return
	capture = ""
	pending = ""
	status.text = String(r["msg"])


# ---- the editor -----------------------------------------------------------------------------------------------------

func open_editor() -> void:
	if ui == null:
		ui = PanelContainer.new()
		ui.name = "hotkeys_editor"
		var st := StyleBoxFlat.new()
		st.bg_color = Tok.c("float")
		st.set_corner_radius_all(8)
		st.set_content_margin_all(14)
		ui.add_theme_stylebox_override("panel", st)
		m.ui_root.add_child(ui)
		var v := VBoxContainer.new()
		ui.add_child(v)
		v.add_child(m._label("HOTKEYS  (click a key, then press the new one; Esc cancels or closes this)", 16, "heading"))
		search = LineEdit.new()
		search.name = "hk_search"
		search.placeholder_text = "search commands"
		search.text_changed.connect(func(_t): rebuild_rows())
		v.add_child(search)
		var scr := ScrollContainer.new()
		scr.custom_minimum_size = Vector2(640, 380)
		scr.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		v.add_child(scr)
		rows = VBoxContainer.new()
		rows.custom_minimum_size.x = 620
		scr.add_child(rows)
		status = m._label("", 15, "say")
		v.add_child(status)
		var bar := HBoxContainer.new()
		v.add_child(bar)
		var reset_b := Button.new()
		reset_b.name = "hk_reset"
		reset_b.text = "Reset to defaults"
		reset_b.pressed.connect(reset_all)
		bar.add_child(reset_b)
		var close_b := Button.new()
		close_b.name = "hk_close"
		close_b.text = "Close"
		close_b.pressed.connect(close_editor)
		bar.add_child(close_b)
	ui.visible = true
	rebuild_rows()
	ui.reset_size()
	ui.position = ((m.get_viewport().get_visible_rect().size - ui.size) / 2.0).floor()
	search.grab_focus()


func close_editor() -> void:
	capture = ""
	pending = ""
	if ui != null:
		ui.visible = false


func begin_capture(id: String) -> void:
	capture = id
	pending = ""
	var c := _find(m.ui_cmd.commands, id)
	status.text = "press the new key for %s  (Esc cancels)" % c.get("name", id)


func rebuild_rows() -> void:
	for ch in rows.get_children():
		rows.remove_child(ch)
		ch.queue_free()
	var q := search.text.strip_edges().to_lower()
	for c in m.ui_cmd.commands:
		var text := "%s %s %s" % [c["name"], area_of(c), c["id"]]
		if q != "" and not text.to_lower().contains(q):
			continue
		var row := HBoxContainer.new()
		rows.add_child(row)
		var area: Label = m._label(area_of(c), 14, "text:0.7")
		area.custom_minimum_size.x = 80
		row.add_child(area)
		var nm: Label = m._label(String(c["name"]), 15, "text")
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nm)
		var b := Button.new()
		b.name = "hk_" + String(c["id"])
		b.text = String(c["keys"]) if String(c["keys"]) != "" else "(no key)"
		b.custom_minimum_size.x = 150
		b.pressed.connect(begin_capture.bind(String(c["id"])))
		row.add_child(b)
