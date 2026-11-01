class_name KMeshSticker
extends RefCounted
## STICKER (Friday plan 158): an image (a PNG, or a built-in star / heart / logo) projected onto the mesh's "color" channel
## (kmesh_vpaint.gd: one colour per face corner) at a surface point. Decal projection: the image plane is the surface
## plane at the click (normal n), its "up" is the world up (or the nearest axis when n is vertical) turned by `rot` radians
## about n; the image is `size` metres across. Every CORNER whose face looks the same way as the click (face normal . n >
## 0.5, so the sticker does not wrap round an edge or show through the back) and that lies inside the image square takes
## the image colour, mixed in by the pixel's alpha (alpha 0 leaves the corner as it was). Pure: no nodes. The caller brackets
## it with KMeshUndo.begin / commit so one sticker is one undo step. The sticker's resolution is the mesh's: a sticker over
## a 4 x 4 quad face is a few coloured corners, a subdivided mesh (Ctrl+1) shows the shape.

const NAMES := ["star", "heart", "logo"]


## a built-in sticker image (n x n, RGBA, transparent outside the shape)
static func builtin(name: String, n := 128) -> Image:
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in n:
		for x in n:
			var u := (float(x) + 0.5) / n * 2.0 - 1.0
			var v := 1.0 - (float(y) + 0.5) / n * 2.0   # y up
			var c := Color(0, 0, 0, 0)
			match name:
				"star":
					if _in_star(u, v):
						c = Color(1.0, 0.85, 0.1, 1.0)
				"heart":
					var hx := u * 1.15
					var hy := v * 1.15 + 0.15
					if pow(hx * hx + hy * hy - 1.0, 3.0) - hx * hx * hy * hy * hy <= 0.0:
						c = Color(0.9, 0.1, 0.2, 1.0)
				_:   # logo: a blue ring with a white bar across
					var r := sqrt(u * u + v * v)
					if r <= 0.95 and r >= 0.7:
						c = Color(0.1, 0.35, 0.85, 1.0)
					elif r < 0.7 and absf(v - u * 0.5) < 0.16:
						c = Color(1, 1, 1, 1)
			img.set_pixel(x, y, c)
	return img


static func _in_star(u: float, v: float) -> bool:
	# a five-point star: inside when the point is under the outline r(theta) between 0.4 (inner) and 0.98 (outer)
	var ang := atan2(u, v)   # 0 = straight up
	var r := sqrt(u * u + v * v)
	var seg := TAU / 5.0
	var a := fposmod(ang + seg * 0.5, seg) - seg * 0.5   # -seg/2 .. seg/2 round a tip
	# the outline between a tip (r 0.98 at a = 0) and a notch (r 0.4 at a = +-seg/2) is a straight line
	var t := absf(a) / (seg * 0.5)
	return r <= lerpf(0.98, 0.4, t)


## a PNG file as a sticker image, or null
static func load_png(path: String) -> Image:
	var img := Image.new()
	if img.load(path) != OK or img.is_empty():
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img


static func _face_normal(m: KMesh, fi: int) -> Vector3:
	var fp: PackedInt32Array = m.faces[fi]
	var n := Vector3.ZERO
	for i in fp.size():
		var a := m.verts[fp[i]]
		var b := m.verts[fp[(i + 1) % fp.size()]]
		n += Vector3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
	return n.normalized()


## the sticker's tangent basis for a surface normal n: [right, up]
static func basis_for(n: Vector3, rot: float) -> Array:
	var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.95 else Vector3.BACK
	var right := up.cross(n).normalized()
	var upv := n.cross(right).normalized()
	var c := cos(rot)
	var s := sin(rot)
	return [right * c + upv * s, upv * c - right * s]


## place `img` at `point` (mesh-local) on face `fi`, `size` metres across, turned `rot` radians. Returns the corners it
## coloured (alpha > 0.02 of the pixel there).
static func place(m: KMesh, fi: int, point: Vector3, img: Image, size: float, rot := 0.0, opacity := 1.0) -> int:
	if img == null or img.is_empty() or fi < 0 or fi >= m.faces.size() or not KMeshVPaint.ensure(m):
		return 0
	var n := _face_normal(m, fi)
	var bs := basis_for(n, rot)
	var right: Vector3 = bs[0]
	var upv: Vector3 = bs[1]
	var half := size * 0.5
	var vd: bool = m.attr_info(KMeshVPaint.CH)["domain"] == KMesh.AD_VERT
	var d: PackedColorArray = m.attr_data(KMeshVPaint.CH)
	m.attrs[KMeshVPaint.CH]["data"] = PackedColorArray()   # one owner while writing
	var w := img.get_width()
	var h := img.get_height()
	var done := 0
	var seen := {}
	for f in m.faces.size():
		var fp: PackedInt32Array = m.faces[f]
		if _face_normal(m, f).dot(n) < 0.5:
			continue
		for i in fp.size():
			var rel := m.verts[fp[i]] - point
			if absf(rel.dot(n)) > half:
				continue
			var u := rel.dot(right) / size + 0.5
			var v := 0.5 - rel.dot(upv) / size
			if u < 0.0 or u >= 1.0 or v < 0.0 or v >= 1.0:
				continue
			var px := img.get_pixel(clampi(int(u * w), 0, w - 1), clampi(int(v * h), 0, h - 1))
			var a := px.a * opacity
			if a <= 0.02:
				continue
			var ci: int = fp[i] if vd else m.face_he0[f] + i
			d[ci] = KMeshVPaint.blend(KMeshVPaint.MIX, d[ci], Color(px.r, px.g, px.b, 1.0), a)
			if not seen.has(ci):
				seen[ci] = true
				done += 1
	m.attrs[KMeshVPaint.CH]["data"] = d
	return done
