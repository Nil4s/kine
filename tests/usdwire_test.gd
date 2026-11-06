## godot --path . -s tests/usdwire_test.gd     (L19 USD-WIRE: the skinned USD export (PR #232 API) built from the app's real state)
## UsdExport.text_skinned / write_skinned took a hand-made character dictionary. This suite holds the wiring that makes it usable:
## UsdWire.character(S, B, main) builds the dictionary from what the viewport draws (the mannequin's visible skinned pieces and
## skeleton, the imported CharImport character, the face_geo AU shapes), and the app exposes it (command palette = the CLI `run`
## step and the MCP `run` tool, the Export... dialog, tools/export_usd.gd --skinned). Written and committed BEFORE the wiring.
## READER: tools/usdskin_check.py UNCHANGED (pxr UsdSkel classes + headless Blender's own USD importer evaluated through the
## depsgraph). The references are NOT taken from the writer's dictionary: the weights, the deformed vertices and the face shapes
## are read off the APP (the pieces' own arrays, CharImport.skin_points with the pose the app put on its skeleton, FaceGeo's AU
## table and the mask the viewport draws). Vertex order of the file (stated, held by the bars): the visible skinned MeshInstance3D
## under the mannequin root in tree order, surfaces in order; then, with the face geometry on, the mask and the two eyeballs.
## BARS (each with a planted control):
##  A MANNEQUIN   the mannequin exported from main round-trips through Blender: skinned vertices at 3 frames within 1e-3 m of the
##                viewport's skinning; weights by joint name within 1e-5; structure. pxr's ComputeSkinnedPoints agrees too.
##                CONTROL: the same file read at frame +5 is caught.
##  L LONG LEGS   the same with the scene's body at other proportions (thigh and shank x1.25): 3 frames within 1e-3 m.
##  I IMPORTED    a CharImport character (tests/fixtures/skinned_mannequin.fbx) exported: 3 frames within 1e-3 m of the app's
##                skinned imported mesh carried into Kine's frame. CONTROL: frame +5.
##  S IMPORTED + SHAPES  a character with 2 blend shapes: the names, the animation's weights, and the shapes' own displacement
##                in Blender within 1e-3 m of CharImport.skin_points with the shapes added. CONTROL: one shape dropped is caught.
##  F FACE        face_geo on: 6 BlendShapes (the AU table), their weights per frame equal the clip's (Face.at of the scene's face
##                keys + the extra AU), the mask posed by them in Blender within 1e-3 m of the mask the viewport draws.
##                CONTROLS: one shape dropped; frame +5.
##  M MENUS       the command, the Export... dialog's format and the CLI flag exist and each produces a file; the file from the
##                command is the very bytes of write_skinned(character). CONTROL: each lookup on a list with the entry removed
##                (and the CLI without its flag) finds nothing.
extends SceneTree

var fails := 0
const DIR := "user://zz_usdwire"
const CMD := "Export animation (.usda, skinned)"
const BAR := 1e-3
const BAR_W := 1e-5
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func ctl(c: bool, what: String) -> void:   # a planted control: it must be CAUGHT by the same metric
	print(("ok   control: " if c else "FAIL control: ") + what)
	if not c:
		fails += 1


func idle(n: int) -> void:
	for i in n:
		await process_frame


func g(p: String) -> String:
	return ProjectSettings.globalize_path(p)


func put(path: String, txt: String) -> void:
	var fa := FileAccess.open(g(path), FileAccess.WRITE)
	fa.store_string(txt)
	fa.close()


func find_blender() -> String:
	var e := OS.get_environment("KINE_BLENDER")
	if e != "" and FileAccess.file_exists(e):
		return e
	for base in ["C:/Program Files/Blender Foundation", "D:/Program Files/Blender Foundation"]:
		if not DirAccess.dir_exists_absolute(base):
			continue
		for d in DirAccess.get_directories_at(base):
			var p: String = "%s/%s/blender.exe" % [base, d]
			if FileAccess.file_exists(p):
				return p
	return ""


func new_body(S: Scene) -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	if b.body != S.body:
		b.set_proportions(S.body)
	return b


# ------------------------------------------------------------------ the app's own numbers (the reference side)
## the mesh instances the viewport draws for the figure: visible, skinned, in tree order
func drawn(root3: Node) -> Array:
	var out := []
	for mi in root3.find_children("*", "MeshInstance3D", true, false):
		var x := mi as MeshInstance3D
		if x.visible and x.skin != null and x.mesh is ArrayMesh:
			out.append(x)
	return out


## bone index -> Kine joint name by the nearest ancestor that is one (the root and the extra bones follow the pelvis)
func joint_map_names(sk: Skeleton3D) -> Dictionary:
	var of := {}
	for j in Body.ORDER:
		var bi := sk.find_bone("Head" if j == "head" else j)
		if bi >= 0:
			of[bi] = j
	return _climb(sk, of)


