## custom_rig.gd - OWN RIGS (ROADMAP_400 track J, lane L69). A non-human skeleton (quadruped, creature, tail, wings, prop) read from
## glTF and kept AS ITSELF: not mapped onto Manny. Pure data + functions, nothing here touches Body or Scene.
## A rig is a Dictionary
##   {"ok", "why", "names": [String], "parent": [int, -1 = root], "rest": [Transform3D local], "pose": {bone: Quaternion},
##    "keys": {frame(int): {bone: Quaternion}}, "fps", "core_matched", "human", "clip"}
## "pose" and the keys are DELTAS from the rest rotation, in the bone's own frame: the local rotation is rest.basis * Basis(delta).
## Positions and scales are the rest ones (FK only). Body-truth features (limits, contacts, body retarget, precheck) are for human
## rigs: run_human_only / human_tool answer "not a human rig" for any other rig instead of running them.
class_name CustomRig
extends RefCounted

const HUMAN_MIN := 16   # of the first 22 Body.ORDER joints found by name: a human rig
const NOT_HUMAN := "not a human rig: this skeleton is its own rig (%d of the 22 body joints found by name), so the body tools (joint limits, contacts, body retarget, rig pre-check) stay off for it"


static func _fail(why: String) -> Dictionary:
	return {"ok": false, "why": why, "names": [], "parent": [], "rest": [], "pose": {}, "keys": {}, "fps": 30.0, "core_matched": 0, "human": false}


static func _core_matched(names: Array) -> int:
	var low := names.map(func(n): return String(n).to_lower())
	var c := 0
	for j in 22:
		if low.has(String(Body.ORDER[j]).to_lower()):
			c += 1
	return c


static func is_human(rig: Dictionary) -> bool:
	return bool(rig.get("ok", false)) and int(rig.get("core_matched", 0)) >= HUMAN_MIN


static func capabilities(rig: Dictionary) -> String:
	if is_human(rig):
		return "Human rig: all body tools are on."
	return "Own rig (%d bones, not a human skeleton): per-bone FK posing, keys, glTF export and bone edit are on; the human-only tools are off (joint limits, ground contacts, body retarget, rig pre-check, mocap fit)." % (rig.get("names", []) as Array).size()


## a glTF / GLB file -> a rig. The largest skeleton is taken; its first (longest) animation becomes keys.
static func load_glb(path: String, fps := 30.0) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail("%s does not exist" % path.get_file())
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_file(path, st)
	if err != OK:
		return _fail("%s could not be read (%s)" % [path.get_file(), error_string(err)])
	var root := doc.generate_scene(st)
	if root == null:
		return _fail("%s has nothing in it" % path.get_file())
	var r := from_node(root, fps)
	root.free()
	return r


static func from_node(root: Node, fps := 30.0) -> Dictionary:
	var sks := root.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return _fail("it has no skeleton")
	var sk: Skeleton3D = sks[0]
	for s in sks:
		if (s as Skeleton3D).get_bone_count() > sk.get_bone_count():
			sk = s
	var names := []
	var parent := []
	var rest := []
	for i in sk.get_bone_count():
		names.append(sk.get_bone_name(i))
		parent.append(sk.get_bone_parent(i))
		rest.append(sk.get_bone_rest(i))
	var rig := {"ok": true, "why": "", "names": names, "parent": parent, "rest": rest, "pose": {}, "keys": {}, "fps": fps,
		"core_matched": _core_matched(names), "clip": ""}
	rig["human"] = is_human(rig)
	# the longest animation that turns this skeleton's bones
	var best: Animation = null
	var best_name := ""
	for ap in root.find_children("*", "AnimationPlayer", true, false):
		for an in (ap as AnimationPlayer).get_animation_list():
			var a: Animation = (ap as AnimationPlayer).get_animation(an)
			if best == null or a.length > best.length:
				best = a
				best_name = an
	if best != null:
		var tr_of := {}
		var times := {}
		for t in best.get_track_count():
			if best.track_get_type(t) != Animation.TYPE_ROTATION_3D:
				continue
			var bone := String(best.track_get_path(t).get_concatenated_subnames())
			if sk.find_bone(bone) < 0:
				continue
			tr_of[bone] = t
			for k in best.track_get_key_count(t):
				times[int(round(best.track_get_key_time(t, k) * fps))] = true
		var frames := times.keys()
		frames.sort()
		for fr in frames:
			var row := {}
			for bone in tr_of:
				var q: Quaternion = best.rotation_track_interpolate(tr_of[bone], fr / fps)
				var rq: Quaternion = (rest[names.find(bone)] as Transform3D).basis.get_rotation_quaternion()
				row[bone] = (rq.inverse() * q).normalized()
			rig["keys"][fr] = row
		rig["clip"] = best_name
		if not frames.is_empty():
			rig["pose"] = (rig["keys"][frames[0]] as Dictionary).duplicate()
	return rig


