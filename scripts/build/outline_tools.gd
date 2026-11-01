class_name OutlineTools
extends RefCounted
## FRIDAY 43 + 166, one 2D outline module (no external library, no GPL code):
##  - trace_image: a picture -> the closed outlines of its dark shape (threshold, boundary walk, Douglas-Peucker), in mm
##  - rasterize / outer_contour: a set of triangles seen from one side -> a mask -> the outline of the silhouette
##  - descriptor / distance: a closed outline -> a scale, rotation, start-point and mirror free number list (the Fourier
##    descriptor of its centre-distance signature), and the difference between two of them
## All sizes are in the unit the caller gives; the picture's y runs DOWN (as pixels) unless a function says otherwise.

const MAX_SIDE := 512      # a bigger picture is shrunk to this on its longer side before it is read
const DP_PX := 0.0025      # Douglas-Peucker tolerance: this share of the longer side (at least 1 px)
const MIN_LOOP := 0.0004   # a loop smaller than this share of the picture is dust, not a shape
const SIG_N := 128         # points of the centre-distance signature
const HARM := 24           # harmonics kept
const WEIGHT_POW := 0.8    # harmonic k counts k^0.8: a corner (high k) outweighs a lopsided drawing (k = 2)


# ------------------------------------------------------------------ picture -> outlines

## {"loops": [PackedVector2Array in mm, y UP, centred on the picture's middle], "why": ""}; width_mm is the picture's whole width.
## A hole in the shape is a loop of its own (the kernel sees it as a hole inside the outer loop).
static func trace_image(img_in: Image, width_mm: float) -> Dictionary:
	if img_in == null or img_in.is_empty() or width_mm <= 0.0:
		return {"loops": [], "why": "That picture cannot be read. Pick a PNG or JPG, then press Trace it again"}
	var img := img_in.duplicate() as Image
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	if maxi(w, h) > MAX_SIDE:
		var k := float(MAX_SIDE) / float(maxi(w, h))
		w = maxi(1, roundi(w * k))
		h = maxi(1, roundi(h * k))
		img.resize(w, h, Image.INTERPOLATE_BILINEAR)
	# grey levels (see-through counts as white), the threshold between the two humps (Otsu)
	var grey := PackedFloat32Array()
	grey.resize(w * h)
	var hist := PackedInt32Array()
	hist.resize(256)
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			var g := (c.r * 0.299 + c.g * 0.587 + c.b * 0.114) * c.a + (1.0 - c.a)
			grey[y * w + x] = g
			hist[clampi(int(g * 255.0), 0, 255)] += 1
	var thr := _otsu(hist, w * h)
	var ink := PackedByteArray()
	ink.resize(w * h)
	var n_ink := 0
	for i in w * h:
		if grey[i] * 255.0 <= thr:
			ink[i] = 1
			n_ink += 1
	if n_ink == 0:
		return {"loops": [], "why": "No dark shape in that picture: use a dark shape on a light background, then press Trace it again"}
	if n_ink == w * h:
		return {"loops": [], "why": "The whole picture is dark: use a dark shape on a light background, then press Trace it again"}
	var raw := walk_loops(ink, w, h)
	var sc := width_mm / float(w)
	var eps := maxf(1.0, DP_PX * float(maxi(w, h)))
	var loops: Array = []
	for lp in raw:
		var poly: PackedVector2Array = lp
		if absf(area(poly)) < MIN_LOOP * float(w * h):
			continue
		var s := simplify_closed(poly, eps)
		if s.size() < 3:
			continue
		var mm := PackedVector2Array()
		for p in s:
			mm.append(Vector2((p.x - w * 0.5) * sc, -(p.y - h * 0.5) * sc))   # y up: the picture's top is the sketch's +y (Top plane, up the screen)
		loops.append(mm)
	if loops.is_empty():
		return {"loops": [], "why": "The dark shape is too small to trace: use a bigger shape, then press Trace it again"}
	return {"loops": loops, "why": ""}


