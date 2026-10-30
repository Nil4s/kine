class_name PictureTrace
extends RefCounted
## P034 YOUR OWN PICTURE: a picture file becomes the outline of its dark shape (the ink), as closed straight-line loops on the floor
## sketch. The picture is read on a grid (one cell per pixel, at most MAX_PX cells on its longer side); a cell is ink when it is dark
## and not see-through. Every edge between ink and no ink is walked into a loop, collinear edges merge, and the largest side is WIDTH_MM.
## Only the outline is kept: a hole in the shape (the middle of an O) is a loop of its own, the kernel decides how it sits.

const MAX_PX := 40
const INK := 0.5          # luminance below this is ink
const MAX_LINES := 400    # more straight lines than this: the picture has too much detail for one raised logo


## returns {"ents": [line entities in mm], "why": ""} or {"ents": [], "why": the words to say}
static func outline(path: String, width_mm: float) -> Dictionary:
	var img: Image = Image.load_from_file(path)
	if img == null or img.is_empty():
		return {"ents": [], "why": "That file is not a picture we can read. Pick a PNG or JPG, then press Picture again"}
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	if maxi(w, h) > MAX_PX:
		var k := float(MAX_PX) / float(maxi(w, h))
		w = maxi(1, roundi(w * k))
		h = maxi(1, roundi(h * k))
		img.resize(w, h, Image.INTERPOLATE_BILINEAR)
	var ink := PackedByteArray()
	ink.resize(w * h)
	var any := false
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			var on := c.a > 0.5 and c.r * 0.299 + c.g * 0.587 + c.b * 0.114 < INK
			ink[y * w + x] = 1 if on else 0
			any = any or on
	if not any:
		return {"ents": [], "why": "No dark shape in that picture: draw a dark shape on white, then press Picture again"}
	var loops := _loops(ink, w, h)
	var sc := width_mm / float(maxi(w, h))
	var ents: Array = []
	for lp in loops:
		var pts: Array = lp
		var n := pts.size()
		for i in n:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[(i + 1) % n]
			ents.append({"k": "line", "a": Part.arr2(_mm(a, sc, w, h)), "b": Part.arr2(_mm(b, sc, w, h))})
	if ents.size() > MAX_LINES:
		return {"ents": [], "why": "That picture has too much fine detail for one raised logo. Use a simpler picture with bigger shapes"}
	return {"ents": ents, "why": ""}


## grid corner (gx, gy) -> plane mm, centred on the middle of the picture (y down, as the picture)
static func _mm(p: Vector2, sc: float, w: int, h: int) -> Vector2:
	return Vector2(p.x * sc - w * sc * 0.5, p.y * sc - h * sc * 0.5)


## the boundary of the ink as loops of grid corners. Every ink edge runs with the ink on the same side, so the walk is one loop per
## outline; collinear corners are merged so a straight side is one line
static func _loops(ink: PackedByteArray, w: int, h: int) -> Array:
	var stride := w + 1
	var nxt := {}   # corner key -> Array of next corner keys
	for y in h:
		for x in w:
			if ink[y * w + x] == 0:
				continue
			var up := y == 0 or ink[(y - 1) * w + x] == 0
			var rt := x == w - 1 or ink[y * w + x + 1] == 0
			var dn := y == h - 1 or ink[(y + 1) * w + x] == 0
			var lf := x == 0 or ink[y * w + x - 1] == 0
			if up:
				_add(nxt, y * stride + x, y * stride + x + 1)
			if rt:
				_add(nxt, y * stride + x + 1, (y + 1) * stride + x + 1)
			if dn:
				_add(nxt, (y + 1) * stride + x + 1, (y + 1) * stride + x)
			if lf:
				_add(nxt, (y + 1) * stride + x, y * stride + x)
	var out := []
	var guard := 0
	while not nxt.is_empty() and guard < 100000:
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
		var pts: Array = []
		for k in keys:
			var kv := Vector2(k % stride, k / stride)
			if pts.size() >= 2 and _straight(pts[-2], pts[-1], kv):
				pts[-1] = kv
			else:
				pts.append(kv)
		if pts.size() >= 2 and _straight(pts[-2], pts[-1], pts[0]):
			pts.pop_back()
		if pts.size() >= 3 and _straight(pts[-1], pts[0], pts[1]):
			pts.pop_front()
		if pts.size() >= 3:
			out.append(pts)
	return out


static func _add(nxt: Dictionary, a: int, b: int) -> void:
	if not nxt.has(a):
		nxt[a] = []
	nxt[a].append(b)


## a, b, c on one straight run going the same way (b is not a turn)
static func _straight(a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1 := b - a
	var d2 := c - b
	return d1.cross(d2) == 0.0 and d1.dot(d2) > 0.0
