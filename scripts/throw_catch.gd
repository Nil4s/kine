## throw_catch.gd - I27 THROW AND CATCH. "Throw to...": a prop held in a hand is let go at the playhead frame; the arc it
## flies, its spin and where another hand catches it are solved and written as keys. The maths here; the command, the
## preview and the drawing are throw_catch_ui.gd.
##
## RELEASE: the prop's velocity v0 and angular velocity w are those of the prop in the hand at the release frame, a finite
## difference over ONE frame (the frame before -> the release frame; the prop is rigid in the hand, so this is the hand's
## velocity at the grip). The test hook opts["v"] / opts["w"] replaces them (a known toss).
## ARC: BALLISTIC, g = 9.81 m/s^2, NO DRAG (no air resistance, no Magnus lift on the spin): p(t) = p0 + v0 t - g t^2 / 2 (+Y up).
##   Sampled at every frame; the keys are exact at the frames (the prop's own curve between keys is Props' monotone cubic).
## SPIN: constant angular velocity. A prop key holds a position and a yaw only, so the spin that is KEPT is the turn about
##   the vertical (w_y); the other components are reported in the plan, not flown (the same limit as Throw, WW8).
## CATCH: the first frame after the apex (the catcher takes it on the way down) where the prop is within the catching arm's
##   reach (shoulder to prop <= arm length x REACH_FRAC) and the hand speeds are human: (a) the prop's speed there <=
##   V_HAND_MAX (the hand moves with it), (b) the hand's travel from where it is at the release to the catch point over the
##   flight time <= V_HAND_MAX. The hand is placed there by a LimbIK key pair (weight 0 at the release, 1 at the catch) and
##   the prop is kept on the arc up to the catch frame; from the catch frame on it rests in the hand (the hand is pinned there).
## V_HAND_MAX = 12 m/s is a HEURISTIC, not a measured limit: boxing punch hand speeds of 9-12 m/s are reported for trained
##   boxers (Walilko et al. 2005, Br J Sports Med 39:710; Smith 2000), and throwing hands are faster but cannot be caught at.
## RED (ok = false, "why" names the cause and a next step): "out of reach", "too fast", "lands before".
class_name ThrowCatch
extends RefCounted

const G := 9.81
const V_HAND_MAX := 12.0       # m/s, a heuristic (see above)
const REACH_FRAC := 0.98       # the wrist may be put this far along the straight arm
const MAX_FLIGHT := 8.0        # s
const AFTER_LAND := 1.0        # s past the floor the "lands before" test still looks


static func tip_of(hand: String) -> String:
	return hand if hand.begins_with("hand_") else "hand" + hand


static func root_of(B: Body, tip: String) -> String:
	return B.parent[B.parent[tip]]


static func arc_pos(p0: Vector3, v0: Vector3, tau: float) -> Vector3:
	return Vector3(p0.x + v0.x * tau, p0.y + v0.y * tau - G * tau * tau / 2.0, p0.z + v0.z * tau)


## the carry that holds prop pi at time t: {} if none. {"k": index in carries(), "c": the carry, "hands": [...]}
static func held(S: Scene, B: Body, pi: int, t: float) -> Dictionary:
	var cs := S.carries()
	var data := S._carry_data(B)
	for k in cs.size():
		var d: Dictionary = data[k]
		if int(cs[k]["prop"]) == pi and not d.is_empty() and t >= float(d["ta"]) - 1e-6 and t < float(d["tb"]) - 1e-6:
			return {"k": k, "c": cs[k], "ta": float(d["ta"])}
	return {}


static func prop_xf(S: Scene, B: Body, pi: int, t: float) -> Transform3D:
	S.apply(B, t)
	return S.props_at(t, B)[pi]["xf"]


## the release state at t (the frame): {"p0", "v0" m/s, "w" rad/s (vector), "yaw0" deg, "xf"}
static func release_state(S: Scene, B: Body, pi: int, t: float) -> Dictionary:
	var dt := 1.0 / S.fps
	var a := prop_xf(S, B, pi, maxf(0.0, t - dt))
	var b := prop_xf(S, B, pi, t)
	var tt := t - maxf(0.0, t - dt)
	var v := (b.origin - a.origin) / tt if tt > 1e-9 else Vector3.ZERO
	var dq := (b.basis.orthonormalized().get_rotation_quaternion() * a.basis.orthonormalized().get_rotation_quaternion().inverse()).normalized()
	var ang := dq.get_angle()
	var w := dq.get_axis() * ang / tt if tt > 1e-9 and ang > 1e-9 else Vector3.ZERO
	return {"p0": b.origin, "v0": v, "w": w, "yaw0": Props.yaw_of(b), "xf": b}


