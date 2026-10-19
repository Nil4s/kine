## THE UNIVERSAL EXPORT (round 34, GATES OO1; Nick 10-16: "universal files to use in all engines, not only in our
## game"). A scene -> glTF 2.0 binary (.glb): the Khronos open standard Godot, Blender and Unreal 5 import natively
## (Unity through glTFast). The mannequin the app shows (assets/mannequin.glb, CC0), one animation named after the
## file, a key on every frame at the scene's fps: every one of our joints' local rotation (Body.gltf_local, the same
## numbers Overlays.pose_skeleton puts on screen) and the pelvis's position; the bones are named as UE5's Mannequin
## (the mannequin's "Head" written "head"). The weapons are animated nodes "weapon" / "weapon2" carrying their world
## motion (knob at the origin, the shaft along +Y), each with a plain shaft mesh. Written by Godot's own GLTFDocument.
class_name GltfExport
extends RefCounted


## the mannequin, its own AnimationPlayer (and, without with_mesh, its meshes) taken out
static func _mannequin(with_mesh: bool) -> Node3D:
	var man: Node3D = (load("res://assets/mannequin.glb") as PackedScene).instantiate()
	man.name = "mannequin"   # not the animation's name: the importer makes names unique and would rename the clip "<name>2"
	for ap in man.find_children("*", "AnimationPlayer", true, false):
		ap.get_parent().remove_child(ap)
		ap.free()
	if not with_mesh:
		for mi in man.find_children("*", "MeshInstance3D", true, false):
			mi.get_parent().remove_child(mi)
			mi.free()
	return man


## the scene as a node tree ready for GLTFDocument (B is posed through the scene; its state is put back)
static func build(S: Scene, B: Body, anim_name: String, with_mesh := true, root_motion := false) -> Node3D:
	var man := _mannequin(with_mesh)
	var sk: Skeleton3D = man.find_children("*", "Skeleton3D", true, false)[0]
	if B.body != S.body:
		B.set_proportions(S.body)   # PR2: the scene's own body (put back with the state at the end)
	Proportions.bake_mannequin(man, sk, B)   # the proportions in the file's rest skeleton and mesh (default: nothing)
	var anim := Animation.new()
	anim.length = S.length()
	_animate(S, B, man, anim, "", S.length(), float(S.fps), "", root_motion)
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	man.add_child(ap)
	var lib := AnimationLibrary.new()
	lib.add_animation(anim_name, anim)
	ap.add_animation_library("", lib)
	return man


## TWO CHARACTERS (round 50, GATES TC6): every actor in one file. actors = [{"name", "S", "B", "xf": Transform3D}]
## (actor 0 the hero, xf in the hero's space). A root "Kine" holds per actor "<name> placement" (at its xf) > "<name>
## mannequin" > the skeleton's parent renamed "<name>" (Blender's armature object takes that name) and the weapons
## "<name> weapon" / "<name> weapon2"; ONE
## animation (anim_name) carries every actor's tracks, each actor posed from its own scene over the same time range
## (0 .. the longest scene, at the hero's fps). Each body's state is put back.
static func build_actors(actors: Array, anim_name: String, with_mesh := true) -> Node3D:
	var root := Node3D.new()
	root.name = "Kine"
	var L := 0.0
	for a in actors:
		L = maxf(L, (a["S"] as Scene).length())
	var fps := float((actors[0]["S"] as Scene).fps)
	var anim := Animation.new()
	anim.length = L
	for a in actors:
		var nm := String(a["name"]).validate_node_name()
		var place := Node3D.new()
		place.name = nm + " placement"
		place.transform = a["xf"]
		root.add_child(place)
		var man := _mannequin(with_mesh)
		man.name = nm + " mannequin"
		place.add_child(man)
		var sk: Skeleton3D = man.find_children("*", "Skeleton3D", true, false)[0]
		var ab: Body = a["B"]
		if ab.body != (a["S"] as Scene).body:
			ab.set_proportions((a["S"] as Scene).body)   # PR2: each fighter's own body
		Proportions.bake_mannequin(man, sk, ab)
		sk.get_parent().name = nm   # the node Blender makes the armature from: the armature is named by the actor
		_animate(a["S"], a["B"], man, anim, String(root.get_path_to(man)) + "/", L, fps, nm + " ")
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	root.add_child(ap)
	var lib := AnimationLibrary.new()
	lib.add_animation(anim_name, anim)
	ap.add_animation_library("", lib)
	return root