func joint_map_pairs(sk: Skeleton3D, mapping: Dictionary) -> Dictionary:
	var of := {}
	for j in mapping["map"]:
		of[int(mapping["map"][j])] = j
	return _climb(sk, of)


func _climb(sk: Skeleton3D, of: Dictionary) -> Dictionary:
	var out := {}
	for b in sk.get_bone_count():
		var c := b
		while c >= 0 and not of.has(c):
			c = sk.get_bone_parent(c)
		out[b] = of[c] if c >= 0 else "pelvis"
	return out


## per vertex {joint: weight} of the meshes the app draws, folded onto Kine's joints
func app_weights(sk: Skeleton3D, meshes: Array, jm: Dictionary) -> Array:
	var out := []
	for mi in meshes:
		for surf in CharImport.weights_of(sk, mi):
			for row in surf:
				var d := {}
				for bn in row:
					var j: String = jm[sk.find_bone(String(bn))]
					d[j] = float(d.get(j, 0.0)) + float(row[bn])
				out.append(d)
	return out


func app_tris(meshes: Array) -> int:
	var n := 0
	for mi in meshes:
		var am := (mi as MeshInstance3D).mesh as ArrayMesh
		for si in am.get_surface_count():
			var arr := am.surface_get_arrays(si)
			n += ((arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() if arr[Mesh.ARRAY_INDEX] != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return n


func flat(pts: Array) -> Array:
	var o := []
	for p in pts:
		o.append(p.x)
		o.append(p.y)
		o.append(p.z)
	return o


## the mannequin pieces as the viewport skins them now, in the world (the figure stands at the origin)
func body_points(sk: Skeleton3D, meshes: Array, extra := {}) -> Array:
	var out := []
	for mi in meshes:
		for pts in CharImport.skin_points(sk, mi, extra.get(mi, {})):
			out.append_array(pts)
	return out


func kine_lbs(Bk: Body, S: Scene, ch: Dictionary, t: float, with_shapes: bool) -> Array:
	S.apply(Bk, t)
	Bk.fk()
	var K: int = ch["k"]
	var sw: Dictionary = (ch["shape_w"] as Callable).call(t) if with_shapes and ch.has("shape_w") else {}
	var verts: PackedVector3Array = ch["verts"]
	var ids: PackedInt32Array = ch["ids"]
	var w: PackedFloat32Array = ch["w"]
	var out := []
	for i in verts.size():
		var v := verts[i]
		for sh in ch.get("shapes", []):
			if sw.has(sh["name"]):
				v += (sh["offsets"] as PackedVector3Array)[i] * float(sw[sh["name"]])
		var p := Vector3.ZERO
		for q in K:
			var wt := w[i * K + q]
			if wt > 0.0:
				var j: String = Body.ORDER[ids[i * K + q]]
				p += (Bk.P[j] + Bk.G[j] * (v - Bk.p0[j])) * wt
		out.append(p)
	return flat(out)


## the reference file for usdskin_check.py: everything from the app's side
func make_ref(S: Scene, weights: Array, ntri: int, nshapes: int, frames: Array, deform: Dictionary, noshape: Dictionary, shapes: Dictionary, shape_w: Dictionary, sparse: Dictionary) -> Dictionary:
	var nv := weights.size()
	var kmax := 1
	for w in weights:
		kmax = maxi(kmax, (w as Dictionary).size())
	var wl := []
	for w in weights:
		wl.append(w)
	var sh := {}
	var offs_len := {}
	for nm in shapes:
		var o := []
		var cnt := 0
		for v in (shapes[nm] as PackedVector3Array):
			o.append([v.x, v.y, v.z])
			if v != Vector3.ZERO:
				cnt += 1
		sh[nm] = {"offsets": o, "sparse": sparse.get(nm, false)}
		offs_len[nm] = cnt if sparse.get(nm, false) else nv
	return {"joints": Array(Body.ORDER), "weights": wl, "shapes": sh, "frames": frames, "deform": deform, "deform_noshape": noshape, "shape_w": shape_w,
		"expect": {"skelroots": 1, "skeletons": 1, "meshes": 1, "blendshape_prims": nshapes, "joints": Body.ORDER.size(), "bind": Body.ORDER.size(),
			"rest": Body.ORDER.size(), "anim_joints": Body.ORDER.size(), "verts": nv, "faces": ntri, "k": kmax, "kw": kmax, "shapes_mesh": nshapes,
			"targets": nshapes, "shapes_anim": nshapes, "weight_len": nshapes, "offs_len": offs_len}}


func frames_of(S: Scene) -> Array:
	var n := int(ceil(S.length() * float(S.fps) - 1e-6)) + 1
	return [0, n / 2, n - 1]


func time_of(S: Scene, f: int) -> float:
	return minf(float(f) / float(maxi(1, S.fps)), S.length())


func show_at(t: float) -> void:
	m.playhead = t
	m._refresh()
	await idle(1)


# ------------------------------------------------------------------ the worst error out of a case's report
func worst_def(rep: Dictionary, key: String, frames: Array) -> float:
	var dd: Dictionary = rep.get(key, {}).get("blender", {}).get("deform", {})
	var w := 0.0
	for f in frames:
		w = maxf(w, float(dd.get(str(f), 9.0)))
	return w if dd.size() == frames.size() else 9.0


func worst_px(rep: Dictionary, key: String, frames: Array) -> float:
	var pxs: Dictionary = rep.get(key, {}).get("pxrskin", {})
	var w := 0.0
	for f in frames:
		w = maxf(w, float(pxs.get(str(f), 9.0)))
	return w if pxs.size() == frames.size() else 9.0


func check_common(rep: Dictionary, key: String, frames: Array, label: String) -> void:
	var c: Dictionary = rep.get(key, {})
	for k in c:
		if String(k).ends_with("_error"):
			print("%s %s: %s" % [key, k, c[k]])
	var st: Dictionary = c.get("struct", {"got": {}, "mismatch": ["no struct"]})
	ok((st["mismatch"] as Array).is_empty(), "%s structure: %s; mismatches %s" % [label, str(st["got"]).left(260), str(st["mismatch"])])
	var wt: Dictionary = c.get("weights", {"max_err": 9.0, "max_sum_err": 9.0})
	ok(float(wt["max_err"]) <= BAR_W and float(wt["max_sum_err"]) <= BAR_W, "%s weights by joint name over %s vertices x %s influences: worst %s, sum worst %s (bar %s)" % [label, str(wt.get("verts")), str(wt.get("k")), wt["max_err"], wt["max_sum_err"], BAR_W])
	var gb: Dictionary = c.get("blender", {})
	ok(float(gb.get("groups_err", 9.0)) <= 1e-4, "%s Blender's vertex groups agree: worst %s" % [label, float(gb.get("groups_err", 9.0))])
	var dw := worst_def(rep, key, frames)
	ok(dw <= BAR, "%s Blender's skinned vertices vs the app at frames %s: worst %s m (bar %s)" % [label, str(frames), dw, BAR])
	var dp := worst_px(rep, key, frames)
	ok(dp <= BAR, "%s pxr ComputeSkinnedPoints at the same frames: worst %s m (bar %s)" % [label, dp, BAR])


func check_wrong_frame(rep: Dictionary, key: String, frames: Array, label: String) -> void:
	var w := worst_def(rep, key, frames)
	var bad: bool = rep.get(key, {}).has("deform_error")
	ctl(w > BAR * 3.0 or bad, "%s the wrong frame (+5) is caught: worst %s m" % [label, w])


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(g(DIR))
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	m._load_scene("res://scenes/combo3.json")
	await idle(3)
	m._commands()
	var S: Scene = m.S
	var fps := float(maxi(1, S.fps))
	var frames := frames_of(S)
	var cases := []
	var ad := g(DIR)

	# ---------------------------------------------------------------- A MANNEQUIN, from main
	var Bk := new_body(S)
	var ch_a: Dictionary = UsdWire.character(S, m.B, m)
	ok(ch_a.has("verts") and (ch_a["verts"] as PackedVector3Array).size() > 5000 and (ch_a["shapes"] as Array).is_empty(), "A UsdWire.character(main) built the mannequin: %d vertices, %d shapes, k %d" % [(ch_a["verts"] as PackedVector3Array).size(), (ch_a["shapes"] as Array).size(), int(ch_a["k"])])
	var meshes_a := drawn(m.man_root)
	var jm_a := joint_map_names(m.skel)
	var w_a := app_weights(m.skel, meshes_a, jm_a)
	var def_a := {}
	for f in frames:
		await show_at(time_of(S, f))
		def_a[str(f)] = flat(body_points(m.skel, meshes_a))
	ok(w_a.size() == (ch_a["verts"] as PackedVector3Array).size(), "A the file's vertex count is the viewport's: %d == %d" % [w_a.size(), (ch_a["verts"] as PackedVector3Array).size()])
	var path_a := DIR + "/mannequin.usda"
	var wa := UsdExport.write_skinned(S, Bk, ch_a, path_a)
	ok(wa[0] == OK, "A the skinned export wrote: %s" % str(wa[1]))
	put(DIR + "/ref_a.json", JSON.stringify(make_ref(S, w_a, app_tris(meshes_a), 0, frames, def_a, def_a, {}, {}, {})))
	cases.append({"name": "m_good", "usda": ad + "/mannequin.usda", "ref": ad + "/ref_a.json", "shift": 0, "metrics": ["struct", "weights", "pxrskin", "deform"]})
	cases.append({"name": "m_frame", "usda": ad + "/mannequin.usda", "ref": ad + "/ref_a.json", "shift": 5, "metrics": ["deform"]})

	# ---------------------------------------------------------------- L LONG LEGS (the scene's body at other proportions)
	m.proportions_set({"stature": 1.0, "scale": {"thigh": 1.25, "shank": 1.25}})
	await idle(3)
	var Sl: Scene = m.S
	var Bl := new_body(Sl)
	ok(not (Sl.body as Dictionary).is_empty(), "L the scene carries other proportions: %s" % str(Sl.body).left(100))
	var ch_l: Dictionary = UsdWire.character(Sl, m.B, m)
	var meshes_l := drawn(m.man_root)
	var w_l := app_weights(m.skel, meshes_l, jm_a)
	var def_l := {}
	for f in frames:
		await show_at(time_of(Sl, f))
		def_l[str(f)] = flat(body_points(m.skel, meshes_l))
	var wl := UsdExport.write_skinned(Sl, Bl, ch_l, DIR + "/long.usda")
	ok(wl[0] == OK and w_l.size() == (ch_l["verts"] as PackedVector3Array).size(), "L the long-legged export wrote %d vertices" % w_l.size())
	put(DIR + "/ref_l.json", JSON.stringify(make_ref(Sl, w_l, app_tris(meshes_l), 0, frames, def_l, def_l, {}, {}, {})))
	cases.append({"name": "l_good", "usda": ad + "/long.usda", "ref": ad + "/ref_l.json", "shift": 0, "metrics": ["struct", "weights", "deform"]})
	m.proportions_set({})
	await idle(3)

	# ---------------------------------------------------------------- I IMPORTED (a real rigged character file)
	var fbx := g("res://tests/fixtures/skinned_mannequin.fbx")
	var ri: Dictionary = CharImportApp.open(m, fbx, {}, false)
	ok(bool(ri["ok"]) and CharImportApp.active(m), "I the rigged character is on the fighter")
	var imp := await imported_case("i", fbx, frames, {})
	cases.append_array(imp["cases"])

	# ---------------------------------------------------------------- S IMPORTED + SHAPES (two blend shapes in a .glb)
	var shp := await shapes_glb(Bk)
	var rs: Dictionary = CharImportApp.open(m, shp, {}, false)
	ok(bool(rs["ok"]) and CharImportApp.active(m), "S the character with two blend shapes is on the fighter")
	var swf := func(t: float) -> Dictionary:
		return {"puff": 0.5 + 0.5 * sin(t * 3.1), "smile": clampf(t / 2.0, 0.0, 1.0)}
	var imps := await imported_case("s", shp, frames, {"shape_w": swf})
	cases.append_array(imps["cases"])
	CharImportApp.clear(m)
	await idle(2)

	# ---------------------------------------------------------------- F FACE (face_geo on)
	m.S.face = {}
	Face.key(m.S.face, 0.0, {"blink": 0.0, "brow_l": 0.0, "brow_r": 0.0, "squint": 0.0, "jaw": 0.0})
	Face.key(m.S.face, 0.9, {"blink": 0.0, "brow_l": 0.0, "brow_r": 0.0, "squint": 0.0})
	Face.key(m.S.face, 1.0, {"blink": 1.0, "squint": 0.5})
	Face.key(m.S.face, 1.2, {"blink": 0.0, "squint": 0.0})
	Face.key(m.S.face, 1.9, {"brow_l": 0.0, "brow_r": 0.0})
	Face.key(m.S.face, 2.0, {"brow_l": 0.8, "brow_r": 0.8})
	Face.key(m.S.face, 2.3, {"brow_l": -0.6, "brow_r": -0.6})
	Face.key(m.S.face, 3.4, {"jaw": 0.0})
	Face.key(m.S.face, 3.8, {"jaw": 1.0})
	Face.key(m.S.face, 4.2, {"jaw": 0.2})
	m.face_geo_au = {"AU12": 0.6}
	m._face_geo_set(true)
	await idle(3)
	ok(m.face_geo_on and not m.face_geo_data.is_empty(), "F the face geometry is on")
	var Sf: Scene = m.S
	var Bf := new_body(Sf)
	var ch_f: Dictionary = UsdWire.character(Sf, m.B, m)
	var fnames := []
	for sh in ch_f["shapes"]:
		fnames.append(sh["name"])
	ok(fnames == FaceGeo.AUS, "F six BlendShapes, the AU table's: %s" % str(fnames))
	var fframes := [0, 30, 60]
	var meshes_f := drawn(m.man_root)
	var nbody := w_a.size()
	var w_f := app_weights(m.skel, meshes_f, jm_a)
	var fd: Dictionary = m.face_geo_data
	var nmask := (fd["verts"] as PackedVector3Array).size()
	var eye_rest := []
	var eye_tris := 0
	for e in fd["eyes"]:
		var ea := FaceGeo.eye_arrays(float(e["r"]))
		eye_rest.append(ea)
		eye_tris += (ea[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	var nv_f := w_f.size() + nmask
	for ea in eye_rest:
		nv_f += (ea[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	for i in nv_f - w_f.size():
		w_f.append({"head": 1.0})
	var ntri_f := app_tris(meshes_f) + (fd["tris"] as PackedInt32Array).size() / 3 + eye_tris
	ok((ch_f["verts"] as PackedVector3Array).size() == nv_f, "F the file holds the body pieces, the mask and the two eyeballs: %d == %d" % [(ch_f["verts"] as PackedVector3Array).size(), nv_f])
	var def_f := {}
	var nos_f := {}
	for f in fframes:
		var t := time_of(Sf, f)
		await show_at(t)
		var pts := body_points(m.skel, meshes_f)
		var rt: Transform3D = (m.face_geo_root as Node3D).transform
		for v in (m.face_geo_mask.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			pts.append(rt * v)
		for ei in 2:
			var et: Transform3D = (m.face_geo_eye_nodes[ei] as Node3D).transform
			for v in (eye_rest[ei][Mesh.ARRAY_VERTEX] as PackedVector3Array):
				pts.append(rt * (et * v))
		def_f[str(f)] = flat(pts)
		nos_f[str(f)] = kine_lbs(Bf, Sf, ch_f, t, false)
	# the shapes the viewport's table holds, spread over the file's vertices; the weights from the clip, every frame
	var sh_ref := {}
	var sp_ref := {}
	for au in FaceGeo.AUS:
		var arr := PackedVector3Array()
		arr.resize(nv_f)
		var tab: PackedVector3Array = fd["au"][au]
		for i in nmask:
			arr[w_a.size() + i] = tab[i]
		sh_ref[au] = arr
		sp_ref[au] = true
	var n_all := int(ceil(Sf.length() * fps - 1e-6)) + 1
	var swref := {}
	var max_au := {}
	for f in n_all:
		var t2 := time_of(Sf, f)
		var P: Dictionary = Face.at(Sf.face, Sf.lip, t2, Sf.expr_at(t2))
		var bv := (float(P["brow_l"]) + float(P["brow_r"])) * 0.5
		var wd := {"AU1": maxf(bv, 0.0), "AU4": maxf(-bv, 0.0), "AU6": float(P["squint"]), "AU12": 0.6, "AU26": float(P["jaw_deg"]) / FaceGeo.JAW_MAX_DEG, "AU45": float(P["blink"])}
		swref[str(f)] = wd
		for k in wd:
			max_au[k] = maxf(float(max_au.get(k, 0.0)), float(wd[k]))
	var all_move := true
	for au in FaceGeo.AUS:
		all_move = all_move and float(max_au[au]) > 0.05
	ok(all_move, "F the clip moves every one of the six weights (instrument can move): peaks %s" % str(max_au))
	var wf := UsdExport.write_skinned(Sf, Bf, ch_f, DIR + "/face.usda")
	ok(wf[0] == OK and int(wf[1]["shapes"]) == 6, "F the face export wrote 6 shapes")
	put(DIR + "/ref_f.json", JSON.stringify(make_ref(Sf, w_f, ntri_f, 6, fframes, def_f, nos_f, sh_ref, swref, sp_ref)))
	cases.append({"name": "f_good", "usda": ad + "/face.usda", "ref": ad + "/ref_f.json", "shift": 0, "metrics": ["struct", "weights", "offsets", "pxrskin", "deform", "effect"]})
	cases.append({"name": "f_frame", "usda": ad + "/face.usda", "ref": ad + "/ref_f.json", "shift": 5, "metrics": ["deform"]})
	var ch_fd: Dictionary = ch_f.duplicate()
	ch_fd["shapes"] = (ch_f["shapes"] as Array).slice(0, 5)
	UsdExport.write_skinned(Sf, Bf, ch_fd, DIR + "/face_drop.usda")
	cases.append({"name": "f_drop", "usda": ad + "/face_drop.usda", "ref": ad + "/ref_f.json", "shift": 0, "metrics": ["struct"]})

	# ---------------------------------------------------------------- the reader
	put(DIR + "/cases.json", JSON.stringify(cases))
	var bl := find_blender()
	ok(bl != "", "an independent reader exists: Blender at '%s' (env KINE_BLENDER overrides)" % bl)
	var rep := {}
	if bl != "":
		var chk := g("res://tools/usdskin_check.py")
		var out := []
		var code := OS.execute(bl, ["-b", "--factory-startup", "--python", chk, "--", ad], out, true)
		var log := "\n".join(PackedStringArray(out))
		var rt2 := FileAccess.get_file_as_string(DIR + "/report.json")
		ok(code == 0 and "USDSKIN_CHECK_DONE" in log and rt2 != "", "headless Blender ran the checker (exit %d)" % code)
		if rt2 != "":
			rep = JSON.parse_string(rt2)
		else:
			print(log.right(3000))
	if not rep.is_empty():
		check_common(rep, "m_good", frames, "A mannequin")
		check_wrong_frame(rep, "m_frame", frames, "A mannequin")
		check_common(rep, "l_good", frames, "L long legs")
		check_common(rep, "i_good", frames, "I imported")
		check_wrong_frame(rep, "i_frame", frames, "I imported")
		check_common(rep, "s_good", frames, "S imported+shapes")
		var so: Dictionary = rep["s_good"].get("offsets", {"names_ok": false, "weights_err": 9.0})
		ok(bool(so["names_ok"]) and float(so["weights_err"]) <= 1e-6, "S shape names %s and animation weights equal the clip's: worst %s (bar 1e-6)" % [str(so.get("names")), so["weights_err"]])
		var se := effect_worst(rep, "s_good", frames)
		ok(se[0] <= BAR and se[1] > 1e-3, "S the shapes' own displacement in Blender vs the app's skin with the shapes: worst %s m (bar %s), expected move up to %s m" % [se[0], BAR, se[1]])
		var sd: Dictionary = rep["s_drop"].get("struct", {"mismatch": []})
		ctl(not (sd["mismatch"] as Array).is_empty() or rep["s_drop"].has("struct_error"), "S one shape dropped is caught: %s" % str(sd["mismatch"]))
		check_common(rep, "f_good", fframes, "F face")
		var fo: Dictionary = rep["f_good"].get("offsets", {"names_ok": false, "weights_err": 9.0, "max_offset_err": 9.0})
		ok(bool(fo["names_ok"]) and float(fo["max_offset_err"]) <= 1e-5 and float(fo["weights_err"]) <= 1e-6, "F 6 shapes %s: offsets = the AU table (worst %s), weights = the clip's at all %d frames (worst %s, bar 1e-6)" % [str(fo.get("names")), fo["max_offset_err"], n_all, fo["weights_err"]])
		var fe := effect_worst(rep, "f_good", fframes)
		ok(fe[0] <= BAR and fe[1] > 1e-3, "F the six shapes' own displacement in Blender: worst %s m (bar %s), expected move up to %s m" % [fe[0], BAR, fe[1]])
		var gbf: Dictionary = rep["f_good"].get("blender", {})
		var svw := 0.0
		for f in fframes:
			svw = maxf(svw, float((gbf.get("shape_value", {}) as Dictionary).get(str(f), 9.0)))
		ok(svw <= 1e-4, "F Blender's shape key values = the clip's weights: worst %s" % svw)
		check_wrong_frame(rep, "f_frame", fframes, "F face")
		var fdr: Dictionary = rep["f_drop"].get("struct", {"mismatch": []})
		ctl(not (fdr["mismatch"] as Array).is_empty() or rep["f_drop"].has("struct_error"), "F one of the six shapes dropped is caught: %s" % str(fdr["mismatch"]))

	# ---------------------------------------------------------------- M MENUS
	m._face_geo_set(false)
	m.face_geo_au = {}
	await idle(2)
	await menus(Bk)
	m.queue_free()
	await idle(2)
	finish()


func effect_worst(rep: Dictionary, key: String, frames: Array) -> Array:
	var ef: Dictionary = rep.get(key, {}).get("blender", {}).get("effect", {})
	var ee := 0.0
	var mv := 0.0
	for f in frames:
		var e: Dictionary = ef.get(str(f), {"err": 9.0, "expected_move": 0.0})
		ee = maxf(ee, float(e["err"]))
		mv = maxf(mv, float(e["expected_move"]))
	return [ee if ef.size() == frames.size() else 9.0, mv]


## a CharImport character on the fighter -> the cases of its round trip. opts: UsdWire.character's options (shape_w).
func imported_case(tag: String, _path: String, frames: Array, opts: Dictionary) -> Dictionary:
	var S: Scene = m.S
	var st := CharImportApp.state(m)
	var chd: Dictionary = st["ch"]
	var sk: Skeleton3D = chd["sk"]
	var mapping: Dictionary = st["mapping"]
	var jm := joint_map_pairs(sk, mapping)
	var meshes: Array = chd["meshes"]
	var weights := app_weights(sk, meshes, jm)
	var Bk := new_body(S)
	var ch: Dictionary = UsdWire.character(S, m.B, m, opts)
	ok((ch["verts"] as PackedVector3Array).size() == weights.size(), "%s the file's vertices are the imported mesh's: %d == %d" % [tag.to_upper(), (ch["verts"] as PackedVector3Array).size(), weights.size()])
	var shw: Callable = opts.get("shape_w", Callable())
	var shapes_in: Dictionary = {}
	for mi in meshes:
		for nm in CharImport.shapes_of(mi):
			shapes_in[nm] = true
	var deform := {}
	var noshape := {}
	var swref := {}
	var C: Quaternion = Quaternion.IDENTITY
	for f in frames:
		var t := time_of(S, f)
		await show_at(t)
		var ft: Dictionary = CharImportApp.state(m)["fit"]
		C = ft["C"]
		var ratio: float = ft["ratio"]
		var base: Transform3D = chd["src"]["base"]
		var sw: Dictionary = shw.call(t) if shw.is_valid() else {}
		var extra := {}
		for mi in meshes:
			var sh: Dictionary = CharImport.shapes_of(mi)
			var per := {}
			for nm in sh:
				for si in (sh[nm] as Array).size():
					var d: PackedVector3Array = (sh[nm] as Array)[si]
					if not per.has(si):
						var z := PackedVector3Array()
						z.resize(d.size())
						per[si] = z
					var acc: PackedVector3Array = per[si]
					for i in d.size():
						acc[i] += d[i] * float(sw.get(nm, 0.0))
					per[si] = acc
			extra[mi] = per
		var withs := []
		var without := []
		for p in body_points(sk, meshes, extra):
			withs.append(ratio * (C * (base * p)))
		for p in body_points(sk, meshes):
			without.append(ratio * (C * (base * p)))
		deform[str(f)] = flat(withs)
		noshape[str(f)] = flat(without)
		swref[str(f)] = sw
	# the shape offsets are the writer's own here (aligned to Kine's rest); their EFFECT is held against the app's skin above
	var sh_ref := {}
	var sp_ref := {}
	for sh in ch["shapes"]:
		sh_ref[sh["name"]] = sh["offsets"]
		sp_ref[sh["name"]] = bool(sh["sparse"])
	var ntri := app_tris(meshes)
	var ref := make_ref(S, weights, ntri, (ch["shapes"] as Array).size(), frames, deform, noshape, sh_ref, swref, sp_ref)
	put(DIR + "/ref_%s.json" % tag, JSON.stringify(ref))
	UsdExport.write_skinned(S, Bk, ch, DIR + "/imp_%s.usda" % tag)
	var ad := g(DIR)
	var metrics := ["struct", "weights", "pxrskin", "deform"]
	if not (ch["shapes"] as Array).is_empty():
		metrics = ["struct", "weights", "offsets", "pxrskin", "deform", "effect"]
	var cases := [{"name": tag + "_good", "usda": ad + "/imp_%s.usda" % tag, "ref": ad + "/ref_%s.json" % tag, "shift": 0, "metrics": metrics}]
	if tag == "i":
		cases.append({"name": "i_frame", "usda": ad + "/imp_i.usda", "ref": ad + "/ref_i.json", "shift": 5, "metrics": ["deform"]})
	else:
		var chd2: Dictionary = ch.duplicate()
		chd2["shapes"] = (ch["shapes"] as Array).slice(0, 1)
		UsdExport.write_skinned(S, Bk, chd2, DIR + "/imp_%s_drop.usda" % tag)
		cases.append({"name": tag + "_drop", "usda": ad + "/imp_%s_drop.usda" % tag, "ref": ad + "/ref_%s.json" % tag, "shift": 0, "metrics": ["struct"]})
	return {"cases": cases}


## a rigged .glb of Kine's own mannequin with two blend shapes (the recipe of tests/charimp_test.gd R4) -> its absolute path
func shapes_glb(Bk: Body) -> String:
	var man := GltfExport.build(m.S, Bk, "shapes", true)
	var mi: MeshInstance3D = null
	for x in man.find_children("*", "MeshInstance3D", true, false):
		if (x as MeshInstance3D).skin != null:
			mi = x
	var om := mi.mesh as ArrayMesh
	var nm := ArrayMesh.new()
	nm.add_blend_shape("puff")
	nm.add_blend_shape("smile")
	nm.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_RELATIVE
	for si in om.get_surface_count():
		var arr := om.surface_get_arrays(si)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var pf := PackedVector3Array()
		var sm := PackedVector3Array()
		for i in vs.size():
			pf.append(ns[i] * 0.03)
			sm.append(Vector3(sin(vs[i].x * 9.0) * 0.004, 0.003 * vs[i].y, cos(vs[i].z * 7.0) * 0.002))
		var bsl := []
		for d in [pf, sm]:
			var ba := []
			ba.resize(Mesh.ARRAY_MAX)
			ba[Mesh.ARRAY_VERTEX] = d
			var zn := PackedVector3Array()
			zn.resize(vs.size())
			ba[Mesh.ARRAY_NORMAL] = zn
			bsl.append(ba)
		nm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, bsl)
		nm.surface_set_material(si, om.surface_get_material(si))
	mi.mesh = nm
	var path := g(DIR + "/shapes.glb")
	GltfExport._write(man, DIR + "/shapes.glb")
	return path


# ------------------------------------------------------------------ M: the menus
func has_cmd(cmds: Array) -> bool:
	for c in cmds:
		if String((c as Dictionary).get("id", "")) == CMD and (c as Dictionary).get("run") is Callable:
			return true
	return false


func has_format(targets: Array) -> Array:
	var hits := []
	for t in targets:
		var fs: Array = (t as Dictionary)["formats"]
		for fi in fs.size():
			if String((fs[fi] as Dictionary)["run"]) == "usda_skinned":
				hits.append([String((t as Dictionary)["id"]), fi])
	return hits


func menus(Bk: Body) -> void:
	var S: Scene = m.S
	var cmds: Array = m._commands()
	ok(has_cmd(cmds), "M the command palette has '%s'" % CMD)
	ctl(not has_cmd(cmds.filter(func(c): return String((c as Dictionary).get("id", "")) != CMD)), "M the lookup on a palette with the entry removed finds nothing")
	# the CLI `run` step and the MCP `run` tool call the same palette command (AgentTools.step)
	var at := AgentTools.new(m)
	var res_path := "res://exports/%s_skinned.usda" % (S.name if S.name != "" else "scene")
	if FileAccess.file_exists(res_path):
		DirAccess.remove_absolute(g(res_path))
	var st: Dictionary = await at.step(CMD)
	ok(bool(st["ok"]) and FileAccess.file_exists(res_path), "M the agent step '%s' (CLI / MCP run) wrote %s: %s" % [CMD, res_path.get_file(), str(st.get("said", "")).left(120)])
	var step_bytes := FileAccess.get_file_as_bytes(res_path)
	if FileAccess.file_exists(res_path):
		DirAccess.remove_absolute(g(res_path))
	# the command's own writer = write_skinned(character): the same bytes
	var out: String = m._export_usd_skinned(DIR)
	ok(out != "" and FileAccess.file_exists(out), "M the command's export wrote %s" % out.get_file())
	var keep: Dictionary = m.B.state()
	var ch: Dictionary = UsdWire.character(S, m.B, m)
	m.B.set_state(keep)
	var ref_path := DIR + "/by_hand.usda"
	UsdExport.write_skinned(S, Bk, ch, ref_path)
	ok(out != "" and FileAccess.get_sha256(out) == FileAccess.get_sha256(ref_path) and step_bytes == FileAccess.get_file_as_bytes(out), "M the menu's file is write_skinned(character) byte for byte (sha256 %s)" % FileAccess.get_sha256(ref_path).left(16))
	var txt := FileAccess.get_file_as_string(out)
	ok(txt.begins_with("#usda 1.0") and "def SkelRoot" in txt and "def Mesh \"Body\"" in txt and "primvars:skel:jointWeights" in txt, "M the file is a skinned USD (SkelRoot, Mesh with joint weights)")
	# the Export... dialog
	m._export_dialog_open()
	var ui: ExportDialog = m.export_ui
	var hits := has_format(ExportDialog.targets())
	ok(hits.size() >= 2, "M the Export... dialog lists 'usda_skinned' under %d targets: %s" % [hits.size(), str(hits)])
	ctl(has_format(ExportDialog.targets().map(func(t): return {"id": t["id"], "formats": (t["formats"] as Array).filter(func(f): return String(f["run"]) != "usda_skinned")})).is_empty(), "M the lookup on dialog targets with the format removed finds nothing")
	for h in hits:
		var d := ui.text_of(String(h[0]), int(h[1]))
		var tagged := not (d["checks"] as Array).is_empty()
		for l in d["checks"]:
			var s := String(l)
			tagged = tagged and (s.begins_with("OK") or s.begins_with("WARN") or s.begins_with("WRONG") or s.begins_with("NOT NOW"))
		ok(String(d["format"]) != "" and String(d["needs"]) != "" and tagged, "M dialog %s [%s]: format, needs and a tagged checklist" % [str(h), d["format"]])
	if not hits.is_empty():
		var dpath: Variant = ui.export_now(String(hits[0][0]), int(hits[0][1]), DIR)
		ok(String(dpath) != "" and FileAccess.file_exists(String(dpath)) and FileAccess.get_sha256(String(dpath)) == FileAccess.get_sha256(ref_path), "M the dialog's export wrote %s with the command's bytes" % String(dpath).get_file())
	# the CLI
	var cli := g(DIR + "/cli.usda")
	var cli_flat := g(DIR + "/cli_flat.usda")
	var exe := OS.get_executable_path()
	var proj := g("res://")
	var o1 := []
	var c1 := OS.execute(exe, ["--headless", "--path", proj, "-s", "res://tools/export_usd.gd", "--", "res://scenes/combo3.json", cli, "--skinned"], o1, true)
	var t1 := FileAccess.get_file_as_string(cli)
	ok(c1 == 0 and t1.begins_with("#usda 1.0") and "def Mesh \"Body\"" in t1 and "primvars:skel:jointWeights" in t1, "M the CLI (tools/export_usd.gd -- scene out --skinned) wrote a skinned file (exit %d, %d bytes)" % [c1, t1.length()])
	var o2 := []
	OS.execute(exe, ["--headless", "--path", proj, "-s", "res://tools/export_usd.gd", "--", "res://scenes/combo3.json", cli_flat], o2, true)
	var t2 := FileAccess.get_file_as_string(cli_flat)
	ctl(t2.begins_with("#usda 1.0") and "def Mesh \"Body\"" not in t2, "M the CLI without its flag finds no skinned mesh (the flat file, %d bytes)" % t2.length())


func finish() -> void:
	if OS.get_environment("USDWIRE_KEEP") != "":
		print("kept ", g(DIR))
	else:
		for f in DirAccess.get_files_at(g(DIR)):
			DirAccess.remove_absolute(g(DIR) + "/" + f)
		DirAccess.remove_absolute(g(DIR))
	print("usdwire: %d fail" % fails)
	quit(fails)
