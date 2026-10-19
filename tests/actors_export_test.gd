## godot --headless --path . -s tests/actors_export_test.gd     (GATES TC6: export per actor with its placement)
## combo3 + "Actor: add a second fighter", the fighter placed at (0.4, 1.3) m, yaw 150 deg, then the app's own export
## commands. The truth is Kine's Body.P of each actor at 5 times (0, L/4, L/2, 3L/4, L), carried by the actor's xf.
## (1) .glb read back by Godot's GLTFDocument: 2 skeletons named by the fighters, every joint within 1 cm;
## (1b) the same .glb and (3b) each .bvh imported by BLENDER's own importers (when a blender.exe is found): hands, feet,
## head of each armature within 1 cm; (2) .usda parsed here (a SkelRoot per actor, its xformOp, joint FK) within 1 cm;
## (3) .bvh: one file per actor, re-parsed (tests/bvh_export_test.gd's reader), within 1 cm; (4) one-actor exports
## byte-identical to the pre-TC6 writers (sha256 recorded at 7ddd976); (5) every export message names every file.
## Files go to user://zz_actors_export (removed after).
extends SceneTree

var fails := 0
const DIR := "user://zz_actors_export"
const BAR := 0.01
const ENDS := ["hand_l", "hand_r", "foot_l", "foot_r", "head"]
## one-actor exports of the pre-TC6 writers (commit 7ddd976), and the scene files they were made from
const BASE := {   # sha256 of the scene file with CR removed (a checkout may add CRLF), then of each pre-TC6 export
	# RE-BASELINED after ccd0d48 (diffed file by file against exports made at ccd0d48; every difference is one of two commits):
	#  f8a3023 toe guard smoothstep: walk_bat ball_l/ball_r rotations change (bvh Xrotation up to 16.6 deg, usda ball quats, glb ball tracks); nothing else.
	#  149c083 foot twist = subtalar roll (merged 97d8598): the Newton solve leaves foot_r Zrotation as -0.00000 where it was 0.00000 (combo3.bvh 36 values,
	#  combo3.usda signed zeros); numerically identical to f8a3023's file, the text differs only in the sign of a zero. Hierarchy, joint count, glb nodes unchanged.
	"combo3": ["e5dcf25a7d716b00c886e86b1ee94f0a7697bdc0b57c37c0c88dc69bbcdc4bea", {
		"glb": "499ee1e47f3e46dd807f3945900ccadd8a0beabb2b0ddaae821adf871b0ccf2e",
		"usda": "f20c1f44928f5f32ccde0c1a9e67bc7f5d823f6b00b4c3346c4f08f3bbbcecfa",
		"bvh": "f9e16271177a6125506064c1bc448cf81cce670754255dc816d807f7f2d13ceb",
		"json": "b63904ebc461805fdf2701d9b8dfeaedc7593180a9e584206c44d47578e02bf2",
		"cs": "86f2376b3a023bf90074d90d6abb31296a096ecb565bb0cab5dfea3670581832"}],
	# walk_bat glb/usda/bvh re-baselined at 88eb4c1 (toe cap): the ONLY change vs the pre-TC6 bvh is the ball_l/ball_r channels
	# (verified: bvh channels and glb animation tracks differ ONLY on ball_l/ball_r; glb nodes, skins, meshes identical; the glb hash is for the test's order, combo3 then walk_bat on one Body). json/cs hashes are unchanged.
	"walk_bat": ["bc08fc8cdc71607353dff4612c4eb6721af3e2c02da252714eeb7fdddfc9b693", {
		"glb": "00db85d36237c50e1204c00e5e63c2859e5b471d4e964579430fc2964cfca27f",
		"usda": "a17d4f2f18075e3a2479f7f504a582b207b47e01d0a38d8e2603d86999c65eb8",
		"bvh": "af9163e5dde2d8b14fa17e35fab27a22e41cfb4ba05d89f02ca6efbd00ca3336",
		"json": "1dc574ca319d52f7f7ee662f1446b432b0f7218877fb325c020aec524ba90f14",
		"cs": "6e8a5a6532c0f3d302f3668e58dbad2fdc4adb11b9efad1593527e809fe7c42e"}],
}


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


