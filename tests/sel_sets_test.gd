## godot --path . -s tests/sel_sets_test.gd     (GATES II2, UPGRADES #67; a real window, the search's commands, real drags)
## SELECTION SETS: each "Select: <set>" command from the search makes exactly that group, the first named part the one
## the panel shows, no undo step; a real drag on the set's SECOND member (an arm's first: a hanging forearm hardly
## bends that way) turns every member by the same change, axis by axis,
## or the member is at its limit that way (a forearm is a hinge: no side, no twist, bend one way), or 2 deg more that way
## would push it deeper into the body (set_ang_safe stops it there: a spine bending into the hanging arms). "Select: just one part" clears the group. Typing "spine" in the
## search finds "Select: spine" among its results.
extends SceneTree

var fails := 0
var m: Node
const WANT := {"spine": ["spine_01", "spine_02", "spine_03"], "neck and head": ["neck_01", "head"],
	"left arm": ["upperarm_l", "lowerarm_l", "hand_l"], "right arm": ["upperarm_r", "lowerarm_r", "hand_r"],
	"left leg": ["thigh_l", "calf_l", "foot_l"], "right leg": ["thigh_r", "calf_r", "foot_r"]}


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func btn(down: bool, p: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await idle()


func move(p: Vector2, rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await idle()


func spot(j: String) -> Vector2:
	var c: Array = m.B.cap(j)
	return m.cam.unproject_position((c[0] + c[1]) * 0.5)


func run(name: String) -> bool:
	for c in m._commands():
		if c["name"] == name:
			(c["run"] as Callable).call()
			await idle()
			return true
	return false


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var bad := []
	var moved := {}
	var body_stops := []
	for st in WANT:
		m._new_scene()
		m.sel = "pelvis"
		m._refresh()
		await idle()
		var u0: int = m.undo.size()
		var found: bool = await run("Select: " + st)
		var g: Array = m.group()
		if not found or g != WANT[st] or m.sel != WANT[st][0] or m.undo.size() != u0:
			bad.append([st, found, g, m.sel, m.undo.size() - u0])
			continue
		var j: String = WANT[st][0] if st.ends_with("arm") else WANT[st][1]   # a hanging forearm hardly bends that way
		var a0 := {}
		for k in g:
			a0[k] = m.B.ang[k]
		# the press must land on the member (a part in front of it would take the press: then the set is not tested)
		var p := spot(j)
		if m._pick(p) != j:
			p = spot(WANT[st][0])
			j = WANT[st][0]
		await btn(true, p)
		for i in 5:
			p += Vector2(14, -18)
			await move(p, Vector2(14, -18))
		await btn(false, p)
		var d: Vector3 = (m.B.ang[j] as Vector3) - (a0[j] as Vector3)
		var each := []
		for k in g:
			var dk: Vector3 = (m.B.ang[k] as Vector3) - (a0[k] as Vector3)
			each.append(snappedf(dk.length(), 0.1))
			# what is left of the dragged part's change once the axes at their limit that way are dropped: none, or
			# 2 deg more along it (no contact check) goes deeper into the body (set_ang_safe stops a step as a whole)
			var now_k: Vector3 = m.B.ang[k]
			var rem := d - dk
			for i in 3:
				if absf(rem[i]) < 0.5:
					rem[i] = 0.0
					continue
				var push := now_k
				push[i] += 5.0 * signf(rem[i])
				if absf((m.B.clamp_ang(k, push) as Vector3)[i] - now_k[i]) <= 0.01:
					rem[i] = 0.0   # at its limit that way
			if rem.length() < 0.5:
				continue
			var keep: Dictionary = m.B.state()
			var pen0: float = m.B.penetration()
			m.B.set_ang(k, now_k + rem.normalized() * 2.0)
			var deeper: bool = m.B.penetration() > pen0 + 1e-4
			m.B.set_state(keep)
			if deeper:
				body_stops.append(k)
			else:
				bad.append([st, "%s changed %s, the dragged %s %s; the rest %s neither at a limit nor against the body" % [k, dk, j, d, rem]])
		if d.length() < 3.0:
			bad.append([st, "the dragged %s hardly turned (%s): the set is not tested" % [j, d]])
		moved[st] = [j, each]
		var now: Array = m.group()
		now.sort()
		var want: Array = WANT[st].duplicate()
		want.sort()
		if now != want:   # the dragged member becomes the one shown: the same members, another order
			bad.append([st, "the group changed by the drag: %s" % [m.group()]])
	ok(bad.is_empty() and moved.size() == 6, "1 the six sets from the search: each the right group, its first part shown, no undo step; a real drag on a member: every member, axis by axis, the same change or at its limit (dragged, change per member: %s; stopped by the body: %s) (bad: %s)" % [moved, body_stops, bad])
	await run("Select: left leg")
	await run("Select: just one part")
	ok(m.group() == ["thigh_l"], "2 'Select: just one part' after the left leg: %s" % [m.group()])
	m.ui_cmd.open()
	await idle()
	m.ui_cmd.box.text = "spine"
	m.ui_cmd._filter()
	var hits: Array = m.ui_cmd.shown.slice(0, 5).map(func(c): return c["name"])
	m.ui_cmd.close()
	ok(hits.has("Select: spine"), "3 the search for 'spine' lists 'Select: spine' in its first 5 (%s)" % [hits])
	print("SEL SETS: %d failed" % fails)
	quit(1 if fails > 0 else 0)
