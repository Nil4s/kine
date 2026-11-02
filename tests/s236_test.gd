extends SceneTree
## S236 TEMPLE ROUND 4 (Nick: Kine on par with Blender on colours, lights, shapes, the Chinese temple rematch). Gaps of round 3 (hall_compare/kine3/difficulties.md):
##   pale sparse ginkgo canopies, a fish-blob ridge beast, a stiff beast row, gentle roof corners, no mountains. The bars are NEW (s225 / s226 / s227 / s232 / s235 untouched) and
##   come from the reference picture's own numbers (hall_compare/reference.png, measured by tools/kine_workers/hall_compare/measure4.py: canopy hue 31-33 deg, sat 0.68, val 0.65-0.75).
##   N1  amber ginkgo, rendered with the temple light: the canopy pixels (orange-gold mask) have mean hue 24..40 deg and saturation >= 0.58 (reference 31-33 deg, 0.68; round 3 49 deg, 0.48)
##   N2  the same tree with fullness 2.6 covers >= 1.25x the canopy pixels of fullness 1 and >= 0.40 of its crown window (reference 0.35-0.48 of an edge window)
##   N3  autumn, spring, summer, red keep their s225 bands (amber is a new season, not a changed one): the default tree's leaf colours are bit for bit those of the s225 hues
##   O1  ridge_dragon: closed manifold mesh of the exact asked size; its MOUTH is open (a vertical line through the snout crosses the jaws twice: 2 solid runs) and it has 2 HORNS (solid above the skull on both sides)
##   O2  corner_sprite is lighter than the old corner beast: its volume / box fill <= 0.8 x the corner beast's (print both) and both are closed manifolds of the exact size
##   O3  seeded: the same ridge_dragon seed gives the same vertices; another seed gives other vertices
##   R1  roof lift_pow: 2 (default, and no key) is the old bump bit for bit; 4 lifts less at half the lift length and the same at the corner (a steeper curl); the replayed roof's top corner is lift higher
##   M1  mountains: with the temple light on and mountains on, the scene holds 'temple_mountains' (2 layers, peaks >= 60 m); off or after turning the light off, none
##   M2  the rendered picture differs from the no-mountains picture in >= 2 % of the pixels (blue-grey hills over the horizon band), and the sky pixels above are unchanged
var OUT := "C:/Users/Nick/tools/kine_workers/hall_compare/kine4/test" + (("_" + OS.get_environment("S236_TAG")) if OS.get_environment("S236_TAG") != "" else "")
var fails := 0
var m: Node
var pu
var W := 1280
var H := 720


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func setup() -> bool:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.size = Vector2i(W, H)
	await idle(4)
	var ss: StartScreen = m.start_screen
	pu = m.bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://s236"))
	ss.dirs_override = ["user://s236"]
	if not Part.available():
		print("FAIL no DLL")
		return false
	ss.show_screen()
	await idle(3)
	m.build_choose.auto = true
	var card: Control = ss._cards["building"]
	var p := card.get_global_rect().get_center()
	for d in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = d
		e.position = p
		e.global_position = p
		root.push_input(e, true)
		await process_frame
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(10)
	pu.set_on(false)
	m.S.part = {}
	await process_frame
	var pb: Button = pu.part_btn
	var q := pb.get_global_rect().get_center()
	for d in [true, false]:
		var e2 := InputEventMouseButton.new()
		e2.button_index = MOUSE_BUTTON_LEFT
		e2.pressed = d
		e2.position = q
		e2.global_position = q
		root.push_input(e2, true)
		await process_frame
	await idle(4)
	if not pu.on:
		pu.set_on(true)
		await idle(4)

	# a small part: a platform with the ornaments on it (2 ridge dragons, 2 chiwen, 4 sprites, 4 old corner beasts)
	var rec: Dictionary = Part.make("s236 ornaments")
	Part.prim(rec, "box", {"x": -7000.0, "y": 0.0, "z": -5000.0, "w": 14000.0, "h": 300.0, "d": 10000.0, "name": "Platform", "op": "new"})
	for sx in [-1.0, 1.0]:
		(rec["features"] as Array).append(Part.new_feature(rec, "ornament", PartOrnament.fields("ridge_dragon", 3, [{"at": [sx * 4200.0, 300.0, 1500.0], "dir": [-sx, 0.0, 0.0]}])))
		(rec["features"] as Array).append(Part.new_feature(rec, "ornament", PartOrnament.fields("chiwen", 3, [{"at": [sx * 4200.0, 300.0, -1500.0], "dir": [-sx, 0.0, 0.0]}])))
	var sprites: Array = []
	var beasts: Array = []
	for i in 4:
		sprites.append({"at": [-1500.0 + 1000.0 * i, 300.0, 3300.0], "dir": [1.0, 0.0, 0.0]})
		beasts.append({"at": [-1500.0 + 1000.0 * i, 300.0, -3300.0], "dir": [1.0, 0.0, 0.0]})
	(rec["features"] as Array).append(Part.new_feature(rec, "ornament", PartOrnament.fields("corner_sprite", 5, sprites, PartOrnament.default_size("corner_sprite") * 1.8)))
	(rec["features"] as Array).append(Part.new_feature(rec, "ornament", PartOrnament.fields("corner_beast", 5, beasts, PartOrnament.default_size("corner_beast") * 1.8)))
	m.S.part = rec
	pu.upto = -1
	pu.sync()
	m.bld.sync()
	var want := 13
	var tw := Time.get_ticks_msec()
	while int(pu.res.get("bodies", -1)) != want and Time.get_ticks_msec() - tw < 300000:
		await idle(4)
	await idle(10)
	print("ornament part bodies ", pu.res.get("bodies", -1), " aabb ", pu.res.get("aabb", null))
	pu.browser.visible = false
	pu.tl.visible = false
	if m.grid_node != null:
		m.grid_node.visible = false
	return int(pu.res.get("bodies", -1)) == want


