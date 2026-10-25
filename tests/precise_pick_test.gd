## godot --path . -s tests/precise_pick_test.gd     (a window: real mouse events, the screenshots and the pixel checks)
## PRECISE PICK (Nick 10-19: "clicking a body part should be 100% precise to the body"). The click and the light read the
## skinned mesh as drawn (scripts/skin_pick.gd), not capsules. combo3 at 2.0 s (elbows and knees bent: corrective shapes
## on) with a fist on the right hand (fingers curled), opened read only. TRUTH here is computed independently of
## SkinPick's own tables: the skin weights are read again from assets/mannequin.glb and each bone mapped to its part by
## this test's own walk up the skeleton; visibility is a brute-force ray against EVERY posed triangle (no broad phase).
## Bars, written before measuring:
##   A SAMPLES: 200 random points on the visible skin (140 in the whole-body view, 60 in a close-up of the fisted hand),
##     each found by a uniform random point on a random triangle (area-weighted), projected to the screen and kept only
##     when the brute-force ray through that pixel meets the skin first at that point (within 1 mm). A REAL mouse motion
##     to the pixel: the hovered part equals the part with the largest skin weight at the point (the corners' weights
##     blended by the barycentric coordinates) in >= 99% (misses printed with their weights). 30 of them are also real
##     clicks: the picked part (m.sel) equals it in >= 29 of 30.
##   B OUTSIDE: 40 points 3 px outside the body's silhouette (rows across the body, the first skin pixel found from the
##     left and from the right to 0.05 px; the brute force confirms the 3 px point misses the skin): no hover and _pick
##     gives "" at all 40 (and 0.5 px INSIDE the edge the skin is hit at >= 38 of 40: the edge is real).
##   C EXACT SET: for the right hand, the left foot, the left thigh and the right index's middle joint, picked in turn:
##     the vertices the light tints (SkinPick.dominant_part's look = the pick's) equal the vertices whose dominant part
##     (the glb's weights, this test's own part map) is that part, exactly (0 extra, 0 missing). No proxy: no capsule
##     mesh named for a body part and no visible CapsuleMesh anywhere in the tree.
##   C2 PLACEMENT (the GPU draws what the CPU says, whole-body view): a screenshot with the light and one with it off;
##     at the pixel of each vertex on screen, the brute-force ray through the pixel's CENTRE names the triangle drawn
##     there; where that triangle is INSIDE the part (its corners and all their neighbours dominated by it) the colour
##     changed for >= 90% of the pixels; where it is inside an OTHER part (one with no light of its own), changed for <= 1%.
##   D SPEED: the hover pick (m.pick_us, real motions of bar A, pose unchanged) p95 < 2 ms. The re-skin after a pose
##     change is printed (not barred).
## Screenshots (C:/Users/Nick/.claude/jobs/9afc22db/tmp/): precisepick.png (picked hand close-up), precisepick_foot.png,
## precisepick_thigh_hover.png, precisepick_index.png. Nothing is written to scenes/, poses/ or data/.
extends SceneTree

var fails := 0
var m: Node
var rng := RandomNumberGenerator.new()
const TMP := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/"
var truth_w := []   # surface k -> Array of {part index: weight} per vertex (the glb's weights, this test's map)
var nbr := []       # surface k -> Array of PackedInt32Array neighbours
var pick_times := []


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.relative = Vector2(1, 0)
	root.push_input(e)
	await process_frame


func click(p: Vector2) -> void:
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = p
		e.global_position = p
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		root.push_input(e)
		await process_frame


