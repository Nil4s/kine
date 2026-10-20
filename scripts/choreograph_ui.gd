## CHOREOGRAPH TO THE SONG panel (ROADMAP I22; the maths: scripts/choreograph.gd). Kept out of main.gd like BeatFightUI.
##   "Choreograph to the song" reads the loudness of the music track, lays out a two-fighter fight on its bars (loud bar = a combo, quiet
##   bar = a pause, the biggest strike on the loudest downbeat, every contact on a beat) and shows it on the timeline: the energy of every
##   beat as a strip, the planned contacts as gold diamonds. Preview plays the attacker; Accept writes a NEW scene (scenes/_wip, never
##   over a file: _2, _3) and opens it, then runs Check on it. The open scene is never written.
class_name ChoreographUI
extends RefCounted

var m: Node
var res: Dictionary = {}
var energy: Array = []
var pv: Scene = null
var pv_t := 0.0
var pv_end := 0.0
var out_dir := "res://scenes/_wip"   # a test points this at user://
var paths: Array = []                # the clips the bank is read from; [] = Nick's clips (StylePrint.clip_paths)
var style_fp: Dictionary = {}        # the I17 fingerprint, when the style panel has one
var saved := ""                      # the file Accept wrote
var summary := ""                    # Check's summary on the written scene


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Choreograph to the song", "", show, "choreograph song music energy bars fight combo downbeat beat strike plan two fighters loud quiet exchange",
		false, "read the loudness of the music and lay out a two-fighter fight on its bars: more strikes in loud bars, a pause in quiet ones, the biggest strike on the loudest downbeat, every contact on a beat, each inside the human strike range; Preview, then Accept writes a NEW scene")


func halt() -> void:
	pv = null


func clear_overlay() -> void:
	res = {}
	pv = null
	_overlay()


func _music() -> int:
	return AudioTrack.index_of_role(m.S.audio_tracks, "music")


func compute() -> void:
	res = {}
	var mi := _music()
	if mi < 0:
		m._say("no music track: add the song as a wav with the music role (the timeline's sound lane), run Beats: find the beats, then Choreograph to the song")
		return
	if m.S.beats_audio.is_empty():
		m._say("no beats yet: run Beats: find the beats in the sound first, then Choreograph to the song")
		return
	var tr: Dictionary = m.S.audio_tracks[mi]
	var en := Choreograph.energy(AudioTrack.load_stream(String(tr["path"])), m.S.beats_audio)
	if not en["ok"]:
		m._say(String(en["msg"]))
		return
	energy = en["rms"]
	var ps: Array = paths if not paths.is_empty() else StylePrint.clip_paths()
	var bk := Choreograph.bank(ps, m.B)
	var off := float(tr["offset"])
	res = Choreograph.plan(m.B, m.S.beats_audio, off, energy, bk, style_fp)
	if res.get("ok", false):
		var A: Scene = res["scene"]
		A.audio_tracks = m.S.audio_tracks.duplicate(true)
		A.beats_audio = m.S.beats_audio.duplicate(true)
	m._ps().apply(m.B, m.playhead)
	_overlay()


func _overlay() -> void:
	var tl = m.ui_timeline
	if tl == null:
		return
	var marks := []
	var gridt := []
	var cg := []
	if res.get("ok", false):
		var mi := _music()
		var off := float(m.S.audio_tracks[mi]["offset"]) if mi >= 0 else 0.0
		var bs := BeatTrack.clean_list(m.S.beats_audio)
		var top := 0.0
		for v in energy:
			top = maxf(top, float(v))
		for k in bs.size():
			gridt.append(float(bs[k]["t"]) + off)
			var t1 := float(bs[k + 1]["t"]) + off if k + 1 < bs.size() else float(bs[k]["t"]) + off + 0.5
			cg.append({"t0": float(bs[k]["t"]) + off, "t1": t1, "e": float(energy[k]) / top if top > 0.0 and k < energy.size() else 0.0})
		for s in res["strikes"]:
			marks.append({"t": float(s["t"]), "ok": true})
	tl.bf = marks
	tl.bf_grid = gridt
	tl.cg = cg
	tl.cg_peak = float(res.get("peak_t", -1.0)) if res.get("ok", false) else -1.0
	tl.queue_redraw()


