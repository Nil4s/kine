## impact_clip_ui.gd - the "Impact frames" toggle of plan 137 (scripts/impact_clip.gd). The SET ribbon's "Impact frames" button opens the
## findings panel with: the toggle (ic_toggle), the Hit-stop slider (ic_stop, 0-6 frames, default 3), the Shake slider (ic_amp, cm) and a
## status line. On: the first contact of a hand / weapon with a prop is found and the clip gets the hold, flash and shake (ONE undo step);
## off: the clip is as it was; moving a slider while on writes the clip again (one undo step). sync() puts the flash on the prop each _refresh.
class_name ImpactClipUI
extends RefCounted

var m: Node
var stop := ImpactClip.STOP_DEFAULT
var amp := ImpactClip.AMP_DEFAULT
var tog: CheckButton = null
var s_stop: HSlider = null
var s_amp: HSlider = null
var status: Label = null
var lit: Array = []          # the MeshInstance3Ds that carry the flash material now
var _mat: StandardMaterial3D = null
var _quiet := false


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Impact frames panel", "", show, "impact frames hit stop flash shake strike punch target box contact toggle slider",
		false, "the Impact frames toggle: the first frame a hand or weapon touches a prop, the clip holds for 0-6 frames, the target flashes white for 2 frames and the shot camera shakes for 0.25 s (plan 137)")


func hero() -> Scene:
	m._actors_sync()
	return m._hero_scene()


func show() -> void:
	var L: VBoxContainer = m.ui_find_list
	for c in L.get_children():
		L.remove_child(c)
		c.queue_free()
	var head := HBoxContainer.new()
	L.add_child(head)
	var title: Label = m._label("IMPACT FRAMES", 18, "heading")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(m._button("Close", m._close_findings))
	var st := ImpactClip.settings(hero())
	if not st.is_empty():
		stop = int(st["frames"])
		amp = float(st["amp"])
	tog = CheckButton.new()
	tog.name = "ic_toggle"
	tog.text = "Impact frames"
	tog.tooltip_text = "on: where a hand or weapon first touches a prop, the clip holds, the target flashes white and the shot camera shakes; off: the clip as it was"
	tog.button_pressed = not st.is_empty()
	tog.toggled.connect(_on_toggle)
	L.add_child(tog)
	s_stop = _row(L, "Hit-stop (frames)", "ic_stop", 0.0, float(ImpactClip.STOP_MAX), 1.0, float(stop), _on_stop)
	s_amp = _row(L, "Shake (cm)", "ic_amp", 0.0, ImpactClip.AMP_MAX, 0.1, amp, _on_amp)
	status = m._label("Needs a prop in the set (Add prop > box) that a hand or weapon of the clip reaches.", 13, "text:0.6", true)
	status.name = "ic_status"
	status.custom_minimum_size = Vector2(380, 0)
	L.add_child(status)
	(m.ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(400, 190)
	m.ui_find.visible = true


func _row(L: VBoxContainer, text: String, nm: String, lo: float, hi: float, step: float, v: float, cb: Callable) -> HSlider:
	var r := HBoxContainer.new()
	var lb: Label = m._label(text, 14, "text:0.85")
	lb.custom_minimum_size = Vector2(130, 0)
	r.add_child(lb)
	var s := HSlider.new()
	s.name = nm
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = v
	s.custom_minimum_size = Vector2(190, 24)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(cb)
	r.add_child(s)
	L.add_child(r)
	return s


func _say(t: String) -> void:
	if is_instance_valid(status):
		status.text = t
	m._say(t)


func _on_stop(v: float) -> void:
	stop = int(v)
	_rebake()


func _on_amp(v: float) -> void:
	amp = v
	_rebake()


func _on_toggle(on: bool) -> void:
	if _quiet:
		return
	if on:
		_bake(true)
	else:
		_unbake()


func _set_tog(on: bool) -> void:
	_quiet = true
	if is_instance_valid(tog):
		tog.button_pressed = on
	_quiet = false


## the clip with the impact frames: one undo step
func _bake(step: bool) -> bool:
	m._actors_sync()
	m._actor_set(0)
	var S: Scene = m.S
	if ImpactFrames.already(S) and ImpactClip.settings(S).is_empty():
		_say("this clip already has impact frames from the fighters: use 'Remove impact frames' first")
		_set_tog(false)
		return false
	if not ImpactClip.settings(S).is_empty():
		return true
	var c := ImpactClip.find_contact(S, m.B)
	if c.is_empty():
		_say("no hand or weapon of this clip touches a prop: add a box in front of the fighter (Add prop) and punch into it")
		_set_tog(false)
		return false
	if step:
		m._step_hint = "Impact frames"
		m._push_undo()
	ImpactClip.apply(S, m.B, c, stop, amp)
	m._retimed()
	m.ui_find.visible = true   # _retimed closes the findings panel; this one stays for the sliders
	_say("impact frames: %s touches the %s at %s: hold %d frame%s, flash %d frames, camera shake %.1f cm for %.2f s (Ctrl+Z undoes)" % [
		String(c["part"]).replace("_", " "), String(S.props[int(c["prop"])]["kind"]), Units.time(float(c["t"]), S.fps), stop,
		"" if stop == 1 else "s", ImpactClip.FLASH_FRAMES, amp, ImpactClip.SHAKE_DUR])
	return true


func _unbake() -> void:
	m._actors_sync()
	m._actor_set(0)
	if ImpactClip.settings(m.S).is_empty():
		return
	m._step_hint = "Impact frames off"
	m._push_undo()
	ImpactClip.remove(m.S)
	m._retimed()
	m.ui_find.visible = true   # _retimed closes the findings panel; this one stays for the sliders
	_say("impact frames off: the clip is as it was (Ctrl+Z puts them back)")


func _rebake() -> void:
	if is_instance_valid(tog) and tog.button_pressed and not ImpactClip.settings(hero()).is_empty():
		m._actor_set(0)
		m._step_hint = "Impact frames"
		m._push_undo()
		ImpactClip.remove(m.S)
		_bake(false)


## each _refresh: the flash is on the target's mesh while the playhead is on its frames, off otherwise
func sync() -> void:
	var want: Array = []
	if not m.S.markers.is_empty():
		want = ImpactClip.flash_props(m.S, m.playhead)
	if want.is_empty() and lit.is_empty():
		return
	for mi in lit:
		if is_instance_valid(mi):
			(mi as MeshInstance3D).material_override = null
	lit = []
	if m.ui_props_root == null:
		return
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = ImpactClip.FLASH_COLOR
		_mat.emission_enabled = true
		_mat.emission = ImpactClip.FLASH_COLOR
		_mat.emission_energy_multiplier = 4.0
	for i in want:
		var n: Node = m.ui_props_root.get_node_or_null("prop_%d" % int(i))
		if n == null:
			continue
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = _mat
			lit.append(mi)
