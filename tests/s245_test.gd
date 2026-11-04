extends SceneTree
## godot --path . --position 4000,4000 -s tests/s245_test.gd     (ITEM 245 AI EASE 5: look-table kinds for window back / window grid / door panel / tree / grass; needs the CAD DLL)
## Bars (written and committed before the first number was read):
##   1 TABLE    each new kind (window_back, window_grid, door_panel, tree, grass) is in KINDS, LABELS and DEFAULTS with a valid colour, and its colour differs from the "other" look
##   2 NAMES    a body called "Window back", "Window grid", "Door panel", "Tree", "Meadow blades" resolves to its kind; "Hedge" resolves as before
##   3 RENDER   a small test part per kind, top view in the final light: the mean of the middle 64x64 pixels has the hue of the spec colour (circular distance < 0.06),
##              is not grey, and differs from the "other" plaster; window_grid is darker than window_back by value 0.25 or more (bars read against their back)
##   4 OLD      the 21 old DEFAULTS hash to the origin values, KINDS starts with the old 20, and 24 old body names resolve to the kinds they did
##   5 CONTROL  a body called "Lattice" (what "Window back" resolved to on origin) fails bar 3 for window_back; "Door" fails it for door_panel
##   6 HEDGE    hedge colour is rendered in the same test and is green (hue 0.2 .. 0.45)
## Shots: C:/Users/Nick/tools/kine_workers/out/245/ (kinds.png: one row of plates, one per new kind and hedge)
var fails := 0
const SHOT := "C:/Users/Nick/tools/kine_workers/out/245"
const NEW := ["window_back", "window_grid", "door_panel", "tree", "grass"]
const NEW_NAME := {"window_back": "Window back", "window_grid": "Window grid", "door_panel": "Door panel", "tree": "Tree", "grass": "Meadow blades"}
const OLD_KINDS := ["roof", "ridge", "column", "beam", "platform", "stair", "rail", "paving", "wall", "plaque", "plaque_frame", "plaque_letters", "door", "lattice",
	"ground", "hedge", "trunk", "canopy", "wall_base", "wall_cap"]
const OLD_HASH := {"roof": 1973352517, "ridge": 578661177, "column": 3706242689, "beam": 1064655231, "platform": 2680539448, "stair": 2540047498, "rail": 1399918259,
	"paving": 3604638733, "wall": 1270735246, "plaque": 2476373882, "plaque_letters": 2434032039, "plaque_frame": 2434032039, "door": 1913016134, "lattice": 4168138810,
	"ground": 3526169535, "hedge": 1781634382, "trunk": 1547339019, "canopy": 701745620, "wall_base": 1122634611, "wall_cap": 490009849, "other": 3634030018}
const OLD_NAMES := {"Column 3": "column", "Stair rail": "rail", "Lower brackets": "beam", "Lattice": "lattice", "Window": "lattice", "Window screen": "lattice", "Door": "door",
	"Hedge": "hedge", "Trunk": "trunk", "Tree trunk": "trunk", "Canopy": "canopy", "Grass": "ground", "Lawn": "ground", "Red hall": "wall", "Wall base": "wall_base",
	"Wall cap": "wall_cap", "Plaque letters": "plaque_letters", "Plaque": "plaque", "Roof": "roof", "Platform": "platform", "Paving": "paving", "Stair": "stair",
	"Ridge beast": "ridge", "Body1": ""}
var rec := {}


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func add(t: String, f: Dictionary) -> String:
	var nf := Part.new_feature(rec, t, f)
	(rec["features"] as Array).append(nf)
	return String(nf["id"])


func plate_rec(nm: String) -> void:
	rec = Part.make("Chinese plate")
	var sk := add("sketch", {"plane": "top", "ents": [{"k": "rect", "a": [-1200.0, -1200.0], "b": [1200.0, 1200.0]}], "dims": []})
	add("extrude", {"sketch": sk, "dist": 100.0, "both": false, "op": "new"})
	add("bname", {"body": 0, "called": nm})


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
	vp.add_child(sun)
	var cam := Camera3D.new()
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


func plate(nm: String) -> Image:
	plate_rec(nm)
	var res := Part.replay(rec)
	var wd: Array = make_world(Vector2i(256, 256), 2.6)
	var vp: SubViewport = wd[0]
	var cam: Camera3D = wd[1]
	vp.add_child(part_node(res))
	cam.position = Vector3(0, 2.0, 0)
	cam.rotation_degrees = Vector3(-90, 0, 0)
	await idle(8)
	var im := vp.get_texture().get_image()
	vp.queue_free()
	return im


## [h, s, v] of the mean colour of the middle 64 x 64 pixels
func centre_hsv(im: Image) -> Array:
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var n := 0
	for y in range(96, 160):
		for x in range(96, 160):
			var c := im.get_pixel(x, y)
			r += c.r
			g += c.g
			b += c.b
			n += 1
	var cm := Color(r / n, g / n, b / n)
	return [cm.h, cm.s, cm.v]


func hue_d(a: float, b: float) -> float:
	var d := absf(a - b)
	return minf(d, 1.0 - d)