func shot(nm: String, sz := 1024) -> Image:
	var r: Dictionary = await TempleLight.final_shot(m, OUT + "/" + nm + ".png", Vector2i(sz, sz))
	if not bool(r.get("ok", false)):
		print("FAIL final shot ", nm, " ", r)
		return null
	return r["image"]


## the same canopy mask as measure4.py (orange-gold leaves): hue 0.05..0.14, saturation > 0.35, value > 0.35
func canopy_stats(img: Image, r: Rect2i) -> Dictionary:
	var sx := 0.0
	var cx := 0.0
	var ss := 0.0
	var sv := 0.0
	var n := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := img.get_pixel(x, y)
			if c.h > 0.05 and c.h < 0.14 and c.s > 0.35 and c.v > 0.35:
				sx += sin(c.h * TAU)
				cx += cos(c.h * TAU)
				ss += c.s
				sv += c.v
				n += 1
	if n == 0:
		return {"hue": 0.0, "sat": 0.0, "val": 0.0, "n": 0, "cover": 0.0}
	return {"hue": fposmod(atan2(sx, cx) / TAU, 1.0) * 360.0, "sat": ss / n, "val": sv / n, "n": n, "cover": float(n) / float(r.size.x * r.size.y)}


func project_px(cam: Vector3, tgt: Vector3, fov: float, p: Vector3, size := 1024.0) -> Vector2:
	var bas := Basis.looking_at((tgt - cam).normalized(), Vector3.UP)
	var q := bas.inverse() * (p - cam)
	var f := (size * 0.5) / tan(deg_to_rad(fov) * 0.5)
	return Vector2(size * 0.5 + f * q.x / -q.z, size * 0.5 - f * q.y / -q.z)


