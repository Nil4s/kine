## godot --path . -s tests/r9_test.gd     (ROADMAP R9, needs a window: /shot reads the viewport)
## The local HTTP API (scripts/local_api.gd) driven by a real TCP client in this process, as a script on the machine would.
## BARS (stated before measuring):
##  1. off by default: a fresh poser has no listener and the settings file has no [api] on
##  2. GET /describe: >= 50 commands (each with id, name, keys, edits, desc) and a state summary
##  3. POST /run "CLIP this pose": 200, the scene gains exactly 1 card, 1 undo step, and one Ctrl+Z takes it back
##  4. GET /check: 200, JSON with a findings array, must_fix, clean (after a 2nd card is clipped)
##  5. GET /shot: 200, image/png, decodes to the viewport's size
##  6. no token / a wrong token / a browser Origin with a wrong token: 401; Origin with the right token: 200; a foreign Host: 403
##  7. binding: connecting to 127.0.0.1 works; to this machine's other IPv4 address is refused; BIND is "127.0.0.1"
##  8. turning it off closes the port
extends SceneTree

const PORT := 48765
var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## one request over a fresh TCP connection -> {"code", "head", "body": PackedByteArray}; {} if it could not connect
func req(method: String, path: String, headers := {}, body := "", host := "127.0.0.1") -> Dictionary:
	var s := StreamPeerTCP.new()
	if s.connect_to_host(host, PORT) != OK:
		return {}
	var t0 := Time.get_ticks_msec()
	while true:
		s.poll()
		if s.get_status() != StreamPeerTCP.STATUS_CONNECTING:
			break
		if Time.get_ticks_msec() - t0 > 3000:
			return {}
		await process_frame
	if s.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return {}
	var h := {"Host": "127.0.0.1:%d" % PORT}
	h.merge(headers, true)
	var txt := "%s %s HTTP/1.1\r\n" % [method, path]
	for k in h:
		txt += "%s: %s\r\n" % [k, h[k]]
	txt += "Content-Length: %d\r\n\r\n%s" % [body.to_utf8_buffer().size(), body]
	s.put_data(txt.to_utf8_buffer())
	var buf := PackedByteArray()
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 15000:
		s.poll()
		if s.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		var n := s.get_available_bytes()
		if n > 0:
			buf.append_array(s.get_data(n)[1])
		await process_frame
	var end := -1
	for i in range(0, buf.size() - 3):
		if buf[i] == 13 and buf[i + 1] == 10 and buf[i + 2] == 13 and buf[i + 3] == 10:
			end = i
			break
	if end < 0:
		return {}
	var head := buf.slice(0, end).get_string_from_utf8()
	return {"code": int(head.split(" ")[1]), "head": head, "body": buf.slice(end + 4)}


func js(r: Dictionary) -> Dictionary:
	var d: Variant = JSON.parse_string((r.get("body", PackedByteArray()) as PackedByteArray).get_string_from_utf8())
	return d if d is Dictionary else {}


