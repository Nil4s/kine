## ch6_tie.gd - CH6: a Kine hand ties a bowline, then the knot is loaded.
## The hand is the existing rig: Body.reach (IK) puts the wrist where a two-finger pinch (Body "pinch" pose, the index opened until
## the fingertip capsules leave a gap of one rope diameter) puts the working end on the keyed path. The rope (RopeSim, C++ when the
## DLL has it) collides with every finger capsule, the palm, the forearm and the peg; the pinch drives the last 3 rope particles.
## Phases (30 fps): tie (hand path) -> open + retract -> seat (S0 pulled 0 -> fmax, held) -> unload to 20 N -> re-load 20 -> fmax (judged).
## The rope's inertia is scaled up (mass per particle 0.3 kg: quasi-static) so a 120 N pull does not stretch the chain.
class_name Ch6Tie
extends RefCounted

const O := Vector3(-0.10, 1.32, 0.50)   # origin of the knot frame in world (the body faces +z, its right hand is at -x)
const FPS := 30
const HAND_JOINTS := ["palm_index", "palm_middle", "palm_ring", "palm_pinky", "lowerarm_r"]
const PALM_R := 0.013
const FINGERS := ["thumb", "index", "middle", "ring", "pinky"]
const STUB := 3

var B: Body
var rope: RopeSim
var pin_local := Vector3.ZERO   # the pinch point in the hand's frame
var ax_local := Vector3.ZERO    # the stub axis (end -> body of the rope) in the hand's frame, pointing to the free end
static var FREE_CURL := 2.0
var idx_ang0 := {}              # the pinch pose's index joint angles (scaled by `open`)
var cap_names: Array = []
var prev_caps: Array = []
var log: Dictionary = {}


func _init() -> void:
	B = Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	for f in FINGERS:
		for k in 3:
			cap_names.append("%s_0%d_r" % [f, k + 1])
	cap_names.append_array(HAND_JOINTS)


func caps_now() -> Array:
	var o: Array = []
	for j in cap_names:
		if String(j).begins_with("palm_"):
			# CH6b: the palm as four metacarpal capsules (wrist -> each finger's knuckle), not the rig's one hand_r capsule of
			# radius 4.5 cm (a 9 cm thick sausage that could not pass a 9 cm hole); PALM_R: palm thickness ~2.6 cm
			var k: String = String(j).substr(5) + "_01_r"
			o.append([B.P["hand_r"], B.P[k], PALM_R])
			continue
		var c: Array = B.cap(j)
		o.append([c[0], c[1], float(B.rad[j])])
	return o


## open: 0 = the pinch pose with the index opened to leave the rope's gap; >0 opens the fingers further (release)
func set_open(open: float) -> void:
	for j in idx_ang0:
		B.ang[j] = (idx_ang0[j] as Vector3) * (1.0 - open) + Vector3(0, 0, 0) * open
	B.fk()


func pinch_world() -> Vector3:
	return (B.P["hand_r"] as Vector3) + (B.G["hand_r"] as Quaternion) * pin_local


func axis_world() -> Vector3:
	return ((B.G["hand_r"] as Quaternion) * ax_local).normalized()


