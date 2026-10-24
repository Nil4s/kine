## text_view.gd - TEXT VIEW OF A POSE (docs/INNOVATIONS.md N001): a model that cannot see images still sees the pose.
## view(B) -> {"text": the whole thing (< 2,500 chars), "ascii": the two drawings + legend, "words": one paragraph, "facts": the
## numbers the words were read from}. Pure: it reads the body and never moves it; the same pose gives the same bytes.
##
## THE DRAWINGS: a FRONT and a SIDE stick figure side by side, each COLS x ROWS characters, the floor (y = 0) on the bottom
## row. Both are in HIS frame, not the world's: the world is turned by the hips' yaw about the pelvis, so "front" is always
## his front (the paragraph says where that faces). Front = looking at him (his left on your right); side = from his right
## (his front on your right). Each view is centred on the middle of the figure's extent across it. A cell is CW wide and CH tall: text cells are about twice as tall as wide (a monospace
## font's advance is ~0.5-0.6 of its line height), so 6 x 11 cm keeps the figure roughly in proportion. 20 rows above the
## floor = 2.2 m: a 1.8 m man's raised fist (~2.2 m) still fits; 31 columns = 1.8 m: a T-pose's hands or an 83 cm lunge fit.
## A joint is drawn at its exact cell; if another joint already has it, at the first free one of the 8 around it (so every
## joint is within 1 character of its cell); off the grid it is clamped to the edge and listed "off grid".
##
## THE WORDS (each from a number in "facts"):
##   stance   the hips' drop below standing (rest pelvis height), named with say_it.gd's own crouch fractions (CROUCH_LIGHT
##            0.15, CROUCH_DEFAULT 0.30, CROUCH_DEEP 0.42): the cut between two words is the midpoint of their fractions, so
##            "crouched" typed into SayIt reads back "crouched". The feet's width and stagger (ankles, his frame).
##   feet     a foot part is DOWN by balance.gd's own rule (a capsule point within Balance.TOUCH of the floor or a prop): heel
##            and ball separately, so "on the toes" is the ball down and the heel up.
##   weight   the static lever rule along the line joining the two footprints' centres (the COM's floor point projected on
##            it), as force_view.gd splits the ground force at rest (no acceleration). The COM and footprints are balance.gd's.
##   balance  Balance.read's margin: past the feet by more than Balance.MARGIN_RES = off balance; inside by less = on the edge.
##   torso    lean = the pelvis -> neck line's tilt from vertical, forward / sideways in his frame; twist = the chest's
##            facing (spine_03) minus the hips' facing, about the vertical.
##   hands    the fist (the hand capsule's middle) against his own landmarks' heights NOW (say_it.gd's landmark(): head top,
##            eyes, chin, shoulder, chest, belly, hip, knee, plus the ankle): the nearest one names it, and above the top of
##            the head is "above his head". Reach (HEURISTIC, mine): the fist more than REACH out from its shoulder sideways =
##            "out to the side", forward = "reaching forward", more than 15 cm behind it = "behind him". A hand GUARDS when it is at chin, head or shoulder height and >= GUARD_FWD in front
##            of the chest (HEURISTIC, mine): one guarding and the other not = "guard open on the <other> side".
##   facing   the hips' yaw: 0 = +z (the world's front, where the default camera looks from).
class_name TextView
extends RefCounted

const COLS := 31
const ROWS := 21           # rows 0..19 above the floor, row 20 = the floor
const CW := 0.06           # m per column
const CH := 0.11           # m per row
const FLOOR_ROW := ROWS - 1
const MID := (COLS - 1) / 2   # the centre column
const GUARD_FWD := 0.10    # m in front of the chest for a raised hand to count as guarding (HEURISTIC, mine)
const REACH := 0.30        # m from the shoulder for a fist to be "out to the side" / "reaching forward" (HEURISTIC, mine)
const LEAN_SAY := 5.0      # deg: a lean or twist under this is "upright" / "square" (HEURISTIC: below what reads on screen)
## symbol -> how to find it. CAPS = his right, small = his left; the centre line has signs
const SYM := {"@": "head", "+": "neck", "#": "chest", "*": "pelvis",
	"S": "shoulder_r", "E": "elbow_r", "F": "fist_r", "H": "hip_r", "K": "knee_r", "A": "ankle_r", "T": "toe_r",
	"s": "shoulder_l", "e": "elbow_l", "f": "fist_l", "h": "hip_l", "k": "knee_l", "a": "ankle_l", "t": "toe_l"}
