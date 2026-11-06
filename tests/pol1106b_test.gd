## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/pol1106b_test.gd     (lane L47 POL1106b: small UI gaps)
## Bars written BEFORE the fixes. Each has a planted control that must hold.
##  1 BADGE   the timeline shows a node "sim_cache_badge" whose text is "cache: none" / "cache: fresh" / "cache: stale":
##            none before any bake; fresh right after Bake sim; stale after a pose-card edit; none after Bake sim: Free.
##            The badge rect lies inside the window in every state.
##            PLANTED: the state after a bake is not "none"; a pose edit really changes the cache state (not vacuous).
##  2 BAND    the cancel band (CancelWindows.COL_BAND) has a WCAG contrast of at least 3:1 against every block colour it can sit on:
##            fd_startup, fd_active, fd_recovery, and fd_active at 0.22 alpha over tl_bg (the tint of an active span), in BOTH themes.
##            The band rects of a live jab are at least 6 px tall.
##            PLANTED: the old teal (#2fbf9b) fails 3:1 against fd_startup in the dark theme (so the bar bites).
##  3 CHIP    with the timeline detached, the layouts dialog's dock map lists a chip named Timeline whose text contains "detached",
##            the chip lies inside the map. PLANTED: before the detach the map has no such chip.
## Gate: pol1106b, simcache, n081, n081w, detach, layouts, uiexp, easypart, peasy3, freestart.
extends SceneTree

var fails := 0
var m: Node
const DIR := "user://pol1106b_test"
const TMP := "user://pol1106b_scene.json"
const JAB := "user://pol1106b_jab.json"
const FPS := 60
const MIN_CONTRAST := 3.0
const MIN_BAND_H := 6.0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func control(claim: bool, what: String) -> void:
	print(("ok   control caught: " if not claim else "FAIL control NOT caught: ") + what)
	if claim:
		fails += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func body() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	return B


func boot_app() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.dummy_on = false


func load_scene(S: Scene) -> void:
	var fa := FileAccess.open(TMP, FileAccess.WRITE)
	fa.store_string(JSON.stringify(S.to_dict(m.B, false)))
	fa.close()
	m._load_scene(TMP)
	m._rebuild_cards()
	m.playing = false
	await idle(2)


## the quick turn at 60 fps (the simcache test's scene): stand 1.0 s, the pelvis turns 90 deg, holds 2.2 s
func turn_scene() -> Scene:
	var S := Scene.new()
	S.fps = 60
	var rest := {}
	for j in Body.ORDER:
		rest[j] = {"bend": 0.0, "side": 0.0, "twist": 0.0}
	S.add("stand", {"joints": rest.duplicate(true), "offset": [0.0, 0.0, 0.0]})
	(S.cards[-1] as Dictionary)["hold"] = 1.0
	var turned := rest.duplicate(true)
	(turned["pelvis"] as Dictionary)["twist"] = 90.0
	S.add("turn", {"joints": turned, "offset": [0.0, 0.0, 0.0]})
	(S.cards[-1] as Dictionary)["move"] = 0.25
	(S.cards[-1] as Dictionary)["hold"] = 2.2
	return S


func jab_scene() -> Scene:
	var B := body()
	var a0: Vector3 = B.ang["upperarm_r"]
	var guard := _posed("upperarm_r", Vector3(10.0, a0.y, a0.z))
	var hit := _posed("upperarm_r", Vector3(70.0, a0.y, a0.z))
	var s := Scene.new()
	s.from_dict({"scene": "zz_pol1106b", "fps": 30, "natural": false, "on_floor": false, "pin": false, "cards": [
		{"name": "guard", "pose": guard, "move": -1.0, "hold": 10.0 / FPS}, {"name": "extend", "pose": hit, "move": 3.0 / FPS, "hold": 3.0 / FPS},
		{"name": "retract", "pose": guard, "move": 12.0 / FPS, "hold": 30.0 / FPS}]})
	return s


