## PARRY REBOUND panel (ROADMAP I40; the maths: scripts/weapon_rebound.gd). "Parry rebound" lists every place two fighters' weapons meet (WeaponClash:
## CLASH or PARRY): how much angular velocity each weapon gets from the impact (momentum exchange at the contact, inertias of I30, restitution 0.5),
## how far each weapon and wrist is deflected, and the wrist torque against I30's maximum (a swing stopped dead with no give is flagged). The
## deflection arcs are drawn in the view: the authored tip path dim, the deflected one bright. Preview plays the exchange with the deflection keyed;
## Accept writes it as IK keys on both fighters' holding hands, ONE undo step. Nothing changes until Accept.
class_name WeaponReboundUI
extends RefCounted

const LEAD_IN := 0.3
const LEAD_OUT := 0.7

var m: Node
var rows: Array = []     # [{"an": analysis, "plan": [keys], "arcs": [...]}]
var override: Dictionary = {}
var ms := 0.0
var pv: Array = []       # the fighters being previewed (clones with the keys written)
var pv_t := 0.0
var pv_end := 0.0
var root: Node3D = null  # the arcs and the sparks, under the stage


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Parry rebound", "", show, "parry rebound weapons clash meet deflect deflection wrist forearm momentum restitution inertia stopped dead no give swing parry bounce recoil",
		false, "where two fighters' weapons meet: the momentum exchanged at the contact (both inertias, restitution 0.5), each weapon's change of angular velocity, and the deflection of both weapons and wrists keyed over the next 0.2 s, decaying back to your motion; flags a parry that stops a heavy swing dead (wrist torque over the maximum); arcs drawn, preview, accept (one undo step)")


func halt() -> void:
	_restore_view()
	clear_arcs()


func _fighters() -> Array:
	m._actors_sync()
	return Choreo.fighters_of(m)


func compute() -> void:
	var t0 := Time.get_ticks_usec()
	var keep: Dictionary = m.B.state()
	rows = []
	var fs := _fighters()
	for an in WeaponRebound.scan(fs, override):
		var pl := WeaponRebound.plan(fs, an)
		rows.append({"an": an, "plan": pl, "arcs": WeaponRebound.arcs(fs, an, pl)})
	m.B.set_state(keep)   # the analysis posed bodies at other times
	m.B.fk()
	ms = float(Time.get_ticks_usec() - t0) / 1000.0


func show() -> void:
	m._actors_sync()
	if m.actors_rt.size() < 2:
		m._say("Parry rebound needs two fighters with weapons: 'Actor: add a second fighter' first, hold a weapon in each, then try again")
		return
	_restore_view()
	compute()
	if rows.is_empty():
		m._say("Parry rebound found no weapon contact: move one swing into the other fighter's weapon (Check: weapon clashes shows where they meet), then try again")
	_panel()
	_draw_arcs()


func close() -> void:
	halt()
	m._close_findings()


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
		c.draw_rect(Rect2(w * 0.5 - 1, 0, 2, 14), Tok.c("text")))   # the wrist's maximum
	row.add_child(c)
	var vl: Label = m._label("%.0f / %.0f N m" % [v, mx], 12, "fail" if ratio > 1.0 else "text:0.8")
	row.add_child(vl)
	return row


func _who(s: Dictionary) -> String:
	var fs: Array = _fighters()
	var nm := String(fs[int(s["fighter"])]["name"])
	return "%s's %s" % [nm, "weapon" if String(s["weapon"]) == "weapon" else "off-hand weapon"]


