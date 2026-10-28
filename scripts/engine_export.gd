## ONE-CLICK ENGINE DELIVERY (ROADMAP item 9, top-25 #19): "Export for Unreal 5...", "Export for Unity...", "Export for Godot...".
## Each writes the scene as a .glb (GltfExport) with that engine's needs, and PRINTS A PRE-FLIGHT REPORT before the file is
## written: every check is "OK ..." or "WRONG ..." with what will go wrong. The needs, the sources and the settings are in
## docs/research/ENGINES.md. Presets differ only where the engine needs something:
##   ue5    : root motion. The pelvis's horizontal travel is moved onto the "root" bone (UE5 Manny's root motion bone), so
##            the pelvis keeps its place. Units: metres in the file; UE5's glTF import scales by 100 to centimetres.
##   unity  : nothing moved. Units are metres, Y up (glTFast). A clip that travels leaves the travel on the hips.
##   godot  : nothing moved. Units are metres, Y up (Godot's glTF import, Root Scale 1).
class_name EngineExport
extends RefCounted

const PRESETS := {
	"ue5": {"label": "Unreal Engine 5", "suffix": "_ue5", "root_motion": true,
		"needs": "Unreal Engine 5 wants the root motion on a root bone and the units in centimetres. Import the .glb as a Skeletal Mesh with Import Animations on, and keep Import Uniform Scale at 100 (the glTF default: metres become centimetres). The pelvis's sideways travel is on the root bone (Manny's 'root'), so the character travels when the clip plays."},
	"unity": {"label": "Unity", "suffix": "_unity", "root_motion": false,
		"needs": "Unity wants metres and Y up, which the file is. Drop the .glb into Assets with the glTFast package. The clip moves the hips, so the character travels only if your game moves it or the clip has no travel. For a Humanoid avatar use the FBX route in docs/EXPORT.md."},
	"godot": {"label": "Godot 4", "suffix": "_godot", "root_motion": false,
		"needs": "Godot 4 wants metres and Y up, which the file is. Copy the .glb into the project: it imports as a Skeleton3D with one AnimationPlayer, at scale 1 (Import dock: Root Scale 1). The clip moves the hips, so the character travels only if your script moves it or the clip has no travel."},
}

## UE5's own mannequin bones (the names Manny and Quinn use); the file must carry every one of them
const UE5_CORE := ["root", "pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head",
	"clavicle_l", "upperarm_l", "lowerarm_l", "hand_l", "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r",
	"thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r", "ball_r"]


static func preset(id: String) -> Dictionary:
	return PRESETS.get(id, {})


## the file base name for a preset: <scene>_ue5.glb etc. (the animation inside keeps the scene's name)
static func file_name(scene_name: String, id: String) -> String:
	return "%s%s.glb" % [scene_name if scene_name != "" else "scene", String(preset(id).get("suffix", ""))]


## the pre-flight lines for the scene as this preset would write it (each "OK ..." or "WRONG ..."), without writing
static func preflight(S: Scene, B: Body, id: String, anim_name: String) -> Array:
	var keep := B.state()
	var p := preset(id)
	var root := GltfExport.build(S, B, anim_name, true, bool(p.get("root_motion", false)))
	var lines := _checks(root, S, B, id, anim_name)
	root.free()
	B.set_state(keep)
	return lines


