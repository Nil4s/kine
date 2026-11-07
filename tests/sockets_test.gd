extends SceneTree
## godot --headless --path . -s tests/sockets_test.gd     (N089: engine sockets from anatomy; scripts/sockets.gd, scripts/sockets_serve.gd)
## weapon_r, weapon_l, back_sheath, hip_holster_r, head_fx: each a parent bone + a local transform in that bone's REST frame, computed from
## the skeleton and the anatomy tags (KMeshAnatomy) of the proportioned, girth-baked mannequin; written into the engine export (EngineExport)
## as bone-attached nodes "socket_<name>". Bars, written BEFORE the code and never moved after a run (an unfit bar goes in the report as a flag).
## Every reference below is measured from the skeleton or the skin here in the test, never read from Sockets. All positions are in skeleton space (m).
##   1 REGION   on male_50, male_95 and female_5 (the sockets are looked up by name and judged by region_errors):
##       weapon_r     within 25 mm of the right palm grip centre = midpoint of the wrist (hand_r) and the middle knuckle joint (middle_01_r)
##       weapon_l     the same, left hand (mirror)
##       back_sheath  |x| < 5 mm (the middle line); y inside the span of the scapula-tagged skin (both sides); z within [back skin - 60 mm, back skin + 30 mm]
##                    where "back skin" is the rearmost skin vertex within 2 cm of the middle line at that height
##       hip_holster_r y within [hip joint y - 40 mm, hip joint y + 120 mm] (greater trochanter .. iliac crest), x on the right and within
##                    [outermost right skin x at that height - 30 mm, + 20 mm] (on the hip surface, not floating)
##       head_fx      [vertex y + 20 mm, vertex y + 150 mm] above the highest skin vertex, |x - vertex x| < 10 mm, |z - vertex z| < 40 mm
##   2 PROPORTION  female_5 (1.525 m) vs male_95 (1.870 m): for every socket t = (socket - parent bone origin) . segment dir / segment length
##       (segments: hand->middle_01, spine_03->neck_01, pelvis->spine_01, head->highest skin vertex) differs by <= 0.05 (5 % of the segment);
##       the parent segments themselves differ by > 10 % between the two bodies (so the bar can fail); socket height / stature differs by < 5 % (relative)
##   3 WIDTH      male_50 stature at 55 kg vs 130 kg: hip_holster_r moves outward with the skin: |holster dx - skin dx| < 15 mm, skin dx > 15 mm
##   4 EXPORT     EngineExport.export(godot) of a scene on male_95 -> the .glb read back by GLTFDocument holds every socket as a node under a
##       BoneAttachment3D whose bone is the same parent, and the node's local origin is within 1 mm of the computed one
##   5 TOOL       agent tool `sockets` is in AgentTools.MCP_EXTRA, tools/mcp/poser_mcp.py, agent_tools.gd, and SocketsServe returns the five names
##   6 CONTROLS   a planted FIXED-OFFSET set (male_50 world positions reused on male_95) FAILS the region bar on male_95 (head_fx and weapon_r both named);
##       the real male_95 sockets pass the same function; a fixed LOCAL offset (female_5 offsets reused on male_95) fails the proportion bar on >= 1
##       socket; a fixed-x holster fails the width bar
var fails := 0
const SCENE := "walk_bat"
const DIR := "C:/Temp/claude/L85/export"
const NAMES := ["weapon_r", "weapon_l", "back_sheath", "hip_holster_r", "head_fx"]


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func mm(x: float) -> String:
	return "%.1f mm" % (x * 1000.0)


## a proportioned, baked mannequin: {man, sk, B, skin (KMesh in skeleton space, anatomy-seeded), sock}
func build(body: Dictionary) -> Dictionary:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.set_proportions(body)
	var man := GltfExport._mannequin(true)
	var sk: Skeleton3D = man.find_children("*", "Skeleton3D", true, false)[0]
	Proportions.bake_mannequin(man, sk, B)
	var skin := Sockets.skin(man, sk)
	KMeshAnatomy.seed_tags(skin, sk)
	return {"man": man, "sk": sk, "B": B, "skin": skin, "sock": Sockets.compute(man, sk), "stature": float(body.get("stature", 1.75))}


func bpos(sk: Skeleton3D, nm: String) -> Vector3:
	var i := Sockets.bone(sk, nm)
	return sk.get_bone_global_rest(i).origin


func world_set(d: Dictionary) -> Dictionary:
	var out := {}
	for n in NAMES:
		out[n] = Sockets.world(d["sk"], d["sock"][n])
	return out


