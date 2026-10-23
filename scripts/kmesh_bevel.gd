class_name KMeshBevel
extends RefCounted
## EDGE BEVEL on a KMesh (ROADMAP_400 B03, the bevel half; inset + bridge are in kmesh_extrude.gd). A static op that edits
## the mesh in place (one from_arrays at the end, so a KMeshUndo begin / commit around it is one "topo" step) and returns
## the new selection {"verts", "edges", "faces" (the bevel faces), "error": "" or a message with the next step}.
## Every selected edge must have a face on both sides (an open border cannot be bevelled here: the op refuses it).
## Width = the OFFSET: each new edge runs parallel to its old edge, `width` from it inside the face it lies in.
## Around a bevelled vertex v the faces are walked in order; the bevelled edges cut that fan into sectors. A sector of:
##   1 face (two bevelled edges of the same face meet at v): one new vert where the two offset lines cross (inset rule);
##   2 faces (one plain edge between them): one new vert ON that plain edge (the two slides averaged);
##   3+ faces: a new vert slides along each of its two outer plain edges (`width / sin(angle to the bevelled edge)` from
##     v, so it is `width` from the bevelled edge); v stays for the faces in between.
## Each bevelled edge then gets, at each end, a profile of `segments` + 1 points from the vert on one side to the vert on
## the other, and a strip of `segments` quads between its two end profiles. The profile is a superellipse in the
## (skewed) frame O = a + b - v, U = a - O, W = b - O: points O + U x + W y with x^r + y^r = 1, r = -2 / log2(profile)
## (Blender's idea, own code): profile 0.5 -> r 2, a round arc (a quarter circle where the faces meet at 90 deg);
## 0.25 -> r 1, the straight chamfer; below 0.25 concave (bowed in towards O); above 0.5 fuller, 1 -> the square corner
## (the profile runs a -> v -> b). Points are spaced evenly along the curve; the ends are tangent to the faces.
## What is left round v: with two bevelled edges and no 3+ sector both strips share one profile (nothing to fill); else
## one face closes the hole (the profiles in turn, plus v where a 3+ sector keeps it). When v sits in only one other face
## (a 3-face sector: a cube corner), that face takes the profile instead of v, so bevelling one cube edge gives the
## Blender counts: 1 segment 10 verts / 7 faces, 3 segments 14 / 9.
## The width is clamped so no slide passes the middle of its edge (two bevels meeting on one edge would cross): the
## result says "clamped". Attributes follow (KMeshExtrude._commit): a new vert copies v, a strip copies the face of its
## edge's first side. Tests: tests/bevel_test.gd.
## UI (kmesh_edit_ui.gd, key()): Ctrl+B bevels the selection (edges; other modes convert) with 2 cm, 1 segment, round.
## While that bevel is the last edit it stays LIVE: [ / ] segments -1 / +1, Shift+[ / ] width -0.5 / +0.5 cm,
## Alt+[ / ] profile -0.05 / +0.05; each change rebuilds it in place, still ONE undo step.

const WIDTH := 0.02        # m: Ctrl+B's default
const SEGMENTS := 1
const PROFILE := 0.5       # round
const MAX_SEGMENTS := 32
const WIDTH_STEP := 0.005  # m per Shift+[ / ]
const WIDTH_MIN := 0.001
const PROFILE_STEP := 0.05
const PROFILE_MIN := 0.05
const SIN_MIN := 0.05      # a plain edge almost in line with the bevelled one: slide by `width` itself
const MIN_COS := 0.1
const SAMPLES := 512       # dense samples of the superellipse before the even re-spacing
const EPS := 1e-6


