## ONE MODEL SWITCH (round 46, GATES BB1): one "chat with tools" call, four backends, each in its own wire format.
## The conversation is kept NEUTRAL and turned into each format only at the edge:
##   {"role": "user", "text"}
##   {"role": "assistant", "text", "calls": [{"id", "name", "args": {}}]}
##   {"role": "tool", "id", "name", "result": String}
## build(...) -> {"url", "headers", "body"} and parse(...) -> {"ok", "text", "calls", "why"} are pure (the test checks them
## against a fake server); chat(...) sends one request with an HTTPRequest child and emits `answered` with parse's result.
## Formats (2026): Ollama /api/chat; OpenAI /v1/chat/completions; Anthropic /v1/messages (anthropic-version 2023-06-01);
## Gemini /v1beta/models/<model>:generateContent. Keys are the user's, typed in Settings; they go only in the header the
## backend asks for, never in a URL.
class_name LlmClient
extends Node

signal answered(r: Dictionary)

const BACKENDS := ["ollama", "anthropic", "openai", "gemini"]
const BASE := {"ollama": "http://127.0.0.1:11434", "anthropic": "https://api.anthropic.com", "openai": "https://api.openai.com",
	"gemini": "https://generativelanguage.googleapis.com"}
const TIMEOUT := 600.0   # a local model on a small card can take minutes for one answer

var backend := "ollama"
var model := "glm-4.7-flash"
var base_url := ""   # "" = BASE[backend]
var key := ""
var busy := false
var last := {}
var _http: HTTPRequest


static func base_of(be: String, url: String) -> String:
	return (url if url != "" else String(BASE.get(be, ""))).trim_suffix("/")


## a tool's schema as Gemini takes it: no additionalProperties (refused there), and an empty object is left out
static func _gemini_schema(sc: Variant) -> Variant:
	if sc is Dictionary:
		var o := {}
		for k in sc:
			if k != "additionalProperties":
				o[k] = _gemini_schema(sc[k])
		return o
	if sc is Array:
		return (sc as Array).map(func(x): return _gemini_schema(x))
	return sc


## the request for one turn: tools = [{"name", "description", "schema"}]
static func build(be: String, mdl: String, url: String, k: String, system: String, convo: Array, tools: Array) -> Dictionary:
	var b := base_of(be, url)
	var h := PackedStringArray(["Content-Type: application/json"])
	var body := {}
	match be:
		"ollama", "openai":
			var msgs := [{"role": "system", "content": system}]
			for it in convo:
				match it["role"]:
					"user":
						msgs.append({"role": "user", "content": it["text"]})
					"assistant":
						var am := {"role": "assistant", "content": it.get("text", "")}
						var cs: Array = it.get("calls", [])
						if not cs.is_empty():
							am["tool_calls"] = cs.map(func(c):
								if be == "ollama":
									return {"function": {"name": c["name"], "arguments": c["args"]}}
								return {"id": c["id"], "type": "function", "function": {"name": c["name"], "arguments": JSON.stringify(c["args"])}})
						msgs.append(am)
					"tool":
						if be == "ollama":
							msgs.append({"role": "tool", "content": it["result"], "tool_name": it["name"]})
						else:
							msgs.append({"role": "tool", "tool_call_id": it["id"], "content": it["result"]})
			body = {"model": mdl, "messages": msgs,
				"tools": tools.map(func(t): return {"type": "function", "function": {"name": t["name"], "description": t["description"], "parameters": t["schema"]}})}
			if be == "ollama":
				body["stream"] = false
				return {"url": b + "/api/chat", "headers": h, "body": body}
			h.append("Authorization: Bearer " + k)
			return {"url": b + "/v1/chat/completions", "headers": h, "body": body}
		"anthropic":
			var msgs := []
			for it in convo:
				match it["role"]:
					"user":
						msgs.append({"role": "user", "content": it["text"]})
					"assistant":
						var blocks := []
						if String(it.get("text", "")) != "":
							blocks.append({"type": "text", "text": it["text"]})
						for c in it.get("calls", []):
							blocks.append({"type": "tool_use", "id": c["id"], "name": c["name"], "input": c["args"]})
						msgs.append({"role": "assistant", "content": blocks})
					"tool":   # results go back as ONE user turn: consecutive ones merge
						var tr := {"type": "tool_result", "tool_use_id": it["id"], "content": it["result"]}
						if not msgs.is_empty() and msgs[-1]["role"] == "user" and msgs[-1]["content"] is Array:
							msgs[-1]["content"].append(tr)
						else:
							msgs.append({"role": "user", "content": [tr]})
			body = {"model": mdl, "max_tokens": 4096, "system": system, "messages": msgs,
				"tools": tools.map(func(t): return {"name": t["name"], "description": t["description"], "input_schema": t["schema"]})}
			h.append("x-api-key: " + k)
			h.append("anthropic-version: 2023-06-01")
			return {"url": b + "/v1/messages", "headers": h, "body": body}
		"gemini":
			var cts := []
			for it in convo:
				match it["role"]:
					"user":
						cts.append({"role": "user", "parts": [{"text": it["text"]}]})
					"assistant":
						var parts := []
						if String(it.get("text", "")) != "":
							parts.append({"text": it["text"]})
						for c in it.get("calls", []):
							parts.append({"functionCall": {"name": c["name"], "args": c["args"]}})
						cts.append({"role": "model", "parts": parts})
					"tool":
						var fr := {"functionResponse": {"name": it["name"], "response": {"result": it["result"]}}}
						if not cts.is_empty() and cts[-1]["role"] == "user" and cts[-1]["parts"][0].has("functionResponse"):
							cts[-1]["parts"].append(fr)
						else:
							cts.append({"role": "user", "parts": [fr]})
			var decl := []
			for t in tools:
				var d := {"name": t["name"], "description": t["description"]}
				if not (t["schema"].get("properties", {}) as Dictionary).is_empty():
					d["parameters"] = _gemini_schema(t["schema"])
				decl.append(d)
			body = {"systemInstruction": {"parts": [{"text": system}]}, "contents": cts, "tools": [{"functionDeclarations": decl}]}
			h.append("x-goog-api-key: " + k)
			return {"url": b + "/v1beta/models/%s:generateContent" % mdl, "headers": h, "body": body}
	return {}


