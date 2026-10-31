extends SceneTree
## p083favourites (Friday plan item 83): a Favourites category (the last chip of the Parts library), its page is the row. It lists the parts used lately
## (screw sizes and the Gear), and a star keeps one as a favourite (favourites come first). A chip drops that part on the floor
## again (one undo step). A beginner walk with real clicks on the live Easy Part, from the BUILDING card. Measured from the BUILT result
## (mesh mm, solid count, undo steps) and from the favourites file on disk, never from the code's own variables. Bars are written before the code.
##   1 ROW       Parts open: the Favourites row is on the 1280 x 720 screen, empty ('none yet'), and its star is greyed (nothing on the floor)
##   2 USED      Screws, M4 x 16: ISO built, ONE undo step; the row now shows one chip, 'M4 x 16'; the star is on
##   3 STAR      press the star: a favourite (the chip has a star icon, the file on disk lists M4 x 16), NO undo step (a star is a list, not a model step)
##   4 GEAR      Gears, the Gear chip: one solid, tip diameter 64 mm (+- 0.6), ONE undo step; the row shows the favourite first, then Gear
##   5 PICK      the M4 x 16 chip: ISO built again, ONE undo step; the Gear is gone from the floor
##   6 UNSTAR    the star again: the file lists no favourite, the file keeps both parts as recent (M4 x 16 and Gear), no undo step
##   7 WORDS     no key name in the row, the star, the status line or the hint
## Shots: C:/Temp/claude/p083favourites/row.png (the row with a favourite), gear.png (the Gear and the two chips)
const SHOT := "C:/Temp/claude/p083favourites"
const DIRT := "user://p083favourites_test"
const FAV_FILE := "user://easy_part_favs.json"
const BAD_WORDS := ["ctrl", "shift", "alt+", "esc", "enter", "tab ", "delete", "backspace", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12", "spacebar", "return key"]
## ISO 4762 socket head: [head diameter, head height] in mm, by the nominal size (the shank is the nominal size, plain)
const ISO := {3: [5.5, 3.0], 4: [7.0, 4.0], 5: [8.5, 5.0], 6: [10.0, 6.0]}
var fails := 0
var m: Node
var pu: PartUI
var ep


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


func ev_move(p: Vector2, held := true) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


## a real click on a visible control; a missing or greyed control is reported by the bar that needs it (no crash)
func click_ctl(c: Control) -> bool:
	if c == null or not c.is_visible_in_tree() or (c is BaseButton and (c as BaseButton).disabled):
		return false
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)
	return true


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func lib(cat: String) -> Button:
	return root.find_child("easypart_lib_" + cat, true, false) as Button


func gear_chip() -> Button:
	return root.find_child("easypart_chip_gear", true, false) as Button


func chip(d: int, L: int) -> Button:
	return root.find_child("easypart_screw_M%d_%d" % [d, L], true, false) as Button


func row() -> HFlowContainer:
	return root.find_child("easypart_fav_row", true, false) as HFlowContainer


func star() -> Button:
	return root.find_child("easypart_fav_star", true, false) as Button


## the favourite chips in the row, in order (the star and the label are not chips)
func row_chips() -> Array:
	var out := []
	if row() == null:
		return out
	for c in row().get_children():
		if c is Button and String(c.name).begins_with("easypart_fav_") and c.name != "easypart_fav_star":
			out.append(c)
	return out


func chip_text(i: int) -> String:
	var ch := row_chips()
	return (ch[i] as Button).text if i < ch.size() else ""


## the favourites file on disk: {"fav": [...], "recent": [...]} read back; empty lists when it is not there
func disk() -> Dictionary:
	if not FileAccess.file_exists(FAV_FILE):
		return {"fav": [], "recent": []}
	var d = JSON.parse_string(FileAccess.get_file_as_string(FAV_FILE))
	if not (d is Dictionary):
		return {"fav": [], "recent": []}
	return {"fav": Array((d as Dictionary).get("fav", [])), "recent": Array((d as Dictionary).get("recent", []))}


