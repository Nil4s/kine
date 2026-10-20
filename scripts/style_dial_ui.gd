## STYLE DIAL panel (ROADMAP I6; the maths: scripts/style_dial.gd). Kept out of main.gd: main makes one (main.sd_ui), lists its
## command and its ribbon button (ANIMATE > STYLE), and calls tick() each frame.
##   "Style dial"  opens four sliders in the find panel: heavier / tired / angry / sneaky, each -1 .. +1. A drag changes nothing until
##                 the button is RELEASED; then the whole clip is restyled from the cards it had at 0 (so the sliders add up and
##                 never compound) as ONE undo step. All four at 0 puts the original cards back, byte for byte.
##   Reset         all four to 0 (one undo step if anything was restyled).
## The base (the cards at 0) is taken when the first slider moves and dropped when anything else changes the scene (an undo, a redo,
## an edit): the sliders then read 0 again, because the clip on screen is the new base.
class_name StyleDialUI
extends RefCounted

var m: Node
var vals: Dictionary = StyleDial.neutral()
var base: Array = []                 # the cards at slider 0 (deep copy); [] = no base yet
var last_report: Dictionary = {}
var last_ms := 0.0
var _undo_mark := -1                 # main.undo.size() right after our last step: a different size = something else happened
var _sl := {}                        # style -> HSlider
var _lab := {}                       # style -> Label
var _busy := false
var _drag := {}


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Style dial", "", show, "style dial heavier tired angry sneaky mood effort sliders whole clip timing posture amplitude",
		false, "four sliders (heavier / tired / angry / sneaky, -1 to +1) that restyle the whole clip: slower or faster moves, bigger or smaller motion, a lower head, a flexed trunk; the size of each change is how much your own clips differ; feet stay planted and the strike keeps its contact; one undo step per release")


func halt() -> void:
	_drag.clear()


func tick(_dt: float) -> void:
	if _undo_mark >= 0 and m.undo.size() != _undo_mark:
		_forget()


func _forget() -> void:
	base = []
	_undo_mark = -1
	vals = StyleDial.neutral()
	_sync()


func _sync() -> void:
	for s in StyleDial.STYLES:
		if _sl.has(s) and is_instance_valid(_sl[s]):
			(_sl[s] as HSlider).set_value_no_signal(float(vals[s]))
			_text(s)


func _text(s: String) -> void:
	if _lab.has(s) and is_instance_valid(_lab[s]):
		(_lab[s] as Label).text = "%s  %+.2f" % [s, float(vals[s])]


func show() -> void:
	if m.S.cards.size() < 2:
		m._say("Style dial needs a scene of two cards or more: press Enter to add the body as a card (two at least), or open a scene in the list below")
		return
	var L: VBoxContainer = m.ui_find_list
	for c in L.get_children():
		L.remove_child(c)
		c.queue_free()
	_sl = {}
	_lab = {}
	var head := HBoxContainer.new()
	L.add_child(head)
	var title: Label = m._label("STYLE DIAL", 18, "heading")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(m._button("Close", m._close_findings))
	L.add_child(m._label("Each slider restyles the whole clip when you let go (one Ctrl+Z). +1 is the size by which your own clips differ at the 90th percentile; the feet stay planted and a strike keeps its contact.", 13, "text:0.6", true))
	for s in StyleDial.STYLES:
		var row := VBoxContainer.new()
		var lb: Label = m._label("", 14, "text:0.85")
		lb.name = "sd_label_" + s
		row.add_child(lb)
		_lab[s] = lb
		var sl := HSlider.new()
		sl.name = "sd_" + s
		sl.min_value = -1.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.custom_minimum_size = Vector2(300, 22)
		sl.focus_mode = Control.FOCUS_ALL
		sl.tooltip_text = "%s: -1 .. +1; the clip is restyled when you release (one undo step)" % s
		sl.value = float(vals[s])
		sl.value_changed.connect(_moved.bind(s))
		sl.drag_started.connect(func(): _drag[s] = true)
		sl.drag_ended.connect(func(_c): _released(s))
		row.add_child(sl)
		L.add_child(row)
		_sl[s] = sl
		_text(s)
	var rb: Button = m._button("Reset", reset, "all four sliders to 0: the original cards come back (one undo step)")
	rb.name = "sd_reset"
	L.add_child(rb)
	var ln: Label = m._label("", 12, "text:0.5", true)
	ln.name = "sd_note"
	L.add_child(ln)
	(m.ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(340, 330)
	m.ui_find.visible = true
	m._say("style dial: move a slider, let go, the whole clip is restyled (Ctrl+Z undoes it)")


func _moved(x: float, s: String) -> void:
	vals[s] = x
	_text(s)
	if not _drag.get(s, false):
		commit(s)   # a click on the track or a key press: no drag to wait for


func _released(s: String) -> void:
	_drag.erase(s)
	commit(s)


func reset() -> void:
	if base.is_empty():
		return
	vals = StyleDial.neutral()
	_sync()
	commit("")


func set_value(s: String, x: float) -> void:
	vals[s] = clampf(x, -1.0, 1.0)
	_sync()
	commit(s)


## restyle the clip from the base at the current slider values: ONE undo step
func commit(_s: String) -> void:
	if _busy:
		return
	_busy = true
	if base.is_empty():
		base = m.S.cards.duplicate(true)
	var t0 := Time.get_ticks_usec()
	var res := StyleDial.style_cards(m.S, m.B, base, vals)
	last_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	last_report = res["report"]
	m._step_hint = "Style dial: " + ", ".join(StyleDial.STYLES.filter(func(k): return absf(float(vals[k])) > 1e-6).map(func(k): return "%s %+.2f" % [k, float(vals[k])])) if not StyleDial.is_neutral(vals) else "Style dial: reset"
	m._push_undo()
	m._markers_hold()
	m.S.cards = res["cards"]
	m._markers_follow()
	m._retimed()
	m.ui_find.visible = true   # _retimed hides the findings; this panel is the dial itself
	_undo_mark = m.undo.size()
	if StyleDial.is_neutral(vals):
		base = []
	m._ps().apply(m.B, minf(m.playhead, m._ps().length()))
	var note: Label = m.ui_find_list.find_child("sd_note", true, false) as Label if m.ui_find_list != null else null
	if note != null:
		note.text = "restyled in %.0f ms; %d planted feet and %d strike contact(s) kept" % [last_ms, int(last_report.get("planted", 0)), (last_report.get("contacts", []) as Array).size()]
	m._say("style dial: the clip is restyled (%.0f ms). Ctrl+Z takes it back in one step" % last_ms)
	_busy = false