## one actor's tracks into anim (paths prefixed by its node's path from the player's root), one key per frame over
## 0..L at fps; the weapon nodes added under man
static func _animate(S: Scene, B: Body, man: Node3D, anim: Animation, pre: String, L: float, fps_in: float, wpre := "", root_motion := false) -> void:
	var keep := B.state()
	var sk: Skeleton3D = man.find_children("*", "Skeleton3D", true, false)[0]
	var sk_path := pre + String(man.get_path_to(sk))
	var rot := {}
	for j in Body.ORDER:
		if sk.find_bone("Head" if j == "head" else j) < 0:
			continue
		var tr := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(tr, NodePath("%s:%s" % [sk_path, "Head" if j == "head" else j]))
		rot[j] = tr
	var pos := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(pos, NodePath("%s:pelvis" % sk_path))
	# ROOT MOTION (engine presets, engine_export.gd): the pelvis's horizontal travel moved onto the "root" bone (UE5 Manny's root
	# motion bone), so the pelvis keeps its height and its horizontal place. Off unless asked, and only with a root bone.
	var rtr := -1
	if root_motion and sk.find_bone("root") >= 0:
		rtr = anim.add_track(Animation.TYPE_POSITION_3D)
		anim.track_set_path(rtr, NodePath("%s:root" % sk_path))
	var P0 := Vector3.ZERO   # the pelvis at frame 0 (set in the key loop, after the first pose)
	# the weapons: present when the scene ever holds one
	var wtr := {}
	for w in ["weapon", "weapon2"]:
		var used := false
		for c in S.cards:
			used = used or not (c["pose"].get(w, {}) as Dictionary).is_empty()
		if not used:
			continue
		var node := Node3D.new()
		node.name = wpre + w
		man.add_child(node)
		var shaft := MeshInstance3D.new()
		shaft.name = w + "_shaft"
		var cm := CylinderMesh.new()
		cm.top_radius = 0.015
		cm.bottom_radius = 0.015
		cm.height = 1.0
		shaft.mesh = cm
		node.add_child(shaft)
		var tp := anim.add_track(Animation.TYPE_POSITION_3D)
		anim.track_set_path(tp, NodePath(pre + wpre + w))
		var tq := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(tq, NodePath(pre + wpre + w))
		var ts := anim.add_track(Animation.TYPE_SCALE_3D)
		anim.track_set_path(ts, NodePath(pre + wpre + w))
		wtr[w] = [tp, tq, ts, shaft]
	var fps: float = maxf(1.0, fps_in)
	var n := int(ceil(L * fps - 1e-6))
	for k in n + 1:
		var t := minf(k / fps, L)
		S.apply(B, t)
		for j in rot:
			anim.rotation_track_insert_key(rot[j], t, B.gltf_local(j))
		var pp := B.gltf_pelvis_pos()
		if rtr >= 0:
			# the scene's pelvis travel since frame 0, horizontal only (Y is the height, kept on the pelvis)
			if k == 0:
				P0 = B.P["pelvis"]
			var D: Vector3 = B.P["pelvis"] - P0
			var T := Vector3(D.x, 0.0, D.z)
			anim.position_track_insert_key(rtr, t, T)
			pp -= B.root_rot.inverse() * T   # the pelvis's local place with the travel taken off it
		anim.position_track_insert_key(pos, t, pp)
		for w in wtr:
			var on: bool = B.wep_on if w == "weapon" else B.wep2_on
			var x: Array = (B.wep_xform() if w == "weapon" else B.wep2_xform()) if on else [Vector3.ZERO, Quaternion.IDENTITY]
			anim.position_track_insert_key(wtr[w][0], t, x[0])
			anim.rotation_track_insert_key(wtr[w][1], t, x[1])
			# a weapon put away is scaled to nothing (glTF has no "visible" channel)
			anim.scale_track_insert_key(wtr[w][2], t, Vector3.ONE if on else Vector3.ZERO)
	# quaternion sign continuity (RotClean.hemisphere, ROADMAP 64): every rotation key has dot >= 0 with the one before it,
	# so an engine's interpolation takes the short way round (q and -q are the same rotation)
	for tr in anim.get_track_count():
		if anim.track_get_type(tr) == Animation.TYPE_ROTATION_3D:
			_hemi(anim, tr)
	# each shaft's length: the scene's (a weapon keeps its kind through a scene)
	B.set_state(keep)
	for w in wtr:
		var WL := 0.84
		for c in S.cards:
			var d: Dictionary = c["pose"].get(w, {})
			if not d.is_empty():
				WL = float(d.get("length", Body.KINDS.get(String(d.get("kind", "dagger")), {"len": 0.3})["len"]))
				break
		var shaft: MeshInstance3D = wtr[w][3]
		(shaft.mesh as CylinderMesh).height = WL
		shaft.position = Vector3(0, WL * 0.5, 0)


