## c36_grip.gd - C36 (complaint 20, second try after C22): grip a prop BY ITS HANDLE with the wrist solved from the handle.
## C22Hands.grip_handle took "the nearest surface point to wherever the palm happens to be", so the arm was asked for a place it
## could not reach (wrist 5 cm short) or the palm ended 12 cm off. Here the contact is chosen on the handle itself:
##  - the handle axis `ax` and centre `c` come from C22Hands.handle_of;
##  - candidate palm normals are the directions round the axis (nearest the hand's side first); the contact point is the prop surface
##    on that ray from the centre; the palm faces it (AnyGrip._orient with the flexion axis along the handle, so the fingers wrap round it);
##  - the wrist target = the palm target (contact + normal * GAP) less the palm's offset from the wrist in the oriented hand;
##  - the first candidate whose wrist the arm reaches (<= 5 mm) with the open fingers clear of the prop wins; then the fingers close (AnyGrip.wrap).
## Nothing existing changes: this is a new command and a new function.
class_name C36Grip
extends RefCounted

const GAP := 0.003   # the palm rests 3 mm off the surface (bar: 0..5 mm)


## the contact point on the prop surface from the handle centre outward along u (unit, perpendicular to the axis)
static func _surface(fn: Callable, c: Vector3, u: Vector3) -> Vector3:
	var lo := 0.0
	var hi := 0.4
	if float(fn.call(c)) > 0.0:   # the centre is outside (a hollow or offset solid): start from the nearest point
		return AnyGrip._nearest(fn, c)
	for i in 30:
		var mid := (lo + hi) * 0.5
		if float(fn.call(c + u * mid)) < 0.0:
			lo = mid
		else:
			hi = mid
	return c + u * hi


## grip prop p by its handle with hand h; keys the 15 finger joints at t. Returns the AnyGrip report plus "handle" and "place"
## {"target": wrist target, "wrist_m": miss, "palm_m": palm signed distance, "theta": degrees round the axis, "tried": candidates}
static func grip(B: Body, h: String, p: Dictionary, pk: Dictionary, t: float) -> Dictionary:
	var F := C22Hands.handle_field(p)
	if F.is_empty():
		return {}
	var hd: Dictionary = F["handle"]
	var ax: Vector3 = hd["ax"]
	var c: Vector3 = hd["c"]
	var fn: Callable = (AnyGrip.field_of(p))["sd"]   # the prop's own surface (the slab only limits the closure)
	# the side the hand is on: the palm's offset from the centre, perpendicular to the axis (else the curl direction)
	var side := (B.palm_point(h) - c)
	side -= ax * side.dot(ax)
	if side.length() < 1e-3:
		side = AnyGrip.curl_dir(B, h)
		side -= ax * side.dot(ax)
	var u0 := side.normalized()
	var w := ax.cross(u0).normalized()
	var offsets := [0.0, 30.0, -30.0, 60.0, -60.0, 90.0, -90.0, 120.0, -120.0, 150.0, -150.0, 180.0]
	var best := {}
	var best_cost := INF
	var tried := 0
	for th in offsets:
		for s in [1.0, -1.0]:
			tried += 1
			var u := (u0 * cos(deg_to_rad(th)) + w * sin(deg_to_rad(th))).normalized()
			var q := _surface(fn, c, u)
			var n := AnyGrip._grad(fn, q)
			AnyGrip._orient(B, h, -n, ax * s)
			var target := (B.P[h] as Vector3) + (q + n * GAP - B.palm_point(h))
			var want: Quaternion = B.G[h]   # the orientation asked for; the wrist's limits may not give it
			var miss := B.fit_hand(h, target, want)
			# the palm after the arm has done what it can: pull the target along the normal by the residual and retry once
			var sdp := float(fn.call(B.palm_point(h)))
			if miss <= 0.005 and (sdp > 0.005 or sdp < 0.0):
				target += n * (GAP - sdp)
				miss = B.fit_hand(h, target, want)
				sdp = float(fn.call(B.palm_point(h)))
			var clear := AnyGrip._open_clearance(B, h, fn)
			var turn := rad_to_deg((B.G[h] as Quaternion).angle_to(want))   # the fingers wrap round the handle only if the hand got its turn
			var kn: Vector3 = (B.P["pinky_01" + h.right(2)] as Vector3) - (B.P["index_01" + h.right(2)] as Vector3)
			var kang := rad_to_deg(kn.angle_to(ax))
			kang = minf(kang, 180.0 - kang)   # the stack of the knuckles must run along the handle, or the fingers do not wrap it
			var cost := miss + 0.004 * turn + 0.004 * kang + (0.0 if clear >= 0.0 else 0.05 - clear) + (0.0 if sdp >= 0.0 and sdp <= 0.005 else 0.02 + absf(sdp))
			if OS.get_environment("C36_DBG") != "":
				print("cand th %s s %s miss %.1f turn %.1f sdp %.1f kang %.1f clear %.1f cost %.3f" % [th, s, miss * 1000, turn, sdp * 1000, kang, clear * 1000, cost])
			if cost < best_cost:
				best_cost = cost
				best = {"target": target, "wrist_m": miss, "palm_m": sdp, "theta": th, "sign": s, "u": u, "turn_deg": turn, "want": want}
			if miss <= 0.005 and turn <= 8.0 and kang <= 20.0 and clear >= 0.0 and sdp >= 0.0 and sdp <= 0.005:
				best_cost = -1.0
				break
		if best_cost < 0.0:
			break
	# put the hand back on the best candidate (the loop may have ended on another)
	var u: Vector3 = best["u"]
	var q := _surface(fn, c, u)
	var n := AnyGrip._grad(fn, q)
	if not (best_cost < 0.0):
		AnyGrip._orient(B, h, -n, ax * float(best["sign"]))
		B.fit_hand(h, best["target"], best["want"])
	AnyGrip._open(B, h)
	var Fw := F.duplicate()
	Fw["sd"] = fn   # the fingers and thumb must not enter ANY part of the prop (C22 clipped it to the slab: the thumb ran past it into the bar)
	var rep := AnyGrip.wrap(B, h, Fw)
	AnyGrip.key_hand(B, h, pk, t)
	best["tried"] = tried
	rep["handle"] = hd
	rep["place"] = best
	return rep


