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


## SKIN AND BLEND SHAPES (L14, GAP_AUDIT_1106 #10): the SkelRoot "Kine" holds Skeleton "Skel", SkelAnimation "Anim" (the
## same ones text() writes, plus blendShapes / blendShapeWeights time samples) and the skinned Mesh "Body" with its BlendShape
## prims, so the character opens in Unreal or Houdini. UsdSkel schema (openusd.org/release/api/_usd_skel__schemas.html):
##   Mesh + SkelBindingAPI: rel skel:skeleton, primvars:skel:jointIndices / jointWeights (int[] / float[], interpolation
##   "vertex", elementSize = the influences per vertex, short vertices padded with index 0 weight 0), primvars:skel:geomBindTransform
##   (matrix4d: mesh space -> skeleton space at bind; points are stored as geomBind^-1 * world rest), uniform token[]
##   skel:blendShapes + rel skel:blendShapeTargets (the BlendShape prims, children of the Mesh).
##   BlendShape: uniform vector3f[] offsets, and uniform int[] pointIndices when the shape is sparse (offsets then has one
##   entry per index). USD evaluates the shapes first (points += weight * offset), then the skinning.
## ch = {"name", "verts" (world rest, the body's rest space), "faces": [PackedInt32Array], "k" (stride of ids / w), "ids"
##   (PackedInt32Array V*k, index into Body.ORDER, -1 = none), "w" (PackedFloat32Array V*k), "bind_xf" (Transform3D, optional,
##   identity default), "shapes": [{"name", "offsets": PackedVector3Array (V), "sparse": bool}], "shape_w": Callable(t) -> {name: weight}}
## -> [text, {"frames", "joints", "fps", "verts", "k", "shapes"}]. text() and the layered / actor writers are unchanged.
static func text_skinned(S: Scene, B: Body, ch: Dictionary, clean := true) -> Array:
	var fps := float(maxi(1, S.fps))
	var L := S.length()
	var n := int(ceil(L * fps - 1e-6)) + 1
	var pad := "    "
	var root := "/Kine"
	var shapes: Array = ch.get("shapes", [])
	var snames := PackedStringArray()
	var pnames := PackedStringArray()
	for sh in shapes:
		pnames.append(prim_name(String(sh["name"])))
		snames.append("\"%s\"" % pnames[pnames.size() - 1])
	var extra := PackedStringArray()
	if not shapes.is_empty():
		extra.append(pad + "    uniform token[] blendShapes = [" + ", ".join(snames) + "]")
		extra.append(pad + "    float[] blendShapeWeights.timeSamples = {")
		var swf: Callable = ch["shape_w"]
		for i in n:
			var sw: Dictionary = swf.call(minf(i / fps, L))
			var ws := PackedStringArray()
			for sh in shapes:
				ws.append(_f(float(sw.get(sh["name"], 0.0))))
			extra.append(pad + "        %d: [%s]," % [i, ", ".join(ws)])
		extra.append(pad + "    }")
	var h := _head(S.name, fps, n)
	h.append_array(PackedStringArray(["def SkelRoot \"Kine\"", "{"]))
	h.append_array(_skel(S, B, n, fps, L, pad, root, clean, extra))
	var verts: PackedVector3Array = ch["verts"]
	var nv := verts.size()
	var stride: int = ch["k"]
	var ids: PackedInt32Array = ch["ids"]
	var w: PackedFloat32Array = ch["w"]
	var kk := 1
	for v in nv:
		var c := 0
		for q in stride:
			if ids[v * stride + q] >= 0 and w[v * stride + q] > 0.0:
				c += 1
		kk = maxi(kk, c)
	var ji := PackedStringArray()
	var jw := PackedStringArray()
	for v in nv:
		var c := 0
		for q in stride:
			if ids[v * stride + q] >= 0 and w[v * stride + q] > 0.0:
				ji.append(str(ids[v * stride + q]))
				jw.append(_f(w[v * stride + q]))
				c += 1
		while c < kk:
			ji.append("0")
			jw.append("0")
			c += 1
	var bx: Transform3D = ch.get("bind_xf", Transform3D.IDENTITY)
	var inv := bx.affine_inverse()
	var pts := PackedStringArray()
	for p in verts:
		var l := inv * p
		pts.append("(%s, %s, %s)" % [_f(l.x), _f(l.y), _f(l.z)])
	var fc := PackedStringArray()
	var fi := PackedStringArray()
	for f in ch["faces"]:
		fc.append(str((f as PackedInt32Array).size()))
		for i in (f as PackedInt32Array):
			fi.append(str(i))
	var b := bx.basis
	var tg := PackedStringArray()
	for nm in pnames:
		tg.append("<%s/Body/%s>" % [root, nm])
	h.append_array(PackedStringArray([pad + "def Mesh \"Body\" (", pad + "    prepend apiSchemas = [\"SkelBindingAPI\"]", pad + ")", pad + "{",
		pad + "    int[] faceVertexCounts = [" + ", ".join(fc) + "]",
		pad + "    int[] faceVertexIndices = [" + ", ".join(fi) + "]",
		pad + "    point3f[] points = [" + ", ".join(pts) + "]",
		pad + "    uniform token subdivisionScheme = \"none\"",
		pad + "    matrix4d primvars:skel:geomBindTransform = ( (%s, %s, %s, 0), (%s, %s, %s, 0), (%s, %s, %s, 0), (%s, %s, %s, 1) )" % [
			_f(b.x.x), _f(b.x.y), _f(b.x.z), _f(b.y.x), _f(b.y.y), _f(b.y.z), _f(b.z.x), _f(b.z.y), _f(b.z.z),
			_f(bx.origin.x), _f(bx.origin.y), _f(bx.origin.z)],
		pad + "    int[] primvars:skel:jointIndices = [" + ", ".join(ji) + "] (",
		pad + "        elementSize = %d" % kk, pad + "        interpolation = \"vertex\"", pad + "    )",
		pad + "    float[] primvars:skel:jointWeights = [" + ", ".join(jw) + "] (",
		pad + "        elementSize = %d" % kk, pad + "        interpolation = \"vertex\"", pad + "    )",
		pad + "    rel skel:skeleton = <%s/Skel>" % root]))
	if not shapes.is_empty():
		h.append(pad + "    uniform token[] skel:blendShapes = [" + ", ".join(snames) + "]")
		h.append(pad + "    rel skel:blendShapeTargets = [" + ", ".join(tg) + "]")
	for si in shapes.size():
		var sh: Dictionary = shapes[si]
		var offs: PackedVector3Array = sh["offsets"]
		var sparse := bool(sh.get("sparse", false))
		var idx := PackedStringArray()
		var ov := PackedStringArray()
		for i in offs.size():
			if sparse and offs[i] == Vector3.ZERO:
				continue
			idx.append(str(i))
			ov.append("(%s, %s, %s)" % [_f(offs[i].x), _f(offs[i].y), _f(offs[i].z)])
		h.append(pad + "    def BlendShape \"%s\"" % pnames[si])
		h.append(pad + "    {")
		h.append(pad + "        uniform vector3f[] offsets = [" + ", ".join(ov) + "]")
		if sparse:
			h.append(pad + "        uniform int[] pointIndices = [" + ", ".join(idx) + "]")
		h.append(pad + "    }")
	h.append(pad + "}")
	h.append("}")
	return ["\n".join(h) + "\n", {"frames": n, "joints": Body.ORDER.size(), "fps": S.fps, "verts": nv, "k": kk, "shapes": shapes.size()}]