## drawing order = priority for a cell: the hands first (what an agent most asks about), the centre line last
const ORDER := ["F", "f", "@", "E", "e", "A", "a", "T", "t", "K", "k", "S", "s", "H", "h", "+", "#", "*"]
const BONES := [["@", "+"], ["+", "#"], ["#", "*"], ["+", "S"], ["+", "s"], ["S", "E"], ["E", "F"], ["s", "e"], ["e", "f"],
	["*", "H"], ["*", "h"], ["H", "K"], ["K", "A"], ["A", "T"], ["h", "k"], ["k", "a"], ["a", "t"]]
const LEGEND := "front: facing you (his left on your right) | side: from his right (his front on your right)\n@ head + neck # chest * pelvis; S E F shoulder elbow fist, H K A T hip knee ankle toe (CAPS right, small left); ^ centre of mass; = floor; 1 char = 6 cm wide, 11 cm tall"


## the world points of every symbol
static func points(B: Body) -> Dictionary:
	var hc: Vector3 = ((B.P["head"] as Vector3) + (B.E["head"] as Vector3)) * 0.5
	var out := {"@": hc, "+": B.P["neck_01"], "#": B.P["spine_03"], "*": B.P["pelvis"]}
	for sd in ["_r", "_l"]:
		var up: bool = sd == "_r"
		var fc: Array = B.cap("hand" + sd)
		out["S" if up else "s"] = B.P["upperarm" + sd]
		out["E" if up else "e"] = B.P["lowerarm" + sd]
		out["F" if up else "f"] = ((fc[0] as Vector3) + (fc[1] as Vector3)) * 0.5
		out["H" if up else "h"] = B.P["thigh" + sd]
		out["K" if up else "k"] = B.P["calf" + sd]
		out["A" if up else "a"] = B.P["foot" + sd]
		out["T" if up else "t"] = B.P["ball" + sd]
	return out


## the hips' yaw (deg): 0 = facing +z, + = turned toward +x
static func yaw(B: Body) -> float:
	var f: Vector3 = (B.G["pelvis"] as Quaternion) * Vector3(0, 0, 1)
	if Vector2(f.x, f.z).length() < 0.2:   # lying face up / down: the hips' forward is vertical; use their up instead
		f = (B.G["pelvis"] as Quaternion) * Vector3(0, 1, 0) * (-1.0 if f.y > 0.0 else 1.0)
	return rad_to_deg(atan2(f.x, f.z))


## a world point in his frame: x = his left, y = up, z = his front; the origin under the pelvis
static func local(B: Body, w: Vector3, yaw_deg: float) -> Vector3:
	var p: Vector3 = B.P["pelvis"]
	var d := Vector3(w.x - p.x, w.y, w.z - p.z)
	return d.rotated(Vector3.UP, -deg_to_rad(yaw_deg))


## the exact cell (col, row) of a local point in a view ("front" / "side"), not clamped; c = the view's centre (m)
static func cell(l: Vector3, view: String, c: float) -> Vector2i:
	var h := l.x if view == "front" else l.z
	return Vector2i(MID + roundi((h - c) / CW), FLOOR_ROW - roundi(l.y / CH))


## a view's centre: the middle of the figure's left-right extent in it (a lunge's back toe stays on the grid)
static func centre(B: Body, pts: Dictionary, yw: float, view: String) -> float:
	var lo := INF
	var hi := -INF
	for k in SYM:
		var l := local(B, pts[k], yw)
		var h := l.x if view == "front" else l.z
		lo = minf(lo, h)
		hi = maxf(hi, h)
	return (lo + hi) * 0.5