func top_vert(skin: KMesh) -> Vector3:
	var best := skin.verts[0]
	for p in skin.verts:
		if p.y > best.y:
			best = p
	return best


## the region bar: name -> error text ("" = inside its region). W: name -> position (the sockets to judge)
func region_errors(d: Dictionary, W: Dictionary) -> Dictionary:
	var sk: Skeleton3D = d["sk"]
	var skin: KMesh = d["skin"]
	var err := {}
	var nums := {}
	for side in ["_r", "_l"]:
		var nm := "weapon" + side
		var c := (bpos(sk, "hand" + side) + bpos(sk, "middle_01" + side)) * 0.5
		var e: float = (W[nm] as Vector3).distance_to(c)
		nums[nm] = e
		err[nm] = "" if e < 0.025 else "%s from the palm centre" % mm(e)
	# back_sheath
	var y0 := INF
	var y1 := -INF
	for v in skin.verts.size():
		var t := KMeshAnatomy.tag_of(skin, v)
		if t == "scapula_l" or t == "scapula_r":
			y0 = minf(y0, skin.verts[v].y)
			y1 = maxf(y1, skin.verts[v].y)
	var bs: Vector3 = W["back_sheath"]
	var zb := INF
	for p in skin.verts:
		if absf(p.y - bs.y) < 0.02 and absf(p.x) < 0.02:
			zb = minf(zb, p.z)
	var es := ""
	if absf(bs.x) >= 0.005:
		es += "x %s off the middle line; " % mm(bs.x)
	if bs.y < y0 or bs.y > y1:
		es += "y %.3f outside the scapulae [%.3f, %.3f]; " % [bs.y, y0, y1]
	if bs.z < zb - 0.06 or bs.z > zb + 0.03:
		es += "z %.3f vs back skin %.3f; " % [bs.z, zb]
	err["back_sheath"] = es
	nums["back_sheath"] = [bs.x, bs.y - y0, y1 - bs.y, bs.z - zb]
	# hip_holster_r
	var hj := bpos(sk, "thigh_r")
	var hh: Vector3 = W["hip_holster_r"]
	var xmin := INF
	for p in skin.verts:
		if absf(p.y - hh.y) < 0.02 and p.x < 0.0 and absf(p.z - hj.z) < 0.08:
			xmin = minf(xmin, p.x)
	var eh := ""
	if hh.y < hj.y - 0.04 or hh.y > hj.y + 0.12:
		eh += "y %.3f vs hip joint %.3f; " % [hh.y, hj.y]
	if hh.x >= 0.0 or hh.x < xmin - 0.03 or hh.x > xmin + 0.02:
		eh += "x %.3f vs hip skin %.3f; " % [hh.x, xmin]
	err["hip_holster_r"] = eh
	nums["hip_holster_r"] = [hh.y - hj.y, hh.x - xmin]
	# head_fx
	var tv := top_vert(skin)
	var hf: Vector3 = W["head_fx"]
	var dy := hf.y - tv.y
	var ef := ""
	if dy < 0.02 or dy > 0.15:
		ef += "%s above the vertex; " % mm(dy)
	if absf(hf.x - tv.x) >= 0.01 or absf(hf.z - tv.z) >= 0.04:
		ef += "off the vertex axis dx %s dz %s; " % [mm(hf.x - tv.x), mm(hf.z - tv.z)]
	err["head_fx"] = ef
	nums["head_fx"] = [dy, hf.x - tv.x, hf.z - tv.z]
	return {"err": err, "nums": nums}


