## godot --path . -s tests/rigretopo_test.gd     (ROADMAP_400 F10 ★; needs a window)
## RIG-AWARE RETOPO of the fighter's skin (scripts/kmesh_rigretopo.gd). Bars, stated before the first run:
##   0 THE INSTRUMENTS CAN MOVE: the loop count (B30's measure, replicated: crossings of mesh edges with 12 half-planes
##     round the joint axis, inside the bend zone, within 10 cm of the axis; loops = the fewest any half-plane sees) reads
##     exactly 4 on a test tube with 4 rings in a +-6 cm zone (its ring gaps 0 % off even); the zone pole / non-quad count
##     reads > 0 on the input skin's elbow zone (triangles are seen); the skin distance reads > 3 mm (the bar of 5) for a
##     vertex moved 5 mm off the skin along its normal. CORRECTED after the first run: this said ">= 4.9 mm"; it read 4.74
##     (the surface curves: a point 5 mm out along one vertex normal is nearer some other triangle), and what the check
##     must show is only that the measure sees a 3 mm miss. The half-planes are turned 3.75 deg off every multiple of 22.5 / 30 deg and
##     an edge lying in a half-plane is not a crossing, a crossing at a vertex counts once (the first runs counted the
##     tube's own lengthwise edges, which lie in, or within a degree of, a half-plane at a sector angle, as
##     crossings: 100 % off even; a 7 deg turn still met the legs' 16 sectors at 247.5 / 337.5 deg: 70-82 % off; at
##     3.75 deg one left-knee half-plane still cut a lengthwise edge whose ends turn ~4 deg round the tilted calf: 51 % off).
##     So only edges ACROSS the limb count (|edge direction . axis| < 0.7): a loop runs round the joint, not along it
##   1 BUILD: all four limbs rebuilt; the build on the 6994-vert skin under 30 s (loaded machine; the time is reported)
##   2 per elbow / knee: loops across >= 3; the ring gaps in the zone within +-20 % of their mean (every half-plane);
##     0 poles (verts with other than 4 edges) and 0 non-quad faces among the zone's verts
##   3 every plane ring is a closed edge loop of the output and its plane (Newell normal) is within 10 deg of
##     perpendicular to its bone (the bone segment its centre is nearest)
##   4 RADIAL: >= 3 radial rings round each shoulder and hip, each a closed edge loop that winds once round the limb axis
##     (|turn| within 1 deg of 360), every vertex at the ring's radius from the joint +-1 mm
##   5 every output vertex within 3 mm of the input skin (nearest point on its triangles)
##   6 the generated faces wind as their neighbours do (no directed edge used twice; ADDED after the first run, where
##     KMesh reported 226 open half-edges while the undirected count said 0); every edge of a generated face (tube quad or
##     junction triangle) has exactly 2 faces; the whole output has no more
##     open-border edges and no more over-shared edges than the input skin had (both counts printed)
##   7 WEIGHTS: every vertex's skin:* weights sum to 1 within 1e-5; every new vertex's weights equal the skin's at its
##     nearest point (barycentric on the nearest triangle, computed here independently) within 3 / 65535 per bone
##   8 FROM THE JOINTS: the same skin rebuilt with the left elbow joint moved 3 cm along the arm: the left elbow's dense
##     run of 5 rings (measured on the mesh, on the half-plane above the arm) moves 3 cm +- 3 mm; the skin is the same
##   9 PREVIEW: "Model: rig-aware retopo" (MeshTools line, op:rigretopo) on the open body: the preview holds and draws the
##     new mesh (its face count; the view rebuilt on it), ONE mesh undo step; Ctrl+Z gives the skin back exactly (verts
##     bit for bit, faces); Ctrl+Y the retopo again. PLACEMENT: the retopo'd body's screen box inside the free view
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func key(k: int, ctrl := false) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	e.ctrl_pressed = ctrl
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


func frame_of(d: Vector3) -> Array:
	var up := Vector3.UP if absf(d.dot(Vector3.UP)) < 0.9 else Vector3.BACK
	var e1 := (up - d * up.dot(d)).normalized()
	return [e1, d.cross(e1)]


