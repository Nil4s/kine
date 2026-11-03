class_name ExplodeCam
extends RefCounted
## s262d: the GPU explode film's camera. frame_boxes = per frame the world box of every moving piece (from the TIMELINE keys); plan = one camera per frame that keeps all of them
## inside the frame with margin (fit per frame, then a symmetric smoothing that can only pull BACK, never in); old_plan = 2c32f1a2's lagging fit (the control).
const FIT := 0.84   # fraction of the frame the boxes may fill (8 pct margin each side; the bar is 5 pct)


static func cam_dir(keys: Array, f: float) -> Vector3:
	var t := f * float(keys[-1]["t"])
	for i in keys.size() - 1:
		var a: Dictionary = keys[i]
		var b: Dictionary = keys[i + 1]
		if t <= float(b["t"]) or i == keys.size() - 2:
			var u := clampf((t - float(a["t"])) / maxf(float(b["t"]) - float(a["t"]), 1e-6), 0.0, 1.0)
			u = u * u * (3.0 - 2.0 * u)
			var da := (Vector3(a["pos"][0], a["pos"][1], a["pos"][2]) - Vector3(a["look"][0], a["look"][1], a["look"][2])).normalized()
			var db := (Vector3(b["pos"][0], b["pos"][1], b["pos"][2]) - Vector3(b["look"][0], b["look"][1], b["look"][2])).normalized()
			return da.lerp(db, u).normalized()
	return Vector3(0.5, 0.4, 0.8).normalized()


## Array (per frame) of Array[AABB] (per drawn piece)
static func frame_boxes(host: Node, rec: Dictionary, opts: Dictionary, r: Dictionary, fps: int) -> Array:
	var p: Dictionary = host.S.props[int(r["prop"])]
	var kd: Dictionary = Props.kind_of(String(p["kind"]))
	var res := Part.replay(rec)
	var names: Array = ExplodeKeys.plan_of(res, opts)["names"]
	var jn: Array = ExplodeKeys._joint_names(names)
	var at: Vector3 = kd["mesh_at"]
	var pieces: Array = kd["pieces"]
	var jof := {}
	for j in kd["pjoints"]:
		jof[int(j["piece"])] = j
	var rest: Array = []
	for i in pieces.size():
		var mesh = pieces[i]["mesh"]
		var bb: AABB = (mesh as ArrayMesh).get_aabb() if mesh != null else AABB()
		rest.append(AABB(bb.position + at, bb.size))
	var out: Array = []
	var n := int(float(r["total"]) * fps)
	for f in n:
		var ang := PropJoints.angles_at(p, float(f) / fps)
		var bs: Array = []
		for i in pieces.size():
			if (rest[i] as AABB).size.length() <= 0.0 or String(names[i]).begins_with("Ring glow"):
				continue
			var off := Vector3.ZERO
			if jof.has(i):
				off = (jof[i]["axis"] as Vector3) * float(ang.get(String(jn[i]), 0.0)) * 0.001
			bs.append(AABB((rest[i] as AABB).position + off, (rest[i] as AABB).size))
		out.append(bs)
	return out


static func union(bs: Array) -> AABB:
	var u: AABB = bs[0]
	for b in bs:
		u = u.merge(b)
	return u


static func screen(cam: Camera3D, boxes: Array) -> Rect2:
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for b in boxes:
		for i in 8:
			var p := cam.unproject_position((b as AABB).get_endpoint(i))
			lo = lo.min(p)
			hi = hi.max(p)
	return Rect2(lo, hi - lo)


## smallest distance (as a fraction of the frame side) from any projected corner to the frame edge; negative = outside
static func margin(cam: Camera3D, boxes: Array, w: int, h: int) -> float:
	var r := screen(cam, boxes)
	return minf(minf(r.position.x / w, (w - r.end.x) / w), minf(r.position.y / h, (h - r.end.y) / h))


