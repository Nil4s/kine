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
const AUS := ["AU1", "AU4", "AU6", "AU10", "AU12", "AU16", "AU18", "AU20", "AU22", "AU23", "AU24", "AU26", "AU28", "AU45"]   # AU25 (lips part) is the lens of posed()
const VISEMES := ["rest", "A", "E", "I", "O", "U", "MBP", "FV", "L", "TH"]
const JAW_MAX_DEG := 27.5
const LIP_ARCH := 0.0036        # m x s: the upper lip's arch when the lips part (AU25)
const LIP_TUCK := 0.0042        # m x s: the lower lip rises toward the incisors by this much per unit jaw fraction
const LIP_PULL := 0.0018        # m x s: each mouth corner draws in by this much per unit jaw fraction
const H := 0.001               # m: the lattice
const MASK_OFF := 0.002        # m: the mask stands this far proud of the head skin
const GLOBE_PROUD := 0.0035    # m: the front pole of an eyeball stands this far in front of the skin plane
const LID_GAIN_UP := 0.5
const LID_GAIN_LO := 0.15
const LID_T := 0.0012           # m: the lid is this thick: every mask vertex stands >= this far outside the globe sphere
const FEATHER_LAYERS := 12.0   # the mask rises from the skin (0 mm at the rim) to MASK_OFF over this many 1 mm layers
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
static func _hf_make(pts: PackedVector3Array, x0: float, y0: float, x1: float, y1: float, res: float, blur: bool = true) -> Dictionary:
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
	if not blur:
		return {"z": z, "nx": nx, "ny": ny, "x0": x0, "y0": y0, "res": res}
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


## the jaw weight at (x, y): hard between the lips, smooth round the corners, fading to 0 at the footprint's side. Used by the mask and by
## the chin part, so the two rotate alike at their seam
static func _jaw_w(x: float, y: float, my: float) -> float:
	var lip_hard := 0.0262
	var ax := absf(x)
	var dym := y - my
	var wx := 1.0 - _ss(0.026, 0.050, ax)
	var wy := 1.0 if dym < -1.0e-9 else (0.5 if absf(dym) <= 1.0e-9 else 0.0)
	if dym < -1.0e-9:
		# the lower lip lifts toward the corners, so an open mouth is a lens, not a box
		wy = 1.0 - 0.65 * _ss(0.010, 0.026, ax) * (1.0 - _ss(0.004, 0.010, absf(dym)))
	var wys := _ss(0.0, 1.0, clampf((my + 0.010 - y) / 0.020, 0.0, 1.0))
	var bl := _ss(lip_hard, 0.031, ax)
	return lerpf(wy, wys, bl) * (1.0 if ax < lip_hard else wx)


