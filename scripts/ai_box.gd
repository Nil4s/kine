## ASK AI (round 46, GATES BB2): type what should happen ("he waves, then sits"); a model and the agent's tools
## (scripts/agent_tools.gd, the SAME code as poser_cli serve and the MCP server) take turns on the scene on screen.
## Each tool call is ONE undo step named after it ("AI: pose raise the right arm 90"); every call shows as a line; Check
## runs at the end and is said; Stop works mid-run. The model is a switch (scripts/llm_client.gd): ollama on this
## machine by default, or Claude / GPT / Gemini with the user's own key, kept in memory only (never written to a file).
## The model sees only the tools below: no open / new / save, so it works on the scene the user is looking at.
class_name AiBox
extends PanelContainer

signal finished(summary: String)

const MAX_TURNS := 30
const RESULT_CHARS := 6000   # a tool's answer as the model sees it (state and commands are long; a small model chokes)
const S := {"type": "string"}
const N := {"type": "number"}
## the model's tools: name -> [serve method, description, input schema]
const TOOLS := {
	"describe": ["describe", "The scene now: its cards (name, arrive / move / hold seconds), length, settings, the picked card and part.",
		{"type": "object", "properties": {}, "additionalProperties": false}],
	"pose": ["pose", "Pose the body in words: 'raise the right arm 90, bend the left elbow 45, turn the head left 30'. A number turns BY that much; 'to N' sets the angle. Says what each joint REACHED and where a limit stopped it. The pose is on the body only: run [\"add\"] makes it a card.",
		{"type": "object", "properties": {"text": S}, "required": ["text"], "additionalProperties": false}],
	"run": ["run", "Run steps in order, as the window's buttons: [\"add\"] (the body as a new card after the picked one), [\"card=2\"] (pick card 2: its pose goes on the body), [\"update\"] (the body onto the picked card), [\"delete\"], [\"name=wave up\"], [\"pose=raise the right arm 90\"], [\"set=lowerarm_r:90,0,0\"] (bend, side, twist deg), [\"retime=2-4:150\"] (cards 2-4 at 150 %, slower), [\"fix=1\"] (Check's first finding's fix), [\"undo\"]; plus any id from commands (e.g. mirror_the_whole_pose, slower_10, weapon_metal_bat). Stops at the first failing step.",
		{"type": "object", "properties": {"steps": {"type": "array", "items": S, "minItems": 1}}, "required": ["steps"], "additionalProperties": false}],
	"state": ["state", "The body: each joint's bend / side / twist (deg) and where 17 parts are (m; y up, +z his front). With t (seconds), at that moment of the scene.",
		{"type": "object", "properties": {"t": N}, "additionalProperties": false}],
	"measure": ["measure", "Numbers at a moment t (s): what = [\"distance hand_r head\", \"angle upperarm_r lowerarm_r hand_r\" (180 = straight), \"height head\", \"speed hand_r\" (m/s), \"com\", \"balance\"].",
		{"type": "object", "properties": {"what": {"type": "array", "items": S, "minItems": 1}, "t": N}, "required": ["what"], "additionalProperties": false}],
	"check": ["check", "Grade the motion against recorded human motion: numbered findings (MUST FIX breaks a human limit; look = looks off), each with its card and a fix if one exists (run [\"fix=N\"]). Needs 2+ cards.",
		{"type": "object", "properties": {}, "additionalProperties": false}],
	"commands": ["commands", "Every command the window has (id, name, keys): the ids are run steps.",
		{"type": "object", "properties": {}, "additionalProperties": false}],
}
const SYSTEM := """You animate a human figure in Poser, an animation app. The user tells you what should happen; you build it with the tools, on the scene they are looking at. A scene is a row of CARDS (key poses); playing it moves the body from card to card. To make a card: pose the body (pose), then run ["add"]. To change a card: run ["card=N"], pose, run ["update"]. Name the cards (run ["name=..."]) after what happens in them. Angles are degrees; left / right are HIS. Keep it simple: 3 to 8 cards for a short action. When done, run check; if it lists MUST FIX findings, fix them (run ["fix=N"] or change the card), then check again. Finish with one or two plain sentences saying what you made. Do not ask the user questions: decide."""

var main: Node
var tools: AgentTools
var client: Node   # LlmClient, or a stand-in with the same chat() / stop() / answered / busy (the test's scripted model)
var running := false
var convo := []
var calls_made := 0
var log_lines := PackedStringArray()

