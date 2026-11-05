## BUILD STAGES panel of the Assembly screen (G33STAGE; the engine is scripts/build/assembly_stage.gd). The Stages button beside Check motion
## and BOM opens it on the left:
##   list        one row per stage in build order: its number, name, parts and seconds; a click picks the stage (its name and time below)
##   New stage   a stage at the end with the selected part; + Part puts the selected part into the picked stage, - Part takes it out of its
##               stage (it is then there from the start). Up / Down reorder, Delete removes the picked stage. Name and s (seconds) are typed.
##               Each change is ONE undo step (Ctrl+Z, AssemblyUI.undo_redo)
##   Check       the support check: each part must touch the ground or a part built before (or a chain in its own stage that does); parts
##               that pass through built parts are listed with the overlap. The flagged parts go red in the view
##   time        the slider and Play show the build: parts appear at their stage's start (and drop in when the record's stage_opts say so)
##   Video       films the build (AssemblyStage.video, 1280 x 720, the way the view looks); Cut films it cut in half toward the camera
## Opening, Check, the time and Close change nothing in the record.
class_name AssemblyStageUI
extends RefCounted

const W := 440.0
const BAD := Color(1.0, 0.12, 0.08, 0.6)

var a: AssemblyUI
var panel: PanelContainer
var info_l: Label
var list_vb: VBoxContainer
var name_e: LineEdit
var dur_e: LineEdit
var problems_l: Label
var time_sl: HSlider
var time_l: Label
var play_btn: Button
var video_btn: Button
var cut_btn: Button
var btns := {}
var sel_stage := -1
var time := -1.0            # the build shown at this time; -1 = everything (the panel just opened)
var playing := false
var filming := false
var last_check := {}
var bad_ids: Array = []
var _bad: StandardMaterial3D


