## REFERENCE IMAGES (ROADMAP_400 B21 + C25): a photo or video frame of a real person under (or behind) the figure, to pose
## against. Pure maths + the file form; the nodes and the panel are scripts/ref_image_ui.gd.
## An entry: {"path" (relative to the scene file when it could be, else absolute), "mode": "camera" | "front" | "side" | "free",
##   "opacity" 0..1, "scale", "offset": [x, y], "flip", and for "free": "pos": [x, y, z], "yaw" deg}.
##   camera   a picture over the 3D view, fitted to the view's height at scale 1; offset is a fraction of the view height
##   front    a plane BEHIND the body seen from the Front view (normal +z, BACK m behind the body); height BASE_H x scale metres
##   side     the same for the "His right" view (normal -x, SIDE_BACK m behind the body at +x)
##   free     the plane at pos, turned yaw degrees about the vertical (normal = +z turned by yaw)
## MATCH (the innovation): the pose detector finds the person's 33 landmarks in the picture; the picture's scale and offset are
## solved (least squares: one scale, one shift, no rotation) so each landmark lands on the body's matching joint as the
## current camera sees it (camera mode) or on the plane (world modes). The residual is the mean distance left, in pixels.
class_name RefImage
extends RefCounted

const MODES := ["camera", "front", "side", "free"]
const BASE_H := 1.9      # m: a world plane's height at scale 1 (the figure's height, feet to crown, about 1.9 m in the rig)
const BACK := 0.6        # m: the front plane's distance behind the body's centre line
const SIDE_BACK := 0.9   # m: the side plane's distance from the centre line: past the hands of the arms-out rest pose (0.74 m)
const CENTRE_Y := 0.95
const MIN_VIS := 0.5     # a detected landmark below this visibility is not used
## the landmarks the fit uses, in MediaPipe's numbering (the ones VideoImport.landmarks_of fills): nose, shoulders, elbows,
## wrists, hips, knees, ankles, heels, toes
const USE := [0, 11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32]


static func entry(path: String, mode := "camera") -> Dictionary:
	return {"path": path, "mode": mode, "opacity": 0.5, "scale": 1.0, "offset": [0.0, 0.0], "flip": false, "pos": [0.0, CENTRE_Y, -BACK], "yaw": 0.0}


## the file form of a list: only what is valid, every number finite and in range. Never crashes on a bad file
static func clean(list) -> Array:
	var out := []
	if not list is Array:
		return out
	for e in list:
		if not e is Dictionary or String((e as Dictionary).get("path", "")) == "":
			continue
		var o := entry(String(e["path"]))
		o["mode"] = String(e.get("mode", "camera")) if String(e.get("mode", "camera")) in MODES else "camera"
		o["opacity"] = clampf(_f(e.get("opacity", 0.5), 0.5), 0.0, 1.0)
		o["scale"] = clampf(_f(e.get("scale", 1.0), 1.0), 0.05, 20.0)
		var off = e.get("offset", [0.0, 0.0])
		o["offset"] = [clampf(_f(off[0], 0.0), -5.0, 5.0), clampf(_f(off[1], 0.0), -5.0, 5.0)] if off is Array and off.size() >= 2 else [0.0, 0.0]
		o["flip"] = bool(e.get("flip", false))
		var p = e.get("pos", [0.0, CENTRE_Y, -BACK])
		o["pos"] = [_f(p[0], 0.0), _f(p[1], CENTRE_Y), _f(p[2], -BACK)] if p is Array and p.size() >= 3 else [0.0, CENTRE_Y, -BACK]
		o["yaw"] = _f(e.get("yaw", 0.0), 0.0)
		out.append(o)
	return out


static func _f(v, d: float) -> float:
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		return d
	var x := float(v)
	return x if is_finite(x) else d


