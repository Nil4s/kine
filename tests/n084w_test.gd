## godot --path . -s tests/n084w_test.gd     (window suite: n084w:w)   N084 BLEND MATRIX WIRED (scripts/blend_matrix_serve.gd, blend_matrix_panel.gd, blend_matrix_ui.gd)
## Places: the agent call `blend_matrix {clips?, blend_s?, a?, b?, full?, top?}` (the CLI serve, the MCP server and the AI box run it; the one-shot CLI has
## `blend_matrix`), the heat grid panel, the command and the click-to-preview in the app. The maths bars are in tests/n084_test.gd.
## Bars, written BEFORE the wiring was run:
##  a AGENT CALL: three scene files (idle, crouch_deep, crouch_ok; each two cards, the crouches grounded). blend_matrix {clips, blend_s: 2/60} answers JSON whose
##    cell (idle -> crouch_deep) equals the module's direct matrix on the same files (stringified, parsed, within 1e-3), whose grid marks that cell B and idle -> idle ".",
##    whose first bad pair is a pair into or out of crouch_deep with skate over 100 mm. {a, b} adds "cell". full adds "cells" (3 x 3); the default leaves them out.
##    Controls: an unknown scene file and blend_s 0 answer -32602; the made-up tool name answers -32601.
##  b LISTS: "blend_matrix" is in AgentTools.MCP_EXTRA, poser_mcp.py names it in TOOLS and MATH_TOOLS, poser_cli.gd has a `blend_matrix` subcommand.
##    Control: a made-up name is in none of them.
##  c PANEL: BlendMatrixPanel for the 3 x 3 matrix: clicking the centre of every cell emits picked(i, j) for exactly that cell (9 of 9); the bad cell's colour
##    is redder than green and the clean diagonal cell is greener than red; a click on the name column, and outside the grid, emit nothing and answer (-1, -1).
##    Control: a claim "the bad cell and the clean cell have the same colour" is false; the tooltip of the bad cell names both clips and says skate.
##  d APP: the command "Blend matrix: check my clips..." is in the command list; with the 3 clips loaded in the app, bm_ui.preview(0, 1) puts the body in the
##    blend's first pose (the idle's end), ticking to the end leaves the last pose of the blend (the thigh bend within 0.01 of the module's last frame), and Ctrl+Z
##    (one undo step) gives the pose back. Control: the thigh bend at the end is not the one at the start.
##  e PICTURE: the dialog with the real scenes and moves of this repo (BlendMatrixUI.run) saved to out/n084w_panel.png (printed; looked at by hand).
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func control(claim: bool, what: String) -> void:
	print(("ok   control caught: " if not claim else "FAIL control NOT caught: ") + what)
	if claim:
		fails += 1


func body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	b.ground()
	return b


func pose_dict(ov: Dictionary) -> Dictionary:
	var b := body()
	for j in ov:
		b.ang[j] = ov[j]
	b.fk()
	b.offset.y -= minf(b.foot_sole_low("_l"), b.foot_sole_low("_r"))
	b.fk()
	return b.to_dict()


