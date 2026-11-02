extends SceneTree
## godot --path . --position 4000,4000 -s tests/s231_test.gd     (ITEM 231 TEMPLE LOOK: scripts/build/piece_look.gd + the 223 material library; needs the CAD DLL)
## Bars:
##   1 KINDS     every body of a temple (built like hall_driver: named boxes, a xieshan roof with its trims, a chiwen) has a kind; every kind of the table is present
##   2 NONFLAT   a temple: bodies with no made material (plain albedo-only look) = 0 (it was every body)
##   3 LOOKS     each default material read from ITS RENDER (top-down, ortho, sun + sky): tile rows and ribs = a periodic luminance signal at the tile pitch;
##               lacquer = red hue band; marble = low saturation, high value; slabs = joints at the slab pitch; caihua = teal ground + gold share; plaster = red; plaque = dark
##   4 PLAIN     an ordinary house (same bodies, no temple name, a gable roof): changed pieces = 0 against the old default looks
##   5 WORDS     "red lacquer columns", "glazed green tiles", "white marble rails", "teal beams": kind + spec; unknown words listed
##   6 UI        the Materials page: the words box and the Aim chips change every piece of a kind, ONE undo step each, Undo takes it back
##   7 SAVE      JSON round trip: the style and the choices replay to the same looks
##   8 GRAVEL    no camouflage: the block-mean colour spread and the hue spread are small, the stones are still there (stone-scale spread)
##   9 OAK       knots: small, oval (long along the grain), rare: the dark blob area and shape of every oak seed
## Shots: C:/Users/Nick/tools/kine_workers/out/231/ (temple.png overview, sheet.png the new materials, gravel.png, oak.png)
var fails := 0
var m: Node
const SHOT := "C:/Users/Nick/tools/kine_workers/out/231"
const DIRT := "user://s231_test"


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


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


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func pu() -> PartUI:
	return m.bld.part


# ---------------------------------------------------------------- a small temple as Part steps (what hall_driver does, in miniature)

var rec := {}
var nb := 0


func add(t: String, f: Dictionary) -> String:
	var nf := Part.new_feature(rec, t, f)
	(rec["features"] as Array).append(nf)
	return String(nf["id"])


func box(x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, nm: String) -> void:
	var pl := "top"
	if absf(y0) > 0.0001:
		pl = add("plane", {"from": "top", "mm": y0})
	var sk := add("sketch", {"plane": pl, "ents": [{"k": "rect", "a": [x0, -z1], "b": [x1, -z0]}], "dims": []})
	add("extrude", {"sketch": sk, "dist": y1 - y0, "both": false, "op": "new"})
	add("bname", {"body": nb, "called": nm})
	nb += 1


