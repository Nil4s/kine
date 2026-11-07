## godot --path . -s tests/anykey_test.gd     (ROADMAP_400 track L: L13 shape-key animation, L15 any property keyed, L16 bake from anything)
## scripts/any_key.gd. Scene.anykeys = {"<id>": {"keys": [{"t", "v": Vector3}]}}, ids "shape:<mesh>:<key>" and "prop:<target>:<path>".
## Bars, written BEFORE the implementation and never moved after a run:
##   1 SHAPE KEY (L13): weight keyed 0 at t0 and 1 at t1 reads 0.5 at the midpoint within 1e-6 (AnyKey.float_at AND the
##     KMesh key's value after Scene.apply); a vertex of the key sits at basis + 0.5 x delta within 1e-6; the dope sheet lists
##     a row for the id with a diamond at t0 and at t1; save -> JSON -> load -> save is the same text and the same midpoint.
##   2 PROPERTY (L15): StandardMaterial3D roughness keyed 0 -> 1 reads 0.5 at the midpoint after Scene.apply within 1e-6; a light's
##     light_energy keyed 2 -> 6 reads 4 within 1e-6; an UNKEYED property (metallic, albedo, a second material's roughness)
##     stays byte-identical (var_to_bytes) and a scene with no anykeys writes no "anykeys" in its file.
##   3 BAKE (L16): hand_l child_of hand_r over 30 frames (0..29 at 30 fps). The constraint really moves the hand (>= 1 deg
##     vs no constraint). Baked as plain part keys: each baked joint's key value at each frame == the live constrained pose
##     within 1e-5 (per frame, per angle). With the source removed (cons empty): playback at every frame == the pre-bake
##     playback within 1e-5. Without remove_source the constraint stays.
##   4 CONTROL: a bake that skips every other frame (step 2) must FAIL the per-frame bar (> 1e-5 somewhere on the full playback).
##   5 UNDO: shape key, property key and "bake + remove source" are each ONE undo step; Ctrl+Z gives the old scene back
##     (anykeys / part keys / constraints as they were).
extends SceneTree

var fails := 0
var m: Node
const CV := [Vector3(0,0,0), Vector3(1,0,0), Vector3(1,1,0), Vector3(0,1,0), Vector3(0,0,1), Vector3(1,0,1), Vector3(1,1,1), Vector3(0,1,1)]
const CF := [[0,3,2,1], [4,5,6,7], [0,1,5,4], [2,3,7,6], [1,2,6,5], [0,4,7,3]]


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	if not c:
		fails += 1


func play(S: Scene, B: Body, n: int) -> Array:
	var out := []
	for f in n:
		S.apply(B, float(f) / S.fps)
		out.append(B.ang.duplicate())
	return out


func worst(a: Array, b: Array) -> float:
	var w := 0.0
	for f in mini(a.size(), b.size()):
		for j in a[f]:
			var x: Vector3 = a[f][j]
			var y: Vector3 = b[f][j]
			w = maxf(w, maxf(absf(x.x - y.x), maxf(absf(x.y - y.y), absf(x.z - y.z))))
	return w


