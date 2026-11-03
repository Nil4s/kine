## godot --path . -s tests/c04_test.gd     (C04; needs a window for part 4b)
## CLIP IMPORT CHECKS (scripts/clip_checks.gd; complaints #266 A-pose, #587/#594 proportion and size, #7 stay in place).
## BARS, written and committed BEFORE the first run:
##  1 POSE (#266): the Mixamo fixture (arms 40 deg off Kine's T) -> kind "A-pose", deg within 39..41, a warning that says the
##    retarget turns the arms back; the end-to-end AnimImport.import_file result carries that warning. CONTROL: our own .glb
##    (a T-pose) -> "T-pose", NO warning (a check that always warned would pass the first half). rest_deg 80 -> "arms at the torso".
##  2 SIZE (#594): the fixture (leg ratio 0.833) -> no size warning (control). Ratio 0.5 and 2.0 -> a warning that names the
##    factor "2.0x" and says "re-authoring". The fixture's rest scaled x3 through analyze() -> a size warning (end to end).
##  3 PROPORTIONS (#587): the fixture (a uniform 1.2 x) -> dev < 0.05, no warning (control). Kine's rest with the arms 1.6 x ->
##    dev > 0.5 and a "stylised proportions" warning.
##  4 STAY IN PLACE (#7): a scene whose hips travel > 0.3 m (the fixture's retarget). BEFORE: travel > 0.3 m (control: it really
##    travels). AFTER ClipChecks.strip_travel: every card's x and z equal card 0's within 1e-6, every card's height (y) and every
##    joint angle unchanged within 1e-6, strip_travel reports >= 0.3 m. Run again on the stripped scene -> 0.0 m (no-op).
##  4b In the app: the ribbon button "Stay in place" exists with its icon and no words inside the MIRROR group, one press strips
##    the open scene (travel < 1e-6 from > 0.3 m), ONE undo restores the scene hash. Screenshot at 1280x720.
extends SceneTree

