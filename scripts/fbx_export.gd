## FBX EXPORT (ROADMAP 78). A scene -> binary FBX 7.4 (.fbx; the ASCII text is a debug view): the mannequin's skeleton with UE5 bone names (the same names
## and the same rest pose as the .glb, GltfExport), one take named after the scene, and the animation on every frame of the
## glb's own keys: a rotation curve set (X, Y, Z in degrees, Euler XYZ) per animated bone, and the pelvis's position curves
## (centimetres). Godot has no FBX writer, so this writes the text itself; the tree and the keys come from GltfExport.build,
## so the file cannot drift from the .glb. Centimetres (UnitScaleFactor 1.0: an FBX unit is a centimetre, 100 would be a metre), Y up, the front to +Z as the glb.
## Not in the file: the weapons (they are animated nodes in the .glb only) and the props, the sound and the camera.
## Euler order is FBX's eEulerXYZ: R = Rz(c) * Ry(b) * Rx(a) for the three angles (X = a, Y = b, Z = c). The rotation
## curves are unrolled (RotClean, ROADMAP 64): each channel continuous frame to frame, no 360-degree steps or flips.
## Checked by tests/fbx_export_test.gd (a Python reader in tests/py/fbx_check.py) and, when Blender is installed, by
## tests/py/fbx_blender_check.py run in Blender 4.5 (docs/EXPORT.md).
class_name FbxExport
extends RefCounted

const KTIME := 46186158000.0   # FBX ticks per second
const CM := 100.0              # metres to centimetres: the numbers in the file (its UnitScaleFactor is 1.0, a centimetre)
## C23 unit presets (opt-in; the defaults are the old file, byte for byte): the numbers' unit and the up axis. write_preset sets them for one write
static var unit_mult := CM       # metres to the file's numbers
static var unit_factor := 1.0    # the header's UnitScaleFactor: centimetres per file unit
static var up_z := false         # true: Z up (UpAxis 2), the rig turned a quarter about X
const PRESETS := {
	"default": {"mult": 100.0, "factor": 1.0, "up_z": false, "words": "centimetres, Y up (the old file)"},
	"unity": {"mult": 1.0, "factor": 100.0, "up_z": false, "words": "metres (1 unit = 100 cm), Y up: Unity reads 1 m as 1 m"},
	"unreal": {"mult": 100.0, "factor": 1.0, "up_z": true, "words": "centimetres, Z up: Unreal reads 1 m as 100 units, standing up"},
	"blender": {"mult": 100.0, "factor": 1.0, "up_z": true, "words": "centimetres, Z up: Blender reads 1 m as 1 m"},
}


## the same as write() under a unit preset ("default" | "unity" | "unreal" | "blender"); the statics are put back after
static func write_preset(preset: String, S: Scene, B: Body, path: String, root_motion := false, xf := Transform3D.IDENTITY, root_name := "", ascii := false, camera_keys := []) -> Dictionary:
	if not PRESETS.has(preset):
		return {"err": ERR_INVALID_PARAMETER, "path": path, "text": ""}
	var p: Dictionary = PRESETS[preset]
	unit_mult = float(p["mult"])
	unit_factor = float(p["factor"])
	up_z = bool(p["up_z"])
	var x2 := xf
	if up_z:
		x2 = Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3.ZERO) * xf   # Y up -> Z up (the front +Z becomes -Y)
	var r := write(S, B, path, root_motion, x2, root_name if root_name != "" else (S.name if S.name != "" else "scene"), ascii, camera_keys)
	unit_mult = CM
	unit_factor = 1.0
	up_z = false
	r["preset"] = preset
	return r

## FBX's TimeMode enum for the frame rates it names (FbxTime::EMode); any other rate is eCustom with CustomFrameRate
const TIME_MODE := {120: 1, 60: 3, 50: 4, 48: 5, 30: 6, 24: 11, 96: 15, 72: 16}


