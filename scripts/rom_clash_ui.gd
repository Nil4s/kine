## RANGE-OF-MOTION CLASH + CLOTHES-SAFE CLEARANCE, the app side (ROADMAP_400 B24 ★, B25 ★; the maths: scripts/rom_clash.gd).
## Kept out of main.gd: main makes one (main.clash_ui), lists its commands, calls tick() each frame.
##   "Check: armour clash, range of motion (ROM test)"  the parts on the fighter (B23's plates) against the body over a
##        built-in sweep of every joint that can move them against it, to F14's limits. "Check: armour clash over the
##        scene": over every frame of the open scene. Both off the UI thread (H17's sampler: main-thread slices of
##        DeformScene.BUDGET_MS; the measuring on WorkerThreadPool tasks); progress in the status line. Then:
##        the worst frames in the findings panel, worst first, one per moment ("frame 67, left elbow bend 145°: armour_1
##        (biceps_l) 4.0 mm into the left biceps"); a click shows that frame (the scene's: the playhead goes there; the
##        ROM test's: the fighter stands in that pose until the panel closes) and lights the offending vertices up RED
##        (their triangles, drawn over everything, so a plate inside the arm still shows); in the model preview (the body
##        open, G01) the overlay sits on the preview with the posed body as a faint ghost. Over the scene, red blocks on the
##        timeline's red lane (H17's / Make it physical's) where a part cuts in; a click goes to its worst frame.
##        B25 under the list: per part its minimum clearance over the whole motion and the frame of it, the verts within
##        1 cm (a warning), and "Heat map": the part drawn green (> 1 cm) / yellow (0..1 cm) / red (inside) by that minimum.
##   "Armour clash: clearance heat map"  the heat map on / off (after a check).
##   "Armour clash: off"  the lane, the overlay, the heat map and the panel away; the pose put back.
## View only: the body, the parts, the scene and the skin are never edited (no undo step).
class_name RomClashUI
extends RefCounted

var m: Node
var job := RomClash.new()
var res := {}
var lane := []              # what we put on the timeline's red lane (ours while ui_timeline.ph is this array)
var overlay: Node3D = null  # the red triangles (and, in the model preview, the posed body as a ghost)
var shown := -1             # the frame the overlay shows
var heat := []              # the heat-map copies drawn now
var _hid := []              # what the heat map hides while it shows (the parts, their preview copies)
var tick_ms := []           # the start's and each tick's main-thread time while a job ran, ms: the UI stall this costs
var _say_t := 0.0
var _hooked := false
var _posed := false         # the fighter stands in a ROM pose (put back by hide_overlay / clear)
var _parts := []            # the MeshInstance3Ds the last job measured, in its order
var _landq := []            # the landing's steps (lane, panel, the status line), one per tick: none of them a stall


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Check: armour clash, range of motion (ROM test)", "", run.bind("rom"), "armour armor clash range of motion rom test sweep joint limits cuts into body penetration interpenetration intersect plate part collision clearance elbow shoulder knee vambrace pauldron", false,
		"B24: every joint that can move the armour against the body swept to its limits (F14's ranges); the frames where a part cuts into the body or another part listed worst first (click one: the fighter in that pose, the offending verts lit red), with B25's clearance per part (within 1 cm = a warning; a heat map). Runs off the UI thread. View only")
	add.call("Check: armour clash over the scene", "", run.bind("scene"), "armour armor clash scene animation frames cuts into body penetration intersect plate part collision clearance clothes safe 1 cm", false,
		"B24 / B25 over every frame of the open scene: where an added part cuts into the body (red on the timeline's lane, the worst frames listed, the offending verts lit red) and each part's minimum clearance to the skin over the whole animation. Runs off the UI thread. View only")
	add.call("Armour clash: clearance heat map", "", toggle_heat, "clearance heat map clothes safe armour armor 1 cm warning green yellow red inside skin distance", false,
		"B25: the checked parts drawn by their minimum clearance to the skin over the motion: green > 1 cm, yellow 0..1 cm, red inside (run a clash check first)")
	add.call("Armour clash: off", "", clear, "armour armor clash off clear lane overlay heat map", false, "take the clash lane, overlay, heat map and list away")


## the op from the model preview (mesh_tools "op:romclash"): the ROM test; -> what it said
func run_said(how: String) -> String:
	run(how)
	return String(m.ui_status.text) if m.get("ui_status") != null else ""