## the built gear's tip diameter (mm): the thin axis of the built box is the gear's axis; the tip is the largest radius round it
func gear_tip_d() -> float:
	var faces: Array = Part.body_faces(m.S.part)
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	var all: Array = []
	for f in faces:
		var arr: PackedVector3Array = f
		for v in arr:
			var p := v * 1000.0
			all.append(p)
			lo = lo.min(p)
			hi = hi.max(p)
	if all.is_empty():
		return 0.0
	var sz := hi - lo
	var ax := 1
	if sz.x <= sz.y and sz.x <= sz.z:
		ax = 0
	elif sz.z <= sz.x and sz.z <= sz.y:
		ax = 2
	var c := (lo + hi) * 0.5
	var pa := [0, 1, 2]
	pa.erase(ax)
	var rmax := 0.0
	for p in all:
		rmax = maxf(rmax, Vector2(p[pa[0]] - c[pa[0]], p[pa[1]] - c[pa[1]]).length())
	return 2.0 * rmax


## the built result, read from the mesh (mm) and the kernel volume (mm3)
func geom() -> Dictionary:
	var faces: Array = Part.body_faces(m.S.part)
	var bins := {}
	var ymin := 1e9
	var rmax := 0.0
	for f in faces:
		var arr: PackedVector3Array = f
		for v in arr:
			var p := v * 1000.0
			ymin = minf(ymin, p.y)
			var r := Vector2(p.x, p.z).length()
			rmax = maxf(rmax, r)
			var key := int(roundf(p.y * 10.0))
			bins[key] = maxf(float(bins.get(key, 0.0)), r)
	if bins.is_empty():
		return {}
	var rs := 1e9
	var ymax := -1e9
	for k in bins:
		rs = minf(rs, float(bins[k]))
		ymax = maxf(ymax, float(k) / 10.0)
	var lo := 1e9
	for k in bins:
		if float(bins[k]) > rs + 0.5:
			lo = minf(lo, float(k) / 10.0)
	return {"ymin": ymin, "ymax": ymax, "d": 2.0 * rs, "D": 2.0 * rmax, "L": lo, "k": ymax - lo, "vol": float(pu.res.get("volume", 0.0)) * 1e9, "bodies": int(pu.res.get("bodies", 0))}


## "" when the built screw is the ISO size d x L (mm); else what it measured
func is_iso(d: int, L: int) -> String:
	var g := geom()
	if g.is_empty():
		return "no geometry"
	var D: float = ISO[d][0]
	var k: float = ISO[d][1]
	var vol := PI / 4.0 * (float(d * d) * float(L) + D * D * k)
	var good: bool = absf(float(g["d"]) - d) <= 0.1 and absf(float(g["D"]) - D) <= 0.1 and absf(float(g["k"]) - k) <= 0.1
	good = good and absf(float(g["L"]) - L) <= 0.1 and absf(float(g["ymin"])) <= 0.05 and int(g["bodies"]) == 1 and absf(float(g["vol"]) - vol) <= 0.01 * vol
	if good:
		return ""
	return "head %.2f x %.2f, shank %.2f x %.2f, lowest %.2f, %d solid, %.1f vs %.1f mm3" % [float(g["D"]), float(g["k"]), float(g["d"]), float(g["L"]), float(g["ymin"]), int(g["bodies"]), float(g["vol"]), vol]


