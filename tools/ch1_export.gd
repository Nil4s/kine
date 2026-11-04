extends SceneTree
## CH1a export: blueprint sheets (plan, 4 elevations, 1 section), the 3/4 render and the making-of frames. Window needed (renders).
## godot --position -30000,-30000 --audio-driver Dummy --path . -s tools/ch1_export.gd -- <outdir> [sheets|shots|video]
## Everything goes to <outdir> (default res://out/ch1). Nothing is written into the user's Poser folder.
var outdir := ""
var d := {}
var denom_pick := {}
const XC := 2438.4   # the section cut: through a joist, a rafter and a stud of the front wall


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	outdir = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://out/ch1")
	var what: String = args[1] if args.size() > 1 else "all"
	DirAccess.make_dir_recursive_absolute(outdir)
	d = JSON.parse_string(FileAccess.get_file_as_string("res://data/challenges/ch1_house.json"))
	root.size = Vector2i(1280, 720)
	if what in ["all", "sheets"]:
		await sheets()
	if what in ["all", "shots"]:
		await shots()
	if what in ["all", "video"]:
		await video()
	quit()


# ------------------------------------------------------------------ blueprint
func yawed(b: Dictionary, tag: String) -> Dictionary:
	var c: Dictionary = b.duplicate(true)
	var r: Dictionary = c["rooms"][0]
	r["x"] = float(r["w"])
	r["z"] = float(r["d"])
	r["yaw"] = 180.0
	c["name"] = String(b["name"]) + " " + tag
	return c


func save_sheet(sh: Dictionary, fname: String) -> void:
	var px := Blueprint.png_size(sh)
	var vp := SubViewport.new()
	vp.size = px
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var v := BlueprintView.new()
	v.sheet = sh
	v.ppm = 300.0 / 25.4
	v.size = Vector2(px)
	vp.add_child(v)
	root.add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	img.save_png("%s/%s.png" % [outdir, fname])
	var f := FileAccess.open("%s/%s.svg" % [outdir, fname], FileAccess.WRITE)
	f.store_string(Blueprint.to_svg(sh))
	f.close()
	print("sheet ", fname, " ", sh["paper"], " 1:", sh["denom"], " ents ", sh["ents"].size())


