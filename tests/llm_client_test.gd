## godot --headless --path . -s tests/llm_client_test.gd     (round 46, GATES BB1)
## ONE MODEL SWITCH, against a FAKE server on 127.0.0.1 (no network, no model). For each of ollama / anthropic / openai /
## gemini, one turn that carries a user line, an earlier tool call and its result:
##   1..4 the request the server GOT: its path, the key in that backend's own header (and never in the URL), the earlier
##        call and its result in that backend's shape, the tools in that backend's shape; and the scripted answer's tool
##        call parsed back to {"name": "pose", "args": {"text": "raise the right arm 90"}} plus its text
##   5 refusals, each a sentence naming what to do: nothing listening (said within 5 s: without a probe Windows took
##     about 30 s to refuse a closed local port); HTTP 401 (a bad key); a cloud backend with no key
##     (nothing sent); a tool the model made up (unknown_calls)
extends SceneTree

var fails := 0
var srv := TCPServer.new()
var port := 0
var got := {}          # the last request: {"line", "headers": {lower name: value}, "body"}
var reply := ""        # the next answer's body
var reply_code := 200

const TOOLS := [
	{"name": "pose", "description": "Pose the body in words.", "schema": {"type": "object", "properties": {"text": {"type": "string"}}, "required": ["text"], "additionalProperties": false}},
	{"name": "check", "description": "Grade the motion.", "schema": {"type": "object", "properties": {}, "additionalProperties": false}}]
const CONVO := [
	{"role": "user", "text": "raise his arm"},
	{"role": "assistant", "text": "", "calls": [{"id": "c0", "name": "check", "args": {}}]},
	{"role": "tool", "id": "c0", "name": "check", "result": "{\"clean\": true}"}]
const KEY := "test-key-for-the-fake-server"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## the fake server, one step a frame (HTTPRequest writes its bytes on later frames, so nothing here may block): take a
## waiting connection, gather the whole request, then answer `reply`
var conn: StreamPeerTCP = null
var buf := PackedByteArray()


