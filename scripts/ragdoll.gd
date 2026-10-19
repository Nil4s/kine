## ragdoll.gd - RAGDOLL TO KEYS WITH PINS (ROADMAP 27). From a frame the body goes limp under gravity: a knockout fall.
## Its own small position-based solver (PBD, 240 Hz substeps, no Godot physics, so it is deterministic):
##   - one particle per simulated joint (the body's own joint pivots, parents first) plus a tip for the head and for each
##     hand; the masses are the de Leva pieces of hit_reaction.gd (clavicles, balls and tips get DEF_M)
##   - DISTANCE constraints on every parent-child pair (the bones keep their rest lengths)
##   - JOINT LIMITS: a joint's rotation is read from its bone (the minimal arc from the bone it has to the bone its
##     parent's frame gives it, decomposed by Body.decompose), clamped by Body.clamp_ang (the body's own bend, side and
##     twist ranges); a clamped joint moves its bone child onto the clamped bone
##   - the FLOOR at y = FLOOR_Y (each particle's radius) with a crude Coulomb friction (MU x the penetration)
##   - CAPSULE contacts between the bones that are not neighbours (samples along each bone); a pair that already touches
##     at the start keeps the gap it starts with (the rest pose's own contacts are not pushed apart forever)
##   - PINS: a picked joint is held at its start position (inverse mass 0)
## The sim is baked as cards: the joint angles of each card frame (Body.decompose of the solver's rotations), the pelvis's
## offset, read back through Body.fk. Not simulated: the fingers and toes (they ride on their hand and foot), the props
## (no contact with them yet), and the torque about a bone (a limb's twist is only what the minimal arcs leave it).
class_name Ragdoll
extends RefCounted

const HZ := 240
const DT := 1.0 / 240.0
const GRAV := Vector3(0.0, -9.81, 0.0)
const ITERS := 24              # PBD iterations per substep
const RIGID_KIDS := true      # a thigh or clavicle is bound to its parent's frame (Body.fk's rule) by a mass-weighted constraint: it keeps its own particle and mass, but the baked pose reads back where the solver has it
const CONT_W := 0.2           # the share of a capsule contact's push applied per pass (1.0 rebounds the collapsing body)
const FINISH := 60            # extra distance passes per substep when a pin is held
const LIM_W := 0.3            # the share of a joint-limit correction applied per pass
const MU := 0.5               # friction: a contact may slide at most MU x its penetration per substep
const FLOOR_Y := 0.0          # m, the floor in the body's space (the pelvis's offset is measured from the rest pose)
const DEF_R := 0.04           # radius of a bone the body has no capsule for
const DEF_M := 0.05           # kg: a clavicle, a ball or a tip
const CARD_FPS := 30
const KD := 0.03              # per substep: the share of the relative velocity of a bone's two ends removed (momentum kept: joint damping, so a free fall is untouched)
const KF := 0.2               # per substep: the share of a floor contact's sliding velocity removed (on top of MU)
const VMAX := 8.0             # m/s: no particle of a body that starts at most 2 m up can be faster than a free fall from 3 m (7.7 m/s); a joint-limit correction is a position change that PBD reads as a velocity, and a bigger one is that artefact, not motion
const REST_V := 9.81 / 240.0  # m/s = g*DT, the speed one substep of gravity adds: a resting contact is gravity added then projected away every substep, so a particle slower than this is at the solver's own resting resolution; at rest = no particle faster for REST_S
const REST_S := 0.3
const SAMP := [0.0, 0.5, 1.0]  # samples along a bone for the capsule contacts
const NAMES := ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head", "tip_head",
	"clavicle_l", "upperarm_l", "lowerarm_l", "hand_l", "tip_hand_l",
	"clavicle_r", "upperarm_r", "lowerarm_r", "hand_r", "tip_hand_r",
	"thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r", "ball_r"]
