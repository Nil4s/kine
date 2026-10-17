## godot --headless --path . -s tests/glb_export_test.gd     (GATES OO1; Nick 10-16: "universal files to use in all engines")
## THE .GLB ROUND TRIP. Every scene in scenes/ exported by GltfExport, then READ BACK by Godot's own GLTFDocument (not
## by the exporter's code): its skeleton, its animation (named after the scene), its weapon nodes. The truth is what
## the app SHOWS: assets/mannequin.glb posed by Overlays.pose_skeleton from the body at that time. On every frame at
## the scene's fps: every one of our joints within 1 cm, every bone's turn within 1 degree, the weapons' knob and tip
## within 1 cm (none in the scene = no weapon node). (2) The file's animation length = the scene's (one frame).
## (3) The head bone is named "head" in the file (the UE5 name; the mannequin's own is "Head").
extends SceneTree

var fails := 0
const DIR := "res://exports/zz_glb"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## degrees between two rotations by how far they carry each axis (acos near 1 is float-noisy)
static func turn_gap(a: Basis, b: Basis) -> float:
	var w := 0.0
	for v in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		w = maxf(w, ((a.orthonormalized() * v) - (b.orthonormalized() * v)).length())
	return rad_to_deg(2.0 * asin(clampf(w * 0.5, 0.0, 1.0)))


## a node's transform relative to an ancestor (the tree is not running inside _init, so no global_transform)
static func rel(n: Node3D, top: Node) -> Transform3D:
	var x := Transform3D.IDENTITY
	var c: Node = n
	while c != null and c != top:
		if c is Node3D:
			x = (c as Node3D).transform * x
		c = c.get_parent()
	return x