## t of every socket along its parent segment, and the segment lengths
func tvals(d: Dictionary) -> Dictionary:
	var sk: Skeleton3D = d["sk"]
	var top := top_vert(d["skin"])
	var seg := {"weapon_r": [bpos(sk, "hand_r"), bpos(sk, "middle_01_r")], "weapon_l": [bpos(sk, "hand_l"), bpos(sk, "middle_01_l")],
		"back_sheath": [bpos(sk, "spine_03"), bpos(sk, "neck_01")], "hip_holster_r": [bpos(sk, "pelvis"), bpos(sk, "spine_01")],
		"head_fx": [bpos(sk, "head"), top]}
	var W := world_set(d)
	var t := {}
	var ln := {}
	for n in NAMES:
		var a: Vector3 = seg[n][0]
		var ab: Vector3 = seg[n][1] - a
		ln[n] = ab.length()
		t[n] = ((W[n] as Vector3) - a).dot(ab) / ab.length_squared()
	return {"t": t, "len": ln, "h": W}


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var bodies := {}
	for p in ["male_50", "male_95", "female_5"]:
		bodies[p] = build(Proportions.preset(p))
	# ---- 1 REGION
	for p in bodies:
		var d: Dictionary = bodies[p]
		var r := region_errors(d, world_set(d))
		for n in NAMES:
			if n == "weapon_l" or n == "weapon_r" or true:
				ok(String(r["err"][n]) == "", "(1) REGION %s %s: %s" % [p, n, str(r["nums"][n]) if r["err"][n] == "" else r["err"][n]])
	# ---- 2 PROPORTION
	var ta := tvals(bodies["female_5"])
	var tb := tvals(bodies["male_95"])
	for n in NAMES:
		var dt: float = absf(float(ta["t"][n]) - float(tb["t"][n]))
		var lr: float = float(tb["len"][n]) / float(ta["len"][n])
		var hr: float = (float(tb["h"][n].y) / float(bodies["male_95"]["stature"])) / (float(ta["h"][n].y) / float(bodies["female_5"]["stature"]))
		ok(dt <= 0.05, "(2) PROPORTION %s: t female_5 %.3f male_95 %.3f, diff %.3f (<= 0.05 of the segment)" % [n, ta["t"][n], tb["t"][n], dt])
		ok(lr > 1.10, "(2) PROPORTION %s: parent segment male_95 / female_5 = %.3f (> 1.10, the bar can fail)" % [n, lr])
		ok(absf(hr - 1.0) < 0.05, "(2) PROPORTION %s: height / stature ratio between the bodies %.3f (within 5 %%)" % [n, hr])
	# ---- 3 WIDTH
	var lt := Proportions.preset("male_50")
	var hv := Proportions.preset("male_50")
	lt["mass"] = 55.0
	hv["mass"] = 130.0
	var dl := build(lt)
	var dh := build(hv)
	var xl := _hip_skin_x(dl)
	var xh := _hip_skin_x(dh)
	var skin_dx: float = xl - xh   # the heavy body's right hip surface is further out (more negative x)
	var hold_dx: float = absf(Sockets.world(dh["sk"], dh["sock"]["hip_holster_r"]).x) - absf(Sockets.world(dl["sk"], dl["sock"]["hip_holster_r"]).x)
	ok(skin_dx > 0.015, "(3) WIDTH skin of the 130 kg body is %s further out at the right hip than the 55 kg one (> 15 mm)" % mm(skin_dx))
	ok(absf(hold_dx - skin_dx) < 0.015, "(3) WIDTH holster moved out %s vs skin %s (diff %s, < 15 mm)" % [mm(hold_dx), mm(skin_dx), mm(absf(hold_dx - skin_dx))])
	# ---- 4 EXPORT
	await _export_bars(bodies["male_95"])
	# ---- 5 TOOL
	var src := FileAccess.get_file_as_string("res://scripts/agent_tools.gd")
	var py := FileAccess.get_file_as_string("res://tools/mcp/poser_mcp.py")
	var in_list: bool = (AgentTools.MCP_EXTRA as Array).has("sockets")
	var sr := SocketsServe.serve(null, {"preset": "male_95"})
	var names := []
	for s in sr.get("result", {}).get("sockets", []):
		names.append(s["name"])
	names.sort()
	var want := NAMES.duplicate()
	want.sort()
	ok(in_list and py.contains("\"sockets\"") and src.contains("\"sockets\":") and bool(sr.get("ok", false)) and names == want,
		"(5) TOOL sockets: in MCP_EXTRA %s, in poser_mcp.py %s, serve names %s" % [in_list, py.contains("\"sockets\""), str(names)])
	# ---- 6 CONTROLS
	var tall: Dictionary = bodies["male_95"]
	var fixed := {}
	var src_d: Dictionary = bodies["male_50"]
	for n in NAMES:
		fixed[n] = Sockets.world(src_d["sk"], src_d["sock"][n])   # one fixed offset set, made on the 1.755 m body
	var cr := region_errors(tall, fixed)
	ok(String(cr["err"]["head_fx"]) != "", "(6) CONTROL fixed-offset head_fx on the tall body FAILS the region bar: %s" % cr["err"]["head_fx"])
	ok(String(cr["err"]["weapon_r"]) != "", "(6) CONTROL fixed-offset weapon_r on the tall body FAILS the region bar: %s" % cr["err"]["weapon_r"])
	var real := region_errors(tall, world_set(tall))
	var nbad := 0
	for n in NAMES:
		nbad += 0 if String(real["err"][n]) == "" else 1
	ok(nbad == 0, "(6) CONTROL the real sockets pass the same function on the tall body (%d bad)" % nbad)
	var fl := bodies["female_5"]
	var bad_t := 0
	for n in NAMES:
		var a: Dictionary = fl["sock"][n]
		var lo: Vector3 = (a["local"] as Transform3D).origin
		var pb: int = Sockets.bone(tall["sk"], String(a["parent"]))
		var W: Vector3 = (tall["sk"] as Skeleton3D).get_bone_global_rest(pb) * lo   # the same LOCAL offset on the tall body
		var segd: Dictionary = tvals(tall)
		var a0: Vector3 = tvals(fl)["h"][n]
		var dtp := absf(float(segd["len"][n]) * 0.0 + _t_of(tall, n, W) - float(ta["t"][n]))
		bad_t += 1 if dtp > 0.05 else 0
	ok(bad_t >= 1, "(6) CONTROL a fixed local offset (female_5 offsets on male_95) FAILS the proportion bar on %d of 5 sockets" % bad_t)
	var fx_dx := 0.0   # a fixed-x holster does not move with the girth
	ok(absf(fx_dx - skin_dx) > 0.015, "(6) CONTROL a fixed-x holster misses the skin by %s (> 15 mm)" % mm(absf(fx_dx - skin_dx)))
	print("sockets: %d fail" % fails)
	quit(1 if fails > 0 else 0)


