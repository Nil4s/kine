class_name PerfDoc
extends RefCounted
## ROADMAP_400 Q15: PERF DOCTOR. "Help: why is it slow?" plays the scene for a few seconds (or orbits the camera when the
## scene has one card) and times the app's own big blocks (main.gd brackets each with PerfDoc.t() / PerfDoc.add(name, t0)).
## Off (the default) a bracket is one static-bool test: no clock is read. Then it names the three heaviest systems by
## ms/frame, each with the fix as a button that runs an existing command (turn the onion off, lower the crowd, take the hair
## off...). After a fix it measures again and prints fps before -> after.
## The numbers beside them are the engine's own Performance monitors (TIME_PROCESS, draw calls, primitives, memory).

static var on := false
static var slow := false   # L12 (tests/perf60_test.gd): true = the reference paths of the PERF60 fixes (equality + before/after timing)
static var acc := {}     # name -> microseconds summed over the measured frames
static var burn := {}    # TEST-ONLY debug hook: name -> milliseconds busy-waited inside that bracket while measuring

const TOP := 3
## what each timed block is called in the report, and the advice when it has no button
const NAMES := {
	"onion": "Onion skin ghosts", "trail": "Motion trail", "skinning": "Skinning the body", "ui": "Panels and the bar",
	"actors": "Other fighters", "crowd": "Crowd", "cloth": "Cloth and cape", "hair": "Hair", "wtrail": "Weapon trail",
	"cshadow": "Contact shadow", "balance": "Balance overlay", "body": "Pose evaluation (play)", "live": "Live puppet",
	"timeline": "Timeline strip",
}
const ADVICE := {
	"skinning": "the body mesh itself: nothing to switch off. Hide the other fighters, or shrink the window.",
	"ui": "the panels redraw each frame: close the panels you are not using (View > panels).",
	"actors": "each extra fighter is a whole body to pose: hide or remove the ones you are not looking at.",
	"body": "the pose is evaluated every frame: fewer IK pins and foot plants make it cheaper.",
	"cshadow": "the contact shadow is cheap unless the floor is crowded.",
	"balance": "turn the balance view off in View.",
	"timeline": "the strip redraws while it plays: collapse the timeline.",
}

var m: Node
var running := false
var _t0 := 0.0           # msec at the start of the run
var _secs := 3.0
var _frames := 0
var _tp := []            # TIME_PROCESS (s) of each frame: the report shows the median (one slow frame must not set it)
var _was := {}           # the state the run borrowed and gives back
var _body = null         # the body as the run found it (its pose at the playhead moves while the scene plays)
var _after := false      # this run follows a fix
var last := {}           # the last result {"rows": [{"k","ms"}], "fps", "frame_ms", "draw", "prims", "mem_mb", "mode"}
var before := {}         # the result before a fix: the 'after' line compares to it
var fixed_name := ""
var panel: PanelContainer
var body: VBoxContainer
var done_cb := Callable()   # tests: called when a run ends


func _init(main: Node) -> void:
	m = main


## the bracket: the clock only when the doctor is measuring
static func t() -> int:
	return Time.get_ticks_usec() if on else 0


static var probe := false   # tests (animcpu): sum the whole _process of the app, apart from the doctor's brackets
static var proc_us := 0
static var proc_n := 0


static func add(k: String, t0: int) -> void:
	if not on:
		return
	if burn.has(k):
		var until := Time.get_ticks_usec() + int(float(burn[k]) * 1000.0)
		while Time.get_ticks_usec() < until:
			pass
	acc[k] = int(acc.get(k, 0)) + (Time.get_ticks_usec() - t0)


# ---------------------------------------------------------------- the run

func start(secs := 3.0, after_fix := false) -> void:
	if running:
		return
	_after = after_fix
	_secs = secs
	_frames = 0
	_tp = []
	acc = {}
	_was = {"playing": m.playing, "playhead": m.playhead, "yaw": m.yaw, "pitch": m.pitch}
	var play: bool = m.S.cards.size() >= 2
	_was["mode"] = "playback" if play else "orbit"
	if play:
		_body = m.B.state()
		m.playhead = 0.0
		m.playing = true
	if panel != null:
		panel.visible = false
	running = true
	on = true
	_t0 = Time.get_ticks_msec()
	m._say_plain("measuring for %.0f s (%s): keep the window as it is" % [secs, _was["mode"]])