func _panel() -> void:
	var L: VBoxContainer = m.ui_find_list
	for c in L.get_children():
		L.remove_child(c)
		c.queue_free()
	var dead := 0
	for r in rows:
		for s in r["an"]["sides"]:
			if bool(s["dead"]):
				dead += 1
	var head := HBoxContainer.new()
	L.add_child(head)
	var title: Label = m._label("PARRY REBOUND  -  " + ("no weapon contact in this scene" if rows.is_empty() else ("%d weapon contacts, %d stopped dead with no give" % [rows.size(), dead] if dead > 0 else "%d weapon contacts, every wrist can give" % rows.size())), 16, "heading" if dead == 0 else "warn")
	title.name = "wr_title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(m._button("Close", close))
	L.add_child(m._label("At the impact each weapon is a rigid body turning about its grip (inertia from the weapon weight panel); the exchange uses restitution %.1f (a heuristic). The wrist pulls it back like a critically damped spring (%.0f N m/rad, a heuristic): light weapons rebound fast and far, heavy ones slowly and little. The white tick is the wrist's isometric maximum, %.0f N m. Arcs: dim = your motion, bright = deflected. Preview changes nothing; Accept writes IK keys on both hands, one undo step (Ctrl+Z)." % [WeaponRebound.E_REST, WeaponRebound.K_WRIST, WeaponTorque.WRIST_MAX], 12, "text:0.6", true))
	for k in rows.size():
		var an: Dictionary = rows[k]["an"]
		var hd: Label = m._label("Contact %d  -  %s at %.2f s, closing at %.1f m/s, impulse %.2f N s" % [k + 1, String(an["ev"]["kind"]), float(an["t"]), float(an["close"]), float(an["j"])], 13, "text", true)
		hd.name = "wr_head_%d" % (k + 1)
		hd.custom_minimum_size = Vector2(380, 0)
		L.add_child(hd)
		for si in 2:
			var s: Dictionary = an["sides"][si]
			var tx: Label = m._label("%s  (%s %.1f kg, I = %.2f kg m2 about the grip): turns %.1f rad/s, weapon deflects %.1f deg, wrist %.1f cm" % [_who(s), String(s["kind"]),
				float(s["mass"]), float(s["i"]), (s["domega"] as Vector3).length(), float(s["angle"]), 100.0 * float(s["shift"])], 12, "text", true)
			tx.name = "wr_side_%d_%d" % [k + 1, si + 1]
			tx.custom_minimum_size = Vector2(380, 0)
			L.add_child(tx)
			var b := _bar(float(s["torque"]), WeaponTorque.WRIST_MAX, "wrist")
			b.name = "wr_bar_%d_%d" % [k + 1, si + 1]
			L.add_child(b)
			if bool(s["dead"]):
				var fl: Label = m._label("STOPPED DEAD: this parry takes %.0f%% of the swing's angular speed and the wrist would need %.0f N m (max %.0f N m): no give. Slow the swing, or let the weapon travel on" % [100.0 * minf(1.0, float(s["lost"])), float(s["torque"]), WeaponTorque.WRIST_MAX], 12, "warn", true)
				fl.name = "wr_dead_%d_%d" % [k + 1, si + 1]
				fl.custom_minimum_size = Vector2(380, 0)
				L.add_child(fl)
			elif s.has("why"):
				var wl: Label = m._label(String(s["why"]), 12, "text:0.6", true)
				wl.name = "wr_why_%d_%d" % [k + 1, si + 1]
				wl.custom_minimum_size = Vector2(380, 0)
				L.add_child(wl)
		if (rows[k]["plan"] as Array).is_empty():
			var nl: Label = m._label("nothing can be keyed here (see above)", 12, "warn", true)
			nl.name = "wr_none_%d" % (k + 1)
			L.add_child(nl)
		else:
			var rw := HBoxContainer.new()
			var pb: Button = m._button("Preview", preview.bind(k), "play the exchange with the deflection keyed; the scene is not changed")
			pb.name = "wr_preview_%d" % (k + 1)
			var ab: Button = m._button("Accept", accept.bind(k), "write the deflection as IK keys on the holding hands; one undo step")
			ab.name = "wr_accept_%d" % (k + 1)
			rw.add_child(pb)
			rw.add_child(ab)
			L.add_child(rw)
	L.add_child(m._label("computed in %.1f s" % (ms / 1000.0), 11, "text:0.5"))
	(m.ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(440, clampf(120.0 + 230.0 * rows.size(), 160.0,
		minf(560.0, m.get_viewport().get_visible_rect().size.y - m.bottom_h - 82 - (m.TOP_H + 12) - 26)))
	m.ui_find.visible = true
	m._say("parry rebound: " + ("no contact found" if rows.is_empty() else "%d contacts, %d stopped dead. Preview or Accept (Ctrl+Z undoes)" % [rows.size(), dead]))


# ---------------------------------------------------------------- the arcs in the view

func clear_arcs() -> void:
	if root != null and is_instance_valid(root):
		root.queue_free()
	root = null


func _line_mesh() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = ImmediateMesh.new()
	var lm := StandardMaterial3D.new()
	lm.vertex_color_use_as_albedo = true
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.no_depth_test = true
	lm.render_priority = 2
	mi.material_override = lm
	return mi


func _draw_arcs() -> void:
	clear_arcs()
	if rows.is_empty() or m.stage_root == null:
		return
	root = Node3D.new()
	root.name = "rebound_arcs"
	m.stage_root.add_child(root)
	var mi := _line_mesh()
	mi.name = "rebound_lines"
	root.add_child(mi)
	var im := mi.mesh as ImmediateMesh
	var dim: Color = Tok.c("text")
	dim.a = 0.55
	var cols := [Tok.c("mk_red"), Tok.c("mk_blue")]
	for r in rows:
		var arcs: Array = r["arcs"]
		for si in arcs.size():
			var a: Dictionary = arcs[si]
			im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
			for p in a["authored"]:
				im.surface_set_color(dim)
				im.surface_add_vertex(p)
			im.surface_end()
			im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
			for p in a["deflected"]:
				im.surface_set_color(cols[si % 2])
				im.surface_add_vertex(p)
			im.surface_end()
		var sp := WeaponClash.spark(r["an"]["ev"]["point"])
		root.add_child(sp)


# ---------------------------------------------------------------- preview / accept

func preview(k: int) -> void:
	if k < 0 or k >= rows.size() or (rows[k]["plan"] as Array).is_empty():
		m._say("pick a contact that can be keyed first (a row with Preview and Accept buttons), then Preview")
		return
	pv = WeaponRebound.with_plan(_fighters(), rows[k]["plan"])
	var t := float(rows[k]["an"]["t"])
	pv_t = maxf(0.0, t - LEAD_IN)
	pv_end = t + LEAD_OUT
	m.playing = false
	m._say("parry rebound preview: both fighters play the deflected exchange on copies (the scene is not changed)")


func _restore_view() -> void:
	if pv.is_empty():
		return
	pv = []
	for a in m.actors_rt:
		a["t"] = NAN
	m._ps().apply(m.B, m.playhead)
	m._refresh()


func tick(dt: float) -> void:
	if root != null and not m.ui_find.visible:
		clear_arcs()
	if pv.is_empty():
		return
	pv_t += dt
	if pv_t >= pv_end:
		_restore_view()
		return
	for k in mini(pv.size(), m.actors_rt.size()):
		(pv[k]["S"] as Scene).apply(m.actors_rt[k]["B"], pv_t)
		if k != m.actor_on:
			m.actors_rt[k]["t"] = m.playhead   # (_pose_others leaves a fighter alone whose t is the playhead)
	m._refresh()


func accept(k: int) -> void:
	if k < 0 or k >= rows.size():
		m._say("pick a contact from the list first, then Accept")
		return
	var pl: Array = rows[k]["plan"]
	if pl.is_empty():
		m._say("nothing to write for this contact: release the IK keys on the hands (see the row) and try again")
		return
	_restore_view()
	var fs := _fighters()
	m._step_hint = "Parry rebound"
	m._push_undo()
	WeaponRebound.write(fs.map(func(f): return f["S"]), pl)
	for a in m.actors_rt:
		a["t"] = NAN
	m._ps().apply(m.B, m.playhead)
	m.ov.mark_dirty()
	m.wt.mark_dirty()
	m._refresh()
	var an: Dictionary = rows[k]["an"]
	var n := 0
	for p in pl:
		n += (p["keys"] as Array).size()
	compute()
	_panel()
	_draw_arcs()
	m._say("parry rebound: %d IK keys on %d hands deflect both weapons over the next %.1f s after %.2f s.  Ctrl+Z undoes it in one step" % [n, pl.size(), WeaponRebound.WINDOW, float(an["t"])])
