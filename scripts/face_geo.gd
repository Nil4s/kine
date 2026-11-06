class_name FaceGeo
extends RefCounted
## face_geo.gd - ROADMAP_400 I01-I04, first slice: THE FACE AS REAL GEOMETRY. Pure data and helpers (no node, no scene); main.gd
## draws it (opt-in: m._face_geo_set(true); the painted face of face.gd stays the default and is untouched).
##
## WHAT IT IS (stated plainly): the mannequin's head is a smooth featureless egg (assets/mannequin.glb, no eyes, no lids, no lips). This
## builds a FACE MASK on its front: a dense grid shell (1 mm lattice, ~16k vertices) draped on the head's front surface (a height
## field rasterised from the head triangles) 2 mm proud of it, sunk under the skin at its rim. The mask has OPENINGS (two eye
## fissures, the mouth slit) so the lids, lips, brows and chin are separate vertex GROUPS (REGION) on real topology; the eyes are
## two separate closed spheres behind the fissures; a dark cavity sits behind the mouth. It is NOT merged into the head piece and
## not part of the 65-bone body skeleton (that would change every export and skin): the face has its own three bones, jaw (hinge
## about the skull's middle, axis X) and eye_l / eye_r (at the eyeball centres), carried by the head. Nothing here is MIT / AGPL
## code or assets: it is generated.
## Space: the head's REST space (+X the hero's LEFT, +Y up, +Z front), the space of Face.anchors.
##
## BLENDSHAPES (I03): d["au"][name] = PackedVector3Array, one delta per mask vertex, linear in the weight, compact support (cos^2
## kernels: exactly zero away from the region). FACS (Ekman, Friesen & Hager 2002) directions:
##   AU1  inner brow raiser    inner brow + forehead UP 6.5 mm (frontalis, pars medialis)
##   AU4  brow lowerer         brow DOWN 5 mm and toward the midline 3.5 mm (corrugator, depressor supercilii, procerus)
##   AU6  cheek raiser         cheek UP 3.5 mm and a little toward the eye, lower lid up 2.2 mm (orbicularis oculi, pars orbitalis)
##   AU12 lip corner puller    corners UP 5 mm, OUT 6 mm, BACK 1.5 mm (zygomaticus major)
##   AU26 jaw drop             the jaw bone's rotation at JAW_MAX_DEG sampled into a shape (masseter relaxed, pterygoids)
##   AU45 blink                upper lid DOWN 1.6 x the margin height, lower lid UP 0.4 x: they meet 0.6 of the way down (Doane 1980:
##                             the upper lid does ~ 85 % of the closure, the lower ~ 1-2 mm), the lid riding the globe in z
## The magnitudes are artist's choices inside plausible ranges (the FACS manual gives directions, not millimetres); the test pins
## the direction and a minimum and the stillness of the far regions, not the exact millimetres.
## BONES (I02): the jaw rotates JAW weights (smooth) about the hinge; the lids FOLLOW the eye: an upper lid gains 0.5 x the globe
## radius x sin(pitch) (Becker & Fuchs 1988, from memory), a lower lid 0.15 x.
## ANTHROPOMETRY (x s, s = top of head / 1.754 m, the mannequin's scale): fissure 30 x 10 mm (Farkas 1994, Anthropometry of the Head
## and Face), mouth 50 mm, globe radius 12 mm (axial length 24 mm), interincisal opening at 27.5 deg about 46 mm with the hinge
## 97 mm from the incisors (Agerberg 1974: 40-55 mm). Figures from memory of the sources.

const REGION := {"face": 0, "lid_up_l": 1, "lid_lo_l": 2, "lid_up_r": 3, "lid_lo_r": 4, "lip_up": 5, "lip_lo": 6, "jaw": 7,
	"brow_l": 8, "brow_r": 9, "cheek_l": 10, "cheek_r": 11, "forehead": 12}
const AUS := ["AU1", "AU4", "AU6", "AU12", "AU26", "AU45"]
const JAW_MAX_DEG := 27.5
const H := 0.001               # m: the lattice
const MASK_OFF := 0.002        # m: the mask stands this far proud of the head skin
const GLOBE_PROUD := 0.0035    # m: the front pole of an eyeball stands this far in front of the skin plane
const LID_GAIN_UP := 0.5
const LID_GAIN_LO := 0.15
const SKIN := Color(0.80, 0.82, 0.88)
const PRESETS := {
	"joy": {"AU6": 0.8, "AU12": 1.0},                              # the Duchenne smile (Ekman, Davidson & Friesen 1990)
	"pain": {"AU4": 0.9, "AU6": 1.0, "AU45": 0.4, "AU26": 0.15}}   # Prkachin 1992: AU4, 6/7, (9/10), 43