static func rel(n: Node, top: Node) -> Transform3D:
	var x := Transform3D.IDENTITY
	var c: Node = n
	while c != null and c != top:
		if c is Node3D:
			x = (c as Node3D).transform * x
		c = c.get_parent()
	return x


static func bone_pose(sk: Skeleton3D, b: int) -> Transform3D:
	var x := Transform3D.IDENTITY
	while b >= 0:
		x = Transform3D(Basis(sk.get_bone_pose_rotation(b)).scaled(sk.get_bone_pose_scale(b)), sk.get_bone_pose_position(b)) * x
		b = sk.get_bone_parent(b)
	return x


static func blender_exe() -> String:
	var env := OS.get_environment("POSER_BLENDER")
	if env != "" and FileAccess.file_exists(env):
		return env
	var root := "C:/Program Files/Blender Foundation"
	var vers := Array(DirAccess.get_directories_at(root)) if DirAccess.dir_exists_absolute(root) else []
	vers.sort()
	vers.reverse()
	for v in vers:
		if FileAccess.file_exists("%s/%s/blender.exe" % [root, v]):
			return "%s/%s/blender.exe" % [root, v]
	return ""


func clean() -> void:
	var g := ProjectSettings.globalize_path(DIR)
	if DirAccess.dir_exists_absolute(g):
		for f in DirAccess.get_files_at(g):
			DirAccess.remove_absolute(g + "/" + f)
		DirAccess.remove_absolute(g)