static func _grid(B: Body, pts: Dictionary, yw: float, view: String, com: Vector3) -> Dictionary:
	var g := []
	for r in ROWS:
		var row := []
		row.resize(COLS)
		row.fill(" ")
		g.append(row)
	for c in COLS:
		g[FLOOR_ROW][c] = "="
	var cells := {}
	var c0 := centre(B, pts, yw, view)
	for k in SYM:
		cells[k] = cell(local(B, pts[k], yw), view, c0)
	var inside := func(q: Vector2i) -> bool: return q.x >= 0 and q.x < COLS and q.y >= 0 and q.y < ROWS
	var clampc := func(q: Vector2i) -> Vector2i: return Vector2i(clampi(q.x, 0, COLS - 1), clampi(q.y, 0, ROWS - 1))
	# bones: the cells between two joints, a slash / bar / dash by the slope on screen
	for bn in BONES:
		var a: Vector2i = clampc.call(cells[bn[0]])
		var b: Vector2i = clampc.call(cells[bn[1]])
		var dx := b.x - a.x
		var dy := b.y - a.y
		var ch := "|" if absi(dx) * 2 < absi(dy) else ("-" if absi(dy) * 2 < absi(dx) else ("/" if (dx > 0) != (dy > 0) else "\\"))
		var n := maxi(absi(dx), absi(dy))
		for i in range(1, n):
			var q := Vector2i(a.x + roundi(dx * float(i) / n), a.y + roundi(dy * float(i) / n))
			g[q.y][q.x] = ch
	var lc: Vector3 = local(B, com, yw)
	var cc: Vector2i = clampc.call(cell(Vector3(lc.x, 0.0, lc.z), view, c0))
	g[FLOOR_ROW][cc.x] = "^"
	var taken := {}
	var drawn := {}
	var off := []
	var near := [Vector2i(0, 0), Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]
	for k in ORDER:
		var q0: Vector2i = cells[k]
		if not inside.call(q0):
			off.append(k)
			q0 = clampc.call(q0)
		var put := Vector2i(-1, -1)
		for d in near:
			var q: Vector2i = q0 + d
			if inside.call(q) and not taken.has(q):
				put = q
				break
		if put.x < 0:
			continue   # every cell around is a joint already: not drawn (the test counts these)
		taken[put] = true
		drawn[k] = put
		g[put.y][put.x] = k
	var lines := []
	for r in ROWS:
		lines.append("".join(g[r]))
	return {"lines": lines, "cells": cells, "drawn": drawn, "off": off}


## does a foot part touch the floor (or a prop) by balance.gd's rule
static func touches(B: Body, part: String) -> bool:
	var c: Array = B.cap(part)
	var r: float = B.rad[part]
	for k in 9:
		var p: Vector3 = (c[0] as Vector3).lerp(c[1], k / 8.0)
		if p.y - r - (0.0 if B.props.is_empty() else B.surface_at(p, r)) <= Balance.TOUCH:
			return true
	return false


## the share of the weight on the left foot (0..1) by the lever rule, or -1 when not both feet are down
static func left_share(B: Body, com: Vector3) -> float:
	var cen := {}
	for sd in ["_l", "_r"]:
		var f := Balance.footprint(B, sd)
		if f.is_empty():
			return -1.0
		var lo := f[0]
		var hi := f[0]
		for q in f:
			lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
			hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
		cen[sd] = (lo + hi) * 0.5
	var d: Vector2 = (cen["_l"] as Vector2) - (cen["_r"] as Vector2)
	if d.length_squared() < 1e-8:
		return 0.5
	return clampf((Vector2(com.x, com.z) - (cen["_r"] as Vector2)).dot(d) / d.length_squared(), 0.0, 1.0)


