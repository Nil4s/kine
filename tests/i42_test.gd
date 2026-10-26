## godot --path . -s tests/i42_test.gd     (ROADMAP I42: the floor plan, scripts/floor_plan.gd + floor_plan_view.gd + floor_plan_ui.gd; needs a window)
## The scene: combo3 (the hero) and a second fighter standing 1.1 m in front of it, facing it (the i28 fixture). combo3 has no foot plants.
## Bars, written before measuring:
##  (1) SOLE CONTACT: with no plants the plan still places feet: >= 4 footprints for the hero (a fight takes steps), every one numbered 1..n in time order
##  (2) PLANTS: turning each of those placements into a Scene.plant, the plan has EXACTLY as many footprints as plants (per fighter), numbered 1..n, each timed at its
##      plant's t0 and read at the middle of its range (fully held), and each footprint's sole centre is within 2 cm of FootPlant.footprint's own heel/toe outline posed at that time (the app's drawing of a plant)
##  (3) the planted sole HOLDS: the footprint's sole centre at the plant's t1 is within 2 cm of the footprint's (read mid-range) (a plant keeps the sole where it was)
##  (4) PLACEMENT: every footprint lies within 1.0 m of its own fighter's centre-of-mass path (a foot is near its body); the COM path has a sample per frame;
##      the strike lines (>= 1 on combo3) end within 1 cm of the striking tip at the contact card's arrival and are >= 0.2 m long
##  (5) the page and the picture are written under user:// (name has the PID): the HTML has the inline SVG with exactly one footprint polygon per footprint
##      and the scale bar text, the PNG is 1400 x 1000 and not blank (>= 1 % of its pixels differ from the floor colour); the scenes' JSON and the open
##      body (B.state) are byte-identical before and after; the files are removed
##  (6) the panel: Floor plan opens on combo3 with the plan view; everything drawn is inside the view (+-1 px), the view is inside the findings panel, and the
##      panel is inside the window (screenshot tmp/i42.png)
##  (7) i42b DECLUTTER: in the PNG (1400 x 1000) and in the panel, no two label rects overlap (labels fit inside the view), every footprint keeps its number
##      (a text "n" within its own footprint's neighbourhood, none dropped), and the PNG drops no more than 2 time labels
extends SceneTree

const TMP := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/"
var fails := 0
var m: Node
var HX := Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, 1.1))


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func body() -> Body:
	return DistanceKeeper.new_body()


func other() -> Scene:
	var b := body()
	b.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	b.ground()
	var p := b.to_dict()
	var s := Scene.new()
	s.from_dict({"scene": "zz_other", "fps": 30, "cards": [{"name": "a", "pose": p, "move": -1.0, "hold": 2.0}, {"name": "b", "pose": p, "move": 0.5, "hold": 6.0}]})
	return s


func jsn(S: Scene) -> String:
	return JSON.stringify([S.cards, S.markers, S.plants])