func section_sheet(b: Dictionary, pick: Dictionary) -> Dictionary:
	var paper: String = pick["paper"]
	var denom := float(pick["denom"])
	var P := func(z: float, y: float) -> Vector2:
		return Vector2(z / denom, -y / denom)
	var ents := []
	ents.append(Blueprint._line(P.call(-1200.0, -102.0), P.call(8820.0, -102.0), "ground"))
	for m in d["members"]:
		var bb: Array = m["box"]
		if float(bb[0]) > XC + 0.5 or float(bb[3]) < XC - 0.5:
			continue
		var k: String = m["kind"]
		if k in ["ground", "window", "door", "idoor", "siding", "wall_sheathing"]:
			continue
		var cls := "roof" if k in ["roof_sheathing", "shingle"] else "wall"
		var pts := []
		if m.has("poly"):
			for p in m["poly"]:
				pts.append(P.call(float(p[0]), float(p[1])))
		else:
			var z0 := float(bb[2])
			var z1 := float(bb[5])
			var y0 := float(bb[1])
			var y1 := float(bb[4])
			pts = [P.call(z0, y0), P.call(z1, y0), P.call(z1, y1), P.call(z0, y1)]
		ents.append(Blueprint._poly(pts, cls, {"member": String(m["name"])}))
	var tx := 2.5
	var notes := [[200.0, 1200.0, "2x4 studs @ 16 in o.c., single bottom plate (PT) + double top plate"], [1500.0, 2850.0, "2x8 ceiling joists @ 16 in o.c. (rafter ties)"],
		[-1100.0, 3750.0, "2x10 rafters @ 24 in o.c., 4:12"], [2900.0, 4250.0, "2x12 ridge board"], [200.0, -450.0, "4 in slab on grade"], [4300.0, 1700.0, "(cut passes the 36 in cased opening in the hall wall: 2-2x8 header)"]]
	for n in notes:
		ents.append(Blueprint._text(P.call(float(n[0]), float(n[1])), String(n[2]), tx, "l", "text"))
	ents.append_array(Blueprint._dim(P.call(0.0, -102.0), P.call(7620.0, -102.0), Vector2(0, 1), 14.0, "%.2f" % 7.62, {"kind": "overall", "axis": "z"}))
	ents.append_array(Blueprint._dim(P.call(0.0, 0.0), P.call(0.0, 2467.0), Vector2(-1, 0), 14.0, "%.3f" % 2.467, {"kind": "wall", "axis": "y"}))
	ents.append_array(Blueprint._dim(P.call(7620.0, 0.0), P.call(7620.0, 3966.0), Vector2(1, 0), 14.0, "%.2f" % 3.97, {"kind": "ridge", "axis": "y"}))
	var area := Blueprint._area(paper)
	var bb2 := Blueprint._bounds(ents)
	ents = Blueprint._shift(ents, area.get_center() - bb2.get_center())
	var bd := b.duplicate(true)
	bd["name"] = String(b["name"]) + " section A-A"
	ents.append_array(Blueprint._frame(bd, "Front", paper, int(denom), 6, 6))
	for e in ents:
		if String(e.get("t", "")) == "text" and String(e["s"]) == "Front elevation":
			e["s"] = "Section A-A (transverse)"
	var sz := Blueprint.paper_size(paper)
	return {"paper": paper, "w": sz.x, "h": sz.y, "denom": int(denom), "k": 1000.0 / denom, "tab": "Section", "title": "Section A-A", "name": bd["name"], "ents": ents, "area": area}


## sheet 7: the HouseCheck report, one line per member, printed on the paper (CH1c)
func structure_sheet(b: Dictionary, pick: Dictionary) -> Dictionary:
	var paper: String = pick["paper"]
	var denom := int(pick["denom"])
	var mj = JSON.parse_string(FileAccess.get_file_as_string("res://out/ch1/members.json"))
	var lines := Ch1House.run(mj)
	var h07 := Ch1House.from_members(mj)
	var st07: Dictionary = h07.get("site", {})
	var ents := []
	var y := 0.0
	var tx := 2.8
	var nfail := 0
	var nunv := 0
	var tfail := 0
	var tunv := 0
	for l in lines:
		tfail += 0 if l["pass"] else 1
		tunv += 1 if String(l["text"]).contains("UNVERIFIED") else 0
	if not st07.is_empty():
		ents.append(Blueprint._text(Vector2(0, y), "CODE: IRC 2021 (ICC International Residential Code), tables read from mirrors. Jurisdiction: " + String(st07["edition"]), 2.6, "l", "text"))
		y += 4.6
		ents.append(Blueprint._text(Vector2(0, y), "SITE: %s  lat %.4f lon %.4f  zip %s  |  Vult %d mph  exposure %s  soil class %s  ground snow %s psf  SDC %s" % [st07["name"], st07["lat"], st07["lon"], st07["zip"], int(st07["wind_mph"]), st07["exposure"], st07["soil_class"], HouseCheck.g(float(st07["ground_snow_psf"])), st07["sdc"]], 2.6, "l", "text"))
		y += 4.6
		ents.append(Blueprint._text(Vector2(0, y), "SITE VALUES: " + String(st07["source"]), 2.2, "l", "text"))
		y += 6.0
	for l in lines:
		if ["fastener", "sheathing_nail", "birdsmouth", "anchorage"].has(String(l["kind"])):
			continue      # sheet 08
		var fp := ""
		var parts := String(l["text"]).split(" | ")
		var tail := String(parts[parts.size() - 1])
		if String(l["kind"]) == "site":
			tail = String(parts[3])
		if tail.contains("first principles"):
			parts = PackedStringArray(String(l["text"]).split(" | first principles"))
			tail = String(String(parts[0]).split(" | ")[-1])
			fp = " | physics " + ("agrees" if bool(l.get("agree", true)) else "DISAGREES")
		var unv := " [UNVERIFIED]" if String(l["text"]).contains("UNVERIFIED") else ""
		nunv += 1 if unv != "" else 0
		nfail += 0 if l["pass"] else 1
		ents.append(Blueprint._text(Vector2(0, y), "%s  %s: %s%s%s" % ["PASS" if l["pass"] else "FAIL", l["member"], tail, fp, unv], tx, "l", "text"))
		y += 4.5
	y += 3.0
	ents.append(Blueprint._text(Vector2(0, y), "RESULT (sheets 07 + 08): %d lines, %d FAIL, %d PASS, %d marked UNVERIFIED (a table cell, site value or rule that could not be read)" % [lines.size(), tfail, lines.size() - tfail, tunv], 3.2, "l", "text"))
	y += 7.0
	ents.append(Blueprint._text(Vector2(0, y), "Tables: " + HouseCheck.TABLES_SOURCE, 2.4, "l", "text"))
	y += 5.0
	ents.append(Blueprint._text(Vector2(0, y), "Not checked by Kine: " + "; ".join(PackedStringArray(HouseCheck.NOT_CHECKED)), 2.4, "l", "text"))
	var area := Blueprint._area(paper)
	var bb2 := Blueprint._bounds(ents)
	ents = Blueprint._shift(ents, area.position + Vector2(12, 14) - bb2.position)
	var bd := b.duplicate(true)
	bd["name"] = String(b["name"]) + " structure check"
	ents.append_array(Blueprint._frame(bd, "Front", paper, denom, 7, 8))
	for e in ents:
		if String(e.get("t", "")) == "text" and String(e["s"]) == "Front elevation":
			e["s"] = "Structure check (IRC 2021)"
	var sz := Blueprint.paper_size(paper)
	return {"paper": paper, "w": sz.x, "h": sz.y, "denom": denom, "k": 1000.0 / denom, "tab": "Structure", "title": "Structure check", "name": bd["name"], "ents": ents, "area": area}