## called from main._process once per frame while running
func tick(dt: float) -> void:
	if not running:
		return
	_frames += 1
	_tp.append(Performance.get_monitor(Performance.TIME_PROCESS))
	if _was["mode"] == "playback":
		if not m.playing:
			m.playhead = 0.0
			m.playing = true   # the clip ended: round again (a loop that is off must not shorten the sample)
	else:
		m.yaw += 60.0 * dt
		m._cam()
		m._refresh()   # the idle orbit redraws the scene each frame like playback does
	if float(Time.get_ticks_msec() - _t0) / 1000.0 >= _secs:
		_finish()


func _median(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return float(b[b.size() / 2])


func _finish() -> void:
	running = false
	on = false
	var wall := maxf(float(Time.get_ticks_msec() - _t0) / 1000.0, 1e-3)
	var n := maxi(_frames, 1)
	var rows := []
	var sum := 0.0
	for k in acc:
		var ms := float(acc[k]) / 1000.0 / n
		rows.append({"k": k, "ms": ms})
		sum += ms
	rows.sort_custom(func(a, b): return a["ms"] > b["ms"])
	var res := {
		"rows": rows, "fps": n / wall, "frame_ms": wall * 1000.0 / n, "mode": _was["mode"], "frames": n, "timed_ms": sum,
		"process_ms": _median(_tp) * 1000.0,
		"draw": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"prims": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"mem_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
	}
	if _body != null:
		m.B.set_state(_body)   # playing moved the body (root offset, ground): put it back as it was
		_body = null
	m.playing = bool(_was["playing"])
	m.playhead = float(_was["playhead"])
	m.yaw = float(_was["yaw"])
	m.pitch = float(_was["pitch"])
	m._cam()
	m._refresh()
	if not _after:
		before = res
		fixed_name = ""
	last = res
	show()
	m._say_plain("perf doctor: %.0f fps; the heaviest is %s" % [res["fps"], String(NAMES.get(res["rows"][0]["k"], res["rows"][0]["k"])) if not (res["rows"] as Array).is_empty() else "the engine's drawing"])
	if done_cb.is_valid():
		done_cb.call()


# ---------------------------------------------------------------- the report

## the top systems with their fix: [{"k", "name", "ms", "fix": Callable or invalid, "label", "text"}]
func top() -> Array:
	var out := []
	for r in last.get("rows", []):
		if out.size() >= TOP or float(r["ms"]) < 0.02:
			break
		var f := fix_for(r["k"])
		out.append({"k": r["k"], "name": NAMES.get(r["k"], r["k"]), "ms": r["ms"], "fix": f["run"], "label": f["label"], "text": f["text"]})
	return out


## the fix for a system: only commands and settings that exist. "run" invalid = advice only
func fix_for(k: String) -> Dictionary:
	var ov = m.ov
	match k:
		"onion":
			if ov.onion_on:
				return {"run": _fix_onion, "label": "Turn off onion skin", "text": "onion skin is on (%d before, %d after): off saves about %.1f ms a frame" % [ov.onion_before, ov.onion_after, _ms(k)]}
		"trail":
			if ov.trail_on:
				return {"run": func(): m._press(KEY_T), "label": "Turn off the motion trail", "text": "the motion trail is redrawn each frame"}
		"crowd":
			var n := int((m.S.crowd as Dictionary).get("n", 0))
			if n > Crowd.DEFAULT_N:
				return {"run": func(): m._crowd_make(Crowd.DEFAULT_N), "label": "Lower the crowd to %d" % Crowd.DEFAULT_N, "text": "crowd: %d actors, lower to %d (about %.1f ms a frame saved)" % [n, Crowd.DEFAULT_N, _ms(k) * (1.0 - float(Crowd.DEFAULT_N) / n)]}
			if n > 0:
				return {"run": m._crowd_remove, "label": "Remove the crowd", "text": "crowd: %d actors, each one poses a whole body" % n}
		"hair":
			if not m.S.hair.is_empty():
				return {"run": m._hair_clear, "label": "Take the hair off", "text": "the hair strands are drawn each frame"}
		"cloth":
			if not (m.S.secondary.get("items", []) as Array).is_empty():
				return {"run": m._sec_clear, "label": "Take the secondary motion off", "text": "cloth at full quality during playback: take it off while blocking"}
			if not m.S.cape.is_empty():
				return {"run": m._cape_clear, "label": "Take the cape off", "text": "the cape grid is drawn each frame"}
		"wtrail":
			if m.wt.ribbon_on:
				return {"run": m._wtrail_ribbon, "label": "Turn off the weapon ribbon", "text": "the weapon ribbon is redrawn each frame"}
		"live":
			if m.live.running:
				return {"run": m._live_toggle, "label": "Stop the webcam puppet", "text": "the live puppet runs the camera every frame"}
	return {"run": Callable(), "label": "", "text": ADVICE.get(k, "nothing to switch off here")}


func _ms(k: String) -> float:
	for r in last.get("rows", []):
		if r["k"] == k:
			return r["ms"]
	return 0.0


func _fix_onion() -> void:
	if m.ov.onion_parts_on:
		m._onion_set_parts(false)
	if m.ov.onion_on:
		m._press(KEY_O)


## the button: apply, then measure again (1.5 s) so the report can say fps before -> after
func apply_fix(k: String) -> void:
	var f := fix_for(k)
	if not (f["run"] as Callable).is_valid():
		m._say_plain("nothing to switch off for %s: %s" % [NAMES.get(k, k), f["text"]])
		return
	var keep := before
	(f["run"] as Callable).call()
	before = keep
	fixed_name = String(NAMES.get(k, k))
	start(1.5, true)


func show() -> void:
	if panel == null:
		panel = PanelContainer.new()
		panel.name = "perfdoc_panel"
		panel.anchor_left = 0.5
		panel.anchor_right = 0.5
		panel.offset_left = -300
		panel.offset_right = 300
		panel.offset_top = m.TOP_H + 30
		m.ui_root.add_child(panel)
		body = VBoxContainer.new()
		body.custom_minimum_size = Vector2(580, 0)
		panel.add_child(body)
	for c in body.get_children():
		c.queue_free()
		body.remove_child(c)
	body.add_child(m._label("WHY IS IT SLOW?", 22, "heading"))
	var l: Dictionary = last
	body.add_child(m._label("%.0f fps (%.1f ms a frame) over %d frames of %s. Engine: process %.1f ms, %d draw calls, %d triangles, %.0f MB." % [l["fps"], l["frame_ms"], l["frames"], l["mode"], l["process_ms"], l["draw"], l["prims"], l["mem_mb"]], 15, "text", true))
	if fixed_name != "" and not before.is_empty():
		body.add_child(m._label("After %s: %.0f fps -> %.0f fps (%.1f ms -> %.1f ms a frame)" % [fixed_name, before["fps"], l["fps"], before["frame_ms"], l["frame_ms"]], 16, "say", true))
	var rows := top()
	if rows.is_empty():
		body.add_child(m._label("Nothing the app times shows up: the time is in the engine's drawing. Try a smaller window.", 15, "text", true))
	var rank := 0
	for r in rows:
		rank += 1
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		h.add_child(m._label("%d  %s  %.2f ms" % [rank, r["name"], r["ms"]], 16, "text"))
		body.add_child(h)
		body.add_child(m._label(r["text"], 14, "text:0.7", true))
		if (r["fix"] as Callable).is_valid():
			var b: Button = m._button(r["label"], apply_fix.bind(r["k"]))
			b.name = "fix_" + String(r["k"])
			body.add_child(b)
	body.add_child(m._button("Close", func(): panel.visible = false))
	panel.visible = true
