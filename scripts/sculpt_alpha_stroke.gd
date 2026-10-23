class_name SculptAlphaStroke
extends RefCounted
## Alpha stamps and stroke methods for one sculpt stroke (ROADMAP_400 C08; the pictures are scripts/sculpt_alphas.gd).
## KMeshSculpt asks make() at begin(): null unless the stroke has an alpha or a stroke method other than dots, so a plain
## stroke runs exactly as before. Then every dab passes through dab() here (jitter, the frame) and weigh() (the weights).
## STROKE PARAMS (all optional):
##   "alpha"          an alpha's name ("" = none: the plain round falloff)
##   "stroke_method"  dots (dabs every spacing x radius, as before) | drag rect (one stamp: press = centre, the drag = its
##                    radius and its rotation, applied on release; drag_rect() below) | spray (each dab jittered: position
##                    within spray_pos x radius, radius x (1 +- spray_scale), any rotation, from RandomNumberGenerator(seed))
##   "alpha_rot"      stroke (the alpha's x axis follows the stroke's direction) | fixed | random (per dab, from the seed)
##   "alpha_angle"    radians added to the rotation (fixed: the whole rotation)
##   "alpha_ref"      the frame's zero direction (mesh local; the sculpt page passes the camera's right), projected onto the
##                    surface; default mesh-local +X (+Z when the normal is along X)
##   "alpha_dir"      a starting stroke direction (drag rect sets it to the drag)
##   "alpha_fade"     the falloff acts over the outer alpha_fade of the radius only (default FADE): w = falloff((d/r - (1 -
##                    fade)) / fade) x alpha. 1 = the brush's whole falloff. Without an alpha the falloff is the brush's own
##   "seed", "spray_pos", "spray_scale"
## THE FRAME of a dab with normal n: t = the rotation's direction projected onto the surface, b = t x n; a vert at offset o
## from the dab centre reads the alpha at (o.t / r, o.b / r). Symmetry copies (C07) project the same t (not mirrored).

const DOTS := "dots"
const DRAG_RECT := "drag rect"
const SPRAY := "spray"
const METHODS := [DOTS, DRAG_RECT, SPRAY]
const R_STROKE := "stroke"
const R_FIXED := "fixed"
const R_RANDOM := "random"
const ROTATIONS := [R_STROKE, R_FIXED, R_RANDOM]
const FADE := 0.05   # the rim only: measured, a fade of 0.15 lets the falloff pull a scales stamp's match with its alpha to r 0.83 (0.05: 0.95; 1: 0.45)
const SPRAY_POS := 0.5
const SPRAY_SCALE := 0.3

var dat := PackedFloat32Array()   # the alpha's pixels (empty: no alpha)
var method := DOTS
var rot := R_STROKE
var angle := 0.0
var fade := 1.0
var ref := Vector3.RIGHT
var dir := Vector3.ZERO     # the stroke's direction so far (mesh local), ZERO = none yet
var rng := RandomNumberGenerator.new()
var spray_pos := SPRAY_POS
var spray_scale := SPRAY_SCALE
var inside := false
var t_axis := Vector3.RIGHT # this dab's frame x axis (before projection onto a copy's surface)
var stamps: Array = []      # every stamp laid: {"at", "radius", "t"} (the tests read it)


static func make(sc: KMeshSculpt) -> SculptAlphaStroke:
	var p := sc.p
	var nm := String(p.get("alpha", ""))
	var meth := String(p.get("stroke_method", DOTS))
	if not METHODS.has(meth):
		meth = DOTS
	if nm == "" and meth == DOTS:
		return null
	if p["brush"] == KMeshSculpt.GRAB:
		return null   # grab is not a dab
	var s := SculptAlphaStroke.new()
	s.dat = SculptAlphas.data(nm) if nm != "" else PackedFloat32Array()
	s.method = meth
	s.rot = String(p.get("alpha_rot", R_STROKE))
	s.angle = float(p.get("alpha_angle", 0.0))
	s.fade = clampf(float(p.get("alpha_fade", FADE)), 0.0, 1.0) if not s.dat.is_empty() else 1.0
	var rf: Variant = p.get("alpha_ref", Vector3.RIGHT)
	s.ref = rf if rf is Vector3 and (rf as Vector3).length_squared() > 1e-12 else Vector3.RIGHT
	var ad: Variant = p.get("alpha_dir", Vector3.ZERO)
	s.dir = ad if ad is Vector3 else Vector3.ZERO
	s.rng.seed = int(p.get("seed", 1))
	s.spray_pos = float(p.get("spray_pos", SPRAY_POS))
	s.spray_scale = clampf(float(p.get("spray_scale", SPRAY_SCALE)), 0.0, 0.95)
	return s


