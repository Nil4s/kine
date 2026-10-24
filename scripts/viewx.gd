## VIEWPORT PARITY (ROADMAP_400 K13-K16): what Blender and Maya give the artist to look at the body from every side.
## All of these are VIEW settings: never saved in a scene, never an undo step (like scripts/shading.gd).
##   K14 QUAD VIEW   the free view is cut into four panes: TOP, PERSPECTIVE, FRONT, SIDE. The three orthographic panes are
##        SubViewports that share the main World3D (the same body, props, lights), each with its own Camera3D (ortho). The
##        PERSPECTIVE pane is the main view itself, left uncovered and shrunk into its quarter (main._cam asks cam_quad()), so
##        picking, dragging, keys and every tool keep working on it exactly as before. Clicking a pane makes it the active one;
##        a right drag turns the active ORTHO pane (it leaves its axis, as Blender's does), the wheel zooms it.
##        Kine's directions: the body faces +Z and his left is +X. FRONT looks down -Z (camera at +Z), SIDE is "his right"
##        (camera at -X, looking +X), TOP looks down -Y with the body's front at the bottom of the pane.
##   K15 LOCAL VIEW  isolate(): every body part and prop except the picked ones is hidden (the browser's hidden_parts and the
##        nodes' own visible flags, saved first); again, and the saved set is put back exactly. frame(): the camera target and
##        distance fit the part's posed AABB (the skinned vertices, SkinPick) to FRAME_FILL of the free view.
##   K16 SECTION     a plane (axis X/Y/Z, offset, which side stays) clips the body and the props with a shader: the surfaces on
##        the far side of the plane are discarded, so the inside of the pose shows (the back faces are drawn in the accent
##        colour as the cut's inside). The plane is ONE global shader uniform (kine_section: xyz normal, w offset), so every
##        material that includes the clip follows the slider; SkinPick's highlight pass includes it too.
##   K13 OVERLAYS    show_normals: short lines along the posed vertex normals (every NORMAL_STEP-th vertex of the skinned body);
##        stats: triangles and vertices of the scene's visible meshes, in a label at the end of the status line.
class_name ViewX
extends RefCounted

const GLOBAL := "kine_section"
const FRAME_FILL := 0.6        # frame(): the part's projected box fills this share of the free view's limiting side
const NORMAL_STEP := 12        # a normal line on every 12th vertex
const NORMAL_LEN := 0.03       # m
const PANES := ["top", "persp", "front", "side"]
const ORTHO := {"top": [0.0, -90.0], "front": [0.0, 0.0], "side": [-90.0, 0.0]}   # yaw, pitch (the camera sits at target + basis * (0,0,d))
const PANE_TEXT := {"top": "TOP", "persp": "PERSPECTIVE", "front": "FRONT", "side": "SIDE (his right)"}
const ORTHO_SIZE := 2.3        # m of world seen top to bottom in an ortho pane at the start

const CLIP_OPAQUE := """shader_type spatial;
render_mode cull_disabled;
global uniform vec4 kine_section;
uniform vec4 albedo : source_color = vec4(0.78, 0.72, 0.64, 1.0);
uniform vec4 cut_col : source_color = vec4(0.2, 0.42, 0.75, 1.0);
uniform float rough = 0.55;
uniform float metal = 0.0;
uniform bool has_tex = false;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
varying vec3 kw;
void vertex() { kw = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	if (dot(kw, kine_section.xyz) > kine_section.w) { discard; }
	if (FRONT_FACING) {
		vec3 c = albedo.rgb;
		if (has_tex) { c *= texture(tex, UV).rgb; }
		ALBEDO = c;
		ROUGHNESS = rough;
		METALLIC = metal;
	} else {
		ALBEDO = cut_col.rgb;
		EMISSION = cut_col.rgb * 0.5;
		ROUGHNESS = 1.0;
	}
}
"""
const CLIP_ALPHA := """shader_type spatial;
render_mode cull_disabled, depth_draw_never;
global uniform vec4 kine_section;
uniform vec4 albedo : source_color = vec4(0.78, 0.72, 0.64, 0.3);
uniform vec4 cut_col : source_color = vec4(0.2, 0.42, 0.75, 1.0);
varying vec3 kw;
void vertex() { kw = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	if (dot(kw, kine_section.xyz) > kine_section.w) { discard; }
	ALBEDO = FRONT_FACING ? albedo.rgb : cut_col.rgb;
	ALPHA = albedo.a;
}
"""