const TIPS := {"head": "tip_head", "hand_l": "tip_hand_l", "hand_r": "tip_hand_r"}

var B: Body
var n := 0
var nm: Array = []        # particle name
var jn: Array = []        # joint name ("" for a tip)
var par: Array = []       # parent particle (-1 = the root)
var bc: Array = []        # bone child particle (-1 = none)
var w0: Array = []        # Vector3: the bone child's rest offset in this joint's own frame
var rl: Array = []        # rest length to the parent
var rr: Array = []        # radius of the bone that starts at this particle
var fr: Array = []        # floor radius of this particle
var ms: Array = []        # kg
var im: Array = []        # inverse mass (0 = pinned)
var X: Array = []         # Vector3 positions (body space, m)
var V: Array = []
var A: Array = []         # Quaternion: the joint's local rotation (Body.compose of its angles)
var TW: Array = []        # deg: each joint's twist, held at its start value
var derived: Array = []   # true: placed by its parent's frame (no particle of its own)
var XO: Array = []        # positions at the start of the substep
var pins := {}            # particle -> held position
var segs: Array = []      # particles with a bone child (the capsules)
var pairs := {}           # "i,j" -> the closest the two capsules may come (their rest gap, when they start overlapping)
var tch: Array = []       # per particle: the floor touched it this substep
var touch := false        # the floor was hit during the substep
var rec_X: Array = []     # per recorded substep (0 = the start): positions
var rec_A: Array = []     # per recorded substep: rotations
var com: Array = []       # per recorded substep: centre of mass (m)
var t_contact := -1.0     # s, the first floor contact (-1 = none)
var t_rest := -1.0        # s, when the body came to rest (-1 = it did not within the run)
var bake_ok := false
var lift := 0.0          # m: how far setup lifted the body off the floor (its deepest start penetration)


## a joint the sim can pin (the bodies' own joints, not the tips, the fingers or the toes)
static func is_sim(j: String) -> bool:
	return NAMES.has(j) and not j.begins_with("tip_")