## one answer -> {"ok", "text", "calls": [{"id", "name", "args"}], "why"}
static func parse(be: String, code: int, raw: String) -> Dictionary:
	var d: Variant = JSON.parse_string(raw)
	if code == 401 or code == 403:
		return {"ok": false, "why": "the %s key was refused (HTTP %d): type a new one in the AI box's model row" % [be, code]}
	if not (d is Dictionary):
		return {"ok": false, "why": "%s answered something that is not JSON (HTTP %d): check the address in the AI box's model row" % [be, code]}
	if code >= 400 or d.has("error"):
		var e: Variant = d.get("error", "")
		var msg: String = String(e.get("message", e)) if e is Dictionary else String(e)
		return {"ok": false, "why": "%s refused the request (HTTP %d): %s. Try another model in the AI box's model row" % [be, code, msg]}
	var text := ""
	var calls := []
	match be:
		"ollama":
			var msg: Dictionary = d.get("message", {})
			text = String(msg.get("content", ""))
			for c in msg.get("tool_calls", []):
				var f: Dictionary = c.get("function", {})
				var a: Variant = f.get("arguments", {})
				calls.append({"id": "call_%d" % calls.size(), "name": String(f.get("name", "")), "args": JSON.parse_string(a) if a is String else a})
		"openai":
			var msg: Dictionary = (d.get("choices", [{}]) as Array)[0].get("message", {})
			text = String(msg.get("content", "")) if msg.get("content") != null else ""
			for c in msg.get("tool_calls", []) if msg.get("tool_calls") != null else []:
				var f: Dictionary = c.get("function", {})
				calls.append({"id": String(c.get("id", "")), "name": String(f.get("name", "")), "args": JSON.parse_string(String(f.get("arguments", "{}")))})
		"anthropic":
			for blk in d.get("content", []):
				if blk.get("type") == "text":
					text += String(blk.get("text", ""))
				elif blk.get("type") == "tool_use":
					calls.append({"id": String(blk.get("id", "")), "name": String(blk.get("name", "")), "args": blk.get("input", {})})
		"gemini":
			var cands: Array = d.get("candidates", [])
			var parts: Array = cands[0].get("content", {}).get("parts", []) if not cands.is_empty() else []
			for p in parts:
				if p.has("text"):
					text += String(p["text"])
				elif p.has("functionCall"):
					calls.append({"id": "call_%d" % calls.size(), "name": String(p["functionCall"].get("name", "")), "args": p["functionCall"].get("args", {})})
	for c in calls:   # a call whose arguments did not parse gets {} (the tool then says what it needs)
		if not (c["args"] is Dictionary):
			c["args"] = {}
	return {"ok": true, "text": text, "calls": calls, "why": ""}


## calls the model made up: [why] for each name not in tools (the loop sends these back as the tool's result)
static func unknown_calls(calls: Array, tools: Array) -> Array:
	var names := tools.map(func(t): return t["name"])
	var out := []
	for c in calls:
		if not c["name"] in names:
			out.append("there is no tool '%s': the tools are %s" % [c["name"], ", ".join(names)])
	return out


