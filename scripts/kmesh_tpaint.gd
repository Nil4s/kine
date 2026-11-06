class_name KMeshTPaint
extends RefCounted
## Texture paint with screen projection (L53, GAP_AUDIT Sculpt item 5). Vertex paint (kmesh_vpaint.gd) writes corner colours; this writes TEXELS of an
## RGBA8 texture through the mesh's "uv" corner attribute, so a stamp that crosses a UV seam colours both islands.
## stamp(mvp, cam_pos, screen, centre px, radius px, colour, strength, hardness, pad): for every texel of every triangle (faces fan-split) the surface
## point is projected with mvp (Projection * view * model, column-major) to screen px; the texel takes the colour when that is inside the disk (weight
## strength * falloff; hardness h = the flat core as a fraction of the radius, smoothstep to the rim), the triangle faces the camera (cull_back), and
## the point is not behind the nearest front-face depth of that pixel (occlusion; depth tolerance 2 % interior, 5 % gutter).
## SEAM BLEED (the dilation): a texel outside every triangle but within `pad` texels of one (and not covered by another island) is painted from that
## triangle's plane continued outward, so bilinear filtering across an island border never meets the unpainted gutter. pad 0 = no dilation.
## Each texel is written once per stamp (the first triangle in index order). u, v wrap (repeat). Texel (ix, iy) has its centre at (ix + .5, iy + .5)
## and uv (0,0) is the image's top-left. Native twin: native/src/kine_tpaint_native.cpp (KineTPaintNative); same arithmetic, doubles.
## Undo: begin_stroke() ... end_stroke() journals (texel, old, new); undo() / redo() restore exact bytes; hash() is SHA-256 of the texture.

var size := 0
var engine := "gdscript"
var cull_back := true
var occlusion := true
var tex := PackedByteArray()
var _nat = null
var _tris := []              # {"p": [3 Vector3], "uv": [3 Vector2 in texels]}
var _cov := PackedByteArray()
var _stamped := PackedByteArray()
var _in_stroke := false
var _cur := {}               # idx -> [old rgba]
var _undo := []
var _redo := []
var ok := false
var _steps := 0              # undo steps available (the native journal cannot be asked)


func _init(mesh: KMesh, p_size := 1024, use_native := true) -> void:
	size = p_size
	if not mesh.has_attr("uv"):
		return
	var pos := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uva: PackedVector2Array = mesh.attr_data("uv")
	var he0 := mesh.face_he0
	for f in mesh.face_count():
		var fp: PackedInt32Array = mesh.faces[f]
		for i in range(1, fp.size() - 1):
			for k in [0, i, i + 1]:
				pos.append(mesh.verts[fp[k]])
				uvs.append(uva[he0[f] + k])
	ok = true
	if use_native and NativeExt.ensure("kine_native", "KineTPaintNative"):
		_nat = ClassDB.instantiate("KineTPaintNative")
		_nat.setup(pos, uvs, size)
		engine = "native"
		return
	for t in pos.size() / 3:
		var uv := []
		for j in 3:
			uv.append(Vector2(uvs[t * 3 + j].x * size, uvs[t * 3 + j].y * size))
		var den: float = (uv[1].x - uv[0].x) * (uv[2].y - uv[0].y) - (uv[2].x - uv[0].x) * (uv[1].y - uv[0].y)
		var tri := {"p": [pos[t * 3], pos[t * 3 + 1], pos[t * 3 + 2]], "uv": uv, "ok": absf(den) >= 1e-12, "inv": 0.0, "h": [0.0, 0.0, 0.0]}
		if tri["ok"]:
			tri["inv"] = 1.0 / den
			var hh := []
			for i in 3:
				var j := (i + 1) % 3
				var k := (i + 2) % 3
				var L := sqrt((uv[k].x - uv[j].x) * (uv[k].x - uv[j].x) + (uv[k].y - uv[j].y) * (uv[k].y - uv[j].y))
				hh.append(absf(den) / maxf(L, 1e-12))
			tri["h"] = hh
		_tris.append(tri)
	tex.resize(size * size * 4)
	tex.fill(255)
	_cov.resize(size * size)
	_stamped.resize(size * size)
	for T in _tris:
		if not T["ok"]:
			continue
		var uv: Array = T["uv"]
		var mn := Vector2(minf(uv[0].x, minf(uv[1].x, uv[2].x)), minf(uv[0].y, minf(uv[1].y, uv[2].y)))
		var mx := Vector2(maxf(uv[0].x, maxf(uv[1].x, uv[2].x)), maxf(uv[0].y, maxf(uv[1].y, uv[2].y)))
		for iy in range(int(floor(mn.y)), int(ceil(mx.y)) + 1):
			for ix in range(int(floor(mn.x)), int(ceil(mx.x)) + 1):
				var b := _bary(uv, T["inv"], ix + 0.5, iy + 0.5)
				if b[0] >= -1e-9 and b[1] >= -1e-9 and b[2] >= -1e-9:
					_cov[posmod(iy, size) * size + posmod(ix, size)] = 1


