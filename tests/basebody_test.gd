## godot --path . -s tests/basebody_test.gd     (ROADMAP_400 G01; needs a window)
## The fighter's skin in the model preview, edited, applied back. Bars, stated before the run:
##   - placement: with the body open, the screen box of all its vertices lies inside the free view (between the side
##     panels, under the top bars, above the status line) and is more than 50 % of the free view's height
##   - leaving with Esc and no Apply: every piece's mesh is the same object as before, its arrays bit-for-bit, and every
##     piece is shown again as it was
##   - round trip, no edits: open, Apply, read the fighter again: the same vertices (positions, order) and the same
##     weights per vertex (bone -> weight, exact float equality); the apply is ONE step of main's undo, and Ctrl+Z puts the
##     original meshes back (the same objects)
##   - extrude one triangle in the middle of the right forearm (E, a real key) and Apply: 3 new vertices, each carrying
##     its source's weights; on the fighter every vertex's weights sum to 1 within 1e-5 with at most 4 bones
##   - bend the right elbow 90 deg (the instrument check: the forearm bone turns 90 +- 2 deg and the new vertices move
##     more than 5 cm): every new vertex's distance to the forearm bone stays within 1 mm of its rest distance
## The topology is reported (info lines, no bar): the mannequin is all triangles; how many pair into quads (F06 rule).
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func key(m: Node, k: int, ctrl := false, shift := false) -> void:
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


func cmd(m: Node, name: String) -> void:
	for c in m._commands():
		if c["name"] == name:
			(c["run"] as Callable).call()
			return
	ok(false, "command '%s' is in the registry" % name)


## every piece: its mesh object and every surface's vertex / bone / weight / index arrays
func grab(m: Node) -> Array:
	var out := []
	for j in m.pieces:
		var mi: MeshInstance3D = m.pieces[j]
		var surfs := []
		var am := mi.mesh as ArrayMesh
		for si in am.get_surface_count():
			var a := am.surface_get_arrays(si)
			surfs.append([a[Mesh.ARRAY_VERTEX], a[Mesh.ARRAY_BONES], a[Mesh.ARRAY_WEIGHTS], a[Mesh.ARRAY_INDEX]])
		out.append([mi, mi.mesh, surfs, mi.visible])
	return out


func same_grab(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i][0] != b[i][0] or a[i][1] != b[i][1] or a[i][3] != b[i][3] or a[i][2].size() != b[i][2].size():
			return false
		for s in a[i][2].size():
			for q in 4:
				if a[i][2][s][q] != b[i][2][s][q]:
					return false
	return true


## the free view's rectangle (what the side panels, the top bars and the status line leave)
func free_rect(m: Node) -> Rect2:
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var top := float(m.TOP_H)
	var bottom := vs.y - float(m.bottom_h) - float(m.LINE_H)
	return Rect2(Vector2(m.lw(), top), Vector2(vs.x - m.rw() - m.lw(), bottom - top))


func dist_seg(p: Vector3, a: Vector3, b: Vector3) -> float:
	return p.distance_to(Geometry3D.get_closest_point_to_segment(p, a, b))