## the profile from a to b round corner c: segments + 1 points, a and b exact (see the class comment)
static func profile_points(a: Vector3, b: Vector3, c: Vector3, segments: int, profile: float) -> PackedVector3Array:
	var dense := PackedVector3Array()
	if profile >= 0.999:
		dense = PackedVector3Array([a, c, b])
	else:
		var o := a + b - c
		var u := a - o
		var w := b - o
		var e := -log(clampf(profile, 0.001, 0.999)) / log(2.0)   # 2 / r
		for j in SAMPLES + 1:
			var th := PI * 0.5 * float(j) / float(SAMPLES)
			dense.append(o + u * pow(maxf(cos(th), 0.0), e) + w * pow(maxf(sin(th), 0.0), e))
		dense[0] = a
		dense[SAMPLES] = b
	var cum := PackedFloat64Array([0.0])
	for j in range(1, dense.size()):
		cum.append(cum[j - 1] + dense[j].distance_to(dense[j - 1]))
	var total := cum[cum.size() - 1]
	var out := PackedVector3Array([a])
	var j := 1
	for i in range(1, segments):
		var s := total * float(i) / float(segments)
		while j < dense.size() - 1 and cum[j] < s:
			j += 1
		var span := cum[j] - cum[j - 1]
		var t := (s - cum[j - 1]) / span if span > EPS * EPS else 0.0
		out.append(dense[j - 1].lerp(dense[j], t))
	out.append(b)
	return out


## the faces round v in order: [{"h": outgoing half-edge v->x, "f": its face, "x": x}], starting at half-edge h0
## (fan step: h' = the twin of the half-edge entering v in h's face). [] when v is on an open border.
static func _fan(m: KMesh, v: int, h0: int) -> Array:
	var out: Array = []
	var h := h0
	var hv := m.he_vert
	while true:
		var nx: int = hv[m.he_next[h]]
		out.append({"h": h, "f": m.he_face[h], "x": nx})
		var y: int = hv[m.he_prev(h)]
		h = m.find_half_edge(v, y)
		if h == -1 or out.size() > 256:
			return []
		if h == h0:
			return out
	return out


## slide from v along plain edge v->y so the point is `w` from the line of the bevelled edge v->x
static func _slide(m: KMesh, v: int, y: int, x: int, w: float) -> float:
	var u := (m.verts[y] - m.verts[v]).normalized()
	var b := (m.verts[x] - m.verts[v]).normalized()
	var s := u.cross(b).length()
	return w / s if s > SIN_MIN else w


