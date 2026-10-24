## godot --path . -s tests/theme_test.gd     (GATES P2, P3; needs a window)
## P2: the chrome's colours come from scripts/tok.gd. Every Color( literal left in the 2D widgets and in main's UI
##     builders is listed against an allow-list WITH ITS REASON; an unlisted one FAILS.
## P3: both palettes are readable (WCAG contrast, computed from the tokens, composited over what they sit on);
##     the VIEW tab's Light button switches everything live (labels, buttons, the 3D background, the widgets), is
##     remembered in user://poser.cfg, pushes no undo step, and switches back. The user's own setting is put back.
extends SceneTree

## file -> [substring a remaining literal line must contain, why it is not a token]
const ALLOW := {
	"scripts/timeline.gd": [
		["draw_rect(r, Color(col, 0.18))", "airborne spin box (I43): an 18 % fill of its own token colour (fail / fv_ok)"],
		["Color(0.32, 0.5, 0.82) if i % 2", "the cards' alternating block colours: content, readable white-on-colour in both"],
		["base = Color(0.95, 0.7, 0.3)", "the picked card's block: content"],
		["Color(1, 1, 1, 0.55), 1.0)", "auto-timing dashes ON a coloured block"],
		["Color(base.r, base.g, base.b, 0.35)", "hatching in the block's own colour"],
		["Color(1, 1, 1, 0.9 if sel else 0.6)", "the arrival tick ON a coloured block"],
		["Color(0, 0, 0, 0.6), 1.0)", "the hold's end ON a coloured block"],
		["Color(0, 0, 0, 0.8))", "the name's shadow ON a coloured block"],
		["size.y), Color(0, 0, 0, 0.45))", "the preview range (WW4): a see-through scrim that darkens whatever is outside the range, in both themes"],
		["Color(0.05, 0.05, 0.07) if sel else Color(1, 1, 1, 0.95)", "the name ON a coloured block"],
		["12, Color(1, 1, 1, 0.9))", "a number ON a coloured block"],
		["11, Color(1, 1, 1, 0.9))", "a narrow block's number ON the coloured block"],
		["Color(0.05, 0.05, 0.06, 0.88)", "the 'won't play' shade with its own light text: an alert"],
		["Color(1, 0.45, 0.35), 2.0)", "the hit line: an alert"],
		["Color(1, 0.75, 0.65))", "the hit text on its own dark shade"],
		["Color(1, 0.95, 0.5), 3.0)", "the hovered edge: a highlight"],
		["Color(0, 0, 0, 0.85))", "the drag readout's own dark box"],
		["13, Color(1, 0.95, 0.5))", "the drag readout's text on its own dark box"],
	],
	"scripts/ring_menu.gd": [], "scripts/red_spots.gd": [], "scripts/view_cube.gd": [], "scripts/command_search.gd": [], "scripts/browser.gd": [],
}
## main.gd: only the UI-building functions are audited (the 3D scene's materials, lights and labels are content)
const MAIN_UI := ["_theme", "_set_light", "_retheme", "_label", "_button", "_row", "_section", "_ui", "_rebuild_cards", "_draw_graph", "_check"]

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func over(fg: Color, bg: Color) -> Color:
	return Color(bg.r + (fg.r - bg.r) * fg.a, bg.g + (fg.g - bg.g) * fg.a, bg.b + (fg.b - bg.b) * fg.a)


func audit() -> void:
	var left := 0
	for f in ALLOW:
		var lines := FileAccess.get_file_as_string("res://" + f).split("\n")
		for i in lines.size():
			var l: String = lines[i]
			if not l.contains("Color(") or l.strip_edges().begins_with("#"):
				continue
			if l.contains("Color(Tok.") or l.contains("Color(base"):
				if l.contains("Color(Tok."):
					continue
			var why := ""
			for a in ALLOW[f]:
				if l.contains(a[0]):
					why = a[1]
			ok(why != "", "%s:%d literal %s" % [f, i + 1, ("allowed: " + why) if why != "" else "NOT A TOKEN: " + l.strip_edges().left(110)])
			left += 1
	var src := FileAccess.get_file_as_string("res://scripts/main.gd").split("\n")
	var fn := ""
	var bad := []
	var n := 0
	for i in src.size():
		var l: String = src[i]
		if l.begins_with("func "):
			fn = l.substr(5, l.find("(") - 5)
		if fn in MAIN_UI and l.contains("Color(") and not l.contains("Color(Tok.") and not l.contains("Color(tx,") and not l.strip_edges().begins_with("#"):
			n += 1
			# the check list's per-colour 3D content and LIMIT/TOUCH are not UI; a token-less Color here is a miss
			bad.append("main.gd:%d %s" % [i + 1, l.strip_edges().left(100)])
	for b in bad:
		print("     " + b)
	ok(bad.is_empty(), "main.gd's UI builders (%s): %d colour literals left" % [", ".join(MAIN_UI), bad.size()])
	print("     %d allowed literals in the widgets, each with its reason" % left)