## the props a grip holds in the air: {prop index: true} for every card take mark with "air" (Props.settle leaves them where they are)
static func air_held(S: Scene) -> Dictionary:
	var out := {}
	for c in S.cards:
		var tk = c.get("take", null)
		if tk is Dictionary and tk.has("prop") and bool(tk.get("air", false)):
			out[int(tk["prop"])] = true
	return out


## the command (Command palette): the picked prop, the selected hand, at the playhead; one undo step. The prop is also marked as
## CARRIED by that hand (the card's take mark, as C22's attach sets it, plus "air": Props.settle does not drop it to the floor) on the
## card that holds the gripped pose (the picked card; else the card at the playhead; a scene with no card gets one)
static func grip_cmd(m: Node) -> void:
	if m.sel_prop < 0 or m.sel_prop >= m.S.props.size():
		m._say("pick a prop first: click it in the view, then Grip: palm on the handle")
		return
	var h := "hand_l" if String(m.sel).ends_with("_l") else "hand_r"
	var t := clampf(m.playhead, 0.0, m.S.length())
	var p: Dictionary = Props.posed(m.S.props[m.sel_prop], t)
	var rep := {}
	var pi: int = m.sel_prop
	m._do(func():
		rep.merge(grip(m.B, h, p, m.S.part_keys, t))
		if rep.is_empty():
			return
		if m.S.cards.is_empty():
			m.S.add("grip", m.B.to_dict())
			m.sel_card = 0
		var ci: int = m.sel_card if m.sel_card >= 0 and m.sel_card < m.S.cards.size() else 0
		if m.sel_card < 0:
			var best := 1e9
			for k in m.S.times().size():
				var d := absf(float(m.S.times()[k][1]) - t)
				if d < best:
					best = d
					ci = k
		m.S.cards[ci]["pose"] = m.B.to_dict()   # the card holds the gripped body
		m.S.props[pi]["xf"] = p["xf"]   # where it was gripped
		C22Hands.take_with(m.S, pi, ci, "_l" if h == "hand_l" else "_r")
		m.S.cards[ci]["take"]["air"] = true)
	if rep.is_empty():
		m._say("that prop has no handle to grip (no solid part)")
		return
	m._rebuild_cards()
	m._props_show()
	m._say("%s palm on the %s's handle (%.1f mm off the surface, wrist %.1f mm from its target), fingers wrapped, carried from card %d; Ctrl+Z takes it back" % [
		"left" if h == "hand_l" else "right", m._prop_name(m.sel_prop), float(rep["place"]["palm_m"]) * 1000.0, float(rep["place"]["wrist_m"]) * 1000.0, m.sel_card + 1])