static func _bary(uv: Array, inv: float, px: float, py: float) -> Array:
	var b1: float = ((px - uv[0].x) * (uv[2].y - uv[0].y) - (uv[2].x - uv[0].x) * (py - uv[0].y)) * inv
	var b2: float = ((uv[1].x - uv[0].x) * (py - uv[0].y) - (px - uv[0].x) * (uv[1].y - uv[0].y)) * inv
	return [1.0 - b1 - b2, b1, b2]


static func mvp_array(m: Projection) -> PackedFloat64Array:
	var a := PackedFloat64Array()
	a.resize(16)
	for c in 4:
		var col: Vector4 = m[c]
		a[c * 4] = col.x
		a[c * 4 + 1] = col.y
		a[c * 4 + 2] = col.z
		a[c * 4 + 3] = col.w
	return a


## returns the number of texels written
func stamp(mvp: Projection, cam_pos: Vector3, screen: Vector2i, centre: Vector2, radius: float, color: Color, strength := 1.0, hardness := 0.0, pad := 2) -> int:
	if not ok or radius <= 0.0:
		return 0
	var M := mvp_array(mvp)
	if _nat != null:
		return _nat.stamp(M, cam_pos, screen.x, screen.y, centre.x, centre.y, radius, color, strength, hardness, pad, cull_back, occlusion)
	return _stamp_gd(M, cam_pos, screen, centre, radius, color, strength, hardness, pad)


## [screen x, screen y, clip w, clip x, clip y], or null behind the camera
static func _proj(M: PackedFloat64Array, P: Vector3, W: int, H: int):
	var cx: float = M[0] * P.x + M[4] * P.y + M[8] * P.z + M[12]
	var cy: float = M[1] * P.x + M[5] * P.y + M[9] * P.z + M[13]
	var cw: float = M[3] * P.x + M[7] * P.y + M[11] * P.z + M[15]
	if cw <= 1e-6:
		return null
	return [(cx / cw * 0.5 + 0.5) * W, (0.5 - cy / cw * 0.5) * H, cw, cx, cy]