## ---- BUILD
static func build(head_pts: PackedVector3Array, anchors_in: Dictionary = {}, opts: Dictionary = {}) -> Dictionary:
	var smooth_rim: bool = bool(opts.get("smooth_rim", true))
	var feather: bool = bool(opts.get("feather", true))
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
	var ax := 0.074
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

	# the outer rim: the footprint is a lattice staircase; smooth the rim loop in the face plane (Jacobi, 1/4-1/2-1/4, 60 passes;
	# topology unchanged: same vertices, same triangles)
	if smooth_rim:
		var ecnt := {}
		for t in range(0, tris.size() - 2, 3):
			for e in 3:
				var ea0 := tris[t + e]
				var eb0 := tris[t + (e + 1) % 3]
				var ek := Vector2i(mini(ea0, eb0), maxi(ea0, eb0))
				ecnt[ek] = int(ecnt.get(ek, 0)) + 1
		var rn := {}
		for ek in ecnt:
			if int(ecnt[ek]) != 1:
				continue
			var k2: Vector2i = ek
			if rim[k2.x] != 0 or rim[k2.y] != 0 or outer[k2.x] != 1 or outer[k2.y] != 1:
				continue
			if not rn.has(k2.x):
				rn[k2.x] = []
			if not rn.has(k2.y):
				rn[k2.y] = []
			(rn[k2.x] as Array).append(k2.y)
			(rn[k2.y] as Array).append(k2.x)
		for it in 60:
			var nxt := {}
			for v in rn:
				var nb: Array = rn[v]
				if nb.size() != 2:
					continue
				var q := verts[v]
				var a2 := verts[nb[0]]
				var b2 := verts[nb[1]]
				nxt[v] = Vector2(0.5 * q.x + 0.25 * (a2.x + b2.x), 0.5 * q.y + 0.25 * (a2.y + b2.y))
			for v in nxt:
				var xy: Vector2 = nxt[v]
				verts[v] = Vector3(xy.x, xy.y, verts[v].z)

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
	var lip_lift := PackedFloat32Array()   # per vertex, per unit jaw fraction: the upper lip's arch (dy, m) and the roll round the opening (dz)
	lip_lift.resize(nv)
	var lip_roll := PackedFloat32Array()
	lip_roll.resize(nv)
	var lip_pull := PackedFloat32Array()   # per vertex, per unit jaw fraction: the corners draw in (the mouth narrows a little when the jaw drops)
	lip_pull.resize(nv)
	var lip_hard := 0.0262
	for v in nv:
		var p := verts[v]
		var zb := _zsym(hf, p.x, p.y)
		var zact := _hz(hf, p.x, p.y)
		if zb > -1.0e8 and zact > -1.0e8:
			zb = lerpf(zb, zact, _ss(0.050, 0.060, absf(p.x)))   # at the sides the rim follows THIS head's surface (it is not exactly symmetric)
		if zb < -1.0e8:
			zb = zf - 0.03
		var t := clampf(float(depth[v]) / 6.0, 0.0, 1.0)
		var off := lerpf(-0.0012, MASK_OFF, _ss(0.0, 1.0, t))
		if feather:
			off = MASK_OFF * _ss(0.0, 1.0, clampf(float(depth[v]) / FEATHER_LAYERS, 0.0, 1.0))   # 0 at the rim: the skin itself
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
			var rg2 := gr + LID_T
			if rr2 < rg2 * rg2:
				z = maxf(z, c.z + sqrt(rg2 * rg2 - rr2))   # a sphere gr + lid thickness: every vertex >= 1.2 mm outside the globe
		verts[v] = Vector3(p.x, p.y, z)
		region[v] = reg
		# the open mouth is a lens, not a box: the upper lip arches up in the middle (cupid's bow stretched), both lips roll back
		# round the opening (the rim turns into the mouth)
		var axm := absf(p.x)
		var arch := maxf(1.0 - (axm / 0.026) * (axm / 0.026), 0.0)
		if dym > 0.0:
			lip_lift[v] = LIP_ARCH * s * arch * (1.0 - _ss(0.0, 0.007, dym))
		else:
			# the lower lip tucks up toward the lower incisors as the mouth opens: the lips follow the teeth, not the whole chin
			lip_lift[v] = LIP_TUCK * s * (1.0 - _ss(0.0, 0.006, -dym)) * (1.0 - _ss(0.012, 0.026, axm))
		lip_pull[v] = -signf(p.x) * LIP_PULL * s * _ss(0.012, 0.026, axm) * (1.0 - _ss(0.026, 0.040, axm)) * (1.0 - _ss(0.004, 0.014, absf(dym)))
		lip_roll[v] = -0.0030 * s * (1.0 - _ss(0.0, 0.005, absf(dym))) * (1.0 - _ss(0.020, 0.027, axm))
		var ab2 := absf(p.x)
		var yb2 := by + 0.004 - 0.012 * ((ab2 - 0.026) / 0.022) * ((ab2 - 0.026) / 0.022)
		var el := sqrt((p.x / 0.0275) * (p.x / 0.0275) + (dym / 0.0078) * (dym / 0.0078))
		var tf := _ss(0.0, 1.0, clampf(float(depth[v]) / 8.0, 0.0, 1.0))   # every tint fades out at the rim: the brow does not run off the edge
		tint[v * 4] = (1.0 - _ss(0.7, 1.0, el)) * tf
		tint[v * 4 + 1] = (1.0 - _ss(0.5, 1.0, absf(p.y - yb2) / 0.0045)) * (1.0 - _ss(0.040, 0.050, ab2)) * _ss(0.003, 0.009, ab2) * _ss(6.0, 12.0, float(depth[v]))
		tint[v * 4 + 2] = lid_g[v]
		var cd := Vector2((ab2 - 0.032) / 0.022, (p.y - (cy - 0.026)) / 0.020).length()
		tint[v * 4 + 3] = (1.0 - _ss(0.4, 1.0, cd)) * tf
		jaw_w[v] = _jaw_w(p.x, p.y, my)

	# ---- the blendshapes
	var au := {}
	var d1 := PackedVector3Array()
	var d4 := PackedVector3Array()
	var d6 := PackedVector3Array()
	var d12 := PackedVector3Array()
	var d26 := PackedVector3Array()
	var d45 := PackedVector3Array()
	var d10 := PackedVector3Array()
	d10.resize(nv)
	var d16 := PackedVector3Array()
	d16.resize(nv)
	var d18 := PackedVector3Array()
	d18.resize(nv)
	var d20 := PackedVector3Array()
	d20.resize(nv)
	var d22 := PackedVector3Array()
	d22.resize(nv)
	var d23 := PackedVector3Array()
	d23.resize(nv)
	var d24 := PackedVector3Array()
	d24.resize(nv)
	var d28 := PackedVector3Array()
	d28.resize(nv)
	d1.resize(nv)
	d4.resize(nv)
	d6.resize(nv)
	d12.resize(nv)
	d26.resize(nv)
	d45.resize(nv)
	# the lid's z at AU45 = 0.25, 0.5, 0.75, 1: the sphere is not linear, so a half blink needs its own z
	var bz1 := PackedFloat32Array()
	var bz2 := PackedFloat32Array()
	var bz3 := PackedFloat32Array()
	var bz4 := PackedFloat32Array()
	bz1.resize(nv)
	bz2.resize(nv)
	bz3.resize(nv)
	bz4.resize(nv)
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
		# the mouth AUs of the visemes (FACS, Ekman, Friesen & Hager 2002). Profiles: cen = central (the mid 20 mm), nr = near the slit
		# vertically, cor = the corner zone; the upper and the lower lip are separate sheets (the slit rows are +- 0.3 mm)
		var dyv := p.y - my
		var adv := absf(dyv)
		var up_s := 1.0 if dyv > 0.0 else 0.0
		var lo_s := 1.0 - up_s
		var cen := 1.0 - _ss(0.010, 0.024, ab)
		var nr := 1.0 - _ss(0.0, 0.012, adv)
		var nr2 := 1.0 - _ss(0.008, 0.018, adv)
		var cor := _ss(0.012, 0.026, ab) * (1.0 - _ss(0.030, 0.042, ab))
		var cor2 := _ss(0.008, 0.026, ab) * (1.0 - _ss(0.026, 0.038, ab))
		var fwd := (1.0 - _ss(0.012, 0.030, ab)) * (1.0 - _ss(0.006, 0.016, adv))
		d10[v] = Vector3(0.0, 0.0035 * s * up_s * cen * nr, 0.0005 * up_s * cen * nr)
		d16[v] = Vector3(0.0, -0.0045 * s * lo_s * cen * nr, 0.0)
		d18[v] = Vector3(-sx * 0.0095 * s * cor2 * nr2, 0.0, 0.0095 * s * fwd)
		d22[v] = Vector3(-sx * 0.0030 * s * cor2 * nr2, 0.0030 * s * (up_s - lo_s) * cen * nr, 0.0045 * s * fwd)
		d20[v] = Vector3(sx * 0.0055 * s * cor * nr2, 0.0, -0.0020 * s * cor * nr2)
		d23[v] = Vector3(-sx * 0.0020 * s * cor2 * nr2, 0.0, -0.0010 * s * cen * (1.0 - _ss(0.004, 0.012, adv)))
		# AU24 presses the lips together: the two rim rows (+- 0.3 mm) meet exactly (the pressure fades over 4 mm)
		var prs := (1.0 - _ss(0.029, 0.036, ab)) * (1.0 - _ss(0.0003, 0.004, adv))
		d24[v] = Vector3(-sx * 0.0012 * s * cor2 * nr2, -0.0003 * prs * (up_s - lo_s), -0.0010 * s * cen * (1.0 - _ss(0.004, 0.012, adv)))
		# AU28 lip suck (the lower lip): back to the incisors and up to their edge
		var suck := lo_s * (1.0 - _ss(0.008, 0.020, ab)) * (1.0 - _ss(0.0003, 0.014, adv))
		d28[v] = Vector3(0.0, 0.0010 * suck, -0.0095 * s * suck)
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
				dv6.z += _ride(c, gr, p, p.y + 0.0022 * g)
			# the lid RIDES the globe: its z at the moved y is the globe sphere (radius + lid thickness) where that is in front of
			# where the lid stood, so no globe pixel can show (finding 3 of the L18 review)
			d45[v] = Vector3(0.0, dy, _ride(c, gr, p, p.y + dy))
			var zq := PackedFloat32Array()
			for kq in 4:
				zq.append(_ride(c, gr, p, p.y + dy * float(kq + 1) * 0.25))
			bz1[v] = zq[0]
			bz2[v] = zq[1]
			bz3[v] = zq[2]
			bz4[v] = zq[3]
		d6[v] = dv6
	# the margins close onto ONE z: the upper and the lower margin vertex of a column end at the same point
	var pair := {}
	for v in nv:
		if (rim[v] == 1 or rim[v] == 2) and lid_g[v] > 0.0:
			var key := Vector3i(rim[v], int(round(verts[v].x * 100000.0)), 0)
			if not pair.has(key):
				pair[key] = []
			(pair[key] as Array).append(v)   # the corner columns are clamped onto one x: a group, not a pair
	for key in pair:
		var grp: Array = pair[key]
		if grp.size() >= 2:
			var zc := -1.0e9
			for v2 in grp:
				zc = maxf(zc, verts[v2].z + d45[v2].z)
			for v2 in grp:
				d45[v2] = Vector3(0.0, d45[v2].y, zc - verts[v2].z)
				bz4[v2] = zc - verts[v2].z
	var blink_z := [bz1, bz2, bz3, bz4]
	au["AU1"] = d1
	au["AU4"] = d4
	au["AU6"] = d6
	au["AU12"] = d12
	au["AU26"] = d26
	au["AU45"] = d45
	au["AU10"] = d10
	au["AU16"] = d16
	au["AU18"] = d18
	au["AU20"] = d20
	au["AU22"] = d22
	au["AU23"] = d23
	au["AU24"] = d24
	au["AU28"] = d28

	var nose := _nose(hf, s, my)
	var ears := _ears(head_pts, an, s)
	var cutd := {"y_max": my + 0.012, "x_max": 0.072, "z_min": zs_m - 0.06}
	var chin_d := _chin_data(head_pts, verts, cutd, my)
	return {"ears": ears, "chin": chin_d, "anchors": an, "scale": s, "verts": verts, "blink_z": blink_z, "lip_lift": lip_lift, "lip_roll": lip_roll, "lip_pull": lip_pull, "nose": nose, "tris": tris, "region": region, "jaw_w": jaw_w, "rim": rim,
		"lid_gain": lid_gain, "tint": tint, "au": au, "eyes": eyes, "eye_r": gr,
		"bones": {"head": {"o": Vector3.ZERO, "parent": ""}, "jaw": {"o": hinge, "parent": "head"},
			"eye_l": {"o": (eyes[0] as Dictionary)["c"], "parent": "head"}, "eye_r": {"o": (eyes[1] as Dictionary)["c"], "parent": "head"}},
		"teeth_up": teeth_up, "teeth_lo": teeth_up,
		"cavity": {"c": Vector3(0.0, my - 0.018, zs_m - 0.030), "r": Vector3(0.031 * s, 0.033 * s, 0.030), "vest": {"c": Vector3(0.0, my - 0.002, zs_m - 0.028), "r": Vector3(0.043 * s, 0.018, 0.030)}},
		"cut": cutd}



