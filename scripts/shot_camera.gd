## shot_camera.gd - THE SHOT CAMERA (docs/GAP_ANALYSIS.md row 21; numbers and sources: docs/research/SHOT_CAMERA.md).
##
## A scene may hold ONE keyed camera: Scene.camera = [{"t": s, "pos": Vector3, "aim": Vector3, "f": mm}, ...] sorted by t.
## pos = where the lens is, aim = the point it looks at (Blender's Track To), both in the HERO's world space (metres,
## y up, +z his front); f = focal length in mm on a 36 mm wide sensor (Blender's default, sensor fit to the width of a
## 16:9 frame). No roll: the camera's up is the world's up.
## BETWEEN KEYS pos, aim and f each follow PartKeys.at: the same monotone cubic (PCHIP, Blender's auto-clamped) the part
## keys and the IK targets use, held past the first and last key.
## LENS: the frame is 16:9; its vertical angle is   fov_v = 2 atan(sensor_h / 2 / f),  sensor_h = 36 / (16 / 9) = 20.25 mm
## (50 mm -> 22.895 deg vertical, 2 atan(18 / 50) = 39.598 deg horizontal).
## FRAME: the 16:9 rectangle the shot is drawn in (look-through) or cut from (playblast): the largest one (height a
## multiple of 18 px, so both sides are even) inside the free part of the view. The viewport's own camera is set so the
## shot camera's view lands exactly in that rectangle: a perspective frustum whose height at the near plane covers the
## whole viewport at the frame's scale, shifted so the axis goes through the frame's centre (Camera3D FRUSTUM mode).
## In the FILE: "camera": [{"t", "pos": [x, y, z], "aim": [x, y, z], "f"}], written only when there is one.
class_name ShotCam
extends RefCounted

const SENSOR_W := 36.0          # mm, Blender's default sensor width (and 35 mm still film's 36 x 24 gate)
const ASPECT := 16.0 / 9.0      # the frame
const F_DEFAULT := 50.0         # mm, Blender's default lens
const F_MIN := 8.0
const F_MAX := 600.0
const LENSES := [18, 24, 35, 50, 85, 135]   # the presets offered as commands (common prime lenses)
const SAME_T := 0.001


static func sensor_h() -> float:
	return SENSOR_W / ASPECT


## the frame's vertical angle (deg) for a focal length f (mm)
static func fov_v(f: float) -> float:
	return rad_to_deg(2.0 * atan(sensor_h() * 0.5 / f))


static func fov_h(f: float) -> float:
	return rad_to_deg(2.0 * atan(SENSOR_W * 0.5 / f))


## the focal length (mm) that gives this vertical angle (deg) in the frame
static func f_for_fov_v(deg: float) -> float:
	return sensor_h() * 0.5 / tan(deg_to_rad(deg) * 0.5)


## the camera at time t: {"pos", "aim", "f"} ({} = no keys)
static func sample(keys: Array, t: float) -> Dictionary:
	if keys.is_empty():
		return {}
	var pk := []
	var ak := []
	var fk := []
	for k in keys:
		pk.append({"t": k["t"], "v": k["pos"]})
		ak.append({"t": k["t"], "v": k["aim"]})
		fk.append({"t": k["t"], "v": Vector3(float(k["f"]), 0, 0)})
	return {"pos": PartKeys.at(pk, t), "aim": PartKeys.at(ak, t), "f": clampf(PartKeys.at(fk, t).x, F_MIN, F_MAX)}


## the camera's transform (looking from pos at aim, world up)
static func xf(pos: Vector3, aim: Vector3) -> Transform3D:
	var d := aim - pos
	if d.length() < 1e-6:
		d = Vector3(0, 0, -1)
	var up := Vector3.UP if absf(d.normalized().y) < 0.999 else Vector3(0, 0, -1)
	return Transform3D(Basis.looking_at(d, up), pos)


## key at t (replacing a key within SAME_T); keeps the list sorted; returns its index
static func put(keys: Array, key: Dictionary) -> int:
	var t := float(key["t"])
	for i in keys.size():
		if absf(float(keys[i]["t"]) - t) < SAME_T:
			keys[i] = key
			return i
	keys.append(key)
	keys.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
	return keys.find(key)


## the index of the key within tol seconds of t (nearest), or -1
static func key_near(keys: Array, t: float, tol: float) -> int:
	var best := -1
	var bd := tol
	for i in keys.size():
		var d := absf(float(keys[i]["t"]) - t)
		if d <= bd:
			best = i
			bd = d
	return best


