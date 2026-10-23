class_name RealSizeUI
extends PanelContainer
## B27 on the model preview: "Model: real-size check" (mesh_tools op "realsize") turns this readout on / off. It sits
## NEXT TO THE MODEL (beside the screen box of its oriented bounding box, right first, then left, below, above; never over
## another panel; kept inside the free view) and says the box's three sides, the kind (a picker: auto = RealSize's guess)
## and the verdict with the reference length it used. The box is drawn round the model (12 lines, no depth test, in the
## verdict's colour). A units slip shows a button: one click rescales (one KMeshUndo step; also the op "realsize_fix").
## The check runs again when the mesh, the fighter's proportions or the pick change (polled every RECHECK s).

const NODE := "real_size_readout"
const GAP := 14.0          # px between the model's screen box and the readout
const PAD := 8.0           # px kept clear of the view's edge and of other panels
const RECHECK := 0.25      # s between looks for a change
const WIDTH := 330.0

var m: Node
var ui: Node               # the KMeshEditUI
var pick := "auto"
var result := {}
var screen_box := Rect2()  # the model's box on screen, the last place()
var _sig := 0
var _t := 0.0
var _dims: Label
var _say: Label
var _kind: OptionButton
var _fix: Button
var _lines: MeshInstance3D


## the op: on (and the check said in the status line) / off. -> what was said
static func toggle(main: Node) -> String:
	var r := get_or_null(main)
	if r != null and r.visible:
		r.close()
		main._say("Model: real-size readout off")
		return "Model: real-size readout off"
	if r == null:
		r = RealSizeUI.new()
		r.setup(main)
	r.visible = true
	return r.recheck(true)


static func get_or_null(main: Node) -> RealSizeUI:
	return main.ui_root.get_node_or_null(NODE) as RealSizeUI if main.get("ui_root") != null else null


## the op "realsize_fix": apply the units fix the last check found
static func fix_op(main: Node) -> String:
	var r := get_or_null(main)
	if r == null:
		r = RealSizeUI.new()
		r.setup(main)
		r.visible = true
	r.recheck(false)
	return r.rescale()


func setup(main: Node) -> void:
	m = main
	ui = main.kmed
	name = NODE
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	var st := StyleBoxFlat.new()
	st.bg_color = Color(Tok.c("float"), 0.94)
	st.set_corner_radius_all(8)
	st.set_content_margin_all(8)
	add_theme_stylebox_override("panel", st)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	add_child(vb)
	var hb := HBoxContainer.new()
	var t: Label = m._label("Real size", 14, "heading")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(t)
	_kind = OptionButton.new()
	_kind.name = "opt_realsize_kind"
	_kind.tooltip_text = "what this model is: auto guesses from its name and where it sits on the body"
	_kind.add_item("auto (guess)")
	for k in RealSize.KINDS:
		_kind.add_item(RealSize.RANGES[k]["label"])
	_kind.item_selected.connect(func(i): set_pick("auto" if i == 0 else RealSize.KINDS[i - 1]))
	hb.add_child(_kind)
	vb.add_child(hb)
	_dims = m._label("", 14, "text", true)
	_dims.name = "dims"
	_dims.custom_minimum_size.x = WIDTH
	vb.add_child(_dims)
	_say = m._label("", 13, "text:0.85", true)
	_say.name = "verdict"
	_say.custom_minimum_size.x = WIDTH
	vb.add_child(_say)
	_fix = Button.new()
	_fix.name = "btn_realsize_fix"
	_fix.visible = false
	_fix.pressed.connect(func(): rescale())
	vb.add_child(_fix)
	m.ui_root.add_child(self)


func set_pick(k: String) -> void:
	pick = k
	_kind.selected = 0 if k == "auto" else RealSize.KINDS.find(k) + 1
	recheck(true)


func close() -> void:
	visible = false
	_drop_lines()


func _drop_lines() -> void:
	if _lines != null and is_instance_valid(_lines):
		_lines.queue_free()
	_lines = null


func _mesh_name() -> String:
	var n = ui.get("mesh_name")
	if n is String and n != "":
		return n
	return String(ui.mesh.get_meta("name", "")) if ui.mesh != null else ""


func _signature() -> int:
	var b: Body = m.get("B")
	return hash([ui.mesh.verts, ui.mesh.vert_count(), b.body.hash() if b != null else 0, pick, _mesh_name()])


## check again; say = put the sentence in the status line. -> the sentence
func recheck(say := false) -> String:
	if ui == null or not ui.on or ui.mesh == null:
		return ""
	_sig = _signature()
	result = RealSize.check(ui.mesh, pick, m.get("B"), _mesh_name())
	var s: Array = result["size"]
	var lab: String = RealSize.RANGES[result["kind"]]["label"]
	_dims.text = "%s x %s x %s   %s%s" % [_cm(s[0]), _cm(s[1]), _cm(s[2]), lab, "" if result["picked"] else " (guess: %s)" % result["kind_why"]]
	_say.text = result["text"]
	_say.add_theme_color_override("font_color", Tok.c({"ok": "info", "suspicious": "warn", "wrong": "fail"}[result["verdict"]]))
	var u: Dictionary = result["units"]
	_fix.visible = not u.is_empty()
	if not u.is_empty():
		_fix.text = "Rescale x%s (one undo step)" % RealSize._num(u["factor"])
		_fix.tooltip_text = u["say"]
	_draw_box()
	reset_size()
	place()
	var said := "Model: real size: %s is %s" % [lab, result["text"]]
	if not u.is_empty():
		said += " (button on the readout, or 'Model: real-size rescale')"
	if say:
		m._say(said)
	return said