func setup(owner: AssemblyUI) -> void:
	a = owner
	_bad = StandardMaterial3D.new()
	_bad.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_bad.albedo_color = BAD
	panel = PanelContainer.new()
	panel.name = "asm_stage_panel"
	panel.visible = false
	panel.add_theme_stylebox_override("panel", a.psb_of())
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	vb.add_child(a._lbl("BUILD STAGES", 15, "asm_stage_title"))
	info_l = a._lbl("", 12, "asm_stage_info")
	info_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_l.custom_minimum_size = Vector2(W - 24.0, 0)
	vb.add_child(info_l)
	var sc := ScrollContainer.new()
	sc.name = "asm_stage_scroll"
	sc.custom_minimum_size = Vector2(W - 20.0, 132)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_vb = VBoxContainer.new()
	list_vb.name = "asm_stage_list"
	list_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list_vb)
	vb.add_child(sc)
	var hn := HBoxContainer.new()
	hn.add_child(a._lbl("Name", 12))
	name_e = a._edit("asm_stage_name", 120)
	name_e.placeholder_text = "Name of the picked stage"
	name_e.text_submitted.connect(func(t: String): name_e.release_focus(); rename(t))
	hn.add_child(name_e)
	dur_e = a._edit("asm_stage_dur", 44)
	dur_e.size_flags_horizontal = Control.SIZE_SHRINK_END
	dur_e.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dur_e.tooltip_text = "How long the stage takes in the video, in seconds (one Ctrl+Z takes a change back)"
	dur_e.text_submitted.connect(func(t: String): dur_e.release_focus(); set_dur(a._num(t, 0.0)))
	hn.add_child(dur_e)
	hn.add_child(a._lbl("s", 12))
	vb.add_child(hn)
	_row(vb, [["New stage", "asm_stage_new", "A new stage at the end, with the selected part (pick parts in the list on the right)", new_stage],
		["+ Part", "asm_stage_addpart", "Put the selected part into the picked stage", add_part],
		["- Part", "asm_stage_rmpart", "Take the selected part out of its stage: it is there from the start", remove_part]])
	_row(vb, [["Up", "asm_stage_up", "Build the picked stage one step earlier", move.bind(-1)],
		["Down", "asm_stage_down", "Build the picked stage one step later", move.bind(1)],
		["Delete", "asm_stage_delete", "Delete the picked stage (its parts are then there from the start)", delete]])
	var ht := HBoxContainer.new()
	play_btn = a._btn("Play", "asm_stage_play", "Play the build: each stage's parts appear at its time", toggle_play)
	ht.add_child(play_btn)
	time_sl = HSlider.new()
	time_sl.name = "asm_stage_time"
	time_sl.focus_mode = Control.FOCUS_NONE
	time_sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_sl.custom_minimum_size = Vector2(120, 22)
	time_sl.tooltip_text = "The build at this time (on screen only)"
	time_sl.value_changed.connect(func(v: float): playing = false; _sync_play(); set_time(v))
	ht.add_child(time_sl)
	time_l = a._lbl("", 12, "asm_stage_at")
	time_l.custom_minimum_size.x = 44
	ht.add_child(time_l)
	vb.add_child(ht)
	var hb := HBoxContainer.new()
	var chk := a._btn("Check", "asm_stage_check", "Check that every part rests on the ground or on parts built before it, and passes through nothing built", run_check)
	video_btn = a._btn("Video", "asm_stage_video", "Film the build: PNG frames, a contact sheet and an .mp4, seen the way you look at it now", export_video)
	cut_btn = a._btn("Cut", "asm_stage_cut", "Film it cut in half toward the camera, to see inside", func(): pass, true)
	var close_btn := a._btn("Close", "asm_stage_close", "Close the stages: every part is shown again", close)
	for b in [chk, video_btn, cut_btn, close_btn]:
		(b as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(b)
		btns[String(b.name)] = b
	vb.add_child(hb)
	problems_l = a._lbl("", 12, "asm_stage_problems")
	problems_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	problems_l.custom_minimum_size = Vector2(W - 24.0, 0)
	vb.add_child(problems_l)
	a.m.ui_root.add_child(panel)


func _row(vb: VBoxContainer, defs: Array) -> void:
	var h := HBoxContainer.new()
	for d in defs:
		var b := a._btn(String(d[0]), String(d[1]), String(d[2]), d[3])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(b)
		btns[String(d[1])] = b
	vb.add_child(h)


func layout(at: Vector2) -> void:
	if panel.visible:
		panel.reset_size()
		panel.position = at
		panel.size.x = W


func is_open() -> bool:
	return panel != null and panel.visible


func open() -> void:
	if not a.on:
		a._say("Build stages work in the Assembly screen: BUILD > New assembly, or open a saved one")
		return
	if a.motion.is_open():
		a.motion.close()
	a.bom.close()
	a.src_open = false
	a._sync_src()
	panel.visible = true
	a.m.ui_root.move_child(panel, a.m.ui_root.get_child_count() - 1)
	a._frame()   # reframe for the panel: the model sat half behind it
	time = -1.0
	playing = false
	sel_stage = clampi(sel_stage, -1, AssemblyStage.stages(a.asm).size() - 1)
	_clear_check()
	refresh()
	var n := AssemblyStage.stages(a.asm).size()
	a._say("BUILD STAGES: %s" % ("%d stages, %s s" % [n, a._fmt(AssemblyStage.total(a.asm))] if n > 0 else "none yet. Select a part, then New stage"))


func close() -> void:
	if panel == null:
		return
	var was := panel.visible
	panel.visible = false
	playing = false
	time = -1.0
	_clear_check()
	if was:
		a._refresh(false)


func _clear_check() -> void:
	last_check = {}
	bad_ids = []
	if problems_l != null:
		problems_l.text = ""


## the panel from the record (after a change, an undo or a new assembly)
func refresh() -> void:
	if panel == null or not panel.visible:
		return
	var st := AssemblyStage.stages(a.asm)
	sel_stage = clampi(sel_stage, -1, st.size() - 1)
	for c in list_vb.get_children():
		list_vb.remove_child(c)
		c.queue_free()
	var names := {}
	for p in a.asm["parts"]:
		names[String(p["id"])] = String(p["name"])
	if st.is_empty():
		list_vb.add_child(a._lbl("No stages yet: select a part on the right, then New stage.", 12, "asm_stage_empty"))
	for i in st.size():
		var s: Dictionary = st[i]
		var b := Button.new()
		b.name = "asm_stage_row_%d" % i
		var pn: Array = (s.get("parts", []) as Array).map(func(id): return names.get(String(id), String(id)))
		b.text = "%d. %s: %s (%s s)" % [i + 1, String(s.get("name", "")), ", ".join(PackedStringArray(pn)) if not pn.is_empty() else "no parts", a._fmt(AssemblyStage.dur_of(s))]
		b.tooltip_text = b.text
		b.toggle_mode = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 13)
		b.set_pressed_no_signal(i == sel_stage)
		b.pressed.connect(pick.bind(i))
		list_vb.add_child(b)
	var free_n := 0
	for p in a.asm["parts"]:
		if AssemblyStage.stage_of(a.asm, String(p["id"])) < 0:
			free_n += 1
	info_l.text = "%d stages, %s s in all. %d parts in no stage are there from the start." % [st.size(), a._fmt(AssemblyStage.total(a.asm)), free_n]
	var has := sel_stage >= 0
	if not name_e.has_focus():
		name_e.text = String(st[sel_stage].get("name", "")) if has else ""
	if not dur_e.has_focus():
		dur_e.text = a._fmt(AssemblyStage.dur_of(st[sel_stage])) if has else ""
	name_e.editable = has
	dur_e.editable = has
	(btns["asm_stage_addpart"] as Button).disabled = not has or a.sel == ""
	(btns["asm_stage_rmpart"] as Button).disabled = a.sel == "" or AssemblyStage.stage_of(a.asm, a.sel) < 0
	(btns["asm_stage_new"] as Button).disabled = a.sel == ""
	(btns["asm_stage_up"] as Button).disabled = not has or sel_stage == 0
	(btns["asm_stage_down"] as Button).disabled = not has or sel_stage >= st.size() - 1
	(btns["asm_stage_delete"] as Button).disabled = not has
	play_btn.disabled = st.is_empty()
	video_btn.disabled = st.is_empty() or filming
	_sync_time()


