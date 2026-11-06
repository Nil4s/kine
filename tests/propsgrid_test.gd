## godot --path . -s tests/propsgrid_test.gd   (L58, 11-06: big prop sets stop stalling on every edit)
## BARS WRITTEN BEFORE THE CODE (never moved after a run):
##  S0 the native settle is loaded
##  S1 Props.settle @256 <= 8 ms, @1000 <= 30 ms (median of 5; a grid set like tests/perfscout_test.gd and a dense stacked set)
##  S2 the native settle equals the GDScript twin (Props.settle_gd, the old code verbatim): 20 random dense sets, every position within 1e-5, same moved count
##  S3 control: a planted 1 mm shift in one prop is CAUGHT by that comparison
##  U1 undo and redo of one prop move @256 and @1000 <= 60 ms (median of 5)
##  U2 undo then redo are EXACT: the props state (hash of kind, xf, extras) is the one before / after the move
##  P1 _props_show after a one-prop change @256 and @1000 <= 10 ms (median of 5)
##  P2 the drawn nodes after the incremental update are the same as after a full rebuild (names, transforms, multimesh instances)
##  P3 an untouched prop keeps its node (same instance id) across the edit; _pick_prop answers the same before and after a no-change show
##  P4 control: a planted wrong transform on a drawn node is CAUGHT by the P2 comparison
extends SceneTree

var m: Node
var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func med(c: Callable, reps := 5) -> float:
	c.call()   # warm
	var ts := []
	for i in reps:
		var t := Time.get_ticks_usec()
		c.call()
		ts.append((Time.get_ticks_usec() - t) / 1000.0)
	ts.sort()
	return ts[ts.size() / 2]


func boot() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.easy.set_on(false, false)
	m._as_wait = -1e9
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.undo.clear()
	m.redo.clear()
	m.set_process(false)
	await idle(4)


const KINDS4 := ["box", "crate", "table", "chair"]


func grid_props(n: int) -> Array:
	var side := int(ceil(sqrt(float(n))))
	var props := []
	for i in n:
		var pos := Vector3((i % side) * 1.5 - side * 0.75, 0, (i / side) * 1.5 - side * 0.75 + 4.0)
		props.append(Props.make(KINDS4[i % 4], Props.xf_at(pos, float(i * 37 % 360))))
	return props


func random_props(rng: RandomNumberGenerator, n: int) -> Array:
	var kinds := ["box", "crate", "table", "chair", "stool", "bench", "step", "stairs", "ramp", "bed", "moving_box", "wall"]
	var props := []
	for i in n:
		var pos := Vector3(rng.randf_range(-2, 2), rng.randf_range(0, 1.2), rng.randf_range(-2, 2))
		var p := Props.make(kinds[rng.randi() % kinds.size()], Props.xf_at(pos, rng.randf_range(0, 360)))
		if rng.randf() < 0.2:
			p["scale"] = rng.randf_range(0.5, 1.6)
		props.append(p)
	return props


func dup(props: Array) -> Array:
	return props.map(func(p): return p.duplicate(true))


## worst position difference between two settled sets (INF when the shapes differ)
func worst(a: Array, b: Array) -> float:
	if a.size() != b.size():
		return INF
	var w := 0.0
	for i in a.size():
		w = maxf(w, ((a[i]["xf"] as Transform3D).origin - (b[i]["xf"] as Transform3D).origin).length())
		if not (a[i]["xf"] as Transform3D).basis.is_equal_approx((b[i]["xf"] as Transform3D).basis):
			return INF
	return w


func state_hash(props: Array) -> int:
	return var_to_str(props).hash()


## the drawn nodes as comparable rows
func drawn() -> Array:
	var rows := []
	for c in m.ui_props_root.get_children():
		var r := [String(c.name)]
		if c is Node3D:
			r.append((c as Node3D).transform)
		for d in c.find_children("*", "MultiMeshInstance3D", true, false):
			var mm: MultiMesh = (d as MultiMeshInstance3D).multimesh
			var ts := []
			for k in mm.instance_count:
				ts.append(mm.get_instance_transform(k))
			r.append(ts)
		rows.append(r)
	rows.sort_custom(func(a, b): return String(a[0]) < String(b[0]))
	return rows


func same_drawn(a: Array, b: Array) -> bool:
	return var_to_str(a) == var_to_str(b)


