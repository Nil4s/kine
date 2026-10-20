## SOUND CUES panel and preview (ROADMAP I35; the maths and the synthesis: scripts/sound_cues.gd).
## "Sound cues" derives the cues of the open scene (whoosh / hit / step), shows them as a lane on the timeline (a tick or icon per cue,
## its SIZE the strength) and lists them. While the scene plays, each cue sounds as the playhead passes it, through an
## AudioStreamGenerator (synthesized: no audio file). Mute toggles it. Export writes <scene>_cues.csv/.json next to the exports.
## Cues are derived, not saved: "Keep cues" turns them into scene markers of kind "sfx" (ONE undo step).
class_name SoundCuesUI
extends RefCounted

var m: Node
var cues: Array = []
var muted := false
var lane_on := false
var _sig := []           # what the cues were derived from (scene, cards, edit generation): a change drops the lane
var _player: AudioStreamPlayer = null
var _pb: AudioStreamGeneratorPlayback = null
var _voices: Array = []   # [{"s": PackedFloat32Array, "p": int}]
var _cache := {}          # kind|strength|pitch|len -> samples
var fired := 0            # cues sounded so far (tests read it)
var last_export := {}


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Sound cues", "", show, "sound cue cues whoosh hit footstep step sfx foley audio markers lane timeline derive",
		false, "derives sound cues from the motion: a whoosh at each weapon-tip / fist / foot speed peak, a hit at each contact (strength from the impulse), a step at each foot plant; drawn as a lane on the timeline and played in step with playback")
	add.call("Sound cues: mute / unmute", "", toggle_mute, "sound cue cues mute unmute silence audio", false, "mutes or unmutes the cue sounds of the preview (the cues and the lane stay)")


func toggle_mute() -> void:
	muted = not muted
	_voices.clear()
	m._say("sound cues %s" % ("muted: press Mute again to hear them" if muted else "on: they sound as the scene plays"))
	if m.ui_find != null and m.ui_find.visible and lane_on:
		_panel()


func _signature() -> Array:
	return [m.S, m.S.cards.size(), snappedf(m.S.length(), 0.001), m._dm_gen, m.actors_rt.size()]


func halt() -> void:
	_voices.clear()


func clear() -> void:
	cues = []
	lane_on = false
	_overlay()


## the actors the cues are derived from: the fighters when there are 2+, else the open scene alone
func actors() -> Array:
	m._actors_sync()
	if m.actors_rt.size() >= 2:
		return m.actors_rt
	return [{"S": m.S, "B": m.B, "xf": Transform3D.IDENTITY, "name": "the hero"}]


func compute() -> void:
	var acts := actors()
	var rows := []
	if acts.size() >= 2:   # the contacts, measured on clones (as the hit commands do)
		var hs: Scene = (acts[0]["S"] as Scene).clone()
		var others := []
		for i in range(1, acts.size()):
			others.append({"name": acts[i]["name"], "S": (acts[i]["S"] as Scene).clone(), "xf": acts[i]["xf"]})
		rows = m._fighters_measure(hs, others)["hits"]
	cues = SoundCues.derive(acts, rows)
	lane_on = true
	_sig = _signature()
	_voices.clear()
	_overlay()


func _overlay() -> void:
	var tl = m.ui_timeline
	if tl == null:
		return
	tl.sc = cues.map(func(c): return {"t": float(c["t"]), "kind": String(c["kind"]), "strength": float(c["strength"])}) if lane_on else []
	m._tl_height()
	tl.queue_redraw()


func counts() -> Dictionary:
	var d := {}
	for c in cues:
		d[c["kind"]] = int(d.get(c["kind"], 0)) + 1
	return d


func show() -> void:
	if m.S.cards.size() < 2:
		m._say("sound cues need a move: clip at least two poses first, then press Sound cues")
		return
	compute()
	_panel()
	m._say("sound cues: %s" % summary())


func summary() -> String:
	if cues.is_empty():
		return "none found (no weapon, fist or foot fast enough, no contact, no foot plant): add a strike or a foot plant, then Recompute"
	var parts := []
	for k in SoundCues.KINDS:
		if counts().has(k):
			parts.append("%d %s" % [counts()[k], k.replace("_", " ")])
	return "%d cues  -  %s" % [cues.size(), ", ".join(parts)]


