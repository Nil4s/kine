## DEFORMATION GRADED OVER THE SCENE, the app side (ROADMAP_400 H17; the maths: scripts/deform_scene.gd).
## Kept out of main.gd: main makes one (main.ds_ui), lists its commands, calls tick() each frame.
##   "Check: deformation over the scene"  grades every frame of the open scene off the UI thread (main-thread slices of
##        DeformScene.BUDGET_MS, the skinning on a Thread; progress in the status line, the window keeps drawing). Then:
##        the worst frames in the findings panel, worst first, one per moment ("frame 41: left elbow -17% volume, ...");
##        a click goes to the frame and stands the skin as it deforms there as a ghost, its joint regions tinted by grade
##        (red = past a bar); red blocks on the timeline's red lane (the one Make it physical uses) where any joint passes
##        a bar; a click on one goes to its worst frame, with its ghost.
##   "Deformation over the scene: off"   the lane, the ghost and the panel away.
## View only: the body, the cards and the skin are never edited (the frames are posed on a scratch body; the skeleton is put
## back inside every slice).
class_name DeformSceneUI
extends RefCounted

var m: Node
var job := DeformScene.new()
var res := {}
var lane := []              # what we put on the timeline's red lane (ours while ui_timeline.ph is this array)
var ghost: MeshInstance3D = null
var ghost_frame := -1
var tick_ms := []           # the start's and each tick's main-thread time while a job ran, ms: the UI stall this costs
var _say_t := 0.0
var _hooked := false


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Check: deformation over the scene", "", run, "deform deformation volume loss skin stretch squash collapse candy wrapper scene frames worst frames elbow knee shoulder hip spine weights linear blend", false,
		"every frame of the scene skinned as weighted and graded per joint against rest: volume lost and the worst skin stretch / squash; the worst frames listed (click one: the playhead goes there and the deformed skin stands as a ghost), red on the timeline where a joint passes a bar (15% volume, 2x stretch). Runs off the UI thread (ROADMAP_400 H17). View only")
	add.call("Deformation over the scene: off", "", clear, "deform deformation ghost off clear lane", false, "take the deformation lane, ghost and list away")


func run() -> void:
	if m.wp.is_empty():
		m._say("Deformation over the scene needs a body with a skin: pick the mannequin")
		return
	if job.running():
		m._say("still grading the skin: %d %% done" % int(job.progress * 100.0))
		return
	var t0 := Time.get_ticks_usec()
	var err := job.begin(m.wp, m.skel, m.bone_idx, m._ps(), func(): Overlays.pose_skeleton(m.skel, m.bone_idx, m.B))
	if err != "":
		m._say(err)
		return
	tick_ms = [float(Time.get_ticks_usec() - t0) / 1000.0]   # the start counts as a stall too
	_say_t = 0.0
	m._say("grading the skin over every frame of '%s' (keep working; the list opens when it is done)..." % m.S.name)


func tick(dt: float) -> void:
	if not job.running():
		return
	var t0 := Time.get_ticks_usec()
	var done := job.step()
	if done:
		_landed()
	else:
		_say_t += dt
		if _say_t > 1.0:
			_say_t = 0.0
			m._say("grading the skin: %d %%" % int(job.progress * 100.0))
	tick_ms.append(float(Time.get_ticks_usec() - t0) / 1000.0)


func longest_tick() -> float:
	var w := 0.0
	for t in tick_ms:
		w = maxf(w, float(t))
	return w


func _landed() -> void:
	res = job.res
	_put_lane(res["spans"])
	_panel()
	var red := 0
	for f in res["frames"]:
		if float(f["sev"]) >= 1.0:
			red += 1
	var w: Array = res["worst"]
	m._say("deformation: %d of %d frames past a bar%s" % [red, res["frames"].size(), "; worst " + str(w[0]["text"]) if not w.is_empty() else ""])


func _put_lane(spans: Array) -> void:
	var tl: Timeline = m.ui_timeline
	if tl == null:
		return
	if m.mp_ui != null and not m.mp_ui.mp.spans.is_empty():
		m.mp_ui.clear()   # one red lane: Make it physical's spans give way (run it again to bring them back)
	var before := tl.ph_px()
	lane = spans
	tl.ph = lane
	tl.ph_sel = -1
	if not _hooked:
		_hooked = true
		tl.ph_picked.connect(_lane_pick)
	if before != tl.ph_px():
		m._tl_height()
		m._layout_bottom()
	tl.queue_redraw()


## a red block clicked: the timeline scrubs to its start first, then we go to its worst frame
func _lane_pick(i: int) -> void:
	if lane.is_empty() or m.ui_timeline.ph != lane or i < 0 or i >= lane.size():
		return
	m.ui_timeline.ph_sel = i
	goto.call_deferred(int(lane[i]["frame"]))


