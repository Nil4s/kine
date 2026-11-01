class_name PropMove
extends RefCounted
## TYPED MOVES WITH PROPS (Friday plan 134): "pick up the box", "throw the ball", "swing the sword", "open the door".
## The words name a prop in the scene; the character stands in front of it, bends or squats until his right hand (the wrist) is on
## the prop's GRIP POINT (reach: Body.reach, the arm's IK), and the prop is carried by that hand from that card on (the Scene's
## card["take"]: the grip is where the prop is in the hand on the take card, so the prop follows the hand). A throw lets go at the
## card where the hand is moving fastest (card["drop"]: the flight is Throw.trajectory from the hand's velocity); a door is
## pushed open by keying its swing while the hand stays on the handle.
##
## GRIP POINT (ours, set on this body; Friday 132's per-prop grip is not on this branch): the spot the WRIST goes to. A box or crate:
## the middle of the face nearest the character, GRIP_OUT outside it, GRIP_BELOW under its top edge (hand over the edge). A ball:
## on the side toward the character at the ball's middle height, GRIP_OUT off the surface. A sword (a rod): above the handle end
## nearer him, one quarter of the rod in. A door: its handle, 6.5 cm in from the free edge, 1 m up, on his side of the leaf.
## Every function is static and leaves the Body as it found it. Returns are plain dictionaries.

const GRIP_OUT := 0.02        # m: the wrist stops this far outside the face it grips
const BALL_ABOVE := 0.21      # m: a ball is taken from above: the wrist this far over its top (a squat can come no lower than this on this body)
const GRIP_BELOW := -0.03     # m: under the top edge of a box (negative: the wrist is this far ABOVE the top edge, the hand over it)
const STAND_OFFS := [0.45, 0.38, 0.52, 0.32, 0.58]
const TOL_GRIP := 0.02        # m: the wrist is on the grip point within this (the plan's bar is 3 cm); a deep bend leaves the arm at its limits
const STAND_OFF := 0.32       # m: his pelvis stands this far from the grip point, along the face's normal
const WALK_MIN := 1.45        # m: shorter than this and he just steps (PathWalk refuses a walk under two steps)
const PICK_MAX := 0.7         # m: the biggest side of a prop he can pick up (a crate is 0.6; a rod such as a sword is the exception)
const TOL := 0.002            # m: the wrist is on the grip point within this (the reach solves to 0.01 mm; this is the search's stop)
const E_STEP := 0.04          # the search of the bend: 0 (standing) .. 1 (full squat), this step
const DROP_MAX := 0.6        # m: the pelvis comes down this far at e = 1
const TRUNK_MAX := 60.0       # deg: the trunk leans this far at e = 1
const HIPS_BACK := 0.05       # m: the hips go back this far at e = 1 (a squat sits back over the heels)
const MOVE := 0.6             # s: the default move of a card
const THROW_MOVE := 0.2       # s: the wind-up to the release (the hand covers about 0.9 m in it)
const FLIGHT_TAIL := 0.3      # s of rest after the ball lands in a clip
const OPEN_DEG := 40.0        # deg: the most he pushes a door in one move (the arm follows the handle; he leans, he does not walk through)

const FILL := ["the", "a", "an", "up", "my", "his", "her", "that", "this", "it", "over", "out", "away", "your", "some", "with", "to", "at", "open"]
const V_PICK := ["pick", "grab", "lift", "take", "carry", "hold"]
const V_THROW := ["throw", "toss", "hurl", "chuck"]
const ALIAS := {"football": "ball", "soccer": "ball", "blade": "sword", "doorway": "door", "boxes": "box", "crates": "crate", "balls": "ball", "swords": "sword",
	"cardboard": "moving box", "parcel": "moving box"}
## nouns that are props Kine knows (a missing one is said in plain words); other nouns fall through to the move builder
const KNOWN := ["box", "crate", "ball", "sword", "door", "chair", "table", "stool", "bench", "bed", "moving box", "cup", "barrel", "bottle", "bag", "stone", "rock", "hammer", "staff"]