## ---- L23: THE EARS. A simple ear (helix, antihelix, lobe) on each side of the head, from anthropometry: length 60 mm x s (Farkas 1994,
## FROM MEMORY: ear length 59-63 mm, width 32-35 mm), the top at brow level, the front edge about 85 mm x s behind the eye (tragion to
## ectocanthus, from memory), the long axis leaning back 10 deg, the rear rim standing ~15 mm off the head (ears flare 20-30 deg).
## A polar grid (rings x angles) over the ear outline: the height above the head's own side surface is a tilted plane plus a dome, the
## helix ridge on the rim, the antihelix ridge inside it (upper rear), the concha dip, the tragus bump; the lobe is a fleshy dome with
## no rim. The rim ring is joined to a skirt ring just under the head's skin, so the ear is a shell standing ON the head. The side
## surface is the average of the two sides (the head is not exactly symmetric), so the two ears mirror exactly.
static func _ears(head_pts: PackedVector3Array, an: Dictionary, s: float) -> Array:
	var by := float((an["brow_l"] as Vector3).y)
	var ez := float((an["eye_l"] as Vector3).z)
	var swl := PackedVector3Array()
	var swr := PackedVector3Array()
	for v in head_pts:
		swl.append(Vector3(v.z, v.y, v.x))
		swr.append(Vector3(v.z, v.y, -v.x))
	var hl := _hf_make(swl, -0.080, by - 0.12, 0.080, by + 0.04, 0.001, false)
	var hr := _hf_make(swr, -0.080, by - 0.12, 0.080, by + 0.04, 0.001, false)
	var ep := {"cy": by - 0.030 * s, "cz": ez - 0.085 * s - 0.0165 * s, "ay": 0.030 * s, "b": 0.0165 * s}
	var e: Dictionary = {}
	for it in 5:
		e = _ear_build(hl, hr, ep, s)
		var vs: PackedVector3Array = e["verts"]
		var mn := Vector3(9, 9, 9)
		var mx := Vector3(-9, -9, -9)
		for v in vs:
			mn = Vector3(minf(mn.x, v.x), minf(mn.y, v.y), minf(mn.z, v.z))
			mx = Vector3(maxf(mx.x, v.x), maxf(mx.y, v.y), maxf(mx.z, v.z))
		ep["ay"] = float(ep["ay"]) * 0.060 * s / (mx.y - mn.y)
		ep["b"] = float(ep["b"]) * 0.033 * s / (mx.z - mn.z)
		ep["cy"] = float(ep["cy"]) + (by - mx.y)
		ep["cz"] = float(ep["cz"]) + (ez - 0.085 * s - mx.z)
	e = _ear_build(hl, hr, ep, s)
	var vl: PackedVector3Array = e["verts"]
	var tl: PackedInt32Array = e["tris"]
	var vr := PackedVector3Array()
	for v in vl:
		vr.append(Vector3(-v.x, v.y, v.z))
	var tr := PackedInt32Array()
	for t in range(0, tl.size() - 2, 3):
		tr.append_array([tl[t], tl[t + 2], tl[t + 1]])   # a mirror flips the winding
	return [{"side": "l", "verts": vl, "tris": tl, "col": e["col"]}, {"side": "r", "verts": vr, "tris": tr, "col": e["col"]}]


static func _g(r: float, c: float, w: float) -> float:
	return exp(-((r - c) / w) * ((r - c) / w))


