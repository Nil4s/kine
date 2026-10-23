## move_knobs_ui.gd - the MOVE KNOBS section of the inspector (N025; the maths: scripts/move_knobs.gd). Four spin boxes on
## the picked card (in the inspector's NUMBERS box: a section header of its own made the hips' box taller than its 300 px bar): strike height (cm over the chin), reach (% of the limb), stance (cm between the ankles), guard (cm of
## the guard wrist over the chin). A changed box sets that one knob through MoveKnobs.serve, the agent's own path: ONE undo
## step, the contact card and its neighbours re-solved, the planted feet kept. The boxes are greyed with the reason when no
## strike card is picked, and a knob the strike does not have (a kick's stance, a two-hand grip's guard) is greyed with its
## own reason. Colours: none here; the boxes and labels take the app's theme (main._label tints from tok.gd).
## It reads again when the picked card, the undo stack or the scene changes, and only while the section is open.
class_name MoveKnobsUI
extends VBoxContainer

const LABEL := {"strike_height_cm": "strike height  cm", "reach_pct": "reach  %", "stance_cm": "stance  cm", "guard_cm": "guard  cm"}
const TIP := {"strike_height_cm": "the striking end (fist, foot or weapon tip) above + / below - his chin height, cm",
	"reach_pct": "shoulder (hip) to wrist (ankle) as % of the arm (leg); 100 = straight",
	"stance_cm": "the distance between the ankles along the floor, cm; the rear foot moves",
	"guard_cm": "the guard hand's wrist above + / below - his chin height, cm"}
const RANGE := {"strike_height_cm": Vector2(-200, 100), "reach_pct": Vector2(0, 150), "stance_cm": Vector2(0, 200), "guard_cm": Vector2(-150, 100)}

var m: Node
var boxes := {}        # knob -> SpinBox
var note: Label        # the reason the boxes are grey, or what the last change did
var _sig := []
var _quiet := false    # set_value_no_signal is not enough for a SpinBox's line edit: a guard


func _init(main: Node) -> void:
	m = main
	name = "move_knobs"
	add_theme_constant_override("separation", 3)
	add_child(m._label("MOVE KNOBS", m.PROP_TXT, "heading"))
	for k in MoveKnobs.KNOBS:
		var sb := SpinBox.new()
		sb.name = "knob_" + k
		sb.min_value = RANGE[k].x
		sb.max_value = RANGE[k].y
		sb.step = 0.1
		sb.custom_arrow_step = 1.0
		sb.allow_greater = true
		sb.allow_lesser = true
		sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sb.tooltip_text = TIP[k]
		sb.value_changed.connect(_changed.bind(k))
		var lb: Label = m._label(LABEL[k], m.PROP_TXT, "text:0.6")
		lb.custom_minimum_size = Vector2(110, 0)
		m._row(self, [lb, sb])
		boxes[k] = sb
	note = m._label("", m.PROP_TXT, "text:0.55", true)
	note.name = "knobs_note"
	add_child(note)
	refresh()


func _process(_dt: float) -> void:
	if not is_visible_in_tree():
		return
	var sig := [m.sel_card, m.undo.size(), m.redo.size(), m.S.get_instance_id(), m.S.cards.size()]
	if sig != _sig:
		refresh()


## read the picked card's knobs into the boxes, or grey them with the reason
func refresh() -> void:
	_sig = [m.sel_card, m.undo.size(), m.redo.size(), m.S.get_instance_id(), m.S.cards.size()]
	var why := ""
	var r := {}
	if m.sel_card < 0:
		why = "pick a strike card (a card named punch / kick / swing / cut ..., or one with a hit marker) to set its height, reach, stance and guard"
	else:
		r = MoveKnobs.read(m.S, m.sel_card)
		if not r["ok"]:
			why = String(r["error"])
	_quiet = true
	for k in MoveKnobs.KNOBS:
		var sb: SpinBox = boxes[k]
		var na: String = String(r.get("na", {}).get(k, "")) if why == "" else why
		sb.editable = na == ""
		sb.tooltip_text = TIP[k] if na == "" else "%s\n(greyed: %s)" % [TIP[k], na]
		if na == "" and r["values"][k] != null:
			sb.set_value_no_signal(float(r["values"][k]))
			sb.get_line_edit().text = str(snappedf(float(r["values"][k]), 0.1))
	_quiet = false
	note.text = why if why != "" else "card %d '%s', a %s: change a number and the card and its neighbours are re-solved (one Ctrl+Z)" % [r["card"], r["name"], r["kind"]]


func _changed(x: float, k: String) -> void:
	if _quiet or not (boxes[k] as SpinBox).editable or m.sel_card < 0:
		return
	var res := MoveKnobs.serve(m, {"card": m.sel_card + 1, "set": {k: x}})
	refresh()
	if res.get("ok", false):
		note.text = String(res["said"])
		m._say("move knobs: " + String(res["said"]) + "  (Ctrl+Z takes it back)")
	else:
		note.text = String(res.get("error", ""))
