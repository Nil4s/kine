## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/meshsearch_test.gd    (ROADMAP_400 P02)
## SEARCH FINDS MESH TOOLS TOO, WITH HOTKEYS SHOWN (scripts/mesh_tools.gd read by scripts/command_search.gd). Bars
## (stated before measuring):
##  1 the registry: ids unique; every "cmd:" line names a real command of the S box (that row gets its page), every
##    other line is exactly one "mesh" row; the empty S box still lists only the commands (no tool rows added there)
##  2 typed into the box: "extrude", "wire", "x ray", "validate" each put a mesh tool in the first row, its right-hand
##    text showing its hotkey (E, X ...) and its page (MODEL); "mesh:" lists every tool row
##  3 one typo forgiven like the commands: "extrdue", "wirre", "valdate", "lassso" find the same rows first
##  4 a pick off the MODEL page opens the model preview first and runs the tool: Enter on "x ray" -> the test cube is
##    open and x-ray is on; validate says the cube is clean; wire turns the wire off; extrude (not built) is greyed and
##    says why; the Blender grab is greyed with the layer off, shows G and is not greyed with it on
##  5 PLACEMENT: the first row's hotkey cell ("X   MODEL") is inside the list and the window, the text fits the cell,
##    and the cell has >= 20 pixels of the heading colour (the text is drawn); screenshot env MESHSEARCH_SHOT
extends SceneTree

