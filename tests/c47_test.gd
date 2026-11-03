extends SceneTree
## godot --headless --path . -s tests/c47_test.gd   (C47: #273 mirror facing axis from geometry, #274 side from geometry, #251 mirror seam continuity)
## Bars (written and committed before the numbers were read):
##  1 FACING  a body in Kine's frame (heading < 20 deg): MirrorFacing.mirror == Body.mirror_pose byte for byte (ang, offset, weapon), on 10 card poses.
##            A body turned 90 / -90 / 180 deg: heading detected within 1 deg; every joint end and joint lands on the reflection through the
##            plane (normal = its left axis, through the rest pelvis) within 2 mm; mirrored twice = the pose within 1 mm.
##            CONTROL: the same turned body under the old Body.mirror_pose is off by more than 50 mm (the bar can fail).
##            A pelvis twisted 15 deg in the front frame stays "not turned".
##  2 SIDE    Kine's own rest laid out as a source: SideCheck 0 findings; the Mixamo fixture: 0 findings (a correctly named rig reports none).
##            One pair swapped (thigh_l <-> thigh_r in the map): exactly 1 finding, kind swapped_pair, bone thigh.
##            Whole rig swapped (every _l <-> _r): exactly 1 finding, kind swapped_rig. CONTROL = the two planted cases.
##            AnimImport calls SideCheck (source text) and its words land in the import warnings.
##  3 SEAM    a box standing on the plane: kink 0 (<= 0.5 deg), no warning; a sloped roof meeting the plane: kink within 2 deg of 2*asin(0.447) = 53.1;
##            warning present with the angle in words; "seam_deg" 80 silences it; without "seam" no warning and the same volume as with it (default unchanged).
##            CONTROL: the roof without the flag has no warning (the flag is what asks).
var fails := 0
const FIX := "res://tests/fixtures/mixamo_rig.fbx"


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func newbody() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	return B


func load_scene(path: String) -> Scene:
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string(path)))
	return S


func same(a: Body, b: Body) -> bool:
	for j in Body.ORDER:
		if a.ang[j] != b.ang[j]:
			return false
	return a.offset == b.offset and a.wep_pos == b.wep_pos and a.wep_rot == b.wep_rot and a.wep_hand == b.wep_hand


func turn(B: Body, deg: float) -> void:
	var r := Quaternion(Vector3.UP, deg_to_rad(deg))
	B.ang["pelvis"] = B.decompose("pelvis", r * B.compose("pelvis", B.ang["pelvis"]))
	B.fk()


func reflect_err(a: Body, m: Body, n: Vector3, c: Vector3) -> float:
	var worst := 0.0
	for j in Body.ORDER:
		var p: Vector3 = a.P[j]
		var q := p - 2.0 * n.dot(p - c) * n
		worst = maxf(worst, (m.P[Body.twin(j)] as Vector3).distance_to(q))
		var e: Vector3 = a.E[j]
		worst = maxf(worst, (m.E[Body.twin(j)] as Vector3).distance_to(e - 2.0 * n.dot(e - c) * n))
	return worst


