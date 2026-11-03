## c22_hands.gd - C22 (complaints 177, 20, 2): hands and props.
##  1 take_with: a prop is attached to a CHOSEN hand (left or right) on a card, whichever hand is nearer (Pick up picks by reach;
##    this names the hand). Same card["take"] mark Scene.carries() reads, so the carry, the drop, the mirror and the save are unchanged.
##  2 grip_handle: a hand grips a prop BY ITS HANDLE directly: the handle is the middle of the prop's long axis (a slab of the prop's
##    own surface, HAND_SPAN long), the hand is placed on it and the fingers closed round the prop's real surface there (AnyGrip). No
##    dummy object, no weapon slot. Nothing existing changes; both are new commands.
class_name C22Hands
extends RefCounted

const HAND_SPAN := 0.10   # the length of prop the hand covers (m)


## attach prop to the chosen hand (hand = "_l" or "_r") on card `card`. Returns "" or why not
static func take_with(S: Scene, prop: int, card: int, hand: String) -> String:
	if hand != "_l" and hand != "_r":
		return "the hand is _l or _r"
	if prop < 0 or prop >= S.props.size():
		return "pick a prop first"
	if card < 0 or card >= S.cards.size():
		return "pick a card first"
	for c in S.cards:   # the prop is held from one card only
		if c.has("take") and int(c["take"]["prop"]) == prop:
			c.erase("take")
	S.cards[card]["take"] = {"prop": prop, "hands": [hand]}
	return ""


## the prop's handle: {"c": centre, "ax": unit long axis, "len": its length, "r": half the thinnest section} in the world, from its
## longest solid (the middle of it: a sword's grip is where a hand holds the bar). {} = a prop with no solid
static func handle_of(p: Dictionary) -> Dictionary:
	var best := {}
	var blen := -1.0
	for sw in Props.solids(p):
		var h: Vector3 = sw["half"]
		var xf: Transform3D = sw["xf"]
		var i := h.max_axis_index()
		if sw.has("r") or h[i] <= blen:
			continue
		blen = h[i]
		var o := [0, 1, 2]
		o.erase(i)
		best = {"c": xf.origin, "ax": (xf.basis * Vector3(1 if i == 0 else 0, 1 if i == 1 else 0, 1 if i == 2 else 0)).normalized(),
			"len": h[i] * 2.0 * xf.basis.get_scale()[i], "r": minf(h[o[0]], h[o[1]]) * xf.basis.get_scale()[o[0]]}
	return best


## the prop's own surface clipped to the handle's slab: {"sd", "size", "sphere"} for AnyGrip
static func handle_field(p: Dictionary) -> Dictionary:
	var hd := handle_of(p)
	if hd.is_empty():
		return {}
	var full := AnyGrip.field_of(p)
	var fn: Callable = full["sd"]
	var c: Vector3 = hd["c"]
	var ax: Vector3 = hd["ax"]
	var half := minf(HAND_SPAN, float(hd["len"])) * 0.5
	var sd := func(q: Vector3) -> float:
		return maxf(float(fn.call(q)), absf((q - c).dot(ax)) - half)
	var r := float(hd["r"]) * 2.0
	return {"sd": sd, "size": Vector3(r, r, half * 2.0), "sphere": false, "handle": hd}


## grip prop p by its handle with hand h ("hand_l" / "hand_r"): place the hand on the handle, fingers across it, close, key the
## 15 finger joints at t. Returns the wrap report plus "handle" and "place". {} = nothing to grip
static func grip_handle(B: Body, h: String, p: Dictionary, pk: Dictionary, t: float) -> Dictionary:
	var F := handle_field(p)
	if F.is_empty():
		return {}
	var hd: Dictionary = F["handle"]
	var place := AnyGrip.place_hand(B, h, F, hd["ax"])
	var rep := AnyGrip.wrap(B, h, F)
	AnyGrip.key_hand(B, h, pk, t)
	rep["handle"] = hd
	rep["place"] = place
	return rep


## the commands (Command palette)
static func take_left(m: Node) -> void:
	_take(m, "_l")


static func take_right(m: Node) -> void:
	_take(m, "_r")


static func _take(m: Node, hand: String) -> void:
	if m.sel_prop < 0 or m.sel_prop >= m.S.props.size() or m.sel_card < 0:
		m._say("pick a prop and a card on the timeline first")
		return
	m._push_undo()
	var why := take_with(m.S, m.sel_prop, m.sel_card, hand)
	if why != "":
		m._drop_undo()
		m._say(why)
		return
	m._rebuild_cards()
	m._props_show()
	m._refresh()
	m._say("card %d: the %s hand holds the %s from here on (Ctrl+Z takes it back)" % [m.sel_card + 1, "left" if hand == "_l" else "right", m._prop_name(m.sel_prop)])


static func grip_handle_cmd(m: Node) -> void:
	if m.sel_prop < 0 or m.sel_prop >= m.S.props.size():
		m._say("pick a prop first: click it in the view, then Grip: by its handle")
		return
	var h := "hand_l" if String(m.sel).ends_with("_l") else "hand_r"
	var t := clampf(m.playhead, 0.0, m.S.length())
	var p: Dictionary = Props.posed(m.S.props[m.sel_prop], t)
	var rep := {}
	m._do(func(): rep.merge(grip_handle(m.B, h, p, m.S.part_keys, t)))
	if rep.is_empty():
		m._say("that prop has no handle to grip (no solid part)")
		return
	m._props_show()
	m._say("%s hand on the %s's handle (%.0f cm of it, %.1f cm across), fingers closed round it, keyed at the playhead; Ctrl+Z takes it back" % [
		"left" if h == "hand_l" else "right", m._prop_name(m.sel_prop), minf(HAND_SPAN, float(rep["handle"]["len"])) * 100.0, float(rep["handle"]["r"]) * 200.0])