## the temple: every kind of the table once or more. xieshan roof + ridge/hip/eave trims, one chiwen at the ridge end
func temple(nm: String, roof_type: String) -> Dictionary:
	rec = Part.make(nm)
	nb = 0
	box(-30000, 30000, -300, 0, -20000, 30000, "Grass")
	box(-9000, 9000, 0, 1400, -6000, 6000, "Platform")
	box(-1800, 1800, 0, 1400, 6000, 8400, "Stair")
	box(-9000, 9000, 1400, 2300, 5800, 6000, "Platform rail")
	box(-6000, 6000, 1400, 1700, -4500, 4500, "Hall floor")
	for k in 4:
		box(-5600 + k * 3700, -5200 + k * 3700, 1400, 5400, 3800, 4200, "Column %d" % (k + 1))
	box(-5500, 5500, 1400, 5000, -4000, 3800, "Red hall")
	box(-6200, 6200, 5400, 6200, -4600, 4600, "Lower brackets")
	box(-1200, 1200, 5000, 5400, 3800, 3900, "Plaque")
	box(-1000, 1000, 5050, 5350, 3900, 3950, "Plaque letters")
	box(-900, 900, 1400, 3400, 3900, 4000, "Door")
	box(-4800, -3000, 2000, 3600, 3900, 4000, "Lattice")
	box(-3000, 3000, 0, 400, 10000, 22000, "Paving")
	box(-12000, -9500, 0, 1200, 9000, 20000, "Hedge")
	box(-20000, -19700, 0, 5000, 2000, 2300, "Trunk")
	box(-21200, -18500, 5000, 7600, 800, 3500, "Canopy")
	box(-30000, 30000, 0, 2600, -20000, -19600, "Wall")
	box(-30000, 30000, 0, 600, -19900, -19500, "Wall base")
	box(-30000, 30000, 2600, 2900, -20100, -19400, "Wall cap")
	add("roof", {"type": roof_type, "w": 11000.0, "d": 9000.0, "overhang": 1800.0, "height": 2600.0, "sag": 250.0 if roof_type == "xieshan" else 0.0,
		"lift": 700.0 if roof_type == "xieshan" else 0.0, "lift_len": 3000.0, "thick": 160.0, "ridge": true, "hips": roof_type == "xieshan", "eave": true, "at": [0.0, 6200.0, 0.0], "detail": 14})
	if roof_type == "xieshan":
		add("ornament", {"kind": "chiwen", "seed": 1, "size": [700.0, 1100.0, 300.0], "places": [{"at": [5400.0, 8800.0, 0.0], "dir": [-1.0, 0.0, 0.0]}]})
	return rec


# ---------------------------------------------------------------- rendering a replay result in a small world

func make_world(size: Vector2i, ortho: float) -> Array:
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#6fb0e8")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.88, 0.95)
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, -30, 0)
	sun.light_energy = 1.0
	vp.add_child(sun)
	var cam := Camera3D.new()
	if ortho > 0.0:
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = ortho
	vp.add_child(cam)
	root.add_child(vp)
	return [vp, cam]


func part_node(res: Dictionary) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh: ArrayMesh = res["mesh"]
	mi.mesh = mesh
	var ls: Array = res.get("looks", [])
	for s in mini(ls.size(), mesh.get_surface_count()):
		var l: Dictionary = ls[s]
		var mm := MaterialMaker.look_material(l)
		if mm != null:
			mi.set_surface_override_material(s, mm)
		else:
			var mt := StandardMaterial3D.new()
			mt.albedo_color = l["c"]
			mt.roughness = float(l["rough"])
			mt.cull_mode = BaseMaterial3D.CULL_DISABLED
			mi.set_surface_override_material(s, mt)
	return mi


## a flat plate of one kind (named like the kind), top view, ortho; returns the image
func plate(nm: String, w_mm: float, view_m: float) -> Image:
	rec = Part.make("Chinese plate")
	nb = 0
	box(-w_mm * 0.5, w_mm * 0.5, 0, 100, -w_mm * 0.5, w_mm * 0.5, nm)
	var res := Part.replay(rec)
	var wd: Array = make_world(Vector2i(512, 512), view_m)
	var vp: SubViewport = wd[0]
	var cam: Camera3D = wd[1]
	vp.add_child(part_node(res))
	cam.position = Vector3(0, 2.0, 0)
	cam.rotation_degrees = Vector3(-90, 0, 0)
	return null if vp == null else await grab(vp)


func grab(vp: SubViewport) -> Image:
	await idle(8)
	var im := vp.get_texture().get_image()
	vp.queue_free()
	return im


func profile(im: Image, along_y: bool) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	var lo := 64
	var hi := 448
	for i in range(lo, hi):
		var s := 0.0
		for j in range(lo, hi):
			s += lum(im.get_pixel(j if along_y else i, i if along_y else j))
		a.append(s / float(hi - lo))
	return a


func autocorr(a: PackedFloat32Array, lag: int) -> float:
	var mean := 0.0
	for v in a:
		mean += v
	mean /= float(a.size())
	var num := 0.0
	var den := 0.0
	for i in a.size():
		den += (a[i] - mean) * (a[i] - mean)
		if i + lag < a.size():
			num += (a[i] - mean) * (a[i + lag] - mean)
	return num / maxf(den, 1e-9)


