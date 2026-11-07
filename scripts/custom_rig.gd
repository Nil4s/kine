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
	rig["pose"][bone] = clamp_delta(rig, bone, delta.normalized())
	return true


static func key(rig: Dictionary, frame: int) -> void:
	rig["keys"][frame] = (rig["pose"] as Dictionary).duplicate()
	if not rig.has("pkeys"):
		rig["pkeys"] = {}
	rig["pkeys"][frame] = rig.get("pos", Vector3.ZERO)   # the root position goes in every key


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
			out[b] = clamp_delta(rig, b, qa)
		else:
			out[b] = clamp_delta(rig, b, qa.slerp(rig["keys"][next][b], (frame - prev) / float(next - prev)))
	return out


## the root bone position offset at a frame: the position keys interpolated linearly, held outside them (no position keys: the current one)
static func pos_at(rig: Dictionary, frame: float) -> Vector3:
	var pk: Dictionary = rig.get("pkeys", {})
	if pk.is_empty():
		return rig.get("pos", Vector3.ZERO)
	var fr: Array = pk.keys()
	fr.sort()
	var prev: int = fr[0]
	var next := -1
	for f in fr:
		if f <= frame:
			prev = f
		elif next < 0:
			next = f
	if frame < fr[0] or next < 0:
		return pk[prev]
	return (pk[prev] as Vector3).lerp(pk[next], (frame - prev) / float(next - prev))


## ---- joint limits: per bone, degrees, on the euler angles of the bone delta from rest (Basis.get_euler, YXZ: x = pitch within +-90)
static func set_limit(rig: Dictionary, bone: String, mn: Vector3, mx: Vector3) -> String:
	if not (rig["names"] as Array).has(bone):
		return "no bone called \"%s\"" % bone
	for i in 3:
		if mn[i] > mx[i]:
			return "the minimum is above the maximum on axis %s" % ["X", "Y", "Z"][i]
	mn.x = clampf(mn.x, -89.9, 89.9)
	mx.x = clampf(mx.x, -89.9, 89.9)
	if not rig.has("limits"):
		rig["limits"] = {}
	rig["limits"][bone] = {"min": mn, "max": mx}
	if (rig["pose"] as Dictionary).has(bone):
		rig["pose"][bone] = clamp_delta(rig, bone, rig["pose"][bone])
	return ""


static func clear_limit(rig: Dictionary, bone: String) -> void:
	if rig.has("limits"):
		(rig["limits"] as Dictionary).erase(bone)


## euler degrees clamped into a bone limit (no limit: unchanged)
static func clamp_euler_deg(rig: Dictionary, bone: String, e: Vector3) -> Vector3:
	var lim: Variant = (rig.get("limits", {}) as Dictionary).get(bone)
	if lim == null:
		return e
	var mn: Vector3 = lim["min"]
	var mx: Vector3 = lim["max"]
	return Vector3(clampf(e.x, mn.x, mx.x), clampf(e.y, mn.y, mx.y), clampf(e.z, mn.z, mx.z))


## a delta rotation clamped into its bone limit (the same rotation back when it is inside)
static func clamp_delta(rig: Dictionary, bone: String, q: Quaternion) -> Quaternion:
	if not (rig.get("limits", {}) as Dictionary).has(bone):
		return q
	var e := Basis(q.normalized()).get_euler() * (180.0 / PI)
	var c := clamp_euler_deg(rig, bone, e)
	if c.is_equal_approx(e):
		return q
	return Quaternion(Basis.from_euler(c * (PI / 180.0))).normalized()