static func _ear_build(hl: Dictionary, hr: Dictionary, ep: Dictionary, s: float) -> Dictionary:
	var nr := 24
	var na := 64
	var cy := float(ep["cy"])
	var cz := float(ep["cz"])
	var ay := float(ep["ay"])
	var bb := float(ep["b"])
	var tilt := deg_to_rad(10.0)
	var vs := PackedVector3Array()
	var col := PackedColorArray()
	var skirt0 := 1 + nr * na
	for i in 1 + nr * na + na:
		vs.append(Vector3.ZERO)
		col.append(Color(1, 1, 1))
	for k in range(0, nr + 1):
		var rho := float(k) / float(nr)
		for j in (1 if k == 0 else na):
			var th := TAU * float(j) / float(na)
			var xn := rho * cos(th)
			var yn := rho * sin(th)
			var wf := 1.0 - 0.30 * _ss(-0.1, -1.0, yn) - 0.08 * _ss(0.5, 1.0, yn)
			var xl := bb * xn * wf
			var yl := ay * yn
			var z := cz + xl * cos(tilt) - yl * sin(tilt)
			var y := cy + xl * sin(tilt) + yl * cos(tilt)
			var a := _hz(hl, z, y)
			var b := _hz(hr, z, y)
			var hsf := 0.07
			if a > -1.0e8 and b > -1.0e8:
				hsf = 0.5 * (a + b)
			elif a > -1.0e8:
				hsf = a
			elif b > -1.0e8:
				hsf = b
			var lobe := _ss(-0.35, -0.85, yn)
			var rear := clampf((1.0 - xn) * 0.5, 0.0, 1.0)
			var plane := (0.001 + 0.012 * s * _ss(-1.0, 1.0, -xn)) * (1.0 - 0.4 * lobe)
			var dome := pow(maxf(1.0 - rho * rho, 0.0), 0.6) * (0.004 * s * (1.0 - lobe) + 0.008 * s * lobe)
			var helix := _g(rho, 0.86, 0.075) * 0.0045 * s * (1.0 - lobe)
			var anti := _g(rho, 0.52, 0.09) * 0.0035 * s * _ss(-0.5, 0.2, yn) * (0.4 + 0.6 * rear)
			var cdist := Vector2(xn - 0.1, yn + 0.15).length()
			var conch := -0.004 * s * (1.0 - _ss(0.1, 0.35, cdist))
			var trag := 0.003 * s * exp(-pow(Vector2(xn - 0.80, yn + 0.12).length() / 0.12, 2.0))
			var hh := maxf(plane + dome + helix + anti + conch + trag, 0.0015)
			var idx := 0 if k == 0 else 1 + (k - 1) * na + j
			vs[idx] = Vector3(hsf + hh, y, z)
			col[idx] = Color(1, 1, 1).lerp(Color(0.93, 0.74, 0.76), 0.55 * (1.0 - _ss(0.1, 0.45, cdist)))
			if k == nr:
				vs[skirt0 + j] = Vector3(hsf - 0.0008, y, z)
	var tl := []
	for j in na:
		tl.append([0, 1 + j, 1 + (j + 1) % na])
	for k in range(1, nr):
		for j in na:
			var j2 := (j + 1) % na
			var a0 := 1 + (k - 1) * na + j
			var a1 := 1 + (k - 1) * na + j2
			var b0 := 1 + k * na + j
			var b1 := 1 + k * na + j2
			tl.append([a0, b0, a1])
			tl.append([a1, b0, b1])
	var rim0 := 1 + (nr - 1) * na
	for j in na:
		var j2 := (j + 1) % na
		tl.append([rim0 + j, skirt0 + j, rim0 + j2])
		tl.append([rim0 + j2, skirt0 + j, skirt0 + j2])
	# the winding is by construction: (radial x tangential) points into the head for the left ear = clockwise from outside
	var tris := PackedInt32Array()
	for t in tl:
		tris.append_array([t[0], t[1], t[2]])
	return {"verts": vs, "tris": tris, "col": col}


static func ear_mesh(d: Dictionary, side: int, skin: Color = SKIN) -> ArrayMesh:
	var e: Dictionary = (d["ears"] as Array)[side]
	var vs: PackedVector3Array = e["verts"]
	var cl: PackedColorArray = e["col"]
	var col := PackedColorArray()
	col.resize(vs.size())
	for i in vs.size():
		col[i] = Color(skin.r * cl[i].r, skin.g * cl[i].g, skin.b * cl[i].b, 1.0)
	var ar := []
	ar.resize(Mesh.ARRAY_MAX)
	ar[Mesh.ARRAY_VERTEX] = vs
	ar[Mesh.ARRAY_NORMAL] = _normals(vs, e["tris"])
	ar[Mesh.ARRAY_COLOR] = col
	ar[Mesh.ARRAY_INDEX] = e["tris"]
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ar)
	return am


## the static extra parts riding the head: [{"name", "mesh"}] (the ears). The chin rides the jaw: chin_mesh()
static func head_parts(d: Dictionary, skin: Color = SKIN) -> Array:
	return [{"name": "ear_l", "mesh": ear_mesh(d, 0, skin)}, {"name": "ear_r", "mesh": ear_mesh(d, 1, skin)}]


## ---- L23: THE CHIN. cut_head() removes the head's lower front (so the mask's jaw can open without a second chin staying behind), but the
## mask only covers it down to 12 mm over the chin: the chin tip, the jaw line and the underside were a hole (a low camera saw into the
## head). The removed triangles that the mask does NOT cover (nothing of the mask within 4 mm over / beside them) are kept here as a
## piece of skin that rides the jaw: each vertex turns about the hinge by the jaw weight of the mask at the same (x, y) (so the two
## sheets turn alike at their seam) times a fade to 0 toward the back of the cut (z), where it meets the static head again.
static func _chin_data(head_pts: PackedVector3Array, mverts: PackedVector3Array, cutd: Dictionary, my: float) -> Dictionary:
	var ymn := {}     # x bin (2 mm) -> the lowest mask y
	var xmx := {}     # y bin (1 mm) -> the largest mask |x|
	for v in mverts:
		var kx := int(floor((v.x + 0.2) / 0.002))
		if not ymn.has(kx) or v.y < float(ymn[kx]):
			ymn[kx] = v.y
		var ky := int(floor((v.y - 1.0) / 0.001))
		if not xmx.has(ky) or absf(v.x) > float(xmx[ky]):
			xmx[ky] = absf(v.x)
	var keyd := {}
	var vs := PackedVector3Array()
	var ix := PackedInt32Array()
	for t in range(0, head_pts.size() - 2, 3):
		var a := head_pts[t]
		var b := head_pts[t + 1]
		var c := head_pts[t + 2]
		var cc := (a + b + c) / 3.0
		if not (cc.y < float(cutd["y_max"]) and absf(cc.x) < float(cutd["x_max"]) and cc.z > float(cutd["z_min"])):
			continue
		var covered := true
		for q in [a, b, c]:
			var qv: Vector3 = q
			var kx := int(floor((qv.x + 0.2) / 0.002))
			var ky := int(floor((qv.y - 1.0) / 0.001))
			if not (ymn.has(kx) and xmx.has(ky)) or qv.y < float(ymn[kx]) + 0.004 or absf(qv.x) > float(xmx[ky]) - 0.004:
				covered = false
				break
		if covered:
			continue
		for q in [a, b, c]:
			var qv2: Vector3 = q
			var key := Vector3i(int(round(qv2.x * 20000.0)), int(round(qv2.y * 20000.0)), int(round(qv2.z * 20000.0)))
			if not keyd.has(key):
				keyd[key] = vs.size()
				vs.append(qv2)
			ix.append(int(keyd[key]))
	var w := PackedFloat32Array()
	w.resize(vs.size())
	for i in vs.size():
		w[i] = _jaw_w(vs[i].x, vs[i].y, my) * _ss(float(cutd["z_min"]), float(cutd["z_min"]) + 0.040, vs[i].z)
	return {"verts": vs, "tris": ix, "w": w}