## B30's loop count, replicated: per half-plane (12 round the axis d through J), the axial positions of the mesh edges'
## crossings inside the zone, within RADIUS of the axis. -> {"loops" (fewest), "ts": [sorted t per half-plane]}
const RADIUS := 0.10
func loops_across(k: KMesh, J: Vector3, d: Vector3, zone: float) -> Dictionary:
	var fr := frame_of(d)
	var es: Array = k.edges()
	var near := []
	for e in es:
		var p := k.verts[(e as Vector2i).x]
		var q := k.verts[(e as Vector2i).y]
		if absf((q - p).normalized().dot(d)) >= 0.7:
			continue   # a lengthwise edge (runs along the limb): it is not part of a loop round it
		if p.distance_to(J) < zone + RADIUS + 0.05 or q.distance_to(J) < zone + RADIUS + 0.05:
			near.append([p, q])
	var ts := []
	var fewest := 1 << 30
	for h in 12:
		var a := TAU * h / 12.0 + deg_to_rad(3.75)   # >= 3.75 deg off every 12- and 16-sector angle
		var u: Vector3 = fr[0] * cos(a) + fr[1] * sin(a)
		var n := d.cross(u)
		var row := []
		for pq in near:
			var sp: float = ((pq[0] as Vector3) - J).dot(n)
			var sq: float = ((pq[1] as Vector3) - J).dot(n)
			if (sp > 0.0) == (sq > 0.0) or sp == sq or (absf(sp) < 1e-7 and absf(sq) < 1e-7):
				continue
			var x: Vector3 = pq[0] + (pq[1] - pq[0]) * (sp / (sp - sq))
			var rad := (x - J).dot(u)
			var t := (x - J).dot(d)
			if rad > 0.0 and rad <= RADIUS and absf(t) <= zone:
				row.append(t)
		row.sort()
		var dd := []   # a half-plane through a vertex meets each of its edges there: one crossing
		for t in row:
			if dd.is_empty() or t - dd[dd.size() - 1] > 1e-6:
				dd.append(t)
		row = dd
		ts.append(row)
		fewest = mini(fewest, row.size())
	return {"loops": fewest, "ts": ts}


## worst gap off the mean, as a fraction, over every half-plane
func gap_off(ts: Array) -> float:
	var worst := 0.0
	for row in ts:
		if row.size() < 3:
			worst = maxf(worst, 1.0)
			continue
		var gs := []
		for i in range(1, row.size()):
			gs.append(row[i] - row[i - 1])
		var mean := 0.0
		for g in gs:
			mean += g
		mean /= gs.size()
		for g in gs:
			worst = maxf(worst, absf(g - mean) / maxf(mean, 1e-9))
	return worst


## the zone's verts (|t| <= zone, within RADIUS of the axis): [poles, non-quad faces touching them, verts]
func zone_topo(k: KMesh, J: Vector3, d: Vector3, zone: float) -> Array:
	var poles := 0
	var bad := {}
	var nv := 0
	for v in k.verts.size():
		var r := k.verts[v] - J
		var t := r.dot(d)
		if absf(t) > zone or (r - d * t).length() > RADIUS:
			continue
		nv += 1
		if k.vert_neighbors(v).size() != 4:
			poles += 1
		for f in k.vert_faces(v):
			if (k.faces[f] as PackedInt32Array).size() != 4:
				bad[f] = true
	return [poles, bad.size(), nv]


func is_loop(k: KMesh, ids: PackedInt32Array) -> bool:
	for i in ids.size():
		if k.find_half_edge(ids[i], ids[(i + 1) % ids.size()]) < 0 and k.find_half_edge(ids[(i + 1) % ids.size()], ids[i]) < 0:
			return false
	return true


func newell(k: KMesh, ids: PackedInt32Array) -> Vector3:
	var n := Vector3.ZERO
	for i in ids.size():
		var a := k.verts[ids[i]]
		var b := k.verts[ids[(i + 1) % ids.size()]]
		n += Vector3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
	return n.normalized()


func seg_d(p: Vector3, a: Vector3, b: Vector3) -> float:
	return p.distance_to(Geometry3D.get_closest_point_to_segment(p, a, b))