func mean_hsv(im: Image) -> Array:
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var k := 0
	for y in range(128, 384, 2):
		for x in range(128, 384, 2):
			var c := im.get_pixel(x, y)
			r += c.r
			g += c.g
			b += c.b
			k += 1
	var c := Color(r / k, g / k, b / k)
	return [c.h, c.s, c.v]


func share(im: Image, h0: float, h1: float, smin: float, vmin: float) -> float:
	var n := 0
	var t := 0
	for y in range(64, 448, 2):
		for x in range(64, 448, 2):
			var c := im.get_pixel(x, y)
			t += 1
			if c.h >= h0 and c.h <= h1 and c.s >= smin and c.v >= vmin:
				n += 1
	return float(n) / float(t)


# ---------------------------------------------------------------- the bars

func kinds_bars() -> Dictionary:
	var r := temple("Chinese hall", "xieshan")
	var res := Part.replay(r)
	var ks: Array = res["body_kinds"]
	var have := {}
	for k in ks:
		have[String(k)] = int(have.get(String(k), 0)) + 1
	var want := ["roof", "ridge", "column", "beam", "platform", "stair", "rail", "paving", "wall", "plaque", "plaque_letters", "door", "lattice", "ground", "hedge", "trunk", "canopy", "wall_base", "wall_cap"]
	var miss := []
	for k in want:
		if not have.has(k):
			miss.append(k)
	ok(int(res["bodies"]) >= 26 and miss.is_empty() and not have.has(""), "1 the temple has %d bodies, every kind of the table is present (missing %s), no body without a kind (%s)" % [int(res["bodies"]), str(miss), str(have)])
	var plain := PieceLook.plain_count(res)
	var plain_old := 0
	var old_rec := r.duplicate(true)
	old_rec["style"] = "none"
	var res_old := Part.replay(old_rec)
	plain_old = PieceLook.plain_count(res_old)
	ok(plain == 0 and plain_old == int(res_old["bodies"]), "2 bodies with a plain albedo-only look: %d of %d in a temple (was %d of %d with style none)" % [plain, int(res["bodies"]), plain_old, int(res_old["bodies"])])
	var kinds_mat := {}
	for i in ks.size():
		kinds_mat[String(ks[i])] = String(((res["body_looks"][i] as Dictionary).get("mat", {}) as Dictionary).get("kind", ""))
	var want_mat := {"roof": "tile", "ridge": "tile", "column": "lacquer", "beam": "caihua", "platform": "marble", "stair": "marble", "rail": "marble", "paving": "slabs", "wall": "plaster", "plaque": "lacquer", "plaque_letters": "brass", "door": "lacquer"}
	var wrong := []
	for k in want_mat:
		if kinds_mat.get(k, "") != want_mat[k]:
			wrong.append("%s=%s" % [k, kinds_mat.get(k, "")])
	ok(wrong.is_empty(), "2 the default material of each piece kind is the one the plan names %s" % str(wrong))
	# the 3D overview
	var wd: Array = make_world(Vector2i(1024, 1024), 0.0)
	var vp: SubViewport = wd[0]
	var cam: Camera3D = wd[1]
	vp.add_child(part_node(res))
	cam.fov = 40.0
	cam.far = 400.0
	cam.near = 0.5
	cam.position = Vector3(-14, 11, 40)
	cam.look_at_from_position(cam.position, Vector3(0, 4, 0))
	var im := await grab(vp)
	DirAccess.make_dir_recursive_absolute(SHOT)
	im.save_png(SHOT + "/temple.png")
	return {"rec": r}


