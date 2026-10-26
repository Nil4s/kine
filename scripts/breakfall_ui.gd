## BREAKFALL CHECK panel (ROADMAP I25; the maths: scripts/breakfall.gd). Each fall or knockdown of the scene (the active fighter) gets a card with the
## four verdicts (head and chin, straight-arm catch, impact spread, speed), each with its number; the timeline wears a badge per fall. Under a card:
## "Tuck the chin", "Bend the arm into a slap", "Roll the trunk" build a changed copy of the landing cards; Preview plays it (the scene is not
## changed), Accept writes it as ONE undo step.
class_name BreakfallUI
extends RefCounted

var m: Node
var rep: Dictionary = {}
var fx: Dictionary = {}
var fk := 0
var pv := false
var pv_t := 0.0
var pv_t1 := 0.0
var pv_sc: Scene = null


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Breakfall check", "", show, "fall knockdown landing breakfall ukemi chin tuck head floor straight arm slap roll shoulder back hip impact speed stunt judo",
		false, "finds each fall of the clip and judges the landing like a judo / stunt coach: head clear and chin tucked, no straight-arm catch, impact spread, impact speed; fixes: tuck the chin, bend the arm into a slap, roll the trunk, slow the landing (preview, then Accept = one undo step)")


func halt() -> void:
	pv = false
	pv_sc = null


func clear_overlay() -> void:
	rep = {}
	fx = {}
	halt()
	_overlay()


static func word(c: String) -> String:
	return "OK" if c == "ok" else ("CHECK" if c == "warn" else "FAIL")


func compute() -> void:
	m._actors_sync()
	rep = Breakfall.analyze(m.S)
	fx = {}
	_overlay()


func _overlay() -> void:
	var tl = m.ui_timeline
	if tl == null:
		return
	var bands := []
	for f in rep.get("falls", []):
		bands.append({"t0": float(f["t0"]), "t1": float(f["t1"]), "cls": String(f["cls"]), "txt": "FALL " + word(String(f["cls"]))})
	tl.bk = bands
	tl.queue_redraw()


func show() -> void:
	compute()
	_panel()


## the Breakfall check button: show() with the falls read on a worker thread (checkslice; Breakfall.analyze makes its own clone and body)
func show_bg() -> void:
	m._actors_sync()
	var C: Scene = m.S.clone()
	var r: Dictionary = await m.bg_run("breakfall check", "breakfall check: reading the falls...", func(): return Breakfall.analyze(C))
	if not r["ok"]:
		return
	rep = r["v"]
	fx = {}
	_overlay()
	_panel()


## the four verdict lines of a fall: [[class, text]]
static func lines(f: Dictionary) -> Array:
	var a := "%s fall: %s" % [String(f["dir"]), String(f["head_how"])]
	a += "  (head touches the floor)" if String(f["a"]) == "fail" else ("  (%s)" % ("tuck the chin: %.0f deg wanted" % Breakfall.TUCK_MIN if String(f["dir"]) == "backward" else "turn the head aside") if String(f["a"]) == "warn" else "")
	var b := "no hand or forearm lands first"
	if String(f["side"]) != "":
		b = "%s lands first, elbow %.0f deg" % ["hand" if String(f["part"]).begins_with("hand") else "forearm", float(f["elbow"])]
		b += "  (straight-arm catch)" if String(f["b"]) != "ok" else ""
	var c := "impact on " + (", ".join(f["regions"]) if not (f["regions"] as Array).is_empty() else "nothing else")
	c += "  (%d of arm / back / hip side)" % int(f["good"])
	var d := "first part (%s) lands at %.1f m/s" % [String(f["part"]), float(f["speed"])]
	return [[f["a"], "HEAD  " + a], [f["b"], "ARM  " + b], [f["c"], "SPREAD  " + c], [f["d"], "SPEED  " + d]]


