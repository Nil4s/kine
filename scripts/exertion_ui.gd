## FATIGUE panel (ROADMAP I34; the maths: scripts/exertion.gd). "Fatigue" reads each fighter's mechanical work over the clip (the Force view's
## joint powers), draws a green -> red fatigue strip per fighter under the timeline, and flags a fighter who is still at full speed (or whose
## guard has not dropped) late in a long exchange. "Tire him" works out slower strikes, longer recovers and a lower guard for the cards after
## fatigue 0.5; Preview plays it (nothing changes), Accept writes it as ONE undo step.
class_name ExertionUI
extends RefCounted

var m: Node
var reps: Array = []        # per fighter: Exertion.analyze
var plan: Dictionary = {}   # the tire-him plan being offered: {"who", "scene", "msg", ...}
var pv: Scene = null
var pv_who := -1
var pv_t := 0.0
var pv_end := 0.0
var ms := 0.0


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Fatigue", "", show, "fatigue tired work power stamina fighter flag fresh tire him guard slow",
		false, "per fighter: the mechanical work done over the clip (joint power from the force view), a green-to-red fatigue strip on the timeline, a flag for a fighter still at full speed late in a long exchange, and a Tire him pass (slower strikes, longer recovers, lower guard); preview, then accept = one undo step")


func fighters() -> Array:
	m._actors_sync()
	if m.actors_rt.is_empty():
		return [{"S": m.S, "B": m.B, "name": "fighter 1"}]
	return m.actors_rt.map(func(a): return {"S": a["S"], "B": a["B"], "name": String(a["name"])})


func halt() -> void:
	pv = null
	pv_who = -1


func compute() -> void:
	var t0 := Time.get_ticks_usec()
	reps = []
	for f in fighters():
		reps.append(Exertion.analyze(f["S"], f["B"]))
	ms = float(Time.get_ticks_usec() - t0) / 1000.0
	plan = {}
	_overlay()


func _overlay() -> void:
	var tl = m.ui_timeline
	if tl == null:
		return
	var strip := []
	for w in reps.size():
		var rep: Dictionary = reps[w]
		if not rep.get("ok", false):
			continue
		var F: Array = rep["F"]
		var step := maxi(int(ForceView.HZ / 12.0), 1)   # a segment per 1/12 s
		var i := 0
		while i < F.size():
			var j := mini(i + step, F.size() - 1)
			strip.append({"who": w, "t0": float(i) / ForceView.HZ, "t1": float(maxi(j, i + 1)) / ForceView.HZ, "f": float(F[mini(i + step / 2, F.size() - 1)])})
			i += step
	tl.fa = strip
	tl.fa_n = reps.size()
	tl.queue_redraw()


func clear_overlay() -> void:
	reps = []
	plan = {}
	halt()
	_overlay()


func show() -> void:
	var fs := fighters()
	if fs.any(func(f): return (f["S"] as Scene).cards.size() < 2) and fs.size() == 1:
		m._say("Fatigue needs a scene of two cards or more: press Enter to add the body as a card (two at least), or open a scene in the list below")
		return
	m._say("fatigue: reading the clip's joint powers...")
	compute()
	_panel()