func look_bars() -> void:
	var t := await plate("Roof", 2200.0, 2.2)
	t.save_png(SHOT + "/plate_roof.png")
	var pitch := roundi(float(PieceLook.DEFAULTS["roof"]["scale"]) / 4.0 * 512.0 / 2200.0)   # 4 rows per tile: 1100 / 4 = 275 mm = 64 px at 233 px per m
	var py := profile(t, true)
	var px := profile(t, false)
	var a1 := autocorr(py, pitch)
	var a2 := autocorr(py, pitch / 2)
	var b1 := autocorr(px, pitch)
	var b2 := autocorr(px, pitch / 2)
	ok(a1 > 0.45 and a1 > a2 + 0.3, "3 roof tile: luminance along the slope repeats at the row pitch (lag %d px autocorr %.2f vs half-pitch %.2f)" % [pitch, a1, a2])
	ok(b1 > 0.45 and b1 > b2 + 0.3, "3 roof tile: and across the slope at the rib pitch (autocorr %.2f vs half-pitch %.2f)" % [b1, b2])
	var hs := mean_hsv(t)
	ok(hs[0] > 0.03 and hs[0] < 0.1 and hs[1] > 0.55, "3 roof tile: orange-terracotta hue %.0f deg, saturation %.2f" % [float(hs[0]) * 360.0, hs[1]])
	var c := await plate("Column", 2400.0, 2.4)
	c.save_png(SHOT + "/plate_column.png")
	var hc := mean_hsv(c)
	ok((hc[0] < 0.035 or hc[0] > 0.96) and hc[1] > 0.6 and hc[2] > 0.25 and hc[2] < 0.85, "3 lacquer: red hue %.0f deg, saturation %.2f, value %.2f" % [float(hc[0]) * 360.0, hc[1], hc[2]])
	var mr := await plate("Platform", 2400.0, 2.4)
	mr.save_png(SHOT + "/plate_marble.png")
	var hm := mean_hsv(mr)
	ok(hm[1] < 0.14 and hm[2] > 0.72, "3 marble: saturation %.2f (< 0.14), value %.2f (> 0.72)" % [hm[1], hm[2]])
	var sl := await plate("Paving", 4800.0, 4.8)
	sl.save_png(SHOT + "/plate_slabs.png")
	var ps := profile(sl, true)
	var s_pitch := 128   # a 1200 mm slab row at 107 px per m
	var as1 := autocorr(ps, s_pitch)
	var as2 := autocorr(ps, s_pitch / 2)
	ok(as1 > 0.3 and as1 > as2 + 0.25, "3 stone slabs: the joints repeat at the slab pitch (lag %d px autocorr %.2f vs half %.2f)" % [s_pitch, as1, as2])
	var cb := await plate("Lower brackets", 1600.0, 1.6)
	cb.save_png(SHOT + "/plate_beam.png")
	var hb := mean_hsv(cb)
	var gold_share := share(cb, 0.08, 0.17, 0.4, 0.45)
	ok(hb[0] > 0.42 and hb[0] < 0.58 and gold_share > 0.015, "3 painted beam: teal mean hue %.0f deg, and gold lines are %.1f %% of the pixels (> 1.5)" % [float(hb[0]) * 360.0, gold_share * 100.0])
	var pw := await plate("Red hall", 2400.0, 2.4)
	var hw := mean_hsv(pw)
	ok((hw[0] < 0.04 or hw[0] > 0.96) and hw[1] > 0.5, "3 red plaster wall: hue %.0f deg, saturation %.2f" % [float(hw[0]) * 360.0, hw[1]])
	var pq := await plate("Plaque", 800.0, 0.8)
	var hq := mean_hsv(pq)
	ok(hq[2] < 0.3, "3 dark lacquer plaque: value %.2f (< 0.3)" % hq[2])
	var pl := await plate("Plaque letters", 800.0, 0.8)
	var hl := mean_hsv(pl)
	ok(hl[0] > 0.07 and hl[0] < 0.16 and hl[1] > 0.45, "3 gilt letters: gold hue %.0f deg, saturation %.2f" % [float(hl[0]) * 360.0, hl[1]])


