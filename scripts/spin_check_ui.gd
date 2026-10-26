## AIRBORNE SPIN panel (ROADMAP I43; the maths: scripts/spin_check.gd). "Airborne spin check" finds every flight (both feet off the floor, nothing
## held), draws the COM's height against the free-fall parabola on the timeline, and flags a hang / float (the COM does not accelerate at g)
## and a mid-air spin the take-off momentum cannot give. "Fix the flights" moves the spin into the take-off (a pivot on the take-off card, a
## constant rate in the air) and puts a floating arc on the parabola; Preview plays it (nothing changes), Accept writes ONE undo step.
class_name SpinCheckUI
extends RefCounted


## the COM's height over one flight: the drawn arc (solid) against the free-fall parabola through the same ends (dotted), with g's own apex
class ArcPlot extends Control:
	var f: Dictionary = {}

	func _draw() -> void:
		var ys: Array = f["ys"]
		var ps: Array = f["ps"]
		var bad: bool = f["float"] or f["dive"]
		var col: Color = Tok.c("fail") if bad else Tok.c("fv_ok")
		draw_rect(Rect2(Vector2.ZERO, size), Color(Tok.c("tl_bg"), 0.9))
		draw_rect(Rect2(Vector2.ZERO, size), Color(Tok.c("ink"), 0.35), false, 1.0)
		var lo := INF
		var hi := -INF
		for v in ys + ps:
			lo = minf(lo, float(v))
			hi = maxf(hi, float(v))
		hi = maxf(hi, lo + 0.1)
		var pa := PackedVector2Array()
		var pb := PackedVector2Array()
		for k in ys.size():
			var x := 6.0 + (size.x - 12.0) * float(k) / maxf(ys.size() - 1.0, 1.0)
			pa.append(Vector2(x, size.y - 8.0 - (size.y - 22.0) * (float(ys[k]) - lo) / (hi - lo)))
			pb.append(Vector2(x, size.y - 8.0 - (size.y - 22.0) * (float(ps[k]) - lo) / (hi - lo)))
		draw_polyline(pb, Color(Tok.c("ink"), 0.8), 1.4)
		draw_polyline(pa, col, 2.4)
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(8.0, 12.0), "COM height: drawn (colour) vs free fall (grey)   %s to %s   a = %.1f m/s^2" % [Units.len(lo), Units.len(hi), -float(f["a"])], HORIZONTAL_ALIGNMENT_LEFT, size.x - 12.0, 10, Tok.c("text"))

var m: Node
var rep: Dictionary = {}
var plan: Dictionary = {}
var pv: Scene = null
var pv_t := 0.0
var pv_end := 0.0
var ms := 0.0


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Airborne spin check", "", show, "airborne spin flight jump somersault twist angular momentum parabola gravity float hang takeoff impossible",
		false, "finds each flight (both feet off the floor, nothing held), draws the centre of mass against the free-fall parabola on the timeline, flags a floaty arc and a mid-air spin the take-off momentum cannot give, and offers a fix (the spin moved into the take-off, the arc put on a parabola); preview, then accept = one undo step")


func halt() -> void:
	pv = null


func compute() -> void:
	var t0 := Time.get_ticks_usec()
	rep = SpinCheck.analyze(m.S, m.B)
	ms = float(Time.get_ticks_usec() - t0) / 1000.0
	plan = {}
	_overlay()


func _overlay() -> void:
	var tl = m.ui_timeline
	if tl == null:
		return
	var sp := []
	for f in rep.get("flights", []):
		sp.append({"t0": f["t0"], "t1": f["t1"], "ys": f["ys"], "ps": f["ps"], "flag": f["flag"], "txt": "%.0f deg, a %.1f m/s^2" % [f["phi"], -float(f["a"])]})
	tl.spn = sp
	tl.queue_redraw()


func clear_overlay() -> void:
	rep = {}
	plan = {}
	halt()
	_overlay()


func show() -> void:
	if m.S.cards.size() < 2:
		m._say("Airborne spin check needs a scene of two cards or more: press Enter to add the body as a card (two at least), or open a scene in the list below")
		return
	m._say("airborne spin check: reading the flights...")
	compute()
	_panel()


## the Airborne spin check button: show() with the flights read on a worker thread (checkslice)
func show_bg() -> void:
	if m.S.cards.size() < 2:
		show()   # the "needs two cards" line
		return
	var C: Scene = m.S.clone()
	var st: Dictionary = m.B.state()
	var t0 := Time.get_ticks_usec()
	var r: Dictionary = await m.bg_run("airborne spin check", "airborne spin check: reading the flights...", func(): return SpinCheck.analyze(C, m.bg_body(st)))
	if not r["ok"]:
		return
	rep = r["v"]
	ms = float(Time.get_ticks_usec() - t0) / 1000.0
	plan = {}
	_overlay()
	_panel()


