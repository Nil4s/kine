## WEAPON WEIGHT panel (ROADMAP I30; the maths: scripts/weapon_torque.gd). "Weapon weight" lists every weapon swing in the scene with its peak
## torque at the wrist and the shoulder against the human maximum (a bar each, red past the maximum), what is weightless about it, and ONE fix per
## swing (anticipation card scaled by the weapon's inertia, overshoot, an eased stop, and a slower swing until the arm can do it). Preview plays
## the fixed swing on a copy; Accept writes it as ONE undo step. Nothing in the scene changes until Accept.
class_name WeaponTorqueUI
extends RefCounted

const LEAD_IN := 0.3
const LEAD_OUT := 0.6

var m: Node
var rows: Array = []      # [{"r": analysis, "fx": fix or {}}]
var override: Dictionary = {}   # {} = each card's own weapon; else a weapon profile override ("what if this were heavier")
var ms := 0.0
var pv: Scene = null
var pv_t := 0.0
var pv_end := 0.0


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Weapon weight", "", show, "weapon weight torque wrist shoulder inertia mass swing heavy too fast weightless windup anticipation follow-through overshoot stop strength",
		false, "for each weapon swing: the torque the wrist and the shoulder must give (weapon + arm, from the clip) against human strength, with a bar; flags a swing too fast for its weapon and a weightless one (no wind-up, no follow-through, an instant stop); one-click fixes, preview then accept (one undo step)")


func halt() -> void:
	pv = null


func compute() -> void:
	var t0 := Time.get_ticks_usec()
	var keep: Dictionary = m.B.state()
	rows = []
	var prof := {} if override.is_empty() else WeaponTorque.profile(String(override.get("kind", "metal_bat")), override)
	for s in WeaponTorque.swings(m.S, m.B):
		var r := WeaponTorque.analyze(m.S, m.B, int(s["card"]), prof)
		rows.append({"r": r, "fx": {}})
	m.B.set_state(keep)   # the analysis posed the body at other times
	m.B.fk()
	ms = float(Time.get_ticks_usec() - t0) / 1000.0


func show() -> void:
	if m.S.cards.size() < 2:
		m._say("Weapon weight needs a swing: press Enter to add the body as a card (two at least) with a weapon in hand, and mark the strike")
		return
	compute()
	if rows.is_empty():
		m._say("Weapon weight found no weapon swing: hold a weapon (Weapon: metal bat ...) and name the strike card 'strike' or put a hit marker on it, then try again")
	_panel()


func _bar(v: float, mx: float, label: String) -> Control:
	var row := HBoxContainer.new()
	var lb: Label = m._label(label, 12, "text:0.8")
	lb.custom_minimum_size = Vector2(66, 0)
	row.add_child(lb)
	var c := Control.new()
	c.custom_minimum_size = Vector2(190, 14)
	var ratio := v / mx
	c.draw.connect(func():
		var w := c.size.x
		var span := 2.0   # the bar's full width is twice the maximum
		c.draw_rect(Rect2(0, 2, w, 10), Tok.c("field"))
		var col := Tok.c("fv_ok") if ratio <= 0.8 else (Tok.c("fv_mid") if ratio <= 1.0 else Tok.c("fv_hot"))
		c.draw_rect(Rect2(0, 2, minf(w, w * ratio / span), 10), col)
		c.draw_rect(Rect2(w * 0.5 - 1, 0, 2, 14), Tok.c("text")))   # the human maximum
	row.add_child(c)
	var vl: Label = m._label("%.0f / %.0f N m" % [v, mx], 12, "fail" if ratio > 1.0 else "text:0.8")
	row.add_child(vl)
	return row


