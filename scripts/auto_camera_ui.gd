## AUTO CAMERA panel (ROADMAP I7; the film grammar: scripts/auto_camera.gd). Kept out of main.gd: main makes one (main.ac_ui) and lists
## its command. "Auto camera" opens a strip of GHOST FRAMES, one per beat (wind-up, contact, recover): a thumbnail rendered through
## the suggested camera, the rule behind it, and a Keep button. NOTHING is written until a click: Keep writes that one shot (one
## undo step), Keep all writes every suggested shot (one undo step). The thumbnails are drawn off screen (a SubViewport with its
## own world and a mannequin per fighter), so the window's view does not move.
class_name AutoCamUI
extends RefCounted

const TW := 192    # thumbnail size, px (16:9)
const TH := 108

var m: Node
var res: Dictionary = {}
var sugs: Array = []
var kept := {}              # beat -> true once written
var panel: PanelContainer
var thumbs: Array = []      # TextureRect per suggestion
var ms := 0.0
var _vp: SubViewport
var _cam: Camera3D
var _men: Array = []        # [{"root": Node3D, "sk": Skeleton3D, "idx": Dictionary}] per fighter
var _bodies: Array = []
var thumbs_done := false
var _gen := 0               # a newer show() makes older renders stop


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Auto camera", "", show, "auto camera shot film grammar 180 deg rule lead room close up low angle wide contact wind-up recover ghost frames suggest cut",
		false, "for the strike: a shot camera per beat (wind-up, contact, recover) from film grammar, each with its rule named, as small ghost frames; click one to keep it as a shot, Keep all keeps them all; nothing changes until you click")


func show() -> void:
	if m.S.cards.size() < 2:
		m._say("Auto camera needs a scene of two cards or more: press Enter to add the body as a card (two at least), or open a scene in the list below")
		return
	var keep: Dictionary = m.B.state()   # compute poses private bodies; the app's own is untouched, this is the belt
	var t0 := Time.get_ticks_usec()
	res = AutoCam.compute(m._hero_scene())
	ms = float(Time.get_ticks_usec() - t0) / 1000.0
	m.B.set_state(keep)
	sugs = res["sugs"]
	kept = {}
	if sugs.is_empty():
		m._say(String(res["why"]))
		hide()
		return
	_build()
	_render_all()
	m._say("auto camera: %d shots suggested (%.0f ms). Click Keep under one to write it as a shot (Ctrl+Z undoes), Keep all for every one; nothing changes until you click" % [sugs.size(), ms])


func hide() -> void:
	_gen += 1
	if panel != null and is_instance_valid(panel):
		panel.visible = false


