## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/stretchskin_shot.gd     (needs a window; STRETCHSKIN_SHOT=<png>, default C:/Temp/claude/l33/stretchskin.png)
## The L33 picture: the app's own skinned mannequin, 2 x 2. Top row: rest. Bottom row: the left arm stretched 1.3 with volume (cross scale 0.877)
## and the spine on a spline curve bent forward (stretch to fit, volume). Columns: front, side. The arm and the spine are the SKIN.
extends SceneTree

var m: Node


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func shot(yaw: float) -> Image:
	m._turn_to(yaw, -4.0, 3.0, Vector3(0, 1.05, 0), false)
	await idle(4)
	return root.get_viewport().get_texture().get_image()


func _init() -> void:
	_run()


func _run() -> void:
	root.size = Vector2i(640, 800)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m._load_scene("res://scenes/combo3.json")
	await idle(3)
	for c in m.get_children():
		if c is Control or c is CanvasLayer:
			c.visible = false
	m.S.ik = {}
	var B: Body = m.B
	for j in B.ang.keys():
		B.ang[j] = Vector3.ZERO
	B.offset = Vector3.ZERO
	B.ang["upperarm_l"] = Vector3(0, -80, 0)
	B.ang["upperarm_r"] = Vector3(0, 80, 0)
	B.fk()
	m._refresh()
	var imgs := []
	imgs.append(await shot(0.0))
	imgs.append(await shot(90.0))
	var ch: Dictionary = SplineChain.make_body(B, ["spine_01", "spine_02", "spine_03", "neck_01"], 4)
	var c: Array = ch["ctrl"]
	c[1] = (c[1] as Vector3) + Vector3(0, 0, 0.07)
	c[2] = (c[2] as Vector3) + Vector3(0, 0, 0.12)
	c[3] = (c[3] as Vector3) + Vector3(0, 0.03, 0.10)
	ch["mode"] = "stretch"
	ch["volume"] = true
	SplineChain.drive_body(B, ch)
	var st := B.stretch.duplicate()
	var cr := B.stretch_cross.duplicate()
	st["lowerarm_l"] = 1.3
	st["hand_l"] = 1.3
	cr["lowerarm_l"] = 1.0 / sqrt(1.3)
	cr["hand_l"] = 1.0 / sqrt(1.3)
	B.set_stretch(st, cr)
	B.fk()
	m._refresh()
	imgs.append(await shot(0.0))
	imgs.append(await shot(90.0))
	var w: int = imgs[0].get_width()
	var h: int = imgs[0].get_height()
	var out := Image.create(w * 2, h * 2, false, Image.FORMAT_RGBA8)
	for i in 4:
		var im: Image = imgs[i]
		im.convert(Image.FORMAT_RGBA8)
		out.blit_rect(im, Rect2i(0, 0, w, h), Vector2i((i % 2) * w, (i / 2) * h))
	var path := OS.get_environment("STRETCHSKIN_SHOT") if OS.get_environment("STRETCHSKIN_SHOT") != "" else "C:/Temp/claude/l33/stretchskin.png"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	out.save_png(path)
	print("saved ", path, " ", out.get_size(), " stretch ", st)
	quit(0)