func _panel() -> void:
	var L: VBoxContainer = m.ui_find_list
	for c in L.get_children():
		L.remove_child(c)
		c.queue_free()
	var bad := rows.filter(func(x): return not x["r"]["ok"]).size()
	var head := HBoxContainer.new()
	L.add_child(head)
	var title: Label = m._label("WEAPON WEIGHT  -  " + ("no weapon swing in this scene" if rows.is_empty() else ("every swing is believable" if bad == 0 else "%d of %d swings need work" % [bad, rows.size()])), 16, "heading" if bad == 0 else "warn")
	title.name = "wt_title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(m._button("Close", m._close_findings))
	L.add_child(m._label("Torque = what the swing needs (I x alpha of the weapon and the arm's segments, 120 Hz finite differences; gravity left out). The white tick is the human isometric maximum: wrist %.0f N m, shoulder %.0f N m - rounded HEURISTICS from Delp 1996 / Otis 1990, not measured here. Preview changes nothing; Accept is one undo step (Ctrl+Z)." % [WeaponTorque.WRIST_MAX, WeaponTorque.SHOULDER_MAX], 12, "text:0.6", true))
	for k in rows.size():
		var r: Dictionary = rows[k]["r"]
		var p: Dictionary = r["prof"]
		var hd: Label = m._label("Swing %d  -  card %d '%s'  -  %s %.1f kg, I = %.2f kg m2 about the grip (%s)" % [k + 1, int(r["card"]) + 1,
			String(m.S.cards[int(r["card"])]["name"]), String(r["kind"]), float(p["mass"]), float(p["i_grip"]), String(p["src"])], 13, "text", true)
		hd.name = "wt_head_%d" % (k + 1)
		hd.custom_minimum_size = Vector2(380, 0)
		L.add_child(hd)
		var pw := maxf(float(r["wrist"][0]), float(r["stop_wrist"][0]))
		var ps := maxf(float(r["shoulder"][0]), float(r["stop_shoulder"][0]))
		var b1 := _bar(pw, WeaponTorque.WRIST_MAX, "wrist")
		b1.name = "wt_bar_wrist_%d" % (k + 1)
		L.add_child(b1)
		var b2 := _bar(ps, WeaponTorque.SHOULDER_MAX, "shoulder")
		b2.name = "wt_bar_shoulder_%d" % (k + 1)
		L.add_child(b2)
		var tx: Label = m._label(WeaponTorque.describe(r), 12, "heading" if r["ok"] else "warn", true)
		tx.name = "wt_text_%d" % (k + 1)
		tx.custom_minimum_size = Vector2(380, 0)
		L.add_child(tx)
		if not r["ok"]:
			var fxd: Dictionary = rows[k]["fx"]
			if fxd.is_empty():
				var fb: Button = m._button("Work out a fix", fix.bind(k), "work out the repair (anticipation, overshoot, eased stop, slower swing); nothing changes until you Accept")
				fb.name = "wt_fix_%d" % (k + 1)
				L.add_child(fb)
			else:
				var fl: Label = m._label("FIX  -  " + String(fxd["msg"]), 12, "say", true)
				fl.name = "wt_fixtext_%d" % (k + 1)
				fl.custom_minimum_size = Vector2(380, 0)
				L.add_child(fl)
				var rw := HBoxContainer.new()
				var pb: Button = m._button("Preview", preview.bind(k), "play the fixed swing; the scene is not changed")
				pb.name = "wt_preview_%d" % (k + 1)
				var ab: Button = m._button("Accept", accept.bind(k), "write the fixed swing; one undo step")
				ab.name = "wt_accept_%d" % (k + 1)
				rw.add_child(pb)
				rw.add_child(ab)
				L.add_child(rw)
	L.add_child(m._label("computed in %.1f s" % (ms / 1000.0), 11, "text:0.5"))
	(m.ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(440, clampf(120.0 + 150.0 * rows.size(), 160.0,
		minf(560.0, m.get_viewport().get_visible_rect().size.y - m.bottom_h - 82 - (m.TOP_H + 12) - 26)))
	m.ui_find.visible = true
	m._say("weapon weight: " + ("no swing found" if rows.is_empty() else "%d swings, %d need work. 'Work out a fix', then Preview or Accept (Ctrl+Z undoes)" % [rows.size(), bad]))


func fix(k: int) -> void:
	if k < 0 or k >= rows.size():
		m._say("pick a swing from the list first")
		return
	var keep: Dictionary = m.B.state()
	var f := WeaponTorque.fix(m.S, m.B, rows[k]["r"])
	m.B.set_state(keep)
	m.B.fk()
	if not f["ok"]:
		m._say(String(f["msg"]))
		return
	rows[k]["fx"] = f
	_panel()


func preview(k: int) -> void:
	if k >= rows.size() or rows[k]["fx"].is_empty():
		m._say("work out a fix first (press 'Work out a fix' beside the swing), then Preview")
		return
	var f: Dictionary = rows[k]["fx"]
	pv = (f["scene"] as Scene).clone()
	var ts := pv.times()
	var c: int = f["card"]
	pv_t = maxf(0.0, float(ts[maxi(1, c - 1)][0]) - LEAD_IN)
	pv_end = minf(pv.length(), float(ts[c][1]) + LEAD_OUT)
	m.playing = false
	m._say("weapon weight preview: the fixed swing plays on a copy (the scene is not changed)")


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
	if k >= rows.size() or rows[k]["fx"].is_empty():
		m._say("work out a fix first (press 'Work out a fix' beside the swing), then Accept")
		return
	pv = null
	var f: Dictionary = rows[k]["fx"]
	m._step_hint = "Weapon weight: fix swing"
	m._push_undo()
	m._markers_hold()
	m.S.cards = (f["scene"] as Scene).cards.duplicate(true)
	m._markers_follow()
	m._retimed()
	m._rebuild_cards()
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	compute()
	_panel()
	m._say("weapon weight: %s.  Ctrl+Z undoes it in one step" % String(f["msg"]))
