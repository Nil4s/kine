class_name SectionLook
extends RefCounted
## S218 SECTION COLOUR (Friday plan 218): the cut faces get a section look, as in a CAD section view. Every body keeps its own colour on its
## sides (its look); its CUT face, the cap, gets a colour of its own from CAPS, chosen so that it differs from the body's own side colour and
## from the caps of the bodies before it. A piston, a bore and a rod cut in half therefore read as three bodies.
## Two kinds of cut face: (1) the Section view / Cut view cut (the inside seen through the cut: the back faces); (2) the faces a Split left
## on the split plane (planar faces lying on the plane, facing along it), drawn the same way with no section on.
## View only: surface materials, never the record. Section off / no split: PartUI._look_surfaces puts every body's own look back.
## Used by PartUI (screen: Section tool, Easy Cut view, split results) and NiceRender (the picture).

## cap colours: orange first (the original single cap colour), then colours far from the grey / red / blue / yellow / green body chips
const CAPS := [Color("#e8833a"), Color("#7b3fe4"), Color("#12a8a0"), Color("#e83a9a"), Color("#1f3fbf"), Color("#8bc34a"), Color("#6d4c41"), Color("#00bcd4")]
const MIN_DIST := 0.30   # the least RGB distance a cap keeps from its body's side colour
const PLANE_TOL := 0.0003   # m: a face this close to a split plane is the cut face
const MAX_PLANES := 4

const CODE := """shader_type spatial;
render_mode cull_disabled, unshaded;
uniform vec4 cut = vec4(0.0, 0.0, 1.0, 0.0);
uniform float on = 0.0;
uniform vec4 cap : source_color = vec4(0.91, 0.51, 0.23, 1.0);
uniform vec4 solid : source_color = vec4(0.74, 0.77, 0.82, 1.0);
uniform vec4 planes[4];
uniform int plane_n = 0;
uniform float rough = 0.5;
uniform float metal = 0.1;
varying vec3 wp;
varying vec3 wn;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	if (on > 0.5 && dot(cut.xyz, wp) > cut.w) {
		discard;
	}
	bool on_cut = on > 0.5 && !FRONT_FACING;
	for (int i = 0; i < 4; i++) {
		if (i < plane_n && abs(dot(planes[i].xyz, wp) - planes[i].w) < 0.0003 && abs(dot(planes[i].xyz, wn)) > 0.98) {
			on_cut = true;
		}
	}
	if (on_cut) {
		ALBEDO = cap.rgb;
	} else {
		ALBEDO = solid.rgb * (0.7 + 0.3 * abs(NORMAL.z));
	}
}
"""

static var _sh_flat: Shader
static var _sh_lit: Shader


## the section shader: flat (unshaded, the screen) or lit (the Nice picture and split results, which keep the body's roughness / metal)
static func shader(lit: bool) -> Shader:
	if lit:
		if _sh_lit == null:
			_sh_lit = Shader.new()
			_sh_lit.code = CODE.replace("render_mode cull_disabled, unshaded;", "render_mode cull_disabled;").replace(
				"		ALBEDO = cap.rgb;\n", "		ALBEDO = cap.rgb;\n		ROUGHNESS = 0.7;\n		METALLIC = 0.0;\n").replace(
				"		ALBEDO = solid.rgb * (0.7 + 0.3 * abs(NORMAL.z));\n", "		ALBEDO = solid.rgb;\n		ROUGHNESS = rough;\n		METALLIC = metal;\n")
		return _sh_lit
	if _sh_flat == null:
		_sh_flat = Shader.new()
		_sh_flat.code = CODE
	return _sh_flat