func _init() -> void:
	clean()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var gdir := ProjectSettings.globalize_path(DIR)
	var BT: Script = load("res://tests/bvh_export_test.gd")
	var UT: Script = load("res://tests/usd_export_test.gd")

	# (4) one actor: the writers and the app's commands, byte for byte
	var B1 := Body.new()
	B1.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var diffs := []
	var stale := []
	for sn in BASE:
		if FileAccess.get_file_as_string("res://scenes/%s.json" % sn).replace("", "").sha256_text() != BASE[sn][0]:
			stale.append(sn)
			continue
		var S1 := Scene.new()
		S1.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/%s.json" % sn)))
		GltfExport.write(S1, B1, "%s/%s.glb" % [DIR, sn])
		UsdExport.write(S1, B1, "%s/%s.usda" % [DIR, sn])
		BvhExport.write(S1, B1, "%s/%s.bvh" % [DIR, sn])
		GameExport.write(S1, B1, DIR)
		for e in BASE[sn][1]:
			if FileAccess.get_sha256("%s/%s.%s" % [DIR, sn, e]) != BASE[sn][1][e]:
				diffs.append("%s.%s" % [sn, e])

	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	m._load_scene("res://scenes/combo3.json")
	clean()
	DirAccess.make_dir_recursive_absolute(gdir)
	var one := [m._export_glb(DIR), m._export_usd(DIR), m._export_bvh(DIR)]
	var og: Array = m._export_game(DIR)
	one.append_array([og[0], og[1]])
	if not "combo3" in stale:
		for p in one:
			var e: String = (p as String).get_extension()
			if FileAccess.get_sha256(p) != BASE["combo3"][1][e]:
				diffs.append("app " + (p as String).get_file())
	ok(diffs.is_empty() and stale.is_empty(), "4 one actor: %d files (combo3, walk_bat x glb/usda/bvh/json/cs, + the app's 5 commands on combo3) byte-identical to the pre-TC6 writers (differ: %s; scene file changed since the baseline: %s)" % [10 - 5 * stale.size() + (0 if "combo3" in stale else 5), diffs, stale])
	clean()
	DirAccess.make_dir_recursive_absolute(gdir)

	# two actors, the second placed off-axis so every axis of the xf counts
	m._actor_add()
	m.actor_place(1, Vector2(0.4, 1.3), 150.0)
	var acts: Array = m._export_actors()
	ok(acts.size() == 2, "two fighters in the app: %s" % [acts.map(func(a): return a["name"])])
	var said := {}
	var glb: String = m._export_glb(DIR)
	said["glb"] = m.ui_status.text
	var usd: String = m._export_usd(DIR)
	said["usd"] = m.ui_status.text
	m._export_bvh(DIR)
	said["bvh"] = m.ui_status.text
	var game: Array = m._export_game(DIR)
	said["game"] = m.ui_status.text
	var files := Array(DirAccess.get_files_at(gdir))
	files.sort()
	print("   written: %s" % [files])

	# the truth: each actor's Body.P at 5 times, carried by its xf
	var L := 0.0
	for a in acts:
		L = maxf(L, (a["S"] as Scene).length())
	var fps := float((acts[0]["S"] as Scene).fps)
	var n := int(ceil(L * fps - 1e-6))
	var ks := [0, n / 4, n / 2, (3 * n) / 4, n]
	var times := ks.map(func(k): return minf(k / fps, L))
	var truth := []   # [actor][time] -> {joint: Vector3}
	for a in acts:
		var per := []
		for t in times:
			(a["S"] as Scene).apply(a["B"], t)
			(a["B"] as Body).fk()
			var d := {}
			for j in Body.ORDER:
				d[j] = (a["xf"] as Transform3D) * ((a["B"] as Body).P[j] as Vector3)
			per.append(d)
		truth.append(per)

	# (1) the .glb through Godot's GLTFDocument
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var w1 := INF
	var at1 := "not read"
	var names1 := []
	var njs := 0
	var missing := []
	var man: Node3D = (load("res://assets/mannequin.glb") as PackedScene).instantiate()
	var msk: Skeleton3D = man.find_children("*", "Skeleton3D", true, false)[0]
	var in_man := Body.ORDER.filter(func(j): return msk.find_bone("Head" if j == "head" else j) >= 0)
	man.free()
	if glb != "" and doc.append_from_file(ProjectSettings.globalize_path(glb), st) == OK:
		var back: Node3D = doc.generate_scene(st)
		root.add_child(back)
		var sks := back.find_children("*", "Skeleton3D", true, false)
		var ap: AnimationPlayer = back.find_children("*", "AnimationPlayer", true, false)[0]
		for sk in sks:
			names1.append(String((sk as Node).get_parent().name))
		w1 = 0.0
		at1 = ""
		ap.play(ap.get_animation_list()[0])
		for ti in times.size():
			ap.seek(times[ti], true)
			for k in acts.size():
				var sk: Skeleton3D = null
				for s in sks:
					if String((s as Node).get_parent().name) == String(acts[k]["name"]):
						sk = s
				if sk == null:
					w1 = INF
					at1 = "no skeleton named " + String(acts[k]["name"])
					continue
				for j in in_man:
					var b := sk.find_bone(j)
					if b < 0:
						if not "%s/%s" % [acts[k]["name"], j] in missing:
							missing.append("%s/%s" % [acts[k]["name"], j])
						continue
					njs += 1
					var got := (rel(sk, back) * bone_pose(sk, b)).origin
					var d: float = got.distance_to(truth[k][ti][j])
					if d > w1:
						w1 = d
						at1 = "%s %s t %.3f" % [acts[k]["name"], j, times[ti]]
		back.free()
	ok(names1.size() == 2 and names1.has("hero") and names1.has("fighter 2") and missing.is_empty() and w1 <= BAR,
		"1 %s read back by GLTFDocument: skeletons %s, %d joint-reads (%d joints x 2 actors x 5 times; bones missing: %s), worst %.4f mm (%s; bar 10 mm)" % [glb.get_file(), names1, njs, in_man.size(), missing.slice(0, 6), w1 * 1000.0, at1])

	# (2) the .usda: a SkelRoot per actor, its xformOp:transform, the joints' FK
	var txt := FileAccess.get_file_as_string(usd) if usd != "" else ""
	var w2 := INF
	var at2 := "not read"
	var prims := []
	if txt != "":
		var lines := txt.split("\n")
		var head := "\n".join(lines.slice(0, lines.find(")") + 1)) + "\n"
		var blocks := txt.split("    def SkelRoot \"")
		w2 = 0.0
		at2 = ""
		for bi in range(1, blocks.size()):
			var blk: String = blocks[bi]
			var pn := blk.get_slice("\"", 0)
			prims.append(pn)
			var k := prims.size() - 1
			var mx: PackedFloat64Array = UT.nums(blk.get_slice("xformOp:transform =", 1).get_slice("\n", 0))
			var X := Transform3D(Basis(Vector3(mx[0], mx[1], mx[2]), Vector3(mx[4], mx[5], mx[6]), Vector3(mx[8], mx[9], mx[10])), Vector3(mx[12], mx[13], mx[14]))
			var d: Dictionary = UT.parse(head + blk)
			var J: Array = d["joints"]
			for ti in times.size():
				var f: int = ks[ti]
				var W := {}
				for ji in J.size():
					var path: String = J[ji]
					var tr: PackedFloat64Array = d["t"][f]
					var rq: PackedFloat64Array = d["r"][f]
					var loc := Transform3D(Basis(Quaternion(rq[ji * 4 + 1], rq[ji * 4 + 2], rq[ji * 4 + 3], rq[ji * 4]).normalized()), Vector3(tr[ji * 3], tr[ji * 3 + 1], tr[ji * 3 + 2]))
					var par := path.get_base_dir()
					W[path] = (W[par] if par != "" else X) * loc
					var j := path.get_file()
					var dd: float = (W[path] as Transform3D).origin.distance_to(truth[k][ti][j])
					if dd > w2:
						w2 = dd
						at2 = "%s %s t %.3f" % [pn, j, times[ti]]
	ok(prims == ["hero", "fighter_2"] and w2 <= BAR, "2 %s parsed: SkelRoots %s, every joint at 5 times worst %.4f mm (%s; bar 10 mm)" % [usd.get_file(), prims, w2 * 1000.0, at2])

	# (3) .bvh: one per actor, re-parsed
	var bvhs := files.filter(func(f): return (f as String).ends_with(".bvh"))
	var w3 := INF
	var at3 := "files " + str(bvhs)
	if bvhs == ["combo3_fighter_2.bvh", "combo3_hero.bvh"]:
		w3 = 0.0
		at3 = ""
		for k in acts.size():
			var bd: Dictionary = BT.parse(FileAccess.get_file_as_string("%s/combo3_%s.bvh" % [DIR, String(acts[k]["name"]).replace(" ", "_")]))
			for ti in times.size():
				var at: Dictionary = BT.pose(bd, bd["rows"][ks[ti]])[0]
				for j in Body.ORDER:
					var dd: float = (at[j] as Vector3).distance_to(truth[k][ti][j]) if at.has(j) else INF
					if dd > w3:
						w3 = dd
						at3 = "%s %s t %.3f" % [acts[k]["name"], j, times[ti]]
	ok(w3 <= BAR, "3 %d .bvh files %s re-parsed: every joint at 5 times worst %.4f mm (%s; bar 10 mm)" % [bvhs.size(), bvhs, w3 * 1000.0, at3])

	# game: one clip per actor, the placement in the JSON
	var gj := []
	for r in game:
		var J = JSON.parse_string(FileAccess.get_file_as_string(r[0]))
		gj.append([(r[0] as String).get_file(), J.get("placement", {}) if J is Dictionary else {}])
	ok(gj.size() == 2 and (gj[1][1] as Dictionary).get("yaw", 0.0) == 150.0 and gj[1][1].get("pos", []) == [0.4, 1.3] and (gj[0][1] as Dictionary).get("yaw", -1.0) == 0.0,
		"game: one clip per actor with its placement: %s" % [gj])

	# (5) every message names every file written
	var miss := []
	for f in files:
		var kind: String = {"glb": "glb", "usda": "usd", "bvh": "bvh", "json": "game", "cs": "game"}[(f as String).get_extension()]
		if not (f as String) in String(said[kind]):
			miss.append(f)
	ok(files.size() == 8 and miss.is_empty(), "5 %d files written, each named in its export's message (missing: %s)\n     %s" % [files.size(), miss, "\n     ".join(said.values())])

	# (1b, 3b) BLENDER's own importers
	var bl := blender_exe()
	if bl == "":
		print("BLENDER: no blender.exe found (POSER_BLENDER, C:/Program Files/Blender Foundation/*): Blender itself was NOT run")
	else:
		var want := {"fps": fps, "times": times, "frames": ks, "glb": ProjectSettings.globalize_path(glb), "bvh": {}, "actors": {}}
		for k in acts.size():
			var nm := String(acts[k]["name"])
			want["bvh"][nm] = "%s/combo3_%s.bvh" % [gdir, nm.replace(" ", "_")]
			var per := []
			for ti in times.size():
				var d := {}
				for j in ENDS:
					var p: Vector3 = truth[k][ti][j]
					d[j] = [p.x, p.y, p.z]
				per.append(d)
			want["actors"][nm] = per
		var wf := FileAccess.open(gdir + "/want.json", FileAccess.WRITE)
		wf.store_string(JSON.stringify(want))
		wf.close()
		var py := FileAccess.open(gdir + "/check.py", FileAccess.WRITE)
		py.store_string(BLENDER_PY)
		py.close()
		var out := []
		var code := OS.execute(bl, ["-b", "--factory-startup", "--python", gdir + "/check.py", "--", gdir + "/want.json"], out, true)
		var res := {}
		for ln in String(out[0]).split("\n"):
			if ln.begins_with("RESULT "):   # RESULT key|worst|armatures|where
				var f := ln.trim_prefix("RESULT ").strip_edges().split("|")
				res[f[0]] = [INF if not f[1].is_valid_float() else f[1].to_float(), f[2], f[3]]
		print("BLENDER: %s (exit %d)" % [bl, code])
		for key in ["glb", "bvh"]:
			var r: Array = res.get(key, [INF, "0", "no result"])
			ok(r[0] <= BAR, "%s BLENDER's own %s importer: %s armatures, hands/feet/head at 5 times worst %.4f mm (%s; bar 10 mm)" % ["1b" if key == "glb" else "3b", key, r[1], r[0] * 1000.0, r[2]])
		if res.size() < 2:
			print(String(out[0]).right(3000))

	m.queue_free()
	await process_frame
	clean()
	print("ACTORS EXPORT: %d failed" % fails)
	quit(1 if fails > 0 else 0)