static func preset(name: String) -> Dictionary:
	return (PRESETS[name] as Dictionary).duplicate() if PRESETS.has(name) else {}


static func _ss(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## cos^2 bump: 1 at the centre, 0 at and beyond r
static func _kern(dist: float, r: float) -> float:
	if dist >= r:
		return 0.0
	var c := cos(PI * 0.5 * dist / r)
	return c * c


## ---- the height field of the head's front: z(x, y), rasterised from the triangles (pts: corners, three per triangle)
static func _hf_make(pts: PackedVector3Array, x0: float, y0: float, x1: float, y1: float, res: float) -> Dictionary:
	var nx := int((x1 - x0) / res) + 1
	var ny := int((y1 - y0) / res) + 1
	var z := PackedFloat32Array()
	z.resize(nx * ny)
	z.fill(-1.0e9)
	for t in range(0, pts.size() - 2, 3):
		var a := pts[t]
		var b := pts[t + 1]
		var c := pts[t + 2]
		var denom := (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
		if absf(denom) < 1.0e-12:
			continue
		var minx := minf(a.x, minf(b.x, c.x))
		var maxx := maxf(a.x, maxf(b.x, c.x))
		var miny := minf(a.y, minf(b.y, c.y))
		var maxy := maxf(a.y, maxf(b.y, c.y))
		var i0 := maxi(int(floor((minx - x0) / res)), 0)
		var i1 := mini(int(ceil((maxx - x0) / res)), nx - 1)
		var j0 := maxi(int(floor((miny - y0) / res)), 0)
		var j1 := mini(int(ceil((maxy - y0) / res)), ny - 1)
		for j in range(j0, j1 + 1):
			var py := y0 + j * res
			for i in range(i0, i1 + 1):
				var px := x0 + i * res
				var l1 := ((b.y - c.y) * (px - c.x) + (c.x - b.x) * (py - c.y)) / denom
				var l2 := ((c.y - a.y) * (px - c.x) + (a.x - c.x) * (py - c.y)) / denom
				var l3 := 1.0 - l1 - l2
				if l1 >= -1.0e-6 and l2 >= -1.0e-6 and l3 >= -1.0e-6:
					var zz := l1 * a.z + l2 * b.z + l3 * c.z
					if zz > z[j * nx + i]:
						z[j * nx + i] = zz
	# the head is a coarse polyhedron: a box blur (+-5 mm, two passes, valid cells only) so the mask does not copy its facets
	var raw := z.duplicate()
	for pass_i in 3:
		var rr := 5 if pass_i < 2 else 3
		if pass_i == 2:
			for q in z.size():
				if raw[q] > -1.0e8:
					z[q] = maxf(z[q], raw[q])   # never under the real surface, then smooth the ridges that leaves
		for horiz in 2:
			var src := z.duplicate()
			for j in ny:
				for i in nx:
					if src[j * nx + i] < -1.0e8:
						continue
					var sum := 0.0
					var cnt := 0
					for k in range(-rr, rr + 1):
						var ii := i + (k if horiz == 0 else 0)
						var jj := j + (k if horiz == 1 else 0)
						if ii < 0 or jj < 0 or ii >= nx or jj >= ny:
							continue
						var zz2 := src[jj * nx + ii]
						if zz2 > -1.0e8:
							sum += zz2
							cnt += 1
					z[j * nx + i] = sum / cnt
	for q in z.size():
		if raw[q] > -1.0e8:
			z[q] = maxf(z[q], raw[q] - 0.0008)
	return {"z": z, "nx": nx, "ny": ny, "x0": x0, "y0": y0, "res": res}


## the height at (x, y): bilinear, -1e9 where the field has a hole
static func _hz(hf: Dictionary, x: float, y: float) -> float:
	var res: float = hf["res"]
	var nx: int = hf["nx"]
	var ny: int = hf["ny"]
	var fx := (x - float(hf["x0"])) / res
	var fy := (y - float(hf["y0"])) / res
	var i := int(floor(fx))
	var j := int(floor(fy))
	if i < 0 or j < 0 or i >= nx - 1 or j >= ny - 1:
		return -1.0e9
	var z: PackedFloat32Array = hf["z"]
	var z00 := z[j * nx + i]
	var z10 := z[j * nx + i + 1]
	var z01 := z[(j + 1) * nx + i]
	var z11 := z[(j + 1) * nx + i + 1]
	if z00 < -1.0e8 or z10 < -1.0e8 or z01 < -1.0e8 or z11 < -1.0e8:
		return -1.0e9
	var u := fx - i
	var v := fy - j
	return lerpf(lerpf(z00, z10, u), lerpf(z01, z11, u), v)


## z made left-right symmetric (the head is not exactly): the mean of z(x) and z(-x), -1e9 if either misses
static func _zsym(hf: Dictionary, x: float, y: float) -> float:
	var a := _hz(hf, x, y)
	var b := _hz(hf, -x, y)
	if a < -1.0e8 or b < -1.0e8:
		return -1.0e9
	return 0.5 * (a + b)


## ---- BUILD
static func build(head_pts: PackedVector3Array, anchors_in: Dictionary = {}) -> Dictionary:
	var an: Dictionary = anchors_in if not anchors_in.is_empty() else Face.anchors(head_pts)
	var s := float(an["top"]) / 1.754
	var cy := float((an["eye_l"] as Vector3).y)
	var hx := float((an["eye_l"] as Vector3).x)
	var my := float((an["mouth"] as Vector3).y)
	var by := float((an["brow_l"] as Vector3).y)
	var chin := float(an["chin"])
	var ea := 0.0150 * s            # eye opening half width (fissure width 30 x s)
	var eb := 0.0050 * s            # eye opening half height (fissure height 10 x s)
	var mh := 0.0250 * s            # mouth half width (50 x s)
	var gr := 0.012 * s             # globe radius
	var zf := -1.0e9
	for v in head_pts:
		zf = maxf(zf, v.z)
	var hf := _hf_make(head_pts, -0.085, chin - 0.01, 0.085, by + 0.04, 0.001)

	# the lattice: x symmetric about 0, a row exactly on the mouth line
	var nxh := 64
	var nxv := nxh * 2 + 1
	var y_lo := chin + 0.012
	var y_hi := by + 0.022
	var y0: float = my - floorf((my - y_lo) / H) * H
	var nyv := int(ceil((y_hi - y0) / H)) + 1
	var ncx := nxv - 1
	var ncy := nyv - 1
	var yc0 := (y0 + y_hi) * 0.5
	var ax := 0.062
	var ay := (y_hi - y0) * 0.5
	# cell state: 0 outside the footprint, 1 skin, 2 an opening (and which: 1 left eye, 2 right eye, 3 mouth in `open`)
	var st := PackedByteArray()
	st.resize(ncx * ncy)
	var open := PackedByteArray()
	open.resize(ncx * ncy)
	var fp := PackedByteArray()
	fp.resize(ncx * ncy)
	for j in ncy:
		var yc := y0 + (j + 0.5) * H
		for i in ncx:
			var xc := (i + 0.5 - nxh) * H
			var e := (xc / ax) * (xc / ax) + ((yc - yc0) / ay) * ((yc - yc0) / ay)
			if e > 1.0:
				continue
			var okc := true
			for q in 4:
				var xq := (i + (q & 1) - nxh) * H
				var yq := y0 + (j + (q >> 1)) * H
				var zq := _zsym(hf, xq, yq)
				if zq < zf - 0.07:
					okc = false
			if not okc:
				continue
			fp[j * ncx + i] = 1
			st[j * ncx + i] = 1
			var oid := 0
			for sd in 2:
				var cx := hx if sd == 0 else -hx
				var rr := ((xc - cx) / ea) * ((xc - cx) / ea) + ((yc - cy) / eb) * ((yc - cy) / eb)
				if rr < 1.0:
					oid = sd + 1
			if oid == 0 and absf(xc) <= mh * 1.0 and absf(yc - my) < H:
				oid = 3
			if oid != 0:
				st[j * ncx + i] = 2
				open[j * ncx + i] = oid

	# vertices touching a skin cell; hole rims; the BFS depth from the outer rim
	var vid := PackedInt32Array()
	vid.resize(nxv * nyv)
	vid.fill(-1)
	var verts := PackedVector3Array()
	var rim := PackedByteArray()      # 1 left eye, 2 right eye, 3 mouth: the opening a vertex borders
	var outer := PackedByteArray()
	var li := PackedInt32Array()
	var lj := PackedInt32Array()
	for j in nyv:
		for i in nxv:
			var n_skin := 0
			var n_open := 0
			var n_out := 0
			var oid2 := 0
			for q in 4:
				var ci := i - 1 + (q & 1)
				var cj := j - 1 + (q >> 1)
				if ci < 0 or cj < 0 or ci >= ncx or cj >= ncy:
					n_out += 1
					continue
				var sc := st[cj * ncx + ci]
				if sc == 1:
					n_skin += 1
				elif sc == 2:
					n_open += 1
					oid2 = open[cj * ncx + ci]
				else:
					n_out += 1
			if n_skin == 0:
				continue
			vid[j * nxv + i] = verts.size()
			verts.append(Vector3((i - nxh) * H, y0 + j * H, 0.0))
			rim.append(oid2 if n_open > 0 else 0)
			outer.append(1 if n_out > 0 else 0)
			li.append(i)
			lj.append(j)
	var nv := verts.size()
	var depth := PackedInt32Array()
	depth.resize(nv)
	depth.fill(999)
	var queue := []
	for v in nv:
		if outer[v] == 1:
			depth[v] = 0
			queue.append(v)
	var qh := 0
	while qh < queue.size():
		var v: int = queue[qh]
		qh += 1
		for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var ni: int = li[v] + (dd as Vector2i).x
			var nj: int = lj[v] + (dd as Vector2i).y
			if ni < 0 or nj < 0 or ni >= nxv or nj >= nyv:
				continue
			var u := vid[nj * nxv + ni]
			if u >= 0 and depth[u] > depth[v] + 1:
				depth[u] = depth[v] + 1
				queue.append(u)

	# triangles (clockwise seen from the front; the diagonal mirrored with x so the mesh is left-right symmetric)
	var tris := PackedInt32Array()
	for j in ncy:
		for i in ncx:
			if st[j * ncx + i] != 1:
				continue
			var a := vid[j * nxv + i]
			var b := vid[j * nxv + i + 1]
			var c := vid[(j + 1) * nxv + i + 1]
			var dq := vid[(j + 1) * nxv + i]
			var xc := (i + 0.5 - nxh)
			if xc > 0.0:
				tris.append_array([a, dq, b, b, dq, c])
			else:
				tris.append_array([a, dq, c, a, c, b])

	# snap the eye rims onto the fissure ellipse, pull the mouth rims to a slit
	for v in nv:
		var p := verts[v]
		if rim[v] == 1 or rim[v] == 2:
			# vertical snap: the rim goes onto the fissure ellipse straight up / down, so the upper and lower margins share their columns
			var cx := hx if rim[v] == 1 else -hx
			var dx0 := p.x - cx
			var upper0 := p.y >= cy
			var adx0 := minf(absf(dx0), ea * 0.999)
			var mm0 := eb * sqrt(maxf(1.0 - (adx0 / ea) * (adx0 / ea), 0.0))
			p.x = cx + signf(dx0) * adx0
			p.y = cy + (mm0 if upper0 else -mm0)
		elif rim[v] == 3:
			if p.y > my + 1.0e-9:
				p.y = my + 0.0003
			elif p.y < my - 1.0e-9:
				p.y = my - 0.0003
		verts[v] = p

	# teeth, hinge, eyes
	var zs_m := _zsym(hf, 0.0, my)
	var teeth_up := Vector3(0.0, my, zs_m - 0.012)
	var hinge := teeth_up + Vector3(0.0, 0.020, -0.095)
	var eyes := []
	for sd in 2:
		var cx := hx if sd == 0 else -hx
		var zse := _zsym(hf, cx, cy)
		eyes.append({"c": Vector3(cx, cy, zse + GLOBE_PROUD - gr), "r": gr, "side": "l" if sd == 0 else "r"})

	# heights, regions, weights
	var region := PackedInt32Array()
	region.resize(nv)
	var jaw_w := PackedFloat32Array()
	jaw_w.resize(nv)
	var lid_gain := PackedFloat32Array()
	lid_gain.resize(nv)
	var lid_g := PackedFloat32Array()      # the falloff of the lid zone (0 outside it)
	lid_g.resize(nv)
	var lid_m := PackedFloat32Array()      # the margin height at the vertex's column
	lid_m.resize(nv)
	var lid_up := PackedByteArray()
	lid_up.resize(nv)
	var lid_side := PackedByteArray()
	lid_side.resize(nv)
	var tint := PackedFloat32Array()      # per vertex: 4 weights (lip, brow, lid, cheek), smooth, for the colours
	tint.resize(nv * 4)
	var lip_hard := 0.0262
	for v in nv:
		var p := verts[v]
		var zb := _zsym(hf, p.x, p.y)
		if zb < -1.0e8:
			zb = zf - 0.03
		var t := clampf(float(depth[v]) / 6.0, 0.0, 1.0)
		var off := lerpf(-0.0012, MASK_OFF, _ss(0.0, 1.0, t))
		# the lips stand out a little (vermilion); the brows are a soft ridge
		var dym := p.y - my
		var lipb := 0.0
		if absf(p.x) < 0.024 and absf(dym) < 0.008:
			lipb = 0.0016 * (1.0 - absf(dym) / 0.008) * (1.0 - _ss(0.014, 0.024, absf(p.x)))
		var z := zb + off + lipb
		var reg := 0
		var found_lid := false
		for sd in 2:
			var cx := hx if sd == 0 else -hx
			var dx := p.x - cx
			var dy := p.y - cy
			var adx := absf(dx)
			var m := ea * 0.0
			if adx < ea:
				m = eb * sqrt(maxf(1.0 - (dx / ea) * (dx / ea), 0.0))
			var upper := dy >= 0.0
			var e := (dy - m) if upper else (-dy - m)
			var lim := 0.008 * s if upper else 0.006 * s
			if adx < ea * 1.35 and e >= -1.0e-6 and e < lim:
				var g := (1.0 - _ss(0.0, lim, maxf(e, 0.0))) * (1.0 - _ss(ea, ea * 1.35, adx))
				reg = REGION["lid_up_" + ("l" if sd == 0 else "r")] if upper else REGION["lid_lo_" + ("l" if sd == 0 else "r")]
				lid_g[v] = g
				lid_m[v] = m
				lid_up[v] = 1 if upper else 0
				lid_side[v] = sd
				lid_gain[v] = (LID_GAIN_UP if upper else LID_GAIN_LO) * g
				found_lid = true
		var is_rim_eye := rim[v] == 1 or rim[v] == 2
		if not found_lid:
			if absf(p.x) < lip_hard and absf(dym) < 0.009:
				reg = REGION["lip_up"] if dym > 1.0e-9 else REGION["lip_lo"]
			else:
				var ab := absf(p.x)
				var yb := by + 0.004 - 0.012 * ((ab - 0.026) / 0.022) * ((ab - 0.026) / 0.022)
				if ab > 0.006 and ab < 0.048 and absf(p.y - yb) < 0.0045:
					reg = REGION["brow_l"] if p.x > 0.0 else REGION["brow_r"]
					z += 0.0008 * (1.0 - absf(p.y - yb) / 0.0045)
				elif p.y < my - 0.009:
					reg = REGION["jaw"]
				elif p.y > my + 0.012 and p.y < cy - 0.008 and ab > 0.010:
					reg = REGION["cheek_l"] if p.x > 0.0 else REGION["cheek_r"]
				elif p.y > cy + 0.010:
					reg = REGION["forehead"]
		# the globe pushes the lids out where it stands in front of the mask
		for e2 in eyes:
			var c: Vector3 = e2["c"]
			var rr2 := (p.x - c.x) * (p.x - c.x) + (p.y - c.y) * (p.y - c.y)
			if rr2 < gr * gr:
				z = maxf(z, c.z + sqrt(gr * gr - rr2) + 0.0012)
		verts[v] = Vector3(p.x, p.y, z)
		region[v] = reg
		var ab2 := absf(p.x)
		var yb2 := by + 0.004 - 0.012 * ((ab2 - 0.026) / 0.022) * ((ab2 - 0.026) / 0.022)
		var el := sqrt((p.x / 0.0275) * (p.x / 0.0275) + (dym / 0.0078) * (dym / 0.0078))
		tint[v * 4] = 1.0 - _ss(0.7, 1.0, el)
		tint[v * 4 + 1] = (1.0 - _ss(0.5, 1.0, absf(p.y - yb2) / 0.0045)) * (1.0 - _ss(0.040, 0.050, ab2)) * _ss(0.003, 0.009, ab2)
		tint[v * 4 + 2] = lid_g[v]
		var cd := Vector2((ab2 - 0.032) / 0.022, (p.y - (cy - 0.026)) / 0.020).length()
		tint[v * 4 + 3] = 1.0 - _ss(0.4, 1.0, cd)
		# the jaw weight: hard between the lips, smooth round the corners; fades to 0 at the footprint's side
		var wx := 1.0 - _ss(0.026, 0.060, absf(p.x))
		var wy := 1.0 if dym < -1.0e-9 else (0.5 if absf(dym) <= 1.0e-9 else 0.0)
		if dym < -1.0e-9:
			# the lower lip lifts toward the corners, so an open mouth is a lens, not a box
			wy = 1.0 - 0.65 * _ss(0.010, 0.026, absf(p.x)) * (1.0 - _ss(0.004, 0.010, absf(dym)))
		var wys := _ss(0.0, 1.0, clampf((my + 0.010 - p.y) / 0.020, 0.0, 1.0))
		var bl := _ss(lip_hard, 0.031, absf(p.x))
		jaw_w[v] = lerpf(wy, wys, bl) * (1.0 if absf(p.x) < lip_hard else wx)

	# ---- the blendshapes
	var au := {}
	var d1 := PackedVector3Array()
	var d4 := PackedVector3Array()
	var d6 := PackedVector3Array()
	var d12 := PackedVector3Array()
	var d26 := PackedVector3Array()
	var d45 := PackedVector3Array()
	d1.resize(nv)
	d4.resize(nv)
	d6.resize(nv)
	d12.resize(nv)
	d26.resize(nv)
	d45.resize(nv)
	var th := deg_to_rad(JAW_MAX_DEG)
	for v in nv:
		var p := verts[v]
		var sx := signf(p.x)
		var ab := absf(p.x)
		# AU1: inner brow + forehead up
		var k1 := _kern(Vector2(ab - 0.016, p.y - by).length(), 0.020)
		d1[v] = Vector3(0.0, 0.0065 * k1, 0.0)
		# AU4: brow down and toward the midline
		var k4 := _kern(Vector2(ab - 0.022, p.y - (by + 0.002)).length(), 0.024)
		d4[v] = Vector3(-sx * 0.0035 * k4, -0.005 * k4, 0.0)
		# AU6: cheek up, a little toward the eye; lower lid up
		var k6 := _kern(Vector2(ab - 0.031, p.y - (cy - 0.020)).length(), 0.020)
		var dv6 := Vector3(-sx * 0.001 * k6, 0.0035 * k6, 0.0)
		# AU12: corners up, out, back
		var k12 := _kern(Vector2(ab - 0.027, p.y - my).length(), 0.017)
		d12[v] = Vector3(sx * 0.006 * k12, 0.005 * k12, -0.0015 * k12)
		# AU26: the jaw bone at its maximum, sampled
		var jw := jaw_w[v]
		if jw > 0.0:
			var rel := p - hinge
			var a := th * jw
			var q := Vector3(rel.x, rel.y * cos(a) - rel.z * sin(a), rel.y * sin(a) + rel.z * cos(a))
			d26[v] = q - rel
		# AU45 + the lid part of AU6
		if lid_g[v] > 0.0:
			var sd: int = lid_side[v]
			var c: Vector3 = (eyes[sd] as Dictionary)["c"]
			var g: float = lid_g[v]
			var m: float = lid_m[v]
			var dy := 0.0
			if lid_up[v] == 1:
				dy = -1.6 * m * g
			else:
				dy = 0.4 * m * g
				dv6.y += 0.0022 * g
			var gz0 := sqrt(maxf(gr * gr - (p.x - c.x) * (p.x - c.x) - (p.y - c.y) * (p.y - c.y), 0.0))
			var gz1 := sqrt(maxf(gr * gr - (p.x - c.x) * (p.x - c.x) - (p.y + dy - c.y) * (p.y + dy - c.y), 0.0))
			var dz := g * (gz1 - gz0)   # the lid rides the globe
			if (p.x - c.x) * (p.x - c.x) + (p.y - c.y) * (p.y - c.y) > 0.64 * gr * gr:
				dz = clampf(dz, -0.5 * absf(dy), 0.5 * absf(dy))   # near the globe's edge the slope is steep: mostly up / down
			d45[v] = Vector3(0.0, dy, dz)
		d6[v] = dv6
	au["AU1"] = d1
	au["AU4"] = d4
	au["AU6"] = d6
	au["AU12"] = d12
	au["AU26"] = d26
	au["AU45"] = d45

	return {"anchors": an, "scale": s, "verts": verts, "tris": tris, "region": region, "jaw_w": jaw_w, "rim": rim,
		"lid_gain": lid_gain, "tint": tint, "au": au, "eyes": eyes, "eye_r": gr,
		"bones": {"head": {"o": Vector3.ZERO, "parent": ""}, "jaw": {"o": hinge, "parent": "head"},
			"eye_l": {"o": (eyes[0] as Dictionary)["c"], "parent": "head"}, "eye_r": {"o": (eyes[1] as Dictionary)["c"], "parent": "head"}},
		"teeth_up": teeth_up, "teeth_lo": teeth_up,
		"cavity": {"c": Vector3(0.0, my - 0.008, zs_m - 0.040), "r": Vector3(0.036, 0.040, 0.034)},
		"cut": {"y_max": my + 0.012, "x_max": 0.072, "z_min": zs_m - 0.06}}


## ---- POSE: the vertices for a state {"au": {name: weight}, "jaw_deg", "eye_pitch_deg", "eye_yaw_deg", "lid_follow" (default true)}
static func posed(d: Dictionary, st: Dictionary) -> PackedVector3Array:
	var v: PackedVector3Array = (d["verts"] as PackedVector3Array).duplicate()
	var n := v.size()
	var au: Dictionary = st.get("au", {})
	var tab: Dictionary = d["au"]
	for k in au:
		var w := float(au[k])
		if w == 0.0 or not tab.has(k):
			continue
		var dl: PackedVector3Array = tab[k]
		for i in n:
			v[i] += dl[i] * w
	var pit := deg_to_rad(float(st.get("eye_pitch_deg", 0.0)))
	if pit != 0.0 and bool(st.get("lid_follow", true)):
		var lg: PackedFloat32Array = d["lid_gain"]
		var k := float(d["eye_r"]) * sin(pit)
		for i in n:
			if lg[i] != 0.0:
				var p := v[i]
				p.y += lg[i] * k
				v[i] = p
	var jd := float(st.get("jaw_deg", 0.0))
	if jd != 0.0:
		var jw: PackedFloat32Array = d["jaw_w"]
		var hinge: Vector3 = d["bones"]["jaw"]["o"]
		for i in n:
			if jw[i] > 0.0:
				var rel := v[i] - hinge
				var a := deg_to_rad(jd) * jw[i]
				v[i] = hinge + Vector3(rel.x, rel.y * cos(a) - rel.z * sin(a), rel.y * sin(a) + rel.z * cos(a))
	return v


## the interincisal distance (mm) with the jaw bone at `deg`: the lower incisal edge rotated about the hinge
static func incisal_mm(d: Dictionary, deg: float) -> float:
	var hinge: Vector3 = d["bones"]["jaw"]["o"]
	var rel: Vector3 = (d["teeth_lo"] as Vector3) - hinge
	var a := deg_to_rad(deg)
	var q := hinge + Vector3(rel.x, rel.y * cos(a) - rel.z * sin(a), rel.y * sin(a) + rel.z * cos(a))
	return q.distance_to(d["teeth_up"]) * 1000.0


## the eye bones: each eye's transform in head space (position = the globe centre; pitch up = positive, yaw toward the hero's left)
static func eye_transforms(d: Dictionary, st: Dictionary) -> Array:
	var out := []
	var pit := deg_to_rad(float(st.get("eye_pitch_deg", 0.0)))
	var yaw := deg_to_rad(float(st.get("eye_yaw_deg", 0.0)))
	for e in d["eyes"]:
		out.append(Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -pit), e["c"]))
	return out


