## hit_harder_ui.gd - the HIT HARDER button of the inspector (N065; the maths: scripts/hit_harder.gd). Under the move knobs in
## NUMBERS: one button on the picked strike card. Pressed, it runs HitHarder.serve, the agent's own path (ONE undo step), and the
## line under it says the gain as a number and which levers did it ("card 3 'CROSS': hand_r 2.64 -> 9.64 m/s, ... +265 %").
## Greyed with the reason when the picked card is not a strike card (or none is picked). Colours: none here (the theme's).
class_name HitHarderUI
extends VBoxContainer

const TIP := "make this strike more powerful by changing the body, within its limits: follow-through, hip and shoulder coil, a longer wind-up, weight toward the target; each kept only if the blow gets faster and the joint limits, the human speed caps, balance and the contact frame hold. One Ctrl+Z"

var m: Node
var button: Button
var note: Label
var _sig := []


func _init(main: Node) -> void:
	m = main
	name = "hit_harder"
	add_theme_constant_override("separation", 3)
	button = m._button("Hit harder", _press, TIP)
	button.name = "hit_harder_button"
	add_child(button)
	note = m._label("", m.PROP_TXT, "text:0.55", true)
	note.name = "hit_harder_note"
	add_child(note)
	refresh()


func _process(_dt: float) -> void:
	if not is_visible_in_tree():
		return
	if [m.sel_card, m.undo.size(), m.S.get_instance_id(), m.S.cards.size()] != _sig:
		refresh()


## grey the button with the reason, or offer it on the picked strike card
func refresh() -> void:
	_sig = [m.sel_card, m.undo.size(), m.S.get_instance_id(), m.S.cards.size()]
	var why := "pick a strike card (a card named punch / kick / swing / cut ..., or one with a hit marker) to make it hit harder" if m.sel_card < 0 else HitHarder.not_strike(m.S, m.sel_card)
	button.disabled = why != ""
	button.tooltip_text = TIP if why == "" else "%s\nNOT NOW: %s" % [TIP, why]
	note.text = why


func _press() -> void:
	if button.disabled or m.sel_card < 0:
		return
	var r := HitHarder.serve(m, {"card": m.sel_card + 1})
	refresh()
	note.text = String(r.get("said", r.get("error", "")))
	if r.get("ok", false):
		m._say("hit harder: " + note.text + ("  (Ctrl+Z takes it back)" if r["changed"] else ""))