func _panel() -> void:
	for c in m.ui_find_list.get_children():
		m.ui_find_list.remove_child(c)
		c.queue_free()
	var red := 0
	for f in res["frames"]:
		if float(f["sev"]) >= 1.0:
			red += 1
	var head := HBoxContainer.new()
	m.ui_find_list.add_child(head)
	var title: Label = m._label("DEFORMATION OVER THE SCENE  -  %d of %d frames red" % [red, res["frames"].size()], 18, "heading")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(m._button("Close", close))
	m.ui_find_list.add_child(m._label(("%d frames at %d Hz, %d triangles, graded in %d ms off the UI thread. Each joint against rest: the volume its skin " +
		"holds and the worst stretch / squash. Red (timeline too): %d%% volume lost or skin stretched %.0fx. Worst first, one per moment; click one to go " +
		"there and see the skin as it deforms (a ghost, tinted by grade).") % [res["frames"].size(), roundi(float(res["fps"])), res["tris"], res["ms"],
		roundi(DeformScene.VOL_BAR * 100.0), DeformScene.STRETCH_BAR], 13, "text:0.6", true))
	var w: Array = res["worst"]
	for k in w.size():
		var e: Dictionary = w[k]
		var b := Button.new()
		b.name = "dscene_%d" % (k + 1)
		b.text = "%d.  %s" % [k + 1, e["text"]]
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(380, 0)
		b.add_theme_font_size_override("font_size", 14)
		b.add_theme_color_override("font_color", DeformCheck.sev_color(_f14_sev(float(e["sev"]))))
		var f: int = e["frame"]
		b.pressed.connect(func(): goto(f))
		m.ui_find_list.add_child(b)
	(m.ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(400, clampf(140.0 + 46.0 * w.size(), 60.0,
		minf(440.0, m.get_viewport().get_visible_rect().size.y - m.bottom_h - 82 - (m.TOP_H + 12) - 26)))
	m.ui_find.visible = true


## our grade (1.0 = a bar) on F14's colour scale: red past the bar, amber from half of it, blue under
static func _f14_sev(sev: float) -> float:
	return DeformCheck.BREAKS if sev >= 1.0 else (DeformCheck.OK_BELOW if sev >= 0.5 else 0.0)


## the playhead to frame f and the skin as it deforms there as a ghost
func goto(f: int) -> void:
	if res.is_empty():
		return
	m.playing = false
	m.playhead = clampf(float(f) / float(res["fps"]), 0.0, m.S.length())
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	show_ghost(f)
	var g: Dictionary = res["frames"][f]
	m._say(str(g["text"]) + "  (the ghost is the skin at this frame: red where a joint passes a bar)")


## the ghost of frame f (one of the listed frames or a red span's worst): false when there is none for it
func show_ghost(f: int) -> bool:
	if not res.get("ghosts", {}).has(f):
		hide_ghost()
		return false
	var gd: Dictionary = res["ghosts"][f]
	var sev: PackedFloat32Array = gd["sev"]
	var cols := PackedColorArray()
	cols.resize(sev.size())
	var c_red := Tok.c("fd_active")
	c_red.a = 0.6
	var c_amb := Tok.of("warn")
	c_amb.a = 0.45
	var c_off := Tok.of("info")
	c_off.a = 0.16
	for i in sev.size():
		cols[i] = c_red if sev[i] >= 1.0 else (c_amb if sev[i] >= 0.5 else c_off)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = gd["pos"]
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = res["T"]
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	if ghost == null:
		ghost = MeshInstance3D.new()
		ghost.name = "DeformGhost"
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		ghost.material_override = mat
		ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.add_child(ghost)
	ghost.mesh = am
	ghost.visible = true
	ghost_frame = f
	return true


func hide_ghost() -> void:
	if ghost != null:
		ghost.visible = false
	ghost_frame = -1


## the panel's Close: the panel and the ghost away (the lane stays until "off" or another lane)
func close() -> void:
	m._close_findings()


func clear() -> void:
	job.stop()
	hide_ghost()
	if m.ui_timeline != null and not lane.is_empty() and m.ui_timeline.ph == lane:
		var tl: Timeline = m.ui_timeline
		var before := tl.ph_px()
		tl.ph = []
		if before != tl.ph_px():
			m._tl_height()
			m._layout_bottom()
		tl.queue_redraw()
	lane = []
	if m.ui_find.visible and m.ui_find_list.find_child("dscene_1", true, false) != null:
		m._close_findings()
	m._say("deformation lane and ghost off")