## the scene as FBX at path (res:// / user:// or absolute), posed through the scene with B put back.
## root_motion as the engine presets (the pelvis's travel on the "root" bone). xf places the rig (a root Null, for
## several fighters); root_name names that Null (default: the scene). Returns {"err", "path", "bones" (PackedStringArray,
## the names in the file), "keys" (keys per curve), "curves" (animation curves written), "text"}.
## BINARY by default (Unreal, Unity, Maya and Blender 4.5 all read it; Blender refuses ASCII). ascii = true writes the
## ASCII text instead, a debug view of the same tree (tests/py/fbx_check.py reads it). The "format" key says which.
static func write(S: Scene, B: Body, path: String, root_motion := false, xf := Transform3D.IDENTITY, root_name := "", ascii := false, camera_keys := []) -> Dictionary:
	var keep := B.state()
	var an := S.name if S.name != "" else "scene"
	# the file is a pure function of the scene, the body and the options: the last one built is kept, so the same scene written
	# again (a second click, the gentle test's hostile starts) is the write only, not the pose of every frame again
	var ck := var_to_str([S.to_dict(B, true), keep, root_motion, xf, root_name, ascii, camera_keys, unit_mult, unit_factor, up_z])
	if ck == _last_key and not _last.is_empty():
		return _write_out(_last, path, ascii)
	var man := GltfExport.build(S, B, an, false, root_motion)
	var sk: Skeleton3D = man.find_children("*", "Skeleton3D", true, false)[0]
	var ap: AnimationPlayer = man.find_children("*", "AnimationPlayer", true, false)[0]
	var A: Animation = ap.get_animation(an)
	# the rig's space in the .glb: the mannequin node's transform times the skeleton's place under it
	var base: Transform3D = man.transform * _rel(sk, man)
	var out := text_of(sk, A, an, float(S.fps), base, xf, root_name if root_name != "" else an)
	man.free()
	if not camera_keys.is_empty():
		out["text"] = FbxCamera.inject(out["text"], camera_keys)   # C09: the shot camera, opt-in
		out["camera_keys"] = camera_keys.size()
	B.set_state(keep)
	_last_key = ck
	_last = out
	return _write_out(out, path, ascii)


static var _last_key := ""
static var _last: Dictionary = {}


static func _write_out(src: Dictionary, path: String, ascii: bool) -> Dictionary:
	var out := src.duplicate()
	var err := OK
	var abs := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	DirAccess.make_dir_recursive_absolute(abs.get_base_dir())
	var data: PackedByteArray = (out["text"] as String).to_utf8_buffer() if ascii else to_binary(out["text"])
	var f := FileAccess.open(abs, FileAccess.WRITE)
	if f == null:
		err = FileAccess.get_open_error()
	else:
		f.store_buffer(data)
		f.close()
	out["err"] = err
	out["path"] = path
	out["format"] = "ascii" if ascii else "binary"
	out["size"] = data.size()
	return out


## a node's transform relative to an ancestor (not including the ancestor's own)
static func _rel(n: Node3D, top: Node) -> Transform3D:
	var x := Transform3D.IDENTITY
	var c: Node = n
	while c != null and c != top:
		if c is Node3D:
			x = (c as Node3D).transform * x
		c = c.get_parent()
	return x


