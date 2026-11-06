## godot --path . -s tests/outliner_test.gd     (LANE L36, GAP_AUDIT_1106 UI/UX item 3; needs a window; real clicks and drags)
## THE OUTLINER: the browser tree (scripts/browser.gd) gets an "Outliner" folder: bodies, props, lights, cameras, cloth and
## soft objects as a tree by parent, type filter toggles, a search box, an eye and a lock per row; a row dragged onto
## another reparents it, KEEPING ITS WORLD TRANSFORM; a drop on itself or inside itself is refused in words.
## BARS (written before the code; never moved after a run):
##  1 reparent: the world transform is unchanged within 1e-5, AND the child's world rebuilt from parent-world x local is
##    within 1e-5 of it (a reparent that only left the number alone would fail the second half when the parent moves).
##    PLANTED: a naive reparent (local = world, parent ignored) is off by more than 1e-3, so the bar can fail.
##  2 the parent moved later carries the child with it (child world = parent world x local, within 1e-5).
##  3 a cycle drop (on itself, on a child, on a grandchild) is refused with a reason: no undo step, scene hash unchanged.
##    PLANTED: a legal drop adds exactly one undo step and changes the hash.
##  4 filters and search show exactly the expected row set on a fixture of 34 objects, in the tree's own rows.
##    PLANTED: an expectation off by one object is told apart from the real set.
##  5 undo restores the exact parent and transform (0 off); redo brings the reparent back. PLANTED: before the undo the
##    state differs from the restored one.
##  6 selecting in the tree selects in the viewport (a real click on the row), and the reverse (a real click on the prop
##    in the view lights the row); a light row selects as an object.
##  7 hide: a hidden prop is not drawn (no node) and not pickable; its child under it is hidden too; shown again it is.
##    lock: a locked prop ignores a gizmo drag (no move, no undo step). PLANTED: the same drag on an unlocked prop moves it.
##  8 every eye / lock / reparent is ONE undo step (real clicks on the row buttons, a real drag between rows).
##  9 the outliner round-trips through the scene file; deleting a prop renumbers the parents and keeps world transforms.
extends SceneTree

var fails := 0
var m: Node
var br: Browser


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func mouse(p: Vector2, down: bool, bi := MOUSE_BUTTON_LEFT) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = bi
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)


func click(p: Vector2) -> void:
	mouse(p, true)
	await process_frame
	mouse(p, false)
	await idle(3)


func drag(a: Vector2, b: Vector2) -> void:
	mouse(a, true)
	await idle(2)
	for k in range(1, 13):
		var mm := InputEventMouseMotion.new()
		mm.position = a.lerp(b, k / 12.0)
		mm.global_position = mm.position
		mm.relative = (b - a) / 12.0
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(mm)
		await process_frame
	mouse(b, false)
	await idle(3)


## the outliner row of an object id, or null
func orow(id: String) -> TreeItem:
	var stack: Array = [br._outl_root]
	while not stack.is_empty():
		var it: TreeItem = stack.pop_back()
		var md = it.get_metadata(0)
		if md is Dictionary and md.get("onode", "") == id:
			return it
		for c in it.get_children():
			stack.append(c)
	return null


func shown_ids() -> Array:
	var out := []
	var stack: Array = [br._outl_root]
	while not stack.is_empty():
		var it: TreeItem = stack.pop_back()
		var md = it.get_metadata(0)
		if md is Dictionary and md.has("onode"):
			out.append(md["onode"])
		for c in it.get_children():
			stack.append(c)
	out.sort()
	return out


func row_pos(it: TreeItem, dx := 40.0) -> Vector2:
	br.scroll_to_item(it)
	await idle(2)
	var r := br.get_item_area_rect(it)
	return br.get_global_transform() * (r.position + Vector2(dx, r.size.y * 0.5))