## one turn: emits `answered` with parse's result (or a refusal naming what to do); `last` keeps it
func chat(system: String, convo: Array, tools: Array) -> void:
	if busy:
		answered.emit({"ok": false, "why": "still waiting for the last answer: press Stop first"})
		return
	if not backend in BACKENDS:
		_finish({"ok": false, "why": "no backend '%s': pick one of %s in the AI box's model row" % [backend, ", ".join(BACKENDS)]})
		return
	var addr := base_of(backend, base_url)
	if not (addr.begins_with("http://") or addr.begins_with("https://")):   # a typed word is no address: refused here, not sent (the engine logged "Invalid URL scheme")
		_finish({"ok": false, "why": "'%s' is not a web address: the address in the AI box's model row must start with http:// or https:// (empty = the usual one)" % addr})
		return
	if backend != "ollama" and key == "":
		_finish({"ok": false, "why": "%s needs your API key: type it in the AI box's model row (or pick ollama, on this machine)" % backend})
		return
	if key != "" and not key_safe(base_of(backend, base_url)):
		_finish({"ok": false, "why": "NOT SENT: %s is plain http to another machine, so your API key and prompts would cross the network unencrypted: use an https:// address in the AI box's model row (or a model on this machine)" % base_of(backend, base_url)})
		return
	var rq := build(backend, model, base_url, key, system, convo, tools)
	busy = true
	# a model on THIS machine that is not running: Windows takes about 30 s to refuse a closed local port through
	# HTTPRequest; a TCP probe of up to PROBE_S says so at once
	var hp := _host_port(base_of(backend, base_url))
	if hp[0] in ["127.0.0.1", "localhost", "::1"] and not await _reachable(hp[0], hp[1]):
		if busy:
			_finish({"ok": false, "why": "could not reach %s (nothing answered): %s" % [base_of(backend, base_url),
				"is Ollama running? Start it, or pick another model in the AI box's model row" if backend == "ollama" else "start the server there, or pick another address in the AI box's model row"]})
		return
	if not busy:   # stopped during the probe
		return
	if _http == null:
		_http = HTTPRequest.new()
		_http.timeout = TIMEOUT
		add_child(_http)
	var err := _http.request(rq["url"], rq["headers"], HTTPClient.METHOD_POST, JSON.stringify(rq["body"]))
	if err != OK:
		_finish({"ok": false, "why": "could not send to %s (error %d): check the address in the AI box's model row" % [rq["url"], err]})
		return
	var res: Array = await _http.request_completed
	if not busy:   # stopped meanwhile
		return
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS:
		var hint := "is Ollama running? Start it, or pick another model in the AI box's model row" if backend == "ollama" else "check your connection, or the address in the AI box's model row"
		_finish({"ok": false, "why": "could not reach %s (%s): %s" % [base_of(backend, base_url), _result_name(int(res[0])), hint]})
		return
	_finish(parse(backend, int(res[1]), (res[3] as PackedByteArray).get_string_from_utf8()))


const PROBE_S := 3.0


## a key may travel only encrypted (https) or to this machine (security review 10-18: the address field took any http)
static func key_safe(url: String) -> bool:
	return url.begins_with("https://") or _host_port(url)[0] in ["127.0.0.1", "localhost", "::1", "[::1]"]


static func _host_port(url: String) -> Array:
	var u := url.trim_prefix("http://").trim_prefix("https://").get_slice("/", 0)
	var tls := url.begins_with("https://")
	var i := u.rfind(":")
	if i > 0 and u.substr(i + 1).is_valid_int():
		return [u.substr(0, i), int(u.substr(i + 1))]
	return [u, 443 if tls else 80]


## true when something accepts a TCP connection at host:port within PROBE_S (polled a frame at a time)
func _reachable(host: String, port: int) -> bool:
	var t := StreamPeerTCP.new()
	if t.connect_to_host("127.0.0.1" if host == "localhost" else host, port) != OK:
		return false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < PROBE_S * 1000.0:
		t.poll()
		match t.get_status():
			StreamPeerTCP.STATUS_CONNECTED:
				t.disconnect_from_host()
				return true
			StreamPeerTCP.STATUS_ERROR, StreamPeerTCP.STATUS_NONE:
				return false
		await get_tree().process_frame
	t.disconnect_from_host()
	return false


func stop() -> void:
	if _http != null:
		_http.cancel_request()
	if busy:
		_finish({"ok": false, "why": "stopped"})


func _finish(r: Dictionary) -> void:
	busy = false
	last = r
	answered.emit(r)


static func _result_name(r: int) -> String:
	match r:
		HTTPRequest.RESULT_CANT_CONNECT:
			return "nothing answered"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "the name did not resolve"
		HTTPRequest.RESULT_TIMEOUT:
			return "it timed out"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "the connection broke"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "the secure connection failed"
	return "result %d" % r