## a test tube along x: 12 sectors, radius 5 cm, rings at the given x
func tube(xs: Array) -> KMesh:
	var pos := PackedVector3Array()
	var fs := []
	for x in xs:
		for j in 12:
			var a := TAU * j / 12.0
			pos.append(Vector3(x, 0.05 * cos(a), 0.05 * sin(a)))
	for i in xs.size() - 1:
		for j in 12:
			var jn := (j + 1) % 12
			fs.append(PackedInt32Array([i * 12 + j, i * 12 + jn, (i + 1) * 12 + jn, (i + 1) * 12 + j]))
	return KMesh.new().from_arrays(pos, fs)


## the dense run of 5 consecutive crossings (smallest span) on the half-plane above the arm, within 15 cm of J: its mean t
func dense_run(k: KMesh, J: Vector3, d: Vector3) -> float:
	var r := loops_across(k, J, d, 0.15)
	var row: Array = r["ts"][0]
	var best := INF
	var at := 0.0
	for i in range(0, row.size() - 4):
		var span: float = row[i + 4] - row[i]
		if span < best:
			best = span
			at = (row[i] + row[i + 1] + row[i + 2] + row[i + 3] + row[i + 4]) / 5.0
	return at


func free_rect(m: Node) -> Rect2:
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var top := float(m.TOP_H)
	var bottom := vs.y - float(m.bottom_h) - float(m.LINE_H)
	return Rect2(Vector2(m.lw(), top), Vector2(vs.x - m.rw() - m.lw(), bottom - top))