## the path to store: relative to the scene file's folder when both are on one drive and there is a folder, else as given.
## dir = the scene file's folder (absolute, "" for a scene never saved)
static func store_path(file: String, dir: String) -> String:
	var f := file.replace("\\", "/")
	var d := dir.replace("\\", "/").rstrip("/")
	if d == "" or not f.is_absolute_path() or f.get_slice("/", 0).to_lower() != d.get_slice("/", 0).to_lower():
		return f
	var fa := f.split("/", false)
	var da := d.split("/", false)
	var i := 0
	while i < da.size() and i < fa.size() - 1 and fa[i].to_lower() == da[i].to_lower():
		i += 1
	var parts := []
	for _k in range(i, da.size()):
		parts.append("..")
	for k in range(i, fa.size()):
		parts.append(fa[k])
	return "/".join(parts)


static func resolve(path: String, dir: String) -> String:
	var p := path.replace("\\", "/")
	if p.is_absolute_path() or p.begins_with("user://") or p.begins_with("res://") or dir == "":
		return p
	return dir.replace("\\", "/").rstrip("/").path_join(p).simplify_path()


## camera mode: where the picture is drawn. view = the free 3D view's rect, img = the picture's size
static func layout(view: Rect2, img: Vector2, e: Dictionary) -> Rect2:
	var sz := img * (view.size.y / img.y) * float(e["scale"])
	var c := view.get_center() + Vector2(float(e["offset"][0]), float(e["offset"][1])) * view.size.y
	return Rect2(c - sz * 0.5, sz)


## a screen point -> the picture's normalised (u, v) under the entry's layout (flip included)
static func screen_to_uv(view: Rect2, img: Vector2, e: Dictionary, s: Vector2) -> Vector2:
	var r := layout(view, img, e)
	var u := (s.x - r.position.x) / r.size.x
	return Vector2(1.0 - u if bool(e["flip"]) else u, (s.y - r.position.y) / r.size.y)


## one scale k and one shift t so that k * a_i + t is nearest b_i (least squares). {"k", "t", "res": mean distance over ALL
## the points}. With 6 or more points the fit is TRIMMED: twice, the worst 30 % of the points (a raised arm, a bent knee: the
## picture's pose is not the body's) are left out of the solve, so the height and hips line up, not the average of a pose
## difference. The residual still counts every point
static func fit2d(a: Array, b: Array) -> Dictionary:
	var n := a.size()
	if n < 2:
		return {"ok": false, "k": 1.0, "t": Vector2.ZERO, "res": 0.0}
	var use := range(n)
	var k := 1.0
	var t := Vector2.ZERO
	for pass_i in (3 if n >= 6 else 1):
		var ma := Vector2.ZERO
		var mb := Vector2.ZERO
		for i in use:
			ma += a[i]
			mb += b[i]
		ma /= use.size()
		mb /= use.size()
		var num := 0.0
		var den := 0.0
		for i in use:
			num += (a[i] - ma).dot(b[i] - mb)
			den += (a[i] - ma).length_squared()
		if den < 1e-12 or num <= 0.0:
			return {"ok": false, "k": 1.0, "t": Vector2.ZERO, "res": 0.0}
		k = num / den
		t = mb - ma * k
		if pass_i < 2 and n >= 6:
			var order := range(n)
			order.sort_custom(func(x, y): return (a[x] * k + t - b[x]).length() < (a[y] * k + t - b[y]).length())
			use = order.slice(0, maxi(4, int(ceil(n * 0.7))))
	var r := 0.0
	for i in n:
		r += (a[i] * k + t - b[i]).length()
	return {"ok": true, "k": k, "t": t, "res": r / n}


## the body's joints in MediaPipe's numbering, world metres: {index: Vector3}
static func body_points(B: Body) -> Dictionary:
	var hip: Vector3 = ((B.P["thigh_l"] as Vector3) + (B.P["thigh_r"] as Vector3)) * 0.5
	var w := VideoImport.landmarks_of(B)
	var out := {}
	for k in USE:
		out[k] = (w[k] as Vector3) + hip
	return out


## the plane of a world-mode entry: its turn (the quad's +z is its normal, toward the camera that looks at the body)
static func plane_basis(e: Dictionary) -> Basis:
	var yaw := 0.0
	match String(e["mode"]):
		"side": yaw = -90.0
		"free": yaw = float(e["yaw"])
	return Basis(Vector3.UP, deg_to_rad(yaw))