func _panel() -> void:
	var L: VBoxContainer = m.ui_find_list
	for c in L.get_children():
		L.remove_child(c)
		c.queue_free()
	var head := HBoxContainer.new()
	L.add_child(head)
	var title: Label = m._label("SOUND CUES  -  %s" % summary(), 14, "heading", true)
	title.name = "sc_title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.custom_minimum_size = Vector2(320, 0)
	head.add_child(title)
	head.add_child(m._button("Close", _close))
	var row := HBoxContainer.new()
	var mb: Button = m._button("Unmute" if muted else "Mute", toggle_mute, "the cue sounds of the preview on / off")
	mb.name = "sc_mute"
	row.add_child(mb)
	var rb: Button = m._button("Recompute", show, "derive the cues again from the scene as it is now")
	rb.name = "sc_recompute"
	row.add_child(rb)
	var eb: Button = m._button("Export cue sheet", export_sheet, "writes <scene>_cues.csv and .json (time, frame, kind, strength, source) in exports/")
	eb.name = "sc_export"
	row.add_child(eb)
	var kb: Button = m._button("Keep cues", keep, "turns the cues into markers of kind sfx on the timeline: one undo step")
	kb.name = "sc_keep"
	row.add_child(kb)
	L.add_child(row)
	var exp: Label = m._label("A whoosh marks each speed peak of the weapon tip (8 m/s and up; for an unarmed fighter, hands over 5 m/s and feet over 6 m/s), a hit each contact, a step each foot plant. The size of a mark is its strength. The cues are not saved with the scene until you press Keep cues.", 12, "text:0.6", true)
	exp.custom_minimum_size = Vector2(380, 0)
	L.add_child(exp)
	for i in mini(cues.size(), 14):
		var c: Dictionary = cues[i]
		var l: Label = m._label("%.2fs  f%d  %s  %.2f  %s" % [c["t"], c["frame"], String(c["kind"]).replace("_", " "), c["strength"], c["source"]], 12, "text:0.8", true)
		l.name = "sc_row_%d" % i
		L.add_child(l)
	if cues.size() > 14:
		L.add_child(m._label("... and %d more (all of them are in the lane and the cue sheet)" % (cues.size() - 14), 12, "text:0.6", true))
	(m.ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(460, clampf(180.0 + 18.0 * mini(cues.size(), 14), 220.0,
		minf(520.0, m.get_viewport().get_visible_rect().size.y - m.bottom_h - 82 - (m.TOP_H + 12) - 26)))
	m.ui_find.visible = true


func _close() -> void:
	m.ui_find.visible = false


## the cue sheet next to the other exports
func export_sheet(dir := "res://exports", name := "") -> Dictionary:
	if cues.is_empty():
		compute()
	if cues.is_empty():
		m._say("no cues to write: add a strike, a contact or a foot plant, then press Sound cues")
		return {"ok": false}
	var r := SoundCues.write_sheet(dir, name if name != "" else m._export_base(), cues, m.S.fps)
	last_export = r
	if r["ok"]:
		m._say("cue sheet written: %s and %s (%d cues)" % [String(r["csv"]).get_file(), String(r["json"]).get_file(), cues.size()])
	else:
		m._say(String(r["why"]))
	return r


## the cues as scene markers of kind "sfx": ONE undo step
func keep() -> int:
	if cues.is_empty():
		m._say("no cues to keep: press Sound cues first")
		return 0
	m._push_undo()
	for c in cues:
		var mk := Markers.clean({"t": float(c["t"]), "name": "sfx " + String(c["kind"]).replace("_", " "), "kind": "sfx",
			"note": "%s, strength %.2f, %s" % [c["kind"], c["strength"], c["source"]]})
		m.S.markers.append(mk)
	m.S.markers = Markers.sorted(m.S.markers)
	m._markers_changed()
	m._say("%d cues kept as sfx markers.  Ctrl+Z takes them back" % cues.size())
	return cues.size()


# ------------------------------------------------------------------ the preview

func _ensure_audio() -> bool:
	if _pb != null:
		return true
	if m.get_tree() == null:
		return false
	_player = AudioStreamPlayer.new()
	_player.name = "SoundCuesPlayer"
	var g := AudioStreamGenerator.new()
	g.mix_rate = SoundCues.RATE
	g.buffer_length = 0.5
	_player.stream = g
	m.add_child(_player)
	_player.play()
	_pb = _player.get_stream_playback() as AudioStreamGeneratorPlayback
	return _pb != null


func samples_of(c: Dictionary) -> PackedFloat32Array:
	var key := "%s|%.2f|%d|%.2f" % [c["kind"], c["strength"], roundi(float(c.get("pitch", 0.0)) / 50.0), float(c.get("len", 0.0))]
	if not _cache.has(key):
		_cache[key] = SoundCues.synth(String(c["kind"]), float(c["strength"]), float(c.get("pitch", 900.0)), float(c.get("len", 0.25)))
	return _cache[key]


## each frame (main's _process, after the playhead moved from `before` to `now`): the cues the playhead passed start sounding; the
## voices are mixed into the generator. A loop (now < before) sounds the cues after `before` and up to `now`.
func tick(before: float, now: float, playing: bool, dt := 0.0167) -> void:
	if not lane_on:
		return
	if _sig != _signature():   # the scene changed: the cues are of the old one
		clear()
		return
	if playing and not muted:
		for c in cues:
			var t := float(c["t"])
			var hit: bool = (t > before and t <= now) if now >= before else (t > before or t <= now)
			if hit:
				_voices.append({"s": samples_of(c), "p": 0})
				fired += 1
	if _voices.is_empty() or muted:
		return
	if not _ensure_audio():
		return
	var n := mini(_pb.get_frames_available(), clampi(int(dt * SoundCues.RATE * 1.5), 512, SoundCues.RATE))   # a little more than this frame's share: a cue that starts later is not queued behind a long tail
	if n <= 0:
		return
	var buf := PackedVector2Array()
	buf.resize(n)
	var live := []
	for i in n:
		var v := 0.0
		for vo in _voices:
			var s: PackedFloat32Array = vo["s"]
			if vo["p"] < s.size():
				v += s[vo["p"]]
				vo["p"] += 1
		v = clampf(v, -1.0, 1.0)
		buf[i] = Vector2(v, v)
	for vo in _voices:
		if vo["p"] < (vo["s"] as PackedFloat32Array).size():
			live.append(vo)
	_voices = live
	_pb.push_buffer(buf)