## shape the pinch: the index scaled until the surface gap of the two tip capsules = rope diameter + 1 mm
func make_pinch(r_rope: float) -> void:
	B.hand_pose("r", "pinch")
	# CH6b: the free fingers are closed into the palm (Body.POSE_FIST, the measured fist), clear of the rope; at 2x the pinch
	# pose they hung 5 cm below the pinch and raked the hole's bottom strand and the peg loop along with the hand
	var fj := ["middle", "ring", "pinky"]
	for fi in 3:
		for k in 3:
			var j := "%s_0%d_r" % [fj[fi], k + 1]
			B.ang[j] = B.clamp_ang(j, Body.POSE_FIST[3 * (fi + 1) + k])
	B.fk()
	idx_ang0.clear()
	for j in ["index_01_r", "index_02_r", "index_03_r"]:
		idx_ang0[j] = B.ang[j]
	var lo := 0.0   # open
	var hi := 1.0
	var want := 2.0 * r_rope + 0.001
	for it in 30:
		var m := (lo + hi) * 0.5   # m = how far OPEN
		set_open(m)
		var t: Array = B.cap("thumb_03_r")
		var i: Array = B.cap("index_03_r")
		var g := Body.seg_seg(t[0], t[1], i[0], i[1]) - float(B.rad["thumb_03_r"]) - float(B.rad["index_03_r"])
		if g > want:
			hi = m
		else:
			lo = m
	set_open(hi)
	var t2: Array = B.cap("thumb_03_r")
	var i2: Array = B.cap("index_03_r")
	var st := RopeSim._closest(t2[0], t2[1], i2[0], i2[1])
	var pt: Vector3 = (t2[0] as Vector3) + ((t2[1] as Vector3) - (t2[0] as Vector3)) * st[0]
	var pi: Vector3 = (i2[0] as Vector3) + ((i2[1] as Vector3) - (i2[0] as Vector3)) * st[1]
	var nrm := (pi - pt).normalized()
	var mid := pt + nrm * (float(B.rad["thumb_03_r"]) + r_rope + 0.0005)
	var u := ((i2[1] as Vector3) - (i2[0] as Vector3)).normalized()
	var s := nrm.cross(u).normalized()
	# the rope leaves the pinch along -ax: pick the sign of ax whose exit line is clearest of the other capsules
	var best_sign := 1.0
	var best_clear := -INF
	for sg in [1.0, -1.0]:
		var clear := INF
		for k in range(1, 7):
			var q: Vector3 = mid - s * sg * (0.01 * k)
			for c in caps_now():
				var cs := RopeSim._closest(q, q + Vector3(1e-5, 0, 0), c[0], c[1])
				var cp: Vector3 = (c[0] as Vector3) + ((c[1] as Vector3) - (c[0] as Vector3)) * cs[1]
				clear = minf(clear, q.distance_to(cp) - float(c[2]))
		if clear > best_clear:
			best_clear = clear
			best_sign = sg
	var Gi: Quaternion = (B.G["hand_r"] as Quaternion).inverse()
	pin_local = Gi * (mid - (B.P["hand_r"] as Vector3))
	ax_local = Gi * (s * best_sign)
	log["pinch_gap_mm"] = (pt.distance_to(pi) - float(B.rad["thumb_03_r"]) - float(B.rad["index_03_r"])) * 1000.0
	log["exit_clear_mm"] = best_clear * 1000.0


## move the wrist so the pinch point lands on `target` (world); returns the miss (m)
func reach_pinch(target: Vector3) -> float:
	var miss := 0.0
	for it in 12:
		var cur := pinch_world()
		var wr: Vector3 = (B.P["hand_r"] as Vector3) + (target - cur)
		B.reach("hand_r", wr)
		miss = pinch_world().distance_to(target)
		if miss < 0.0003:
			break
	return miss


## CH6b: clearance of the hand from the rope: the smallest surface gap (m) between any hand capsule and any rope particle
## within 0.18 m of the pinch, the held stub (and the next 4 particles, which leave the pinch) excluded
func hand_clear(xs: PackedVector3Array, skip_end := 7) -> float:
	var pw := pinch_world()
	var n := xs.size()
	var m := INF
	var caps := caps_now()
	for i in n - skip_end:
		var q: Vector3 = xs[i]
		if q.distance_squared_to(pw) > 0.0324:
			continue
		for c in caps:
			var a: Vector3 = c[0]
			var ab: Vector3 = (c[1] as Vector3) - a
			var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 1e-12), 0.0, 1.0)
			m = minf(m, q.distance_to(a + ab * t) - float(c[2]) - Ch6Knot.R_ROPE)
	return m


## CH6b: a wrist that keeps the hand off the rope. Each frame the wrist (hand_r bend / side / twist, inside its limits) tries
## its current angles and one step either way on each axis, the pinch put back on the target each time (reach_pinch), and keeps
## the most clearance (capped at 2 cm, so it does not wander once clear). Returns the pinch miss.
func reach_pinch_clear(target: Vector3, xs_world: PackedVector3Array, step := 4.0) -> float:
	var a0: Vector3 = B.ang["hand_r"]
	var best := a0
	var best_s := -INF
	var cands: Array = [a0]
	for ax in 3:
		for sg in [-1.0, 1.0]:
			var d := Vector3.ZERO
			d[ax] = step * sg
			cands.append(a0 + d)
	var snap: Dictionary = B.ang.duplicate()
	for c in cands:
		B.ang = snap.duplicate()
		B.ang["hand_r"] = B.clamp_ang("hand_r", c)
		B.fk()
		var miss := reach_pinch(target)
		var s := minf(hand_clear(xs_world), 0.02) - miss * 10.0 - (0.0 if c == a0 else 0.0005)
		if s > best_s:
			best_s = s
			best = B.ang["hand_r"]
	B.ang = snap
	B.ang["hand_r"] = best
	B.fk()
	return reach_pinch(target)


