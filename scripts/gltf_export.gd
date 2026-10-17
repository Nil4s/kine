## THE UNIVERSAL EXPORT (round 34, GATES OO1; Nick 10-16: "universal files to use in all engines, not only in our
## game"). A scene -> glTF 2.0 binary (.glb): the Khronos open standard Godot, Blender and Unreal 5 import natively
## (Unity through glTFast). The mannequin the app shows (assets/mannequin.glb, CC0), one animation named after the
## file, a key on every frame at the scene's fps: every one of our joints' local rotation (Body.gltf_local, the same
## numbers Overlays.pose_skeleton puts on screen) and the pelvis's position; the bones are named as UE5's Mannequin
## (the mannequin's "Head" written "head"). The weapons are animated nodes "weapon" / "weapon2" carrying their world
## motion (knob at the origin, the shaft along +Y), each with a plain shaft mesh. Written by Godot's own GLTFDocument.
class_name GltfExport
extends RefCounted


## the scene as a node tree ready for GLTFDocument (B is posed through the scene; its state is put back)
static func build(S: Scene, B: Body, anim_name: String, with_mesh := true) -> Node3D:
	var keep := B.state()
	var man: Node3D = (load("res://assets/mannequin.glb") as PackedScene).instantiate()
	man.name = "mannequin"   # not the animation's name: the importer makes names unique and would rename the clip "<name>2"
	for ap in man.find_children("*", "AnimationPlayer", true, false):
		ap.get_parent().remove_child(ap)
		ap.free()
	if not with_mesh:
		for mi in man.find_children("*", "MeshInstance3D", true, false):
			mi.get_parent().remove_child(mi)
			mi.free()
	var sk: Skeleton3D = man.find_children("*", "Skeleton3D", true, false)[0]
	var sk_path := String(man.get_path_to(sk))
	var anim := Animation.new()
	anim.length = S.length()
	var rot := {}
	for j in Body.ORDER:
		if sk.find_bone("Head" if j == "head" else j) < 0:
			continue
		var tr := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(tr, NodePath("%s:%s" % [sk_path, "Head" if j == "head" else j]))
		rot[j] = tr
	var pos := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(pos, NodePath("%s:pelvis" % sk_path))
	# the weapons: present when the scene ever holds one
	var wtr := {}
	for w in ["weapon", "weapon2"]:
		var used := false
		for c in S.cards:
			used = used or not (c["pose"].get(w, {}) as Dictionary).is_empty()
		if not used:
			continue
		var node := Node3D.new()
		node.name = w
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
		anim.track_set_path(tp, NodePath(w))
		var tq := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(tq, NodePath(w))
		var ts := anim.add_track(Animation.TYPE_SCALE_3D)
		anim.track_set_path(ts, NodePath(w))
		wtr[w] = [tp, tq, ts, shaft]
	var fps: float = maxf(1.0, S.fps)
	var n := int(ceil(S.length() * fps - 1e-6))
	for k in n + 1:
		var t := minf(k / fps, S.length())
		S.apply(B, t)
		for j in rot:
			anim.rotation_track_insert_key(rot[j], t, B.gltf_local(j))
		anim.position_track_insert_key(pos, t, B.gltf_pelvis_pos())
		for w in wtr:
			var on: bool = B.wep_on if w == "weapon" else B.wep2_on
			var x: Array = (B.wep_xform() if w == "weapon" else B.wep2_xform()) if on else [Vector3.ZERO, Quaternion.IDENTITY]
			anim.position_track_insert_key(wtr[w][0], t, x[0])
			anim.rotation_track_insert_key(wtr[w][1], t, x[1])
			# a weapon put away is scaled to nothing (glTF has no "visible" channel)
			anim.scale_track_insert_key(wtr[w][2], t, Vector3.ONE if on else Vector3.ZERO)
	# each shaft's length: the scene's (a weapon keeps its kind through a scene)
	B.set_state(keep)
	for w in wtr:
		var L := 0.84
		for c in S.cards:
			var d: Dictionary = c["pose"].get(w, {})
			if not d.is_empty():
				L = float(d.get("length", Body.KINDS.get(String(d.get("kind", "dagger")), {"len": 0.3})["len"]))
				break
		var shaft: MeshInstance3D = wtr[w][3]
		(shaft.mesh as CylinderMesh).height = L
		shaft.position = Vector3(0, L * 0.5, 0)
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	man.add_child(ap)
	var lib := AnimationLibrary.new()
	lib.add_animation(anim_name, anim)
	ap.add_animation_library("", lib)
	B.set_state(keep)
	return man


## write the scene as a .glb at path (res:// or absolute); OK or the error
static func write(S: Scene, B: Body, path: String, with_mesh := true) -> Error:
	var nm := path.get_file().get_basename()
	var root := build(S, B, nm, with_mesh)
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_scene(root, st)
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
