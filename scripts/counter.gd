## counter.gd - COUNTER SUGGESTION (ROADMAP Innovations I3). Static, no UI (counter_ui.gd draws it; main.gd owns undo).
## Fight choreography help: for the ATTACKER'S current card (the move into the card the playhead is on) it takes the
## path of the weapon tip (the fist's palm without a weapon) over the move up to the contact, and proposes up to three
## poses for the DEFENDER, each built from the defender's own body (LimbIK / Body.plant, every angle inside its joint
## limits), NOTHING of the scene touched:
##   BLOCK   a forearm laid ACROSS the path (its axis square to the tip's velocity) at the first path point the arm can
##           reach (within REACH_K of the arm's length from the shoulder): the forearm's axis passes within TOL of that point.
##   SLIP    head and torso (head, spine_03, spine_02) moved off the path by the SMALLEST move that clears the attacker's
##           weapon line (the tip for a fist) by >= CLEAR over the whole path and FOLLOW seconds past the contact. The
##           move is the pelvis shifted by the move (a duck is down, a slip is sideways or back) with both feet kept on
##           their marks (Body.plant: the knees bend), and the centre of mass kept inside the support (Balance).
##   PARRY   a forearm that meets the weapon at a slant: its axis is tilted 25-65 deg out of square to the velocity, toward
##           the outside of the arm used, so the tip SLIDES along it (frictionless: v' = (v.d) d) and leaves sideways.
##           Reported: the deflection angle, and how far the tip ends from its old path at the contact time.
## CONTACT = the first 1/120 s sample at which the tip is inside the defender's body (Choreo.surface_gap <= 0), or the
## card's arrival when it never gets there. All in the hero's space (a fighter's xf maps its body space into it).
## Numbers are the SAME kind the bars read: forearm axis to the path point (m), clearance = distance between the weapon
## line and the body capsule minus both radii (m), COM margin (Balance.read: + inside the support polygon).
class_name Counter
extends RefCounted

const HZ := 120.0          # the path's samples a second
const FOLLOW := 0.12       # s of follow-through kept on the path after the contact
const CLEAR := 0.10        # m: the slip's bar (surface to the weapon line)
const PLAN := 0.112        # m: what the search plans for, so the realised pose lands above CLEAR
const TOL := 0.025         # m: the forearm axis to the path point, planned (the test's bar is 3 cm)
const REACH_K := 0.97      # the arm may be this share of its length stretched
const PARRY_LATE := 0.04   # s: a parry meets the weapon this long after the block's first point (not before the entry)
const TORSO := ["head", "spine_03", "spine_02"]
const SEARCH_EVERY := 6    # the slip's search looks at every 6th sample (20 Hz); the realised pose at all of them
const FRACS := [0.5, 0.7, 0.3, 0.85, 0.15, 1.0, 0.0]   # where along the forearm (0 elbow, 1 wrist) the path point may fall
const MAX_SOLVES := 14      # IK solves a forearm placement may spend (the best by a cheap score)
const FIST_R := 0.04       # m: a fist's radius
const MARGIN_MIN := 0.01   # m: the centre of mass at least this far inside the support


## a body for this scene's proportions, in its rest pose
static func scratch(S: Scene) -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	if b.body != S.body:
		b.set_proportions(S.body)
	b.fk()
	return b


## the card whose move the playhead is in or after (the first move when it is on card 0), or -1 with under two cards
static func card_of(S: Scene, t: float) -> int:
	var ts := S.times()
	if ts.size() < 2:
		return -1
	for i in range(1, ts.size()):
		if t <= float(ts[i][2]) + 1e-3:
			return i
	return ts.size() - 1


## the defender posed at t by its scene, on a body of its own
static func ghost(DS: Scene, t: float) -> Body:
	var G := scratch(DS)
	DS.apply(G, t)
	G.fk()
	return G