func _stamp_gd(M: PackedFloat64Array, cam: Vector3, scr: Vector2i, centre: Vector2, R: float, color: Color, strength: float, hardness: float, pad: int) -> int:
	var cx := centre.x
	var cy := centre.y
	var nt := _tris.size()
	var sv := []
	var okv := PackedByteArray()
	var front := PackedByteArray()
	okv.resize(nt)
	front.resize(nt)
	sv.resize(nt)
	var rx0 := cx - R - 4.0
	var rx1 := cx + R + 4.0
	var ry0 := cy - R - 4.0
	var ry1 := cy + R + 4.0
	for t in nt:
		var P: Array = _tris[t]["p"]
		var s := []
		var all := true
		var mnx := 1e300
		var mny := 1e300
		var mxx := -1e300
		var mxy := -1e300
		for j in 3:
			var q = _proj(M, P[j], scr.x, scr.y)
			if q == null:
				all = false
				break
			s.append(q)
			mnx = minf(mnx, q[0])
			mxx = maxf(mxx, q[0])
			mny = minf(mny, q[1])
			mxy = maxf(mxy, q[1])
		sv[t] = s
		if not all or not _tris[t]["ok"]:
			continue
		var e1: Vector3 = P[1] - P[0]
		var e2: Vector3 = P[2] - P[0]
		var n0 := e1.y * e2.z - e1.z * e2.y
		var n1 := e1.z * e2.x - e1.x * e2.z
		var n2 := e1.x * e2.y - e1.y * e2.x
		front[t] = 1 if (n0 * (cam.x - P[0].x) + n1 * (cam.y - P[0].y) + n2 * (cam.z - P[0].z)) > 0.0 else 0
		okv[t] = 1 if (mxx >= rx0 and mnx <= rx1 and mxy >= ry0 and mny <= ry1) else 0
	var dx0 := maxi(0, int(floor(cx - R)) - 1)
	var dx1 := mini(scr.x - 1, int(ceil(cx + R)) + 1)
	var dy0 := maxi(0, int(floor(cy - R)) - 1)
	var dy1 := mini(scr.y - 1, int(ceil(cy + R)) + 1)
	var dw := maxi(0, dx1 - dx0 + 1)
	var dh := maxi(0, dy1 - dy0 + 1)
	var INF := 1e300
	var depth := PackedFloat64Array()
	if occlusion and dw > 0 and dh > 0:
		depth.resize(dw * dh)
		depth.fill(INF)
		for t in nt:
			if okv[t] == 0 or front[t] == 0:
				continue
			var s: Array = sv[t]
			var area: float = (s[1][0] - s[0][0]) * (s[2][1] - s[0][1]) - (s[2][0] - s[0][0]) * (s[1][1] - s[0][1])
			if absf(area) < 1e-12:
				continue
			var ia := 1.0 / area
			var mnx := minf(s[0][0], minf(s[1][0], s[2][0]))
			var mxx := maxf(s[0][0], maxf(s[1][0], s[2][0]))
			var mny := minf(s[0][1], minf(s[1][1], s[2][1]))
			var mxy := maxf(s[0][1], maxf(s[1][1], s[2][1]))
			var x0 := maxi(dx0, int(floor(mnx)))
			var x1 := mini(dx1, int(ceil(mxx)))
			var y0 := maxi(dy0, int(floor(mny)))
			var y1 := mini(dy1, int(ceil(mxy)))
			for y in range(y0, y1 + 1):
				for x in range(x0, x1 + 1):
					var px := x + 0.5
					var py := y + 0.5
					var l0: float = ((s[1][0] - px) * (s[2][1] - py) - (s[2][0] - px) * (s[1][1] - py)) * ia
					var l1: float = ((s[2][0] - px) * (s[0][1] - py) - (s[0][0] - px) * (s[2][1] - py)) * ia
					var l2 := 1.0 - l0 - l1
					if l0 < -1e-9 or l1 < -1e-9 or l2 < -1e-9:
						continue
					var w: float = 1.0 / (l0 / s[0][2] + l1 / s[1][2] + l2 / s[2][2])
					var di := (y - dy0) * dw + (x - dx0)
					if w < depth[di]:
						depth[di] = w
	var col := [color.r * 255.0, color.g * 255.0, color.b * 255.0, color.a * 255.0]
	var written := 0
	var stouched := PackedInt32Array()
	for t in nt:
		if okv[t] == 0 or (cull_back and front[t] == 0):
			continue
		var T: Dictionary = _tris[t]
		var uv: Array = T["uv"]
		var mnx := minf(uv[0].x, minf(uv[1].x, uv[2].x))
		var mxx := maxf(uv[0].x, maxf(uv[1].x, uv[2].x))
		var mny := minf(uv[0].y, minf(uv[1].y, uv[2].y))
		var mxy := maxf(uv[0].y, maxf(uv[1].y, uv[2].y))
		var sw: Array = sv[t]
		var inv: float = T["inv"]
		var hh: Array = T["h"]
		for iy in range(int(floor(mny)) - pad, int(ceil(mxy)) + pad + 1):
			for ix in range(int(floor(mnx)) - pad, int(ceil(mxx)) + pad + 1):
				var b := _bary(uv, inv, ix + 0.5, iy + 0.5)
				var inside: bool = b[0] >= -1e-9 and b[1] >= -1e-9 and b[2] >= -1e-9
				var idx := posmod(iy, size) * size + posmod(ix, size)
				if not inside:
					if pad <= 0 or _cov[idx] != 0:
						continue
					if minf(b[0] * hh[0], minf(b[1] * hh[1], b[2] * hh[2])) <= -float(pad):
						continue
				elif _stamped[idx] != 0:
					continue
				var cw: float = b[0] * sw[0][2] + b[1] * sw[1][2] + b[2] * sw[2][2]
				if cw <= 1e-6:
					continue
				var ccx: float = b[0] * sw[0][3] + b[1] * sw[1][3] + b[2] * sw[2][3]
				var ccy: float = b[0] * sw[0][4] + b[1] * sw[1][4] + b[2] * sw[2][4]
				var sx: float = (ccx / cw * 0.5 + 0.5) * scr.x
				var sy: float = (0.5 - ccy / cw * 0.5) * scr.y
				var d2: float = (sx - cx) * (sx - cx) + (sy - cy) * (sy - cy)
				if d2 >= R * R:
					continue
				var tt := sqrt(d2) / R
				var f := 1.0
				if tt > hardness:
					var u := (tt - hardness) / (1.0 - hardness)
					f = 1.0 - (3.0 * u * u - 2.0 * u * u * u)
				var w := strength * f
				if w <= 0.0:
					continue
				if occlusion and dw > 0:
					var px := clampi(int(floor(sx)), dx0, dx1)
					var py := clampi(int(floor(sy)), dy0, dy1)
					var dv: float = depth[(py - dy0) * dw + (px - dx0)]
					if dv < INF and cw > dv * (1.02 if inside else 1.05) + 1e-9:
						continue
				if _stamped[idx] != 0:
					continue
				_stamped[idx] = 1
				stouched.append(idx)
				var o := idx * 4
				if _in_stroke and not _cur.has(idx):
					_cur[idx] = [tex[o], tex[o + 1], tex[o + 2], tex[o + 3]]
				for c in 4:
					var v: float = tex[o + c] * (1.0 - w) + col[c] * w
					tex[o + c] = clampi(int(floor(v + 0.5)), 0, 255)
				written += 1
	for i in stouched:
		_stamped[i] = 0
	return written


