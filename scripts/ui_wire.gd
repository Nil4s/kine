class_name UiWire
extends RefCounted
## L95 UIWIRE: features that were merged as agent tools only, reachable by a user. One small panel (palette: "Key this property", "Weight: open the mass
## slider", "Quaternion view: show the readout") plus palette commands. Every control calls the SAME code the agent tool calls, so the result is
## byte-identical to the tool's (tests/uiwire_test.gd):
##   Key this property   -> Main._anykey_put (tool `anykey`); the registries AnyKey.targets / AnyKey.meshes are filled from the stage's real
##                          lights, floor and skin material and the open model / sculpt meshes (register) when a scene opens, a mesh opens, or a key is put
##   Rig: mirror ...     -> RigAnimServe (tool `rig_anim`)
##   React: ...          -> ReactWeightServe (tools `react_time`, `react_place`); the mass slider -> ReactWeightServe `weight_slider` on release
##   quaternion readout  -> QuatCurve.view (tool `euler_warp` quat), read only
## A keyed id whose target is not registered is kept in the scene and skipped at playback; here it is NOT silent: skipped() lists it, the panel
## and the status line say so.
## The graph editor's own controls (Ghost, Alt-drag weight, channel picker, Interp menu) live in scripts/curve_editor.gd.

var m: Node
var panel: PanelContainer
var id_pick: OptionButton
var id_edit: LineEdit
var value_box: SpinBox
var key_btn: Button
var report: Label
var weight_slider: HSlider
var weight_label: Label
var quat_label: Label
var last_say := ""   # the last thing this wire said to the status line (the status label may be rewritten by easy mode)


func _init(main: Node) -> void:
	m = main


## fill the AnyKey registries from the stage's real objects
static func register(main: Node) -> void:
	var t := {}
	for pr in [["key", main.light_key], ["fill", main.light_fill], ["rim", main.light_rim], ["floor", main.floor_mat], ["skin", main.body_skin]]:
		if pr[1] != null and is_instance_valid(pr[1]):
			t[pr[0]] = pr[1]
	AnyKey.targets = t
	var ms := {}
	if main.kmed != null and main.kmed.mesh != null:
		ms["cube"] = main.kmed.mesh
	if main.ksc != null and main.ksc.mesh != null:
		ms["sphere"] = main.ksc.mesh
	AnyKey.meshes = ms


## the keyed ids of the scene whose target is not registered (skipped at playback)
static func skipped(S: Scene) -> Array:
	var out := []
	for id in S.anykeys:
		var p := String(id).split(":", true, 2)
		if p.size() != 3:
			out.append(id)
		elif p[0] == "shape":
			var mesh = AnyKey.meshes.get(p[1])
			if mesh == null or KMeshShapes.find(mesh, p[2]) < 0:
				out.append(id)
		elif p[0] == "prop":
			var o = AnyKey.targets.get(p[1])
			if o == null or not is_instance_valid(o):
				out.append(id)
		else:
			out.append(id)
	return out


## every id the registries can key
static func ids() -> Array:
	var out := []
	for n in AnyKey.targets:
		var o = AnyKey.targets[n]
		if o is Light3D:
			out.append(AnyKey.prop_id(String(n), "light_energy"))
		elif o is BaseMaterial3D:
			out.append(AnyKey.prop_id(String(n), "roughness"))
			out.append(AnyKey.prop_id(String(n), "metallic"))
	for n in AnyKey.meshes:
		for k in KMeshShapes.keys(AnyKey.meshes[n]):
			out.append(AnyKey.shape_id(String(n), String(k["name"])))
	return out


func say(t: String) -> void:
	last_say = t
	m._say(t)


