## godot --headless --path . -s tests/usdskin_test.gd     (L14, GAP_AUDIT_1106 #10: USD export with SKIN and BLENDSHAPES)
## A skinned character (two tubes bound to the right arm and right leg, 4 influences, 2 blend shapes: one dense, one sparse)
## written by UsdExport.text_skinned / write_skinned, then READ BACK by headless Blender (tools/usdskin_check.py: pxr UsdSkel
## schema classes plus Blender's own USD importer evaluated through the depsgraph). Nothing here reads the file with the writer.
## Fixture note: the L9 mannequin-with-2-shapes fixture (tests/charimp_test.gd) is on a local branch only (w4-charimp), not on
## origin, so this suite builds its own character from the Kine body's rest pose.
## BARS (each with a planted control; the controls are the same file damaged by text edits, caught by the same metric):
##  1 STRUCTURE  SkelRoot 1, Skeleton 1, Mesh 1, BlendShape prims = shapes; joints / bind / rest / anim joints = Body.ORDER;
##               vertices, faces, influences (elementSize K, arrays V*K), shapes (mesh list, targets, anim list, weights) match.
##               CONTROL: one joint dropped from the Skeleton joints list is caught.
##  2 WEIGHTS    per vertex, weights BY JOINT NAME equal Kine's within 1e-5, sum to 1 within 1e-5 (pxr; Blender's vertex groups
##               are printed and held to 1e-4). CONTROL: two joints' names swapped is caught.
##  3 DEFORM     Blender imports and poses frame N: the skinned vertices equal Kine's deformed mesh within 1e-3 m (1 mm);
##               pxr's own ComputeSkinnedPoints too. CONTROL: the wrong frame (+5) is caught.
##  4 SHAPES     names and offsets within 1e-5, the animation's blendShapeWeights = Kine's within 1e-6; at frame N the shapes'
##               own displacement in Blender = the expected one within 1e-3. CONTROL: one shape's offsets x1.01 is caught.
##  5 the usd_export and usd_layers suites are untouched (run next to this one).
extends SceneTree

var fails := 0
const DIR := "res://exports/zz_usdskin"
const K := 4
const SIDES := 12
const BAR_W := 1e-5
const BAR_OFF := 1e-5
const BAR_DEF := 1e-3


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _seg_d(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-12), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## one tube along chain's joints (rest pose), appended to the character arrays
func add_tube(B: Body, ch: Dictionary, chain: Array, radial: PackedVector3Array, ring_of: PackedInt32Array, tube_id: int) -> void:
	var knots: Array = []
	for j in chain:
		knots.append(B.p0[j])
	knots.append(B.e0[chain[chain.size() - 1]])
	var pj: String = B.parent[chain[0]]
	var cand: Array = [pj] + chain
	var segs: Array = [[B.p0[pj], B.p0[chain[0]]]]
	for i in chain.size():
		segs.append([knots[i], knots[i + 1]])
	var verts: PackedVector3Array = ch["verts"]
	var ids: PackedInt32Array = ch["ids"]
	var w: PackedFloat32Array = ch["w"]
	var faces: Array = ch["faces"]
	var base := verts.size()
	var rings := 0
	var acc := 0.0
	var centres: Array = []
	var tans: Array = []
	for i in knots.size() - 1:
		var a: Vector3 = knots[i]
		var b: Vector3 = knots[i + 1]
		var len := a.distance_to(b)
		var n := maxi(1, int(round(len / 0.025)))
		for s in n:
			centres.append(a.lerp(b, float(s) / n))
			tans.append((b - a).normalized())
	centres.append(knots[knots.size() - 1])
	tans.append(tans[tans.size() - 1])
	for ri in centres.size():
		var c: Vector3 = centres[ri]
		var tn: Vector3 = tans[ri]
		var ref := Vector3(0, 0, 1) if absf(tn.z) < 0.9 else Vector3(1, 0, 0)
		var u := tn.cross(ref).normalized()
		var v := tn.cross(u).normalized()
		for s in SIDES:
			var th := TAU * s / SIDES
			var dir := u * cos(th) + v * sin(th)
			var p := c + dir * 0.035
			verts.append(p)
			radial.append(dir)
			ring_of.append(ri + tube_id * 1000)
			var raw: Array = []
			for q in cand.size():
				var d := _seg_d(p, segs[q][0], segs[q][1])
				raw.append([exp(-pow(d / 0.05, 2.0)), Body.ORDER.find(cand[q])])
			raw.sort_custom(func(x, y): return x[0] > y[0])
			var kept: Array = []
			var tot := 0.0
			for e in raw:
				if e[0] > 0.01 and kept.size() < K:
					kept.append(e)
					tot += e[0]
			if kept.is_empty():
				kept.append(raw[0])
				tot = raw[0][0]
			for q in K:
				if q < kept.size():
					ids.append(kept[q][1])
					w.append(kept[q][0] / tot)
				else:
					ids.append(-1)
					w.append(0.0)
	for ri in centres.size() - 1:
		for s in SIDES:
			var s2 := (s + 1) % SIDES
			faces.append(PackedInt32Array([base + ri * SIDES + s, base + ri * SIDES + s2, base + (ri + 1) * SIDES + s2, base + (ri + 1) * SIDES + s]))
	ch["verts"] = verts
	ch["ids"] = ids
	ch["w"] = w
	ch["faces"] = faces