func _init() -> void:
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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	# a clean favourites file for this walk (the test's own user:// file)
	if FileAccess.file_exists(FAV_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(FAV_FILE))
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	m.bld.part.set_on(false)
	m.S.part = {}
	await idle(8)
	if not Part.available():
		print("FAIL: no KineCAD DLL, the favourites cannot run")
		quit(1)
		return
	pu = m.bld.part
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	ep = pu.ep
	var vp := Rect2(Vector2.ZERO, Vector2(1280, 720))

	# 1 ROW: the Parts page has the Favourites row, empty, and the star greyed
	var pb := root.find_child("easypart_chip_parts", true, false) as Button
	await click_ctl(pb)
	await click_ctl(lib("Favourites"))
	var rw := row()
	var on_screen := rw != null and rw.is_visible_in_tree() and vp.encloses(Rect2(rw.global_position, rw.size))
	var st := star()
	var st_grey := st != null and st.disabled
	var empty_says := rw != null and root.find_child("easypart_fav_label", true, false) is Label and String((root.find_child("easypart_fav_label", true, false) as Label).text).contains("none yet")
	ok(on_screen and row_chips().is_empty() and st_grey and empty_says, "1 the Favourites row is on the 1280 x 720 screen (%s), empty (%d chips), says 'none yet' (%s), the star greyed (%s)" % [str(on_screen), row_chips().size(), str(empty_says), str(st_grey)])

	# 2 USED: Screws, M4 x 16: ISO built, one undo step; the row shows one chip; the star is on
	await click_ctl(lib("Screws"))
	var ub0: int = m.undo.size()
	await click_ctl(chip(4, 16))
	var e := is_iso(4, 16)
	var one_chip := row_chips().size() == 1 and chip_text(0) == "M4 x 16"
	ok(e == "" and m.undo.size() == ub0 + 1 and one_chip and st != null and not st.disabled, "2 Screws, M4 x 16: ISO built [%s], one undo step (%d -> %d), the row shows one chip 'M4 x 16' (%d chips, first '%s'), star on" % [e, ub0, m.undo.size(), row_chips().size(), chip_text(0)])
	await click_ctl(lib("Favourites"))
	await shot("row")

	# 3 STAR: the star makes M4 x 16 a favourite: a star icon on its chip, the file on disk lists it, no undo step
	var ub1: int = m.undo.size()
	await click_ctl(star())
	var fav_chip: Button = row_chips()[0] if not row_chips().is_empty() else null
	var starred := fav_chip != null and fav_chip.icon != null
	var fd := disk()
	ok(starred and fd["fav"] == ["M4 x 16"] and m.undo.size() == ub1, "3 the star: the chip has a star icon (%s), the file on disk lists %s, no undo step (%d -> %d)" % [str(starred), str(fd["fav"]), ub1, m.undo.size()])

	# 4 GEAR: Gears, then the Gear chip: one solid, tip 64 mm, one undo step; the favourite comes first, then Gear
	await click_ctl(lib("Gears"))
	var ub2: int = m.undo.size()
	await click_ctl(gear_chip())
	var g := geom()
	var tipd := gear_tip_d()
	var gear_ok := not g.is_empty() and int(g["bodies"]) == 1 and absf(tipd - 64.0) <= 0.6
	var order_ok := row_chips().size() == 2 and chip_text(0) == "M4 x 16" and chip_text(1) == "Gear"
	ok(gear_ok and m.undo.size() == ub2 + 1 and order_ok, "4 Gear: one undo step (%d -> %d), %d solid, tip diameter %.2f mm (want 64 +- 0.6); row order %s" % [ub2, m.undo.size(), int(g.get("bodies", 0)), tipd, str(chip_text(0)) + ", " + chip_text(1)])
	await shot("gear")

	# 5 PICK: the M4 x 16 chip puts the screw back on the floor (the gear goes): ISO, one undo step
	await click_ctl(lib("Favourites"))
	var ub3: int = m.undo.size()
	await click_ctl(row_chips()[0])
	var e2 := is_iso(4, 16)
	ok(e2 == "" and m.undo.size() == ub3 + 1, "5 the favourite M4 x 16 chip: ISO built [%s], one undo step (%d -> %d)" % [e2, ub3, m.undo.size()])

	# 6 UNSTAR: the star again takes the favourite off; the file keeps both parts as recent; no undo step
	var ub4: int = m.undo.size()
	await click_ctl(star())
	var fd2 := disk()
	var recent_ok: bool = (fd2["recent"] as Array).has("M4 x 16") and (fd2["recent"] as Array).has("Gear")
	ok((fd2["fav"] as Array).is_empty() and recent_ok and m.undo.size() == ub4, "6 unstar: the file lists no favourite (%s), recent %s, no undo step (%d -> %d)" % [str(fd2["fav"]), str(fd2["recent"]), ub4, m.undo.size()])
	await shot("unstar")

	# 7 WORDS: no key name in the row, the star, the status line or the hint
	var hit := []
	var texts := [ep.hint_l.text, ep.status_l.text]
	for c in row_chips():
		texts.append((c as Button).text)
	if star() != null:
		texts.append(star().text)
	if root.find_child("easypart_fav_label", true, false) is Label:
		texts.append((root.find_child("easypart_fav_label", true, false) as Label).text)
	for t in texts:
		for w in BAD_WORDS:
			if String(t).to_lower().contains(w):
				hit.append("%s in [%s]" % [w, t])
	ok(hit.is_empty(), "7 no key name in the row, the star, the status line or the hint %s" % str(hit))
	print("p083favourites: %d fail" % fails)
	quit(1 if fails > 0 else 0)