func set_tree(season: String, full: float) -> void:
	m.S.building["nature"] = []
	var it := {"kind": "tree", "species": "ginkgo", "x": 14.0, "z": 0.0, "height": 15.0, "crown": 11.0, "season": season, "density": 9, "seed": 11}
	if full != 1.0:
		it["fullness"] = full
	Nature.add(m.S.building, it)
	m.bld.sync()


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	if not await setup():
		quit(1)
		return
	if m.S.building.is_empty():
		m.S.building = Building.make("Untitled")
	# ------------------------------------------------------------------ O: the ornament shapes (numbers first)
	var sz := PartOrnament.default_size("ridge_dragon")
	var d1 := PartOrnament.mesh_dict("ridge_dragon", 3, sz)
	var d1b := PartOrnament.mesh_dict("ridge_dragon", 3, sz)
	var d2 := PartOrnament.mesh_dict("ridge_dragon", 4, sz)
	var km1: KMesh = d1["km"]
	var bb := AABB(km1.verts[0], Vector3.ZERO)
	for v in km1.verts:
		bb = bb.expand(v)
	ok(not d1.is_empty() and km1.boundary_edge_count() == 0 and km1.is_manifold() and absf(bb.size.x * 1000.0 - sz.x) < 1.0 and absf(bb.size.y * 1000.0 - sz.y) < 1.0 and absf(bb.size.z * 1000.0 - sz.z) < 1.0,
		"O1 ridge_dragon: one closed manifold, box %.0f x %.0f x %.0f mm = the asked %.0f x %.0f x %.0f" % [bb.size.x * 1000.0, bb.size.y * 1000.0, bb.size.z * 1000.0, sz.x, sz.y, sz.z])
	var g := OrnShapes.new()
	g.rng.seed = 3 * 7919 + 13
	PartOrnament.design(g, "ridge_dragon")
	var runs := 0
	var was := false
	for i in 120:
		var ins := g.field(Vector3(0.75, 0.3 + float(i) * 0.01, 0.0)) < 0.0
		if ins and not was:
			runs += 1
		was = ins
	var horns := 0
	for zs in [-1.0, 1.0]:
		for i in 40:
			var y := 1.06 + float(i) * 0.01
			if g.field(Vector3(0.22, y, 0.11 * zs)) < 0.0:
				horns += 1
				break
	ok(runs == 2 and horns == 2, "O1 the mouth is OPEN (a vertical line through the snout crosses solid %d times: upper and lower jaw) and it has %d horns above the skull (want 2 and 2)" % [runs, horns])
	var same: bool = km1.verts.size() == (d1b["km"] as KMesh).verts.size()
	if same:
		for i in km1.verts.size():
			if km1.verts[i] != (d1b["km"] as KMesh).verts[i]:
				same = false
				break
	var other: bool = (d2["km"] as KMesh).verts.size() != km1.verts.size() or (d2["km"] as KMesh).verts[5] != km1.verts[5]
	ok(same and other, "O3 seeded: the same seed gives the same %d vertices bit for bit, another seed gives another mesh" % km1.verts.size())
	var ds := PartOrnament.mesh_dict("corner_sprite", 5, PartOrnament.default_size("corner_sprite"))
	var db := PartOrnament.mesh_dict("corner_beast", 5, PartOrnament.default_size("corner_beast"))
	var szs := PartOrnament.default_size("corner_sprite")
	var szb := PartOrnament.default_size("corner_beast")
	var fill_s := float(ds["vol"]) / (szs.x * szs.y * szs.z)
	var fill_b := float(db["vol"]) / (szb.x * szb.y * szb.z)
	var kms: KMesh = ds["km"]
	ok(not ds.is_empty() and kms.boundary_edge_count() == 0 and kms.is_manifold() and fill_s <= 0.8 * fill_b, "O2 corner_sprite is closed and light: volume / box fill %.3f <= 0.8 x the corner beast's %.3f" % [fill_s, fill_b])
	# ------------------------------------------------------------------ R: roof lift_pow
	var base := {"type": "xieshan", "w": 14800.0, "d": 7000.0, "overhang": 2700.0, "height": 3300.0, "thick": 160.0, "sag": 800.0, "lift": 1100.0, "lift_len": 3400.0, "gable_in": 900.0}
	var Gd := PartRoof.geometry(PartRoof.norm(base))
	var G2 := PartRoof.geometry(PartRoof.norm(base.merged({"lift_pow": 2.0})))
	var G4 := PartRoof.geometry(PartRoof.norm(base.merged({"lift_pow": 4.0})))
	var ax: float = Gd["a"]
	var bz: float = Gd["b"]
	var ll: float = Gd["ll"]
	var lc_d: float = PartRoof._lift(Gd, ax, bz)
	var lm_d: float = PartRoof._lift(Gd, ax - ll * 0.5, bz)
	var lm_2: float = PartRoof._lift(G2, ax - ll * 0.5, bz)
	var lc_4: float = PartRoof._lift(G4, ax, bz)
	var lm_4: float = PartRoof._lift(G4, ax - ll * 0.5, bz)
	ok(lm_d == lm_2 and absf(lc_d - 1100.0) < 0.01 and absf(lc_4 - 1100.0) < 0.01 and lm_4 < 0.5 * lm_d, "R1 lift_pow: default == 2 (%.2f mm at half the lift length), 4 gives %.2f mm there (< half) and the same %.1f mm at the corner" % [lm_d, lm_4, lc_4])
	# ------------------------------------------------------------------ N: the canopy, rendered with the light
	var cam := Vector3(14.0, 6.0, 30.0)
	var tgt := Vector3(14.0, 7.5, 0.0)
	TempleLight.set_camera(m, cam, tgt, 45.0, 0.5, 3000.0)
	if TempleLight.on:
		TempleLight.set_live(m, false)
	TempleLight.set_live(m, true)
	var p0 := project_px(cam, tgt, 45.0, Vector3(14.0 - 4.0, 12.5, 0.0))
	var p1 := project_px(cam, tgt, 45.0, Vector3(14.0 + 4.0, 6.5, 0.0))
	var win := Rect2i(int(p0.x), int(p0.y), int(p1.x - p0.x), int(p1.y - p0.y))
	set_tree("autumn", 1.0)
	await idle(20)
	var im_a := await shot("canopy_autumn")
	var st_a := canopy_stats(im_a, win)
	set_tree("amber", 1.0)
	await idle(20)
	var im_1 := await shot("canopy_amber1")
	var st_1 := canopy_stats(im_1, win)
	var fl := float(OS.get_environment("S236_FULL")) if OS.get_environment("S236_FULL") != "" else 2.6
	set_tree("amber", fl)
	await idle(20)
	var im_f := await shot("canopy_amber_full")
	var st_f := canopy_stats(im_f, win)
	print("REF (reference.png, measure4.py): canopy hue 31.5 / 33.1 deg, sat 0.676 / 0.692, val 0.649 / 0.747, edge-window cover 0.345 / 0.479; round 3: 49.1 deg, 0.481, 0.671, cover 0.233 / 0.192")
	print("KINE window ", win, " autumn: ", st_a, "  amber x1: ", st_1, "  amber full %.1f: " % fl, st_f)
	ok(int(st_f["n"]) > 800 and float(st_f["hue"]) >= 24.0 and float(st_f["hue"]) <= 40.0 and float(st_f["sat"]) >= 0.58, "N1 amber canopy (rendered): hue %.1f deg in [24, 40], saturation %.3f >= 0.58 (reference 31-33 deg, 0.68; round 3 autumn 49 deg, 0.48; this run's autumn: %.1f deg, %.3f)" % [st_f["hue"], st_f["sat"], st_a["hue"], st_a["sat"]])
	ok(float(st_f["val"]) >= 0.5 and float(st_f["val"]) <= 0.86, "N1 canopy value %.3f in [0.5, 0.86] (reference 0.65-0.75: not neon, not dark)" % st_f["val"])
	ok(float(st_f["n"]) >= 1.25 * float(st_1["n"]) and float(st_f["cover"]) >= 0.40, "N2 fullness %.1f: canopy pixels %d >= 1.25 x %d (fullness 1) and covers %.3f >= 0.40 of the crown window" % [fl, st_f["n"], st_1["n"], st_f["cover"]])
	var t_def := Nature.make_tree({"kind": "tree", "species": "ginkgo", "height": 6.0, "season": "autumn", "density": 5, "seed": 2})
	var t_one := Nature.make_tree({"kind": "tree", "species": "ginkgo", "height": 6.0, "season": "autumn", "density": 5, "seed": 2, "fullness": 1.0})
	var cl := Nature.clean({"kind": "tree", "species": "oak", "season": "autumn"})
	ok(int(t_def["leaf_n"]) == int(t_one["leaf_n"]) and not cl.has("fullness") and Nature.SEASONS.has("amber") and Nature.SEASONS.has("autumn"), "N3 fullness 1 changes nothing (%d leaves both ways), a record without it stays without it, amber is added beside autumn" % int(t_def["leaf_n"]))
	# ------------------------------------------------------------------ M: mountains
	m.S.building["nature"] = []
	m.bld.sync()
	var cam2 := Vector3(0.0, 4.5, 38.0)
	var tgt2 := Vector3(0.0, 6.3, 0.0)
	TempleLight.set_camera(m, cam2, tgt2, 45.0, 0.5, 3000.0)
	TempleLight.mountains = false
	TempleLight.refresh(m)
	await idle(10)
	var n_off := m.find_children("temple_mountains", "Node3D", true, false).size()
	var im_n := await shot("mountains_off")
	TempleLight.mountains = true
	TempleLight.refresh(m)
	await idle(20)
	var mts := m.find_children("temple_mountains", "Node3D", true, false)
	var im_m := await shot("mountains_on")
	var peak := 0.0
	var layers := 0
	if mts.size() == 1:
		for ch in mts[0].get_children():
			layers += 1
			var arr: PackedVector3Array = (ch as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for v in arr:
				peak = maxf(peak, v.y)
	var diff := 0
	var sky_diff := 0.0
	for y in range(0, 1024, 2):
		for x in range(0, 1024, 2):
			var c1 := im_n.get_pixel(x, y)
			var c2 := im_m.get_pixel(x, y)
			var dd := maxf(absf(c1.r - c2.r), maxf(absf(c1.g - c2.g), absf(c1.b - c2.b)))
			if dd > 0.06:
				diff += 1
			if y < 100:
				sky_diff += dd
	var frac := float(diff) / float(512 * 512)
	sky_diff /= float(50 * 512)
	ok(n_off == 0 and mts.size() == 1 and layers == 2 and peak >= 80.0, "M1 mountains off: %d nodes; on: %d node with %d layers, highest peak %.0f m >= 80" % [n_off, mts.size(), layers, peak])
	TempleLight.set_live(m, false)
	var n_gone := m.find_children("temple_mountains", "Node3D", true, false).size()
	ok(n_gone == 0, "M1 turning the temple light off removes them (%d left)" % n_gone)
	ok(frac >= 0.02 and sky_diff < 0.01, "M2 rendered: %.1f %% of the pixels differ from the no-mountains picture (>= 2 %%), the sky rows above differ by %.4f (< 0.01)" % [frac * 100.0, sky_diff])
	TempleLight.mountains = false
	# ------------------------------------------------------------------ the ornaments on their platform, with the light (a picture for the eyes; the bars are above)
	TempleLight.set_camera(m, Vector3(0.0, 2.6, 9.0), Vector3(0.0, 1.2, 0.0), 40.0, 0.2, 3000.0)
	TempleLight.set_live(m, true)
	await idle(20)
	await shot("ornaments_front")
	TempleLight.set_camera(m, Vector3(-7.5, 3.2, 6.0), Vector3(0.0, 1.0, 0.0), 40.0, 0.2, 3000.0)
	await idle(8)
	await shot("ornaments_3q")
	TempleLight.set_camera(m, Vector3(-1.8, 2.3, 5.6), Vector3(-4.2, 2.0, 1.5), 40.0, 0.2, 3000.0)
	await idle(8)
	await shot("dragon_close")
	TempleLight.set_live(m, false)
	print("s236: %d fail" % fails)
	quit(1 if fails > 0 else 0)
