## crowd.gd - CROWD (ROADMAP 95): copies of the current fighter's clip, each with its own seeded variation.
## A crowd is "Crowd: make 20 copies" on the active fighter; its settings live in the scene ("crowd": {"n", "seed"}, one
## undo step, saved with the file). Everything here is a pure function of (n, seed, clip): the same seed gives the same
## bytes, a re-roll gives another seed. The copies are drawn (main.gd _crowd_draw) and exported (_export_actors) and are
## not pickable or editable: they are the fighter's clip played again, not new fighters.
##
## THE VARIATIONS, each with its number and its reason:
##   place    scattered in a square of half-width HALF (5 m) about the hero, no copy within HOLE (1.2 m) of it, and no two
##            copies closer than SPACING (0.6 m) centre to centre: a bideltoid breadth of about 0.45 m (ANSUR II, see
##            docs/research/PROPORTIONS.md) plus 0.15 m of clearance. Dart throwing with the seeded generator.
##   yaw      +-15 deg about the vertical: they do not stand in one line.
##   time     a clip-time offset uniform in +-0.3 s (TIME_DT).
##   speed    the copy plays at 1 +- 8 % of the fighter's speed (SPEED_VAR).
##   noise    per joint and per axis an amplitude uniform in +-3 deg (NOISE_DEG), a sinusoid of one shared frequency per copy
##            (0.15 to 0.40 Hz, so it is smooth in time), added to what the clip plays and clamped to the joint's limits
##            (Body.clamp_ang), so every copy's joints stay inside the limits at every frame.
##   mirror   half the copies are mirrored about the body's own sagittal plane (the placement's X scale is -1).
##   stature  a body height drawn from ANSUR II men: mean 175.62 cm, sd 6.86 cm (Gordon et al. 2014, NATICK/TR-15/007, the
##            numbers computed in docs/research/PROPORTIONS.md), redrawn while it lies outside mean +- 2 sd. The copy's
##            body is made at that stature through Proportions (the same retarget path as a scene's body), so the mesh
##            and the joints follow it. Only the stature is drawn from the table; the segment proportions stay the
##            fighter's own.
class_name Crowd
extends RefCounted

const DEFAULT_N := 20
const MAX_N := 60
const SPACING := 0.6
const HALF := 5.0
const HOLE := 1.2
const TIME_DT := 0.3
const SPEED_VAR := 0.08
const NOISE_DEG := 3.0
const NOISE_HZ := [0.15, 0.40]
const YAW_DEG := 15.0
## the copies' skins: muted, so the fighter (its own plain skin) stands out; cycled by copy number
const TINTS := [Color(0.62, 0.62, 0.6), Color(0.56, 0.6, 0.66), Color(0.66, 0.6, 0.56)]
const STATURE_MEAN := 1.7562   # m: ANSUR II men, 175.62 cm (Gordon et al. 2014; docs/research/PROPORTIONS.md)
const STATURE_SD := 0.0686     # m: 6.86 cm, the same source


## the copies of a crowd of n for this seed: a list of plain dictionaries (no objects, so the list can be saved and
## compared byte for byte). joints: the joint names the noise is drawn for (Body.ORDER)
static func make(n: int, seed: int, joints: Array) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var pts := _layout(n, rng)
	var out := []
	for i in pts.size():
		var amp := {}
		var ph := {}
		var yaw := rng.randf_range(-YAW_DEG, YAW_DEG)
		var dt := rng.randf_range(-TIME_DT, TIME_DT)
		var speed := 1.0 + rng.randf_range(-SPEED_VAR, SPEED_VAR)
		var mirror := rng.randf() < 0.5
		var stature := _stature(rng)
		var hz := rng.randf_range(NOISE_HZ[0], NOISE_HZ[1])
		for j in joints:
			amp[j] = Vector3(rng.randf_range(-NOISE_DEG, NOISE_DEG), rng.randf_range(-NOISE_DEG, NOISE_DEG), rng.randf_range(-NOISE_DEG, NOISE_DEG))
			ph[j] = Vector3(rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU))
		out.append({"pos": pts[i], "yaw": yaw, "dt": dt, "speed": speed, "mirror": mirror, "stature": stature, "hz": hz, "amp": amp, "ph": ph})
	return out


## scattered points: dart throwing, at most 4000 darts (a crowd of 20 in a 10 m square needs about 30)
static func _layout(n: int, rng: RandomNumberGenerator) -> Array:
	var pts := []
	var tries := 0
	while pts.size() < n and tries < 4000:
		tries += 1
		var p := Vector2(rng.randf_range(-HALF, HALF), rng.randf_range(-HALF, HALF))
		if p.length() < HOLE:
			continue
		var clear := true
		for q in pts:
			if p.distance_to(q) < SPACING:
				clear = false
				break
		if clear:
			pts.append(p)
	return pts


