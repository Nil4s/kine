extends SceneTree
## godot --path . --position 4000,4000 -s tests/s225_test.gd     (FRIDAY 225 NATURE + SCATTER; scripts/build/nature.gd, nature_view.gd, nature_words.gd, nature_ui.gd, nature_agent.gd; needs a window)
## Bars (all measured from the MADE nodes / the saved file, never from the generator's own variables):
##   1 SEED      the same tree record twice = the same wood (every vertex) and the same leaves; another seed differs; same for a hedge
##   2 SIZE      6 species x 2 heights: the tree NODE's height and crown width (wood AABB + every leaf card corner) within 5 pct of asked
##   3 DENSITY   branch count (the tubes in the wood, and the record's count) grows with density 2 < 5 < 9, at least 2x from 2 to 9
##   4 SEASON    autumn ginkgo leaf colours (read back from the MultiMesh): mean hue in the gold band 36-58 deg, 95 pct of leaves in it; summer green, spring lighter green, red red
##   5 HEDGE     straight 12 m and bent 8 + 6 m: the body mesh spans the path +-1 pct (arc length of its vertices projected on the path); height as asked; round-top lower at the sides
##   6 SCATTER   40 copies over 20 x 20 m beside a house and a path: count exact, min spacing held, none in the mask, all in the area; same seed same points; an area too small says "placed k of n"
##   7 WORDS     the 4 sentences from the brief give the right items near the house, the stair, the path (trees left and right of the house; the hedge as long as the path)
##   8 UI        the Nature tool by real clicks: a tree card + a click = ONE undo step and a tree node; a hedge by two clicks = length of the clicks +-1 pct; typing a sentence in Words + Enter = ONE undo step; Undo takes each back
##   9 AGENT     agent_tools "nature": add / words / measure / remove
##  10 SAVE      the record written to a file, read back = the same record and the same mesh; the scene file holds the nature list
##  11 FPS       a 30 x 30 m courtyard (6 trees, 40 m of hedge, grass, a house) at 1280 x 720 draws at >= 30 fps (measured over 3 s of frames)
## Shots: C:/Temp/claude/s225/ (sheet_<species>.png: four seasons, hedges.png, grass.png, courtyard.png)
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/s225"
const DIRT := "user://s225_test"
var bld: BuildUI


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ev_mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func ev_move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	root.push_input(e, true)
	await process_frame


func click_at(p: Vector2) -> void:
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func click_ctl(c: Control) -> void:
	await click_at(c.get_global_rect().get_center())


func key(k: Key, uni := 0) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.unicode = uni
		e.pressed = down
		root.push_input(e, true)
		await process_frame


func type_text(s: String) -> void:
	for i in s.length():
		var c := s.substr(i, 1)
		var k: Key = KEY_SPACE
		if c == ".":
			k = KEY_PERIOD
		elif c == ",":
			k = KEY_COMMA
		elif c != " ":
			k = c.to_upper().unicode_at(0) as Key
		await key(k, c.unicode_at(0))
	await idle(2)


func shot(nm: String) -> void:
	await idle(4)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func to_house() -> void:
	await click_ctl(m.bld.part.reopen_btn)
	await idle(6)
	await click_ctl(m.build_choose.btns["house"]["expert"])
	m.bld.reset_view()
	await idle(10)


# ---------------------------------------------------------------- measuring the MADE nodes

## [min, max] of a tree node's AABB: wood mesh + every leaf card corner (read back from the MultiMesh)
func node_box(n: Node3D) -> AABB:
	var bb := AABB()
	var first := true
	var wood := n.get_node_or_null("wood") as MeshInstance3D
	if wood != null and wood.mesh != null and wood.mesh.get_surface_count() > 0:
		bb = wood.mesh.get_aabb()
		first = false
	var lv := n.get_node_or_null("leaves") as MultiMeshInstance3D
	if lv != null:
		var mm := lv.multimesh
		for i in mm.instance_count:
			var xf := mm.get_instance_transform(i)
			for c in [Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(-0.5, 1, 0), Vector3(0.5, 1, 0)]:
				var q: Vector3 = xf * c
				if first:
					bb = AABB(q, Vector3.ZERO)
					first = false
				else:
					bb = bb.expand(q)
	return bb


func wood_verts(n: Node3D) -> PackedVector3Array:
	var wood := n.get_node_or_null("wood") as MeshInstance3D
	return wood.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]


func leaf_cols(n: Node3D) -> PackedColorArray:
	var out := PackedColorArray()
	var lv := n.get_node_or_null("leaves") as MultiMeshInstance3D
	if lv != null:
		for i in lv.multimesh.instance_count:
			out.append(lv.multimesh.get_instance_color(i))
	return out


func leaf_hash(n: Node3D) -> int:
	var lv := n.get_node_or_null("leaves") as MultiMeshInstance3D
	if lv == null:
		return 0
	return hash(lv.multimesh.buffer)


func tree_of(sp: String, h: float, crown: float, season: String, dens: int, sd: int) -> Node3D:
	return NatureView.tree_node({"kind": "tree", "species": sp, "height": h, "crown": crown, "season": season, "density": dens, "seed": sd, "x": 0.0, "z": 0.0})


func hue_deg(c: Color) -> float:
	return c.h * 360.0