## Bevel the edges `es` (Vector2i) by `width` (m) with `segments` and `profile`. Returns the bevel faces as the selection.
static func bevel_edges(m: KMesh, es: Array, width: float, segments := SEGMENTS, profile := PROFILE) -> Dictionary:
	if es.is_empty():
		return _none("pick edges first (2 = edge mode, then click one; Ctrl+B bevels)")
	segments = clampi(segments, 1, MAX_SEGMENTS)
	var bev := {}
	for e in es:
		var k := KMeshSelect.ekey(e.x, e.y)
		if m.find_half_edge(k.x, k.y) == -1 or m.find_half_edge(k.y, k.x) == -1:
			return _none("edge %d-%d has a face on one side only (an open border): bevel needs a face on both sides" % [k.x, k.y])
		bev[k] = true
	# the fans of the bevelled verts, each started at a bevelled edge
	var fans := {}
	for k in bev:
		for v in [k.x, k.y]:
			if fans.has(v):
				continue
			var other: int = k.y if v == k.x else k.x
			var f := _fan(m, v, m.find_half_edge(v, other))
			if f.is_empty():
				return _none("vertex %d is on an open border or not a clean fan: bevel works on closed, manifold surfaces" % v)
			fans[v] = f
	# the width: no slide past the middle of its edge
	var w := width
	var clamped := false
	for v in fans:
		var fan: Array = fans[v]
		var n := fan.size()
		for i in n:
			var isb := bev.has(KMeshSelect.ekey(v, fan[i]["x"]))
			var nb := bev.has(KMeshSelect.ekey(v, fan[(i + 1) % n]["x"]))
			var pb := bev.has(KMeshSelect.ekey(v, fan[(i - 1 + n) % n]["x"]))
			if isb:
				if nb:   # two bevelled edges of one face: the crossing point is `width` along both
					var lim := 0.5 * minf(m.verts[v].distance_to(m.verts[fan[i]["x"]]), m.verts[v].distance_to(m.verts[fan[(i + 1) % n]["x"]]))
					if w > lim:
						w = lim * 0.999
						clamped = true
				continue
			var y: int = fan[i]["x"]
			var ln := m.verts[v].distance_to(m.verts[y])
			for nbr in ([fan[(i + 1) % n]["x"]] if nb else []) + ([fan[(i - 1 + n) % n]["x"]] if pb else []):
				var s := _slide(m, v, y, nbr, w)
				if s > 0.5 * ln:
					w *= 0.5 * ln / s * 0.999
					clamped = true
	var nverts := m.verts.duplicate()
	var src_v := PackedInt32Array()
	for v in m.verts.size():
		src_v.append(v)
	var rep := {}          # face * V + v -> [verts that replace corner v]
	var chain := {}        # v * V + x (bevelled edge v->x, h-face side first) -> PackedInt32Array of segments + 1 verts
	var holes: Array = []  # [poly, src face]
	var merge := {}        # face * V + v -> poly to splice in place of v
	var nv := m.verts.size()
	for v in fans:
		var fan: Array = fans[v]
		var n := fan.size()
		var bi := []
		for i in n:
			if bev.has(KMeshSelect.ekey(v, fan[i]["x"])):
				bi.append(i)
		var d := bi.size()
		var sec: Array = []   # per sector: {"i0", "k", "a", "b"}
		for si in d:
			var i0: int = bi[si]
			var i1: int = bi[(si + 1) % d]
			var k := posmod(i1 - i0, n) if d > 1 else n
			var a := -1
			var b := -1
			var p := m.verts[v]
			if k == 1:
				var x: int = fan[i0]["x"]
				var y: int = fan[(i0 + 1) % n]["x"]
				var nrm := m.face_normals[fan[i0]["f"]]
				var m1 := nrm.cross((p - m.verts[y]).normalized()).normalized()
				var m2 := nrm.cross((m.verts[x] - p).normalized()).normalized()
				var bis := m1 + m2
				bis = bis.normalized() if bis.length() > EPS else m1
				a = nverts.size()
				nverts.append(p + bis * (w / maxf(bis.dot(m1), MIN_COS)))
				src_v.append(v)
				b = a
			else:
				var ya: int = fan[(i0 + 1) % n]["x"]
				var yb: int = fan[(i1 - 1 + n) % n]["x"]
				var sa := _slide(m, v, ya, fan[i0]["x"], w)
				var sb := _slide(m, v, yb, fan[i1]["x"], w)
				if k == 2:
					a = nverts.size()
					nverts.append(p + (m.verts[ya] - p).normalized() * (sa + sb) * 0.5)
					src_v.append(v)
					b = a
				else:
					a = nverts.size()
					nverts.append(p + (m.verts[ya] - p).normalized() * sa)
					b = a + 1
					nverts.append(p + (m.verts[yb] - p).normalized() * sb)
					src_v.append(v)
					src_v.append(v)
			sec.append({"i0": i0, "k": k, "a": a, "b": b})
			# the corners of the sector's faces
			for j in k:
				var fi: int = fan[(i0 + j) % n]["f"]
				var r: Array = []
				if k <= 2 or j == 0:
					r = [a]
				elif j == k - 1:
					r = [b]
				else:
					if j == k - 2:
						r.append(b)
					r.append(v)
					if j == 1:
						r.append(a)
				rep[fi * nv + v] = r
		# the profiles: across bevelled edge E_i, from the vert of face F_i to the vert of face F_(i-1)
		for si in d:
			var i: int = bi[si]
			var a2: int = sec[si]["a"]
			var b2: int = sec[(si - 1 + d) % d]["b"]
			var key: int = v * nv + int(fan[i]["x"])
			if d == 2 and sec[0]["k"] <= 2 and sec[1]["k"] <= 2 and si == 1:
				var c0: PackedInt32Array = chain[v * nv + int(fan[bi[0]]["x"])]
				var rc := c0.duplicate()
				rc.reverse()
				chain[key] = rc
				continue
			var pts := profile_points(nverts[a2], nverts[b2], m.verts[v], segments, profile)
			var c := PackedInt32Array([a2])
			for t in range(1, segments):
				c.append(nverts.size())
				nverts.append(pts[t])
				src_v.append(v)
			c.append(b2)
			chain[key] = c
		if d == 2 and sec[0]["k"] <= 2 and sec[1]["k"] <= 2:
			continue
		# the hole round v
		var poly: Array = []
		var keep := -1
		for si in d:
			var c: PackedInt32Array = chain[v * nv + int(fan[bi[si]]["x"])]
			for t in range(segments - 1, 0, -1):
				poly.append(c[t])
			var s: Dictionary = sec[si]
			poly.append(s["a"])
			if s["k"] >= 3:
				if keep != -1:
					return _none("vertex %d has two runs of 3+ plain faces between its bevelled edges: bevel fewer edges there" % v)
				keep = si
				poly.append(v)
			if s["b"] != s["a"]:
				poly.append(s["b"])
		if keep != -1 and sec[keep]["k"] == 3:
			var mid: int = fan[(int(sec[keep]["i0"]) + 1) % n]["f"]
			var at := poly.find(v)
			merge[mid * nv + v] = poly.slice(at + 1) + poly.slice(0, at)
		else:
			holes.append([poly, fan[bi[0]]["f"]])
	# the faces: corners replaced
	var nfaces: Array = []
	var src_f := PackedInt32Array()
	for fi in m.faces.size():
		var f: PackedInt32Array = m.faces[fi]
		var g := PackedInt32Array()
		for v in f:
			var key: int = fi * nv + v
			if merge.has(key):
				g.append_array(PackedInt32Array(merge[key]))
			elif rep.has(key):
				g.append_array(PackedInt32Array(rep[key]))
			else:
				g.append(v)
		nfaces.append(g)
		src_f.append(fi)
	var out: Array = []
	for k in bev:
		var h := m.find_half_edge(k.x, k.y)
		var pv: PackedInt32Array = chain[k.x * nv + k.y]
		var cw: PackedInt32Array = chain[k.y * nv + k.x]
		var pw := cw.duplicate()
		pw.reverse()
		for i in segments:
			out.append(nfaces.size())
			nfaces.append(PackedInt32Array([pv[i], pv[i + 1], pw[i + 1], pw[i]]))
			src_f.append(m.he_face[h])
	for hl in holes:
		out.append(nfaces.size())
		nfaces.append(PackedInt32Array(hl[0]))
		src_f.append(hl[1])
	# drop the verts no face uses any more (the bevelled corners)
	var used := PackedInt32Array()
	used.resize(nverts.size())
	used.fill(-1)
	var cv := PackedVector3Array()
	var cs := PackedInt32Array()
	for f in nfaces:
		for v in (f as PackedInt32Array):
			if used[v] == -1:
				used[v] = 0
	for v in nverts.size():
		if used[v] == 0:
			used[v] = cv.size()
			cv.append(nverts[v])
			cs.append(src_v[v])
	for i in nfaces.size():
		var f: PackedInt32Array = nfaces[i]
		for j in f.size():
			f[j] = used[f[j]]
		nfaces[i] = f
	KMeshExtrude._commit(m, cv, nfaces, cs, src_f)
	var r := KMeshExtrude._from_faces(m, out)
	r["width"] = w
	r["clamped"] = clamped
	return r