var fails := 0
var m: Node
var cs: CommandSearch


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func key(code: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = down
		root.push_input(e)
		await process_frame


func search(q: String) -> Array:
	cs.open()
	cs.box.text = q
	cs._filter()
	return cs.shown


func first_text(q: String) -> Array:   # [name, right-hand text, greyed]
	search(q)
	var it: TreeItem = cs.list.get_root().get_first_child()
	if it == null:
		return ["", "", false]
	return [it.get_text(0), it.get_text(1), it.get_custom_color(0) == Tok.dim(0.6)]


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	cs = m.ui_cmd
	m.blk.set_on(false, false)

	# 1. the registry
	var ids := {}
	var cmd_ids := {}
	for c in cs.commands:
		cmd_ids[String(c["id"])] = c
	var bad := []
	var n_rows := 0
	for t in MeshTools.TOOLS:
		ids[t["id"]] = true
		var d := String(t["do"])
		if d.begins_with("cmd:"):
			var c = cmd_ids.get(d.substr(4))
			if c == null or not c.has("page"):
				bad.append(d)
		else:
			n_rows += 1
	ok(ids.size() == MeshTools.TOOLS.size() and bad.is_empty(), "1a %d lines, ids unique, every cmd: line is a command row with a page (missing %s)" % [MeshTools.TOOLS.size(), bad])
	ok(cs.tools.size() == n_rows and cs.tools.all(func(r): return r["kind"] == "mesh"), "1b %d mesh rows for the %d non-command lines" % [cs.tools.size(), n_rows])
	search("")
	ok(cs.shown.size() == cs.commands.size(), "1c the empty box lists the %d commands only (%d rows)" % [cs.commands.size(), cs.shown.size()])

	# 2. found, with the hotkey and the page
	for q in [["extrude", "Model: extrude", "E   MODEL"], ["wire", "Model: wire over the surface on / off", "MODEL"], ["x ray", "Model: x-ray select through", "X   MODEL"], ["validate", "Model: check the mesh (validate)", "MODEL"]]:
		var r := first_text(q[0])
		print("     '%s' -> %s" % [q[0], str(cs.shown.slice(0, 4).map(func(c): return c["name"]))])
		ok(r[0] == q[1] and String(r[1]).begins_with(q[2]), "2 '%s': first row '%s', right text '%s' (bar: '%s' then '%s...')" % [q[0], r[0], r[1], q[1], q[2]])
	var wr := search("wire").filter(func(c): return c["name"] == "View: shading wireframe")
	ok(wr.size() == 1 and MeshTools.right_text(wr[0]).contains("every page"), "2b 'wire' also lists the viewport's 'View: shading wireframe' (a command row) with its page: '%s'" % (MeshTools.right_text(wr[0]) if wr.size() > 0 else "-"))
	var qv := search("quad").filter(func(c): return c["name"] == "View: quad view on/off")
	ok(qv.size() == 1 and MeshTools.right_text(qv[0]) == "Ctrl+Alt+Q   every page", "2c 'quad': the quad view command shows 'Ctrl+Alt+Q   every page' ('%s'), one row" % (MeshTools.right_text(qv[0]) if qv.size() > 0 else "-"))
	ok(search("mesh:").size() == n_rows, "2d 'mesh:' lists every mesh row (%d)" % cs.shown.size())

	# 3. typos
	for q in [["extrdue", "Model: extrude"], ["wirre", "Model: wire over the surface on / off"], ["valdate", "Model: check the mesh (validate)"], ["lassso", "Model: lasso select"]]:
		var r := first_text(q[0])
		ok(r[0] == q[1], "3 '%s' (one typo) -> '%s'" % [q[0], r[0]])

	# 4. picks: off the MODEL page, the model preview opens first
	ok(m.kmed == null or not m.kmed.on, "4a the model preview is closed at the start")
	search("x ray")
	await key(KEY_ENTER)
	await idle(2)
	print("     status: ", m.ui_status.text)
	ok(m.kmed != null and m.kmed.on and m.kmed.xray and not cs.visible, "4b Enter on 'x ray': the test cube opened first, x-ray on (%s)" % (m.kmed.xray if m.kmed != null else "-"))
	ok(String(m.ui_status.text).contains("opened the test cube first") and String(m.ui_status.text).contains("x-ray on"), "4c the status says why the page changed and x-ray on: '%s'" % m.ui_status.text)
	search("validate")
	await key(KEY_ENTER)
	ok(String(m.ui_status.text).contains("clean") and String(m.ui_status.text).contains("%d verts" % m.kmed.mesh.verts.size()), "4d validate on the cube: '%s'" % m.ui_status.text)
	var w0: bool = m.kmed.view.show_wire
	search("wire")
	await key(KEY_ENTER)
	ok(m.kmed.view.show_wire == not w0, "4e 'wire' Enter: wire %s -> %s" % [w0, m.kmed.view.show_wire])
	var ex := first_text("extrude")
	await key(KEY_ENTER)
	ok(ex[2] and String(ex[1]).ends_with("soon") and String(m.ui_status.text).contains("not built yet"), "4f extrude is greyed ('%s') and says why: '%s'" % [ex[1], m.ui_status.text])
	var gr := first_text("grab vertices")
	ok(gr[0] == "Model: grab the selected vertices" and gr[2] and String(gr[1]).begins_with("G"), "4g layer off: grab greyed, shows '%s'" % gr[1])
	await key(KEY_ENTER)
	ok(String(m.ui_status.text).contains("Blender-style") and m.blk.active == "", "4h a greyed grab says how to turn the layer on and starts nothing: '%s'" % m.ui_status.text)
	m.blk.set_on(true, false)
	gr = first_text("grab vertices")
	ok(not gr[2] and String(gr[1]).begins_with("G   MODEL"), "4i layer on: grab not greyed, '%s'" % gr[1])
	cs.close()
	m.blk.set_on(false, false)

	# 5. placement: the hotkey cell on screen
	search("x ray")
	await idle(3)
	var it: TreeItem = cs.list.get_root().get_first_child()
	var cell: Rect2 = cs.list.get_item_area_rect(it, 1)
	cell.position += cs.list.get_global_rect().position
	var vp := m.get_viewport().get_visible_rect()
	var f: Font = cs.list.get_theme_font("font")
	var tw := f.get_string_size(it.get_text(1), HORIZONTAL_ALIGNMENT_LEFT, -1, cs.list.get_theme_font_size("font_size")).x
	var img: Image = m.get_viewport().get_texture().get_image()
	var head := Tok.c("heading")
	var n_px := 0
	for y in range(int(cell.position.y), int(cell.end.y)):
		for x in range(int(cell.position.x), int(cell.end.x)):
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				var p := img.get_pixel(x, y)
				if absf(p.r - head.r) + absf(p.g - head.g) + absf(p.b - head.b) < 0.25:
					n_px += 1
	print("     cell %s text '%s' %.0f px, list %s, viewport %s, %d heading pixels" % [cell, it.get_text(1), tw, cs.list.get_global_rect(), vp, n_px])
	ok(cs.list.get_global_rect().grow(1).encloses(cell) and vp.encloses(cell) and tw <= cell.size.x and n_px >= 20,
		"5 the hotkey cell '%s' is inside the list and the window, the text fits (%.0f <= %.0f px), %d heading pixels drawn (bar 20)" % [it.get_text(1), tw, cell.size.x, n_px])
	var shot := OS.get_environment("MESHSEARCH_SHOT")
	if shot == "":
		shot = "user://meshsearch.png"
	img.save_png(shot)
	print("     screenshot: ", shot)
	cs.close()
	print("MESHSEARCH %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
