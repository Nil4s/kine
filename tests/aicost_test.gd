## godot --path . -s tests/aicost_test.gd     (11-04 AI COST; windowed: the app itself, for the real command list)
## Ask AI paid the WHOLE conversation again on every turn: the scene (changing every turn) sat at the start of the
## request, no cache marks, no token count anywhere. Bars, all measured from the requests build() makes:
##   1 anthropic: the scene is NOT in the system text; cache marks on the last tool and the last conversation block;
##     the scene is the very last block, after the mark
##   2 turn N vs turn N+1 (a tool call later, the scene changed): the request up to turn N's mark is byte-identical in
##     turn N+1 (that is what a cache can reuse), for anthropic, openai, ollama, gemini; >= 80 % of turn N's bytes
##   3 parse() gives the tokens in one shape for all 4 backends (in counts cached ones, out, cache_read, cache_write)
##   4 AiBox: a 3-turn question with usage on each answer sums into box.stats, says "USED: 3 turns, ..." in the box,
##     and appends one line (no prompt text) to user://ai_usage.csv
##   5 commands {find}: "mirror pose" gives <= 25 commands, a mirror command first, under 5 % of the whole list's bytes;
##     no find = the whole list as before
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


const TOOLS := [
	{"name": "pose", "description": "Pose the body in words.", "schema": {"type": "object", "properties": {"text": {"type": "string"}}, "required": ["text"], "additionalProperties": false}},
	{"name": "check", "description": "Grade the motion.", "schema": {"type": "object", "properties": {}, "additionalProperties": false}}]
const SYS := "You animate a human figure."


static func strip_cache(v: Variant) -> Variant:
	if v is Dictionary:
		var o := {}
		for k in v:
			if k != "cache_control":
				o[k] = strip_cache(v[k])
		return o
	if v is Array:
		return (v as Array).map(func(x): return strip_cache(x))
	return v


## the request without the scene line, as text IN THE ORDER THE BACKEND READS ITS PROMPT (tools, system, then the turns
## one by one: a cache reuses a leading run of that), so turn N's text must be the start of turn N+1's.
## (JSON.stringify of the body itself puts "messages" before "tools": that order says nothing about caching.)
static func head_text(be: String, body: Dictionary, scene: String) -> String:
	var b: Dictionary = strip_cache(body)
	var turns: Array = b["contents"] if be == "gemini" else b["messages"]
	match be:
		"anthropic":
			var last: Array = turns[-1]["content"]
			if String(last[-1].get("text", "")).begins_with("The scene now: "):
				last.pop_back()
		"openai", "ollama":
			if String(turns[-1].get("content", "")).begins_with("The scene now: "):
				turns.pop_back()
		"gemini":
			var parts: Array = turns[-1]["parts"]
			if String(parts[-1].get("text", "")).begins_with("The scene now: "):
				parts.pop_back()
	var t := JSON.stringify(b.get("tools", [])) + JSON.stringify(b.get("system", b.get("systemInstruction", "")))
	for i in turns.size():
		var tx := JSON.stringify(turns[i])
		if i == turns.size() - 1:   # the open turn: its blocks may grow next turn (anthropic / gemini merge tool results)
			tx = tx.trim_suffix("}").trim_suffix("]")
		t += tx
	return t if not t.contains(scene) else "SCENE-LEAKED " + t


static func common_prefix(a: String, b: String) -> int:
	var n := mini(a.length(), b.length())
	for i in n:
		if a.unicode_at(i) != b.unicode_at(i):
			return i
	return n


class FakeModel:
	extends Node
	signal answered(r: Dictionary)
	var busy := false
	var script_: Array = []

	func chat(_system: String, _convo: Array, _tools: Array) -> void:
		busy = true
		await get_tree().create_timer(0.05).timeout
		busy = false
		answered.emit(script_.pop_front() if not script_.is_empty() else {"ok": true, "text": "done", "calls": []})

	func stop() -> void:
		busy = false


