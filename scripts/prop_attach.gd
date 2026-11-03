## prop_attach.gd - C13 (complaint 627): the frame a prop is attached to the hand and the frame it is let go, as a control on the
## timeline's selected card. Scene.carries() already starts a carry at the card holding card["take"] and ends it at the card holding
## card["drop"]; these move those two marks to another card (the grip is re-read from the hands on the new card, as Pick up does),
## and read them back as card numbers, times and frames. Pure functions on a Scene, plus two command wrappers for main.gd.
class_name PropAttach
extends RefCounted


## {"a", "b", "ta", "tb", "fa", "fb", "hands"} of prop i's carry (b = -1: held to the end, tb/fb = -1); {} = it is not carried
static func info(S: Scene, prop: int) -> Dictionary:
	var ts := S.times()
	for c in S.carries():
		if int(c["prop"]) != prop:
			continue
		var a := int(c["a"])
		var b := int(c["b"])
		var ta := float(ts[a][1])
		var tb := float(ts[b][1]) if b >= 0 else -1.0
		return {"a": a, "b": b, "ta": ta, "tb": tb, "fa": roundi(ta * S.fps), "fb": roundi(tb * S.fps) if b >= 0 else -1, "hands": c["hands"]}
	return {}


## the attach moved to card `to` (before the let-go). Returns "" or why not
static func move_attach(S: Scene, prop: int, to: int) -> String:
	var i := info(S, prop)
	if i.is_empty():
		return "that prop is not carried: Pick up puts it in a hand first"
	if to < 0 or to >= S.cards.size():
		return "pick a card first"
	if int(i["b"]) >= 0 and to >= int(i["b"]):
		return "the prop is let go on card %d: attach it on an earlier card" % (int(i["b"]) + 1)
	if to == int(i["a"]):
		return "it is attached on this card already"
	var tk: Dictionary = S.cards[int(i["a"])]["take"]
	S.cards[int(i["a"])].erase("take")
	S.cards[to]["take"] = tk
	return ""


## the let-go moved to card `to` (after the attach); its baked fall is cleared (re-baked by the caller if it wants it)
static func move_detach(S: Scene, prop: int, to: int) -> String:
	var i := info(S, prop)
	if i.is_empty():
		return "that prop is not carried: Pick up puts it in a hand first"
	if to <= int(i["a"]) or to >= S.cards.size():
		return "let it go on a card after card %d, where it is attached" % (int(i["a"]) + 1)
	if to == int(i["b"]):
		return "it is let go on this card already"
	if int(i["b"]) >= 0:
		S.cards[int(i["b"])].erase("drop")
		S.cards[int(i["b"])].erase("drop_rig")
	S.cards[to]["drop"] = prop
	return ""


static func words(S: Scene, prop: int) -> String:
	var i := info(S, prop)
	if i.is_empty():
		return "not carried"
	var s := "attached on card %d (frame %d, %s)" % [int(i["a"]) + 1, int(i["fa"]), Units.time(float(i["ta"]), S.fps)]
	if int(i["b"]) >= 0:
		return s + ", let go on card %d (frame %d, %s)" % [int(i["b"]) + 1, int(i["fb"]), Units.time(float(i["tb"]), S.fps)]
	return s + ", held to the end"


## the commands (Command palette): the picked prop, the selected card
static func attach_here(m: Node) -> void:
	_run(m, true)


static func detach_here(m: Node) -> void:
	_run(m, false)


static func _run(m: Node, attach: bool) -> void:
	if m.sel_prop < 0 or m.sel_prop >= m.S.props.size() or m.sel_card < 0:
		m._say("pick a prop and a card on the timeline first")
		return
	var S: Scene = m.S
	m._push_undo()
	var why := move_attach(S, m.sel_prop, m.sel_card) if attach else move_detach(S, m.sel_prop, m.sel_card)
	if why != "":
		m._drop_undo()
		m._say(why)
		return
	if not attach:
		S.bake_drop(m.B, m.sel_card)
	m._rebuild_cards()
	m._props_show()
	m._refresh()
	m._say("the %s is %s. Ctrl+Z takes it back" % [m._prop_name(m.sel_prop), words(S, m.sel_prop)])