## the FBX text for a skeleton and its animation (pure: no file, no Body). base places the skeleton's root bones in the
## glb's space; xf places the whole rig (a root Null when xf is not the identity or root_name is given by the caller).
static func text_of(sk: Skeleton3D, A: Animation, an: String, fps: float, base: Transform3D, xf: Transform3D, root_name: String) -> Dictionary:
	var nb := sk.get_bone_count()
	var names := PackedStringArray()
	var idx_of := {}
	var par := []
	var rest := []
	for i in nb:
		var gn := sk.get_bone_name(i)
		idx_of[gn] = i
		names.append("head" if gn == "Head" else gn)   # the glb's rename (GltfExport._write)
		par.append(sk.get_bone_parent(i))
		rest.append(sk.get_bone_rest(i))
	# local rest per bone as the file has it (the root bones carry the glb's base), and the bind pose in the scene
	var local := []
	var memo := {}
	for i in nb:
		var lt: Transform3D = (base * rest[i]) if par[i] < 0 else rest[i]
		local.append(lt)
	# the root null: a placement (xf), written only when the rig is placed or named
	var has_null := xf != Transform3D.IDENTITY or root_name != ""
	var tracks := {}   # bone index -> {"rot": track, "pos": track}
	for tr in A.get_track_count():
		var ty := A.track_get_type(tr)
		if ty != Animation.TYPE_ROTATION_3D and ty != Animation.TYPE_POSITION_3D:
			continue
		var np := A.track_get_path(tr)
		if np.get_subname_count() == 0:
			continue   # the weapon nodes: whole-node tracks, not a bone's
		var bn := String(np.get_subname(0))
		if not idx_of.has(bn):
			continue
		var i: int = idx_of[bn]
		if not tracks.has(i):
			tracks[i] = {}
		tracks[i]["rot" if ty == Animation.TYPE_ROTATION_3D else "pos"] = tr
	var L := A.length

	# ---- Objects -------------------------------------------------------------------------------------------------------
	var nid := 1000000000
	var model_id := []
	for i in nb:
		nid += 1
		model_id.append(nid)
	nid += 1
	var null_id := nid if has_null else 0
	var attr_id := []
	for i in nb:
		nid += 1
		attr_id.append(nid)
	nid += 1
	var pose_id := nid
	nid += 1
	var stack_id := nid
	nid += 1
	var layer_id := nid
	var objs := PackedStringArray()
	var conns := PackedStringArray()
	var bind := {}   # bone index -> bind matrix (cm, FBX row-vector form)
	var gl := []
	for i in nb:
		gl.append(_glob(i, par, local, memo))
	var mod := PackedStringArray()
	if has_null:
		mod.append(_model_block(null_id, root_name, "Null", xf))
	for i in nb:
		mod.append(_model_block(model_id[i], names[i], "LimbNode", local[i]))
	objs.append_array(mod)
	var attrs := PackedStringArray()
	for i in nb:
		attrs.append("\tNodeAttribute: %d, \"NodeAttribute::%s\", \"LimbNode\" {\n\t\tTypeFlags: \"Skeleton\"\n\t}" % [attr_id[i], names[i]])
	objs.append_array(attrs)
	# bind pose (every bone's global matrix at rest, in cm)
	var pn := PackedStringArray()
	for i in nb:
		pn.append("\t\tPoseNode:  {\n\t\t\tNode: %d\n\t\t\tMatrix: *16 {\n\t\t\t\ta: %s\n\t\t\t}\n\t\t}" % [model_id[i], _mat(xf * gl[i])])
	objs.append("\tPose: %d, \"Pose::BIND_POSES\", \"BindPose\" {\n\t\tType: \"BindPose\"\n\t\tVersion: 100\n\t\tNbPoseNodes: %d\n%s\n\t}" % [pose_id, nb, "\n".join(pn)])
	# the take: one stack, one layer, a curve node per animated channel, three curves each
	var ncurve_nodes := 0
	var curve_objs := PackedStringArray()
	var ncurves := 0
	var keys_per := 0
	var bone_order := tracks.keys()
	bone_order.sort()
	var ticks_L := int(round(L * KTIME))
	objs.append("\tAnimationStack: %d, \"AnimStack::%s\", \"\" {\n\t\tProperties70:  {\n\t\t\tP: \"LocalStart\", \"KTime\", \"Time\", \"\",0\n\t\t\tP: \"LocalStop\", \"KTime\", \"Time\", \"\",%d\n\t\t\tP: \"ReferenceStart\", \"KTime\", \"Time\", \"\",0\n\t\t\tP: \"ReferenceStop\", \"KTime\", \"Time\", \"\",%d\n\t\t}\n\t}" % [stack_id, _esc(an), ticks_L, ticks_L])
	objs.append("\tAnimationLayer: %d, \"AnimLayer::BaseLayer\", \"\" {\n\t}" % layer_id)
	conns.append("\tC: \"OO\", %d, %d" % [layer_id, stack_id])
	for i in bone_order:
		var tk: Dictionary = tracks[i]
		var bone_id: int = model_id[i]
		if tk.has("rot"):
			ncurve_nodes += 1
			nid += 1
			var cn := nid
			var r0 := _euler_deg(local[i] as Transform3D)
			objs.append("\tAnimationCurveNode: %d, \"AnimCurveNode::R\", \"\" {\n\t\tProperties70:  {\n\t\t\tP: \"d|X\", \"Number\", \"\", \"A\",%s\n\t\t\tP: \"d|Y\", \"Number\", \"\", \"A\",%s\n\t\t\tP: \"d|Z\", \"Number\", \"\", \"A\",%s\n\t\t}\n\t}" % [cn, _f(r0.x), _f(r0.y), _f(r0.z)])
			conns.append("\tC: \"OO\", %d, %d" % [cn, layer_id])
			conns.append("\tC: \"OP\", %d, %d, \"Lcl Rotation\"" % [cn, bone_id])
			var e := _curves_for(tk["rot"], A, true)
			for ax in 3:
				nid += 1
				var cv := nid
				objs.append("\tAnimationCurve: %d, \"AnimCurve::\", \"\" {\n%s\n\t}" % [cv, e[ax]["text"]])
				conns.append("\tC: \"OP\", %d, %d, \"d|%s\"" % [cv, cn, ["X", "Y", "Z"][ax]])
				ncurves += 1
			keys_per = e[0]["n"]
		if tk.has("pos"):
			ncurve_nodes += 1
			nid += 1
			var tn := nid
			var p0 := (local[i] as Transform3D).origin * unit_mult
			objs.append("\tAnimationCurveNode: %d, \"AnimCurveNode::T\", \"\" {\n\t\tProperties70:  {\n\t\t\tP: \"d|X\", \"Number\", \"\", \"A\",%s\n\t\t\tP: \"d|Y\", \"Number\", \"\", \"A\",%s\n\t\t\tP: \"d|Z\", \"Number\", \"\", \"A\",%s\n\t\t}\n\t}" % [tn, _f(p0.x), _f(p0.y), _f(p0.z)])
			conns.append("\tC: \"OO\", %d, %d" % [tn, layer_id])
			conns.append("\tC: \"OP\", %d, %d, \"Lcl Translation\"" % [tn, bone_id])
			var e2 := _curves_for(tk["pos"], A, false)
			for ax in 3:
				nid += 1
				var cv2 := nid
				objs.append("\tAnimationCurve: %d, \"AnimCurve::\", \"\" {\n%s\n\t}" % [cv2, e2[ax]["text"]])
				conns.append("\tC: \"OP\", %d, %d, \"d|%s\"" % [cv2, tn, ["X", "Y", "Z"][ax]])
				ncurves += 1
			keys_per = maxi(keys_per, e2[0]["n"])
	# the model hierarchy: a root bone under the null (or 0), a bone under its parent
	if has_null:
		conns.append("\tC: \"OO\", %d, 0" % null_id)
	for i in nb:
		conns.append("\tC: \"OO\", %d, %d" % [attr_id[i], model_id[i]])
		if par[i] < 0:
			conns.append("\tC: \"OO\", %d, %d" % [model_id[i], null_id])
		else:
			conns.append("\tC: \"OO\", %d, %d" % [model_id[i], model_id[par[i]]])

	var fps_i := int(round(fps))
	var mode: int = TIME_MODE.get(fps_i, 14)
	var head := _header(fps, mode, ticks_L)
	var defs := "Definitions:  {\n\tVersion: 100\n\tCount: 8\n\tObjectType: \"GlobalSettings\" {\n\t\tCount: 1\n\t}\n\tObjectType: \"AnimationStack\" {\n\t\tCount: 1\n\t}\n\tObjectType: \"AnimationLayer\" {\n\t\tCount: 1\n\t}\n\tObjectType: \"AnimationCurveNode\" {\n\t\tCount: %d\n\t}\n\tObjectType: \"AnimationCurve\" {\n\t\tCount: %d\n\t}\n\tObjectType: \"Model\" {\n\t\tCount: %d\n\t}\n\tObjectType: \"NodeAttribute\" {\n\t\tCount: %d\n\t}\n\tObjectType: \"Pose\" {\n\t\tCount: 1\n\t}\n}" % [
		ncurve_nodes, ncurves, nb + (1 if has_null else 0), nb]
	var text := head + defs + "\nObjects:  {\n" + "\n".join(objs) + "\n}\nConnections:  {\n" + "\n".join(conns) + "\n}\n"
	return {"text": text, "bones": names, "keys": keys_per, "curves": ncurves, "n_bones": nb,
		"animated": tracks.size(), "length": L, "ticks": ticks_L}