func _panel() -> void:
	var L: VBoxContainer = m.ui_find_list
	for c in L.get_children():
		L.remove_child(c)
		c.queue_free()
	var falls: Array = rep.get("falls", [])
	var head := HBoxContainer.new()
	L.add_child(head)
	var title: Label = m._label("BREAKFALL CHECK  -  %s" % String(rep.get("msg", "")), 14, "fail" if int(rep.get("bad", 0)) > 0 else "heading", true)
	title.name = "bk_title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(m._button("Close", _close))
	if falls.is_empty():
		m.ui_find.visible = true
		m._say("breakfall check: " + String(rep.get("msg", "")))
		return
	L.add_child(m._label("A fall = the centre of mass drops %.0f%% of the standing height within %.0f s and a part but the feet reaches the floor. The rules are judo ukemi / stunt practice taken as heuristics (head clear, chin tucked %.0f deg, elbow bent %.0f deg, impact over arm / back / hip side, speed under %.1f m/s). Fixes change a copy; Preview changes nothing, Accept is one undo step." % [Breakfall.DROP * 100.0, Breakfall.WIN, Breakfall.TUCK_MIN, Breakfall.ELBOW_OK, Breakfall.SPEED_OK],
		13, "text:0.6", true))
	for k in falls.size():
		var f: Dictionary = falls[k]
		var hd: Label = m._label("fall %d  -  impact at %.2f s on the %s  -  %s" % [k + 1, float(f["t_c"]), String(f["part"]), word(String(f["cls"]))], 13, "fail" if f["cls"] == "fail" else ("warn" if f["cls"] == "warn" else "heading"), true)
		hd.name = "bk_fall_%d" % k
		L.add_child(hd)
		var li := 0
		for ln in lines(f):
			var lb: Label = m._label(String(word(String(ln[0]))) + "  " + String(ln[1]), 13, "text:0.85" if ln[0] == "ok" else ("fail" if ln[0] == "fail" else "warn"), true)
			lb.name = "bk_v%d_%d" % [k, li]
			lb.custom_minimum_size = Vector2(380, 0)
			L.add_child(lb)
			li += 1
		var row := HBoxContainer.new()
		var b1: Button = m._button("Protect the head", select.bind(k, "tuck"), "by the direction of the fall: forward = turn the head aside and lift it a little, backward = tuck the chin (%.0f deg), side = turn it away from the floor" % (Breakfall.CHIN_NECK + Breakfall.CHIN_HEAD))
		b1.name = "bk_tuck_%d" % k
		var b2: Button = m._button("Bend the arm into a slap", select.bind(k, "slap"), "the catching arm: elbow bent, forearm flat, palm down, %.0f deg off the body" % Breakfall.SLAP_DEG)
		b2.name = "bk_slap_%d" % k
		var b3: Button = m._button("Roll the trunk", select.bind(k, "roll"), "turn the trunk %.0f deg about its long axis so the shoulder and back land first" % Breakfall.ROLL_DEG)
		b3.name = "bk_roll_%d" % k
		var b4: Button = m._button("Slow the landing", select.bind(k, "lower"), "lower first (knees bend), then stretch the last cards so the first part lands under %.1f m/s; the fall still ends within %.1f s of its start" % [Breakfall.SPEED_OK, Breakfall.FALL_CAP])
		b4.name = "bk_lower_%d" % k
		row.add_child(b1)
		row.add_child(b2)
		row.add_child(b3)
		row.add_child(b4)
		L.add_child(row)
	if not fx.is_empty():
		var af: Dictionary = fx.get("after", {})
		var l2: Label = m._label("FIX  -  " + String(fx["msg"]) + ("; then the landing reads %s" % word(String(af["cls"])) if not af.is_empty() else ""), 13, "heading", true)
		l2.name = "bk_fix"
		l2.custom_minimum_size = Vector2(380, 0)
		L.add_child(l2)
		if not af.is_empty():
			var l3: Label = m._label("after:  " + "   |   ".join(lines(af).map(func(x): return String(x[1]).split("  (")[0])), 12, "text:0.7", true)
			l3.name = "bk_after"
			L.add_child(l3)
		var r2 := HBoxContainer.new()
		var pb: Button = m._button("Preview", preview, "play the landing with the fix; the scene is not changed")
		pb.name = "bk_preview"
		var ab: Button = m._button("Accept", accept, "write the fix; one undo step")
		ab.name = "bk_accept"
		r2.add_child(pb)
		r2.add_child(ab)
		L.add_child(r2)
	(m.ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(440, clampf(160.0 + 150.0 * falls.size() + (120.0 if not fx.is_empty() else 0.0), 220.0,
		minf(560.0, m.get_viewport().get_visible_rect().size.y - m.bottom_h - 82 - (m.TOP_H + 12) - 26)))
	m.ui_find.visible = true
	m._say("breakfall check: " + String(rep.get("msg", "")) + (".  The buttons under a fall build a fix to preview" if int(rep.get("bad", 0)) > 0 else ""))


func select(k: int, kind: String) -> void:
	var f: Dictionary = rep["falls"][k]
	var r: Dictionary
	if kind == "tuck":
		r = Breakfall.tuck(m.S, f)
	elif kind == "slap":
		r = Breakfall.slap(m.S, f)
	elif kind == "lower":
		r = Breakfall.lower(m.S, f)
	else:
		r = Breakfall.roll(m.S, f)
	if not r["ok"]:
		m._say(String(r["why"]))
		return
	fx = r
	fk = k
	_panel()


func _close() -> void:
	clear_overlay()
	m._close_findings()


func preview() -> void:
	if fx.is_empty():
		m._say("nothing to preview: press 'Protect the head', 'Bend the arm into a slap' or 'Roll the trunk' under a fall first")
		return
	var f: Dictionary = rep["falls"][fk]
	halt()
	pv_sc = (fx["scene"] as Scene).clone()
	pv_t = maxf(0.0, float(f["t0"]) - 0.2)
	pv_t1 = float(f["t1"]) + 0.5
	pv = true
	m.playing = false
	m._say("breakfall check: previewing the fix (the scene is not changed)")


func tick(dt: float) -> void:
	if not pv:
		return
	pv_t += dt
	if pv_t >= pv_t1:
		halt()
		m._ps().apply(m.B, m.playhead)
		m._refresh()
		return
	pv_sc.apply(m.B, pv_t)
	m._refresh()


func accept() -> void:
	if fx.is_empty():
		m._say("nothing to accept: press 'Protect the head', 'Bend the arm into a slap' or 'Roll the trunk' under a fall first")
		return
	halt()
	var f := fx
	m._actors_sync()
	m._step_hint = "Breakfall check"
	m._push_undo()
	(m.S as Scene).cards = (f["scene"] as Scene).cards.duplicate(true)
	m._rebuild_cards()
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	m._say("breakfall check: %s.  Ctrl+Z undoes it in one step" % String(f["msg"]))
	compute()
	_panel()