## THE STRIKE: the attacker's tip over card ci's move into the contact.
## {"ok", "why", "ci", "t0", "tc", "contact" (the tip got inside), "ts": [t], "p": [tip, hero space], "a", "b": [the weapon
## line's ends], "r": its radius, "what" ("tip" / "fist"), "hand"}
static func strike(AS: Scene, axf: Transform3D, DS: Scene, dxf: Transform3D, ci: int) -> Dictionary:
	var out := {"ok": false, "why": "", "ci": ci}
	var ts := AS.times()
	if ci < 1 or ci >= ts.size():
		out["why"] = "the attacker needs a card with a move into it: put the playhead after its first card"
		return out
	var t0 := float(ts[ci][0])
	var t_arr := float(ts[ci][1])
	var T := AS.length()
	var t_end := minf(float(ts[ci][2]), T)
	var AB := scratch(AS)
	var DB := scratch(DS)
	var step := 1.0 / HZ
	var tc := -1.0
	for i in int(floor((t_end - t0) / step)) + 1:
		var t := t0 + float(i) * step
		AS.apply(AB, t)
		DS.apply(DB, t)
		var tp := Choreo.tip(AB, axf, DB, dxf)
		if float(Choreo.surface_gap(tp["p"], DB, dxf)["gap"]) <= 0.0:
			tc = t
			break
	var contact := tc >= 0.0
	if not contact:
		tc = t_arr
	if tc - t0 < 2.0 * step:
		out["why"] = "the attacker's tip is already touching the defender at the start of this move: pick a card with room before the hit"
		return out
	AS.apply(AB, tc)
	DS.apply(DB, tc)
	var tip0 := Choreo.tip(AB, axf, DB, dxf)
	var hand: String = tip0["hand"]
	var what: String = tip0["what"]
	var tl := []
	var pl := []
	var al := []
	var bl := []
	var r := float(AB.rad["bat_barrel"]) if AB.wep_on else FIST_R
	var t_last := minf(tc + FOLLOW, T)
	for i in int(floor((t_last - t0) / step)) + 1:
		var t := t0 + float(i) * step
		AS.apply(AB, t)
		var p: Vector3
		var a: Vector3
		var b: Vector3
		if AB.wep_on:
			a = axf * AB.wep_point(0.0)
			b = axf * AB.wep_point(AB.wep_len)
			p = b
		else:
			p = axf * AB.palm_point(hand)
			a = p
			b = p
		tl.append(t)
		pl.append(p)
		al.append(a)
		bl.append(b)
	out.merge({"ok": true, "t0": t0, "tc": tc, "contact": contact, "ts": tl, "p": pl, "a": al, "b": bl, "r": r, "what": what, "hand": hand}, true)
	return out


## the tip at t (linear between samples)
static func path_at(P: Dictionary, t: float) -> Vector3:
	var ts: Array = P["ts"]
	var ps: Array = P["p"]
	if t <= float(ts[0]):
		return ps[0]
	for i in range(1, ts.size()):
		if t <= float(ts[i]):
			var u := (t - float(ts[i - 1])) / maxf(1e-9, float(ts[i]) - float(ts[i - 1]))
			return (ps[i - 1] as Vector3).lerp(ps[i], u)
	return ps[-1]


## the tip's velocity at sample i (m/s, central difference)
static func vel_at(P: Dictionary, i: int) -> Vector3:
	var ts: Array = P["ts"]
	var ps: Array = P["p"]
	var a := maxi(0, i - 1)
	var b := mini(ts.size() - 1, i + 1)
	return ((ps[b] as Vector3) - (ps[a] as Vector3)) / maxf(1e-9, float(ts[b]) - float(ts[a]))


## distance from the path (the tip's polyline) to a segment, m
static func path_dist(P: Dictionary, c0: Vector3, c1: Vector3) -> float:
	var ps: Array = P["p"]
	var m := INF
	for i in range(1, ps.size()):
		m = minf(m, Body.seg_seg(ps[i - 1], ps[i], c0, c1))
	return m


# ---------------------------------------------------------------- BLOCK and PARRY

static func _perp(v: Vector3, axis: Vector3) -> Vector3:
	return v - axis * v.dot(axis)


static func _arm_len(G: Body, sd: String) -> float:
	return (G.p0["lowerarm" + sd] as Vector3).distance_to(G.p0["upperarm" + sd]) + (G.p0["hand" + sd] as Vector3).distance_to(G.p0["lowerarm" + sd])


## the outside of the arm used (body space, square to vh): where a parry sends the tip
static func _outside(G: Body, sd: String, vh: Vector3) -> Vector3:
	var lat: Vector3 = (G.P["upperarm_l"] as Vector3) - (G.P["upperarm_r"] as Vector3)
	lat.y = 0.0
	lat = lat.normalized()
	if sd == "_r":
		lat = -lat
	var w := _perp(lat, vh)
	if w.length() < 1e-3:
		w = _perp(Vector3.RIGHT, vh)
	return w.normalized()