## the landmark heights (m, now) a hand on side sd is named against, highest first
static func landmarks(B: Body, sd: String) -> Array:
	var out := []
	for n in ["head", "eyes", "chin", "shoulder", "chest", "belly", "hip", "knee"]:
		out.append([n, (SayIt.landmark(B, n, sd, sd) as Vector3).y])
	out.append(["ankle", (B.P["foot" + sd] as Vector3).y])
	return out


static func height_word(B: Body, sd: String, y: float) -> String:
	var lm := landmarks(B, sd)
	if y > float(lm[0][1]):
		return "above his head"
	var best := ""
	var bd := INF
	for x in lm:
		if absf(y - float(x[1])) < bd:
			bd = absf(y - float(x[1]))
			best = x[0]
	return "the top of his head" if best == "head" else ("eye" if best == "eyes" else best) + " height"


static func _dir_word(v: Vector2) -> String:
	# v = (his left, his front)
	var a := rad_to_deg(atan2(v.x, v.y))   # 0 = front, 90 = left
	var names := ["front", "front-left", "left", "back-left", "back", "back-right", "right", "front-right"]
	return names[posmod(roundi(a / 45.0), 8)]


static func _facing_word(yw: float) -> String:
	var names := ["the front (+z)", "front-left (+z+x)", "left (+x)", "back-left (-z+x)", "the back (-z)", "back-right (-z-x)", "right (-x)", "front-right (+z-x)"]
	return names[posmod(roundi(yw / 45.0), 8)]


static func _deg_diff(a: float, b: float) -> float:
	return wrapf(a - b, -180.0, 180.0)


