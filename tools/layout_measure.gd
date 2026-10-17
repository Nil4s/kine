## godot --path . -s tools/layout_measure.gd -- [--m-size 1600x900] [--m-scene res://scenes/combo3.json] [--m-fold l,r,b]
##        [--m-shot C:/Temp/qq4/x.png] [--m-taught]  (own flag names: main.gd reads --scene and --shot itself)     (GATES QQ4)
## --m-taught (round 36, RR6): not a first start (the yellow welcome strip, first start only, is gone)
## ROOM TO WORK, MEASURED: the window at --size (100 % UI), the app as it starts (an empty scene) or with --scene open,
## with the panels named in --fold folded (l = left, r = right, b = bottom; needs round 35a). Every visible piece of
## chrome straight under the UI root (the ribbon, the side panels or their rails, the bottom panel, the say strip, the
## status bar) is listed with its rect; the VIEW = the window's pixels none of them cover (sampled every 4 px), as a
## share of the window. A screenshot when --shot is given.
extends SceneTree


func arg(k: String, d: String) -> String:
	var a := OS.get_cmdline_user_args()
	var i := a.find(k)
	return a[i + 1] if i >= 0 and i + 1 < a.size() else d


func _init() -> void:
	var sz := arg("--m-size", "1600x900").split("x")
	var ws := Vector2i(int(sz[0]), int(sz[1]))
	DisplayServer.window_set_size(ws)
	root.size = ws
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 6:
		await process_frame
	var sc := arg("--m-scene", "")
	if sc != "":
		m._load_scene(sc)
		m._rebuild_cards()
	var fo := arg("--m-fold", "")
	if fo != "":
		if not m.has_method("_fold"):
			print("NO FOLDING in this build")
		else:
			for k in fo.split(","):
				m._fold({"l": "left", "r": "right", "b": "bottom"}[k], true, false)
	if OS.get_cmdline_user_args().has("--m-taught") and m.has_method("_end_teach"):
		m._end_teach()
	for i in 6:
		await process_frame
	var vs: Vector2 = root.get_visible_rect().size
	var chrome: Array = []
	for c in m.ui_root.get_children():
		if c is Control and (c as Control).is_visible_in_tree() and (c is PanelContainer or c is Panel or c == m.ui_status or c == m.ui_bar):
			var r: Rect2 = (c as Control).get_global_rect()
			if r.get_area() > 0 and c != m.ui_tour:
				chrome.append([c, r])
	var free := 0
	var tot := 0
	var y := 0.0
	while y < vs.y:
		var x := 0.0
		while x < vs.x:
			tot += 1
			var cov: bool = y < m.TOP_H
			if not cov:
				for cr in chrome:
					if (cr[1] as Rect2).has_point(Vector2(x, y)):
						cov = true
						break
			if not cov:
				free += 1
			x += 4.0
		y += 4.0
	print("WINDOW %dx%d  scene %s  fold [%s]" % [vs.x, vs.y, sc if sc != "" else "(empty)", fo])
	print("  ribbon      0,0 %dx%d" % [vs.x, m.TOP_H])
	for cr in chrome:
		var r: Rect2 = cr[1]
		print("  %-11s %d,%d %dx%d" % [String(cr[0].name).substr(0, 11), r.position.x, r.position.y, r.size.x, r.size.y])
	print("VIEW SHARE %.1f %%" % (100.0 * free / tot))
	var shot := arg("--m-shot", "")
	if shot != "":
		DirAccess.make_dir_recursive_absolute(shot.get_base_dir())
		root.get_texture().get_image().save_png(shot)
	quit()