func table_bars() -> void:
	var miss := []
	for k in NEW:
		if not PieceLook.KINDS.has(k) or not PieceLook.LABELS.has(k) or not PieceLook.DEFAULTS.has(k):
			miss.append(k)
			continue
		var col := String((PieceLook.DEFAULTS[k] as Dictionary).get("color", ""))
		if not Color.html_is_valid(col) or col == String(PieceLook.DEFAULTS["other"]["color"]):
			miss.append(k + " colour " + col)
	ok(miss.is_empty(), "1 each new kind is in KINDS, LABELS, DEFAULTS with its own colour %s" % str(miss))
	var spec := PieceLook.default_spec("temple", "window_back")
	ok(not spec.is_empty() and spec != PieceLook.default_spec("temple", "other"), "1 default_spec(temple, window_back) is the named look")
	ok(PieceLook.default_spec("", "window_back").is_empty(), "1 an ordinary house (no style) still gets no default look")


func names_bars() -> void:
	var wrong := []
	for k in NEW:
		var got := PieceLook.kind_of_name(String(NEW_NAME[k]))
		if got != k:
			wrong.append("%s -> '%s'" % [NEW_NAME[k], got])
	ok(wrong.is_empty(), "2 new body names resolve to their kind %s" % str(wrong))
	ok(PieceLook.kind_of_name("Hedge") == "hedge", "2 Hedge resolves to hedge")


func old_bars() -> void:
	var bad := []
	for k in OLD_HASH:
		if JSON.stringify(PieceLook.DEFAULTS[k], "", true).hash() != int(OLD_HASH[k]):
			bad.append(k)
	ok(bad.is_empty(), "4 the 21 old DEFAULTS are byte-identical to origin %s" % str(bad))
	ok(PieceLook.KINDS.slice(0, 20) == OLD_KINDS, "4 KINDS starts with the 20 old kinds, same order")
	var wrong := []
	for nm in OLD_NAMES:
		var got := PieceLook.kind_of_name(String(nm))
		if got != String(OLD_NAMES[nm]):
			wrong.append("%s -> '%s' (was '%s')" % [nm, got, OLD_NAMES[nm]])
	ok(wrong.is_empty(), "4 %d old body names resolve to the kinds they did %s" % [OLD_NAMES.size(), str(wrong)])


func render_bars() -> void:
	var hs := {}
	var ims := {}
	var other := centre_hsv(await plate("Mystery piece"))
	for k in NEW + ["hedge"]:
		var nm: String = String(NEW_NAME[k]) if NEW_NAME.has(k) else "Hedge"
		var im: Image = await plate(nm)
		ims[k] = im
		hs[k] = centre_hsv(im)
	DirAccess.make_dir_recursive_absolute(SHOT)
	var sheet := Image.create(256 * 6, 256, false, Image.FORMAT_RGB8)
	var i := 0
	for k in NEW + ["hedge"]:
		sheet.blit_rect(ims[k], Rect2i(0, 0, 256, 256), Vector2i(i * 256, 0))
		i += 1
	sheet.save_png(SHOT + "/kinds.png")
	for k in NEW:
		if not PieceLook.DEFAULTS.has(k):
			ok(false, "3 %s has no look to render" % k)
			continue
		var want := Color(String(PieceLook.DEFAULTS[k]["color"]))
		var h: Array = hs[k]
		var dh := hue_d(float(h[0]), want.h)
		var far_other: bool = hue_d(float(h[0]), float(other[0])) > 0.02 or absf(float(h[2]) - float(other[2])) > 0.08
		ok(dh < 0.06 and float(h[1]) > 0.12 and far_other, "3 %s plate: hue %.3f vs spec %.3f (d %.3f), sat %.2f, value %.2f, differs from other plaster %s" % [k, h[0], want.h, dh, h[1], h[2], str(far_other)])
	var gv: float = float(hs["window_grid"][2])
	var bv: float = float(hs["window_back"][2])
	ok(bv - gv >= 0.25, "3 window grid value %.2f is darker than window back %.2f by >= 0.25" % [gv, bv])
	var hh: Array = hs["hedge"]
	ok(float(hh[0]) > 0.2 and float(hh[0]) < 0.45, "6 hedge plate is green: hue %.3f" % hh[0])
	# control: what the old resolution gave. The same test on a Lattice / Door plate must FAIL for the new kinds
	var lat := centre_hsv(await plate("Lattice"))
	var wbc := Color(String(PieceLook.DEFAULTS.get("window_back", PieceLook.DEFAULTS["other"])["color"]))
	ok(not (hue_d(float(lat[0]), wbc.h) < 0.06 and absf(float(lat[2]) - float(hs["window_back"][2])) < 0.1), "5 control: a Lattice plate does not pass as window back (hue %.3f value %.2f)" % [lat[0], lat[2]])
	var dr := centre_hsv(await plate("Door"))
	ok(absf(float(dr[2]) - float(hs["door_panel"][2])) > 0.05 or hue_d(float(dr[0]), float(hs["door_panel"][0])) > 0.01, "5 control: a Door plate does not pass as door panel (value %.2f vs %.2f)" % [dr[2], hs["door_panel"][2]])


func _init() -> void:
	if not Part.available():
		print("FAIL: no KineCAD DLL")
		quit(1)
		return
	var wd := Timer.new()   # watchdog: a hang ends the run
	wd.wait_time = 240.0
	wd.one_shot = true
	wd.timeout.connect(func():
		print("FAIL watchdog: s245 ran over 240 s")
		quit(2))
	root.add_child(wd)
	wd.start()
	table_bars()
	names_bars()
	old_bars()
	await render_bars()
	print("s245: %d fail" % fails)
	quit(1 if fails > 0 else 0)
