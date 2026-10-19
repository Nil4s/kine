## godot --path . -s tools/make_tip_clips.gd [-- only=id,id]     (ROADMAP 49; needs a window)
## Makes the tooltip clips (assets/tips/): the app drives ITSELF, scripted, over combo3 held in memory (nothing is
## saved but the clips): each clip is 30 frames = 2 s at 15 fps of the 3D view (or the view plus the card strip and
## timeline for the tools that live there), 320x200, packed as one PNG frame sheet (6 columns) per clip, and
## assets/tips/tips.json says which button shows which clip. Every clip gets a fresh app, so none leaks into the next.
## The scene is never written: edits happen in memory and the app is thrown away.
extends SceneTree

const N := 30
const FPS := 15
const W := 320
const H := 200
const COLS := 6
const OUT := "res://assets/tips/"
const SCENE := "res://scenes/combo3.json"

## id -> which buttons show it (by label, or by node name), and where the picture is taken from
const CLIPS := {
	"pick": {"buttons": ["Lock this part"], "crop": "view"},
	"ik_drag": {"buttons": [], "crop": "view"},
	"key": {"buttons": ["CLIP this pose (Enter)"], "crop": "bottom"},
	"mirror": {"buttons": ["Mirror pose (Shift+M)"], "crop": "view"},
	"retime": {"buttons": [], "names": ["b_slower"], "crop": "bottom"},
	"onion": {"buttons": ["Onion (O)"], "crop": "view"},
	"foot_plant": {"buttons": [], "crop": "bottom"},
	"playback": {"buttons": ["Play (Space)", "Stop (Space)"], "names": ["b_play"], "crop": "bottom"},
	"undo": {"buttons": ["Undo (Ctrl+Z)"], "crop": "view"},
	"critique": {"buttons": ["Check"], "crop": "bottom"},
	"export": {"buttons": ["Export .glb", "Export .bvh"], "crop": "view"},
	"trail": {"buttons": ["Trail (T)"], "crop": "view"},
	"speed_graph": {"buttons": ["Speed graph (Y)"], "crop": "view"},
	"balance": {"buttons": ["Balance (Shift+B)"], "crop": "view"},
}

var m: Node
var shots: Array = []
var crop := "view"


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func proj(p: Vector3) -> Vector2:
	return m.cam.unproject_position(p)


func mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await process_frame