## ---- pose
static func set_pose(rig: Dictionary, bone: String, delta: Quaternion) -> bool:
	if not (rig["names"] as Array).has(bone):
		return false
	rig["pose"][bone] = delta.normalized()
	return true


static func key(rig: Dictionary, frame: int) -> void:
	rig["keys"][frame] = (rig["pose"] as Dictionary).duplicate()


static func key_frames(rig: Dictionary) -> Array:
	var f: Array = (rig["keys"] as Dictionary).keys()
	f.sort()
	return f


static func has_key_rows(rig: Dictionary, bone: String) -> bool:
	if (rig["pose"] as Dictionary).has(bone):
		return true
	for f in rig["keys"]:
		if (rig["keys"][f] as Dictionary).has(bone):
			return true
	return false


## the pose (bone -> delta) at a frame: keys interpolated by slerp, held before the first and after the last
static func pose_at(rig: Dictionary, frame: float) -> Dictionary:
	var fr := key_frames(rig)
	var out := {}
	if fr.is_empty():
		return (rig["pose"] as Dictionary).duplicate()
	var bones := {}
	for f in fr:
		for b in rig["keys"][f]:
			bones[b] = true
	for b in bones:
		var prev := -1
		var next := -1
		for f in fr:
			if (rig["keys"][f] as Dictionary).has(b):
				if f <= frame:
					prev = f
				elif next < 0:
					next = f
		if prev < 0:
			prev = next
		if prev < 0:
			continue
		var qa: Quaternion = rig["keys"][prev][b]
		if next < 0 or next == prev:
			out[b] = qa
		else:
			out[b] = qa.slerp(rig["keys"][next][b], (frame - prev) / float(next - prev))
	return out


## every bone's world transform for a pose (bone -> delta; missing = rest)
static func globals(rig: Dictionary, pose: Dictionary) -> Array:
	var n := (rig["names"] as Array).size()
	var out := []
	out.resize(n)
	var done := PackedByteArray()
	done.resize(n)
	for i in n:
		_glob(rig, pose, i, out, done, 0)
	return out


static func _glob(rig: Dictionary, pose: Dictionary, i: int, out: Array, done: PackedByteArray, depth: int) -> Transform3D:
	if done[i] == 1:
		return out[i]
	var loc: Transform3D = rig["rest"][i]
	var nm: String = rig["names"][i]
	if pose.has(nm):
		loc = Transform3D(loc.basis * Basis(pose[nm] as Quaternion), loc.origin)
	var p: int = rig["parent"][i]
	var g := loc
	if p >= 0 and depth < 4096:
		g = _glob(rig, pose, p, out, done, depth + 1) * loc
	out[i] = g
	done[i] = 1
	return g


## ---- export: the rig + its keys -> a .glb (a skeleton, a one-triangle skin so exporters keep the bones, an animation)
static func export_glb(rig: Dictionary, path: String, fps := 30.0) -> Error:
	var names: Array = rig["names"]
	var order := _topo(rig)
	var root := Node3D.new()
	root.name = "rig"
	var sk := Skeleton3D.new()
	sk.name = "Skeleton3D"
	root.add_child(sk)
	var idx := {}
	for i in order:
		var b := sk.get_bone_count()
		sk.add_bone(names[i])
		idx[i] = b
		if rig["parent"][i] >= 0:
			sk.set_bone_parent(b, idx[rig["parent"][i]])
		var x: Transform3D = rig["rest"][i]
		sk.set_bone_rest(b, x)
		sk.set_bone_pose_position(b, x.origin)
		sk.set_bone_pose_rotation(b, x.basis.get_rotation_quaternion())
	var mi := MeshInstance3D.new()
	mi.name = "Skin"
	root.add_child(mi)
	var stt := SurfaceTool.new()
	stt.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in [Vector3(-0.01, 0, 0), Vector3(0.01, 0, 0), Vector3(0, 0.01, 0)]:
		stt.set_bones(PackedInt32Array([0, 0, 0, 0]))
		stt.set_weights(PackedFloat32Array([1, 0, 0, 0]))
		stt.add_vertex(p)
	mi.mesh = stt.commit()
	mi.skin = sk.create_skin_from_rest_transforms()
	mi.skeleton = mi.get_path_to(sk)
	var fr := key_frames(rig)
	if not fr.is_empty():
		var anim := Animation.new()
		anim.length = maxf(float(fr[fr.size() - 1]) / fps, 1.0 / fps)
		var bones := {}
		for f in fr:
			for b in rig["keys"][f]:
				bones[b] = true
		for b in bones:
			var bi: int = names.find(b)
			if bi < 0:
				continue
			var rq: Quaternion = (rig["rest"][bi] as Transform3D).basis.get_rotation_quaternion()
			var tr := anim.add_track(Animation.TYPE_ROTATION_3D)
			anim.track_set_path(tr, NodePath("Skeleton3D:%s" % b))
			for f in fr:
				var d: Quaternion = (rig["keys"][f] as Dictionary).get(b, Quaternion.IDENTITY)
				anim.rotation_track_insert_key(tr, float(f) / fps, rq * d)
		var ap := AnimationPlayer.new()
		ap.name = "AnimationPlayer"
		root.add_child(ap)
		var lib := AnimationLibrary.new()
		lib.add_animation("clip", anim)
		ap.add_animation_library("", lib)
	return GltfExport._write(root, path, true)


