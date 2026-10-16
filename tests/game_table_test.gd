## godot --headless --path . -s tests/game_table_test.gd     (GATES LL2, UPGRADES_200 #101, #103, #104)
## THE TABLE THE GAME READS. For every scene in scenes/: the exported table, played through the GAME's sampler
## (PoseTrack.Sample: smoothstep between the bracketing keys, re-written HERE from PoseTable.cs, not borrowed from the
## exporter) and the game's composition, stays within 1 degree of Poser on every 60 fps frame and every slot; t ascending
## in [0, 1], first key 0, last 1. (2) Keys at the cards only (no keys added) miss the 1 degree bar on at least one
## scene: the added keys are doing work. (3) The JSON re-read gives the same keys (0.01 degrees) and the same playback;
## the C# is PoseTable.cs's own syntax: one `new PoseTrack(Bone.X` per slot, one `new PoseKey(` per key, brackets
## balanced. (4) "Export to game" from the app: exports/<scene>.json and .cs written (to a scratch folder here),
## the body's pose unchanged by the export, nothing written in scenes/.
extends SceneTree

var fails := 0
var m: Node
var B: Body
const SCRATCH := "res://exports/zz_test"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## PoseTrack.Sample (PoseTable.cs), line for line
func game_sample(keys: Array, t: float) -> Vector3:
	if keys.size() == 0:
		return Vector3.ZERO
	if t <= keys[0][0]:
		return keys[0][1]
	for i in range(1, keys.size()):
		if t > keys[i][0]:
			continue
		var a: Array = keys[i - 1]
		var b: Array = keys[i]
		var span: float = b[0] - a[0]
		var u: float = 1.0 if span <= 1e-6 else (t - a[0]) / span
		u = u * u * (3.0 - 2.0 * u)
		return (a[1] as Vector3).lerp(b[1], u)
	return keys[keys.size() - 1][1]


## LimbRig.Joint.Set's order: pitch about the character's right, then yaw about up, then roll about forward
## (Poser's character: right = -x, up = +y, forward = +z)
func game_rot(a: Vector3) -> Quaternion:
	return Quaternion(Vector3(-1, 0, 0), deg_to_rad(a.x)) * Quaternion(Vector3.UP, deg_to_rad(a.y)) * Quaternion(Vector3(0, 0, 1), deg_to_rad(a.z))


func ang_gap(a: Quaternion, b: Quaternion) -> float:
	return rad_to_deg(2.0 * acos(clampf(absf(a.dot(b)), 0.0, 1.0)))