## sheet 8: connections + nailing table (Table R602.3(1) rows against what the drawing calls out) and two details at 1:5: the foundation section and the eave connection (CH1d)
func connection_sheet(b: Dictionary, pick: Dictionary) -> Dictionary:
	var paper: String = pick["paper"]
	var mj = JSON.parse_string(FileAccess.get_file_as_string("res://out/ch1/members.json"))
	var lines := Ch1House.run(mj)
	var h := Ch1House.from_members(mj)
	var tab := []
	var y := 0.0
	tab.append(Blueprint._text(Vector2(0, y), "CONNECTIONS AND NAILING  -  IRC 2021 Table R602.3(1) row against what this drawing calls out", 3.6, "l", "text"))
	y += 7.0
	for l in lines:
		if not ["fastener", "sheathing_nail", "birdsmouth", "anchorage", "uplift"].has(String(l["kind"])):
			continue
		var parts := String(l["text"]).split(" | ")
		var words := String(parts[parts.size() - 1])
		var unv := "  [UNVERIFIED]" if String(l["text"]).contains("UNVERIFIED") else ""
		tab.append(Blueprint._text(Vector2(0, y), "%s  %s: %s%s" % ["PASS" if l["pass"] else "FAIL", l["member"], words, unv], 2.5, "l", "text"))
		y += 4.2
	y += 2.0
	var st: Dictionary = h.get("site", {})
	tab.append(Blueprint._text(Vector2(0, y), "Site loads on every line: Vult %s mph, exposure %s (%s). Anchor bolts placed: %d. Rafter ties: %d H2.5A." % [str(st.get("wind_mph", "?")), st.get("exposure", "?"), st.get("name", ""), int(mj["meta"]["anchor_bolts"]["count"]), int(mj["meta"]["ties"]["count"])], 2.4, "l", "text"))
	y += 4.6
	tab.append(Blueprint._text(Vector2(0, y), "UNVERIFIED here: anchor bolt tension capacity (ACI 318 hand calc), toenail capacity, Fc-perp, Table R602.3(3) wind cell for 7/16 OSB, and the site values marked on sheet 07.", 2.4, "l", "text"))
	var area := Blueprint._area(paper)
	var tb := Blueprint._bounds(tab)
	tab = Blueprint._shift(tab, area.position + Vector2(0, 2) - tb.position)
	var top := area.position.y + 2 + tb.size.y + 14.0
	# detail A: foundation section at 1:10 (model mm, y up -> paper mm / 5, y down)
	var k := 10.0
	var P := func(z: float, yy: float) -> Vector2:
		return Vector2(z / k, -yy / k)
	var A := []
	A.append(Blueprint._poly([P.call(-600, -102), P.call(0, -102), P.call(0, -305), P.call(305, -305), P.call(305, -102), P.call(900, -102), P.call(900, 0), P.call(0, 0), P.call(0, -102)], "roof"))
	A.append(Blueprint._poly([P.call(0, 0), P.call(89, 0), P.call(89, 38), P.call(0, 38)], "elev-wall"))
	A.append(Blueprint._poly([P.call(0, 38), P.call(89, 38), P.call(89, 300), P.call(0, 300)], "elev-wall"))
	A.append(Blueprint._poly([P.call(-11, 0), P.call(0, 0), P.call(0, 300), P.call(-11, 300)], "elev-door"))
	A.append(Blueprint._poly([P.call(-30, 0), P.call(-11, 0), P.call(-11, 300), P.call(-30, 300)], "elev-wall"))
	A.append(Blueprint._poly([P.call(38.2, -178), P.call(50.8, -178), P.call(50.8, 55), P.call(38.2, 55)], "wall"))
	A.append(Blueprint._poly([P.call(28, 38), P.call(61, 38), P.call(61, 50), P.call(28, 50)], "wall"))
	A.append(Blueprint._line(P.call(-600, -102), P.call(0, -102), "ground"))
	var ax := 1000.0
	var lab := [["1/2 in A307 anchor bolt, 7 in embed (R403.1.6), 68 in o.c. max, 9 in from each plate end", P.call(44, -120), P.call(ax, -120)], ["2x4 pressure-treated bottom plate", P.call(60, 18), P.call(ax, 18)],
		["2x4 stud: 4-8d box toe nails to the plate (Table R602.3(1))", P.call(70, 150), P.call(ax, 150)], ["7/16 OSB, 6d common 6 in edges / 12 in field", P.call(-5, 250), P.call(ax, 250)],
		["4 in slab on grade", P.call(500, -50), P.call(ax, -50)], ["footing 12 x 8 in (Table R403.1(1), 1500 psf soil)", P.call(150, -230), P.call(ax, -230)]]
	for t in lab:
		A.append(Blueprint._line(t[1], t[2] + Vector2(-2, 0), "leader"))
		A.append(Blueprint._text(t[2] + Vector2(0, 0.8), String(t[0]), 2.5, "l", "callout-text"))
	A.append(Blueprint._text(P.call(-600, 460), "A  FOUNDATION SECTION AT THE WALL  1:10", 3.2, "l", "text"))
	var ab := Blueprint._bounds(A)
	A = Blueprint._shift(A, Vector2(area.position.x, top) - ab.position)
	# detail B: eave connection at 1:10, the heel of a rafter (clipped from its own sketch polygon), double top plate, ceiling joist, H2.5A
	var B := []
	var raf: Dictionary = {}
	for m in d["members"]:
		if String(m["kind"]) == "rafter" and m.has("poly") and m["poly"] != null:
			raf = m
			break
	var pts := []
	for q in raf["poly"]:
		pts.append(Vector2(float(q[0]), float(q[1])))
	var cl := Ch1House.clip(pts, [Vector2(-420, 2300), Vector2(620, 2300), Vector2(620, 2750), Vector2(-420, 2750)])
	var rp := []
	for q in cl:
		rp.append(P.call(q.x, q.y))
	B.append(Blueprint._poly(rp, "elev-wall"))
	B.append(Blueprint._poly([P.call(0, 2353), P.call(89, 2353), P.call(89, 2391), P.call(0, 2391)], "elev-wall"))
	B.append(Blueprint._poly([P.call(0, 2391), P.call(89, 2391), P.call(89, 2429), P.call(0, 2429)], "elev-wall"))
	B.append(Blueprint._poly([P.call(0, 2429), P.call(89, 2429), P.call(89, 2467), P.call(0, 2467)], "elev-wall"))
	B.append(Blueprint._poly([P.call(0, 2300), P.call(89, 2300), P.call(89, 2353), P.call(0, 2353)], "elev-wall"))
	B.append(Blueprint._poly([P.call(-11, 2300), P.call(0, 2300), P.call(0, 2467), P.call(-11, 2467)], "elev-door"))
	B.append(Blueprint._poly([P.call(95, 2467), P.call(620, 2467), P.call(620, 2651), P.call(95, 2651)], "elev-wall"))
	B.append(Blueprint._poly([P.call(-8, 2440), P.call(-8, 2515), P.call(2, 2515), P.call(2, 2440)], "wall"))
	var bx := 1000.0
	var labb := [["H2.5A hurricane tie at every rafter: rated 625 lb, uplift 307 lb at 130 mph (Table R802.11)", P.call(-8, 2480), P.call(bx, 2400)],
		["rafter 2x10 @ 24 in: 3-16d box toe nails to the plate (2 + 1), Table R602.3(1)", P.call(150, 2660), P.call(bx, 2680)],
		["birdsmouth seat 1.17 in deep in 9.25 in (max 1/4 = 2.31 in, R802.7.1 -> R502.8.1), 3.5 in bearing (R802.6)", P.call(40, 2440), P.call(bx, 2470)],
		["double top plate: 16d common at 16 in o.c. (plate to plate)", P.call(80, 2410), P.call(bx, 2540)],
		["ceiling joist 2x8: 4-8d box toe nails to the plate", P.call(300, 2560), P.call(bx, 2610)], ["stud: 4-8d box toe nails to the plate", P.call(60, 2330), P.call(bx, 2330)]]
	for t in labb:
		B.append(Blueprint._line(t[1], t[2] + Vector2(-2, 0), "leader"))
		B.append(Blueprint._text(t[2] + Vector2(0, 0.8), String(t[0]), 2.5, "l", "callout-text"))
	B.append(Blueprint._text(P.call(-420, 2800), "B  EAVE CONNECTION, HEEL OF THE RAFTER  1:10", 3.2, "l", "text"))
	var bb2 := Blueprint._bounds(B)
	B = Blueprint._shift(B, Vector2(area.position.x, top + ab.size.y + 12.0) - bb2.position)
	var ents := tab + A + B
	var bd := b.duplicate(true)
	bd["name"] = String(b["name"]) + " connections"
	ents.append_array(Blueprint._frame(bd, "Front", paper, 10, 8, 8))
	for e in ents:
		if String(e.get("t", "")) == "text" and String(e["s"]) == "Front elevation":
			e["s"] = "Connections, nailing, foundation (IRC 2021)"
	var sz := Blueprint.paper_size(paper)
	return {"paper": paper, "w": sz.x, "h": sz.y, "denom": 10, "k": 100.0, "tab": "Connections", "title": "Connections", "name": bd["name"], "ents": ents, "area": area}