func plain_bars() -> void:
	var r := temple("House", "gable")
	var res := Part.replay(r)
	var changed := 0
	var texts := []
	for i in int(res["bodies"]):
		var l: Dictionary = res["body_looks"][i]
		var d := {"c": Color("#bdc4d0"), "rough": 0.5, "metal": 0.15, "alpha": 1.0, "preset": "Default"}   # the old default look of body i (chip by index)
		var chip: Color = Part.LOOK_CHIPS[i % Part.LOOK_CHIPS.size()][1]
		d["c"] = chip
		if (l["c"] as Color).to_html() != chip.to_html() or String(l["preset"]) != "Default" or float(l["rough"]) != 0.5 or float(l["metal"]) != 0.15 or not (l.get("mat", {}) as Dictionary).is_empty():
			changed += 1
			texts.append(i)
	ok(int(res["bodies"]) >= 20 and changed == 0 and PieceLook.style_of(r) == "", "4 an ordinary house (name House, a gable roof): %d bodies, changed pieces %d (want 0), style '%s'" % [int(res["bodies"]), changed, PieceLook.style_of(r)])
	var r2 := temple("Garden shed", "gable")
	r2["style"] = "temple"
	var res2 := Part.replay(r2)
	ok(PieceLook.plain_count(res2) == 0, "4 the same house with style temple set by hand: plain bodies %d" % PieceLook.plain_count(res2))


func words_bars() -> void:
	var a := PieceLook.parse("red lacquer columns")
	ok(a["ok"] and a["kind"] == "column" and a["spec"]["kind"] == "lacquer" and Color(a["spec"]["color"]).r > 0.9 and Color(a["spec"]["color"]).g < 0.1 and a["unknown"].is_empty(), "5 'red lacquer columns': column, %s" % MaterialWords.describe(a["spec"]))
	var b := PieceLook.parse("glazed green tiles")
	var bc := Color(b["spec"].get("color", "#000000"))
	ok(b["ok"] and b["kind"] == "roof" and b["spec"]["kind"] == "tile" and float(b["spec"]["gloss"]) >= 0.85 and bc.g > bc.r and bc.g > bc.b, "5 'glazed green tiles': roof, tile, glossy, green (%s)" % MaterialWords.describe(b["spec"]))
	var c := PieceLook.parse("white marble rails")
	ok(c["ok"] and c["kind"] == "rail" and c["spec"]["kind"] == "marble" and Color(c["spec"]["color"]).s < 0.05, "5 'white marble rails': rail, marble, white")
	var d := PieceLook.parse("teal caihua beams")
	var dc := Color(d["spec"].get("color", "#000000"))
	ok(d["ok"] and d["kind"] == "beam" and d["spec"]["kind"] == "caihua" and dc.h > 0.45 and dc.h < 0.55, "5 'teal caihua beams': beam, painted beam, teal")
	var e := PieceLook.parse("worn red columns sparkly")
	ok(e["ok"] and e["kind"] == "column" and e["spec"]["kind"] == "lacquer" and float(e["spec"]["wear"]) > 0.2 and e["unknown"] == ["sparkly"], "5 'worn red columns sparkly': the column lacquer, worn, 'sparkly' listed not guessed")
	var f := PieceLook.parse("dark oak")
	ok(f["ok"] and f["kind"] == "" and f["spec"]["kind"] == "oak", "5 no piece noun: kind '' (the picked solid), the 223 reading unchanged")
	ok(PieceLook.kind_of_name("Stair rail") == "rail" and PieceLook.kind_of_name("Door plaque") == "plaque" and PieceLook.kind_of_name("Plaque letters 3") == "plaque_letters" and PieceLook.kind_of_name("Wall base") == "wall_base" and PieceLook.kind_of_name("Body4") == "", "5 names read by kind: Stair rail, Door plaque, Plaque letters 3, Wall base, Body4")


func looks_of(res: Dictionary, kind: String) -> Array:
	var out := []
	var ks: Array = res["body_kinds"]
	for i in ks.size():
		if String(ks[i]) == kind:
			out.append(res["body_looks"][i])
	return out


