## ANIMATION IMPORT FROM OTHER SKELETONS (docs/GAP_ANALYSIS.md row 26; UPGRADES_200 #209). An .fbx (Mixamo, Unreal,
## Blender ...), a .glb / .gltf, or a .bvh whose skeleton is NOT Kine's becomes Kine cards. The method, its sources and its
## limits: docs/research/RETARGET.md. Four steps, each testable alone:
##   load_source(path)          the file's skeleton (rest) and its longest animation sampled at its own frame rate, through
##                              Godot's own readers (FBXDocument = ufbx, GLTFDocument; BvhImport.parse for .bvh)
##   map_bones(src)             source bone -> Kine joint: known names (Mixamo, UE4/UE5, Godot humanoid, Blender, DAZ, 3ds
##                              Max Biped) by a side + part classifier, the spine by STRUCTURE; a report of what is unmapped
##   retarget(src, map, B)      per frame: Kine world deltas from the source's world deltas, corrected for the REST POSE
##                              difference (bone directions compared at rest), root motion scaled by the leg-length ratio;
##                              one card per frame (exact, like BvhImport)
##   cards(dense, B)            the editable form, made as the video import makes it: MocapClean (feet planted, pops mended)
##                              then VideoImport.thin (about 6 cards a second, the timing kept)
## A .bvh with Kine's own joint names goes through BvhImport (exact). Nothing here writes a file: main._import_anim does.
class_name AnimImport
extends RefCounted

const EXTS := ["fbx", "glb", "gltf", "bvh"]
## the 22 joints a body animation must reach (fingers are optional: a source without them leaves the hands open)
const MAIN := ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head",
	"clavicle_l", "upperarm_l", "lowerarm_l", "hand_l", "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r",
	"thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r", "ball_r"]
## bones that are never body joints: helpers, ends, twist / roll correctives, IK targets, props
## (a word longer than 4 letters anywhere in the name; a shorter one at its start or end)
const SKIP_WORDS := ["end", "top", "nub", "site", "twist", "roll", "ik", "root", "corrective", "weapon", "prop", "pole",
	"target", "metacarpal", "jaw", "eye", "tongue", "breast", "toe1", "toe2", "toe3", "toe4", "toe5",
	"bigtoe", "littletoe", "attach", "socket", "camera", "helper", "ctrl", "mch", "org"]


## a .bvh whose root joint is Kine's pelvis (a Kine export): BvhImport reads it exactly, one card per frame
static func is_kine_bvh(path: String) -> bool:
	var bv := BvhImport.load_file(path)
	return bv["ok"] and (bv["joints"] as Array).any(func(j): return j["name"] == "pelvis")


static func _fail(why: String) -> Dictionary:
	return {"ok": false, "why": why}