func _init() -> void:
	var B := newbody()
	var M := newbody()
	var Sc := load_scene("res://scenes/combo3.json")
	var nsame := 0
	var tot := 0
	for k in mini(10, Sc.cards.size()):
		B.from_dict(Sc.cards[k]["pose"])
		M.from_dict(Sc.cards[k]["pose"])
		B.mirror_pose()
		MirrorFacing.mirror(M)
		tot += 1
		nsame += 1 if same(B, M) else 0
	ok(nsame == tot, "1 FACING front frame: Mirror to facing == Mirror pose byte for byte on %d/%d card poses" % [nsame, tot])
	var c0 := (B.p0["pelvis"] as Vector3)
	for h in [90.0, -90.0, 180.0]:
		B.from_dict(Sc.cards[9]["pose"])
		turn(B, h)
		var det := MirrorFacing.detect(B)
		var hd: float = det["heading"]
		ok(absf(angle_difference(deg_to_rad(hd), deg_to_rad(h))) < deg_to_rad(1.0) and det["turned"], "1 FACING heading %.0f detected as %.2f" % [h, hd])
		var n := Quaternion(Vector3.UP, deg_to_rad(h)) * Vector3.RIGHT
		M.from_dict(B.to_dict())
		M.fk()
		MirrorFacing.mirror(M)
		var e := reflect_err(B, M, n, c0)
		ok(e < 0.002, "1 FACING turned %.0f: mirror lands on the reflection through its own middle plane, worst %.2f mm" % [h, e * 1000.0])
		var M2 := newbody()
		M2.from_dict(B.to_dict())
		M2.fk()
		M2.mirror_pose()
		var eo := reflect_err(B, M2, n, c0)
		ok(eo > 0.05, "1 CONTROL turned %.0f under the old mirror is off by %.0f mm (the bar can fail)" % [h, eo * 1000.0])
		MirrorFacing.mirror(M)
		var tw := 0.0
		for j in Body.ORDER:
			tw = maxf(tw, (M.P[j] as Vector3).distance_to(B.P[j]))
		ok(tw < 0.001, "1 FACING turned %.0f: mirrored twice = the pose, worst %.3f mm" % [h, tw * 1000.0])
	B.from_dict(Sc.cards[9]["pose"])
	turn(B, 15.0)
	ok(not MirrorFacing.detect(B)["turned"], "1 FACING a pelvis twisted 15 deg in the front frame is not a turned body (heading %.1f)" % MirrorFacing.heading(B))

	# ---- 2 SIDE
	var src := {"names": [], "parent": [], "rest": []}
	var mp := {}
	var K := newbody()
	for j in Body.ORDER:
		mp[j] = (src["names"] as Array).size()
		(src["names"] as Array).append(j)
		(src["parent"] as Array).append(-1)
		(src["rest"] as Array).append(Transform3D(Basis(), K.p0[j]))
	for j in Body.ORDER:
		(src["parent"] as Array)[mp[j]] = (src["names"] as Array).find(K.parent[j]) if K.parent[j] != "" else -1
	var r0 := SideCheck.check(src, {"map": mp})
	ok((r0["findings"] as Array).is_empty() and r0["text"] == "", "2 SIDE Kine's own rest: no finding")
	var fs := AnimImport.load_source(ProjectSettings.globalize_path(FIX))
	var rf := SideCheck.check(fs, RetargetMap.resolve(fs))
	ok((rf["findings"] as Array).is_empty(), "2 SIDE Mixamo fixture (correctly named): no finding (%s)" % rf["text"])
	var m1 := mp.duplicate()
	m1["thigh_l"] = mp["thigh_r"]
	m1["thigh_r"] = mp["thigh_l"]
	var r1 := SideCheck.check(src, {"map": m1})
	var f1: Array = r1["findings"]
	ok(f1.size() == 1 and f1[0]["kind"] == "swapped_pair" and f1[0]["bone"] == "thigh", "2 SIDE one pair swapped: %s" % r1["text"])
	var m2 := mp.duplicate()
	for j in Body.ORDER:
		if j.ends_with("_l"):
			m2[j] = mp[j.substr(0, j.length() - 2) + "_r"]
			m2[j.substr(0, j.length() - 2) + "_r"] = mp[j]
	var r2 := SideCheck.check(src, {"map": m2})
	var f2: Array = r2["findings"]
	ok(f2.size() == 1 and f2[0]["kind"] == "swapped_rig", "2 SIDE whole rig swapped: %s" % r2["text"])
	var ai := FileAccess.get_file_as_string("res://scripts/anim_import.gd")
	ok(ai.contains("SideCheck.check(src, mapping)") and ai.contains("(checks[\"warnings\"] as Array).append(sc[\"text\"])"), "2 SIDE AnimImport runs the check and adds its words to the warnings")

	# ---- 3 SEAM
	if not Part.available():
		ok(false, "3 SEAM needs the CAD DLL")
	else:
		var box := _rec([_sk("f1", [[0, 0], [20, 0], [20, 20], [0, 20]]), _ext("f2", "f1")], true, {})
		var roof := _rec([_sk("f1", [[0, 0], [20, 0], [20, 10], [0, 20]]), _ext("f2", "f1")], true, {})
		var bx := Part.replay(box)
		var rr := Part.replay(roof)
		ok(not (bx["warnings"] as Dictionary).has("f3") and not (bx["errors"] as Dictionary).has("f3"), "3 SEAM box on the plane: no warning")
		var rw: Dictionary = rr["warnings"]
		ok(rw.has("f3") and (String(rw["f3"]).contains("53 degrees") or String(rw["f3"]).contains("52 degrees") or String(rw["f3"]).contains("54 degrees")), "3 SEAM sloped roof: warning with the ridge angle 53 +-1: %s" % str(rw.get("f3", "")))
		var quiet := Part.replay(_rec([_sk("f1", [[0, 0], [20, 0], [20, 10], [0, 20]]), _ext("f2", "f1")], true, {"seam_deg": 80.0}))
		ok(not (quiet["warnings"] as Dictionary).has("f3"), "3 SEAM seam_deg 80 silences the 53 degree ridge")
		var off := Part.replay(_rec([_sk("f1", [[0, 0], [20, 0], [20, 10], [0, 20]]), _ext("f2", "f1")], false, {}))
		ok(not (off["warnings"] as Dictionary).has("f3"), "3 CONTROL roof without the seam flag: no warning")
		ok(absf(float(off["volume"]) - float(rr["volume"])) < 1e-12 and float(rr["volume"]) > 0.0, "3 SEAM the mirror is unchanged by the flag: volume %.9f vs %.9f" % [rr["volume"], off["volume"]])
	print("c47: %d fail" % fails)
	quit(1 if fails > 0 else 0)


func _sk(id: String, pts: Array) -> Dictionary:
	var ents := []
	for i in pts.size():
		var a: Array = pts[i]
		var b: Array = pts[(i + 1) % pts.size()]
		ents.append({"k": "line", "a": [float(a[0]), float(a[1])], "b": [float(b[0]), float(b[1])]})
	return {"t": "sketch", "id": id, "name": "S" + id, "plane": "front", "ents": ents, "dims": []}


func _ext(id: String, sk: String) -> Dictionary:
	return {"t": "extrude", "id": id, "name": "E" + id, "sketch": sk, "dist": 10.0, "both": true, "op": "new"}


func _rec(feats: Array, seam: bool, extra: Dictionary) -> Dictionary:
	var r := Part.make("c47")
	var f := {"t": "mirror", "id": "f3", "name": "Mirror1", "plane": "right", "op": "join"}
	if seam:
		f["seam"] = true
	f.merge(extra, true)
	r["features"] = feats + [f]
	r["seq"] = 3
	return r
