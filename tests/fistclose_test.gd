## godot --path . -s tests/fistclose_test.gd     (L116: close the mannequin's right fist; measurement = scripts/fist_check.gd from lane w4-fistmat 74718f80, bars of fistmat NOT edited; needs a window)
## BARS WRITTEN AND COMMITTED BEFORE THE FIX. None was changed after a run.
## FINDING (w4-fistmat): fingertip-to-palm gaps index 17.0 / middle 15.1 / ring 15.3 mm vs 15 mm; skin self-intersects 10.6 mm in the fist and in all 25 grip poses.
## DIAGNOSIS NUMBERS (probe runs before the bars, fist = hand_shape "fist"): (1) the thumb is weighted into the palm: 31 vertices whose heaviest bone is the
##  hand carry > 5% thumb weight, so curling the thumb drags the palm the index tip lands on: index gap 16.7 mm with that bleed, 13.6 mm without it (same angles).
##  (2) the fist's tip joint is set to 70 deg, 10 deg under its own limit (80): middle 15.1, ring 15.3 -> 14.9 / 14.6 at 80. (3) the self-intersection is NOT between
##  fingers (middle|ring 53 pairs, index|middle 6 of 1957) but inside each finger (index 313, middle 330, ring 317, pinky 247) and finger-against-palm (115-175
##  per finger); re-weighting the PIP/DIP blend zones to 4/8/12/16 mm changed the count 1957 -> 2780/2618/2245/1890 and the depth not at all (10.9 mm): the
##  crossing is the linear-blend fold of a finger tube bent 90-105 deg, not a weight-width problem. The relaxed hand (30-45 deg) already crosses 8.0 mm deep.
## SOURCES
##  * Hume MC, Gellman H, McKellop H, Brumfield RH. Functional range of motion of the joints of the hand. J Hand Surg Am 1990;15(2):240-3. PMID 2324451,
##    doi 10.1016/0363-5023(90)90102-w (checked on PubMed): daily-living postures average MCP 61 / PIP 60 / DIP 39 deg: FUNCTIONAL means, well below a fist.
##  * Maximum active flexion MCP ~90-100, PIP ~100-110, DIP ~80-90 deg: UNVERIFIED (from memory; the paper that would carry it, Mallon 1991 J Hand Surg
##    16(5):882, was not found on PubMed here). The bar uses MCP 100 / PIP 110 / DIP 90 (top of those ranges: UNVERIFIED) AND the rig's own limits (body_limits.json 90/105/80).
##  * 15 mm (about one finger pad) and 2 mm (a skin crease) are MINE.
## BARS
##  A  fist (hand_shape "fist", sweep frame 4, FistCheck definition): A1 index, middle, ring, pinky tip gap <= 15 mm (thumb printed, not barred)
##  B  self-intersection depth (FistCheck chord): B1 the fist <= 2 mm; B2 every right-hand grip-book pose <= 2 mm (25 poses expected by the finding;
##     the number over the bar and the worst are printed)
##  C  joint angles of the fist: every finger bend inside the rig's limits AND <= MCP 100 / PIP 110 / DIP 90 (UNVERIFIED) AND >= 0
##  D  the open hand is unchanged: D1 posed with every angle 0 equals the rest vertices (each of the hand's vertices within 1e-5 m); D2 the POSITION bytes of the
##     mannequin glb hash to 411cf5eb65ec071bfe586801c7264eed (md5 of both primitives' positions before the fix: the rest hand did not move);
##     D3 every vertex's weights sum to 1 within 1e-4
##  E  cause bar: no vertex whose heaviest bone is the hand has more than 5% weight on a thumb bone (right and left), 31 on the right before the fix
##  F  planted fakes: F1 the index limited to 20 deg: A's check returns FAIL for the index (and only it); F2 two crossing 1 cm bars: B's check returns FAIL;
##     F3 a planted MCP 120 fails C; F4 a planted hand-bone vertex with 30% thumb weight fails E's check (1% passes: control)
##  G  tools/run_all.sh has the fistclose line
extends SceneTree

var fails := 0
const TIP_BAR := 15.0
const DEPTH_BAR := 2.0
const ROM_MAX := [100.0, 110.0, 90.0]   # UNVERIFIED (from memory)


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func add_box(vs: PackedVector3Array, fs: Array, c: Vector3, h: Vector3) -> void:
	var o := vs.size()
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			for sz in [-1, 1]:
				vs.append(c + Vector3(sx * h.x, sy * h.y, sz * h.z))
	for q in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
		fs.append(PackedInt32Array([o + q[0], o + q[1], o + q[2]]))
		fs.append(PackedInt32Array([o + q[0], o + q[2], o + q[3]]))