## the particles for body b at its current pose (call B.fk first, or let setup do it), pins: joint names held in place
func setup(b: Body, pin_joints: Array) -> void:
	B = b
	B.fk()
	var mass_of := {}
	for p in HitReaction.pieces(B):
		var jj := String(p["j"])
		mass_of[jj] = float(mass_of.get(jj, 0.0)) + float(p["m"])
	n = NAMES.size()
	var ix := {}
	for i in n:
		ix[NAMES[i]] = i
	nm = NAMES.duplicate()
	jn.resize(n)
	par.resize(n)
	bc.resize(n)
	w0.resize(n)
	rl.resize(n)
	rr.resize(n)
	fr.resize(n)
	ms.resize(n)
	im.resize(n)
	X.resize(n)
	V.resize(n)
	A.resize(n)
	TW.resize(n)
	derived.resize(n)
	XO.resize(n)
	for i in n:
		var s := String(nm[i])
		var tip := s.begins_with("tip_")
		var joint := s.trim_prefix("tip_") if tip else s
		var p_joint := joint if tip else String(B.parent.get(s, ""))
		par[i] = int(ix[p_joint]) if p_joint != "" else -1
		jn[i] = "" if tip else s
		var bone := -1
		if TIPS.has(s):
			bone = int(ix[TIPS[s]])
		elif not tip and Body.CHILD.has(s):
			bone = int(ix[Body.CHILD[s]])
		bc[i] = bone
		if bone < 0:
			w0[i] = Vector3.ZERO
		elif String(nm[bone]).begins_with("tip_"):
			w0[i] = (B.e0[joint] as Vector3) - (B.p0[joint] as Vector3)
		else:
			w0[i] = (B.p0[String(nm[bone])] as Vector3) - (B.p0[s] as Vector3)
		if par[i] < 0:
			rl[i] = 0.0
		elif tip:
			rl[i] = ((B.e0[joint] as Vector3) - (B.p0[joint] as Vector3)).length()
		else:
			rl[i] = ((B.p0[s] as Vector3) - (B.p0[p_joint] as Vector3)).length()
		rr[i] = float(B.rad.get(joint, DEF_R))
		ms[i] = 0.0
		im[i] = 0.0
		X[i] = (B.E[joint] as Vector3) if tip else (B.P[s] as Vector3)
		V[i] = Vector3.ZERO
		A[i] = Quaternion.IDENTITY if tip else B.compose(s, B.ang[s])
		TW[i] = 0.0 if tip else float((B.ang[s] as Vector3).z)
	# lumped masses: a bone's mass is split half and half between its two end particles (a leaf particle that carried only the
	# fixed DEF_M was flung by every joint-limit correction, which is shared by inverse mass)
	for i in n:
		var mj := float(mass_of.get(String(jn[i]), 0.0)) if String(jn[i]) != "" else 0.0
		if mj <= 0.0:
			continue
		if int(bc[i]) >= 0:
			ms[i] = float(ms[i]) + 0.5 * mj
			ms[bc[i]] = float(ms[bc[i]]) + 0.5 * mj
		else:
			ms[i] = float(ms[i]) + mj
	for i in n:
		ms[i] = maxf(float(ms[i]), DEF_M)
		im[i] = 1.0 / float(ms[i])
	for i in n:
		# the floor as the test and Body.ground_body measure it: a particle is an end of its own bone (radius rr[i]) and of the
		# bone that ends on it (radius of that bone's joint, or of the joint of a tip); the capsule's end sphere is the larger
		fr[i] = rr[i]
		for q in n:
			if int(bc[q]) == i:
				fr[i] = maxf(float(fr[i]), float(rr[q]))
		# a joint that is not the bone child of its parent (a thigh on the pelvis, a clavicle on the spine) sits rigidly in
		# the parent's frame, as Body.fk puts it: it has no particle of its own (no mass to move, no contact)
		derived[i] = RIGID_KIDS and par[i] >= 0 and int(bc[par[i]]) != i
	for pj in pin_joints:
		var k: int = int(ix.get(String(pj), -1))
		if k >= 0 and not String(nm[k]).begins_with("tip_"):
			pins[k] = X[k]
			im[k] = 0.0
	# the start must be above the floor: a body posed by Body.ground stands on its soles, and its toes' capsules can sit a
	# few cm deeper; that correction would become a velocity of several m/s, so the whole body is lifted by the deepest
	# start penetration instead (one posed lift, no velocity; the cards start from the lifted pose)
	var low := INF
	for i in n:
		low = minf(low, (X[i] as Vector3).y - float(fr[i]) - FLOOR_Y)
	if low < 0.0:
		for i in n:
			X[i] = (X[i] as Vector3) + Vector3(0.0, -low, 0.0)
		lift = -low
	for pk in pins.keys():
		pins[pk] = X[pk]
	segs = []
	for i in n:
		if int(bc[i]) >= 0:
			segs.append(i)
	pairs = {}
	for a in segs.size():
		for b2 in range(a + 1, segs.size()):
			var i: int = segs[a]
			var j: int = segs[b2]
			if _adjacent(i, j):
				continue
			pairs["%d,%d" % [i, j]] = minf(float(rr[i]) + float(rr[j]), _min_gap(i, j))


func _adjacent(a: int, b: int) -> bool:
	return a == b or par[a] == b or par[b] == a or par[a] == par[b] or bc[a] == b or bc[b] == a or bc[a] == bc[b]


func _min_gap(i: int, j: int) -> float:
	var best := INF
	for s in SAMP:
		var p: Vector3 = (X[i] as Vector3).lerp(X[bc[i]] as Vector3, s)
		for u in SAMP:
			var q: Vector3 = (X[j] as Vector3).lerp(X[bc[j]] as Vector3, u)
			best = minf(best, p.distance_to(q))
	return best