func _build() -> void:
	if panel != null and is_instance_valid(panel):
		panel.queue_free()
	panel = PanelContainer.new()
	panel.name = "autocam_panel"
	var st := StyleBoxFlat.new()
	st.bg_color = Tok.c("float")
	st.set_corner_radius_all(8)
	st.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", st)
	m.ui_root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title: Label = m._label("AUTO CAMERA  -  %d shots for card %d (%s)" % [sugs.size(), int((res["beats"] as Dictionary)["c"]) + 1,
		"action line: between the fighters" if bool(res.get("two", false)) else "action line: his facing"], 14, "warn")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var all: Button = m._button("Keep all", keep_all, "keep every suggested shot above as a shot of the scene; one undo step")
	all.name = "ac_keep_all"
	head.add_child(all)
	head.add_child(m._button("Close", hide, "close the strip; the scene is untouched"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	thumbs = []
	for k in sugs.size():
		var s: Dictionary = sugs[k]
		var col := VBoxContainer.new()
		col.custom_minimum_size = Vector2(TW, 0)
		col.add_theme_constant_override("separation", 2)
		row.add_child(col)
		var pc := PanelContainer.new()
		var fs := StyleBoxFlat.new()
		fs.bg_color = Tok.c("float")
		fs.set_border_width_all(2)
		fs.border_color = Tok.c("warn")
		fs.set_content_margin_all(2)
		pc.add_theme_stylebox_override("panel", fs)
		col.add_child(pc)
		var tr := TextureRect.new()
		tr.name = "ac_thumb_%d" % (k + 1)
		tr.custom_minimum_size = Vector2(TW, TH)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.modulate = Color(1, 1, 1, 0.85)   # a ghost until it is kept
		pc.add_child(tr)
		thumbs.append(tr)
		var t1: Label = m._label("%s  at %.2f s" % [s["label"], float(s["cut"])], 13, "text")
		t1.name = "ac_label_%d" % (k + 1)
		col.add_child(t1)
		var t2: Label = m._label("rule: %s" % s["rule"], 13, "warn", true)
		t2.name = "ac_rule_%d" % (k + 1)
		t2.custom_minimum_size = Vector2(TW, 0)
		col.add_child(t2)
		var kb: Button = m._button("Keep this shot", keep.bind(k), String(s["why"]))
		kb.name = "ac_keep_%d" % (k + 1)
		col.add_child(kb)
	panel.visible = true
	_place_panel.call_deferred()


func _place_panel() -> void:
	if panel == null or not is_instance_valid(panel):
		return
	var fr: Rect2 = m._shot_free()   # the strip sits along the bottom of the 3D view: the head and the strike stay in sight above it
	var sz := panel.get_combined_minimum_size()
	panel.size = sz
	panel.position = Vector2(fr.position.x + (fr.size.x - sz.x) * 0.5, fr.position.y + fr.size.y - sz.y - 4.0)


# ---------------------------------------------------------------- the thumbnails

func _stage(n: int) -> void:
	if _vp == null or not is_instance_valid(_vp):
		_vp = SubViewport.new()
		_vp.name = "autocam_stage"
		_vp.size = Vector2i(TW, TH)
		_vp.own_world_3d = true
		_vp.msaa_3d = Viewport.MSAA_4X
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		m.add_child(_vp)
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = PoseLibrary.BG
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(1, 1, 1)
		env.ambient_light_energy = 0.45
		var we := WorldEnvironment.new()
		we.environment = env
		_vp.add_child(we)
		var key := DirectionalLight3D.new()
		key.rotation_degrees = Vector3(-40, 35, 0)
		key.light_energy = 1.1
		_vp.add_child(key)
		var fill := DirectionalLight3D.new()
		fill.rotation_degrees = Vector3(-15, -140, 0)
		fill.light_energy = 0.35
		_vp.add_child(fill)
		var fl := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(40, 40)
		fl.mesh = pm
		var fm := StandardMaterial3D.new()
		fm.albedo_color = PoseLibrary.BG.darkened(0.25)
		fl.material_override = fm
		_vp.add_child(fl)
		_cam = Camera3D.new()
		_cam.near = 0.05
		_cam.far = 60.0
		_vp.add_child(_cam)
		_cam.current = true
	while _men.size() < n:
		var root := Node3D.new()
		_vp.add_child(root)
		var skin := StandardMaterial3D.new()
		skin.albedo_color = PoseLibrary.SKIN if _men.is_empty() else Color(0.55, 0.68, 0.85)
		skin.roughness = 0.55
		var mq := Overlays.mannequin(root, skin)
		_men.append({"root": root, "sk": mq[1], "idx": mq[2]})


func _render_all() -> void:
	_gen += 1
	thumbs_done = false
	var g := _gen
	var S: Scene = m._hero_scene()
	var n := 1 + S.actors.size()
	_stage(n)
	_bodies = AutoCam.bodies_for(S)
	for k in sugs.size():
		if g != _gen:
			return
		var s: Dictionary = sugs[k]
		for q in n:
			var sc: Scene = S if q == 0 else S.actors[q - 1]["scene"]
			sc.apply(_bodies[q], float(s["t"]))
			(_bodies[q] as Body).fk()
			Overlays.pose_skeleton(_men[q]["sk"], _men[q]["idx"], _bodies[q])
			(_men[q]["root"] as Node3D).transform = Transform3D.IDENTITY if q == 0 else AutoCam.actor_xf(S.actors[q - 1]["xf"])
		var key: Dictionary = s["key"]
		ShotCam.apply_to(_cam, ShotCam.xf(key["pos"], key["aim"]), float(key["f"]), Rect2i(0, 0, TW, TH), Vector2(TW, TH))
		await m.get_tree().process_frame
		if g != _gen or _vp == null or not is_instance_valid(_vp):
			return
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		if g != _gen or _vp == null or not is_instance_valid(_vp):
			return
		var img := _vp.get_texture().get_image()
		if img != null and not img.is_empty() and k < thumbs.size() and is_instance_valid(thumbs[k]):
			(thumbs[k] as TextureRect).texture = ImageTexture.create_from_image(img)
	if g == _gen:
		thumbs_done = true


## wait until the thumbnails are drawn (tests)
func settle() -> void:
	var n := 0
	while not thumbs_done and n < 600:
		await m.get_tree().process_frame
		n += 1


# ---------------------------------------------------------------- keeping

func keep(k: int) -> void:
	_write([k])


func keep_all() -> void:
	_write(range(sugs.size()))


func _write(ix: Array) -> void:
	if ix.is_empty() or sugs.is_empty():
		return
	var fps: int = m.S.fps
	var did := []
	var skipped := []
	m._step_hint = "Auto camera: keep" + (" all" if ix.size() > 1 else "")
	m._do(func():
		for i in ix:
			if AutoCam.add_shot(m._shot_shots(), sugs[i], fps):
				did.append(i)
			else:
				skipped.append(i))
	for i in did:
		kept[sugs[i]["beat"]] = true
		if i < thumbs.size() and is_instance_valid(thumbs[i]):
			(thumbs[i] as TextureRect).modulate = Color(1, 1, 1, 1)
			var b = panel.find_child("ac_keep_%d" % (i + 1), true, false)
			if b != null:
				(b as Button).text = "Kept"
	var sh: Array = m._shot_shots()
	m._say("auto camera: %d shot%s written (Ctrl+Z undoes them in one step); the scene has %d shots now%s" % [did.size(), "" if did.size() == 1 else "s", sh.size(),
		"" if skipped.is_empty() else "; %d skipped because a shot already starts on that frame: move or delete that shot, then keep again" % skipped.size()])
