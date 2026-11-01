extends RefCounted
## OFFSET the whole solid (Friday plan 18, "Make it thinner / thicker everywhere"). A record step {"t": "offset", "id", "name", "mm": d}.
## EVERY face of EVERY body moves along its normal by d mm: d > 0 thicker (a box 40 x 20 x 10 becomes 42 x 22 x 12, a hole 10 mm wide
## becomes 8 mm wide, a wall 2 mm thick becomes 4 mm thick), d < 0 thinner. The kernel (KineCAD) has no solid-offset call and cannot be
## rebuilt by a worker, so this is made from the one offset it does have, the one inside shell():
##   thinner  = body minus its hollow shell of wall |d| (the shell with no open face is body minus the inward offset body, so the rest is it);
##              a solid the shell refuses (one with a hole in it) is cut down to what 26 shifted copies of it share instead (_erode);
##   thicker  = the body fused with 26 copies of itself moved d along the 26 directions of a 3 x 3 x 3 grid (see _swell).
## With KineCAD 5 (KCad.has_offset()) the kernel's own offset does it exactly; the 26-copy path stays as the fallback for an older DLL.
## The step re-runs with the record, so the Pull it up slider of an earlier step still edits the result (the offset is replayed after it).
## A distance the kernel cannot do (a wall thinner than 2 x |d|, a feature that would vanish) leaves the body as it was and returns the reason.
const KCad := preload("res://scripts/kcad.gd")
const MM := 0.001
static var force_fallback := false   # s155b: tests/timing switch, true = always the 26-copy path


## the step's effect on `bodies` (kernel ids, replaced in place); "" = done, else the sentence for the error list
static func apply(bodies: Array, f: Dictionary) -> String:
	var d := float(f.get("mm", 0.0)) * MM
	if absf(d) < 1e-9:
		return ""
	if bodies.is_empty():
		return "there is nothing to make thinner or thicker"
	var out: Array = []
	for b in bodies:
		var r := grow(int(b), d)
		if r == 0:
			for o in out:
				KCad.release(int(o))
			return "that is too much: the shape would vanish or break. Try a smaller number"
		out.append(r)
	for i in bodies.size():
		KCad.release(int(bodies[i]))
		bodies[i] = out[i]
	return ""


## a new solid: `id` moved out (d > 0) or in (d < 0) on every face, d in metres. 0 when the kernel refuses; `id` stays valid
static func grow(id: int, d: float) -> int:
	if not force_fallback and KCad.has_offset():   # s155b: KineCAD 5 moves every face exactly (BRepOffsetAPI_MakeOffsetShape)
		var k := KCad.offset(id, d)
		if k != 0:
			return k
		# the kernel refused (a wall thinner than 2 x |d|, ...): the 26-copy path below may still manage a rough answer, or refuses too
	if d < 0.0:
		return _shrink(id, -d)
	return _swell(id, d)


static func _shrink(id: int, d: float) -> int:
	var vol := KCad.volume(id)
	var h := KCad.shell(id, d, Vector3.ZERO)
	if h != 0:
		var inner := KCad.cut(id, h)
		KCad.release(h)
		if inner != 0:
			var v := KCad.volume(inner)
			if v > 1e-15 and v < vol - 1e-15:
				return inner
			KCad.release(inner)
	return _erode(id, d)   # the kernel's shell refuses a solid with a hole in it (or a rounded one): the same 26 moves, intersected


## thinner by copies: the body cut down to what all 26 shifted copies of it share (the mirror image of _swell). A wall d thick or less
## vanishes, which the volume check below reports as a refusal
static func _erode(id: int, d: float) -> int:
	var cur := KCad.translate(id, Vector3.ZERO)
	if cur == 0:
		return 0
	var vol := KCad.volume(id)
	for dir in _dirs(d):
		var mv := KCad.translate(id, dir)
		if mv == 0:
			KCad.release(cur)
			return 0
		var u := KCad.intersect(cur, mv)
		KCad.release(mv)
		KCad.release(cur)
		if u == 0:
			return 0
		cur = u
	var v := KCad.volume(cur)
	if v <= 1e-15 or v >= vol - 1e-15:
		KCad.release(cur)
		return 0
	return cur


## the 26 moves of length d (6 face, 12 edge, 8 corner directions of a 3 x 3 x 3 grid)
static func _dirs(d: float) -> Array:
	var out: Array = []
	for ix in [-1, 0, 1]:
		for iy in [-1, 0, 1]:
			for iz in [-1, 0, 1]:
				if ix != 0 or iy != 0 or iz != 0:
					out.append(Vector3(ix, iy, iz).normalized() * d)
	return out


## thicker: the body fused with 26 copies of itself, each moved by d along one of the 26 directions of a 3 x 3 x 3 grid (6 faces, 12 edges,
## 8 corners; every move is d long). That is the body grown by a ball of radius d, to within a few hundredths of a mm on flat and round walls:
## a hole shrinks by d on every side, a box face moves out by exactly d. (The kernel's own offset cannot grow a solid: its shell call refuses
## a solid that has an inner void, so the "offset the empty space inward" way fails; tested.)
static func _swell(id: int, d: float) -> int:
	var cur := KCad.translate(id, Vector3.ZERO)   # a copy, so `id` stays untouched and every step below may release its input
	if cur == 0:
		return 0
	for dir in _dirs(d):
		var mv := KCad.translate(id, dir)
		if mv == 0:
			KCad.release(cur)
			return 0
		var u := KCad.union(cur, mv)
		KCad.release(mv)
		KCad.release(cur)
		if u == 0:
			return 0
		cur = u
	if KCad.volume(cur) <= KCad.volume(id) + 1e-15:
		KCad.release(cur)
		return 0
	return cur


static func _box_at(lo: Vector3, sz: Vector3) -> int:
	var b := KCad.box(sz.x, sz.y, sz.z)
	if b == 0:
		return 0
	var at := KCad.edges(b)
	var mn := Vector3(INF, INF, INF)
	for e in at:
		for k in ["center", "a", "b"]:
			mn = mn.min(e[k])
	var m := KCad.translate(b, lo - mn)
	KCad.release(b)
	return m
