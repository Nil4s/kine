## arc_check.gd - ARC CHECKER (ROADMAP L26). Natural motion follows arcs (the "arcs" principle of the twelve: Thomas & Johnston,
## The Illusion of Life; Williams, The Animator's Survival Kit): a limb swinging on a pivot draws a smooth curve, and a KINK in
## its path (a sudden change of direction without a stop) reads as mechanical.
## The scene is sampled at 60 Hz for the wrists, ankles, head and the weapon tip (world positions). On each path:
##   TURN(i)   the angle between the chord arriving at frame i (p[i]-p[i-W]) and the chord leaving it (p[i+W]-p[i]), W = 3 frames.
##   KINK(i)   TURN(i) minus the largest turn measured a window either side (the curve's own bend there: CURVATURE CONTINUITY): a
##             smooth arc has the same turn all along, a corner is a spike. Flagged when the excess is at least KINK_DEG and
##             TURN(i) itself at least TURN_DEG. With no measurable neighbour (a scene shorter than 4 windows of motion) nothing is judged.
##   SPEED     a stop-and-reverse is NOT a kink (the speed goes to zero at the turn): every per-frame speed in the window
##             [i-W, i+W] must stay above SPEED_FLOOR, else the frame is skipped. A planted ankle (heel and ball on the floor)
##             is a contact, not a path: its frames are skipped too.
## Local maxima within MERGE s of each other are one kink. The finding's angle is the turn of the path there; severity by that turn (HIGH >= 90, MED >= 55, else LOW); "excess" is how far it exceeds the curve's own bend.
## Findings: {"joint", "t", "angle", "excess", "speed", "sev", "pos", "card"} sorted worst first by angle.
## Only "Check: arcs (kinks in the paths)" opens this (main.gd): the default Check never calls it.
class_name ArcCheck
extends RefCounted

const FPS := 60.0
const W := 6               # frames each side of a frame for the chords (0.1 s, ours: a spline spreads a corner over a key spacing)
const TURN_DEG := 30.0     # ours: the turn at a kink must be at least this ...
const KINK_DEG := 25.0     # ... and exceed the turns a window either side by this (a circle of 0.3 m at 2 m/s turns 38 deg per 6 frames)
const SPEED_FLOOR := 0.5   # m/s, ours: below this in the window the part is stopping or starting, not cornering
const REL_FLOOR := 0.4      # ours: the slowest frame in the window must keep this share of the fastest
const MERGE := 0.15        # s: kinks closer than this are one
const HIGH := 90.0
const MED := 55.0
const JOINTS := ["hand_l", "hand_r", "foot_l", "foot_r", "head", "tip"]


## the sampled paths of a scene: {"joint": {"p": [Vector3 per frame], "ok": [bool per frame: the part is free (not planted/absent)]}}
static func sample(S: Scene, B: Body) -> Dictionary:
	var n := int(ceil(S.length() * FPS)) + 1
	var out := {}
	for j in JOINTS:
		out[j] = {"p": [], "ok": []}
	var was := S.stepped
	S.stepped = false
	for i in n:
		S.apply(B, minf(i / FPS, S.length()))
		for j in JOINTS:
			var free := true
			var p := Vector3.ZERO
			if j == "tip":
				free = B.wep_on
				p = B.wep_point(B.wep_len) if B.wep_on else Vector3.ZERO
			else:
				p = B.P[j]
			if j.begins_with("foot"):
				var fs: Array = B.foot_state(j.substr(4))
				free = not (bool(fs[2]) and bool(fs[3]))   # ball and heel both on the floor: planted
			out[j]["p"].append(p)
			out[j]["ok"].append(free)
	S.stepped = was
	return out


## the angle (deg) between two chords
static func _ang(a: Vector3, b: Vector3) -> float:
	var la := a.length()
	var lb := b.length()
	if la < 1e-9 or lb < 1e-9:
		return 0.0
	return rad_to_deg(acos(clampf(a.dot(b) / (la * lb), -1.0, 1.0)))


## the turn at frame i, or -1 when the part is not free / too slow anywhere in [i-W, i+W]
static func turn_at(p: Array, ok: Array, i: int, fps := FPS) -> float:
	if i - W < 0 or i + W >= p.size():
		return -1.0
	for k in range(i - W, i + W + 1):
		if not ok[k]:
			return -1.0
	var lo := INF
	var hi := 0.0
	for k in range(i - W + 1, i + W + 1):
		var v: float = ((p[k] as Vector3) - p[k - 1]).length() * fps
		lo = minf(lo, v)
		hi = maxf(hi, v)
	if lo < SPEED_FLOOR or lo < REL_FLOOR * hi:
		return -1.0   # slow, or dipping towards a stop inside the window: a stop-and-reverse, not a corner
	return _ang((p[i] as Vector3) - p[i - W], (p[i + W] as Vector3) - p[i])