var m                           # the poser (main.gd, untyped: its helpers are main's own)

# ---- K14 quad view
var quad_on := false
var active := "persp"
var panes := {}                 # "top"/"front"/"side" -> {"svc", "vp", "cam", "yaw", "pitch", "size"}
var quad_root: Control          # the frame, the names and the active border (mouse-transparent)
var _fov0 := 40.0
var _drag := ""                 # the ortho pane being turned by a right drag

# ---- K15 local view
var iso_on := false
var _iso_hidden := {}           # hidden_parts before the isolation
var _iso_vis := {}              # node -> its visible flag before (the props, the weapon pieces)

# ---- K16 section
var sec_on := false
var sec_axis := 1               # 0 X, 1 Y, 2 Z
var sec_off := 0.95             # m along the axis
var sec_flip := false           # false: keep the side below the plane (the far side of the normal is cut)
var sec_ui: PanelContainer
var _sec_slider: HSlider
var _sec_val: Label
var _sec_wrap := {}             # MeshInstance3D -> {"src": Material, "mat": ShaderMaterial}

# ---- K13 overlays
var normals_on := false
var normals_node: MeshInstance3D
var normal_lines := 0           # how many lines are drawn now
var _nsig := ""
var _tri_cache := {}            # mesh id + surface -> PackedInt32Array indices
var stats_on := false
var stats_lbl: Label
var _stats_t := 0.0


func _init(main) -> void:
	m = main
	ensure_global()


## the global uniform exists (disabled: offset 1e9 cuts nothing) before any shader that names it is compiled
static var _added := false


static func ensure_global() -> void:
	if not _added:
		_added = true
		RenderingServer.global_shader_parameter_add(GLOBAL, RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4(0, 0, 0, 1.0e9))


# ================================================================================ K14 QUAD VIEW

## the four panes' rectangles in window coordinates: the free view cut in two by two
func quad_rects() -> Dictionary:
	var cl: Rect2 = m.nav_clear_rect()
	var w := cl.size.x * 0.5
	var h := cl.size.y * 0.5
	return {"top": Rect2(cl.position, Vector2(w, h)), "persp": Rect2(cl.position + Vector2(w, 0), Vector2(w, h)),
		"front": Rect2(cl.position + Vector2(0, h), Vector2(w, h)), "side": Rect2(cl.position + Vector2(w, h), Vector2(w, h))}


## the rectangle the perspective view fills now (the whole free view, or its quarter)
func view_rect() -> Rect2:
	return quad_rects()["persp"] if quad_on else m.nav_clear_rect()


func quad_toggle() -> void:
	quad_set(not quad_on)


func quad_set(on: bool) -> void:
	if on == quad_on:
		return
	if on and m.shot_through:
		m._say("the shot camera's view is on: leave it first ('Camera: look through' again), then turn the quad view on")
		return
	quad_on = on
	if on:
		_fov0 = m.cam.fov
		_quad_build()
		active = "persp"
		m._cam()
		m._say("quad view on: top, perspective, front, side. Click a pane to make it the active one; right-drag turns it, the wheel zooms it. The perspective pane keeps every tool. Ctrl+Alt+Q turns it off")
	else:
		if quad_root != null:
			quad_root.queue_free()
		quad_root = null
		panes = {}
		_drag = ""
		m.cam.fov = _fov0
		m.cam.h_offset = 0.0
		m.cam.v_offset = 0.0
		m._cam()
		m._say("quad view off: the single perspective view is back (Ctrl+Alt+Q turns the quad view on again)")


