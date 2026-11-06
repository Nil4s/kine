## godot --path . -s tests/pol1106_test.gd     (lane L45, polish 11-06: five small UI flaws; window suite pol1106:w)
## BARS, written BEFORE the fixes and not moved after a run:
##  1 PLAYHEAD: the Throw check panel draws a playhead marker. Its x centre equals the current frame's cell centre within 1 px,
##    on 3 consecutive frames (f 10, 11, 12, set through the app's playhead and refresh). Control 1a: the marker at f 12 is not the
##    cell centre of f 17 (5 frames = 1 px per 2 px of cell at this width, so the comparator can tell).
##  2 PLACEMENT: the panel's global rect overlaps the viewport's axis-label rects by 0 px in total (summed over every visible axis_*
##    label). A label's rect is estimated from its font metrics (0.5 x the 32 px font: a Label3D with fixed_size, p156) and grown 4 px.
##    At least one label is visible, or the bar is empty. Control 2a: a rect on the panel's centre reads more than 0 px.
##  3 BRIEF: throw_check {clip, brief: true} on the 4 fixtures: at most 1024 bytes of JSON, no frames list, and verdict, frame,
##    partner_out_m and thrower_margin_m equal the full reply's (its key frame's out_m and margin_m). Control 3a: a brief out 0.5 mm off is caught.
##  4 OUTLINER FILTERS: at the 214 px tree, every filter button's label (10 px font) plus the button's side margins fits its rect.
##    Control 4a: "Lighting" does not fit a 30 px button by the same measure.
##  5 OUTLINER SEARCH: the LineEdit placeholder (12 px) is at most the LineEdit's inner width (rect minus box margins minus the clear icon).
##    Control 5a: a 40-character placeholder does not fit.
extends SceneTree

var fails := 0
const FPS := 30
const KINDS := ["osoto", "no_kuzushi", "overcommit", "apart"]


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func control(claim: bool, what: String) -> void:
	print(("ok   control caught: " if not claim else "FAIL control NOT caught: ") + what)
	if claim:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func save(s: Scene, name: String) -> String:
	DirAccess.make_dir_recursive_absolute("user://pol1106")
	var p := ProjectSettings.globalize_path("user://pol1106/" + name + ".json")
	var fh := FileAccess.open(p, FileAccess.WRITE)
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	b.ground()
	fh.store_string(JSON.stringify(s.to_dict(b, false)))
	fh.close()
	return p


func load_scene(p: String) -> Scene:
	var s := Scene.new()
	s.from_dict(JSON.parse_string(FileAccess.get_file_as_string(p)))
	return s


## the estimated on-screen rect of an axis label: its text at half the 32 px font (a fixed_size label, p156), grown 4 px
func label_rect(cam: Camera3D, l: Label3D) -> Rect2:
	var p := cam.unproject_position(l.global_position)
	var sz := ThemeDB.fallback_font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 32) * 0.5
	return Rect2(p - sz * 0.5, sz).grow(4.0)


func overlap_px(a: Rect2, b: Rect2) -> float:
	var r := a.intersection(b)
	return 0.0 if r.size.x <= 0.0 or r.size.y <= 0.0 else r.size.x * r.size.y


## does a label fit a box of this width: its text at px plus the box's side margins
func fits(font: Font, text: String, px: int, width: float, margin: float) -> bool:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + margin <= width