## the bars as pure checks so the planted fakes run the same code
func tips_fail(tips: Dictionary) -> Array:
	var out := []
	for f in ["index", "middle", "ring", "pinky"]:
		if float(tips.get(f, 999.0)) > TIP_BAR:
			out.append(f)
	return out


func depth_fails(depth_mm: float) -> bool:
	return depth_mm > DEPTH_BAR


func rom_fails(B: Body, side: String) -> Array:
	var bad := []
	for f in ["index", "middle", "ring", "pinky"]:
		for k in 3:
			var j := "%s_0%d_%s" % [f, k + 1, side]
			var a: float = (B.ang[j] as Vector3).x
			var hi: float = 999.0
			if B.lim.has(j):
				hi = float(B.lim[j]["bend"].y)
			if a < -0.0001 or a > ROM_MAX[k] + 0.0001 or a > hi + 0.0001:
				bad.append("%s %.1f" % [j, a])
	return bad


## vertices whose heaviest bone is hand_name and whose thumb weight is > 5%
func thumb_bleed(wl: Array, bname: PackedStringArray, hand_name: String) -> int:
	var n := 0
	for i in wl.size():
		var d: Dictionary = wl[i]
		var bb := -1
		var bw := 0.0
		for b in d:
			if float(d[b]) > bw:
				bw = float(d[b])
				bb = int(b)
		if bb < 0 or bname[bb] != hand_name:
			continue
		var th := 0.0
		for b in d:
			if bname[b].begins_with("thumb"):
				th += float(d[b])
		if th > 0.05:
			n += 1
	return n


func glb_position_md5() -> String:
	var f := FileAccess.open("res://assets/mannequin.glb", FileAccess.READ)
	var bytes := f.get_buffer(f.get_length())
	var jl := bytes.decode_u32(12)
	var j: Dictionary = JSON.parse_string(bytes.slice(20, 20 + jl).get_string_from_utf8())
	var bin0 := 20 + jl + 8
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_MD5)
	for p in j["meshes"][0]["primitives"]:
		var ac: Dictionary = j["accessors"][int(p["attributes"]["POSITION"])]
		var bv: Dictionary = j["bufferViews"][int(ac["bufferView"])]
		var o := bin0 + int(bv.get("byteOffset", 0))
		hc.update(bytes.slice(o, o + int(bv["byteLength"])))
	return hc.finish().hex_encode()


func bind_names(m: Node, ctx: Dictionary) -> PackedStringArray:
	var sk: Skeleton3D = m.skel
	var skin: Skin = ctx["skin"]
	var bn := PackedStringArray()
	for k in skin.get_bind_count():
		bn.append(sk.get_bone_name(SkinPaint.bind_bone(skin, sk, k)))
	return bn