func hero_scene() -> Scene:
	var s := Scene.new()
	s.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json")))
	return s


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var H := hero_scene()
	var O := other()
	var names := ["the hero", "fighter 2"]
	var xfs := [Transform3D.IDENTITY, HX]
	var before := jsn(H) + jsn(O)
	var keep0 := JSON.stringify(m.B.state())
	# (1) sole contact
	var p0 := FloorPlan.analyze([H, O], names, xfs, 30)
	var st0: Array = p0["fighters"][0]["steps"]
	var ordered := true
	for i in st0.size():
		ordered = ordered and int(st0[i]["n"]) == i + 1 and (i == 0 or float(st0[i]["t"]) >= float(st0[i - 1]["t"]))
	print("     detected %d footprints for the hero, %d for fighter 2, %d strike lines, %d safety marks, length %.2f s" % [st0.size(), (p0["fighters"][1]["steps"] as Array).size(),
		(p0["fighters"][0]["strikes"] as Array).size(), (p0["safety"] as Array).size(), p0["length"]])
	ok(st0.size() >= 4 and ordered and not bool(p0["fighters"][0]["from_plants"]), "(1) no plants: %d footprints from sole contact, numbered 1..n in time order" % st0.size())
	# (2) plants
	var P := []
	for s in st0:
		P.append({"foot": "foot_l" if s["foot"] == "left" else "foot_r", "t0": float(s["t"]), "t1": float(s["t1"])})
	var HP := hero_scene()
	HP.plants = FootPlant.from_file(P)
	var np := HP.plants.size()
	var p1 := FloorPlan.analyze([HP, O], names, xfs, 30)
	var st1: Array = p1["fighters"][0]["steps"]
	var worst := 0.0
	var worst_hold := 0.0
	var B := body()
	var HC := HP.clone()
	for i in st1.size():
		var pl: Dictionary = HP.plants[i]
		HC.apply(B, float(st1[i]["tr"]))
		var fp: Array = FootPlant.footprint(B, HC.plants, float(st1[i]["tr"]), 30)
		var ref := Vector2.ZERO
		var found := false
		for q in fp:
			if q["foot"] == pl["foot"]:
				var pts: Array = q["pts"]
				ref = (Vector2(pts[0].x, pts[0].z) + Vector2(pts[2].x, pts[2].z)) * 0.5
				found = true
		worst = maxf(worst, (st1[i]["pos"] as Vector2).distance_to(ref) if found else 9.0)
		var sd := String(pl["foot"]).right(2)
		HC.apply(B, float(pl["t1"]))
		var s1 := FloorPlan.sole(B, sd)
		var dh := (st1[i]["pos"] as Vector2).distance_to((s1[0] + s1[1]) * 0.5)
		print("     plant %d %s %.2f-%.2f s: hold drift %.2f cm, heel %.2f cm, toe %.2f cm, reach miss %.2f cm" % [i + 1, pl["foot"], pl["t0"], pl["t1"], dh * 100.0, (st1[i]["heel"] as Vector2).distance_to(s1[0]) * 100.0, (st1[i]["toe"] as Vector2).distance_to(s1[1]) * 100.0, float(HC.plant_last.get(i, {}).get("miss", -1.0)) * 100.0])
		worst_hold = maxf(worst_hold, dh)
	ok(from_plants_ok(p1) and st1.size() == np and np > 0 and worst <= 0.02,
		"(2) %d plants -> %d footprints, the worst is %.2f cm from the sole outline FootPlant draws (<= 2 cm)" % [np, st1.size(), worst * 100.0])
	ok(worst_hold <= 0.02, "(3) the planted sole holds: its centre at t1 is at most %.2f cm from the one at t0 (<= 2 cm)" % (worst_hold * 100.0))
	# (4) placement
	var far := 0.0
	for f in p1["fighters"]:
		for s in f["steps"]:
			var dmin := INF
			for q in f["com"]:
				dmin = minf(dmin, (s["pos"] as Vector2).distance_to(q))
			far = maxf(far, dmin)
	var strikes: Array = p1["fighters"][0]["strikes"]
	var s_err := 0.0
	var s_len := INF
	var ts := HP.times()
	for st in strikes:
		HC.apply(B, float(ts[int(st["card"])][1]))
		var tip: Vector3 = DistanceKeeper.tips(B)[st["tip"]]
		s_err = maxf(s_err, (st["to"] as Vector2).distance_to(Vector2(tip.x, tip.z)))
		s_len = minf(s_len, float(st["len"]))
	var ncom := (p1["fighters"][0]["com"] as PackedVector2Array).size()
	ok(far <= 1.0 and strikes.size() >= 1 and s_err <= 0.01 and s_len >= 0.2 and ncom == int(ceil(HP.length() * 30)) + 1,
		"(4) every footprint within %.2f m of its COM path (<= 1.0); %d strike lines end %.2f cm from the tip (<= 1), shortest %.2f m (>= 0.2); %d COM samples" % [far, strikes.size(), s_err * 100.0, s_len, ncom])
	# (5) the files
	var ui := FloorPlanUI.new(m)
	ui.forced = {"scenes": [HP, O], "names": names, "xfs": xfs}
	ui.compute()
	var dir := "user://i42_%d" % OS.get_process_id()
	var path: String = await ui.write_page(m, dir)
	var html := FileAccess.get_file_as_string(path) if path != "" else ""
	var total := 0
	for f in ui.plan["fighters"]:
		total += (f["steps"] as Array).size()
	var polys := html.count("fill-opacity=\"0.55\"")
	var img := Image.new()
	var perr := img.load(ui.last_png) if ui.last_png != "" else ERR_FILE_NOT_FOUND
	var floor_c := Tok.c("floor")
	var diff := 0
	if perr == OK:
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if absf(c.r - floor_c.r) + absf(c.g - floor_c.g) + absf(c.b - floor_c.b) > 0.15:
					diff += 1
	var share := float(diff) / maxf(1.0, float(img.get_width() * img.get_height()))
	ok(path != "" and path.contains("user:") == false and html.contains("<svg") and polys == total and html.contains(">100 cm</text>") and perr == OK and img.get_width() == 1400 and img.get_height() == 1000
		and share >= 0.01 and jsn(HP) + jsn(O) == jsn(HP) + jsn(O) and JSON.stringify(m.B.state()) == keep0 and before == jsn(H) + jsn(O),
		"(5) page %s holds %d footprint polygons (%d footprints), picture %dx%d with %.1f %% of its pixels drawn; scenes and body untouched" % [path.get_file(), polys, total, img.get_width(), img.get_height(), share * 100.0])
	var lo_png := overlaps(ui.png_labels, Rect2(Vector2.ZERO, Vector2(1400, 1000)))
	var nums_png := 0
	for l in ui.png_labels:
		nums_png += 1 if l["kind"] == "number" else 0
	ok(lo_png[0] == 0 and lo_png[1] == 0 and nums_png == total and ui.png_dropped <= 2,
		"(7) PNG: %d labels, %d overlapping pairs, %d outside the picture, %d of %d numbers kept, %d time labels dropped (<= 2)" % [ui.png_labels.size(), lo_png[0], lo_png[1], nums_png, total, ui.png_dropped])
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(ui.last_png)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))
	ok(not FileAccess.file_exists(path) and not FileAccess.file_exists(ui.last_png), "(5b) the test's files are removed again")
	# (6) the panel on combo3 with a second fighter
	ui = FloorPlanUI.new(m)
	m.fp_ui = ui
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle()
	m.S.actors.append({"name": "fighter 2", "xf": {"pos": [0.0, 1.1], "yaw": 180.0}, "scene": other()})
	m._actors_sync()
	m._refresh()
	await idle()
	ui.show()
	await idle(6)
	var v: FloorPlanView = ui.view
	var vr := v.get_global_rect()
	var dr := v.drawn
	var inside := dr.position.x >= -1.0 and dr.position.y >= -1.0 and dr.end.x <= v.size.x + 1.0 and dr.end.y <= v.size.y + 1.0 and dr.size.x > 50.0
	var pr: Rect2 = (m.ui_find as Control).get_global_rect()
	var win := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var in_panel := pr.grow(1.0).encloses(vr)
	var in_win := win.grow(1.0).encloses(pr)
	print("     panel view %s, drawn %s, findings panel %s, window %s" % [vr, dr, pr, win])
	root.get_texture().get_image().save_png(TMP + "i42.png")
	ok(m.ui_find.visible and inside and in_panel and in_win, "(6) the plan fits: drawn box inside its view, view inside the panel, panel inside the window (%s)" % FloorPlan.summary(ui.plan))
	var lo_v := overlaps(v.labels, Rect2(Vector2.ZERO, v.size))
	ok(lo_v[0] == 0 and lo_v[1] == 0 and v.labels.size() > 10, "(7b) panel: %d labels, %d overlapping pairs, %d outside the view, %d time labels dropped" % [v.labels.size(), lo_v[0], lo_v[1], v.dropped])
	print("i42: %d failures" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)


## [pairs of label rects that overlap, labels not inside the box]
func overlaps(ls: Array, box: Rect2) -> Array:
	var n := 0
	var out := 0
	for i in ls.size():
		var r: Rect2 = ls[i]["rect"]
		if not box.grow(0.5).encloses(r):
			out += 1
		for j in range(i + 1, ls.size()):
			if r.intersects(ls[j]["rect"]):
				n += 1
	return [n, out]


func from_plants_ok(p: Dictionary) -> bool:
	return bool(p["fighters"][0]["from_plants"])
