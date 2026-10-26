## TIMING COACH panel (ROADMAP I4; the maths: scripts/timing_coach.gd). Kept out of main.gd: main makes one (main.tc_ui),
## lists its command, and calls tick() each frame (the preview).
##   "Timing coach"   opens the list in the CHECK panel: each line says what to change and why (real clip + principle numbers).
##                    Preview plays the suggested timing around that card WITHOUT changing the scene; Accept writes that one
##                    line (one undo step); Accept all writes every line (one undo step).
class_name TimingCoachUI
extends RefCounted

const LEAD_IN := 0.4    # s before the move the preview starts
const LEAD_OUT := 0.5   # s after the card's arrival the preview runs on

var m: Node
var db: Dictionary = {}
var sugs: Array = []
var ms := 0.0           # the last compute, in ms
var pv: Scene = null    # the preview's scene (a clone with the suggested timing); null = not previewing
var pv_t := 0.0
var pv_end := 0.0


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Timing coach", "", show, "timing coach suggest better move time strike speed anticipation follow-through real clip principles preview accept",
		false, "for each strike: a better move time with the reason (a real clip in your scenes that does the same pose pair, and the strike-size and wind-up numbers with their sources); Preview plays it without changing the scene; Accept per line or Accept all, one undo step each")


var _reading := false

## the timing database, read a few scenes per frame; a second click while it reads cancels it
func _database() -> bool:
	if int(db.get("n", 0)) == 0:
		if _reading:
			FrameMemo.abort = true
			m._say("reading your scenes cancelled")
			return false
		_reading = true
		m._say("timing coach: reading your scenes (once, about 20 s)...")
		FrameMemo.slice_begin(8.0, func(f: float): m._say_plain("reading your scenes... %d%%  (click again to cancel)" % int(f * 100.0)))
		var r: Dictionary = await MotionMatch.build_co()
		var stopped := FrameMemo.abort
		FrameMemo.slice_end()
		_reading = false
		if stopped:
			return false
		db = r
	return int(db.get("n", 0)) > 0


func halt() -> void:
	if pv != null:
		pv = null


func show() -> void:
	if m.S.cards.size() < 2:
		m._say("Timing coach needs a scene of two cards or more: press Enter to add the body as a card (two at least), or open a scene in the list below")
		return
	var had := int(db.get("n", 0)) > 0
	var ok: bool = await _database()
	if not ok and not had and FrameMemo.abort:
		return
	if m.S.cards.size() < 2:
		return   # the scene changed while the scenes were read
	var t0 := Time.get_ticks_usec()
	var keep: Dictionary = m.B.state()   # a view: the body the user is editing comes back as it was (not re-posed from the playhead)
	sugs = TimingCoach.compute(m.S, m.B, db, String(m.S.name))
	ms = float(Time.get_ticks_usec() - t0) / 1000.0
	m.B.set_state(keep)   # compute posed the body at other times
	m.B.fk()
	learn()
	_panel()


## I26: more-time / less-time offers sort by how often you keep them; a kind you always change by the same amount comes pre-applied
static func kind_of(s: Dictionary) -> String:
	return "more time" if float(s["to"]) > float(s["from"]) else "less time"


func learn() -> void:
	for s in sugs:
		if s.has("learned"):
			continue
		var d: float = m.sj.learned("timing coach", kind_of(s))
		if not is_nan(d):
			s["base"] = s["to"]
			s["to"] = snappedf(maxf(TimingCoach.MIN_MOVE, float(s["to"]) + d), 0.001)
			s["learned"] = d
	sugs = m.sj.sort_offers("timing coach", sugs, kind_of)