func sheets() -> void:
	var b: Dictionary = d["building"]
	var pick := Blueprint.choose(b)
	print("pick ", pick)
	var bb: Dictionary = b.duplicate(true)
	var s1 := Blueprint.sheet(bb, "Floor 1", pick)
	print("sheet made ", s1.size())
	await save_sheet(s1, "01_plan")
	await save_sheet(Blueprint.sheet(bb, "Front", pick), "02_front_elevation")
	await save_sheet(Blueprint.sheet(bb, "Side", pick), "03_right_elevation")
	var by := yawed(b, "(rear)")
	await save_sheet(Blueprint.sheet(by, "Front", pick), "04_rear_elevation")
	var bl := yawed(b, "(left)")
	await save_sheet(Blueprint.sheet(bl, "Side", pick), "05_left_elevation")
	await save_sheet(section_sheet(b, pick), "06_section")
	await save_sheet(structure_sheet(b, pick), "07_structure")
	await save_sheet(connection_sheet(b, pick), "08_connections")


# ------------------------------------------------------------------ 3D
var vp: SubViewport
var cam: Camera3D
var mi: MeshInstance3D
var lab: Label
var lab2: Label


func make_view(size: Vector2i) -> void:
	vp = SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var world := Node3D.new()
	vp.add_child(world)
	mi = MeshInstance3D.new()
	world.add_child(mi)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -40, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	world.add_child(sun)
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.36, 0.55, 0.85)
	psm.sky_horizon_color = Color(0.72, 0.82, 0.92)
	psm.ground_horizon_color = Color(0.72, 0.82, 0.92)
	psm.ground_bottom_color = Color(0.30, 0.42, 0.26)
	sky.sky_material = psm
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	cam = Camera3D.new()
	cam.fov = 38.0
	cam.near = 0.1
	cam.far = 400.0
	world.add_child(cam)
	cam.current = true
	var cl := CanvasLayer.new()
	vp.add_child(cl)
	lab = Label.new()
	lab.position = Vector2(24, 18)
	lab.add_theme_font_size_override("font_size", 34)
	lab.add_theme_color_override("font_color", Color.WHITE)
	lab.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lab.add_theme_constant_override("outline_size", 8)
	cl.add_child(lab)
	lab2 = Label.new()
	lab2.position = Vector2(24, size.y - 52)
	lab2.add_theme_font_size_override("font_size", 22)
	lab2.add_theme_color_override("font_color", Color.WHITE)
	lab2.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lab2.add_theme_constant_override("outline_size", 6)
	cl.add_child(lab2)
	root.add_child(vp)