## kinks on one path (positions per frame at fps, ok = free flags): [{"i", "t", "angle", "turn", "speed", "sev"}]
static func kinks_in(p: Array, ok: Array, fps := FPS) -> Array:
	var n := p.size()
	var turn := []
	for i in n:
		turn.append(turn_at(p, ok, i, fps))
	var spike := []
	for i in n:
		var t: float = turn[i]
		if t < TURN_DEG:
			spike.append(0.0)
			continue
		var ref := []   # the turns a window either side: the curve's own bend. An unmeasured side (a stop, a planted foot, the scene's end) is left out
		for q in [i - 2 * W, i + 2 * W]:
			if q >= 0 and q < n and float(turn[q]) >= 0.0:
				ref.append(float(turn[q]))
		if ref.is_empty():
			spike.append(0.0)   # no curve to compare with: cannot judge a corner
			continue
		spike.append(t - ref.max())
	var cand := []
	for i in n:
		var s: float = spike[i]
		if s < KINK_DEG:
			continue
		if (i > 0 and spike[i - 1] > s) or (i + 1 < n and spike[i + 1] >= s and spike[i + 1] > s):
			continue   # a local maximum only
		cand.append(i)
	var out := []
	for i in cand:
		if not out.is_empty() and float(i - out[-1]["i"]) / fps < MERGE:
			if spike[i] > out[-1]["excess"]:
				out.pop_back()
			else:
				continue
		var sp := 0.0
		for k in range(i - W + 1, i + W + 1):
			sp += ((p[k] as Vector3) - p[k - 1]).length() * fps
		sp /= 2.0 * W
		var tn: float = turn[i]
		out.append({"i": i, "t": i / fps, "angle": tn, "excess": spike[i], "speed": sp,
			"sev": "HIGH" if tn >= HIGH else ("MED" if tn >= MED else "LOW")})
	return out


## every kink in a scene, worst first: [{"joint", "t", "angle", "turn", "speed", "sev", "pos": world position, "card"}]
static func check(S: Scene, B: Body, sm := {}) -> Array:
	if sm.is_empty():
		sm = sample(S, B)
	var out := []
	for j in JOINTS:
		for k in kinks_in(sm[j]["p"], sm[j]["ok"]):
			k["joint"] = j
			k["pos"] = sm[j]["p"][k["i"]]
			k["card"] = Rulebook.card_at(S, k["t"])
			out.append(k)
	out.sort_custom(func(a, b): return a["angle"] > b["angle"])
	return out


static func nice(j: String) -> String:
	return {"hand_l": "left wrist", "hand_r": "right wrist", "foot_l": "left ankle", "foot_r": "right ankle", "head": "head", "tip": "weapon tip"}.get(j, j)


## the fix in words, shown under each finding
const FIX := "round it: add a breakdown key that pulls the path onto an arc, or ease the turn over more frames"


## a finding as one line
static func words(k: Dictionary) -> String:
	return "%s  %s: the path turns %.0f deg at %.1f m/s without stopping (%.0f deg beyond its own curve) - %s" % [
		k["sev"], nice(k["joint"]), k["angle"], k["speed"], k["excess"], FIX]



## THE VIEW: the kinked joints' whole paths as a line (reuses the motion trail's look: unshaded, seen through the body) and a
## big dot at each kink. Colours are Tok tokens (fail = HIGH, warn = the rest). Returns the world positions of the dots.
static func draw_view(mi: MeshInstance3D, sm: Dictionary, ks: Array) -> Array:
	var im := mi.mesh as ImmediateMesh
	im.clear_surfaces()
	var marks := []
	if ks.is_empty():
		mi.visible = false
		return marks
	var seen := {}
	for k in ks:
		if seen.has(k["joint"]):
			continue
		seen[k["joint"]] = true
		im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, Overlays._mat())
		var ps: Array = sm[k["joint"]]["p"]
		var ok: Array = sm[k["joint"]]["ok"]
		for i in ps.size():
			if ok[i]:
				im.surface_set_color(Tok.of("warn"))
				im.surface_add_vertex(ps[i])
		im.surface_end()
	im.surface_begin(Mesh.PRIMITIVE_POINTS, Overlays._mat(18.0))
	for k in ks:
		im.surface_set_color(Tok.of("fail") if k["sev"] == "HIGH" else Tok.of("warn"))
		im.surface_add_vertex(k["pos"])
		marks.append(k["pos"])
	im.surface_end()
	mi.visible = true
	return marks