## the length a hedge/path body spans along its path: each vertex projected on the polyline, arc parameter, max - min
func span_along(verts: PackedVector3Array, path: Array) -> float:
	var segs := []
	var tot := 0.0
	for i in range(1, path.size()):
		var a := Vector2(path[i - 1][0], path[i - 1][1])
		var b := Vector2(path[i][0], path[i][1])
		segs.append([a, b, tot])
		tot += a.distance_to(b)
	var lo := INF
	var hi := -INF
	for v in verts:
		var p := Vector2(v.x, v.z)
		var best := INF
		var arc := 0.0
		for s in segs:
			var cp := Geometry2D.get_closest_point_to_segment(p, s[0], s[1])
			var d := cp.distance_to(p)
			if d < best - 1e-9:
				best = d
				arc = float(s[2]) + (s[0] as Vector2).distance_to(cp)
		lo = minf(lo, arc)
		hi = maxf(hi, arc)
	return hi - lo


func rooms_rect_hit(b: Dictionary, x: float, z: float) -> bool:
	for r in b["rooms"]:
		if x >= float(r["x"]) and x <= float(r["x"]) + float(r["w"]) and z >= float(r["z"]) and z <= float(r["z"]) + float(r["d"]):
			return true
	return false


func near_path(path: Array, w: float, x: float, z: float) -> bool:
	for i in range(1, path.size()):
		var cp := Geometry2D.get_closest_point_to_segment(Vector2(x, z), Vector2(path[i - 1][0], path[i - 1][1]), Vector2(path[i][0], path[i][1]))
		if cp.distance_to(Vector2(x, z)) <= w * 0.5:
			return true
	return false