## the plan. S/B: the thrower's scene and body (B is left posed at some time). pi: the prop; t: the release time (snapped to
## a frame); catcher {"S", "B", "hand": "hand_l"|"hand_r"|"_l"|"_r"}. opts: "v", "w" (known toss), "floor" (y of the floor, 0)
## Returns {"ok", "why", "t0", "t_catch", "frames", "p0", "v0", "w", "keys": [{"t","pos","yaw"}], "catch_pos", "catch_n",
## "ik": [key, key], "tip", "arm", "speed_prop", "speed_hand", "closest", "land_t"}
static func plan(S: Scene, B: Body, pi: int, t_in: float, catcher: Dictionary, opts := {}) -> Dictionary:
	var fps := float(S.fps)
	var dt := 1.0 / fps
	var t0 := snappedf(t_in, dt)
	var out := {"ok": false, "why": "", "t0": t0}
	if pi < 0 or pi >= S.props.size():
		out["why"] = "pick a prop first: click the held prop in the view, then Throw to..."
		return out
	var hd := held(S, B, pi, t0)
	if hd.is_empty():
		out["why"] = "the prop is not held at %s: move the playhead to a time after its Pick up card (and before it is put down), then Throw to..." % Units.time(t0, S.fps)
		return out
	var tip := tip_of(String(catcher["hand"]))
	var holders: Array = (hd["c"]["hands"] as Array).map(func(h): return tip_of(String(h)))
	var S2: Scene = catcher["S"]
	var B2: Body = catcher["B"]
	if S2 == S and tip in holders:
		out["why"] = "the %s hand is the one holding the prop: pick the other hand, or another fighter's hand, to catch it" % ("left" if tip.ends_with("_l") else "right")
		return out
	var st := release_state(S, B, pi, t0)
	var p0: Vector3 = st["p0"]
	var v0: Vector3 = opts.get("v", st["v0"])
	var w: Vector3 = opts.get("w", st["w"])
	var floor_y := float(opts.get("floor", 0.0))
	var yaw_rate := rad_to_deg(w.y)
	out["p0"] = p0
	out["v0"] = v0
	out["w"] = w
	out["yaw0"] = st["yaw0"]
	out["tip"] = tip
	# the catching arm
	S2.apply(B2, t0)
	var root: String = B2.parent[B2.parent[tip]]
	var mid: String = B2.parent[tip]
	var arm := (B2.P[mid] as Vector3).distance_to(B2.P[root]) + (B2.P[tip] as Vector3).distance_to(B2.P[mid])
	out["arm"] = arm
	var hand0: Vector3 = B2.P[tip]
	var pole0 := LimbIK.pole_from_pose(B2, tip)
	# the flight, frame by frame, to the floor (and AFTER_LAND past it for the "lands before" read)
	var apex_t := maxf(0.0, v0.y / G)
	var land_t := INF
	var disc := v0.y * v0.y + 2.0 * G * (p0.y - floor_y)
	if disc >= 0.0:
		land_t = (v0.y + sqrt(disc)) / G
	out["land_t"] = land_t
	var n_max := mini(int(MAX_FLIGHT * fps), int(ceil((minf(land_t, MAX_FLIGHT) + AFTER_LAND) * fps)))
	var catch_n := -1
	var closest := INF
	var closest_n := 0
	var limit_frames := 0
	var reach_ok_frames := 0      # in reach (any speed), in flight
	var fast_prop := 0.0
	var fast_hand := 0.0
	var late_n := -1
	for n in range(1, n_max + 1):
		var tau := n * dt
		var pp := arc_pos(p0, v0, tau)
		var in_flight := tau <= land_t + 1e-9
		S2.apply(B2, t0 + tau)
		var sh: Vector3 = B2.P[root]
		var d := pp.distance_to(sh)
		if in_flight and d < closest:
			closest = d
			closest_n = n
		if d > arm * REACH_FRAC or tau < apex_t:
			continue
		if not in_flight:
			if late_n < 0:
				late_n = n
			continue
		reach_ok_frames += 1
		var vprop := (v0 - Vector3(0, G * tau, 0)).length()
		var vhand := pp.distance_to(hand0) / tau
		if vprop > V_HAND_MAX or vhand > V_HAND_MAX:
			fast_prop = maxf(fast_prop, vprop)
			fast_hand = maxf(fast_hand, vhand)
			continue
		# the sphere is the arm's length; the joints' limits cut it down: the IK must really put the wrist on the point (5 mm)
		var rr := LimbIK.solve(B2, tip, pp, LimbIK.pole_from_pose(B2, tip))
		if float(rr.get("miss", 0.0)) > 0.005:
			limit_frames += 1
			continue
		out["speed_prop"] = vprop
		out["speed_hand"] = vhand
		catch_n = n
		out["speed_prop"] = vprop
		out["speed_hand"] = vhand
		break
	out["closest"] = closest
	out["closest_n"] = closest_n
	# the keys: to the catch frame, or to the landing when red (the preview shows where it goes)
	var last_n := catch_n if catch_n > 0 else mini(n_max, int(floor(minf(land_t, MAX_FLIGHT) * fps)))
	last_n = maxi(last_n, 1)
	var keys := []
	for n in range(0, last_n + 1):
		var tau := n * dt
		var pos := arc_pos(p0, v0, tau)
		pos.y = maxf(pos.y, floor_y) if catch_n < 0 else pos.y
		keys.append({"t": t0 + tau, "pos": pos, "yaw": float(st["yaw0"]) + yaw_rate * tau})
	out["keys"] = keys
	out["frames"] = last_n
	if catch_n < 0:
		var cm := closest * 100.0
		if late_n >= 0:
			out["why"] = "lands before the hand can get there: the prop is on the floor at %s and only comes into the %s hand's reach (%.0f cm) %.2f s after that. Throw it higher or toward the hand, or pick a hand that is closer" % [
				Units.time(t0 + land_t, S.fps), "left" if tip.ends_with("_l") else "right", arm * 100.0, (late_n * dt - land_t)]
		elif fast_prop > 0.0:
			out["why"] = "too fast: the arc is within reach but a hand would have to move at %.1f m/s (the prop flies at %.1f m/s there; the heuristic human limit is %.0f m/s). Throw it softer or catch it nearer the hand" % [
				maxf(fast_hand, fast_prop), fast_prop, V_HAND_MAX]
		elif fast_prop <= 0.0 and limit_frames > 0:
			out["why"] = "out of reach: the arc passes within the %.0f cm arm's length of the shoulder but the shoulder and elbow limits stop the hand reaching it (%d frames tried). Throw it lower or toward the front of that hand" % [arm * 100.0, limit_frames]
		else:
			out["why"] = "out of reach: the arc never comes closer than %.0f cm to the catching shoulder (frame %d) and the arm is %.0f cm long. Throw it toward that hand, or move the catcher nearer" % [
				cm, closest_n, arm * 100.0]
		return out
	var tc := t0 + catch_n * dt
	var pc: Vector3 = keys[catch_n]["pos"]
	out["t_catch"] = tc
	out["catch_n"] = catch_n
	out["catch_pos"] = pc
	S2.apply(B2, tc)
	var pole1 := LimbIK.pole_from_pose(B2, tip)
	out["ik"] = [{"t": t0, "target": hand0, "pole": pole0, "w": 0.0}, {"t": tc, "target": pc, "pole": pole1, "w": 1.0}]
	out["ok"] = true
	return out