static func _topo(rig: Dictionary) -> Array:
	var n := (rig["names"] as Array).size()
	var out := []
	var seen := {}
	for i in n:
		var chain := []
		var c: int = i
		while c >= 0 and not seen.has(c) and chain.size() <= n:
			chain.append(c)
			c = rig["parent"][c]
		chain.reverse()
		for x in chain:
			seen[x] = true
			out.append(x)
	return out


## ---- the tools for human rigs only
static func human_tool(rig: Dictionary, tool: String) -> Dictionary:
	if not is_human(rig):
		return {"ok": false, "why": NOT_HUMAN % int(rig.get("core_matched", 0)), "tool": tool}
	if tool == "precheck":
		var src := {"names": rig["names"], "rest": globals(rig, {})}
		var mp := {}
		for j in Body.ORDER:
			var i: int = (rig["names"] as Array).find(j)
			if i >= 0:
				mp[j] = i
		return {"ok": true, "why": "", "result": RigPrecheck.check(src, {"map": mp})}
	return {"ok": true, "why": ""}


## run a body-only tool (a Callable taking the rig) only on a human rig; any other rig gets a clear answer, never an error
static func run_human_only(rig: Dictionary, tool: String, fn: Callable) -> Dictionary:
	var g := human_tool(rig, tool)
	if not g["ok"]:
		return g
	var r = fn.call(rig)
	return r if r is Dictionary else {"ok": true, "why": "", "result": r}


## ---- bone editing (each returns "" or the reason it was refused; a refusal changes nothing)
static func _err_name(rig: Dictionary, n: String) -> String:
	if n.strip_edges() == "" or n.contains(":") or n.contains("/"):
		return "\"%s\" is not a usable bone name" % n
	if (rig["names"] as Array).has(n):
		return "a bone called \"%s\" already exists" % n
	return ""


static func add_bone(rig: Dictionary, name: String, parent: String, local: Transform3D) -> String:
	var e := _err_name(rig, name)
	if e != "":
		return e
	var p := -1
	if parent != "":
		p = (rig["names"] as Array).find(parent)
		if p < 0:
			return "the parent \"%s\" is not a bone of this rig" % parent
	(rig["names"] as Array).append(name)
	(rig["parent"] as Array).append(p)
	(rig["rest"] as Array).append(local)
	return ""


static func _is_below(rig: Dictionary, i: int, anc: int) -> bool:
	var c: int = rig["parent"][i]
	var guard := 0
	while c >= 0 and guard < 100000:
		if c == anc:
			return true
		c = rig["parent"][c]
		guard += 1
	return false


## move a bone under another (or "" = a root); its world rest transform is kept
static func reparent(rig: Dictionary, bone: String, new_parent: String) -> String:
	var i: int = (rig["names"] as Array).find(bone)
	if i < 0:
		return "no bone called \"%s\"" % bone
	var p := -1
	if new_parent != "":
		p = (rig["names"] as Array).find(new_parent)
		if p < 0:
			return "the parent \"%s\" is not a bone of this rig" % new_parent
		if p == i or _is_below(rig, p, i):
			return "\"%s\" cannot go under \"%s\": that would make a loop" % [bone, new_parent]
	var g := globals(rig, {})
	var pw: Transform3D = g[p] if p >= 0 else Transform3D.IDENTITY
	rig["rest"][i] = pw.affine_inverse() * (g[i] as Transform3D)
	rig["parent"][i] = p
	return ""


## delete a bone; its children go to its parent with their world rest kept; its keys go with it
static func remove_bone(rig: Dictionary, bone: String) -> String:
	var i: int = (rig["names"] as Array).find(bone)
	if i < 0:
		return "no bone called \"%s\"" % bone
	var kids := []
	for c in (rig["names"] as Array).size():
		if rig["parent"][c] == i:
			kids.append(c)
	if rig["parent"][i] < 0 and kids.size() > 1:
		return "\"%s\" is the root of %d chains: move them first" % [bone, kids.size()]
	var g := globals(rig, {})
	var np: int = rig["parent"][i]
	var pw: Transform3D = g[np] if np >= 0 else Transform3D.IDENTITY
	for c in kids:
		rig["rest"][c] = pw.affine_inverse() * (g[c] as Transform3D)
		rig["parent"][c] = np
	(rig["names"] as Array).remove_at(i)
	(rig["rest"] as Array).remove_at(i)
	(rig["parent"] as Array).remove_at(i)
	for j in (rig["parent"] as Array).size():
		if rig["parent"][j] > i:
			rig["parent"][j] -= 1
	(rig["pose"] as Dictionary).erase(bone)
	for f in rig["keys"]:
		(rig["keys"][f] as Dictionary).erase(bone)
	return ""
