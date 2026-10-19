## USD EXPORT (round 42, GATES XX9; UPGRADES_300 #327). A scene -> USDA text, the skeleton animation as UsdSkel, one time
## sample per frame at the scene's fps. Read: openusd.org/release/api/_usd_skel__intro.html and _usd_skel__schemas.html
## (the page does not spell out the attribute types; the types below are the UsdSkel schema's: Skeleton joints
## uniform token[] (paths, parents first), bindTransforms matrix4d[] (joint to WORLD at bind), restTransforms matrix4d[]
## (joint to PARENT), SkelAnimation joints token[], translations float3[], rotations quatf[] written (w, x, y, z) as
## GfQuatf, scales half3[]; the animation is bound by rel skel:animationSource through SkelBindingAPI).
## The poser's FK is the USD form: G[j] = G[parent] * A[j], and a joint's offset from its parent is p0[j] - p0[parent],
## all in world axes at rest (rest rotation = identity), so a joint's local rotation is compose(j, ang[j]) and its
## translation is that offset (the pelvis: its world position P). USD matrices are row-vector: the translation is the
## LAST ROW. Metres, Y up: metersPerUnit = 1, upAxis = "Y", as the poser. The weapons are not exported (a skeleton file).
class_name UsdExport
extends RefCounted


static func _f(v: float) -> String:
	return String.num(v, 9)


static func _m(t: Vector3) -> String:
	return "( (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 1, 0), (%s, %s, %s, 1) )" % [_f(t.x), _f(t.y), _f(t.z)]


## the scene as USDA text: [text, {"frames", "joints", "fps"}]. B is posed through the scene; its state is put back.
static func text(S: Scene, B: Body) -> Array:
	var keep := B.state()
	if B.body != S.body:
		B.set_proportions(S.body)   # PR2: bind and rest transforms are the scene's own body's (put back at the end)
	var paths := {}
	var joints := PackedStringArray()
	for j in Body.ORDER:   # ORDER lists parents before children
		paths[j] = j if B.parent[j] == "" else String(paths[B.parent[j]]) + "/" + j
		joints.append(paths[j])
	var q := func(a: PackedStringArray) -> String: return "[" + ", ".join(a) + "]"
	var jt := PackedStringArray()
	var bind := PackedStringArray()
	var rest := PackedStringArray()
	var scl := PackedStringArray()
	for j in Body.ORDER:
		jt.append("\"%s\"" % paths[j])
		bind.append(_m(B.p0[j]))
		rest.append(_m(B.p0[j] if B.parent[j] == "" else (B.p0[j] as Vector3) - (B.p0[B.parent[j]] as Vector3)))
		scl.append("(1, 1, 1)")
	var fps := float(maxi(1, S.fps))
	var n := int(ceil(S.length() * fps - 1e-6)) + 1
	var h := PackedStringArray(["#usda 1.0", "(", "    defaultPrim = \"Kine\"", "    metersPerUnit = 1", "    upAxis = \"Y\"",
		"    timeCodesPerSecond = %s" % _f(fps), "    framesPerSecond = %s" % _f(fps), "    startTimeCode = 0", "    endTimeCode = %d" % (n - 1),
		"    doc = \"Kine scene %s\"" % S.name, ")", "", "def SkelRoot \"Kine\"", "{",
		"    def Skeleton \"Skel\" (", "        prepend apiSchemas = [\"SkelBindingAPI\"]", "    )", "    {",
		"        uniform token[] joints = " + q.call(jt),
		"        uniform matrix4d[] bindTransforms = " + q.call(bind),
		"        uniform matrix4d[] restTransforms = " + q.call(rest),
		"        rel skel:animationSource = </Kine/Skel/Anim>", "    }", "",
		"    def SkelAnimation \"Anim\"", "    {", "        uniform token[] joints = " + q.call(jt)])
	var tr := PackedStringArray()
	var ro := PackedStringArray()
	for i in n:
		S.apply(B, minf(i / fps, S.length()))
		B.fk()
		var t := PackedStringArray()
		var r := PackedStringArray()
		for j in Body.ORDER:
			var off: Vector3 = B.P[j] if B.parent[j] == "" else (B.p0[j] as Vector3) - (B.p0[B.parent[j]] as Vector3)
			t.append("(%s, %s, %s)" % [_f(off.x), _f(off.y), _f(off.z)])
			var a := B.compose(j, B.ang[j]).normalized()
			r.append("(%s, %s, %s, %s)" % [_f(a.w), _f(a.x), _f(a.y), _f(a.z)])
		tr.append("            %d: %s," % [i, q.call(t)])
		ro.append("            %d: %s," % [i, q.call(r)])
	h.append("        float3[] translations.timeSamples = {")
	h.append_array(tr)
	h.append("        }")
	h.append("        quatf[] rotations.timeSamples = {")
	h.append_array(ro)
	h.append("        }")
	h.append("        half3[] scales = " + q.call(scl))
	h.append("    }")
	h.append("}")
	B.set_state(keep)
	return ["\n".join(h) + "\n", {"frames": n, "joints": Body.ORDER.size(), "fps": S.fps}]


## write the scene as USDA at path (res:// or absolute): [OK or the error, info]
static func write(S: Scene, B: Body, path: String) -> Array:
	var r := text(S, B)
	var abs := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	DirAccess.make_dir_recursive_absolute(abs.get_base_dir())
	var fa := FileAccess.open(abs, FileAccess.WRITE)
	if fa == null:
		return [FileAccess.get_open_error(), r[1]]
	fa.store_string(r[0])
	fa.close()
	return [OK, r[1]]