## write the scene as a .glb at path (res:// or absolute); OK or the error
## the rotation keys of one track made sign-continuous in place (RotClean.hemisphere)
static func _hemi(anim: Animation, tr: int) -> void:
	var qs := []
	for k in anim.track_get_key_count(tr):
		qs.append(anim.track_get_key_value(tr, k))
	var hq: Array = RotClean.hemisphere(qs, true)
	for k in hq.size():
		anim.track_set_key_value(tr, k, hq[k])


static func write(S: Scene, B: Body, path: String, with_mesh := true) -> Error:
	var err := _write(build(S, B, path.get_file().get_basename(), with_mesh), path)
	if err == OK and not S.attrs.is_empty():
		# ROADMAP 82: the custom attributes as node extras ("poser_attrs") on the part's node; no attrs = the file as before
		var abs := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
		err = CustomAttr.add_glb_extras(abs, S.attrs)["err"]
	if err == OK and not S.markers.is_empty():
		# ROADMAP 97: the markers (name, kind, t, frame, note, color) as extras "poser_markers" on the animation
		var abs_m := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
		err = Markers.add_glb_extras(abs_m, S.markers, S.fps)
	return err


## every actor in one .glb at path (build_actors); OK or the error
static func write_actors(actors: Array, path: String, with_mesh := true) -> Error:
	return _write(build_actors(actors, path.get_file().get_basename(), with_mesh), path, true)


static func _write(root: Node3D, path: String, bone_names := false) -> Error:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_scene(root, st)
	# TC6: the exporter makes node names unique across the FILE, so a second skeleton's bones came out "pelvis2",
	# "Head2" (Blender then finds no "pelvis" on it); a bone's name only has to be unique in its own skeleton
	if bone_names:
		var nodes := st.get_nodes()
		for gs in st.get_skeletons():
			var sk := (gs as GLTFSkeleton).get_godot_skeleton()
			var bn: Dictionary = (gs as GLTFSkeleton).get_godot_bone_node()
			for b in bn:
				var nd: GLTFNode = nodes[bn[b]]
				nd.resource_name = sk.get_bone_name(b)
				nd.original_name = sk.get_bone_name(b)
	# the head bone as UE5 names it: renamed in the file, not in the Skeleton3D (Godot 4.7's exporter drops a bone
	# renamed there: 65 bones in, 64 out)
	for nd in st.get_nodes():
		if (nd as GLTFNode).resource_name == "Head":
			nd.resource_name = "head"
			nd.original_name = "head"
	if err == OK:
		var abs := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
		DirAccess.make_dir_recursive_absolute(abs.get_base_dir())
		err = doc.write_to_filesystem(st, abs)
	root.free()
	return err