## Bevel what `sel` holds (edges; vertex / face mode converts to the edges first), then select the bevel faces.
static func bevel(m: KMesh, sel: KMeshSelect, width: float, segments := SEGMENTS, profile := PROFILE) -> Dictionary:
	var md := sel.mode
	sel.set_mode(KMeshSelect.EDGE)
	var r := bevel_edges(m, sel.edges.keys(), width, segments, profile)
	sel.set_mode(md)
	KMeshExtrude.select_result(sel, r)
	return r


static func _none(msg: String) -> Dictionary:
	return {"verts": [], "edges": [], "faces": [], "error": msg}


# ---------------------------------------------------------------- the model preview's keys

const LIVE := "bevel_live"


## the bevel still live in `ui` (a KMeshEditUI): {edges, mode, width, segments, profile, step}, or {} once anything else edited
static func live_of(ui) -> Dictionary:
	if not ui.has_meta(LIVE):
		return {}
	var lv: Dictionary = ui.get_meta(LIVE)
	var st = lv.get("step")
	if st == null or ui.undo.steps.is_empty() or not is_same(ui.undo.steps[ui.undo.steps.size() - 1], st) \
			or not is_same(st["mesh"], ui.mesh) or ui.mesh.verts != st["new_v"] or not KMeshUndo._same_faces(ui.mesh.faces, st["new_f"]):
		ui.remove_meta(LIVE)
		return {}
	return lv