## one Model block (a LimbNode bone or the root Null): its rest local transform in cm
static func _model_block(id: int, nm: String, kind: String, t: Transform3D) -> String:
	var tr := t.origin * unit_mult
	var e := _euler_deg(t)
	var s := t.basis.get_scale()
	return "\tModel: %d, \"Model::%s\", \"%s\" {\n\t\tVersion: 232\n\t\tProperties70:  {\n\t\t\tP: \"RotationOrder\", \"enum\", \"\", \"\",0\n\t\t\tP: \"Lcl Translation\", \"Lcl Translation\", \"\", \"A\",%s,%s,%s\n\t\t\tP: \"Lcl Rotation\", \"Lcl Rotation\", \"\", \"A\",%s,%s,%s\n\t\t\tP: \"Lcl Scaling\", \"Lcl Scaling\", \"\", \"A\",%s,%s,%s\n\t\t}\n\t\tShading: Y\n\t\tCulling: \"CullingOff\"\n\t}" % [id, _esc(nm), kind, _f(tr.x), _f(tr.y), _f(tr.z), _f(e.x), _f(e.y), _f(e.z), _f(s.x), _f(s.y), _f(s.z)]


## the curve values of one channel: n keys, KeyTime in ticks, the values (degrees for a rotation; cm for a position).
## Returns [{"text": the curve's properties, "n": keys}, ... one per axis]
static func _curves_for(tr: int, A: Animation, rot: bool) -> Array:
	var n := A.track_get_key_count(tr)
	var times := PackedStringArray()
	var vals := [PackedStringArray(), PackedStringArray(), PackedStringArray()]
	# a rotation track: the keys' Euler XYZ unrolled per channel (RotClean: nearest the previous key, no 360 jumps,
	# no flips between the two solutions at a gimbal), so an engine's interpolation takes the short way round
	var eu := []
	if rot:
		var qs := []
		for k in n:
			qs.append(A.track_get_key_value(tr, k) as Quaternion)
		eu = RotClean.euler_track(qs, true, true)
	for k in n:
		times.append(str(int(round(A.track_get_key_time(tr, k) * KTIME))))
		var v = A.track_get_key_value(tr, k)
		var xyz: Vector3
		if rot:
			xyz = eu[k]
		else:
			xyz = (v as Vector3) * unit_mult
		vals[0].append(_f(xyz.x))
		vals[1].append(_f(xyz.y))
		vals[2].append(_f(xyz.z))
	var out := []
	for ax in 3:
		var txt := "\t\tDefault: 0\n\t\tKeyVer: 4008\n\t\tKeyTime: *%d {\n\t\t\ta: %s\n\t\t}\n\t\tKeyValueFloat: *%d {\n\t\t\ta: %s\n\t\t}\n\t\tKeyAttrFlags: *1 {\n\t\t\ta: 24836\n\t\t}\n\t\tKeyAttrDataFloat: *4 {\n\t\t\ta: 0,0,0,0\n\t\t}\n\t\tKeyAttrRefCount: *1 {\n\t\t\ta: %d\n\t\t}" % [n, ",".join(times), n, ",".join(vals[ax]), n]
		out.append({"text": txt, "n": n})
	return out