static func _fit(cam: Camera3D, boxes: Array, dir: Vector3, w: int, h: int, fill: float) -> Dictionary:
	var u := union(boxes)
	var target := u.get_center()
	var dist := u.size.length() * 1.6
	for it in 6:
		cam.look_at_from_position(target + dir * dist, target, Vector3.UP)
		var rr := screen(cam, boxes)
		var s2 := minf(fill * h / maxf(rr.size.y, 1.0), fill * w / maxf(rr.size.x, 1.0))
		var err := rr.get_center() - Vector2(w, h) * 0.5
		var mpp := 2.0 * dist * tan(deg_to_rad(cam.fov) * 0.5) / h
		target += cam.global_transform.basis.x * err.x * mpp - cam.global_transform.basis.y * err.y * mpp
		dist /= s2
	return {"target": target, "dist": dist}


## 2c32f1a2's camera: fit the union box to 0.78 H / 0.8 W each frame, then the distance lags (lerp 0.35)
static func old_plan(fr: Array, dirs: Array, cam: Camera3D, w: int, h: int) -> Array:
	var out: Array = []
	var fit_d := 0.0
	for f in fr.size():
		var u := union(fr[f])
		var target := u.get_center()
		var dist := u.size.length() * 1.6
		for it in 5:
			cam.look_at_from_position(target + dirs[f] * dist, target, Vector3.UP)
			var rr := screen(cam, [u])
			var s2 := minf(0.78 * h / maxf(rr.size.y, 1.0), 0.8 * w / maxf(rr.size.x, 1.0))
			var err := rr.get_center() - Vector2(w, h) * 0.5
			var mpp := 2.0 * dist * tan(deg_to_rad(cam.fov) * 0.5) / h
			target += cam.global_transform.basis.x * err.x * mpp - cam.global_transform.basis.y * err.y * mpp
			dist /= s2
		fit_d = dist if fit_d == 0.0 else lerpf(fit_d, dist, 0.35)
		out.append({"pos": target + dirs[f] * fit_d, "target": target})
	return out


## per-frame exact fit of every piece box, target and distance smoothed over +-8 frames, then the distance pushed back out until the margin holds
static func plan(fr: Array, dirs: Array, cam: Camera3D, w: int, h: int) -> Array:
	var n := fr.size()
	var tg: Array = []
	var ds: Array = []
	for f in n:
		var d := _fit(cam, fr[f], dirs[f], w, h, FIT)
		tg.append(d["target"])
		ds.append(d["dist"])
	var out: Array = []
	for f in n:
		var t := Vector3.ZERO
		var dd := 0.0
		var c := 0
		for k in range(maxi(f - 8, 0), mini(f + 9, n)):
			t += tg[k]
			dd += float(ds[k])
			c += 1
		t /= c
		dd = maxf(dd / c, float(ds[f]))   # never closer than the exact fit
		for it in 40:
			cam.look_at_from_position(t + dirs[f] * dd, t, Vector3.UP)
			if margin(cam, fr[f], w, h) >= 0.07:
				break
			dd *= 1.03
		out.append({"pos": t + dirs[f] * dd, "target": t})
	return out


## the boxes plus their mirror images in the floor plane y = floor_y, clipped at the depth where the glossy reflection has faded (fade_h): the reflection is picture too
static func with_mirror(fr: Array, floor_y: float, fade_h: float) -> Array:
	var out: Array = []
	for bs in fr:
		var o: Array = (bs as Array).duplicate()
		for b in bs:
			var bb: AABB = b
			var lo := 2.0 * floor_y - bb.end.y
			var hi := 2.0 * floor_y - bb.position.y
			lo = maxf(lo, floor_y - fade_h)
			if hi > lo:
				o.append(AABB(Vector3(bb.position.x, lo, bb.position.z), Vector3(bb.size.x, hi - lo, bb.size.z)))
		out.append(o)
	return out
