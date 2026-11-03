## godot --path . -s tests/c08_test.gd     (C08; complaints #274 side from geometry, #273 facing axis, #543 hand bend after BVH import)
## BARS, written and committed BEFORE the first run:
##  1 SIDES (#274): the Mixamo fixture -> swapped false, no warning (control). The same rest with x negated (a mirror image: every
##    bone named _l now sits on the character's right) -> swapped true and a warning containing "left and right" and "names"; end to
##    end through ClipChecks.analyze the warning is in analyze()["warnings"]. Our own .glb import -> no sides warning (control).
##    A rest with no feet/ball bones -> kind "names only", swapped false, no warning (it must not guess).
##  2 FACING (#273): fixture -> face_deg < 15 and no facing warning (control). The rest turned 180 deg about up -> face_deg within
##    175..185, axis "-Z", swapped false (a turn is not a mirror), a warning containing "faces -Z". Turned 90 deg -> face_deg 85..95.
##  3 HANDS (#543): a scene whose fingers all sit inside Kine's limits -> text "" (control). A scene with index_02_l bend past the
##    upper limit by 60 deg on 5 of 10 cards -> joints 1, cards_out 5, worst joint "index_02_l" axis "bend", over_deg within
##    59..61, text containing "index_02_l" and "5 of 10". A twist 40 deg past the limit on thumb_01_r on 2 cards -> joints 2.
##    A Kine .bvh exported from an in-range scene and imported with AnimImport.import_file -> no hands warning (control).
extends SceneTree

var fails := 0
const FIX := "res://tests/fixtures/mixamo_rig.fbx"
const DIR := "user://zz_c08"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func rest_pos(src: Dictionary, mp: Dictionary) -> Dictionary:
	var sp := {}
	for j in mp["map"]:
		sp[j] = (src["rest"][mp["map"][j]] as Transform3D).origin
	return sp


func turned(pos: Dictionary, deg: float) -> Dictionary:
	var o := {}
	for j in pos:
		o[j] = (pos[j] as Vector3).rotated(Vector3.UP, deg_to_rad(deg))
	return o