## ---- MESHES
static func _normals(vs: PackedVector3Array, ix: PackedInt32Array) -> PackedVector3Array:
	var nm := PackedVector3Array()
	nm.resize(vs.size())
	for t in range(0, ix.size() - 2, 3):
		var fn := (vs[ix[t + 1]] - vs[ix[t]]).cross(vs[ix[t + 2]] - vs[ix[t]])
		for q in 3:
			nm[ix[t + q]] += fn
	for i in nm.size():
		# the triangles are clockwise from the front, so the cross product points inward: flip
		nm[i] = -nm[i].normalized() if nm[i].length() > 1.0e-14 else Vector3(0, 0, 1)
	return nm


static func mask_mesh(d: Dictionary, verts: PackedVector3Array, skin: Color = SKIN) -> ArrayMesh:
	var rim: PackedByteArray = d["rim"]
	var tint: PackedFloat32Array = d["tint"]
	var col := PackedColorArray()
	col.resize(verts.size())
	var ink := Color(0.18, 0.16, 0.18)
	var lipc := Color(0.74, 0.40, 0.44)
	var lidc := Color(0.62, 0.50, 0.52)
	var chkc := Color(0.86, 0.60, 0.60)
	for i in verts.size():
		var c := skin
		c = c.lerp(chkc, 0.14 * tint[i * 4 + 3])
		c = c.lerp(lidc, 0.22 * tint[i * 4 + 2])
		c = c.lerp(lipc, 0.55 * tint[i * 4])
		c = c.lerp(ink, 0.85 * tint[i * 4 + 1])
		if rim[i] == 1 or rim[i] == 2:
			c = skin.lerp(ink, 0.7)
		elif rim[i] == 3:
			c = lipc.lerp(ink, 0.55)
		col[i] = c
	var ar := []
	ar.resize(Mesh.ARRAY_MAX)
	ar[Mesh.ARRAY_VERTEX] = verts
	ar[Mesh.ARRAY_NORMAL] = _normals(verts, d["tris"])
	ar[Mesh.ARRAY_COLOR] = col
	ar[Mesh.ARRAY_INDEX] = d["tris"]
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ar)
	return am


