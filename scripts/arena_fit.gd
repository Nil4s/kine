## arena_fit.gd - ROADMAP I1 ARENA FIT: will the fight fit the room? A square ring (or room floor) of a size the user sets, centred between the
## fighters where they start. For every frame of the fight it takes each fighter's body volumes (Body.cross_caps: the capsules with their radii)
## and measures how far they reach toward each wall (+X, -X, +Z, -Z). A fighter's room on a wall is the half side less his farthest reach
## toward that wall; the tightest wall is his nearest, and a wall he goes past is named (two walls past = a corner).
## STEP is a walking step: 0.7 m (0.415 of body height, Gait Posture 2009, PMID 19502061; the same source as distance_keeper.gd). Room left
## in steps = room / STEP, whole steps rounded down.
## Read only: the scenes and the fighters' places are not changed. The ring is a measurement, not a stage prop.
class_name ArenaFit
extends RefCounted

const STEP := 0.7
const DIRS := ["+X", "-X", "+Z", "-Z"]


## the fight of N fighters (scenes[i] placed at xfs[i], world space) in a ring of `size` metres a side, centred between their starting pelvises.
## {"ok", "why" | "msg", "size", "half", "need" (the side the fight needs, m), "fits", "fighters": [{"i", "wall" (the nearest wall), "corner" (names
## every wall he goes past), "room" (m to the nearest wall; < 0 = past it), "over" (m past the wall, 0 if inside), "steps", "t" (s when he is
## furthest toward that wall)}]}
static func analyze(scenes: Array, xfs: Array, size: float, fps := 30) -> Dictionary:
	if scenes.size() < 2 or xfs.size() != scenes.size():
		return {"ok": false, "why": "the fit needs two fighters"}
	var n_f := scenes.size()
	var T := 0.0
	var bodies := []
	var centre := Vector2.ZERO
	for i in n_f:
		var S: Scene = scenes[i]
		T = maxf(T, S.length())
		var B := DistanceKeeper.new_body()
		S.apply(B, 0.0)
		bodies.append(B)
		var root: Vector3 = (xfs[i] as Transform3D) * (B.P["pelvis"] as Vector3)
		centre += Vector2(root.x, root.z) / float(n_f)
	# reach[i][k]: the farthest any volume of fighter i gets toward DIRS[k] from the centre (m, the volume's radius included); at[i][k]: when
	var reach := []
	var at := []
	for i in n_f:
		reach.append([-INF, -INF, -INF, -INF])
		at.append([0.0, 0.0, 0.0, 0.0])
	var frames := int(ceil(T * float(fps))) + 1
	for f in frames:
		var t := minf(float(f) / float(fps), T)
		for i in n_f:
			var S: Scene = scenes[i]
			var B: Body = bodies[i]
			S.apply(B, minf(t, S.length()))
			for c in B.cross_caps(xfs[i]):
				var r: float = c[3]
				for e in 2:
					var p: Vector3 = c[1 + e]
					var d := Vector2(p.x, p.z) - centre
					var out := [d.x + r, -d.x + r, d.y + r, -d.y + r]
					for k in 4:
						if float(out[k]) > float(reach[i][k]):
							reach[i][k] = out[k]
							at[i][k] = t
	var half := size * 0.5
	var fighters := []
	var fits := true
	var need := 0.0
	for i in n_f:
		var room := []
		var past := []
		for k in 4:
			room.append(half - float(reach[i][k]))
			need = maxf(need, float(reach[i][k]))
			if float(room[k]) < 0.0:
				past.append(DIRS[k])
		var near := 0
		for k in 4:
			if float(room[k]) < float(room[near]):
				near = k
		var left := float(room[near])
		fits = fits and left >= 0.0
		fighters.append({"i": i, "wall": DIRS[near], "corner": " ".join(past) if past.size() > 0 else "", "room": left,
			"over": maxf(0.0, -left), "steps": int(floor(left / STEP)) if left >= 0.0 else 0, "t": float(at[i][near])})
	var worst := 0
	for f in fighters:
		if float(f["room"]) < float(fighters[worst]["room"]):
			worst = int(f["i"])
	var w: Dictionary = fighters[worst]
	var msg := ""
	if fits:
		msg = "fits a %.1f m ring: the tightest fighter (%d) has %.2f m to the %s wall = %d step%s" % [size, worst + 1, float(w["room"]), w["wall"], int(w["steps"]), "" if int(w["steps"]) == 1 else "s"]
	else:
		var where := ("the %s corner" % String(w["corner"])) if String(w["corner"]).contains(" ") else ("the %s wall" % String(w["wall"]))
		msg = "does NOT fit a %.1f m ring: fighter %d is pushed into %s, %.2f m past it at %.2f s; the fight needs %.2f m" % [size, worst + 1, where, float(w["over"]), float(w["t"]), 2.0 * need]
	return {"ok": true, "msg": msg, "size": size, "half": half, "need": 2.0 * need, "fits": fits, "fighters": fighters}
