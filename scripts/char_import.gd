## RIGGED CHARACTER IMPORT (docs/GAP_AUDIT_1106.md top 10 #2; lane L9). A .glb / .gltf / .fbx with a skinned mesh becomes a
## Kine character: its mesh, skin weights and blend shapes come in whole, its skeleton is mapped onto Kine's body, and Kine's
## poses drive it. Five steps, each testable alone (tests/charimp_test.gd):
##   load_character(path)   Godot's own readers (GLTFDocument, FBXDocument = ufbx): the scene, the skeleton with the most
##                          skinned meshes, the meshes, and the `src` dict AnimImport reads (names, parent, rest global)
##   map_bones(src)         source bone -> Kine joint. NAMES first (AnimImport.classify: Mixamo, UE4 / UE5 Mannequin, Godot,
##                          Blender, DAZ, 3ds Max, plus Rigify "DEF-" and VRM "J_Bip_" / humanoid names through `canon`), then
##                          GEOMETRY when the names do not give the body: chain topology + positions (the hips are the bone
##                          where the spine and two mirrored legs meet, the shoulders where two mirrored arms and a neck meet;
##                          left is up x forward, forward from foot -> toe). The report names every bone left unmapped.
##   fit(src, map, B)       REST-POSE ALIGNMENT, the one AnimImport.retarget uses: the frame both rests share (any up axis,
##                          Z-up or Y-up), a per-joint turn from Kine's rest bone direction to the file's (T-pose vs A-pose),
##                          the leg-length ratio (scale)
##   body_dict(src, map)    the character's own proportions as a Kine `body` dict (Proportions): limits, balance, contacts and
##                          the ground then use ITS segment lengths
##   pose(ch, map, fit, B)  Kine's pose (B.G, B.P) written onto the imported skeleton; every mapped bone ends with the world
##                          rotation  Ci * (G * roff^-1) * C * rest  (the inverse of AnimImport.retarget's), the hips at the
##                          body's position / ratio, unmapped bones carrying their rest rotation under their parent
## Also here: skin_points (the independent CPU linear-blend skin the bars measure), weights_of, shapes_of, and the scene key
## (path + the map by bone NAME) the saved scene keeps.
class_name CharImport
extends RefCounted

const KEY := "charimp"
const EXTS := ["glb", "gltf", "fbx"]
const MAIN_NEED := 12          # fewer main joints than this by name: the geometry route is tried
const NAME_GOOD := 18          # and below this a geometry map that finds more wins
const HEAD_TOP_FRAC := 0.13    # geometry: a leaf this far above the shoulders (x stature) is a head-top end bone, not the head


static func _fail(why: String) -> Dictionary:
	return {"ok": false, "why": why}