## a closed ellipsoid: r = the radii (x, y, z), +Z the front pole. Shared vertices (no seam), 2 poles; clockwise from outside
static func _sphere_arrays(r: Vector3, nlat: int, nlon: int, paint: bool, rad: float) -> Array:
	var vs := PackedVector3Array()
	var col := PackedColorArray()
	var ix := PackedInt32Array()
	vs.append(Vector3(0, 0, r.z))
	for i in range(1, nlat):
		var a := PI * i / nlat
		for j in nlon:
			var ph := TAU * j / nlon
			vs.append(Vector3(r.x * sin(a) * cos(ph), r.y * sin(a) * sin(ph), r.z * cos(a)))
	vs.append(Vector3(0, 0, -r.z))
	var last := vs.size() - 1
	for j in nlon:
		ix.append_array([0, 1 + (j + 1) % nlon, 1 + j])
	for i in range(0, nlat - 2):
		for j in nlon:
			var a0 := 1 + i * nlon + j
			var a1 := 1 + i * nlon + (j + 1) % nlon
			var b0 := 1 + (i + 1) * nlon + j
			var b1 := 1 + (i + 1) * nlon + (j + 1) % nlon
			ix.append_array([a0, a1, b0, a1, b1, b0])
	for j in nlon:
		var a0 := 1 + (nlat - 2) * nlon + j
		var a1 := 1 + (nlat - 2) * nlon + (j + 1) % nlon
		ix.append_array([a0, a1, last])
	# orient: front faces clockwise (cross . outward < 0)
	for t in range(0, ix.size() - 2, 3):
		var cr := (vs[ix[t + 1]] - vs[ix[t]]).cross(vs[ix[t + 2]] - vs[ix[t]])
		var cen := (vs[ix[t]] + vs[ix[t + 1]] + vs[ix[t + 2]]) / 3.0
		if cr.dot(cen) > 0.0:
			var tmp := ix[t + 1]
			ix[t + 1] = ix[t + 2]
			ix[t + 2] = tmp
	col.resize(vs.size())
	for i in vs.size():
		var c := Color(0.93, 0.92, 0.90)
		if paint:
			var ang := rad_to_deg(acos(clampf(vs[i].z / r.z, -1.0, 1.0)))
			var ir := rad_to_deg(asin(clampf(0.0061 / rad, 0.0, 1.0)))   # the iris, 12.2 mm across
			var pu := rad_to_deg(asin(clampf(0.0021 / rad, 0.0, 1.0)))   # the pupil, 4.2 mm
			if ang < pu:
				c = Color(0.03, 0.03, 0.04)
			elif ang < ir:
				c = Color(0.55, 0.40, 0.18).lerp(Color(0.30, 0.20, 0.10), _ss(ir * 0.6, ir, ang))
		col[i] = c
	var ar := []
	ar.resize(Mesh.ARRAY_MAX)
	ar[Mesh.ARRAY_VERTEX] = vs
	var nm := PackedVector3Array()
	nm.resize(vs.size())
	for i in vs.size():
		nm[i] = Vector3(vs[i].x / (r.x * r.x), vs[i].y / (r.y * r.y), vs[i].z / (r.z * r.z)).normalized()
	ar[Mesh.ARRAY_NORMAL] = nm
	ar[Mesh.ARRAY_COLOR] = col
	ar[Mesh.ARRAY_INDEX] = ix
	return ar