static func _otsu(hist: PackedInt32Array, total: int) -> float:
	var sum_all := 0.0
	for i in 256:
		sum_all += float(i) * float(hist[i])
	var wb := 0.0
	var sb := 0.0
	var best := -1.0
	var thr := 127.0
	for t in 256:
		wb += float(hist[t])
		if wb == 0.0:
			continue
		var wf := float(total) - wb
		if wf == 0.0:
			break
		sb += float(t) * float(hist[t])
		var mb := sb / wb
		var mf := (sum_all - sb) / wf
		var between := wb * wf * (mb - mf) * (mb - mf)
		if between > best:
			best = between
			thr = float(t)
	return thr


## a sketch's line entities (closed loops of mm points)
static func line_ents(loops: Array) -> Array:
	var ents: Array = []
	for lp in loops:
		var poly: PackedVector2Array = lp
		for i in poly.size():
			ents.append({"k": "line", "a": [poly[i].x, poly[i].y], "b": [poly[(i + 1) % poly.size()].x, poly[(i + 1) % poly.size()].y]})
	return ents


# ------------------------------------------------------------------ masks and boundary walks

## every boundary of the ink cells as a closed loop, through the MIDDLES of the boundary edges (so a staircase does not bias the size)
static func walk_loops(ink: PackedByteArray, w: int, h: int) -> Array:
	var stride := w + 1
	var nxt := {}   # corner key -> Array of next corner keys
	for y in h:
		for x in w:
			if ink[y * w + x] == 0:
				continue
			if y == 0 or ink[(y - 1) * w + x] == 0:
				_add(nxt, y * stride + x, y * stride + x + 1)
			if x == w - 1 or ink[y * w + x + 1] == 0:
				_add(nxt, y * stride + x + 1, (y + 1) * stride + x + 1)
			if y == h - 1 or ink[(y + 1) * w + x] == 0:
				_add(nxt, (y + 1) * stride + x + 1, (y + 1) * stride + x)
			if x == 0 or ink[y * w + x - 1] == 0:
				_add(nxt, (y + 1) * stride + x, y * stride + x)
	var out: Array = []
	var guard := 0
	while not nxt.is_empty() and guard < 200000:
		guard += 1
		var start: int = nxt.keys()[0]
		var keys: Array = []
		var cur := start
		while true:
			keys.append(cur)
			var lst: Array = nxt[cur]
			var to: int = lst.pop_back()
			if lst.is_empty():
				nxt.erase(cur)
			cur = to
			if cur == start or not nxt.has(cur):
				break
		if keys.size() < 4:
			continue
		# the middle of each edge (key i -> key i+1)
		var pts := PackedVector2Array()
		for i in keys.size():
			var a: int = keys[i]
			var b: int = keys[(i + 1) % keys.size()]
			pts.append(Vector2(float(a % stride + b % stride) * 0.5, float(a / stride + b / stride) * 0.5))
		out.append(pts)
	return out


static func _add(nxt: Dictionary, a: int, b: int) -> void:
	if not nxt.has(a):
		nxt[a] = []
	nxt[a].append(b)


## the loop with the biggest area (the outside of the shape; the others are holes or specks)
static func outer_loop(loops: Array) -> PackedVector2Array:
	var best := PackedVector2Array()
	var ba := 0.0
	for lp in loops:
		var a := absf(area(lp))
		if a > ba:
			ba = a
			best = lp
	return best


