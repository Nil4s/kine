## next_beat_ui.gd - NEXT BEAT IN THE APP (ROADMAP I44; the reading and the ranking: scripts/next_beat.gd). With two fighters, "View > Next poses" shows
## the NEXT BEATS of the exchange instead of the single fighter's next poses: a ranked list over the bottom of the view, one row per beat with the
## fighter it is for and a one-line WHY that names its evidence. Nothing in the scene changes until Enter:
##   Tab    the next beat in the list (a blue ghost stands on the fighter it is for, where the beat ends)     Esc   hide the list
##   Enter  (or a click on a row) inserts the beat's card(s) on that fighter at the playhead with Nick's timing: ONE undo step, the fighter becomes the
##          active one; the accept goes into the suggestion journal (I26) as source "next beat", so an undo within 30 s counts against that kind
## The set is worked out once per scene revision and playhead (cards, poses, moves and holds of both fighters), so Tab and redraws cost nothing; the
## fatigue (the heavy part: inverse dynamics) once per revision of the cards.
class_name NextBeatUI
extends RefCounted

const KIND_TOK := {"answer": "sg_habit", "continue": "sg_habit", "close": "sg_motion", "defend": "sg_phase", "strike": "sg_between", "reset": "sg_between"}

var m: Node
var res: Dictionary = {}
var list: Array = []
var sel := -1
var hidden := false
var _hid_sig: Array = []
var ms := 0.0              # how long the last set took (not counting the fatigue, which is cached per revision)
var ms_fatigue := 0.0      # how long the last fatigue reading took
var computes := 0          # how many sets were worked out (the cache test reads this)
var combos_override: Variant = null   # a test's own combos ([] = none); null = the mined ones
var cards_of := Callable()            # a test's own card source (default ComboMine.cards_for)
var pv: Scene = null       # the picked beat's fighter scene with the cards inserted (the ghost reads it)
var pv_t := 0.0
var pv_xf := Transform3D.IDENTITY
var hud: CanvasLayer
var panel: PanelContainer
var _sig: Array = []
var _fat_sig: Array = []
var _fat: Array = []
var _fat_task := -1        # the worker task reading the fatigue (inverse dynamics, ~1.6 s for a 5 s fight: never on the frame)
var _fat_job_sig: Array = []
var _fat_job := {}


func _init(main: Node) -> void:
	m = main


## the beat list is what View > Next poses shows while two fighters stand in the scene
func wants() -> bool:
	if hidden and not _same(_scene_sig(true), _hid_sig):
		hidden = false   # another playhead or an edit: the beats come back
	return m.sg_on and m._fighters_on() and not hidden and m.cur_page in ["POSE", "ANIMATE"] and not m.playing and m.ui_cards != null


func clear() -> void:
	list = []
	res = {}
	sel = -1
	pv = null
	_sig = []
	if panel != null and is_instance_valid(panel):
		panel.visible = false


func _scene_sig(with_t: bool) -> Array:
	var sig := []
	for a in m.actors_rt:
		var S: Scene = a["S"]
		var cs := []
		for c in S.cards:
			cs.append([c["pose"], float(c["move"]), float(c["hold"]), String(c["name"])])
		sig.append([S, cs])
	if with_t:
		sig.append(snappedf(float(m.playhead), 0.001))
	sig.append(m.sg_on)
	return sig


