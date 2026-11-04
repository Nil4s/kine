## godot --path . -s tests/c62_test.gd     (a window)
## C62: the default view must not draw the body under the toolbar. Bar, written before any number was read:
##   at 1024x600, 1280x720 and 1920x1080 (combo3, the view the app opens with, then after Fit): the screen point of EVERY bone's
##   head and tail (Body.cap ends of each part) is inside the window and under NO visible Control that takes mouse presses
##   (0 px under the ribbon / toolbar / bottom bar). CONTROL: a camera pushed up 0.6 m puts the head under the toolbar (the
##   probe must see >= 1 covered point), so the bar can fail.
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	if not c:
		fails += 1


func idle(n := 4) -> void:
	for i in n:
		await process_frame


func covered() -> Array:
	var vp: Rect2 = m.get_viewport().get_visible_rect()
	var bad := []
	var n := 0
	for j in m.B.P.keys():
		var c: Array = m.B.cap(j)
		for k in 2:
			n += 1
			var w: Vector3 = c[k]
			var p: Vector2 = m.cam.unproject_position(w)
			var why := ""
			if m.cam.is_position_behind(w) or not vp.has_point(p):
				why = "outside the window"
			else:
				for ch in m.ui_root.get_children():
					if ch is CanvasItem and not (ch as CanvasItem).visible:
						continue
					var bl: Control = PickCheck.blocker(ch, p)
					if bl != null:
						why = "under " + String(bl.name)
						break
			if why != "":
				bad.append("%s.%s %s %s" % [j, "head" if k == 0 else "tail", p.round(), why])
	return [n, bad]


func _init() -> void:
	var wd := create_timer(200.0)
	wd.timeout.connect(func():
		print("FAIL c62 watchdog")
		quit(1))
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	for sz in [Vector2i(1280, 720), Vector2i(1024, 600), Vector2i(1920, 1080)]:
		if m != null:
			m.queue_free()   # a fresh app per size: the opening view is what a user gets, not a resized old one
			await idle(3)
		DisplayServer.window_set_size(sz)
		root.size = sz
		m = (load("res://main.tscn") as PackedScene).instantiate()
		root.add_child(m)
		await idle(4)
		m._load_scene("res://scenes/combo3.json")
		m._rebuild_cards()
		m.playhead = 0.0
		m._refresh()
		await idle(6)
		var r: Array = covered()
		ok((r[1] as Array).is_empty(), "%dx%d the opening view: %d of %d bone ends covered or outside %s" % [sz.x, sz.y, (r[1] as Array).size(), r[0], (r[1] as Array).slice(0, 4)])
		m._nav_fit()
		await idle(3)
		r = covered()
		ok((r[1] as Array).is_empty(), "%dx%d after Fit: %d of %d bone ends covered or outside %s" % [sz.x, sz.y, (r[1] as Array).size(), r[0], (r[1] as Array).slice(0, 4)])
		m._view_home(false)
		await idle(3)
		r = covered()
		ok((r[1] as Array).is_empty(), "%dx%d after Home: %d of %d covered %s" % [sz.x, sz.y, (r[1] as Array).size(), r[0], (r[1] as Array).slice(0, 4)])
	# control: push the target down so the body rides up under the toolbar
	m.target.y -= 0.6
	m._cam()
	await idle(3)
	var rc: Array = covered()
	ok((rc[1] as Array).size() >= 1, "CONTROL a camera aimed 0.6 m low is caught: %d covered" % (rc[1] as Array).size())
	print("c62: %d fail" % fails)
	quit(1 if fails > 0 else 0)