func colliders(prev: Array, cur: Array, peg: Array) -> Array:
	var a0 := PackedVector3Array()
	var b0 := PackedVector3Array()
	var a1 := PackedVector3Array()
	var b1 := PackedVector3Array()
	var rad := PackedFloat32Array()
	var mus := PackedFloat32Array()
	a0.append(peg[0])
	b0.append(peg[1])
	a1.append(peg[0])
	b1.append(peg[1])
	rad.append(Ch6Knot.PEG_R)
	mus.append(0.4)
	for i in cur.size():
		var p: Array = prev[i] if prev.size() > i else cur[i]
		a0.append(p[0])
		b0.append(p[1])
		a1.append(cur[i][0])
		b1.append(cur[i][1])
		rad.append(cur[i][2])
		mus.append(0.5)
	return [a0, b0, a1, b1, rad, mus]


static func _mean(P: PackedVector3Array, idx: Array) -> Vector3:
	var m := Vector3.ZERO
	for i in idx:
		m += P[i]
	return m / maxf(1.0, float(idx.size()))


func load_at(f: int, fmax: float) -> float:
	# seat: 0 -> fmax in 120 frames, hold to 330; unload to 20 by 360; hold to 390; re-ramp to 510; hold to the end
	if f < 120:
		return float(f) / 120.0 * fmax
	if f < 330:
		return fmax
	if f < 360:
		return fmax - float(f - 330) / 30.0 * (fmax - 20.0)
	if f < 390:
		return 20.0
	if f < 510:
		return 20.0 + float(f - 390) / 120.0 * (fmax - 20.0)
	return fmax