func ui_bars() -> void:
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	ok(m.cur_page == "BUILD" and pu().on and pu().easy, "0 BUILDING card, one click -> Easy Part on")
	var r := temple("Chinese hall", "gable")
	m.S.part = r
	pu().upto = -1
	pu().sync()
	await idle(40)
	var ep = pu().ep
	await click_ctl(ep.make_btns["colour"])
	if not (m.find_child("easypart_materials", true, false) as Control).visible:
		await click_ctl(m.find_child("easypart_colour_materials", true, false))
	await idle(6)
	var nbod := int(pu().res.get("bodies", 0))
	ok(nbod >= 20 and PieceLook.plain_count(pu().res) == 0, "6 the temple is on screen: %d bodies, plain %d" % [nbod, PieceLook.plain_count(pu().res)])
	var ncol := PieceLook.bodies_of(pu().res, "column").size()
	var words := m.find_child("easypart_mat_words", true, false) as LineEdit
	var u0: int = m.undo.size()
	var f0: int = (m.S.part["features"] as Array).size()
	words.text = "glazed green tiles"
	words.text_submitted.emit("glazed green tiles")
	await idle(10)
	var roofs := looks_of(pu().res, "roof")
	var green := true
	for l in roofs:
		var cc: Color = Color(String((l["mat"] as Dictionary)["color"]))
		green = green and cc.g > cc.r and cc.g > cc.b and String((l["mat"] as Dictionary)["kind"]) == "tile"
	ok(roofs.size() >= 1 and green and m.undo.size() == u0 + 1 and (m.S.part["features"] as Array).size() == f0 + roofs.size(), "6 words 'glazed green tiles': %d roof piece(s) green tile, ONE undo step (%d -> %d), %d appear steps" % [roofs.size(), u0, m.undo.size(), (m.S.part["features"] as Array).size() - f0])
	var u1: int = m.undo.size()
	words.text = "worn dark red lacquer columns"
	words.text_submitted.emit("worn dark red lacquer columns")
	await idle(10)
	var cols := looks_of(pu().res, "column")
	var all_worn := true
	for l in cols:
		all_worn = all_worn and float((l["mat"] as Dictionary)["wear"]) > 0.4
	ok(cols.size() == ncol and ncol >= 4 and all_worn and m.undo.size() == u1 + 1, "6 words 'worn dark red lacquer columns': all %d columns worn lacquer, ONE undo step" % ncol)
	# the chips: Aim at Rails, then the granite swatch
	var u2: int = m.undo.size()
	await click_ctl(m.find_child("easypart_aim_rail", true, false))
	await click_ctl(m.find_child("easypart_mat_granite", true, false))
	await idle(8)
	var rails := looks_of(pu().res, "rail")
	var gran := true
	for l in rails:
		gran = gran and String((l["mat"] as Dictionary)["kind"]) == "granite"
	ok(rails.size() >= 1 and gran and m.undo.size() == u2 + 1, "6 chips: Aim at Rails + the granite swatch: %d rail piece(s) granite, ONE undo step" % rails.size())
	var cols_after := looks_of(pu().res, "column")
	var still := true
	for l in cols_after:
		still = still and String((l["mat"] as Dictionary)["kind"]) == "lacquer"
	ok(still, "6 the other kinds were not touched by the rails' change")
	await click_ctl(m.find_child("easypart_aim_", true, false))
	var snap_before := JSON.stringify(m.S.part)
	var ub: int = m.undo.size()
	m._undo()
	await idle(20)
	var rails2 := looks_of(pu().res, "rail")
	var back := true
	for l in rails2:
		back = back and String((l.get("mat", {}) as Dictionary).get("kind", "")) == "marble"
	ok(back and m.undo.size() == ub - 1, "6 Undo takes the rails' granite back to the default marble")
	# 7 SAVE
	var txt := JSON.stringify(m.S.part)
	var back_rec := Part.from_file(JSON.parse_string(txt))
	var r1 := Part.replay(m.S.part)
	var r2 := Part.replay(back_rec)
	var same: bool = r1["body_looks"].size() == r2["body_looks"].size()
	for i in r1["body_looks"].size():
		var l1: Dictionary = r1["body_looks"][i]
		var l2: Dictionary = r2["body_looks"][i]
		same = same and JSON.stringify(MaterialMaker.norm(l1.get("mat", {})), "", true) == JSON.stringify(MaterialMaker.norm(l2.get("mat", {})), "", true) and (l1["c"] as Color).to_html() == (l2["c"] as Color).to_html()
	ok(same and String(back_rec.get("name", "")) == "Chinese hall", "7 saved as JSON, read back and replayed: all %d looks the same (tiles %s, columns %s)" % [r1["body_looks"].size(), String(((looks_of(r2, "roof")[0] as Dictionary)["mat"] as Dictionary)["kind"]), String(((looks_of(r2, "column")[0] as Dictionary)["mat"] as Dictionary)["color"])])
	var rs := Part.make("Garden")
	rs["style"] = "temple"
	rs["features"] = (m.S.part["features"] as Array).duplicate(true)
	var rs2 := Part.from_file(JSON.parse_string(JSON.stringify(rs)))
	ok(String(rs2.get("style", "")) == "temple", "7 the style survives save and load")
	# the Temple look / Plain buttons: one undo step each
	var u3: int = m.undo.size()
	await click_ctl(m.find_child("easypart_plain_look", true, false))
	await idle(10)
	var plain_now := PieceLook.plain_count(pu().res)
	await click_ctl(m.find_child("easypart_temple_look", true, false))
	await idle(10)
	ok(plain_now > 0 and m.undo.size() == u3 + 2, "6 the Plain button sets the plain colours back (%d plain bodies), Temple look sets the materials again; one undo step each (%d -> %d)" % [plain_now, u3, m.undo.size()])
	var rr := Part.replay(m.S.part)
	var plain_sty := 0
	for l in rr["body_looks"]:
		if String(l.get("preset", "")) == "Style":
			plain_sty += 1
	ok(plain_sty >= 8, "6 after Plain then Temple look the default materials are back (%d bodies wear the style, the rest keep the user's choices)" % plain_sty)