## ---- IK on a chain the user marks: bones = a parent-to-child path; the last bone origin is the effector. pole = a world point (or null)
static func mark_chain(rig: Dictionary, cname: String, bones: Array, pole: Variant = null) -> String:
	if cname.strip_edges() == "":
		return "a chain needs a name"
	if bones.size() < 2:
		return "a chain needs at least 2 bones"
	var names: Array = rig["names"]
	for i in bones.size():
		var bi := names.find(bones[i])
		if bi < 0:
			return "no bone called \"%s\"" % bones[i]
		if i > 0 and rig["parent"][bi] != names.find(bones[i - 1]):
			return "\"%s\" is not a child of \"%s\": a chain is a path down the skeleton" % [bones[i], bones[i - 1]]
	if not rig.has("chains"):
		rig["chains"] = {}
	rig["chains"][cname] = {"bones": bones.duplicate(), "pole": pole}
	return ""


static func _local_delta(rig: Dictionary, g: Array, i: int, new_world: Basis) -> Quaternion:
	var p: int = rig["parent"][i]
	var pw: Basis = (g[p] as Transform3D).basis.orthonormalized() if p >= 0 else Basis.IDENTITY
	var rb: Basis = (rig["rest"][i] as Transform3D).basis.orthonormalized()
	return (rb.inverse() * pw.inverse() * new_world).orthonormalized().get_rotation_quaternion()


## turn chain bone k (shortest arc, in the world) so the effector bone eff moves toward to_pt, then clamp into its limit; true if the clamp changed it
static func _aim(rig: Dictionary, pose: Dictionary, idx: Array, k: int, eff: int, to_pt: Vector3, off: Vector3) -> bool:
	var g := globals(rig, pose, off)
	var bo: Vector3 = (g[idx[k]] as Transform3D).origin
	var v1: Vector3 = (g[eff] as Transform3D).origin - bo
	var v2 := to_pt - bo
	if v1.length() < 1e-9 or v2.length() < 1e-9:
		return false
	var r := Quaternion(v1.normalized(), v2.normalized())
	var nw := Basis(r) * (g[idx[k]] as Transform3D).basis.orthonormalized()
	var d := _local_delta(rig, g, idx[k], nw)
	var nm: String = rig["names"][idx[k]]
	var c := clamp_delta(rig, nm, d)
	pose[nm] = c
	return not c.is_equal_approx(d)