## the skinned character in one .usda at path (text_skinned): [OK or the error, info]
static func write_skinned(S: Scene, B: Body, ch: Dictionary, path: String) -> Array:
	var r := text_skinned(S, B, ch)
	var abs := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	DirAccess.make_dir_recursive_absolute(abs.get_base_dir())
	var fa := FileAccess.open(abs, FileAccess.WRITE)
	if fa == null:
		return [FileAccess.get_open_error(), r[1]]
	fa.store_string(r[0])
	fa.close()
	return [OK, r[1]]


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
static func _skel(S: Scene, B: Body, n: int, fps: float, L: float, pad: String, root: String, clean := true, extra := PackedStringArray()) -> PackedStringArray:
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
		pad + "    rel skel:animationSource = <%s/Anim>" % root, pad + "}", "",
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
	h.append_array(extra)   # skinned export: the SkelAnimation's blendShapes / blendShapeWeights (empty for the flat writers)
	h.append(pad + "}")
	B.set_state(keep)
	return h


## LAYERED USD (ROADMAP 79, GATES USDL): the scene as a folder <name>_usd/ of .usda layers under one root <name>.usda.
## The root's subLayers, strongest first (USD: the first listed wins):
##   <name>_props.usda        the set's props at rest (Xform each) and the shot camera (Camera "Shot", a sample per frame)
##   <name>_points.usda       the joints' world positions per frame: Kine/JointCache, a Points prim in metres. This is the
##                            joint point cache. It is NOT Alembic: no Ogawa writer here (the export dialog says why)
##   <name>_layer_NN_<label>.usda   one per animation layer, numbered in the order the app plays them (the YY9 layer first,
##                            then Scene.layers): an override of Kine/Anim whose rotations and translations are the WHOLE pose
##                            after the stack up to that layer (layers above it muted, as the app mutes them). The top layer
##                            therefore plays the full pose on its own; muting it reveals the pose below it.
##   <name>_base.usda         SkelAnimation Kine/Anim: the pose with NO layer (the cards, clips, breath, IK, plants, constraints)
##   <name>_skeleton.usda     SkelRoot Kine > Skeleton Skel: joints, bind and rest transforms (the rest pose)
## LIMIT: a mute shows only from the top of the stack. A lower layer muted under a live layer above it changes nothing the
## DCC shows, because the layer above carries the whole pose. A layer's file holds its played curve (its weight is baked in).
## The flat single-file writers (text, write, text_actors) are unchanged: their bytes are pinned by other suites.
static func _units(S: Scene) -> Array:
	var u := []
	if not S.layer.is_empty():
		u.append({"label": "yy9", "src": -1})
	for i in S.layers.size():
		u.append({"label": String(S.layers[i].get("name", "layer")), "src": i})
	return u


