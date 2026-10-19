## key_reduce.gd - KEY REDUCTION (ROADMAP 68). Dense part keys (a bake, a video import) thinned out: a key goes when the
## curve WITHOUT it stays within a tolerance of the curve WITH it, on every angle channel (bend, side, twist; the worst
## channel counts). The curve is PartKeys.at() (the keys alone, no modifiers: a modifier stacks on top of whatever keys
## remain, so it is the keys' curve that the tolerance is about).
##
## THE CHECK POINTS: each original key time and the midpoint between each two original keys (so a 30 fps curve is
## checked at its frames and halfway between them). Every check point's reference is the ORIGINAL curve at that time.
## A key is removed only when every check point in the stretch its removal can change stays under the tolerance (strict:
## tolerance 0 removes nothing). The pass is greedy, left to right: removing key i changes the curve only between the
## kept keys two before it and two after it (a key's auto-clamped slope reads its two neighbours), so only those check
## points are re-measured. The first and last key of a joint are never removed (they carry the joint's "inf" and the
## modifier stack, and the clip's ends stay where they were).
##
## Returns {"pk": the reduced part keys (same joints, same order), "before": keys before, "after": keys after,
## "worst": deg, "t": s, "joint": name}: the worst error over the whole scene, at the check point where it occurs.
class_name KeyReduce
extends RefCounted


## reduce every joint of pk within tol degrees (see the header). pk itself is not changed.
static func reduce(pk: Dictionary, tol: float) -> Dictionary:
	var out := {}
	var before := 0
	var after := 0
	var worst := 0.0
	var wt := 0.0
	var wj := ""
	for j in pk:
		var keys: Array = pk[j]
		before += keys.size()
		var r := _joint(keys, maxf(tol, 0.0))
		out[j] = r["keys"]
		after += (r["keys"] as Array).size()
		if float(r["worst"]) > worst:
			worst = float(r["worst"])
			wt = float(r["t"])
			wj = String(j)
	return {"pk": out, "before": before, "after": after, "worst": worst, "t": wt, "joint": wj}


## the error between two Vector3 curves values, the worst channel in degrees
static func channel_err(a: Vector3, b: Vector3) -> float:
	var d := (a - b).abs()
	return maxf(d.x, maxf(d.y, d.z))


## one joint: {"keys": the kept keys (copies), "worst": deg over the check points, "t": where}
static func _joint(keys: Array, tol: float) -> Dictionary:
	var n := keys.size()
	if n < 3:
		return {"keys": _copy(keys, range(n)), "worst": 0.0, "t": 0.0}
	# the check points: index 2k = key k's time, 2k+1 = the midpoint of keys k and k+1
	var ts: Array = []
	var refs: Array = []
	for k in n:
		ts.append(float(keys[k]["t"]))
		if k < n - 1:
			ts.append(0.5 * (float(keys[k]["t"]) + float(keys[k + 1]["t"])))
	for c in ts.size():
		refs.append(PartKeys.at(keys, float(ts[c])))
	var mode := PartKeys.inf_of(keys)
	var stack: Array = [0]   # original indices of the kept keys so far; the first key is always kept
	for i in range(1, n - 1):
		var s0: int = stack[stack.size() - 2] if stack.size() >= 2 else stack[0]   # kept key two before i
		var e0 := mini(i + 2, n - 1)                                                # two after i
		var local := _window(keys, stack, i, mode)
		var ok := true
		for c in range(2 * s0, 2 * e0 + 1):
			if channel_err(PartKeys.at(local, float(ts[c])), refs[c]) >= tol:
				ok = false
				break
		if not ok:
			stack.append(i)   # kept
	stack.append(n - 1)
	var red: Array = []
	for k in stack:
		red.append(keys[k])
	var worst := 0.0
	var wt := 0.0
	if stack.size() < n:
		for c in ts.size():
			var e := channel_err(PartKeys.at(red, float(ts[c])), refs[c])
			if e > worst:
				worst = e
				wt = float(ts[c])
	return {"keys": _copy(keys, stack), "worst": worst, "t": wt}


## the keys the curve around candidate i needs, with i removed: the joint's curve reads a key's two neighbours, so
## three kept keys before and three after are enough (a joint whose infinity is not "hold" uses the whole array, since its
## ends wrap; the window's first key carries the joint's infinity so the hold test of the sampler reads the same mode)
static func _window(keys: Array, stack: Array, i: int, mode: String) -> Array:
	var n := keys.size()
	var out: Array = []
	if mode != "hold":
		for k in stack:
			out.append(keys[k])
		for k in range(i + 1, n):
			out.append(keys[k])
		return out
	for q in range(maxi(0, stack.size() - 3), stack.size()):
		out.append(keys[stack[q]])
	for k in range(i + 1, mini(n, i + 4)):
		out.append(keys[k])
	var d := (out[0] as Dictionary).duplicate()
	d["inf"] = "hold"
	out[0] = d
	return out


static func _copy(keys: Array, idx) -> Array:
	var out: Array = []
	for k in idx:
		out.append((keys[k] as Dictionary).duplicate(true))
	return out