## solve a marked chain to a world target. Returns {"ok", "reached", "why", "err" (m), "limited", "pose"}; apply = write the pose into the rig.
## Two bones plus a third as effector (a leg: upper, lower, paw) is solved exactly, the pole picking the bend side; any other chain by CCD.
## Joint limits are never exceeded: a limited solve stops short and says so.
static func ik_solve(rig: Dictionary, cname: String, target: Vector3, apply := true) -> Dictionary:
	var ch: Variant = (rig.get("chains", {}) as Dictionary).get(cname)
	if ch == null:
		return {"ok": false, "reached": false, "why": "no chain called \"%s\"" % cname, "err": INF, "limited": false}
	var idx := []
	for b in ch["bones"]:
		idx.append((rig["names"] as Array).find(b))
	var n := idx.size()
	var off: Vector3 = rig.get("pos", Vector3.ZERO)
	var pose: Dictionary = (rig["pose"] as Dictionary).duplicate()
	var g := globals(rig, pose, off)
	var A: Vector3 = (g[idx[0]] as Transform3D).origin
	var total := 0.0
	for i in n - 1:
		total += ((g[idx[i + 1]] as Transform3D).origin - (g[idx[i]] as Transform3D).origin).length()
	var dist := (target - A).length()
	var oor := dist > total + 1e-6
	var te := A
	if dist > 1e-9:
		te = A + (target - A).normalized() * minf(dist, total * 0.999999)
	var limited := false
	if n == 3:
		var B: Vector3 = (g[idx[1]] as Transform3D).origin
		var C: Vector3 = (g[idx[2]] as Transform3D).origin
		var l1 := (B - A).length()
		var l2 := (C - B).length()
		var T := te - A
		var d := clampf(T.length(), absf(l1 - l2) + 1e-6, l1 + l2)
		var u := T.normalized()
		var along := (l1 * l1 + d * d - l2 * l2) / (2.0 * d)
		var h := sqrt(maxf(l1 * l1 - along * along, 0.0))
		var perp := Vector3.ZERO
		var pv: Variant = ch.get("pole")
		if pv is Vector3:
			perp = ((pv as Vector3) - A) - u * (((pv as Vector3) - A).dot(u))
		if perp.length() < 1e-9:
			perp = (B - A) - u * ((B - A).dot(u))
		if perp.length() < 1e-9:
			perp = u.cross(Vector3.UP) if absf(u.dot(Vector3.UP)) < 0.99 else u.cross(Vector3.RIGHT)
		perp = perp.normalized()
		var Mp := A + u * along + perp * h
		var Tp := A + u * d
		limited = _aim(rig, pose, idx, 0, idx[1], Mp, off) or limited
		limited = _aim(rig, pose, idx, 1, idx[2], Tp, off) or limited
	var err := ((globals(rig, pose, off)[idx[n - 1]] as Transform3D).origin - target).length()
	if n != 3 or (err > 1e-4 and not oor):
		for it in 400:
			for k in range(n - 2, -1, -1):
				limited = _aim(rig, pose, idx, k, idx[n - 1], te, off) or limited
			if ((globals(rig, pose, off)[idx[n - 1]] as Transform3D).origin - te).length() < 1e-6:
				break
		err = ((globals(rig, pose, off)[idx[n - 1]] as Transform3D).origin - target).length()
	var reached := err < 1e-3 and not oor
	var why := ""
	if oor:
		why = "out of reach: the target is %.3f m from the chain root and the chain is %.3f m long; it is stretched toward it" % [dist, total]
	elif not reached:
		why = ("stopped %.1f mm short: the joint limits stop the chain" if limited else "stopped %.1f mm short") % (err * 1000.0)
	if apply:
		for b in pose:
			rig["pose"][b] = pose[b]
	return {"ok": true, "reached": reached, "why": why, "err": err, "limited": limited, "pose": pose}


## every bone's world transform for a pose (bone -> delta; missing = rest)
static func globals(rig: Dictionary, pose: Dictionary, off := Vector3.ZERO) -> Array:
	var n := (rig["names"] as Array).size()
	var out := []
	out.resize(n)
	var done := PackedByteArray()
	done.resize(n)
	for i in n:
		_glob(rig, pose, i, out, done, 0, off)
	return out


## the drawn world transforms: the rig current pose and its root position offset
static func globals_posed(rig: Dictionary) -> Array:
	return globals(rig, rig["pose"], rig.get("pos", Vector3.ZERO))


static func _glob(rig: Dictionary, pose: Dictionary, i: int, out: Array, done: PackedByteArray, depth: int, off := Vector3.ZERO) -> Transform3D:
	if done[i] == 1:
		return out[i]
	var loc: Transform3D = rig["rest"][i]
	var nm: String = rig["names"][i]
	if pose.has(nm):
		loc = Transform3D(loc.basis * Basis(pose[nm] as Quaternion), loc.origin)
	var p: int = rig["parent"][i]
	if p < 0:
		loc.origin += off
	var g := loc
	if p >= 0 and depth < 4096:
		g = _glob(rig, pose, p, out, done, depth + 1, off) * loc
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