static func _same(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		var x: Variant = a[i]
		var y: Variant = b[i]
		if x is Array and y is Array:
			if not _same(x, y):
				return false
		elif x is Dictionary and y is Dictionary:
			if not is_same(x, y):
				return false
		elif x is Object or y is Object:
			if not is_same(x, y):
				return false
		elif x != y:
			return false
	return true


func combos() -> Array:
	if combos_override != null:
		return combos_override
	if m.cm_ui != null and not m.cm_ui.data.is_empty():
		return m.cm_ui.data.get("combos", [])
	var cache: String = m.cm_ui.cache if m.cm_ui != null else ComboMine.CACHE
	if FileAccess.file_exists(cache):
		var c: Variant = JSON.parse_string(FileAccess.get_file_as_string(cache))
		if c is Dictionary:
			return c.get("combos", [])
	return []


## every frame (via main's _sg_tick): worked out again only when a card of either fighter or the playhead moved
func tick() -> void:
	m._actors_sync()
	_fat_poll()
	var sig := _scene_sig(true)
	if not _sig.is_empty() and _same(sig, _sig):
		_place()
		return
	_sig = sig
	compute()


func compute() -> Dictionary:
	var fs := _scene_sig(false)
	if (_fat_sig.is_empty() or not _same(fs, _fat_sig)) and _fat_task < 0:
		_fat = []   # the cards changed: the old reading is not theirs; the new one comes from the worker
		_fat_sig = []
		_fat_job_sig = fs
		var scs: Array = m.actors_rt.map(func(a): return (a["S"] as Scene).clone())
		_fat_job = {}
		_fat_task = WorkerThreadPool.add_task(func():
			var t0 := Time.get_ticks_usec()
			_fat_job = {"fat": NextBeat.fatigue_of(scs), "ms": float(Time.get_ticks_usec() - t0) / 1000.0})
	var opt := {"combos": combos(), "fatigue": _fat, "journal": m.sj}
	if cards_of.is_valid():
		opt["cards_of"] = cards_of
	var keep: Dictionary = m.B.state()   # the reading poses bodies at other times: the live one is put back EXACTLY
	res = NextBeat.analyze(m.actors_rt.map(func(a): return a["S"]), m.actors_rt.map(func(a): return String(a["name"])),
		m.actors_rt.map(func(a): return a["xf"]), float(m.playhead), opt)
	m.B.set_state(keep)
	list = res["list"]
	ms = float(res["ms"])
	computes += 1
	sel = -1
	pv = null
	_panel()
	return res


## true while the fatigue reading is still being made (the beats come without it, then again with it)
## the worker ends (and is waited for) before the scenes it was given go
func finish() -> void:
	if _fat_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_fat_task)
		_fat_task = -1


func fat_pending() -> bool:
	return _fat_task >= 0


## per frame while the fatigue is being read; when it lands the set is made again (on the next _sg_tick)
func poll() -> void:
	var was := _fat_task >= 0
	_fat_poll()
	if was and _fat_task < 0:
		m._sg_tick()


func _fat_poll() -> void:
	if _fat_task >= 0 and WorkerThreadPool.is_task_completed(_fat_task):
		WorkerThreadPool.wait_for_task_completion(_fat_task)
		_fat_task = -1
		if _same(_scene_sig(false), _fat_job_sig):
			_fat = _fat_job["fat"]
			_fat_sig = _fat_job_sig
			ms_fatigue = float(_fat_job["ms"])
		_sig = []   # worked out again with the fatigue (or again for the cards that changed meanwhile)


func key(k: InputEventKey) -> bool:
	if not wants() or list.is_empty() or k.echo:
		return false
	var plain := not k.ctrl_pressed and not k.alt_pressed and not k.shift_pressed
	if k.keycode == KEY_TAB and plain:
		pick((sel + 1) % list.size())
		m._say("next beat %d of %d: %s.  Enter inserts it, Tab for the next, Esc hides" % [sel + 1, list.size(), list[sel]["label"]])
		return true
	if k.keycode in [KEY_ENTER, KEY_KP_ENTER] and plain and sel >= 0:
		accept(sel)
		return true
	if k.keycode == KEY_ESCAPE and plain:
		hidden = true
		_hid_sig = _scene_sig(true)
		clear()
		m.ov.fight_ghost(null, 0.0, Transform3D.IDENTITY)
		m._say("next beats hidden: pick another card, or View > Next poses, to bring them back")
		return true
	return false


## beat i is the picked one: its ghost stands on its fighter at the end of the beat
func pick(i: int) -> void:
	sel = i
	var c: Dictionary = list[i]
	var k := int(c["who"])
	var a: Dictionary = m.actors_rt[k]
	pv = (a["S"] as Scene).clone()
	var first := NextBeat.insert(pv, float(m.playhead), c["cards"])
	pv_t = NextBeat.ghost_time(pv, first, (c["cards"] as Array).size())
	pv_xf = a["xf"]
	_panel()
	m._refresh()