## the facts and the paragraph
static func read(B: Body) -> Dictionary:
	var yw := yaw(B)
	var bal := Balance.read(B)
	var com: Vector3 = bal["com"]
	var f := {"yaw_deg": snappedf(yw, 0.1)}
	# stance
	var stand: float = (B.p0["pelvis"] as Vector3).y
	var drop := clampf(1.0 - (B.P["pelvis"] as Vector3).y / stand, -1.0, 1.0)
	f["hip_drop"] = snappedf(drop, 0.001)
	var c_light: float = SayIt.CROUCH_LIGHT
	var stance := "standing tall"
	if drop >= (SayIt.CROUCH_DEFAULT + SayIt.CROUCH_DEEP) * 0.5:
		stance = "in a deep crouch"
	elif drop >= (c_light + SayIt.CROUCH_DEFAULT) * 0.5:
		stance = "crouched"
	elif drop >= c_light * 0.5:
		stance = "slightly crouched"
	var la := local(B, B.P["foot_l"], yw)
	var ra := local(B, B.P["foot_r"], yw)
	f["feet_apart_m"] = snappedf(absf(la.x - ra.x), 0.01)
	f["left_ahead_m"] = snappedf(la.z - ra.z, 0.01)
	var s := "%s (hips %d %% below standing)" % [stance, roundi(drop * 100.0)]
	s = s.left(1).to_upper() + s.substr(1)
	s += ", feet %d cm apart" % roundi(f["feet_apart_m"] * 100.0)
	var st: float = f["left_ahead_m"]
	if absf(st) >= 0.05:
		s += ", %s foot %d cm ahead" % ["left" if st > 0.0 else "right", roundi(absf(st) * 100.0)]
	var parts := []
	var feet := {}
	for sd in ["_l", "_r"]:
		var nm := "left" if sd == "_l" else "right"
		var heel := touches(B, "foot" + sd)
		var ball := touches(B, "ball" + sd)
		feet[nm] = "flat" if heel and ball else ("toes" if ball else ("heel" if heel else "up"))
		match feet[nm]:
			"flat":
				parts.append("%s foot flat" % nm)
			"toes":
				parts.append("%s foot on its toes" % nm)
			"heel":
				parts.append("%s foot on its heel" % nm)
			"up":
				var lo := INF
				for prt in ["foot" + sd, "ball" + sd]:
					var cp: Array = B.cap(prt)
					lo = minf(lo, minf((cp[0] as Vector3).y, (cp[1] as Vector3).y) - float(B.rad[prt]))
				parts.append("%s foot %d cm up" % [nm, roundi(lo * 100.0)])
	f["feet"] = feet
	s += "; " + " and ".join(parts) + ". "
	# weight
	var ls := left_share(B, com)
	f["weight_left"] = snappedf(ls, 0.001) if ls >= 0.0 else null
	if ls >= 0.0:
		var pl := roundi(ls * 100.0)
		if pl == 50:
			s += "Weight even, 50 % on each foot. "
		else:
			s += "Weight %d %% on the %s foot. " % [maxi(pl, 100 - pl), "left" if pl > 50 else "right"]
	elif bal["down"].size() == 1:
		s += "All his weight on the %s foot. " % ("left" if bal["down"][0] == "_l" else "right")
	else:
		s += "No foot on the floor. "
	# torso
	var v := local(B, B.P["neck_01"], yw) - local(B, B.P["pelvis"], yw)
	var fwd := rad_to_deg(atan2(v.z, v.y))
	var side := rad_to_deg(atan2(v.x, v.y))
	var cf: Vector3 = (B.G["spine_03"] as Quaternion) * Vector3(0, 0, 1)
	var tw := _deg_diff(rad_to_deg(atan2(cf.x, cf.z)), yw) if Vector2(cf.x, cf.z).length() > 0.2 else 0.0
	f["lean_fwd_deg"] = snappedf(fwd, 0.1)
	f["lean_left_deg"] = snappedf(side, 0.1)
	f["twist_left_deg"] = snappedf(tw, 0.1)
	var lean := []
	if absf(fwd) >= LEAN_SAY:
		lean.append("%d° %s" % [roundi(absf(fwd)), "forward" if fwd > 0.0 else "back"])
	if absf(side) >= LEAN_SAY:
		lean.append("%d° to his %s" % [roundi(absf(side)), "left" if side > 0.0 else "right"])
	s += ("Torso upright" if lean.is_empty() else "Torso leans " + " and ".join(lean))
	s += (", shoulders square to the hips. " if absf(tw) < LEAN_SAY else ", shoulders turned %d° to his %s of the hips. " % [roundi(absf(tw)), "left" if tw > 0.0 else "right"])
	# hands
	var pts := points(B)
	var chest: Vector3 = B.P["spine_03"]
	var chest_fwd := Vector3(cf.x, 0.0, cf.z).normalized() if Vector2(cf.x, cf.z).length() > 0.2 else Vector3(0, 0, 1)
	var hw := []
	var guard := {}
	for sd in ["_r", "_l"]:
		var nm := "right" if sd == "_r" else "left"
		var p: Vector3 = pts["F" if sd == "_r" else "f"]
		var w := height_word(B, sd, p.y)
		f["fist_" + nm] = {"y": snappedf(p.y, 0.001), "word": w}
		guard[nm] = w in ["above his head", "the top of his head", "eye height", "chin height", "shoulder height"] and (p - chest).dot(chest_fwd) >= GUARD_FWD
		var rl := local(B, p, yw) - local(B, B.P["upperarm" + sd], yw)
		var outw := rl.x * (1.0 if sd == "_l" else -1.0)
		var reach := ""   # a guarding hand is in front by definition: its reach is not news
		if guard[nm]:
			pass
		elif outw > REACH and outw > rl.z:
			reach = " out to the side"
		elif rl.z > REACH:
			reach = " reaching forward"
		elif rl.z < -0.15:
			reach = " behind him"
		f["fist_" + nm]["reach"] = reach.strip_edges()
		hw.append("%s fist %s%s" % [nm, ("at " + w) if w != "above his head" else w, reach])
	s += (", ".join(hw)).left(1).to_upper() + (", ".join(hw)).substr(1)
	f["guard"] = guard
	if guard["right"] and guard["left"]:
		s += "; guard up. "
	elif guard["right"] or guard["left"]:
		s += "; guard open on the %s. " % ("left" if guard["right"] else "right")
	else:
		s += "; no guard. "
	# facing and balance
	s += "Hips face %s, %d°. " % [_facing_word(yw), roundi(yw)]
	var mg: float = bal["margin"]
	f["balance_margin_m"] = snappedf(mg, 0.001) if bal["down"].size() > 0 else null
	if bal["down"].is_empty():
		s += "Unsupported: nothing under him."
	elif mg < -Balance.MARGIN_RES:
		var q := Vector2(com.x, com.z)
		var poly: PackedVector2Array = bal["poly"]
		var best := INF
		for i in poly.size():
			var c2 := Geometry2D.get_closest_point_to_segment(Vector2(com.x, com.z), poly[i], poly[(i + 1) % poly.size()])
			if c2.distance_to(Vector2(com.x, com.z)) < best:
				best = c2.distance_to(Vector2(com.x, com.z))
				q = c2
		var dl := local(B, Vector3(com.x, 0, com.z), yw) - local(B, Vector3(q.x, 0, q.y), yw)
		s += "OFF BALANCE: centre of mass %d cm past his feet, to his %s." % [roundi(-mg * 100.0), _dir_word(Vector2(dl.x, dl.z))]
	elif mg < Balance.MARGIN_RES:
		s += "On the edge of balance: centre of mass %d cm inside his feet." % roundi(mg * 100.0)
	else:
		s += "Balanced: centre of mass %d cm inside his feet." % roundi(mg * 100.0)
	return {"words": s, "facts": f, "com": com, "yaw": yw}