func _init() -> void:
	var paths := {}
	var fixtures := {}
	for k in KINDS:
		fixtures[k] = ThrowFixtures.build(k)
		paths[k] = save(fixtures[k], k)
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var T := AgentTools.new(m)
	var rid := 0

	# 1 the playhead marker
	rid += 1
	await T.request(rid, "open", {"path": paths["osoto"]})
	m.throw_on = true
	m._refresh()
	await idle(3)
	var P: ThrowPanel = m.throw_panel
	var n_frames := (ThrowTruth.judge(load_scene(paths["osoto"]), FPS)["frames"] as Array).size()
	var waited := 0   # L42: the judge runs off-thread after a debounce; bar 1 reads the cells only once the result has landed
	while P != null and P.res.is_empty() and waited < 600:
		await process_frame
		waited += 1
	ok(P != null and P.visible and n_frames > 13, "1 the panel is shown on the osoto fixture (%d frames, result after %d frames)" % [n_frames, waited])
	for f in [10, 11, 12]:
		m.playhead = float(f) / float(FPS)
		m._refresh()
		await idle(2)
		await RenderingServer.frame_post_draw
		var d := absf(P.marker_x() - P.x_of_frame(f))
		ok(d <= 1.0, "1 frame %d: the marker at x %.1f px, the cell centre at %.1f px (%.2f px apart)" % [f, P.marker_x(), P.x_of_frame(f), d])
	control(absf(P.marker_x() - P.x_of_frame(17)) <= 1.0, "1a the marker at f 12 is not the cell centre of f 17 (%.1f px apart)" % absf(P.marker_x() - P.x_of_frame(17)))

	# 2 placement against the axis labels
	await idle(3)
	await RenderingServer.frame_post_draw
	var pr := P.get_global_rect()
	var cam: Camera3D = m.cam
	var shown := 0
	var total := 0.0
	for c in m.stage_root.get_children():
		if c is Label3D and String(c.name).begins_with("axis_") and c.visible and not cam.is_position_behind(c.global_position):
			shown += 1
			var lr := label_rect(cam, c)
			total += overlap_px(pr, lr)
			print("     axis '%s' rect %s" % [c.text, lr])
	print("     throw panel rect %s" % pr)
	ok(shown >= 1 and total == 0.0, "2 the throw panel overlaps the %d visible axis labels by %.0f px" % [shown, total])
	control(overlap_px(pr, Rect2(pr.get_center() - Vector2(20, 8), Vector2(40, 16))) == 0.0, "2a a label rect on the panel's centre reads 0 px")
	m.throw_on = false
	m._refresh()

	# 3 the brief reply
	for k in KINDS:
		rid += 1
		var full: Dictionary = (await T.request(rid, "throw_check", {"clip": paths[k]})).get("result", {})
		rid += 1
		var brief: Dictionary = (await T.request(rid, "throw_check", {"clip": paths[k], "brief": true})).get("result", {})
		var kf := int(full["frame"])
		var fk: Dictionary = full["frames"][kf]
		var size := JSON.stringify(brief).length()
		var same: bool = brief.get("verdict") == full["verdict"] and int(brief.get("frame", -1)) == kf and not brief.has("frames")
		same = same and absf(float(brief.get("partner_out_m", -1.0)) - float(fk["partner"]["out_m"])) < 1e-9
		same = same and absf(float(brief.get("thrower_margin_m", -1.0)) - float(fk["thrower"]["margin_m"])) < 1e-9
		ok(same and size <= 1024, "3 %s: brief == full (%s, key f %d, out %.1f mm, margin %.1f mm), %d bytes (full %d)" % [k, full["verdict"], kf, float(fk["partner"]["out_m"]) * 1000.0, float(fk["thrower"]["margin_m"]) * 1000.0, size, JSON.stringify(full).length()])
		if k == "osoto":
			var nudged := brief.duplicate()
			nudged["partner_out_m"] = float(brief.get("partner_out_m", 0.0)) + 0.0005
			control(absf(float(nudged["partner_out_m"]) - float(fk["partner"]["out_m"])) < 1e-9, "3a a brief out 0.5 mm off equals the full reply")

	# 4 and 5 the outliner at its 214 px tree
	rid += 1
	await T.request(rid, "open", {"path": "scenes/combo3.json"})
	await idle(3)
	var br: Browser = m.ui_browser
	br._outl_root.collapsed = false
	br.set_outl_filter_all(true)
	br.set_outl_query("")
	br.refresh()
	await idle(6)
	br.scroll_to_item(br._ol_box_row)   # the search box and toggles ride on that row: measured only while it is in sight (as outliner_test does)
	await idle(4)
	print("     browser tree width %.0f px, search box %.0f px" % [br.size.x, br._ol_search.size.x])
	var bar: HBoxContainer = br._ol_bar
	ok(bar.get_child_count() == 6, "4 the filter bar has its 6 toggles (%d)" % bar.get_child_count())
	var font := ThemeDB.fallback_font
	for b in bar.get_children():
		var btn := b as Button
		var sb: StyleBox = btn.get_theme_stylebox("normal")
		var margin := sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT)
		var px: int = btn.get_theme_font_size("font_size")
		var need := font.get_string_size(btn.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + margin
		ok(need <= btn.size.x, "4 filter '%s': text + margins %.1f px in a %.1f px button (tree %.0f px)" % [btn.text, need, btn.size.x, br.size.x])
	control(fits(font, "Lighting", 10, 30.0, 0.0), "4a 'Lighting' does not fit a 30 px button")

	var le: LineEdit = br._ol_search
	var lsb: StyleBox = le.get_theme_stylebox("normal")
	var clear_w := le.get_theme_icon("clear").get_width() if le.clear_button_enabled else 0
	var inner := le.size.x - lsb.get_margin(SIDE_LEFT) - lsb.get_margin(SIDE_RIGHT) - float(clear_w)
	var pf := le.get_theme_font("font")
	var pfs: int = le.get_theme_font_size("font_size")
	var pw := pf.get_string_size(le.placeholder_text, HORIZONTAL_ALIGNMENT_LEFT, -1, pfs).x
	ok(pw <= inner, "5 search placeholder '%s': %.1f px in an inner width of %.1f px (box %.0f px)" % [le.placeholder_text, pw, inner, le.size.x])
	var long := "wardrobe, chandelier, the big red sofa..."
	control(pf.get_string_size(long, HORIZONTAL_ALIGNMENT_LEFT, -1, pfs).x <= inner, "5a a 40-character placeholder does not fit (%d px needed)" % int(pf.get_string_size(long, HORIZONTAL_ALIGNMENT_LEFT, -1, pfs).x))

	print("POL1106 TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
