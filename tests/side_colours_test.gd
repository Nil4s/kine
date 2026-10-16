## godot --headless --path . -s tests/side_colours_test.gd     (GATES EE2, UPGRADES #42)
## LEFT AND RIGHT TELL APART: the body at rest. Every joint dot: his left (_l) red, his right (_r) blue, the middle
## dark; every _l dot stands at +x (the side the floor's "X his left" marks), its _r twin at the mirror place (x
## negated, y and z the same, within 1 mm). The selected part's name in the right panel: a left part's in red, a right
## part's in blue, a middle part's in the theme's own colour (no override), a weapon's too; in both themes the coloured
## name reads against the panel (contrast 3:1 or more, the large-text bar) and the dots keep their colours.
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func dot_bad() -> Array:
	var bad := []
	for j in m.dots:
		var col: Color = (m.dots[j].material_override as StandardMaterial3D).albedo_color
		var want: Color = Color(0.9, 0.3, 0.3) if j.ends_with("_l") else (Color(0.3, 0.5, 0.95) if j.ends_with("_r") else Color(0.15, 0.15, 0.18))
		if not col.is_equal_approx(want):
			bad.append([j, col])
	return bad


func title_of(j: String) -> Array:
	m.sel = j
	m._refresh()
	await idle(2)
	var t: Label = m.ui_title
	return [t.has_theme_color_override("font_color"), t.get_theme_color("font_color")]


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	m._new_scene()
	m._reset_all()
	m._refresh()
	await idle(2)
	var counts := {"l": 0, "r": 0, "mid": 0}
	for j in m.dots:
		counts["l" if j.ends_with("_l") else ("r" if j.ends_with("_r") else "mid")] += 1
	var bad := dot_bad()
	ok(bad.is_empty() and counts["l"] >= 6 and counts["l"] == counts["r"] and counts["mid"] >= 3,
		"1 the dots: %d left red, %d right blue, %d middle dark (bad: %s)" % [counts["l"], counts["r"], counts["mid"], bad])
	var mir := []
	for j in m.dots:
		if not j.ends_with("_l"):
			continue
		var tw: String = j.left(j.length() - 2) + "_r"
		var pl: Vector3 = m.dots[j].position
		var pr: Vector3 = m.dots[tw].position
		if pl.x <= 0.0 or Vector3(-pr.x, pr.y, pr.z).distance_to(pl) > 0.001:
			mir.append([j, pl, pr])
	ok(mir.is_empty(), "2 at rest every red dot stands at +x (his left, where the floor's X points) and its blue twin at its mirror place within 1 mm (bad: %s)" % [mir.slice(0, 2)])
	var res := {}
	for j in ["upperarm_l", "thigh_r", "spine_01" if m.dots.has("spine_01") else "pelvis"]:
		res[j] = await title_of(j)
	var lt: Array = res["upperarm_l"]
	var rt: Array = res["thigh_r"]
	var mt: Array = res.values()[2]
	ok(lt[0] and (lt[1] as Color).is_equal_approx(m.SIDE_L) and rt[0] and (rt[1] as Color).is_equal_approx(m.SIDE_R) and not mt[0],
		"3 the selected part's name: left upper arm red %s, right thigh blue %s, %s no override" % [lt, rt, res.keys()[2]])
	var con := {}
	for light in [false, true]:
		m._set_light(light)
		await idle(2)
		var bg := Tok.c("panel")
		con["light" if light else "dark"] = [snappedf(Tok.contrast(m.SIDE_L, bg), 0.01), snappedf(Tok.contrast(m.SIDE_R, bg), 0.01), dot_bad().is_empty()]
	m._set_light(false)
	ok(con.values().all(func(c): return c[0] >= 3.0 and c[1] >= 3.0 and c[2]),
		"4 both themes: [red name contrast, blue name contrast, dots unchanged] %s" % con)
	m.sel = "upperarm_l"
	m._refresh()
	m.sel = m.B.WEAPON[0] if m.B.wep_on else "pelvis"
	m._refresh()
	await idle(2)
	ok(not m.ui_title.has_theme_color_override("font_color"), "5 a left part, then %s selected: the side colour does not stick" % m.sel)
	print("SIDE COLOURS: %d failed" % fails)
	quit(1 if fails > 0 else 0)
