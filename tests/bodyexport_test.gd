## godot --path . -s tests/bodyexport_test.gd     (ROADMAP_400 G12 the body as .glb with skin weights; needs a window: main)
## The fighter's body (edited: one forearm triangle extruded and applied, so the export carries G01's new vertices) written
## by "Model: export the body as glb (skin weights)", then read back with Godot's own GLTFDocument. Bars, stated before the run:
##   - VERTEX COUNT, the split rule: the file holds one vertex per distinct (KMesh vertex, UV) per surface (a vertex on a UV
##     seam is written once per side; normals are smooth per vertex so they never split one). So: the file's vertex count
##     equals that count (BaseBody.build's), and the file's distinct positions are exactly the KMesh's vertices (every one
##     present, nothing else)
##   - WEIGHTS: every file vertex, matched to its KMesh vertex by position, has the same bones (by name) and each weight
##     within 1/65535 of what Kine writes (the 4 heaviest, in whole 16-bit steps adding to 1)
##   - SKELETON: the file's skeleton has every UE5 mannequin core bone name (EngineExport.UE5_CORE: root, pelvis, spine_01..,
##     head, clavicle / upperarm / lowerarm / hand, thigh / calf / foot / ball, both sides)
##   - POSE: the right elbow bent 90 deg in Kine (instrument: the forearm bone turns 90 +- 2 deg, and the forearm vertices
##     move more than 5 cm in Kine AND in the file); the file's skeleton given the same bone poses moves every forearm vertex
##     (lowerarm_r weight >= 0.5) by the same displacement as Kine's skin, within 1 mm (linear blend skinning with the file's
##     own skin and bind poses)
## FBX is not written for the body (scripts/body_export.gd says why); this test has no fbx bar.
extends SceneTree

var fails := 0
var m: Node
const OUT := "user://bodyexport_test"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func key(k: int) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	root.push_input(e)
	var u := e.duplicate() as InputEventKey
	u.pressed = false
	root.push_input(u)