## the chin part's mesh for a state (the jaw bone's angle plus the AU26 blendshape, weighted like the mask's jaw)
static func chin_mesh(d: Dictionary, st: Dictionary, skin: Color = SKIN) -> ArrayMesh:
	var cd: Dictionary = d["chin"]
	var v0: PackedVector3Array = cd["verts"]
	var w: PackedFloat32Array = cd["w"]
	var hinge: Vector3 = d["bones"]["jaw"]["o"]
	var au: Dictionary = st.get("au", {})
	var a26 := float(au.get("AU26", 0.0))
	var jd := deg_to_rad(float(st.get("jaw_deg", 0.0)))
	var th := deg_to_rad(JAW_MAX_DEG)
	var vs := PackedVector3Array()
	vs.resize(v0.size())
	for i in v0.size():
		var rel := v0[i] - hinge
		if a26 != 0.0 and w[i] > 0.0:
			var a := th * w[i]
			rel += (Vector3(rel.x, rel.y * cos(a) - rel.z * sin(a), rel.y * sin(a) + rel.z * cos(a)) - rel) * a26
		if jd != 0.0 and w[i] > 0.0:
			var b := jd * w[i]
			rel = Vector3(rel.x, rel.y * cos(b) - rel.z * sin(b), rel.y * sin(b) + rel.z * cos(b))
		vs[i] = hinge + rel
	var col := PackedColorArray()
	col.resize(vs.size())
	col.fill(skin)
	var ar := []
	ar.resize(Mesh.ARRAY_MAX)
	ar[Mesh.ARRAY_VERTEX] = vs
	ar[Mesh.ARRAY_NORMAL] = _normals(vs, cd["tris"])
	ar[Mesh.ARRAY_COLOR] = col
	ar[Mesh.ARRAY_INDEX] = cd["tris"]
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ar)
	return am


## the dz a lid vertex p needs to stand at height ny: where the globe sphere (radius + the lid thickness) is in front of it there, the
## vertex goes to the sphere; elsewhere (outside the disc, or the skin already in front) 0
static func _ride(c: Vector3, gr: float, p: Vector3, ny: float) -> float:
	var rg := gr + LID_T
	var r2 := (p.x - c.x) * (p.x - c.x) + (ny - c.y) * (ny - c.y)
	if r2 >= rg * rg:
		return 0.0
	return maxf(p.z, c.z + sqrt(rg * rg - r2)) - p.z


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
		if k == "AU45" and d.has("blink_z"):
			var bzt: Array = d["blink_z"]
			var fq := clampf(w, 0.0, 1.0) * 4.0
			var q0 := mini(int(floor(fq)), 3)
			var fr := fq - float(q0)
			for i in n:
				var za := 0.0 if q0 == 0 else float((bzt[q0 - 1] as PackedFloat32Array)[i])
				var zb2 := float((bzt[q0] as PackedFloat32Array)[i])
				v[i] += Vector3(0.0, dl[i].y * w, lerpf(za, zb2, fr))
			continue
		for i in n:
			v[i] += dl[i] * w
	# the open-mouth lens and the lip roll follow the jaw fraction (AU26 weight + the jaw bone's angle), linear in it
	# AU25 (lips part, FACS) = the lens and the roll; the jaw bone's angle brings it along (a jaw that opens parts the lips). AU26 alone
	# (the jaw-drop blendshape) leaves the upper lip still: its own bar in tests/face_geo_test.gd.
	var jf := float(au.get("AU25", 0.0)) + float(st.get("jaw_deg", 0.0)) / JAW_MAX_DEG
	var lsh := float(st.get("lip_shape", 1.0))
	if jf != 0.0 and lsh != 0.0:
		var ll: PackedFloat32Array = d["lip_lift"]
		var lr: PackedFloat32Array = d["lip_roll"]
		var lpl: PackedFloat32Array = d["lip_pull"]
		for i in n:
			if ll[i] != 0.0 or lr[i] != 0.0 or lpl[i] != 0.0:
				v[i] += Vector3(lpl[i], ll[i], lr[i]) * (jf * lsh)
	var pit := deg_to_rad(float(st.get("eye_pitch_deg", 0.0)))
	if pit != 0.0 and bool(st.get("lid_follow", true)):
		var lg: PackedFloat32Array = d["lid_gain"]
		var k := float(d["eye_r"]) * sin(pit) * (1.0 - clampf(float(au.get("AU45", 0.0)), 0.0, 1.0))   # a closed lid stays closed when the eye looks up
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
	var vs := PackedVector3Array()
	var col := PackedColorArray()
	var nmv := PackedVector3Array()
	var ix := PackedInt32Array()
	# the vault, and a flat vestibule right behind the lips (rays that enter the slit at a low angle must not leave through the vault's
	# side into the cut-away head: L23 low-camera bar)
	for part in [cv, cv.get("vest", {})]:
		if (part as Dictionary).is_empty():
			continue
		var pc: Vector3 = part["c"]
		var r: Vector3 = part["r"]
		var ar := _sphere_arrays(r, 16, 24, false, 0.01)
		var pv: PackedVector3Array = ar[Mesh.ARRAY_VERTEX]
		var pn: PackedVector3Array = ar[Mesh.ARRAY_NORMAL]
		var pi: PackedInt32Array = ar[Mesh.ARRAY_INDEX]
		var base := vs.size()
		for i in pv.size():
			var q := pv[i] + pc
			vs.append(q)
			nmv.append(-pn[i])   # lit from inside
			# seen from inside (the material culls the FRONT faces): the back wall is the lighter end, the rim of the oval the dark; deeper
			# red toward the throat, never a flat wall
			var rr := sqrt(pow((q.x - pc.x) / r.x, 2.0) + pow((q.y - pc.y) / r.y, 2.0))
			col.append(Color(0.56, 0.19, 0.22).lerp(Color(0.32, 0.09, 0.11), _ss(0.2, 1.0, rr)))
		for i in pi:
			ix.append(base + i)
	var ar2 := []
	ar2.resize(Mesh.ARRAY_MAX)
	ar2[Mesh.ARRAY_VERTEX] = vs
	ar2[Mesh.ARRAY_COLOR] = col
	ar2[Mesh.ARRAY_NORMAL] = nmv
	ar2[Mesh.ARRAY_INDEX] = ix
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ar2)
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