var ui_log: RichTextLabel
var ui_in: LineEdit
var ui_go: Button
var ui_stop: Button
var ui_backend: OptionButton
var ui_model: LineEdit
var ui_url: LineEdit
var ui_key: LineEdit


func setup(m: Node) -> void:
	main = m
	tools = AgentTools.new(m)
	name = "AiBox"
	if client == null:
		var c := LlmClient.new()
		c.name = "LlmClient"
		add_child(c)
		client = c
	_build()
	_load_model_row()


func _build() -> void:
	custom_minimum_size = Vector2(420, 300)
	var v := VBoxContainer.new()
	add_child(v)
	var title := Label.new()
	title.text = "ASK AI"
	v.add_child(title)
	var row := HBoxContainer.new()
	v.add_child(row)
	ui_backend = OptionButton.new()
	ui_backend.name = "AiBackend"
	for be in LlmClient.BACKENDS:
		ui_backend.add_item(be)
	ui_backend.tooltip_text = "which model answers: ollama runs on this machine; the others need your own key"
	row.add_child(ui_backend)
	ui_model = LineEdit.new()
	ui_model.name = "AiModel"
	ui_model.placeholder_text = "model"
	ui_model.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ui_model)
	var row2 := HBoxContainer.new()
	v.add_child(row2)
	ui_url = LineEdit.new()
	ui_url.name = "AiUrl"
	ui_url.placeholder_text = "address (empty = the usual one)"
	ui_url.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(ui_url)
	ui_key = LineEdit.new()
	ui_key.name = "AiKey"
	ui_key.secret = true
	ui_key.placeholder_text = "API key (kept in memory only)"
	ui_key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(ui_key)
	ui_log = RichTextLabel.new()
	ui_log.name = "AiLog"
	ui_log.scroll_following = true
	ui_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ui_log.custom_minimum_size = Vector2(0, 160)
	ui_log.selection_enabled = true
	v.add_child(ui_log)
	var row3 := HBoxContainer.new()
	v.add_child(row3)
	ui_in = LineEdit.new()
	ui_in.name = "AiAsk"
	ui_in.placeholder_text = "what should happen? e.g. he waves with the right hand, then sits"
	ui_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui_in.text_submitted.connect(func(t): ask(t))
	row3.add_child(ui_in)
	ui_go = Button.new()
	ui_go.name = "AiGo"
	ui_go.text = "Ask"
	ui_go.pressed.connect(func(): ask(ui_in.text))
	row3.add_child(ui_go)
	ui_stop = Button.new()
	ui_stop.name = "AiStop"
	ui_stop.text = "Stop"
	ui_stop.disabled = true
	ui_stop.tooltip_text = "nothing is running: ask something first"
	ui_stop.pressed.connect(stop)
	row3.add_child(ui_stop)
	for w in [ui_model, ui_url]:
		(w as LineEdit).text_changed.connect(func(_t): _save_model_row())
	ui_backend.item_selected.connect(func(_i): _save_model_row())


func _load_model_row() -> void:
	var cf := ConfigFile.new()
	cf.load(main.settings)
	var be: String = cf.get_value("ai", "backend", "ollama")
	ui_backend.select(maxi(0, LlmClient.BACKENDS.find(be)))
	ui_model.text = cf.get_value("ai", "model", "glm-4.7-flash")
	ui_url.text = cf.get_value("ai", "url", "")


## backend, model and address are remembered; the key never is
func _save_model_row() -> void:
	var cf := ConfigFile.new()
	cf.load(main.settings)
	cf.set_value("ai", "backend", LlmClient.BACKENDS[ui_backend.selected])
	cf.set_value("ai", "model", ui_model.text)
	cf.set_value("ai", "url", ui_url.text)
	cf.save(main.settings)


func _line(t: String) -> void:
	log_lines.append(t)
	if ui_log != null:
		ui_log.append_text(t.replace("[", "[lb]") + "\n")


static func tool_specs() -> Array:
	var out := []
	for k in TOOLS:
		out.append({"name": k, "description": TOOLS[k][1], "schema": TOOLS[k][2]})
	return out


## what a call looks like in the log and as its undo step's name
static func call_label(c: Dictionary) -> String:
	var a: Dictionary = c.get("args", {})
	match String(c["name"]):
		"pose":
			return "pose " + String(a.get("text", ""))
		"run":
			return "run " + ", ".join(PackedStringArray((a.get("steps", []) as Array).map(func(x): return String(x))))
		"measure":
			return "measure " + ", ".join(PackedStringArray((a.get("what", []) as Array).map(func(x): return String(x))))
	return String(c["name"])