func save_scene(name: String, ov_a: Dictionary, ov_b: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute("user://n084w")
	var s := Scene.new()
	s.from_dict({"scene": "zz_" + name, "fps": 30, "natural": false, "on_floor": false, "pin": false, "cards": [
		{"name": "a", "pose": pose_dict(ov_a), "move": -1.0, "hold": 0.0}, {"name": "b", "pose": pose_dict(ov_b), "move": 1.0, "hold": 0.0}]})
	var p := ProjectSettings.globalize_path("user://n084w/" + name + ".json")
	var fh := FileAccess.open(p, FileAccess.WRITE)
	fh.store_string(JSON.stringify(s.to_dict(body(), false)))
	fh.close()
	return p


func _init() -> void:
	var deep := {"thigh_l": Vector3(110, 0, 0), "thigh_r": Vector3(110, 0, 0), "calf_l": Vector3(130, 0, 0), "calf_r": Vector3(130, 0, 0)}
	var okc := {"thigh_l": Vector3(60, 0, 0), "thigh_r": Vector3(60, 0, 0), "calf_l": Vector3(120, 0, 0), "calf_r": Vector3(120, 0, 0)}
	var p_idle := save_scene("idle", {}, {})
	var p_deep := save_scene("crouch_deep", deep, deep)
	var p_ok := save_scene("crouch_ok", okc, okc)
	var files := [p_idle, p_deep, p_ok]
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var T := AgentTools.new(m)
	var bs := 2.0 / 60.0
	var direct := BlendMatrix.matrix(BlendMatrix.clips_of_files(files), bs)
	var dcell: Dictionary = direct["cells"][0][1]
	print("     direct idle -> crouch_deep: skate %.1f mm, %s" % [dcell["skate_mm"], dcell["verdict"]])
	# a
	var r1: Dictionary = (await T.request(1, "blend_matrix", {"clips": files, "blend_s": bs, "a": "idle", "b": "crouch_deep"})).get("result", {})
	var rj: Dictionary = JSON.parse_string(JSON.stringify(r1))
	var cc: Dictionary = rj.get("cell", {})
	var same := not cc.is_empty()
	for k in ["limit_deg", "clash_mm", "skate_mm", "seam", "score"]:
		if not cc.has(k) or absf(float(cc[k]) - float(dcell[k])) > 1e-3:
			same = false
	ok(same and cc.get("verdict", "") == "bad", "a agent call: the cell idle -> crouch_deep equals the module's direct numbers (skate %.1f mm)" % float(cc.get("skate_mm", -1.0)))
	var grid: Array = rj.get("grid", [])
	ok(grid.size() == 3 and String(grid[0])[1] == "B" and String(grid[0])[0] == ".", "a grid rows %s: idle -> crouch_deep is B, idle -> idle is ." % [grid])
	var bad: Array = rj.get("bad", [])
	ok(not bad.is_empty() and (bad[0]["a"] == "crouch_deep" or bad[0]["b"] == "crouch_deep") and float(bad[0]["skate_mm"]) > 100.0, "a the first bad pair %s -> %s skates %.0f mm (> 100)" % [bad[0]["a"] if not bad.is_empty() else "?", bad[0]["b"] if not bad.is_empty() else "?", float(bad[0]["skate_mm"]) if not bad.is_empty() else -1.0])
	ok(not rj.has("cells"), "a the default reply leaves the 3 x 3 cells out")
	var r2: Dictionary = (await T.request(2, "blend_matrix", {"clips": files, "blend_s": bs, "full": true})).get("result", {})
	ok((r2.get("cells", []) as Array).size() == 3 and ((r2["cells"] as Array)[0] as Array).size() == 3, "a full: the 3 x 3 cells")
	var e1: Dictionary = await T.request(3, "blend_matrix", {"clips": ["nope/none.json"]})
	var e2: Dictionary = await T.request(4, "blend_matrix", {"clips": files, "blend_s": 0.0})
	ok(e1.has("error") and int(e1["error"]["code"]) == -32602 and e2.has("error") and int(e2["error"]["code"]) == -32602, "a unknown file and blend_s 0 answer -32602")
	var nm: Dictionary = await T.request(5, "blend_matrix_nope", {})
	ok(nm.has("error") and int(nm["error"]["code"]) == -32601, "a the made-up tool name answers -32601")
	print("     reply bytes %d" % JSON.stringify(r1).to_utf8_buffer().size())
	# b
	var py := FileAccess.get_file_as_string("res://tools/mcp/poser_mcp.py")
	var cli := FileAccess.get_file_as_string("res://tools/poser_cli.gd")
	ok("blend_matrix" in AgentTools.MCP_EXTRA, "b agent tool list: MCP_EXTRA has blend_matrix")
	ok(py.contains("\"blend_matrix\": (\"blend_matrix\"") and py.split("MATH_TOOLS = [")[1].split("]")[0].contains("\"blend_matrix\""), "b MCP: TOOLS names blend_matrix and MATH_TOOLS lists it")
	ok(cli.contains("\"blend_matrix\":"), "b CLI: a one-shot blend_matrix subcommand")
	control("blend_matrix_nope" in AgentTools.MCP_EXTRA or py.contains("\"blend_matrix_nope\"") or cli.contains("\"blend_matrix_nope\":"), "b1 a made-up name is listed somewhere")
	# c
	var P := BlendMatrixPanel.new()
	P.size = Vector2(400, 200)
	root.add_child(P)
	P.set_matrix(direct)
	var picks: Array = []
	P.picked.connect(func(i, j): picks.append(Vector2i(i, j)))
	var right := 0
	for i in 3:
		for j in 3:
			picks.clear()
			var got := P.click(P.cell_rect(i, j).get_center())
			if picks.size() == 1 and picks[0] == Vector2i(i, j) and got == Vector2i(i, j):
				right += 1
	ok(right == 9, "c a click on the centre of each cell emits that cell: %d of 9" % right)
	picks.clear()
	var o1 := P.click(Vector2(10, 40))
	var o2 := P.click(Vector2(BlendMatrixPanel.LABEL_W + 3 * BlendMatrixPanel.CELL + 20.0, 40))
	ok(picks.is_empty() and o1 == Vector2i(-1, -1) and o2 == Vector2i(-1, -1), "c a click on the names or outside the grid emits nothing")
	var cb := P.cell_color(0, 1)
	var cg := P.cell_color(0, 0)
	ok(cb.r > cb.g and cg.g > cg.r, "c the bad cell reads red (%s) and the clean cell green (%s)" % [cb.to_html(false), cg.to_html(false)])
	control(cb.is_equal_approx(cg), "c1 the bad cell and the clean cell have the same colour")
	var tip := P._get_tooltip(P.cell_rect(0, 1).get_center())
	ok("idle" in tip and "crouch_deep" in tip and "skate" in tip, "c the tooltip of the bad cell: '%s'" % tip)
	P.queue_free()
	# d
	var found := false
	for c in (await T.request(6, "commands", {"find": "blend matrix"})).get("result", []):
		if "Blend matrix" in String(c.get("name", "")):
			found = true
	ok(found, "d the command 'Blend matrix: check my clips...' is in the list")
	var ui: BlendMatrixUI = m.bm_ui
	ok(ui != null, "d main made the BlendMatrixUI")
	if ui != null:
		ui.clips = BlendMatrix.clips_of_files(files)
		ui.set_matrix(direct)
		var th0: float = (m.B.ang["thigh_l"] as Vector3).x
		ui.preview(0, 1)
		var fr := BlendMatrix.frames(ui.clips[0], ui.clips[1], bs)
		var first_ok: bool = absf((m.B.ang["thigh_l"] as Vector3).x - float((fr[0]["ang"]["thigh_l"] as Vector3).x)) < 0.01
		ui.tick(1.0)
		var th1: float = (m.B.ang["thigh_l"] as Vector3).x
		var last_x := float((fr[fr.size() - 1]["ang"]["thigh_l"] as Vector3).x)
		ok(first_ok and absf(th1 - last_x) < 0.01, "d preview: starts on the blend's first pose, ends on its last (thigh bend %.2f, the module's %.2f)" % [th1, last_x])
		control(absf(th1 - float((fr[0]["ang"]["thigh_l"] as Vector3).x)) < 0.5, "d1 the end pose is the start pose")
		m._undo()
		var th2: float = (m.B.ang["thigh_l"] as Vector3).x
		ok(absf(th2 - th0) < 0.01, "d one undo gives the pose back (thigh bend %.2f, was %.2f)" % [th2, th0])
		# e
		ui.open()
		ui.run()
		for i in 12:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_viewport().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://out"))
		img.save_png(ProjectSettings.globalize_path("res://out/n084w_panel.png"))
		print("SHOT out/n084w_panel.png %dx%d" % [img.get_width(), img.get_height()])
		# PLACEMENT (numbers, not looking): every cell's box sits inside the grid control, the grid control inside the window, and the pixel at a cell's centre is that cell's colour
		var pr: Rect2 = ui.panel.get_global_rect()
		var wsz := root.get_visible_rect().size
		var n_in := 0
		var n_px := 0
		var nn := int(ui.M.get("n", 0))
		var sc: ScrollContainer = ui.panel.get_parent()
		var vis: Rect2 = sc.get_global_rect()
		var n_vis := 0
		for ci in nn:
			for cj in nn:
				var cr: Rect2 = ui.panel.cell_rect(ci, cj)
				if Rect2(Vector2.ZERO, ui.panel.size).encloses(cr):
					n_in += 1
				var gc: Vector2 = pr.position + cr.get_center()
				if vis.has_point(gc) and Rect2(Vector2.ZERO, wsz).has_point(gc):
					n_vis += 1
					var px := img.get_pixel(int(gc.x), int(gc.y))
					var want: Color = ui.panel.cell_color(ci, cj)
					if absf(px.r - want.r) + absf(px.g - want.g) + absf(px.b - want.b) < 0.06:
						n_px += 1
		print("     PLACEMENT grid %s in window %s; %d of %d cell boxes inside the grid; %d visible cells, %d read back their colour from the screenshot" % [pr, wsz, n_in, nn * nn, n_vis, n_px])
		ok(nn >= 2 and n_in == nn * nn and n_vis > 0 and n_px == n_vis and Rect2(Vector2.ZERO, wsz).encloses(vis), "e placement: all %d cell boxes inside the grid, %d of %d visible cells match their colour on screen" % [nn * nn, n_px, n_vis])
		print(BlendMatrix.words(ui.M, 8))
		ok(int(ui.M.get("n", 0)) >= 2, "e the real scenes: %d clips, %d bad pairs" % [int(ui.M.get("n", 0)), (ui.M.get("bad", []) as Array).size()])
	print("N084W TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	print("n084w: %d fail" % fails)
	TestFiles.cleanup()
	quit(fails)
