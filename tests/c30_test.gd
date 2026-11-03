extends SceneTree
## godot --path . --position 4000,4000 -s tests/c30_test.gd     (C30: the Export dialog fits the screen; its buttons stay pinned)
## BARS, written before any number was read:
##  A  FITS    at 1280x720 AND 1024x600, for EVERY target of the dialog, the dialog window lies inside the app window and its
##             Export (OK), Cancel and Batch... buttons lie inside it too (screen rects, no scrolling of the window).
##  B  PINNED  the options sit in a ScrollContainer "export_opts_scroll"; the three buttons are NOT inside it.
##  C  REACH   with the dialog at 1024x600 the FBX choice "opt_fbx_for" (target Unity) is still reachable: after ensure_control_visible
##             its rect lies inside the scroll's rect.
##  D  SAME    defaults untouched: the opened dialog has target 0 / budget 0 / opt_fbx_for 0 and ExportNames.fbx_for == "default".
##  CONTROL    the fit check fails on a rect planted 40 px below the window (so bar A can fail).
const SHOT := "C:/Users/Nick/tools/kine_workers/out/c30"
var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func _watchdog() -> void:
	await create_timer(300.0).timeout
	print("FAIL watchdog: the test did not finish in 300 s")
	quit(1)


func scr(dlg: Window, c: Control) -> Rect2:
	var r := c.get_global_rect()
	return Rect2(r.position + (Vector2(dlg.position) if dlg != root else Vector2.ZERO), r.size)


func inside(win: Rect2, r: Rect2) -> bool:
	return win.grow(0.5).encloses(r)


func one_size(sz: Vector2i, tag: String) -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = sz
	root.size = sz
	await idle(4)
	var win := Rect2(Vector2.ZERO, Vector2(sz))
	var ui: ExportDialog = m.export_ui
	var n := ExportDialog.targets().size()
	for t in n:
		m._export_dialog_open()
		await idle(4)
		ui = m.export_ui
		ui.ui_target.select(t)
		ui._on_target(t)
		ui._refresh()
		await idle(6)
		var d := ui.dlg
		var dr := Rect2(Vector2(d.position), Vector2(d.size))
		var okb := scr(d, d.get_ok_button())
		var cb := scr(d, d.get_cancel_button())
		var bb: Rect2 = Rect2()
		for b in d.get_children():
			pass
		var batch: Button = null
		for c in d.find_children("*", "Button", true, false):
			if (c as Button).text == "Batch...":
				batch = c
		if batch != null:
			bb = scr(d, batch)
		var fit := inside(win, dr) and inside(win, okb) and inside(win, cb) and batch != null and inside(win, bb)
		ok(fit, "A %s target %d (%s): dialog %s, Export %s, Cancel %s, Batch %s in window %s" % [tag, t, str(ui.ui_target.get_item_text(t)), str(dr), str(okb), str(cb), str(bb), str(win)])
		if t == 0 or t == n - 1:
			root.get_texture().get_image().save_png("%s/dialog_%s_t%d.png" % [SHOT, tag, t])
		d.hide()
		await idle(2)


func _init() -> void:
	_watchdog()
	DirAccess.make_dir_recursive_absolute(SHOT)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	await idle(4)
	m._load_scene("res://scenes/combo3.json")
	await idle(3)
	ok(not inside(Rect2(0, 0, 1280, 720), Rect2(500, 700, 100, 60)), "CONTROL a rect planted 40 px below the window fails the fit check")
	await one_size(Vector2i(1280, 720), "1280x720")
	await one_size(Vector2i(1024, 600), "1024x600")
	# B, C, D at 1024x600
	m._export_dialog_open()
	await idle(6)
	var ui: ExportDialog = m.export_ui
	var d := ui.dlg
	var sc := d.find_child("export_opts_scroll", true, false) as ScrollContainer
	ok(sc != null, "B the options scroll in 'export_opts_scroll'")
	if sc != null:
		for b in [d.get_ok_button(), d.get_cancel_button()]:
			ok(not sc.is_ancestor_of(b), "B button '%s' is outside the scroll" % (b as Button).text)
		var opt := d.find_child("opt_fbx_for", true, false) as OptionButton
		ok(opt != null and sc.is_ancestor_of(opt), "B the FBX choice lives in the scroll")
		if opt != null:
			sc.ensure_control_visible(opt)
			await idle(4)
			var sr := Rect2(sc.get_global_rect())
			ok(sr.grow(0.5).encloses(opt.get_global_rect()), "C FBX choice %s inside the scroll %s after scrolling to it" % [str(opt.get_global_rect()), str(sr)])
			ok(opt.selected == 0 and ExportNames.fbx_for == "default", "D opt_fbx_for default 0, fbx_for = %s" % ExportNames.fbx_for)
	ok(ui.ui_budget.selected == 0, "D budget default 0")
	ok(ui.ui_target.selected == 0, "D target default 0 (selected %d)" % ui.ui_target.selected)
	print("C30 DONE fails=", fails)
	quit(1 if fails > 0 else 0)