func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	await idle()
	var ctx := FistCheck.make(m, "r")
	ok(not ctx.is_empty() and int(ctx.get("hand_verts", 0)) > 100, "the right hand has a skin: %d vertices" % ctx.get("hand_verts", 0))
	var res := FistCheck.run(ctx, {"poses": "all"})
	var tips: Dictionary = res["fist"]["tips_mm"]
	print("fist tips (mm): ", tips)

	# A
	var bad := tips_fail(tips)
	ok(bad.is_empty() and tips.size() == 5, "A1 fist: index %.1f middle %.1f ring %.1f pinky %.1f mm (bar %.0f); thumb %.1f printed; over the bar: %s" % [tips.get("index", -1), tips.get("middle", -1), tips.get("ring", -1), tips.get("pinky", -1), TIP_BAR, tips.get("thumb", -1), bad])

	# B
	var fi: Dictionary = res["fist"]["inter"]
	ok(not depth_fails(float(fi["depth_mm"])), "B1 fist self-intersection: %d pairs, %d tris, depth %.2f mm (bar %.0f)" % [fi["count"], fi["tris"], fi["depth_mm"], DEPTH_BAR])
	var ngrip := 0
	var over := 0
	var worst := 0.0
	var worst_name := ""
	for p in res["poses"]:
		if String(p["kind"]) != "grip":
			continue
		ngrip += 1
		var dm: float = p["inter"]["depth_mm"]
		if depth_fails(dm):
			over += 1
		if dm > worst:
			worst = dm
			worst_name = String(p["name"])
	ok(ngrip == 25 and over == 0, "B2 grip poses: %d posed (25 expected), %d over %.0f mm, worst %.2f mm (%s)" % [ngrip, over, DEPTH_BAR, worst, worst_name])

	# C
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.set_proportions(m.B.body)
	B.hand_shape("r", "fist")
	var rb := rom_fails(B, "r")
	ok(rb.is_empty(), "C1 fist angles: index %.1f/%.1f/%.1f middle %.1f/%.1f/%.1f ring %.1f/%.1f/%.1f pinky %.1f/%.1f/%.1f; out of range: %s" % [
		B.ang["index_01_r"].x, B.ang["index_02_r"].x, B.ang["index_03_r"].x, B.ang["middle_01_r"].x, B.ang["middle_02_r"].x, B.ang["middle_03_r"].x,
		B.ang["ring_01_r"].x, B.ang["ring_02_r"].x, B.ang["ring_03_r"].x, B.ang["pinky_01_r"].x, B.ang["pinky_02_r"].x, B.ang["pinky_03_r"].x, rb])

	# D
	var G0 := FistCheck._angles(ctx, "sweep", 0.0, {}, {})
	var pv0 := FistCheck._pose_verts(ctx, G0)
	var worst_d := 0.0
	for i in pv0.size():
		worst_d = maxf(worst_d, pv0[i].distance_to((ctx["rest"] as PackedVector3Array)[i]))
	ok(worst_d <= 1e-5, "D1 open hand posed == rest: worst vertex %.8f m over %d vertices" % [worst_d, pv0.size()])
	var md5 := glb_position_md5()
	ok(md5 == "411cf5eb65ec071bfe586801c7264eed", "D2 glb positions md5 %s" % md5)
	var worst_s := 0.0
	for d in ctx["w"]:
		var s := 0.0
		for b in d:
			s += float(d[b])
		worst_s = maxf(worst_s, absf(s - 1.0))
	ok(worst_s <= 1e-4, "D3 weights sum to 1: worst deviation %.6f" % worst_s)

	# E
	var bname := bind_names(m, ctx)
	var bl := thumb_bleed(ctx["w"], bname, "hand_r")
	ok(bl == 0, "E1 right-hand palm vertices with > 5%% thumb weight: %d (31 before the fix)" % bl)
	var ctxl := FistCheck.make(m, "l")
	var bll := -1
	if not ctxl.is_empty():
		bll = thumb_bleed(ctxl["w"], bind_names(m, ctxl), "hand_l")
	ok(bll == 0, "E2 left-hand palm vertices with > 5%% thumb weight: %d" % bll)

	# F planted fakes
	var lim := FistCheck.run(ctx, {"poses": "fist", "limits": {"index": 20.0}})
	var lf := tips_fail(lim["fist"]["tips_mm"])
	ok(lf == ["index"], "F1 planted: index limited to 20 deg fails A's check, only the index: %s (index %.1f mm)" % [lf, lim["fist"]["tips_mm"].get("index", -1)])
	var pv := PackedVector3Array()
	var pf := []
	add_box(pv, pf, Vector3(0, 0, 0), Vector3(0.05, 0.005, 0.005))
	add_box(pv, pf, Vector3(0, 0, 0), Vector3(0.005, 0.004, 0.05))
	var cr := FistCheck.self_intersections(pv, pf)
	ok(depth_fails(float(cr["depth_mm"])), "F2 planted crossing bars: depth %.2f mm fails B's check" % cr["depth_mm"])
	var P := Body.new()
	P.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	P.set_proportions(m.B.body)
	P.hand_shape("r", "fist")
	P.ang["index_01_r"] = Vector3(120, 0, 0)
	ok(not rom_fails(P, "r").is_empty(), "F3 planted MCP 120 deg fails C: %s" % [rom_fails(P, "r")])
	var hb := bname.find("hand_r")
	var tb := bname.find("thumb_01_r")
	ok(thumb_bleed([{hb: 0.7, tb: 0.3}], bname, "hand_r") == 1 and thumb_bleed([{hb: 0.99, tb: 0.01}], bname, "hand_r") == 0, "F4 planted palm vertex 30%% thumb fails E's check, 1%% passes (control)")

	# G
	var ra := FileAccess.get_file_as_string("res://tools/run_all.sh")
	ok(ra.contains("fistclose:"), "G run_all.sh has the fistclose line")

	print("fistclose: %d fail" % fails)
	quit(1 if fails > 0 else 0)