## the whole delivery: pre-flight lines go to report (a Callable taking the Array) BEFORE the file is written.
## Returns {"path", "err", "lines", "wrong"}.
## blows: the fighters' blows (ImpactFrames.blows; [] with one fighter), written as the impact feel file beside the .glb (I3)
static func export(S: Scene, B: Body, id: String, dir: String, report := Callable(), blows: Array = []) -> Dictionary:
	var p := preset(id)
	if p.is_empty():
		return {"path": "", "err": ERR_INVALID_PARAMETER, "lines": [], "wrong": 0}
	var keep := B.state()
	var an := S.name if S.name != "" else "scene"
	var root := GltfExport.build(S, B, an, true, bool(p.get("root_motion", false)))
	var lines := _checks(root, S, B, id, an)
	var wrong := 0
	for l in lines:
		if (l as String).begins_with("WRONG"):
			wrong += 1
	if report.is_valid():
		report.call(lines)
	var path := "%s/%s" % [dir, file_name(S.name, id)]
	var abs_path := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var err := GltfExport._write(root, path)   # frees root
	# WEAPON TRAILS (ROADMAP 35): the bat's two edge points per frame, next to the .glb, when the scene holds a weapon
	var trail := ""
	if err == OK:
		var sc := WeaponTrail.sidecar(S, B, an)
		if not sc.is_empty():
			trail = path.get_basename() + "_weapon_trail.json"
			var abs_t := ProjectSettings.globalize_path(trail) if trail.begins_with("res://") or trail.begins_with("user://") else trail
			var f := FileAccess.open(abs_t, FileAccess.WRITE)
			if f == null:
				trail = ""
			else:
				f.store_string(JSON.stringify(sc, "	"))
				f.close()
	# IMPACT FEEL (ROADMAP I3): the blows as rumble events, next to the .glb (an empty list when there is no blow)
	var feel := ""
	if err == OK:
		feel = ImpactFeel.write(path, ImpactFeel.sidecar(blows, int(S.fps), an))
	B.set_state(keep)
	return {"path": path, "err": err, "lines": lines, "wrong": wrong, "trail": trail, "feel": feel, "feel_n": blows.size()}


static func _bone(sk: Skeleton3D, nm: String) -> int:
	var i := sk.find_bone(nm)
	if i < 0 and nm == "head":
		i = sk.find_bone("Head")   # the mannequin's own name; the file says "head" (GltfExport._write)
	return i