func _init() -> void:
	# ---------------------------------------------------------------- 1 SEED
	var ta := tree_of("oak", 6.0, 5.0, "summer", 5, 3)
	var tb := tree_of("oak", 6.0, 5.0, "summer", 5, 3)
	var tc := tree_of("oak", 6.0, 5.0, "summer", 5, 4)
	ok(wood_verts(ta) == wood_verts(tb) and leaf_hash(ta) == leaf_hash(tb) and wood_verts(ta).size() > 500, "1 same seed: the same wood (%d vertices, every one equal) and the same %d leaves" % [wood_verts(ta).size(), (ta.get_node("leaves") as MultiMeshInstance3D).multimesh.instance_count])
	ok(wood_verts(ta) != wood_verts(tc) and leaf_hash(ta) != leaf_hash(tc), "1 another seed: another wood and other leaves")
	var hp := {"kind": "hedge", "path": [[0, 0], [8, 0]], "height": 0.8, "seed": 5}
	var ha := NatureView.hedge_node(hp)
	var hb := NatureView.hedge_node(hp)
	var hc := NatureView.hedge_node(Nature.clean(hp).merged({"seed": 6}, true))
	var hv := func(n: Node3D) -> PackedVector3Array: return (n.get_node("body") as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	ok(hv.call(ha) == hv.call(hb) and hv.call(ha) != hv.call(hc), "1 a hedge: same seed same body, another seed another body")
	for n in [ta, tb, tc, ha, hb, hc]:
		n.free()
	# ---------------------------------------------------------------- 2 SIZE
	var overhang := 0.0
	var cnt := 0
	for sp in ["ginkgo", "oak", "pine", "palm", "birch", "bare"]:
		for hh in [4.0, 9.0]:
			var cw: float = hh * 0.55
			var n := tree_of(sp, hh, cw, "summer", 5, 11)
			var bb := node_box(n)
			var eh: float = absf(bb.end.y - hh) / hh
			var ew: float = absf(maxf(bb.size.x, bb.size.z) - cw) / cw
			overhang = maxf(overhang, maxf(eh, ew))
			cnt += 1
			if eh > 0.05 or ew > 0.05:
				print("     %s %.1f: height %.3f crown %.3f (asked %.1f / %.2f)" % [sp, hh, bb.end.y, maxf(bb.size.x, bb.size.z), hh, cw])
			n.free()
	ok(overhang <= 0.05, "2 %d trees (6 species x 2 heights): height and crown width within 5 pct of asked, overhang %.2f pct" % [cnt, overhang * 100.0])
	var tk := tree_of("oak", 8.0, 0.0, "summer", 5, 2)
	var tk2 := NatureView.tree_node({"kind": "tree", "species": "oak", "height": 8.0, "trunk": 0.6, "seed": 2})
	var rad := func(n: Node3D) -> float:
		var vs := wood_verts(n)
		var lo := 1e9
		var hi := -1e9
		for v in vs:
			if v.y < 0.02:
				lo = minf(lo, v.x)
				hi = maxf(hi, v.x)
		return hi - lo
	ok(absf(rad.call(tk2) - 0.6) < 0.12 and rad.call(tk2) > rad.call(tk) * 1.2, "2 trunk thickness asked 0.6 m: base is %.2f m across (default tree %.2f m)" % [rad.call(tk2), rad.call(tk)])
	tk.free()
	tk2.free()
	# ---------------------------------------------------------------- 3 DENSITY
	var br := []
	var vc := []
	for d in [2, 5, 9]:
		var n := tree_of("oak", 6.0, 5.0, "summer", d, 7)
		br.append(int((n.get_meta("tree") as Dictionary)["branches"]))
		vc.append(wood_verts(n).size())
		n.free()
	ok(br[0] < br[1] and br[1] < br[2] and br[2] >= br[0] * 2, "3 branches by density 2 / 5 / 9: %s (the record's count), wood vertices %s" % [str(br), str(vc)])
	ok(vc[0] < vc[1] and vc[1] < vc[2], "3 the wood in the node grows with density too")
	# ---------------------------------------------------------------- 4 SEASON
	var hues := {}
	for se in ["spring", "summer", "autumn", "red"]:
		var n := tree_of("ginkgo", 6.0, 3.0, se, 5, 5)
		var cs := leaf_cols(n)
		var inband := 0
		for c in cs:
			var hd := hue_deg(c)
			if (se == "autumn" and hd >= 36.0 and hd <= 58.0) or (se == "summer" and hd >= 70.0 and hd <= 130.0) or (se == "spring" and hd >= 65.0 and hd <= 110.0) or (se == "red" and (hd <= 15.0 or hd >= 350.0)):
				inband += 1
		hues[se] = [hue_deg(Color.from_hsv(Nature.mean_hue(cs), 1, 1)), float(inband) / float(cs.size())]
		n.free()
	ok(hues["autumn"][0] >= 36.0 and hues["autumn"][0] <= 58.0 and hues["autumn"][1] >= 0.95, "4 autumn ginkgo: mean leaf hue %.1f deg (gold band 36-58), %.0f pct of leaves in it" % [hues["autumn"][0], hues["autumn"][1] * 100.0])
	ok(hues["summer"][1] >= 0.95 and hues["spring"][1] >= 0.95 and hues["red"][1] >= 0.95, "4 summer %.0f deg, spring %.0f deg, red %.0f deg: each 95 pct inside its own band" % [hues["summer"][0], hues["spring"][0], hues["red"][0]])
	var tw := NatureView.tree_node({"kind": "tree", "species": "oak", "height": 6.0, "season": "winter", "seed": 1})
	ok(tw.get_node_or_null("leaves") == null and wood_verts(tw).size() > 300, "4 winter: bare branches, no leaves")
	tw.free()
	# ---------------------------------------------------------------- 5 HEDGE
	var hs := NatureView.hedge_node({"kind": "hedge", "path": [[0, 0], [12, 0]], "height": 0.8, "width": 0.6, "seed": 1})
	var hv1 := hv.call(hs) as PackedVector3Array
	var sp1 := span_along(hv1, [[0, 0], [12, 0]])
	var top := 0.0
	for v in hv1:
		top = maxf(top, v.y)
	ok(absf(sp1 - 12.0) / 12.0 <= 0.01, "5 straight hedge 12 m: the body spans %.3f m" % sp1)
	ok(top >= 0.76 and top <= 0.9, "5 hedge height asked 0.8 m: the body reaches %.3f m" % top)
	var lpath := [[0, 0], [8, 0], [8, 6]]
	var hl := NatureView.hedge_node({"kind": "hedge", "path": lpath, "height": 1.0, "seed": 2})
	var sp2 := span_along(hv.call(hl), lpath)
	ok(absf(sp2 - 14.0) / 14.0 <= 0.01, "5 bent hedge 8 + 6 m: the body spans %.3f m of the 14 m path" % sp2)
	var hr := NatureView.hedge_node({"kind": "hedge", "path": [[0, 0], [12, 0]], "height": 1.0, "width": 1.0, "shape": "round", "seed": 2})
	var side_y := 0.0
	var mid_y := 0.0
	for v in hv.call(hr):
		if absf(v.x - 6.0) < 0.2:
			if absf(v.z) >= 0.40 and absf(v.z) <= 0.50:
				side_y = maxf(side_y, v.y)
			if absf(v.z) < 0.08:
				mid_y = maxf(mid_y, v.y)
	ok(mid_y >= 0.95 and side_y <= 0.85 and side_y > 0.4, "5 round-top hedge 1.0 m x 1.0 m: the middle reaches %.2f m, 0.45 m out from it only %.2f m (the crown curves over)" % [mid_y, side_y])
	hs.free()
	hl.free()
	hr.free()
	# ---------------------------------------------------------------- 6 SCATTER
	var house := Building.make("t")
	house["rooms"].append({"id": "r1", "x": 8.0, "z": 8.0, "w": 6.0, "d": 4.0, "yaw": 0.0, "height": "wall_height", "thickness": "wall_thickness", "floor": true})
	var pth := [[2.0, 10.0], [18.0, 10.0]]
	Nature.add(house, {"kind": "path", "path": pth, "width": 1.6})
	var sc := {"kind": "scatter", "of": "shrub", "n": 40, "spacing": 1.5, "jitter": 0.6, "size": 0.8, "seed": 9, "area": {"shape": "rect", "x": 0.0, "z": 0.0, "w": 20.0, "d": 20.0}}
	var sn := NatureView.scatter_node(Nature.clean(sc), house)
	var pts: Array = []
	for c in sn.get_children():
		pts.append(Vector2(c.position.x, c.position.z))
	var mind := 1e9
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			mind = minf(mind, (pts[i] as Vector2).distance_to(pts[j]))
	var in_mask := 0
	var out_area := 0
	for p in pts:
		if rooms_rect_hit(house, p.x, p.y) or near_path(pth, 1.6, p.x, p.y):
			in_mask += 1
		if p.x < 0.0 or p.x > 20.0 or p.y < 0.0 or p.y > 20.0:
			out_area += 1
	ok(pts.size() == 40, "6 scatter: %d shrub nodes stand, 40 asked (count exact)" % pts.size())
	ok(mind >= 1.5 - 1e-6, "6 scatter: the closest two copies are %.3f m apart (min spacing 1.5 m)" % mind)
	ok(in_mask == 0 and out_area == 0, "6 scatter: %d copies inside the house or on the path, %d outside the area" % [in_mask, out_area])
	var sn2 := NatureView.scatter_node(Nature.clean(sc), house)
	var same := sn2.get_child_count() == sn.get_child_count()
	for i in sn.get_child_count():
		same = same and sn.get_child(i).position == sn2.get_child(i).position
	var sn3 := NatureView.scatter_node(Nature.clean(sc.merged({"seed": 10}, true)), house)
	var diff := false
	for i in mini(sn.get_child_count(), sn3.get_child_count()):
		diff = diff or sn.get_child(i).position != sn3.get_child(i).position
	ok(same and diff, "6 scatter: same seed = the same places, another seed = other places")
	var tiny := NatureView.scatter_node(Nature.clean({"kind": "scatter", "of": "rock", "n": 500, "spacing": 3.0, "size": 0.5, "seed": 1, "area": {"shape": "rect", "x": 0.0, "z": 0.0, "w": 10.0, "d": 10.0}}), {})
	var tm: Dictionary = tiny.get_meta("scatter")
	ok(int(tm["placed"]) < 500 and int(tm["placed"]) > 3 and String(tm["why"]).begins_with("placed") and tiny.get_child_count() == int(tm["placed"]), "6 an area too small for 500 at 3 m: says '%s'" % tm["why"])
	var sl := NatureView.scatter_node(Nature.clean({"kind": "scatter", "of": "rock", "n": 20, "spacing": 1.0, "size": 0.4, "seed": 3, "area": {"shape": "line", "path": [[0, 0], [30, 0]], "width": 4.0}}), {})
	var line_ok := sl.get_child_count() == 20
	for c in sl.get_children():
		line_ok = line_ok and c.position.x >= -0.01 and c.position.x <= 30.01 and absf(c.position.z) <= 2.01
	ok(line_ok, "6 scatter along a 30 m line: 20 rocks, all within 2 m of the line")
	for n in [sn, sn2, sn3, tiny, sl]:
		n.free()
	# ---------------------------------------------------------------- 7 WORDS (parse)
	var wh := Building.make("w")
	wh["rooms"].append({"id": "r1", "x": 0.0, "z": 0.0, "w": 8.0, "d": 6.0, "yaw": 0.0, "height": "wall_height", "thickness": "wall_thickness", "floor": true})
	Building.add_piece(wh, "stairs", 6.0, 3.0, 0.0, 0)
	var r1 := NatureWords.parse("2 golden ginkgo trees 6 m tall left and right", wh)
	var its: Array = r1["items"]
	ok(bool(r1["ok"]) and its.size() == 2 and its[0]["species"] == "ginkgo" and its[0]["season"] == "autumn" and absf(float(its[0]["height"]) - 6.0) < 1e-6
			and ((float(its[0]["x"]) < 0.0 and float(its[1]["x"]) > 8.0) or (float(its[1]["x"]) < 0.0 and float(its[0]["x"]) > 8.0)), "7 '2 golden ginkgo trees 6 m tall left and right': 2 gold ginkgos 6 m, one each side of the 8 m house (x %.1f and %.1f)" % [float(its[0]["x"]), float(its[1]["x"])])
	var wp := NatureWords.parse("a path 10 m long, a box hedge 0.8 m high along the path", wh)
	var pitem: Dictionary = {}
	var hitem: Dictionary = {}
	for it in wp["items"]:
		if it["kind"] == "path":
			pitem = it
		if it["kind"] == "hedge":
			hitem = it
	var plen := Nature.path_length(pitem["path"]) if not pitem.is_empty() else 0.0
	var hlen := Nature.path_length(hitem["path"]) if not hitem.is_empty() else -1.0
	ok(not hitem.is_empty() and absf(plen - 10.0) < 0.01 and absf(hlen - plen) / plen <= 0.01 and absf(float(hitem["height"]) - 0.8) < 1e-6 and hitem["shape"] == "box", "7 'a path 10 m long, a box hedge 0.8 m high along the path': path %.2f m, hedge %.2f m, 0.8 m high" % [plen, hlen])
	var rs := NatureWords.parse("round shrubs by the stair", wh)
	var near_st: bool = rs["ok"] and rs["items"].size() == 2
	if near_st:
		for it in rs["items"]:
			near_st = near_st and it["kind"] == "shrub" and it["shape"] == "round" and Vector2(float(it["x"]) - 6.0, float(it["z"]) - 3.0).length() < 2.5
	ok(near_st, "7 'round shrubs by the stair': 2 round shrubs within 2.5 m of the stairs at (6, 3)")
	var rg := NatureWords.parse("grass", wh)
	var gi: Dictionary = rg["items"][0] if rg["ok"] else {}
	ok(rg["ok"] and gi["kind"] == "grass" and float(gi["x"]) < 0.0 and float(gi["x"]) + float(gi["w"]) > 8.0 and float(gi["z"]) + float(gi["d"]) > 6.0, "7 'grass': a lawn around the house (%.0f x %.0f m)" % [float(gi.get("w", 0)), float(gi.get("d", 0))])
	var rbad := NatureWords.parse("make it sparkle", wh)
	ok(not rbad["ok"] and (rbad["ignored"] as Array).has("sparkle"), "7 a sentence with no nature in it is refused and the unknown word is listed")
	var rsc := NatureWords.parse("scatter 12 rocks over 20 x 20 m", wh)
	ok(rsc["ok"] and rsc["items"][0]["kind"] == "scatter" and rsc["items"][0]["n"] == 12 and absf(float(rsc["items"][0]["area"]["w"]) - 20.0) < 1e-6, "7 'scatter 12 rocks over 20 x 20 m': 12 rocks over a 20 x 20 m area")
	# ---------------------------------------------------------------- the app
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	var ss: StartScreen = m.start_screen
	bld = m.bld
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	await to_house()
	# a house to plant around: 8 x 6 m at the origin
	var r0 := BuildWords.parse("a house 8 x 6 m with a door and 4 windows", {})
	m._push_undo()
	m.S.building = BuildWords.make_building_full(r0["plan"], "Garden")["b"]
	bld.sync()
	bld._frame_house()
	await idle(6)
	# ---------------------------------------------------------------- 8 UI
	var nb: Button = m.ui_ribbon["BUILD"].find_child("build_tool_nature", true, false)
	ok(nb != null and nb.visible and nb.get_global_rect().end.x <= 1280.0 and nb.icon != null, "8 a Nature tool on the BUILD ribbon, on screen (right edge %.0f of 1280)" % (nb.get_global_rect().end.x if nb != null else -1.0))
	await click_ctl(nb)
	await idle(3)
	var nui: NatureUI = bld.nature_ui
	ok(bld.tool == "Nature" and nui.panel.visible and nui.panel.get_global_rect().end.x < 330.0 and nui.panel.get_global_rect().end.y <= 720.0, "8 the Nature picker opens on the left, inside the window (%s)" % str(nui.panel.get_global_rect()))
	var n_undo: int = m.undo.size()
	var n_items: int = (m.S.building.get("nature", []) as Array).size()
	await click_ctl(nui.card_btns["oak"])
	await click_ctl(nui.season_btns["autumn"])
	var gp: Vector2 = m.cam.unproject_position(Vector3(-4.0, 0, -1.0))
	await click_at(gp)
	var items: Array = m.S.building.get("nature", [])
	ok(m.undo.size() == n_undo + 1 and items.size() == n_items + 1 and items[-1]["kind"] == "tree" and items[-1]["species"] == "oak" and items[-1]["season"] == "autumn" and absf(float(items[-1]["x"]) + 4.0) < 0.6, "8 oak card + season + a click = ONE undo step, an autumn oak at x %.1f z %.1f" % [float(items[-1]["x"]), float(items[-1]["z"])])
	ok(bld.nature.get_child_count() == items.size() and bld.nature.get_child(items.size() - 1).get_node_or_null("leaves") != null, "8 the tree is drawn: a node with wood and %d leaves" % (bld.nature.get_child(items.size() - 1).get_node("leaves") as MultiMeshInstance3D).multimesh.instance_count)
	await click_ctl(nui.card_btns["hedge"])
	var a3 := Vector3(-6.0, 0, 9.0)
	var b3 := Vector3(6.0, 0, 9.0)
	n_undo = m.undo.size()
	await click_at(m.cam.unproject_position(a3))
	await click_at(m.cam.unproject_position(b3))
	items = m.S.building["nature"]
	var hh2: Dictionary = items[-1]
	var clen := Nature.path_length(hh2["path"]) if hh2["kind"] == "hedge" else -1.0
	var asked := Vector2(float(hh2["path"][0][0]) - float(hh2["path"][1][0]), float(hh2["path"][0][1]) - float(hh2["path"][1][1])).length() if hh2["kind"] == "hedge" else 1.0
	ok(m.undo.size() == n_undo + 1 and hh2["kind"] == "hedge" and clen > 8.0 and absf(clen - asked) / asked <= 0.01, "8 hedge by two clicks = ONE undo step, %.2f m long between its end points" % clen)
	var hn := bld.nature.get_child(items.size() - 1)
	ok(absf(span_along((hn.get_node("body") as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], hh2["path"]) - clen) / clen <= 0.01, "8 and the drawn hedge body spans it")
	await shot("ui_tool")
	m._undo()
	await idle(3)
	ok((m.S.building.get("nature", []) as Array).size() == items.size() - 1 and bld.nature.get_child_count() == items.size() - 1, "8 Undo takes the hedge back (record and drawn)")
	var wb: Button = m.ui_ribbon["BUILD"].find_child("build_tool_words", true, false)
	await click_ctl(wb)
	await idle(3)
	n_undo = m.undo.size()
	n_items = (m.S.building["nature"] as Array).size()
	await click_ctl(bld.words.edit)
	await type_text("2 golden ginkgo trees 6 m tall left and right")
	await key(KEY_ENTER)
	await idle(4)
	items = m.S.building["nature"]
	ok(m.undo.size() == n_undo + 1 and items.size() == n_items + 2 and items[-1]["species"] == "ginkgo" and items[-2]["species"] == "ginkgo", "8 typing the sentence + Enter in Words = ONE undo step, 2 ginkgos planted (%d items)" % items.size())
	await shot("words")
	# ---------------------------------------------------------------- 9 AGENT
	var AT := AgentTools.new(m)
	var ra: Dictionary = await AT.request(1, "nature", {"op": "add", "item": {"kind": "shrub", "x": 3.0, "z": -3.0, "size": 1.5, "seed": 4}})
	var rm: Dictionary = await AT.request(2, "nature", {"op": "measure"})
	var ml: Array = rm["result"]["measures"] if rm.has("result") else []
	var found_tree := false
	for e in ml:
		if e["kind"] == "tree" and absf(float(e["height"]) - 6.0) / 6.0 <= 0.05 and int(e["branches"]) > 20:
			found_tree = true
	ok(ra.has("result") and ra["result"]["ok"] and found_tree, "9 agent nature add + measure: a 6 m ginkgo measured %s" % str(ml.size()))
	var rw: Dictionary = await AT.request(3, "nature", {"op": "words", "text": "a box hedge 0.8 m high along the front"})
	var rr: Dictionary = await AT.request(4, "nature", {"op": "remove", "id": String(ra["result"]["id"])})
	var rbad2: Dictionary = await AT.request(5, "nature", {"op": "add", "item": {"kind": "spaceship"}})
	ok(rw.has("result") and rr.has("result") and rbad2.has("error"), "9 agent words, remove, and a bad item refused with a message")
	# ---------------------------------------------------------------- 10 SAVE
	var rec: Dictionary = m.S.building
	var f1 := Building.to_file(rec)
	var path := ProjectSettings.globalize_path(DIRT + "/save.json")
	var fa := FileAccess.open(path, FileAccess.WRITE)
	fa.store_string(JSON.stringify(f1))
	fa.close()
	var back: Dictionary = Building.from_file(JSON.parse_string(FileAccess.get_file_as_string(path)))
	ok(JSON.stringify(Building.to_file(back)) == JSON.stringify(f1) and (back["nature"] as Array).size() == (rec["nature"] as Array).size() and (back["nature"] as Array).size() >= 3, "10 the record written to a file and read back is the same (%d nature items)" % (back["nature"] as Array).size())
	var t1 := NatureView.tree_node(rec["nature"][0])
	var t2 := NatureView.tree_node(back["nature"][0])
	ok(wood_verts(t1) == wood_verts(t2) and leaf_hash(t1) == leaf_hash(t2), "10 and the tree made from the file is the same tree, vertex for vertex")
	t1.free()
	t2.free()
	var sd: Dictionary = m.S.to_dict(m.B, false)
	ok(sd.has("building") and sd["building"].has("nature") and (sd["building"]["nature"] as Array).size() == (rec["nature"] as Array).size(), "10 the scene file holds the nature list")
	var S2 := Scene.new()
	S2.from_dict(JSON.parse_string(JSON.stringify(sd)))
	ok((S2.building.get("nature", []) as Array).size() == (rec["nature"] as Array).size(), "10 a scene read back has the same %d items" % (S2.building.get("nature", []) as Array).size())
	var mir := Building.mirror_file(f1)
	ok(Building.mirror_file(mir) == f1 or JSON.stringify(Building.to_file(Building.from_file(Building.mirror_file(mir)))) == JSON.stringify(f1), "10 mirrored twice, the nature list is the original")
	# ---------------------------------------------------------------- 12 EASY PARTS > NATURE, and the look of the hedge and the pine
	var pup = bld.part
	m.S.part = {}
	await click_ctl(pup.part_btn)
	await click_ctl(pup.easy_open_btn)
	await idle(4)
	var epn = pup.ep
	var pbtn := root.find_child("easypart_chip_parts", true, false) as Button
	await click_ctl(pbtn)
	await idle(3)
	await open_group_of(root.find_child("easypart_nature_chip", true, false))   # 239: Nature is in the "Nature and decor" group
	var nchip := root.find_child("easypart_nature_chip", true, false) as Button
	var win := Rect2(0, 0, 1280, 720)
	ok(nchip != null and nchip.is_visible_in_tree() and win.encloses(nchip.get_global_rect()), "12 Easy Parts: a Nature chip on the Parts library page, inside 1280 x 720 (%s)" % str(nchip.get_global_rect() if nchip != null else Rect2()))
	var scr_vp := (epn.panel.find_child("easypart_panel_scroll", true, false) as Control).get_global_rect()
	var m416 := root.find_child("easypart_screw_M4_16", true, false) as Control
	ok(m416 != null and scr_vp.has_point(m416.get_global_rect().get_center()), "12 the Nature chip adds no row: the M4 x 16 screw chip's middle (%s) is still inside the scroll area (%s), so a real click reaches it" % [str(m416.get_global_rect().get_center()) if m416 != null else "-", str(scr_vp)])
	var lib_box := root.find_child("easypart_library", true, false) as Control
	var lib_b0 := lib_box.get_global_rect().end.y if lib_box != null else -1.0
	var cat_n := (lib_box.find_children("easypart_lib_*", "Button", true, false) as Array).size() if lib_box != null else -1
	await click_ctl(nchip)
	await idle(4)
	var nbox := root.find_child("easypart_nature_box", true, false) as Control
	var soon := root.find_child("easypart_lib_soon", true, false) as Label
	var lib_b1 := lib_box.get_global_rect().end.y if lib_box != null else -1.0
	ok(nbox != null and nbox.is_visible_in_tree() and (soon == null or not soon.is_visible_in_tree()) and epn.screw_box != null and not epn.screw_box.is_visible_in_tree(), "12 the Nature chip opens the Nature page (no 'coming soon', no screw grid)")
	await idle(8)
	var scr_rect := (epn.panel.find_child("easypart_panel_scroll", true, false) as Control).get_global_rect()
	var all_in := nbox != null
	var ovh := 0.0
	for kk in ["ginkgo", "oak", "pine", "palm", "birch", "bare", "hedge", "shrub", "grass", "flowers", "path"]:
		var bt0 := root.find_child("easypart_nature_" + kk, true, false) as Control
		if bt0 == null or not scr_rect.encloses(bt0.get_global_rect()) or not win.encloses(bt0.get_global_rect()):
			all_in = false
			ovh = maxf(ovh, bt0.get_global_rect().end.y - scr_rect.end.y if bt0 != null else 9999.0)
	ok(all_in and cat_n >= 16, "12 the page opens scrolled into view: all 11 chips inside the panel's scroll area and the 1280 x 720 window (ovh ovh %.0f px), the library keeps its %d category chips" % [ovh, cat_n])
	await shot("easy_nature")
	var n_before: int = (m.S.building.get("nature", []) as Array).size()
	var u_before: int = m.undo.size()
	var res_kinds := {}
	for kk in ["ginkgo", "hedge", "path", "grass", "flowers", "shrub", "oak", "pine", "palm", "birch", "bare"]:
		var bt := root.find_child("easypart_nature_" + kk, true, false) as Button
		var nb0: int = (m.S.building.get("nature", []) as Array).size()
		var ub0: int = m.undo.size()
		if bt != null:
			await click_ctl(bt)
		var itl: Array = m.S.building.get("nature", [])
		res_kinds[kk] = [itl.size() - nb0, m.undo.size() - ub0, String(itl[-1]["kind"]) if itl.size() > nb0 else "", itl[-1] if itl.size() > nb0 else {}]
	var all_one := true
	for kk in res_kinds:
		var rk: Array = res_kinds[kk]
		if int(rk[1]) != 1 or int(rk[0]) < 1:
			all_one = false
	ok(all_one, "12 each of the 11 Nature chips adds its item in ONE undo step (%s)" % str(res_kinds.keys().map(func(k): return "%s +%d/%d" % [k, int(res_kinds[k][0]), int(res_kinds[k][1])])))
	ok(res_kinds["ginkgo"][2] == "tree" and res_kinds["hedge"][2] == "hedge" and res_kinds["path"][2] == "path" and res_kinds["grass"][2] == "grass" and res_kinds["flowers"][2] == "flowers" and res_kinds["shrub"][2] == "shrub", "12 and the kinds are tree, hedge, path, grass, flowers, shrub")
	await click_ctl(root.find_child("easypart_nature_season_autumn", true, false) as Button)
	await click_ctl(root.find_child("easypart_nature_ginkgo", true, false) as Button)
	var last_t: Dictionary = (m.S.building["nature"] as Array)[-1]
	ok(String(last_t.get("season", "")) == "autumn" and String(last_t.get("species", "")) == "ginkgo", "12 the Gold leaf button then Ginkgo plants an autumn ginkgo (season %s)" % str(last_t.get("season", "")))
	var n_mid: int = (m.S.building["nature"] as Array).size()
	m._undo()
	ok((m.S.building["nature"] as Array).size() == n_mid - 1, "12 Undo takes the last planting back (%d -> %d items)" % [n_mid, (m.S.building["nature"] as Array).size()])
	pup.set_on(false)
	await idle(4)
	# the hedge reads as a clipped hedge, not a tube: a flat top, lumpy sides, many leaves; the pine is a full cone of tiers
	var hz := NatureView.hedge_node({"kind": "hedge", "path": [[0, 0], [12, 0]], "height": 0.8, "width": 0.6, "seed": 3})
	var hzv: PackedVector3Array = (hz.get_node("body") as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var top_ys := PackedFloat32Array()
	var side_zs := PackedFloat32Array()
	for v in hzv:
		if v.y > 0.7:
			top_ys.append(v.y)
		if v.z > 0.2 and v.y > 0.15 and v.y < 0.6 and v.x > 0.5 and v.x < 11.5:
			side_zs.append(v.z)
	var sdv := func(a: PackedFloat32Array) -> float:
		if a.is_empty():
			return -1.0
		var mu := 0.0
		for x in a:
			mu += x
		mu /= a.size()
		var q := 0.0
		for x in a:
			q += (x - mu) * (x - mu)
		return sqrt(q / a.size())
	var top_sd: float = sdv.call(top_ys)
	var side_sd: float = sdv.call(side_zs)
	var hl_n := (hz.get_node("leaves") as MultiMeshInstance3D).multimesh.instance_count
	ok(top_sd >= 0.005 and top_sd <= 0.05 and side_sd >= 0.015 and hl_n >= 8000, "12 a 12 m hedge: top flat but textured (height sd %.3f m), sides clipped lumpy (lateral sd %.3f m), %d leaf cards" % [top_sd, side_sd, hl_n])
	hz.free()
	var pn := tree_of("pine", 8.0, 0.0, "summer", 5, 3)
	var pmm := (pn.get_node("leaves") as MultiMeshInstance3D).multimesh
	var bands := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])
	var low_r := 0.0
	for i in pmm.instance_count:
		var o := pmm.get_instance_transform(i).origin
		var b := clampi(int((o.y / 8.0 - 0.15) / 0.1), 0, 7)
		if o.y / 8.0 >= 0.15:
			bands[b] += 1
		if o.y / 8.0 > 0.15 and o.y / 8.0 < 0.35:
			low_r = maxf(low_r, Vector2(o.x, o.z).length())
	var bmin := 1 << 30
	for c in bands:
		bmin = mini(bmin, c)
	ok(pmm.instance_count >= 5000 and bmin >= 150 and low_r >= 1.0, "12 the pine is a full cone: %d leaves, fewest in any of 8 height bands %d (want 150), lower crown reaches %.2f m out" % [pmm.instance_count, bmin, low_r])
	pn.free()
	bld._pick_tool("Floor")   # the shots: no words box over the view
	# ---------------------------------------------------------------- the sheets: every kind in every season
	m.S.building = Building.make("Sheet")
	var kinds := ["ginkgo", "oak", "pine", "palm", "birch", "bare"]
	for sp in kinds:
		m.S.building["nature"] = []
		var seas := ["spring", "summer", "autumn", "red"] if sp != "bare" else ["winter", "winter", "winter", "winter"]
		for i in 4:
			Nature.add(m.S.building, {"kind": "tree", "species": sp, "x": float(i) * 7.0, "z": 0.0, "height": 6.0, "season": seas[i], "density": 6, "seed": 2 + i})
		Nature.add(m.S.building, {"kind": "grass", "x": -5.0, "z": -5.0, "w": 40.0, "d": 14.0, "density": 20.0, "seed": 1})
		bld.sync()
		m._turn_to(0.0, -12.0, 34.0, Vector3(10.5, 3.0, 0.0), false)
		await idle(6)
		await shot("sheet_" + sp)
	# hedges + shrubs
	m.S.building["nature"] = []
	Nature.add(m.S.building, {"kind": "grass", "x": -6.0, "z": -6.0, "w": 24.0, "d": 16.0, "density": 30.0, "seed": 1})
	Nature.add(m.S.building, {"kind": "path", "path": [[0.0, -4.0], [0.0, 8.0]], "width": 1.4})
	Nature.add(m.S.building, {"kind": "hedge", "path": [[-1.6, -4.0], [-1.6, 8.0]], "height": 0.8, "width": 0.6, "seed": 1})
	Nature.add(m.S.building, {"kind": "hedge", "path": [[1.6, -4.0], [1.6, 8.0]], "height": 1.1, "width": 0.8, "shape": "round", "seed": 2})
	Nature.add(m.S.building, {"kind": "shrub", "x": 4.0, "z": 1.0, "size": 1.4, "seed": 3})
	Nature.add(m.S.building, {"kind": "shrub", "x": 6.5, "z": 2.0, "size": 1.2, "shape": "cone", "seed": 4})
	Nature.add(m.S.building, {"kind": "flowers", "x": -6.0, "z": 0.0, "w": 3.0, "d": 3.0, "n": 60, "color": "red", "seed": 5})
	Nature.add(m.S.building, {"kind": "scatter", "of": "rock", "n": 8, "spacing": 0.9, "size": 0.5, "seed": 2, "area": {"shape": "rect", "x": 8.0, "z": 4.0, "w": 6.0, "d": 4.0}})
	bld.sync()
	m._turn_to(25.0, -24.0, 15.0, Vector3(0.0, 0.3, 2.0), false)
	await idle(6)
	await shot("hedges")
	m._turn_to(0.0, -9.0, 7.0, Vector3(0.0, 0.3, 1.0), false)
	await idle(6)
	await shot("grass")
	# ---------------------------------------------------------------- 11 FPS: the courtyard
	var cy := Building.make("Courtyard")
	cy["rooms"].append({"id": "r1", "x": 11.0, "z": 11.0, "w": 8.0, "d": 6.0, "yaw": 0.0, "height": "wall_height", "thickness": "wall_thickness", "floor": true})
	cy["roof"] = {"kind": "gable", "pitch": 25.0, "overhang": "roof_overhang"}
	m.S.building = cy
	Nature.add(cy, {"kind": "grass", "x": 0.0, "z": 0.0, "w": 30.0, "d": 30.0, "density": 30.0, "seed": 1})
	Nature.add(cy, {"kind": "path", "path": [[15.0, 0.0], [15.0, 10.5]], "width": 1.6})
	Nature.add(cy, {"kind": "hedge", "path": [[13.5, 0.5], [13.5, 10.0]], "height": 0.9, "seed": 1})
	Nature.add(cy, {"kind": "hedge", "path": [[16.5, 0.5], [16.5, 10.0]], "height": 0.9, "seed": 2})
	Nature.add(cy, {"kind": "hedge", "path": [[1.0, 1.0], [29.0, 1.0]], "height": 1.2, "shape": "round", "seed": 3})
	Nature.add(cy, {"kind": "hedge", "path": [[1.0, 29.0], [14.0, 29.0]], "height": 1.2, "shape": "round", "seed": 4})
	var hedge_total := 0.0
	for it in cy["nature"]:
		if it["kind"] == "hedge":
			hedge_total += Nature.path_length(it["path"])
	var cts := [["ginkgo", 4.0, 9.0, "autumn"], ["ginkgo", 26.0, 9.0, "autumn"], ["oak", 5.0, 22.0, "summer"], ["pine", 25.0, 22.0, "summer"], ["birch", 8.0, 15.0, "spring"], ["oak", 23.0, 15.0, "red"]]
	for c in cts:
		Nature.add(cy, {"kind": "tree", "species": c[0], "x": c[1], "z": c[2], "height": 7.0, "season": c[3], "density": 5, "seed": int(c[1])})
	Nature.add(cy, {"kind": "shrub", "x": 10.0, "z": 12.0, "size": 1.4, "seed": 2})
	Nature.add(cy, {"kind": "shrub", "x": 20.0, "z": 12.0, "size": 1.4, "seed": 3})
	var t0 := Time.get_ticks_msec()
	bld.sync()
	var build_ms := Time.get_ticks_msec() - t0
	m._turn_to(35.0, -28.0, 36.0, Vector3(15.0, 1.0, 15.0), false)
	await idle(8)
	await shot("courtyard")
	var f0: int = Engine.get_process_frames()
	var tt := Time.get_ticks_msec()
	while Time.get_ticks_msec() - tt < 3000:
		m.yaw += 0.2
		m._cam()
		await process_frame
	var fps := float(Engine.get_process_frames() - f0) / (float(Time.get_ticks_msec() - tt) / 1000.0)
	var blades := 0
	for c in bld.nature.get_children():
		if c.has_meta("blades"):
			blades = int(c.get_meta("blades"))
	ok(fps >= 30.0, "11 courtyard 30 x 30 m: 6 trees, %.0f m of hedge, %d grass blades, a house: %.1f fps at 1280 x 720 (built in %d ms)" % [hedge_total, blades, fps, build_ms])
	ok(hedge_total >= 40.0, "11 the courtyard has %.0f m of hedge (>= 40)" % hedge_total)
	print("s225: %d fail" % fails)
	quit()


## 239 (a28b6389): the library chips sit in groups; a user opens a chip's group tab (a real click) before pressing the chip
func open_group_of(c: Control) -> void:
	if c == null or c.is_visible_in_tree():
		return
	for g in root.find_children("easypart_libgroup_*", "Button", true, false):
		var fl := root.find_child("easypart_libchips_" + (g as Button).text, true, false)
		if fl != null and fl.is_ancestor_of(c):
			await click_ctl(g)
			return