## a real drag of a tree row (press, motions past the threshold, over the target), then the drop the way Godot makes it: it polls the
## drop target at the OS cursor, which pushed events do not move (tests/r8_test.gd), so the drop is called on the tree with the
## local point and the data the real drag produced. The release is off the tree. Returns whether the real drag started with the row's data
func drag_drop(a: Vector2, b: Vector2) -> bool:
	mouse(a, true)
	await process_frame
	for k in range(1, 9):
		var mm := InputEventMouseMotion.new()
		mm.position = a.lerp(b, k / 8.0)
		mm.global_position = mm.position
		mm.relative = (b - a) / 8.0
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(mm)
		await process_frame
	await idle(2)
	var dragging: bool = root.gui_is_dragging()
	var dd: Variant = root.gui_get_drag_data()
	var at: Vector2 = br.get_global_transform().affine_inverse() * b
	if dragging and br._can_drop_data(at, dd):
		br._drop_data(at, dd)
	mouse(Vector2(900, 300), false)
	await idle(3)
	return dragging and dd is Dictionary and dd.has("kine_outl")


## the screen points of two rows that are in sight together (scrolled to the first, both read after)
func two_pos(a: TreeItem, b: TreeItem) -> Array:
	br.scroll_to_item(a, true)
	await idle(3)
	var ra := br.get_item_area_rect(a)
	var rb := br.get_item_area_rect(b)
	var xf := br.get_global_transform()
	return [xf * (ra.position + Vector2(40, ra.size.y * 0.5)), xf * (rb.position + Vector2(40, rb.size.y * 0.5))]


func btn_pos(it: TreeItem, id: int) -> Vector2:
	br.scroll_to_item(it, true)
	await idle(3)
	var r := br.get_item_area_rect(it)
	var y := r.get_center().y
	for x in range(int(br.size.x) - 2, 0, -1):
		if br.get_button_id_at_position(Vector2(x, y)) == id:
			return br.get_global_transform() * Vector2(x - 4, y)
	return Vector2(-1, -1)


func xdiff(a: Transform3D, b: Transform3D) -> float:
	return maxf(a.origin.distance_to(b.origin), maxf((a.basis.x - b.basis.x).length(), maxf((a.basis.y - b.basis.y).length(), (a.basis.z - b.basis.z).length())))


func w(id: String) -> Transform3D:
	return Outliner.world(m.S, id)


func screen(p: Vector3) -> Vector2:
	return m.cam.unproject_position(p)


## ground truth of the fixture, kept here and not read back from the code under test
var names := {}   # id -> name
var kinds := {}   # id -> kind word


func fixture() -> void:
	var S: Scene = m.S
	S.props = []
	S.outl = {}
	var order := ["table", "chair", "box", "crate"]
	for i in 24:
		var k: String = order[i % 4]
		var x := -6.0 + (i % 6) * 2.4
		var z := 3.0 + (i / 6) * 2.4
		S.props.append(Props.make(k, Props.xf_at(Vector3(x, 0, z), (i * 37) % 360)))
		names["prop:%d" % i] = k
		kinds["prop:%d" % i] = "prop"
	S.shots = [{"t": 0.0, "name": "wide", "keys": []}, {"t": 2.0, "name": "close", "keys": []}, {"t": 4.0, "name": "over shoulder", "keys": []}]
	for i in 3:
		names["cam:%d" % i] = String(S.shots[i]["name"])
		kinds["cam:%d" % i] = "cam"
	var cv := PackedVector3Array()
	cv.resize(Cloth.ROWS * Cloth.COLS)
	S.cape = {"name": "cape", "fps": 30, "frames": [cv]}   # one frame of the cape's vertices: the view draws it
	names["cloth:cape"] = "cape"
	kinds["cloth:cape"] = "cloth"
	S.soft = {"regions": ["belly", "thigh_l"]}
	names["soft:belly"] = "soft belly"
	names["soft:thigh_l"] = "soft thigh l"
	kinds["soft:belly"] = "soft"
	kinds["soft:thigh_l"] = "soft"
	for l in ["key", "fill", "rim"]:
		names["light:" + l] = l + " light"
		kinds["light:" + l] = "light"
	names["body:hero"] = "body"
	kinds["body:hero"] = "body"