func begin_stroke() -> void:
	_in_stroke = true
	_cur = {}
	if _nat != null:
		_nat.begin_stroke()


## the number of texels the stroke changed (0 = nothing journalled)
func end_stroke() -> int:
	_in_stroke = false
	if _nat != null:
		var nn: int = _nat.end_stroke()
		if nn > 0:
			_steps += 1
		return nn
	var e := []
	for idx in _cur:
		var o: Array = _cur[idx]
		var i4: int = idx * 4
		e.append([idx, o, [tex[i4], tex[i4 + 1], tex[i4 + 2], tex[i4 + 3]]])
	_cur = {}
	if not e.is_empty():
		_undo.append(e)
		_redo.clear()
		_steps += 1
	return e.size()


func undo() -> bool:
	if _nat != null:
		var r: bool = _nat.undo()
		if r:
			_steps -= 1
		return r
	if _undo.is_empty():
		return false
	_steps -= 1
	var e: Array = _undo.pop_back()
	for x in e:
		var o: Array = x[1]
		for c in 4:
			tex[x[0] * 4 + c] = o[c]
	_redo.append(e)
	return true


func redo() -> bool:
	if _nat != null:
		var r: bool = _nat.redo()
		if r:
			_steps += 1
		return r
	if _redo.is_empty():
		return false
	_steps += 1
	var e: Array = _redo.pop_back()
	for x in e:
		var n: Array = x[2]
		for c in 4:
			tex[x[0] * 4 + c] = n[c]
	_undo.append(e)
	return true


func can_undo() -> bool:
	return _steps > 0


func data() -> PackedByteArray:
	return _nat.get_data() if _nat != null else tex


func set_data(d: PackedByteArray) -> void:
	if _nat != null:
		_nat.set_data(d)
	elif d.size() == tex.size():
		tex = d


func coverage() -> PackedByteArray:
	return _nat.coverage() if _nat != null else _cov


func hash() -> String:
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_SHA256)
	hc.update(data())
	return hc.finish().hex_encode()


func image() -> Image:
	return Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, data())