## ---- L18 FACE2: material, nose, teeth, tongue, jaw, visemes

## the mask's material IS the head's (same roughness, metallic, shading), its vertex colours read as sRGB (the default is LINEAR, which
## drew every colour brighter than the head's own albedo: the "bright plate" of the L18 review) and carry the skin colour
static func mask_material(hm: Material) -> StandardMaterial3D:
	var mm: StandardMaterial3D
	if hm is StandardMaterial3D:
		mm = (hm as StandardMaterial3D).duplicate() as StandardMaterial3D
	else:
		mm = StandardMaterial3D.new()
		mm.roughness = 0.8
	mm.albedo_color = Color(1, 1, 1)
	mm.albedo_texture = null
	mm.vertex_color_use_as_albedo = true
	mm.vertex_color_is_srgb = true
	return mm


static func eye_material() -> StandardMaterial3D:
	var em := StandardMaterial3D.new()
	em.vertex_color_use_as_albedo = true
	em.vertex_color_is_srgb = true
	em.roughness = 0.25
	return em


static func cavity_material() -> StandardMaterial3D:
	var cm := StandardMaterial3D.new()
	cm.vertex_color_use_as_albedo = true
	cm.vertex_color_is_srgb = true
	cm.roughness = 0.55
	cm.cull_mode = BaseMaterial3D.CULL_FRONT   # the inside of the oral vault, so the tongue and teeth stand IN it
	cm.emission_enabled = true
	cm.emission = Color(0.20, 0.05, 0.07)
	cm.emission_energy_multiplier = 1.0
	return cm


static func tooth_material() -> StandardMaterial3D:
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(1, 1, 1)
	tm.vertex_color_use_as_albedo = true   # cream crowns, pink gum (teeth_mesh)
	tm.vertex_color_is_srgb = true
	tm.roughness = 0.35
	return tm


static func tongue_material() -> StandardMaterial3D:
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.80, 0.36, 0.40)
	tm.roughness = 0.5
	tm.emission_enabled = true
	tm.emission = Color(0.25, 0.06, 0.08)
	tm.emission_energy_multiplier = 0.4
	return tm


## the jaw bone's transform about the hinge (head space) for a state: the lower teeth and the tongue ride it. The angle is the jaw
## bone's plus the AU26 weight's (the same rotation posed() gives the mask's jaw vertices)
static func jaw_transform(d: Dictionary, st: Dictionary) -> Transform3D:
	var au: Dictionary = st.get("au", {})
	var a := deg_to_rad(float(st.get("jaw_deg", 0.0)) + JAW_MAX_DEG * float(au.get("AU26", 0.0)))
	var h: Vector3 = d["bones"]["jaw"]["o"]
	var b := Basis(Vector3.RIGHT, a)
	return Transform3D(b, h - b * h)


## the viseme's AU weights (cheap wiring: the E shape is the lips drawn wide = AU12; M, A, O act through the jaw channel)
static func viseme_au(vname: String) -> Dictionary:
	return {"AU12": 0.6} if vname == "E" else {}


## L23: the full viseme set as a pose {"au": {...}, "jaw_deg": deg, "viseme": canonical name, "tongue": {"up", "fwd", "pitch"}}; {} for an
## unknown name. rest, A, E, I, O, U, MBP (M B P), FV (F V), L, TH; the lip-sync letters M B P F V and S (a fricative, drawn as I) map
## on them. The jaw is the viseme's own SPEECH jaw (a few degrees, nothing like the 27.5 deg of a yawn); in the app the lip sync's own
## jaw channel replaces it. Weights are artist's choices tuned until the measured aperture / width / protrusion sit in the ranges of
## tests/face_geo3_test.gd (Fromkin 1964, Linker 1982: from memory).
const VISEME_POSE := {
	"rest": {"au": {}, "jaw_deg": 0.0},
	"A": {"au": {"AU10": 0.3, "AU16": 0.4, "AU25": 0.2}, "jaw_deg": 10.0},
	"E": {"au": {"AU12": 0.6, "AU20": 0.35, "AU25": 0.25}, "jaw_deg": 4.0},
	"I": {"au": {"AU12": 0.4, "AU20": 0.8, "AU25": 0.2}, "jaw_deg": 2.5},
	"O": {"au": {"AU18": 0.55, "AU22": 0.7, "AU25": 0.2}, "jaw_deg": 6.0},
	"U": {"au": {"AU18": 1.0, "AU22": 0.25}, "jaw_deg": 2.5},
	"MBP": {"au": {"AU24": 1.0, "AU23": 0.15}, "jaw_deg": 0.0},
	"FV": {"au": {"AU10": 0.8, "AU28": 1.0}, "jaw_deg": 0.0},
	"L": {"au": {"AU25": 0.15}, "jaw_deg": 5.0, "tongue": {"up": 0.0125, "fwd": -0.0035, "pitch": -15.0}},
	"TH": {"au": {"AU10": 0.2, "AU25": 0.1}, "jaw_deg": 3.5, "tongue": {"up": 0.0025, "fwd": 0.0080, "pitch": 0.0}}}
const VISEME_ALIAS := {"M": "MBP", "B": "MBP", "P": "MBP", "F": "FV", "V": "FV", "S": "I", "Th": "TH", "R": "rest", "": "rest"}


static func viseme_pose(vname: String) -> Dictionary:
	var k := String(VISEME_ALIAS.get(vname, vname))
	if not VISEME_POSE.has(k):
		return {}
	var o: Dictionary = (VISEME_POSE[k] as Dictionary).duplicate(true)
	o["viseme"] = k
	return o


