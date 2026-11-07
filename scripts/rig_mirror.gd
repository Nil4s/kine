## rig_mirror.gd - MIRROR ANIMATION ON A CUSTOM RIG (ROADMAP_400 L18, lane L91). Bones are paired by NAME first (_l/_r, .L/.R, Left/Right,
## camel-case L/R, fl/fr style tokens; a pair needs both names to point at each other), then by POSITION: the rig's symmetry plane is
## x = plane_x (found from the name pairs, else by voting on the rest positions), the rest position is mirrored across it and the nearest
## unpaired bone within PAIR_TOL is the partner (both must pick each other). Bones on the plane are centre bones (their own partner).
## A bone with no partner is reported in "unmatched", never paired, and its pose is left as it is.
## A delta is mirrored with C = F_b^-1 * M * F_a (F = rest world basis, M = flip of x): for a rest that is a true mirror C = M and
## (x,y,z,w) -> (x,-y,-z,w): side swing and twist flip, pitch does not. C is used as a signed permutation when it is one, so mirroring is
## made of sign flips and swaps only and mirroring twice is byte-identical.
class_name RigMirror
extends RefCounted

const PAIR_TOL := 0.008
const PLANE_TOL := 0.0015
const MX := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))


static func _swap_lr(t: String) -> String:
	match t:
		"l": return "r"
		"r": return "l"
		"L": return "R"
		"R": return "L"
	return t


## candidate partner names of n (the caller keeps the first that exists on the rig)
static func candidates(n: String) -> Array:
	var out := []
	for pr in [["Left", "Right"], ["LEFT", "RIGHT"], ["left", "right"]]:
		if n.contains(pr[0]):
			out.append(n.replace(pr[0], pr[1]))
		if n.contains(pr[1]):
			out.append(n.replace(pr[1], pr[0]))
	var parts := []
	var cur := ""
	for ch in n:
		if ch == "_" or ch == "." or ch == "-":
			parts.append(cur)
			parts.append(ch)
			cur = ""
		else:
			cur += ch
	parts.append(cur)
	var any := false
	var s1 := ""
	var s2 := ""
	for t in parts:
		if t.length() == 1 and (t.to_lower() == "l" or t.to_lower() == "r"):
			s1 += _swap_lr(t)
			any = true
		else:
			s1 += t
		if t.length() == 2 and t[1].to_lower() in ["l", "r"] and t[0].to_lower() in ["f", "h", "b", "m", "a", "k"]:
			s2 += t[0] + _swap_lr(t[1])
		else:
			s2 += t
	if any:
		out.append(s1)
	if s2 != n:
		out.append(s2)
	if n.length() > 2 and n[-1] in ["L", "R"] and n[-2] == n[-2].to_lower() and n[-2] != n[-2].to_upper():
		out.append(n.substr(0, n.length() - 1) + _swap_lr(n[-1]))
	return out


## the pairing: {"ok", "pair": {bone: partner}, "how": {bone: "name"|"position"|"centre"}, "unmatched": [bones], "plane_x", "pairs": [[a, b]], "report"}
static func pairs(rig: Dictionary) -> Dictionary:
	var names: Array = rig["names"]
	var n := names.size()
	var gl := CustomRig.globals(rig, {})
	var pos := []
	for t in gl:
		pos.append((t as Transform3D).origin)
	var idx := {}
	for i in n:
		idx[names[i]] = i
	var pair := {}
	var how := {}
	# 1 names
	for i in n:
		var a: String = names[i]
		if pair.has(a):
			continue
		for c in candidates(a):
			if c != a and idx.has(c):
				if candidates(c).has(a) and not pair.has(c):
					pair[a] = c
					pair[c] = a
					how[a] = "name"
					how[c] = "name"
				break
	# 2 the plane
	var cx := 0.0
	var mids := []
	for a in pair:
		if idx[a] < idx[pair[a]]:
			mids.append((pos[idx[a]].x + pos[idx[pair[a]]].x) * 0.5)
	if not mids.is_empty():
		mids.sort()
		cx = mids[mids.size() / 2]
	else:
		var votes := {}
		for i in n:
			var k := int(round(pos[i].x * 1000.0))
			votes[k] = votes.get(k, []) + [pos[i].x]
			for j in range(i + 1, n):
				var d: Vector3 = pos[j] - pos[i]
				if absf(d.y) < 0.002 and absf(d.z) < 0.002 and absf(d.x) > 0.002:
					var m: float = (pos[i].x + pos[j].x) * 0.5
					var km := int(round(m * 1000.0))
					votes[km] = votes.get(km, []) + [m]
		var best: Array = []
		for k in votes:
			if (votes[k] as Array).size() > best.size():
				best = votes[k]
		if not best.is_empty():
			var s := 0.0
			for v in best:
				s += v
			cx = s / best.size()
	# 3 centre bones, then position
	var left := []
	for i in n:
		var a: String = names[i]
		if pair.has(a):
			continue
		if absf(pos[i].x - cx) <= PLANE_TOL:
			pair[a] = a
			how[a] = "centre"
		else:
			left.append(i)
	var pick := {}
	for i in left:
		var tgt := Vector3(2.0 * cx - pos[i].x, pos[i].y, pos[i].z)
		var bj := -1
		var bd := INF
		for j in left:
			if j != i and (pos[j] - tgt).length() < bd:
				bd = (pos[j] - tgt).length()
				bj = j
		if bj >= 0 and bd <= PAIR_TOL:
			pick[i] = bj
	var unmatched := []
	for i in left:
		if pick.has(i) and pick.get(pick[i], -1) == i:
			pair[names[i]] = names[pick[i]]
			how[names[i]] = "position"
		else:
			unmatched.append(names[i])
	var lst := []
	var nn := 0
	var np := 0
	var nc := 0
	for i in n:
		var a: String = names[i]
		if not pair.has(a):
			continue
		if how[a] == "centre":
			nc += 1
		elif i < idx[pair[a]]:
			lst.append([a, pair[a]])
			if how[a] == "name":
				nn += 1
			else:
				np += 1
	var rep := "%d pairs (%d by name, %d by position), %d centre bones, plane x = %.4f" % [lst.size(), nn, np, nc, cx]
	if not unmatched.is_empty():
		rep += "; NO PARTNER for %s (left as they are)" % ", ".join(unmatched)
	return {"ok": true, "pair": pair, "how": how, "unmatched": unmatched, "plane_x": cx, "pairs": lst, "report": rep}