func scene3(_unused: Body) -> Scene:
	var B := Body.new()   # a fresh rest body per scene: the cards must not inherit the last scene's pose
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var S := Scene.new()
	S.name = "zz_anykey"
	S.fps = 30
	B.fk()
	S.add("a", B.to_dict())
	B.ang["upperarm_r"] = Vector3(70, 40, 10)
	B.ang["lowerarm_r"] = Vector3(50, 0, 0)
	B.fk()
	S.add("b", B.to_dict())
	B.ang["upperarm_r"] = Vector3(-30, 80, -20)
	B.ang["lowerarm_r"] = Vector3(10, 0, 0)
	B.fk()
	S.add("c", B.to_dict())
	S.cards[1]["move"] = 0.6
	S.cards[2]["move"] = 0.5
	return S


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 6:
		await process_frame
	m.tour_step = -1
	var S := scene3(B)
	m.S = S
	m._rebuild_cards()
	m._refresh()
	await process_frame
	var t0 := 0.0
	var t1 := 1.0
	var tm := 0.5

	# ---- 1 shape key
	var mesh := KMesh.new().from_arrays(PackedVector3Array(CV), CF)
	var d := PackedVector3Array()
	d.resize(8)
	d[6] = Vector3(0.5, 0.25, 0)
	KMeshShapes.add_key(mesh, "smile", d, KMeshShapes.BASIS, 0.0)
	AnyKey.meshes = {"head": mesh}
	AnyKey.targets = {}
	var sid := AnyKey.shape_id("head", "smile")
	var u0: int = m.undo.size()
	m.playhead = t0
	m._anykey_put(sid, 0.0)
	ok(m.undo.size() == u0 + 1, "5a shape key put = one undo step (%d -> %d)" % [u0, m.undo.size()])
	m.playhead = t1
	m._anykey_put(sid, 1.0)
	ok(m.undo.size() == u0 + 2, "5b second shape key put = one more undo step")
	var mid := AnyKey.float_at(S, sid, tm)
	ok(absf(mid - 0.5) <= 1e-6, "1a shape key weight at the midpoint = %.9f (bar 0.5 +- 1e-6)" % mid)
	S.apply(B, tm)
	var kv: float = float(KMeshShapes.keys(mesh)[0]["value"])
	ok(absf(kv - 0.5) <= 1e-6, "1b the KMesh key value after Scene.apply = %.9f" % kv)
	KMeshShapes.apply(mesh)
	var want: Vector3 = CV[6] + d[6] * 0.5
	var dv := (mesh.verts[6] - want).length()
	ok(dv <= 1e-6, "1c vertex 6 sits at basis + 0.5 delta: off by %.9f" % dv)
	var dope := DopeSheet.new()
	dope.m = m
	var rows := DopeSheet.any_rows(S)
	var found := {}
	for dm in dope.canvas.diamonds():
		if dm.get("any", "") == sid:
			found[snappedf(float(dm["t"]), 0.001)] = true
	ok(rows.has(sid) and found.has(0.0) and found.has(1.0), "1d the dope sheet lists row %s with diamonds at %s (rows: %s)" % [sid, found.keys(), rows])
	var txt1 := JSON.stringify(S.to_dict(B))
	var S2 := Scene.new()
	S2.from_dict(JSON.parse_string(txt1))
	var txt2 := JSON.stringify(S2.to_dict(B))
	ok(txt1 == txt2 and txt1.contains("anykeys") and absf(AnyKey.float_at(S2, sid, tm) - mid) <= 1e-9, "1e save/reload identical (%d chars), midpoint %.9f" % [txt1.length(), AnyKey.float_at(S2, sid, tm)])

	# ---- 2 property
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.37
	mat.metallic = 0.61
	mat.albedo_color = Color(0.2, 0.4, 0.6)
	var other := StandardMaterial3D.new()
	other.roughness = 0.81
	var lamp := OmniLight3D.new()
	lamp.light_energy = 1.0
	AnyKey.targets = {"skin": mat, "other": other, "lamp": lamp}
	var rid := AnyKey.prop_id("skin", "roughness")
	var lid := AnyKey.prop_id("lamp", "light_energy")
	var before_unkeyed := var_to_bytes([mat.metallic, mat.albedo_color, other.roughness, other.metallic])
	m.playhead = t0
	u0 = m.undo.size()
	m._anykey_put(rid, 0.0)
	ok(m.undo.size() == u0 + 1, "5c property key put = one undo step")
	m.playhead = t1
	m._anykey_put(rid, 1.0)
	m.playhead = t0
	m._anykey_put(lid, 2.0)
	m.playhead = t1
	m._anykey_put(lid, 6.0)
	S.apply(B, tm)
	ok(absf(mat.roughness - 0.5) <= 1e-6, "2a roughness at the midpoint = %.9f" % mat.roughness)
	ok(absf(lamp.light_energy - 4.0) <= 1e-6, "2b light_energy at the midpoint = %.9f" % lamp.light_energy)
	ok(var_to_bytes([mat.metallic, mat.albedo_color, other.roughness, other.metallic]) == before_unkeyed, "2c unkeyed properties byte-identical")
	var plain := scene3(B)
	mat.roughness = 0.37
	var rough_bytes := var_to_bytes(mat.roughness)   # float32 storage: compare what the material holds, not the double 0.37
	plain.apply(B, tm)
	ok(var_to_bytes(mat.roughness) == rough_bytes and not JSON.stringify(plain.to_dict(B)).contains("anykeys"), "2d a scene without anykeys leaves roughness 0.37 and writes no anykeys")

	# ---- 3 bake
	var Sb := scene3(B)
	Sb.apply(B, 0.0)
	var c := Constraints.add_child_of(Sb, B, "hand_l", {"kind": "part", "part": "hand_r"}, 0.0)
	ok(not c.is_empty(), "3a child_of made")
	var live := play(Sb, B, 30)
	var Sn := scene3(B)
	var nocons := play(Sn, B, 30)
	var moved := worst(live, nocons)
	ok(moved >= 1.0, "3b the constraint moves the hand: worst %.3f deg vs no constraint (bar >= 1)" % moved)
	m.S = Sb
	m._rebuild_cards()
	m._refresh()
	await process_frame
	u0 = m.undo.size()
	var rep: Dictionary = m._bake_any([], 0, 29, true)
	ok(m.undo.size() == u0 + 1, "5d bake + remove source = one undo step (%d -> %d)" % [u0, m.undo.size()])
	var Sa: Scene = m.S
	var wk := 0.0
	for f in 30:
		for j in rep.get("joints", []):
			var kv3: Vector3 = PartKeys.at(Sa.part_keys[j], float(f) / Sa.fps)
			var lv: Vector3 = live[f][j]
			wk = maxf(wk, maxf(absf(kv3.x - lv.x), maxf(absf(kv3.y - lv.y), absf(kv3.z - lv.z))))
	ok((rep.get("joints", []) as Array).size() > 0 and wk <= 1e-5, "3c baked keys vs live pose per frame: worst %.9f deg over %s (bar 1e-5)" % [wk, rep.get("joints", [])])
	ok(Sa.cons.is_empty(), "3d source removed: %d constraints left" % Sa.cons.size())
	var after := play(Sa, B, 30)
	var wp := worst(after, live)
	ok(wp <= 1e-5, "3e playback after removing the source vs pre-bake: worst %.9f deg (bar 1e-5)" % wp)
	m._undo()
	ok(m.S.cons.size() == 1 and m.S.part_keys.is_empty(), "5e Ctrl+Z gives the constraint back and no part keys (cons %d, keys %d)" % [m.S.cons.size(), m.S.part_keys.size()])
	var Sk := scene3(B)
	Sk.apply(B, 0.0)
	Constraints.add_child_of(Sk, B, "hand_l", {"kind": "part", "part": "hand_r"}, 0.0)
	AnyKey.bake(Sk, B, [], 0, 29, true, 1)
	ok(Sk.cons.is_empty() and worst(play(Sk, B, 30), live) <= 1e-5, "3f direct AnyKey.bake step 1 equals the live pose")
	var Sc := scene3(B)
	Sc.apply(B, 0.0)
	Constraints.add_child_of(Sc, B, "hand_l", {"kind": "part", "part": "hand_r"}, 0.0)
	AnyKey.bake(Sc, B, [], 0, 29, false, 1)
	ok(Sc.cons.size() == 1, "3g without remove_source the constraint stays")

	# ---- 4 control: skipping frames
	var Ss := scene3(B)
	Ss.apply(B, 0.0)
	Constraints.add_child_of(Ss, B, "hand_l", {"kind": "part", "part": "hand_r"}, 0.0)
	AnyKey.bake(Ss, B, [], 0, 29, true, 2)
	var ws := worst(play(Ss, B, 30), live)
	ok(ws > 1e-5, "4 CONTROL: a bake skipping every other frame fails the per-frame bar: worst %.6f deg (> 1e-5 expected)" % ws)

	print("anykey: %d fail" % fails)
	quit(1 if fails > 0 else 0)
