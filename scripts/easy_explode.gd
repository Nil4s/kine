## s262 EXPLODED VIEW panel (Easy Part, Parts > Hinges page, and the Ctrl+K row "Easy Part: Exploded view"): Direction, Layers, Gap, Camera and the button
## "Exploded view". One press plans the order (scripts/build/explode_view.gd: no body sweeps through another), then plays out, hold and in on the part
## on screen (a VIEW only: the record and the undo stack are untouched). "Put back" shows the part as it is. The words under the button give the order.
extends VBoxContainer

var ep: Node
var dir_opt: OptionButton
var lay_opt: OptionButton
var gap_edit: LineEdit
var cam_check: CheckBox
var go_btn: Button
var back_btn: Button
var report: Label
var plan := {}
var sched := {}
var cam_frames: Array = []
var src_mesh: ArrayMesh
var playing := false
var t := 0.0
var last_words := ""
var cam_share := 0.8   # the share of the picture the pieces fill when the camera follows (the Easy Part panel covers the right third: tests use less)


func setup(easy: Node) -> void:
	ep = easy
	name = "easypart_explode"
	visible = false
	add_theme_constant_override("separation", 3)
	var words := Label.new()
	words.text = "Exploded view: pull the pieces apart so none passes through another"
	words.add_theme_font_size_override("font_size", 13)
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(words)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	add_child(hb)
	dir_opt = OptionButton.new()
	dir_opt.name = "easypart_explode_dir"
	for o in ["Up / down", "Left / right", "Front / back"]:
		dir_opt.add_item(o)
	hb.add_child(dir_opt)
	lay_opt = OptionButton.new()
	lay_opt.name = "easypart_explode_layers"
	for o in ["Each body a layer", "Same level = one layer"]:
		lay_opt.add_item(o)
	hb.add_child(lay_opt)
	var hb2 := HBoxContainer.new()
	hb2.add_theme_constant_override("separation", 4)
	add_child(hb2)
	var l := Label.new()
	l.text = "Gap mm"
	l.add_theme_font_size_override("font_size", 13)
	hb2.add_child(l)
	gap_edit = LineEdit.new()
	gap_edit.name = "easypart_explode_gap"
	gap_edit.text = "10"
	gap_edit.custom_minimum_size = Vector2(52, 0)
	hb2.add_child(gap_edit)
	cam_check = CheckBox.new()
	cam_check.name = "easypart_explode_camera"
	cam_check.text = "Camera follows"
	cam_check.add_theme_font_size_override("font_size", 13)
	hb2.add_child(cam_check)
	go_btn = Button.new()
	go_btn.name = "easypart_explode_go"
	go_btn.text = "Exploded view"
	go_btn.focus_mode = Control.FOCUS_NONE
	go_btn.tooltip_text = "Find an order that takes every body out without passing through another, and play it out and back in (a view only)"
	go_btn.pressed.connect(press)
	add_child(go_btn)
	back_btn = Button.new()
	back_btn.name = "easypart_explode_back"
	back_btn.text = "Put back"
	back_btn.focus_mode = Control.FOCUS_NONE
	back_btn.pressed.connect(put_back)
	add_child(back_btn)
	report = Label.new()
	report.name = "easypart_explode_report"
	report.add_theme_font_size_override("font_size", 12)
	report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(report)
	set_process(false)


func _axis() -> Vector3:
	return [Vector3.UP, Vector3.RIGHT, Vector3.BACK][dir_opt.selected]


## bodies of the part on screen: world boxes (a surface is one body, as in the Pull apart slider)
func _bodies() -> Dictionary:
	var pu = ep.pu
	var pm: MeshInstance3D = pu.part_mesh
	if pm == null or pm.mesh == null:
		return {}
	var src: ArrayMesh = pu.res.get("mesh", null)
	if src == null or src.get_surface_count() < 2:
		return {}
	var xf: Transform3D = pm.global_transform
	var boxes: Array = []
	var names: Array = []
	var bn: Array = pu.res.get("body_names", [])
	for s in src.get_surface_count():
		var vs: PackedVector3Array = src.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for v in vs:
			var w := xf * v
			lo = lo.min(w)
			hi = hi.max(w)
		boxes.append(AABB(lo, hi - lo))
		names.append(String(bn[s]) if s < bn.size() and String(bn[s]) != "" else "Body%d" % (s + 1))
	return {"boxes": boxes, "names": names, "src": src}


