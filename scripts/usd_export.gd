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
static func text(S: Scene, B: Body, clean := true) -> Array:
	var fps := float(maxi(1, S.fps))
	var n := int(ceil(S.length() * fps - 1e-6)) + 1
	var h := _head(S.name, fps, n)
	h.append_array(PackedStringArray(["def SkelRoot \"Kine\"", "{"]))
	h.append_array(_skel(S, B, n, fps, S.length(), "    ", "/Kine", clean))
	h.append("}")
	return ["\n".join(h) + "\n", {"frames": n, "joints": Body.ORDER.size(), "fps": S.fps}]


## TWO CHARACTERS (round 50, GATES TC6): every actor in one stage. actors = [{"name", "S", "B", "xf": Transform3D}].
## defaultPrim Xform "Kine" holds one SkelRoot per actor, named by the actor (spaces and the like made "_"), placed by
## its xformOp:transform (the actor's xf, row-vector: the translation is the last row), each with its own Skeleton and
## SkelAnimation sampled from its own scene over the same time range (0 .. the longest scene, the hero's fps).
## -> [text, {"frames", "joints", "fps", "prims": [prim names]}]
static func text_actors(actors: Array, title: String, clean := true) -> Array:
	var L := 0.0
	for a in actors:
		L = maxf(L, (a["S"] as Scene).length())
	var fps := float(maxi(1, (actors[0]["S"] as Scene).fps))
	var n := int(ceil(L * fps - 1e-6)) + 1
	var h := _head(title, fps, n)
	h.append_array(PackedStringArray(["def Xform \"Kine\"", "{"]))
	var prims := []
	for a in actors:
		var pn := prim_name(String(a["name"]))
		while pn in prims:
			pn += "_"
		prims.append(pn)
		var x: Transform3D = a["xf"]
		var bx := x.basis
		h.append_array(PackedStringArray(["    def SkelRoot \"%s\" (" % pn, "        doc = \"Kine actor %s\"" % String(a["name"]).c_escape(), "    )", "    {",
			"        matrix4d xformOp:transform = ( (%s, %s, %s, 0), (%s, %s, %s, 0), (%s, %s, %s, 0), (%s, %s, %s, 1) )" % [
				_f(bx.x.x), _f(bx.x.y), _f(bx.x.z), _f(bx.y.x), _f(bx.y.y), _f(bx.y.z), _f(bx.z.x), _f(bx.z.y), _f(bx.z.z),
				_f(x.origin.x), _f(x.origin.y), _f(x.origin.z)],
			"        uniform token[] xformOpOrder = [\"xformOp:transform\"]"]))
		h.append_array(_skel(a["S"], a["B"], n, fps, L, "        ", "/Kine/" + pn, clean))
		h.append("    }")
	h.append("}")
	return ["\n".join(h) + "\n", {"frames": n, "joints": Body.ORDER.size(), "fps": int(fps), "prims": prims}]


## an actor's name as a USD prim name (letters, digits, "_"; not starting with a digit)
static func prim_name(s: String) -> String:
	var o := ""
	for c in s:
		o += c if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "_" else "_"
	if o == "" or (o[0] >= "0" and o[0] <= "9"):
		o = "_" + o
	return o


static func _head(title: String, fps: float, n: int) -> PackedStringArray:
	return PackedStringArray(["#usda 1.0", "(", "    defaultPrim = \"Kine\"", "    metersPerUnit = 1", "    upAxis = \"Y\"",
		"    timeCodesPerSecond = %s" % _f(fps), "    framesPerSecond = %s" % _f(fps), "    startTimeCode = 0", "    endTimeCode = %d" % (n - 1),
		"    doc = \"Kine scene %s\"" % title, ")", ""])


## one Skeleton + SkelAnimation (lines, indented by pad) under the prim at root, n samples at fps over 0..L
static func _skel(S: Scene, B: Body, n: int, fps: float, L: float, pad: String, root: String, clean := true) -> PackedStringArray:
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
	var h := PackedStringArray([
		pad + "def Skeleton \"Skel\" (", pad + "    prepend apiSchemas = [\"SkelBindingAPI\"]", pad + ")", pad + "{",
		pad + "    uniform token[] joints = " + q.call(jt),
		pad + "    uniform matrix4d[] bindTransforms = " + q.call(bind),
		pad + "    uniform matrix4d[] restTransforms = " + q.call(rest),
		pad + "    rel skel:animationSource = <%s/Skel/Anim>" % root, pad + "}", "",
		pad + "def SkelAnimation \"Anim\"", pad + "{", pad + "    uniform token[] joints = " + q.call(jt)])
	var tr := PackedStringArray()
	var ro := PackedStringArray()
	# the rotations per joint, then the sign continuity pass (RotClean.hemisphere: dot with the previous frame >= 0)
	var qa := []
	for _j in Body.ORDER.size():
		qa.append([])
	for i in n:
		S.apply(B, minf(i / fps, L))
		B.fk()
		var t := PackedStringArray()
		for jj in Body.ORDER.size():
			var j: String = Body.ORDER[jj]
			var off: Vector3 = B.P[j] if B.parent[j] == "" else (B.p0[j] as Vector3) - (B.p0[B.parent[j]] as Vector3)
			t.append("(%s, %s, %s)" % [_f(off.x), _f(off.y), _f(off.z)])
			qa[jj].append(B.compose(j, B.ang[j]).normalized())
		tr.append(pad + "        %d: %s," % [i, q.call(t)])
	var hq := []
	for jj in Body.ORDER.size():
		hq.append(RotClean.hemisphere(qa[jj], clean))
	for i in n:
		var r := PackedStringArray()
		for jj in Body.ORDER.size():
			var a: Quaternion = hq[jj][i]
			r.append("(%s, %s, %s, %s)" % [_f(a.w), _f(a.x), _f(a.y), _f(a.z)])
		ro.append(pad + "        %d: %s," % [i, q.call(r)])
	h.append(pad + "    float3[] translations.timeSamples = {")
	h.append_array(tr)
	h.append(pad + "    }")
	h.append(pad + "    quatf[] rotations.timeSamples = {")
	h.append_array(ro)
	h.append(pad + "    }")
	h.append(pad + "    half3[] scales = " + q.call(scl))
	h.append(pad + "}")
	B.set_state(keep)
	return h


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


## every actor in one .usda at path (text_actors): [OK or the error, info]
static func write_actors(actors: Array, path: String) -> Array:
	var r := text_actors(actors, path.get_file().get_basename())
	var abs := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	DirAccess.make_dir_recursive_absolute(abs.get_base_dir())
	var fa := FileAccess.open(abs, FileAccess.WRITE)
	if fa == null:
		return [FileAccess.get_open_error(), r[1]]
	fa.store_string(r[0])
	fa.close()
	return [OK, r[1]]