func show_prefix(n: int) -> void:
	var rec: Dictionary = (d["part"] as Dictionary).duplicate(true)
	rec["features"] = (rec["features"] as Array).slice(0, n)
	var res := Part.replay(rec)
	var mesh: ArrayMesh = res["mesh"]
	if mesh == null:
		return
	Part.paint(mesh, res["looks"])
	mi.mesh = mesh


func aim(az_deg: float, el_deg: float, dist: float) -> void:
	var tgt := Vector3(4.877, 1.4, 3.81)
	var az := deg_to_rad(az_deg)
	var el := deg_to_rad(el_deg)
	var off := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el)) * dist   # az 0 = from the street (-Z side)
	cam.look_at_from_position(tgt + off, tgt, Vector3.UP)


func grab(path: String, jpg := false) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if jpg:
		img.save_jpg(path, 0.9)
	else:
		img.save_png(path)


func shots() -> void:
	make_view(Vector2i(1600, 900))
	var n := (d["part"]["features"] as Array).size()
	show_prefix(n)
	lab.text = "Levitt Ranch 1949, one storey, 32 x 25 ft"
	lab2.text = ""
	aim(-35.0, 24.0, 21.0)
	await grab(outdir + "/front_3q.png")
	aim(145.0, 24.0, 21.0)
	await grab(outdir + "/rear_3q.png")
	# the framing alone: stop before the wall sheathing
	var stages: Array = d["stages"]
	var fr := 0
	for s in stages:
		if s["name"] == "Rafters and ridge":
			fr = int(s["upto"])
	show_prefix(fr)
	lab.text = "Framing only"
	aim(-35.0, 28.0, 17.0)
	await grab(outdir + "/framing_3q.png")
	# the same framing from straight above: the front slope and the back slope meet at the ridge, they do not cross
	aim(0.0, 89.0, 17.0)
	cam.look_at_from_position(cam.position, Vector3(4.877, 1.4, 3.81), Vector3(0, 0, -1))
	lab.text = "Framing from above"
	await grab(outdir + "/framing_top.png")
	print("shots done")


