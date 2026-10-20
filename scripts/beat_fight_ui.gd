## FIGHT TO THE BEAT panel (ROADMAP I15; the maths: scripts/beat_fight.gd). Kept out of main.gd like TimingCoachUI.
##   "Fit the fight to the beat" opens the panel in the CHECK list: choose the grid (every beat / every 2nd beat / downbeats only)
##   and on-beat or off-beat; the result shows what moved and which contact was FLAGGED (and why). The timeline shows the
##   beat ticks, the fitted contacts on them and the flagged ones. Preview plays the new timing WITHOUT changing the scene;
##   Accept writes it as ONE undo step.
class_name BeatFightUI
extends RefCounted

var m: Node
var mode := "every"
var offbeat := false
var res: Dictionary = {}
var pv: Scene = null
var pv_t := 0.0
var pv_end := 0.0
var off_s := 0.0


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Fit the fight to the beat", "", show, "beats fight music contact beat rhythm sync off-beat downbeat strike timing retime preview accept",
		false, "move each contact (hit) onto a beat of the music, or the off-beat, by retiming the moves before it; a strike never leaves the timing coach's human range, a contact that cannot be reached is flagged; Preview, then Accept (one undo step)")


func halt() -> void:
	pv = null


func clear_overlay() -> void:
	res = {}
	pv = null
	_overlay()


func _music_offset() -> float:
	var mi := AudioTrack.index_of_role(m.S.audio_tracks, "music")
	return float(m.S.audio_tracks[mi]["offset"]) if mi >= 0 else 0.0


func compute() -> void:
	var trial: Scene = m.S.clone()
	off_s = _music_offset()
	res = BeatFight.fit(trial, m.B, m.S.beats_audio, off_s, mode, offbeat)
	res["scene"] = trial
	m._ps().apply(m.B, m.playhead)   # fit posed the body at other times
	_overlay()


func _overlay() -> void:
	var tl = m.ui_timeline
	if tl == null:
		return
	var marks := []
	var gridt := []
	if not res.is_empty():
		gridt = res.get("grid", [])
		for f in res.get("fits", []):
			marks.append({"t": float(f["to"]), "ok": true})
		for f in res.get("flags", []):
			marks.append({"t": float(f["t"]), "ok": false, "why": String(f["why"])})
	tl.bf = marks
	tl.bf_grid = gridt
	tl.queue_redraw()


func show() -> void:
	if m.S.beats_audio.is_empty():
		m._say("no beats yet: run Beats: find the beats in the sound first (add a wav with the music role), then Fit the fight to the beat")
		return
	if m.S.cards.size() < 2:
		m._say("Fit the fight to the beat needs a scene of two cards or more: press Enter to add the body as a card (two at least)")
		return
	compute()
	_panel()


func set_grid(md: String, off: bool) -> void:
	mode = md
	offbeat = off
	compute()
	_panel()


func _panel() -> void:
	var L: VBoxContainer = m.ui_find_list
	for c in L.get_children():
		L.remove_child(c)
		c.queue_free()
	var flags: Array = res.get("flags", [])
	var fits: Array = res.get("fits", [])
	var head := HBoxContainer.new()
	L.add_child(head)
	var title: Label = m._label("FIGHT TO THE BEAT  -  %s" % String(res.get("msg", "")), 14, "warn" if not flags.is_empty() or not res.get("ok", false) else "heading", true)
	title.name = "bf_title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(m._button("Close", _close))
	L.add_child(m._label("Each contact lands on a beat by retiming the moves before it; a strike never goes outside the recorded human range (timing coach). Preview changes nothing; Accept is one undo step (Ctrl+Z).", 13, "text:0.6", true))
	var r1 := HBoxContainer.new()
	for o in [["Every beat", "every"], ["Every 2nd beat", "every2"], ["Downbeats only", "down"]]:
		var b: Button = m._button(("> " if mode == o[1] else "") + String(o[0]), set_grid.bind(String(o[1]), offbeat), "land the contacts on %s" % String(o[0]).to_lower())
		b.name = "bf_grid_" + String(o[1])
		r1.add_child(b)
	L.add_child(r1)
	var r2 := HBoxContainer.new()
	var on: Button = m._button(("> " if not offbeat else "") + "On the beat", set_grid.bind(mode, false), "the contact lands exactly on the beat")
	on.name = "bf_on"
	var of: Button = m._button(("> " if offbeat else "") + "Off the beat", set_grid.bind(mode, true), "the contact lands half way between two beats")
	of.name = "bf_off"
	r2.add_child(on)
	r2.add_child(of)
	L.add_child(r2)
	var row := HBoxContainer.new()
	var pb: Button = m._button("Preview", preview, "play the fight with the new timing; the scene is not changed")
	pb.name = "bf_preview"
	var ab: Button = m._button("Accept", accept, "write the new timing; one undo step")
	ab.name = "bf_accept"
	row.add_child(pb)
	row.add_child(ab)
	L.add_child(row)
	for f in fits:
		var chg: Array = f["changes"]
		var txt := "card %d  %.2f s -> %.2f s (beat %.2f s)" % [int(f["card"]) + 1, float(f["from"]), float(f["to"]), float(f["beat"])]
		if chg.is_empty():
			txt += "  already on it"
		else:
			var parts := []
			for c in chg:
				parts.append("card %d move %.2f -> %.2f s" % [int(c[0]) + 1, float(c[1]), float(c[2])])
			txt += "  (" + ", ".join(parts) + ")"
		L.add_child(m._label(txt, 13, "text:0.85", true))
	for f in flags:
		var lb: Label = m._label("FLAGGED  -  " + String(f["why"]), 13, "warn", true)
		lb.custom_minimum_size = Vector2(380, 0)
		L.add_child(lb)
	(m.ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(400, clampf(230.0 + 44.0 * (fits.size() + flags.size()), 230.0,
		minf(520.0, m.get_viewport().get_visible_rect().size.y - m.bottom_h - 82 - (m.TOP_H + 12) - 26)))
	m.ui_find.visible = true
	m._say("fight to the beat: " + String(res.get("msg", "")) + (".  Preview plays it, Accept writes it (Ctrl+Z undoes)" if res.get("ok", false) else ""))


func _close() -> void:
	clear_overlay()
	m._close_findings()


func preview() -> void:
	if not res.get("ok", false):
		m._say("nothing to preview: " + String(res.get("msg", "pick another grid")))
		return
	pv = (res["scene"] as Scene).clone()
	pv_t = 0.0
	pv_end = pv.length()
	m.playing = false
	m._say("fight to the beat: previewing the new timing (the scene is not changed)")


func tick(dt: float) -> void:
	if pv == null:
		return
	pv_t += dt
	if pv_t >= pv_end:
		pv = null
		m._ps().apply(m.B, m.playhead)
		m._refresh()
		return
	pv.apply(m.B, pv_t)
	m._refresh()


func accept() -> void:
	if not res.get("ok", false):
		m._say("nothing to accept: " + String(res.get("msg", "pick another grid")))
		return
	pv = null
	var trial: Scene = res["scene"]
	var msg := String(res["msg"])
	m._step_hint = "Fit the fight to the beat"
	m._push_undo()
	m._markers_hold()
	m.S.cards = trial.cards.duplicate(true)
	m._markers_follow()
	m._retimed()
	m._say("fight to the beat: %s.  Ctrl+Z undoes it in one step" % msg)
	compute()   # the contacts now sit on the beat: the overlay follows the scene
	res["msg"] = msg
	_panel()
