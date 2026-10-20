class_name PhysImport
extends RefCounted
## R15: IMPORT A PHYSICS REACTION. A hit recorded by tools/physics (MuJoCo: export.py writes Kine-named BVH) becomes a NEW
## scene of key cards. The BVH is read by BvhImport (the app's joint set: the joints we have are mapped, the rest listed; the
## root travel is the pelvis channels), then the dense scene (a card per sim frame) is thinned by VideoIQ.smart_cards, the same
## key-card search the video import uses (the tolerance is bisected until the cards REPLAY within `target` m mean joint error
## of the dense scene). The target here is tighter than a video's (0.12 cm against 3 cm): a sim has no tracker jitter to
## forgive, and the cards must replay the fall's joint angles, not just a look-alike. The root is kept as simulated (a fall
## ends with the pelvis near the floor, so the scene is NOT floor-snapped, which would lift the body off its own fall); the
## one correction is the FEET: the lowest sole over the whole clip is lifted to the floor by one constant (never per frame),
## so the capsule/box model's few-mm difference from Kine's sole points cannot sink the feet through the ground.

const TARGET_M := 0.0012


## {"ok", "why", "scene": Scene, "text", "dense": Scene, "frames", "cards", "lift": the constant root lift (m)}
static func import_file(path: String, B: Body, scene_name: String, target := TARGET_M) -> Dictionary:
	var bv := BvhImport.load_file(path)
	if not bv["ok"]:
		return {"ok": false, "why": String(bv["why"])}
	var r := BvhImport.to_scene(bv, B, 1, 1.0, scene_name)
	if not r["ok"]:
		return r
	var dense: Scene = r["scene"]
	var dt: float = bv["dt"]
	var fitted := []
	for i in dense.cards.size():
		fitted.append({"t": i * dt})
	dense.free_limits = true
	var keep := B.state()
	var sk := VideoIQ.smart_cards(B, dense, fitted, target, 0.05)
	var V: Scene = sk["scene"]
	V.name = scene_name
	V.on_floor = false
	V.free_limits = true   # the sim's own angles (the free root beyond the pelvis side limit, a soft stop's overshoot) play as simulated
	# feet on the floor: one constant for the clip, from the lowest sole of the dense replay
	var low := 0.0
	for i in dense.cards.size():
		dense.apply(B, i * dt)
		low = minf(low, sole_y(B))
	var lift := -low
	if lift > 0.0:
		for c in V.cards:
			var o: Array = c["pose"]["offset"]
			c["pose"]["offset"] = [o[0], o[1] + lift, o[2]]
	B.set_state(keep)
	var txt := "%d frames at %d fps -> %d key cards (%s, %.2f cm mean replay error), the root travel kept, the lowest sole lifted %.1f cm to the floor" % [
		dense.cards.size(), dense.fps, V.cards.size(), "spline" if sk["spline"] else "linear", float(sk["mean"]) * 100.0, maxf(lift, 0.0) * 100.0]
	if not r["not_mapped"].is_empty():
		txt += "; not mapped: " + ", ".join(PackedStringArray(r["not_mapped"]))
	return {"ok": true, "why": "", "scene": V, "text": txt, "dense": dense, "frames": dense.cards.size(), "cards": V.cards.size(), "lift": lift}


## the lowest sole point's height above the floor (m) wherever the foot is turned: the ball and the toe tip (the heel is the
## ankle's height, which the foot box already holds off the floor; Body.sole_low measures from the standing rest heights, which is wrong for a foot rolled on its side)
static func sole_y(B: Body) -> float:
	var low := INF
	for sd in ["_l", "_r"]:
		low = minf(low, (B.P["ball" + sd] as Vector3).y)
		low = minf(low, (B.E["ball" + sd] as Vector3).y)
	return low