## write a plan (the caller has taken the undo step): flight keys on the prop (a home key one frame before the pick-up so the
## prop still sits where it was put before it is taken), the IK pair on the catcher
static func commit(S: Scene, pi: int, pl: Dictionary, catcher: Dictionary) -> void:
	if not bool(pl.get("ok", false)):
		return   # a red plan writes nothing
	var p: Dictionary = S.props[pi]
	var dt := 1.0 / S.fps
	var t0 := float(pl["t0"])
	var ks: Array = (p.get("keys", []) as Array).filter(func(k): return float(k["t"]) < t0 - Props.SAME_T)
	p["keys"] = ks
	var home: Transform3D = p["xf"]
	var cs := S.carries()
	for c in cs:
		if int(c["prop"]) == pi and float(S.times()[c["a"]][1]) <= t0 + 1e-6:
			var ta := float(S.times()[c["a"]][1])
			if ta - dt >= 0.0 and ks.filter(func(k): return float(k["t"]) < ta - Props.SAME_T).is_empty():
				Props.key_at(p, ta - dt, home)
	for k in pl["keys"]:
		Props.key_at(p, float(k["t"]), Props.xf_at(k["pos"], float(k["yaw"])))
	var S2: Scene = catcher["S"]
	var tip: String = pl["tip"]
	var old: Array = (S2.ik.get(tip, []) as Array).filter(func(k): return float(k["t"]) < t0 - LimbIK.SAME_T)
	S2.ik[tip] = old
	for k in pl["ik"]:
		LimbIK.put(S2.ik, tip, (k as Dictionary).duplicate())


## the scene copied for a preview or a test: Scene.clone shares the props array, and a throw writes keys on a prop
static func copy_scene(S: Scene) -> Scene:
	var c := S.clone()
	c.props = S.props.duplicate(true)
	return c