## Ctrl+B, and [ / ] (Shift: width, Alt: profile) while the bevel is live. true = used
static func key(ui, k: InputEventKey) -> bool:
	if k.keycode == KEY_B and k.ctrl_pressed and not k.alt_pressed:
		run(ui)
		return true
	if not (k.keycode == KEY_BRACKETLEFT or k.keycode == KEY_BRACKETRIGHT) or k.ctrl_pressed:
		return false
	var lv := live_of(ui)
	if lv.is_empty():
		return false   # [ / ] are the shape key's then
	var dir := 1 if k.keycode == KEY_BRACKETRIGHT else -1
	var p: Dictionary = lv.duplicate()
	if k.shift_pressed:
		p["width"] = maxf(WIDTH_MIN, float(p["width"]) + WIDTH_STEP * dir)
	elif k.alt_pressed:
		p["profile"] = clampf(snappedf(float(p["profile"]) + PROFILE_STEP * dir, 0.01), PROFILE_MIN, 1.0)
	else:
		p["segments"] = clampi(int(p["segments"]) + dir, 1, MAX_SEGMENTS)
	set_live(ui, p["width"], p["segments"], p["profile"])
	return true


## Ctrl+B: bevel the selection with the defaults; it stays live for [ / ]. Returns what was said
static func run(ui) -> String:
	if ui.has_meta(LIVE):
		ui.remove_meta(LIVE)
	var md: int = ui.sel.mode
	ui.sel.set_mode(KMeshSelect.EDGE)
	var es: Array = ui.sel.edges.keys()
	ui.sel.set_mode(md)
	return _apply(ui, {"edges": es, "mode": md}, WIDTH, SEGMENTS, PROFILE)


## change the live bevel: the mesh goes back to before it and is bevelled again (the old step is replaced: one step)
static func set_live(ui, width: float, segments: int, profile: float) -> String:
	var lv := live_of(ui)
	if lv.is_empty():
		return ""
	ui.undo.undo()
	return _apply(ui, lv, width, segments, profile)


static func _apply(ui, lv: Dictionary, width: float, segments: int, profile: float) -> String:
	var es: Array = lv["edges"]
	ui.sel.clear()
	ui.sel.mode = KMeshSelect.EDGE
	ui.sel.edges.clear()
	for e in es:
		ui.sel.edges[e] = true
	ui.undo.begin(ui.mesh)
	var r := bevel(ui.mesh, ui.sel, width, segments, profile)
	var st: Dictionary = ui.undo.commit("Bevel")
	if ui.sel.mode != lv["mode"] and String(r["error"]) == "":
		ui.sel.set_mode(lv["mode"])
	ui.view.mark_dirty()
	var said := ""
	if String(r["error"]) != "":
		said = "Model: bevel: %s" % r["error"]
		ui.sel.clear()
		ui.sel.mode = lv["mode"]
		if ui.has_meta(LIVE):
			ui.remove_meta(LIVE)
	else:
		ui.set_meta(LIVE, {"edges": es, "mode": lv["mode"], "width": float(r["width"]), "segments": segments, "profile": profile, "step": st})
		said = "Model: bevelled %d edge%s by %s, %d segment%s, profile %.2f%s. [ / ] segments, Shift+[ / ] width, Alt+[ / ] profile; Ctrl+Z takes it back" % [
			es.size(), "" if es.size() == 1 else "s", Units.len(float(r["width"])), segments, "" if segments == 1 else "s", profile,
			" (width clamped: the edges are short)" if r["clamped"] else ""]
	ui.m._say(said)
	return said
