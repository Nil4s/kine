## s262 EXPLODED VIEW (INNOVATION): pull a Part with many bodies apart along an axis so that NO body sweeps through another on its way out.
## The GPU challenge (hall_compare/gpu, Blender notes) hand-wrote the explode order and the backplate passed through its own screws; Kine computes the order.
##
## THE MODEL (all boxes are world AABBs of whole bodies, a "layer" is one or more bodies that move together):
##  - A layer leaves along +axis or -axis. Its SLAB is the part of its swept box beyond its own box: from the leading face out to infinity.
##    A layer is FREE to leave when no layer still in place has a box that overlaps the slab with positive volume. (Boxes that already overlap at rest,
##    a screw in the plate, are fine: only the NEW region it sweeps counts.) A layer that is not free leaves later; the first free one in the given order goes next.
##  - Which way: the side where the layer sticks out most beyond the layers it overlaps (the head of a screw, the far face of a plate), else the side away from the middle.
##  - The biggest layer stays at 0 (the anchor) unless the caller names one.
##  - Distances are fixed from the LAST leaver back to the first: a layer goes the shortest multiple of gap/4 (never less than gap) such that its final box, padded by gap
##    along the axis, clears the whole travel envelope (rest box + final box) of every layer that leaves after it, and its own slab clears their rest boxes.
##  - Timing: out is staggered; a layer starts at its stagger slot or later, when its motion samples clear every layer already moving. In is the out run played backwards.
## check() is an independent test of a schedule: at many times it asks whether any layer's new swept region overlaps another layer's CURRENT box.
## The naive given order (index order) is reported by the same check as a collision.
class_name ExplodeView
extends RefCounted

const EPS := 1.0e-6
const BIG := 1.0e7
## "to infinity" for a slab: a few part-sizes, set by plan(). AABB is float32: with 1e7 the far face of a downward slab (pos - 1e7 + 1e7) lost every digit below 1 unit (the GPU part: a screw "blocked" by the PCB above it)
static var reach_world := 100.0


static func axis_vec(a: String) -> Vector3:
	match a.to_lower():
		"x", "left-right", "side":
			return Vector3.RIGHT
		"z", "front-back":
			return Vector3.BACK
	return Vector3.UP


static func _k(axis: Vector3) -> int:
	return 0 if absf(axis.x) > 0.5 else (2 if absf(axis.z) > 0.5 else 1)