func _init() -> void:
	var M = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(M)
	await process_frame
	await process_frame

	var cf := ConfigFile.new()
	cf.load(M.settings)
	ok(M.api == null or not M.api.running(), "off by default: no listener on a fresh poser")
	ok(not cf.get_value("api", "on", false), "off by default: the settings file has no [api] on")
	ok(LocalApi.BIND == "127.0.0.1" and LocalApi.DEFAULT_PORT == 8765, "bind address %s, default port %d" % [LocalApi.BIND, LocalApi.DEFAULT_PORT])
	var src := FileAccess.get_file_as_string("res://scripts/local_api.gd")
	ok(not src.contains('"0.0.0.0"') and not src.contains('"*"') and src.contains("server.listen(p, BIND)"), "the source listens on BIND only (no 0.0.0.0 / *)")

	ok(M._set_api(true, false, PORT), "turned on at port %d" % PORT)
	var tk: String = M.api.token
	ok(tk.length() == 32, "a 32-hex-char session token (%d)" % tk.length())
	var auth := {"X-Poser-Token": tk}

	# 6. the token
	var r := await req("GET", "/describe")
	ok(r.get("code", 0) == 401, "no token: %s" % r.get("code", "no answer"))
	r = await req("GET", "/describe", {"X-Poser-Token": "0".repeat(32)})
	ok(r.get("code", 0) == 401, "wrong token: %s" % r.get("code", "no answer"))
	r = await req("GET", "/describe", {"Origin": "http://evil.example", "X-Poser-Token": "0".repeat(32)})
	ok(r.get("code", 0) == 401 and js(r).get("error", "").contains("browser"), "browser Origin, wrong token: 401 naming the browser")
	r = await req("GET", "/describe", {"Origin": "http://evil.example"})
	ok(r.get("code", 0) == 401, "browser Origin, no token: 401")
	ok(not String(r.get("head", "")).to_lower().contains("access-control"), "no CORS header is ever sent")
	r = await req("GET", "/describe", {"Origin": "http://localhost:3000", "X-Poser-Token": tk})
	ok(r.get("code", 0) == 200, "Origin with the right token: %s" % r.get("code", "no answer"))
	r = await req("GET", "/describe", {"X-Poser-Token": tk, "Host": "evil.example"})
	ok(r.get("code", 0) == 403, "a foreign Host: %s" % r.get("code", "no answer"))
	r = await req("GET", "/describe", {"Authorization": "Bearer " + tk})
	ok(r.get("code", 0) == 200, "Authorization: Bearer <token> works too")

	# 2. describe
	r = await req("GET", "/describe", auth)
	var d := js(r)
	var cmds: Array = d.get("commands", [])
	ok(r.get("code", 0) == 200 and cmds.size() >= 50, "describe: %d commands (bar >= 50)" % cmds.size())
	ok(cmds.all(func(c): return c.has("id") and c.has("name") and c.has("keys") and c.has("edits") and c.has("desc")), "describe: each command has id, name, keys, edits, desc")
	ok(d.get("state", {}).has("cards") and d.get("state", {}).has("length_s"), "describe: a state summary (cards, length_s)")
	ok(cmds.map(func(c): return c["id"]) == (M._commands() as Array).map(func(c): return c["id"]), "describe: the registry's own ids, in order")

	# 3. run
	var n0: int = M.S.cards.size()
	var u0: int = M.undo.size()
	r = await req("POST", "/run", auth, JSON.stringify({"command": "CLIP this pose"}))
	d = js(r)
	ok(r.get("code", 0) == 200 and d.get("ok", false), "run 'CLIP this pose': %s %s" % [r.get("code", "no answer"), d.get("error", "")])
	ok(M.S.cards.size() == n0 + 1 and d.get("cards", -1) == n0 + 1, "run: the scene gained 1 card (%d -> %d)" % [n0, M.S.cards.size()])
	ok(d.get("undo_steps", -1) == 1 and M.undo.size() == u0 + 1, "run: exactly 1 undo step (reported %s, stack +%d)" % [d.get("undo_steps", "?"), M.undo.size() - u0])
	M._undo()
	ok(M.S.cards.size() == n0, "Ctrl+Z takes the card back (%d)" % M.S.cards.size())
	r = await req("POST", "/run", auth, JSON.stringify({"command": "no_such_command"}))
	ok(r.get("code", 0) == 400 and js(r).get("error", "").contains("describe"), "an unknown command: 400 naming GET /describe")
	r = await req("POST", "/run", auth, "not json")
	ok(r.get("code", 0) == 400, "a bad body: 400")
	r = await req("GET", "/run", auth)
	ok(r.get("code", 0) == 405, "GET /run: 405")
	r = await req("GET", "/nope", auth)
	ok(r.get("code", 0) == 404, "an unknown path: 404")

	# 4. check (needs two cards)
	r = await req("POST", "/run", auth, JSON.stringify({"command": "clip_this_pose_add_a_card"}))
	r = await req("POST", "/run", auth, JSON.stringify({"command": "clip_this_pose_add_a_card", "args": ["set=lowerarm_r:90,0,0"]}))
	ok(js(r).get("ok", false) and M.S.cards.size() >= 2, "two cards for Check (%d), args steps ran after the command" % M.S.cards.size())
	r = await req("GET", "/check", auth)
	d = js(r)
	ok(r.get("code", 0) == 200 and d.get("findings") is Array and d.has("must_fix") and d.has("clean"), "check: 200, findings (%d), must_fix %s, clean %s" % [d.get("findings", []).size(), d.get("must_fix"), d.get("clean")])

	# 5. shot
	r = await req("GET", "/shot", auth)
	var body: PackedByteArray = r.get("body", PackedByteArray())
	var img := Image.new()
	var le := img.load_png_from_buffer(body) if body.size() > 8 else ERR_INVALID_DATA
	var vs := Vector2i(M.get_viewport().get_visible_rect().size)
	ok(r.get("code", 0) == 200 and String(r.get("head", "")).contains("image/png") and body.size() > 8 and body[1] == 0x50 and body[2] == 0x4E and body[3] == 0x47, "shot: 200, image/png, PNG signature (%d bytes)" % body.size())
	ok(le == OK and img.get_width() > 0 and Vector2i(img.get_width(), img.get_height()) == vs, "shot decodes to %dx%d (viewport %dx%d)" % [img.get_width(), img.get_height(), vs.x, vs.y])

	# 7. binding
	var own := ""
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			own = a
			break
	ok(own == "" or (await req("GET", "/describe", auth, "", own)).is_empty(), "binding: this machine's address %s is refused (only 127.0.0.1 answers)" % (own if own != "" else "- none to try -"))
	ok(not (await req("GET", "/describe", auth)).is_empty(), "binding: 127.0.0.1 answers")

	# 8. off
	M._set_api(false, false)
	ok((await req("GET", "/describe", auth)).is_empty(), "turned off: the port is closed")
	ok(not M.api.running() and M.api.token == "", "turned off: no listener, no token kept")

	# 9. the setting: View > Display > Local API turns it on (at [api] port) and off, and remembers it
	var cf2 := ConfigFile.new()
	cf2.load(M.settings)
	cf2.set_value("api", "port", PORT)
	cf2.save(M.settings)
	var mb: MenuButton = null
	var idx := -1
	for pair in M.ui_caps["VIEW"]:
		for b in pair[1]:
			if M.label_of(b) == "Local API":
				mb = pair[0]
				idx = (pair[1] as Array).find(b)
	ok(mb != null and idx >= 0, "the toggle is in the VIEW > DISPLAY caption's menu (item %d)" % idx)
	if mb != null:
		var pm := mb.get_popup()
		pm.id_pressed.emit(pm.get_item_id(idx))
		ok(M.api.running() and M.api.port == PORT, "the menu item turns it on at the settings port %d" % PORT)
		var cf3 := ConfigFile.new()
		cf3.load(M.settings)
		ok(cf3.get_value("api", "on", false), "and the setting [api] on is remembered")
		r = await req("GET", "/describe", {"X-Poser-Token": M.api.token})
		ok(r.get("code", 0) == 200, "answers with the token the status line shows: %s" % r.get("code", "no answer"))
		ok(String(M.ui_status.text).contains(M.api.token) and String(M.ui_status.text).contains("127.0.0.1:%d" % PORT), "the status line prints the address and the token")
		pm.id_pressed.emit(pm.get_item_id(idx))
		ok(not M.api.running(), "the same item turns it off")

	print("R9: %d failures" % fails)
	quit(1 if fails > 0 else 0)