func _quad_build() -> void:
	quad_root = Control.new()
	quad_root.name = "quad_view"
	quad_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	quad_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.ui_root.add_child(quad_root)
	m.ui_root.move_child(quad_root, 0)   # under every panel
	var rects := quad_rects()
	for k in ORTHO:
		var svc := SubViewportContainer.new()
		svc.name = "pane_" + k
		svc.stretch = true
		svc.mouse_filter = Control.MOUSE_FILTER_STOP
		var vp := SubViewport.new()
		vp.world_3d = m.get_viewport().world_3d   # the same world: the same body, props and lights
		vp.handle_input_locally = false
		vp.size = Vector2i(rects[k].size)
		var c := Camera3D.new()
		c.projection = Camera3D.PROJECTION_ORTHOGONAL
		c.size = ORTHO_SIZE
		c.near = 0.05
		c.far = 60.0
		vp.add_child(c)
		svc.add_child(vp)
		quad_root.add_child(svc)
		svc.gui_input.connect(_pane_input.bind(k))
		panes[k] = {"svc": svc, "vp": vp, "cam": c, "yaw": ORTHO[k][0], "pitch": ORTHO[k][1], "size": ORTHO_SIZE}
	var fr := Control.new()
	fr.name = "frames"
	fr.set_anchors_preset(Control.PRESET_FULL_RECT)
	fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fr.draw.connect(_paint_frames.bind(fr))
	quad_root.add_child(fr)
	_quad_layout()
	_quad_cams()


func _quad_layout() -> void:
	var rects := quad_rects()
	for k in panes:
		var svc: SubViewportContainer = panes[k]["svc"]
		svc.position = rects[k].position
		svc.size = rects[k].size


func _quad_cams() -> void:
	for k in panes:
		var p: Dictionary = panes[k]
		var b := Basis.from_euler(Vector3(deg_to_rad(p["pitch"]), deg_to_rad(p["yaw"]), 0))
		var c: Camera3D = p["cam"]
		c.transform = Transform3D(b, m.target + b * Vector3(0, 0, 10.0))
		c.size = p["size"]
		c.cull_mask = m.cam.cull_mask


## main._cam() calls this last while the quad view is on: the main perspective camera is put in its quarter, at half the scale
func cam_quad() -> void:
	var r := view_rect()
	var vs: Vector2 = m.get_viewport().get_visible_rect().size if m.is_inside_tree() else Vector2(1600, 900)
	var cl: Rect2 = m.nav_clear_rect()
	var ratio := r.size.y / maxf(cl.size.y, 1.0)   # the quarter is this share of the free view's height
	m.cam.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(_fov0 * 0.5)) / ratio))
	var mpp: float = 2.0 * m.dist * tan(deg_to_rad(m.cam.fov * 0.5)) / vs.y
	m.cam.h_offset = (vs.x * 0.5 - r.get_center().x) * mpp
	m.cam.v_offset = (r.get_center().y - vs.y * 0.5) * mpp


func _pane_at(p: Vector2) -> String:
	if not quad_on:
		return ""
	var rects := quad_rects()
	for k in PANES:
		if (rects[k] as Rect2).has_point(p):
			return k
	return ""


## main's mouse press: a press on the perspective quarter makes it the active pane (the press itself goes on as before)
func press(p: Vector2) -> void:
	if quad_on and _pane_at(p) == "persp" and active != "persp":
		active = "persp"
		_paint()


func _pane_input(ev: InputEvent, k: String) -> void:
	if not panes.has(k):
		return
	var pn: Dictionary = panes[k]
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.pressed:
			active = k
			_paint()
			if mb.button_index == MOUSE_BUTTON_RIGHT:
				_drag = k
			elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				pn["size"] = clampf(float(pn["size"]) * 0.9, 0.2, 12.0)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				pn["size"] = clampf(float(pn["size"]) / 0.9, 0.2, 12.0)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_drag = ""
		_quad_cams()
	elif ev is InputEventMouseMotion and _drag == k and active == k:
		orbit_pane(k, (ev as InputEventMouseMotion).relative)