# ---------------------------------------------------------------- gravel and oak

func block_stats(im: Image) -> Array:
	var n := im.get_width()
	var bs := n / 16
	var bl := []
	var hue := []
	var allv := []
	for by in 16:
		for bx in 16:
			var s := Color(0, 0, 0)
			for y in range(by * bs, by * bs + bs, 2):
				for x in range(bx * bs, bx * bs + bs, 2):
					s += im.get_pixel(x, y)
			var k := float(bs / 2 * (bs / 2))
			var c := Color(s.r / k, s.g / k, s.b / k)
			bl.append(lum(c))
			hue.append((c.r - c.b) / maxf(c.r + c.g + c.b, 1e-6))
	for y in range(0, n, 2):
		for x in range(0, n, 2):
			allv.append(lum(im.get_pixel(x, y)))
	return [bl, hue, allv]


func sdv(a: Array) -> float:
	var s := 0.0
	for v in a:
		s += float(v)
	var mean := s / a.size()
	var q := 0.0
	for v in a:
		q += (float(v) - mean) * (float(v) - mean)
	return sqrt(q / a.size())


func meanv(a: Array) -> float:
	var s := 0.0
	for v in a:
		s += float(v)
	return s / a.size()


func gravel_bars() -> void:
	var g := MaterialMaker.make(MaterialMaker.library_spec("gravel"), 512)
	var im: Image = g["albedo"]
	var st := block_stats(im)
	var cv_block := sdv(st[0]) / meanv(st[0])
	var hue_sd := sdv(st[1])
	var cv_stone := sdv(st[2]) / meanv(st[2])
	im.save_png(SHOT + "/gravel_albedo.png")
	print("     gravel: block-mean luminance CV %.3f, block hue spread %.4f, stone-scale CV %.3f" % [cv_block, hue_sd, cv_stone])
	ok(cv_block < 0.07 and hue_sd < 0.012 and cv_stone > 0.12, "8 gravel: no camouflage blotches (16 x 16 block-mean luminance CV %.3f < 0.07 (223: 0.121), block colour spread %.4f < 0.012 (223: 0.021)) and the stones are there (pixel-scale CV %.3f > 0.12)" % [cv_block, hue_sd, cv_stone])