func commands(add: Callable) -> void:
	add.call("Key this property", "", open, "key this property anykey any key shape key weight material roughness metallic light energy animate dope sheet register skipped", true,
		"opens the wire panel: pick a shape key, material or light value (or type its id), set a value, press Key: it is keyed at the playhead (one undo step). An id with no registered target is kept but skipped at playback, and the panel says so (L13/L15)")
	add.call("Rig: mirror the pose", "", rig_mirror.bind("pose"), "rig mirror pose custom own rig left right symmetry bones", true,
		"on the scene's own (imported) rig: the pose of every left bone is copied mirrored onto its right partner and back (names first, then position); one undo step (L18)")
	add.call("Rig: mirror the keys", "", rig_mirror.bind("keys"), "rig mirror keys animation custom own rig left right symmetry bones", true,
		"on the scene's own (imported) rig: every left bone's keys are mirrored onto its right partner and back; one undo step (L18)")
	add.call("React: place the block after the cue", "", react.bind(true), "react reaction time block defender attacker cue 0.29 superhuman place", true,
		"the defender's block starts 0.29 s after the attacker's cue (the measured human reaction time), the rest of its timing unchanged; one undo step; refused with a reason when there is no cue or no block (L29)")
	add.call("React: read the timing", "", react.bind(false), "react reaction time block defender attacker cue gap superhuman read check", false,
		"says when the attacker's cue is and how long after it the defender blocks, and whether a person could (superhuman under 0.20 s); changes nothing (L29)")
	add.call("Weight: open the mass slider", "", open, "weight mass slider heavier lighter log2 ratio swing anticipation settle", false,
		"opens the wire panel with the mass slider: release it and the clip is retimed for that mass (log2 of the mass ratio), one undo step (L23)")
	add.call("Quaternion view: show the readout", "", open, "quaternion view readout w x y z rotation euler slerp part", false,
		"opens the wire panel with a read-only readout of the picked part's world rotation as a quaternion at the playhead (L04)")


func _ensure() -> void:
	if panel != null:
		return
	panel = PanelContainer.new()
	panel.name = "uiwire_panel"
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -420.0
	panel.offset_right = -12.0
	panel.offset_top = 96.0
	panel.visible = false
	var v := VBoxContainer.new()
	panel.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var title := Label.new()
	title.text = "Key a property / mass / quaternion"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var close := Button.new()
	close.text = "Close"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func(): panel.visible = false)
	top.add_child(close)
	id_pick = OptionButton.new()
	id_pick.tooltip_text = "the shape keys, materials and lights the scene registered"
	id_pick.item_selected.connect(func(i): id_edit.text = id_pick.get_item_text(i))
	v.add_child(id_pick)
	id_edit = LineEdit.new()
	id_edit.placeholder_text = "id: prop:key:light_energy  or  shape:cube:smile"
	v.add_child(id_edit)
	var row := HBoxContainer.new()
	v.add_child(row)
	value_box = SpinBox.new()
	value_box.min_value = -10000.0
	value_box.max_value = 10000.0
	value_box.step = 0.01
	value_box.allow_greater = true
	value_box.allow_lesser = true
	value_box.tooltip_text = "the value to key at the playhead"
	row.add_child(value_box)
	key_btn = Button.new()
	key_btn.text = "Key at playhead"
	key_btn.focus_mode = Control.FOCUS_NONE
	key_btn.pressed.connect(_key)
	row.add_child(key_btn)
	report = Label.new()
	report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	report.custom_minimum_size = Vector2(380, 0)
	v.add_child(report)
	v.add_child(HSeparator.new())
	var wrow := HBoxContainer.new()
	v.add_child(wrow)
	var wl := Label.new()
	wl.text = "Mass"
	wrow.add_child(wl)
	weight_slider = HSlider.new()
	weight_slider.min_value = -3.0
	weight_slider.max_value = 3.0
	weight_slider.step = 0.25
	weight_slider.value = 0.0
	weight_slider.custom_minimum_size = Vector2(220, 20)
	weight_slider.tooltip_text = "log2 of the mass ratio: 1 = twice as heavy, -1 = half; release to retime the clip"
	weight_slider.drag_ended.connect(func(_changed): apply_weight())
	wrow.add_child(weight_slider)
	var wb := Button.new()
	wb.text = "Apply"
	wb.focus_mode = Control.FOCUS_NONE
	wb.pressed.connect(apply_weight)
	wrow.add_child(wb)
	weight_label = Label.new()
	weight_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	weight_label.custom_minimum_size = Vector2(380, 0)
	v.add_child(weight_label)
	v.add_child(HSeparator.new())
	quat_label = Label.new()
	quat_label.text = "quaternion: pick a part"
	v.add_child(quat_label)
	m.ui_root.add_child(panel)