## ---- 1. READ ---------------------------------------------------------------------------------------------------------
## {"ok", "why", "path", "format", "root" (Node3D, the caller frees it or adds it to the tree), "sk", "meshes", "src", "text"}
## src: {"names", "parent", "rest" (global in the scene's space, the scene root's own transform left out), "base" (the
## skeleton node's transform in that space)}
static func load_character(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail("%s does not exist" % path.get_file())
	var ext := path.get_extension().to_lower()
	if not ext in EXTS:
		return _fail("%s is not .glb, .gltf or .fbx" % path.get_file())
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
	r["path"] = path
	r["format"] = ext
	if not r["ok"]:
		root.free()
	return r


## the skeleton as the `src` dict: names, parent, rest (global, scene space), base (the skeleton node in scene space)
static func src_of(sk: Skeleton3D, root: Node) -> Dictionary:
	var base := AnimImport._scene_xf(sk, root)
	var names := []
	var parent := []
	var rest := []
	for i in sk.get_bone_count():
		names.append(sk.get_bone_name(i))
		parent.append(sk.get_bone_parent(i))
		rest.append(base * sk.get_bone_global_rest(i))
	return {"names": names, "parent": parent, "rest": rest, "base": base}


## a generated scene -> the character dict (see load_character)
static func from_node(root: Node) -> Dictionary:
	var best: Skeleton3D = null
	var best_meshes := []
	for s in root.find_children("*", "Skeleton3D", true, false):
		var sk := s as Skeleton3D
		var ms := []
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.skin != null and m.mesh is ArrayMesh and m.get_node_or_null(m.skeleton) == sk:
				ms.append(m)
		if best == null or ms.size() > best_meshes.size() or (ms.size() == best_meshes.size() and sk.get_bone_count() > best.get_bone_count()):
			best = sk
			best_meshes = ms
	if best == null:
		return _fail("it has no skeleton: a character needs one (a model without a skeleton is a prop)")
	if best_meshes.is_empty():
		return _fail("it has a skeleton (%d bones) but no skinned mesh: that is an animation file, use Import animation" % best.get_bone_count())
	var src := src_of(best, root)
	var nv := 0
	var nsh := 0
	for m in best_meshes:
		var am := (m as MeshInstance3D).mesh as ArrayMesh
		nsh += am.get_blend_shape_count()
		for si in am.get_surface_count():
			nv += am.surface_get_array_len(si)
	var names: Array = src["names"]
	return {"ok": true, "why": "", "root": root, "sk": best, "meshes": best_meshes, "src": src,
		"text": "%d bones, %d skinned mesh%s (%d vertices), %d blend shape%s" % [names.size(), best_meshes.size(),
			"" if best_meshes.size() == 1 else "es", nv, nsh, "" if nsh == 1 else "s"]}


## ---- 2. MAP ----------------------------------------------------------------------------------------------------------
## Rigify and VRM bone names -> Kine's joint names (everything else is returned as it came: AnimImport.classify reads it)
const _VRM := {"hips": "pelvis", "spine": "spine_01", "chest": "spine_02", "upperchest": "spine_03", "neck": "neck_01", "head": "head"}
const _VRM_SIDED := {"shoulder": "clavicle", "upperarm": "upperarm", "lowerarm": "lowerarm", "hand": "hand", "upperleg": "thigh",
	"lowerleg": "calf", "foot": "foot", "toes": "ball", "toebase": "ball"}
const _RIG_SPINE := {"": "pelvis", "001": "spine_01", "002": "spine_02", "003": "spine_03", "004": "neck_01", "006": "head"}
const _RIG_SIDED := {"shoulder": "clavicle", "upper_arm": "upperarm", "forearm": "lowerarm", "hand": "hand", "thigh": "thigh",
	"shin": "calf", "foot": "foot", "toe": "ball"}
const _FINGERS := ["thumb", "index", "middle", "ring", "pinky", "little"]


static func canon(raw: String) -> String:
	var s := raw
	var low := s.to_lower()
	# VRM 0.x: J_Bip_C_Hips, J_Bip_L_UpperArm, J_Bip_L_Index1 ... (J_Sec_ / J_Adj_ are hair, skirts: left alone)
	if low.begins_with("j_bip_"):
		var rest := low.substr(6)
		var side := ""
		if rest.begins_with("l_"):
			side = "_l"
			rest = rest.substr(2)
		elif rest.begins_with("r_"):
			side = "_r"
			rest = rest.substr(2)
		elif rest.begins_with("c_"):
			rest = rest.substr(2)
		return _vrm_part(rest, side, raw)
	# VRM 1.0 humanoid names: hips, spine, chest, upperChest, neck, head, leftUpperArm, rightHand, leftIndexProximal ...
	if low in _VRM and (s == s.to_lower() or s[0] == s[0].to_lower()) and raw != "":
		if not low in ["spine", "neck", "head", "chest"] or _looks_vrm(raw):
			return _VRM[low]
	for pre in ["left", "right"]:
		if low.begins_with(pre) and raw.length() > pre.length() and raw[0] == raw[0].to_lower() and raw[pre.length()] == raw[pre.length()].to_upper() and raw[pre.length()] != raw[pre.length()].to_lower():
			var r := _vrm_part(low.substr(pre.length()), "_l" if pre == "left" else "_r", raw)
			if r != raw:
				return r
	# Rigify: DEF-spine.003, DEF-upper_arm.L, DEF-f_index.01.L, DEF-thumb.02.R, upper_arm.L (the metarig)
	var b := s
	if b.begins_with("DEF-") or b.begins_with("ORG-"):
		b = b.substr(4)
	var sd := ""
	var core := b
	var tw := ""
	var parts := b.split(".")
	if parts.size() >= 2:
		var last := String(parts[parts.size() - 1])
		if last in ["L", "R"]:
			sd = "_l" if last == "L" else "_r"
			core = ".".join(parts.slice(0, parts.size() - 1))
		elif last.is_valid_int() and parts.size() >= 3 and String(parts[parts.size() - 2]) in ["L", "R"]:
			sd = "_l" if parts[parts.size() - 2] == "L" else "_r"
			tw = last
			core = ".".join(parts.slice(0, parts.size() - 2))
	if core == "spine" or core.begins_with("spine."):
		var suf := core.substr(6) if core.length() > 6 else ""
		if suf.begins_with("."):
			suf = suf.substr(1)
		if raw.begins_with("DEF-") or raw.begins_with("ORG-") or _RIG_SPINE.has(suf):
			return String(_RIG_SPINE.get(suf, "neck_02")) if (b.begins_with("spine") and (raw.begins_with("DEF-") or raw.begins_with("ORG-") or true)) and _is_rigify_ctx(raw) else raw
	if sd != "":
		var cl := core.to_lower()
		if _RIG_SIDED.has(cl):
			return String(_RIG_SIDED[cl]) + ("_twist_" + tw if tw != "" else "") + sd if tw == "" else "%s_twist_%s%s" % [_RIG_SIDED[cl], tw, sd]
		for f in _FINGERS:
			for pre in ["f_", ""]:
				if cl.begins_with(pre + f + "."):
					var k := cl.substr((pre + f + ".").length())
					if k.length() == 2 and k.is_valid_int() and int(k) in [1, 2, 3]:
						return "%s_%s%s" % ["pinky" if f == "little" else f, k, sd]
	return raw


## is this name a Rigify one (a "DEF-" / "ORG-" prefix, or a dotted ".L" / ".R" metarig name)? "spine" alone is too common
static func _is_rigify_ctx(raw: String) -> bool:
	return raw.begins_with("DEF-") or raw.begins_with("ORG-") or raw.contains(".")


static func _looks_vrm(raw: String) -> bool:
	return raw == "hips" or raw == "upperChest" or raw == "chest"


static func _vrm_part(rest: String, side: String, raw: String) -> String:
	var r := rest.replace("_", "")
	if side == "" and _VRM.has(r):
		return _VRM[r]
	if side != "":
		if _VRM_SIDED.has(r):
			return String(_VRM_SIDED[r]) + side
		for f in _FINGERS:
			if r.begins_with(f):
				var tail := r.substr(f.length())
				var n := 0
				if tail.is_valid_int():
					n = int(tail)
				else:
					var words := ["metacarpal", "proximal", "distal"] if f == "thumb" else ["proximal", "intermediate", "distal"]
					n = words.find(tail) + 1
				if n >= 1 and n <= 3:
					return "%s_0%d%s" % ["pinky" if f == "little" else f, n, side]
	return raw


## a copy of src whose bone names are `canon`ed (a clash keeps the shallower bone's name, the other gets a "_dup" tail)
static func canon_src(src: Dictionary) -> Dictionary:
	var out: Dictionary = src.duplicate()
	var names := []
	var seen := {}
	var ue5 := false   # UE5's Mannequin has spine_01..05: the exact-name route would take the first three; the structure route takes first, middle, last
	for nm in src["names"]:
		if String(nm).to_lower() == "spine_04":
			ue5 = true
	for nm in src["names"]:
		var c := canon(String(nm))
		if ue5 and c.to_lower().begins_with("spine_0") and c.length() == 8:
			c = "spine" + c.substr(7)
		if seen.has(c) and c != String(nm):
			c = c + "_dup"
		seen[c] = true
		names.append(c)
	out["names"] = names
	return out


## the whole map: names first, geometry when the names do not give the body. -> AnimImport.map_bones's dict plus
## "method" ("name" / "geometry"), "name_main", "geo_main", and "unmapped" (every bone not mapped, by its own file name)
static func map_bones(src: Dictionary) -> Dictionary:
	var cs := canon_src(src)
	var nm := AnimImport.map_bones(cs)
	nm["name_main"] = int(nm["main"])
	var use := nm
	var method := "name"
	var geo_main := -1
	if int(nm["main"]) < NAME_GOOD or not _sides_agree(src, nm):
		var g := geometry_map(src)
		geo_main = int(g["main"])
		if geo_main > int(nm["main"]) or (int(nm["main"]) < MAIN_NEED and geo_main > 0):
			use = g
			method = "geometry"
	use["method"] = method
	use["name_main"] = int(nm["name_main"])
	use["geo_main"] = geo_main
	use["unmapped"] = _unmapped(src, use["map"])
	return use


static func _unmapped(src: Dictionary, mp: Dictionary) -> Array:
	var used := {}
	for j in mp:
		used[int(mp[j])] = true
	var un := []
	for i in (src["names"] as Array).size():
		if not used.has(i):
			un.append(src["names"][i])
	return un


## the named map's left bones must be on the body's left (SideCheck): a rig named the wrong way round is not trusted by name
static func _sides_agree(src: Dictionary, mapping: Dictionary) -> bool:
	var r := SideCheck.check(src, mapping)
	return bool(r["ok"])


## ---- GEOMETRY MAP ----------------------------------------------------------------------------------------------------
static func _kids_of(parent: Array) -> Array:
	var kids := []
	for i in parent.size():
		kids.append([])
	for i in parent.size():
		var p := int(parent[i])
		if p >= 0:
			(kids[p] as Array).append(i)
	return kids


static func _subtree(kids: Array, i: int, memo: Dictionary) -> int:
	if memo.has(i):
		return memo[i]
	var s := 1
	for k in kids[i]:
		s += _subtree(kids, k, memo)
	memo[i] = s
	return s


static func _height(kids: Array, i: int, memo: Dictionary) -> int:
	if memo.has(i):
		return memo[i]
	var h := 0
	for k in kids[i]:
		h = maxi(h, 1 + _height(kids, k, memo))
	memo[i] = h
	return h


## the main chain down from bone i: at each bone the child with the greatest height (ties: the bigger subtree)
static func _chain(kids: Array, i: int, hm: Dictionary, sm: Dictionary) -> Array:
	var out := [i]
	var c := i
	while not (kids[c] as Array).is_empty():
		var best := -1
		for k in kids[c]:
			if best < 0 or _height(kids, k, hm) > _height(kids, best, hm) or (_height(kids, k, hm) == _height(kids, best, hm) and _subtree(kids, k, sm) > _subtree(kids, best, sm)):
				best = k
		out.append(best)
		c = best
	return out


static func _pair_across(pos: Array, hip: Vector3, up: Vector3, cands: Array, size: float) -> Array:
	var best := []
	var bsep := 0.0
	for a in cands.size():
		for b in range(a + 1, cands.size()):
			var la: Vector3 = (pos[cands[a]] as Vector3) - hip
			var lb: Vector3 = (pos[cands[b]] as Vector3) - hip
			la -= up * la.dot(up)
			lb -= up * lb.dot(up)
			var sep := (la - lb).length()
			if la.dot(lb) <= 0.0 and sep > bsep:
				bsep = sep
				best = [cands[a], cands[b]]
	if bsep < 0.04 * size:
		return []
	return best


## names ignored: the body from the skeleton's topology and rest positions. -> {"map", "how", "missing", "main", "unmapped", "why"}
static func geometry_map(src: Dictionary) -> Dictionary:
	var parent: Array = src["parent"]
	var rest: Array = src["rest"]
	var n := parent.size()
	var pos := []
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for i in n:
		var o: Vector3 = (rest[i] as Transform3D).origin
		pos.append(o)
		lo = lo.min(o)
		hi = hi.max(o)
	var size := maxf((hi - lo)[(hi - lo).max_axis_index()], 1e-6)
	var kids := _kids_of(parent)
	var sm := {}
	var hm := {}
	var res := {"map": {}, "how": {}, "missing": [], "main": 0, "unmapped": [], "why": ""}
	var roots := []
	for i in n:
		if int(parent[i]) < 0:
			roots.append(i)
	if roots.is_empty():
		res["why"] = "no root bone"
		return _geo_done(src, res)
	roots.sort_custom(func(a, b): return _subtree(kids, a, sm) > _subtree(kids, b, sm))
	# the hips: walk down the biggest branch until a bone has a spine (the biggest child) and two mirrored legs below it
	var hip := -1
	var spine0 := -1
	var legs := []
	var up := Vector3.UP
	var node: int = roots[0]
	while true:
		var ks: Array = (kids[node] as Array).duplicate()
		if ks.is_empty():
			break
		ks.sort_custom(func(a, b): return _subtree(kids, a, sm) > _subtree(kids, b, sm))
		if ks.size() >= 3:
			var s0: int = ks[0]
			var cen := Vector3.ZERO
			var cnt := 0
			var stack := [s0]
			while not stack.is_empty():
				var c: int = stack.pop_back()
				cen += pos[c]
				cnt += 1
				stack.append_array(kids[c])
			var u: Vector3 = (cen / cnt - (pos[node] as Vector3))
			if u.length() > 1e-6:
				u = u.normalized()
				var cands := []
				for k in ks.slice(1):
					if _subtree(kids, k, sm) < 3:
						continue
					var tip: int = _chain(kids, k, hm, sm)[-1]
					var v: Vector3 = (pos[tip] as Vector3) - (pos[node] as Vector3)
					if v.length() > 1e-6 and v.dot(u) < -0.3 * v.length():
						cands.append(k)
				var pr := _pair_across(pos, pos[node], u, cands, size)
				if not pr.is_empty():
					hip = node
					spine0 = s0
					legs = pr
					up = u
					break
		node = ks[0]
	if hip < 0:
		res["why"] = "no bone where a spine and two mirrored legs meet"
		return _geo_done(src, res)
	var mp: Dictionary = res["map"]
	var how: Dictionary = res["how"]
	mp["pelvis"] = hip
	# the spine up to the shoulders: the first bone with 3 or more children (two arms and a neck)
	var chain := [spine0]
	var jn := spine0
	var arms := []
	var neck0 := -1
	while true:
		var ks2: Array = kids[jn]
		if ks2.size() >= 3:
			var cands2 := []
			for k in ks2:
				if _subtree(kids, k, sm) >= 3:
					cands2.append(k)
			var pa := _pair_across(pos, pos[jn], up, cands2, size)
			if not pa.is_empty():
				arms = pa
				var bestn := -1
				var bu := -INF
				for k in cands2:
					if k in pa:
						continue
					var d: float = ((pos[k] as Vector3) - (pos[jn] as Vector3)).dot(up)
					if d > bu:
						bu = d
						bestn = k
				neck0 = bestn
				break
		if ks2.is_empty():
			break
		var nxt := -1
		for k in ks2:
			if nxt < 0 or _subtree(kids, k, sm) > _subtree(kids, nxt, sm):
				nxt = k
		jn = nxt
		chain.append(jn)
	if arms.is_empty():
		res["why"] = "no shoulders: no bone where two mirrored arms and a neck meet"
	else:
		var cn: int = chain.size()
		if cn == 1:
			mp["spine_03"] = chain[0]
		elif cn == 2:
			mp["spine_01"] = chain[0]
			mp["spine_03"] = chain[1]
		else:
			mp["spine_01"] = chain[0]
			mp["spine_02"] = chain[cn / 2]
			mp["spine_03"] = chain[cn - 1]
	# forward (foot -> toe, flat) then left = up x forward
	var fwd := Vector3.ZERO
	for lg in legs:
		var lc := _chain(kids, lg, hm, sm)
		if lc.size() >= 4:
			var d: Vector3 = (pos[lc[3]] as Vector3) - (pos[lc[2]] as Vector3)
			fwd += d - up * d.dot(up)
	if fwd.length() < 1e-6:
		fwd = Vector3.BACK - up * Vector3.BACK.dot(up)
		if fwd.length() < 1e-3:
			fwd = Vector3.DOWN - up * Vector3.DOWN.dot(up)
	fwd = fwd.normalized()
	var left := up.cross(fwd).normalized()
	var side_of := func(b: int) -> String:
		return "_l" if ((pos[b] as Vector3) - (pos[hip] as Vector3)).dot(left) > 0.0 else "_r"
	for lg in legs:
		var sd: String = side_of.call(lg)
		var lc2 := _chain(kids, lg, hm, sm)
		var jn2 := ["thigh", "calf", "foot", "ball"]
		for k in mini(4, lc2.size()):
			mp[jn2[k] + sd] = lc2[k]
	for a in arms:
		var sd2: String = side_of.call(a)
		var ac := _chain(kids, a, hm, sm)
		var h := ac.size() - 1
		for k in ac.size():
			if (kids[ac[k]] as Array).size() >= 3:
				h = k
				break
		if h >= 2:
			mp["hand" + sd2] = ac[h]
			mp["lowerarm" + sd2] = ac[h - 1]
			mp["upperarm" + sd2] = ac[h - 2]
			if h >= 3:
				mp["clavicle" + sd2] = ac[h - 3]
	if neck0 >= 0:
		var nc := _chain(kids, neck0, hm, sm)
		var topj: int = chain[-1]
		var last: int = nc[-1]
		var rise := ((pos[last] as Vector3) - (pos[topj] as Vector3)).dot(up) / size
		var hd := nc.size() - 1
		if rise > HEAD_TOP_FRAC and nc.size() >= 2:
			hd = nc.size() - 2   # the last bone is the head's top: an end
		mp["head"] = nc[hd]
		if hd >= 1:
			mp["neck_01"] = nc[0]
	for j in mp:
		how[j] = "geometry"
	return _geo_done(src, res)


static func _geo_done(src: Dictionary, res: Dictionary) -> Dictionary:
	var main := 0
	var miss := []
	for j in Body.ORDER:
		if (res["map"] as Dictionary).has(j):
			main += 1 if j in AnimImport.MAIN else 0
		else:
			miss.append(j)
	res["main"] = main
	res["missing"] = miss
	res["unmapped"] = _unmapped(src, res["map"])
	return res


## the mapping's plain-words report: how it was found and what is left over
static func report(src: Dictionary, mapping: Dictionary) -> String:
	var un: Array = _unmapped(src, mapping["map"])
	var miss: Array = (mapping["missing"] as Array).filter(func(j): return j in AnimImport.MAIN)
	var s := "%d of %d main joints matched by %s" % [mapping["main"], AnimImport.MAIN.size(), mapping.get("method", "name")]
	if not miss.is_empty():
		s += "; no bone for " + ", ".join(PackedStringArray(miss))
	if not un.is_empty():
		s += "; %d bone%s not mapped (%s%s)" % [un.size(), "" if un.size() == 1 else "s", ", ".join(PackedStringArray(un.slice(0, 6))), "..." if un.size() > 6 else ""]
	return s


## ---- 3. FIT: the rest-pose alignment ---------------------------------------------------------------------------------------
## {"ok", "why", "C" (source space -> Kine space), "ratio" (Kine leg / source leg), "roff" {joint: turn from Kine's rest bone
## direction to the file's, in Kine space}, "rest_deg", "rq" (each bone's rest rotation in the scene's space), "base_q", "up"}
static func fit(src: Dictionary, mapping: Dictionary, B: Body) -> Dictionary:
	var mp: Dictionary = mapping["map"]
	if not mp.has("pelvis"):
		return _fail("no bone could be matched to the hips")
	if int(mapping["main"]) < MAIN_NEED:
		return _fail("only %d of the %d main body bones could be matched" % [mapping["main"], AnimImport.MAIN.size()])
	var rest: Array = src["rest"]
	var parent: Array = src["parent"]
	var sp := {}
	for j in mp:
		sp[j] = (rest[mp[j]] as Transform3D).origin
	var kp := {}
	for j in Body.ORDER:
		kp[j] = B.p0[j]
	var Fs := AnimImport._frame(sp)
	var Fk := AnimImport._frame(kp)
	var C := (Fk * Fs.inverse()).get_rotation_quaternion()
	var leg_s := AnimImport._leg(sp)
	var leg_k := AnimImport._leg(kp)
	var ratio := leg_k / leg_s if leg_s > 1e-6 else 1.0
	var kids := _kids_of(parent)
	var roff := {}
	var rest_deg := {}
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
		elif (kids[b] as Array).size() == 1:
			end = (rest[kids[b][0]] as Transform3D).origin
		if end == null:
			continue
		var ds: Vector3 = C * ((end as Vector3) - (rest[b] as Transform3D).origin)
		var dk: Vector3 = (B.e0[j] as Vector3) - (B.p0[j] as Vector3)
		if ds.length() < 1e-6:
			continue
		roff[j] = AnimImport._arc(dk, ds)
		rest_deg[j] = snappedf(rad_to_deg((roff[j] as Quaternion).get_angle()), 0.1)
	var rq := []
	for x in rest:
		rq.append((x as Transform3D).basis.get_rotation_quaternion())
	var base: Transform3D = src.get("base", Transform3D.IDENTITY)
	return {"ok": true, "why": "", "C": C, "ratio": ratio, "roff": roff, "rest_deg": rest_deg, "rq": rq,
		"base_q": base.basis.orthonormalized().get_rotation_quaternion(), "up": Fs.y, "leg_s": leg_s, "leg_k": leg_k}


## the character's own proportions as a Kine `body` dict (Proportions): each segment's length over the default body's, and
## the stature that makes the segments come out at exactly those lengths. {} when it is the default body (or too little is mapped).
static func body_dict(src: Dictionary, mapping: Dictionary, B: Body) -> Dictionary:
	var mp: Dictionary = mapping["map"]
	var rest: Array = src["rest"]
	var sp := {}
	for j in mp:
		sp[j] = (rest[mp[j]] as Transform3D).origin
	var d0 := Proportions.default_lengths()
	var fs := AnimImport._frame(sp)
	var up: Vector3 = fs.y
	var k := {}
	var seg := func(a: String, b: String, name: String):
		var vals := []
		for sd in ["_l", "_r"]:
			if sp.has(a + sd) and sp.has(b + sd):
				vals.append((sp[a + sd] as Vector3).distance_to(sp[b + sd]))
		if not vals.is_empty():
			var m := 0.0
			for v in vals:
				m += float(v)
			k[name] = m / vals.size() / float(d0[name])
	seg.call("upperarm", "lowerarm", "upper_arm")
	seg.call("lowerarm", "hand", "forearm")
	seg.call("thigh", "calf", "thigh")
	seg.call("calf", "foot", "shank")
	if sp.has("upperarm_l") and sp.has("thigh_l"):
		var tr := ((sp["upperarm_l"] as Vector3) - (sp["thigh_l"] as Vector3)).dot(up)
		if tr > 1e-3:
			k["trunk"] = tr / float(d0["trunk"])
	if k.size() < 3:
		return {}
	var sc := {}
	for s in k:
		sc[s] = snappedf(clampf(float(k[s]), 0.5, 2.0), 0.0001)
	# the stature that gives g = 1 (the segment lengths are then exactly default x scale): measured on a scratch body at stature 1
	var tmp := Body.new()
	tmp.load_files(B._files[0], B._files[1])
	tmp.set_proportions({"stature": 1.0, "scale": sc})
	var g: float = float(tmp.seg_s["foot_l"]) / float(sc.get("foot", 1.0))
	var nat := snappedf(clampf(1.0 / g, 0.5, 2.5), 0.0001)
	return Proportions.clean({"stature": nat, "scale": sc})


## ---- 4. POSE ---------------------------------------------------------------------------------------------------------------
## Kine's pose B (G, P) onto the imported skeleton. Mapped bones: world rotation Ci * (G roff^-1) * C * rest; the hips at
## Ci * P[pelvis] / ratio; every other bone keeps its rest rotation under its (posed) parent.
static func pose(ch: Dictionary, mapping: Dictionary, ft: Dictionary, B: Body) -> void:
	var sk: Skeleton3D = ch["sk"]
	var src: Dictionary = ch["src"]
	var parent: Array = src["parent"]
	var n := parent.size()
	var mp: Dictionary = mapping["map"]
	var who := {}
	for j in mp:
		who[int(mp[j])] = j
	var C: Quaternion = ft["C"]
	var Ci := C.inverse()
	var rq: Array = ft["rq"]
	var roff: Dictionary = ft["roff"]
	var bq: Quaternion = ft["base_q"]
	var base: Transform3D = src.get("base", Transform3D.IDENTITY)
	var ratio: float = ft["ratio"]
	var W := []
	var SQ := []
	var GT := []
	W.resize(n)
	SQ.resize(n)
	GT.resize(n)
	for i in AnimImport._order(parent):
		var p := int(parent[i])
		var wq: Quaternion
		if who.has(i):
			var j: String = who[i]
			var D: Quaternion = (B.G[j] as Quaternion) * (roff[j] as Quaternion).inverse()
			wq = (Ci * D * C * (rq[i] as Quaternion)).normalized()
		elif p < 0:
			wq = rq[i]
		else:
			wq = ((W[p] as Quaternion) * (rq[p] as Quaternion).inverse() * (rq[i] as Quaternion)).normalized()
		W[i] = wq
		var sq: Quaternion = (bq.inverse() * wq).normalized()
		SQ[i] = sq
		var rest: Transform3D = sk.get_bone_rest(i)
		var scl := rest.basis.get_scale()
		var local_q: Quaternion = sq if p < 0 else (SQ[p] as Quaternion).inverse() * sq
		var org: Vector3 = rest.origin
		if who.has(i) and who[i] == "pelvis":
			var t_root: Vector3 = Ci * (B.P["pelvis"] as Vector3) / ratio if ratio > 1e-6 else Ci * (B.P["pelvis"] as Vector3)
			var t_sk: Vector3 = base.affine_inverse() * t_root
			org = t_sk if p < 0 else (GT[p] as Transform3D).affine_inverse() * t_sk
		var loc := Transform3D(Basis(local_q) * Basis.from_scale(scl), org)
		GT[i] = loc if p < 0 else (GT[p] as Transform3D) * loc
		sk.set_bone_pose(i, loc)


## each bone's rotation in the scene's space as the skeleton is posed now (composed from the local poses, parents first)
static func world_rots(ch: Dictionary) -> Array:
	var sk: Skeleton3D = ch["sk"]
	var src: Dictionary = ch["src"]
	var bq: Quaternion = (src.get("base", Transform3D.IDENTITY) as Transform3D).basis.orthonormalized().get_rotation_quaternion()
	var n := sk.get_bone_count()
	var g := []
	g.resize(n)
	var out := []
	out.resize(n)
	for i in n:
		var p := sk.get_bone_parent(i)
		g[i] = sk.get_bone_pose(i) if p < 0 else (g[p] as Transform3D) * sk.get_bone_pose(i)
		out[i] = (bq * (g[i] as Transform3D).basis.orthonormalized().get_rotation_quaternion()).normalized()
	return out


## ---- 5. SKIN, WEIGHTS, SHAPES ----------------------------------------------------------------------------------------------
## the mesh's vertices skinned by plain linear blending with the skeleton as posed now, in the skeleton's space:
## [per surface PackedVector3Array]. (Written here, not Godot's: the bars measure the file, not the engine.)
static func skin_points(sk: Skeleton3D, mi: MeshInstance3D, extra := {}) -> Array:
	var sn := mi.skin
	var mats := DqSkin.bind_mats(sk, sn)
	var am := mi.mesh as ArrayMesh
	var out := []
	for si in am.get_surface_count():
		var arr := am.surface_get_arrays(si)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		if extra.has(si):
			var ex: PackedVector3Array = extra[si]
			vs = vs.duplicate()
			for i in vs.size():
				vs[i] += ex[i]
		var bo: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var w: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var per := bo.size() / maxi(vs.size(), 1)
		var pts := PackedVector3Array()
		pts.resize(vs.size())
		for i in vs.size():
			var acc := Vector3.ZERO
			var ws := 0.0
			for k in per:
				var wk := w[i * per + k]
				if wk > 0.0:
					acc += (mats[bo[i * per + k]] as Transform3D) * vs[i] * wk
					ws += wk
			pts[i] = acc if ws > 0.0 else vs[i]
		out.append(pts)
	return out


## per surface, per vertex: {bone NAME: weight} (only weights above 1e-6), so two files compare by bone, not by index
static func weights_of(sk: Skeleton3D, mi: MeshInstance3D) -> Array:
	var sn := mi.skin
	var am := mi.mesh as ArrayMesh
	var nm := []
	for k in sn.get_bind_count():
		nm.append(sk.get_bone_name(SkinPaint.bind_bone(sn, sk, k)))
	var out := []
	for si in am.get_surface_count():
		var arr := am.surface_get_arrays(si)
		var bo: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var w: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var nv := (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var per := bo.size() / maxi(nv, 1)
		var rows := []
		for i in nv:
			var d := {}
			for k in per:
				if w[i * per + k] > 1e-6:
					var b: String = nm[bo[i * per + k]]
					d[b] = float(d.get(b, 0.0)) + w[i * per + k]
			rows.append(d)
		out.append(rows)
	return out


## {shape name: [per surface PackedVector3Array of vertex DELTAS]} whatever the mesh's blend mode (relative or normalized)
static func shapes_of(mi: MeshInstance3D) -> Dictionary:
	var am := mi.mesh as ArrayMesh
	var out := {}
	var rel := am.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_RELATIVE
	for bi in am.get_blend_shape_count():
		var per := []
		for si in am.get_surface_count():
			var bs := am.surface_get_blend_shape_arrays(si)
			var d: PackedVector3Array = (bs[bi] as Array)[Mesh.ARRAY_VERTEX]
			if not rel:
				var base: PackedVector3Array = am.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
				var dd := PackedVector3Array()
				dd.resize(d.size())
				for i in d.size():
					dd[i] = d[i] - base[i]
				d = dd
			per.append(d)
		out[String(am.get_blend_shape_name(bi))] = per
	return out


## ---- 6. THE SCENE KEEPS IT -----------------------------------------------------------------------------------------------
## {"path", "pairs": {joint: bone name}, "method"}: written under the scene's "charimp" key; from_key reads it back against a
## freshly loaded character (a bone no longer in the file is dropped, the rest of the map stands)
static func to_key(ch: Dictionary, mapping: Dictionary) -> Dictionary:
	var names: Array = ch["src"]["names"]
	var pr := {}
	for j in mapping["map"]:
		pr[j] = String(names[mapping["map"][j]])
	return {"path": String(ch.get("path", "")), "pairs": pr, "method": String(mapping.get("method", "name"))}


static func from_key(src: Dictionary, key: Dictionary) -> Dictionary:
	var at := {}
	for i in (src["names"] as Array).size():
		at[String(src["names"][i])] = i
	var m := {"map": {}, "how": {}, "method": String(key.get("method", "name"))}
	var pr: Dictionary = key.get("pairs", {})
	for j in pr:
		if Body.ORDER.has(j) and at.has(String(pr[j])):
			m["map"][j] = at[String(pr[j])]
			m["how"][j] = "saved"
	return _geo_done(src, m)