func build_character(B: Body) -> Dictionary:
	var ch := {"name": "Tubes", "verts": PackedVector3Array(), "faces": [], "k": K, "ids": PackedInt32Array(), "w": PackedFloat32Array(),
		"bind_xf": Transform3D(Basis(), Vector3(0.05, 0.10, -0.02))}
	var radial := PackedVector3Array()
	var ring_of := PackedInt32Array()
	add_tube(B, ch, ["upperarm_r", "lowerarm_r", "hand_r"], radial, ring_of, 0)
	add_tube(B, ch, ["thigh_r", "calf_r", "foot_r"], radial, ring_of, 1)
	var nv: int = (ch["verts"] as PackedVector3Array).size()
	var bulge := PackedVector3Array()
	var tip := PackedVector3Array()
	var last_arm := 0
	for i in nv:
		if ring_of[i] < 1000:
			last_arm = maxi(last_arm, ring_of[i])
	for i in nv:
		bulge.append(radial[i] * 0.012)
		tip.append(Vector3(0.0, 0.02, 0.01) if (ring_of[i] < 1000 and ring_of[i] >= last_arm - 2) else Vector3.ZERO)
	ch["shapes"] = [{"name": "bulge", "offsets": bulge, "sparse": false}, {"name": "tip", "offsets": tip, "sparse": true}]
	ch["shape_w"] = func(t: float) -> Dictionary:
		return {"bulge": 0.5 + 0.5 * sin(t * 3.1), "tip": clampf(t / 2.0, 0.0, 1.0)}
	return ch


## Kine's own deformed mesh at time t: shapes first, then linear blend skinning with the body's G / P (not USD maths)
func kine_deform(B: Body, S: Scene, ch: Dictionary, t: float, with_shapes: bool) -> PackedFloat64Array:
	S.apply(B, t)
	B.fk()
	var sw: Dictionary = (ch["shape_w"] as Callable).call(t) if with_shapes else {}
	var verts: PackedVector3Array = ch["verts"]
	var ids: PackedInt32Array = ch["ids"]
	var w: PackedFloat32Array = ch["w"]
	var out := PackedFloat64Array()
	for i in verts.size():
		var v := verts[i]
		for sh in ch["shapes"]:
			v += (sh["offsets"] as PackedVector3Array)[i] * float(sw.get(sh["name"], 0.0))
		var p := Vector3.ZERO
		for q in K:
			var wt := w[i * K + q]
			if wt > 0.0:
				var j: String = Body.ORDER[ids[i * K + q]]
				p += (B.P[j] + B.G[j] * (v - B.p0[j])) * wt
		out.append(p.x)
		out.append(p.y)
		out.append(p.z)
	return out