func _t_of(d: Dictionary, n: String, w: Vector3) -> float:
	var sk: Skeleton3D = d["sk"]
	var top := top_vert(d["skin"])
	var seg := {"weapon_r": [bpos(sk, "hand_r"), bpos(sk, "middle_01_r")], "weapon_l": [bpos(sk, "hand_l"), bpos(sk, "middle_01_l")],
		"back_sheath": [bpos(sk, "spine_03"), bpos(sk, "neck_01")], "hip_holster_r": [bpos(sk, "pelvis"), bpos(sk, "spine_01")],
		"head_fx": [bpos(sk, "head"), top]}
	var a: Vector3 = seg[n][0]
	var ab: Vector3 = seg[n][1] - a
	return (w - a).dot(ab) / ab.length_squared()


## outermost right-hip skin x at the hip joint's height (z near the joint)
func _hip_skin_x(d: Dictionary) -> float:
	var hj := bpos(d["sk"], "thigh_r")
	var xmin := INF
	for p in (d["skin"] as KMesh).verts:
		if absf(p.y - hj.y) < 0.02 and p.x < 0.0 and absf(p.z - hj.z) < 0.08:
			xmin = minf(xmin, p.x)
	return xmin


func _export_bars(d: Dictionary) -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/%s.json" % SCENE)))
	S.body = Proportions.preset("male_95")
	var r: Dictionary = EngineExport.export(S, B, "godot", DIR)
	ok(r["err"] == OK, "(4) EXPORT written to %s (err %d)" % [r["path"], r["err"]])
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	ok(doc.append_from_file(String(r["path"]), st) == OK, "(4) EXPORT read back by GLTFDocument")
	var back: Node3D = doc.generate_scene(st)
	root.add_child(back)
	var sk2: Skeleton3D = back.find_children("*", "Skeleton3D", true, false)[0]
	var worst := 0.0
	var found := 0
	var wrong_parent := 0
	for n in NAMES:
		var node: Node = back.find_child("socket_" + n, true, false)
		if node == null:
			ok(false, "(4) EXPORT socket_%s is in the file" % n)
			continue
		found += 1
		var ba := node.get_parent() as BoneAttachment3D
		var pb := ""
		if ba != null:
			pb = ba.bone_name if ba.bone_name != "" else sk2.get_bone_name(ba.bone_idx)
		var want: Dictionary = d["sock"][n]
		var same: bool = pb != "" and Sockets.bone(sk2, pb) == Sockets.bone(sk2, String(want["parent"]))
		wrong_parent += 0 if same else 1
		var e := ((node as Node3D).transform.origin - (want["local"] as Transform3D).origin).length()
		worst = maxf(worst, e)
		ok(same and e < 0.001, "(4) EXPORT socket_%s: parent %s (want %s), origin error %s (< 1 mm)" % [n, pb, want["parent"], mm(e)])
	ok(found == NAMES.size() and wrong_parent == 0, "(4) EXPORT %d of %d sockets found, %d wrong parents, worst origin error %s" % [found, NAMES.size(), wrong_parent, mm(worst)])
	back.queue_free()