## the tongue's transform in head space for a state: the jaw bone's (jaw_transform), then the viseme's own move (st["viseme"]):
## L raises the tip behind the upper incisors, TH pushes it forward between the teeth
static func tongue_transform(d: Dictionary, st: Dictionary) -> Transform3D:
	var jt := jaw_transform(d, st)
	var vp := viseme_pose(String(st.get("viseme", "")))
	if not vp.has("tongue"):
		return jt
	var tg: Dictionary = vp["tongue"]
	var s := float(d["scale"])
	var tl: Vector3 = d["teeth_lo"]
	var pivot := tl + Vector3(0.0, -0.002 * s, -0.016 * s)   # the tongue's centre
	var pb := Basis(Vector3.RIGHT, deg_to_rad(float(tg["pitch"])))
	var pt := Transform3D(pb, pivot - pb * pivot)
	return Transform3D(Basis.IDENTITY, Vector3(0.0, float(tg["up"]), float(tg["fwd"]))) * pt * jt


## THE NOSE: a heightfield patch standing on the mask. Farkas 1994 (Anthropometry of the Head and Face), adult male, FROM MEMORY:
## nose height n-sn 53 mm, width al-al 35 mm, tip projection sn-prn 17 mm, sn-sto 20 mm; all x s. The patch is trimmed to the nose's
## outline, sunk 0.8 mm under the mask at its edge, so it merges with the skin (same material): a dorsum ridge, a tip lobule and
## two alar wings. Not part of the mask (its 4 boundary loops stay).
static func _nose(hf: Dictionary, s: float, my: float) -> Dictionary:
	var sn := my + 0.020 * s
	var hgt := 0.053 * s
	var nrow := int(round(hgt / 0.001)) + 1
	var ncol := 25
	var verts := PackedVector3Array()
	var col := PackedColorArray()
	for r in nrow:
		var v := float(r) / float(nrow - 1)
		var y := sn + v * hgt
		# the outline half width: alar base 17.5 s mm, the lobule narrower, the root narrower still
		var hw := lerpf(0.0045 * s, 0.0105 * s, 1.0 - _ss(0.15, 0.95, v))
		hw = maxf(hw, 0.0175 * s * (1.0 - _ss(0.10, 0.30, v)))
		var prof := lerpf(0.017 * s, 0.005 * s, clampf((v - 0.20) / 0.80, 0.0, 1.0))
		if v < 0.20:
			prof = 0.017 * s * pow(v / 0.20, 0.7)
		var sig := lerpf(0.0070 * s, 0.0040 * s, _ss(0.2, 1.0, v))
		var fade_v := _ss(0.0, 0.04, v) * (1.0 - _ss(0.90, 1.0, v))
		for c in ncol:
			var x := lerpf(-hw, hw, float(c) / float(ncol - 1))
			var zb := _zsym(hf, x, y)
			if zb < -1.0e8:
				zb = _zsym(hf, 0.0, y)
			zb += MASK_OFF
			var ax := absf(x)
			var dors := prof * exp(-(ax / sig) * (ax / sig))
			var wing := 0.009 * s * exp(-pow((ax - 0.011 * s) / (0.005 * s), 2.0)) * exp(-pow((v - 0.07) / 0.09, 2.0))
			var ef := 1.0 - _ss(0.72, 1.0, ax / hw)
			var off := (dors + wing) * ef * fade_v
			verts.append(Vector3(x, y, zb - 0.0008 + off))
			# the nostrils: two dark ovals under the tip
			var nx := (ax - 0.0065 * s) / (0.0033 * s)
			var ny := (y - (sn + 0.0035 * s)) / (0.0020 * s)
			col.append(Color(1, 1, 1).lerp(Color(0.25, 0.12, 0.12), 0.75 * (1.0 - _ss(0.5, 1.0, sqrt(nx * nx + ny * ny)))))
	var tris := PackedInt32Array()
	for r in nrow - 1:
		for c in ncol - 1:
			var a := r * ncol + c
			var b := a + 1
			var dq := a + ncol
			var cc := dq + 1
			tris.append_array([a, dq, b, b, dq, cc])
	return {"verts": verts, "tris": tris, "col": col, "base_y": sn, "cols": ncol}


static func nose_mesh(d: Dictionary, skin: Color = SKIN) -> ArrayMesh:
	var nz: Dictionary = d["nose"]
	var vs: PackedVector3Array = nz["verts"]
	var cl: PackedColorArray = nz["col"]
	var col := PackedColorArray()
	col.resize(vs.size())
	for i in vs.size():
		col[i] = Color(skin.r * cl[i].r, skin.g * cl[i].g, skin.b * cl[i].b, 1.0)
	var ar := []
	ar.resize(Mesh.ARRAY_MAX)
	ar[Mesh.ARRAY_VERTEX] = vs
	ar[Mesh.ARRAY_NORMAL] = _normals(vs, nz["tris"])
	ar[Mesh.ARRAY_COLOR] = col
	ar[Mesh.ARRAY_INDEX] = nz["tris"]
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ar)
	return am


## a box (centre, size, yaw about Y), flat normals, clockwise from outside; appended to the arrays
static func _box(vs: PackedVector3Array, nm: PackedVector3Array, ix: PackedInt32Array, c: Vector3, sz: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var h := sz * 0.5
	var faces := [[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)], [Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
		[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)], [Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
		[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)], [Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)]]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var w: Vector3 = f[2]
		var k := vs.size()
		for su in [-1.0, 1.0]:
			for sw in [-1.0, 1.0]:
				vs.append(c + b * (n * h + u * h * su + w * h * sw))
				nm.append(b * n)
		for tt in [[k, k + 1, k + 2], [k + 2, k + 1, k + 3]]:
			var cr := (vs[tt[1]] - vs[tt[0]]).cross(vs[tt[2]] - vs[tt[0]])
			if cr.dot(b * n) > 0.0:
				ix.append_array([tt[0], tt[2], tt[1]])
			else:
				ix.append_array([tt[0], tt[1], tt[2]])