## how a delta goes from bone a to its partner b: [perm, sign] when C is a signed permutation, else [Basis C, det]
static func _map_for(gl: Array, ia: int, ib: int) -> Array:
	var fa: Basis = (gl[ia] as Transform3D).basis
	var fb: Basis = (gl[ib] as Transform3D).basis
	var c: Basis = fb.inverse() * MX * fa
	var cols := [c.x, c.y, c.z]   # column j = C * e_j
	var det := -1.0 if c.determinant() < 0.0 else 1.0
	var perm := [-1, -1, -1]      # output component i comes from input component perm[i]
	var sg := [1.0, 1.0, 1.0]
	for i in 3:
		for j in 3:
			var e: float = cols[j][i]
			if absf(absf(e) - 1.0) < 1e-4:
				if perm[i] != -1:
					return [c, det]
				perm[i] = j
				sg[i] = (1.0 if e > 0.0 else -1.0) * det
			elif absf(e) > 1e-4:
				return [c, det]
	if perm.count(0) != 1 or perm.count(1) != 1 or perm.count(2) != 1:
		return [c, det]
	return [perm, sg]


static func _apply(m: Array, q: Quaternion) -> Quaternion:
	if m[0] is Basis:
		var o: Vector3 = (m[0] as Basis) * Vector3(q.x, q.y, q.z) * float(m[1])
		return Quaternion(o.x, o.y, o.z, q.w).normalized()
	var v := [q.x, q.y, q.z]
	var perm: Array = m[0]
	var sg: Array = m[1]
	var o := []
	for i in 3:
		var s: float = v[perm[i]]
		o.append(s if sg[i] > 0.0 else -s)
	return Quaternion(o[0], o[1], o[2], q.w)


## a row (bone -> delta) mirrored: the order follows the old row, so mirroring twice restores the order too
static func _mirror_row(row: Dictionary, pr: Dictionary, maps: Dictionary) -> Dictionary:
	var out := {}
	for a in row:
		if pr["pair"].has(a):
			out[pr["pair"][a]] = _apply(maps[a], row[a])
		else:
			out[a] = row[a]   # no partner: untouched
	return out


static func _maps(rig: Dictionary, pr: Dictionary) -> Dictionary:
	var names: Array = rig["names"]
	var gl := CustomRig.globals(rig, {})
	var maps := {}
	for a in pr["pair"]:
		maps[a] = _map_for(gl, names.find(a), names.find(pr["pair"][a]))
	return maps


static func _flipx(v: Vector3) -> Vector3:
	return Vector3(-v.x, v.y, v.z)


## the current pose and root offset mirrored in place
static func mirror_pose(rig: Dictionary) -> Dictionary:
	var pr := pairs(rig)
	var maps := _maps(rig, pr)
	rig["pose"] = _mirror_row(rig["pose"], pr, maps)
	if rig.has("pos"):
		rig["pos"] = _flipx(rig["pos"])
	return {"ok": true, "unmatched": pr["unmatched"], "report": pr["report"]}


## every key row, and the root position keys, mirrored in place
static func mirror_keys(rig: Dictionary) -> Dictionary:
	var pr := pairs(rig)
	var maps := _maps(rig, pr)
	var keys := {}
	for f in rig["keys"]:
		keys[f] = _mirror_row(rig["keys"][f], pr, maps)
	rig["keys"] = keys
	if rig.has("pkeys"):
		var pk := {}
		for f in rig["pkeys"]:
			pk[f] = _flipx(rig["pkeys"][f])
		rig["pkeys"] = pk
	return {"ok": true, "unmatched": pr["unmatched"], "report": pr["report"]}