func ref_json(B: Body, S: Scene, ch: Dictionary, frames: Array, fps: float, L: float) -> Dictionary:
	var verts: PackedVector3Array = ch["verts"]
	var ids: PackedInt32Array = ch["ids"]
	var w: PackedFloat32Array = ch["w"]
	var wts := []
	for i in verts.size():
		var d := {}
		for q in K:
			if w[i * K + q] > 0.0:
				var nm: String = Body.ORDER[ids[i * K + q]]
				d[nm] = float(d.get(nm, 0.0)) + w[i * K + q]
		wts.append(d)
	var shapes := {}
	var offs_len := {}
	for sh in ch["shapes"]:
		var o := []
		for v in (sh["offsets"] as PackedVector3Array):
			o.append([v.x, v.y, v.z])
		shapes[sh["name"]] = {"offsets": o, "sparse": sh["sparse"]}
		var cnt := 0
		for v in (sh["offsets"] as PackedVector3Array):
			if v != Vector3.ZERO:
				cnt += 1
		offs_len[sh["name"]] = cnt if sh["sparse"] else verts.size()
	var deform := {}
	var nosh := {}
	var shw := {}
	for f in frames:
		var t := minf(float(f) / fps, L)
		deform[str(f)] = Array(kine_deform(B, S, ch, t, true))
		nosh[str(f)] = Array(kine_deform(B, S, ch, t, false))
		shw[str(f)] = (ch["shape_w"] as Callable).call(t)
	return {"joints": Array(Body.ORDER), "weights": wts, "shapes": shapes, "frames": frames, "deform": deform, "deform_noshape": nosh,
		"shape_w": shw,
		"expect": {"skelroots": 1, "skeletons": 1, "meshes": 1, "blendshape_prims": ch["shapes"].size(), "joints": Body.ORDER.size(),
			"bind": Body.ORDER.size(), "rest": Body.ORDER.size(), "anim_joints": Body.ORDER.size(), "verts": verts.size(),
			"faces": (ch["faces"] as Array).size(), "k": K, "kw": K, "shapes_mesh": ch["shapes"].size(), "targets": ch["shapes"].size(),
			"shapes_anim": ch["shapes"].size(), "weight_len": ch["shapes"].size(), "offs_len": offs_len}}


func put(path: String, txt: String) -> void:
	var fa := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.WRITE)
	fa.store_string(txt)
	fa.close()


## the Skeleton prim's `uniform token[] joints = [...]` line index and tokens
func skel_joint_line(lines: PackedStringArray) -> int:
	var in_skel := false
	for i in lines.size():
		var s := lines[i].strip_edges()
		if s.begins_with("def Skeleton "):
			in_skel = true
		elif s.begins_with("def ") and in_skel:
			return -1
		if in_skel and s.begins_with("uniform token[] joints"):
			return i
	return -1


func damage_joints(txt: String, mode: String) -> String:
	var lines := txt.split("\n")
	var i := skel_joint_line(lines)
	if i < 0:
		return txt
	var ln := lines[i]
	var head := ln.substr(0, ln.find("[") + 1)
	var toks := ln.substr(ln.find("[") + 1, ln.rfind("]") - ln.find("[") - 1).split(", ")
	if mode == "drop":
		toks.remove_at(toks.size() - 1)
	else:
		var a := -1
		var b := -1
		for k in toks.size():
			if toks[k].ends_with("/upperarm_r\"") or toks[k] == "\"pelvis/spine_01/spine_02/spine_03/clavicle_r/upperarm_r\"":
				a = k
			if toks[k].ends_with("/lowerarm_r\""):
				b = k
		if a >= 0 and b >= 0:
			# swap only the LEAF names so both stay valid paths: the weights of upperarm_r and lowerarm_r trade places by name
			var la: String = toks[a].get_slice("/", toks[a].get_slice_count("/") - 1)
			var lb: String = toks[b].get_slice("/", toks[b].get_slice_count("/") - 1)
			toks[a] = toks[a].trim_suffix(la) + lb
			toks[b] = toks[b].trim_suffix(lb) + la
	lines[i] = head + ", ".join(toks) + "]"
	return "\n".join(lines)


func scale_offsets(txt: String, shape: String, f: float) -> String:
	var lines := txt.split("\n")
	var in_shape := false
	for i in lines.size():
		var s := lines[i].strip_edges()
		if s.begins_with("def BlendShape \"%s\"" % shape):
			in_shape = true
		elif in_shape and s.begins_with("uniform vector3f[] offsets") or in_shape and s.begins_with("vector3f[] offsets"):
			var a := lines[i].find("[", lines[i].find("offsets") + 10)
			var body := lines[i].substr(a)
			var rx := RegEx.new()
			rx.compile("-?[0-9.]+(?:e[-+]?[0-9]+)?")
			var out := ""
			var pos := 0
			for m in rx.search_all(body):
				out += body.substr(pos, m.get_start() - pos) + String.num(m.get_string().to_float() * f, 9)
				pos = m.get_end()
			out += body.substr(pos)
			lines[i] = lines[i].substr(0, a) + out
			break
	return "\n".join(lines)


