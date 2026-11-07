class_name LearnKeys
extends Node
## P18 LEARN-FROM-ME HOTKEYS (the live half; the counting file is scripts/cmd_learn.gd, kept in Hotkeys.learn).
## Every command the user runs from the S box (ui_cmd.ran) is counted. At THRESHOLD runs a command that has no key anywhere is OFFERED
## the first free key in a small panel (Bind it / No thanks). Accept binds through Hotkeys.set_key (so a real key event then runs it);
## decline is remembered for good (the dismissed list of the learn file) and for this session. A command that already has a key is never offered.
## Runs from a key do not count: this learns what the user reaches for by hand. Tests: tests/learnkeys_test.gd.

const THRESHOLD := 5   # runs from the box before the offer; fixed here, not tuned after a run
## keys main.gd matches by hand (not in the command registry): never offered
const FIXED := ["Esc", "Alt+E", "Shift+Alt+E", "Ctrl+Alt+Q", "Alt+1", "Alt+2", "Alt+3", "Alt+4", "Alt+5"]
const SHOW_SECONDS := 25.0

var m
var declined := {}   # command id -> true, this session
var offer := {}      # {id, name, key} while the panel is up
var panel: PanelContainer
var label: Label


func _init(main = null) -> void:
	m = main
	name = "learn_keys"


## main calls this once the S box exists
func attach() -> void:
	if m != null and m.ui_cmd != null and not m.ui_cmd.ran.is_connected(_ran):
		m.ui_cmd.ran.connect(_ran)


static func is_free(cmds: Array, scoped: PageKeys, combo: String) -> bool:
	if combo == "" or combo in FIXED or combo in Hotkeys.RESERVED:
		return false
	if not Hotkeys.holder(cmds, combo).is_empty() or not Hotkeys.built_in(cmds, combo).is_empty():
		return false
	return not scoped.has_key(combo)


static func first_free(cmds: Array, scoped: PageKeys) -> String:
	for pre in ["Alt+", "Ctrl+Alt+"]:
		for ch in "ABCDEFGHIJKLMNOPQRSTUVWXYZ":
			if is_free(cmds, scoped, pre + ch):
				return pre + ch
	return ""


func runs(id: String) -> int:
	return m.hk.learn.runs(id)


func _cmd(id: String) -> Dictionary:
	for c in m.ui_cmd.commands:
		if String(c["id"]) == id:
			return c
	return {}


func would_offer(id: String) -> bool:
	var c := _cmd(id)
	return (not c.is_empty() and String(c["keys"]) == "" and runs(id) >= THRESHOLD and not m.hk.scoped.has_cmd(id)
		and not m.hk.learn.is_dismissed(id) and not declined.has(id))


func _ran(nm: String) -> void:
	for c in m.ui_cmd.commands:
		if String(c["name"]) == nm:
			var id := String(c["id"])
			# counted once by main._learn_after (L108), which every S-box run already passes through
			m.hk.learn.save_file()
			if offer.is_empty() and would_offer(id):
				var key := first_free(m.ui_cmd.commands, m.hk.scoped)
				if key != "":
					_show({"id": id, "name": nm, "key": key})
			return


func offer_id() -> String:
	return String(offer.get("id", ""))


func offer_key() -> String:
	return String(offer.get("key", ""))


func panel_visible() -> bool:
	return panel != null and panel.visible


func _show(o: Dictionary) -> void:
	offer = o
	if panel == null:
		panel = PanelContainer.new()
		panel.name = "learn_offer"
		var v := HBoxContainer.new()
		panel.add_child(v)
		label = Label.new()
		v.add_child(label)
		var yes := Button.new()
		yes.name = "learn_yes"
		yes.text = "Bind it"
		yes.pressed.connect(accept)
		v.add_child(yes)
		var no := Button.new()
		no.name = "learn_no"
		no.text = "No thanks"
		no.pressed.connect(decline)
		v.add_child(no)
		m.ui_root.add_child(panel)
		panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		panel.position += Vector2(16, -64)
	label.text = "You run \"%s\" a lot (%d times). Give it %s?  " % [o["name"], runs(String(o["id"])), o["key"]]
	panel.visible = true
	var id: String = o["id"]
	get_tree().create_timer(SHOW_SECONDS).timeout.connect(func():
		if offer_id() == id:
			_clear())   # ignored: the panel goes, nothing is remembered, it may come back on a later run


func _clear() -> void:
	offer = {}
	if panel != null:
		panel.visible = false


func accept() -> Dictionary:
	if offer.is_empty():
		return {"ok": false, "msg": "no offer"}
	var r: Dictionary = m.hk.set_key(String(offer["id"]), String(offer["key"]))
	if r.get("ok", false):
		_clear()
	return r


func decline() -> void:
	if offer.is_empty():
		return
	declined[offer["id"]] = true
	m.hk.learn.dismiss(String(offer["id"]))
	_clear()


func save() -> bool:
	return m.hk.learn.save_file()
