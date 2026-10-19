## any_grip.gd - THE GRIP FOR ANY PROP (ROADMAP 18; docs/research/ANY_GRIP.md). grip_wrap.gd closes the fingers round a
## CAPSULE (a weapon's handle). A prop can be any shape, so here the handle is a DISTANCE FIELD: field(p) is the signed
## distance from a world point p to the prop's surface (m, negative inside). A built-in prop answers it from its solids
## and spheres (props.gd _sd); an imported model, or any mesh, from a voxel grid of the distance to its triangles.
##   gap(segment) = min over the segment's axis of field(point) - the segment's radius   (> 0 apart, < 0 inside)
## Everything else is the weapon wrap's rule, unchanged: each joint closes until its segment or one beyond it touches
## (Buchholz & Armstrong 1992), the joints close in Gulke's ratio (MCP 28 : PIP 43 : DIP 26), they stop at their limits,
## and a power grasp settles every segment onto the surface. The weapon path (grip_wrap.gd) is not touched.
class_name AnyGrip
extends RefCounted

const SAMPLE := 0.004      # a finger's axis is sampled every 4 mm
const TOUCH := 0.001       # within 1 mm = touching (as grip_wrap.gd)
const STEP := 2.0          # deg per closing step; the touch is then found by halving inside the step
const HALVE := 6
const PALM_GAP := 0.005    # place_hand: the palm rests 5 mm off the surface
const GRID_MARGIN := 0.01  # the voxel grid reaches 1 cm past the mesh
const CELL_MIN := 0.004    # voxel size for a mesh field (4 mm); coarser for a big mesh (work bound below)
const WORK_MAX := 1.5e6    # voxel x triangle tests allowed in one field build
const RATIO := [28.0 / 43.0, 1.0, 26.0 / 43.0]   # Gulke 2010 MCP : PIP : DIP
const THUMB_RATIO := [18.0 / 32.0, 1.0]          # the thumb's two flexing joints (as grip_wrap.gd)


# ---------------------------------------------------------------- the prop as a distance field

## a prop's field: {"sd": Callable(world point) -> signed distance, "size": Vector3 (its bounding box), "sphere": bool}
static func field_of(p: Dictionary) -> Dictionary:
	var kd := Props.kind_of(String(p["kind"]))
	if String(kd.get("glb", "")) != "":   # an imported model: its triangles, not its box
		var root := Props.mesh(p)
		var out := field_of_node(root)
		root.free()
		return out
	var sol := Props.solids(p)
	var sd := func(q: Vector3) -> float:
		var m := INF
		for sw in sol:
			m = minf(m, Props._sd(sw, q))
		return m
	var sphere: bool = (kd["solids"] as Array).is_empty() and kd.has("spheres")
	return {"sd": sd, "size": _box_size(sol), "sphere": sphere}


## the field of any mesh subtree (a Node3D root; its transform places it in the world)
static func field_of_node(root: Node3D) -> Dictionary:
	var tris := PackedVector3Array()
	for pair in _meshes(root, root):
		var m: MeshInstance3D = pair[0]
		var t: Transform3D = pair[1]
		if m.mesh == null:
			continue
		var faces: PackedVector3Array = m.mesh.create_trimesh_shape().get_faces()
		for v in faces:
			tris.append(root.transform * (t * v))
	var f := MeshField.build(tris)
	return {"sd": Callable(f, "sd"), "size": f.size, "sphere": f.sphere, "field": f}   # "field" keeps the object alive (a Callable does not)


static func _meshes(n: Node, root: Node3D) -> Array:
	var out := []
	if n is MeshInstance3D:
		out.append([n, _rel(root, n as Node3D)])
	for c in n.get_children():
		out.append_array(_meshes(c, root))
	return out


