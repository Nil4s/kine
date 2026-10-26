## godot --headless --path . -s tests/checkhunt_drv.gd -- <scene|empty|two|long> <tool text|LIST> <once|twice|playing>
## FREEZE HUNT driver: opens the CHECK page on a scene, really clicks one tool (root.push_input), prints "CH|..." lines
## with the main-thread frame times (max / count over 1 s / total) of the frames after it. One tool per process so a crash shows.
extends SceneTree

var m: Node
var worst := 0.0
var frames := 0


func walk(n: Node, out: Array) -> Array:
	out.append(n)
	for c in n.get_children(true):
		walk(c, out)
	return out


func text_of(b: Button) -> String:
	if b.has_meta("label"):
		return str(b.get_meta("label"))
	if b.text.strip_edges() != "":
		return b.text.strip_edges()
	for n in walk(b, []):
		if n is Label and (n as Label).text.strip_edges() != "":
			return (n as Label).text.strip_edges()
	return ""


## the ribbon button with these words; a tool the strip has folded into a menu (cap / More) is clicked through the same signal
func find_btn(txt: String) -> Button:
	for n in walk(m.ui_ribbon["CHECK"], []):
		if n is Button and text_of(n) == txt:
			return n
	return null


func mouse_btn(down: bool, p: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)


func click(b: Button) -> void:
	if not b.is_visible_in_tree():
		print("CH|VIA_MENU|%s" % text_of(b))
		b.pressed.emit()
		await process_frame
		return
	var p := b.get_global_rect().get_center()
	var hm := InputEventMouseMotion.new()
	hm.position = p
	hm.global_position = p
	root.push_input(hm)
	await process_frame
	mouse_btn(true, p)
	await process_frame
	mouse_btn(false, p)


## frame times: the time between process_frame signals, so a blocked main thread shows as one long frame
func watch(n: int, tag: String) -> void:
	var last := Time.get_ticks_usec()
	var t0 := last
	for i in n:
		await process_frame
		var now := Time.get_ticks_usec()
		var d := (now - last) / 1000.0
		last = now
		worst = maxf(worst, d)
		if d > 200.0:
			print("CH|HITCH|%s|frame %d took %.0f ms (busy check %s polish %s)" % [tag, i, d, str(m._check_busy), str(m._polish_busy)])
	print("CH|WATCH|%s|worst %.0f ms over %d frames, total %.0f ms" % [tag, worst, n, (Time.get_ticks_usec() - t0) / 1000.0])


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var which: String = a[0] if a.size() > 0 else "combo3"
	var tool: String = a[1] if a.size() > 1 else "LIST"
	var how: String = a[2] if a.size() > 2 else "once"
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 10:
		await process_frame
	if which != "empty":
		var src := "res://scenes/combo3.json" if which in ["combo3", "two", "long"] else "res://scenes/%s.json" % which
		var d = JSON.parse_string(FileAccess.get_file_as_string(src))
		if which == "long":   # 60 s: repeat the cards until the clip is that long
			var cards: Array = d.get("cards", [])
			var out := []
			while cards.size() > 0 and out.size() < 140:
				out.append_array(cards.duplicate(true))
			d["cards"] = out
		var p := "user://checkhunt_%s.json" % which
		var f := FileAccess.open(p, FileAccess.WRITE)
		f.store_string(JSON.stringify(d))
		f.close()
		m._load_scene(p)
		for i in 20:
			await process_frame
	m._page_set(a[3] if a.size() > 3 else "CHECK")
	for i in 10:
		await process_frame
	print("CH|SCENE|%s|cards %d" % [which, m.S.cards.size()])
	if tool == "LIST":
		var names := []
		for n in walk(m.ui_ribbon["CHECK"], []):
			if n is Button:
				names.append(text_of(n))
		print("CH|LIST|", JSON.stringify(names))
		quit()
		return
	var b := find_btn(tool)
	if b == null:
		print("CH|NOBTN|%s" % tool)
		quit()
		return
	if how == "playing":
		m.playing = true
		for i in 5:
			await process_frame
	var t0 := Time.get_ticks_usec()
	var ac0: int = Scene.apply_calls
	await click(b)
	print("CH|CLICK|%s|returned after %.0f ms, Scene.apply calls %d" % [tool, (Time.get_ticks_usec() - t0) / 1000.0, Scene.apply_calls - ac0])
	if how == "twice":
		var b2 := find_btn(tool)
		if b2 != null:
			await click(b2)
	await watch(int(a[4]) if a.size() > 4 else 240, tool)
	print("CH|DONE|%s|cards %d" % [tool, m.S.cards.size()])
	quit()