func _panel() -> void:
	var L: VBoxContainer = m.ui_find_list
	for c in L.get_children():
		L.remove_child(c)
		c.queue_free()
	var head := HBoxContainer.new()
	L.add_child(head)
	var title: Label = m._label("TIMING COACH  -  " + ("every strike is inside the recorded range" if sugs.is_empty() else "%d suggestions" % sugs.size()), 18, "heading" if sugs.is_empty() else "warn")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(m._button("Close", m._close_findings))
	L.add_child(m._label("Each line: the evidence is a real clip in your scenes and the strike numbers with their sources. Preview changes nothing; Accept is one undo step (Ctrl+Z).", 13, "text:0.6", true))
	for k in sugs.size():
		var s: Dictionary = sugs[k]
		var lb: Label = m._label("%s  -  %s" % [s["kind"], s["reason"]], 14, "text:0.85", true)
		lb.name = "tc_line_%d" % (k + 1)
		lb.custom_minimum_size = Vector2(380, 0)
		L.add_child(lb)
		var row := HBoxContainer.new()
		var pb: Button = m._button("Preview", preview.bind(k), "play this timing around card %d; the scene is not changed" % (int(s["card"]) + 1))
		pb.name = "tc_preview_%d" % (k + 1)
		var ab: Button = m._button("Accept" if not s.has("learned") else "Accept (%s - applied)" % SuggestionJournal.phrase(float(s["learned"])), accept.bind(k), "write this one move time (card %d); one undo step" % (int(s["card"]) + 1))
		ab.name = "tc_accept_%d" % (k + 1)
		row.add_child(pb)
		row.add_child(ab)
		L.add_child(row)
	if sugs.size() > 1:
		var all: Button = m._button("Accept all", accept_all, "write every suggestion above; one undo step")
		all.name = "tc_accept_all"
		L.add_child(all)
	L.add_child(m._label("computed in %.0f ms against %d frames of real motion" % [ms, int(db.get("n", 0))], 12, "text:0.5", true))
	(m.ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(400, clampf(70.0 + 150.0 * sugs.size(), 80.0,
		minf(520.0, m.get_viewport().get_visible_rect().size.y - m.bottom_h - 82 - (m.TOP_H + 12) - 26)))
	m.ui_find.visible = true
	m._say("timing coach: " + ("nothing to change" if sugs.is_empty() else "%d suggestions. Preview plays one, Accept writes it (Ctrl+Z undoes)" % sugs.size()))


func preview(k: int) -> void:
	if k >= sugs.size():
		return
	var s: Dictionary = sugs[k]
	pv = TimingCoach.with_applied(m.S, [s])
	var ts := pv.times()
	var c: int = s["card"]
	pv_t = maxf(0.0, float(ts[c][0]) - LEAD_IN)
	pv_end = minf(pv.length(), float(ts[c][1]) + LEAD_OUT)
	m.playing = false
	m._say("timing coach preview: card %d move %.2f s (the scene is not changed)" % [c + 1, float(s["to"])])


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


func accept(k: int) -> void:
	_write([k])


func accept_all() -> void:
	_write(range(sugs.size()))


func _write(ix: Array) -> void:
	if ix.is_empty() or sugs.is_empty():
		return
	pv = null
	var chosen := ix.map(func(i): return sugs[i])
	m._step_hint = "Timing coach: accept" + (" all" if ix.size() > 1 else "")
	m._push_undo()
	m._markers_hold()
	for s in chosen:
		var ci := TimingCoach.accept(m.S, s)
		if ci >= 0:
			var sc: Scene = m.S
			m.sj.log("timing coach", kind_of(s), ci, {"field": "move", "base": float(s.get("base", s["to"])), "applied": float(s["to"])}, m.undo.size(),
				func(): return sc.cards[ci]["move"] if ci < sc.cards.size() else null)
	m._markers_follow()
	m._retimed()
	var left := TimingCoach.compute(m.S, m.B, db, String(m.S.name))
	sugs = left
	learn()
	m._ps().apply(m.B, m.playhead)
	_panel()
	m._say("timing coach: %d written (Ctrl+Z undoes them in one step); %d suggestions left" % [chosen.size(), left.size()])
