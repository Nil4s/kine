class_name KeymapTranslate
extends RefCounted
## "COMING FROM BLENDER / MAYA" (docs/ROADMAP_400.md P20). A helper mode: while it is on, pressing a Blender (or Maya) key
## that Kine does not use the same way shows a toast naming Kine's own key for it ("In Blender, I inserts a keyframe -
## in Kine that's K (Key the part here)") and offers to run the Kine command (Shift+Enter within OFFER_T).
## - the tables below map each key to a Kine command ID looked up in the REAL registry (main._commands()); "" = Kine has
##   no equivalent yet, and the toast says exactly that. "@search" is the S box (hard-wired in main, not a registry row).
## - a key Kine already uses for something else shows the toast but does not block Kine's action, unless the sub-option
##   "Blender keys win" is on: then the mapped Kine command runs instead (and the key is consumed).
## - the mode is remembered in the settings file ([look] keytrans = "", "blender" or "maya"; keytrans_wins).
## Key lists are the common Blender 4.x / Maya animation and viewport defaults written from their public manuals; no code
## from either program. Tests: tests/keytrans_test.gd.

const CFG := "look"
const OFFER_T := 7.0
const SEARCH := "@search"   # the S box: a key in main's own match, not a command row
const MODIFIERS := [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]

## [combo as Hotkeys.combo_of writes it (numpad = "Num1"), what that key does there, Kine command id, note]
const BLENDER := [
	["I", "inserts a keyframe", "key_the_part_here", ""],
	["Alt+I", "deletes the keyframe", "cards_delete_the_selected", "it deletes the picked cards"],
	["K", "opens the keying set menu", "keying_set_use_the_picked_set_for_k", ""],
	["G", "grabs (moves) the selection", "", "drag the part in the view"],
	["R", "rotates the selection", "", "drag the part in the view"],
	["S", "scales the selection", "", ""],
	["Alt+G", "clears the location", "reset_the_part", ""],
	["Alt+R", "clears the rotation", "reset_the_part", ""],
	["Alt+S", "clears the scale", "reset_the_part", ""],
	["Shift+D", "duplicates", "cards_copy_the_selected", "then paste after the current card"],
	["Num1", "shows the front view", "front_view", ""],
	["Ctrl+Num1", "shows the back view", "back_view", ""],
	["Num3", "shows the right view", "his_right_view", ""],
	["Ctrl+Num3", "shows the left view", "his_left_view", ""],
	["Num7", "shows the top view", "top_view", ""],
	["Num0", "looks through the camera", "camera_look_through_the_shot_camera", ""],
	["Space", "plays and pauses", "play_pause", ""],
	["Shift+Left", "jumps to the first frame", "", ""],
	["Shift+Right", "jumps to the last frame", "", ""],
	["Up", "jumps to the next keyframe", "", ""],
	["Down", "jumps to the previous keyframe", "", ""],
	["Ctrl+Space", "maximises the area", "big_view_hide_the_panels", ""],
	["Tab", "toggles edit mode", "", ""],
	["H", "hides the selection", "", ""],
	["Alt+H", "unhides everything", "", ""],
	["N", "toggles the sidebar", "", ""],
	["T", "toggles the toolbar", "", ""],
	["Shift+A", "opens the add menu", "", ""],
	["Ctrl+Z", "undoes", "undo", ""],
	["Ctrl+Shift+Z", "redoes", "redo", ""],
	["F3", "opens the operator search", SEARCH, ""],
	["Home", "frames everything in the view", "", ""],
	["Num.", "frames the selection in the view", "", ""],
	["Z", "opens the shading pie", "shading_next", ""],
	["Ctrl+S", "saves the file", "save_scene", ""],
	["Ctrl+N", "starts a new file", "new_empty_scene", ""],
	["M", "adds a marker (timeline)", "add_marker_at_the_playhead", ""],
	["Ctrl+M", "mirrors", "mirror_the_whole_pose", ""],
	["F12", "renders the animation", "render_shots_to_video_mp4", ""],
	["B", "box-selects", "", ""],
	["C", "circle-selects", "", ""],
	["X", "deletes", "cards_delete_the_selected", "it deletes the picked cards"],
	["Ctrl+C", "copies the pose", "copy_pose", ""],
	["Ctrl+V", "pastes the pose", "paste_pose", ""],
	["Ctrl+Shift+V", "pastes the pose flipped", "paste_pose_mirrored", ""],
	["Left", "steps one frame back", "", ""],
	["Right", "steps one frame on", "", ""],
]