## ---- 1. READ ---------------------------------------------------------------------------------------------------------
## {"ok", "why", "names": [bone], "parent": [index, -1 = root], "rest": [Transform3D in the file's scene space, global],
##  "frames": [[Transform3D global per bone] per frame], "fps", "length", "clip", "clips" (every animation's name), "format"}
static func load_source(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail("%s does not exist" % path.get_file())
	var ext := path.get_extension().to_lower()
	if ext == "bvh":
		var bv := BvhImport.load_file(path)
		if not bv["ok"]:
			return bv
		return from_bvh(bv)
	if not ext in ["fbx", "glb", "gltf"]:
		return _fail("%s is not .fbx, .glb, .gltf or .bvh" % path.get_file())
	var head := FileAccess.get_file_as_bytes(path).slice(0, 256).get_string_from_ascii()
	if ext == "fbx" and not head.contains("FBX"):
		return _fail("%s is not an FBX file inside (no FBX header)" % path.get_file())
	if ext == "glb" and not head.begins_with("glTF"):
		return _fail("%s is not a .glb inside (no glTF header)" % path.get_file())
	var doc: GLTFDocument = FBXDocument.new() if ext == "fbx" else GLTFDocument.new()
	var st: GLTFState = FBXState.new() if ext == "fbx" else GLTFState.new()
	var err := doc.append_from_file(path, st)
	if err != OK:
		return _fail("%s could not be read (%s): is it a whole file?" % [path.get_file(), error_string(err)])
	var root := doc.generate_scene(st)
	if root == null:
		return _fail("%s has nothing in it to show" % path.get_file())
	var r := from_node(root)
	root.free()
	r["format"] = ext
	return r


## the node's transform in the scene's space (the scene root's own transform left out), outside the tree
static func _scene_xf(n: Node, top: Node) -> Transform3D:
	var x := Transform3D.IDENTITY
	var c := n
	while c != null and c != top:
		if c is Node3D:
			x = (c as Node3D).transform * x
		c = c.get_parent()
	return x


## a generated scene (GLTFDocument / FBXDocument) -> the source dict (see load_source)
static func from_node(root: Node) -> Dictionary:
	var sks := root.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return _fail("it has no skeleton, so there is no animation of a body to bring in")
	var sk: Skeleton3D = sks[0]
	for s in sks:
		if (s as Skeleton3D).get_bone_count() > sk.get_bone_count():
			sk = s
	var n := sk.get_bone_count()
	var base := _scene_xf(sk, root)
	var names := []
	var parent := []
	var rest_l := []
	for i in n:
		names.append(sk.get_bone_name(i))
		parent.append(sk.get_bone_parent(i))
		rest_l.append(sk.get_bone_rest(i))
	# the longest animation that moves this skeleton
	var best: Animation = null
	var best_name := ""
	var clips := []
	var ap_best: AnimationPlayer = null
	for ap in root.find_children("*", "AnimationPlayer", true, false):
		for an in (ap as AnimationPlayer).get_animation_list():
			clips.append(String(an))
			var a: Animation = (ap as AnimationPlayer).get_animation(an)
			if best == null or a.length > best.length:
				best = a
				best_name = an
				ap_best = ap
	if best == null or best.length <= 0.0:
		return _fail("it has a skeleton (%d bones) but no animation" % n)
	# tracks -> bone index; their paths are relative to the player's root node
	var anim_root: Node = ap_best.get_node_or_null(ap_best.root_node)
	var tr_of := {}   # bone -> {"pos": track, "rot": track, "scl": track}
	var dt := 0.0
	for t in best.get_track_count():
		var ty := best.track_get_type(t)
		if not ty in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
			continue
		var p := best.track_get_path(t)
		var bone := p.get_concatenated_subnames()
		var node: Node = anim_root.get_node_or_null(NodePath(String(p).get_slice(":", 0))) if anim_root != null else null
		if node != sk or bone == "":
			continue
		var bi := sk.find_bone(bone)
		if bi < 0:
			continue
		if not tr_of.has(bi):
			tr_of[bi] = {}
		tr_of[bi][{Animation.TYPE_POSITION_3D: "pos", Animation.TYPE_ROTATION_3D: "rot", Animation.TYPE_SCALE_3D: "scl"}[ty]] = t
		if dt == 0.0 and best.track_get_key_count(t) > 2:
			dt = best.track_get_key_time(t, 2) - best.track_get_key_time(t, 1)
	if tr_of.is_empty():
		return _fail("its animation \"%s\" does not move the skeleton's bones" % best_name)
	var fps := clampi(int(round(1.0 / dt)) if dt > 1e-4 else 30, 10, 120)
	var L := best.length
	var nf := int(ceil(L * fps - 1e-6)) + 1
	var order := _order(parent)
	var rest_g := _globals(rest_l, parent, order, base)
	var frames := []
	for f in nf:
		var t := minf(f / float(fps), L)
		var loc := []
		for i in n:
			var x: Transform3D = rest_l[i]
			if tr_of.has(i):
				var d: Dictionary = tr_of[i]
				var o := x.origin
				var q := x.basis.get_rotation_quaternion()
				var s := x.basis.get_scale()
				if d.has("pos"):
					o = best.position_track_interpolate(d["pos"], t)
				if d.has("rot"):
					q = best.rotation_track_interpolate(d["rot"], t)
				if d.has("scl"):
					s = best.scale_track_interpolate(d["scl"], t)
				x = Transform3D(Basis(q).scaled_local(s), o)
			loc.append(x)
		frames.append(_globals(loc, parent, order, base))
	return {"ok": true, "why": "", "names": names, "parent": parent, "rest": rest_g, "frames": frames, "fps": fps,
		"length": L, "clip": best_name, "clips": clips}


## a parsed BVH (BvhImport.parse) -> the source dict. The rest pose is every rotation zero (the OFFSETs' pose); an End
## Site becomes a bone "<joint>_end" (it gives the last bone its direction)
static func from_bvh(bv: Dictionary) -> Dictionary:
	var js: Array = bv["joints"]
	var names := []
	var parent := []
	var rest_l := []
	var end_of := {}   # joint index -> its end bone index
	for i in js.size():
		names.append(js[i]["name"])
		parent.append(int(js[i]["parent"]))
		rest_l.append(Transform3D(Basis(), js[i]["offset"]))
	for i in js.size():
		if js[i]["end"] != null:
			end_of[i] = names.size()
			names.append(String(js[i]["name"]) + "_end")
			parent.append(i)
			rest_l.append(Transform3D(Basis(), js[i]["end"]))
	var order := _order(parent)
	var frames := []
	for row in bv["frames"]:
		var loc := rest_l.duplicate()
		for i in js.size():
			var j: Dictionary = js[i]
			var o: Vector3 = j["offset"]
			for c in j["channels"]:
				if String(c).ends_with("position"):
					o = (j["offset"] as Vector3) + BvhImport.position(j, row)
					break
			loc[i] = Transform3D(Basis(BvhImport.rotation(j, row)), o)
		frames.append(_globals(loc, parent, order, Transform3D.IDENTITY))
	return {"ok": true, "why": "", "names": names, "parent": parent, "rest": _globals(rest_l, parent, order, Transform3D.IDENTITY),
		"frames": frames, "fps": maxi(1, int(round(bv["fps"]))), "length": (bv["frames"].size() - 1) * float(bv["dt"]),
		"clip": "motion", "clips": ["motion"], "format": "bvh"}


## bone indices, parents before children
static func _order(parent: Array) -> Array:
	var out := []
	var done := {}
	while out.size() < parent.size():
		var moved := false
		for i in parent.size():
			if not done.has(i) and (int(parent[i]) < 0 or done.has(int(parent[i]))):
				done[i] = true
				out.append(i)
				moved = true
		if not moved:
			break
	return out


static func _globals(loc: Array, parent: Array, order: Array, base: Transform3D) -> Array:
	var g := []
	g.resize(loc.size())
	for i in order:
		var p := int(parent[i])
		g[i] = (base if p < 0 else (g[p] as Transform3D)) * (loc[i] as Transform3D)
	return g


## ---- 2. MAP ----------------------------------------------------------------------------------------------------------
## the bone's name -> [side "_l" / "_r" / "", part] or [] for a bone that is not a body joint. The part is a Kine joint
## stem ("upperarm", "thigh", "index_02" ...) or "pelvis" / "neck" / "head" / "spine" (the spine is placed by structure).
static func classify(raw: String) -> Array:
	var s := raw
	if s.contains(":"):
		s = s.get_slice(":", s.get_slice_count(":") - 1)   # "mixamorig:Hips" -> "Hips"
	if s.contains("|"):
		s = s.get_slice("|", s.get_slice_count("|") - 1)
	var low := s.to_lower()
	for pre in ["mixamorig", "bip01", "bip001", "def-", "def_", "def.", "armature_", "skeleton_", "character_", "cc_base_", "rig_"]:
		if low.begins_with(pre):
			low = low.substr(pre.length())
			s = s.substr(pre.length())
	# mixamorig1_Hips, mixamorig2_ ...
	while low.length() > 0 and (low[0].is_valid_int() or low[0] in "_ .-"):
		low = low.substr(1)
		s = s.substr(1)
	var side := ""
	var toks := low.replace(".", " ").replace("_", " ").replace("-", " ").split(" ", false)
	if low.contains("left"):
		side = "_l"
	elif low.contains("right"):
		side = "_r"
	elif "l" in toks:
		side = "_l"
	elif "r" in toks:
		side = "_r"
	elif s.length() > 1 and s[0] in "lLrR" and s[1] == s[1].to_upper() and s[1] != s[1].to_lower():
		side = "_l" if s[0] in "lL" else "_r"   # DAZ: lShldrBend, rThighBend; "LThigh"
		low = low.substr(1)
	var w := low.replace("left", "").replace("right", "")
	var flat := ""
	for t in w.replace(".", " ").replace("_", " ").replace("-", " ").split(" ", false):
		if t != "l" and t != "r":
			flat += t
	if flat == "":
		return []
	# fingers first (a thumb's metacarpal is its first joint): thumb / index / middle / ring / pinky (little) + 1..3, 01..03
	# or proximal / intermediate / distal
	if side != "" and not flat.contains("forearm") and not flat.contains("twist") and not flat.ends_with("end"):
		for f in [["thumb", "thumb"], ["index", "index"], ["middle", "middle"], ["ring", "ring"], ["pinky", "pinky"], ["little", "pinky"]]:
			if not flat.contains(f[0]):
				continue
			var dg := ""
			var k := flat.length() - 1
			while k >= 0 and flat[k].is_valid_int():
				dg = flat[k] + dg
				k -= 1
			var n := int(dg) if dg != "" else 0
			if dg == "":
				var words := ["metacarpal", "proximal", "distal"] if f[1] == "thumb" else ["proximal", "intermediate", "distal"]
				for w2 in 3:
					if flat.contains(words[w2]):
						n = w2 + 1
			if n < 1 or n > 3:
				return []
			return [side, "%s_0%d" % [f[1], n]]
	for sw in SKIP_WORDS:
		if flat == sw or flat.begins_with(sw) or flat.ends_with(sw) and not flat.ends_with("bend") or (sw.length() > 4 and flat.contains(sw)):
			return []
	if side != "":
		var parts := [["forearm", "lowerarm"], ["lowerarm", "lowerarm"], ["loarm", "lowerarm"], ["elbow", "lowerarm"],
			["upperarm", "upperarm"], ["uparm", "upperarm"], ["shldr", "upperarm"], ["clavicle", "clavicle"], ["collar", "clavicle"],
			["shoulder", "clavicle"], ["hand", "hand"], ["wrist", "hand"], ["upleg", "thigh"], ["upperleg", "thigh"],
			["thigh", "thigh"], ["lowerleg", "calf"], ["calf", "calf"], ["shin", "calf"], ["knee", "calf"],
			["toebase", "ball"], ["toes", "ball"], ["toe", "ball"], ["ball", "ball"], ["foot", "foot"], ["ankle", "foot"],
			["arm", "upperarm"], ["leg", "calf"], ["hip", "thigh"]]
		for p in parts:
			if flat.contains(p[0]):
				return [side, p[1]]
		return []
	if flat in ["hips", "hip", "pelvis", "pelvic"]:
		return ["", "pelvis"]
	if flat.begins_with("neck"):
		return ["", "neck"]
	if flat == "head":
		return ["", "head"]
	if flat.begins_with("spine") or flat.contains("chest") or flat in ["abdomen", "abdomenlower", "abdomenupper", "torso", "waist", "back", "upperback", "lowerback"]:
		return ["", "spine"]
	return []


## source bones -> Kine joints. {"map": {kine joint: bone index}, "unmapped": [bone names], "missing": [Kine joints the
## file has no bone for], "main": how many of the 22 MAIN joints are mapped, "how": {kine joint: "name" / "structure"}}
static func map_bones(src: Dictionary) -> Dictionary:
	var names: Array = src["names"]
	var parent: Array = src["parent"]
	var depth := []
	for i in names.size():
		var d := 0
		var p := int(parent[i])
		while p >= 0:
			d += 1
			p = int(parent[p])
		depth.append(d)
	var mp := {}
	var how := {}
	var cls := []
	for i in names.size():
		cls.append(classify(names[i]))
	# 1. exact Kine names first (a Kine export), then sided parts and the pelvis / head; the shallower bone wins a tie
	var exact := {}
	for i in names.size():
		var low := String(names[i]).to_lower()
		if low in Body.ORDER and not mp.has(low):
			mp[low] = i
			how[low] = "name"
			exact[low] = true
	for i in names.size():
		var c: Array = cls[i]
		if c.is_empty() or c[1] == "spine":
			continue
		var j: String = "neck_01" if c[1] == "neck" else c[1] if c[1] in ["pelvis", "head"] else c[1] + c[0]
		if not Body.ORDER.has(j) or exact.has(j):
			continue
		if not mp.has(j) or depth[i] < depth[mp[j]]:
			mp[j] = i
			how[j] = "name"
	# 3. the spine by STRUCTURE: the bones strictly between the pelvis and the neck (else the clavicles' parent, inclusive)
	if mp.has("pelvis") and not (how.get("spine_01", "") == "name" and how.get("spine_03", "") == "name"):
		var top := -1
		if mp.has("neck_01"):
			top = int(parent[mp["neck_01"]])
		elif mp.has("clavicle_l"):
			top = int(parent[mp["clavicle_l"]])
		elif mp.has("head"):
			top = int(parent[mp["head"]])
		var chain := []
		var c := top
		while c >= 0 and c != mp["pelvis"]:
			chain.push_front(c)
			c = int(parent[c])
		if c == mp["pelvis"] and not chain.is_empty():
			for j in ["spine_01", "spine_02", "spine_03"]:
				mp.erase(j)
			var n := chain.size()
			if n == 1:
				mp["spine_03"] = chain[0]
			elif n == 2:
				mp["spine_01"] = chain[0]
				mp["spine_03"] = chain[1]
			else:
				mp["spine_01"] = chain[0]
				mp["spine_02"] = chain[n / 2]
				mp["spine_03"] = chain[n - 1]
			for j in ["spine_01", "spine_02", "spine_03"]:
				if mp.has(j):
					how[j] = "structure"
	var used := {}
	for j in mp:
		used[mp[j]] = true
	var unmapped := []
	for i in names.size():
		if not used.has(i):
			unmapped.append(names[i])
	var missing := []
	var main := 0
	for j in Body.ORDER:
		if mp.has(j):
			main += 1 if j in MAIN else 0
		else:
			missing.append(j)
	return {"map": mp, "unmapped": unmapped, "missing": missing, "main": main, "how": how}


## ---- 3. RETARGET -----------------------------------------------------------------------------------------------------
## the frame both skeletons share: left (the left thigh minus the right, else the upper arms) and up (pelvis -> the
## highest spine / neck / head joint), made square. Kine's from its rest, the source's from its rest, by the SAME rule.
static func _frame(pos: Dictionary) -> Basis:
	var left := Vector3.ZERO
	if pos.has("thigh_l") and pos.has("thigh_r"):
		left = (pos["thigh_l"] as Vector3) - pos["thigh_r"]
	elif pos.has("upperarm_l") and pos.has("upperarm_r"):
		left = (pos["upperarm_l"] as Vector3) - pos["upperarm_r"]
	var up := Vector3.ZERO
	for j in ["head", "neck_01", "spine_03", "spine_02", "spine_01"]:
		if pos.has(j):
			up = (pos[j] as Vector3) - pos["pelvis"]
			break
	if left.length() < 1e-6 or up.length() < 1e-6:
		return Basis()
	var u := up.normalized()
	var l := (left - u * left.dot(u)).normalized()
	return Basis(l, u, l.cross(u))


## the leg's length at rest: thigh -> calf -> foot, both sides averaged (0 when the legs are not mapped)
static func _leg(pos: Dictionary) -> float:
	var n := 0
	var s := 0.0
	for sd in ["_l", "_r"]:
		if pos.has("thigh" + sd) and pos.has("calf" + sd) and pos.has("foot" + sd):
			s += (pos["thigh" + sd] as Vector3).distance_to(pos["calf" + sd]) + (pos["calf" + sd] as Vector3).distance_to(pos["foot" + sd])
			n += 1
	return s / n if n > 0 else 0.0


## the shortest turn taking unit a onto unit b
static func _arc(a: Vector3, b: Vector3) -> Quaternion:
	if a.length() < 1e-9 or b.length() < 1e-9:
		return Quaternion.IDENTITY
	a = a.normalized()
	b = b.normalized()
	var d := a.dot(b)
	if d > 0.999999:
		return Quaternion.IDENTITY
	if d < -0.999999:
		var ax := a.cross(Vector3.RIGHT)
		if ax.length() < 1e-3:
			ax = a.cross(Vector3.UP)
		return Quaternion(ax.normalized(), PI)
	return Quaternion(a.cross(b).normalized(), acos(clampf(d, -1.0, 1.0)))


## the source + its map -> {"ok", "scene" (one card per frame), "ratio", "rest_deg" {joint: the rest difference in
## degrees}, "frames", "fps", "text"}. B is only read (rest, axes); its state is put back.
static func retarget(src: Dictionary, mapping: Dictionary, B: Body, scene_name := "anim_import") -> Dictionary:
	var mp: Dictionary = mapping["map"]
	if not mp.has("pelvis"):
		return _fail("no bone could be matched to the hips (bones found: %s)" % ", ".join(PackedStringArray((src["names"] as Array).slice(0, 8))))
	if int(mapping["main"]) < 12:
		return _fail("only %d of the %d main body bones could be matched (unmatched: %s)" % [mapping["main"], MAIN.size(),
			", ".join(PackedStringArray(MAIN.filter(func(j): return not mp.has(j))))])
	var rest: Array = src["rest"]
	var parent: Array = src["parent"]
	# source rest positions per Kine joint, in the source's space
	var sp := {}
	for j in mp:
		sp[j] = (rest[mp[j]] as Transform3D).origin
	var kp := {}
	for j in Body.ORDER:
		kp[j] = B.p0[j]
	# C: source space -> Kine space (turn), by matching the two rest frames
	var Fs := _frame(sp)
	var Fk := _frame(kp)
	var C := (Fk * Fs.inverse()).get_rotation_quaternion()
	var leg_s := _leg(sp)
	var leg_k := _leg(kp)
	var ratio := leg_k / leg_s if leg_s > 1e-6 else 0.0
	if ratio <= 0.0:   # no legs: the hips' height above the lowest bone instead
		var lo := INF
		for x in rest:
			lo = minf(lo, (C * (x as Transform3D).origin).y)
		var hs := (C * (sp["pelvis"] as Vector3)).y - lo
		ratio = (B.p0["pelvis"] as Vector3).y / hs if hs > 1e-6 else 1.0
	# REST DIFFERENCE per Kine joint: the turn from Kine's rest bone direction to the source's (in Kine space). A joint
	# with no end to compare (no mapped child, no single child bone) inherits its parent's: its chain turned as a whole.
	var roff := {}
	var rest_deg := {}
	var kids := {}
	for i in parent.size():
		var p := int(parent[i])
		if p >= 0:
			if not kids.has(p):
				kids[p] = []
			kids[p].append(i)
	for j in Body.ORDER:
		var inherit: Quaternion = roff[B.parent[j]] if B.parent[j] != "" else Quaternion.IDENTITY
		roff[j] = inherit
		if not mp.has(j):
			continue
		var b: int = mp[j]
		var end = null
		var ch := String(Body.CHILD.get(j, ""))
		if ch == "" and j.begins_with("hand_"):
			ch = "middle_01" + j.right(2)
		if ch != "" and mp.has(ch):
			end = (rest[mp[ch]] as Transform3D).origin
		elif kids.has(b) and (kids[b] as Array).size() == 1:
			end = (rest[kids[b][0]] as Transform3D).origin
		if end == null:
			continue
		var ds: Vector3 = C * ((end as Vector3) - (rest[b] as Transform3D).origin)
		var dk: Vector3 = (B.e0[j] as Vector3) - (B.p0[j] as Vector3)
		if ds.length() < 1e-6:
			continue
		roff[j] = _arc(dk, ds)
		rest_deg[j] = snappedf(rad_to_deg((roff[j] as Quaternion).get_angle()), 0.1)
	var rq := []
	for x in rest:
		rq.append((x as Transform3D).basis.get_rotation_quaternion())
	# ROOT MOTION: the hips where the file has them, about the file's origin (its floor at height 0), x the leg ratio. Not
	# against the rest hips: an FBX's rest root can be the pose the file was saved in (Godot's FBX reader takes the root's
	# node translation; found on the test rig), and the floor is the reference both skeletons share.
	var pel0: Vector3 = B.p0["pelvis"]
	var S := Scene.new()
	S.name = scene_name
	S.fps = int(src["fps"])
	S.natural = false
	S.on_floor = false
	S.pin = false
	var frames: Array = src["frames"]
	var dt := 1.0 / float(S.fps)
	var Ci := C.inverse()
	for f in frames.size():
		var fr: Array = frames[f]
		var G := {}
		var jd := {}
		for j in Body.ORDER:
			var gp: Quaternion = G[B.parent[j]] if B.parent[j] != "" else Quaternion.IDENTITY
			if mp.has(j):
				var b: int = mp[j]
				var D: Quaternion = C * ((fr[b] as Transform3D).basis.get_rotation_quaternion() * (rq[b] as Quaternion).inverse()) * Ci
				G[j] = (D * roff[j]).normalized()
			else:
				G[j] = gp * ((roff[B.parent[j]] as Quaternion).inverse() * roff[j] if B.parent[j] != "" else roff[j])
			var A: Quaternion = (gp.inverse() * G[j]).normalized()
			var a := BvhImport.decompose(B, j, A)
			jd[j] = {"bend": a.x, "side": a.y, "twist": a.z}
		var off: Vector3 = C * (fr[mp["pelvis"]] as Transform3D).origin * ratio - pel0
		S.add("f%d" % f, {"joints": jd, "offset": [off.x, off.y, off.z]})
		var c: Dictionary = S.cards[-1]
		c["move"] = dt if f > 0 else -1.0
		c["hold"] = 0.0
		c["ease"] = "linear"
	var txt := "%d frames at %d fps, %d of %d main bones matched, root motion x%.2f (leg length %.2f -> %.2f)" % [frames.size(), S.fps,
		mapping["main"], MAIN.size(), ratio, leg_s, leg_k]
	return {"ok": true, "why": "", "scene": S, "ratio": ratio, "rest_deg": rest_deg, "frames": frames.size(), "fps": S.fps, "text": txt}


## ---- 4. CARDS + the whole pipeline --------------------------------------------------------------------------------------
## the dense scene -> the editable one, as the video import does it: MocapClean (feet planted, pops mended; it needs a card
## per frame; only when Check finds a foot slide), then VideoImport.thin's even spacing (about 6 cards a second), REFINED: an animation made for a game snaps
## (a swing in a fifth of a second), and the even spacing alone blended combo3's bat swing 77 cm off its path (measured on
## the .glb round trip). So inside each gap the frame the cards would blend worst is kept too, until every joint's three
## angles are within TOL_DEG of the file and the hips within TOL_M (the cards blend angles linearly: that is what is
## measured). Returns [scene, MocapClean's report]. B's state is put back.
const TOL_DEG := 1.0
const TOL_M := 0.005


static func cards(dense: Scene, B: Body) -> Array:
	var keep := B.state()
	# the foot lock only where Check finds a FOOT SLIDE: on a clean game animation (combo3 through .glb: no slide) it moved
	# a pivoting foot 8.7 cm off the file's path, fixing nothing
	var s0 := MocapClean.slide_of(dense, B)
	var r := {"text": "feet as the file has them (Check finds no FOOT SLIDE: no lock needed)", "locked": 0, "slide0": s0}
	if int(s0["n"]) > 0:
		r = MocapClean.clean(dense, B, {})
	var every := VideoImport.every_for(dense.fps)
	var T := VideoImport.thin(dense, every, refine(dense, every))
	T.name = dense.name
	B.set_state(keep)
	return [T, r]


## the card indices to keep beyond the even spacing (see cards())
static func refine(S: Scene, every: int) -> Dictionary:
	var n := S.cards.size()
	var base := []
	for i in n:
		if i % maxi(1, every) == 0 or i == n - 1:
			base.append(i)
	var extra := {}
	var todo := []
	for k in base.size() - 1:
		todo.append([base[k], base[k + 1]])
	while not todo.is_empty():
		var seg: Array = todo.pop_back()
		var a: int = seg[0]
		var b: int = seg[1]
		if b - a < 2:
			continue
		var worst := 0.0
		var at := -1
		for f in range(a + 1, b):
			var e := _gap_err(S, a, b, f)
			if e > worst:
				worst = e
				at = f
		if worst > 1.0:
			extra[at] = true
			todo.append([a, at])
			todo.append([at, b])
	return extra


## how far card f is from the straight blend of cards a and b at its place, in units of the tolerance (> 1 = too far)
static func _gap_err(S: Scene, a: int, b: int, f: int) -> float:
	var u := float(f - a) / float(b - a)
	var pa: Dictionary = S.cards[a]["pose"]
	var pb: Dictionary = S.cards[b]["pose"]
	var pf: Dictionary = S.cards[f]["pose"]
	var e := 0.0
	for j in pf["joints"]:
		var x: Dictionary = pf["joints"][j]
		var xa: Dictionary = pa["joints"].get(j, x)
		var xb: Dictionary = pb["joints"].get(j, x)
		for k in ["bend", "side", "twist"]:
			e = maxf(e, absf(lerpf(float(xa[k]), float(xb[k]), u) - float(x[k])) / TOL_DEG)
	var oa: Array = pa["offset"]
	var ob: Array = pb["offset"]
	var of: Array = pf["offset"]
	for k in 3:
		e = maxf(e, absf(lerpf(float(oa[k]), float(ob[k]), u) - float(of[k])) / TOL_M)
	return e


## a file -> {"ok", "why", "scene" (the cards), "dense" (one card per frame), "map", "text": one line for the status bar,
## "report": the mapping in words}. A .bvh with Kine's joint names goes through BvhImport (exact).
static func import_file(path: String, B: Body, scene_name := "") -> Dictionary:
	# the new scene has no "body" of its own, so it plays on the mannequin's proportions: retarget onto those
	var keep_body: Dictionary = B.body.duplicate(true)
	if not keep_body.is_empty():
		B.set_proportions({})
	var r := _import_file(path, B, scene_name)
	if not keep_body.is_empty():
		B.set_proportions(keep_body)
	return r


static func _import_file(path: String, B: Body, scene_name := "") -> Dictionary:
	var keep := B.state()
	var nm := scene_name if scene_name != "" else path.get_file().get_basename()
	var dense: Scene = null
	var head := ""
	var mapping := {}
	var checks := {"warnings": []}   # C04: ClipChecks (A-pose, size, proportions); words only, the import is unchanged
	if path.get_extension().to_lower() == "bvh":
		var bv := BvhImport.load_file(path)
		if not bv["ok"]:
			return bv
		var kine := false
		for j in bv["joints"]:
			kine = kine or j["name"] == "pelvis"
		if kine:
			var r := BvhImport.to_scene(bv, B, 1, 1.0, nm)
			if not r["ok"]:
				return r
			dense = r["scene"]
			head = "a Kine .bvh: " + String(r["text"])
			mapping = {"map": {}, "unmapped": r["not_mapped"], "missing": r["missing"], "main": MAIN.size() - (r["missing"] as Array).filter(func(j): return j in MAIN).size(), "how": {}}
	if dense == null:
		var src := load_source(path)
		if not src["ok"]:
			return src
		mapping = RetargetMap.resolve(src)   # W04: the rig's saved bone map, else the guess
		var rt := retarget(src, mapping, B, nm)
		if not rt["ok"]:
			return rt
		dense = rt["scene"]
		checks = ClipChecks.analyze(src, mapping, B, rt)
		head = "\"%s\" (%s%s): %s" % [src["clip"], src["format"], (", %d animations in the file, the longest taken" % (src["clips"] as Array).size()) if (src["clips"] as Array).size() > 1 else "", rt["text"]]
	var cr := cards(dense, B)
	B.set_state(keep)
	var T: Scene = cr[0]
	var rep := report(mapping)
	return {"ok": true, "why": "", "scene": T, "dense": dense, "map": mapping, "clean": cr[1], "checks": checks, "warnings": checks["warnings"],
		"text": "%s; %d cards; %s" % [head, T.cards.size(), String(cr[1]["text"])], "report": rep}


## the mapping in words: what was not matched (the file's bones) and which Kine joints stay at rest
static func report(mapping: Dictionary) -> String:
	var miss_main := (mapping["missing"] as Array).filter(func(j): return j in MAIN)
	var miss_fing := (mapping["missing"] as Array).size() - miss_main.size()
	var s := "%d of %d main bones matched" % [mapping["main"], MAIN.size()]
	if not miss_main.is_empty():
		s += " (at rest: %s)" % ", ".join(PackedStringArray(miss_main))
	if miss_fing > 0:
		s += ", %d finger joints at rest" % miss_fing
	var un: Array = mapping["unmapped"]
	if not un.is_empty():
		s += "; not used from the file: %s%s" % [", ".join(PackedStringArray(un.slice(0, 12))), " and %d more" % (un.size() - 12) if un.size() > 12 else ""]
	return s
