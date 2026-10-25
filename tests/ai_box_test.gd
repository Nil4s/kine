## godot --path . -s tests/ai_box_test.gd     (round 46, GATES BB2; windowed: the app itself)
## ASK AI, with a SCRIPTED model in place of the real one (the same chat / answered / stop / busy as LlmClient):
##   1 ANIMATE has "Ask AI" (its own icon), the search has it; pressing it opens the box with the typing line focused
##   2 "he raises his right arm, then bends the elbow" on an EMPTY scene: the model's 4 turns (2 poses + 2 runs, then a
##     made-up tool + check, then a sentence) build 2 named cards ("up", "bend"); every call is a line in the box, the
##     made-up one refused there; the end says Check's verdict and the model's sentence on the status line
##   3 ONE undo step per editing call, each named "AI: ..."; undoing them all empties the scene again
##   4 what the model was SENT: the tool results of the turn before (pose's "reached", the refusal of 'fly'), the tools
##     (7, none of open / new / save), and the scene as it stands in the system text
##   5 Stop while the model is thinking: the box stops at once, says so, and can be asked again; nothing changed
##   6 the model row (backend, model) is remembered in the settings file, the key is NOT
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


class FakeModel:
	extends Node
	signal answered(r: Dictionary)
	var busy := false
	var script_: Array = []   # the answers, in order
	var sent: Array = []      # [system, convo copy, tools] per turn
	var hang := false         # never answer (to test Stop)

	func chat(system: String, convo: Array, tools: Array) -> void:
		sent.append([system, convo.duplicate(true), tools])
		busy = true
		if hang:
			return
		await get_tree().create_timer(0.05).timeout
		busy = false
		answered.emit(script_.pop_front() if not script_.is_empty() else {"ok": true, "text": "done", "calls": []})

	func stop() -> void:
		if busy:
			busy = false
			answered.emit({"ok": false, "why": "stopped"})


func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	# 1
	var found := false
	for b in (m.ui_ribbon["ANIMATE"] as Node).find_children("*", "Button", true, false):
		if String((b as Button).tooltip_text).begins_with("Ask AI"):
			found = true
	var in_search := false
	for c in m.ui_cmd.commands:
		if c["name"] == "Ask AI" and String(c.get("also", "")).contains("ollama"):
			in_search = true
	var fake := FakeModel.new()
	m._ai_toggle()   # builds the box (with its own LlmClient), then the scripted model is put in its place
	await process_frame
	var box: AiBox = m.ui_ai
	box.client = fake
	box.add_child(fake)
	await process_frame
	ok(found and in_search and m.ICON_OF.get("Ask AI", "") == "ai" and Icons.DRAW.has("ai") and box.visible and box.ui_in.has_focus(),
		"1 ANIMATE has Ask AI (icon %s), the search has it, the box opened with the typing line focused (%s)" % [m.ICON_OF.get("Ask AI", "-"), box.ui_in.has_focus()])
	# 2 on an empty scene
	await AgentTools.new(m).request(0, "new", {})
	m.undo.clear()
	fake.script_ = [
		{"ok": true, "text": "", "calls": [{"id": "a", "name": "pose", "args": {"text": "raise the right arm 90"}}, {"id": "b", "name": "run", "args": {"steps": ["add", "name=up"]}}]},
		{"ok": true, "text": "", "calls": [{"id": "c", "name": "pose", "args": {"text": "bend the right elbow 60"}}, {"id": "d", "name": "run", "args": {"steps": ["add", "name=bend"]}}]},
		{"ok": true, "text": "", "calls": [{"id": "e", "name": "fly", "args": {}}, {"id": "f", "name": "check", "args": {}}]},
		{"ok": true, "text": "Made two cards: the arm goes up, then the elbow bends.", "calls": []}]
	box.ui_in.text = "he raises his right arm, then bends the elbow"
	box.ui_go.pressed.emit()
	var t := 0
	while box.running and t < 2000:
		await process_frame
		t += 1
	var names := []
	for c in m.S.cards:
		names.append(c["name"])
	var lines := "\n".join(box.log_lines)
	var status: String = m.ui_status.text
	ok(names == ["up", "bend"] and lines.contains("- pose raise the right arm 90") and lines.contains("- run add, name=up")
		and lines.contains("x there is no tool 'fly'") and lines.contains("- check") and lines.contains("CHECK: 2 cards")
		and status.contains("Made two cards") and status.contains("Check:"),
		"2 built %s in %d frames; the box says:\n%s\n   status: %s" % [names, t, lines, status])
	# 3 undo
	var hints := []
	for u in m.undo:
		hints.append(String(u.get("hint", "")))
	var n_steps: int = m.undo.size()
	for k in n_steps:
		m._undo()
	ok(n_steps == 4 and hints.all(func(h): return h.begins_with("AI: ")) and m.S.cards.is_empty(),
		"3 %d undo steps (bar 4: pose, run, pose, run; fly and check change nothing), named %s; undoing them all left %d cards" % [n_steps, hints, m.S.cards.size()])
	# 4 what it was sent
	var turn3: Array = fake.sent[2][1] if fake.sent.size() > 2 else []
	var turn4: Array = fake.sent[3][1] if fake.sent.size() > 3 else []
	var had_reached := JSON.stringify(turn3).contains("reached")
	var had_fly := JSON.stringify(turn4).contains("there is no tool 'fly'")
	var tools: Array = fake.sent[0][2] if fake.sent.size() > 0 else []
	var tnames := tools.map(func(x): return x["name"])
	var sys1: String = fake.sent[1][0] if fake.sent.size() > 1 else ""
	ok(fake.sent.size() == 4 and had_reached and had_fly and tnames.size() == 7 and not ("open" in tnames or "new" in tnames or "save" in tnames)
		and sys1.contains("\"name\":\"up\""),
		"4 sent %d turns; tool results carried back (reached %s, fly refused %s); tools %s; turn 2's system text has card 'up' %s" % [fake.sent.size(), had_reached, had_fly, tnames, sys1.contains("\"name\":\"up\"")])
	# 5 stop
	fake.hang = true
	var c0 := JSON.stringify(m.S.cards)
	box.ask("he jumps")
	for k in 10:
		await process_frame
	var was_running: bool = box.running
	box.ui_stop.pressed.emit()
	for k in 10:
		await process_frame
	ok(was_running and not box.running and "\n".join(box.log_lines).contains("(stopped)") and not box.ui_go.disabled and JSON.stringify(m.S.cards) == c0,
		"5 Stop while thinking: was running %s, now %s, '(stopped)' in the box, Ask on again %s, the cards unchanged" % [was_running, box.running, not box.ui_go.disabled])
	# 6 settings
	box.ui_key.text = "zz-test-key-not-real"
	box.ui_backend.select(LlmClient.BACKENDS.find("anthropic"))
	box.ui_model.text = "zz-model"   # text_changed is not emitted by assignment: save as the box does on an edit
	box._save_model_row()
	var cfg := FileAccess.get_file_as_string(m.settings)
	ok(m.settings != m.SETTINGS and cfg.contains("zz-model") and cfg.contains("anthropic") and not cfg.contains("zz-test-key"),
		"6 the model row remembered in the test's own settings file (%s), the key not in it" % m.settings.get_file())
	m.queue_free()
	print("AI BOX TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
