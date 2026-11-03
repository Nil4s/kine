class_name FbxCamera
extends RefCounted
## FbxCamera (C09, complaint #702): the scene's shot camera written into the FBX as a Camera Model + a Camera NodeAttribute, keyed.
## Opt-in: FbxExport.write(..., camera_keys) with the keys of one shot (ShotCam: [{"t", "pos", "aim", "f"}]); [] writes nothing new.
## POSITION: Lcl Translation in centimetres, like every bone in the file, one key per camera key.
## ROTATION: Lcl Rotation, Euler XYZ degrees, unrolled (RotClean) so a pan does not flip. FBX (Autodesk) cameras look down their
##   local +X axis, Kine's (Godot's) look down -Z, so the stored basis is look_basis * Ry(+90 deg): then local +X lands on the view direction.
## LENS: NodeAttribute "Camera" with FocalLength (mm, 36 mm film width), FieldOfView (horizontal degrees), FieldOfViewX/Y, AspectWidth/Height 16:9;
##   FocalLength is also a key curve, so a zoom survives.
## Times are KTime ticks like the bones' (FbxExport.KTIME). The text is inserted into the finished ASCII tree, so the binary writer takes it too.

const ID0 := 1200000000
const TURN := Basis(Vector3.UP, PI * 0.5)


static func _curve(times: PackedStringArray, vals: PackedStringArray) -> String:
	var n := times.size()
	return "\t\tDefault: 0\n\t\tKeyVer: 4008\n\t\tKeyTime: *%d {\n\t\t\ta: %s\n\t\t}\n\t\tKeyValueFloat: *%d {\n\t\t\ta: %s\n\t\t}\n\t\tKeyAttrFlags: *1 {\n\t\t\ta: 24836\n\t\t}\n\t\tKeyAttrDataFloat: *4 {\n\t\t\ta: 0,0,0,0\n\t\t}\n\t\tKeyAttrRefCount: *1 {\n\t\t\ta: %d\n\t\t}" % [n, ",".join(times), n, ",".join(vals), n]


## the camera's local transform per key as FBX stores it (basis turned, origin metres)
static func fbx_xf(pos: Vector3, aim: Vector3) -> Transform3D:
	var t := ShotCam.xf(pos, aim)
	return Transform3D(t.basis * TURN, pos)


static func _bump(text: String, kind: String, by: int) -> String:
	var rx := RegEx.new()
	rx.compile("(ObjectType: \"" + kind + "\" [{]\n\t\tCount: )([0-9]+)")
	var m := rx.search(text)
	if m == null:
		return text
	return text.substr(0, m.get_start(2)) + str(int(m.get_string(2)) + by) + text.substr(m.get_end(2))