## the silhouette of a triangle soup (metres, Vector3 per corner) seen along an axis: 0 = from above (x, -z), 1 = from the front (x, y), 2 = from the side (z, y).
## {"contours": one outer contour (in cell units of a side x side grid; the shape spans SPAN cells) for each grow level: the shape fattened by
## level x SPAN cells all round, so a thin outline (a bracket's L) can meet a fat drawn one, "area": the silhouette's area in m2}. Empty contours when the view shows nothing.
const SIDE := 144
const PAD := 24
static func silhouette_contours(tris_list: Array, view: int, levels: Array) -> Dictionary:
	var side := SIDE
	var pts := PackedVector2Array()
	for tris in tris_list:
		var t: PackedVector3Array = tris
		for v in t:
			pts.append(_proj(v, view))
	if pts.size() < 3:
		return {"contours": [], "area": 0.0}
	var lo := pts[0]
	var hi := pts[0]
	for p in pts:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var span := maxf(hi.x - lo.x, hi.y - lo.y)
	if span < 1e-9:
		return {"contours": [], "area": 0.0}
	var k := float(side - 2 * PAD) / span
	var mask := PackedByteArray()
	mask.resize(side * side)
	for tris in tris_list:
		var t: PackedVector3Array = tris
		for i in range(0, t.size() - 2, 3):
			var a := (_proj(t[i], view) - lo) * k + Vector2(PAD, PAD)
			var b := (_proj(t[i + 1], view) - lo) * k + Vector2(PAD, PAD)
			var c := (_proj(t[i + 2], view) - lo) * k + Vector2(PAD, PAD)
			_fill_tri(mask, side, a, b, c)
	var dist := _dist_to_ink(mask, side)
	var cells := 0
	for i in side * side:
		cells += mask[i]
	var cell_len := span / float(side - 2 * PAD)
	var out: Array = []
	for lv in levels:
		var r := float(lv) * float(side - 2 * PAD)
		var m2 := PackedByteArray()
		m2.resize(side * side)
		for i in side * side:
			m2[i] = 1 if dist[i] <= r else 0
		var lp := outer_loop(walk_loops(m2, side, side))
		out.append(lp)
	return {"contours": out, "area": float(cells) * cell_len * cell_len}


## distance (cells, chamfer 1 / 1.414) from every cell to the nearest ink cell (0 on ink)
static func _dist_to_ink(mask: PackedByteArray, side: int) -> PackedFloat32Array:
	var d := PackedFloat32Array()
	d.resize(side * side)
	for i in side * side:
		d[i] = 0.0 if mask[i] == 1 else 1e6
	for y in side:
		for x in side:
			var i := y * side + x
			var v := d[i]
			if x > 0:
				v = minf(v, d[i - 1] + 1.0)
			if y > 0:
				v = minf(v, d[i - side] + 1.0)
				if x > 0:
					v = minf(v, d[i - side - 1] + 1.414)
				if x < side - 1:
					v = minf(v, d[i - side + 1] + 1.414)
			d[i] = v
	for y in range(side - 1, -1, -1):
		for x in range(side - 1, -1, -1):
			var i := y * side + x
			var v := d[i]
			if x < side - 1:
				v = minf(v, d[i + 1] + 1.0)
			if y < side - 1:
				v = minf(v, d[i + side] + 1.0)
				if x < side - 1:
					v = minf(v, d[i + side + 1] + 1.414)
				if x > 0:
					v = minf(v, d[i + side - 1] + 1.414)
			d[i] = v
	return d


## a drawn stroke as an outline to compare. A stroke that comes back near its start is the outline itself; an open stroke (an L drawn as
## two lines) is a line, so it is fattened into a band and the band's outline is used. Returns an empty array for a speck.
static func stroke_outline(stroke: PackedVector2Array) -> PackedVector2Array:
	var n := stroke.size()
	if n < 3:
		return PackedVector2Array()
	var lo := stroke[0]
	var hi := stroke[0]
	var length := 0.0
	for i in n:
		lo = Vector2(minf(lo.x, stroke[i].x), minf(lo.y, stroke[i].y))
		hi = Vector2(maxf(hi.x, stroke[i].x), maxf(hi.y, stroke[i].y))
		if i > 0:
			length += stroke[i].distance_to(stroke[i - 1])
	var ext := maxf(hi.x - lo.x, hi.y - lo.y)
	if ext < 1e-6:
		return PackedVector2Array()
	if stroke[0].distance_to(stroke[n - 1]) <= 0.3 * ext:
		return stroke
	var side := 160
	var pad := 14
	var k := float(side - 2 * pad) / ext
	var rr := maxf(2.0, 0.045 * float(side - 2 * pad))
	var mask := PackedByteArray()
	mask.resize(side * side)
	for i in range(1, n):
		var a := (stroke[i - 1] - lo) * k + Vector2(pad, pad)
		var b := (stroke[i] - lo) * k + Vector2(pad, pad)
		var steps := maxi(1, int(ceilf(a.distance_to(b) / 1.0)))
		for s in steps + 1:
			var c := a.lerp(b, float(s) / float(steps))
			for dy in range(-int(rr), int(rr) + 1):
				for dx in range(-int(rr), int(rr) + 1):
					if dx * dx + dy * dy <= rr * rr:
						var x := int(c.x) + dx
						var y := int(c.y) + dy
						if x >= 0 and y >= 0 and x < side and y < side:
							mask[y * side + x] = 1
	return outer_loop(walk_loops(mask, side, side))