## plan + schedule (+ camera). Returns {ok, words, collisions (of the plan), naive_collisions, order}
func make(axis: Vector3, gap_mm: float, by_level: bool, with_cam: bool, dur := 1.0, stagger := 0.4) -> Dictionary:
	var b := _bodies()
	if b.is_empty():
		return {"ok": false, "why": "Exploded view needs a part with two or more bodies"}
	var boxes: Array = b["boxes"]
	var layers: Array = ExplodeView.level_layers(boxes, axis) if by_level else ExplodeView.body_layers(boxes.size())
	plan = ExplodeView.plan(boxes, layers, axis, gap_mm * Part.MM)
	if not bool(plan.get("ok", false)):
		return {"ok": false, "why": String(plan.get("why", "no plan"))}
	sched = ExplodeView.schedule(plan, dur, stagger, 0.5)
	src_mesh = b["src"]
	var ck := ExplodeView.check(plan, sched)
	var nk := ExplodeView.check(plan, ExplodeView.naive_schedule(plan, dur, stagger, 0.5))
	last_words = ExplodeView.words(plan, b["names"])
	cam_frames = []
	if with_cam:
		var g := FrameFacts.gather(ep.m)
		var cam0 := FrameFacts.camera_of(ep.m, {})
		if bool(cam0.get("ok", false)) and (g["names"] as Array).size() == boxes.size():
			var lob: Array = []
			lob.resize(boxes.size())
			for u in (plan["units"] as Array).size():
				for bi in plan["units"][u]:
					lob[int(bi)] = u
			var times: Array = [0.0]
			for u in (plan["order"] as Array):
				times.append(float(sched["out_end"][u]))
			times.sort()
			cam_frames = ExplodeView.camera_frames(g, cam0, plan, sched, times, lob, cam_share)
	return {"ok": true, "words": last_words, "collisions": (ck["collisions"] as Array).size(), "naive_collisions": (nk["collisions"] as Array).size(),
		"order": plan["order"], "stuck": plan["stuck"], "cams": cam_frames.size()}


## the part on screen at time t (also the camera when frames were made)
func show_at(tt: float) -> void:
	if plan.is_empty():
		return
	var pm: MeshInstance3D = ep.pu.part_mesh
	var offs := ExplodeView.offsets_at(plan, sched, tt)
	var inv: Basis = pm.global_transform.basis.inverse()
	var out := ArrayMesh.new()
	var unit_of := {}
	for u in (plan["units"] as Array).size():
		for bi in plan["units"][u]:
			unit_of[int(bi)] = u
	for s in src_mesh.get_surface_count():
		var arr: Array = src_mesh.surface_get_arrays(s)
		var off: Vector3 = inv * (offs[int(unit_of.get(s, 0))] as Vector3)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var mv := PackedVector3Array()
		mv.resize(vs.size())
		for i in vs.size():
			mv[i] = vs[i] + off
		arr[Mesh.ARRAY_VERTEX] = mv
		out.add_surface_from_arrays(src_mesh.surface_get_primitive_type(s), arr)
	pm.mesh = out
	ep.pu._look_surfaces()
	_apply_cam(tt)


func _apply_cam(tt: float) -> void:
	if cam_frames.size() < 2:
		return
	var out_total: float = sched["out_total"]
	var tq := tt if tt <= out_total else maxf(2.0 * out_total + float(sched["hold"]) - tt, 0.0)   # in = out backwards
	var i := 0
	while i < cam_frames.size() - 2 and tq > float(cam_frames[i + 1]["t"]):
		i += 1
	var a: Dictionary = cam_frames[i]
	var b: Dictionary = cam_frames[i + 1]
	var f := ExplodeView.smooth((tq - float(a["t"])) / maxf(float(b["t"]) - float(a["t"]), 1e-6))
	TempleLight.set_camera(ep.m, (a["pos"] as Vector3).lerp(b["pos"], f), (a["target"] as Vector3).lerp(b["target"], f), lerpf(float(a["fov"]), float(b["fov"]), f))


func press() -> void:
	var gt := gap_edit.text.strip_edges().replace("mm", "")
	var g := float(gt) if gt.is_valid_float() else 0.0
	if g <= 0.0:
		ep._say("Type a gap in mm (more than 0)")
		return
	var r := make(_axis(), g, lay_opt.selected == 1, cam_check.button_pressed)
	if not bool(r["ok"]):
		ep._say(String(r["why"]))
		report.text = String(r["why"])
		return
	report.text = "Order: %s. %s" % [r["words"], "No body passes through another." if int(r["collisions"]) == 0 else "%d clashes: some bodies are locked in" % int(r["collisions"])]
	ep._say("Exploded view: " + String(r["words"]))
	t = 0.0
	playing = true
	set_process(true)


func _process(dt: float) -> void:
	if not playing:
		return
	t += dt
	if t >= float(sched["total"]):
		t = float(sched["total"])
		playing = false
		set_process(false)
	show_at(t)


func put_back() -> void:
	playing = false
	set_process(false)
	if not plan.is_empty() and ep.pu.part_mesh != null and src_mesh != null:
		ep.pu.part_mesh.mesh = src_mesh
		ep.pu._look_surfaces()
	plan = {}
	if ep.pu.part_mesh != null:
		ep.pu.upto = -1
		ep.pu.sync()   # the shown mesh is the one the part builds, as before the view
