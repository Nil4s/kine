## THE LOCAL API (ROADMAP R9): the command registry over HTTP/JSON, for a script or an agent on THIS machine.
##   GET  /describe      the commands (id, name, keys, edits, desc) + a summary of the live scene
##   POST /run           {"command": "<registry id, name, or unique name prefix>", "args": ["card=3", ...]}  -> the step results
##   GET  /check         Check's findings (the same list serve's `check` gives)
##   GET  /shot          the viewport as a PNG
## It reuses AgentTools (scripts/agent_tools.gd), the code behind `poser_cli serve`, the MCP server and the AI box, so a
## command here is the same command there: one undo step per edit, the same refusals.
## Safety: binds 127.0.0.1 ONLY (never 0.0.0.0); OFF unless the setting is on; every request needs the per-session random
## token in the X-Poser-Token header (or Authorization: Bearer), so a web page in a browser (which sends an Origin header
## and cannot know the token) cannot drive it; the Host header must be 127.0.0.1 / localhost (DNS rebinding); no CORS
## header is ever sent, so a browser never lets a page read an answer.
class_name LocalApi
extends Node

const BIND := "127.0.0.1"
const DEFAULT_PORT := 8765
const MAX_HEAD := 16384
const MAX_BODY := 1048576
const TIMEOUT_MS := 10000
const STEP_WORDS := ["update", "delete", "add", "undo", "redo"]
const STEP_PREFIXES := ["card=", "sel=", "set=", "name=", "pose=", "retime=", "fix="]

var m: Node
var tools
var server: TCPServer
var token := ""
var port := 0
var _conns: Array = []   # {"s": StreamPeerTCP, "buf": PackedByteArray, "t0": int}
var _busy := false


func _init(main: Node) -> void:
	m = main
	tools = load("res://scripts/agent_tools.gd").new(main)


## true when listening
func start(p: int) -> bool:
	stop()
	server = TCPServer.new()
	if server.listen(p, BIND) != OK:
		server = null
		return false
	port = p
	token = Crypto.new().generate_random_bytes(16).hex_encode()
	tools = load("res://scripts/agent_tools.gd").new(m)   # the registry as it is now
	return true


func stop() -> void:
	for c in _conns:
		(c["s"] as StreamPeerTCP).disconnect_from_host()
	_conns.clear()
	if server != null:
		server.stop()
	server = null
	token = ""


func running() -> bool:
	return server != null and server.is_listening()


func _process(_dt: float) -> void:
	if not running():
		return
	while server.is_connection_available():
		_conns.append({"s": server.take_connection(), "buf": PackedByteArray(), "t0": Time.get_ticks_msec()})
	for c in _conns.duplicate():
		var s: StreamPeerTCP = c["s"]
		s.poll()
		if s.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_conns.erase(c)
			continue
		if Time.get_ticks_msec() - int(c["t0"]) > TIMEOUT_MS:
			_reply(c, 408, _j({"ok": false, "error": "request not finished in 10 s: send the whole request at once"}))
			continue
		var n := s.get_available_bytes()
		if n > 0:
			var r := s.get_data(n)
			if r[0] == OK:
				var nb: PackedByteArray = c["buf"]   # a packed array is a value: put it back
				nb.append_array(r[1])
				c["buf"] = nb
		if _busy or c.get("done", false):
			continue
		var req := _parse(c)
		if req.is_empty():
			continue   # not complete yet
		c["done"] = true
		_busy = true
		await _handle(c, req)
		_busy = false


## {} while incomplete; else {"method", "path", "headers" (lower-cased names), "body"}; a malformed one answers 400 itself
func _parse(c: Dictionary) -> Dictionary:
	var b: PackedByteArray = c["buf"]
	var end := -1
	for i in range(0, b.size() - 3):
		if b[i] == 13 and b[i + 1] == 10 and b[i + 2] == 13 and b[i + 3] == 10:
			end = i
			break
	if end < 0:
		if b.size() > MAX_HEAD:
			c["done"] = true
			_reply(c, 431, _j({"ok": false, "error": "headers over 16 KB"}))
		return {}
	var lines := b.slice(0, end).get_string_from_utf8().split("\r\n")
	var rl := lines[0].split(" ")
	if rl.size() != 3 or not rl[2].begins_with("HTTP/1."):
		c["done"] = true
		_reply(c, 400, _j({"ok": false, "error": "not HTTP/1.1: send e.g. GET /describe HTTP/1.1"}))
		return {}
	var h := {}
	for i in range(1, lines.size()):
		var k := lines[i].find(":")
		if k > 0:
			h[lines[i].substr(0, k).strip_edges().to_lower()] = lines[i].substr(k + 1).strip_edges()
	var want := int(h.get("content-length", "0"))
	if want < 0 or want > MAX_BODY:
		c["done"] = true
		_reply(c, 413, _j({"ok": false, "error": "body over 1 MB"}))
		return {}
	if b.size() < end + 4 + want:
		return {}
	var path: String = rl[1]
	var q := path.find("?")
	if q >= 0:
		path = path.substr(0, q)
	return {"method": rl[0].to_upper(), "path": path, "headers": h, "body": b.slice(end + 4, end + 4 + want).get_string_from_utf8()}


func _j(d: Variant) -> PackedByteArray:
	return JSON.stringify(d).to_utf8_buffer()