func _panel() -> void:
	var L: VBoxContainer = m.ui_find_list
	for c in L.get_children():
		L.remove_child(c)
		c.queue_free()
	var fs := fighters()
	var nflag := reps.filter(func(r): return r.get("flag", false)).size()
	var head := HBoxContainer.new()
	L.add_child(head)
	var title: Label = m._label("FATIGUE  -  " + ("%d fighter%s still fresh" % [nflag, "" if nflag == 1 else "s"] if nflag > 0 else "nobody is flagged"), 16, "warn" if nflag > 0 else "heading", true)
	title.name = "fa_title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(m._button("Close", _close))
	var exp: Label = m._label("Work = positive joint power summed (Force view). Budget with recovery (critical power, Skiba 2012); constants are a heuristic: CP %.0f W, W' %.0f J, tau %.0f s." % [Exertion.CP, Exertion.WPRIME, Exertion.TAU_REC], 12, "text:0.6", true)
	exp.custom_minimum_size = Vector2(380, 0)
	L.add_child(exp)
	for w in reps.size():
		var rep: Dictionary = reps[w]
		if not rep.get("ok", false):
			continue
		var nm := String((fs[w] as Dictionary)["name"]) if w < fs.size() else "fighter %d" % (w + 1)
		var lb: Label = m._label("%s  -  work %.0f J, fatigue at the end %.2f (peak %.2f)\n%s" % [nm, rep["work"], Exertion.at(rep, float((fs[w]["S"] as Scene).length())), rep["fmax"], rep["msg"]], 13,
			"warn" if rep.get("flag", false) else "text:0.85", true)
		lb.name = "fa_row_%d" % w
		lb.custom_minimum_size = Vector2(380, 0)
		L.add_child(lb)
		if float(rep["fmax"]) > Exertion.TIRE_FROM:
			var b: Button = m._button("Tire him" + (" (%s)" % nm if reps.size() > 1 else ""), offer.bind(w), "work out slower strikes, longer recovers and a lower guard for the cards after fatigue %.1f; nothing changes until you Accept" % Exertion.TIRE_FROM)
			b.name = "fa_tire_%d" % w
			L.add_child(b)
	if not plan.is_empty():
		var l2: Label = m._label("TIRE HIM  -  %s: %s" % [plan["name"], plan["msg"]], 13, "heading", true)
		l2.name = "fa_plan"
		l2.custom_minimum_size = Vector2(380, 0)
		L.add_child(l2)
		var r2 := HBoxContainer.new()
		var pb: Button = m._button("Preview", preview, "play the tired fighter; the scene is not changed")
		pb.name = "fa_preview"
		var ab: Button = m._button("Accept", accept, "write the tired timing and guard; one undo step")
		ab.name = "fa_accept"
		r2.add_child(pb)
		r2.add_child(ab)
		L.add_child(r2)
	L.add_child(m._label("computed in %.0f ms" % ms, 12, "text:0.5", true))
	(m.ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(440, clampf(170.0 + 120.0 * reps.size() + (80.0 if not plan.is_empty() else 0.0), 200.0,
		minf(560.0, m.get_viewport().get_visible_rect().size.y - m.bottom_h - 82 - (m.TOP_H + 12) - 26)))
	m.ui_find.visible = true
	m._say("fatigue: " + " | ".join(reps.map(func(r): return String(r.get("msg", "")))))


func offer(w: int) -> void:
	var fs := fighters()
	if w < 0 or w >= reps.size() or w >= fs.size():
		m._say("pick a fighter from the list first")
		return
	var f: Dictionary = fs[w]
	var p := Exertion.tire(f["S"], f["B"], reps[w])
	p["who"] = w
	p["name"] = String(f["name"])
	plan = p
	_panel()
	m._say("tire him (%s): %s.  Preview, or Accept (Ctrl+Z undoes)" % [plan["name"], plan["msg"]])


func _close() -> void:
	clear_overlay()
	m._close_findings()


func preview() -> void:
	if plan.is_empty():
		m._say("nothing to preview: press Tire him beside a fighter first")
		return
	pv = (plan["scene"] as Scene).clone()
	pv_who = int(plan["who"])
	pv_t = 0.0
	pv_end = maxf(pv.length(), 0.1)
	m.playing = false
	m._say("tire him: previewing %s (the scene is not changed)" % plan["name"])


func tick(dt: float) -> void:
	if pv == null:
		return
	pv_t += dt
	if pv_t >= pv_end:
		halt()
		m._ps().apply(m.B, m.playhead)
		m._refresh()
		return
	for k in m.actors_rt.size():
		var sc: Scene = pv if k == pv_who else m.actors_rt[k]["S"]
		sc.apply(m.actors_rt[k]["B"], pv_t)
	if m.actors_rt.is_empty():
		pv.apply(m.B, pv_t)
	m._refresh()


func accept() -> void:
	if plan.is_empty():
		m._say("nothing to accept: press Tire him beside a fighter first")
		return
	halt()
	var w: int = plan["who"]
	var msg := "%s: %s" % [plan["name"], plan["msg"]]
	var fs := fighters()
	var S: Scene = fs[w]["S"]
	m._step_hint = "Fatigue: tire him"
	m._push_undo()   # (the snapshot holds every fighter's cards)
	m._markers_hold()
	S.cards = (plan["scene"] as Scene).cards.duplicate(true)
	if S == m.S:
		m._markers_follow()
	m.sj.log("fatigue", "tire him", -1, {}, m.undo.size())
	m._rebuild_cards()
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	compute()
	_panel()
	m._say("tire him: %s.  Ctrl+Z undoes it in one step" % msg)