## the worst gap (degrees) between the table played through the game's sampler and Poser, over every frame and slot
func playback_gap(S: Scene, tracks: Dictionary) -> Array:
	var L := S.length()
	var n := int(ceil(L * 60.0)) + 1
	var worst := 0.0
	var at := ""
	for k in n:
		var t := minf(k / 60.0, L)
		S.apply(B, t)
		var truth := GameExport.slot_angles(B)
		for s in truth:
			var g := ang_gap(game_rot(game_sample(tracks[s], t / L)), game_rot(truth[s]))
			if g > worst:
				worst = g
				at = "%s at %.3f s" % [s, t]
	return [worst, at]


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	B = m.B
	var names := []
	for f in DirAccess.get_files_at("res://scenes"):
		if f.ends_with(".json") and not f.begins_with("zz_"):
			names.append(f.get_basename())
	names.sort()
	var all_in := true
	var shape := true
	var coarse_miss := 0
	var report := []
	var keep_T := {}
	var keep_S: Scene = null
	for sn in names:
		var S := Scene.new()
		S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/%s.json" % sn)))
		if S.cards.size() < 2:
			report.append("%s: %d card, skipped" % [sn, S.cards.size()])
			continue
		var T := GameExport.table(S, B)
		var g := playback_gap(S, T["tracks"])
		var nk := 0
		for s in T["tracks"]:
			var ks: Array = T["tracks"][s]
			nk += ks.size()
			if absf(ks[0][0]) > 1e-6 or absf(ks[-1][0] - 1.0) > 1e-6:
				shape = false
			for i in range(1, ks.size()):
				if ks[i][0] <= ks[i - 1][0]:
					shape = false
		all_in = all_in and g[0] <= 1.0
		var C := GameExport.table(S, B, false)
		var gc := playback_gap(S, C["tracks"])
		if gc[0] > 1.0:
			coarse_miss += 1
		report.append("%s %.2fs: %d keys, worst %.3f deg (%s); cards-only %d keys, worst %.2f" % [sn, S.length(), nk, g[0], g[1], _count(C), gc[0]])
		if keep_S == null:
			keep_S = S
			keep_T = T
	for r in report:
		print("   " + r)
	ok(all_in and shape and report.size() == names.size() and names.size() >= 10, "1 every scene (%d) within 1 degree on every frame and slot through the game's sampler; t ascending 0..1: %s" % [names.size(), shape])
	ok(coarse_miss >= 1, "2 keys at the cards only miss 1 degree on %d scene(s): the added keys do work" % coarse_miss)
	# (3)
	var J := GameExport.to_json(keep_S.name, keep_T)
	var back := GameExport.from_json(JSON.parse_string(JSON.stringify(J)))
	var same := true
	for s in keep_T["tracks"]:
		var a: Array = keep_T["tracks"][s]
		var b: Array = back["tracks"][s]
		if a.size() != b.size():
			same = false
			continue
		for i in a.size():
			var d: Vector3 = ((a[i][1] as Vector3) - (b[i][1] as Vector3)).abs()
			if d[d.max_axis_index()] > 0.0051 or absf(a[i][0] - b[i][0]) > 0.00006:
				same = false
	var gb := playback_gap(keep_S, back["tracks"])
	var cs := GameExport.to_csharp(keep_S.name, keep_T)
	var tracks_n := cs.count("new PoseTrack(Bone.")
	var keys_n := cs.count("new PoseKey(")
	var bal := cs.count("(") == cs.count(")")
	ok(same and gb[0] <= 1.05 and tracks_n == 11 and keys_n == _count(keep_T) and bal and cs.contains("public static readonly PoseTable "),
		"3 %s: JSON re-read same keys %s, plays within %.3f deg; C#: %d tracks, %d PoseKeys of %d, brackets balanced %s" % [keep_S.name, same, gb[0], tracks_n, keys_n, _count(keep_T), bal])
	# (4) the app's command
	m._load_scene("res://scenes/%s.json" % keep_S.name)
	m._rebuild_cards()
	m._timeline_pick(1)
	await process_frame
	var pose0: Dictionary = B.ang.duplicate()
	var scenes0 := _scene_sums()
	var out: Array = m._export_game(SCRATCH)
	var wrote: bool = out.size() == 3 and FileAccess.file_exists(out[0]) and FileAccess.file_exists(out[1])
	var kept := true
	for j in pose0:
		if not (B.ang[j] as Vector3).is_equal_approx(pose0[j]):
			kept = false
	var said: bool = (m.ui_status.text as String).contains("exported to the game")
	ok(wrote and kept and said and _scene_sums() == scenes0, "4 Export to game: wrote %s and .cs %s; the pose unchanged %s; the status says so %s; scenes/ untouched %s" % [out[0] if out.size() > 0 else "-", wrote, kept, said, _scene_sums() == scenes0])
	for f in DirAccess.get_files_at(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH + "/" + f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
	print("GAME TABLE: %d failed" % fails)
	quit(1 if fails > 0 else 0)


func _count(T: Dictionary) -> int:
	var n := 0
	for s in T["tracks"]:
		n += (T["tracks"][s] as Array).size()
	return n


func _scene_sums() -> String:
	var s := ""
	for f in DirAccess.get_files_at("res://scenes"):
		s += f + FileAccess.get_md5("res://scenes/" + f)
	return s