func _init() -> void:
	# 1 + 2: the requests themselves
	var c1 := [{"role": "user", "text": "raise his arm"},
		{"role": "assistant", "text": "", "calls": [{"id": "c0", "name": "pose", "args": {"text": "raise the right arm 90"}}]},
		{"role": "tool", "id": "c0", "name": "pose", "result": "{\"reached\": {\"upperarm_r\": 90}}"}]
	var c2 := c1.duplicate(true)
	c2.append({"role": "assistant", "text": "", "calls": [{"id": "c1", "name": "check", "args": {}}]})
	c2.append({"role": "tool", "id": "c1", "name": "check", "result": "{\"clean\": true}"})
	var scene1 := "{\"cards\":[{\"name\":\"start\"}]}"
	var scene2 := "{\"cards\":[{\"name\":\"start\"},{\"name\":\"up\"}]}"
	var a1: Dictionary = LlmClient.build("anthropic", "m", "", "k", SYS + LlmClient.NOW_MARK + scene1, c1, TOOLS)["body"]
	var ms: Array = a1["messages"]
	var last: Array = ms[-1]["content"]
	var marks := JSON.stringify(a1).count("cache_control")
	ok(a1["system"] == SYS and a1["tools"][-1].has("cache_control") and last.size() >= 2 and last[-2].has("cache_control")
		and String(last[-1]["text"]) == "The scene now: " + scene1 and not last[-1].has("cache_control") and marks == 2,
		"1 anthropic: system is the fixed text only (%s), %d cache marks (last tool, last block), the scene is the last block after the mark" % [a1["system"] == SYS, marks])
	var shares := []
	var all_same := true
	var real_tools := AiBox.tool_specs()   # what Ask AI really sends: its 7 tools and its SYSTEM text
	for be in ["anthropic", "openai", "ollama", "gemini"]:
		var b1: Dictionary = LlmClient.build(be, "m", "", "k", AiBox.SYSTEM + LlmClient.NOW_MARK + scene1, c1, real_tools)["body"]
		var b2: Dictionary = LlmClient.build(be, "m", "", "k", AiBox.SYSTEM + LlmClient.NOW_MARK + scene2, c2, real_tools)["body"]
		var h1 := head_text(be, b1, scene1)
		var h2 := head_text(be, b2, scene2)
		var cp := common_prefix(h1, h2)
		# share of turn N's PROMPT TEXT (tools + system + turns + the scene line, in reading order) that turn N+1 starts with
		var prompt_n := (h1 + LlmClient.NOW_MARK + scene1).length()
		var share := float(cp) / maxf(1.0, float(prompt_n))
		shares.append("%s %.0f%%%s" % [be, share * 100.0, "" if h2.begins_with(h1) else " (differs at byte %d of %d)" % [cp, h1.length()]])
		all_same = all_same and not h1.begins_with("SCENE") and not h2.begins_with("SCENE") and h2.begins_with(h1) and share >= 0.8
	ok(all_same, "2 turn N's request (scene line left out) is the start of turn N+1's, byte for byte: %s of turn N's bytes reusable (bar >= 80 %%)" % ", ".join(shares))
	# 3 usage
	var u_a: Dictionary = LlmClient.parse("anthropic", 200, JSON.stringify({"content": [{"type": "text", "text": "hi"}], "usage": {"input_tokens": 20, "cache_read_input_tokens": 900, "cache_creation_input_tokens": 80, "output_tokens": 15}}))["usage"]
	var u_o: Dictionary = LlmClient.parse("openai", 200, JSON.stringify({"choices": [{"message": {"content": "hi"}}], "usage": {"prompt_tokens": 1000, "completion_tokens": 15, "prompt_tokens_details": {"cached_tokens": 768}}}))["usage"]
	var u_g: Dictionary = LlmClient.parse("gemini", 200, JSON.stringify({"candidates": [{"content": {"parts": [{"text": "hi"}]}}], "usageMetadata": {"promptTokenCount": 1000, "candidatesTokenCount": 10, "thoughtsTokenCount": 5, "cachedContentTokenCount": 700}}))["usage"]
	var u_l: Dictionary = LlmClient.parse("ollama", 200, JSON.stringify({"message": {"content": "hi"}, "prompt_eval_count": 1000, "eval_count": 15}))["usage"]
	var u_none: Dictionary = LlmClient.parse("anthropic", 200, JSON.stringify({"content": []}))["usage"]
	ok(u_a == {"in": 1000, "out": 15, "cache_read": 900, "cache_write": 80} and u_o == {"in": 1000, "out": 15, "cache_read": 768, "cache_write": 0}
		and u_g == {"in": 1000, "out": 15, "cache_read": 700, "cache_write": 0} and u_l == {"in": 1000, "out": 15, "cache_read": 0, "cache_write": 0}
		and u_none["in"] == 0, "3 usage in one shape: anthropic %s, openai %s, gemini %s, ollama %s, none %s" % [u_a, u_o, u_g, u_l, u_none])
	# 4 the box sums it
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	m._ai_toggle()
	await process_frame
	var box: AiBox = m.ui_ai
	var fake := FakeModel.new()
	box.client = fake
	box.add_child(fake)
	await AgentTools.new(m).request(0, "new", {})
	if FileAccess.file_exists(AiBox.USAGE_LOG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AiBox.USAGE_LOG))
	var u := {"in": 1200, "out": 40, "cache_read": 1000, "cache_write": 150}
	fake.script_ = [
		{"ok": true, "text": "", "calls": [{"id": "a", "name": "describe", "args": {}}], "usage": u},
		{"ok": true, "text": "", "calls": [{"id": "b", "name": "commands", "args": {"find": "mirror"}}], "usage": u},
		{"ok": true, "text": "Nothing to change.", "calls": [], "usage": u}]
	box.ask("look at the scene")
	var t := 0
	while box.running and t < 2000:
		await process_frame
		t += 1
	var lines := "\n".join(box.log_lines)
	var csv := FileAccess.get_file_as_string(AiBox.USAGE_LOG)
	var rows := csv.strip_edges().split("\n")
	ok(int(box.stats.get("in", 0)) == 3600 and int(box.stats.get("cache_read", 0)) == 3000 and int(box.stats.get("out", 0)) == 120 and int(box.stats.get("turns", 0)) == 3
		and lines.contains("USED: 3 turns, 3.6k tokens in (3.0k from cache), 120 out") and rows.size() == 2 and rows[1].contains(",3,2,3600,3000,450,120,")
		and not csv.contains("look at the scene"),
		"4 box.stats %s; the box says '%s'; usage log %d rows: %s" % [box.stats, lines.get_slice("USED: ", 1).get_slice("\n", 0), rows.size(), rows[-1] if rows.size() > 0 else "-"])
	# 5 commands find
	var full: Dictionary = await AgentTools.new(m).request(1, "commands", {})
	var found: Dictionary = await AgentTools.new(m).request(2, "commands", {"find": "mirror pose"})
	var fl: Array = full.get("result", [])
	var fd: Array = found.get("result", [])
	var fb := JSON.stringify(fl).length()
	var db := JSON.stringify(fd).length()
	var first_id: String = String(fd[0]["id"]) if not fd.is_empty() else ""
	ok(fl.size() > 300 and not fd.is_empty() and fd.size() <= AgentTools.FIND_MAX and first_id.contains("mirror") and db * 20 < fb,
		"5 commands: whole list %d commands / %d bytes; find 'mirror pose' %d commands / %d bytes (%.1f %%), first '%s'" % [fl.size(), fb, fd.size(), db, 100.0 * db / maxf(1.0, fb), first_id])
	m.queue_free()
	print("aicost: %d fail" % fails)
	TestFiles.cleanup()
	quit(fails)