## a bone's pose in its skeleton, built from the LOCAL poses up the chain (get_bone_global_pose is a cache refreshed by
## the running tree; in _init it keeps its first value)
static func bone_pose(sk: Skeleton3D, b: int) -> Transform3D:
	var x := Transform3D.IDENTITY
	while b >= 0:
		x = Transform3D(Basis(sk.get_bone_pose_rotation(b)).scaled(sk.get_bone_pose_scale(b)), sk.get_bone_pose_position(b)) * x
		b = sk.get_bone_parent(b)
	return x


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	# the truth: the app's own mannequin
	var holder := Node3D.new()
	root.add_child(holder)
	var mq := Overlays.mannequin(holder, StandardMaterial3D.new())
	var sk0: Skeleton3D = mq[1]
	var idx0: Dictionary = mq[2]
	var names := []
	for f in DirAccess.get_files_at("res://scenes"):
		if f.ends_with(".json"):
			names.append(f.get_basename())
	names.sort()
	var worst_p := 0.0
	var worst_r := 0.0
	var worst_w := 0.0
	var at_p := ""
	var at_r := ""
	var at_w := ""
	var frames := 0
	var dbg := 0
	var len_bad := []
	var head_ok := true
	var wep_seen := 0
	for sn in names:
		var S := Scene.new()
		S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/%s.json" % sn)))
		var t_sc := Time.get_ticks_msec()
		var path := "%s/%s.glb" % [DIR, sn]
		var err := GltfExport.write(S, B, path)
		if err != OK:
			ok(false, "%s: write failed (%d)" % [sn, err])
			continue
		# READ BACK with Godot's importer
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		if doc.append_from_file(ProjectSettings.globalize_path(path), st) != OK:
			ok(false, "%s: GLTFDocument could not read it back" % sn)
			continue
		var back: Node3D = doc.generate_scene(st)
		root.add_child(back)
		var sks := back.find_children("*", "Skeleton3D", true, false)
		var aps := back.find_children("*", "AnimationPlayer", true, false)
		if sks.is_empty() or aps.is_empty():
			ok(false, "%s: read back without a skeleton (%d) or an animation player (%d)" % [sn, sks.size(), aps.size()])
			back.queue_free()
			continue
		var sk: Skeleton3D = sks[0]
		var ap: AnimationPlayer = aps[0]
		var anims := ap.get_animation_list()
		if not anims.has(S.name) and not anims.has(sn):
			ok(false, "%s: no animation named after the scene in %s" % [sn, anims])
			back.queue_free()
			continue
		var an: String = S.name if anims.has(S.name) else sn
		var A: Animation = ap.get_animation(an)
		if absf(A.length - S.length()) > 1.0 / maxf(1.0, S.fps):
			len_bad.append("%s %.3f vs %.3f" % [sn, A.length, S.length()])
		# one key per frame, no two at one time (4.6 s x 30 = 138.0000x in floats once made a duplicate last key)
		var want_keys := int(ceil(S.length() * S.fps - 1e-6)) + 1
		var dup := 0
		for q in range(1, A.track_get_key_count(0)):
			if A.track_get_key_time(0, q) - A.track_get_key_time(0, q - 1) < 1e-4:
				dup += 1
		if A.track_get_key_count(0) != want_keys or dup > 0:
			len_bad.append("%s %d keys (want %d), %d at the same time as the one before" % [sn, A.track_get_key_count(0), want_keys, dup])
		head_ok = head_ok and sk.find_bone("head") >= 0 and sk.find_bone("Head") < 0
		var idx := {}
		for j in Body.ORDER:
			idx[j] = sk.find_bone("head" if j == "head" else j)
		var wn := back.find_child("weapon", true, false) as Node3D
		var wn2 := back.find_child("weapon2", true, false) as Node3D
		ap.play(an)
		var n := int(ceil(S.length() * S.fps - 1e-6))
		for k in n + 1:
			var t := minf(k / float(S.fps), S.length())
			ap.seek(t, true)
			S.apply(B, t)
			Overlays.pose_skeleton(sk0, idx0, B)
			frames += 1
			for j in Body.ORDER:
				if idx0[j] < 0:
					continue
				if idx[j] < 0:
					worst_p = 999.0
					at_p = "%s: bone %s missing in the file" % [sn, j]
					continue
				var want: Transform3D = rel(sk0, holder) * bone_pose(sk0, idx0[j])
				var got: Transform3D = rel(sk, back.get_parent()) * bone_pose(sk, idx[j])
				var dp := want.origin.distance_to(got.origin)
				if OS.get_environment("GLB_DBG") != "" and dp > 0.01 and dbg < 25 and t > 0.0:
					dbg += 1
					print("DBG %s %.3f %s %.3f m want %s got %s" % [sn, t, j, dp, want.origin, got.origin])
				var dr := turn_gap(want.basis, got.basis)
				if dp > worst_p:
					worst_p = dp
					at_p = "%s %.3f s %s" % [sn, t, j]
				if dr > worst_r:
					worst_r = dr
					at_r = "%s %.3f s %s" % [sn, t, j]
			for w in [[B.wep_on, wn, "weapon"], [B.wep2_on, wn2, "weapon2"]]:
				if not w[0]:
					continue
				var node := w[1] as Node3D
				if node == null:
					worst_w = 999.0
					at_w = "%s: no %s node" % [sn, w[2]]
					continue
				wep_seen += 1
				var L: float = B.wep_len if w[2] == "weapon" else B.wep2_len()
				var knob: Vector3 = B.wep_point(0.0) if w[2] == "weapon" else B.wep2_point(0.0)
				var tip: Vector3 = B.wep_point(L) if w[2] == "weapon" else B.wep2_point(L)
				var g := rel(node, back)
				var d := maxf(g.origin.distance_to(knob), (g.origin + g.basis.orthonormalized().y * L).distance_to(tip))
				if d > worst_w:
					worst_w = d
					at_w = "%s %.3f s %s" % [sn, t, w[2]]
		back.queue_free()
		print("   %s: %d frames, %d ms" % [sn, n + 1, Time.get_ticks_msec() - t_sc])
	ok(frames > 500 and worst_p <= 0.01 and worst_r <= 1.0, "1 %d scenes, %d frames read back by GLTFDocument: joints worst %.4f m (%s), bones worst %.3f deg (%s)" % [names.size(), frames, worst_p, at_p, worst_r, at_r])
	ok(wep_seen > 100 and worst_w <= 0.01, "1w the weapons in the file: %d weapon-frames, knob/tip worst %.4f m (%s)" % [wep_seen, worst_w, at_w])
	ok(len_bad.is_empty(), "2 every animation's length = its scene's, one key per frame, none doubled (off: %s)" % [len_bad])
	ok(head_ok, "3 the head bone is \"head\" in every file (UE5's name)")
	# (4) the app's own command: the registry row, and what it writes
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var row := {}
	for c in m._commands():
		if c["name"] == "Export animation (.glb)":
			row = c
	m._load_scene("res://scenes/combo3.json")
	var out: String = m._export_glb(DIR)
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var read_ok := out != "" and doc.append_from_file(ProjectSettings.globalize_path(out), st) == OK
	var anims: Array = []
	if read_ok:
		for a in st.get_animations():
			anims.append((a as GLTFAnimation).resource_name)
	ok(not row.is_empty() and (row["run"] as Callable).get_method() == "_export_glb" and read_ok and anims == ["combo3"], "4 the command 'Export animation (.glb)' (bound to %s) wrote %s, read back with animations %s" % [row.get("run", Callable()).get_method() if not row.is_empty() else "-", out.get_file(), anims])
	m.queue_free()
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR + "/" + f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))
	print("GLB EXPORT: %d failed" % fails)
	quit(1 if fails > 0 else 0)