static func _dist(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


## the cap colour of each of n bodies: palette order from the body's index; skips a colour too near the body's own side colour, and one a
## body before it already has (while the palette has others). looks: the replay's looks (null entries = the default chip by index)
static func cap_colors(looks: Array, n: int) -> Array:
	var out := []
	for i in n:
		var side: Color = Part.look_at(looks, i)["c"]
		var pick := -1
		for pass_no in 2:   # pass 0: far from its side colour and unused; pass 1: far from its side colour only
			for k in CAPS.size():
				var j := (i + k) % CAPS.size()
				if _dist(CAPS[j], side) < MIN_DIST:
					continue
				if pass_no == 0 and out.has(CAPS[j]):
					continue
				pick = j
				break
			if pick >= 0:
				break
		out.append(CAPS[pick] if pick >= 0 else CAPS[i % CAPS.size()])
	return out


## the planes the record's split steps cut along, as world planes (xyz = normal, w = n . point), at most MAX_PLANES, newest last
static func split_planes(rec: Dictionary) -> Array:
	var out := []
	for f in rec.get("features", []):
		if String((f as Dictionary).get("t", "")) != "split" or bool((f as Dictionary).get("off", false)):
			continue
		var nm := String(f.get("plane", "right"))
		if not Part.PLANES.has(nm):
			continue
		var pl: Dictionary = Part.plane(nm)
		var n: Vector3 = pl["n"]
		var o: Vector3 = (pl["o"] as Vector3) + n * float(f.get("at", 0.0)) * Part.MM
		out.append(Vector4(n.x, n.y, n.z, n.dot(o)))
	while out.size() > MAX_PLANES:
		out.pop_front()
	return out


## one material per body surface. cut: {} (no cut) or {"n": Vector3, "w": float}; planes: split_planes(rec)
static func materials(looks: Array, n: int, cut: Dictionary, planes: Array, lit: bool) -> Array:
	var caps := cap_colors(looks, n)
	var mats := []
	for i in n:
		var l: Dictionary = Part.look_at(looks, i)
		var mt := ShaderMaterial.new()
		mt.shader = shader(lit)
		mt.set_shader_parameter("cap", caps[i])
		mt.set_shader_parameter("solid", l["c"])
		mt.set_shader_parameter("rough", float(l["rough"]))
		mt.set_shader_parameter("metal", float(l["metal"]))
		if not cut.is_empty():
			var cn: Vector3 = cut["n"]
			mt.set_shader_parameter("cut", Vector4(cn.x, cn.y, cn.z, float(cut["w"])))
			mt.set_shader_parameter("on", 1.0)
		var arr := []
		for p in planes:
			arr.append(p)
		while arr.size() < MAX_PLANES:
			arr.append(Vector4())
		mt.set_shader_parameter("planes", arr)
		mt.set_shader_parameter("plane_n", planes.size())
		mats.append(mt)
	return mats


## PartUI._look_surfaces calls this after the bodies' own looks are on: a cut (Section tool / Cut view: pu.sec_cut) or a split in the record
## puts the section look on every surface. Nothing to do (the own looks stay) when neither is there, or while X-ray is on
static func after_look(pu: Node) -> void:
	var mi: MeshInstance3D = pu.part_mesh
	if mi == null or mi.mesh == null or bool(pu.xray):
		return
	var cut: Dictionary = pu.sec_cut
	var planes := split_planes(pu.m.S.part)
	if cut.is_empty() and planes.is_empty():
		return
	var n := mi.mesh.get_surface_count()
	var ov = mi.material_override
	if not cut.is_empty() and ov is ShaderMaterial:   # the one override material outranks the surface ones: it picks each body's colours from the vertex tag
		if n > 0 and (mi.mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_COLOR) == 0:
			mi.mesh = tag(mi.mesh)
		feed(ov, pu.res.get("looks", []), n)
	var mats := materials(pu.res.get("looks", []), n, cut, planes, cut.is_empty())
	for s in n:
		mi.set_surface_override_material(s, mats[s])


## the cut the Nice picture should show: the Section tool's or the Easy Cut view's, as {"n", "w"}; {} when no cut is on
static func live_cut(main: Node) -> Dictionary:
	if main == null or main.bld == null or main.bld.part == null:
		return {}
	var pu: Node = main.bld.part
	return (pu.sec_cut as Dictionary).duplicate() if not (pu.sec_cut as Dictionary).is_empty() else {}


## a copy of the mesh whose vertices carry their body (surface) number in COLOR.r (i / 16): the section shader picks the body's colours by it
static func tag(src: ArrayMesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		var arr: Array = src.surface_get_arrays(s)
		var nv: int = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var cols := PackedColorArray()
		cols.resize(nv)
		cols.fill(Color(float(s) / 16.0, 0.0, 0.0, 1.0))
		arr[Mesh.ARRAY_COLOR] = cols
		out.add_surface_from_arrays(src.surface_get_primitive_type(s), arr)
		out.surface_set_material(s, src.surface_get_material(s))
	return out


## the per-body colour arrays of the section shader (linear colours: the arrays carry no colour hint)
static func feed(mat: ShaderMaterial, looks: Array, n: int) -> void:
	var caps := cap_colors(looks, n)
	var ca := []
	var sa := []
	for i in 16:
		if i < n:
			var cl: Color = (caps[i] as Color).srgb_to_linear()
			ca.append(Vector4(cl.r, cl.g, cl.b, 1.0))
			var sc: Color = (Part.look_at(looks, i)["c"] as Color).srgb_to_linear()
			sa.append(Vector4(sc.r, sc.g, sc.b, 1.0))
		else:
			ca.append(Vector4(0, 0, 0, 1.0))
			sa.append(Vector4(0, 0, 0, 1.0))
	mat.set_shader_parameter("caps", ca)
	mat.set_shader_parameter("solids", sa)
	mat.set_shader_parameter("body_n", mini(n, 16))