func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	var skin := BaseBody.read(m)
	var J := KMeshRigRetopo.joints_of(m)

	# ---- 0 the instruments
	var tb := tube([-0.12, -0.09, -0.045, -0.015, 0.015, 0.045, 0.09, 0.12])
	var tl := loops_across(tb, Vector3.ZERO, Vector3.RIGHT, 0.06)
	ok(int(tl["loops"]) == 4 and gap_off(tl["ts"]) < 1e-4, "INSTRUMENT: the loop count reads %d on a tube with 4 rings in the zone (gaps %.1f %% off even)" % [tl["loops"], gap_off(tl["ts"]) * 100.0])
	var el_d: Vector3 = ((J["hand_l"] - J["lowerarm_l"]) as Vector3).normalized()
	var zs := zone_topo(skin, J["lowerarm_l"], el_d, 0.06)
	ok(int(zs[1]) > 0, "INSTRUMENT: on the input skin the elbow zone has %d verts, %d poles, %d non-quad faces (the count sees triangles)" % [zs[2], zs[0], zs[1]])
	var grid := KMeshDecimate._Grid.new(skin)
	var v0 := skin.verts[100] + skin.vert_normals[100] * 0.005
	var gd: float = grid.closest(v0)[0]
	ok(gd > 0.003, "INSTRUMENT: a vertex moved 5 mm off the skin along its normal reads %.2f mm from it (> the 3 mm bar)" % (gd * 1000.0))

	# ---- 1 build
	var r := KMeshRigRetopo.build(skin, J)
	var out: KMesh = r["mesh"]
	var all_ok := true
	for L in r["limbs"]:
		all_ok = all_ok and L["ok"]
		print("info: %s %s r0 %.0f cm, %d rings %s" % [L["name"], "rebuilt" if L["ok"] else "NOT rebuilt (" + String(L["why"]) + ")", float(L.get("r0", 0.0)) * 100.0, (L.get("rings", []) as Array).size(), str((L.get("rings", []) as Array).map(func(g): return ("r%.1f" % (g["r"] * 100.0)) if g["kind"] == "radial" else ("s%.1f" % (g["s"] * 100.0))))])
	var q := 0
	var tri := 0
	for f in out.faces:
		q += 1 if (f as PackedInt32Array).size() == 4 else 0
		tri += 1 if (f as PackedInt32Array).size() == 3 else 0
	var pd: PackedFloat32Array = out.attr_data(KMeshRigRetopo.PART)
	var np := [0, 0, 0]
	for x in pd:
		np[int(x)] += 1
	print("info: in %d verts, %d faces (all triangles) -> out %d verts, %d faces: %d quads, %d triangles, %d other; tube quads %d, junction triangles %d, kept skin faces %d (%d triangle pairs joined)" % [skin.verts.size(), skin.faces.size(), out.verts.size(), out.faces.size(), q, tri, out.faces.size() - q - tri, np[1], np[2], np[0], r["paired"]])
	print("info: build time %.0f ms" % r["ms"])
	ok(all_ok, "all four limbs rebuilt as quad tubes")
	ok(float(r["ms"]) < 30000.0, "the build took %.1f s (< 30 s)" % (float(r["ms"]) / 1000.0))

	# ---- 2 the bend zones
	for L in r["limbs"]:
		if not L["ok"]:
			continue
		var la := loops_across(out, L["joint"], L["axis"], L["zone"])
		var zt := zone_topo(out, L["joint"], L["axis"], L["zone"])
		var jn := "elbow" if String(L["name"]).begins_with("arm") else "knee"
		ok(int(la["loops"]) >= 3, "%s %s: %d loops across the +-%.0f cm zone (>= 3)" % [L["name"], jn, la["loops"], L["zone"] * 100.0])
		ok(gap_off(la["ts"]) <= 0.2, "%s %s: ring gaps in the zone within %.1f %% of even (<= 20 %%)" % [L["name"], jn, gap_off(la["ts"]) * 100.0])
		ok(int(zt[0]) == 0 and int(zt[1]) == 0 and int(zt[2]) > 0, "%s %s: %d zone verts, %d poles, %d non-quad faces (0, 0)" % [L["name"], jn, zt[2], zt[0], zt[1]])

	# ---- 3 plane rings perpendicular to their bone; 4 radial rings
	var worst := 0.0
	var not_loop := 0
	var nplane := 0
	for L in r["limbs"]:
		if not L["ok"]:
			continue
		var j0: Vector3 = L["j0"]
		var j1: Vector3 = L["joint"]
		var j2: Vector3 = L["j2"]
		var nrad := 0
		var rad_off := 0.0
		var turn_off := 0.0
		var rad_loops := true
		for g in L["rings"]:
			var ids: PackedInt32Array = g["verts"]
			var c := Vector3.ZERO
			for v in ids:
				c += out.verts[v]
			c /= ids.size()
			if g["kind"] == "plane":
				nplane += 1
				if not is_loop(out, ids):
					not_loop += 1
				var bd := (j1 - j0).normalized() if seg_d(c, j0, j1) <= seg_d(c, j1, j2) else (j2 - j1).normalized()
				worst = maxf(worst, rad_to_deg(acos(clampf(absf(newell(out, ids).dot(bd)), 0.0, 1.0))))
			else:
				nrad += 1
				rad_loops = rad_loops and is_loop(out, ids)
				for v in ids:
					rad_off = maxf(rad_off, absf(out.verts[v].distance_to(j0) - float(g["r"])))
				var a := (j1 - j0).normalized()
				var fr := frame_of(a)
				var tot := 0.0
				for i in ids.size():
					var p := out.verts[ids[i]] - j0
					var p2 := out.verts[ids[(i + 1) % ids.size()]] - j0
					tot += wrapf(atan2(p2.dot(fr[1]), p2.dot(fr[0])) - atan2(p.dot(fr[1]), p.dot(fr[0])), -PI, PI)
				turn_off = maxf(turn_off, absf(absf(rad_to_deg(tot)) - 360.0))
		var where := "shoulder" if String(L["name"]).begins_with("arm") else "hip"
		ok(nrad >= 3 and rad_loops and turn_off <= 1.0 and rad_off <= 0.001, "%s %s: %d radial rings, closed loops, each winds once round the limb (off by %.2f deg), verts at their radius from the joint +-%.3f mm" % [L["name"], where, nrad, turn_off, rad_off * 1000.0])
	ok(nplane > 0 and not_loop == 0, "%d plane rings, every one a closed edge loop of the output (%d not)" % [nplane, not_loop])
	ok(worst <= 10.0, "every plane ring is within %.2f deg of perpendicular to its bone (<= 10)" % worst)

	# ---- 5 on the skin
	var far := 0.0
	for p in out.verts:
		far = maxf(far, float(grid.closest(p)[0]))
	ok(far <= 0.003, "every output vertex within %.4f mm of the input skin (<= 3 mm)" % (far * 1000.0))

	# ---- 6 manifold
	var cnt := func(k: KMesh) -> Dictionary:
		var ec := {}
		for f in k.faces:
			var fp: PackedInt32Array = f
			for i in fp.size():
				var a := fp[i]
				var b := fp[(i + 1) % fp.size()]
				var key2 := Vector2i(mini(a, b), maxi(a, b))
				ec[key2] = int(ec.get(key2, 0)) + 1
		var one := 0
		var many := 0
		for e in ec:
			one += 1 if int(ec[e]) == 1 else 0
			many += 1 if int(ec[e]) > 2 else 0
		return {"ec": ec, "one": one, "many": many}
	var ci: Dictionary = cnt.call(skin)
	var co: Dictionary = cnt.call(out)
	var gen_bad := 0
	var dirs := {}
	var twice := 0
	for fi in out.faces.size():
		var fq: PackedInt32Array = out.faces[fi]
		for i in fq.size():
			var de := Vector2i(fq[i], fq[(i + 1) % fq.size()])
			if dirs.has(de) and (pd[fi] > 0.5 or pd[dirs[de]] > 0.5):
				twice += 1
			dirs[de] = fi
	for fi in out.faces.size():
		if pd[fi] < 0.5:
			continue
		var fp: PackedInt32Array = out.faces[fi]
		for i in fp.size():
			var a := fp[i]
			var b := fp[(i + 1) % fp.size()]
			if int(co["ec"][Vector2i(mini(a, b), maxi(a, b))]) != 2:
				gen_bad += 1
	print("info: open-border edges in %d -> out %d; edges with 3+ faces in %d -> out %d; KMesh manifold: in %s, out %s" % [ci["one"], co["one"], ci["many"], co["many"], str(skin.is_manifold()), str(out.is_manifold())])
	ok(twice == 0, "the generated faces wind the same way as their neighbours (%d directed edges used twice)" % twice)
	ok(gen_bad == 0, "every edge of a generated face has exactly 2 faces (%d do not)" % gen_bad)
	ok(int(co["one"]) <= int(ci["one"]) and int(co["many"]) <= int(ci["many"]), "no new open borders (%d, the skin had %d) and no new over-shared edges (%d, the skin had %d)" % [co["one"], ci["one"], co["many"], ci["many"]])

	# ---- 7 weights
	var chans := []
	for nm in skin.list_attrs():
		if String(nm).begins_with("skin:"):
			chans.append(nm)
	var sum_off := 0.0
	for v in out.verts.size():
		var s := 0.0
		for nm in chans:
			s += float((out.attr_data(nm) as PackedFloat32Array)[v])
		sum_off = maxf(sum_off, absf(s - 1.0))
	ok(chans.size() > 0 and sum_off <= 1e-5, "every vertex's weights (%d skin: channels) sum to 1 (worst off by %.7f)" % [chans.size(), sum_off])
	var old_pos := {}
	for p in skin.verts:
		old_pos[p] = true
	var wbad := 0.0
	var nnew := 0
	for v in out.verts.size():
		if old_pos.has(out.verts[v]):
			continue
		nnew += 1
		var hit: Array = grid.closest(out.verts[v])
		var t: int = hit[1]
		var a := grid.P[grid.T[3 * t]]
		var b := grid.P[grid.T[3 * t + 1]]
		var c := grid.P[grid.T[3 * t + 2]]
		var v0b := b - a
		var v1b := c - a
		var v2b := KMeshDecimate.closest_on_tri(out.verts[v], a, b, c) - a
		var d00 := v0b.dot(v0b)
		var d01 := v0b.dot(v1b)
		var d11 := v1b.dot(v1b)
		var d20 := v2b.dot(v0b)
		var d21 := v2b.dot(v1b)
		var den := d00 * d11 - d01 * d01
		var yy := (d11 * d20 - d01 * d21) / den
		var zz := (d00 * d21 - d01 * d20) / den
		var bc := Vector3(1.0 - yy - zz, yy, zz)
		for nm in chans:
			var col: PackedFloat32Array = skin.attr_data(nm)
			var want := bc.x * col[grid.T[3 * t]] + bc.y * col[grid.T[3 * t + 1]] + bc.z * col[grid.T[3 * t + 2]]
			wbad = maxf(wbad, absf(want - float((out.attr_data(nm) as PackedFloat32Array)[v])))
	ok(nnew > 0 and wbad <= 3.0 / 65535.0, "the %d new verts carry the skin's weights at their nearest point (worst off by %.7f <= 3/65535 = 0.0000458)" % [nnew, wbad])

	# ---- 8 from the joints, not the triangles
	var J2 := J.duplicate()
	var arm_d: Vector3 = ((J["lowerarm_l"] - J["upperarm_l"]) as Vector3).normalized()
	J2["lowerarm_l"] = (J["lowerarm_l"] as Vector3) + arm_d * 0.03
	var r2 := KMeshRigRetopo.build(skin, J2, {"only": ["arm_l"]})
	var r1 := KMeshRigRetopo.build(skin, J, {"only": ["arm_l"]})
	var ax: Vector3 = ((J["hand_l"] - J["upperarm_l"]) as Vector3).normalized()
	var at1 := dense_run(r1["mesh"], J["lowerarm_l"], ax)
	var at2 := dense_run(r2["mesh"], J["lowerarm_l"], ax)
	ok(absf((at2 - at1) - 0.03) <= 0.003 and r2["limbs"][0]["ok"], "FROM THE JOINTS: the left elbow moved 3 cm along the arm moves its dense run of rings %.2f cm (3 +- 0.3), on the same skin" % ((at2 - at1) * 100.0))

	# ---- 9 the preview
	cmd(m, "Model: edit the body mesh")
	await process_frame
	var ui = m.kmed
	ok(ui != null and ui.on and BaseBody.is_open(m), "the body is open in the model preview")
	var line := {}
	for t in MeshTools.TOOLS:
		if t["do"] == "op:rigretopo":
			line = t
	ok(not line.is_empty(), "MeshTools has the line \"%s\" (op:rigretopo)" % line.get("label", "?"))
	var verts0: PackedVector3Array = ui.mesh.verts.duplicate()
	var nf0: int = ui.mesh.faces.size()
	var steps0: int = ui.undo.steps.size()
	var said := MeshTools.op("rigretopo", m)
	await process_frame
	print("info: said: " + said)
	ok(ui.mesh.faces.size() == out.faces.size() and ui.mesh.verts.size() == out.verts.size(), "the preview holds the retopo'd body (%d verts, %d faces)" % [ui.mesh.verts.size(), ui.mesh.faces.size()])
	ok(ui.view.mesh == ui.mesh and ui.view._ftri0.size() == ui.mesh.faces.size(), "the view draws it (%d faces drawn)" % ui.view._ftri0.size())
	ok(ui.undo.steps.size() == steps0 + 1, "ONE mesh undo step (%d -> %d)" % [steps0, ui.undo.steps.size()])
	var cam: Camera3D = m.cam
	var lo := Vector2(INF, INF)
	var hi := -lo
	for p in ui.mesh.verts:
		var s: Vector2 = cam.unproject_position(ui.view.global_transform * p)
		lo = lo.min(s)
		hi = hi.max(s)
	var fr2 := free_rect(m)
	ok(fr2.encloses(Rect2(lo, hi - lo)), "PLACEMENT: the retopo'd body's screen box %s is inside the free view %s" % [str(Rect2(lo, hi - lo)), str(fr2)])
	key(KEY_Z, true)
	await process_frame
	ok(ui.mesh.verts == verts0 and ui.mesh.faces.size() == nf0, "Ctrl+Z gives the skin back (%d verts bit for bit, %d faces)" % [ui.mesh.verts.size(), ui.mesh.faces.size()])
	key(KEY_Y, true)
	await process_frame
	ok(ui.mesh.faces.size() == out.faces.size(), "Ctrl+Y does the retopo again (%d faces)" % ui.mesh.faces.size())
	key(KEY_ESCAPE)
	await process_frame
	print("rigretopo: %d failed" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