static func smooth(x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## the AABB of a set of boxes
static func union_box(boxes: Array, idx: Array) -> AABB:
	var out := AABB()
	var first := true
	for i in idx:
		var b: AABB = boxes[int(i)]
		out = b if first else out.merge(b)
		first = false
	return out


## positive-volume overlap of two boxes (touching faces are not an overlap)
static func overlaps(a: AABB, b: AABB, eps := EPS) -> bool:
	var a1 := a.end
	var b1 := b.end
	return a.position.x < b1.x - eps and b.position.x < a1.x - eps \
		and a.position.y < b1.y - eps and b.position.y < a1.y - eps \
		and a.position.z < b1.z - eps and b.position.z < a1.z - eps


## the region a box sweeps BEYOND itself moving s (+1 / -1) along axis index k by d (d < 0 = to infinity)
static func slab(b: AABB, k: int, s: float, d: float) -> AABB:
	var pos := b.position
	var sz := b.size
	var reach := reach_world if d < 0.0 else d
	if s > 0.0:
		pos[k] = b.position[k] + b.size[k]
	else:
		pos[k] = b.position[k] - reach
	sz[k] = reach
	return AABB(pos, sz)


static func shifted(b: AABB, k: int, s: float, d: float) -> AABB:
	var pos := b.position
	pos[k] += s * d
	return AABB(pos, b.size)


## LAYERS BY LEVEL: bodies whose extents along the axis coincide (overlap >= share of the shorter one) move together (four screws at one height, one layer).
## Returns [[body index, ...], ...] ordered by first body.
static func level_layers(boxes: Array, axis: Vector3, share := 0.8) -> Array:
	var k := _k(axis)
	var n := boxes.size()
	var par: Array = []
	for i in n:
		par.append(i)
	var find := func(x: int) -> int:
		while int(par[x]) != x:
			par[x] = par[int(par[x])]
			x = int(par[x])
		return x
	for i in n:
		for j in range(i + 1, n):
			var a: AABB = boxes[i]
			var b: AABB = boxes[j]
			var lo := maxf(a.position[k], b.position[k])
			var hi := minf(a.position[k] + a.size[k], b.position[k] + b.size[k])
			var sh := minf(a.size[k], b.size[k])
			if hi - lo >= share * sh - EPS and sh > EPS and absf(a.size[k] - b.size[k]) <= (1.0 - share) * maxf(a.size[k], b.size[k]) + EPS:
				par[int(find.call(i))] = int(find.call(j))
	var groups := {}
	var order: Array = []
	for i in n:
		var r := int(find.call(i))
		if not groups.has(r):
			groups[r] = []
			order.append(r)
		(groups[r] as Array).append(i)
	var out: Array = []
	for r in order:
		out.append(groups[r])
	return out


## one layer per body
static func body_layers(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append([i])
	return out


static func _free(ub: Array, u: int, k: int, s: float, in_place: Array) -> bool:
	var sl := slab(ub[u], k, s, -1.0)
	for o in in_place:
		if int(o) != u and overlaps(sl, ub[int(o)]):
			return false
	return true


static func _protrusion(ub: Array, u: int, k: int, s: float, in_place: Array) -> float:
	var b: AABB = ub[u]
	var lead_u: float = (b.position[k] + b.size[k]) * s if s > 0.0 else -b.position[k]
	var best := -INF
	for o in in_place:
		if int(o) == u or not overlaps(b, ub[int(o)]):
			continue
		var c: AABB = ub[int(o)]
		var lead_c: float = (c.position[k] + c.size[k]) * s if s > 0.0 else -c.position[k]
		best = maxf(best, lead_c)
	return 0.0 if best == -INF else lead_u - best


## The plan. boxes: world AABB per body; layers: [[body idx...]] (default one per body); axis: unit axis; gap: world units (metres) between layers at the end.
## opts: one_way (only +axis), anchor (layer index or -1 for the biggest, -2 for none).
## Returns {ok, units, ubox, order (layer indexes, first out first), sign, dist, anchor, stuck, report}
static func plan(boxes: Array, layers: Array, axis: Vector3, gap: float, opts := {}) -> Dictionary:
	if boxes.size() < 2:
		return {"ok": false, "why": "an exploded view needs at least two bodies"}
	if layers.is_empty():
		layers = body_layers(boxes.size())
	var k := _k(axis)
	var nu := layers.size()
	var ub: Array = []
	for l in layers:
		ub.append(union_box(boxes, l))
	var anchor := int(opts.get("anchor", -1))
	if anchor == -1:
		var best := -1.0
		for u in nu:
			var vol := 0.0   # the bodies' own volume (a layer's union box would make four thin screws the biggest thing)
			for bi in layers[u]:
				vol += (boxes[int(bi)] as AABB).get_volume()
			if vol > best + EPS:
				best = vol
				anchor = u
	var whole := union_box(ub, range(nu))
	reach_world = maxf(whole.size.length() * 3.0 + gap * 4.0, 1e-3)
	var all_c := whole.get_center()[k]
	var in_place: Array = range(nu)
	var order: Array = []
	var sgn: Array = []
	sgn.resize(nu)
	sgn.fill(1.0)
	var remaining: Array = []
	for u in nu:
		if u != anchor:
			remaining.append(u)
	var stuck: Array = []
	var one_way := bool(opts.get("one_way", false))
	while not remaining.is_empty():
		var pick := -1
		var pick_s := 1.0
		for u in remaining:
			var free_s: Array = []
			for s in ([1.0] if one_way else [1.0, -1.0]):
				if _free(ub, int(u), k, s, in_place):
					free_s.append(s)
			if free_s.is_empty():
				continue
			pick = int(u)
			if free_s.size() == 1:
				pick_s = free_s[0]
			else:
				var pp := _protrusion(ub, pick, k, 1.0, in_place)
				var pm := _protrusion(ub, pick, k, -1.0, in_place)
				if absf(pp - pm) > EPS:
					pick_s = 1.0 if pp > pm else -1.0
				else:
					pick_s = -1.0 if (ub[pick] as AABB).get_center()[k] < all_c - EPS else 1.0
			break
		if pick < 0:   # a deadlock: the rest go in the given order, flagged
			for u in remaining:
				stuck.append(u)
				order.append(u)
				sgn[u] = 1.0
			break
		order.append(pick)
		sgn[pick] = pick_s
		remaining.erase(pick)
		in_place.erase(pick)
	# distances: last leaver first
	var dist: Array = []
	dist.resize(nu)
	dist.fill(0.0)
	var env: Array = []   # [layer, hull AABB of rest + final]
	if anchor >= 0:
		env.append([anchor, ub[anchor]])
	var later: Array = []   # layers that leave after the one being placed (in place at its departure)
	if anchor >= 0:
		later.append(anchor)
	var step := gap * 0.25
	for oi in range(order.size() - 1, -1, -1):
		var u: int = order[oi]
		var s: float = sgn[u]
		var found := -1.0
		for kk in range(4, 4 + 800):
			var d: float = step * kk
			var sl := slab(ub[u], k, s, d)
			var ok := true
			for l in later:
				if overlaps(sl, ub[int(l)]):
					ok = false
					break
			if not ok:
				continue
			var fin: AABB = shifted(ub[u], k, s, d)
			var pp: Vector3 = fin.position
			var ps: Vector3 = fin.size
			pp[k] -= gap
			ps[k] += 2.0 * gap
			var padded := AABB(pp, ps)
			for e in env:
				if overlaps(padded, e[1]):
					ok = false
					break
			if ok:
				found = d
				break
		if found < 0.0:
			found = gap
			if not stuck.has(u):
				stuck.append(u)
		dist[u] = found
		env.append([u, ub[u].merge(shifted(ub[u], k, s, found))])
		later.append(u)
	var names := []
	return {"ok": true, "units": layers, "ubox": ub, "order": order, "sign": sgn, "dist": dist, "anchor": anchor, "stuck": stuck, "axis": axis, "k": k, "gap": gap}


## The schedule. Out: layer order[j] moves 0 -> dist over dur seconds (smoothstep), starting no sooner than j * stagger and not before it can go without touching
## a layer that is still moving. Hold, then In = the out run backwards. Returns {out_start, out_end (per layer, -1 = anchor), out_total, in_start, in_end, total, hold}.
static func schedule(p: Dictionary, dur := 1.0, stagger := 0.4, hold := 0.5) -> Dictionary:
	var order: Array = p["order"]
	var nu: int = (p["units"] as Array).size()
	var st: Array = []
	st.resize(nu)
	st.fill(-1.0)
	var en: Array = []
	en.resize(nu)
	en.fill(-1.0)
	var last_start := -stagger
	for j in order.size():
		var u: int = order[j]
		var t0 := float(j) * stagger   # s262b: its own slot, not after the previous start: one blocked layer must not hold every later one back
		var tries := 0
		while tries < 400:
			st[u] = t0
			en[u] = t0 + dur
			if _motion_clear(p, st, en, u):
				break
			t0 += dur / 20.0
			tries += 1
		if tries >= 400:   # s262b: no clear window by sliding: go after every layer that has started (nothing else moves then)
			var after := 0.0
			for q in nu:
				if q != u and float(st[q]) >= 0.0:
					after = maxf(after, float(en[q]))
			st[u] = after + 1e-3
			en[u] = st[u] + dur
		last_start = st[u]
	var out_total := 0.0
	for u in order:
		out_total = maxf(out_total, en[u])
	var in_st: Array = []
	var in_en: Array = []
	in_st.resize(nu)
	in_en.resize(nu)
	in_st.fill(-1.0)
	in_en.fill(-1.0)
	for u in order:
		in_st[u] = out_total + hold + (out_total - en[u])
		in_en[u] = out_total + hold + (out_total - st[u])
	return {"out_start": st, "out_end": en, "out_total": out_total, "in_start": in_st, "in_end": in_en, "total": out_total * 2.0 + hold, "hold": hold, "dur": dur, "stagger": stagger}


## how far layer u has travelled at time t
static func dist_at(p: Dictionary, sc: Dictionary, u: int, t: float) -> float:
	var d: float = (p["dist"] as Array)[u]
	if float((sc["out_start"] as Array)[u]) < 0.0:
		return 0.0
	var o0: float = (sc["out_start"] as Array)[u]
	var o1: float = (sc["out_end"] as Array)[u]
	var i0: float = (sc["in_start"] as Array)[u]
	var i1: float = (sc["in_end"] as Array)[u]
	if t < i0:
		return d * smooth((t - o0) / maxf(o1 - o0, 1e-9))
	return d * (1.0 - smooth((t - i0) / maxf(i1 - i0, 1e-9)))


## the current box of every layer at time t
static func boxes_at(p: Dictionary, sc: Dictionary, t: float) -> Array:
	var out: Array = []
	for u in (p["ubox"] as Array).size():
		out.append(shifted(p["ubox"][u], int(p["k"]), float((p["sign"] as Array)[u]), dist_at(p, sc, u, t)))
	return out


## offsets (world vector per layer) at t
static func offsets_at(p: Dictionary, sc: Dictionary, t: float) -> Array:
	var out: Array = []
	for u in (p["ubox"] as Array).size():
		out.append((p["axis"] as Vector3).normalized() * float((p["sign"] as Array)[u]) * dist_at(p, sc, u, t))
	return out


## every collision at time t: [{mover, hit}] = layer `mover`'s new swept region overlaps layer `hit`'s current box
static func hits_at(p: Dictionary, sc: Dictionary, t: float) -> Array:
	var k: int = p["k"]
	var cur := boxes_at(p, sc, t)
	var out: Array = []
	for i in cur.size():
		var d := dist_at(p, sc, i, t)
		if d <= EPS or not _moving_at(sc, i, t):   # s262b: a layer that is parked sweeps nothing now (its old swept region is not a collision)
			continue
		var sl := slab(p["ubox"][i], k, float((p["sign"] as Array)[i]), d)
		for j in cur.size():
			if j != i and overlaps(sl, cur[j]):
				out.append({"mover": i, "hit": j})
	return out


## is layer i in motion at t (out or in run, open interval)?
static func _moving_at(sc: Dictionary, i: int, t: float) -> bool:
	var o0 := float((sc["out_start"] as Array)[i])
	if o0 < 0.0:
		return false
	if t > o0 + 1e-9 and t < float((sc["out_end"] as Array)[i]) - 1e-9:
		return true
	return t > float((sc["in_start"] as Array)[i]) + 1e-9 and t < float((sc["in_end"] as Array)[i]) - 1e-9


static func _grown(b: AABB, k: int, pad: float) -> AABB:
	var pos := b.position
	var sz := b.size
	pos[k] -= pad
	sz[k] += 2.0 * pad
	return AABB(pos, sz)


static func _motion_clear(p: Dictionary, st: Array, en: Array, u: int) -> bool:
	# samples of u's out motion: u's new swept region against every layer's box, and every layer still moving against u's box. Only pairs that contain u
	# can clash newly here (s262b: O(layers) per sample, was O(layers^2)). Samples are 1/24 of the run apart, so every box that moves is grown by
	# the most it can travel between two samples (smoothstep peak speed 1.5 x distance / duration): a graze shorter than a sample is not missed.
	var t0: float = st[u]
	var t1: float = en[u]
	var ub: Array = p["ubox"]
	var nu := ub.size()
	var k: int = p["k"]
	var sg: Array = p["sign"]
	var dd: Array = p["dist"]
	var started: Array = []
	for i in nu:
		if i != u and float(st[i]) >= 0.0:
			started.append(i)
	var padu: float = 1.5 * float(dd[u]) / 24.0
	for si in 25:
		var t := lerpf(t0, t1, float(si) / 24.0)
		var du := dist_out(p, st, en, u, t)
		var cu: AABB = _grown(shifted(ub[u], k, float(sg[u]), du), k, padu)
		if du > EPS:
			var sl := slab(ub[u], k, float(sg[u]), du + padu)
			for j in nu:
				if j == u:
					continue
				var pj := 1.5 * float(dd[j]) / 24.0 if (float(st[j]) >= 0.0 and t < float(en[j])) else 0.0
				if overlaps(sl, _grown(shifted(ub[j], k, float(sg[j]), dist_out(p, st, en, j, t)), k, pj)):
					return false
		for i in started:
			if t >= float(en[i]) - 1e-9:
				continue
			var d := dist_out(p, st, en, i, t)
			if d > EPS and overlaps(slab(ub[i], k, float(sg[i]), d + 1.5 * float(dd[i]) / 24.0), cu):
				return false
	return true


static func dist_out(p: Dictionary, st: Array, en: Array, u: int, t: float) -> float:
	if float(st[u]) < 0.0:
		return 0.0
	return float((p["dist"] as Array)[u]) * smooth((t - float(st[u])) / maxf(float(en[u]) - float(st[u]), 1e-9))


static func boxes_at_out(p: Dictionary, st: Array, en: Array, t: float) -> Array:
	var out: Array = []
	for u in (p["ubox"] as Array).size():
		out.append(shifted(p["ubox"][u], int(p["k"]), float((p["sign"] as Array)[u]), dist_out(p, st, en, u, t)))
	return out


## The independent check of a plan + schedule: {ok, collisions: [{t, mover, hit}], samples}. Samples every key time and 16 steps between keys.
static func check(p: Dictionary, sc: Dictionary) -> Dictionary:
	var keys: Array = [0.0, float(sc["total"])]
	for u in (p["order"] as Array):
		for a in ["out_start", "out_end", "in_start", "in_end"]:
			keys.append(float((sc[a] as Array)[u]))
	keys.sort()
	var cols: Array = []
	var n := 0
	var steps := 24 if keys.size() <= 60 else 4   # s262b: a 180-layer run has ~700 key times; 5 samples between keys keep the check minutes, not hours
	for i in keys.size() - 1:
		for si in steps + 1:
			var t := lerpf(float(keys[i]), float(keys[i + 1]), float(si) / float(steps))
			n += 1
			for h in hits_at(p, sc, t):
				h["t"] = snappedf(t, 0.001)
				cols.append(h)
	return {"ok": cols.is_empty(), "collisions": cols, "samples": n}


## The control: the same signs and distances, but the layers leave in the GIVEN order (index order), one stagger apart.
static func naive_schedule(p: Dictionary, dur := 1.0, stagger := 0.4, hold := 0.5) -> Dictionary:
	var q: Dictionary = p.duplicate()
	var ord: Array = []
	for u in (p["units"] as Array).size():
		if u != int(p["anchor"]):
			ord.append(u)
	q["order"] = ord
	var nu := (p["units"] as Array).size()
	var st: Array = []
	st.resize(nu)
	st.fill(-1.0)
	var en: Array = []
	en.resize(nu)
	en.fill(-1.0)
	for j in ord.size():
		st[ord[j]] = j * stagger
		en[ord[j]] = j * stagger + dur
	var ot := 0.0
	for u in ord:
		ot = maxf(ot, en[u])
	var ins: Array = []
	var ine: Array = []
	ins.resize(nu)
	ine.resize(nu)
	ins.fill(-1.0)
	ine.fill(-1.0)
	for u in ord:
		ins[u] = ot + hold + (ot - en[u])
		ine[u] = ot + hold + (ot - st[u])
	return {"order": ord, "out_start": st, "out_end": en, "out_total": ot, "in_start": ins, "in_end": ine, "total": ot * 2.0 + hold, "hold": hold, "dur": dur, "stagger": stagger}


## the plan in words: "screws out first, then ..." with the layer names
static func words(p: Dictionary, names: Array) -> String:
	var parts: Array = []
	for u in (p["order"] as Array):
		var nm: Array = []
		for b in (p["units"] as Array)[u]:
			nm.append(String(names[int(b)]) if int(b) < names.size() else "Body%d" % (int(b) + 1))
		parts.append("%s %s" % [", ".join(nm), "up" if float((p["sign"] as Array)[u]) > 0.0 else "down"])
	var a := int(p["anchor"])
	var tail := ""
	if a >= 0:
		var nm2: Array = []
		for b in (p["units"] as Array)[a]:
			nm2.append(String(names[int(b)]) if int(b) < names.size() else "Body%d" % (int(b) + 1))
		tail = "; stays: " + ", ".join(nm2)
	return " > ".join(parts) + tail


## The key table the timeline makes: per layer [{t, d, kind}] with out and in keys. d = distance along its signed axis (world units).
static func keys(p: Dictionary, sc: Dictionary) -> Array:
	var out: Array = []
	for u in (p["units"] as Array).size():
		var ks: Array = []
		if float((sc["out_start"] as Array)[u]) >= 0.0:
			var d: float = (p["dist"] as Array)[u]
			ks = [{"t": 0.0, "d": 0.0, "kind": "rest"}, {"t": sc["out_start"][u], "d": 0.0, "kind": "out"}, {"t": sc["out_end"][u], "d": d, "kind": "out"},
				{"t": sc["in_start"][u], "d": d, "kind": "in"}, {"t": sc["in_end"][u], "d": 0.0, "kind": "in"}, {"t": sc["total"], "d": 0.0, "kind": "rest"}]
		else:
			ks = [{"t": 0.0, "d": 0.0, "kind": "rest"}, {"t": sc["total"], "d": 0.0, "kind": "rest"}]
		out.append(ks)
	return out


## CAMERA: for each time in `times`, the camera that keeps every piece in view (FrameFacts.solve on the pieces moved to that time), the live camera's aim kept.
## g: FrameFacts gather dict (names, verts, aabb in world); layer_of_body: body -> layer; share: asked width/height share (<= 0.9).
## Returns [{t, pos, target, fov, share_w, share_h}]
static func camera_frames(g: Dictionary, cam0: Dictionary, p: Dictionary, sc: Dictionary, times: Array, layer_of_body: Array, share := 0.8, rect := Rect2()) -> Array:
	var out: Array = []
	var idx: Array = range((g["names"] as Array).size())
	# s262b VISIBLE AREA: with a rect (the clear view beside the panel, in window pixels) the pieces are framed to THAT, at the live lens's pixel scale,
	# then the camera is slid sideways so the rect's centre is where the pieces' centre lands. Shares are reported against the whole window.
	var use_rect := rect.size.x > 8.0 and rect.size.y > 8.0
	var camx: Dictionary = cam0
	var W := float(cam0["w"])
	var H := float(cam0["h"])
	var fpx := FrameFacts.focal(cam0)
	var sx := 0.0
	var sy := 0.0
	if use_rect:
		camx = cam0.duplicate()
		camx["w"] = int(rect.size.x)
		camx["h"] = int(rect.size.y)
		var ratio: float = rect.size.x / W if bool(cam0.get("keep_width", false)) else rect.size.y / H
		camx["fov"] = rad_to_deg(2.0 * atan(tan(deg_to_rad(float(cam0["fov"])) * 0.5) * ratio))
		var rc := rect.get_center()
		sx = W * 0.5 - rc.x
		sy = rc.y - H * 0.5
	for t in times:
		var offs := offsets_at(p, sc, float(t))
		var verts: Array = []
		var boxes: Array = []
		for b in idx:
			var off: Vector3 = offs[int(layer_of_body[b])]
			var vs: PackedVector3Array = g["verts"][b]
			var mv := PackedVector3Array()
			mv.resize(vs.size())
			for i in vs.size():
				mv[i] = vs[i] + off
			verts.append(mv)
			var bb: AABB = g["aabb"][b]
			boxes.append(AABB(bb.position + off, bb.size))
		var g2 := {"names": g["names"], "verts": verts, "aabb": boxes}
		var r: Dictionary = FrameFacts.solve(g2, idx, camx, "w", share, "fov", "xy", {})
		if bool(r.get("ok", false)):
			var sil: Dictionary = FrameFacts.measure(g2, idx, r["cam"])["sil"]
			if (float(sil["y1"]) - float(sil["y0"])) / float(r["cam"]["h"]) > share + 0.005:
				var r2: Dictionary = FrameFacts.solve(g2, idx, camx, "h", share, "fov", "xy", {})
				if bool(r2.get("ok", false)):
					r = r2
					sil = FrameFacts.measure(g2, idx, r["cam"])["sil"]
			var pos: Vector3 = r["pos"]
			var tg: Vector3 = r["target"]
			var fov: float = r["fov"]
			if use_rect:
				var bas := FrameFacts.look(pos, tg).basis
				var k := (pos - tg).length() / maxf(fpx, 1e-6)
				var sh: Vector3 = bas.x * sx * k + bas.y * sy * k
				pos += sh
				tg += sh
				fov = float(cam0["fov"]) if absf(fov - float(camx["fov"])) < 1e-4 else fov
			out.append({"t": float(t), "pos": pos, "target": tg, "fov": fov,
				"share_w": (float(sil["x1"]) - float(sil["x0"])) / W, "share_h": (float(sil["y1"]) - float(sil["y0"])) / H})
	return out