const MAYA := [
	["S", "sets a key", "key_the_part_here", ""],
	["Shift+W", "keys the translate channels", "key_the_part_here", "it keys the whole pose of the part"],
	["Shift+E", "keys the rotate channels", "key_the_part_here", "it keys the whole pose of the part"],
	["Shift+R", "keys the scale channels", "key_the_part_here", "it keys the whole pose of the part"],
	["W", "is the Move tool", "", "drag the part in the view"],
	["E", "is the Rotate tool", "", "drag the part in the view"],
	["R", "is the Scale tool", "", ""],
	["F", "frames the selection", "", ""],
	["A", "frames everything", "", ""],
	["4", "shows wireframe", "shading_next", ""],
	["5", "shows shaded", "shading_next", ""],
	["6", "shows textured", "shading_next", ""],
	["Alt+drag", "orbits the view", "", "right-drag turns around the body"],
	[",", "goes to the previous key", "", ""],
	[".", "goes to the next key", "", ""],
	["Alt+V", "plays and stops", "play_pause", ""],
	["Space", "opens the hotbox", SEARCH, ""],
	["Ctrl+G", "groups the selection", "selection_set_new_from_the_selected_parts", ""],
	["Ctrl+D", "duplicates", "cards_copy_the_selected", "then paste after the current card"],
	["Insert", "edits the pivot", "", ""],
	["Z", "undoes", "undo", ""],
	["Shift+Z", "redoes", "redo", ""],
	["Ctrl+Z", "undoes", "undo", ""],
	["Ctrl+S", "saves the scene", "save_scene", ""],
	["Ctrl+N", "starts a new scene", "new_empty_scene", ""],
	["Delete", "deletes", "cards_delete_the_selected", "it deletes the picked cards"],
	["Ctrl+C", "copies", "copy_pose", ""],
	["Ctrl+V", "pastes", "paste_pose", ""],
	["Ctrl+H", "hides the selection", "", ""],
]

var m                      # the poser (main.gd)
var mode := ""             # "", "blender" or "maya"
var wins := false          # "Blender keys win": the mapped Kine command runs instead of the key Kine has there
var toast: Label
var offered := ""          # the Kine command id the toast offers (Shift+Enter runs it)
var offer_until := 0
var last_text := ""
var _gen := 0


func _init(main) -> void:
	m = main


# ---- the tables (pure) ---------------------------------------------------------------------------------------------

static func table(which: String) -> Array:
	return BLENDER if which == "blender" else MAYA if which == "maya" else []


static func name_of(which: String) -> String:
	return "Blender" if which == "blender" else "Maya"


static func combo_of(k: InputEventKey) -> String:
	if k.keycode == 0 or k.keycode in MODIFIERS:
		return ""
	var base := ""
	if k.keycode >= KEY_KP_0 and k.keycode <= KEY_KP_9:
		base = "Num%d" % (k.keycode - KEY_KP_0)
	elif k.keycode == KEY_KP_PERIOD:
		base = "Num."
	else:
		base = Hotkeys.key_name(k.keycode)
	return ("Ctrl+" if k.ctrl_pressed else "") + ("Shift+" if k.shift_pressed else "") + ("Alt+" if k.alt_pressed else "") + base


static func entry_for(which: String, combo: String) -> Array:
	for e in table(which):
		if String(e[0]) == combo:
			return e
	return []


## every Kine command id the tables name that is not in the registry (SEARCH is checked by the test with a real S)
static func dangling(cmds: Array) -> Array:
	var ids := {}
	for c in cmds:
		ids[String(c["id"])] = true
	var out := []
	for which in ["blender", "maya"]:
		for e in table(which):
			var id := String(e[2])
			if id != "" and id != SEARCH and not ids.has(id):
				out.append("%s %s -> %s" % [which, e[0], id])
	return out


static func command(cmds: Array, id: String) -> Dictionary:
	for c in cmds:
		if String(c["id"]) == id:
			return c
	return {}


## who has this key in Kine now: a registry command, or the S box ("" = nobody)
static func holder_id(cmds: Array, combo: String) -> String:
	var c := Hotkeys.holder(cmds, combo)
	if not c.is_empty():
		return String(c["id"])
	return SEARCH if combo == "S" else ""