const BLENDER_PY := """
import bpy, json, sys
from mathutils import Vector
want = json.load(open(sys.argv[sys.argv.index("--") + 1]))
sc = bpy.context.scene

def zup(p):
    return Vector((p[0], -p[2], p[1]))

def worst(arms, frame_of):
    w, at = 0.0, ""
    for name, per in want["actors"].items():
        arm = arms.get(name)
        if arm is None:
            return float("inf"), "no armature " + name
        for ti, joints in enumerate(per):
            f = frame_of(ti)
            sc.frame_set(int(f), subframe=f - int(f))
            for j, p in joints.items():
                pb = arm.pose.bones.get(j)
                if pb is None:
                    return float("inf"), "no bone %s in %s" % (j, name)
                d = ((arm.matrix_world @ pb.head) - zup(p)).length
                if d > w:
                    w, at = d, "%s %s t %.3f" % (name, j, want["times"][ti])
    return w, at

# the .glb: the scene's fps first, so a key at t lands on frame t * fps
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.fps = int(want["fps"])
bpy.ops.import_scene.gltf(filepath=want["glb"])
arms = {o.name: o for o in sc.objects if o.type == "ARMATURE"}
w, at = worst(arms, lambda ti: want["times"][ti] * want["fps"])
print("RESULT glb|%.6f|%s|%s" % (w, ",".join(sorted(arms)), at))

# each .bvh: BVH frame k on Blender frame k + 1
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
arms = {}
for name, path in want["bvh"].items():
    bpy.ops.import_anim.bvh(filepath=path, global_scale=1.0, frame_start=1, use_fps_scale=False, update_scene_fps=True, update_scene_duration=True, rotate_mode="NATIVE")
    arms[name] = bpy.context.active_object
w, at = worst(arms, lambda ti: want["frames"][ti] + 1)
print("RESULT bvh|%.6f|%s|%s" % (w, ",".join(sorted(o.name for o in arms.values())), at))
"""