## the scene as the stack plays it up to unit p (p = -1: no layer at all): the layers above p are muted and unsoloed
static func _upto(S: Scene, units: Array, p: int) -> Scene:
	var C := S.clone()
	var keep := {}
	for k in range(0, p + 1):
		if int(units[k]["src"]) >= 0:
			keep[int(units[k]["src"])] = true
	if p < 0:
		C.layer = {}
	for i in C.layers.size():
		if not keep.has(i):
			C.layers[i]["mute"] = true
			C.layers[i]["solo"] = false
	return C


## the header every layer file opens with: "#usda 1.0" and its layer metadata (which part of the set it is)
## the time metadata is in every layer too: USD rescales a sublayer whose timeCodesPerSecond differs from the root's
## (a 30 fps root over a layer without it reads the layer's frame 71 at stage frame 88.75), so each layer repeats the root's
static func _hdr_lines(part: String, fps: float) -> PackedStringArray:
	return PackedStringArray(["#usda 1.0", "(", "    customLayerData = {", "        string kine_part = \"%s\"" % part, "    }",
		"    timeCodesPerSecond = %s" % _f(fps), "    framesPerSecond = %s" % _f(fps), ")", ""])


static func _xfm(x: Transform3D) -> String:
	var bx := x.basis
	return "( (%s, %s, %s, 0), (%s, %s, %s, 0), (%s, %s, %s, 0), (%s, %s, %s, 1) )" % [
		_f(bx.x.x), _f(bx.x.y), _f(bx.x.z), _f(bx.y.x), _f(bx.y.y), _f(bx.y.z), _f(bx.z.x), _f(bx.z.y), _f(bx.z.z),
		_f(x.origin.x), _f(x.origin.y), _f(x.origin.z)]


## per frame: the translation and rotation sample lines ("i: [...],") of C's pose, joints in Body.ORDER
static func _samples(C: Scene, B: Body, n: int, fps: float, L: float, ind: String) -> Array:
	var tr := PackedStringArray()
	var ro := PackedStringArray()
	for i in n:
		C.apply(B, minf(i / fps, L))
		B.fk()
		var t := PackedStringArray()
		var r := PackedStringArray()
		for j in Body.ORDER:
			var off: Vector3 = B.P[j] if B.parent[j] == "" else (B.p0[j] as Vector3) - (B.p0[B.parent[j]] as Vector3)
			t.append("(%s, %s, %s)" % [_f(off.x), _f(off.y), _f(off.z)])
			var a := B.compose(j, B.ang[j]).normalized()
			r.append("(%s, %s, %s, %s)" % [_f(a.w), _f(a.x), _f(a.y), _f(a.z)])
		tr.append("%s%d: [%s]," % [ind, i, ", ".join(t)])
		ro.append("%s%d: [%s]," % [ind, i, ", ".join(r)])
	return [tr, ro]


