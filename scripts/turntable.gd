class_name Turntable
## TURNTABLE (the command "Deliver: turntable video of this pose"; the render loop is main.gd's _export_turntable).
## A 360 degree orbit of the CAMERA around the standing body (the body does not turn, so the light and the floor stay put),
## the standard way a character / model is presented. Frame k of n looks from yaw0 + 360 * k / n: the last frame is one step
## short of a full turn, so the video loops with no repeated frame. n = seconds * fps.
## FRAMING: the camera looks at the pelvis from a distance chosen so that, at EVERY yaw, every point of the body (and of the
## held weapons) projects inside the frame with MARGIN (15%) to spare: the body fills at most 1 / 1.15 of the half-frame.

const ROOT := "user://turntables"
const MARGIN := 1.15
const BODY_R := 0.09    # m: the body's limbs are fatter than the bones' end points; head top and soles get this much room
const WEAPON_R := 0.05


static func frame_count(seconds: float, fps: int) -> int:
	return maxi(1, roundi(seconds * fps))


static func yaw_of(k: int, n: int, yaw0 := 0.0) -> float:
	return yaw0 + 360.0 * float(k) / float(n)


## the points that must stay in the frame: [[position, radius], ...] (every bone start and end, the weapons' knob and tip)
static func points(B: Body) -> Array:
	var out := []
	for j in B.P:
		out.append([B.P[j] as Vector3, BODY_R])
		if B.E.has(j):
			out.append([B.E[j] as Vector3, BODY_R])
	if B.wep_on:
		for u in 5:
			out.append([B.wep_point(B.wep_len * float(u) / 4.0), WEAPON_R])
	if B.wep2_on:
		for u in 5:
			out.append([B.wep2_point(B.wep2_len() * float(u) / 4.0), WEAPON_R])
	return out


## the smallest camera distance from `centre` such that, at every yaw (5 degree steps), every point projects inside the
## frame with `margin`. fov: the vertical field of view of the VIEWPORT (deg); fy: the share of the viewport's height the
## frame covers (< 1 when the viewport is narrower than the frame's aspect); aspect: frame width / height
static func fit(pts: Array, centre: Vector3, pitch_deg: float, fov_deg: float, aspect: float, fy := 1.0, margin := MARGIN) -> float:
	var ty := tan(deg_to_rad(fov_deg * 0.5)) * fy
	var tx := ty * aspect
	var best := 0.5
	for yd in range(0, 360, 5):
		var inv := Basis.from_euler(Vector3(deg_to_rad(pitch_deg), deg_to_rad(float(yd)), 0)).inverse()
		for p in pts:
			var q: Vector3 = inv * ((p[0] as Vector3) - centre)
			var r: float = p[1]
			best = maxf(best, q.z + (absf(q.y) + r) * margin / ty)
			best = maxf(best, q.z + (absf(q.x) + r) * margin / tx)
	return best


## the largest rectangle of the frame's aspect, centred in a viewport of size vs
static func crop_rect(vs: Vector2, aspect: float) -> Rect2i:
	var w := vs.y * aspect
	var h := vs.y
	if w > vs.x:
		w = vs.x
		h = vs.x / aspect
	return Rect2i(int((vs.x - w) * 0.5), int((vs.y - h) * 0.5), int(w), int(h))