func _reply(c: Dictionary, code: int, body: PackedByteArray, ctype := "application/json") -> void:
	var names := {200: "OK", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 408: "Request Timeout", 413: "Payload Too Large", 431: "Request Header Fields Too Large", 500: "Internal Server Error"}
	var head := "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n" % [code, names.get(code, "Status"), ctype, body.size()]
	var s: StreamPeerTCP = c["s"]
	if s.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		s.put_data(head.to_utf8_buffer())
		s.put_data(body)
		s.disconnect_from_host()
	_conns.erase(c)


func _authorised(h: Dictionary) -> bool:
	var got := String(h.get("x-poser-token", ""))
	if got == "" and String(h.get("authorization", "")).begins_with("Bearer "):
		got = String(h["authorization"]).substr(7).strip_edges()
	if token == "" or got.length() != token.length():
		return false
	var diff := 0   # compared in full, whatever the first wrong character
	for i in token.length():
		diff |= token.unicode_at(i) ^ got.unicode_at(i)
	return diff == 0


static func is_step(tok: String) -> bool:
	return tok in STEP_WORDS or STEP_PREFIXES.any(func(p): return tok.begins_with(p))


## {"id"} from an id, a step word, a name, or a unique name prefix; else {"error"}
func resolve(cmd: String) -> Dictionary:
	if tools.reg.has(cmd) or is_step(cmd):
		return {"id": cmd}
	var low := cmd.to_lower()
	var hits := []
	for id in tools.reg:
		var nm: String = String(tools.reg[id]["name"]).to_lower()
		if nm == low:
			return {"id": id}
		if nm.begins_with(low):
			hits.append(id)
	if hits.size() == 1:
		return {"id": hits[0]}
	if hits.is_empty():
		return {"error": "no command '%s': GET /describe lists the ids" % cmd}
	return {"error": "'%s' is %d commands (%s...): give the full id" % [cmd, hits.size(), ", ".join(hits.slice(0, 3))]}


func _handle(c: Dictionary, r: Dictionary) -> void:
	var h: Dictionary = r["headers"]
	var hn := String(h.get("host", "")).to_lower().get_slice(":", 0)
	if hn != "127.0.0.1" and hn != "localhost":
		_reply(c, 403, _j({"ok": false, "error": "Host must be 127.0.0.1 or localhost (this API answers the local machine only)"}))
		return
	# the token decides. A browser page always sends Origin and cannot know the token; an Origin with no matching token is refused here
	if not _authorised(h):
		var why := "send the session token in the X-Poser-Token header (the poser's status line shows it when the Local API is turned on)"
		if h.has("origin"):
			why = "a browser page may not drive the poser: " + why
		_reply(c, 401, _j({"ok": false, "error": "unauthorised: " + why}))
		return
	var path: String = r["path"]
	var meth: String = r["method"]
	var want := {"/describe": "GET", "/check": "GET", "/shot": "GET", "/run": "POST"}
	if not want.has(path):
		_reply(c, 404, _j({"ok": false, "error": "no such path '%s': GET /describe, POST /run, GET /check, GET /shot" % path}))
		return
	if meth != want[path]:
		_reply(c, 405, _j({"ok": false, "error": "%s %s" % [want[path], path]}))
		return
	match path:
		"/describe":
			var cmds: Array = m._commands().map(func(k): return {"id": k["id"], "name": k["name"], "keys": k["keys"], "edits": k["edits"], "desc": k["desc"]})
			_reply(c, 200, _j({"ok": true, "commands": cmds, "state": tools.describe(),
				"steps": "also accepted by /run: card=N sel=<part> set=<joint>:b,s,t pose=<words> update delete add undo redo name=<text> retime=A-B:pct fix=N"}))
		"/check":
			var a: Dictionary = await tools.request(1, "check", {})
			if a.has("error"):
				_reply(c, 400, _j({"ok": false, "error": a["error"]["message"]}))
			else:
				var res: Dictionary = a["result"]
				res["ok"] = true
				_reply(c, 200, _j(res))
		"/shot":
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img: Image = m.get_viewport().get_texture().get_image()
			if img == null or img.is_empty():
				_reply(c, 500, _j({"ok": false, "error": "no picture: the viewport has no renderer (a headless run); start the poser with a window"}))
			else:
				_reply(c, 200, img.save_png_to_buffer(), "image/png")
		"/run":
			var jp := JSON.new()   # not parse_string: a bad body is an answer here, not an engine error
			var q: Variant = jp.data if jp.parse(String(r["body"])) == OK else null
			if not (q is Dictionary) or not (q.get("command") is String):
				_reply(c, 400, _j({"ok": false, "error": "send JSON {\"command\": \"clip_this_pose_add_a_card\", \"args\": [\"card=2\"]} (GET /describe lists the ids)"}))
				return
			var extra: Variant = q.get("args", [])
			if not (extra is Array) or not extra.all(func(s): return s is String):
				_reply(c, 400, _j({"ok": false, "error": "args must be a list of step strings, e.g. [\"card=2\", \"update\"]"}))
				return
			var rc := resolve(q["command"])
			if rc.has("error"):
				_reply(c, 400, _j({"ok": false, "error": rc["error"]}))
				return
			var out := []
			var all_ok := true
			var toks: Array = [rc["id"]]
			toks.append_array(extra)   # step tokens after the command: its arguments, in order
			for tok: String in toks:
				var st: Dictionary = await tools.step(tok)
				out.append(st)
				if not st["ok"]:
					all_ok = false
					break
			var us := 0
			for st in out:
				us += int(st["undo_steps"])
			_reply(c, 200 if all_ok else 400, _j({"ok": all_ok, "steps": out, "cards": m.S.cards.size(), "undo_steps": us}))