## a stature in metres from ANSUR II men, redrawn while it lies outside mean +- 2 sd
static func _stature(rng: RandomNumberGenerator) -> float:
	while true:
		var z := rng.randfn(0.0, 1.0)
		if absf(z) <= 2.0:
			return STATURE_MEAN + STATURE_SD * z
	return STATURE_MEAN


## the copy's noise on joint j at the fighter's unwrapped clip time T (degrees, one value per axis)
static func noise(c: Dictionary, j: String, T: float) -> Vector3:
	var a: Vector3 = c["amp"][j]
	var p: Vector3 = c["ph"][j]
	var w := TAU * float(c["hz"]) * T
	return Vector3(a.x * sin(w + p.x), a.y * sin(w + p.y), a.z * sin(w + p.z))


## the copy's placement in the hero's space: yaw, then the mirror in the figure's own X, then the position on the floor
static func placement(c: Dictionary) -> Transform3D:
	var p: Vector2 = c["pos"]
	var sx := -1.0 if bool(c["mirror"]) else 1.0
	var basis := Basis(Vector3.UP, deg_to_rad(float(c["yaw"]))) * Basis.from_scale(Vector3(sx, 1.0, 1.0))
	return Transform3D(basis, Vector3(p.x, 0.0, p.y))


## the copy's scene: the fighter's, with this copy's stature (the fighter's own segment scales are kept)
static func scene_for(src: Scene, c: Dictionary) -> Scene:
	var sc := src.clone()
	sc.actors = []
	sc.crowd = {}
	var d: Dictionary = src.body.duplicate(true)
	d["stature"] = float(c["stature"])
	sc.body = Proportions.clean(d)
	return sc


## THE POSE TABLE (the fast path). The fighter's clip is sampled once per scene at BAKE_HZ on a copy of its scene, so no
## cache of the fighter's is touched: per sample the joint angles Scene.apply gives (in Body.ORDER), the pelvis offset, and
## the height of the lowest sole above the floor (Body.sole_low, 0 on the floor, more in the air). One Scene.apply costs
## about 2.8 ms on this machine, so 20 copies posed with it were 18 fps with the fighter (the test prints both); a copy
## plays the table instead: its clip time through the table (linear between samples, wrapping at the clip's end), its
## noise, its clamp, its offset.
const BAKE_HZ := 60.0   # 30 Hz: worst joint 8.7 deg off the exact pose at a fast move; 60 Hz: 2.1 deg; 120 Hz: 3.8 (the exact pose has history: a fresh body each time here); mean 0.05 / 0.016 / 0.010 deg


## the table of src (a scene the caller owns: a clone of the fighter's, with no actors and no crowd)
static func bake(src: Scene) -> Dictionary:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var L := src.length()
	var n := maxi(1, ceili(L * BAKE_HZ))
	var angs := []
	var offs := []
	var hs := []
	for k in n:
		src.apply(B, float(k) * L / float(n))
		var a := PackedVector3Array()
		for j in Body.ORDER:
			a.append(B.ang[j])
		angs.append(a)
		offs.append(B.offset)
		hs.append(B.sole_low())
	return {"L": L, "n": n, "angs": angs, "offs": offs, "hs": hs}


## the copy's pose at the hero's playhead, from the table: the joints of the table (plus the copy's noise, clamped to the
## limits), the pelvis offset, and the lowest sole kept at the height the fighter's has in the table, so a copy of another
## stature stands on the floor (and is in the air when the fighter is). B must belong to this copy
static func pose(c: Dictionary, tb: Dictionary, B: Body, playhead: float, joints: Array) -> void:
	var T := playhead * float(c["speed"]) + float(c["dt"])
	var L: float = tb["L"]
	var n: int = tb["n"]
	var f := 0.0
	if L > 0.0:
		f = fposmod(T, L) / L * float(n)
	var i0 := int(floor(f)) % n
	var i1 := (i0 + 1) % n
	var u: float = f - floor(f)
	var A: PackedVector3Array = tb["angs"][i0]
	var A1: PackedVector3Array = tb["angs"][i1]
	for q in joints.size():
		var j: String = joints[q]
		B.ang[j] = B.clamp_ang(j, A[q].lerp(A1[q], u) + noise(c, j, T))
	B.offset = (tb["offs"][i0] as Vector3).lerp(tb["offs"][i1], u)
	B.fk()
	var h := lerpf(float(tb["hs"][i0]), float(tb["hs"][i1]), u)
	B.offset.y += h - B.sole_low()
	B.fk()