## text = the finished ASCII FBX; returns it with the camera added. keys empty -> text unchanged.
static func inject(text: String, keys: Array, name := "Camera") -> String:
	if keys.is_empty():
		return text
	var lay := RegEx.create_from_string("AnimationLayer: ([0-9]+)").search(text)
	if lay == null:
		return text
	var layer_id := int(lay.get_string(1))
	var cam := ID0 + 1
	var attr := ID0 + 2
	var times := PackedStringArray()
	var xfs := []
	var qs := []
	for k in keys:
		times.append(str(int(round(float(k["t"]) * FbxExport.KTIME))))
		var x := fbx_xf(k["pos"], k["aim"])
		xfs.append(x)
		qs.append(x.basis.orthonormalized().get_rotation_quaternion())
	var eu := RotClean.euler_track(qs, true, true)
	var x0: Transform3D = xfs[0]
	var e0: Vector3 = eu[0]
	var f0 := float(keys[0]["f"])
	var nm := FbxExport._esc(name)
	var objs := PackedStringArray()
	var conns := PackedStringArray()
	objs.append(FbxExport._model_block(cam, name, "Camera", x0))
	objs.append("\tNodeAttribute: %d, \"NodeAttribute::%s\", \"Camera\" {\n\t\tProperties70:  {\n\t\t\tP: \"FocalLength\", \"Number\", \"\", \"A\",%s\n\t\t\tP: \"FieldOfView\", \"FieldOfView\", \"\", \"A\",%s\n\t\t\tP: \"FieldOfViewX\", \"FieldOfView\", \"\", \"A\",%s\n\t\t\tP: \"FieldOfViewY\", \"FieldOfView\", \"\", \"A\",%s\n\t\t\tP: \"FilmWidth\", \"double\", \"Number\", \"\",1.417323\n\t\t\tP: \"AspectWidth\", \"double\", \"Number\", \"\",1920\n\t\t\tP: \"AspectHeight\", \"double\", \"Number\", \"\",1080\n\t\t\tP: \"ApertureMode\", \"enum\", \"\", \"\",1\n\t\t}\n\t\tTypeFlags: \"Camera\"\n\t\tGeometryVersion: 124\n\t}" % [
		attr, nm, FbxExport._f(f0), FbxExport._f(ShotCam.fov_h(f0)), FbxExport._f(ShotCam.fov_h(f0)), FbxExport._f(ShotCam.fov_v(f0))])
	conns.append("\tC: \"OO\", %d, 0" % cam)
	conns.append("\tC: \"OO\", %d, %d" % [attr, cam])
	var nid := ID0 + 10
	var ncurves := 0
	var nodes := 0
	var chans := [["T", "Lcl Translation", cam], ["R", "Lcl Rotation", cam]]
	for ch in chans:
		nodes += 1
		nid += 1
		var cn := nid
		var v0: Vector3 = x0.origin * 100.0 if ch[0] == "T" else e0
		objs.append("\tAnimationCurveNode: %d, \"AnimCurveNode::%s\", \"\" {\n\t\tProperties70:  {\n\t\t\tP: \"d|X\", \"Number\", \"\", \"A\",%s\n\t\t\tP: \"d|Y\", \"Number\", \"\", \"A\",%s\n\t\t\tP: \"d|Z\", \"Number\", \"\", \"A\",%s\n\t\t}\n\t}" % [cn, ch[0], FbxExport._f(v0.x), FbxExport._f(v0.y), FbxExport._f(v0.z)])
		conns.append("\tC: \"OO\", %d, %d" % [cn, layer_id])
		conns.append("\tC: \"OP\", %d, %d, \"%s\"" % [cn, cam, ch[1]])
		for ax in 3:
			var vals := PackedStringArray()
			for i in keys.size():
				var v: Vector3 = (xfs[i] as Transform3D).origin * 100.0 if ch[0] == "T" else eu[i]
				vals.append(FbxExport._f(v[ax]))
			nid += 1
			objs.append("\tAnimationCurve: %d, \"AnimCurve::\", \"\" {\n%s\n\t}" % [nid, _curve(times, vals)])
			conns.append("\tC: \"OP\", %d, %d, \"d|%s\"" % [nid, cn, ["X", "Y", "Z"][ax]])
			ncurves += 1
	nodes += 1
	nid += 1
	var fn := nid
	objs.append("\tAnimationCurveNode: %d, \"AnimCurveNode::FocalLength\", \"\" {\n\t\tProperties70:  {\n\t\t\tP: \"d|FocalLength\", \"Number\", \"\", \"A\",%s\n\t\t}\n\t}" % [fn, FbxExport._f(f0)])
	conns.append("\tC: \"OO\", %d, %d" % [fn, layer_id])
	conns.append("\tC: \"OP\", %d, %d, \"FocalLength\"" % [fn, attr])
	var fv := PackedStringArray()
	for k in keys:
		fv.append(FbxExport._f(float(k["f"])))
	nid += 1
	objs.append("\tAnimationCurve: %d, \"AnimCurve::\", \"\" {\n%s\n\t}" % [nid, _curve(times, fv)])
	conns.append("\tC: \"OP\", %d, %d, \"d|FocalLength\"" % [nid, fn])
	ncurves += 1
	var out := text
	for kv in [["Model", 1], ["NodeAttribute", 1], ["AnimationCurveNode", nodes], ["AnimationCurve", ncurves]]:
		out = _bump(out, kv[0], kv[1])
	var oi := out.find("\n}\nConnections:  {\n")
	out = out.substr(0, oi) + "\n" + "\n".join(objs) + out.substr(oi)
	var ci := out.rfind("\n}\n")
	out = out.substr(0, ci) + "\n" + "\n".join(conns) + out.substr(ci)
	return out