## the words -> {"verb": "pick" | "throw" | "swing" | "open", "words": [the noun candidates]} ; {} = not this kind of line
static func parse(text: String) -> Dictionary:
	var low := text.to_lower()
	for ch in [",", ".", "!", "?", ";", "'", "\""]:
		low = low.replace(ch, " ")
	if (" " + low + " ").contains(" then ") or (" " + low + " ").contains(" and "):
		return {}
	var ws: Array = Array(low.split(" ", false))
	if ws.size() < 2:
		return {}
	var v: String = ws[0]
	var verb := ""
	if V_PICK.has(v):
		verb = "pick"
	elif V_THROW.has(v):
		verb = "throw"
	elif v == "swing" or v == "swish":
		verb = "swing"
	elif v == "open":
		verb = "open"
	else:
		return {}
	var rest: Array = ws.slice(1).filter(func(w): return not (FILL.has(w) and not (w == "open")))
	rest = rest.map(func(w): return String(ALIAS.get(w, w)))
	if rest.is_empty():
		return {}
	var cand: Array = []
	for i in rest.size():
		cand.append(rest[i])
		if i + 1 < rest.size():
			cand.append("%s %s" % [rest[i], rest[i + 1]])
	return {"verb": verb, "words": cand, "first": rest[0]}


## the scene's prop the words name, the nearest to `from` (an xz point) if several: its index, or -1
static func find(m: Node, words: Array, from: Vector3) -> int:
	var best := -1
	var bd := INF
	for i in m.S.props.size():
		var nm: String = m._prop_name(i)
		if nm == "":
			continue
		var hit := false
		for w in words:
			if nm == w or nm.ends_with(" " + String(w)):
				hit = true
		if not hit:
			continue
		var o: Vector3 = (m.S.props[i]["xf"] as Transform3D).origin
		var d := Vector2(o.x - from.x, o.z - from.z).length()
		if d < bd:
			bd = d
			best = i
	return best


## the world box of a prop's solids: [min, max]
static func bounds(p: Dictionary) -> Array:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for sw in Props.solids(p):
		var xf: Transform3D = sw["xf"]
		var h: Vector3 = sw["half"]
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var c := xf * Vector3(h.x * sx, h.y * sy, h.z * sz)
					lo = lo.min(c)
					hi = hi.max(c)
	return [lo, hi]


static func pickable(p: Dictionary) -> bool:
	if Props.hinged(p):
		return false
	if RigidDrop.rod(p):
		return true
	var b := bounds(p)
	var d: Vector3 = (b[1] as Vector3) - (b[0] as Vector3)
	return maxf(d.x, maxf(d.y, d.z)) <= PICK_MAX + 1e-6