## the beat's cards go into its fighter at the playhead: ONE undo step
func accept(i: int) -> Dictionary:
	if i < 0 or i >= list.size():
		return {"ok": false}
	var c: Dictionary = list[i]
	var k := int(c["who"])
	m._actor_set(k)
	if int(m.actor_on) != k:
		m._say("Next beat: that fighter is read only here: press Co-edit: stop to animate it, then try again")
		return {"ok": false}
	var cards: Array = (c["cards"] as Array).duplicate(true)
	var base := float(cards[0]["move"])
	var d: float = m.sj.learned("next beat", String(c["kind"]))   # I26: the move time you always change this kind by, applied
	if not is_nan(d):
		cards[0]["move"] = maxf(0.04, base + d)
	m._step_hint = "Next beat: " + String(c["label"])
	m._push_undo()
	var first := NextBeat.insert(m.S, float(m.playhead), cards)
	var sj_s: Scene = m.S
	m.sj.log("next beat", String(c["kind"]), first, {"field": "move", "base": base, "applied": float(cards[0]["move"])}, m.undo.size(),
		func(): return sj_s.cards[first]["move"] if first < sj_s.cards.size() else null)
	m.sel_card = first + cards.size() - 1
	m.sel_end = -1
	m.actors_rt[k]["t"] = NAN
	var label := String(c["label"])
	clear()
	m.ov.fight_ghost(null, 0.0, Transform3D.IDENTITY)
	m._rebuild_cards()
	m.ov.mark_dirty()
	m.wt.mark_dirty()
	m._refresh()
	m._say("inserted for %s: %s (%d card%s at %.2f s).  Ctrl+Z takes it back" % [m.actors_rt[k]["name"], label, cards.size(), "" if cards.size() == 1 else "s", float(m.playhead)])
	return {"ok": true, "who": k, "first": first, "count": cards.size(), "t": float(m.playhead)}


# ---------------------------------------------------------------- drawing

func _ensure_hud() -> void:
	if hud != null and is_instance_valid(hud):
		return
	hud = CanvasLayer.new()
	hud.layer = 5
	m.add_child(hud)
	panel = PanelContainer.new()
	panel.name = "next_beat"
	var sty := StyleBoxFlat.new()
	sty.bg_color = Color(Tok.c("card"), 0.88)
	sty.set_corner_radius_all(6)
	sty.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", sty)
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hud.add_child(panel)


func _place() -> void:
	if panel != null and is_instance_valid(panel):
		panel.visible = not list.is_empty()
		var vs: Vector2 = m.get_viewport().get_visible_rect().size
		panel.offset_left = m.lw() + 12.0
		panel.offset_bottom = -(float(m.bottom_h) + 40.0)
		panel.custom_minimum_size.x = clampf(vs.x - m.lw() - m.rw() - 36.0, 260.0, 640.0)


func _panel() -> void:
	_ensure_hud()
	for ch in panel.get_children():
		panel.remove_child(ch)
		ch.queue_free()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	panel.add_child(v)
	if list.is_empty():
		v.add_child(m._label("NEXT BEAT  -  " + String(res.get("msg", "")), 13, "heading", true))
		_place()
		return
	v.add_child(m._label("NEXT BEAT at %.2f s  -  %s.  Tab picks, Enter inserts, Esc hides" % [float(m.playhead), String(res.get("msg", ""))], 12, "text:0.7", true))
	for i in list.size():
		var c: Dictionary = list[i]
		var row := PanelContainer.new()
		row.name = "beat_%d" % (i + 1)
		var rs := StyleBoxFlat.new()
		var col: Color = Tok.c(String(KIND_TOK.get(c["kind"], "sg_habit")))
		rs.bg_color = Color(col, 0.30 if i == sel else 0.08)
		rs.border_color = col
		rs.border_width_left = 4
		rs.set_content_margin_all(4)
		row.add_theme_stylebox_override("panel", rs)
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func(): pick(i) if i != sel else accept(i))
		b.tooltip_text = "Click to pick (ghost), click again or Enter to insert for %s" % c["label"]
		var vb := VBoxContainer.new()
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_theme_constant_override("separation", 0)
		var head: Label = m._label("%s%d  %s   (%.0f points of 100)" % ["> " if i == sel else "", i + 1, c["label"], float(c["score"]) * 100.0], 14, "text")
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var why: Label = m._label(String(c["why"]), 12, "text:0.8", true)
		why.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(head)
		vb.add_child(why)
		row.add_child(b)
		row.add_child(vb)
		v.add_child(row)
	_place()