func ask(text: String) -> void:
	text = text.strip_edges()
	if text == "":
		_say("type what should happen first, e.g. he waves with the right hand")
		return
	if running:
		_say("still working on the last one: press Stop first")
		return
	if client is LlmClient:
		var lc := client as LlmClient
		lc.backend = LlmClient.BACKENDS[ui_backend.selected]
		lc.model = ui_model.text.strip_edges()
		lc.base_url = ui_url.text.strip_edges()
		lc.key = ui_key.text.strip_edges()
	running = true
	calls_made = 0
	ui_stop.disabled = false
	ui_stop.tooltip_text = "stop after the step that is running"
	ui_go.disabled = true
	ui_in.text = ""
	convo = [{"role": "user", "text": text}]
	_line("YOU: " + text)
	var specs := tool_specs()
	var turns := 0
	var said := ""
	while running and turns < MAX_TURNS:
		turns += 1
		client.chat.call_deferred(SYSTEM + "\n\nThe scene now: " + JSON.stringify(tools.describe()), convo, specs)   # deferred: a refusal emits at once, before the await could hear it
		var r: Dictionary = await client.answered
		if not running:
			break
		if not r.get("ok", false):
			said = "the model could not answer: " + String(r.get("why", "?"))
			_line("AI: " + said)
			break
		var calls: Array = r.get("calls", [])
		convo.append({"role": "assistant", "text": r.get("text", ""), "calls": calls})
		if String(r.get("text", "")).strip_edges() != "" and calls.is_empty():
			said = String(r["text"]).strip_edges()
			_line("AI: " + said)
		if calls.is_empty():
			break
		for c in calls:
			if not running:
				break
			var res := await _call(c, specs)
			convo.append({"role": "tool", "id": c["id"], "name": c["name"], "result": res})
	if turns >= MAX_TURNS and running:
		said = "stopped after %d turns: ask again to go on" % MAX_TURNS
		_line("AI: " + said)
	var was_stopped := not running
	running = false
	ui_stop.disabled = true
	ui_stop.tooltip_text = "nothing is running: ask something first"
	ui_go.disabled = false
	var summary := _check_line()
	if was_stopped:
		summary = "stopped. " + summary
	_line("CHECK: " + summary)
	_say(("AI: %s  |  " % said.left(140) if said != "" else "") + summary)
	finished.emit(summary)


## one tool call: shown, run as ONE undo step named after it, its answer trimmed for the model
func _call(c: Dictionary, specs: Array) -> String:
	calls_made += 1
	var label := call_label(c)
	var bad := LlmClient.unknown_calls([c], specs)
	if not bad.is_empty():
		_line("  x " + bad[0])
		return JSON.stringify({"error": bad[0]})
	var n0: int = main.undo.size()
	var resp: Dictionary = await tools.request(calls_made, TOOLS[c["name"]][0], c.get("args", {}) if c.get("args") is Dictionary else {})
	_one_step(n0, "AI: " + label)
	var ok := resp.has("result")
	_line(("  %s %s" % ["-" if ok else "x", label]) + ("" if ok else ": " + String(resp["error"]["message"])))
	var out := JSON.stringify(resp.get("result") if ok else {"error": resp["error"]["message"]})
	if out.length() > RESULT_CHARS:
		out = out.left(RESULT_CHARS) + "... (cut: ask for less)"
	return out


## the undo steps one call pushed become ONE, named after the call (the stack holds the state BEFORE each step, so the
## first one pushed is the state before the whole call)
func _one_step(n0: int, step: String) -> void:
	var u: Array = main.undo
	n0 = clampi(n0, 0, u.size())
	if u.size() <= n0:
		return
	u.resize(n0 + 1)
	u[n0]["hint"] = main.step_name(step)
	main._history_rows.call_deferred()


func _check_line() -> String:
	if main.S.cards.size() < 2:
		return "%d card%s: Check needs two" % [main.S.cards.size(), "" if main.S.cards.size() == 1 else "s"]
	var fs: Array = tools.findings()
	var must := fs.filter(func(f): return f["sev"] == "MUST FIX").size()
	return "%d cards, %.2f s; Check: %d MUST FIX, %d to look at%s" % [main.S.cards.size(), main.S.length(), must, fs.size() - must,
		"" if must == 0 else " (press Check to see them)"]


func stop() -> void:
	if not running:
		return
	running = false
	if client.has_method("stop"):
		client.stop()
	_line("(stopped)")


func _say(t: String) -> void:
	if main != null and main.has_method("_say"):
		main._say(t)