## put the forearm's axis through X (body space). The direction d is searched on the sphere (36 turns about the velocity
## vh x 7 tilts out of the plane square to it); only the directions whose ELBOW (X - d Lf/2) is one upper arm from the
## shoulder (+-3 cm) are solved (LimbIK), since the arm cannot put the forearm anywhere else. BLOCK keeps the forearm
## within ~20 deg of square to vh; PARRY tilts it 25-65 deg out of square toward the outside w, so the tip slides along it.
## {"ok", "dist" (axis to X), "pose", "clamped", "dir" (the forearm's actual direction), "tilt" (deg out of square)}
static func _place(base: Dictionary, W: Body, sd: String, X: Vector3, vh: Vector3, parry: bool) -> Dictionary:
	W.from_dict(base)
	W.fk()
	var S: Vector3 = W.P["upperarm" + sd]
	var Lu := (W.p0["lowerarm" + sd] as Vector3).distance_to(W.p0["upperarm" + sd])
	var c0: Array = W.cap("lowerarm" + sd)
	var Lf := (c0[0] as Vector3).distance_to(c0[1])
	var reach := REACH_K * _arm_len(W, sd)
	var cur: Vector3 = ((c0[1] as Vector3) - (c0[0] as Vector3)).normalized()
	var ref := Vector3.UP if absf(vh.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var e1 := vh.cross(ref).normalized()
	var e2 := vh.cross(e1).normalized()
	var w := _outside(W, sd, vh)
	var tilts := [25.0, 35.0, 45.0, 55.0, 65.0] if parry else [0.0, 15.0, -15.0]
	var cands := []
	for k in 48:
		var th := TAU * float(k) / 48.0
		var inp: Vector3 = e1 * cos(th) + e2 * sin(th)
		if parry and inp.dot(w) < 0.5:
			continue   # the forearm leans toward the outside, so the tip leaves that way
		for ph in tilts:
			var cp := cos(deg_to_rad(ph))
			var d: Vector3 = inp * cp + vh * sin(deg_to_rad(ph))
			for f in FRACS:
				var E: Vector3 = X - d * Lf * f
				var Wp: Vector3 = X + d * Lf * (1.0 - f)
				if absf(E.distance_to(S) - Lu) > 0.04 or Wp.distance_to(S) > reach:
					continue
				cands.append([d, f, absf(E.distance_to(S) - Lu) * 5.0 + 0.05 * (1.0 - d.dot(cur)) + absf(f - 0.55) * 0.05])
	cands.sort_custom(func(a, b): return float(a[2]) < float(b[2]))
	if cands.size() > MAX_SOLVES:
		cands.resize(MAX_SOLVES)   # the best by the cheap score: each solve is ~10 ms
	var best := {"ok": false, "dist": INF}
	var best_cost := INF
	var tip := "hand" + sd
	for cd in cands:
		var d: Vector3 = cd[0]
		var f: float = cd[1]
		W.from_dict(base)
		W.fk()
		var Wt: Vector3 = X + d * Lf * (1.0 - f)
		var Et: Vector3 = X - d * Lf * f
		var dist := INF
		var clamped := []
		var da: Vector3 = d
		for it in 5:
			var r := LimbIK.solve(W, tip, Wt, Et)
			clamped = r["clamped"]
			var c: Array = W.cap("lowerarm" + sd)
			var q := Choreo.closest_on(X, c[0], c[1])
			dist = q.distance_to(X)
			da = ((c[1] as Vector3) - (c[0] as Vector3)).normalized()
			if dist <= 0.002:
				break
			Wt += X - q
		var along: float = da.dot(vh)
		var tilt := rad_to_deg(asin(clampf(absf(along), 0.0, 1.0)))
		var good := dist <= TOL
		if parry:
			good = good and tilt >= 20.0 and tilt <= 70.0
		else:
			good = good and tilt <= 20.0
		var cost: float = dist * 10.0 + 0.05 * (1.0 - da.dot(cur)) + 0.02 * float(clamped.size()) + absf(f - 0.55) * 0.05 + (0.0 if parry else tilt * 0.01)
		if not good:
			cost += 10.0
		if cost < best_cost:
			best_cost = cost
			best = {"ok": good, "dist": dist, "pose": W.to_dict(), "clamped": clamped, "dir": da, "tilt": tilt}
	return best


## BLOCK (parry = false) or PARRY (true): the forearm found at the first path point (searched at 60 Hz) the arm reaches.
## A parry first looks for a point PARRY_LATE after the first reachable one (so it does not sit on the block), then any.
## dxf: the defender's placement. {"ok", "why", "kind", "t", "tx", "X", "pose", "side", "dist", "gap", ...}
static func guard(P: Dictionary, DS: Scene, dxf: Transform3D, parry: bool) -> Dictionary:
	var out := {"ok": false, "kind": "PARRY" if parry else "BLOCK", "why": ""}
	var G0 := ghost(DS, float(P["tc"]))
	var base := G0.to_dict()
	var W := scratch(DS)
	for late in ([PARRY_LATE, 0.0] if parry else [0.0]):
		var r := _guard_scan(P, DS, dxf, parry, late, G0, base, W)
		if bool(r["ok"]):
			return r
	out["why"] = "the path never comes within the defender's arm reach with a forearm that fits before the contact: move the fighters closer or pick a later card"
	return out


static func _guard_scan(P: Dictionary, DS: Scene, dxf: Transform3D, parry: bool, late: float, G0: Body, base: Dictionary, W: Body) -> Dictionary:
	var out := {"ok": false, "kind": "PARRY" if parry else "BLOCK", "why": ""}
	var tc: float = P["tc"]
	var xi := dxf.affine_inverse()
	var ts: Array = P["ts"]
	var first := -1.0
	for i in range(0, ts.size(), 2):
		var t: float = ts[i]
		if t > tc + 1e-6:
			break
		var Xh: Vector3 = P["p"][i]
		var X: Vector3 = xi * Xh
		var sides := []
		for sd in ["_l", "_r"]:
			if (G0.P["upperarm" + sd] as Vector3).distance_to(X) <= REACH_K * _arm_len(G0, sd):
				sides.append(sd)
		if sides.is_empty():
			continue
		if first < 0.0:
			first = t
		if t < first + late and first + late <= tc:
			continue
		var vh: Vector3 = xi.basis * vel_at(P, i)
		if vh.length() < 1e-3:
			continue
		vh = vh.normalized()
		var tried: Array = []
		for sd in sides:
			var r := _place(base, W, sd, X, vh, parry)
			r["side"] = sd
			tried.append(r)
		tried.sort_custom(func(a, b): return float(a["dist"]) < float(b["dist"]) if bool(a["ok"]) == bool(b["ok"]) else bool(a["ok"]))
		var r0: Dictionary = tried[0]
		if not bool(r0["ok"]):
			continue
		var G := scratch(DS)
		G.from_dict(r0["pose"])
		G.fk()
		var sd: String = r0["side"]
		var cf: Array = G.cap("lowerarm" + sd)
		var fa: Vector3 = dxf * (cf[0] as Vector3)
		var fb: Vector3 = dxf * (cf[1] as Vector3)
		var v: Vector3 = vel_at(P, i)
		var strike_gap := Body.seg_seg(P["a"][i], P["b"][i], fa, fb) - float(P["r"]) - float(G.rad["lowerarm" + sd])
		out.merge({"ok": true, "t": t, "tx": t, "X": Xh, "pose": r0["pose"], "side": sd, "dist": r0["dist"], "B": G,
			"clamped": r0["clamped"], "speed": v.length(), "gap": strike_gap, "forearm": [fa, fb]}, true)
		var d_h: Vector3 = (fb - fa).normalized()
		out["across"] = rad_to_deg(acos(clampf(absf(d_h.dot(v.normalized())), 0.0, 1.0)))   # forearm to velocity: 90 = square
		if parry:
			# the tip leaves along the forearm: v' = (v.d) d, d signed to point on with the tip
			var ds := d_h if d_h.dot(v) >= 0.0 else -d_h
			var v_after := ds * v.dot(ds)
			out["deflect"] = rad_to_deg(v.angle_to(v_after))
			var side_v := v_after - v.normalized() * v_after.dot(v.normalized())
			out["aside"] = side_v.length() * maxf(0.0, tc + FOLLOW - t)
		return out
	return out


# ---------------------------------------------------------------- SLIP / DUCK

## the least clearance (surface to the weapon line) of the torso parts of body G (hero space) at the samples idx,
## the parts moved by delta (hero space)
static func _clear_of(P: Dictionary, G: Body, dxf: Transform3D, delta: Vector3, idx: Array, parts := TORSO) -> float:
	var m := INF
	var sa: Array = P["a"]
	var sb: Array = P["b"]
	var r: float = P["r"]
	for part in parts:
		var c: Array = G.cap(part)
		var a: Vector3 = (dxf * (c[0] as Vector3)) + delta
		var b: Vector3 = (dxf * (c[1] as Vector3)) + delta
		var rr := float(G.rad[part])
		for i in idx:
			m = minf(m, Body.seg_seg(sa[i], sb[i], a, b) - r - rr)
	return m


## the body G's clearance of the whole path (every sample) for these parts
static func clearance(P: Dictionary, G: Body, dxf: Transform3D, parts := TORSO) -> float:
	return _clear_of(P, G, dxf, Vector3.ZERO, range((P["ts"] as Array).size()), parts)


## the pelvis moved by delta_h (hero space; the drop is in it), both feet kept on their marks by Body.plant
static func _realize(base: Dictionary, DS: Scene, dxf: Transform3D, delta_h: Vector3) -> Dictionary:
	var G := scratch(DS)
	G.from_dict(base)
	G.fk()
	var st := {}
	for sd in ["_l", "_r"]:
		st[sd] = G.foot_state(sd)
	G.offset += dxf.affine_inverse().basis * delta_h
	G.fk()
	var miss := 0.0
	for sd in ["_l", "_r"]:
		var s: Array = st[sd]
		miss = maxf(miss, G.plant(sd, s[0], float(s[1]), bool(s[3])))
	return {"B": G, "miss": miss}


## can the legs still reach their feet, and does the centre of mass stay inside the support, if the pelvis moves by
## d (body space)? A cheap test before the clearance and the plant (the body moves rigidly: hips and COM by d)
static func _stands(G0: Body, poly: PackedVector2Array, com0: Vector3, d: Vector3) -> bool:
	for sd in ["_l", "_r"]:
		var ll := (G0.p0["calf" + sd] as Vector3).distance_to(G0.p0["thigh" + sd]) + (G0.p0["foot" + sd] as Vector3).distance_to(G0.p0["calf" + sd])
		if ((G0.P["thigh" + sd] as Vector3) + d).distance_to(G0.P["foot" + sd]) > 0.985 * ll:
			return false
	return Balance.signed_dist(poly, Vector2(com0.x + d.x, com0.z + d.z)) >= MARGIN_MIN + 0.005


## the smallest move of head and torso that clears the weapon line by CLEAR. The pelvis moves by (a direction on the floor
## x a step) + a drop, tried smallest first; each is kept only if the legs reach, the weight stays inside the feet, the
## torso clears the path, and then the plant and the clearance are checked on the realised body.
## {"ok", "kind" ("SLIP" / "DUCK" / "STAY"), "t", "pose", "B", "move" (m, the head's), "head", "torso" (clearance, m),
## "com" (margin, m), "foot" (m)}
static func slip(P: Dictionary, DS: Scene, dxf: Transform3D) -> Dictionary:
	var out := {"ok": false, "kind": "SLIP", "why": ""}
	var tc: float = P["tc"]
	var G0 := ghost(DS, tc)
	var base := G0.to_dict()
	var ts: Array = P["ts"]
	var coarse := []
	for i in range(0, ts.size(), SEARCH_EVERY):
		coarse.append(i)
	if coarse[-1] != ts.size() - 1:
		coarse.append(ts.size() - 1)
	# when the tip comes closest to the head: the pose must be in place by then
	var hc: Array = G0.cap("head")
	var hmid: Vector3 = dxf * (((hc[0] as Vector3) + (hc[1] as Vector3)) * 0.5)
	var t_close := tc
	var dmin := INF
	for i in ts.size():
		var d: float = (P["p"][i] as Vector3).distance_to(hmid)
		if d < dmin:
			dmin = d
			t_close = ts[i]
	out["t"] = t_close
	if _clear_of(P, G0, dxf, Vector3.ZERO, coarse) >= PLAN:
		var cl0 := clearance(P, G0, dxf)
		if cl0 >= CLEAR + 0.003:
			out.merge({"ok": true, "kind": "STAY", "pose": base, "B": G0, "move": 0.0, "head": clearance(P, G0, dxf, ["head"]),
				"torso": cl0, "com": float(Balance.read(G0)["margin"]), "foot": 0.0}, true)
			return out
	var bal0 := Balance.read(G0)
	var poly: PackedVector2Array = bal0["poly"]
	var com0: Vector3 = bal0["com"]
	var xb := dxf.affine_inverse().basis
	var cands := []
	for k in 16:
		var az := TAU * float(k) / 16.0
		var u := Vector3(cos(az), 0, sin(az))
		for sh in range(0, 11):
			for dr in range(0, 7):
				if sh == 0 and dr == 0:
					continue
				if sh == 0 and k > 0:
					continue
				var dl: Vector3 = u * (0.04 * float(sh)) + Vector3(0, -0.06 * float(dr), 0)
				cands.append({"dl": dl, "s": dl.length()})
	cands.sort_custom(func(a, b): return float(a["s"]) < float(b["s"]))
	var tries := 0
	for c in cands:
		var dl: Vector3 = c["dl"]
		if not _stands(G0, poly, com0, xb * dl):
			continue
		if _clear_of(P, G0, dxf, dl, coarse) < PLAN:
			continue
		if tries >= 25:
			break
		tries += 1
		var rz := _realize(base, DS, dxf, dl)
		if float(rz["miss"]) > 0.015:
			continue
		var G: Body = rz["B"]
		var cl := clearance(P, G, dxf)
		if cl < CLEAR + 0.003:
			continue
		var bal := Balance.read(G)
		if float(bal["margin"]) < MARGIN_MIN or (bal["down"] as Array).size() < 2:
			continue
		var h1: Array = G.cap("head")
		var h1m: Vector3 = dxf * (((h1[0] as Vector3) + (h1[1] as Vector3)) * 0.5)
		var vert := absf(h1m.y - hmid.y)
		var hor := Vector2(h1m.x - hmid.x, h1m.z - hmid.z).length()
		out.merge({"ok": true, "kind": "DUCK" if vert > hor else "SLIP", "pose": G.to_dict(), "B": G, "move": h1m.distance_to(hmid),
			"head": clearance(P, G, dxf, ["head"]), "torso": cl, "com": float(bal["margin"]), "foot": float(rz["miss"]),
			"dir": h1m - hmid}, true)
		return out
	out["why"] = "no slip or duck clears the path by 10 cm with both feet kept and the weight inside them: step the fighter back or pick a slower card"
	return out


# ---------------------------------------------------------------- ALL THREE

## up to three proposals for the defender: BLOCK, SLIP/DUCK, PARRY, each {"ok", "kind", "t", "pose", "B", "label", ...}.
## AS / DS: the two scenes; axf / dxf: their placements in the hero's space; t: the playhead (picks the card)
static func suggest(AS: Scene, axf: Transform3D, DS: Scene, dxf: Transform3D, t: float) -> Dictionary:
	var ci := card_of(AS, t)
	var P := strike(AS, axf, DS, dxf, ci)
	if not bool(P["ok"]):
		return {"ok": false, "why": P["why"], "path": P, "list": []}
	var list := [guard(P, DS, dxf, false), slip(P, DS, dxf), guard(P, DS, dxf, true)]
	for r in list:
		r["label"] = text(r, P)
	return {"ok": true, "why": "", "path": P, "list": list}


## the label: the kind and the numbers
static func text(r: Dictionary, P: Dictionary) -> String:
	if not bool(r["ok"]):
		return "%s: none  (%s)" % [r["kind"], r["why"]]
	match String(r["kind"]):
		"BLOCK":
			return "BLOCK  %.2fs\nforearm %.1f cm off the path, %.0f deg across it\ncontact gap %.1f cm at %.1f m/s" % [
				r["tx"], float(r["dist"]) * 100.0, r["across"], float(r["gap"]) * 100.0, r["speed"]]
		"PARRY":
			return "PARRY  %.2fs\nforearm %.1f cm off the path, deflects %.0f deg\ntip ends %.0f cm aside at the hit; contact gap %.1f cm" % [
				r["tx"], float(r["dist"]) * 100.0, r["deflect"], float(r["aside"]) * 100.0, float(r["gap"]) * 100.0]
		"STAY":
			return "SLIP  %.2fs\nalready clear: head %.1f cm, torso %.1f cm\ncentre of mass %.1f cm inside the feet" % [
				r["t"], float(r["head"]) * 100.0, float(r["torso"]) * 100.0, float(r["com"]) * 100.0]
		_:
			return "%s  %.2fs\nhead clears %.1f cm (torso %.1f cm), moved %.0f cm\ncentre of mass %.1f cm inside the feet" % [
				r["kind"], r["t"], float(r["head"]) * 100.0, float(r["torso"]) * 100.0, float(r["move"]) * 100.0, float(r["com"]) * 100.0]
	return ""