static func _cm(x: float) -> String:
	return "%.1f cm" % (x * 100.0) if x < 10.0 else "%.2f m" % x


## apply the units fix (one undo step) and check again. -> what was said
func rescale() -> String:
	var u: Dictionary = result.get("units", {})
	if u.is_empty():
		var no := "Model: real size: no units slip to fix (%s)" % String(result.get("text", "nothing checked"))
		m._say(no)
		return no
	var f: float = u["factor"]
	ui.undo.begin(ui.mesh)
	RealSize.rescale(ui.mesh, f, result["box"]["center"])
	ui.undo.commit("Real-size rescale x%s" % RealSize._num(f))
	ui.view.mark_dirty()
	recheck(false)
	var said := "Model: rescaled x%s (one undo step): now %s" % [RealSize._num(f), result["text"]]
	m._say(said)
	return said


func _process(dt: float) -> void:
	if not visible:
		return
	if ui == null or not ui.on or ui.view == null:
		close()
		return
	_t += dt
	if _t >= RECHECK:
		_t = 0.0
		if _signature() != _sig:
			recheck(false)
	if _lines == null or not is_instance_valid(_lines) or _lines.get_parent() != ui.view:
		_draw_box()
	place()


## the model's box on screen: the bounding rect of its 8 projected corners (those in front of the camera)
func model_rect() -> Rect2:
	var cam: Camera3D = m.cam
	var r := Rect2()
	var first := true
	for c in result.get("box", {}).get("corners", PackedVector3Array()):
		var w: Vector3 = ui.view.global_transform * c
		if cam.is_position_behind(w):
			continue
		var p := cam.unproject_position(w)
		r = Rect2(p, Vector2.ZERO) if first else r.expand(p)
		first = false
	return r


## the other panels to keep off: visible Controls straight under ui_root that are not near full-screen
func avoid_rects() -> Array:
	var out := []
	var scr: Vector2 = get_viewport_rect().size
	for c in m.ui_root.get_children():
		if c == self or not (c is Control) or not (c as Control).visible or (c as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE and not (c is PanelContainer):
			continue
		var r := (c as Control).get_global_rect()
		if r.size.x * r.size.y > 0.4 * scr.x * scr.y or r.size.x < 1.0 or r.size.y < 1.0:
			continue
		out.append(r)
	return out


## beside the model: right, left, below, above, the first that is inside the free view and over no other panel; else the
## right one pushed inside
func place() -> void:
	screen_box = model_rect()
	var sz := get_combined_minimum_size()
	size = sz
	var view: Rect2 = m.nav_clear_rect() if m.has_method("nav_clear_rect") else get_viewport_rect()
	var inner := view.grow(-PAD)
	var b := screen_box
	var cy := b.get_center().y - sz.y * 0.5
	var cx := b.get_center().x - sz.x * 0.5
	var cands := [Vector2(b.end.x + GAP, cy), Vector2(b.position.x - GAP - sz.x, cy), Vector2(cx, b.end.y + GAP), Vector2(cx, b.position.y - GAP - sz.y)]
	var avoid := avoid_rects()
	for at in cands:
		var r := Rect2(at, sz)
		if not inner.encloses(r):
			# slide along the side it is on (keep it beside the model, inside the view)
			r.position = r.position.clamp(inner.position, (inner.end - sz).max(inner.position))
			if r.intersects(b):
				continue
		var hit := false
		for a in avoid:
			if r.intersects((a as Rect2).grow(PAD * 0.5)):
				hit = true
				break
		if not hit:
			position = r.position
			return
	position = (cands[0] as Vector2).clamp(inner.position, (inner.end - sz).max(inner.position))


func _draw_box() -> void:
	_drop_lines()
	var cs: PackedVector3Array = result.get("box", {}).get("corners", PackedVector3Array())
	if cs.size() != 8 or ui.view == null:
		return
	var seg := PackedVector3Array()
	for i in 8:
		for bit in [1, 2, 4]:
			if i & bit == 0:
				seg.append(cs[i])
				seg.append(cs[i | bit])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = seg
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	var mt := StandardMaterial3D.new()
	mt.albedo_color = Tok.c({"ok": "info", "suspicious": "warn", "wrong": "fail"}[result.get("verdict", "ok")])
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.no_depth_test = true
	mt.render_priority = 10
	_lines = MeshInstance3D.new()
	_lines.name = "real_size_box"
	_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lines.mesh = am
	_lines.material_override = mt
	ui.view.add_child(_lines)