func _sync_time() -> void:
	var L := AssemblyStage.total(a.asm)
	time_sl.set_block_signals(true)
	time_sl.min_value = 0.0
	time_sl.max_value = maxf(L, 0.001)
	time_sl.step = 1.0 / float(AssemblyStage.fps(a.asm))
	time_sl.value = time if time >= 0.0 else L
	time_sl.set_block_signals(false)
	time_l.text = "%s s" % String.num(time if time >= 0.0 else L, 2)


func _sync_play() -> void:
	if play_btn != null:
		play_btn.text = "Pause" if playing else "Play"


func pick(i: int) -> void:
	sel_stage = i
	refresh()


# ---------------------------------------------------------------- record changes: ONE undo step each

func _change(label: String, f: Callable) -> bool:
	var cp: Dictionary = a.asm.duplicate(true)
	if not bool(f.call(cp)):
		return false
	a.push_undo(label)
	a.asm = cp
	_clear_check()
	a._refresh(false)
	refresh()
	return true


func new_stage() -> void:
	if a.sel == "":
		a._say("Select a part first (the list on the right), then New stage")
		return
	var nm := AssemblyStage.free_stage_name(a.asm)
	var id := a.sel
	if _change("Stages: new stage %s" % nm, func(c): AssemblyStage.add_stage(c, nm, [id]); return true):
		sel_stage = AssemblyStage.stages(a.asm).size() - 1
		refresh()
		a._say("%s: %s" % [nm, _pname(id)])


func add_part() -> void:
	var i := sel_stage
	var id := a.sel
	if id == "" or i < 0:
		return
	if _change("Stages: %s into stage %d" % [_pname(id), i + 1], func(c): return AssemblyStage.add_part_to(c, i, id)):
		a._say("%s is built in stage %d" % [_pname(id), i + 1])


func remove_part() -> void:
	var id := a.sel
	if _change("Stages: %s out of its stage" % _pname(id), func(c): return AssemblyStage.remove_part(c, id)):
		a._say("%s is there from the start" % _pname(id))


func move(by: int) -> void:
	var i := sel_stage
	if _change("Stages: stage %d %s" % [i + 1, "up" if by < 0 else "down"], func(c): return AssemblyStage.move_stage(c, i, by)):
		sel_stage = i + by
		refresh()


func rename(t: String) -> void:
	var i := sel_stage
	if _change("Stages: rename stage %d" % (i + 1), func(c): return AssemblyStage.rename_stage(c, i, t)):
		a._say("Stage %d is %s" % [i + 1, t.strip_edges()])


func set_dur(s: float) -> void:
	var i := sel_stage
	if s <= 0.0:
		refresh()
		return
	_change("Stages: stage %d takes %s s" % [i + 1, a._fmt(s)], func(c): return AssemblyStage.set_dur(c, i, s))


func delete() -> void:
	var i := sel_stage
	if _change("Stages: delete stage %d" % (i + 1), func(c): return AssemblyStage.delete_stage(c, i)):
		sel_stage = mini(i, AssemblyStage.stages(a.asm).size() - 1)
		refresh()


