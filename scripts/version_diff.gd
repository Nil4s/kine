## version_diff.gd - COMPARE WITH (ROADMAP 28): an older saved version of the scene against the open one. Pure math, no
## node and no window: the rows (what changed per card) and the frame marks (the frames where a joint differs). The
## ghost is drawn by Overlays.version_ghost. Both read the versions as they are; nothing is written.
##   card_rows: added / removed / retimed (move, hold or flow changed) / joints (a pose changed: the biggest joint)
##   frame_marks: the frame times whose biggest joint difference (over the whole body) is over TOL degrees
class_name VersionDiff
extends RefCounted

const TOL := 2.0        # deg: a frame is marked when some joint differs by more than this
const POSE_EPS := 0.01  # deg: a card's stored angle that differs by less than this is not a change (the file's rounding)

static var _body: Body = null   # one body for every sample (its files are read once)


## a saved version file as a Scene; null when the file is not a scene
static func load_scene(path: String) -> Scene:
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary):
		return null
	var S := Scene.new()
	S.from_dict(d)
	return S


static func _sampler() -> Body:
	if _body == null:
		_body = Body.new()
		_body.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	return _body


## the body's joint angles (deg, Vector3) at t, sampled from the scene on the sampler body
static func angles_at(S: Scene, t: float) -> Dictionary:
	var B := _sampler()
	S.apply(B, t)
	var out := {}
	for j in Body.ORDER:
		out[j] = B.ang[j]
	return out


## the wrapped difference of two angles in degrees (-180..180)
static func wrap_deg(d: float) -> float:
	return fposmod(d + 180.0, 360.0) - 180.0


## the biggest joint difference between two sets of joint angles: [deg, joint name] ("", 0.0 when none)
static func biggest(a: Dictionary, b: Dictionary) -> Array:
	var best := 0.0
	var who := ""
	for j in Body.ORDER:
		if not (a.has(j) and b.has(j)):
			continue
		var v: Vector3 = a[j] - b[j]
		var d := maxf(absf(wrap_deg(v.x)), maxf(absf(wrap_deg(v.y)), absf(wrap_deg(v.z))))
		if d > best:
			best = d
			who = j
	return [best, who]


## a card's stored joint angles (the pose dictionary Body.to_dict wrote): joint -> Vector3(bend, side, twist)
static func pose_angles(pose: Dictionary) -> Dictionary:
	var out := {}
	var js: Dictionary = pose.get("joints", {})
	for j in Body.ORDER:
		var q: Dictionary = js.get(j, {})
		out[j] = Vector3(float(q.get("bend", 0.0)), float(q.get("side", 0.0)), float(q.get("twist", 0.0)))
	return out


## the joints of two card poses that differ, joint -> deg (the biggest component difference, wrapped)
static func changed_joints(pa: Dictionary, pb: Dictionary) -> Dictionary:
	var out := {}
	var a := pose_angles(pa)
	var b := pose_angles(pb)
	for j in Body.ORDER:
		var v: Vector3 = a[j] - b[j]
		var d := maxf(absf(v.x), maxf(absf(v.y), absf(v.z)))
		if d > POSE_EPS:
			out[j] = d
	return out


## the cards of two scenes lined up by name (longest common run, in order): [[ia, ib], ...] with -1 for the side that
## has no such card
static func align(A: Array, B: Array) -> Array:
	var n := A.size()
	var m := B.size()
	var dp := []
	for i in n + 1:
		var row := []
		row.resize(m + 1)
		row.fill(0)
		dp.append(row)
	for i in range(n - 1, -1, -1):
		for j in range(m - 1, -1, -1):
			var best: int = maxi(dp[i + 1][j], dp[i][j + 1])
			if A[i]["name"] == B[j]["name"]:
				best = maxi(best, dp[i + 1][j + 1] + 1)
			dp[i][j] = best
	var out := []
	var i := 0
	var j := 0
	while i < n or j < m:
		if i < n and j < m and A[i]["name"] == B[j]["name"] and dp[i][j] == dp[i + 1][j + 1] + 1:
			out.append([i, j])
			i += 1
			j += 1
		elif i < n and (j >= m or dp[i + 1][j] >= dp[i][j + 1]):
			out.append([i, -1])
			i += 1
		else:
			out.append([-1, j])
			j += 1
	return out


## the rows that say what changed between the old scene A and the open scene B, in the order of B's cards (removed cards
## where they were in A). Each row: {"kind", "name", "t" (seconds in the scene it is about), "detail", and for joints:
## "joint" (the biggest), "deg", "n" (joints changed)}
static func card_rows(A: Scene, B: Scene) -> Array:
	var out := []
	var ta := A.times()
	var tb := B.times()
	for p in align(A.cards, B.cards):
		var ia: int = p[0]
		var ib: int = p[1]
		if ib < 0:
			out.append({"kind": "removed", "name": A.cards[ia]["name"], "t": float(ta[ia][1]), "detail": "was card %d" % (ia + 1)})
			continue
		if ia < 0:
			out.append({"kind": "added", "name": B.cards[ib]["name"], "t": float(tb[ib][1]), "detail": "card %d" % (ib + 1)})
			continue
		var ca: Dictionary = A.cards[ia]
		var cb: Dictionary = B.cards[ib]
		var t_old := float(ta[ia][1])
		var t_new := float(tb[ib][1])
		if ca["move"] != cb["move"] or ca["hold"] != cb["hold"] or ca.get("flow", false) != cb.get("flow", false):
			out.append({"kind": "retimed", "name": cb["name"], "t": t_new,
				"detail": "%.2f s -> %.2f s (move %s -> %s, hold %.2f s -> %.2f s)" % [t_old, t_new, str(ca["move"]), str(cb["move"]), float(ca["hold"]), float(cb["hold"])]})
		if ca["pose"] != cb["pose"]:
			var ch := changed_joints(ca["pose"], cb["pose"])
			if not ch.is_empty():
				var big := ""
				var deg := 0.0
				for j in ch:
					if ch[j] > deg:
						deg = ch[j]
						big = j
				out.append({"kind": "joints", "name": cb["name"], "t": t_new, "joint": big, "deg": deg, "n": ch.size(),
					"detail": "%s %.1f° (%d joint%s)" % [big, deg, ch.size(), "" if ch.size() == 1 else "s"]})
	return out


## the frame times (s) where the biggest joint difference between A and B is over TOL, every 1/fps s. Each mark:
## {"t", "deg", "joint"}
static func frame_marks(A: Scene, B: Scene, fps := 30) -> Array:
	var out := []
	var L := maxf(A.length(), B.length())
	var n := int(ceil(L * fps)) + 1
	for i in n:
		var t := float(i) / fps
		var hit := biggest(angles_at(A, t), angles_at(B, t))
		if float(hit[0]) > TOL:
			out.append({"t": t, "deg": float(hit[0]), "joint": hit[1]})
	return out