## the grip point of prop p for a hand coming from the floor point `from`: {"pt": the wrist's spot, "n": the horizontal outward normal
## of the grip (he stands along it and faces against it)}
static func grip_point(p: Dictionary, from: Vector3, verb := "pick") -> Dictionary:
	if Props.hinged(p):
		var xf: Transform3D = (p["xf"] as Transform3D) * Props.leaf_xf(p)
		var k := Props.scale_of(p)
		var w := float(Props.kind_of(p["kind"]).get("width", 0.8)) * k
		var nz: Vector3 = xf.basis * Vector3(0, 0, 1)
		var side := 1.0
		if (Vector3(from.x, 0.0, from.z) - Vector3(xf.origin.x, 0.0, xf.origin.z)).dot(Vector3(nz.x, 0.0, nz.z)) < 0.0:
			side = -1.0
		var n := Vector3(nz.x, 0.0, nz.z).normalized() * side
		var pt := xf * Vector3(w - 0.065 * k, 1.0 * k, 0.0) + n * 0.06
		return {"pt": pt, "n": n}
	var sws: Array = Props.solids(p)
	if RigidDrop.rod(p):
		var sw0: Dictionary = sws[0]
		var xf0: Transform3D = sw0["xf"]
		var ax: Vector3 = xf0.basis * Vector3(1, 0, 0)
		ax.y = 0.0
		ax = ax.normalized()
		var hl: float = (sw0["half"] as Vector3).x
		var e1 := xf0.origin + ax * hl * 0.5
		var e2 := xf0.origin - ax * hl * 0.5
		var fz := Vector3(from.x, 0.0, from.z)
		var pe := e1 if Vector3(e1.x, 0.0, e1.z).distance_to(fz) < Vector3(e2.x, 0.0, e2.z).distance_to(fz) else e2
		var n2 := Vector3(pe.x - xf0.origin.x, 0.0, pe.z - xf0.origin.z)
		var away := Vector3(fz.x - pe.x, 0.0, fz.z - pe.z)
		var side_n := ax.cross(Vector3.UP)
		if side_n.dot(away) < 0.0:
			side_n = -side_n
		var h2: float = (sw0["half"] as Vector3).y
		return {"pt": Vector3(pe.x, xf0.origin.y + h2 + 0.04, pe.z), "n": side_n.normalized() if side_n.length() > 0.01 else n2.normalized()}
	var sw: Dictionary = sws[0]
	var xf1: Transform3D = sw["xf"]
	var hf: Vector3 = sw["half"]
	var toward := Vector3(from.x - xf1.origin.x, 0.0, from.z - xf1.origin.z)
	if toward.length() < 0.001:
		toward = Vector3(0, 0, 1)
	toward = toward.normalized()
	if sw.has("r"):   # a ball: on the side toward him at the ball's middle height
		var r: float = sw["r"]
		return {"pt": xf1.origin + toward * (r * 0.4 + GRIP_OUT) + Vector3(0, r + BALL_ABOVE, 0), "n": toward}   # the hand comes down on the ball's top, BALL_ABOVE over it
	var best_n := Vector3(0, 0, 1)
	var best_d := -2.0
	var best_h := 0.0
	for axis in [Vector3(1, 0, 0), Vector3(0, 0, 1)]:
		for sgn in [-1.0, 1.0]:
			var n3: Vector3 = xf1.basis * (axis * sgn)
			n3.y = 0.0
			n3 = n3.normalized()
			if n3.dot(toward) > best_d:
				best_d = n3.dot(toward)
				best_n = n3
				best_h = hf.x if axis.x != 0.0 else hf.z
	var top := xf1.origin.y + hf.y
	var y := maxf(top - GRIP_BELOW, xf1.origin.y)
	var base := Vector3(xf1.origin.x, y, xf1.origin.z)
	return {"pt": base + best_n * (best_h + GRIP_OUT), "n": best_n}


## ---- the body

## the arm's root joint of a hand (the shoulder: the upper arm)
static func _root(B: Body, tip: String) -> String:
	return B.parent[B.parent[tip]]


## one key: standing at xz (+ shift along fwd) facing fwd, the pelvis lowered by `drop` m and the trunk leaning `lean` deg, the feet on their marks,
## then every tip on its target. Returns the largest miss (m)
static func _key(B: Body, xz: Vector2, fwd: Vector3, y0: float, feet: Array, drop: float, targets: Dictionary, lean := 0.0, back := 0.0) -> float:
	B.props = []
	var at := xz - Vector2(fwd.x, fwd.z) * back
	Rise._place(B, at, y0 - drop, fwd)
	Rise._trunk(B, lean)
	for k in 2:
		for i in 2:
			B.plant(["_l", "_r"][i], feet[i], B.foot_heading(["_l", "_r"][i]), true)
	B.ground()   # as the Scene grounds every frame it plays (a bent leg that leaves a sole under the floor lifts the body): the arm is solved after it
	var miss := 0.0
	for tip in targets:
		miss = maxf(miss, B.reach(tip, targets[tip]))
	return miss