func _pname(id: String) -> String:
	var i := Assembly.index_of(a.asm, id)
	return String(a.asm["parts"][i]["name"]) if i >= 0 else id


# ---------------------------------------------------------------- check, time, video

func run_check() -> Dictionary:
	last_check = AssemblyStage.check(a.asm)
	bad_ids = AssemblyStage.flagged(last_check)
	if String(last_check.get("why", "")) != "":
		problems_l.text = String(last_check["why"])
	elif bool(last_check["ok"]):
		problems_l.text = "No problems: all %d staged parts rest on the ground or on parts built before them, and pass through nothing built." % int(last_check["placed"])
	else:
		problems_l.text = "\n".join(AssemblyStage.words(last_check))
	a._refresh(false)
	a._say("Stages: %s" % ("checked, no problems" if bool(last_check.get("ok", false)) else "%d unsupported, %d overlaps" % [(last_check.get("unsupported", []) as Array).size(), (last_check.get("collisions", []) as Array).size()] if String(last_check.get("why", "")) == "" else String(last_check["why"])))
	return last_check


## red over the parts the last Check flagged
func overlay_of(id: String) -> Material:
	return _bad if is_open() and bad_ids.has(id) else null


## AssemblyUI._refresh: with a time on, only the parts built by then are shown (and a dropping part is lifted)
func apply(meshes: Dictionary) -> void:
	if not is_open() or time < 0.0 or not AssemblyStage.has_stages(a.asm):
		return
	var po := AssemblyStage.pose_at(a.asm, time)
	var vis: Array = po["visible"]
	var mv: Dictionary = po["moves"]
	for p in a.asm["parts"]:
		var id := String(p["id"])
		var mi: MeshInstance3D = meshes.get(id)
		if mi == null:
			continue
		mi.visible = vis.has(id)
		mi.transform = (mv[id] as Transform3D) * Assembly.xf_of(p) if mv.has(id) else Assembly.xf_of(p)


func set_time(t: float) -> void:
	time = clampf(t, 0.0, AssemblyStage.total(a.asm))
	_sync_time()
	a._refresh(false)


func toggle_play() -> void:
	if not AssemblyStage.has_stages(a.asm):
		a._say("Nothing to play: make a stage first (select a part, New stage)")
		return
	playing = not playing
	if playing and (time < 0.0 or time >= AssemblyStage.total(a.asm) - 1e-9):
		set_time(0.0)
	_sync_play()


## AssemblyUI._process: Play moves the time on
func tick(dt: float) -> void:
	if not playing:
		return
	if not is_open() or not AssemblyStage.has_stages(a.asm):
		playing = false
		_sync_play()
		return
	var L := AssemblyStage.total(a.asm)
	var t := minf(time + dt, L)
	set_time(t)
	if t >= L:
		playing = false
		_sync_play()


## the build filmed into <exports>/<name>_stages_<stamp>/ (frames, sheet.png, an .mp4 when ffmpeg is found); Cut: the half toward the camera cut away
func export_video(opts := {}) -> Dictionary:
	if filming or not AssemblyStage.has_stages(a.asm):
		return {}
	var o := {"width": 1280, "height": 720}
	var vd := Vector3(0.55, 0.4, 1.0)
	if a.m.cam != null:
		vd = a.m.cam.global_transform.basis.z
		o["view_dir"] = vd
	if cut_btn.button_pressed:
		var n := Vector3(vd.x, 0.0, vd.z).normalized() if Vector2(vd.x, vd.z).length() > 1e-6 else Vector3.BACK
		o["cut"] = {"n": n, "w": n.dot(Assembly.total_aabb(a.asm).get_center())}
	o.merge(opts, true)
	filming = true
	video_btn.disabled = true
	a._say("Filming %d frames of the build..." % AssemblyStage.frame_count(a.asm))
	var r: Dictionary = await AssemblyStage.video(a.m, a.asm, o)
	filming = false
	video_btn.disabled = false
	r["text"] = ("Filmed %d frames to %s: sheet.png%s" % [int(r["n"]), String(r["dir"]).get_file(), ", " + String(r["mp4"]).get_file() if String(r.get("mp4", "")) != "" else " (no .mp4: ffmpeg was not found)"]) if bool(r.get("ok", false)) else "NOT DONE: " + String(r.get("why", ""))
	a.last_export = r
	a._say(String(r["text"]))
	return r