## run the fall for `secs` seconds (or until it rests): one substep at a time, every substep recorded
func run(secs: float) -> void:
	_record()
	var steps := int(round(secs * HZ))
	var need := int(round(REST_S * HZ))
	var still := 0
	for k in steps:
		touch = false
		_step()
		if touch and t_contact < 0.0:
			t_contact = float(k + 1) * DT
		_record()
		var vmax := 0.0
		for i in n:
			if float(im[i]) > 0.0:
				vmax = maxf(vmax, (V[i] as Vector3).length())
		still = still + 1 if vmax < REST_V else 0
		if still >= need:
			t_rest = float(k + 1) * DT
			break


func _record() -> void:
	rec_X.append(X.duplicate())
	rec_A.append(A.duplicate())
	var M := 0.0
	var c := Vector3.ZERO
	for i in n:
		M += float(ms[i])
		c += (X[i] as Vector3) * float(ms[i])
	com.append(c / M)


func _step() -> void:
	XO = X.duplicate()
	tch.resize(n)
	tch.fill(false)
	for i in n:
		if float(im[i]) > 0.0:
			var v: Vector3 = (V[i] as Vector3) + GRAV * DT
			V[i] = v
			X[i] = (X[i] as Vector3) + v * DT
	for it in ITERS:
		_distance()
		_limits()
		_contacts()
		_hold()
		_floor()
	# a pinned end under a hanging body converges slowly (mass ratio): the bone lengths, the limits and the frame bindings get extra passes, floor last
	if not pins.is_empty():
		for it in FINISH:
			_distance()
			_limits()
			_hold()
		_floor()
	for i in n:
		if float(im[i]) > 0.0:
			var vv: Vector3 = ((X[i] as Vector3) - (XO[i] as Vector3)) / DT
			if bool(tch[i]):
				# an inelastic floor: the correction that lifted a particle out of the floor is not a velocity (no pop, no bounce),
				# and sliding loses KF of its speed
				vv.y = minf(vv.y, 0.0)
				vv.x *= 1.0 - KF
				vv.z *= 1.0 - KF
			if vv.length() > VMAX:
				vv = vv.normalized() * VMAX
			V[i] = vv
		else:
			V[i] = Vector3.ZERO
	_damp()


## joint damping: the relative velocity of a bone's two ends is reduced by KD, shared by inverse mass (the total momentum is kept)
func _damp() -> void:
	for i in n:
		var p: int = par[i]
		if p < 0:
			continue
		var wsum: float = float(im[i]) + float(im[p])
		if wsum <= 0.0:
			continue
		var dv: Vector3 = ((V[i] as Vector3) - (V[p] as Vector3)) * KD
		V[i] = (V[i] as Vector3) - dv * (float(im[i]) / wsum)
		V[p] = (V[p] as Vector3) + dv * (float(im[p]) / wsum)


func _distance() -> void:
	for i in n:
		var p: int = par[i]
		if p < 0 or bool(derived[i]):
			continue
		var d: Vector3 = (X[i] as Vector3) - (X[p] as Vector3)
		var len := d.length()
		if len < 1e-12:
			continue
		var wsum: float = float(im[i]) + float(im[p])
		if wsum <= 0.0:
			continue
		var corr: Vector3 = d * ((len - float(rl[i])) / len)
		X[i] = (X[i] as Vector3) - corr * (float(im[i]) / wsum)
		X[p] = (X[p] as Vector3) + corr * (float(im[p]) / wsum)


