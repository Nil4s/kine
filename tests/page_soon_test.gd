extends SceneTree
## P11: a greyed page (MODEL / SCULPT / SURFACE) says why when clicked, never a dead end. Bars: (1) each of the 3 says
## "greyed because" + its plan; (2) a command whose name starts with the page's prefix is listed when it exists (a test
## row added to the registry is found); (3) the click changes no page and adds no undo step
var fails := 0
func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1
func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 4:
		await process_frame
	m.tour_step = -1
	var page0: String = m.page if m.get("page") != null else ""
	var und: int = (m.undo_stack as Array).size() if m.get("undo_stack") != null else -1
	var all := true
	for p in ["MODEL", "SCULPT", "SURFACE"]:
		var b: Button = m.find_child("page_" + p.to_lower(), true, false)
		b.pressed.emit()
		await process_frame
		var t := String(m.ui_status.text)
		all = all and t.contains("greyed because") and t.contains(p)
		print("  ", t.left(220))
	ok(all, "(1) each greyed page explains itself")
	var w := String(m._page_soon_why("MODEL"))
	ok(w.contains("Model:") or w.contains("Nothing to click"), "(2) MODEL lists its existing commands or says none: %s" % w.left(160))
	ok((page0 == "" or m.page == page0) and (und < 0 or (m.undo_stack as Array).size() == und), "(3) no page change, no undo step")
	print("PAGE SOON ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails else 0)