## the toast for one key; "" = Kine already does the same thing on that key, say nothing
static func text_for(which: String, combo: String, cmds: Array) -> String:
	var e := entry_for(which, combo)
	if e.is_empty():
		return ""
	var tid := String(e[2])
	var held := holder_id(cmds, combo)
	if tid != "" and held == tid:
		return ""
	var s := "In %s, %s %s" % [name_of(which), combo, e[1]]
	if tid == "":
		s += " - Kine has no equivalent yet"
		if String(e[3]) != "":
			s += " (%s)" % e[3]
	elif tid == SEARCH:
		s += " - in Kine that's S (Command search: type what you want)"
	else:
		var c := command(cmds, tid)
		var key := String(c.get("keys", ""))
		s += " - in Kine that's %s (%s)" % [key if key != "" else "the command", c.get("name", tid)]
		if key == "":
			s += ", no key yet: search it with S"
		if String(e[3]) != "":
			s += "; " + String(e[3])
	if held != "":
		var hn := "Command search" if held == SEARCH else String(command(cmds, held).get("name", held))
		s += "\nKine's own %s here is '%s'" % [combo, hn]
	return s


# ---- the mode, in the app ------------------------------------------------------------------------------------------

func load_from(path: String) -> void:
	var cf := ConfigFile.new()
	if cf.load(path) == OK:
		mode = String(cf.get_value(CFG, "keytrans", ""))
		wins = bool(cf.get_value(CFG, "keytrans_wins", false))
	if mode != "blender" and mode != "maya":
		mode = ""


func set_mode(which: String, save := true) -> void:
	mode = which if which in ["blender", "maya"] else ""
	if mode == "":
		hide_toast()
	if save:
		_save()
	m._say_plain("Keys: helper off" if mode == "" else "Coming from %s: pressing one of its keys that Kine uses differently shows Kine's own key (Shift+Enter runs it)" % name_of(mode))


func set_wins(on: bool, save := true) -> void:
	wins = on
	if save:
		_save()
	m._say_plain("Blender/Maya keys win: a key Kine uses differently runs the Kine command it maps to (the helper must be on)" if on else "Kine keys win again: the toast shows, the key does what Kine's key does")


func _save() -> void:
	var cf := ConfigFile.new()
	cf.load(m.settings)
	cf.set_value(CFG, "keytrans", mode)
	cf.set_value(CFG, "keytrans_wins", wins)
	cf.save(m.settings)


## main's key handler calls this first; true = the key is consumed (Shift+Enter on an offer, or a winning key)
func key(k: InputEventKey) -> bool:
	if mode == "" or m._pressing:   # a key main synthesises to run a command (_press) is not the user's key
		return false
	if offered != "" and Time.get_ticks_msec() < offer_until and k.keycode in [KEY_ENTER, KEY_KP_ENTER] and k.shift_pressed and not k.ctrl_pressed and not k.alt_pressed:
		var id := offered
		hide_toast()
		return run(id)
	var combo := combo_of(k)
	if combo == "":
		return false
	var t := text_for(mode, combo, m.ui_cmd.commands)
	if t == "":
		return false
	var e := entry_for(mode, combo)
	var tid := String(e[2])
	var offer := tid != "" and tid != SEARCH
	show_toast(t + ("\nShift+Enter runs it now" if offer else ""), tid if tid != "" else "")
	if wins and tid != "" and holder_id(m.ui_cmd.commands, combo) != "":
		return run(tid)
	return false


func run(id: String) -> bool:
	if id == SEARCH:
		m.ui_cmd.open()
		return true
	var c := command(m.ui_cmd.commands, id)
	if c.is_empty():
		return false
	m._step_hint = String(c["name"])
	(c["run"] as Callable).call()
	return true


func show_toast(t: String, offer_id := "") -> void:
	if m.ui_root == null:
		return
	last_text = t
	offered = offer_id if offer_id != SEARCH else ""
	offer_until = Time.get_ticks_msec() + int(OFFER_T * 1000.0)
	if toast == null:
		toast = Label.new()
		toast.name = "keytrans_toast"
		toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
		toast.add_theme_font_size_override("font_size", 17)
		toast.add_theme_color_override("font_color", Tok.c("say"))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Tok.c("say_bg")
		sb.set_corner_radius_all(8)
		sb.set_content_margin_all(10)
		toast.add_theme_stylebox_override("normal", sb)
		m.ui_root.add_child(toast)
	toast.text = t
	toast.visible = true
	toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	toast.position.y = 150
	_gen += 1
	var g := _gen
	m.get_tree().create_timer(OFFER_T).timeout.connect(func():
		if g == _gen:
			hide_toast())


func hide_toast() -> void:
	offered = ""
	last_text = ""
	if toast != null and is_instance_valid(toast):
		toast.visible = false