func hands_scene(B: Body, joint: String, axis: String, add: float, n_bad: int, n := 10) -> Scene:
	var S := Scene.new()
	var base := {}
	for i in n:
		var jd := {}
		for f in Body.FINGERS:
			jd[f] = {"bend": 5.0, "side": 0.0, "twist": 0.0}
		if joint != "" and i < n_bad:
			var r: Vector2 = B.lim[joint][axis]
			jd[joint][axis] = (r.y if add > 0.0 else r.x) + add
		S.add("c%d" % i, {"joints": jd, "offset": [0, 0, 0]})
	return S


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var fx := ProjectSettings.globalize_path(FIX)
	var src := AnimImport.load_source(fx)
	var mp := AnimImport.map_bones(src)
	var pos := rest_pos(src, mp)

	# 1 SIDES
	var s0 := SideChecks.sides(pos)
	ok(not s0["swapped"] and String(s0["warn_sides"]) == "", "1 control: fixture swapped=%s kind=%s warn '%s'" % [s0["swapped"], s0["kind"], s0["warn_sides"]])
	var mir := {}
	for j in pos:
		var v: Vector3 = pos[j]
		mir[j] = Vector3(-v.x, v.y, v.z)
	var s1 := SideChecks.sides(mir)
	ok(s1["swapped"] and String(s1["warn_sides"]).contains("left and right") and String(s1["warn_sides"]).contains("names"), "1 mirror image: swapped=%s warn: %s" % [s1["swapped"], s1["warn_sides"]])
	var mrest := []
	for x in src["rest"]:
		var t: Transform3D = x
		mrest.append(Transform3D(t.basis, Vector3(-t.origin.x, t.origin.y, t.origin.z)))
	var msrc: Dictionary = src.duplicate(true)
	msrc["rest"] = mrest
	var rt := AnimImport.retarget(src, mp, B, "zz_c08")
	var an := ClipChecks.analyze(msrc, mp, B, rt)
	var found := false
	for w in an["warnings"]:
		found = found or String(w).contains("left and right")
	ok(found, "1 end to end: analyze() on the mirror-image rig carries the sides warning")
	var an0 := ClipChecks.analyze(src, mp, B, rt)
	var f0 := false
	for w in an0["warnings"]:
		f0 = f0 or String(w).contains("left and right") or String(w).contains("faces")
	ok(not f0, "1 control: analyze() on the fixture has no sides or facing warning (%s)" % [an0["warnings"]])
	var S0 := Scene.new()
	S0.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json")))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var glb := DIR + "/zz_c08.glb"
	GltfExport.write(S0, B, glb)
	var gi := AnimImport.import_file(ProjectSettings.globalize_path(glb), B, "zz_c08_g")
	var gw := false
	for w in gi.get("warnings", []):
		gw = gw or String(w).contains("left and right") or String(w).contains("faces")
	ok(gi["ok"] and not gw, "1 control: our own .glb has no sides or facing warning (%s)" % [gi.get("warnings")])
	var nof := {}
	for j in pos:
		if not (String(j).begins_with("ball") or String(j).begins_with("foot")):
			nof[j] = pos[j]
	var s2 := SideChecks.sides(nof)
	ok(s2["kind"] == "names only" and not s2["swapped"] and String(s2["warn_sides"]) == "", "1 no feet: kind '%s', swapped=%s, warn '%s'" % [s2["kind"], s2["swapped"], s2["warn_sides"]])

	# 2 FACING
	ok(float(s0["face_deg"]) < 15.0 and String(s0["warn_facing"]) == "", "2 control: fixture faces %s, %.1f deg off +Z, warn '%s'" % [s0["axis"], s0["face_deg"], s0["warn_facing"]])
	var s3 := SideChecks.sides(turned(pos, 180.0))
	ok(float(s3["face_deg"]) > 175.0 and float(s3["face_deg"]) < 185.0 and s3["axis"] == "-Z" and not s3["swapped"] and String(s3["warn_facing"]).contains("faces -Z"), "2 turned 180: %.1f deg, axis %s, swapped=%s, warn: %s" % [s3["face_deg"], s3["axis"], s3["swapped"], s3["warn_facing"]])
	var s4 := SideChecks.sides(turned(pos, 90.0))
	ok(float(s4["face_deg"]) > 85.0 and float(s4["face_deg"]) < 95.0 and not s4["swapped"], "2 turned 90: %.1f deg, axis %s" % [s4["face_deg"], s4["axis"]])

	# 3 HANDS
	var h0 := HandCheck.check(hands_scene(B, "", "bend", 0.0, 0), B)
	ok(String(h0["text"]) == "" and h0["joints"] == 0, "3 control: in-range fingers -> text '%s'" % h0["text"])
	var h1 := HandCheck.check(hands_scene(B, "index_02_l", "bend", 60.0, 5), B)
	ok(h1["joints"] == 1 and h1["cards_out"] == 5 and h1["worst"]["joint"] == "index_02_l" and h1["worst"]["axis"] == "bend" and absf(float(h1["worst"]["over_deg"]) - 60.0) < 1.0 and String(h1["text"]).contains("index_02_l") and String(h1["text"]).contains("5 of 10"), "3 planted +60 on 5 cards: %s" % [h1])
	var hs := hands_scene(B, "thumb_01_r", "twist", 40.0, 2)
	var h2 := HandCheck.check(hs, B)
	ok(h2["joints"] >= 1 and h2["cards_out"] == 2 and h2["worst"]["joint"] == "thumb_01_r", "3 planted twist: joints %s cards %s worst %s" % [h2["joints"], h2["cards_out"], h2["worst"]])
	var bp := ProjectSettings.globalize_path(DIR + "/zz_c08.bvh")
	BvhExport.write(S0, B, bp)
	var bi := AnimImport.import_file(bp, B, "zz_c08_b")
	var bw := false
	for w in bi.get("warnings", []):
		bw = bw or String(w).contains("hands")
	ok(bi["ok"] and not bw, "3 control: Kine .bvh of an in-range scene has no hands warning (%s)" % [bi.get("warnings")])

	print("c08: %d fail" % fails)
	quit(1 if fails > 0 else 0)