## THE FRAME: the largest 16:9 rectangle (height a multiple of 18 px) centred in `free` (a Rect2 in viewport pixels)
static func frame_rect(free: Rect2) -> Rect2i:
	var h := int(floor(minf(free.size.y, free.size.x / ASPECT) / 18.0)) * 18
	h = maxi(h, 18)
	var w := h * 16 / 9
	var x := int(round(free.position.x + (free.size.x - w) * 0.5))
	var y := int(round(free.position.y + (free.size.y - h) * 0.5))
	return Rect2i(x, y, w, h)


## the viewport camera set to show the shot camera (its transform tf: xf(pos, aim), shaken by shot_fx.gd) at focal length f
## inside `rect` of a viewport of size vs
static func apply_to(c: Camera3D, tf: Transform3D, f: float, rect: Rect2i, vs: Vector2) -> void:
	c.h_offset = 0.0
	c.v_offset = 0.0
	c.keep_aspect = Camera3D.KEEP_HEIGHT
	c.global_transform = tf
	var half := tan(deg_to_rad(fov_v(f)) * 0.5)
	var cx := rect.position.x + rect.size.x * 0.5
	var cy := rect.position.y + rect.size.y * 0.5
	if absf(cx - vs.x * 0.5) < 1e-4 and absf(cy - vs.y * 0.5) < 1e-4:
		c.projection = Camera3D.PROJECTION_PERSPECTIVE   # centred (the playblast, a clean view): a plain perspective
		c.fov = rad_to_deg(2.0 * atan(half * vs.y / rect.size.y))
		return
	var s := 2.0 * c.near * half / rect.size.y   # near-plane units per pixel
	c.projection = Camera3D.PROJECTION_FRUSTUM
	c.size = vs.y * s
	c.frustum_offset = Vector2((vs.x * 0.5 - cx) * s, (cy - vs.y * 0.5) * s)


## where world point p lands in the viewport (pixels) through the shot camera drawn in rect; the pinhole model on its
## own (no Godot camera): x right, y down
static func project(pos: Vector3, aim: Vector3, f: float, rect: Rect2i, p: Vector3) -> Vector2:
	var q := xf(pos, aim).affine_inverse() * p
	var k := rect.size.y * 0.5 / tan(deg_to_rad(fov_v(f)) * 0.5)
	return Vector2(rect.position.x + rect.size.x * 0.5 + q.x / -q.z * k, rect.position.y + rect.size.y * 0.5 - q.y / -q.z * k)


# ---------------------------------------------------------------- the file

static func to_file(keys: Array) -> Array:
	return keys.map(func(k): return {"t": snappedf(float(k["t"]), 0.0001),
		"pos": [snappedf(k["pos"].x, 0.00001), snappedf(k["pos"].y, 0.00001), snappedf(k["pos"].z, 0.00001)],
		"aim": [snappedf(k["aim"].x, 0.00001), snappedf(k["aim"].y, 0.00001), snappedf(k["aim"].z, 0.00001)],
		"f": snappedf(float(k["f"]), 0.001)})


static func from_file(d: Variant) -> Array:
	var out := []
	if not d is Array:
		return out
	for k in d:
		if not k is Dictionary or not k.has("pos") or not k.has("aim"):
			continue
		var p: Array = k["pos"]
		var a: Array = k["aim"]
		out.append({"t": maxf(0.0, float(k.get("t", 0.0))), "pos": Vector3(float(p[0]), float(p[1]), float(p[2])),
			"aim": Vector3(float(a[0]), float(a[1]), float(a[2])), "f": clampf(float(k.get("f", F_DEFAULT)), F_MIN, F_MAX)})
	out.sort_custom(func(x, y): return float(x["t"]) < float(y["t"]))
	return out


## MIRROR (Scene.MIRROR_SCENE "camera"): the body mirrors across x = 0 (his left <-> right), so the camera does too:
## pos and aim x negated; the lens and the times stay. On the file form
static func mirror_file(d: Array) -> Array:
	return d.map(func(k): return {"t": k["t"], "pos": [-float(k["pos"][0]), k["pos"][1], k["pos"][2]],
		"aim": [-float(k["aim"][0]), k["aim"][1], k["aim"][2]], "f": k["f"]})