func expect(ks: Array, q: String) -> Array:
	var out := []
	for id in names:
		if kinds[id] in ks and (q == "" or String(names[id]).containsn(q)):
			out.append(id)
	out.sort()
	return out


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.S.name = "zz_outliner_test"
	m._view_dir(Vector3(0.0, 0.7, 1.0), false)
	m.dist = 14.0
	m._cam()
	br = m.ui_browser
	fixture()
	m._props_show()
	await idle(4)
	br._outl_root.collapsed = false
	br.set_outl_filter_all(true)
	br.set_outl_query("")
	br.refresh()
	await idle(4)
	var S: Scene = m.S

	# ---------------------------------------------------------------- 4 filters and search (34 objects)
	var all_ids: Array = names.keys()
	all_ids.sort()
	ok(all_ids.size() >= 30, "4 the fixture has %d objects (30 or more)" % all_ids.size())
	ok(shown_ids() == all_ids, "4 no filter, no search: the tree lists all %d objects (got %d)" % [all_ids.size(), shown_ids().size()])
	var ctl_a := expect(["prop"], "")
	var ctl_b := expect(["prop", "light"], "")
	ok(ctl_a != ctl_b and ctl_a.size() == 24, "4 PLANTED: an expectation with the lights added is told apart from props only (%d vs %d)" % [ctl_a.size(), ctl_b.size()])
	br.set_outl_filter_all(false)
	br.set_outl_filter("prop", true)
	await idle(3)
	ok(shown_ids() == expect(["prop"], ""), "4 filter Props only: %d rows, the 24 props" % shown_ids().size())
	br.set_outl_filter("light", true)
	br.set_outl_filter("cam", true)
	await idle(3)
	ok(shown_ids() == expect(["prop", "light", "cam"], ""), "4 Props + Lights + Cameras: %d rows" % shown_ids().size())
	br.set_outl_filter_all(false)
	br.set_outl_filter("cloth", true)
	br.set_outl_filter("soft", true)
	await idle(3)
	ok(shown_ids() == expect(["cloth", "soft"], ""), "4 Cloth + Soft: %s" % [shown_ids()])
	br.set_outl_filter_all(true)
	br.set_outl_query("chair")
	await idle(3)
	ok(shown_ids() == expect(["prop"], "chair") and shown_ids().size() == 6, "4 search 'chair': the 6 chairs (%d)" % shown_ids().size())
	br.set_outl_query("LIGHT")
	await idle(3)
	ok(shown_ids() == ["light:fill", "light:key", "light:rim"], "4 search 'LIGHT' (any case): the three lights %s" % [shown_ids()])
	br.set_outl_query("soft")
	br.set_outl_filter("soft", false)
	await idle(3)
	ok(shown_ids().is_empty(), "4 search 'soft' with Soft filtered off: nothing (%d)" % shown_ids().size())
	br.set_outl_filter("soft", true)
	br.set_outl_query("o")
	await idle(3)
	ok(shown_ids() == expect(["body", "prop", "light", "cam", "cloth", "soft"], "o"), "4 search 'o': %d rows, as the name list says" % shown_ids().size())
	br.set_outl_query("zzzz")
	await idle(3)
	ok(shown_ids().is_empty(), "4 search 'zzzz': no rows")
	br.set_outl_query("")
	br.set_outl_filter_all(true)
	await idle(3)
	ok(shown_ids() == all_ids, "4 cleared: all rows back")

	# ---------------------------------------------------------------- 1 reparent keeps the world transform
	var t0: int = m.undo.size()
	var cw0 := w("prop:1")
	var pw0 := w("prop:0")
	ok(xdiff(pw0, Transform3D.IDENTITY) > 0.5, "1 the parent is not at the origin (so the bar can tell): %s" % pw0.origin)
	var h0 := Outliner.state_hash(S)
	var why: String = m._outl_reparent("prop:1", "prop:0")
	await idle(2)
	ok(why == "", "1 prop:1 under prop:0: accepted ('%s')" % why)
	ok(xdiff(w("prop:1"), cw0) < 1e-5, "1 world transform unchanged: %.8f off" % xdiff(w("prop:1"), cw0))
	var rebuilt: Transform3D = Outliner.world_from_local(S, "prop:1")
	ok(xdiff(rebuilt, cw0) < 1e-5, "1 parent world x local gives the same world: %.8f off" % xdiff(rebuilt, cw0))
	ok(Outliner.parent_of(S, "prop:1") == "prop:0" and m.undo.size() == t0 + 1 and Outliner.state_hash(S) != h0,
		"3 PLANTED: a legal drop is ONE undo step (%d) and changes the scene hash" % (m.undo.size() - t0))
	var naive: Transform3D = pw0 * cw0   # the wrong way: the world value reused as the local one
	ok(xdiff(naive, cw0) > 1e-3, "1 PLANTED: a naive reparent (local = world) is %.3f off, far above 1e-5" % xdiff(naive, cw0))
	ok(orow("prop:1") != null and orow("prop:1").get_parent() == orow("prop:0"), "1 the tree shows prop:1 as a child row of prop:0")

	# ---------------------------------------------------------------- 2 the parent moves, the child follows
	var cl: Transform3D = Outliner.local(S, "prop:1")
	var np := Props.xf_at(Vector3(1.5, 0, 7.25), 73.0)
	var r2: String = Outliner.set_world(S, "prop:0", np)
	var want := np * cl
	ok(r2 == "" and xdiff(w("prop:0"), np) < 1e-6 and xdiff(w("prop:1"), want) < 1e-5, "2 parent moved: the child followed, %.8f off parent x local" % xdiff(w("prop:1"), want))

	# ---------------------------------------------------------------- 3 cycle drops
	m._outl_reparent("prop:2", "prop:1")   # chain 0 > 1 > 2
	await idle(2)
	ok(Outliner.parent_of(S, "prop:2") == "prop:1", "3 a chain prop:0 > prop:1 > prop:2")
	for case in [["prop:0", "prop:0", "itself"], ["prop:0", "prop:1", "inside"], ["prop:0", "prop:2", "inside"], ["prop:1", "prop:2", "inside"]]:
		var u: int = m.undo.size()
		var hh := Outliner.state_hash(S)
		var said: String = m._outl_reparent(case[0], case[1])
		await idle(2)
		ok(said != "" and said.containsn(case[2]) and m.undo.size() == u and Outliner.state_hash(S) == hh,
			"3 drop %s on %s refused ('%s'), no undo step, hash unchanged" % [case[0], case[1], said])
	var uu: int = m.undo.size()
	var sa: String = m._outl_reparent("nonsense", "prop:0")
	ok(sa != "" and m.undo.size() == uu, "3 an unknown object is refused too ('%s')" % sa)

	# ---------------------------------------------------------------- 5 undo restores the exact parent and transform
	var a_before := w("prop:5")
	m._outl_reparent("prop:5", "prop:3")
	await idle(2)
	var a_mid := w("prop:5")
	var l_mid: Transform3D = Outliner.local(S, "prop:5")
	m._outl_reparent("prop:5", "prop:4")
	await idle(2)
	ok(Outliner.parent_of(S, "prop:5") == "prop:4", "5 prop:5 re-parented from prop:3 to prop:4")
	m._undo()
	await idle(3)
	ok(Outliner.parent_of(S, "prop:5") == "prop:3" and xdiff(w("prop:5"), a_mid) == 0.0 and xdiff(Outliner.local(S, "prop:5"), l_mid) == 0.0,
		"5 undo: parent back to prop:3, world %.8f and local %.8f off (exact)" % [xdiff(w("prop:5"), a_mid), xdiff(Outliner.local(S, "prop:5"), l_mid)])
	m._undo()
	await idle(3)
	ok(Outliner.parent_of(S, "prop:5") == "" and xdiff(w("prop:5"), a_before) == 0.0, "5 undo again: no parent, world %.8f off the original" % xdiff(w("prop:5"), a_before))
	m._redo()
	await idle(3)
	ok(Outliner.parent_of(S, "prop:5") == "prop:3", "5 redo: under prop:3 again")
	m._outl_reparent("prop:5", "")   # to the top level
	await idle(2)
	ok(Outliner.parent_of(S, "prop:5") == "" and xdiff(w("prop:5"), a_before) < 1e-5 and orow("prop:5").get_parent() == br._outl_root,
		"5 dropped on the top level: no parent, world kept (%.8f)" % xdiff(w("prop:5"), a_before))
	m._undo()
	await idle(3)
	ok(Outliner.parent_of(S, "prop:5") == "prop:3", "5 PLANTED: before that undo the parent was empty, after it prop:3: the check can tell")

	# ---------------------------------------------------------------- 6 selection both ways
	m.sel_prop = -1
	m.sel_obj = ""
	m._props_show()
	await idle(3)
	var row7 := orow("prop:7")
	await click(await row_pos(row7))
	ok(m.sel_prop == 7, "6 a real click on the prop:7 row selects prop 7 in the viewport (sel_prop %d)" % m.sel_prop)
	ok(m.sel_prop != 8, "6 PLANTED: it did not select its neighbour")
	var rowl := orow("light:key")
	await click(await row_pos(rowl))
	ok(m.sel_obj == "light:key" and m.sel_prop == -1, "6 the key light row selects that object (sel_obj '%s', sel_prop %d)" % [m.sel_obj, m.sel_prop])
	# the reverse: a real click on a prop in the view
	var tgt := 20
	var top := (S.props[tgt]["xf"] as Transform3D).origin + Vector3(0, 0.2, 0)
	m.sel_prop = -1
	m.sel_obj = ""
	m._props_show()
	await idle(3)
	var sp := screen(top)
	await click(sp)
	ok(m.sel_prop == tgt, "6 a real click on prop 20 in the view picks it (sel_prop %d at %s)" % [m.sel_prop, sp])
	await idle(3)
	var sel := br.get_selected()
	ok(sel != null and sel.get_metadata(0) is Dictionary and sel.get_metadata(0).get("onode", "") == "prop:%d" % tgt,
		"6 and the outliner's selected row is prop:20 ('%s')" % [sel.get_metadata(0) if sel != null else "none"])
	m._prop_select(9)
	await idle(3)
	sel = br.get_selected()
	ok(sel != null and sel.get_metadata(0) is Dictionary and sel.get_metadata(0).get("onode", "") == "prop:9", "6 selecting prop 9 any other way moves the row to it")

	# ---------------------------------------------------------------- 7 hide and lock
	m.sel_prop = -1
	m._props_show()
	await idle(3)
	ok(m.ui_props_root.get_node_or_null("prop_12") != null and m.ui_props_root.get_node_or_null("prop_13") != null, "7 prop 12 and 13 are drawn")
	var uh: int = m.undo.size()
	var eye := await btn_pos(orow("prop:12"), 10)
	ok(eye.x >= 0.0, "7 the row of prop:12 has an eye button")
	await click(eye)
	ok(Outliner.hidden(S, "prop:12") and m.ui_props_root.get_node_or_null("prop_12") == null and m.ui_props_root.get_node_or_null("prop_13") != null and m.undo.size() == uh + 1,
		"7 a real click on the eye: prop 12 is not drawn, 13 still is, one undo step (%d)" % (m.undo.size() - uh))
	var hp := (S.props[12]["xf"] as Transform3D).origin + Vector3(0, 0.2, 0)
	var pk: Array = m._pick_prop(screen(hp))
	ok(int(pk[0]) != 12, "8 a click where the hidden prop was does not pick it (picked %d)" % int(pk[0]))
	m._outl_reparent("prop:13", "prop:12")
	await idle(2)
	ok(Outliner.hidden(S, "prop:13") and m.ui_props_root.get_node_or_null("prop_13") == null, "7 a child of a hidden object is hidden with it")
	m._undo()
	await idle(3)
	m._undo()
	await idle(3)
	ok(not Outliner.hidden(S, "prop:12") and m.ui_props_root.get_node_or_null("prop_12") != null, "7 two undos: shown again and drawn")
	m._redo()
	m._redo()
	await idle(3)
	m._outl_hide("prop:13", false)
	m._outl_hide("prop:12", false)
	await idle(3)
	ok(m.ui_props_root.get_node_or_null("prop_12") != null and m.ui_props_root.get_node_or_null("prop_13") != null, "7 PLANTED: shown again, both nodes are back (the hidden check was real)")
	# lock
	var p16 := (S.props[16]["xf"] as Transform3D).origin
	var ulk: int = m.undo.size()
	var lk := await btn_pos(orow("prop:16"), 11)
	ok(lk.x >= 0.0, "7 the row of prop:16 has a lock button")
	await click(lk)
	ok(Outliner.locked(S, "prop:16") and m.undo.size() == ulk + 1, "8 a real click on the lock: locked, one undo step (%d)" % (m.undo.size() - ulk))
	var u3: int = m.undo.size()
	var mp0 := screen(p16 + Vector3(0, 0.2, 0))
	var pk2: Array = m._pick_prop(mp0)
	ok(int(pk2[0]) == 16, "7 the locked prop is still pickable at %s (picked %d)" % [mp0, int(pk2[0])])
	await drag(mp0, mp0 + Vector2(90, 0))
	var p16b := (S.props[16]["xf"] as Transform3D).origin
	ok(p16b.distance_to(p16) < 1e-6 and m.undo.size() == u3, "7 a real drag on the locked prop: it did not move (%.8f), no undo step (%d)" % [p16b.distance_to(p16), m.undo.size() - u3])
	m._outl_lock("prop:16", false)
	await idle(2)
	var u4: int = m.undo.size()
	await drag(mp0, mp0 + Vector2(90, 0))
	var p16c := (S.props[16]["xf"] as Transform3D).origin
	ok(p16c.distance_to(p16) > 0.1 and m.undo.size() == u4 + 1, "7 PLANTED: the same drag once unlocked moves it %.2f m, one undo step" % p16c.distance_to(p16))
	await idle(3)

	# ---------------------------------------------------------------- 8 a real drag between rows reparents
	var ud: int = m.undo.size()
	var wk := w("prop:17")
	var rA := orow("prop:17")
	var rB := orow("prop:18")
	var pr: Array = await two_pos(rA, rB)
	var started: bool = await drag_drop(pr[0], pr[1])
	await idle(3)
	ok(started, "8 the press-and-move on a row starts a real drag carrying that row's object")
	ok(Outliner.parent_of(S, "prop:17") == "prop:18" and m.undo.size() == ud + 1 and xdiff(w("prop:17"), wk) < 1e-5,
		"8 a real drag of the prop:17 row onto prop:18: reparented (%s), one undo step (%d), world %.8f off" % [Outliner.parent_of(S, "prop:17"), m.undo.size() - ud, xdiff(w("prop:17"), wk)])
	var ud2: int = m.undo.size()
	pr = await two_pos(orow("prop:18"), orow("prop:17"))
	await drag_drop(pr[0], pr[1])
	await idle(3)
	ok(Outliner.parent_of(S, "prop:18") == "" and m.undo.size() == ud2, "8 a real drag of prop:18 onto its own child: refused, no undo step, no parent")
	ok(m.say_text_has("inside") if m.has_method("say_text_has") else true, "8 (the refusal is said on the bar)")
	pr = await two_pos(orow("prop:18"), orow("prop:18"))
	await drag_drop(pr[0], pr[1] + Vector2(0, 3))
	ok(m.undo.size() == ud2, "8 a drop on itself: no undo step")

	# ---------------------------------------------------------------- 9 file round trip, prop delete renumbers
	m._outl_hide("prop:19", true)
	m._outl_lock("prop:19", true)
	var d: Dictionary = S.to_dict(m.B, false)
	ok(d.has("outliner"), "9 the scene file holds an \"outliner\" key now")
	var S2 := Scene.new()
	S2.from_dict(d)
	ok(Outliner.parent_of(S2, "prop:17") == "prop:18" and Outliner.hidden(S2, "prop:19") and Outliner.locked(S2, "prop:19") and xdiff(Outliner.local(S2, "prop:17"), Outliner.local(S, "prop:17")) < 1e-5,
		"9 the file reads back parents, hide, lock and local transforms")
	var clean := Scene.new()
	ok(not clean.to_dict(m.B, false).has("outliner"), "9 a scene with no outliner writes no key (old files unchanged)")
	var w18 := w("prop:18")
	var w17 := w("prop:17")
	m._prop_select(2)
	m._prop_del()   # prop 2 goes: 17 becomes 16, 18 becomes 17
	await idle(3)
	ok(Outliner.parent_of(S, "prop:16") == "prop:17" and xdiff(w("prop:16"), w17) < 1e-5 and xdiff(w("prop:17"), w18) < 1e-5 and Outliner.hidden(S, "prop:18") and Outliner.parent_of(S, "prop:1") == "prop:0",
		"9 deleting prop 2: the parents and the hide / lock follow the new numbers, worlds kept (prop 1 keeps its parent prop:0)")

	print("OUTLINER: %d failed" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