## the glb's own weights, mapped bone -> part by walking up to the nearest Body.ORDER joint (root -> pelvis)
func read_truth() -> void:
	var man: Node3D = (load("res://assets/mannequin.glb") as PackedScene).instantiate()
	root.add_child(man)
	var sk: Skeleton3D = man.find_children("*", "Skeleton3D", true, false)[0]
	var src: MeshInstance3D = man.find_children("*", "MeshInstance3D", true, false)[0]
	var skin: Skin = src.skin
	var part_of_bone := {}
	for b in sk.get_bone_count():
		var c := b
		while c >= 0:
			var nm := sk.get_bone_name(c)
			var j := "head" if nm == "Head" else nm
			if Body.ORDER.has(j):
				break
			c = sk.get_bone_parent(c)
		part_of_bone[b] = Body.ORDER.find(sk.get_bone_name(c) if sk.get_bone_name(c) != "Head" else "head") if c >= 0 else 0
	var bind_part := []
	for k in skin.get_bind_count():
		var bb := skin.get_bind_bone(k)
		if bb < 0:
			bb = sk.find_bone(skin.get_bind_name(k))
		bind_part.append(part_of_bone[bb])
	var skp: SkinPick = m.skp
	truth_w = []
	nbr = []
	for k in skp.surfs.size():
		var n: int = (skp.surfs[k]["rest"] as PackedVector3Array).size()
		var arr: Array = []
		for si in src.mesh.get_surface_count():
			var a: Array = src.mesh.surface_get_arrays(si)
			if (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() == n:
				arr = a
		var bo: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var w: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var per := bo.size() / n
		var tw := []
		for i in n:
			var d := {}
			var tot := 0.0
			for q in per:
				if w[i * per + q] > 0.0:
					tot += w[i * per + q]
			for q in per:
				if w[i * per + q] > 0.0:
					var pi: int = bind_part[bo[i * per + q]]
					d[pi] = float(d.get(pi, 0.0)) + w[i * per + q] / tot
			tw.append(d)
		truth_w.append(tw)
		var sets := []
		for i in n:
			sets.append({})
		var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for t in range(0, ix.size(), 3):
			for q in 3:
				for r in 3:
					sets[ix[t + q]][ix[t + r]] = true
		var nb := []
		for st in sets:
			nb.append(PackedInt32Array(st.keys()))
		nbr.append(nb)
	man.queue_free()


static func argmax(d: Dictionary) -> int:
	var bp := -1
	var bw := -1.0
	for pi in d:
		if float(d[pi]) > bw or (float(d[pi]) == bw and int(pi) < bp):
			bw = d[pi]
			bp = pi
	return bp


func truth_part(k: int, tri: Vector3i, bc: Vector3) -> String:
	var s := {}
	for q in 3:
		var d: Dictionary = truth_w[k][tri[q]]
		for pi in d:
			s[pi] = float(s.get(pi, 0.0)) + float(d[pi]) * bc[q]
	return Body.ORDER[argmax(s)]


func truth_dom(k: int, i: int) -> String:
	return Body.ORDER[argmax(truth_w[k][i])]


## every visible triangle of the body, posed: [[k, a, b, c], ...] (each triangle once: the pieces split them)
func all_tris() -> Array:
	var out := []
	var skp: SkinPick = m.skp
	skp.refresh()
	for g in skp.groups:
		if not (g["mi"] as MeshInstance3D).is_visible_in_tree():
			continue
		for c in g["chunks"]:
			var tr: PackedInt32Array = c["tris"]
			for t in range(0, tr.size(), 3):
				out.append([int(g["k"]), tr[t], tr[t + 1], tr[t + 2]])
	return out


## the brute force: the nearest skin hit along the ray (distance, INF none)
func brute(o: Vector3, d: Vector3, tris: Array) -> float:
	var best := INF
	var skp: SkinPick = m.skp
	for t in tris:
		var pos: PackedVector3Array = skp.surfs[t[0]]["pos"]
		var r = Geometry3D.ray_intersects_triangle(o, d, pos[t[1]], pos[t[2]], pos[t[3]])
		if r != null:
			best = minf(best, ((r as Vector3) - o).dot(d))
	return best


## the brute force's nearest triangle: [k, a, b, c] ([] none)
func brute_hit(o: Vector3, d: Vector3, tris: Array) -> Array:
	var best := INF
	var out := []
	var skp: SkinPick = m.skp
	for t in tris:
		var pos: PackedVector3Array = skp.surfs[t[0]]["pos"]
		var r = Geometry3D.ray_intersects_triangle(o, d, pos[t[1]], pos[t[2]], pos[t[3]])
		if r != null and ((r as Vector3) - o).dot(d) < best:
			best = ((r as Vector3) - o).dot(d)
			out = t
	return out


func view_rect() -> Rect2:
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	return Rect2(Vector2(m.lw() + 6, m.TOP_H + 6), Vector2(vs.x - m.rw() - m.lw() - 12, vs.y - m.bottom_h - m.LINE_H - m.TOP_H - 12))


## n visible random skin points in the current view: [[screen, part, info], ...]
func samples(n: int, tris: Array, want := "") -> Array:
	var skp: SkinPick = m.skp
	var areas := PackedFloat32Array()
	var tot := 0.0
	for t in tris:
		var pos: PackedVector3Array = skp.surfs[t[0]]["pos"]
		tot += ((pos[t[2]] - pos[t[1]]).cross(pos[t[3]] - pos[t[1]])).length() * 0.5
		areas.append(tot)
	var out := []
	var vr := view_rect()
	var tries := 0
	while out.size() < n and tries < (n * 40 if want == "" else 6000):
		tries += 1
		var x := rng.randf() * tot
		var lo := 0
		var hi := areas.size() - 1
		while lo < hi:
			var mid := (lo + hi) / 2
			if areas[mid] < x:
				lo = mid + 1
			else:
				hi = mid
		var t: Array = tris[lo]
		var pos: PackedVector3Array = skp.surfs[t[0]]["pos"]
		var u := rng.randf()
		var v := rng.randf()
		if u + v > 1.0:
			u = 1.0 - u
			v = 1.0 - v
		var bc := Vector3(1.0 - u - v, u, v)
		var p: Vector3 = pos[t[1]] * bc.x + pos[t[2]] * bc.y + pos[t[3]] * bc.z
		if m.cam.is_position_behind(p):
			continue
		var sp: Vector2 = m.cam.unproject_position(p)
		if not vr.has_point(sp):
			continue
		var o: Vector3 = m.cam.project_ray_origin(sp)
		var d: Vector3 = m.cam.project_ray_normal(sp)
		if absf(brute(o, d, tris) - (p - o).dot(d)) > 0.001:
			continue   # another part of the skin is in front of it
		var tp := truth_part(int(t[0]), Vector3i(t[1], t[2], t[3]), bc)
		if want != "" and tp != want:
			continue
		var sums := {}
		for q in 3:
			var dd: Dictionary = truth_w[t[0]][t[q + 1]]
			for pi in dd:
				sums[Body.ORDER[pi]] = snappedf(float(sums.get(Body.ORDER[pi], 0.0)) + float(dd[pi]) * bc[q], 0.001)
		out.append([sp, tp, sums])
	return out


## hover each sample with a real motion: [hits, misses]
func hover_all(ss: Array, label: String) -> Array:
	var hit := 0
	var miss := []
	for s in ss:
		await move(s[0] + Vector2(7, 5))   # away first: every sample is a fresh hover
		await move(s[0])
		pick_times.append(int(m.pick_us))
		if m.hover_part == s[1]:
			hit += 1
		else:
			var gc: Control = root.gui_get_hovered_control()
			miss.append("%s at %s: hovered '%s', truth %s, weights %s%s" % [label, s[0].round(), m.hover_part, s[1], s[2], (", under the control " + gc.name) if gc != null else ""])
	return [hit, miss]


func shot(name: String, region := Rect2i(), scale := 1) -> Image:
	var img: Image = m.get_viewport().get_texture().get_image()
	var out := img
	if region.size.x > 0:
		out = img.get_region(region)
		out.resize(region.size.x * scale, region.size.y * scale, Image.INTERPOLATE_LANCZOS)
	out.save_png(TMP + name)
	return img


## the vertices tinted with the PICK's look (the sel look: rim 1) -> {"k|i": true}
func tinted_sel() -> Dictionary:
	var skp: SkinPick = m.skp
	var out := {}
	for k in skp.surfs.size():
		var n: int = (skp.surfs[k]["rest"] as PackedVector3Array).size()
		for i in n:
			var lk: Array = skp.look_of(skp.dominant_part(k, i))
			if not lk.is_empty() and float(lk[1]) >= 1.0:
				out["%d|%d" % [k, i]] = true
	return out


## C2: the light's pixels. Visible interior vertices of part j vs of the parts with no light: [in_changed, in_n, out_changed, out_n]
func placement(j: String, tris: Array) -> Array:
	await idle(3)
	var on_img: Image = m.get_viewport().get_texture().get_image()
	var keep: Dictionary = m.skp._state.duplicate(true)
	var without := keep.duplicate(true)
	without.erase(j)   # only this part's light off: the others (a finger at its limit) stay as they are
	m.skp.set_looks(without)
	await idle(3)
	var off_img: Image = m.get_viewport().get_texture().get_image()
	m.skp.set_looks(keep)
	await idle(3)
	var skp: SkinPick = m.skp
	var vr := view_rect()
	var res := [0, 0, 0, 0]
	var dbg := []
	var seen := {}
	for k in skp.surfs.size():
		var pos: PackedVector3Array = skp.surfs[k]["pos"]
		for i in pos.size():
			if m.cam.is_position_behind(pos[i]):
				continue
			var sp: Vector2 = m.cam.unproject_position(pos[i])
			if not vr.has_point(sp):
				continue
			var px := Vector2i(sp)   # the pixel the vertex falls in: what is drawn at its CENTRE is the triangle the
			if seen.has(px):          # centre's ray meets first (the brute force), so that triangle is the truth there
				continue
			seen[px] = true
			var pc := Vector2(px) + Vector2(0.5, 0.5)
			var h := brute_hit(m.cam.project_ray_origin(pc), m.cam.project_ray_normal(pc), tris)
			if h.is_empty():
				continue
			var hk: int = h[0]
			var dj := truth_dom(hk, h[1])
			var inside := true   # the hit triangle's corners, and all their neighbours, of one part
			for c in [h[1], h[2], h[3]]:
				if truth_dom(hk, c) != dj:
					inside = false
				for q in nbr[hk][c]:
					if truth_dom(hk, q) != dj:
						inside = false
			if not inside:
				continue
			var lit: bool = dj == j
			if not lit and not skp.look_of(dj).is_empty():
				continue   # a part with a light of its own (a finger at its limit)
			var a := on_img.get_pixelv(px)
			var b := off_img.get_pixelv(px)
			var changed := absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.06
			if lit:
				res[0] += int(changed)
				res[1] += 1
			else:
				res[2] += int(changed)
				res[3] += 1
				if changed and dbg.size() < 12:
					var o2: Vector3 = m.cam.project_ray_origin(pc)
					var d2: Vector3 = m.cam.project_ray_normal(pc)
					var jt := tris.filter(func(t): return truth_dom(t[0], t[1]) == j)
					dbg.append("%s at %s (colour moved %.2f; the %s's skin %.2f mm behind it)" % [dj, px, absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b), j, (brute(o2, d2, jt) - brute(o2, d2, tris)) * 1000.0])
	print("  changed others (", j, "): ", dbg)
	return res