var fails := 0
const FIX := "res://tests/fixtures/mixamo_rig.fbx"
const DIR := "user://zz_c04"
const SHOT := "C:/Users/Nick/tools/kine_workers/out/c04"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func travel(S: Scene) -> float:
	var o0 := ClipChecks._off(S.cards[0]["pose"])
	var far := 0.0
	for c in S.cards:
		var o := ClipChecks._off(c["pose"])
		far = maxf(far, Vector2(o.x - o0.x, o.z - o0.z).length())
	return far


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var fx := ProjectSettings.globalize_path(FIX)
	var src := AnimImport.load_source(fx)
	var mp := AnimImport.map_bones(src)
	var rt := AnimImport.retarget(src, mp, B, "zz_c04")
	ok(src["ok"] and rt["ok"], "fixture read and retargeted")

	# 1 POSE
	var po := ClipChecks.pose_check(rt["rest_deg"])
	ok(po["kind"] == "A-pose" and po["deg"] > 39.0 and po["deg"] < 41.0 and String(po["warn"]).contains("turns each arm back"), "1 fixture: %s, %.1f deg, warn: %s" % [po["kind"], po["deg"], po["warn"]])
	var imp := AnimImport.import_file(fx, B, "zz_c04_imp")
	var ws: Array = imp.get("warnings", [])
	ok(imp["ok"] and ws.size() >= 1 and String(ws[0]).contains("A-pose"), "1 import_file carries the A-pose warning (%d warnings)" % ws.size())
	var S0 := Scene.new()
	S0.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json")))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var glb := DIR + "/zz_c04.glb"
	GltfExport.write(S0, B, glb)
	var gs := AnimImport.load_source(ProjectSettings.globalize_path(glb))
	var gm := AnimImport.map_bones(gs)
	var gr := AnimImport.retarget(gs, gm, B, "zz_c04g")
	var gp := ClipChecks.pose_check(gr["rest_deg"])
	ok(gp["kind"] == "T-pose" and String(gp["warn"]) == "", "1 control: our own .glb is a %s, warn '%s'" % [gp["kind"], gp["warn"]])
	var gi := AnimImport.import_file(ProjectSettings.globalize_path(glb), B, "zz_c04_g")
	ok(gi["ok"] and (gi["warnings"] as Array).is_empty(), "1 control: its import has no warnings (%s)" % [gi.get("warnings")])
	ok(ClipChecks.pose_check({"upperarm_l": 80.0, "upperarm_r": 79.0})["kind"] == "arms at the torso", "1 80 deg -> arms at the torso")

	# 2 SIZE
	var sz := ClipChecks.size_check(float(rt["ratio"]))
	ok(String(sz["warn"]) == "", "2 control: fixture ratio %.3f -> no size warning" % rt["ratio"])
	var s5 := ClipChecks.size_check(0.5)
	var s2 := ClipChecks.size_check(2.0)
	ok(String(s5["warn"]).contains("2.0x") and String(s5["warn"]).contains("re-authoring") and String(s2["warn"]).contains("2.0x") and String(s2["warn"]).contains("re-authoring"), "2 ratio 0.5 and 2.0 warn: %s" % s5["warn"])
	var big: Dictionary = src.duplicate(true)
	var rest3 := []
	for x in src["rest"]:
		var t: Transform3D = x
		rest3.append(Transform3D(t.basis, t.origin * 3.0))
	big["rest"] = rest3
	var rt3 := AnimImport.retarget(big, mp, B, "zz_c04_big")
	var an3 := ClipChecks.analyze(big, mp, B, rt3)
	ok(String(an3["size"]["warn"]) != "", "2 end to end: the rig scaled x3 -> ratio %.3f -> %s" % [rt3["ratio"], an3["size"]["warn"]])

	# 3 PROPORTIONS
	var sp := {}
	for j in mp["map"]:
		sp[j] = (src["rest"][mp["map"][j]] as Transform3D).origin
	var kp := {}
	for j in Body.ORDER:
		kp[j] = B.p0[j]
	var pc := ClipChecks.proportion_check(sp, kp)
	ok(pc["dev"] < 0.05 and String(pc["warn"]) == "", "3 control: uniform 1.2 x rig dev %.3f, warn '%s'" % [pc["dev"], pc["warn"]])
	var kq := kp.duplicate()
	for sd in ["_l", "_r"]:
		var ua: Vector3 = kp["upperarm" + sd]
		for j in ["lowerarm", "hand"]:
			kq[j + sd] = ua + ((kp[j + sd] as Vector3) - ua) * 1.6
	var pq := ClipChecks.proportion_check(kq, kp)
	ok(pq["dev"] > 0.5 and String(pq["warn"]).contains("stylised proportions"), "3 arms 1.6 x: dev %.3f -> %s" % [pq["dev"], pq["warn"]])

	# 4 STAY IN PLACE
	var T: Scene = imp["scene"]
	var tr0 := travel(T)
	ok(tr0 > 0.3, "4 control: the imported scene's hips travel %.2f m" % tr0)
	var before: Array = JSON.parse_string(JSON.stringify(T.cards))
	var res := ClipChecks.strip_travel(T)
	var bad_xz := 0.0
	var bad_y := 0.0
	var bad_j := 0.0
	var o0 := ClipChecks._off(T.cards[0]["pose"])
	for i in T.cards.size():
		var o := ClipChecks._off(T.cards[i]["pose"])
		var ob := ClipChecks._off(before[i]["pose"])
		bad_xz = maxf(bad_xz, Vector2(o.x - o0.x, o.z - o0.z).length())
		bad_y = maxf(bad_y, absf(o.y - ob.y))
		var ja: Dictionary = T.cards[i]["pose"]["joints"]
		var jb: Dictionary = before[i]["pose"]["joints"]
		for j in ja:
			for k in ["bend", "side", "twist"]:
				bad_j = maxf(bad_j, absf(float(ja[j][k]) - float(jb[j][k])))
	ok(bad_xz < 1e-6 and bad_y < 1e-6 and bad_j < 1e-6 and res["metres"] >= 0.3, "4 stripped %d cards: xz drift %s, y change %s, joint change %s, reported %.2f m" % [res["cards"], str(bad_xz), str(bad_y), str(bad_j), res["metres"]])
	var res2 := ClipChecks.strip_travel(T)
	ok(res2["metres"] < 1e-6, "4 a scene with no travel: %s m (no-op)" % str(res2["metres"]))

	# 4b in the app
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 6:
		await process_frame
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.size = Vector2i(1280, 720)
	var imp2 := AnimImport.import_file(fx, B, "zz_c04_imp2")
	m.S.from_dict((imp2["scene"] as Scene).to_dict(B))
	m._rebuild_cards()
	for i in 4:
		await process_frame
	var btn: Button = null
	for b in m.ui_ribbon["ANIMATE"].get_children():
		if b is Button and m.label_of(b) == "Stay in place":
			btn = b
	var in_group: bool = "Stay in place" in (m.RIBBON_GROUPS["ANIMATE"].filter(func(g): return g[0] == "MIRROR")[0][1])
	ok(btn != null and btn.icon != null and btn.text == "" and in_group, "4b ribbon button 'Stay in place' with icon, no words, in MIRROR")
	m.ui_ribbon_tabs["ANIMATE"].pressed.emit()
	for i in 6:
		await process_frame
	var h0: int = JSON.stringify(m._scene_dict(false)).hash()
	var t_before := travel(m.S)
	ok(t_before > 0.3, "4b the open scene travels %.2f m" % t_before)
	btn.pressed.emit()
	for i in 3:
		await process_frame
	ok(travel(m.S) < 1e-6, "4b one press: travel %s m" % str(travel(m.S)))
	DirAccess.make_dir_recursive_absolute(SHOT)
	m.get_viewport().get_texture().get_image().save_png(SHOT + "/stay_in_place_1280x720.png")
	m._undo()
	for i in 3:
		await process_frame
	ok(JSON.stringify(m._scene_dict(false)).hash() == h0, "4b one undo restores the scene hash")
	print("C04 TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
