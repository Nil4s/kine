## MY STYLE panel (ROADMAP I17; the maths: scripts/style_print.gd). Kept out of main.gd like BeatFightUI.
##   "My style" opens the fingerprint of Nick's own clips in the CHECK list: per move kind his median move and hold next to the
##   neutral default, the guard height and stance, his usual transitions, each with how many clips it came from.
##   "Like Nick / Neutral" decides what a NEW card gets (Add card, a taken Next pose): his median for its kind, or the fixed default.
##   "Use my style" retimes the clip toward the medians: Preview plays it on a copy (the scene is not changed), Accept is ONE undo step.
class_name StyleUI
extends RefCounted

var m: Node
var on := true                       # like Nick (true) / neutral
var fp: Dictionary = {}              # the fingerprint ({} = not read yet)
var path := StylePrint.PATH          # a test points this at its own file under user://
var dirs: Array = ["res://scenes/"]  # read-only
var pl: Array = []
var pv: Scene = null
var pv_t := 0.0
var pv_end := 0.0
var ms := 0.0


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("My style", "", show, "my style learn fingerprint median timing strike wind-up guard stance transitions like nick neutral",
		false, "the fingerprint of your own clips: your median move and hold per kind of move, guard height, stance width and usual transitions, each from how many clips")
	add.call("Use my style", "", use_style, "use my style retime clip toward my median timing strike wind-up recover preview accept human range",
		false, "retime this clip toward your own median move and hold per kind of move, never outside the timing coach's human range; Preview, then Accept (one undo step)")


func halt() -> void:
	pv = null


## read the saved fingerprint, or learn it from the clips once
func ensure(force := false) -> Dictionary:
	if force or fp.is_empty():
		if not force:
			fp = StylePrint.load_print(path)
		if force or fp.is_empty():
			var t0 := Time.get_ticks_usec()
			var paths: Array = []
			for d in dirs:
				paths.append_array(StylePrint.clip_paths(String(d)))
			fp = StylePrint.compute(paths, m.B)
			ms = float(Time.get_ticks_usec() - t0) / 1000.0
			StylePrint.save(fp, path)
			m._ps().apply(m.B, m.playhead)   # compute posed the body at other times
	return fp


## a card newly added at `at` takes his median for its kind (when like-Nick is on and there is one); false = left as it is
func new_card(S: Scene, at: int) -> bool:
	if not on or at < 1 or at >= S.cards.size():
		return false
	var tg := StylePrint.target(ensure(), StylePrint.kind_of(S, at))
	if tg.is_empty():
		return false
	S.cards[at]["move"] = float(tg["move"])
	S.cards[at]["hold"] = float(tg["hold"])
	return true


func show() -> void:
	ensure(true)
	_panel()


func toggle(v: bool) -> void:
	on = v
	_panel()
	m._say("new cards now take %s" % ("your median timing for their kind" if on else "the fixed default (neutral)"))