## six crowns of a row along a parabolic arch (Wheeler's crown widths, FROM MEMORY: upper central 8.5, lateral 6.5, canine 7.5 mm;
## lower 5.0, 5.5, 7.0; heights 10.5 / 9 / 10 and 9 / 9.5 / 11). Each crown is a rounded superellipsoid (flat-ish incisal edge, rounded
## corners, thicker toward the root) with 3.5 mm x s of GUM beyond it: vertex colours cream above the gum line (a scallop, higher
## between the teeth) and pink under it. Neighbours overlap by 10 % (o["crown_w"] = 1.10) so no gap shows. The upper incisal edge is
## at the lip line, hanging from above; the lower edge stands 0.6 mm under it. Rest space; the lower row rides jaw_transform().
## o: {"crown_w": the crown width factor, "gum": false = no gum colour} (the tests' controls)
static func teeth_mesh(d: Dictionary, upper: bool, o: Dictionary = {}) -> ArrayMesh:
	var s := float(d["scale"])
	var cw := float(o.get("crown_w", 1.10))
	var with_gum: bool = bool(o.get("gum", true))
	var tu: Vector3 = d["teeth_up"] if upper else d["teeth_lo"]
	var wid := [0.0085, 0.0065, 0.0075] if upper else [0.0050, 0.0055, 0.0070]
	var hei := [0.0105, 0.0090, 0.0100] if upper else [0.0090, 0.0095, 0.0110]
	var thick := 0.0070 if upper else 0.0060
	var vs := PackedVector3Array()
	var nm := PackedVector3Array()
	var cl := PackedColorArray()
	var ix := PackedInt32Array()
	var z0 := tu.z + 0.006
	var edge_y := tu.y + 0.0004 if upper else tu.y + 0.0009
	var dirv := 1.0 if upper else -1.0      # toward the root
	for side in [-1.0, 1.0]:
		var x := 0.0
		for i in 3:
			var w: float = float(wid[i]) * s
			var h: float = float(hei[i]) * s
			var xs: float = (x + w * 0.5) * float(side)
			x += w
			var zc := z0 - thick * s * 0.5 - 22.0 * xs * xs
			_crown(vs, nm, cl, ix, Vector3(xs, edge_y, zc), w * 0.5 * cw, thick * s * 0.5, h, 0.0035 * s, dirv, atan(44.0 * xs), with_gum)
	var ar := []
	ar.resize(Mesh.ARRAY_MAX)
	ar[Mesh.ARRAY_VERTEX] = vs
	ar[Mesh.ARRAY_NORMAL] = nm
	ar[Mesh.ARRAY_COLOR] = cl
	ar[Mesh.ARRAY_INDEX] = ix
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ar)
	return am


## one crown + gum: a closed superellipsoid whose axis runs from the incisal edge (at `edge`) toward the root (dirv = +1 up, -1 down);
## half width a (x), half thickness b (z), crown height h, gum length g. Smooth normals; clockwise from outside
static func _crown(vs: PackedVector3Array, nm: PackedVector3Array, cl: PackedColorArray, ix: PackedInt32Array, edge: Vector3, a: float, b: float,
		h: float, g: float, dirv: float, yaw: float, with_gum: bool) -> void:
	var nl := 16
	var nlon := 24
	var tot := h + g
	var tg := h / tot
	var bas := Basis(Vector3.UP, yaw)
	var first := vs.size()
	var cream := Color(0.94, 0.92, 0.85)
	var pink := Color(0.80, 0.42, 0.46)
	var centre := edge + bas * Vector3(0.0, dirv * tot * 0.5, 0.0)
	var ring_start := PackedInt32Array()
	# pole at the edge (t = 0)
	for k in range(0, nl + 1):
		var t := 0.5 - 0.5 * cos(PI * float(k) / float(nl))
		var sf := pow(maxf(1.0 - pow(absf(2.0 * t - 1.0), 5.0), 0.0), 0.2)
		var bf := (0.45 + 0.55 * t) * sf
		if k == 0 or k == nl:
			ring_start.append(vs.size())
			var pp := edge + bas * Vector3(0.0, dirv * tot * t, 0.0)
			vs.append(pp)
			nm.append(Vector3.ZERO)
			cl.append(cream if k == 0 else (pink if with_gum else cream))
			continue
		ring_start.append(vs.size())
		for j in nlon:
			var ph := TAU * float(j) / float(nlon)
			var cx := cos(ph)
			var sz := sin(ph)
			var px := a * sf * signf(cx) * pow(absf(cx), 2.0 / 2.6)
			var pz := b * bf * signf(sz) * pow(absf(sz), 2.0 / 2.6)
			vs.append(edge + bas * Vector3(px, dirv * tot * t, pz))
			nm.append(Vector3.ZERO)
			var xn := px / maxf(a, 1.0e-9)
			var line := tg - 0.07 * xn * xn
			var gk := _ss(line - 0.02, line + 0.02, t) if with_gum else 0.0
			cl.append(cream.lerp(pink, gk))
	# triangles, oriented away from the centre
	var tris := []
	for k in range(0, nl):
		var r0 := ring_start[k]
		var r1 := ring_start[k + 1]
		if k == 0:
			for j in nlon:
				tris.append([r0, r1 + (j + 1) % nlon, r1 + j])
		elif k == nl - 1:
			for j in nlon:
				tris.append([r0 + j, r0 + (j + 1) % nlon, r1])
		else:
			for j in nlon:
				var j2 := (j + 1) % nlon
				tris.append([r0 + j, r0 + j2, r1 + j])
				tris.append([r0 + j2, r1 + j2, r1 + j])
	for tr in tris:
		var pa := vs[tr[0]]
		var pb := vs[tr[1]]
		var pc := vs[tr[2]]
		var cr := (pb - pa).cross(pc - pa)
		var outv := (pa + pb + pc) / 3.0 - centre
		# clockwise from outside = the cross product points inward
		if cr.dot(outv) > 0.0:
			ix.append_array([tr[0], tr[2], tr[1]])
		else:
			ix.append_array([tr[0], tr[1], tr[2]])
	# smooth normals over this crown's triangles
	var nn := PackedVector3Array()
	nn.resize(vs.size())
	var start_ix := ix.size() - tris.size() * 3
	for t in range(start_ix, ix.size() - 2, 3):
		var fn := (vs[ix[t + 1]] - vs[ix[t]]).cross(vs[ix[t + 2]] - vs[ix[t]])
		for q in 3:
			nn[ix[t + q]] += fn
	for i in range(first, vs.size()):
		nm[i] = -nn[i].normalized() if nn[i].length() > 1.0e-14 else Vector3(0, 0, 1)


## the tongue: a flattened ellipsoid on the floor of the mouth behind the lower teeth, riding the jaw
static func tongue_mesh(d: Dictionary) -> ArrayMesh:
	var s := float(d["scale"])
	var tl: Vector3 = d["teeth_lo"]
	var r := Vector3(0.017, 0.008, 0.024) * s
	var ar := _sphere_arrays(r, 14, 22, false, 0.01)
	var vs: PackedVector3Array = ar[Mesh.ARRAY_VERTEX]
	var c := tl + Vector3(0.0, -0.0020 * s, -0.016 * s)
	for i in vs.size():
		vs[i] += c
	ar[Mesh.ARRAY_VERTEX] = vs
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ar)
	return am