func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	var before := grab(m)
	var info := {}
	var k0 := BaseBody.read(m, info)
	var skin := BaseBody.skin_of(m)
	var w0 := BaseBody.weights_of(k0, skin)
	var quads0 := 0
	for f in k0.faces:
		quads0 += 1 if (f as PackedInt32Array).size() == 4 else 0
	print("info: the fighter's skin: %d file verts weld to %d, %d faces (%d quads), %d bones weighted, %d boundary edges, manifold %s" % [info["file_verts"], k0.verts.size(), k0.faces.size(), quads0, info["binds"], k0.boundary_edge_count(), str(k0.is_manifold())])
	var kq := KMesh.new().from_arrays(k0.verts, k0.faces)
	KMeshTopo.quadrangulate(kq)
	var q := 0
	for f in kq.faces:
		q += 1 if (f as PackedInt32Array).size() == 4 else 0
	print("info: tris to quads (F06 rule, not applied) would make %d quads + %d triangles (%.0f %% of the triangles paired)" % [q, kq.faces.size() - q, 200.0 * q / maxf(1.0, k0.faces.size())])
	# what the fighter drew at load vs what the preview carries: weights snapped to whole 16-bit steps that sum to 65535
	var at_of := {}
	for v in k0.verts.size():
		at_of[k0.verts[v]] = v
	var snap := 0.0
	var seen := 0
	for j in m.pieces:
		var am := (m.pieces[j] as MeshInstance3D).mesh as ArrayMesh
		for si in am.get_surface_count():
			var a := am.surface_get_arrays(si)
			var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var bs: PackedInt32Array = a[Mesh.ARRAY_BONES]
			var ws: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
			var per := bs.size() / vs.size()
			for i in vs.size():
				var v: int = at_of.get(vs[i], -1)
				if v < 0:
					continue
				seen += 1
				var d := {}
				for qq in per:
					if ws[i * per + qq] > 0.0:
						d[bs[i * per + qq]] = float(d.get(bs[i * per + qq], 0.0)) + ws[i * per + qq]
				for b in d:
					snap = maxf(snap, absf(float(d[b]) - float(w0[v].get(b, 0.0))))
				for b in w0[v]:
					snap = maxf(snap, absf(float(w0[v][b]) - float(d.get(b, 0.0))))
		break   # one piece holds every vertex
	ok(seen > 0 and snap <= 2.0 / 65535.0, "the carried weights are the drawn ones snapped to 16-bit steps: off by at most %.7f (<= 2 steps of 1/65535)" % snap)
	ok(int(info["conflicts"]) == 0, "welded seam copies agree on their weights (%d disagree)" % info["conflicts"])
	ok(k0.has_attr("skin:lowerarm_r") and k0.has_attr("skin:pelvis"), "weights carried as A09 vertex channels named by UE5 bone (skin:lowerarm_r, skin:pelvis, ...)")

	# ---- open: placement
	cmd(m, "Model: edit the body mesh")
	await process_frame
	ok(m.kmed != null and m.kmed.on and BaseBody.is_open(m), "Model: edit the body mesh opens the model preview")
	ok(m.kmed.mesh.verts == k0.verts and m.kmed.mesh.faces.size() == k0.faces.size(), "the preview holds the fighter's skin (%d verts, %d faces)" % [m.kmed.mesh.verts.size(), m.kmed.mesh.faces.size()])
	var hidden := true
	for j in m.pieces:
		hidden = hidden and not (m.pieces[j] as MeshInstance3D).visible
	ok(hidden, "the fighter's pieces are hidden while its copy is edited")
	var cam: Camera3D = m.cam
	var lo := Vector2(INF, INF)
	var hi := -lo
	var behind := 0
	for p in m.kmed.mesh.verts:
		var w: Vector3 = m.kmed.view.global_transform * p
		if cam.is_position_behind(w):
			behind += 1
		var s := cam.unproject_position(w)
		lo = lo.min(s)
		hi = hi.max(s)
	var fr := free_rect(m)
	var box := Rect2(lo, hi - lo)
	print("info: body on screen %s, free view %s, window %s" % [str(box), str(fr), str(m.get_viewport().get_visible_rect().size)])
	ok(behind == 0 and fr.encloses(box), "PLACEMENT: the body's screen box is inside the free view")
	ok(box.size.y > 0.5 * fr.size.y, "PLACEMENT: the body is %.0f %% of the free view's height (> 50 %%)" % (100.0 * box.size.y / fr.size.y))

	# ---- leave without Apply
	var steps0: int = m.undo.size()
	key(m, KEY_ESCAPE)
	await process_frame
	await process_frame
	ok(not m.kmed.on, "Esc leaves the preview")
	ok(same_grab(before, grab(m)), "leaving without Apply: every piece has the same mesh object, arrays bit-for-bit, and its visibility back")
	ok(m.undo.size() == steps0, "leaving without Apply adds no undo step")

	# ---- round trip, no edits
	cmd(m, "Model: edit the body mesh")
	await process_frame
	# the round trip goes through BaseBody.apply itself: since 0fcd8c7 the Apply COMMAND skips a body with no edit (bodymesh's bar)
	BaseBody.apply(m, m.kmed.mesh)
	await process_frame
	ok(m.undo.size() == steps0 + 1, "Apply is ONE undo step (%d -> %d)" % [steps0, m.undo.size()])
	ok(BaseBody.gen(m) == 1, "the fighter draws the applied generation")
	var k1 := BaseBody.read(m)
	var w1 := BaseBody.weights_of(k1, BaseBody.skin_of(m))
	ok(k1.verts == k0.verts, "ROUND TRIP: the same %d vertices, positions bit-for-bit and in order" % k1.verts.size())
	var wdiff := 0
	for v in mini(w0.size(), w1.size()):
		if w0[v] != w1[v]:
			if wdiff < 4:
				print("info: vertex %d weights %s -> %s" % [v, str(w0[v]), str(w1[v])]); for b in w0[v]: print("   ", b, " ", "%.9f" % w0[v][b], " ", "%.9f" % w1[v].get(b, -1.0))
			wdiff += 1
	ok(w0.size() == w1.size() and wdiff == 0, "ROUND TRIP: every vertex's weights exact (%d differ)" % wdiff)
	ok(k1.faces.size() == k0.faces.size(), "ROUND TRIP: the same %d faces" % k1.faces.size())
	key(m, KEY_ESCAPE)
	await process_frame
	key(m, KEY_Z, true)   # main's undo: the apply goes back
	await process_frame
	await process_frame
	ok(BaseBody.gen(m) == 0, "Ctrl+Z takes the apply back")
	var g0: Dictionary = (m.get_meta(BaseBody.META_GENS) as Array)[0]
	var back := true
	for j in m.pieces:
		back = back and (BaseBody.rest_meshes(m)[m.pieces[j]] == g0["pieces"][m.pieces[j]])
	ok(back and BaseBody.read(m).verts == k0.verts, "after Ctrl+Z every piece draws its original mesh again (the same objects)")

	# ---- extrude a forearm triangle, apply, bend the elbow
	cmd(m, "Model: edit the body mesh")
	await process_frame
	var km: KMesh = m.kmed.mesh
	var la := km.attr_data("skin:lowerarm_r") as PackedFloat32Array
	var b_la := -1
	var b_hand := -1
	for qb in skin.get_bind_count():
		if skin.get_bind_name(qb) == "lowerarm_r":
			b_la = qb
		if skin.get_bind_name(qb) == "hand_r":
			b_hand = qb
	var la_head := skin.get_bind_pose(b_la).affine_inverse().origin
	var hand_head := skin.get_bind_pose(b_hand).affine_inverse().origin
	var mid := (la_head + hand_head) * 0.5
	var best := -1
	var bscore := -INF
	for fi in km.faces.size():
		var f: PackedInt32Array = km.faces[fi]
		var mn := 1.0
		for v in f:
			mn = minf(mn, la[v])
		var sc := mn * 10.0 - km.face_center(fi).distance_to(mid)
		if sc > bscore:
			bscore = sc
			best = fi
	var minw := 1.0
	for v in (km.faces[best] as PackedInt32Array):
		minw = minf(minw, la[v])
	print("info: the forearm face %d, %.1f cm from the forearm's middle, its corners' lowerarm_r weight >= %.4f" % [best, km.face_center(best).distance_to(mid) * 100.0, minw])
	var nv0 := km.verts.size()
	key(m, KEY_3)
	await process_frame
	m.kmed.sel.faces = {best: true}
	key(m, KEY_E)
	await process_frame
	for ch in "0.050":   # E is a live drag since 97f6e52: the amount is typed and Enter confirms
		key(m, KEY_PERIOD if ch == "." else (KEY_0 + int(ch)))
	key(m, KEY_ENTER)
	await process_frame
	km = m.kmed.mesh
	var newv := range(nv0, km.verts.size())
	ok(newv.size() == 3, "E extruded the forearm triangle: %d new verts" % newv.size())
	var wk := BaseBody.weights_of(km, skin)
	var inherit := newv.size() > 0
	for v in newv:
		var src := -1
		for u in (k0.faces[best] as PackedInt32Array):   # its source: the corner it was copied from (same weights)
			if wk[v] == w0[u]:
				src = u
		inherit = inherit and src >= 0
	ok(inherit, "each new vertex carries the weights of the corner it grew from")
	cmd(m, "Model: apply the body mesh to the fighter")
	await process_frame
	ok(m.undo.size() == steps0 + 1, "the second Apply is one more step (the undone one was dropped): %d" % m.undo.size())
	var k2 := BaseBody.read(m)
	var w2 := BaseBody.weights_of(k2, BaseBody.skin_of(m))
	var bad := 0
	var worst := 0.0
	for d in w2:
		var s := 0.0
		for b in d:
			s += float(d[b])
		worst = maxf(worst, absf(s - 1.0))
		if absf(s - 1.0) > 1e-5 or (d as Dictionary).size() > 4 or (d as Dictionary).is_empty():
			bad += 1
	ok(k2.verts.size() == nv0 + 3 and bad == 0, "after the edit, on the fighter: %d verts, every weight sum 1 (worst off by %.7f), at most 4 bones (%d bad)" % [k2.verts.size(), worst, bad])
	# the new vertices on the fighter, found by position in the weight model (the fighter's skin as drawn)
	var newp := []
	for v in newv:
		newp.append(km.verts[v])
	var hits := []   # [surf, index] per new vertex
	for p in newp:
		var h = null
		for si in m.wp["surfs"].size():
			var vs: PackedVector3Array = m.wp["surfs"][si]["verts"]
			var at := vs.find(p)
			if at >= 0:
				h = [si, at]
				break
		hits.append(h)
	ok(not hits.has(null), "the new vertices are in the fighter's skinned mesh")
	var rest_d := []
	for p in newp:
		rest_d.append(dist_seg(p, la_head, hand_head))
	var sk: Skeleton3D = m.skel
	var bi_la := SkinPaint.bind_bone(skin, sk, b_la)
	var bi_hand := SkinPaint.bind_bone(skin, sk, b_hand)
	var posed := []
	var segs := []
	for ang in [0.0, 90.0]:
		m.B.ang["lowerarm_r"] = Vector3(ang, m.B.ang["lowerarm_r"].y, m.B.ang["lowerarm_r"].z)
		m._refresh()
		await process_frame
		SkinPaint.refresh(m.wp)
		var a := sk.global_transform * sk.get_bone_global_pose(bi_la).origin
		var b := sk.global_transform * sk.get_bone_global_pose(bi_hand).origin
		segs.append([a, b])
		var ps := []
		for h in hits:
			ps.append((m.wp["surfs"][h[0]]["pos"] as PackedVector3Array)[h[1]] if h != null else Vector3.ZERO)
		posed.append(ps)
	var turn := rad_to_deg(((segs[0][1] - segs[0][0]) as Vector3).angle_to(segs[1][1] - segs[1][0]))
	var moved := 0.0
	var dev := 0.0
	for i in newp.size():
		moved = maxf(moved, (posed[0][i] as Vector3).distance_to(posed[1][i]))
		for pi in 2:
			dev = maxf(dev, absf(dist_seg(posed[pi][i], segs[pi][0], segs[pi][1]) - float(rest_d[i])))
	ok(absf(turn - 90.0) <= 2.0, "INSTRUMENT: the forearm bone turned %.1f deg between elbow 0 and 90" % turn)
	ok(moved > 0.05, "INSTRUMENT: the new vertices moved %.1f cm with the bend (they are skinned, not left behind)" % (moved * 100.0))
	ok(dev <= 0.001, "the new vertices keep their distance to the forearm bone within 1 mm of rest (worst %.4f mm)" % (dev * 1000.0))
	var skinned := true
	for j in m.pieces:
		var mi: MeshInstance3D = m.pieces[j]
		skinned = skinned and mi.skin != null and ((mi.mesh as ArrayMesh).get_surface_count() == 0 or (mi.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_BONES] != null)
	ok(skinned, "every piece is still a skinned mesh (skin + bone arrays)")
	key(m, KEY_ESCAPE)
	await process_frame
	print("basebody: %d failed" % fails)
	quit(1 if fails > 0 else 0)