## opts: mu (0.4), wrong (false), speed (0.08 m/s), fmax (120 N), hand (true), keep_hand (false: only record the rope)
func run(opts := {}) -> Dictionary:
	var mu: float = opts.get("mu", 0.4)
	var wrong: bool = opts.get("wrong", false)
	var speed: float = opts.get("speed", 0.08)
	var fmax: float = opts.get("fmax", 120.0)
	var lay := Ch6Knot.layout()
	var pts := PackedVector3Array()
	for q in lay:
		pts.append(q + O)
	rope = RopeSim.new()
	rope.setup(pts, Ch6Knot.DS, Ch6Knot.R_ROPE, {"mass": 0.3, "mu": mu, "kb": 0.003, "iters": 24, "subs": 16, "damp": 0.98,
		"kin": 1.0 if opts.get("kin", true) else 0.0, "adapt": float(opts.get("adapt", 0.5)), "selfcol": 1.0 if opts.get("selfcol", true) else 0.0})
	var n := pts.size()
	var peg := [O + Ch6Knot.PEG + Vector3(0, 0, -0.2), O + Ch6Knot.PEG + Vector3(0, 0, 0.2)]
	make_pinch(Ch6Knot.R_ROPE)
	var plan := Ch6Knot.tie_plan(lay[n - 1], speed, wrong)
	var path: PackedVector3Array = plan["path"]
	var ptarget: PackedVector3Array = plan["target"]
	var pmode: PackedStringArray = plan["mode"]
	var stub_local := Vector3.ZERO   # CH6b: the held stub's direction (pinch -> rope body) in the hand's frame, taken at each grasp
	var held := true
	var drift := Vector3.ZERO
	var slip := Vector3.ZERO
	var slip_dir := Vector3.ZERO
	var escape := Vector3.ZERO
	var stub_rest: Array = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	# the hand starts on the end of the rope
	var miss0 := reach_pinch(pts[n - 1])
	prev_caps = caps_now()
	var frames: Array = []
	var hand: Array = []
	var selfpen := PackedFloat32Array()
	var colpen := PackedFloat32Array()
	var missv := PackedFloat32Array()
	var tens := PackedFloat32Array()
	var s0y := PackedFloat32Array()
	var tail := PackedVector3Array()
	var phase := {}
	rope.drive(0, pts[0], pts[0])   # S0 pinned while tying
	# live features (closed loop): the standing part A below the hole, the hole circle, and the off-hand grip on the crossing
	var a_idx: Array = []
	var h_idx: Array = []
	var g_idx: Array = []
	var hold_c := Vector3(-0.10, 0.0, 0.0)   # the off hand pinches the left arc of the hole
	for i in n:
		var q: Vector3 = lay[i]
		if i < 60 and q.y > -0.12 and q.y < -0.08 and absf(q.x) < 0.01:
			a_idx.append(i)
		if i < 80 and absf(Vector2(q.x + 0.05, q.y).length() - 0.05) < 0.004 and q.y > -0.04 and q.x > -0.05:
			h_idx.append(i)
		if i < 80 and absf(Vector2(q.x + 0.05, q.y).length() - 0.05) < 0.004 and q.y > -0.045:   # the whole ring is held open
			g_idx.append(i)
	var a_ref := _mean(pts, a_idx)
	var h_ref := _mean(pts, h_idx)
	# CH6b: the standing part (the "tree") from S0 up to the hole is held taut while tying, as the load / the off hand holds it
	# in a real tie; without it the turn of the working end round it dragged it 12 cm sideways and stretched it to 2.5 ds
	# and the off hand's pinch takes the whole crossing: the hole's bottom strand up to and over the standing part (without it the
	# hand pushed the bottom strand down past the end on the way DOWN, which un-threads the end)
	if opts.get("hold_tree", true):
		var g0: int = g_idx.min() if not g_idx.is_empty() else n
		for i in range(1, g0):
			if absf(lay[i].x) < 0.012:
				g_idx.append(i)
		var g1 := g0
		for i in range(g0, mini(n, 100)):
			if absf(lay[i].y + 0.05) < 0.008 and lay[i].x > -0.06 and lay[i].x < 0.04:
				g1 = i
		for i in range(g0, g1 + 1):   # contiguous: a free particle between two held ones is crushed by a passing finger
			if not g_idx.has(i):
				g_idx.append(i)
	var grip_pos := {}
	for i in g_idx:
		grip_pos[i] = pts[i]
	log["grip_particles"] = g_idx.size()
	var dt := 1.0 / FPS
	var total_force_frames := 600
	var hand_frames := path.size() + 40
	var nframes := hand_frames + (0 if opts.get("tie_only", false) else total_force_frames)
	var open_cur := 0.0
	for f in nframes:
		var xs := rope.positions()
		var miss := 0.0
		var in_tie := f < path.size()
		if f < hand_frames:
			if in_tie:
				var dA := _mean(xs, a_idx) - a_ref
				var dH := _mean(xs, h_idx) - h_ref
				dA.y = 0.0
				dA = dA.limit_length(0.012)   # bounded: a feature the hand itself shoves must not make the hand chase it
				dH = dH.limit_length(0.012)
				var wy := clampf((-0.07 - path[f].y) / 0.02, 0.0, 1.0)   # 1 below the hole: anchored to the standing part
				var tgt: Vector3 = ptarget[f] + O + dA * wy + dH * (1.0 - wy)
				var md: String = pmode[f]
				if md == "seek" or md == "close":
					drift = (xs[n - 1] - O) - path[f]
					tgt += drift
				elif md == "hold":
					drift *= 0.92   # back onto the keyed path over ~1 s after a regrip
					tgt += drift
				# letting go: the end sits AT the pinch, so the opened fingertips slide off it toward its free end (-stub direction);
				# backing the hand off along the rope instead dragged the end 9 cm with it
				if md == "open":
					if held:
						slip_dir = -((B.G["hand_r"] as Quaternion) * stub_local).normalized()
					open_cur = minf(1.0, open_cur + 1.0 / 8.0)
					set_open(open_cur)
					held = false
					slip = slip_dir * (0.035 * open_cur)
				elif md == "close":
					open_cur = maxf(0.0, open_cur - 1.0 / 6.0)
					set_open(open_cur)
					if not held:
						held = true
						var Gi: Quaternion = (B.G["hand_r"] as Quaternion).inverse()
						stub_local = Gi * (xs[n - 2] - xs[n - 1]).normalized()
				if md == "seek" or md == "close" or md == "hold":
					slip *= 0.85
				tgt += slip
				# CH6b pass 2: the empty hand first backs out of the rope it is wrapped in (the working part lies in the thumb-index
				# web): each "free" frame the pinch target may step 6 mm along one of the six axes, whichever leaves the most room
				# between the hand and the rope (only the 3 held end particles excluded); kept through the transit, faded in "seek"
				if md == "free":
					var snap: Dictionary = B.ang.duplicate()
					var best_e := escape
					var best_c := -INF
					for d in [Vector3.ZERO, Vector3(0.006, 0, 0), Vector3(-0.006, 0, 0), Vector3(0, 0.006, 0), Vector3(0, -0.006, 0), Vector3(0, 0, 0.006), Vector3(0, 0, -0.006)]:
						B.ang = snap.duplicate()
						B.fk()
						reach_pinch(tgt + escape + d)
						var c := minf(hand_clear(xs, 3), 0.015) - (0.0 if d == Vector3.ZERO else 0.0002)
						if c > best_c:
							best_c = c
							best_e = escape + d
					B.ang = snap
					B.fk()
					escape = best_e
				elif md == "seek" or md == "close" or md == "hold":
					escape *= 0.85
				tgt += escape
				miss = reach_pinch_clear(tgt, xs) if opts.get("wrist_clear", true) else reach_pinch(tgt)
			else:
				# release: open the pinch a little (CH6b: to 0.4 over 12 frames, standing still; opening fully at once flicked
				# the end 7 cm across the hole), then draw the hand back along -z
				var k := f - path.size()
				open_cur = minf(0.4, float(k) / 30.0)
				set_open(open_cur)
				if k >= 12:
					B.reach("hand_r", (B.P["hand_r"] as Vector3) + Vector3(0, 0, -0.004))
		var cur := caps_now()
		var cl := colliders(prev_caps, cur, peg)
		rope.set_colliders(cl[0], cl[1], cl[2], cl[3], cl[4], cl[5])
		prev_caps = cur
		if in_tie:
			var pw := pinch_world()
			if stub_local == Vector3.ZERO:
				stub_local = -ax_local
			var sd: Vector3 = ((B.G["hand_r"] as Quaternion) * stub_local).normalized()
			# rope end at the pinch; the stub runs from it along sd (toward the rope's body)
			for k in STUB:
				if held:
					var from: Vector3 = xs[n - 1 - k]
					rope.drive(n - 1 - k, from, pw + sd * (float(k) * Ch6Knot.DS))
					stub_rest[k] = pw + sd * (float(k) * Ch6Knot.DS)
				else:
					# during a regrip the off hand keeps the end where the working hand left it (the off hand is not a rig hand:
					# a kinematic grip, like its grip on the crossing)
					rope.drive(n - 1 - k, xs[n - 1 - k], stub_rest[k])
			for i in g_idx:   # the off hand pinches the crossing: a kinematic grip, released with the working-end pinch
				rope.drive(i, xs[i], grip_pos[i])
		else:
			for k in STUB:
				rope.undrive(n - 1 - k)
			for i in g_idx:
				rope.undrive(i)
			if f == path.size():
				rope.undrive(0)
				phase["tie_end"] = f
		if f >= hand_frames:
			var lf := f - hand_frames
			rope.set_force(0, Vector3(0, -load_at(lf, fmax), 0))
			if lf == 0:
				phase["load_start"] = f
			if lf == 330:
				phase["seat_end"] = f
			if lf == 390:
				phase["unload_end"] = f
		rope.step(dt)
		var xr := rope.positions()
		if f % 15 == 0 and f <= path.size() + 15:
			var dq := PackedVector3Array()
			for q in xr:
				dq.append(q - O)
			log["trace_%03d" % f] = "gauss0=%d best=%s a=%s h=%s" % [Ch6Knot.gauss(dq).size(), Ch6Knot.code_str(Ch6Knot.best_code(dq, 10)), str(_mean(dq, a_idx)), str(_mean(dq, h_idx))]
		var kf := PackedVector3Array()
		for q in xr:
			kf.append(q - O)
		frames.append(kf)
		if f < hand_frames:
			var snap := {}
			for j in B.ang:
				snap[j] = B.ang[j]
			hand.append(snap)
		else:
			hand.append(hand[hand.size() - 1])
		selfpen.append(rope.max_self_pen())
		colpen.append(rope.max_col_pen(true))
		missv.append(miss)
		tens.append(rope.tension())
		s0y.append(kf[0].y)
		tail.append(kf[n - 1])
	phase["hand_end"] = hand_frames
	phase["end"] = nframes
	return {"frames": frames, "hand": hand, "selfpen": selfpen, "colpen": colpen, "miss": missv, "tension": tens, "s0y": s0y, "tail": tail,
		"phase": phase, "path": path, "layout": lay, "miss0": miss0, "log": log, "native": rope.is_native(), "n": n}