func _posed(j: String, v: Vector3) -> Dictionary:
	var b := body()
	b.ang[j] = v
	b.fk()
	return b.to_dict()


## WCAG relative-luminance blend: colour c at alpha a over the opaque colour bg
func over(c: Color, a: float, bg: Color) -> Color:
	return Color(bg.r + (c.r - bg.r) * a, bg.g + (c.g - bg.g) * a, bg.b + (c.b - bg.b) * a)


## the block colours the band can sit on, in the current theme
func blocks() -> Dictionary:
	var bg := Tok.c("tl_bg")
	return {
		"startup": Tok.c("fd_startup"),
		"active": Tok.c("fd_active"),
		"recovery": Tok.c("fd_recovery"),
		"active_tint": Tok.c("fd_tint"),   # the drawn wash of an active span (POL1106b: a token now; was fd_active at 0.22 over tl_bg)
	}


func worst_contrast(band: Color) -> String:
	var worst := INF
	var at := ""
	for k in blocks():
		var r := Tok.contrast(band, blocks()[k])
		if r < worst:
			worst = r
			at = k
	return "%.2f (%s)" % [worst, at]


func min_contrast(band: Color) -> float:
	var worst := INF
	for k in blocks():
		worst = minf(worst, Tok.contrast(band, blocks()[k]))
	return worst