## the joints' world positions per frame (B.P: the app's own FK of the scene's final pose)
static func _points(S: Scene, B: Body, n: int, fps: float, L: float, ind: String) -> PackedStringArray:
	var out := PackedStringArray()
	for i in n:
		S.apply(B, minf(i / fps, L))
		B.fk()
		var p := PackedStringArray()
		for j in Body.ORDER:
			var v: Vector3 = B.P[j]
			p.append("(%s, %s, %s)" % [_f(v.x), _f(v.y), _f(v.z)])
		out.append("%s%d: [%s]," % [ind, i, ", ".join(p)])
	return out


## the camera's transform and focal length per frame (ShotCam: pos, aim, f mm; Godot looks down -Z as USD does)
static func _camera(S: Scene, n: int, fps: float, L: float, ind: String) -> Array:
	var tr := PackedStringArray()
	var fo := PackedStringArray()
	for i in n:
		var k := ShotCam.at(S.shots, minf(i / fps, L))
		tr.append("%s%d: %s," % [ind, i, _xfm(ShotCam.xf(k["pos"], k["aim"]))])
		fo.append("%s%d: %s," % [ind, i, _f(float(k["f"]))])
	return [tr, fo]


## one Kine/Anim block (SkelAnimation or an override of it) at 4 spaces; scl = a whole "half3[] scales" line or ""
static func _anim(prim: String, jline: String, tr: PackedStringArray, ro: PackedStringArray, scl: String) -> PackedStringArray:
	var h := PackedStringArray(["    " + prim, "    {", "        uniform token[] joints = " + jline, "        float3[] translations.timeSamples = {"])
	h.append_array(tr)
	h.append("        }")
	h.append("        quatf[] rotations.timeSamples = {")
	h.append_array(ro)
	h.append("        }")
	if scl != "":
		h.append("        " + scl)
	h.append("    }")
	return h


static func _write_text(path: String, txt: String) -> int:
	var fa := FileAccess.open(path, FileAccess.WRITE)
	if fa == null:
		return FileAccess.get_open_error()
	fa.store_string(txt)
	fa.close()
	return OK