func _panel() -> void:
	var L: VBoxContainer = m.ui_find_list
	for c in L.get_children():
		L.remove_child(c)
		c.queue_free()
	var n := int(fp.get("clips", 0))
	var enough := bool(fp.get("enough", false))
	var head := HBoxContainer.new()
	L.add_child(head)
	var title: Label = m._label("MY STYLE  -  " + StylePrint.source_text(n), 14, "heading" if enough else "warn", true)
	title.name = "style_title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(m._button("Close", m._close_findings))
	L.add_child(m._label("Read from your own clips in scenes/ (never changed). Your median beside the neutral default a new card gets otherwise.", 13, "text:0.6", true))
	var r := HBoxContainer.new()
	var lk: Button = m._button(("> " if on else "") + "Like Nick", toggle.bind(true), "new cards take your median move and hold for their kind")
	lk.name = "style_like"
	var ne: Button = m._button(("> " if not on else "") + "Neutral", toggle.bind(false), "new cards take the fixed default (move from the angles, hold 0.30 s)")
	ne.name = "style_neutral"
	r.add_child(lk)
	r.add_child(ne)
	var lb: Button = m._button("Learn again", show, "read your clips again and save the fingerprint")
	lb.name = "style_learn"
	r.add_child(lb)
	L.add_child(r)
	var rows := 0
	var kinds: Dictionary = fp.get("kinds", {})
	for k in StylePrint.KINDS:
		if not kinds.has(k):
			continue
		var e: Dictionary = kinds[k]
		var t: Label = m._label("%s:  you move %.2f s, hold %.2f s  |  neutral: auto, hold 0.30 s  |  %d cards from %d clip%s" % [
			StylePrint.LABEL[k], float(e["move"]), float(e["hold"]), int(e["n"]), int(e["clips"]), "" if int(e["clips"]) == 1 else "s"], 13, "text:0.85", true)
		t.name = "style_row_" + k
		t.custom_minimum_size = Vector2(460, 0)
		L.add_child(t)
		rows += 1
	if fp.has("guard"):
		var g: Dictionary = fp["guard"]
		var hc := float(g["hand_cm"])
		var gl: Label = m._label("guard hands %.0f cm %s the chin, stance %.2f x hip width  |  %d guard cards from %d clip%s" % [
			absf(hc), "above" if hc >= 0.0 else "below", float(g["stance"]), int(g["n"]), int(g["clips"]), "" if int(g["clips"]) == 1 else "s"], 13, "text:0.85", true)
		gl.name = "style_guard"
		gl.custom_minimum_size = Vector2(460, 0)
		L.add_child(gl)
		rows += 1
	var tr: Array = fp.get("transitions", [])
	if not tr.is_empty():
		var parts := []
		for e in tr:
			var ab := String(e[0]).split(">")
			parts.append("%s > %s x%d" % [StylePrint.LABEL.get(ab[0], ab[0]), StylePrint.LABEL.get(ab[1], ab[1]), int(e[1])])
		var tl: Label = m._label("usual transitions: " + ",  ".join(parts), 13, "text:0.85", true)
		tl.name = "style_trans"
		tl.custom_minimum_size = Vector2(460, 0)
		L.add_child(tl)
		rows += 1
	if not enough:
		L.add_child(m._label("Not enough to learn from yet: save %d or more clips with cards you timed yourself, then Learn again. Until then new cards keep the fixed default." % StylePrint.MIN_CLIPS, 13, "warn", true))
	(m.ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(440, clampf(210.0 + 34.0 * rows, 230.0,
		minf(520.0, m.get_viewport().get_visible_rect().size.y - m.bottom_h - 82 - (m.TOP_H + 12) - 26)))
	m.ui_find.visible = true
	m._say("my style: " + StylePrint.source_text(n))


## "Use my style": the plan, listed in the panel with Preview and Accept
func use_style() -> void:
	ensure()
	if not bool(fp.get("enough", false)):
		m._say("my style: " + StylePrint.source_text(int(fp.get("clips", 0))) + "; save more clips, then My style > Learn again")
		_panel()
		return
	if m.S.cards.size() < 2:
		m._say("Use my style needs a scene of two cards or more: press Enter to add the body as a card (two at least)")
		return
	pl = StylePrint.plan(m.S, m.B, fp)
	m._ps().apply(m.B, m.playhead)
	_plan_panel()


func _plan_panel() -> void:
	var L: VBoxContainer = m.ui_find_list
	for c in L.get_children():
		L.remove_child(c)
		c.queue_free()
	var head := HBoxContainer.new()
	L.add_child(head)
	var title: Label = m._label("USE MY STYLE  -  %s" % ("%d card%s move toward your medians" % [pl.size(), "" if pl.size() == 1 else "s"] if not pl.is_empty() else "this clip is already at your medians"), 14, "heading", true)
	title.name = "style_plan_title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(m._button("Close", m._close_findings))
	L.add_child(m._label("Each card moves toward your median for its kind (%s). A strike never leaves the timing coach's human range. Preview changes nothing; Accept is one undo step (Ctrl+Z)." % StylePrint.source_text(int(fp.get("clips", 0))), 13, "text:0.6", true))
	var row := HBoxContainer.new()
	var pb: Button = m._button("Preview", preview, "play the clip with your timing; the scene is not changed")
	pb.name = "style_preview"
	var ab: Button = m._button("Accept", accept, "write your timing; one undo step")
	ab.name = "style_accept"
	row.add_child(pb)
	row.add_child(ab)
	L.add_child(row)
	for p in pl:
		L.add_child(m._label("card %d (%s)  move %.2f -> %.2f s,  hold %.2f -> %.2f s" % [int(p["card"]) + 1, StylePrint.LABEL[p["kind"]],
			float(p["mv_from"]), float(p["mv_to"]), float(p["hd_from"]), float(p["hd_to"])], 13, "text:0.85", true))
	(m.ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(440, clampf(200.0 + 26.0 * pl.size(), 230.0,
		minf(520.0, m.get_viewport().get_visible_rect().size.y - m.bottom_h - 82 - (m.TOP_H + 12) - 26)))
	m.ui_find.visible = true
	m._say("use my style: %d card%s; Preview plays it, Accept writes it (Ctrl+Z undoes)" % [pl.size(), "" if pl.size() == 1 else "s"])


func preview() -> void:
	if pl.is_empty():
		m._say("nothing to preview: this clip is already at your medians; time a card by hand, or pick another clip")
		return
	pv = StylePrint.with_applied(m.S, pl)
	pv_t = 0.0
	pv_end = pv.length()
	m.playing = false
	m._say("use my style: previewing your timing (the scene is not changed)")


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
	if pl.is_empty():
		m._say("nothing to accept: this clip is already at your medians; time a card by hand, or pick another clip")
		return
	pv = null
	var n := pl.size()
	m._step_hint = "Use my style"
	m._push_undo()
	m._markers_hold()
	StylePrint.apply_plan(m.S, pl)
	m._markers_follow()
	m._retimed()
	m._say("use my style: %d card%s retimed toward your medians.  Ctrl+Z undoes it in one step" % [n, "" if n == 1 else "s"])
	pl = StylePrint.plan(m.S, m.B, fp)
	m._ps().apply(m.B, m.playhead)
	_plan_panel()
