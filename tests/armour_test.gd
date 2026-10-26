## godot --path . -s tests/armour_test.gd     (ROADMAP_400 B23; needs a window)
## Armour from the body: a vambrace over the right forearm's anatomy tags (forearm_extensors_r + forearm_flexors_r), made
## through the op (Search "Model: armour from the body", its panel's Make plate). Bars, stated before the run:
##   - one undo step: Make plate adds ONE step to main's undo; Ctrl+Z takes the part off the fighter (and its preview copy
##     away), Ctrl+Y puts the same part back
##   - closed and manifold: KMeshValidate.report finds nothing (no holes, no non-manifold edge, nothing flipped or inside
##     out), KMesh.is_closed and is_manifold
##   - OUTWARD: the patch's normals were checked against the forearm bone (0 verts left pointing in), and every measured
##     point below lies on the OUTER side of the skin (measured independently here: (vertex - its nearest skin point) .
##     (that skin point - the forearm bone's axis) > 0)
##   - GAP: every vertex of the shell's inside (all its faces inside faces) is 4 mm +- 0.5 mm from the nearest skin
##     triangle (brute force over the body's triangles near the plate, own closest-point code)
##   - THICKNESS: every vertex of the outside (all its faces outside faces) is 3 mm +- 0.2 mm from the nearest triangle
##     of the inside
##   - nothing of the shell (rim and bevel included) is nearer the skin than 3.5 mm or further than 7.5 mm
##   - BEVEL: both border loops bevelled: bevel faces present, the bevel width 1 mm (not clamped below 0.99 mm)
##   - WEIGHTS: every vertex of the part (as the GPU gets it: its ARRAY_BONES / ARRAY_WEIGHTS) sums to 1 within 1e-5 on
##     at most 4 bones, and its weights are exactly those of the nearest body vertex (found again here by brute force)
##   - POSED: with the right elbow bent 90 deg (instrument: the forearm bone turns 90 +- 2 deg, the plate moves > 5 cm),
##     the inside verts of the skinned plate stay 4 +- 1.5 mm from the posed skin over >= 95 % of them
##   - PLACEMENT (on screen, the body preview): the pixels the plate changes (drawn vs hidden) are > 200, their box inside
##     the free view, their centre within 40 px of the right forearm bone as drawn on screen, between its ends
##   - PLACEMENT on the fighter (after Esc): the same, the part drawn vs hidden
##   - a second plate over "deltoid_l pectoral_l" (two tags, one shell) and one over region shin_l are closed and manifold,
##     gapped outward (inside verts 4 +- 0.5 mm, outward)
##   - TIMING: the vambrace builds in < 4 s (info line with the time; flaky under load: re-run alone)
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func key(k: int, ctrl := false, shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	e.ctrl_pressed = ctrl
	e.shift_pressed = shift
	root.push_input(e)
	var u := e.duplicate() as InputEventKey
	u.pressed = false
	root.push_input(u)


## closest point on triangle abc to p (Ericson 5.1.5, written again here: the instrument is not the op's code)
func closest(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var den := 1.0 / (va + vb + vc)
	return a + ab * (vb * den) + ac * (vc * den)


## the triangles (flat index list) of pts within `pad` of the box of `near`
func tris_near(pts: PackedVector3Array, tris: PackedInt32Array, near: PackedVector3Array, pad: float) -> PackedInt32Array:
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for p in near:
		lo = lo.min(p)
		hi = hi.max(p)
	lo -= Vector3.ONE * pad
	hi += Vector3.ONE * pad
	var out := PackedInt32Array()
	for t in range(0, tris.size(), 3):
		var a := pts[tris[t]]
		var b := pts[tris[t + 1]]
		var c := pts[tris[t + 2]]
		var l := a.min(b).min(c)
		var h := a.max(b).max(c)
		if h.x >= lo.x and h.y >= lo.y and h.z >= lo.z and l.x <= hi.x and l.y <= hi.y and l.z <= hi.z:
			out.append_array([tris[t], tris[t + 1], tris[t + 2]])
	return out


## nearest point of the triangles to p -> [distance, point]
func nearest(pts: PackedVector3Array, tris: PackedInt32Array, p: Vector3) -> Array:
	var bd := INF
	var bq := p
	for t in range(0, tris.size(), 3):
		var q := closest(p, pts[tris[t]], pts[tris[t + 1]], pts[tris[t + 2]])
		var d := p.distance_squared_to(q)
		if d < bd:
			bd = d
			bq = q
	return [sqrt(bd), bq]


func tri_list(k: KMesh, only := -1, part := PackedFloat32Array()) -> PackedInt32Array:
	var t := PackedInt32Array()
	for fi in k.faces.size():
		if only >= 0 and int(part[fi]) != only:
			continue
		var f: PackedInt32Array = k.faces[fi]
		for i in range(1, f.size() - 1):
			t.append_array([f[0], f[i], f[i + 1]])
	return t


## the verts all of whose faces are of part p
func verts_of_part(k: KMesh, p: int) -> PackedInt32Array:
	var part: PackedFloat32Array = k.attr_data(ArmourFromBody.CH_PART)
	var out := PackedInt32Array()
	for v in k.verts.size():
		var all := true
		var any := false
		for fi in k.vert_faces(v):
			any = true
			all = all and int(part[fi]) == p
		if any and all:
			out.append(v)
	return out


## the bone segments (bind heads to the first child's head) in mesh space, as skin binds: [[a, b], ...]
func bind_segments(skin: Skin, sk: Skeleton3D) -> Array:
	var out := []
	var head := {}
	for q in skin.get_bind_count():
		head[q] = skin.get_bind_pose(q).affine_inverse().origin
	for q in skin.get_bind_count():
		var bq := SkinPaint.bind_bone(skin, sk, q)
		var tail: Vector3 = head[q]
		for r in skin.get_bind_count():
			if sk.get_bone_parent(SkinPaint.bind_bone(skin, sk, r)) == bq:
				tail = head[r]
				break
		if tail != head[q]:
			out.append([head[q], tail])
	return out


func axis_point(segs: Array, p: Vector3) -> Vector3:
	var bd := INF
	var bq := p
	for s in segs:
		var q := Geometry3D.get_closest_point_to_segment(p, s[0], s[1])
		if p.distance_squared_to(q) < bd:
			bd = p.distance_squared_to(q)
			bq = q
	return bq


## the gap of the given verts: -> {"lo", "hi" (mm), "bad" (outside 4 +- 0.5), "inside" (on the inner side of the skin)}
func gap_of(k: KMesh, ids: PackedInt32Array, body: KMesh, segs: Array, want_lo: float, want_hi: float) -> Dictionary:
	var near := PackedVector3Array()
	for v in ids:
		near.append(k.verts[v])
	var bt := tris_near(body.verts, tri_list(body), near, 0.03)
	var lo := INF
	var hi := 0.0
	var bad := 0
	var inside := 0
	for v in ids:
		var r := nearest(body.verts, bt, k.verts[v])
		var d: float = r[0] * 1000.0
		lo = minf(lo, d)
		hi = maxf(hi, d)
		if d < want_lo or d > want_hi:
			bad += 1
			if bad <= 6 and k.has_attr(ArmourFromBody.CH_PART):
				var pts := []
				for fi in k.vert_faces(v):
					pts.append(int(k.get_attr(ArmourFromBody.CH_PART, fi)))
				print("info:   vert %d at %.2f mm, faces of parts %s, region of the skin vert %s" % [v, d, str(pts), KMeshBody.label(body, int(k.get_attr(ArmourFromBody.CH_SRC, v)))["region"] if k.has_attr(ArmourFromBody.CH_SRC) else "?"])
		var q: Vector3 = r[1]
		if (k.verts[v] - q).dot(q - axis_point(segs, q)) <= 0.0:
			inside += 1
	return {"lo": lo, "hi": hi, "bad": bad, "inside": inside, "n": ids.size()}


func free_rect(m: Node) -> Rect2:
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var top := float(m.TOP_H)
	var bottom := vs.y - float(m.bottom_h) - float(m.LINE_H)
	return Rect2(Vector2(m.lw(), top), Vector2(vs.x - m.rw() - m.lw(), bottom - top))


func grab() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_viewport().get_texture().get_image()


## the pixels that differ between a and b: {"n", "box": Rect2, "centre"}
func diff(a: Image, b: Image) -> Dictionary:
	var n := 0
	var lo := Vector2(INF, INF)
	var hi := -lo
	var s := Vector2.ZERO
	for y in range(0, a.get_height()):
		for x in range(0, a.get_width()):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.06:
				n += 1
				var p := Vector2(x, y)
				lo = lo.min(p)
				hi = hi.max(p)
				s += p
	return {"n": n, "box": Rect2(lo, hi - lo), "centre": s / maxf(n, 1)}


## the placement bar: what `node` draws, against the forearm segment a..b (world) on screen
func placement(m: Node, node: Node3D, a: Vector3, b: Vector3, where: String) -> void:
	node.visible = true
	var on := await grab()
	node.visible = false
	var off := await grab()
	node.visible = true
	var d := diff(on, off)
	var cam: Camera3D = m.cam
	var sa := cam.unproject_position(a)
	var sb := cam.unproject_position(b)
	var c: Vector2 = d["centre"]
	var q := Geometry2D.get_closest_point_to_segment(c, sa, sb)
	var t := (c - sa).dot(sb - sa) / maxf((sb - sa).length_squared(), 1e-6)
	var fr := free_rect(m)
	print("info: %s: %d pixels changed, box %s, centre %s; the forearm on screen %s -> %s; free view %s" % [where, d["n"], str(d["box"]), str(c), str(sa), str(sb), str(fr)])
	ok(int(d["n"]) > 200, "PLACEMENT (%s): the plate draws %d pixels (> 200)" % [where, d["n"]])
	ok(fr.encloses(d["box"]), "PLACEMENT (%s): every pixel it draws is inside the free view" % where)
	ok(c.distance_to(q) <= 40.0 and t >= 0.0 and t <= 1.0, "PLACEMENT (%s): its centre is %.0f px from the right forearm on screen (<= 40), %.0f %% along it (elbow 0, wrist 100)" % [where, c.distance_to(q), t * 100.0])


func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	var skin := BaseBody.skin_of(m)
	var sk: Skeleton3D = m.skel
	var segs := bind_segments(skin, sk)
	var b_la := -1
	var b_hand := -1
	for qb in skin.get_bind_count():
		if skin.get_bind_name(qb) == "lowerarm_r":
			b_la = qb
		if skin.get_bind_name(qb) == "hand_r":
			b_hand = qb
	var la_head := skin.get_bind_pose(b_la).affine_inverse().origin
	var hand_head := skin.get_bind_pose(b_hand).affine_inverse().origin

	# ---- the op opens the body and its panel
	var found := false
	for t in MeshTools.TOOLS:
		found = found or String(t["do"]) == "op:armour"
	ok(found, "the op is a line of MeshTools (Search finds \"Model: armour from the body\")")
	print("info: the op said: ", MeshTools.op("armour", m))
	await process_frame
	var u := ArmourUI.of(m)
	ok(BaseBody.is_open(m) and u.panel != null and u.panel.visible, "the op opens the body in the model preview and the armour panel")
	if u.panel == null:
		TestFiles.cleanup()
		quit(1)
		return
	ok(u.panel.find_child("btn_armour_make", true, false) != null, "the panel has its Make plate button")
	var body: KMesh = m.kmed.mesh
	var steps0: int = m.undo.size()
	u.words.text = "forearm_extensors_r, forearm_flexors_r"
	var r: Dictionary = u.make_plate()
	await process_frame
	ok(r["ok"], "Make plate made the plate (%s)" % String(r.get("said", r.get("error", ""))))
	if not r["ok"]:
		TestFiles.cleanup()
		quit(1)
		return
	var k: KMesh = r["mesh"]
	print("info: %s" % r["said"])
	print("info: %d body faces picked, %d in the cleaned patch (removed: %s; %d cut back to keep clear of other skin), flipped %s, built in %.0f ms" % [r["picked_faces"], r["patch_faces"], str(r["removed"]), r["trimmed"], str(r["flipped"]), r["ms"]])
	var mi: MeshInstance3D = r["part"]
	ok(m.undo.size() == steps0 + 1, "ONE UNDO STEP: Make plate added one step to main's undo (%d -> %d)" % [steps0, m.undo.size()])
	ok(mi != null and mi.is_inside_tree() and mi.get_parent() == (m.pieces.values()[0] as Node).get_parent() and mi.skin == skin, "the plate is a part of the fighter: a skinned mesh beside the body pieces, the body's skin")

	# ---- closed, manifold
	var rep := KMeshValidate.report(k)
	ok(rep["ok"] and k.is_closed() and k.is_manifold(), "CLOSED AND MANIFOLD: KMeshValidate finds nothing (%s), closed %s, manifold %s" % [str(rep["problems"].map(func(p): return p["kind"])), str(k.is_closed()), str(k.is_manifold())])

	# ---- outward, gap, thickness
	print("info: OUTWARD: the patch was %s; %d verts whose normal still pointed into the body were turned out" % ["turned over (its normals pointed in)" if r["flipped"] else "already outward", r["inward"]])
	ok(bool(r["flipped"]), "OUTWARD: the welded body's patch winds inward (A19's note) and was turned over by the check against the bones")
	var inner := verts_of_part(k, 1)
	var outer := verts_of_part(k, 0)
	var g := gap_of(k, inner, body, segs, 3.5, 4.5)
	ok(inner.size() > 20 and int(g["bad"]) == 0, "GAP: all %d inside verts are 4 +- 0.5 mm off the skin (%.2f .. %.2f mm; %d outside the band)" % [g["n"], g["lo"], g["hi"], g["bad"]])
	ok(int(g["inside"]) == 0, "OUTWARD (measured): every inside vert is on the outer side of the skin (%d on the inner side)" % g["inside"])
	var part: PackedFloat32Array = k.attr_data(ArmourFromBody.CH_PART)
	var it := tri_list(k, 1, part)
	var tlo := INF
	var thi := 0.0
	var tbad := 0
	for v in outer:
		var d: float = nearest(k.verts, it, k.verts[v])[0] * 1000.0
		tlo = minf(tlo, d)
		thi = maxf(thi, d)
		if absf(d - 3.0) > 0.2:
			tbad += 1
	ok(outer.size() > 20 and tbad == 0, "THICKNESS: all %d outside verts are 3 +- 0.2 mm from the inside (%.2f .. %.2f mm)" % [outer.size(), tlo, thi])
	var all_ids := PackedInt32Array()
	for v in k.verts.size():
		all_ids.append(v)
	var ga := gap_of(k, all_ids, body, segs, 3.0, 7.5)
	ok(int(ga["bad"]) == 0 and int(ga["inside"]) == 0, "every one of the %d shell verts (rim, bevel too) is 3 .. 7.5 mm out from the skin (%.2f .. %.2f mm), none inside it" % [ga["n"], ga["lo"], ga["hi"]])
	var nbev := 0
	var nrim := 0
	for p in part:
		nbev += 1 if int(p) == 3 else 0
		nrim += 1 if int(p) == 2 else 0
	ok(nbev > 0 and nrim > 0 and String(r["bevel_error"]) == "" and float(r["bevel_width"]) >= 0.00099, "BEVEL: %d bevel faces on the border loops (rim %d faces), %.2f mm wide" % [nbev, nrim, float(r["bevel_width"]) * 1000.0])

	# ---- weights, as the GPU gets them, against the nearest body vertex found again
	var arr := (mi.mesh as ArrayMesh).surface_get_arrays(0)
	var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var wts: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / pos.size()
	var bw := BaseBody.weights_of(body, skin)
	var near_body := PackedInt32Array()
	var wbad := 0
	var srcbad := 0
	var worst := 0.0
	var at := {}
	for v in k.verts.size():
		at[k.verts[v]] = v
	var src: PackedFloat32Array = k.attr_data(ArmourFromBody.CH_SRC)
	var nb := {}
	for v in k.verts.size():
		var bi := -1
		var bd := INF
		for q in body.verts.size():
			var d := k.verts[v].distance_squared_to(body.verts[q])
			if d < bd:
				bd = d
				bi = q
		nb[v] = bi
		if int(src[v]) != bi and body.verts[int(src[v])].distance_squared_to(k.verts[v]) > bd:
			srcbad += 1
	for i in pos.size():
		var d := {}
		var s := 0.0
		for q in per:
			if wts[i * per + q] > 0.0:
				d[bones[i * per + q]] = float(d.get(bones[i * per + q], 0.0)) + wts[i * per + q]
				s += wts[i * per + q]
		worst = maxf(worst, absf(s - 1.0))
		var v: int = at.get(pos[i], -1)
		var want: Dictionary = BaseBody.canon(BaseBody.fit4(bw[nb[v]])) if v >= 0 else {}
		var same := v >= 0 and d.size() == want.size()
		for b in d:   # in the GPU's 16-bit steps (both sides are float32 of whole steps)
			same = same and want.has(b) and roundi(float(d[b]) * 65535.0) == roundi(float(want[b]) * 65535.0)
		if absf(s - 1.0) > 1e-5 or d.size() > 4 or not same:
			if wbad < 3:
				print("info:   drawn vert %d (shell %d): %s, the nearest body vertex's %s" % [i, v, str(d), str(want)])
			wbad += 1
	ok(srcbad == 0, "the weights' source is the nearest body vertex for every shell vertex (%d not)" % srcbad)
	ok(wbad == 0, "WEIGHTS: all %d drawn verts sum to 1 (worst off %.7f), <= 4 bones, exactly the nearest body vertex's (%d differ)" % [pos.size(), worst, wbad])

	# ---- placement in the preview
	var pv: MeshInstance3D = null
	for c in m.kmed.view.get_children():
		if c.has_meta("armour_of") and c.get_meta("armour_of") == mi:
			pv = c
	ok(pv != null, "the plate shows in the body preview (a copy under the preview's view)")
	if pv != null:
		var vx: Transform3D = m.kmed.view.global_transform
		await placement(m, pv, vx * la_head, vx * hand_head, "body preview")

	# ---- leave, undo, redo
	key(KEY_ESCAPE)
	await process_frame
	await process_frame
	ok(not BaseBody.is_open(m) and mi.visible and mi.is_inside_tree(), "after Esc the plate is on the fighter, shown")
	key(KEY_Z, true)
	await process_frame
	await process_frame
	ok(not mi.is_inside_tree() and ArmourFromBody.parts(m).is_empty(), "Ctrl+Z takes the plate off the fighter in one step")
	key(KEY_Y, true)
	await process_frame
	await process_frame
	ok(mi.is_inside_tree() and ArmourFromBody.parts(m) == [mi], "Ctrl+Y puts the same plate back")

	# ---- placement on the fighter
	var gx := (m.pieces.values()[0] as MeshInstance3D).global_transform
	await placement(m, mi, gx * la_head, gx * hand_head, "on the fighter")

	# ---- the elbow bent 90 deg
	var bi_la := SkinPaint.bind_bone(skin, sk, b_la)
	var bi_hand := SkinPaint.bind_bone(skin, sk, b_hand)
	var am := SkinPaint.read([mi], sk)
	var posed := []
	var bsegs := []
	var bodyp := []
	for ang in [0.0, 90.0]:
		m.B.ang["lowerarm_r"] = Vector3(ang, m.B.ang["lowerarm_r"].y, m.B.ang["lowerarm_r"].z)
		m._refresh()
		await process_frame
		SkinPaint.refresh(m.wp)
		SkinPaint.refresh(am)
		bsegs.append([sk.global_transform * sk.get_bone_global_pose(bi_la).origin, sk.global_transform * sk.get_bone_global_pose(bi_hand).origin])
		posed.append((am["surfs"][0]["pos"] as PackedVector3Array).duplicate())
		var bp := PackedVector3Array()
		var bt := PackedInt32Array()
		for s in m.wp["surfs"]:
			var o := bp.size()
			bp.append_array(s["pos"])
			for t in (s["tris"] as PackedInt32Array):
				bt.append(t + o)
		bodyp.append([bp, bt])
	var turn := rad_to_deg(((bsegs[0][1] - bsegs[0][0]) as Vector3).angle_to(bsegs[1][1] - bsegs[1][0]))
	var moved := 0.0
	for i in (posed[0] as PackedVector3Array).size():
		moved = maxf(moved, (posed[0][i] as Vector3).distance_to(posed[1][i]))
	ok(absf(turn - 90.0) <= 2.0, "INSTRUMENT: the forearm bone turned %.1f deg between elbow 0 and 90" % turn)
	ok(moved > 0.05, "INSTRUMENT: the plate moved %.1f cm with the bend (it is skinned, not left behind)" % (moved * 100.0))
	# the drawn verts that are inside verts of the shell
	var inner_set := {}
	for v in inner:
		inner_set[k.verts[v]] = true
	var src_pos: PackedVector3Array = am["surfs"][0]["verts"]
	var ids := []
	for i in src_pos.size():
		if inner_set.has(src_pos[i]):
			ids.append(i)
	var pp: PackedVector3Array = posed[1]
	var near := PackedVector3Array()
	for i in ids:
		near.append(pp[i])
	var bt90 := tris_near(bodyp[1][0], bodyp[1][1], near, 0.03)
	var within := 0
	var plo := INF
	var phi := 0.0
	for i in ids:
		var d: float = nearest(bodyp[1][0], bt90, pp[i])[0] * 1000.0
		plo = minf(plo, d)
		phi = maxf(phi, d)
		if absf(d - 4.0) <= 1.5:
			within += 1
	var frac := float(within) / maxf(ids.size(), 1)
	ok(ids.size() > 50 and frac >= 0.95, "POSED (elbow 90 deg): %.1f %% of the plate's %d inside verts stay 4 +- 1.5 mm off the posed skin (>= 95 %%; %.2f .. %.2f mm)" % [frac * 100.0, ids.size(), plo, phi])
	m.B.ang["lowerarm_r"] = Vector3(0.0, m.B.ang["lowerarm_r"].y, m.B.ang["lowerarm_r"].z)
	m._refresh()

	# ---- two tags in one plate, and a region
	var k0 := BaseBody.read(m)
	var gx0 := (m.pieces.values()[0] as MeshInstance3D).global_transform
	for wd in ["deltoid_l pectoral_l", "shin_l"]:
		var r2 := ArmourFromBody.build(k0, sk, gx0, wd)
		if not r2["ok"]:
			ok(false, "a plate over %s: %s" % [wd, r2["error"]])
			continue
		var k2: KMesh = r2["mesh"]
		var rep2 := KMeshValidate.report(k2)
		var g2 := gap_of(k2, verts_of_part(k2, 1), k0, segs, 3.5, 4.5)
		ok(rep2["ok"] and k2.is_closed() and k2.is_manifold(), "a plate over %s: closed and manifold (%d verts, %d faces; %s)" % [wd, k2.verts.size(), k2.faces.size(), str(rep2["problems"].map(func(p): return p["kind"]))])
		ok(int(g2["bad"]) == 0 and int(g2["inside"]) == 0, "a plate over %s: outward (%d normals turned out), all %d inside verts 4 +- 0.5 mm off the skin (%.2f .. %.2f mm, %d on the inner side)" % [wd, r2["inward"], g2["n"], g2["lo"], g2["hi"], g2["inside"]])

	# the instrument can move: the same vambrace asked for an 8 mm gap and a 5 mm shell measures 8 and 5 here
	var r8 := ArmourFromBody.build(k0, sk, gx0, "forearm_extensors_r forearm_flexors_r", {"gap": 0.008, "thickness": 0.005})
	if r8["ok"]:
		var k8: KMesh = r8["mesh"]
		var g8 := gap_of(k8, verts_of_part(k8, 1), k0, segs, 7.5, 8.5)
		var it8 := tri_list(k8, 1, k8.attr_data(ArmourFromBody.CH_PART))
		var t8 := 0.0
		for v in verts_of_part(k8, 0):
			t8 = maxf(t8, absf(nearest(k8.verts, it8, k8.verts[v])[0] * 1000.0 - 5.0))
		ok(int(g8["bad"]) == 0 and int(g8["n"]) > 0 and t8 <= 0.2, "INSTRUMENT: asked for 8 mm / 5 mm, the bars measure %.2f .. %.2f mm gap, thickness off by <= %.2f mm" % [g8["lo"], g8["hi"], t8])
	else:
		ok(false, "INSTRUMENT: the 8 mm plate: %s" % r8["error"])
	ok(float(r["ms"]) < 4000.0, "TIMING: the vambrace built in %.0f ms (< 4000)" % float(r["ms"]))
	print("armour: %d failed" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