## a unit tangent of the surface with normal n along v (projected); fallback: along the reference, then any
static func tangent(n: Vector3, v: Vector3, fallback := Vector3.RIGHT) -> Vector3:
	var t := v - n * n.dot(v)
	if t.length_squared() > 1e-10:
		return t.normalized()
	t = fallback - n * n.dot(fallback)
	if t.length_squared() > 1e-10:
		return t.normalized()
	t = Vector3.FORWARD - n * n.dot(Vector3.FORWARD)
	return t.normalized()


## one dab of the stroke: jitter (spray), the rotation, then the brush's own dab (and its symmetry copies)
func dab(sc: KMeshSculpt, hit: Vector3, normal: Vector3, pressure: float) -> int:
	var n := normal.normalized() if normal.length_squared() > 0.0 else Vector3.UP
	var r0 := float(sc.p["radius"])
	var t0 := tangent(n, ref)
	var h := hit
	var sc_r := 1.0
	var a := angle
	var base := t0
	if method == SPRAY:
		var b0 := t0.cross(n)
		var ja := rng.randf() * TAU
		var jr := sqrt(rng.randf()) * spray_pos * r0
		h = hit + (t0 * cos(ja) + b0 * sin(ja)) * jr
		sc_r = 1.0 + spray_scale * (rng.randf() * 2.0 - 1.0)
		a = rng.randf() * TAU
	elif rot == R_RANDOM:
		a = rng.randf() * TAU
	elif rot == R_STROKE:
		if sc._has_last:
			var mv := hit - sc._last
			mv -= n * n.dot(mv)
			if mv.length_squared() > 1e-14:
				dir = mv
		if dir != Vector3.ZERO:
			base = tangent(n, dir, ref)
	t_axis = base.rotated(n, a) if a != 0.0 else base
	stamps.append({"at": h, "radius": r0 * sc_r, "t": t_axis})
	inside = true
	sc.p["radius"] = r0 * sc_r
	var moved := sc.dab(h, normal, pressure)
	sc.p["radius"] = r0
	inside = false
	return moved


## the weights of a dab's verts: the faded falloff x the alpha in the dab's frame
func weigh(sc: KMeshSculpt, ids: PackedInt32Array, w: PackedFloat32Array, hit: Vector3, n: Vector3, r: float) -> PackedFloat32Array:
	var vp := sc.mesh.verts
	var fk := String(sc.p["falloff"])
	var t := tangent(n, t_axis, ref)
	var b := t.cross(n)
	var core := 1.0 - fade
	for i in ids.size():
		var o := vp[ids[i]] - hit
		var d := o.length() / r
		var tf := d if fade >= 1.0 else (clampf((d - core) / fade, 0.0, 1.0) if fade > 0.0 else (1.0 if d >= 1.0 else 0.0))
		var f := KMeshSculpt.falloff(fk, tf) if d < 1.0 else 0.0
		w[i] = f * (SculptAlphas.sample(dat, o.dot(t) / r, o.dot(b) / r) if not dat.is_empty() else 1.0)
	return w


## DRAG RECT: one stamp centred at a (mesh local) with normal n, its radius the drag a -> b along the surface and its x
## axis along the drag; a whole stroke (begin, one dab, end) on sc. Returns the radius (0: too short, nothing done)
static func drag_rect(sc: KMeshSculpt, m: KMesh, params: Dictionary, a: Vector3, b: Vector3, n: Vector3) -> float:
	var nn := n.normalized() if n.length_squared() > 0.0 else Vector3.UP
	var d := b - a
	d -= nn * nn.dot(d)
	var r := d.length()
	if r < 1e-4:
		return 0.0
	var prm := params.duplicate()
	prm["radius"] = r
	prm["stroke_method"] = DRAG_RECT
	prm["alpha_rot"] = R_STROKE
	prm["alpha_dir"] = d
	prm["alpha_angle"] = 0.0   # the drag is the rotation
	sc.begin(m, prm)
	sc.to(a, nn, 1.0)
	sc.end()
	return r