func _init() -> void:
	# ---- 2 BAND (pure colour bar first: no app needed)
	var old_teal := Color("2fbf9b")
	Tok.set_dark(true)
	var dark_band := min_contrast(CancelWindows.COL_BAND)
	Tok.set_dark(false)
	var light_band := min_contrast(CancelWindows.COL_BAND)
	Tok.set_dark(true)
	print("band colour %s: worst contrast dark %.2f, light %.2f (bar >= %.1f)" % [CancelWindows.COL_BAND, dark_band, light_band, MIN_CONTRAST])
	ok(dark_band >= MIN_CONTRAST, "2 the band colour is >= 3:1 against every block colour, dark theme: worst %s" % worst_contrast(CancelWindows.COL_BAND))
	Tok.set_dark(false)
	ok(light_band >= MIN_CONTRAST, "2 the band colour is >= 3:1 against every block colour, light theme: worst %s" % worst_contrast(CancelWindows.COL_BAND))
	Tok.set_dark(true)
	var old_worst := 0.0
	Tok.set_dark(true)
	old_worst = Tok.contrast(old_teal, Tok.c("fd_startup"))
	Tok.set_dark(true)
	control(old_worst >= MIN_CONTRAST, "2 PLANTED the old teal fails 3:1 against the startup green (%.2f)" % old_worst)

	# ---- 1 BADGE and 2 HEIGHT, in the live app
	var DIRS := DIR + "/session"
	await boot_app()
	m.simc.dir = DIRS
	await load_scene(turn_scene())
	m._do(func(): m.S.cape = Cloth.bake_scene(m.S.clone(), body()))
	await idle(3)
	var win := m.get_viewport().get_visible_rect()
	var badge := m.find_child("sim_cache_badge", true, false) as Label
	ok(badge != null and badge.text == "cache: none", "1 before any bake the badge reads 'cache: none' (%s)" % (badge.text if badge != null else "no badge"))
	var inside := true
	if badge != null:
		inside = inside and Rect2(win).encloses(badge.get_global_rect())

	m._simc_bake()
	await idle(3)
	badge = m.find_child("sim_cache_badge", true, false) as Label
	var t_fresh := badge.text if badge != null else ""
	ok(t_fresh == "cache: fresh", "1 after Bake sim the badge reads 'cache: fresh' (%s)" % t_fresh)
	control(t_fresh == "cache: none", "1 PLANTED the badge after a bake is not still 'none'")
	if badge != null:
		inside = inside and Rect2(win).encloses(badge.get_global_rect())

	m._do(func(): (m.S.cards[1]["pose"]["joints"]["spine_01"] as Dictionary)["bend"] = 20.0)
	await idle(3)
	badge = m.find_child("sim_cache_badge", true, false) as Label
	ok(badge != null and badge.text == "cache: stale", "1 after a pose-card edit the badge reads 'cache: stale' (%s)" % (badge.text if badge != null else "no badge"))
	if badge != null:
		inside = inside and Rect2(win).encloses(badge.get_global_rect())

	m._simc_free()
	await idle(3)
	badge = m.find_child("sim_cache_badge", true, false) as Label
	ok(badge != null and badge.text == "cache: none", "1 after Bake sim: Free the badge reads 'cache: none' (%s)" % (badge.text if badge != null else "no badge"))
	if badge != null:
		inside = inside and Rect2(win).encloses(badge.get_global_rect())
	ok(inside, "1 the badge rect lies inside the window in every state")

	# ---- 2 HEIGHT: the live jab's cancel band rects
	var jab_s := jab_scene()
	var fa := FileAccess.open(JAB, FileAccess.WRITE)
	fa.store_string(JSON.stringify(jab_s.to_dict(body(), false)))
	fa.close()
	m._load_scene(JAB)
	m._rebuild_cards()
	m.playing = false
	await idle(2)
	m.fd_on = true
	m._refresh()
	var waited := 0
	while (m.fd_cache.get("fd", {}).get("cancel", null) == null) and waited < 600:
		await process_frame
		waited += 1
	await idle(3)
	var rects: Array = m.ui_timeline.cancel_rects()
	var tallest := 0.0
	var shortest := INF
	for rc in rects:
		tallest = maxf(tallest, (rc as Rect2).size.y)
		shortest = minf(shortest, (rc as Rect2).size.y)
	ok(rects.size() >= 1 and shortest >= MIN_BAND_H, "2 every cancel band rect of the live jab is >= %.0f px tall: %d bands, shortest %.1f px" % [MIN_BAND_H, rects.size(), shortest if rects.size() > 0 else -1.0])
	control(rects.size() >= 1 and tallest <= 4.0, "2 PLANTED the band is not already 6 px (the pre-fix bands were 4 px): tallest %.1f" % tallest)
	m.fd_on = false
	m._refresh()
	await idle(2)

	# ---- 3 CHIP: the layouts dialog's dock map with the timeline detached
	var d := UiExpDrive.new()
	await d.boot(self)
	m = d.m
	await d.screen("part")
	await d.idle(6)
	var sh: UiExpShell = m.bld.shell
	var ui = sh.layouts_ui
	ui.open_dialog()
	await d.idle(6)
	var dm = ui.dock_map
	var before_chips: Array = dm.detached_chips()
	control(not before_chips.is_empty(), "3 PLANTED before the detach the map lists no detached chip")
	var pd: PanelDetach = m.detach
	pd.native = false
	pd.rescue = false
	var det_ok := pd.detach("timeline", Rect2i(120, 140, 420, 260))
	sh.sync_detached()
	ui.refresh()
	await d.idle(6)
	ok(det_ok, "3 the timeline detaches (%s)" % str(pd.rects()))
	var chips: Array = dm.detached_chips()
	var tl_chip := {}
	for c in chips:
		if String(c["title"]) == "Timeline":
			tl_chip = c
	var txt := String(tl_chip.get("text", ""))
	ok(not tl_chip.is_empty() and txt.contains("detached"), "3 the dock map lists a chip named Timeline whose text contains 'detached' (text '%s')" % txt)
	ok(not tl_chip.is_empty() and Rect2(Vector2.ZERO, dm.size).encloses(tl_chip["rect"]), "3 the Timeline chip lies inside the map")

	print("pol1106b: %d failures" % fails)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(JAB))
	quit(1 if fails > 0 else 0)