func run(how := "rom") -> void:
	if job.running():
		m._say("still checking the armour: %d %% done" % int(job.progress * 100.0))
		return
	var t0 := Time.get_ticks_usec()
	hide_overlay()
	_landq = []   # a new check: the last one's landing is not run
	var err := job.begin_clash(m, how)
	if err != "":
		m._say(err)
		return
	_parts = load("res://scripts/armour_from_body.gd").parts(m).filter(func(x): return is_instance_valid(x) and (x as Node).is_inside_tree())
	tick_ms = [float(Time.get_ticks_usec() - t0) / 1000.0]   # the start counts as a stall too
	_say_t = 0.0
	m._say(("checking the armour over a range-of-motion sweep (%d poses)" % job._nf if how == "rom" else "checking the armour over every frame of '%s'" % m.S.name) + " (keep working; the list opens when it is done)...")


func tick(dt: float) -> void:
	if not _landq.is_empty():
		var t1 := Time.get_ticks_usec()
		var f: Callable = _landq.pop_front()
		f.call()
		tick_ms.append(float(Time.get_ticks_usec() - t1) / 1000.0)
		return
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
			m._say("checking the armour: %d %%" % int(job.progress * 100.0))
	tick_ms.append(float(Time.get_ticks_usec() - t0) / 1000.0)


func longest_tick() -> float:
	var w := 0.0
	for t in tick_ms:
		w = maxf(w, float(t))
	return w


func _clashing() -> int:
	var n := 0
	for f in res["frames"]:
		if float(f["sev"]) > RomClash.EPS_IN:
			n += 1
	return n


## the result is in: the lane (the scene), the panel and the status line are each their own tick (a tick each, so the
## landing is not one long stall: the lane and the panel measured ~2 ms each, the status line's undo naming more)
func _landed() -> void:
	res = job.res
	_landq = []
	if String(res.get("mode", "")) == "scene":
		_landq.append(func(): _put_lane(res["spans"]))
	_landq.append(_panel)
	_landq.append(_say_landed)


func _say_landed() -> void:
	var w: Array = res["worst"]
	m._say("armour clash: %d of %d %s cut in%s" % [_clashing(), res["frames"].size(), "poses" if res["mode"] == "rom" else "frames",
		"; worst " + str(w[0]["text"]) if not w.is_empty() else ""])


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


func _lane_pick(i: int) -> void:
	if lane.is_empty() or m.ui_timeline.ph != lane or i < 0 or i >= lane.size():
		return
	m.ui_timeline.ph_sel = i
	goto.call_deferred(int(lane[i]["frame"]))