## ---- the scene file: a rig as plain JSON numbers (doubles hold the floats exactly, so the round trip is exact)
static func to_file(rig: Dictionary) -> Dictionary:
	var rest := []
	for x in rig["rest"]:
		var t: Transform3D = x
		rest.append([t.basis.x.x, t.basis.x.y, t.basis.x.z, t.basis.y.x, t.basis.y.y, t.basis.y.z, t.basis.z.x, t.basis.z.y, t.basis.z.z, t.origin.x, t.origin.y, t.origin.z])
	var keys := []
	for f in key_frames(rig):
		var row := {}
		for b in rig["keys"][f]:
			var q: Quaternion = rig["keys"][f][b]
			row[b] = [q.x, q.y, q.z, q.w]
		keys.append({"f": f, "q": row})
	var d := {"names": (rig["names"] as Array).duplicate(), "parent": (rig["parent"] as Array).duplicate(), "rest": rest, "keys": keys, "fps": float(rig.get("fps", 30.0))}
	var lim: Dictionary = rig.get("limits", {})
	if not lim.is_empty():
		var lo := {}
		var lk := lim.keys()
		lk.sort()
		for b in lk:
			var mn: Vector3 = lim[b]["min"]
			var mx: Vector3 = lim[b]["max"]
			lo[b] = [mn.x, mn.y, mn.z, mx.x, mx.y, mx.z]
		d["limits"] = lo
	var chs: Dictionary = rig.get("chains", {})
	if not chs.is_empty():
		var co := {}
		var ck := chs.keys()
		ck.sort()
		for c in ck:
			var pv: Variant = chs[c].get("pole")
			co[c] = {"bones": (chs[c]["bones"] as Array).duplicate(), "pole": [pv.x, pv.y, pv.z] if pv is Vector3 else null}
		d["chains"] = co
	var pk: Dictionary = rig.get("pkeys", {})
	var any_pos := false
	for f in pk:
		if (pk[f] as Vector3) != Vector3.ZERO:
			any_pos = true
	if any_pos:
		var pl := []
		var pf := pk.keys()
		pf.sort()
		for f in pf:
			pl.append({"f": f, "p": [pk[f].x, pk[f].y, pk[f].z]})
		d["pkeys"] = pl
	return d


static func from_file(d: Variant) -> Dictionary:
	if not (d is Dictionary) or not d.has("names") or not d.has("parent") or not d.has("rest"):
		return {}
	var rest := []
	for r in d["rest"]:
		rest.append(Transform3D(Basis(Vector3(r[0], r[1], r[2]), Vector3(r[3], r[4], r[5]), Vector3(r[6], r[7], r[8])), Vector3(r[9], r[10], r[11])))
	var parent := []
	for p in d["parent"]:
		parent.append(int(p))
	var keys := {}
	for k in d.get("keys", []):
		var row := {}
		for b in k["q"]:
			var q: Array = k["q"][b]
			row[b] = Quaternion(q[0], q[1], q[2], q[3])
		keys[int(k["f"])] = row
	var names: Array = (d["names"] as Array).map(func(n): return String(n))
	var rig := {"ok": true, "why": "", "names": names, "parent": parent, "rest": rest, "pose": {}, "keys": keys, "fps": float(d.get("fps", 30.0)),
		"core_matched": _core_matched(names), "clip": ""}
	rig["human"] = is_human(rig)
	var fr := key_frames(rig)
	if not fr.is_empty():
		rig["pose"] = (keys[fr[0]] as Dictionary).duplicate()
	if d.has("limits"):
		rig["limits"] = {}
		for b in d["limits"]:
			var a: Array = d["limits"][b]
			rig["limits"][String(b)] = {"min": Vector3(a[0], a[1], a[2]), "max": Vector3(a[3], a[4], a[5])}
	if d.has("chains"):
		rig["chains"] = {}
		for c in d["chains"]:
			var pa: Variant = d["chains"][c].get("pole")
			rig["chains"][String(c)] = {"bones": (d["chains"][c]["bones"] as Array).map(func(x): return String(x)), "pole": Vector3(pa[0], pa[1], pa[2]) if pa is Array else null}
	if d.has("pkeys"):
		rig["pkeys"] = {}
		for k in d["pkeys"]:
			rig["pkeys"][int(k["f"])] = Vector3(k["p"][0], k["p"][1], k["p"][2])
		rig["pos"] = pos_at(rig, float(fr[0])) if not fr.is_empty() else Vector3.ZERO
	return rig


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
