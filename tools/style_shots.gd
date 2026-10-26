## STYLE PROPOSAL driver (w4-style). A test run (-s), so settings and autosave stay in user://.
## godot --path . -s tools/style_shots.gd -- --kine-palette=a --tag=a --shots
## godot --path . -s tools/style_shots.gd -- --audit --sizes=1280x720,1024x600
## --shots: four 1280x720 pictures (Expert POSE with walk_bat, Expert MODEL, Easy home, Easy My scenes).
## --audit: Expert pages, each ribbon button clicked for real (blocked words skipped), every visible Control or Window
## whose global rect leaves the viewport is listed, and its first screenshot gets a red outline (limits_<n>.png).
extends SceneTree

const PAGES := ["BODY", "POSE", "ANIMATE", "STAGE", "CHECK", "DELIVER", "MODEL", "SCULPT", "SURFACE"]
const BLOCK := ["open", "save", "export", "import", "load", "browse", "delete", "quit", "exit", "reset", "new", "make", "video", "copy", "remove", "clear", "undo", "redo", "reload", "install", "send", "upload", "publish", "bake", "overwrite", "restore", "close", "recover", "print", "share", "render"]

var m: Node
var out := "C:/Temp/claude/style"
var tag := "now"
var n_lim := 0
var seen := {}
var lim_lines: Array = []