## the joint limits, top down: each joint's rotation in its parent's frame is the minimal arc that puts its bone where
## the particles have it; decomposed and clamped with the body's own ranges; a clamped joint moves its bone child
func _limits() -> void:
	var G: Array = []
	for i in n:
		G.append(Quaternion.IDENTITY)
	for i in n:
		var c: int = int(bc[i])
		var s := String(jn[i])
		if c < 0 or s == "":
			continue
		var gp: Quaternion = G[par[i]] if par[i] >= 0 else Quaternion.IDENTITY
		var pi: Vector3 = X[i]
		var dl: Vector3 = gp.inverse() * ((X[c] as Vector3) - pi)
		var vc: Vector3 = (A[i] as Quaternion) * (w0[i] as Vector3)
		var An: Quaternion = A[i]
		if dl.length() > 1e-12 and vc.length() > 1e-12:
			# the twist is not driven by the fall: it stays at its start value (a minimal arc splits a rotation between
			# swing and twist arbitrarily, and clamping that split would swing the bone); bend and side are limited
			An = (_arc(vc, dl) * (A[i] as Quaternion)).normalized()
			var ang: Vector3 = B.decompose(s, An)
			var want := Vector3(ang.x, ang.y, float(TW[i]))
			var cl: Vector3 = B.clamp_ang(s, want)
			An = B.compose(s, cl).normalized()   # always rebuilt with the held twist (the playback reads the same twist)
			if (cl - want).length() > 1e-6:
				# only a joint past its range moves its bone child, and only part of the way each pass (PBD converges over
				# the iterations; a full snap of a folded chain is a jump the velocity would keep)
				var tgt: Vector3 = pi + gp * (An * (w0[i] as Vector3))
				# the correction is shared by inverse mass, the child one way and the joint the other (momentum is kept:
				# a limit that moved only the child would push the whole body)
				var S := float(im[c]) + float(im[i])
				if S > 0.0:
					var dv: Vector3 = (tgt - (X[c] as Vector3)) * LIM_W
					X[c] = (X[c] as Vector3) + dv * (float(im[c]) / S)
					X[i] = pi - dv * (float(im[i]) / S)
		A[i] = An
		G[i] = gp * An
		# the derived children of this joint sit in its frame (Body.fk's rule: the child's rest offset from this joint)
		for k in n:
			if par[k] == i and bool(derived[k]):
				var off: Vector3 = (B.p0[String(jn[k])] as Vector3) - (B.p0[s] as Vector3)
				var want_k: Vector3 = (X[i] as Vector3) + (G[i] as Quaternion) * off
				var Sk := float(im[k]) + float(im[i])
				if Sk > 0.0:
					var dk: Vector3 = want_k - (X[k] as Vector3)
					X[k] = (X[k] as Vector3) + dk * (float(im[k]) / Sk)
					X[i] = (X[i] as Vector3) - dk * (float(im[i]) / Sk)


## the shortest rotation that turns direction a onto direction b
static func _arc(a: Vector3, b: Vector3) -> Quaternion:
	var an := a.normalized()
	var bn := b.normalized()
	var d := clampf(an.dot(bn), -1.0, 1.0)
	var ax := an.cross(bn)
	if ax.length() < 1e-12:
		if d > 0.0:
			return Quaternion.IDENTITY
		ax = an.cross(Vector3.RIGHT)
		if ax.length() < 1e-6:
			ax = an.cross(Vector3.UP)
	return Quaternion(ax.normalized(), acos(d))


func _floor() -> void:
	for i in n:
		if float(im[i]) <= 0.0:
			continue
		var p: Vector3 = X[i]
		var pen := (float(fr[i]) + FLOOR_Y) - p.y
		if pen <= 0.0:
			continue
		touch = true
		tch[i] = true
		p.y += pen
		var o: Vector3 = XO[i]
		var dx := Vector3(p.x - o.x, 0.0, p.z - o.z)
		var l := dx.length()
		if l > 1e-12:
			p -= dx / l * minf(l, MU * pen)
		X[i] = p


## capsule contacts between the bones that are not neighbours: samples along both bones, pushed apart
func _contacts() -> void:
	_contacts_w(CONT_W)