## the plane's centre before the entry's own offset
static func plane_base(e: Dictionary) -> Vector3:
	match String(e["mode"]):
		"side": return Vector3(SIDE_BACK, CENTRE_Y, 0.0)
		"free": return Vector3(float(e["pos"][0]), float(e["pos"][1]), float(e["pos"][2]))
	return Vector3(0.0, CENTRE_Y, -BACK)


static func plane_centre(e: Dictionary) -> Vector3:
	var b := plane_basis(e)
	return plane_base(e) + b.x * float(e["offset"][0]) + b.y * float(e["offset"][1])


## MATCH. lms = [[x, y, visibility] x 33] normalised to the picture; img = its size; proj = Callable(Vector3) -> screen
## Vector2 (camera mode); view = the 3D view's rect. Returns {"ok", "scale", "offset", "res_px", "n"}; for a world mode the
## scale / offset are the plane's and the residual is in the picture's own pixels
static func fit_landmarks(B: Body, lms: Array, img: Vector2, e: Dictionary, view: Rect2, proj: Callable) -> Dictionary:
	var bp := body_points(B)
	var pts := []   # [uv, world]
	for k in USE:
		if k < lms.size() and lms[k] is Array and lms[k].size() >= 2 and (lms[k].size() < 3 or float(lms[k][2]) >= MIN_VIS):
			pts.append([Vector2(float(lms[k][0]), float(lms[k][1])), bp[k]])
	return fit_pairs(pts, img, e, view, proj)


## the same from [uv, world point] pairs (the two-point fallback gives two)
static func fit_pairs(pts: Array, img: Vector2, e: Dictionary, view: Rect2, proj: Callable) -> Dictionary:
	var flip := bool(e["flip"])
	var a := []
	var b := []
	var cam_mode := String(e["mode"]) == "camera"
	var bas := plane_basis(e)
	var c0 := plane_base(e)
	for p in pts:
		var uv: Vector2 = p[0]
		var u := 1.0 - uv.x if flip else uv.x
		if cam_mode:
			a.append(Vector2(u * img.x, uv.y * img.y))
			b.append(proj.call(p[1]))
		else:
			var rel: Vector3 = (p[1] as Vector3) - c0
			a.append(Vector2((u - 0.5) * img.x / img.y, 0.5 - uv.y) * BASE_H)
			b.append(Vector2(rel.dot(bas.x), rel.dot(bas.y)))
	var f := fit2d(a, b)
	if not f["ok"]:
		return {"ok": false, "n": pts.size()}
	var k: float = f["k"]
	var t: Vector2 = f["t"]
	if cam_mode:
		var centre := t + img * k * 0.5
		return {"ok": true, "scale": k / (view.size.y / img.y), "offset": [(centre.x - view.get_center().x) / view.size.y, (centre.y - view.get_center().y) / view.size.y],
			"res_px": f["res"], "n": pts.size()}
	return {"ok": true, "scale": k, "offset": [t.x, t.y], "res_px": float(f["res"]) / (BASE_H * k) * img.y, "n": pts.size()}


## the mean pixel distance between the picture's landmarks (as the entry lays them out now) and the body's joints as the
## camera sees them: what Match reports. Camera mode only
static func residual_px(B: Body, lms: Array, img: Vector2, e: Dictionary, view: Rect2, proj: Callable) -> float:
	var bp := body_points(B)
	var r := layout(view, img, e)
	var sum := 0.0
	var n := 0
	for k in USE:
		if k < lms.size() and lms[k] is Array and lms[k].size() >= 2 and (lms[k].size() < 3 or float(lms[k][2]) >= MIN_VIS):
			var u := 1.0 - float(lms[k][0]) if bool(e["flip"]) else float(lms[k][0])
			var s := r.position + Vector2(u * r.size.x, float(lms[k][1]) * r.size.y)
			sum += s.distance_to(proj.call(bp[k]))
			n += 1
	return sum / maxi(n, 1)
