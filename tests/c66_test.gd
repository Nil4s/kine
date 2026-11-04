## godot --path . -s tests/c66_test.gd     (a window)
## C66: the hands card ("Right hand holds the ...", Both hands / Weapon in hand / Flip blade) with a weapon held. Bar, written before any
## number was read: at 1024x600, 1280x720 and 1920x1080 (axe_strike_pose, Expert), the card's rect overlaps NO other visible Button
## (the view tool buttons included), nor the status Label, nor the mouse-hint Label, by 0 px2, and lies inside the 3D view rect
## (between the side panels, under the top bar, above the bottom bar). CONTROL: the card moved onto the status line overlaps it
## (> 0 px2), so the probe can fail.
extends SceneTree

var fails := 0
var m: Node
const SRC := "res://scenes/axe_strike_pose.json"
const COPY := "user://zz_c66_axe.json"
const OUT := "C:/Users/Nick/tools/kine_workers/out/c66/"


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	if not c:
		fails += 1


func idle(n := 4) -> void:
	for i in n:
		await process_frame


func area(a: Rect2, b: Rect2) -> float:
	var r := a.intersection(b)
	return r.size.x * r.size.y if r.has_area() else 0.0


func hits(card: Control) -> Array:
	var out := []
	var cr := card.get_global_rect()
	var list := m.find_children("*", "Button", true, false)
	list.append(m.ui_status)
	list.append(m.ui_mouse)
	for n in list:
		var c := n as Control
		if c == null or not is_instance_valid(c) or not c.is_visible_in_tree() or card.is_ancestor_of(c) or c.is_ancestor_of(card):
			continue
		var a := area(cr, c.get_global_rect())
		if a > 0.0:
			out.append("%s %.0f" % [c.name if String(c.name) != "" else c.get_class(), a])
	return out


func _init() -> void:
	var wd := create_timer(240.0)
	wd.timeout.connect(func():
		print("FAIL c66 watchdog")
		quit(1))
	DirAccess.make_dir_recursive_absolute(OUT)
	for sz in [Vector2i(1280, 720), Vector2i(1024, 600), Vector2i(1920, 1080)]:
		if m != null:
			m.queue_free()
			await idle(3)
		DisplayServer.window_set_size(sz)
		root.size = sz
		m = (load("res://main.tscn") as PackedScene).instantiate()
		root.add_child(m)
		await idle(4)
		DirAccess.copy_absolute(ProjectSettings.globalize_path(SRC), ProjectSettings.globalize_path(COPY))
		m._load_scene(COPY)
		m._refresh()
		await idle(8)
		var card: Control = m.ui_hands_panel
		var tag := "%dx%d" % [sz.x, sz.y]
		ok(card.is_visible_in_tree(), tag + " the hands card is showing with the axe held")
		var vs: Vector2 = m.get_viewport().get_visible_rect().size
		var view := Rect2(float(m.LEFT_W), float(m.TOP_H), vs.x - float(m.LEFT_W) - float(m.RIGHT_W), vs.y - float(m.TOP_H) - float(m.BOTTOM_H))
		var h := hits(card)
		ok(h.is_empty(), "%s card %s overlaps %d controls (px2): %s" % [tag, card.get_global_rect(), h.size(), h.slice(0, 5)])
		ok(view.encloses(card.get_global_rect()), "%s card inside the 3D view %s" % [tag, view])
		root.get_viewport().get_texture().get_image().save_png(OUT + "after_%d.png" % sz.x)
		if sz.x == 1280:
			var old := card.position
			card.position = (m.ui_status as Control).get_global_rect().position
			await idle(1)
			ok(not hits(card).is_empty(), "CONTROL: the card dropped on the status line is seen overlapping")
			card.position = old
	print("c66: ", "FAIL" if fails > 0 else "PASS")
	quit(1 if fails > 0 else 0)
