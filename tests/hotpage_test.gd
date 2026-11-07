extends SceneTree
## godot --headless --path . -s tests/hotpage_test.gd   (lane L113: ROADMAP_400 P06, customisable hotkeys PER PAGE, wired into Hotkeys)
## Bars written BEFORE the code (Hotkeys.set_page_key / clear_page_key, scoped keys saved beside the config and read by load_from).
## A stub poser (cur_page, ui_cmd.commands, _commands, settings) and a real Hotkeys; keys are real InputEventKey pushed through the viewport.
##   RUN      "J" bound to cmd_a on ANIMATE and cmd_b on STAGE, "J" global (registry) = cmd_c. Switch page, press J: animate runs a, stage runs b,
##            pose (no override) falls back to c. Run log must equal [a, b, c] exactly.
##   NONE     a key with no binding anywhere runs nothing on any page.
##   CONFLICT a second command on J on ANIMATE is refused with conflict=cmd_a, J on animate still runs a; confirm=true moves it (b/c no longer a).
##   SAVE     save, build a new Hotkeys + stub, load_from(the same config): to_json identical and the same key presses run the same commands.
##   OLD      a config with only [hotkeys] (no page file) and a schema-1 json profile both load; the global key runs on every page.
##   PLANT    after clear_page_key the animate press runs c, not a: the log comparison used above detects a changed binding.
## Only user:// is written (wtest gives each run its own APPDATA).

var fails := 0
var log_: Array = []


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


class Cmds:
	extends RefCounted
	var commands: Array = []


class Stub:
	extends RefCounted
	var cur_page := "POSE"
	var ui_cmd := Cmds.new()
	var settings := ""
	var _step_hint := ""
	var hk: Hotkeys
	var log_: Array

	func _init(cfg: String, lg: Array) -> void:
		settings = cfg
		log_ = lg
		ui_cmd.commands = Hotkeys.apply(_build(), {})

	func _build() -> Array:
		var out := []
		for p in [["cmd_a", "F5"], ["cmd_b", "F6"], ["cmd_c", "F7"]]:
			var id: String = p[0]
			out.append({"id": id, "name": id, "keys": p[1], "run": func(): log_.append(id)})
		return out

	func _commands() -> Array:
		return Hotkeys.apply(_build(), hk.over if hk != null else {})


class Feeder:
	extends Node
	var hk: Hotkeys

	func _input(ev: InputEvent) -> void:
		if ev is InputEventKey and ev.pressed:
			hk.dispatch(ev)


var feeder: Feeder