func cmd(name: String) -> void:
	for c in m._commands():
		if c["name"] == name:
			(c["run"] as Callable).call()
			return
	ok(false, "command '%s' is in the registry" % name)


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func ue(nm: String) -> String:
	return "head" if nm == "Head" else nm


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle()
	var skin := BaseBody.skin_of(m)
	# ---- an edited body: one forearm triangle extruded in the model preview, applied
	cmd("Model: edit the body mesh")
	await idle(1)
	var km: KMesh = m.kmed.mesh
	var la := km.attr_data("skin:lowerarm_r") as PackedFloat32Array
	var best := -1
	var bw := -1.0
	for fi in km.faces.size():
		var mn := 1.0
		for v in (km.faces[fi] as PackedInt32Array):
			mn = minf(mn, la[v])
		if mn > bw:
			bw = mn
			best = fi
	key(KEY_3)
	await idle(1)
	m.kmed.sel.faces = {best: true}
	key(KEY_E)
	await idle(1)
	cmd("Model: apply the body mesh to the fighter")
	await idle(1)
	key(KEY_ESCAPE)
	await idle()
	var k := BaseBody.read(m)
	print("info: the body: %d verts, %d faces" % [k.verts.size(), k.faces.size()])

	# ---- export through the command
	var path := BodyExport.export_cmd(m, OUT)
	ok(path != "" and FileAccess.file_exists(path), "Model: export the body as glb wrote %s" % path)
	var srcs := []
	for si in 2:
		srcs.append({"mat": null})
	var want := BaseBody.build(k, skin, m.skel, srcs)
	var nwant := 0
	for s in want["surfs"]:
		nwant += (s["arr"][Mesh.ARRAY_VERTEX] as PackedVector3Array).size()

	# ---- read it back with GLTFDocument
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_file(ProjectSettings.globalize_path(path), st)
	ok(err == OK, "GLTFDocument reads the file back (%s)" % error_string(err))
	var scn: Node = doc.generate_scene(st)
	root.add_child(scn)
	await idle()
	var isk: Skeleton3D = scn.find_children("*", "Skeleton3D", true, false)[0]
	var imi: MeshInstance3D = null
	for n in scn.find_children("*", "MeshInstance3D", true, false):
		if (n as MeshInstance3D).skin != null:
			imi = n
	ok(imi != null, "the file holds a skinned mesh (%s)" % (imi.name if imi else "none"))
	var iskin: Skin = imi.skin
	var bind_name := []
	for q in iskin.get_bind_count():
		var nm := String(iskin.get_bind_name(q))
		if nm == "" and iskin.get_bind_bone(q) >= 0:
			nm = isk.get_bone_name(iskin.get_bind_bone(q))
		bind_name.append(nm)
	var bind_bone := []
	for q in iskin.get_bind_count():
		bind_bone.append(iskin.get_bind_bone(q) if iskin.get_bind_bone(q) >= 0 else isk.find_bone(bind_name[q]))

	# ---- vertex count
	var at := {}
	for v in k.verts.size():
		at[k.verts[v]] = v
	var gv := PackedVector3Array()
	var gb := PackedInt32Array()
	var gw := PackedFloat32Array()
	var per := 4
	var am := imi.mesh as ArrayMesh
	for si in am.get_surface_count():
		var a := am.surface_get_arrays(si)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var bs: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var ws: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
		per = bs.size() / maxi(1, vs.size())
		gv.append_array(vs)
		gb.append_array(bs)
		gw.append_array(ws)
	var seen := {}
	var stray := 0
	for p in gv:
		if at.has(p):
			seen[at[p]] = true
		else:
			stray += 1
	print("info: the file: %d surfaces, %d verts (%d influences each); the KMesh %d verts; built %d" % [am.get_surface_count(), gv.size(), per, k.verts.size(), nwant])
	ok(gv.size() == nwant, "VERTEX COUNT: the file has %d vertices = one per distinct (vertex, UV) per surface (%d); the KMesh has %d" % [gv.size(), nwant, k.verts.size()])
	ok(stray == 0 and seen.size() == k.verts.size(), "VERTEX COUNT: the file's positions are exactly the KMesh's %d vertices (%d present, %d not in the KMesh)" % [k.verts.size(), seen.size(), stray])

	# ---- weights
	var kw := BaseBody.weights_of(k, skin)
	var worst := 0.0
	var worst_steps := 0
	var off_steps := 0   # weights one or more 16-bit steps away
	var nweights := 0
	var bonesdiff := 0
	for i in gv.size():
		var v: int = at.get(gv[i], -1)
		if v < 0:
			continue
		var exp := {}
		for b in BaseBody.canon(BaseBody.fit4(kw[v])):
			exp[ue(String(skin.get_bind_name(b)))] = float(BaseBody.canon(BaseBody.fit4(kw[v]))[b])
		var got := {}
		for q in per:
			var w := gw[i * per + q]
			if w > 0.0:
				var nm := ue(String(bind_name[gb[i * per + q]]))
				got[nm] = float(got.get(nm, 0.0)) + w
		var ke := exp.keys()
		ke.sort()
		var kg := got.keys()
		kg.sort()
		if ke != kg:
			bonesdiff += 1
			continue
		for nm in ke:
			worst = maxf(worst, absf(float(exp[nm]) - float(got[nm])))
			var ds := absi(roundi(float(exp[nm]) * 65535.0) - roundi(float(got[nm]) * 65535.0))
			worst_steps = maxi(worst_steps, ds)
			off_steps += 1 if ds > 0 else 0
			nweights += 1
	# compared in whole steps: a float32 cannot hold k/65535 exactly (near 0.5 its spacing is 0.002 of a step), so the raw
	# difference of a one-step weight reads a hair over 1/65535; the bar is one step
	print("info: %d of %d weights are a step off; the raw worst difference %.9f (%.4f steps)" % [off_steps, nweights, worst, worst * 65535.0])
	ok(bonesdiff == 0 and worst_steps <= 1 and worst <= 1.01 / 65535.0, "WEIGHTS: every vertex has the same bones by name (%d differ), each weight within 1/65535 (worst %d step)" % [bonesdiff, worst_steps])

	# ---- the UE5 names
	var names := {}
	for i in isk.get_bone_count():
		names[isk.get_bone_name(i)] = true
	var missing := EngineExport.UE5_CORE.filter(func(n): return not names.has(n))
	ok(missing.is_empty(), "SKELETON: the file's %d bones include all %d UE5 core names (missing %s)" % [isk.get_bone_count(), EngineExport.UE5_CORE.size(), missing])

	# ---- the 90 deg elbow
	var fore := []   # KMesh vertices weighted mostly to the forearm
	var b_la := -1
	for q in skin.get_bind_count():
		if skin.get_bind_name(q) == "lowerarm_r":
			b_la = q
	for v in k.verts.size():
		if float(BaseBody.canon(BaseBody.fit4(kw[v])).get(b_la, 0.0)) >= 0.5:
			fore.append(v)
	# where each one is in Kine's weight model (the fighter's skin as drawn) and in the file
	var hits := []
	for v in fore:
		var h = null
		for si in m.wp["surfs"].size():
			var f: int = (m.wp["surfs"][si]["verts"] as PackedVector3Array).find(k.verts[v])
			if f >= 0:
				h = [si, f]
				break
		hits.append(h)
	var gi := {}
	for i in gv.size():
		if not gi.has(gv[i]):
			gi[gv[i]] = i
	ok(fore.size() > 50 and not hits.has(null), "%d forearm vertices (lowerarm_r >= 0.5), every one found in Kine's skin" % fore.size())
	var sk: Skeleton3D = m.skel
	var la_b := SkinPaint.bind_bone(skin, sk, b_la)
	var hand_b := sk.find_bone("hand_r")
	var kine := []
	var glb := []
	var segs := []
	for ang in [0.0, 90.0]:
		m.B.ang["lowerarm_r"] = Vector3(ang, m.B.ang["lowerarm_r"].y, m.B.ang["lowerarm_r"].z)
		m._refresh()
		await idle(1)
		SkinPaint.refresh(m.wp)
		var inv := sk.global_transform.affine_inverse()
		segs.append([sk.get_bone_global_pose(la_b).origin, sk.get_bone_global_pose(hand_b).origin])
		var kp := []
		for h in hits:
			kp.append(inv * (m.wp["surfs"][h[0]]["pos"] as PackedVector3Array)[h[1]] if h != null else Vector3.ZERO)
		kine.append(kp)
		# the file's skeleton takes every bone's pose from Kine's, by name
		for b in sk.get_bone_count():
			var ib := isk.find_bone(ue(sk.get_bone_name(b)))
			if ib >= 0:
				isk.set_bone_pose(ib, sk.get_bone_pose(b))
		var mats := []
		for q in iskin.get_bind_count():
			mats.append(isk.get_bone_global_pose(bind_bone[q]) * iskin.get_bind_pose(q))
		var gp := []
		for v in fore:
			var i: int = gi[k.verts[v]]
			var p := Vector3.ZERO
			for q in per:
				var w := gw[i * per + q]
				if w > 0.0:
					p += (mats[gb[i * per + q]] as Transform3D) * gv[i] * w
			gp.append(p)
		glb.append(gp)
	var turn := rad_to_deg(((segs[0][1] - segs[0][0]) as Vector3).angle_to(segs[1][1] - segs[1][0]))
	var mk := 0.0
	var mg := 0.0
	var dev := 0.0
	var dabs := 0.0
	for i in fore.size():
		var dk: Vector3 = kine[1][i] - kine[0][i]
		var dg: Vector3 = glb[1][i] - glb[0][i]
		mk = maxf(mk, dk.length())
		mg = maxf(mg, dg.length())
		dev = maxf(dev, dk.distance_to(dg))
		dabs = maxf(dabs, (kine[1][i] as Vector3).distance_to(glb[1][i]))
	ok(absf(turn - 90.0) <= 2.0, "INSTRUMENT: the forearm bone turned %.1f deg between elbow 0 and 90" % turn)
	ok(mk > 0.05 and mg > 0.05, "INSTRUMENT: the forearm vertices moved up to %.1f cm in Kine and %.1f cm in the file" % [mk * 100.0, mg * 100.0])
	ok(dev <= 0.001, "POSE: every forearm vertex moves the same in the file as in Kine within 1 mm (worst %.4f mm)" % (dev * 1000.0))
	print("info: posed positions (skeleton space) differ by at most %.4f mm" % (dabs * 1000.0))
	scn.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("bodyexport: %d failed" % fails)
	quit(1 if fails > 0 else 0)