func _arg(name: String, dflt: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(name + "="):
			return a.trim_prefix(name + "=")
	return dflt


func wait(n := 2) -> void:
	for i in n:
		await process_frame
	await RenderingServer.frame_post_draw


func _grab() -> Image:
	await wait(2)
	return root.get_viewport().get_texture().get_image()


func _init() -> void:
	out = _arg("--out", out)
	tag = _arg("--tag", tag)
	DirAccess.make_dir_recursive_absolute(out)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await wait(90)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var a := OS.get_cmdline_user_args()
	if a.has("--shots"):
		await _shots()
	if a.has("--audit"):
		for s in _arg("--sizes", "1280x720,1024x600").split(","):
			var d := s.split("x")
			await _size(Vector2i(int(d[0]), int(d[1])))
			await _walk()
		_write_lim()
	print("DONE")
	quit()


func _size(v: Vector2i) -> void:
	root.min_size = Vector2i.ZERO   # main sets 1280 x 720 as the floor; the audit needs the smaller sizes too
	DisplayServer.window_set_size(v)
	root.size = v
	await wait(30)
	print("VIEWPORT ", root.get_visible_rect().size)


func _save(name: String) -> void:
	var img := await _grab()
	var p := "%s/%s_%s.png" % [out, tag, name]
	img.save_png(p)
	print("SHOT ", p, " ", img.get_size())


func _shots() -> void:
	await _size(Vector2i(1280, 720))
	var src := FileAccess.get_file_as_string("res://scenes/walk_bat.json")
	var f := FileAccess.open("user://style_walk_bat.json", FileAccess.WRITE)
	f.store_string(src)
	f.close()
	m.easy.set_on(false)
	m._load_scene("user://style_walk_bat.json")
	await wait(30)
	m._page_set("POSE")
	await wait(30)
	await _save("expert_pose")
	m._page_set("MODEL")
	await wait(30)
	await _save("expert_model")
	m._page_set("POSE")
	m.easy.set_on(true)
	await wait(40)
	await _save("easy_home")
	m.easy.scenes.open_panel()
	await wait(40)
	await _save("easy_scenes")


# ---------------------------------------------------------------- limits audit

func _walk() -> void:
	var sz := root.get_visible_rect().size
	m.easy.set_on(false)
	for p in PAGES:
		m._page_set(p)
		await wait(12)
		await _snap("page %s, opened" % p, sz)
		var seen_lab := {}
		for b in _buttons(sz):
			if not is_instance_valid(b) or not b.is_visible_in_tree():
				continue
			var lab := _label(b)
			if seen_lab.has(lab):
				continue
			seen_lab[lab] = true
			if m.cur_page != p:
				m._page_set(p)
				await wait(12)
			await _click(b)
			await wait(8)
			await _snap("page %s, clicked '%s'" % [p, lab], sz)
			await _esc()
			await wait(6)


func _label(b: Node) -> String:
	var t = b.get("text")
	if t is String and t != "":
		return t
	if b.tooltip_text != "":
		return b.tooltip_text
	return String(b.name)


func _collect_btn(n: Node, acc: Array) -> void:
	for c in n.get_children():
		if c is BaseButton:
			acc.append(c)
		_collect_btn(c, acc)


func _buttons(sz: Vector2) -> Array:
	var acc := []
	_collect_btn(root, acc)
	var res := []
	var vp := Rect2(Vector2.ZERO, sz)
	for b in acc:
		if not b.is_visible_in_tree() or b.disabled:
			continue
		if not vp.has_point(b.get_global_rect().get_center()):
			continue
		var inside_popup := false
		var a: Node = b.get_parent()
		while a != null:
			if a is Popup:
				inside_popup = true
				break
			a = a.get_parent()
		if inside_popup:
			continue
		var lab := _label(b).to_lower()
		var blocked := false
		for w in BLOCK:
			if lab.contains(w):
				blocked = true
				break
		if not blocked:
			res.append(b)
	return res


func _click(b: Control) -> void:
	var p := b.get_global_rect().get_center()
	var mm := InputEventMouseMotion.new()
	mm.position = p
	mm.global_position = p
	Input.parse_input_event(mm)
	await wait(2)
	var d := InputEventMouseButton.new()
	d.position = p
	d.global_position = p
	d.button_index = MOUSE_BUTTON_LEFT
	d.pressed = true
	Input.parse_input_event(d)
	await wait(2)
	var u := InputEventMouseButton.new()
	u.position = p
	u.global_position = p
	u.button_index = MOUSE_BUTTON_LEFT
	u.pressed = false
	Input.parse_input_event(u)


func _esc() -> void:
	for pr in [true, false]:
		var k := InputEventKey.new()
		k.keycode = KEY_ESCAPE
		k.physical_keycode = KEY_ESCAPE
		k.pressed = pr
		Input.parse_input_event(k)
		await wait(1)


func _collect(n: Node, acc: Array) -> void:
	for c in n.get_children():
		if c is Control or c is Window:
			acc.append(c)
		_collect(c, acc)


## every visible Control / Window whose global rect is not inside the viewport
func _items(sz: Vector2) -> Array:
	var acc := []
	_collect(root, acc)
	var res := []
	var vp := Rect2(Vector2.ZERO, sz)
	for c in acc:
		var r: Rect2
		if c is Control:
			if not c.is_visible_in_tree() or c.size == Vector2.ZERO:
				continue
			r = c.get_global_rect()
		else:
			if not c.visible:
				continue
			r = Rect2(Vector2(c.position), Vector2(c.size))
			if c.is_embedded() == false:
				r.position -= Vector2(root.position)
		if vp.encloses(r):
			continue
		var clipped := false
		var a: Node = c.get_parent()
		while a != null:
			if a is Control and (a as Control).clip_contents:
				clipped = true
			a = a.get_parent()
		var ov := {"L": maxf(0.0, -r.position.x), "T": maxf(0.0, -r.position.y), "R": maxf(0.0, r.end.x - sz.x), "B": maxf(0.0, r.end.y - sz.y)}
		res.append({"node": c, "path": str(c.get_path()) if c.is_inside_tree() else String(c.name), "kind": c.get_class(), "rect": r, "over": ov, "clipped": clipped})
	return res


func _snap(trigger: String, sz: Vector2) -> void:
	var new_items := []
	for it in _items(sz):
		var key := "%s|%s" % [it.path, sz]
		if seen.has(key):
			continue
		seen[key] = true
		new_items.append(it)
	if new_items.is_empty():
		return
	var img := await _grab()
	for it in new_items:
		n_lim += 1
		var im := img.duplicate()
		_outline(im, it.rect)
		var file := "limits_%d.png" % n_lim
		im.save_png(out + "/" + file)
		var o: Dictionary = it.over
		var line := "%s | %s | %s | %s | rect %s | out L%.0f T%.0f R%.0f B%.0f | %s | %s" % [file, sz, trigger, it.kind, it.rect, o.L, o.T, o.R, o.B, it.path, "in clipping parent" if it.clipped else "free"]
		lim_lines.append(line)
		print("LIMIT ", line)


func _outline(img: Image, r: Rect2) -> void:
	var red := Color(1, 0, 0)
	var ri := Rect2i(int(floor(r.position.x)), int(floor(r.position.y)), int(ceil(r.size.x)), int(ceil(r.size.y)))
	var bounds := Rect2i(0, 0, img.get_width(), img.get_height())
	var t := 4
	var edges := [
		Rect2i(ri.position.x, ri.position.y, ri.size.x, t),
		Rect2i(ri.position.x, ri.end.y - t, ri.size.x, t),
		Rect2i(ri.position.x, ri.position.y, t, ri.size.y),
		Rect2i(ri.end.x - t, ri.position.y, t, ri.size.y),
	]
	for e in edges:
		var c: Rect2i = e.intersection(bounds)
		if c.size.x > 0 and c.size.y > 0:
			img.fill_rect(c, red)


func _write_lim() -> void:
	var f := FileAccess.open(out + "/limits.txt", FileAccess.WRITE)
	f.store_string("\n".join(lim_lines) + "\n")
	f.close()
	print("LIMITS ", lim_lines.size(), " -> ", out + "/limits.txt")