## every check, in order. root is the built node (its skeleton, its animation player); S and B give the motion
static func _checks(root: Node3D, S: Scene, B: Body, id: String, an: String) -> Array:
	var out := []
	var p := preset(id)
	var sk: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
	var ap: AnimationPlayer = root.find_children("*", "AnimationPlayer", true, false)[0]
	var A: Animation = ap.get_animation(an)
	var fps := float(S.fps)
	var L := S.length()

	# UNITS: the file is metres; the mannequin's height from its own mesh
	var H := 0.0
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		H = maxf(H, (mi as MeshInstance3D).get_aabb().size.y)
	if H >= 1.5 and H <= 2.0:
		if id == "ue5":
			out.append("OK    units: the file is metres; the mannequin is %s, so UE5 shows %s with Import Uniform Scale 100 (the glTF default)" % [Units.len(H), Units.len(H)])
		else:
			out.append("OK    units: the file is metres, the mannequin is %s, %s reads metres: no scale to set" % [Units.len(H), p["label"]])
	else:
		out.append("WRONG units: the mannequin is %s tall (a person is 150 to 200 cm); %s will show it at that size, so check the body proportions" % [Units.len(H), p["label"]])

	# UP AXIS and FACING: from the rest skeleton in the file (glTF: +Y up, the front faces +Z)
	if sk.find_bone("pelvis") >= 0 and _bone(sk, "head") >= 0 and sk.find_bone("foot_l") >= 0 and sk.find_bone("ball_l") >= 0:
		var hd := sk.get_bone_global_rest(_bone(sk, "head")).origin
		var pv := sk.get_bone_global_rest(sk.find_bone("pelvis")).origin
		var ft := sk.get_bone_global_rest(sk.find_bone("foot_l")).origin
		var bl := sk.get_bone_global_rest(sk.find_bone("ball_l")).origin
		if hd.y > pv.y and pv.y > ft.y + 0.3:
			out.append("OK    up: standing in the file: head %s, pelvis %s, foot %s (Y up; %s)" % [Units.len(hd.y), Units.len(pv.y), Units.len(ft.y), "UE5 is Z up and converts it on import" if id == "ue5" else "%s keeps Y up" % p["label"]])
		else:
			out.append("WRONG up: the rest pose is not standing (head %s, pelvis %s, foot %s): %s would show it on its side or upside down" % [Units.len(hd.y), Units.len(pv.y), Units.len(ft.y), p["label"]])
		if bl.z > ft.z:
			out.append("OK    facing: the toes point to +Z, the glTF front")
		else:
			out.append("WRONG facing: the toes point away from +Z: the character turns around in %s" % p["label"])

	# ROOT MOTION: the pelvis's travel (its horizontal path in the scene), measured over the same frames the file has
	var n := int(ceil(L * fps - 1e-6))
	var P0 := Vector3.ZERO
	var travel := 0.0
	var drift := 0.0
	var local0 := Vector3.ZERO
	for k in n + 1:
		var t := minf(k / fps, L)
		S.apply(B, t)
		if k == 0:
			P0 = B.P["pelvis"]
		var D: Vector3 = B.P["pelvis"] - P0
		travel = maxf(travel, Vector2(D.x, D.z).length())
		# the pelvis as the file holds it (GltfExport._animate): its place with the travel taken off, against frame 0.
		# (Measured on the same formula the writer uses; the old check subtracted the travel from its own source and
		# was always zero, so the line said "drift 0 mm" whatever the file held.)
		var T := Vector3(D.x, 0.0, D.z)
		var local: Vector3 = B.gltf_pelvis_pos() - B.root_rot.inverse() * T
		if k == 0:
			local0 = local
		var dl: Vector3 = local - local0
		drift = maxf(drift, Vector2(dl.x, dl.z).length())
	if bool(p.get("root_motion", false)):
		if sk.find_bone("root") >= 0:
			out.append("OK    root motion: the pelvis travels %s sideways; it is on the root bone, and the pelvis keeps its place (drift %s)" % [Units.len(travel), Units.len(drift)])
		else:
			out.append("WRONG root motion: the file has no root bone, so the travel stays on the pelvis and %s will not move the character" % p["label"])
	elif travel > 0.05:
		out.append("WRONG root motion: the character travels %s, but %s does not move it from the file: it plays on the spot unless the game moves it (UE5 export moves it onto the root bone)" % [Units.len(travel), p["label"]])
	else:
		out.append("OK    root motion: the character travels %s: nothing to move" % Units.len(travel))

	# FRAME RATE: a key on every frame at the scene's rate
	if S.fps >= 1 and S.fps <= 120:
		out.append("OK    frame rate: %d fps, a key on every frame (%d keys); the engine plays the same frames" % [S.fps, n + 1])
	else:
		out.append("WRONG frame rate: %d fps is outside 1 to 120 fps; set the scene's fps" % S.fps)

	# ANIMATION NAME: the clip is named after the scene
	var name_ok := an.length() <= 63 and an.is_valid_filename() and RegEx.create_from_string("^[A-Za-z0-9_]+$").search(an) != null
	if A != null and name_ok:
		out.append("OK    animation name: '%s' (the clip's name in %s)" % [an, p["label"]])
	elif A == null:
		out.append("WRONG animation name: the file has no clip named '%s'" % an)
	else:
		out.append("WRONG animation name: '%s' has characters %s renames: use letters, digits and _ (at most 63 characters)" % [an, p["label"]])

	# BONES: the count, the leaves engines ignore, and UE5's core names
	var leaves := 0
	for i in sk.get_bone_count():
		if sk.get_bone_name(i).contains("leaf"):
			leaves += 1
	out.append("OK    %d bones (%d leaf bones with no motion: %s ignores them)" % [sk.get_bone_count(), leaves, p["label"]])
	if id == "ue5":
		var missing := []
		for nm in UE5_CORE:
			if _bone(sk, nm) < 0:
				missing.append(nm)
		if missing.is_empty():
			out.append("OK    UE5 bones: all %d of UE5's core names are present (Manny's names)" % UE5_CORE.size())
		else:
			out.append("WRONG UE5 bones: missing %s: the IK Retargeter cannot pair them" % ", ".join(missing))
	return out