## the least effort (drop m, lean deg) at which the wrist reaches the target AND the pose survives the file round trip (to_dict / from_dict
## put it on the floor if a part is under it: a squat too deep for the floor is refused here, not found out in the clip). {} = none
static func solve_bend(B: Body, xz: Vector2, fwd: Vector3, y0: float, feet: Array, tip: String, target: Vector3) -> Dictionary:
	var combos: Array = []
	for di in 10:
		for li in 11:
			var d := DROP_MAX * float(di) / 9.0
			var l := TRUNK_MAX * float(li) / 10.0
			combos.append([d / DROP_MAX + l / TRUNK_MAX * 0.8, d, l])
	combos.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	for c in combos:
		var d: float = c[1]
		var l: float = c[2]
		if _key(B, xz, fwd, y0, feet, d, {tip: target}, l, HIPS_BACK * d / DROP_MAX) >= TOL_GRIP:
			continue
		var pose := B.to_dict()
		B.from_dict(pose)
		B.ground()
		if (B.P[tip] as Vector3).distance_to(target) < TOL_GRIP + 0.005:
			return {"drop": d, "lean": l, "back": HIPS_BACK * d / DROP_MAX}
	return {}


static func _right(B: Body) -> Vector3:
	var r: Vector3 = B.P["hand_r"] - B.P["hand_l"]
	r.y = 0.0
	return r.normalized()


static func _card(nm: String, B: Body, move: float, hold := 0.0) -> Dictionary:
	return {"name": nm, "pose": B.to_dict(), "move": move, "hold": hold, "plant": ["_l", "_r"]}