func show() -> void:
	compute()
	if res.is_empty():
		return
	_panel()


func _panel() -> void:
	var L: VBoxContainer = m.ui_find_list
	for c in L.get_children():
		L.remove_child(c)
		c.queue_free()
	var ok: bool = res.get("ok", false)
	var head := HBoxContainer.new()
	L.add_child(head)
	var title: Label = m._label("CHOREOGRAPH TO THE SONG  -  %s" % String(res.get("msg", "")), 14, "heading" if ok else "warn", true)
	title.name = "cg_title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(m._button("Close", _close))
	L.add_child(m._label("Loud bars get a combo, quiet bars a pause; the biggest strike lands on the loudest downbeat; every contact is on a beat and inside the recorded human strike range (timing coach). Preview changes nothing; Accept writes a NEW scene in scenes/_wip and opens it; your scene is not touched.", 13, "text:0.6", true))
	var row := HBoxContainer.new()
	var pb: Button = m._button("Preview", preview, "play the planned fight on the fighter; nothing is written")
	pb.name = "cg_preview"
	var ab: Button = m._button("Accept", accept, "write the plan as a NEW scene and open it, then run Check on it")
	ab.name = "cg_accept"
	row.add_child(pb)
	row.add_child(ab)
	L.add_child(row)
	if ok:
		for k in (res["bars"] as Array).size():
			var b: Dictionary = res["bars"][k]
			var kind := "pause" if int(b["n"]) == 0 else "%d strike%s" % [int(b["n"]), "" if int(b["n"]) == 1 else "s"]
			L.add_child(m._label("bar %d  %.1f s  energy %.0f %%  ->  %s" % [k + 1, float(b["t0"]), float(b["e"]) * 100.0, kind], 13, "text:0.85", true))
		var df: Dictionary = res.get("defence", {})
		L.add_child(m._label("the defender: " + (String(df.get("text", "")).replace("\n", "; ") if df.get("ok", false) else String(df.get("why", "no answer"))), 12, "text:0.7", true))
	if summary != "":
		var sl: Label = m._label("CHECK  -  " + summary, 13, "heading", true)
		sl.name = "cg_check"
		L.add_child(sl)
	(m.ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(400, clampf(180.0 + 24.0 * (res.get("bars", []) as Array).size(), 230.0,
		minf(520.0, m.get_viewport().get_visible_rect().size.y - m.bottom_h - 82 - (m.TOP_H + 12) - 26)))
	m.ui_find.visible = true
	m._say("choreograph: " + String(res.get("msg", "")) + (".  Preview plays it, Accept writes a new scene" if ok else ""))


func _close() -> void:
	clear_overlay()
	m._close_findings()


func preview() -> void:
	if not res.get("ok", false):
		m._say("nothing to preview: " + String(res.get("msg", "add the song and find its beats first")))
		return
	pv = (res["scene"] as Scene).clone()
	pv_t = 0.0
	pv_end = pv.length()
	m.playing = false
	m._say("choreograph: previewing the attacker (the scene is not changed; the defender's answers are in the scene Accept writes)")


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


## write the plan as a NEW scene file (never over a file), open it, run Check. Returns the path ("" = nothing written)
func accept() -> String:
	if not res.get("ok", false):
		m._say("nothing to accept: " + String(res.get("msg", "add the song and find its beats first")))
		return ""
	pv = null
	var A: Scene = res["scene"]
	var base := String(m.S.name) if String(m.S.name) != "" else "scene"
	var nm: String = String(m.safe_file(base + "_song")).trim_prefix("_wip/")
	var path := Templates.new_path(nm, out_dir)
	var d := A.to_dict(m.B)
	d["scene"] = path.get_file().get_basename()
	m._write(path, d)
	saved = path
	m._load_scene(path)
	m._rebuild_cards()
	m._refresh()
	m._check()
	var nf: int = m.findings.size()
	var must := (m.findings as Array).filter(func(f): return f["sev"] == "FAIL").size()
	summary = "%s: %s" % [path.get_file(), "clean" if nf == 0 else "%d findings, %d must fix" % [nf, must]]
	_overlay()
	_panel()
	m._say("choreograph: saved %s and opened it; '%s' is untouched.  Check: %s" % [path.get_file(), base, summary])
	return path