func _contacts_w(w: float) -> void:
	for a in segs.size():
		var i: int = segs[a]
		for b2 in range(a + 1, segs.size()):
			var j: int = segs[b2]
			var key := "%d,%d" % [i, j]
			if not pairs.has(key):
				continue
			var thr: float = pairs[key]
			var ci: Vector3 = ((X[i] as Vector3) + (X[bc[i]] as Vector3)) * 0.5
			var cj: Vector3 = ((X[j] as Vector3) + (X[bc[j]] as Vector3)) * 0.5
			var reach: float = 0.5 * ((X[i] as Vector3).distance_to(X[bc[i]] as Vector3) + (X[j] as Vector3).distance_to(X[bc[j]] as Vector3)) + float(rr[i]) + float(rr[j])
			if ci.distance_to(cj) > reach:
				continue
			# one contact per pair: the deepest of the sample pairs (nine contacts on the same four particles overshot, ringing
			# against a joint limit)
			var best := INF
			var bs := 0.0
			var bu := 0.0
			var bd := Vector3.ZERO
			for s in SAMP:
				for u in SAMP:
					var p: Vector3 = (X[i] as Vector3).lerp(X[bc[i]] as Vector3, s)
					var q: Vector3 = (X[j] as Vector3).lerp(X[bc[j]] as Vector3, u)
					var d: Vector3 = p - q
					var dist := d.length()
					if dist < best and dist >= 1e-9:
						best = dist
						bs = s
						bu = u
						bd = d
			if best < thr:
				_push([i, bc[i], j, bc[j]], [1.0 - bs, bs, 1.0 - bu, bu], [1.0, 1.0, -1.0, -1.0], bd / best, (thr - best) * w)


## move the particles so that the weighted point of each side separates by pen along nrm (mass weighted)
func _push(ids: Array, ws: Array, sg: Array, nrm: Vector3, pen: float) -> void:
	var W := 0.0
	for k in ids.size():
		W += float(im[ids[k]]) * float(ws[k]) * float(ws[k])
	if W <= 0.0:
		return
	var lam := pen / W
	for k in ids.size():
		var q: int = ids[k]
		if float(im[q]) <= 0.0:
			continue
		X[q] = (X[q] as Vector3) + nrm * (float(sg[k]) * float(im[q]) * float(ws[k]) * lam)


func _hold() -> void:
	for k in pins.keys():
		X[k] = pins[k]


## the cards for the recorded fall: one per fps (the first one is the start pose). keep_ang = the body's angles at the
## start (the fingers and toes keep them). Leaves the body posed at the last card: the caller restores its state.
func bake(keep_ang: Dictionary, fps: int) -> Array:
	var cards: Array = []
	var stride := maxi(1, int(round(float(HZ) / float(fps))))
	var last := rec_X.size() - 1
	var ks: Array = []
	for k in range(0, last + 1, stride):
		ks.append(k)
	if ks[-1] != last:
		ks.append(last)
	bake_ok = true
	for q in ks.size():
		var k: int = ks[q]
		var ang: Dictionary = keep_ang.duplicate()
		for i in n:
			var s := String(jn[i])
			if s == "":
				continue
			ang[s] = B.decompose(s, (rec_A[k] as Array)[i] as Quaternion)
		B.ang = ang
		var x0: Vector3 = (rec_X[k] as Array)[0]
		B.offset = x0 - (B.p0["pelvis"] as Vector3)
		B.fk()
		var move := -1.0 if q == 0 else float(ks[q] - ks[q - 1]) * DT
		cards.append({"name": "fall %.2f s" % (float(k) * DT), "pose": B.to_dict(), "move": move, "hold": 0.0, "ease": "linear"})
	return cards


## the solver's joint angles at recorded substep k (joint -> Vector3 bend, side, twist in degrees)
func angles_at(k: int) -> Dictionary:
	var out := {}
	for i in n:
		var s := String(jn[i])
		if s != "":
			out[s] = B.decompose(s, (rec_A[k] as Array)[i] as Quaternion)
	return out