## the cards of a typed prop move for prop index idx of m.S.props. verb: "pick" | "throw" | "swing" | "open".
## {"cards", "why" ("" = built), "take" (index of the card the hand holds from, -1 = none), "drop" (card the hand lets go at, -1 = none),
##  "grip" (the wrist's spot at the take card), "hands", "swing" ([card index, deg] for a door), "say"}.
static func build(m: Node, verb: String, idx: int) -> Dictionary:
	var out := {"cards": [], "why": "", "take": -1, "drop": -1, "grip": Vector3.ZERO, "hands": ["_r"], "swing": [], "say": ""}
	var B: Body = m.B
	var S = m.S
	var p: Dictionary = S.props[idx]
	var nm: String = m._prop_name(idx)
	var keep: Dictionary = B.state()
	var bp = B.props
	var start := Vector3.ZERO
	if S.cards.is_empty():
		start = Vector3(B.P["pelvis"].x, 0.0, B.P["pelvis"].z)
	else:
		m._ps().apply(B, S.length())
		start = Vector3(B.P["pelvis"].x, 0.0, B.P["pelvis"].z)
	B.set_state(keep)
	var door := verb == "open"
	var gp := grip_point(p, start, verb)
	var gpt: Vector3 = gp["pt"]
	var n: Vector3 = gp["n"]
	var stand := Vector3(gpt.x, 0.0, gpt.z) + n * STAND_OFF
	var fwd := -n
	# how far in front of it he stands: the first distance (STAND_OFFS) from which the arm gets the wrist onto the grip point; his right
	# shoulder is put over the grip point sideways (the pelvis is shifted by the shoulder's offset from it)
	var base_stand := stand
	var found_so := false
	for so in STAND_OFFS:
		stand = Vector3(gpt.x, 0.0, gpt.z) + n * float(so)
		Rise._stand(B, Vector2(stand.x, stand.z), fwd)
		var rt0 := _right(B)
		var lat: float = ((B.P[_root(B, "hand_r")] as Vector3) - (B.P["pelvis"] as Vector3)).dot(rt0)
		stand -= rt0 * lat
		Rise._stand(B, Vector2(stand.x, stand.z), fwd)
		if not solve_bend(B, Vector2(stand.x, stand.z), fwd, (B.P["pelvis"] as Vector3).y, Rise._balls(B), "hand_r", gpt).is_empty():
			found_so = true
			break
	if not found_so:
		stand = base_stand
	var cards: Array = []
	# the walk to the spot in front of it (PathWalk), or a step
	var dvec := stand - start
	if dvec.length() >= WALK_MIN:
		var d := dvec.normalized()
		var r: Dictionary = PathWalk.build([start + d * PathWalk.HIP_BACK, stand], 1.3)
		if not bool(r["ok"]):
			B.set_state(keep)
			B.props = bp
			out["why"] = "the walk to the %s is refused (%s)" % [nm, String(r["why"])]
			return out
		cards = ((r["scene"] as Dictionary)["cards"] as Array).duplicate()
	var sxz := Vector2(stand.x, stand.z)
	Rise._stand(B, sxz, fwd)
	var y0: float = (B.P["pelvis"] as Vector3).y
	var feet: Array = Rise._balls(B)
	var right := _right(B)
	var c_stand := _card("stand by the %s" % nm, B, MOVE if cards.is_empty() else 0.7)
	cards.append(c_stand)
	var hand := "hand_r"
	var sol := solve_bend(B, sxz, fwd, y0, feet, hand, gpt)
	if sol.is_empty():
		B.set_state(keep)
		B.props = bp
		out["why"] = "he cannot reach the %s from the floor in front of it (too low or too far for the arm)" % nm
		return out
	var dr: float = sol["drop"]
	var ln: float = sol["lean"]
	var bk: float = sol["back"]
	if not door and dr + ln > 0.0:
		_key(B, sxz, fwd, y0, feet, dr * 0.8, {}, ln * 0.8, bk * 0.8)
		cards.append(_card("bend toward the %s" % nm, B, 0.7))
	var miss := _key(B, sxz, fwd, y0, feet, dr, {hand: gpt}, ln, bk)
	out["grip"] = gpt
	out["miss"] = miss
	var grip_card := _card("%s the %s" % ["hand on" if door else "take hold of", nm], B, 0.5, 0.15)
	cards.append(grip_card)
	var gi := cards.size() - 1
	var rs: Vector3 = B.P[_root(B, hand)]
	if door:
		# push it open: the wrist stays on the handle while the leaf turns; he leans in as far as the arm follows
		var sw0 := float(p.get("swing", 0.0))
		var sgn := 1.0   # the leaf's + swing turns toward +Z
		var nz: Vector3 = (p["xf"] as Transform3D).basis * Vector3(0, 0, 1)
		var pushing := n.dot(Vector3(nz.x, 0.0, nz.z).normalized()) < 0.0   # he stands on the -Z side: + swing pushes the leaf away
		sgn = 1.0 if pushing else -1.0
		var done := 0.0
		var steps := 4
		for s2 in range(1, steps + 1):
			var deg := OPEN_DEG * float(s2) / steps
			var q: Dictionary = p.duplicate()
			q["swing"] = sw0 + sgn * deg
			var tgt: Vector3 = grip_point(q, start, verb)["pt"]
			var found := false
			for sh in range(0, 13):
				var shift := 0.05 * sh
				var sxz2 := sxz + Vector2(fwd.x, fwd.z) * shift
				Rise._stand(B, sxz2, fwd)
				var feet2: Array = Rise._balls(B)
				for l in range(0, 31, 5):
					if _key(B, sxz2, fwd, y0, feet2, 0.0, {hand: tgt}, float(l)) < TOL:
						found = true
						break
				if found:
					break
			if not found:
				break
			done = deg
			cards.append(_card("push the %s open" % nm, B, 0.45))
			(out["swing"] as Array).append([cards.size() - 1, sw0 + sgn * deg])
		if done <= 0.0:
			B.set_state(keep)
			B.props = bp
			out["why"] = "the %s handle is out of the arm's reach once it starts to move" % nm
			return out
		out["say"] = "He puts his hand on the %s handle and pushes it open %.0f degrees" % [nm, done] if pushing else "He puts his hand on the %s handle and pulls it open %.0f degrees" % [nm, done]
		B.set_state(keep)
		B.props = bp
		B.fk()
		out["cards"] = cards
		return out
	out["take"] = gi
	# lift: upright, the prop held in front of the belly
	var pel: Vector3 = B.P["pelvis"]
	var carry := Vector3(sxz.x, 0.0, sxz.y) + fwd * 0.38 + right * 0.10
	carry.y = 0.0
	var lift_t := Vector3(carry.x, y0 + 0.12, carry.z)
	_key(B, sxz, fwd, y0, feet, 0.0, {hand: lift_t}, 5.0)
	cards.append(_card("stand up with the %s" % nm, B, 0.9, 0.1))
	if verb == "pick":
		out["say"] = "He takes the %s in his right hand and lifts it" % nm
	elif verb == "throw":
		var rs2: Vector3 = B.P[_root(B, hand)]
		var back := rs2 + (-fwd * 0.30) + right * 0.12 + Vector3(0, 0.30, 0)
		_key(B, sxz, fwd, y0, feet, 0.0, {hand: back}, -6.0)
		cards.append(_card("wind up", B, 0.5, 0.05))
		var ahead := rs2 + fwd * 0.55 + Vector3(0, 0.30, 0) + right * 0.04
		_key(B, sxz, fwd, y0, feet, 0.0, {hand: ahead}, 14.0)
		cards.append(_card("let go of the %s" % nm, B, THROW_MOVE, 0.0))
		out["drop"] = cards.size() - 1
		var thru := rs2 + fwd * 0.30 + Vector3(0, -0.30, 0) + right * 0.12
		_key(B, sxz, fwd, y0, feet, 0.0, {hand: thru}, 20.0)
		cards.append(_card("follow through", B, 0.3, 0.2))
		out["say"] = "He picks up the %s and throws it" % nm
	else:   # swing: overhead, then down in front of him
		var rs3: Vector3 = B.P[_root(B, hand)]
		var up_t := rs3 + Vector3(0, 0.55, 0) + (-fwd * 0.05) + right * 0.05
		_key(B, sxz, fwd, y0, feet, 0.0, {hand: up_t}, -4.0)
		cards.append(_card("raise the %s" % nm, B, 0.6, 0.1))
		var dn := rs3 + fwd * 0.55 + Vector3(0, -0.35, 0) + right * 0.05
		_key(B, sxz, fwd, y0, feet, 0.0, {hand: dn}, 22.0)
		cards.append(_card("swing the %s down" % nm, B, 0.25, 0.25))
		out["say"] = "He picks up the %s and swings it" % nm
	B.set_state(keep)
	B.props = bp
	B.fk()
	out["cards"] = cards
	return out