func _panel() -> void:
	for c in m.ui_find_list.get_children():
		m.ui_find_list.remove_child(c)
		c.queue_free()
	var rom: bool = res["mode"] == "rom"
	var head := HBoxContainer.new()
	m.ui_find_list.add_child(head)
	var title: Label = m._label("ARMOUR CLASH  -  %s: %d of %d %s cut in" % ["ROM TEST" if rom else "OVER THE SCENE", _clashing(), res["frames"].size(), "poses" if rom else "frames"], 18, "heading")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var hb: Button = m._button("Heat map", toggle_heat)
	hb.name = "romclash_heat"
	head.add_child(hb)
	head.add_child(m._button("Close", close))
	m.ui_find_list.add_child(m._label(("%d %s, skinned %s, measured in %d ms off the UI thread. A part vertex inside the body skin (or inside another part) cuts in; " +
		"its depth is its distance to the nearest skin. Worst first, one per moment; click one to see it (the offending verts lit red).") % [res["frames"].size(),
		"poses (each joint that can move the armour, to its limits)" if rom else "frames at %d Hz" % roundi(float(res["fps"])), DqSkin.describe(float(res["k"])) if float(res["k"]) > 0.0 else "by linear blend",
		res["ms"]], 13, "text:0.6", true))
	var w: Array = res["worst"]
	for k in w.size():
		var e: Dictionary = w[k]
		var b := Button.new()
		b.name = "romclash_%d" % (k + 1)
		b.text = "%d.  %s  (%d verts)" % [k + 1, e["text"], e["n"]]
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(380, 0)
		b.add_theme_font_size_override("font_size", 14)
		b.add_theme_color_override("font_color", DeformCheck.sev_color(DeformCheck.BREAKS))
		var f: int = e["frame"]
		b.pressed.connect(func(): goto(f))
		m.ui_find_list.add_child(b)
	if w.is_empty():
		m.ui_find_list.add_child(m._label("Nothing cuts in: no part vertex is inside the body or another part in any %s." % ("pose" if rom else "frame"), 14, "text", true))
	# B25
	m.ui_find_list.add_child(m._label("CLEARANCE over the whole %s (B25: within %s of the skin = a warning)" % ["sweep" if rom else "animation", Units.len(RomClash.WARN)], 15, "heading"))
	for pi in (res["parts"] as Array).size():
		var pd: Dictionary = res["parts"][pi]
		var lo: float = pd["low"]
		var lv: int = pd["low_v"]
		var where := ""
		if lv >= 0:
			var f: int = (pd["minf"] as PackedInt32Array)[lv]
			where = " at %s %d%s" % ["pose" if rom else "frame", f, (" (" + String(res["labels"][f]) + ")") if rom and String(res["labels"][f]) != "" else ""]
		var lb: Label = m._label("%s: closest %s%s; %d red (inside), %d yellow (under %s), %d green" % [pd["name"],
			(Units.len(-lo) + " inside") if lo < 0.0 else (Units.len(lo) if lo < RomClash.CAP else "over " + Units.len(RomClash.CAP)), where,
			pd["red"], pd["yellow"], Units.len(RomClash.WARN), pd["green"]], 13, "text", true)
		lb.name = "romclash_part_%d" % (pi + 1)
		if int(pd["red"]) + int(pd["yellow"]) > 0:
			lb.add_theme_color_override("font_color", RomClash.heat(lo))
		m.ui_find_list.add_child(lb)
	(m.ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(400, clampf(200.0 + 46.0 * w.size() + 22.0 * (res["parts"] as Array).size(), 60.0,
		minf(480.0, m.get_viewport().get_visible_rect().size.y - m.bottom_h - 82 - (m.TOP_H + 12) - 26)))
	m.ui_find.visible = true


## show frame f: the scene's (the playhead goes there) or the ROM test's (the fighter stands in that pose), with the overlay
func goto(f: int) -> void:
	if res.is_empty() or f < 0 or f >= (res["frames"] as Array).size():
		return
	if res["mode"] == "scene":
		m.playing = false
		m.playhead = clampf(float(f) / float(res["fps"]), 0.0, m.S.length())
		m._ps().apply(m.B, m.playhead)
		m._refresh()
	else:
		var G := Body.new()
		G.load_files("res://data/skeleton.json", "res://data/body_limits.json")
		job._scene.apply(G, float(f) / float(res["fps"]))
		Overlays.pose_skeleton(m.skel, m.bone_idx, G)
		if m.get("dq_skin_pass") != null and float(m.S.dq_skin) > 0.0:
			m.dq_skin_pass.update(m.S.dq_skin)
		_posed = true
	show_overlay(f)
	m._say(str(res["frames"][f]["text"]) + "  (red: the part's verts that cut in at this %s)" % ("pose" if res["mode"] == "rom" else "frame"))


## the offending verts of frame f (per part: vertex -> true)
func offending(f: int) -> Array:
	var out := []
	var g: Dictionary = res["per"][f]
	for pi in (g["clr"] as Array).size():
		var clr: PackedFloat32Array = g["clr"][pi]
		var pv: PackedFloat32Array = g["pv"][pi]
		var d := {}
		for i in clr.size():
			if -clr[i] > RomClash.EPS_IN or pv[i] > RomClash.EPS_IN:
				d[i] = true
		out.append(d)
	return out


static func _mat(col: bool, on_top: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = col
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if on_top:
		mat.no_depth_test = true
		mat.render_priority = 10
	return mat


## the red overlay of frame f (one of the listed frames, a span's worst or a part's minimum): false when there is none
func show_overlay(f: int) -> bool:
	hide_overlay(false)
	if not res.get("posed", {}).has(f):
		return false
	var off := offending(f)
	var posed: Array = res["posed"][f]
	var pos := PackedVector3Array()
	var cols := PackedColorArray()
	var red := Color(1.0, 0.08, 0.06)
	for pi in posed.size():
		var pp: PackedVector3Array = posed[pi]
		var T: PackedInt32Array = res["parts"][pi]["T"]
		var o: Dictionary = off[pi]
		for t in range(0, T.size(), 3):
			if o.has(T[t]) or o.has(T[t + 1]) or o.has(T[t + 2]):
				for c in [0, 2, 1]:
					pos.append(pp[T[t + c]])
					cols.append(red)
	overlay = Node3D.new()
	overlay.name = "RomClashOverlay"
	if not pos.is_empty():
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = pos
		arr[Mesh.ARRAY_COLOR] = cols
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mi := MeshInstance3D.new()
		mi.name = "clash_red"
		mi.mesh = am
		mi.material_override = _mat(true, true)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		overlay.add_child(mi)
	if BaseBody.is_open(m):   # the model preview: the overlay on the preview, the posed body as a faint ghost
		var bp: PackedVector3Array = res["bpos"][f]
		var arr2 := []
		arr2.resize(Mesh.ARRAY_MAX)
		arr2[Mesh.ARRAY_VERTEX] = bp
		arr2[Mesh.ARRAY_INDEX] = res["bodyT"]
		var am2 := ArrayMesh.new()
		am2.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr2)
		var gh := MeshInstance3D.new()
		gh.name = "clash_body"
		gh.mesh = am2
		var gm := _mat(false, false)
		gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gm.albedo_color = Color(0.75, 0.78, 0.85, 0.22)
		gh.material_override = gm
		gh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		overlay.add_child(gh)
		var view: Node3D = m.kmed.view
		view.add_child(overlay)
		overlay.transform = (m.pieces.values()[0] as Node3D).global_transform.affine_inverse()
	else:
		m.add_child(overlay)
	shown = f
	return true


## the overlay away (and the fighter's own pose back when a ROM pose stood there)
func hide_overlay(pose_back := true) -> void:
	if overlay != null and is_instance_valid(overlay):
		if overlay.get_parent() != null:
			overlay.get_parent().remove_child(overlay)
		overlay.queue_free()
	overlay = null
	shown = -1
	if pose_back and _posed:
		_posed = false
		Overlays.pose_skeleton(m.skel, m.bone_idx, m.B)
		if m.get("dq_skin_pass") != null and float(m.S.dq_skin) > 0.0:
			m.dq_skin_pass.update(m.S.dq_skin)


## B25's heat map on / off: each checked part drawn by its minimum clearance (green / yellow / red), skinned like it (it
## follows every pose); in the model preview, over the part's preview copy
func toggle_heat() -> void:
	if not heat.is_empty():
		heat_off()
		m._say("clearance heat map off")
		return
	if res.is_empty() or _parts.size() != (res["parts"] as Array).size():
		m._say("run a clash check first (Check: armour clash, range of motion)")
		return
	var open := BaseBody.is_open(m)
	for pi in _parts.size():
		var mi: MeshInstance3D = _parts[pi]
		if not is_instance_valid(mi):
			continue
		var pd: Dictionary = res["parts"][pi]
		var minc: PackedFloat32Array = pd["minc"]
		var k := RomClash.part_kmesh(mi, mi.skin)
		var cols := PackedColorArray()
		for i in k.verts.size():
			cols.append(RomClash.heat(minc[i]) if i < minc.size() else Color.GRAY)
		var idx := PackedInt32Array()
		var T: PackedInt32Array = pd["T"]
		for t in range(0, T.size(), 3):
			idx.append_array([T[t], T[t + 2], T[t + 1]])
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = k.verts
		arr[Mesh.ARRAY_COLOR] = cols
		arr[Mesh.ARRAY_INDEX] = idx
		var hm := MeshInstance3D.new()
		hm.name = "clash_heat_%d" % (pi + 1)
		hm.material_override = _mat(true, false)
		hm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if open:
			var am := ArrayMesh.new()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			hm.mesh = am
			var view: Node3D = m.kmed.view
			for c in view.get_children():
				if c.has_meta("armour_of") and c.get_meta("armour_of") == mi and (c as Node3D).visible:
					(c as Node3D).visible = false
					_hid.append(c)
			view.add_child(hm)
		else:
			var inf := RomClash.infl4(k, mi.skin, m.skel)
			arr[Mesh.ARRAY_BONES] = inf[0]
			arr[Mesh.ARRAY_WEIGHTS] = inf[1]
			var am := ArrayMesh.new()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			hm.mesh = am
			hm.skin = mi.skin
			hm.transform = mi.transform
			mi.get_parent().add_child(hm)
			hm.skeleton = mi.skeleton
			if mi.visible:
				mi.visible = false
				_hid.append(mi)
		heat.append(hm)
	m._say("clearance heat map: green over %s from the skin all through the motion, yellow within it, red inside" % Units.len(RomClash.WARN))


func heat_off() -> void:
	for h in heat:
		if is_instance_valid(h):
			if (h as Node).get_parent() != null:
				(h as Node).get_parent().remove_child(h)
			(h as Node).queue_free()
	heat = []
	for n in _hid:
		if is_instance_valid(n):
			(n as Node3D).visible = true
	_hid = []


## the panel's Close: the panel and the overlay away (the lane stays until "off")
func close() -> void:
	m._close_findings()


func clear() -> void:
	job.stop()
	hide_overlay()
	heat_off()
	if m.ui_timeline != null and not lane.is_empty() and m.ui_timeline.ph == lane:
		var tl: Timeline = m.ui_timeline
		var before := tl.ph_px()
		tl.ph = []
		if before != tl.ph_px():
			m._tl_height()
			m._layout_bottom()
		tl.queue_redraw()
	lane = []
	if m.ui_find.visible and m.ui_find_list.find_child("romclash_heat", true, false) != null:
		m._close_findings()
	m._say("armour clash lane, overlay and heat map off")