func _serve_once() -> void:
	if conn == null:
		if not srv.is_connection_available():
			return
		conn = srv.take_connection()
		buf = PackedByteArray()
	conn.poll()
	var n := conn.get_available_bytes()
	if n > 0:
		buf.append_array(conn.get_data(n)[1])
	var s := buf.get_string_from_utf8()
	var head_end := s.find("\r\n\r\n")
	if head_end < 0:
		if conn.get_status() != StreamPeerTCP.STATUS_CONNECTED:   # a probe (LlmClient._reachable) that only knocked
			conn = null
		return
	var lines := s.substr(0, head_end).split("\r\n")
	var hd := {}
	for l in lines.slice(1):
		var k := l.find(":")
		hd[l.substr(0, k).to_lower()] = l.substr(k + 1).strip_edges()
	if buf.size() - (head_end + 4) < int(hd.get("content-length", "0")):
		return
	got = {"line": lines[0], "headers": hd, "body": JSON.parse_string(s.substr(head_end + 4))}
	var out := reply.to_utf8_buffer()
	var status := "200 OK" if reply_code == 200 else "%d Error" % reply_code
	conn.put_data(("HTTP/1.1 %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [status, out.size()]).to_utf8_buffer())
	conn.put_data(out)
	conn.poll()
	conn = null   # closed when freed; the client has the whole answer by its length


func turn(c: LlmClient) -> Dictionary:
	got = {}
	c.chat("You animate.", CONVO, TOOLS)
	var t0 := Time.get_ticks_msec()
	while c.busy and Time.get_ticks_msec() - t0 < 20000:
		_serve_once()
		await process_frame
	return c.last


func _init() -> void:
	for p in range(18431, 18531):
		if srv.listen(p, "127.0.0.1") == OK:
			port = p
			break
	print("   fake server on 127.0.0.1:%d" % port)
	var c := LlmClient.new()
	root.add_child(c)
	await process_frame
	var want_call := {"name": "pose", "args": {"text": "raise the right arm 90"}}
	var answers := {
		"ollama": {"message": {"role": "assistant", "content": "posing", "tool_calls": [{"function": {"name": "pose", "arguments": {"text": "raise the right arm 90"}}}]}},
		"openai": {"choices": [{"message": {"role": "assistant", "content": "posing", "tool_calls": [{"id": "call_9", "type": "function", "function": {"name": "pose", "arguments": "{\"text\": \"raise the right arm 90\"}"}}]}}]},
		"anthropic": {"content": [{"type": "text", "text": "posing"}, {"type": "tool_use", "id": "toolu_9", "name": "pose", "input": {"text": "raise the right arm 90"}}]},
		"gemini": {"candidates": [{"content": {"role": "model", "parts": [{"text": "posing"}, {"functionCall": {"name": "pose", "args": {"text": "raise the right arm 90"}}}]}}]}}
	var n := 0
	for be in ["ollama", "anthropic", "openai", "gemini"]:
		n += 1
		c.backend = be
		c.model = "m-" + be
		c.base_url = "http://127.0.0.1:%d" % port
		c.key = KEY if be != "ollama" else ""
		reply = JSON.stringify(answers[be])
		reply_code = 200
		var r: Dictionary = await turn(c)
		var b: Dictionary = got.get("body", {}) if got.get("body") is Dictionary else {}
		var hd: Dictionary = got.get("headers", {})
		var line: String = got.get("line", "")
		var shape := false
		var keyed := false
		match be:
			"ollama":
				var ms: Array = b.get("messages", [])
				shape = line.begins_with("POST /api/chat ") and b.get("stream") == false and ms.size() == 4 and ms[0]["role"] == "system"
				shape = shape and ms[2]["tool_calls"][0]["function"]["name"] == "check" and ms[3]["role"] == "tool" and ms[3]["tool_name"] == "check"
				shape = shape and b["tools"][0]["function"]["parameters"]["required"] == ["text"]
				keyed = not hd.has("authorization")
			"openai":
				var ms: Array = b.get("messages", [])
				shape = line.begins_with("POST /v1/chat/completions ") and ms.size() == 4 and ms[2]["tool_calls"][0]["id"] == "c0"
				shape = shape and ms[2]["tool_calls"][0]["function"]["arguments"] is String and ms[3]["tool_call_id"] == "c0"
				shape = shape and b["tools"][1]["function"]["name"] == "check"
				keyed = hd.get("authorization", "") == "Bearer " + KEY
			"anthropic":
				var ms: Array = b.get("messages", [])
				shape = line.begins_with("POST /v1/messages ") and b.get("system") == "You animate." and ms.size() == 3
				shape = shape and ms[1]["content"][0]["type"] == "tool_use" and ms[2]["role"] == "user" and ms[2]["content"][0]["type"] == "tool_result"
				shape = shape and ms[2]["content"][0]["tool_use_id"] == "c0" and b["tools"][0].has("input_schema") and int(b.get("max_tokens", 0)) > 0
				keyed = hd.get("x-api-key", "") == KEY and hd.get("anthropic-version", "") == "2023-06-01"
			"gemini":
				var cs: Array = b.get("contents", [])
				var decl: Array = b.get("tools", [{}])[0].get("functionDeclarations", [])
				shape = line.begins_with("POST /v1beta/models/m-gemini:generateContent ") and cs.size() == 3 and cs[1]["role"] == "model"
				shape = shape and cs[1]["parts"][0]["functionCall"]["name"] == "check" and cs[2]["parts"][0]["functionResponse"]["name"] == "check"
				shape = shape and not decl[0]["parameters"].has("additionalProperties") and not decl[1].has("parameters")
				keyed = hd.get("x-goog-api-key", "") == KEY
		var no_key_in_url := not line.contains(KEY)
		var call: Dictionary = (r.get("calls", [{}]) as Array)[0] if not (r.get("calls", []) as Array).is_empty() else {}
		var parsed: bool = r.get("ok", false) and call.get("name") == want_call["name"] and call.get("args") == want_call["args"] and r.get("text") == "posing"
		ok(shape and keyed and no_key_in_url and parsed, "%d %s: %s; the request's shape %s, the key in its header %s (not in the URL %s), the call parsed %s (%s)"
			% [n, be, line.get_slice(" HTTP", 0), shape, keyed, no_key_in_url, parsed, JSON.stringify(call)])
	# 5 refusals
	c.backend = "ollama"
	c.base_url = "http://127.0.0.1:%d" % (port + 1)   # nothing there
	var t1 := Time.get_ticks_msec()
	var r1: Dictionary = await turn(c)
	var dt1 := (Time.get_ticks_msec() - t1) / 1000.0
	c.backend = "openai"
	c.key = "wrong"
	c.base_url = "http://127.0.0.1:%d" % port
	reply = "{\"error\": {\"message\": \"Incorrect API key\"}}"
	reply_code = 401
	var r2: Dictionary = await turn(c)
	c.backend = "anthropic"
	c.key = ""
	got = {}
	var r3: Dictionary = await turn(c)
	var sent3 := not got.is_empty()
	var r4 := LlmClient.unknown_calls([{"id": "x", "name": "fly", "args": {}}, {"id": "y", "name": "pose", "args": {}}], TOOLS)
	var w1: String = r1.get("why", "")
	var w2: String = r2.get("why", "")
	var w3: String = r3.get("why", "")
	ok(dt1 <= 5.0 and not r1.get("ok", true) and w1.contains("could not reach") and w1.contains("Ollama running")
		and not r2.get("ok", true) and w2.contains("key was refused") and w2.contains("model row")
		and not r3.get("ok", true) and w3.contains("needs your API key") and not sent3
		and r4.size() == 1 and r4[0].contains("no tool 'fly'"),
		"5 refused: nothing listening, said after %.1f s (bar 5): \"%s\" | \"%s\" | \"%s\" (sent %s) | %s" % [dt1, w1, w2, w3, sent3, r4])
	# 6 an API key never crosses the network unencrypted
	c.backend = "openai"
	c.key = "sk-zz-test"
	c.base_url = "http://10.20.30.40:8080"
	got = {}
	var r6: Dictionary = await turn(c)
	var w6: String = r6.get("why", "")
	var safe := [LlmClient.key_safe("https://api.openai.com"), LlmClient.key_safe("http://127.0.0.1:11434"),
		LlmClient.key_safe("http://localhost:1234"), not LlmClient.key_safe("http://10.20.30.40:8080"),
		not LlmClient.key_safe("http://api.openai.com")]
	ok(not r6.get("ok", true) and w6.contains("NOT SENT") and w6.contains("https://") and got.is_empty()
		and not safe.has(false), "6 a key to plain http on another machine is refused before sending: \"%s\"; key_safe on https / 127.0.0.1 / localhost / 10.x http / remote http: %s (want all true)" % [w6, safe])
	srv.stop()
	print("LLM CLIENT TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