func contrast() -> void:
	for dark in [true, false]:
		Tok.set_dark(dark)
		var pal := "dark" if dark else "light"
		var world := Tok.c("world")
		var panel := over(Tok.c("panel"), world)
		var flt := over(Tok.c("float"), world)
		var pairs := [["text on panel", Tok.c("text"), panel], ["side note (text:0.55) on panel", Tok.dim(0.55), panel],
			["faint (text:0.45) on panel", Tok.dim(0.45), panel],
			["info on panel", Tok.c("info"), panel], ["heading on panel", Tok.c("heading"), panel],
			["status text on its box", Tok.c("say"), over(Tok.c("say_bg"), world)], ["warn on findings", Tok.c("warn"), flt],
			["fail on findings", Tok.c("fail"), flt], ["button text", Tok.c("btn_text"), Tok.c("btn")],
			["button text hovered", Tok.c("btn_text"), Tok.c("btn_hover")], ["pressed button", Tok.c("on_accent"), Tok.c("accent")],
			["graph labels", over(Tok.of("ink:0.8"), over(Tok.c("graph_bg"), world)), over(Tok.c("graph_bg"), world)],
			["dummy text on panel", Tok.c("dummy_text"), panel]]
		var worst := 99.0
		var low := []
		for p in pairs:
			var r := Tok.contrast(p[1], p[2])
			worst = minf(worst, r)
			if r < 4.5:
				low.append("%s %.2f" % [p[0], r])
		ok(low.is_empty(), "%s palette: every text pair >= 4.5:1 (worst %.2f) %s" % [pal, worst, low])
	Tok.set_dark(true)


func _init() -> void:
	var real := FileAccess.get_file_as_string("user://poser.cfg")   # Nick's own setting: must come out untouched
	audit()
	contrast()
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	ok(Tok.dark and m.settings != "user://poser.cfg", "under a test: boots dark and saves to its own file (%s)" % m.settings)
	# a heading label (round 36: the inspector's "2 SELECTED PART" heading is gone; the left panel's "1  POSES")
	var lbl: Label = m.ui_tinted.filter(func(pr): return pr[1] == "heading" and pr[0] != m.ui_title and is_instance_valid(pr[0]))[0][0]
	var heading0 := lbl.get_theme_color("font_color")
	var btn0: Color = (m.ui_root.theme.get_stylebox("normal", "Button") as StyleBoxFlat).bg_color
	var u0: int = m.undo.size()
	m._ribbon("VIEW")
	await process_frame
	var light_btn: Button = null
	for b in m.ui_ribbon["VIEW"].get_children():
		if b is Button and m.label_of(b) == "Light":
			light_btn = b
	ok(light_btn != null and light_btn.is_visible_in_tree(), "VIEW tab has a 'Light' button on screen")
	var p := light_btn.get_global_rect().get_center()
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = p
		e.global_position = p
		root.push_input(e)
	await process_frame
	await process_frame
	ok(not Tok.dark and light_btn.button_pressed, "a click on it: light palette on, the button lit")
	ok(lbl.get_theme_color("font_color") == Tok.c("heading") and lbl.get_theme_color("font_color") != heading0, "a heading label re-tinted live: %s -> %s" % [heading0, lbl.get_theme_color("font_color")])
	var btn1: Color = (m.ui_root.theme.get_stylebox("normal", "Button") as StyleBoxFlat).bg_color
	ok(btn1 == Tok.c("btn") and btn1 != btn0, "buttons re-styled: %s -> %s" % [btn0, btn1])
	ok(m.world_env.background_color == Tok.LIGHT["world"] and m.floor_mat.albedo_color == Tok.LIGHT["floor"], "the 3D background and floor took the light palette")
	ok(m.undo.size() == u0, "no undo step (a view setting)")
	var cf2 := ConfigFile.new()
	cf2.load(m.settings)
	ok(cf2.get_value("look", "light", false) == true, "remembered: %s look/light = true" % m.settings)
	m._set_light(false)
	await process_frame
	ok(Tok.dark and lbl.get_theme_color("font_color") == heading0 and m.world_env.background_color == Tok.DARK["world"], "back to dark: the heading and the background as they were")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(m.settings))
	ok(FileAccess.get_file_as_string("user://poser.cfg") == real, "Nick's user://poser.cfg untouched")
	print("THEME TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