## the global (cm-free, metres) transform of bone i: its parent's global times its local; a root bone sits under the placement xf
static func _glob(i: int, par: Array, local: Array, memo: Dictionary) -> Transform3D:
	if memo.has(i):
		return memo[i]
	var p: int = par[i]
	var g: Transform3D = (local[i] as Transform3D) if p < 0 else (_glob(p, par, local, memo) * (local[i] as Transform3D))
	memo[i] = g
	return g


## FBX's matrix text for a transform (row-vector form, translation in the last row, cm): the 16 values of the
## bind pose. xf_global is already in the file's space when a root null holds the placement.
static func _mat(t: Transform3D) -> String:
	var o := t.origin * unit_mult
	var v := PackedStringArray()
	for c in [t.basis.x, t.basis.y, t.basis.z]:
		v.append(_f(c.x))
		v.append(_f(c.y))
		v.append(_f(c.z))
		v.append("0.000000000")
	v.append(_f(o.x))
	v.append(_f(o.y))
	v.append(_f(o.z))
	v.append("1.000000000")
	return ",".join(v)


## Euler XYZ in degrees (X = a, Y = b, Z = c) from a transform's rotation: R = Rz(c) Ry(b) Rx(a), column vectors
static func _euler_deg(t: Transform3D) -> Vector3:
	var b: Basis = t.basis.orthonormalized()
	var bb := asin(clampf(-b.x.z, -1.0, 1.0))
	var aa := atan2(b.y.z, b.z.z)
	var cc := atan2(b.x.y, b.x.x)
	return Vector3(rad_to_deg(aa), rad_to_deg(bb), rad_to_deg(cc))