func _panel() -> void:
	var L: VBoxContainer = m.ui_find_list
	for c in L.get_children():
		L.remove_child(c)
		c.queue_free()
	var fl: Array = rep.get("flights", [])
	var nbad := fl.filter(func(f): return f["flag"]).size()
	var head := HBoxContainer.new()
	L.add_child(head)
	var title: Label = m._label("AIRBORNE SPIN  -  " + ("impossible flights, count: %d" % nbad if nbad > 0 else ("no flight found" if fl.is_empty() else "every flight is possible")), 16, "warn" if nbad > 0 else "heading", true)
	title.name = "sp_title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(m._button("Close", _close))
	var exp: Label = m._label("In the air only gravity acts: the centre of mass follows y'' = -9.81 m/s^2 and the angular momentum about it is conserved. A body turns at H / I, so a turn needs momentum at take-off. " + SpinCheck.constants_text(), 12, "text:0.6", true)
	exp.custom_minimum_size = Vector2(380, 0)
	L.add_child(exp)
	for k in fl.size():
		var f: Dictionary = fl[k]
		var lb: Label = m._label(String(f["msg"]), 13, "warn" if f["flag"] else "text:0.85", true)
		lb.name = "sp_row_%d" % k
		lb.custom_minimum_size = Vector2(380, 0)
		L.add_child(lb)
		var ap := ArcPlot.new()
		ap.name = "sp_arc_%d" % k
		ap.f = f
		ap.custom_minimum_size = Vector2(380, 76)
		L.add_child(ap)
	if nbad > 0 and plan.is_empty():
		var b: Button = m._button("Fix the flights", offer, "move the needed spin into the take-off (a pivot on the take-off card, a constant rate in the air) and put a floating arc on the parabola; nothing changes until you Accept")
		b.name = "sp_fix"
		L.add_child(b)
	if not plan.is_empty():
		var l2: Label = m._label("FIX  -  " + String(plan["msg"]), 13, "heading", true)
		l2.name = "sp_plan"
		l2.custom_minimum_size = Vector2(380, 0)
		L.add_child(l2)
		var r2 := HBoxContainer.new()
		var pb: Button = m._button("Preview", preview, "play the fixed flights; the scene is not changed")
		pb.name = "sp_preview"
		var ab: Button = m._button("Accept", accept, "write the fixed take-off and arc; one undo step")
		ab.name = "sp_accept"
		r2.add_child(pb)
		r2.add_child(ab)
		L.add_child(r2)
	L.add_child(m._label("computed in %.0f ms" % ms, 12, "text:0.5", true))
	(m.ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(440, clampf(170.0 + 150.0 * fl.size() + (90.0 if not plan.is_empty() else 40.0), 200.0,
		minf(560.0, m.get_viewport().get_visible_rect().size.y - m.bottom_h - 82 - (m.TOP_H + 12) - 26)))
	m.ui_find.visible = true
	m._say("airborne spin: " + String(rep.get("msg", "")))


func offer() -> void:
	if not rep.get("ok", false):
		m._say("run the Airborne spin check first (Check > Airborne spin check)")
		return
	var p := SpinCheck.fix(m.S, m.B, rep)
	if int(p["spin"]) + int(p["float"]) == 0:
		m._say("nothing to fix: every flight is possible")
		return
	plan = p
	_panel()
	m._say("airborne spin fix: %s.  Preview, or Accept (Ctrl+Z undoes)" % plan["msg"])


func _close() -> void:
	clear_overlay()
	m._close_findings()


func preview() -> void:
	if plan.is_empty():
		m._say("nothing to preview: press Fix the flights first")
		return
	pv = (plan["scene"] as Scene).clone()
	pv_t = 0.0
	pv_end = maxf(pv.length(), 0.1)
	m.playing = false
	m._say("airborne spin: previewing the fixed flights (the scene is not changed)")


func tick(dt: float) -> void:
	if pv == null:
		return
	pv_t += dt
	if pv_t >= pv_end:
		halt()
		m._ps().apply(m.B, m.playhead)
		m._refresh()
		return
	pv.apply(m.B, pv_t)
	m._refresh()


func accept() -> void:
	if plan.is_empty():
		m._say("nothing to accept: press Fix the flights first")
		return
	halt()
	var msg: String = plan["msg"]
	m._step_hint = "Airborne spin: fix the flights"
	m._push_undo()
	m._markers_hold()
	m.S.cards = (plan["scene"] as Scene).cards.duplicate(true)
	m._markers_follow()
	m.sj.log("spin_check", "fix flights", -1, {}, m.undo.size())
	m._rebuild_cards()
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	compute()
	_panel()
	m._say("airborne spin: %s.  Ctrl+Z undoes it in one step" % msg)