func move(p: Vector2, rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await process_frame


## the picture: the 3D view, cut to 16:10 about its middle ("view"); or the same width taken from the bottom of the
## window up, so the card strip and the timeline are in it ("bottom"); then 320x200, no alpha
func grab() -> Image:
	var full := root.get_texture().get_image()
	var vs := Vector2(full.get_size())
	var lw: float = m.lw()
	var rw: float = m.rw()
	var r: Rect2
	if crop == "bottom":
		var w := vs.x - lw - rw
		var h := w / 1.6
		r = Rect2(lw, vs.y - h, w, h)
	else:
		var vr := Rect2(lw, m.TOP_H, vs.x - lw - rw, vs.y - m.TOP_H - m.bottom_h - 56.0)   # 56: the hint line sits at the view's foot
		var h := minf(vr.size.y, vr.size.x / 1.6)
		var w := h * 1.6
		r = Rect2(vr.position.x + (vr.size.x - w) * 0.5, vr.position.y + (vr.size.y - h) * 0.5, w, h)
	var img := full.get_region(Rect2i(r))
	img.resize(W, H, Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGB8)
	var d := img.get_data()
	for i in d.size():
		d[i] = d[i] & 0xFC   # 6 bits a channel: the sheet compresses ~25 % smaller, the banding is below what 320x200 shows
	return Image.create_from_data(W, H, false, Image.FORMAT_RGB8, d)


func shoot() -> void:
	await RenderingServer.frame_post_draw
	shots.append(grab())


func at(t: float) -> void:
	m.playhead = clampf(t, 0.0, m.S.length())
	m._ps().apply(m.B, m.playhead)
	m._refresh()


func fresh() -> void:
	if m != null:
		m.queue_free()
		await idle(2)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene(SCENE)
	m._rebuild_cards()
	m.playing = false
	m.ui_status.text = ""
	m.sel = "head"
	at(float(m.S.times()[1][1]))
	cam_to(28.0)
	await idle(4)


## the camera for this clip's crop: the "bottom" ones sit further back and higher so the body stays in the top of the picture
func cam_to(yaw: float) -> void:
	if crop == "bottom":
		m._turn_to(yaw, -8.0, 6.6, Vector3(0, 1.45, 0), false)
	else:
		m._turn_to(yaw, -8.0, 5.0, Vector3(0, 1.2, 0), false)


func pick_card(i: int) -> void:
	var c: Node = m.find_child("card_%d" % (i + 1), true, false)
	if c != null:
		(c.find_child("b_pick", true, false) as Button).pressed.emit()
	await idle(2)


func click_at(p: Vector2) -> void:
	await mouse(p, true)
	await mouse(p, false)


## one frame k (0..29) of the clip `id`: the drive, then the picture is taken by the caller
func drive(id: String, k: int, st: Dictionary) -> void:
	var u := float(k) / float(N - 1)
	var t0: float = st.get("t0", 0.0)
	match id:
		"pick":
			var parts := ["head", "hand_r", "foot_l", "upperarm_l"]
			if k % 7 == 1:
				var part: String = parts[(k / 7) % parts.size()]
				await click_at(proj(m.B.P[part]))
				await idle(2)
		"ik_drag":
			var kh: Dictionary = LimbIK.sample(m.S.ik["hand_l"], m.playhead)
			var ph := proj(kh["target"])
			var d: Vector2 = (proj(m.B.P["upperarm_l"]) - ph).normalized() * 80.0
			if k == 2:
				await mouse(ph, true)
			elif k > 2 and k <= 24:
				var q: Vector2 = ph + d * float(k - 2) / 22.0
				await move(q, d / 22.0)
			elif k == 25:
				await mouse(ph + d, false)
		"key":
			if k < 14:
				var a := Vector3(-8.0, -87.0 + 70.0 * float(k) / 13.0, 32.0)
				m.B.ang["upperarm_r"] = m.B.clamp_ang("upperarm_r", a)
				m.B.fk()
				m._refresh()
			elif k == 16:
				m._card_add()
		"mirror":
			if k == 8 or k == 20:
				m._tool(0)
		"retime":
			if k == 6 or k == 12 or k == 18 or k == 24:
				m._speed(1.1)
		"onion":
			if k == 2:
				m._press(KEY_O)
			at(t0 + u * 2.0)
		"foot_plant":
			if k == 14:
				m.sel = "foot_r"
				m._foot_plant_next()
			var f := float(k % 15) / 14.0
			at(t0 + f * (st["t1"] - t0))
		"playback":
			at(t0 + u * 2.0)
		"undo":
			if k == 4:
				m._tool(0)
			elif k == 10:
				m._do(func(): m.B.ang["head"] = m.B.clamp_ang("head", Vector3(0, 40, 0)); m.B.fk())
			elif k == 17 or k == 23:
				m._undo()
		"critique":
			if k == 3:
				m._check()
			elif k == 12:
				m._critique()
			at(t0 + u * 2.0)
		"export":
			cam_to(28.0 + 360.0 * u)
			at(t0 + u * 2.0)
		"trail":
			if k == 1:
				m._press(KEY_T)
			at(t0 + u * 2.0)
		"speed_graph":
			if k == 1:
				m._tool(2)
			at(t0 + u * 2.0)
		"balance":
			if k == 1:
				m._press(KEY_B, true)
			at(t0 + u * 1.5)
	await idle(2)


func make(id: String) -> Dictionary:
	crop = CLIPS[id]["crop"]
	await fresh()
	var st := {"t0": 0.6}
	match id:
		"pick":
			at(float(m.S.times()[2][1]))
		"ik_drag":
			at(float(m.S.times()[1][1]))
			for tip in ["hand_l"]:
				m.sel = tip
				m._ik_pin()
			m.sel = "head"
			m._refresh()
			await idle(3)
		"key", "retime":
			await pick_card(1 if id == "key" else 2)
		"mirror", "undo":
			at(float(m.S.times()[3][1]))
		"foot_plant":
			var tt: Array = m.S.times()
			st["t0"] = float(tt[1][1])
			st["t1"] = float(tt[2][1])
			at(st["t0"])
			await pick_card(1)
	await idle(3)
	shots.clear()
	for k in N:
		await drive(id, k, st)
		await shoot()
	return pack(id)


## the frames as one sheet (COLS wide) saved as <id>.png; returns the index entry
func pack(id: String) -> Dictionary:
	var rows := int(ceil(float(N) / COLS))
	var sheet := Image.create(COLS * W, rows * H, false, Image.FORMAT_RGB8)
	for i in N:
		sheet.blit_rect(shots[i], Rect2i(0, 0, W, H), Vector2i((i % COLS) * W, (i / COLS) * H))
	var path := ProjectSettings.globalize_path(OUT + id + ".png")
	sheet.save_png(path)
	var c: Dictionary = (CLIPS[id] as Dictionary).duplicate(true)
	c.erase("crop")
	c["sheet"] = id + ".png"
	c["frames"] = N
	c["cols"] = COLS
	c["view"] = crop
	var fa := FileAccess.open(path, FileAccess.READ)
	print("clip %-12s %d frames  %6.1f KB  buttons %s" % [id, N, fa.get_length() / 1024.0, c.get("buttons", []) + c.get("names", [])])
	return c


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var only := []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			only = a.substr(5).split(",")
	var man := {"fps": FPS, "w": W, "h": H, "generated_by": "tools/make_tip_clips.gd", "clips": {}}
	var old := TipVideo.load_manifest(OUT)
	if not old.is_empty():
		man["clips"] = old["clips"]
	for id in CLIPS:
		if only.is_empty() or id in only:
			man["clips"][id] = await make(id)
	var fa := FileAccess.open(ProjectSettings.globalize_path(OUT + "tips.json"), FileAccess.WRITE)
	fa.store_string(JSON.stringify(man, "\t"))
	fa.close()
	print("tips: %d clips, %.2f MB in assets/tips" % [man["clips"].size(), TipVideo.dir_bytes(OUT) / 1048576.0])
	quit(0)
