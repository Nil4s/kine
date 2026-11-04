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
const HAND_JOINTS := ["hand_r", "lowerarm_r"]
const FINGERS := ["thumb", "index", "middle", "ring", "pinky"]
const STUB := 3

var B: Body
var rope: RopeSim
var pin_local := Vector3.ZERO   # the pinch point in the hand's frame
var ax_local := Vector3.ZERO    # the stub axis (end -> body of the rope) in the hand's frame, pointing to the free end
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
	var mid := (pt + pi) * 0.5
	var nrm := (pi - pt).normalized()
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
	for it in 4:
		var cur := pinch_world()
		var wr: Vector3 = (B.P["hand_r"] as Vector3) + (target - cur)
		B.reach("hand_r", wr)
		miss = pinch_world().distance_to(target)
		if miss < 0.0005:
			break
	return miss


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
	rope.setup(pts, Ch6Knot.DS, Ch6Knot.R_ROPE, {"mass": 0.3, "mu": mu, "kb": 0.003, "iters": 24, "subs": 16, "damp": 0.98})
	var n := pts.size()
	var peg := [O + Ch6Knot.PEG + Vector3(0, 0, -0.2), O + Ch6Knot.PEG + Vector3(0, 0, 0.2)]
	make_pinch(Ch6Knot.R_ROPE)
	var path := Ch6Knot.tip_path(lay[n - 1], speed, wrong)
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
	var dt := 1.0 / FPS
	var total_force_frames := 600
	var hand_frames := path.size() + 40
	var nframes := hand_frames + total_force_frames
	var open_cur := 0.0
	for f in nframes:
		var xs := rope.positions()
		var miss := 0.0
		var in_tie := f < path.size()
		if f < hand_frames:
			if in_tie:
				miss = reach_pinch(path[f] + O)
			else:
				# release: open the pinch (10 frames), drawing the hand back along -z
				var k := f - path.size()
				open_cur = minf(1.0, float(k) / 10.0)
				set_open(open_cur)
				B.reach("hand_r", (B.P["hand_r"] as Vector3) + Vector3(0, 0, -0.004))
		var cur := caps_now()
		var cl := colliders(prev_caps, cur, peg)
		rope.set_colliders(cl[0], cl[1], cl[2], cl[3], cl[4], cl[5])
		prev_caps = cur
		if in_tie:
			var pw := pinch_world()
			var ax := axis_world()
			# rope end at the pinch; the stub runs back along -ax... the free end of the stub points to +ax
			for k in STUB:
				var from: Vector3 = xs[n - 1 - k]
				rope.drive(n - 1 - k, from, pw - ax * (float(k) * Ch6Knot.DS))
		else:
			for k in STUB:
				rope.undrive(n - 1 - k)
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
		colpen.append(rope.max_col_pen(false))
		missv.append(miss)
		tens.append(rope.tension())
		s0y.append(kf[0].y)
		tail.append(kf[n - 1])
	phase["hand_end"] = hand_frames
	phase["end"] = nframes
	return {"frames": frames, "hand": hand, "selfpen": selfpen, "colpen": colpen, "miss": missv, "tension": tens, "s0y": s0y, "tail": tail,
		"phase": phase, "path": path, "layout": lay, "miss0": miss0, "log": log, "native": rope.is_native(), "n": n}
