## godot --headless --path . -s tests/engine_names_test.gd     (GATES OO4; Nick 10-16: "some people will use unity, ue5,
## godot or others... open source power for all")
## (1) Every bone in an exported .glb (read back by GLTFDocument) checked against UE5's Mannequin (Manny / Quinn) bone
## list, WRITTEN HERE from UE5's skeleton, not read from the exporter: every one of Poser's joints must be on it; any
## other bone in the file is PRINTED (the mannequin's leaf bones are not UE5's). (2) docs/EXPORT.md names each engine's
## way in (Unreal 5, Unity, Godot, Blender) and says what was not tested inside Unity or Unreal.
extends SceneTree

var fails := 0

## UE5 Manny/Quinn (SKM_Manny): the body, the hands with metacarpals, twist bones, the IK bones
const UE5 := ["root", "pelvis", "spine_01", "spine_02", "spine_03", "spine_04", "spine_05", "neck_01", "neck_02", "head",
	"clavicle_l", "upperarm_l", "lowerarm_l", "hand_l", "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r",
	"upperarm_twist_01_l", "upperarm_twist_02_l", "lowerarm_twist_01_l", "lowerarm_twist_02_l",
	"upperarm_twist_01_r", "upperarm_twist_02_r", "lowerarm_twist_01_r", "lowerarm_twist_02_r",
	"thumb_01_l", "thumb_02_l", "thumb_03_l", "index_metacarpal_l", "index_01_l", "index_02_l", "index_03_l",
	"middle_metacarpal_l", "middle_01_l", "middle_02_l", "middle_03_l", "ring_metacarpal_l", "ring_01_l", "ring_02_l",
	"ring_03_l", "pinky_metacarpal_l", "pinky_01_l", "pinky_02_l", "pinky_03_l",
	"thumb_01_r", "thumb_02_r", "thumb_03_r", "index_metacarpal_r", "index_01_r", "index_02_r", "index_03_r",
	"middle_metacarpal_r", "middle_01_r", "middle_02_r", "middle_03_r", "ring_metacarpal_r", "ring_01_r", "ring_02_r",
	"ring_03_r", "pinky_metacarpal_r", "pinky_01_r", "pinky_02_r", "pinky_03_r",
	"thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r", "ball_r",
	"thigh_twist_01_l", "thigh_twist_02_l", "calf_twist_01_l", "calf_twist_02_l",
	"thigh_twist_01_r", "thigh_twist_02_r", "calf_twist_01_r", "calf_twist_02_r",
	"ik_foot_root", "ik_foot_l", "ik_foot_r", "ik_hand_root", "ik_hand_gun", "ik_hand_l", "ik_hand_r",
	"interaction", "center_of_mass"]


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json")))
	var path := "res://exports/zz_names/combo3.glb"
	var err := GltfExport.write(S, B, path)
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if err != OK or doc.append_from_file(ProjectSettings.globalize_path(path), st) != OK:
		ok(false, "1 the .glb could not be written and read back")
		quit(1)
		return
	var sk: Skeleton3D = doc.generate_scene(st).find_children("*", "Skeleton3D", true, false)[0]
	var names := []
	for b in sk.get_bone_count():
		names.append(sk.get_bone_name(b))
	var ours_off := []
	for j in Body.ORDER:
		if not names.has(j):
			ours_off.append(j + " (not in the file)")
		elif not UE5.has(j):
			ours_off.append(j)
	var extra := names.filter(func(n): return not UE5.has(n))
	print("     bones in the file NOT on UE5's list (%d): %s" % [extra.size(), extra])
	ok(names.size() >= Body.ORDER.size() and ours_off.is_empty(), "1 %d bones in the file; every one of Poser's %d joints is a UE5 Mannequin bone by name (off: %s)" % [names.size(), Body.ORDER.size(), ours_off])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("res://exports/zz_names"))
	# (2) the guide
	var md := FileAccess.get_file_as_string("res://docs/EXPORT.md")
	var need := ["## Unreal Engine 5", "## Unity", "## Godot", "## Blender", "IK Retargeter", "Humanoid", "BoneMap", "SkeletonProfileHumanoid", "bake_anim_simplify_factor", "NOT TESTED"]
	var lacking := need.filter(func(w): return not md.contains(w))
	ok(md.length() > 2000 and lacking.is_empty(), "2 docs/EXPORT.md (%d chars) covers every engine and says what was not tested (lacking: %s)" % [md.length(), lacking])
	print("ENGINE NAMES: %d failed" % fails)
	quit(1 if fails > 0 else 0)