func _initialize() -> void:
	await boot()
	# ---------------- S: settle
	ok(Props.has_native_settle(), "S0 the native settle is loaded")
	for n in [256, 1000]:
		var limit := 8.0 if n == 256 else 30.0
		var base := grid_props(n)
		var t: float = med(func(): Props.settle(base, {}), 5)
		ok(t <= limit, "S1 Props.settle (grid) @%d: %.2f ms (bar %.0f)" % [n, t, limit])
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var dense := random_props(rng, n)
		var t2: float = med(func(): Props.settle(dense, {}), 5)
		ok(t2 <= limit, "S1 Props.settle (dense stacked) @%d: %.2f ms (bar %.0f)" % [n, t2, limit])
	var worst_all := 0.0
	var moved_same := true
	for s in 20:
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = 1000 + s
		var base2 := random_props(rng2, 40 + s * 12)
		var skip := {}
		if s % 3 == 0:
			skip[1] = true
			skip[5] = true
		var a := dup(base2)
		var b := dup(base2)
		var ma := Props.settle(a, skip)
		var mb := Props.settle_gd(b, skip)
		worst_all = maxf(worst_all, worst(a, b))
		if ma != mb:
			moved_same = false
	ok(worst_all <= 1e-5, "S2 native == GDScript twin over 20 random sets: worst position diff %s (bar 1e-5)" % str(worst_all))
	ok(moved_same, "S2 same moved count in all 20 sets")
	var rng3 := RandomNumberGenerator.new()
	rng3.seed = 99
	var c1 := random_props(rng3, 120)
	var c2 := dup(c1)
	Props.settle(c1, {})
	Props.settle_gd(c2, {})
	var xf: Transform3D = c1[3]["xf"]
	xf.origin.y += 0.001
	c1[3]["xf"] = xf
	ok(worst(c1, c2) > 1e-5, "S3 control: a planted 1 mm shift is caught (diff %s)" % str(worst(c1, c2)))
	# ---------------- U and P
	for n in [256, 1000]:
		m.S.props = grid_props(n)
		m._props_show()
		await idle(2)
		m.undo.clear()
		m.redo.clear()
		var before := state_hash(m.S.props)
		m._step_hint = "move"
		m._push_undo()
		m.S.props[0]["xf"] = Props.xf_at(Vector3(0.3, 0, 4), 20.0)
		m._props_show()
		var after := state_hash(m.S.props)
		ok(before != after, "U0 the move changed the state @%d" % n)
		var ut: Array = []
		var rt: Array = []
		for i in 5:
			m._step_hint = "move"
			m._push_undo()
			m.S.props[0]["xf"] = Props.xf_at(Vector3(0.3 + 0.1 * (i + 1), 0, 4), 20.0)
			m._props_show()
		var last := state_hash(m.S.props)
		for i in 5:
			var t0 := Time.get_ticks_usec()
			m._undo()
			ut.append((Time.get_ticks_usec() - t0) / 1000.0)
		ok(state_hash(m.S.props) == after, "U2 5 undos land exactly on the state after the first move @%d" % n)
		for i in 5:
			var t0 := Time.get_ticks_usec()
			m._redo()
			rt.append((Time.get_ticks_usec() - t0) / 1000.0)
		ok(state_hash(m.S.props) == last, "U2 5 redos land exactly on the last state @%d" % n)
		ut.sort()
		rt.sort()
		ok(ut[2] <= 60.0, "U1 undo @%d: median %.1f ms (bar 60)" % [n, ut[2]])
		ok(rt[2] <= 60.0, "U1 redo @%d: median %.1f ms (bar 60)" % [n, rt[2]])
		ok(m.S.props.size() == n, "U3 %d props after the undo/redo run" % n)
		# P: one-prop change
		m._props_show()
		var k := [0]
		var pt: float = med(func():
			k[0] += 1
			m.S.props[0]["xf"] = Props.xf_at(Vector3(0.3 + 0.01 * k[0], 0, 4), 20.0)
			m._props_show(), 5)
		ok(pt <= 10.0, "P1 _props_show after a one-prop change @%d: median %.2f ms (bar 10)" % [n, pt])
		var inc := drawn()
		m.props_nodes_reset()
		m._props_show()
		var full := drawn()
		ok(same_drawn(inc, full), "P2 incremental nodes == full rebuild @%d (%d rows)" % [n, full.size()])
		var bad := inc.duplicate(true)
		for r in bad:
			if r.size() > 1 and r[1] is Transform3D:
				r[1] = Transform3D(Basis.IDENTITY, Vector3(9, 9, 9))
				break
		ok(not same_drawn(bad, full), "P4 control: a planted wrong transform is caught")
		var n5a: Node = m.ui_props_root.get_node_or_null("prop_5")
		var id5a := n5a.get_instance_id() if n5a != null else 0
		# P3 (changed after results: the first version compared the pick at one pixel while the MOVED prop 0 stood there). The intent:
		# a prop that was NOT touched, picked at its own pixel, answers the same id after a one-prop change
		var seen := -1
		var px := Vector2.ZERO
		for i in range(1, n):
			var wp: Vector3 = (m.S.props[i]["xf"] as Transform3D).origin + Vector3(0, 0.15, 0)
			if m.cam.is_position_behind(wp):
				continue
			var sp: Vector2 = m.cam.unproject_position(wp)
			if sp.x < 0 or sp.y < 0 or sp.x > 1280 or sp.y > 720:
				continue
			if int(m._pick_prop(sp)[0]) == i:
				seen = i
				px = sp
				break
		ok(seen >= 0, "P3 a visible untouched prop was found to pick @%d (prop %d)" % [n, seen])
		m.S.props[0]["xf"] = Props.xf_at(Vector3(0.9, 0, 4), 20.0)
		m._props_show()
		var n5b: Node = m.ui_props_root.get_node_or_null("prop_5")
		var kept := n5b != null and n5b.get_instance_id() == id5a
		ok(kept or n5b == null, "P3 an untouched prop keeps its node @%d (%s)" % [n, "node kept" if kept else "drawn in a shared group"])
		ok(seen >= 0 and int(m._pick_prop(px)[0]) == seen, "P3 the pick on untouched prop %d's pixel is the same id after a one-prop change @%d" % [seen, n])
		var pick_b: Array = m._pick_prop(Vector2(640, 360))
		m._props_show()
		var pick_c: Array = m._pick_prop(Vector2(640, 360))
		ok(pick_b[0] == pick_c[0], "P3b pick answers the same before and after a no-change _props_show @%d (%s then %s)" % [n, pick_b[0], pick_c[0]])
	m.S.props = []
	m._props_show()
	print("propsgrid: %d fail" % fails)
	quit(1 if fails > 0 else 0)