static func _header(fps: float, mode: int, ticks_L: int) -> String:
	var d := Time.get_datetime_dict_from_system()
	var s := "; FBX 7.4.0 project file\n; Written by Kine (Poser): ASCII FBX 7.4, centimetres, Y up, UE5 bone names.\n; ----------------------------------------------------\n"
	s += "FBXHeaderExtension:  {\n\tFBXHeaderVersion: 1003\n\tFBXVersion: 7400\n\tCreationTimeStamp:  {\n\t\tVersion: 1000\n\t\tYear: %d\n\t\tMonth: %d\n\t\tDay: %d\n\t\tHour: %d\n\t\tMinute: %d\n\t\tSecond: %d\n\t\tMillisecond: 0\n\t}\n\tCreator: \"Kine FBX writer (ROADMAP 78)\"\n}\n" % [d["year"], d["month"], d["day"], d["hour"], d["minute"], d["second"]]
	s += "GlobalSettings:  {\n\tVersion: 1000\n\tProperties70:  {\n"
	s += "\t\tP: \"UpAxis\", \"int\", \"Integer\", \"\",%d\n\t\tP: \"UpAxisSign\", \"int\", \"Integer\", \"\",1\n" % (2 if up_z else 1)
	s += "\t\tP: \"FrontAxis\", \"int\", \"Integer\", \"\",%d\n\t\tP: \"FrontAxisSign\", \"int\", \"Integer\", \"\",%d\n" % [1 if up_z else 2, -1 if up_z else 1]
	s += "\t\tP: \"CoordAxis\", \"int\", \"Integer\", \"\",0\n\t\tP: \"CoordAxisSign\", \"int\", \"Integer\", \"\",1\n"
	s += "\t\tP: \"UnitScaleFactor\", \"double\", \"Number\", \"\",%s\n\t\tP: \"OriginalUnitScaleFactor\", \"double\", \"Number\", \"\",%s\n" % [_f(unit_factor), _f(unit_factor)]
	s += "\t\tP: \"TimeMode\", \"enum\", \"\", \"\",%d\n\t\tP: \"TimeSpanStart\", \"KTime\", \"Time\", \"\",0\n\t\tP: \"TimeSpanStop\", \"KTime\", \"Time\", \"\",%d\n" % [mode, ticks_L]
	s += "\t\tP: \"CustomFrameRate\", \"double\", \"Number\", \"\",%s\n\t}\n}\n" % _f(fps)
	s += "Documents:  {\n\tCount: 1\n\tDocument: 1000000000, \"\", \"Scene\" {\n\t\tProperties70:  {\n\t\t\tP: \"ActiveAnimStackName\", \"KString\", \"\", \"\", \"\"\n\t\t}\n\t\tRootNode: 0\n\t}\n}\n"
	s += "References:  {\n}\n"
	return s


static func _f(v: float) -> String:
	return "%.9f" % v


static func _esc(s: String) -> String:
	return s.replace("\"", "'")