static func _proj(v: Vector3, view: int) -> Vector2:
	match view:
		0:
			return Vector2(v.x, -v.z)
		1:
			return Vector2(v.x, -v.y)
		_:
			return Vector2(v.z, -v.y)


## the cells whose centre is inside the triangle (grown by half a cell, so two triangles that share an edge leave no crack)
static func _fill_tri(mask: PackedByteArray, side: int, a: Vector2, b: Vector2, c: Vector2) -> void:
	var x0 := maxi(0, int(floorf(minf(a.x, minf(b.x, c.x)) - 0.5)))
	var x1 := mini(side - 1, int(ceilf(maxf(a.x, maxf(b.x, c.x)) + 0.5)))
	var y0 := maxi(0, int(floorf(minf(a.y, minf(b.y, c.y)) - 0.5)))
	var y1 := mini(side - 1, int(ceilf(maxf(a.y, maxf(b.y, c.y)) + 0.5)))
	var d := (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
	if absf(d) < 1e-12:
		# an edge-on triangle: its line of cells
		_fill_seg(mask, side, a, b)
		_fill_seg(mask, side, b, c)
		return
	var tol := 0.5 * (absf(b.y - c.y) + absf(c.x - b.x)) / absf(d)   # half a cell, in barycentric units (rough)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var px := float(x) + 0.5
			var py := float(y) + 0.5
			var l1 := ((b.y - c.y) * (px - c.x) + (c.x - b.x) * (py - c.y)) / d
			var l2 := ((c.y - a.y) * (px - c.x) + (a.x - c.x) * (py - c.y)) / d
			var l3 := 1.0 - l1 - l2
			var m := -tol
			if l1 >= m and l2 >= m and l3 >= m:
				mask[y * side + x] = 1


static func _fill_seg(mask: PackedByteArray, side: int, a: Vector2, b: Vector2) -> void:
	var n := maxi(1, int(ceilf(a.distance_to(b))))
	for i in n + 1:
		var p := a.lerp(b, float(i) / float(n))
		var x := clampi(int(p.x), 0, side - 1)
		var y := clampi(int(p.y), 0, side - 1)
		mask[y * side + x] = 1


# ------------------------------------------------------------------ polygons

static func area(poly: PackedVector2Array) -> float:
	var s := 0.0
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		s += a.x * b.y - b.x * a.y
	return s * 0.5


static func centroid(poly: PackedVector2Array) -> Vector2:
	var ar := area(poly)
	var n := poly.size()
	if absf(ar) < 1e-9:
		var m := Vector2.ZERO
		for p in poly:
			m += p
		return m / float(maxi(n, 1))
	var cx := 0.0
	var cy := 0.0
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var cr := a.x * b.y - b.x * a.y
		cx += (a.x + b.x) * cr
		cy += (a.y + b.y) * cr
	return Vector2(cx, cy) / (6.0 * ar)


## Douglas-Peucker on a closed loop: split at the two points farthest apart, simplify each half
static func simplify_closed(poly: PackedVector2Array, eps: float) -> PackedVector2Array:
	var n := poly.size()
	if n < 4:
		return poly
	var i0 := 0
	var i1 := 0
	var far := -1.0
	var p0 := poly[0]
	for i in n:
		var d := poly[i].distance_squared_to(p0)
		if d > far:
			far = d
			i1 = i
	far = -1.0
	var p1 := poly[i1]
	for i in n:
		var d := poly[i].distance_squared_to(p1)
		if d > far:
			far = d
			i0 = i
	if i0 == i1:
		return poly
	var a := mini(i0, i1)
	var b := maxi(i0, i1)
	var half1 := PackedVector2Array()
	for i in range(a, b + 1):
		half1.append(poly[i])
	var half2 := PackedVector2Array()
	for i in range(b, n):
		half2.append(poly[i])
	for i in range(0, a + 1):
		half2.append(poly[i])
	var s1 := simplify_open(half1, eps)
	var s2 := simplify_open(half2, eps)
	var out := PackedVector2Array()
	for i in s1.size() - 1:
		out.append(s1[i])
	for i in s2.size() - 1:
		out.append(s2[i])
	return out


## Douglas-Peucker on an open run (iterative, so a long run cannot overflow the stack)
static func simplify_open(pts: PackedVector2Array, eps: float) -> PackedVector2Array:
	var n := pts.size()
	if n < 3:
		return pts
	var keep := PackedByteArray()
	keep.resize(n)
	keep[0] = 1
	keep[n - 1] = 1
	var stack: Array = [[0, n - 1]]
	while not stack.is_empty():
		var seg: Array = stack.pop_back()
		var s: int = seg[0]
		var e: int = seg[1]
		if e <= s + 1:
			continue
		var worst := -1.0
		var wi := s
		var a := pts[s]
		var b := pts[e]
		for i in range(s + 1, e):
			var d := _seg_dist(pts[i], a, b)
			if d > worst:
				worst = d
				wi = i
		if worst > eps:
			keep[wi] = 1
			stack.append([s, wi])
			stack.append([wi, e])
	var out := PackedVector2Array()
	for i in n:
		if keep[i] == 1:
			out.append(pts[i])
	return out


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-12:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## n points spaced evenly along the closed outline
static func resample(poly: PackedVector2Array, n: int) -> PackedVector2Array:
	var m := poly.size()
	var out := PackedVector2Array()
	if m < 2:
		return out
	var cum := PackedFloat32Array()
	cum.resize(m + 1)
	for i in m:
		cum[i + 1] = cum[i] + poly[i].distance_to(poly[(i + 1) % m])
	var total := cum[m]
	if total < 1e-9:
		return out
	var j := 0
	for k in n:
		var s := total * float(k) / float(n)
		while j < m - 1 and cum[j + 1] < s:
			j += 1
		var seg := cum[j + 1] - cum[j]
		var t := 0.0 if seg < 1e-12 else (s - cum[j]) / seg
		out.append(poly[j].lerp(poly[(j + 1) % m], t))
	return out


# ------------------------------------------------------------------ shape descriptor

## the Fourier descriptor of the centre-distance signature: HARM numbers, free of size (the signature is divided by its mean), of turning
## (only the magnitudes are kept), of where the outline starts and of the way round it is walked. A closed outline of 3 or more points.
## Empty when the outline has no area.
static func descriptor(poly: PackedVector2Array) -> PackedFloat32Array:
	var pts := resample(poly, SIG_N)
	if pts.size() < SIG_N or absf(area(poly)) < 1e-9:
		return PackedFloat32Array()
	var c := centroid(poly)
	var r := PackedFloat32Array()
	r.resize(SIG_N)
	var mean := 0.0
	for i in SIG_N:
		r[i] = pts[i].distance_to(c)
		mean += r[i]
	mean /= float(SIG_N)
	if mean < 1e-9:
		return PackedFloat32Array()
	var out := PackedFloat32Array()
	out.resize(HARM)
	for k in range(1, HARM + 1):
		var re := 0.0
		var im := 0.0
		for i in SIG_N:
			var ang := TAU * float(k) * float(i) / float(SIG_N)
			var v := r[i] / mean
			re += v * cos(ang)
			im -= v * sin(ang)
		out[k - 1] = sqrt(re * re + im * im) / float(SIG_N)
	return out


## how different two descriptors are (0 = the same shape); each harmonic counts k^WEIGHT_POW
static func distance(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	if a.size() != b.size() or a.is_empty():
		return INF
	var s := 0.0
	for k in a.size():
		var w := pow(float(k + 1), WEIGHT_POW)
		var d := (a[k] - b[k]) * w
		s += d * d
	return sqrt(s)


## how many other loops each loop sits inside (0 = an outside, 1 = a hole, 2 = an island in a hole ...), by testing the loop's first point
static func depths(loops: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in loops.size():
		var d := 0
		var p: Vector2 = (loops[i] as PackedVector2Array)[0]
		for j in loops.size():
			if i != j and Geometry2D.is_point_in_polygon(p, loops[j]):
				d += 1
		out.append(d)
	return out