## turn the ortho pane by a mouse movement (pixels): the same 0.4 degrees a pixel as the main view
func orbit_pane(k: String, rel: Vector2) -> void:
	if not panes.has(k):
		return
	panes[k]["yaw"] = float(panes[k]["yaw"]) - rel.x * 0.4
	panes[k]["pitch"] = clampf(float(panes[k]["pitch"]) - rel.y * 0.4, -90.0, 90.0)
	_quad_cams()
	_paint()


func pane_dir(k: String) -> Vector3:
	## the direction pane k looks along (world)
	return -(panes[k]["cam"] as Camera3D).global_transform.basis.z if panes.has(k) and (panes[k]["cam"] as Camera3D).is_inside_tree() else (-(Basis.from_euler(Vector3(deg_to_rad(panes[k]["pitch"]), deg_to_rad(panes[k]["yaw"]), 0)).z) if panes.has(k) else Vector3.ZERO)


func _paint() -> void:
	if quad_root != null and quad_root.has_node("frames"):
		quad_root.get_node("frames").queue_redraw()


func _paint_frames(fr: Control) -> void:
	var rects := quad_rects()
	var font := ThemeDB.fallback_font
	for k in PANES:
		var r: Rect2 = rects[k]
		var on: bool = k == active
		fr.draw_rect(r, Tok.c("focus") if on else Tok.c("grid_major"), false, 3.0 if on else 1.0)
		var t: String = PANE_TEXT[k]
		if k != "persp" and panes.has(k) and (absf(float(panes[k]["yaw"]) - ORTHO[k][0]) > 0.5 or absf(float(panes[k]["pitch"]) - ORTHO[k][1]) > 0.5):
			t = "USER (ortho)"
		fr.draw_string(font, r.position + Vector2(8, 18), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Tok.c("heading"))


# ================================================================================ K15 LOCAL VIEW, FRAME

## the parts the isolation keeps: the picked part and the group it is in
func keep_parts() -> Array:
	var out := [m.sel]
	for j in m.sel_more:
		if not j in out:
			out.append(j)
	return out


func isolate_toggle() -> void:
	if iso_on:
		_iso_restore()
		m._say("local view off: everything is back as it was (hidden parts stay hidden)")
		return
	if m.sel_prop < 0 and not m.pieces.has(m.sel):
		m._say("nothing to isolate: pick a body part (click it) or a prop first")
		return
	iso_on = true
	_iso_hidden = m.hidden_parts.duplicate()
	_iso_vis = {}
	for n in _iso_nodes():
		_iso_vis[n] = n.visible
	_iso_apply()
	frame()
	m._say("local view: only %s is shown. Run 'View: isolate the selected part' again to bring everything back" % (m._prop_name(m.sel_prop) if m.sel_prop >= 0 else m.nice(m.sel)))


## every node the isolation may switch: the prop roots, the weapon pieces
func _iso_nodes() -> Array:
	var out := []
	if m.ui_props_root != null:
		for c in m.ui_props_root.get_children():
			if c is Node3D:
				out.append(c)
	for n in [m.bat_handle, m.bat_barrel, m.bat_knob, m.d2_handle, m.d2_blade] + m.weapon_pieces():
		if n != null:
			out.append(n)
	return out


func _iso_apply() -> void:
	var keep: Array = [] if m.sel_prop >= 0 else keep_parts()
	var changed := false
	for j in Body.ORDER + Body.WEAPON + Body.WEAPON2:
		var want: bool = not j in keep
		if want != m.hidden_parts.has(j):
			changed = true
			if want:
				m.hidden_parts[j] = true
			else:
				m.hidden_parts.erase(j)
	if changed:
		m._refresh()
	var props: Array = m.ui_props_root.get_children() if m.ui_props_root != null else []
	for n in _iso_nodes():
		var is_prop: bool = n in props
		var show: bool = is_prop and m.sel_prop >= 0 and String(n.name) == "prop_%d" % m.sel_prop
		if n.visible != show:
			n.visible = show


func _iso_restore() -> void:
	iso_on = false
	m.hidden_parts = _iso_hidden.duplicate()
	m._refresh()
	for n in _iso_vis:
		if is_instance_valid(n):
			n.visible = _iso_vis[n]
	_iso_vis = {}
	_iso_hidden = {}


