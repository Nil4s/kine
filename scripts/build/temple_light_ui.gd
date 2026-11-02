class_name TempleLightUI
extends RefCounted
## The "Light and camera" panel of item 232 (View ribbon): time of day, sun, exposure, haze, clouds, GI, camera by numbers, final-shot size.

static func _spin(lo: float, hi: float, step: float, tip: String) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.allow_greater = false
	s.custom_minimum_size = Vector2(88, 0)
	s.tooltip_text = tip
	return s


static func _row(vb: VBoxContainer, label: String, ctrls: Array) -> void:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(92, 0)
	h.add_child(l)
	for c in ctrls:
		h.add_child(c)
	vb.add_child(h)


static func build(m: Node) -> Control:
	var pc := PanelContainer.new()
	pc.name = "temple_panel"
	pc.position = Vector2(300, 90)
	pc.visible = false
	var vb := VBoxContainer.new()
	pc.add_child(vb)
	var t := Label.new()
	t.text = "LIGHT AND CAMERA (item 232)"
	vb.add_child(t)
	var knobs := {}
	for k in [["time", "Time of day (h)", 5.0, 19.0, 0.25], ["sun_az", "Sun direction", -180.0, 180.0, 5.0], ["exposure", "Exposure", 0.2, 4.0, 0.05],
			["haze", "Haze", 0.0, 4.0, 0.1], ["clouds", "Clouds", 0.0, 1.0, 0.05]]:
		var sp := _spin(k[2], k[3], k[4], String(k[1]))
		sp.name = "k_" + String(k[0])
		knobs[k[0]] = sp
		_row(vb, String(k[1]), [sp])
		sp.value_changed.connect(func(_v): _apply(pc, m))
	var gi := OptionButton.new()
	gi.name = "k_gi"
	for g in TempleLight.GI_MODES:
		gi.add_item(g)
	gi.item_selected.connect(func(_i): _apply(pc, m))
	_row(vb, "Bounce (GI)", [gi])
	var cp: Array = []
	for n in ["x", "y", "z"]:
		var s := _spin(-5000.0, 5000.0, 0.1, "camera position " + n + " (m)")
		s.name = "cp_" + n
		cp.append(s)
	_row(vb, "Camera pos", cp)
	var ct: Array = []
	for n in ["x", "y", "z"]:
		var s2 := _spin(-5000.0, 5000.0, 0.1, "look-at point " + n + " (m)")
		s2.name = "ct_" + n
		ct.append(s2)
	_row(vb, "Look at", ct)
	var fov := _spin(5.0, 120.0, 0.5, "vertical field of view (degrees)")
	fov.name = "cam_fov"
	var set_b := Button.new()
	set_b.text = "Set camera"
	set_b.pressed.connect(func(): _set_cam(pc, m))
	var get_b := Button.new()
	get_b.text = "Read camera"
	get_b.pressed.connect(func(): fill(pc, m))
	_row(vb, "FOV", [fov, set_b, get_b])
	var w := _spin(16, 8192, 1, "final shot width")
	w.name = "shot_w"
	var h := _spin(16, 8192, 1, "final shot height")
	h.name = "shot_h"
	_row(vb, "Shot size", [w, h])
	var go := Button.new()
	go.text = "Final shot"
	go.pressed.connect(func():
		TempleLight.final_size = Vector2i(int(w.value), int(h.value))
		m._temple_final_shot())
	vb.add_child(go)
	return pc


static func fill(pc: Control, m: Node) -> void:
	var s: Dictionary = TempleLight.settings_dict()
	for k in ["time", "sun_az", "exposure", "haze", "clouds"]:
		var sp := pc.find_child("k_" + k, true, false) as SpinBox
		if sp != null:
			sp.set_value_no_signal(float(s[k]))
	var gi := pc.find_child("k_gi", true, false) as OptionButton
	gi.select(TempleLight.GI_MODES.find(TempleLight.gi_mode))
	if m.cam != null:
		var c := TempleLight.get_camera(m)
		var p: Vector3 = c["pos"]
		var tg: Vector3 = c["target"]
		for i in 3:
			(pc.find_child("cp_" + ["x", "y", "z"][i], true, false) as SpinBox).set_value_no_signal(p[i])
			(pc.find_child("ct_" + ["x", "y", "z"][i], true, false) as SpinBox).set_value_no_signal(tg[i])
		(pc.find_child("cam_fov", true, false) as SpinBox).set_value_no_signal(float(c["fov"]))
	(pc.find_child("shot_w", true, false) as SpinBox).set_value_no_signal(TempleLight.final_size.x)
	(pc.find_child("shot_h", true, false) as SpinBox).set_value_no_signal(TempleLight.final_size.y)


static func _apply(pc: Control, m: Node) -> void:
	var p := {}
	for k in ["time", "sun_az", "exposure", "haze", "clouds"]:
		p[k] = (pc.find_child("k_" + k, true, false) as SpinBox).value
	p["gi"] = TempleLight.GI_MODES[(pc.find_child("k_gi", true, false) as OptionButton).selected]
	TempleLight.set_from(p)
	TempleLight.refresh(m)


static func _set_cam(pc: Control, m: Node) -> void:
	var p := Vector3((pc.find_child("cp_x", true, false) as SpinBox).value, (pc.find_child("cp_y", true, false) as SpinBox).value, (pc.find_child("cp_z", true, false) as SpinBox).value)
	var tg := Vector3((pc.find_child("ct_x", true, false) as SpinBox).value, (pc.find_child("ct_y", true, false) as SpinBox).value, (pc.find_child("ct_z", true, false) as SpinBox).value)
	TempleLight.set_camera(m, p, tg, (pc.find_child("cam_fov", true, false) as SpinBox).value)