## a node's transform relative to root (root's own transform left out)
static func _rel(root: Node3D, n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var c: Node = n
	while c != null and c != root:
		t = (c as Node3D).transform * t
		c = c.get_parent()
	return t


static func _box_size(sol: Array) -> Vector3:
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := -lo
	for sw in sol:
		var xf: Transform3D = sw["xf"]
		var hf: Vector3 = sw["half"]
		for k in 8:
			var c := Vector3(hf.x if (k & 1) else -hf.x, hf.y if (k & 2) else -hf.y, hf.z if (k & 4) else -hf.z)
			var w := xf * c
			lo = lo.min(w)
			hi = hi.max(w)
	return hi - lo


## the grasp shape of a prop (Feix et al. 2016, GRASP taxonomy, by the object's form; docs/research/ANY_GRIP.md):
##   "sphere"    a ball: the spherical grasp, every finger round it, the thumb opposing (a power grasp)
##   "cylinder"  one long side and a round section: the power cylinder grasp (fingers wrap, thumb over them)
##   "plate"     thin in one direction (under 2.5 cm): a precision grasp, fingertips only, no settling
##   "block"     anything else (a box, a crate): a power grasp, the palm and fingers on its sides
static func shape_of(size: Vector3, sphere: bool) -> String:
	if sphere:
		return "sphere"
	var s := [size.x, size.y, size.z]
	s.sort()
	s.reverse()
	if s[0] >= 1.6 * s[1] and s[1] >= 0.85 * s[2]:
		return "cylinder"
	if s[2] < 0.025:
		return "plate"
	return "block"


# ---------------------------------------------------------------- the closure

## the gap of one segment of the hand from the prop: the nearest point of its axis to the surface, less its radius
static func gap(B: Body, F: Callable, j: String) -> float:
	var c: Array = B.cap(j)
	var a: Vector3 = c[0]
	var b: Vector3 = c[1]
	var n := maxi(1, ceili(a.distance_to(b) / SAMPLE))
	var m := INF
	for i in n + 1:
		m = minf(m, float(F.call(a.lerp(b, float(i) / n))))
	return m - float(B.rad[j])


static func _gap_from(B: Body, F: Callable, chain: Array, k: int) -> float:
	var g := INF
	for i in range(k, chain.size()):
		g = minf(g, gap(B, F, chain[i]))
	return g


## close one finger (chain = its joints, knuckle first) round the prop. Rows per joint: [bend, gap, how] where how is
## "touch" (its segment or one beyond held it), "limit", or "inside" (already in the prop with the finger straight)
static func close(B: Body, chain: Array, F: Callable, settle := true) -> Array:
	for j in chain:
		var v: Vector3 = B.ang[j]
		B.ang[j] = B.clamp_ang(j, Vector3(0.0, v.y, v.z))
	B.fk_some(chain)
	var n := chain.size()
	var state := []
	for k in n:
		state.append("")
	for k in n:
		if gap(B, F, chain[k]) <= TOUCH:
			for q in k + 1:
				if state[q] == "":
					state[q] = "inside"
	var guard := 0
	while state.has("") and guard < 400:
		guard += 1
		var keep := {}
		for k in n:
			keep[chain[k]] = B.ang[chain[k]]
		var moved := false
		for k in n:
			if state[k] != "":
				continue
			var j: String = chain[k]
			var v: Vector3 = B.ang[j]
			var hi: float = (B.lim[j]["bend"] as Vector2).y
			var nv := minf(v.x + STEP * float(RATIO[k]), hi)
			if nv <= v.x + 1e-6:
				state[k] = "limit"
				continue
			B.ang[j] = B.clamp_ang(j, Vector3(nv, v.y, v.z))
			moved = true
		if not moved:
			break
		B.fk_some(chain)
		var first := -1
		for k in n:
			if gap(B, F, chain[k]) <= TOUCH:
				first = k
				break
		if first < 0:
			continue
		# a segment reached the surface inside this step: halve the step back to the touch, then hold it
		var after := {}
		for k in n:
			after[chain[k]] = B.ang[chain[k]]
		var lo := 0.0
		var up := 1.0
		for it in HALVE:
			var mid := (lo + up) * 0.5
			for k in n:
				var j: String = chain[k]
				var a0: Vector3 = keep[j]
				var a1: Vector3 = after[j]
				B.ang[j] = a0.lerp(a1, mid)
			B.fk_some(chain)
			if _gap_from(B, F, chain, 0) <= TOUCH:
				up = mid
			else:
				lo = mid
		for k in n:
			var j: String = chain[k]
			var a0: Vector3 = keep[j]
			var a1: Vector3 = after[j]
			B.ang[j] = a0.lerp(a1, up)
		B.fk_some(chain)
		for k in n:
			if gap(B, F, chain[k]) <= TOUCH:
				for q in k + 1:
					if state[q] == "":
						state[q] = "touch"
	if settle:
		_settle(B, chain, F)
	var out := []
	for k in n:
		var g := gap(B, F, chain[k])
		var how: String = "touch" if g <= TOUCH + 0.002 else (String(state[k]) if state[k] not in ["", "touch"] else "limit")
		out.append([(B.ang[chain[k]] as Vector3).x, g, how])
	return out


## SETTLE (power grasps): every segment is drawn onto the surface together, least squares on the gaps (a segment inside
## the prop costs 25 times one off it). Coordinate descent on the bends, 8 -> 1 deg.
static func _settle(B: Body, chain: Array, F: Callable) -> void:
	var cost := func() -> float:
		var c := 0.0
		for j in chain:
			var g := gap(B, F, j)
			c += g * g if g > 0.0 else 25.0 * g * g
		return c
	var best: float = cost.call()
	for stp in [8.0, 4.0, 2.0, 1.0]:
		var moved := true
		var rounds := 0
		while moved and rounds < 6:
			moved = false
			rounds += 1
			for k in chain.size():
				var j: String = chain[k]
				for sg in [-1.0, 1.0]:
					var v: Vector3 = B.ang[j]
					var nv := B.clamp_ang(j, v + Vector3(sg * stp, 0, 0))
					if nv == v:
						continue
					B.ang[j] = nv
					B.fk_some(chain.slice(k))
					var c: float = cost.call()
					if c < best - 1e-9:
						best = c
						moved = true
					else:
						B.ang[j] = v
						B.fk_some(chain.slice(k))


## the thumb: its base (thumb_01: the abduction across the palm) is searched over a small grid, and from each base the
## thumb's two flexing joints close (THUMB_RATIO) until a thumb segment meets the prop. The base kept is the one whose
## tip ends on the surface with nothing inside (the thumb opposes on the side the palm does not face). Rows as close().
static func close_thumb(B: Body, th: Array, F: Callable) -> Array:
	var base := "thumb_01" + String(th[0]).right(2)
	var ch := [base, th[0], th[1]]
	var best_score := INF
	var best := []
	var best_rows := []
	for ax in [-20.0, 0.0, 20.0, 40.0, 60.0]:
		for ay in [-60.0, -30.0, 0.0, 30.0, 60.0]:
			for az in [-60.0, -30.0, 0.0, 30.0, 60.0]:
				B.ang[base] = B.clamp_ang(base, Vector3(ax, ay, az))
				B.fk_some(ch)
				var rows := _close_thumb_at(B, th, F)
				var inside := false
				for r in rows:
					if float(r[1]) < -0.001:
						inside = true
				var score := absf(float(rows[1][1])) + (0.05 if inside else 0.0)
				if score < best_score:
					best_score = score
					best = [B.ang[base], B.ang[th[0]], B.ang[th[1]]]
					best_rows = rows
	B.ang[base] = best[0]
	B.ang[th[0]] = best[1]
	B.ang[th[1]] = best[2]
	B.fk_some(ch)
	return best_rows


## the thumb's two flexing joints from straight, closing until a segment meets the prop (no base search)
static func _close_thumb_at(B: Body, th: Array, F: Callable) -> Array:
	for j in th:
		var v: Vector3 = B.ang[j]
		B.ang[j] = B.clamp_ang(j, Vector3(0.0, v.y, v.z))
	B.fk_some(th)
	var how := "limit"
	for it in 60:
		var moved := false
		var keep := [B.ang[th[0]], B.ang[th[1]]]
		for k in 2:
			var v: Vector3 = B.ang[th[k]]
			var hi: float = (B.lim[th[k]]["bend"] as Vector2).y
			var nv := minf(v.x + STEP * float(THUMB_RATIO[k]), hi)
			if nv > v.x + 1e-6:
				B.ang[th[k]] = B.clamp_ang(th[k], Vector3(nv, v.y, v.z))
				moved = true
		if not moved:
			break
		B.fk_some(th)
		if _gap_from(B, F, th, 0) <= TOUCH:   # whichever thumb segment meets the prop first holds it
			var after := [B.ang[th[0]], B.ang[th[1]]]
			var lo := 0.0
			var up := 1.0
			for q in HALVE:
				var mid := (lo + up) * 0.5
				for k in 2:
					var a0: Vector3 = keep[k]
					var a1: Vector3 = after[k]
					B.ang[th[k]] = a0.lerp(a1, mid)
				B.fk_some(th)
				if _gap_from(B, F, th, 0) <= TOUCH:
					up = mid
				else:
					lo = mid
			for k in 2:
				var a0: Vector3 = keep[k]
				var a1: Vector3 = after[k]
				B.ang[th[k]] = a0.lerp(a1, up)
			B.fk_some(th)
			how = "touch"
			break
	var out := []
	for j in th:
		out.append([(B.ang[j] as Vector3).x, gap(B, F, j), how])
	return out


## THE WRAP OF ANY PROP: the fingers of hand h (hand_r / hand_l) closed round the prop's field F, and the thumb
## opposing. Returns {"pattern": shape, finger: rows (close), "thumb": rows (close_thumb)}.
static func wrap(B: Body, h: String, F: Dictionary, shape := "") -> Dictionary:
	var sd := h.right(2)
	var fn: Callable = F["sd"]
	if shape == "":
		shape = shape_of(F["size"], bool(F["sphere"]))
	var rep := {"pattern": shape}
	for f in GripWrap.LONG:
		rep[f] = close(B, [f + "_01" + sd, f + "_02" + sd, f + "_03" + sd], fn, shape != "plate")
	rep["thumb"] = close_thumb(B, ["thumb_02" + sd, "thumb_03" + sd], fn)
	return rep


## the command: wrap the hand round the prop, then key every finger and thumb joint at time t (PartKeys, one undo step
## is the caller's). Returns the wrap's report.
static func grip_prop(B: Body, h: String, F: Dictionary, pk: Dictionary, t: float) -> Dictionary:
	var rep: Dictionary = wrap(B, h, F)
	key_hand(B, h, pk, t)
	return rep


## key the hand's 15 finger and thumb joints at time t (PartKeys.put: a key already there is replaced)
static func key_hand(B: Body, h: String, pk: Dictionary, t: float) -> void:
	var sd := h.right(2)
	for f in GripWrap.LONG:
		for k in 3:
			var j := "%s_0%d%s" % [f, k + 1, sd]
			PartKeys.put(pk, j, t, B.ang[j])
	for k in 3:
		var j := "thumb_0%d%s" % [k + 1, sd]
		PartKeys.put(pk, j, t, B.ang[j])


# ---------------------------------------------------------------- placing the hand at a prop (for tests and a start)

## open the hand's fingers and thumb (flexion 0), the rest pose the wrap starts from
static func _open(B: Body, h: String) -> void:
	var sd := h.right(2)
	var js := []
	for f in GripWrap.LONG:
		for k in 3:
			js.append("%s_0%d%s" % [f, k + 1, sd])
	for k in 3:
		js.append("thumb_0%d%s" % [k + 1, sd])
	for j in js:
		var v: Vector3 = B.ang[j]
		B.ang[j] = B.clamp_ang(j, Vector3(0.0, v.y, v.z))
	B.fk()


## the outward unit normal of the field at p (central differences)
static func _grad(F: Callable, p: Vector3) -> Vector3:
	var e := 1e-3
	var g := Vector3(float(F.call(p + Vector3(e, 0, 0))) - float(F.call(p - Vector3(e, 0, 0))),
		float(F.call(p + Vector3(0, e, 0))) - float(F.call(p - Vector3(0, e, 0))),
		float(F.call(p + Vector3(0, 0, e))) - float(F.call(p - Vector3(0, 0, e))))
	return g.normalized() if g.length() > 1e-9 else Vector3.UP


## the surface point nearest to p (Newton steps along the field)
static func _nearest(F: Callable, p: Vector3) -> Vector3:
	var q := p
	for i in 40:
		var d := float(F.call(q))
		if absf(d) < 1e-5:
			break
		q -= _grad(F, q) * d
	return q


## ORIENT the hand for a prop whose surface faces it along dn (the curl direction, into the prop): the flexion axis
## up (or forward when dn is vertical), the fingers tangent to the surface (f = d x a). The curl is measured on the
## rig (the knuckle bent 10 deg, the fingertip's motion), so the joint frames need not be known.
static func _orient(B: Body, h: String, dn: Vector3) -> void:
	var sd := h.right(2)
	var aw := Vector3.UP
	if absf(dn.dot(aw)) > 0.7:
		aw = Vector3.FORWARD
	aw = (aw - dn * aw.dot(dn)).normalized()
	var fw := dn.cross(aw).normalized()   # d = a x f  =>  f = d x a
	_open(B, h)
	var idx := "index_01" + sd
	var f0: Vector3 = ((B.E["index_03" + sd] as Vector3) - (B.P[idx] as Vector3)).normalized()
	var tip0: Vector3 = B.E["index_03" + sd]
	var v_keep: Vector3 = B.ang[idx]
	B.ang[idx] = Vector3(v_keep.x + 10.0, v_keep.y, v_keep.z)
	B.fk()
	var c0: Vector3 = ((B.E["index_03" + sd] as Vector3) - tip0).normalized()
	B.ang[idx] = v_keep
	B.fk()
	var a0: Vector3 = f0.cross(c0).normalized()   # a x f = curl, so a = f x curl (f and curl are at right angles)
	var q1 := Quaternion(f0, fw)
	var a1: Vector3 = q1 * a0
	var u := (a1 - fw * a1.dot(fw)).normalized()
	var v := (aw - fw * aw.dot(fw)).normalized()
	var roll := atan2(fw.dot(u.cross(v)), u.dot(v))
	var R := (Quaternion(fw, roll) * q1).normalized()
	B.turn_world(h, R)
	B.fk()


## the direction the fingers curl toward at the hand's rest pose (the index knuckle bent 10 deg, the tip's motion, unit):
## the side the palm faces. A prop placed on that side needs the least turn of the wrist (the arm's reach is wrist-limited)
static func curl_dir(B: Body, h: String) -> Vector3:
	var sd := h.right(2)
	_open(B, h)
	var idx := "index_01" + sd
	var tip0: Vector3 = B.E["index_03" + sd]
	var v_keep: Vector3 = B.ang[idx]
	B.ang[idx] = Vector3(v_keep.x + 10.0, v_keep.y, v_keep.z)
	B.fk()
	var c := ((B.E["index_03" + sd] as Vector3) - tip0).normalized()
	B.ang[idx] = v_keep
	B.fk()
	return c


## how far the most-inside open finger segment is (negative = inside; the fingers opened first)
static func _open_clearance(B: Body, h: String, F: Callable) -> float:
	var sd := h.right(2)
	_open(B, h)
	var worst := INF
	for f in GripWrap.LONG:
		for k in 3:
			worst = minf(worst, gap(B, F, "%s_0%d%s" % [f, k + 1, sd]))
	return worst


## PLACE the hand at the prop: the palm faces the nearest surface point, PALM_GAP off it, and the fingers start OUTSIDE
## the prop (a finger that starts inside is held there by the closure, so the palm backs off until none does). The
## wrist is moved by the arm's own IK (Body.fit_hand), which also turns the hand, so the orientation is redone each
## pass. Returns {"wrist_m": how far the wrist is from where the arm wanted it, "palm_m": the palm's signed distance
## from the surface, "clear_m": how far the palm backed off to free the fingers, "passes": placement passes}.
static func place_hand(B: Body, h: String, F: Dictionary) -> Dictionary:
	var fn: Callable = F["sd"]
	var clear := 0.0
	var miss := 0.0
	var passes := 0
	for pass_i in 5:
		passes += 1
		var q := _nearest(fn, B.palm_point(h))
		var n := _grad(fn, q)
		_orient(B, h, -n)
		var want := q + n * (PALM_GAP + clear)
		miss = B.fit_hand(h, (B.P[h] as Vector3) + (want - B.palm_point(h)), B.G[h])
		var worst := _open_clearance(B, h, fn)
		if worst >= 0.0:
			break
		clear += -worst + 0.002
	return {"wrist_m": miss, "palm_m": float(fn.call(B.palm_point(h))), "clear_m": clear, "passes": passes}


# ---------------------------------------------------------------- the mesh field

## a signed distance field on a voxel grid, built from triangles (world space): trilinear inside the grid, a bound
## (distance to the grid + 1 cm) outside it. Sign from the nearest triangle's normal, the normals oriented by the
## mesh's signed volume (a closed mesh; open meshes come out with the sign of the nearest face)
class MeshField:
	var gmin := Vector3.ZERO
	var gmax := Vector3.ZERO
	var h := 0.004
	var nx := 2
	var ny := 2
	var nz := 2
	var d := PackedFloat32Array()
	var size := Vector3.ZERO
	var sphere := false

	static func build(tris: PackedVector3Array) -> MeshField:
		var f := MeshField.new()
		var ntri := tris.size() / 3
		if ntri == 0:
			return f
		var lo := tris[0]
		var hi := tris[0]
		for p in tris:
			lo = lo.min(p)
			hi = hi.max(p)
		f.size = hi - lo
		var ext := maxf(f.size.x, maxf(f.size.y, f.size.z))
		var cell := maxf(AnyGrip.CELL_MIN, ext / 40.0)
		var span := f.size + Vector3.ONE * 2.0 * AnyGrip.GRID_MARGIN
		while true:
			var cnt := (ceilf(span.x / cell) + 1) * (ceilf(span.y / cell) + 1) * (ceilf(span.z / cell) + 1)
			if cnt * ntri <= AnyGrip.WORK_MAX:
				break
			cell *= 1.25
		f.h = cell
		f.gmin = lo - Vector3.ONE * AnyGrip.GRID_MARGIN
		f.nx = int(ceilf(span.x / cell)) + 2
		f.ny = int(ceilf(span.y / cell)) + 2
		f.nz = int(ceilf(span.z / cell)) + 2
		f.gmax = f.gmin + Vector3(f.nx - 1, f.ny - 1, f.nz - 1) * cell
		# sphere-like: the vertices all about the same distance from their centre
		var cen := Vector3.ZERO
		for p in tris:
			cen += p
		cen /= float(tris.size())
		var rs := []
		for p in tris:
			rs.append((p - cen).length())
		var mean := 0.0
		for r in rs:
			mean += r
		mean /= float(rs.size())
		var sd := 0.0
		for r in rs:
			sd += (r - mean) * (r - mean)
		sd = sqrt(sd / float(rs.size()))
		f.sphere = mean > 0.0 and sd / mean < 0.03
		# per triangle: vertices, bounding sphere, outward normal
		var A := PackedVector3Array()
		var Bv := PackedVector3Array()
		var C := PackedVector3Array()
		var cc := PackedVector3Array()
		var rr := PackedFloat32Array()
		var nn := PackedVector3Array()
		var vol := 0.0
		for t in ntri:
			var a := tris[3 * t]
			var b := tris[3 * t + 1]
			var c := tris[3 * t + 2]
			A.append(a)
			Bv.append(b)
			C.append(c)
			vol += a.dot(b.cross(c))
		var flip := -1.0 if vol < 0.0 else 1.0
		for t in ntri:
			var a := A[t]
			var b := Bv[t]
			var c := C[t]
			var ctr := (a + b + c) / 3.0
			cc.append(ctr)
			rr.append(maxf((a - ctr).length(), maxf((b - ctr).length(), (c - ctr).length())))
			var nrm := (b - a).cross(c - a)
			nn.append(nrm.normalized() * flip if nrm.length() > 1e-12 else Vector3.UP)
		f.d.resize(f.nx * f.ny * f.nz)
		for k in f.nz:
			for j in f.ny:
				for i in f.nx:
					var p := f.gmin + Vector3(i, j, k) * cell
					var best := INF
					var sgn := 1.0
					for t in ntri:
						if (p - cc[t]).length() - rr[t] > best:
							continue
						var q := closest(p, A[t], Bv[t], C[t])
						var dd := (p - q).length()
						if dd < best:
							best = dd
							sgn = 1.0 if (p - q).dot(nn[t]) >= 0.0 else -1.0
					f.d[i + f.nx * (j + f.ny * k)] = float(best * sgn)
		return f

	## the point of triangle abc nearest p (Ericson, Real-Time Collision Detection 5.1.5)
	static func closest(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
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
		var denom := 1.0 / (va + vb + vc)
		return a + ab * (vb * denom) + ac * (vc * denom)

	## the signed distance at world point q (trilinear on the grid; a bound outside it)
	func sd(q: Vector3) -> float:
		if d.is_empty():
			return INF
		var cl := q.clamp(gmin, gmax)
		if cl != q:
			return (q - cl).length() + AnyGrip.GRID_MARGIN
		var g := (q - gmin) / h
		var ix := mini(int(floorf(g.x)), nx - 2)
		var iy := mini(int(floorf(g.y)), ny - 2)
		var iz := mini(int(floorf(g.z)), nz - 2)
		var tx := g.x - ix
		var ty := g.y - iy
		var tz := g.z - iz
		var s := 0.0
		for dz in 2:
			for dy in 2:
				for dx in 2:
					var w := (tx if dx == 1 else 1.0 - tx) * (ty if dy == 1 else 1.0 - ty) * (tz if dz == 1 else 1.0 - tz)
					s += w * d[(ix + dx) + nx * ((iy + dy) + ny * (iz + dz))]
		return s