## ---- BINARY FBX 7.4 (the default output) -------------------------------------------------------------------------------
## The ASCII text above, re-encoded node by node: the same tree, so the binary cannot differ from the debug ASCII.
## Value types as FBX writes them: ids and KTime int64 ('L'), other integers int32 ('I'), decimals float64 ('D'),
## KeyTime int64 arrays, KeyValueFloat float32, KeyAttr int32 / float32, matrices float64, T / Y bool. An object's name
## "Class::name" is written "name" + NUL + SOH + "Class" (Blender's reader needs that). Little-endian, uncompressed.
const ID_NODES := ["Model", "NodeAttribute", "AnimationCurveNode", "AnimationCurve", "Pose", "AnimationStack", "AnimationLayer", "Document"]
const ARRAY_CODE := {"KeyTime": "l", "KeyValueFloat": "f", "KeyAttrFlags": "i", "KeyAttrDataFloat": "f", "KeyAttrRefCount": "i", "Matrix": "d"}


## the FBX text as binary FBX 7.4 bytes
static func to_binary(text: String) -> PackedByteArray:
	var top: Array = _block(_tokens(text), 0)[0]
	var out := "Kaydara FBX Binary  ".to_ascii_buffer()
	out.append(0)
	out.append(0x1a)
	out.append(0)
	out.append_array(_u32(7400))
	for node in top:
		out.append_array(_rec(node, out.size()))
	out.append_array(_null13())
	for k in 16:
		out.append(0)
	return out


## the ASCII text as tokens: [kind, text] with kind "S" (quoted), "P" (punctuation), "W" (a word or number)
static func _tokens(src: String) -> Array:
	var b := src.to_utf8_buffer()
	var out := []
	var i := 0
	var n := b.size()
	while i < n:
		var c := b[i]
		if c == 32 or c == 9 or c == 13 or c == 10:
			i += 1
		elif c == 59:   # ; a comment to the end of the line
			while i < n and b[i] != 10:
				i += 1
		elif c == 34:   # "..."
			var j := i + 1
			while b[j] != 34:
				j += 1
			out.append(["S", b.slice(i + 1, j).get_string_from_utf8()])
			i = j + 1
		elif c == 123 or c == 125 or c == 58 or c == 44 or c == 42:   # { } : , *
			out.append(["P", char(c)])
			i += 1
		else:
			var j := i
			while j < n and not (b[j] in [32, 9, 13, 10, 123, 125, 58, 44, 42, 34]):
				j += 1
			out.append(["W", b.slice(i, j).get_string_from_utf8()])
			i = j
	return out


## the nodes of a block from token i, up to its closing brace: [nodes, index after it]. A node is
## {name, values (each [kind, text], or {"arr": PackedStringArray} for a '*N { a: ... }' array), children}
static func _block(toks: Array, i: int) -> Array:
	var nodes := []
	while i < toks.size():
		if toks[i] == ["P", "}"]:
			return [nodes, i + 1]
		var name: String = toks[i][1]
		i += 2   # the name and its colon
		var values := []
		var children := []
		if toks[i] == ["P", "*"]:
			var r := _block(toks, i + 3)   # '*', the count, then the block
			i = r[1]
			var arr := PackedStringArray()
			for cn in r[0]:
				for v in cn["values"]:
					if v is Dictionary:
						arr.append_array((v as Dictionary)["arr"])
					else:
						arr.append((v as Array)[1])
			values.append({"arr": arr})
		else:
			while true:
				var k: String = toks[i][0]
				var is_node: bool = k == "W" and i + 1 < toks.size() and toks[i + 1] == ["P", ":"]
				if k == "P" or is_node:
					break
				values.append([k, toks[i][1]])
				i += 1
				if toks[i] == ["P", ","]:
					i += 1
					continue
				break
			if i < toks.size() and toks[i] == ["P", "{"]:
				var r2 := _block(toks, i + 1)
				children = r2[0]
				i = r2[1]
		nodes.append({"name": name, "values": values, "children": children})
	return [nodes, i]