func find_blender() -> String:
	var e := OS.get_environment("KINE_BLENDER")
	if e != "" and FileAccess.file_exists(e):
		return e
	for base in ["C:/Program Files/Blender Foundation", "D:/Program Files/Blender Foundation"]:
		for d in DirAccess.get_directories_at(base):
			var p: String = "%s/%s/blender.exe" % [base, d]
			if FileAccess.file_exists(p):
				return p
	return ""


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json")))
	if B.body != S.body:
		B.set_proportions(S.body)
	var fps := float(maxi(1, S.fps))
	var L := S.length()
	var n := int(ceil(L * fps - 1e-6)) + 1
	var ch := build_character(B)
	var nv: int = (ch["verts"] as PackedVector3Array).size()
	var frames: Array = [0, n / 4, n / 2, (3 * n) / 4, n - 1]
	print("character: %d vertices, %d faces, %d joints in the skeleton, %d frames at %d fps" % [nv, (ch["faces"] as Array).size(), Body.ORDER.size(), n, S.fps])

	var path := DIR + "/char.usda"
	var r := UsdExport.write_skinned(S, B, ch, path)
	ok(r[0] == OK, "the skinned export wrote (%s): %s" % [error_string(r[0]), str(r[1])])
	var txt := FileAccess.get_file_as_string(path)
	ok(txt.begins_with("#usda 1.0") and "UsdSkel" not in txt.substr(0, 0) and "def SkelRoot" in txt and "def BlendShape" in txt, "the file is ASCII .usda with SkelRoot and BlendShape prims")
	var ref := ref_json(B, S, ch, frames, fps, L)
	put(DIR + "/ref.json", JSON.stringify(ref))
	put(DIR + "/c_drop.usda", damage_joints(txt, "drop"))
	put(DIR + "/c_swap.usda", damage_joints(txt, "swap"))
	put(DIR + "/c_scale.usda", scale_offsets(txt, "bulge", 1.01))
	var ad := ProjectSettings.globalize_path(DIR)
	var rj := ad + "/ref.json"
	var cases := [
		{"name": "good", "usda": ad + "/char.usda", "ref": rj, "shift": 0, "metrics": ["struct", "weights", "offsets", "pxrskin", "deform", "effect"]},
		{"name": "drop", "usda": ad + "/c_drop.usda", "ref": rj, "shift": 0, "metrics": ["struct"]},
		{"name": "swap", "usda": ad + "/c_swap.usda", "ref": rj, "shift": 0, "metrics": ["weights"]},
		{"name": "scale", "usda": ad + "/c_scale.usda", "ref": rj, "shift": 0, "metrics": ["offsets"]},
		{"name": "frame", "usda": ad + "/char.usda", "ref": rj, "shift": 5, "metrics": ["deform"]},
	]
	put(DIR + "/cases.json", JSON.stringify(cases))
	var bl := find_blender()
	ok(bl != "", "an independent reader exists: Blender at '%s' (env KINE_BLENDER overrides)" % bl)
	if bl == "":
		finish()
		return
	var chk := ProjectSettings.globalize_path("res://tools/usdskin_check.py")
	var out := []
	var code := OS.execute(bl, ["-b", "--factory-startup", "--python", chk, "--", ad], out, true)
	var log := "\n".join(PackedStringArray(out))
	var rep_txt := FileAccess.get_file_as_string(DIR + "/report.json")
	ok(code == 0 and "USDSKIN_CHECK_DONE" in log and rep_txt != "", "headless Blender ran the checker (exit %d)" % code)
	if rep_txt == "":
		print(log.right(3000))
		finish()
		return
	var rep: Dictionary = JSON.parse_string(rep_txt)
	var g: Dictionary = rep["good"]
	for k in g:
		if k.ends_with("_error"):
			print("good %s: %s" % [k, g[k]])

	# 1 STRUCTURE
	var gs: Dictionary = g.get("struct", {"got": {}, "mismatch": ["no struct"]})
	ok((gs["mismatch"] as Array).is_empty(), "1 structure: %s; mismatches %s" % [str(gs["got"]), str(gs["mismatch"])])
	var ds: Dictionary = rep["drop"].get("struct", {"mismatch": []})
	ok(not (ds["mismatch"] as Array).is_empty() or rep["drop"].has("struct_error"), "1 CONTROL one joint dropped is caught: %s" % str(ds["mismatch"]))
	# 2 WEIGHTS
	var gw: Dictionary = g.get("weights", {"max_err": 9.0, "max_sum_err": 9.0})
	ok(float(gw["max_err"]) <= BAR_W and float(gw["max_sum_err"]) <= BAR_W, "2 weights by joint name over %s vertices x %s influences: worst %.3g, sum worst %.3g (bar %g)" % [str(gw.get("verts")), str(gw.get("k")), gw["max_err"], gw["max_sum_err"], BAR_W])
	var gb: Dictionary = g.get("blender", {})
	ok(float(gb.get("groups_err", 9.0)) <= 1e-4 and float(gb.get("groups_sum_err", 9.0)) <= 1e-4, "2 Blender's vertex groups agree: worst %.3g, sum worst %.3g (bar 1e-4)" % [float(gb.get("groups_err", 9.0)), float(gb.get("groups_sum_err", 9.0))])
	var sw: Dictionary = rep["swap"].get("weights", {"max_err": 0.0})
	ok(float(sw["max_err"]) > 0.1 or rep["swap"].has("weights_error"), "2 CONTROL two joints swapped is caught: worst %.3g" % float(sw["max_err"]))
	# 3 DEFORM
	var dw := 0.0
	var dpx := 0.0
	var dd: Dictionary = gb.get("deform", {})
	var pxs: Dictionary = g.get("pxrskin", {})
	for f in frames:
		dw = maxf(dw, float(dd.get(str(f), 9.0)))
		dpx = maxf(dpx, float(pxs.get(str(f), 9.0)))
	ok(dd.size() == frames.size() and dw <= BAR_DEF, "3 Blender's skinned vertices at frames %s: worst %.3g m (bar %g); objects %s" % [str(frames), dw, BAR_DEF, str(gb.get("info", {}).get("objects"))])
	ok(pxs.size() == frames.size() and dpx <= BAR_DEF, "3 pxr ComputeSkinnedPoints at the same frames: worst %.3g m (bar %g)" % [dpx, BAR_DEF])
	var fw := 0.0
	var fd: Dictionary = rep["frame"].get("blender", {}).get("deform", {})
	for f in frames:
		fw = maxf(fw, float(fd.get(str(f), 0.0)))
	ok(fw > BAR_DEF * 3.0 or rep["frame"].has("deform_error"), "3 CONTROL the wrong frame (+5) is caught: worst %.3g m" % fw)
	# 4 SHAPES
	var go: Dictionary = g.get("offsets", {"max_offset_err": 9.0, "weights_err": 9.0, "names_ok": false})
	ok(bool(go["names_ok"]) and float(go["max_offset_err"]) <= BAR_OFF and float(go["weights_err"]) <= 1e-6, "4 shapes %s: offsets worst %.3g (bar %g), animation weights worst %.3g (bar 1e-6)" % [str(go.get("names")), go["max_offset_err"], BAR_OFF, go["weights_err"]])
	var ef: Dictionary = gb.get("effect", {})
	var ee := 0.0
	var mv := 0.0
	for f in frames:
		var e: Dictionary = ef.get(str(f), {"err": 9.0, "expected_move": 0.0})
		ee = maxf(ee, float(e["err"]))
		mv = maxf(mv, float(e["expected_move"]))
	ok(ef.size() == frames.size() and ee <= BAR_DEF and mv > 0.005, "4 the shapes' own displacement in Blender at frames %s: worst error %.3g m (bar %g), expected move up to %.3g m (instrument can move)" % [str(frames), ee, BAR_DEF, mv])
	var sv := 0.0
	for f in frames:
		sv = maxf(sv, float((gb.get("shape_value", {}) as Dictionary).get(str(f), 9.0)))
	ok(sv <= 1e-4, "4 Blender's shape key values = Kine's weights: worst %.3g (bar 1e-4)" % sv)
	var sc: Dictionary = rep["scale"].get("offsets", {"max_offset_err": 0.0})
	ok(float(sc["max_offset_err"]) > BAR_OFF * 5.0 or rep["scale"].has("offsets_error"), "4 CONTROL an offset scaled 1.01 is caught: worst %.3g (bar %g)" % [float(sc["max_offset_err"]), BAR_OFF])
	finish()


func finish() -> void:
	for f in DirAccess.get_files_at(ProjectSettings.globalize_path(DIR)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR + "/" + f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))
	print("usdskin: %d fail" % fails)
	quit(fails)