func pick_part(j: String) -> void:
	m.sel = j
	m.hover_part = ""
	m._refresh()
	await idle(3)


func _init() -> void:
	rng.seed = 1019
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.playhead = 2.0
	m.playing = false
	m._ps().apply(m.B, m.playhead)
	m.sel = "hand_r"
	m._refresh()
	m._pose_pick("fist")
	m.undo.clear()
	m.redo.clear()
	m.dummy_on = false
	m.B.wep_on = false
	m.B.wep2_on = false
	m._refresh()
	await idle(4)
	read_truth()
	var t0 := Time.get_ticks_usec()
	m.skp.mark()
	m.skp.refresh()
	print("re-skin after a pose change: %.1f ms (%d vertices, %d chunks)" % [(Time.get_ticks_usec() - t0) / 1000.0, m.skp.surfs.reduce(func(a, s): return a + (s["rest"] as PackedVector3Array).size(), 0), m.skp.groups.reduce(func(a, g): return a + g["chunks"].size(), 0)])

	# ---- A: the whole body
	m._view_home(false)
	await idle(4)
	var tris := all_tris()
	var ss := samples(140, tris)
	var full := ss.duplicate()
	await move(ss[0][0])   # warm (the first pick after the pose: the re-skin)
	pick_times = []
	var r1: Array = await hover_all(ss, "body")
	# ---- A: the fisted hand, close
	m._turn_to(-90.0, -8.0, 0.9, m.B.P["hand_r"] + m.B.offset, false)
	await idle(4)
	var ss2 := samples(60, tris)
	var r2: Array = await hover_all(ss2, "hand")
	var hits: int = r1[0] + r2[0]
	var n_all := ss.size() + ss2.size()
	for s in r1[1] + r2[1]:
		print("  miss: " + s)
	var fingers := ss2.filter(func(s): return Body.FINGERS.has(s[1])).size()
	ok(n_all >= 200 and hits >= ceili(n_all * 0.99), "A %d of %d random visible skin points (140 body, 60 hand close-up: %d on fingers) hovered as the part with the most skin weight there (%.1f%%; bar >= 99%%)" % [hits, n_all, fingers, 100.0 * hits / maxi(n_all, 1)])
	# 30 real clicks (the hand close-up's first 15 and the body's first 15)
	var cl := 0
	var cmiss := []
	for s in ss2.slice(0, 15):
		await click(s[0])
		if m.sel == s[1]:
			cl += 1
		else:
			cmiss.append("%s -> %s" % [s[1], m.sel])
	m._view_home(false)
	await idle(4)
	for s in full.slice(0, 15):
		await click(s[0])
		if m.sel == s[1]:
			cl += 1
		else:
			cmiss.append("%s -> %s" % [s[1], m.sel])
	ok(cl >= 29, "A2 %d of 30 real clicks pick the part with the most skin weight at the point (misses: %s)" % [cl, cmiss])

	# ---- D: the hover's cost
	pick_times.sort()
	var p95: int = pick_times[int(pick_times.size() * 0.95)]
	ok(p95 < 2000, "D hover pick p95 %.2f ms over %d real motions (median %.2f ms, max %.2f ms; bar < 2 ms)" % [p95 / 1000.0, pick_times.size(), pick_times[pick_times.size() / 2] / 1000.0, pick_times[-1] / 1000.0])

	# ---- B: 3 px outside the silhouette, whole body
	await pick_part("head")
	tris = all_tris()
	var lo_y := INF
	var hi_y := -INF
	for t in tris:
		var sp: Vector2 = m.cam.unproject_position(m.skp.surfs[t[0]]["pos"][t[1]])
		lo_y = minf(lo_y, sp.y)
		hi_y = maxf(hi_y, sp.y)
	var vr := view_rect()
	var outside_ok := 0
	var inside_ok := 0
	var bad := []
	var hit_at := func(p: Vector2) -> bool:
		return String(m.skp.pick(m.cam.project_ray_origin(p), m.cam.project_ray_normal(p))[0]) != ""
	for row in 20:
		var y := lerpf(lo_y + 4.0, hi_y - 4.0, (row + 0.5) / 20.0)
		for side in [1, -1]:
			var x0: float = vr.position.x + 2.0 if side == 1 else vr.end.x - 2.0
			var x: float = x0
			while (x < vr.end.x if side == 1 else x > vr.position.x) and not hit_at.call(Vector2(x, y)):
				x += 2.0 * side
			var a: float = x - 2.0 * side   # off
			var b: float = x                # on
			for it in 6:
				var mid: float = (a + b) * 0.5
				if hit_at.call(Vector2(mid, y)):
					b = mid
				else:
					a = mid
			var p_out := Vector2(b - 3.0 * side, y)
			var p_in := Vector2(b + 0.5 * side, y)
			var bf := brute(m.cam.project_ray_origin(p_out), m.cam.project_ray_normal(p_out), tris)
			await move(p_out)
			var picked: String = m._pick(p_out)
			if m.hover_part == "" and picked == "" and bf == INF:
				outside_ok += 1
			else:
				bad.append("%s: hover '%s' pick '%s' brute %.3f" % [p_out.round(), m.hover_part, picked, bf])
			if m._pick(p_in) != "":
				inside_ok += 1
	ok(outside_ok == 40 and inside_ok >= 38, "B 3 px outside the silhouette: nothing picked at %d of 40 (bad: %s); 0.5 px inside: the skin at %d of 40" % [outside_ok, bad.slice(0, 3), inside_ok])

	# ---- C: the exact tinted sets, no proxy, and the placement on screen
	var proxies := []
	var caps_vis := []
	for n in m.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if String(mi.name).begins_with("cap_") and Body.ORDER.has(String(mi.name).substr(4)):
			proxies.append(mi.name)
		if mi.mesh is CapsuleMesh and mi.is_visible_in_tree():
			caps_vis.append(mi.get_path())
	for j in ["hand_r", "foot_l", "thigh_l", "index_02_r"]:
		await pick_part(j)
		var got := tinted_sel()
		var extra := 0
		var missing := 0
		var want_n := 0
		for k in truth_w.size():
			for i in (truth_w[k] as Array).size():
				var want: bool = truth_dom(k, i) == j
				var has: bool = got.has("%d|%d" % [k, i])
				want_n += int(want)
				extra += int(has and not want)
				missing += int(want and not has)
		ok(want_n > 0 and extra == 0 and missing == 0, "C %s: the light tints %d vertices, its dominant-weight vertices are %d: %d extra, %d missing" % [j, got.size(), want_n, extra, missing])
	ok(proxies.is_empty() and caps_vis.is_empty(), "C no proxy: body-part capsules in the tree %s, visible capsule meshes %s" % [proxies, caps_vis])

	# C2 + the shots: the whole-body view (the left foot, the left thigh hovered), then the hand and the index close
	m._view_home(false)
	await pick_part("foot_l")
	var pf: Array = await placement("foot_l", tris)
	var fsp: Vector2 = m.cam.unproject_position(m.B.P["foot_l"] + m.B.offset)
	shot("precisepick_foot.png", Rect2i(Rect2i(fsp - Vector2(110, 70), Vector2(220, 140))), 3)
	ok(pf[1] >= 20 and pf[0] >= pf[1] * 0.9 and pf[2] <= pf[3] * 0.01, "C2 the left foot, whole body: the light shows at %d of %d of its visible interior vertices, and at %d of %d of the other parts'" % [pf[0], pf[1], pf[2], pf[3]])
	await pick_part("thigh_l")
	var pt: Array = await placement("thigh_l", tris)
	ok(pt[1] >= 20 and pt[0] >= pt[1] * 0.9 and pt[2] <= pt[3] * 0.01, "C2 the left thigh, whole body: the light shows at %d of %d of its visible interior vertices, and at %d of %d of the other parts'" % [pt[0], pt[1], pt[2], pt[3]])
	await pick_part("head")
	var th := samples(1, tris, "thigh_l")
	if not th.is_empty():
		await move(th[0][0])
		await idle(3)
		var tsp: Vector2 = th[0][0]
		shot("precisepick_thigh_hover.png", Rect2i(Rect2i(tsp - Vector2(120, 110), Vector2(240, 220))), 2)
		ok(m.hover_part == "thigh_l" and m.skin_col("thigh_l").a > 0.0 and m.skin_col("thigh_l").a < m.skin_col("head").a,
			"C2 the thigh hovered by a real motion: lit fainter (%.2f) than the picked head (%.2f)" % [m.skin_col("thigh_l").a, m.skin_col("head").a])
	await move(Vector2(view_rect().position.x + 4, view_rect().position.y + 4))
	m._turn_to(-90.0, -8.0, 0.9, m.B.P["hand_r"] + m.B.offset, false)
	await pick_part("hand_r")
	var ph: Array = await placement("hand_r", tris)
	ok(ph[1] >= 20 and ph[0] >= ph[1] * 0.9 and ph[2] <= ph[3] * 0.01, "C2 the right hand, close: the light shows at %d of %d of its visible interior vertices, and at %d of %d of the other parts'" % [ph[0], ph[1], ph[2], ph[3]])
	shot("precisepick.png")
	# the index finger: the hand opened (the fist hid the index's middle joint), close from the thumb's side
	m.B.hand_shape("r", "open")
	m._refresh()
	var mid3: Vector3 = (m.B.P["index_02_r"] + m.B.offset)
	m._turn_to(-60.0, -20.0, 0.45, mid3, false)
	await pick_part("hand_r")
	tris = all_tris()
	var ix := samples(1, tris, "index_02_r")
	if ix.is_empty():
		ix = samples(1, tris, "index_01_r")
	if not ix.is_empty():
		await click(ix[0][0])
		await move(view_rect().position + Vector2(4, 4))
		await idle(3)
		ok(m.sel == ix[0][1], "A3 a real click on the index finger's skin picks %s (wanted %s)" % [m.sel, ix[0][1]])
		var isp: Vector2 = ix[0][0]
		shot("precisepick_index_full.png")
		shot("precisepick_index.png", Rect2i(Rect2i(isp - Vector2(200, 130), Vector2(400, 260))), 2)
	else:
		ok(false, "A3 no visible index finger skin in the close-up")
	print("PRECISE PICK: %d failed" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
