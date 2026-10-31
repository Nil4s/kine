## godot --path . -s tests/p149animglb_test.gd     (Friday plan 149: the edited character + its animation as one .glb; needs a window: main)
## A body edit (one forearm triangle extruded, applied to the fighter), a scene with a move (combo3), then the Export dialog's
## "My edited character + animation (GLB)" target, then the file READ BACK with Godot's GLTFDocument. Bars, written before the run:
##   - the target is NOT in the dialog before a body is applied (7 targets), and is there after (8)
##   - SKELETON: the file's bone count equals the live mannequin's, and every live bone name is in the file ("Head" is written "head")
##   - SKIN: a MeshInstance3D with a Skin; at least 1 skin weight vertex bound
##   - CLIP: at least 1 animation; its length is the scene's within 1 frame; keys at the scene's fps (key count = frames + 1)
##   - POSE: the bone that turns most in the live clip, sampled at the clip middle, has the file's local rotation within 1 degree
##     of the live pose (the app's own mannequin posed by Overlays.pose_skeleton at that time)
##   - UNITS: Y up, metres: the file's head bone sits above its foot bone by 1.2 - 2.4 m in the rest pose
##   - the file's animation changes: the chosen bone's rotation at the middle differs from the first key by more than 5 degrees
extends SceneTree

var fails := 0
var m: Node
const OUT := "user://p149animglb"
const KEEP := "C:/Temp/claude/w4-p149animglb"


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


func turn(a: Quaternion, b: Quaternion) -> float:
	return rad_to_deg(a.angle_to(b))


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle()
	m._load_scene("res://scenes/combo3.json")
	await idle()
	m._export_dialog_open()
	var ui: ExportDialog = m.export_ui
	ok(ui.ui_target.item_count == 7, "before a body edit the dialog has 7 targets (%d)" % ui.ui_target.item_count)
	ui.dlg.hide()
	# ---- an edited body
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
	m._export_dialog_open()
	ui = m.export_ui
	var ids := []
	for i in ui.ui_target.item_count:
		ids.append(ui.ui_target.get_item_text(i))
	ok(ui.ui_target.item_count == 8 and ids.has("My edited character + animation (GLB)"), "after the body is applied the dialog has the new target (%d targets)" % ui.ui_target.item_count)
	ui.ui_target.select(7)
	ui._on_target(7)
	ok("FBX" in ui.text_of("bodyanim", 0)["needs"] and "Blender" in ui.text_of("bodyanim", 0)["needs"], "the dialog says plainly that FBX goes through Blender")
	ui.dlg.hide()

	# ---- export through the dialog's own road
	var S: Scene = m._hero_scene()
	var path := String(ui.export_now("bodyanim", 0, OUT))
	ok(path != "" and FileAccess.file_exists(path), "the dialog wrote %s" % path)
	DirAccess.make_dir_recursive_absolute(KEEP)
	var abs := ProjectSettings.globalize_path(path)
	DirAccess.copy_absolute(abs, KEEP + "/combo3_edited_body_anim.glb")

	# ---- read it back
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	ok(doc.append_from_file(abs, st) == OK, "GLTFDocument reads the file back")
	var back: Node3D = doc.generate_scene(st)
	root.add_child(back)
	await idle()
	var fsk: Skeleton3D = back.find_children("*", "Skeleton3D", true, false)[0]
	var holder := Node3D.new()
	root.add_child(holder)
	var mq := Overlays.mannequin(holder, StandardMaterial3D.new())
	var sk0: Skeleton3D = mq[1]
	var idx0: Dictionary = mq[2]
	ok(fsk.get_bone_count() == sk0.get_bone_count(), "skeleton bone count: file %d, character %d" % [fsk.get_bone_count(), sk0.get_bone_count()])
	var missing := []
	for b in sk0.get_bone_count():
		var nm := sk0.get_bone_name(b)
		if fsk.find_bone("head" if nm == "Head" else nm) < 0:
			missing.append(nm)
	ok(missing.is_empty(), "every bone name of the character is in the file (missing %s)" % [missing])
	var skinned := 0
	var skin_ok := false
	for n in back.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.skin != null:
			skin_ok = true
			for s in mi.mesh.get_surface_count():
				skinned += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	ok(skin_ok and skinned > 1000, "the mesh is skinned (Skin present, %d vertices)" % skinned)
	var aps := back.find_children("*", "AnimationPlayer", true, false)
	ok(aps.size() >= 1 and (aps[0] as AnimationPlayer).get_animation_list().size() >= 1, "1+ animation in the file")
	var ap: AnimationPlayer = aps[0]
	var an: String = ap.get_animation_list()[0]
	var A: Animation = ap.get_animation(an)
	ok(absf(A.length - S.length()) <= 1.0 / S.fps, "clip length %.3f s vs scene %.3f s (within 1 frame at %d fps)" % [A.length, S.length(), S.fps])
	var want_keys := int(ceil(S.length() * S.fps - 1e-6)) + 1
	var kc := 0
	for tr in A.get_track_count():
		if A.track_get_type(tr) == Animation.TYPE_ROTATION_3D:
			kc = A.track_get_key_count(tr)
			break
	ok(kc == want_keys, "keys on a bone track: %d, frames + 1 = %d" % [kc, want_keys])
	# ---- the pose at the clip middle against the live pose
	var tmid := S.length() * 0.5
	var B: Body = Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	S.apply(B, 0.0)
	Overlays.pose_skeleton(sk0, idx0, B)
	var q0 := {}
	for j in Body.ORDER:
		if idx0[j] >= 0:
			q0[j] = sk0.get_bone_pose_rotation(idx0[j])
	S.apply(B, tmid)
	Overlays.pose_skeleton(sk0, idx0, B)
	var pick := ""
	var most := -1.0
	for j in q0:
		var d := turn(q0[j], sk0.get_bone_pose_rotation(idx0[j]))
		if d > most:
			most = d
			pick = j
	var live: Quaternion = sk0.get_bone_pose_rotation(idx0[pick])
	ap.play(an)
	ap.seek(tmid, true)
	ap.advance(0.0)
	var fb := fsk.find_bone("head" if pick == "head" else pick)
	var got := fsk.get_bone_pose_rotation(fb)
	ap.seek(0.0, true)
	var first := fsk.get_bone_pose_rotation(fb)
	ok(turn(got, live) <= 1.0, "bone %s at the clip middle (%.2f s): file vs live pose %.4f deg (bar 1)" % [pick, tmid, turn(got, live)])
	ok(turn(got, first) > 5.0, "the file's animation moves %s: %.1f deg between the first key and the middle" % [pick, turn(got, first)])
	var hd := fsk.find_bone("head")
	var ft := fsk.find_bone("foot_l")
	var hh := 0.0
	if hd >= 0 and ft >= 0:
		hh = fsk.get_bone_global_rest(hd).origin.y - fsk.get_bone_global_rest(ft).origin.y
	ok(hh > 1.2 and hh < 2.4, "Y up, metres: head is %.2f m above the foot in the rest pose" % hh)
	print("RESULT p149animglb: %d fails" % fails)
	quit(1 if fails > 0 else 0)