func press(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	root.push_input(e)
	await process_frame


func make(cfg: String) -> Array:   # [stub, hk]
	var s := Stub.new(cfg, log_)
	var h := Hotkeys.new(s)
	s.hk = h
	feeder.hk = h
	return [s, h]


func _initialize() -> void:
	feeder = Feeder.new()
	root.add_child(feeder)
	DirAccess.make_dir_recursive_absolute("user://hotpage")
	for f in ["a.cfg", "kine_pagekeys.json", "old/poser.cfg", "old/kine_pagekeys.json"]:
		if FileAccess.file_exists("user://hotpage/" + f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://hotpage/" + f))
	run.call_deferred()


func run() -> void:
	var cfg := "user://hotpage/a.cfg"
	var sh := make(cfg)
	var s: Stub = sh[0]
	var h: Hotkeys = sh[1]
	ok(h.set_key("cmd_c", "J")["ok"], "RUN global J -> cmd_c")
	ok(h.set_page_key("cmd_a", "J", "ANIMATE")["ok"], "RUN J on ANIMATE -> cmd_a")
	ok(h.set_page_key("cmd_b", "J", "STAGE")["ok"], "RUN J on STAGE -> cmd_b")
	log_.clear()
	for pg in ["ANIMATE", "STAGE", "POSE"]:
		s.cur_page = pg
		await press(KEY_J)
	ok(log_ == ["cmd_a", "cmd_b", "cmd_c"], "RUN per page + fallback log = %s" % str(log_))
	log_.clear()
	for pg in ["ANIMATE", "STAGE", "POSE"]:
		s.cur_page = pg
		await press(KEY_Q)
	ok(log_.is_empty(), "NONE an unbound key runs nothing (log %s)" % str(log_))
	s.cur_page = "ANIMATE"
	var r := h.set_page_key("cmd_b", "J", "ANIMATE")
	ok(not r["ok"] and r.get("conflict", "") == "cmd_a", "CONFLICT reported on the same page (conflict=%s)" % r.get("conflict", "none"))
	log_.clear()
	await press(KEY_J)
	ok(log_ == ["cmd_a"], "CONFLICT refused bind did not overwrite (log %s)" % str(log_))
	var js := h.scoped.to_json()
	# SAVE round trip (before the confirmed move)
	var sh2 := make(cfg)
	var s2: Stub = sh2[0]
	var h2: Hotkeys = sh2[1]
	h2.load_from(cfg)
	s2.ui_cmd.commands = s2._commands()   # main builds its registry after load_from
	ok(h2.scoped.to_json() == js, "SAVE reload from disk: bindings byte-identical (%d bytes)" % js.length())
	log_.clear()
	for pg in ["ANIMATE", "STAGE", "POSE"]:
		s2.cur_page = pg
		await press(KEY_J)
	ok(log_ == ["cmd_a", "cmd_b", "cmd_c"], "SAVE reloaded keys run the same commands (log %s)" % str(log_))
	ok(h2.over.get("cmd_c", "") == "J", "SAVE the global override still loads too")
	# confirm moves
	s2.cur_page = "ANIMATE"
	ok(h2.set_page_key("cmd_b", "J", "ANIMATE", true)["ok"], "CONFLICT confirm=true moves the key")
	log_.clear()
	await press(KEY_J)
	ok(log_ == ["cmd_b"], "CONFLICT after the move animate runs cmd_b (log %s)" % str(log_))
	# PLANT
	ok(h2.clear_page_key("cmd_b", "ANIMATE"), "PLANT clear the animate binding")
	log_.clear()
	await press(KEY_J)
	ok(log_ == ["cmd_c"] and log_ != ["cmd_a"], "PLANT animate now falls to the global cmd_c, so a changed binding is detected (log %s)" % str(log_))
	# OLD files
	DirAccess.make_dir_recursive_absolute("user://hotpage/old")
	var cf := ConfigFile.new()
	cf.set_value("hotkeys", "cmd_c", "K")
	cf.save("user://hotpage/old/poser.cfg")
	var sh3 := make("user://hotpage/old/poser.cfg")
	sh3[1].load_from("user://hotpage/old/poser.cfg")
	sh3[0].ui_cmd.commands = sh3[0]._commands()
	var all_ok := true
	log_.clear()
	for pg in ["ANIMATE", "STAGE", "POSE", "MODEL"]:
		sh3[0].cur_page = pg
		await press(KEY_K)
	ok(log_ == ["cmd_c", "cmd_c", "cmd_c", "cmd_c"], "OLD global-only config: K runs cmd_c on every page (log %s)" % str(log_))
	var f := FileAccess.open("user://hotpage/old/kine_pagekeys.json", FileAccess.WRITE)
	f.store_string(Hotkeys.to_json({"cmd_a": "L"}))
	f.close()
	var sh4 := make("user://hotpage/old/poser.cfg")
	sh4[1].load_from("user://hotpage/old/poser.cfg")
	sh4[0].ui_cmd.commands = sh4[0]._commands()
	log_.clear()
	for pg in ["ANIMATE", "POSE"]:
		sh4[0].cur_page = pg
		await press(KEY_L)
	ok(log_ == ["cmd_a", "cmd_a"], "OLD schema-1 profile loads as global (log %s)" % str(log_))
	feeder.queue_free()
	print("hotpage: %d fail" % fails)
	quit(1 if fails > 0 else 0)