func open() -> void:
	_ensure()
	register(m)
	_fill_ids()
	refresh_report()
	panel.visible = true
	refresh()


func _fill_ids() -> void:
	if id_pick == null:
		return
	id_pick.clear()
	for id in ids():
		id_pick.add_item(String(id))


func _key() -> void:
	var id := id_edit.text.strip_edges()
	if id.split(":", true, 2).size() != 3:
		say("type an id like prop:key:light_energy or shape:cube:smile (or pick one from the list), then press Key")
		return
	m._anykey_put(id, value_box.value)


## after any key is put (here or by the tool): registries current, the panel's list and report current, an unregistered id said out loud
func after_key(id: String) -> void:
	_ensure()
	_fill_ids()
	refresh_report()
	if skipped(m.S).has(id):
		say("%s is not registered in this scene (no such mesh, material or light): the key is saved but skipped at playback" % id)


func after_open() -> void:
	_ensure()
	_fill_ids()
	refresh_report()
	var sk := skipped(m.S)
	if not sk.is_empty():
		say("%d keyed propert%s not registered here, skipped at playback: %s" % [sk.size(), "y is" if sk.size() == 1 else "ies are", ", ".join(PackedStringArray(sk))])


func refresh_report() -> void:
	if report == null:
		return
	var sk := skipped(m.S)
	if sk.is_empty():
		report.text = "every keyed id has a registered target"
		return
	var s := ""
	for id in sk:
		s += "%s: not registered, skipped at playback\n" % id
	report.text = s.strip_edges()


func rig_mirror(what: String) -> void:
	m._step_hint = "Rig: mirror the " + what
	var r := RigAnimServe.serve(m, {"action": "mirror", "what": what})
	m._step_hint = ""
	if not bool(r["ok"]):
		say("Rig: " + String(r["error"]))
		return
	m._refresh()
	say("rig mirrored (%s): left and right bones swapped, mirrored  (Ctrl+Z takes it back)" % what)


func react(place: bool) -> void:
	var r := ReactWeightServe.serve("react_place" if place else "react_time", m, {})
	if not bool(r["ok"]):
		say("React: " + String(r["error"]))
		return
	var res: Dictionary = r["result"]
	if place:
		say("React: " + String(res.get("msg", "the block is placed")) + "  (Ctrl+Z takes it back)")
	else:
		say("React timing: %s; the block starts %.2f s after the cue (a person needs 0.29 s; under 0.20 s is superhuman)" % [String(res.get("status", "?")), float(res.get("gap", 0.0))])


func apply_weight() -> void:
	var r := ReactWeightServe.serve("weight_slider", m, {"value": weight_slider.value})
	if not bool(r["ok"]):
		say("Weight: " + String(r["error"]))
		return
	weight_label.text = String(r["result"].get("msg", ""))
	say(weight_label.text + "  (Ctrl+Z takes it back)")


## the read-only quaternion of the picked part's world rotation at the playhead (QuatCurve.view, the tool `euler_warp` quat)
func refresh() -> void:
	if panel == null or not panel.visible or quat_label == null:
		return
	var j := String(m.sel)
	if not (j in Body.ORDER):
		quat_label.text = "quaternion: pick a body part"
		return
	var fr: Array = QuatCurve.view(m.S, j, float(m.playhead), float(m.playhead), float(m.S.fps))
	if fr.is_empty():
		quat_label.text = "quaternion: none"
		return
	var f: Array = fr[0]
	quat_label.text = "quaternion %s  w=%.5f x=%.5f y=%.5f z=%.5f" % [j, float(f[1]), float(f[2]), float(f[3]), float(f[4])]