func oak_bars() -> void:
	# the knots as the generator draws them (MaterialMaker.knots_of is the list _wood itself reads): size in mm, shape, how many of 12 seeds have one
	var with_knot := 0
	var widest := 0.0
	var squat := 1e9
	var old_mm := 2.0 * 0.04 * 240.0   # 223: radius 0.04 to 0.08 of a 240 mm tile, round: 19 to 38 mm across, one in every tile
	for seed in range(1, 13):
		var sp := MaterialMaker.library_spec("oak")
		sp["seed"] = seed
		var ks := MaterialMaker.knots_of(sp)
		if not ks.is_empty():
			with_knot += 1
		for k in ks:
			widest = maxf(widest, 2.0 * float(k[2]) * float(sp["scale"]))
			squat = minf(squat, float(k[3]))
	print("     oak knots: %d of 12 seeds have one, widest %.1f mm across, shortest stretch along the grain x%.1f (223: one in every tile, %.0f to %.0f mm round)" % [with_knot, widest, squat, old_mm, old_mm * 2.0])
	ok(with_knot >= 1 and with_knot <= 6, "9 oak knots are rare: %d of 12 seeds have one (<= 6; 223 had one in every tile)" % with_knot)
	ok(widest <= 15.0 and squat >= 2.0, "9 an oak knot is small and oval: at most %.1f mm across (<= 15, was 19 to 38) and at least x%.1f as long as wide along the grain (>= 2, was round)" % [widest, squat])
	var sp1 := MaterialMaker.library_spec("oak")
	sp1["seed"] = 3
	var sp2 := MaterialMaker.library_spec("pine")
	var a: Image = MaterialMaker.make(sp1, 512)["albedo"]
	var b: Image = MaterialMaker.make(sp2, 512)["albedo"]
	var both := Image.create(1024, 512, false, Image.FORMAT_RGB8)
	both.blit_rect(a, Rect2i(0, 0, 512, 512), Vector2i(0, 0))
	both.blit_rect(b, Rect2i(0, 0, 512, 512), Vector2i(512, 0))
	both.save_png(SHOT + "/oak_pine.png")


func sheet() -> void:
	var ids := ["tile", "slabs", "caihua", "gold", "gravel", "oak", "lacquer", "marble"]
	var wd: Array = make_world(Vector2i(1600, 400), 0.0)
	var vp: SubViewport = wd[0]
	var cam: Camera3D = wd[1]
	cam.position = Vector3(0, 0, 4.2)
	cam.fov = 40.0
	for k in ids.size():
		var mt := MaterialMaker.standard(MaterialMaker.library_spec(String(ids[k])))
		mt.uv1_scale = mt.uv1_scale * 0.5
		var cu := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.8, 0.8, 0.8)
		cu.mesh = bm
		cu.material_override = mt
		cu.position = Vector3(-3.5 + k * 1.0, 0, 0)
		cu.rotation_degrees = Vector3(30, 35, 0)
		vp.add_child(cu)
	var im := await grab(vp)
	im.save_png(SHOT + "/sheet.png")


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT)
	if not Part.available():
		print("FAIL: no KineCAD DLL")
		quit(1)
		return
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	gravel_bars()
	oak_bars()
	await kinds_bars()
	await look_bars()
	plain_bars()
	words_bars()
	await sheet()
	await ui_bars()
	print("s231: %d fail" % fails)
	quit(1 if fails > 0 else 0)