## the layered set: [OK or the error, {"root", "sublayers" (strongest first), "layers", "joints", "frames", "fps"}].
## B is posed through the scene and put back at the end. nm names the folder and the files.
static func write_layers(S: Scene, B: Body, dir: String, nm: String) -> Array:
	var fps := float(maxi(1, S.fps))
	var L := S.length()
	var n := int(ceil(L * fps - 1e-6)) + 1
	var N := Body.ORDER.size()
	var keep := B.state()
	if B.body != S.body:
		B.set_proportions(S.body)
	var pn := prim_name(nm)
	var abs := ProjectSettings.globalize_path(dir) if (dir.begins_with("res://") or dir.begins_with("user://")) else dir
	var folder := abs.path_join(pn + "_usd")
	DirAccess.make_dir_recursive_absolute(folder)
	var jt := PackedStringArray()
	var bind := PackedStringArray()
	var rest := PackedStringArray()
	var wd := PackedStringArray()
	var sc := PackedStringArray()
	var paths := {}
	for j in Body.ORDER:
		paths[j] = j if B.parent[j] == "" else String(paths[B.parent[j]]) + "/" + j
		jt.append("\"%s\"" % paths[j])
		bind.append(_m(B.p0[j]))
		rest.append(_m(B.p0[j] if B.parent[j] == "" else (B.p0[j] as Vector3) - (B.p0[B.parent[j]] as Vector3)))
		wd.append("0.02")
		sc.append("(1, 1, 1)")
	var jline := "[" + ", ".join(jt) + "]"
	var files := {}   # file name -> text
	var sk_head := "\n".join(_hdr_lines("skeleton", fps)) +"\ndef SkelRoot \"Kine\"\n{\n    def Skeleton \"Skel\" (\n        prepend apiSchemas = [\"SkelBindingAPI\"]\n    )\n    {\n"
	var sk_body := "        uniform token[] joints = %s\n        uniform matrix4d[] bindTransforms = [%s]\n        uniform matrix4d[] restTransforms = [%s]\n" % [jline, ", ".join(bind), ", ".join(rest)]
	files[pn + "_skeleton.usda"] = sk_head + sk_body + "        rel skel:animationSource = </Kine/Anim>\n    }\n}\n"
	var units := _units(S)
	var bl := _hdr_lines("base", fps) +PackedStringArray(["over \"Kine\"", "{"])
	var bs := _samples(_upto(S, units, -1), B, n, fps, L, "            ")
	bl.append_array(_anim("def SkelAnimation \"Anim\"", jline, bs[0], bs[1], "half3[] scales = [" + ", ".join(sc) + "]"))
	bl.append("}")
	files[pn + "_base.usda"] = "\n".join(bl) + "\n"
	for k in units.size():
		var src := int(units[k]["src"])
		var muted := src >= 0 and bool(S.layers[src].get("mute", false))
		var s := _samples(_upto(S, units, k), B, n, fps, L, "            ")
		var lf := PackedStringArray(["#usda 1.0", "(", "    customLayerData = {", "        string kine_layer = \"%s\"" % String(units[k]["label"]).c_escape(),
			"        bool kine_muted = %s" % ("true" if muted else "false"), "    }", "    timeCodesPerSecond = %s" % _f(fps), "    framesPerSecond = %s" % _f(fps), ")", "", "over \"Kine\"", "{"])
		lf.append_array(_anim("over \"Anim\"", jline, s[0], s[1], ""))
		lf.append("}")
		files["%s_layer_%02d_%s.usda" % [pn, k, prim_name(String(units[k]["label"]))]] = "\n".join(lf) + "\n"
	var pts := _hdr_lines("points", fps) +PackedStringArray(["over \"Kine\"", "{", "    def Points \"JointCache\"", "    {",
		"        uniform token[] kine:joints = " + jline, "        float[] widths = [" + ", ".join(wd) + "]", "        point3f[] points.timeSamples = {"])
	pts.append_array(_points(S, B, n, fps, L, "            "))
	pts.append_array(PackedStringArray(["        }", "    }", "}"]))
	files[pn + "_points.usda"] = "\n".join(pts) + "\n"
	var pc := _hdr_lines("props", fps)
	if not S.props.is_empty():
		pc.append_array(PackedStringArray(["def Xform \"Props\"", "{"]))
		for k in S.props.size():
			var p: Dictionary = S.props[k]
			pc.append_array(PackedStringArray(["    def Xform \"Prop_%d_%s\"" % [k, prim_name(String(p["kind"]))], "    {",
				"        matrix4d xformOp:transform = " + _xfm(p["xf"]), "        uniform token[] xformOpOrder = [\"xformOp:transform\"]", "    }"]))
		pc.append("}")
	if not S.shots.is_empty():
		var cam := _camera(S, n, fps, L, "            ")
		pc.append_array(PackedStringArray(["def Camera \"Shot\"", "{", "    float horizontalAperture = 36", "    float verticalAperture = 20.25",
			"    float focalLength.timeSamples = {"]))
		pc.append_array(cam[1])
		pc.append_array(PackedStringArray(["    }", "    matrix4d xformOp:transform.timeSamples = {"]))
		pc.append_array(cam[0])
		pc.append_array(PackedStringArray(["    }", "    uniform token[] xformOpOrder = [\"xformOp:transform\"]", "}"]))
	files[pn + "_props.usda"] = "\n".join(pc) + "\n"
	var order := [pn + "_props.usda", pn + "_points.usda"]
	for k in range(units.size() - 1, -1, -1):
		order.append("%s_layer_%02d_%s.usda" % [pn, k, prim_name(String(units[k]["label"]))])
	order.append_array([pn + "_base.usda", pn + "_skeleton.usda"])
	var subs := PackedStringArray()
	for f in order:
		subs.append("        @./%s@" % f)
	var root_head := "#usda 1.0\n(\n    defaultPrim = \"Kine\"\n    metersPerUnit = 1\n    upAxis = \"Y\"\n    timeCodesPerSecond = %s\n    framesPerSecond = %s\n" % [_f(fps), _f(fps)]
	var root_tail := "    startTimeCode = 0\n    endTimeCode = %d\n    doc = \"Kine scene %s\"\n    subLayers = [\n%s\n    ]\n)\n" % [n - 1, nm, ",\n".join(subs)]
	files[pn + ".usda"] = root_head + root_tail
	for f in files:
		var e := _write_text(folder + "/" + f, files[f])
		if e != OK:
			B.set_state(keep)
			return [e, {}]
	B.set_state(keep)
	return [OK, {"root": folder + "/" + pn + ".usda", "sublayers": order, "layers": units.size(), "joints": N, "frames": n, "fps": S.fps}]


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