## the posed box of part j (world): the skinned vertices the part owns; a part with no skin: its capsule
func part_aabb(j: String) -> AABB:
	m.skp.refresh()
	var bb := AABB()
	var first := true
	for gr in m.skp.groups:
		if String(gr["part"]) == j:
			bb = gr["box"] if first else bb.merge(gr["box"])
			first = false
	if first:
		var c: Array = m.B.cap(j)
		bb = AABB(c[0], Vector3.ZERO).expand(c[1]).grow(0.04)
	return bb


## the box of the picked prop (world)
func prop_aabb(i: int) -> AABB:
	var node: Node = m.ui_props_root.get_node_or_null("prop_%d" % i)
	var bb := AABB()
	var first := true
	if node != null:
		for mi in node.find_children("*", "MeshInstance3D", true, false):
			var b := (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
			bb = b if first else bb.merge(b)
			first = false
	return bb


func sel_aabb() -> AABB:
	if m.sel_prop >= 0:
		return prop_aabb(m.sel_prop)
	var bb := AABB()
	var first := true
	for j in keep_parts():
		var b := part_aabb(j)
		bb = b if first else bb.merge(b)
		first = false
	return bb


## the camera target and distance that fit the picked part's box (with margin) to FRAME_FILL of the free view
func frame(bb := AABB()) -> void:
	if bb.size == Vector3.ZERO:
		bb = sel_aabb()
	m.target = bb.get_center()
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	for it in 6:
		m._cam()
		var clear := view_rect()
		var r := Rect2(m.cam.unproject_position(bb.position), Vector2.ZERO)
		for i in 8:
			r = r.expand(m.cam.unproject_position(bb.get_endpoint(i)))
		var need := maxf(r.size.x / clear.size.x, r.size.y / clear.size.y) / FRAME_FILL
		var mpp: float = 2.0 * m.dist * tan(deg_to_rad(m.cam.fov * 0.5)) / vs.y
		var d := clear.get_center() - r.get_center()
		m.target -= m.cam.global_basis.x * d.x * mpp - m.cam.global_basis.y * d.y * mpp
		m.dist = clampf(m.dist * need, 0.15, 12.0)
	m._cam()


## the projected box of bb as a fraction of the free view: [width share, height share]
func projected_share(bb: AABB) -> Vector2:
	var clear := view_rect()
	var r := Rect2(m.cam.unproject_position(bb.position), Vector2.ZERO)
	for i in 8:
		r = r.expand(m.cam.unproject_position(bb.get_endpoint(i)))
	return Vector2(r.size.x / clear.size.x, r.size.y / clear.size.y)


# ================================================================================ K16 SECTION

func section_vec() -> Vector4:
	var n := Vector3.ZERO
	n[sec_axis] = -1.0 if sec_flip else 1.0
	return Vector4(n.x, n.y, n.z, -sec_off if sec_flip else sec_off)


func section_toggle() -> void:
	section_set(not sec_on)


func section_set(on: bool) -> void:
	sec_on = on
	if on:
		_sec_ui_build()
		sec_ui.visible = true
		_sec_axis_sync()
		section_update()
		m._say("section plane on (%s = %.2f m): the body above it is cut away, so you see inside the pose. The panel top left moves it; run 'View: section plane' again to turn it off" % ["XYZ"[sec_axis], sec_off])
	else:
		RenderingServer.global_shader_parameter_set(GLOBAL, Vector4(0, 0, 0, 1.0e9))
		_sec_unwrap()
		if sec_ui != null:
			sec_ui.visible = false
		m._say("section plane off: the whole body is drawn again")


func section_axis(a: int) -> void:
	sec_axis = a
	sec_off = m.target[a] if a == 1 else 0.0
	if not sec_on:
		section_set(true)
		return
	_sec_axis_sync()
	section_update()


func section_flip() -> void:
	sec_flip = not sec_flip
	if not sec_on:
		section_set(true)
		return
	section_update()


func section_offset(v: float) -> void:
	sec_off = v
	section_update()


func section_update() -> void:
	if not sec_on:
		return
	RenderingServer.global_shader_parameter_set(GLOBAL, section_vec())
	_sec_wrap_all()
	if _sec_val != null:
		_sec_val.text = "%s = %.2f m" % ["XYZ"[sec_axis], sec_off]
	if _sec_slider != null and absf(_sec_slider.value - sec_off) > 1e-4:
		_sec_slider.set_value_no_signal(sec_off)


func _sec_axis_sync() -> void:
	if _sec_slider == null:
		return
	_sec_slider.min_value = -1.0 if sec_axis != 1 else -0.2
	_sec_slider.max_value = 1.0 if sec_axis != 1 else 2.2
	_sec_slider.set_value_no_signal(sec_off)
	var ob: OptionButton = sec_ui.find_child("sec_axis", true, false)
	if ob != null:
		ob.select(sec_axis)


func _sec_ui_build() -> void:
	if sec_ui != null:
		return
	sec_ui = PanelContainer.new()
	sec_ui.name = "section_panel"
	var hb := HBoxContainer.new()
	sec_ui.add_child(hb)
	var l := Label.new()
	l.text = "Section"
	hb.add_child(l)
	var ob := OptionButton.new()
	ob.name = "sec_axis"
	for a in ["X", "Y", "Z"]:
		ob.add_item(a)
	ob.select(sec_axis)
	ob.tooltip_text = "the axis the section plane is square to (Y: a horizontal cut)"
	ob.item_selected.connect(func(i): section_axis(i))
	hb.add_child(ob)
	_sec_slider = HSlider.new()
	_sec_slider.custom_minimum_size = Vector2(180, 24)
	_sec_slider.step = 0.01
	_sec_slider.min_value = -0.2
	_sec_slider.max_value = 2.2
	_sec_slider.value = sec_off
	_sec_slider.tooltip_text = "slide the cut along its axis (metres from the floor for Y)"
	_sec_slider.value_changed.connect(func(v): section_offset(v))
	hb.add_child(_sec_slider)
	_sec_val = Label.new()
	hb.add_child(_sec_val)
	var cb := CheckBox.new()
	cb.text = "flip"
	cb.tooltip_text = "keep the other side of the plane"
	cb.toggled.connect(func(_on): section_flip())
	hb.add_child(cb)
	m.ui_root.add_child(sec_ui)
	sec_ui.position = Vector2(m.lw() + 12, m.TOP_H + 8)


func _sec_wrap_all() -> void:
	var shading = m.shading
	for mi in Shading.bodies(m):
		var w: Dictionary = _sec_wrap.get(mi, {})
		var cur: Material = mi.material_override
		if not w.is_empty() and cur == w["mat"]:
			continue
		if not w.is_empty() and shading._orig.get(mi) == w["mat"]:
			shading._orig[mi] = w["src"]   # shading remembered our clip as the body's own look: give it the real one back
		var mat := _clip_of(cur, mi)
		if mat == null:
			continue
		_sec_wrap[mi] = {"src": cur, "mat": mat}
		mi.material_override = mat
	for mi in _sec_wrap.keys():
		if not is_instance_valid(mi):
			_sec_wrap.erase(mi)


func _sec_unwrap() -> void:
	var shading = m.shading
	for mi in _sec_wrap:
		if not is_instance_valid(mi):
			continue
		var w: Dictionary = _sec_wrap[mi]
		if mi.material_override == w["mat"]:
			mi.material_override = w["src"]
		if shading._orig.get(mi) == w["mat"]:
			shading._orig[mi] = w["src"]
	_sec_wrap = {}


## the clipping twin of a material: the same colour, roughness and texture, plus the discard and the cut's inside colour
func _clip_of(src: Material, mi: MeshInstance3D) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	if src is ShaderMaterial:   # a matcap: the same shader with the clip put in (one without its own vertex() only)
		var old: Shader = (src as ShaderMaterial).shader
		if old == null or old.code.contains("void vertex") or not old.code.contains("void fragment() {"):
			return null
		var code := _splice(old.code, "shader_type spatial;", "shader_type spatial;\nglobal uniform vec4 kine_section;\nvarying vec3 kw;\nvoid vertex() { kw = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }")
		code = _splice(code, "void fragment() {", "void fragment() {\n\tif (dot(kw, kine_section.xyz) > kine_section.w) { discard; }")
		sh.code = code
		sm.shader = sh
		for u in old.get_shader_uniform_list():
			sm.set_shader_parameter(u["name"], (src as ShaderMaterial).get_shader_parameter(u["name"]))
		return sm
	var st: StandardMaterial3D = src as StandardMaterial3D
	if st == null:
		st = mi.get_active_material(0) as StandardMaterial3D
	var alb := Color(0.7, 0.7, 0.72, 1.0)
	var rough := 0.6
	var metal := 0.0
	var tex: Texture2D = null
	if st != null:
		alb = st.albedo_color
		rough = st.roughness
		metal = st.metallic
		tex = st.albedo_texture
	if alb.a < 0.99:
		sh.code = CLIP_ALPHA
	else:
		sh.code = CLIP_OPAQUE
	sm.shader = sh
	sm.set_shader_parameter("albedo", alb)
	sm.set_shader_parameter("cut_col", Tok.c("accent"))
	if alb.a >= 0.99:
		sm.set_shader_parameter("rough", rough)
		sm.set_shader_parameter("metal", metal)
		sm.set_shader_parameter("has_tex", tex != null)
		if tex != null:
			sm.set_shader_parameter("tex", tex)
	return sm


# ================================================================================ K13 OVERLAYS

func normals_toggle() -> void:
	normals_on = not normals_on
	if normals_on:
		_nsig = ""
		_normals_build()
		m._say("normals shown: a short line on every %dth vertex of the body, along the way the skin faces (%d lines). Run 'View: show normals' again to hide them" % [NORMAL_STEP, normal_lines])
	else:
		if normals_node != null:
			normals_node.queue_free()
			normals_node = null
		normal_lines = 0
		m._say("normals hidden")


func _pose_sig() -> String:
	var s := ""
	for sf in m.skp.surfs:
		var p: PackedVector3Array = sf["pos"]
		if p.size() > 0:
			s += "%s%s%s" % [p[0], p[p.size() / 2], p[p.size() - 1]]
	return s


func _normals_build() -> void:
	m.skp.refresh()
	var sig := _pose_sig()
	if sig == _nsig and normals_node != null:
		return
	_nsig = sig
	if normals_node == null:
		normals_node = MeshInstance3D.new()
		normals_node.name = "viewx_normals"
		var mt := StandardMaterial3D.new()
		mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mt.albedo_color = Tok.c("heading")
		mt.no_depth_test = true
		normals_node.material_override = mt
		normals_node.mesh = ImmediateMesh.new()
		m.add_child(normals_node)
	var im := normals_node.mesh as ImmediateMesh
	im.clear_surfaces()
	var n := 0
	var vs := PackedVector3Array()
	for k in m.skp.surfs.size():
		var sf: Dictionary = m.skp.surfs[k]
		var pos: PackedVector3Array = sf["pos"]
		if pos.is_empty():
			continue
		var nrm := PackedVector3Array()
		nrm.resize(pos.size())
		for gr in m.skp.groups:   # the pieces share one vertex set: each piece holds its own triangles of it
			if int(gr["k"]) != k:
				continue
			var mi: MeshInstance3D = gr["mi"]
			for si in mi.mesh.get_surface_count():
				var key := "%d_%d" % [mi.mesh.get_instance_id(), si]
				if not _tri_cache.has(key):
					var arr := mi.mesh.surface_get_arrays(si)
					var ixa = arr[Mesh.ARRAY_INDEX]
					_tri_cache[key] = [(arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), ixa if ixa != null else PackedInt32Array()]
				var ce: Array = _tri_cache[key]
				if int(ce[0]) != pos.size():
					continue
				var ix: PackedInt32Array = ce[1]
				for t in range(0, ix.size(), 3):
					var a := ix[t]
					var b := ix[t + 1]
					var c := ix[t + 2]
					var fn := (pos[b] - pos[a]).cross(pos[c] - pos[a])   # area-weighted
					nrm[a] += fn
					nrm[b] += fn
					nrm[c] += fn
		for i in range(0, pos.size(), NORMAL_STEP):
			if nrm[i].length_squared() < 1e-24:
				continue
			vs.append(pos[i])
			vs.append(pos[i] + nrm[i].normalized() * NORMAL_LEN)
			n += 1
	if vs.size() > 0:
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		for v in vs:
			im.surface_add_vertex(v)
		im.surface_end()
	normal_lines = n


func stats_toggle() -> void:
	stats_on = not stats_on
	if stats_on:
		if stats_lbl == null:
			stats_lbl = m._label("", 15, "info")
			stats_lbl.name = "stats_label"
			stats_lbl.anchor_left = 1.0
			stats_lbl.anchor_right = 1.0
			stats_lbl.anchor_top = 1.0
			stats_lbl.anchor_bottom = 1.0
			stats_lbl.offset_left = -m.RIGHT_W - 12 - 360
			stats_lbl.offset_right = -m.RIGHT_W - 12
			stats_lbl.offset_top = -m.BOTTOM_H - 82
			stats_lbl.offset_bottom = -m.BOTTOM_H - 40
			stats_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			stats_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			stats_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			m.ui_root.add_child(stats_lbl)
		stats_lbl.visible = true
		_stats_text()
		m._say("stats on: %s (at the end of the status line; 'View: stats' again hides it)" % stats_lbl.text)
	else:
		if stats_lbl != null:
			stats_lbl.visible = false
		m._say("stats hidden")


## triangles and vertices of every mesh drawn now. The body's pieces each hold their own triangles of ONE shared vertex
## set (SkinPick.surfs): its vertices count once per set, its triangles per visible piece.
func scene_stats() -> Dictionary:
	var tris := 0
	var verts := 0
	var meshes := 0
	var piece_of := {}
	for j in m.pieces:
		piece_of[m.pieces[j]] = true
	var any_piece := false
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var n := mi as MeshInstance3D
		if n == normals_node or n.mesh == null or not n.is_visible_in_tree():
			continue
		if not (n.mesh is ArrayMesh or n.mesh is PrimitiveMesh):
			continue
		meshes += 1
		var is_piece: bool = piece_of.has(n)
		any_piece = any_piece or is_piece
		for si in n.mesh.get_surface_count():
			var nv := 0
			var ni := 0
			if n.mesh is ArrayMesh:
				nv = (n.mesh as ArrayMesh).surface_get_array_len(si)
				ni = (n.mesh as ArrayMesh).surface_get_array_index_len(si)
			else:
				var ar := n.mesh.surface_get_arrays(si)
				nv = (ar[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
				ni = (ar[Mesh.ARRAY_INDEX] as PackedInt32Array).size() if ar[Mesh.ARRAY_INDEX] != null else 0
			if not is_piece:
				verts += nv
			tris += (ni if ni > 0 else nv) / 3
	if any_piece:
		for sf in m.skp.surfs:
			verts += (sf["rest"] as PackedVector3Array).size()
	return {"tris": tris, "verts": verts, "meshes": meshes}


func _stats_text() -> void:
	var s := scene_stats()
	stats_lbl.text = "%s tris  %s verts  %d meshes" % [_thousands(int(s["tris"])), _thousands(int(s["verts"])), int(s["meshes"])]


## the first occurrence of a replaced by b
static func _splice(src: String, a: String, b: String) -> String:
	var i := src.find(a)
	return src if i < 0 else src.substr(0, i) + b + src.substr(i + a.length())


static func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return out


# ================================================================================ per frame

func tick(dt: float) -> void:
	if quad_on and quad_root != null:
		_quad_layout()
		_quad_cams()
		if m.shot_through:
			quad_set(false)
	if iso_on:
		_iso_apply()
	if sec_on:
		_sec_wrap_all()
	if normals_on:
		_normals_build()
	if stats_on and stats_lbl != null:
		_stats_t += dt
		if _stats_t > 0.5:
			_stats_t = 0.0
			_stats_text()