func video() -> void:
	make_view(Vector2i(1280, 720))
	var feats: Array = d["part"]["features"]
	var stages: Array = d["stages"]
	var steps := {"Slab": 2, "Sill plates": 3, "Wall framing": 22, "Top plates": 4, "Ceiling joists": 3, "Gable studs": 4, "Rafters and ridge": 6, "Wall sheathing": 6,
		"Roof sheathing": 4, "Shingles": 3, "Siding": 4, "Windows and doors": 5}
	var shown := {"prim": 1, "extrude": 1, "pattern": 1}
	var plan := []   # [upto, stage name]
	var prev := 0
	for s in stages:
		var up: int = int(s["upto"])
		var cuts := []
		for i in range(prev, up):
			if shown.has(String(feats[i]["t"])):
				cuts.append(i + 2 if i + 1 < feats.size() and String(feats[i + 1]["t"]) == "appear" else i + 1)
		var m: int = int(steps.get(s["name"], 3))
		for j in m:
			var idx := mini(cuts.size() - 1, int(round(float(j + 1) / float(m) * cuts.size())) - 1)
			plan.append([cuts[maxi(idx, 0)], s["name"]])
		prev = up
	plan.append([feats.size(), "Windows and doors"])
	var fps := 24
	var hold := 13
	var frame := 0
	var total := plan.size() * hold
	DirAccess.make_dir_recursive_absolute(outdir + "/frames")
	for si in plan.size():
		show_prefix(int(plan[si][0]))
		lab.text = "%s" % plan[si][1]
		lab2.text = "Levitt Ranch 1949 on Kine   step %d / %d" % [si + 1, plan.size()]
		for h in hold:
			var u := float(frame) / float(total)
			aim(-40.0 + 230.0 * u, 26.0 - 4.0 * u, 20.0 - 2.0 * u)
			await grab("%s/frames/f_%04d.jpg" % [outdir, frame], true)
			frame += 1
	# a last hold on the front
	for h in 36:
		aim(-35.0, 22.0, 18.0)
		await grab("%s/frames/f_%04d.jpg" % [outdir, frame], true)
		frame += 1
	# the end card: the structure check result, held 3 s
	var mj = JSON.parse_string(FileAccess.get_file_as_string("res://out/ch1/members.json"))
	var lines := Ch1House.run(mj)
	var nf := 0
	var nu := 0
	for l in lines:
		nf += 0 if l["pass"] else 1
		nu += 1 if String(l["text"]).contains("UNVERIFIED") else 0
	var show := "STRUCTURE CHECK (IRC 2021)
%d lines   %d PASS   %d FAIL
%d marked UNVERIFIED, listed on sheet 07
rafters, joists, headers, studs, bracing, ties, footing" % [lines.size(), lines.size() - nf, nf, nu]
	mi.visible = false
	lab.text = ""
	lab2.text = ""
	var card := ColorRect.new()
	card.color = Color(0.07, 0.09, 0.12) if nf == 0 else Color(0.25, 0.05, 0.05)
	card.size = Vector2(1280, 720)
	vp.add_child(card)
	var cl2 := Label.new()
	cl2.text = show
	cl2.position = Vector2(90, 220)
	cl2.add_theme_font_size_override("font_size", 44)
	cl2.add_theme_color_override("font_color", Color(0.55, 0.95, 0.6) if nf == 0 else Color(1, 0.5, 0.5))
	vp.add_child(cl2)
	for h in 72:
		await grab("%s/frames/f_%04d.jpg" % [outdir, frame], true)
		frame += 1
	print("frames ", frame)