## the whole text view of the body as it stands
static func view(B: Body) -> Dictionary:
	var r := read(B)
	var pts := points(B)
	var fr := _grid(B, pts, r["yaw"], "front", r["com"])
	var sd := _grid(B, pts, r["yaw"], "side", r["com"])
	var rows := ["FRONT".rpad(COLS) + "  SIDE"]
	for i in ROWS:
		rows.append((fr["lines"][i] + "  " + sd["lines"][i]).strip_edges(false, true))
	var off: Array = fr["off"] + sd["off"].filter(func(k): return not k in fr["off"])
	var ascii := "\n".join(rows) + "\n" + LEGEND
	if not off.is_empty():
		ascii += "\noff grid (drawn at the edge): " + " ".join(off)
	var text: String = ascii + "\n\n" + String(r["words"])
	return {"text": text, "ascii": ascii, "words": r["words"], "facts": r["facts"], "chars": text.length(),
		"cells": {"front": fr["drawn"], "side": sd["drawn"]}}


## serve's `text_view` on a live poser: {t} or {frame, fps} = that moment of what plays; {card: N} = card N's pose put on
## the body as the card picker does (Scene.put), with no undo step (a read); nothing = the body as it stands. -> {"ok": true, ...view} or {"ok": false, "error"}
static func on_main(m: Node, p: Dictionary) -> Dictionary:
	if p.has("card"):
		var n := int(p["card"])
		if n < 1 or n > m.S.cards.size():
			return {"ok": false, "error": "no card %d (the scene has %d)" % [n, m.S.cards.size()]}
		Scene.put(m.B, Moves._flat(m.S.cards[n - 1]["pose"]))
	elif p.has("t") or p.has("frame"):
		var at: Variant = float(p["frame"]) / float(p.get("fps", m.S.fps)) if p.has("frame") else p["t"]
		if not (at is float or at is int) or m.S.cards.size() < 2:
			return {"ok": false, "error": "text_view {\"t\": seconds} or {\"frame\": n} needs a number and a scene of 2+ cards; {\"card\": N} a card"}
		await m.dummy_settle()
		m.playhead = float(at)
		m._ps().apply(m.B, float(at))
	var v := view(m.B)
	var cells := {}
	for vw in v["cells"]:
		var d := {}
		for k in v["cells"][vw]:
			d[k] = [v["cells"][vw][k].x, v["cells"][vw][k].y]
		cells[vw] = d
	v["cells"] = cells
	v["ok"] = true
	return v
