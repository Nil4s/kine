class_name QuatCurve
extends RefCounted
## L86 (ROADMAP_400 L04): the Euler filter on part keys, a read-only quaternion view, and quaternion-slerp key interpolation.
## EULER FILTER: Curves.euler_filter (per angle, every key moved by a multiple of 360 so no step is over 180) applied to the part keys'
## values. It is exact (the world rotation does not change) for twist, and for bend/side while the other swing angle is 0: Body.compose
## is a swing-twist split, so a 360 shift of one swing angle with the other not 0 is a different rotation (report: "world_note").
## QUATERNION VIEW: (t, w, x, y, z) per frame of a part's WORLD rotation as Scene.apply poses it (the product of the chain's
## Body.compose), sign kept in one hemisphere from frame to frame. Read-only.
## SLERP: a key with "interp": "slerp" leaves toward the next key along the shortest quaternion arc of Body.compose(angles): constant
## angular velocity. The key carries "qj" (its joint, set here and on load) because PartKeys' curve functions get keys, not names.

static var _body: Body = null
static var _scratch: Body = null
static var _mu := Mutex.new()


static func _mk() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.fk()
	return b


static func _ref() -> Body:
	_mu.lock()
	if _body == null:
		_body = _mk()
	_mu.unlock()
	return _body


## the angles a segment of a slerp key gives at s in 0..1 (a, b: the two keys' angles)
static func seg(j: String, a: Vector3, b: Vector3, s: float) -> Vector3:
	if s <= 0.0:
		return a
	if s >= 1.0:
		return b
	if j == "" or not (j in Body.ORDER):
		return a + (b - a) * s
	var B := _ref()
	var qa: Quaternion = B.compose(j, a)
	var qb: Quaternion = B.compose(j, b)
	if qa.dot(qb) < 0.0:
		qb = -qb
	return B.decompose(j, qa.slerp(qb, s).normalized())


## (t, w, x, y, z) of part j's world rotation at fps over t0..t1 (frames t0 + k / fps, the last one at t1 when it falls on a frame)
static func view(S: Scene, j: String, t0: float, t1: float, fps: float) -> Array:
	var out := []
	if not (j in Body.ORDER) or fps <= 0.0:
		return out
	_mu.lock()
	if _scratch == null:
		_scratch = _mk()
	var B := _scratch
	var chain := []
	var c := j
	while c != "":
		chain.push_front(c)
		c = String(B.parent[c])
	var n := int(floor((t1 - t0) * fps + 1e-6))
	var prev := Quaternion.IDENTITY
	for k in n + 1:
		var t := t0 + float(k) / fps
		S.apply(B, t)
		var q := Quaternion.IDENTITY
		for a in chain:
			q = q * B.compose(a, B.ang[a])
		if k > 0 and q.dot(prev) < 0.0:
			q = -q
		elif k == 0 and q.w < 0.0:
			q = -q
		prev = q
		out.append([t, q.w, q.x, q.y, q.z])
	_mu.unlock()
	return out


## Euler filter on the keys of the given joints (written in place). Returns {"parts", "keys_changed", "worst_shift", "joints"}
static func euler_filter_parts(pk: Dictionary, joints: Array) -> Dictionary:
	var n := 0
	var worst := 0.0
	var done := []
	for j in joints:
		if not pk.has(j) or (pk[j] as Array).size() < 2:
			continue
		var ks: Array = pk[j]
		var ch := []
		for k in ks:
			ch.append([k["t"], k["v"]])
		var r := Curves.euler_filter(ch)
		var out: Array = r["track"]
		var any := false
		for i in ks.size():
			if out[i][1] != ks[i]["v"]:
				ks[i]["v"] = out[i][1]
				n += 1
				any = true
		worst = maxf(worst, float(r["report"]["worst_err"]))
		done.append(String(j))
	return {"parts": done.size(), "keys_changed": n, "worst_shift": worst, "joints": done}


## slerp on (every key but the last gets interp "slerp") or off (back to bezier)
static func set_slerp(pk: Dictionary, joints: Array, on: bool) -> int:
	var n := 0
	for j in joints:
		if not pk.has(j):
			continue
		var ks: Array = pk[j]
		for i in ks.size() - 1:
			PartKeys.set_interp(pk, j, i, "slerp" if on else "bezier")
			n += 1
	return n