## one node record (FBX 7.4: 32-bit offsets), starting at byte start of the file
static func _rec(node: Dictionary, start: int) -> PackedByteArray:
	var name_b: PackedByteArray = String(node["name"]).to_utf8_buffer()
	var props := _props(node)
	var header := 13 + name_b.size()
	var cur := start + header + props.size()
	var kids := PackedByteArray()
	for ch in node["children"]:
		var r := _rec(ch, cur)
		kids.append_array(r)
		cur += r.size()
	if not (node["children"] as Array).is_empty():
		kids.append_array(_null13())
	var end := start + header + props.size() + kids.size()
	var out := _u32(end)
	out.append_array(_u32((node["values"] as Array).size()))
	out.append_array(_u32(props.size()))
	out.append(name_b.size())
	out.append_array(name_b)
	out.append_array(props)
	out.append_array(kids)
	return out


static func _props(node: Dictionary) -> PackedByteArray:
	var name: String = node["name"]
	var vals: Array = node["values"]
	var out := PackedByteArray()
	var is_ktime: bool = name == "P" and vals.size() > 1 and vals[1] is Array and (vals[1] as Array)[1] == "KTime"
	for idx in vals.size():
		var v = vals[idx]
		if v is Dictionary:
			out.append_array(_enc_array(ARRAY_CODE.get(name, "d"), (v as Dictionary)["arr"]))
			continue
		var force_long: bool = (ID_NODES.has(name) and idx == 0) or (name == "C" and (idx == 1 or idx == 2)) \
			or name in ["PoseNode", "Node", "RootNode"] or (is_ktime and idx >= 4)
		out.append_array(_enc_scalar((v as Array)[0], (v as Array)[1], force_long, name == "Default"))
	return out


static func _enc_scalar(kind: String, s: String, force_long: bool, as_double: bool) -> PackedByteArray:
	var out := PackedByteArray()
	if kind == "S":
		var bytes := PackedByteArray()
		if s.contains("::"):   # "Class::name" -> "name" NUL SOH "Class"
			var at := s.find("::")
			bytes = s.substr(at + 2).to_utf8_buffer()
			bytes.append(0)
			bytes.append(1)
			bytes.append_array(s.substr(0, at).to_utf8_buffer())
		else:
			bytes = s.to_utf8_buffer()
		out.append_array("S".to_ascii_buffer())
		out.append_array(_u32(bytes.size()))
		out.append_array(bytes)
		return out
	if s == "T" or s == "Y":
		out.append_array("C".to_ascii_buffer())
		out.append(1)
		return out
	if s.is_valid_int():
		var v := s.to_int()
		if as_double:
			return _cat(_tag("D"), _f64(float(v)))
		if force_long or absi(v) >= 2147483648:
			return _cat(_tag("L"), _s64(v))
		return _cat(_tag("I"), _s32(v))
	return _cat(_tag("D"), _f64(s.to_float()))


static func _enc_array(code: String, arr: PackedStringArray) -> PackedByteArray:
	var n := arr.size()
	var data := PackedByteArray()
	match code:
		"l":
			data.resize(8 * n)
			for k in n:
				data.encode_s64(8 * k, arr[k].to_int())
		"f":
			data.resize(4 * n)
			for k in n:
				data.encode_float(4 * k, arr[k].to_float())
		"i":
			data.resize(4 * n)
			for k in n:
				data.encode_s32(4 * k, arr[k].to_int())
		_:
			data.resize(8 * n)
			for k in n:
				data.encode_double(8 * k, arr[k].to_float())
	var out := _tag(code)
	out.append_array(_u32(n))
	out.append_array(_u32(0))   # encoding: raw
	out.append_array(_u32(data.size()))
	out.append_array(data)
	return out


static func _cat(a: PackedByteArray, b: PackedByteArray) -> PackedByteArray:
	var r := a.duplicate()
	r.append_array(b)
	return r


static func _tag(c: String) -> PackedByteArray:
	return c.to_ascii_buffer()


static func _u32(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_u32(0, v)
	return b


static func _s32(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_s32(0, v)
	return b


static func _s64(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(8)
	b.encode_s64(0, v)
	return b


static func _f64(v: float) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(8)
	b.encode_double(0, v)
	return b


static func _null13() -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(13)
	return b