static func eye_arrays(radius: float) -> Array:
	return _sphere_arrays(Vector3(radius, radius, radius), 36, 40, true, radius)


static func eye_mesh(radius: float) -> ArrayMesh:
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, eye_arrays(radius))
	return am


## the dark inside of the mouth (and the throat seen when the jaw drops): a closed ellipsoid in head space, placed by d["cavity"]
static func cavity_mesh(d: Dictionary) -> ArrayMesh:
	var cv: Dictionary = d["cavity"]
	var r: Vector3 = cv["r"]
	var ar := _sphere_arrays(r, 16, 24, false, 0.01)
	var vs: PackedVector3Array = ar[Mesh.ARRAY_VERTEX]
	for i in vs.size():
		vs[i] += cv["c"]
	ar[Mesh.ARRAY_VERTEX] = vs
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ar)
	return am


## a copy of a head mesh with the triangles of the lower face (below the mouth, in front) removed, so the jaw of the mask can open
## without a second chin staying behind. Every array (bones, weights) and the materials are kept.
static func cut_head(mesh: ArrayMesh, d: Dictionary) -> ArrayMesh:
	var cut: Dictionary = d["cut"]
	var out := ArrayMesh.new()
	for si in mesh.get_surface_count():
		var ar := mesh.surface_get_arrays(si)
		var vs: PackedVector3Array = ar[Mesh.ARRAY_VERTEX]
		var ix: PackedInt32Array = ar[Mesh.ARRAY_INDEX] if ar[Mesh.ARRAY_INDEX] != null and (ar[Mesh.ARRAY_INDEX] as PackedInt32Array).size() > 0 else PackedInt32Array()
		if ix.is_empty():
			ix = PackedInt32Array()
			for i in vs.size():
				ix.append(i)
		var keep := PackedInt32Array()
		for t in range(0, ix.size() - 2, 3):
			var c := (vs[ix[t]] + vs[ix[t + 1]] + vs[ix[t + 2]]) / 3.0
			if c.y < float(cut["y_max"]) and absf(c.x) < float(cut["x_max"]) and c.z > float(cut["z_min"]):
				continue
			keep.append_array([ix[t], ix[t + 1], ix[t + 2]])
		ar[Mesh.ARRAY_INDEX] = keep
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ar)
		var mat := mesh.surface_get_material(si)
		if mat != null:
			out.surface_set_material(out.get_surface_count() - 1, mat)
	return out