## the typed line -> the built move, in ONE undo step (m._do). Returns {"handled": bool, "say": String, "ok": bool}
## handled = false: the words are not a prop move (the move builder gets them). A prop that is not in the scene, or cannot do it: said
## in plain words, nothing added.
static func run(m: Node, text: String) -> Dictionary:
	var ps := parse(text)
	if ps.is_empty():
		return {"handled": false}
	var verb: String = ps["verb"]
	var words: Array = ps["words"]
	var from := Vector3.ZERO
	if not m.S.cards.is_empty():
		var keep: Dictionary = m.B.state()
		m._ps().apply(m.B, m.S.length())
		from = m.B.P["pelvis"]
		m.B.set_state(keep)
	else:
		from = m.B.P["pelvis"]
	var idx := find(m, words, from)
	var noun: String = String(ps["first"])
	if idx < 0:
		var known := false
		for w in words:
			known = known or KNOWN.has(String(w)) or Props.has_kind(String(w).replace(" ", "_"))
		if verb in ["swing", "throw"] and not known:
			return {"handled": false}
		if verb == "swing" and TextBlocking.WEAPON.has(noun):
			return {"handled": false}   # a weapon word with no prop: the move builder equips it
		var shown := String(words[0]) if known else noun
		for w in words:
			if KNOWN.has(String(w)):
				shown = String(w)
		return {"handled": true, "ok": false, "say": "There is no %s in the scene. Add one from the Library (Props), then type '%s' again." % [shown, text.strip_edges()]}
	var p: Dictionary = m.S.props[idx]
	var nm: String = m._prop_name(idx)
	if verb == "open" and not Props.hinged(p):
		return {"handled": true, "ok": false, "say": "The %s does not open. Only a door opens." % nm}
	if verb != "open" and Props.hinged(p):
		return {"handled": true, "ok": false, "say": "The %s is fixed to its hinge: type 'open the door'." % nm}
	if verb != "open" and not pickable(p):
		return {"handled": true, "ok": false, "say": "The %s is too big to pick up." % nm}
	var go := build(m, verb, idx)
	if String(go["why"]) != "" or (go["cards"] as Array).is_empty():
		return {"handled": true, "ok": false, "say": "Kine could not build that: %s." % (String(go["why"]) if String(go["why"]) != "" else "no cards")}
	m._do(func(): _add(m, go, idx))
	return {"handled": true, "ok": true, "say": String(go["say"]), "cards": (go["cards"] as Array).size()}


static func _add(m: Node, go: Dictionary, idx: int) -> void:
	var S = m.S
	var cards: Array = go["cards"]
	var at: int = S.cards.size()
	var i := at
	for c in cards:
		S.add(c["name"], c["pose"], i)
		var cd: Dictionary = S.cards[i]
		cd["move"] = c["move"] if (i > at and float(c["move"]) >= 0.0) else 0.5
		cd["hold"] = c["hold"]
		for k in ["plant", "ease", "steps", "lift", "walk"]:
			if c.has(k):
				cd[k] = c[k]
		i += 1
	if int(go["take"]) >= 0:
		S.cards[at + int(go["take"])]["take"] = {"prop": idx, "hands": go["hands"]}
	S._carry_memo = []
	if not (go["swing"] as Array).is_empty():
		var ts: Array = S.times()
		var p: Dictionary = S.props[idx]
		var g0 := at + (cards.size() - 1 - (go["swing"] as Array).size())
		Props.key_at(p, float(ts[g0][1]), p["xf"], float(p.get("swing", 0.0)))
		for sw in go["swing"]:
			Props.key_at(p, float(ts[at + int(sw[0])][1]), p["xf"], float(sw[1]))
	if int(go["drop"]) >= 0:
		# THE THROW: the hand carries the ball to the release card; from there it flies on prop keys (the Throw to... way: keys after the
		# take win), launched with the hand's mean velocity over the throwing move (wind-up card -> release card)
		var ts2: Array = S.times()
		var ri := at + int(go["drop"])
		var tb: float = float(ts2[ri][1])
		var ta: float = float(ts2[ri - 1][1])
		S._carry_memo = []
		var grip: Transform3D = S._carry_data(m.B)[0]["grip"]
		S.apply(m.B, ta)
		var h0: Vector3 = Scene.hand_frame(m.B, go["hands"]).origin
		S.apply(m.B, tb)
		var xf1: Transform3D = Scene.hand_frame(m.B, go["hands"]) * grip
		var h1: Vector3 = Scene.hand_frame(m.B, go["hands"]).origin
		var v0 := (h1 - h0) / maxf(tb - ta, 0.05)
		var tr: Dictionary = Throw.trajectory(xf1.origin, v0, S.solid_props(), float(S.props[idx].get("e", Throw.E)))
		var tl := float(tr["t_rest"])
		var q: Dictionary = S.props[idx]
		var tau := 0.0
		while tau < tl:
			var x2 := xf1
			x2.origin = Throw.pos_at(tr, tau)
			Props.key_at(q, tb + tau, x2)
			tau += 0.05
		var x3 := xf1
		x3.origin = Throw.pos_at(tr, tl)
		Props.key_at(q, tb + tl, x3)
		S.cards[S.cards.size() - 1]["hold"] = minf(tl, 2.5) + FLIGHT_TAIL
		S._carry_memo = []
	m.sel_card = S.cards.size() - 1
	m.playhead = S.times()[m.sel_card][1]
	m._rebuild_cards()
	S.apply(m.B, m.playhead)
