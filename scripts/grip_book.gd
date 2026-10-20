## grip_book.gd - THE GRIP BOOK (round 49, Nick 10-20: "the weapons at least have its body for limits and parts for grip,
## so we record all the possible grips and stop guessing").
##
## A weapon's BODY: Body.KINDS[kind]["parts"] = [[name, from, to, hold]] along the shaft, metres from the butt (a negative
## number = from the tip), hold = "hold" (a hand may close on it), "blade" (only on purpose: half-swording) or "no"
## (a guard, a head, an edge). A hand's spot on the shaft (its palm, as u from the butt) must be on a holdable part.
##
## A GRIP: one or two hands, each written down as RECORDED, never solved: the wrist's place and turn in the weapon's
## own frame, measured from the palm's spot u on the shaft (the same numbers tools/grip_from_pose.gd wrote for Nick's
## bo pose: data/grips/staff.json "second"). On a round shaft the same hand is still exactly on it when it is slid along
## (u), turned round the shaft (roll) or turned end for end (reverse: the thumb toward the butt), and the left hand is
## the right one's mirror; a grip is a recorded hand + those exact moves, so nothing is fitted to put a hand ON the weapon.
## Only the ARMS are fitted (to reach the hands where the grip puts them), and the miss is reported, never hidden.
##
## The book: data/grips/book/<kind>.json {"weapon", "grips": [{"name", "label", "ref", "main_side"?, "arms"?, "hands":
## [{"role": "main" | "other", "side": "_r" | "_l", "u", "lpos", "lrot", "fingers"}]}]}. "Record this grip" adds the
## pose's grip to it WITH the arms that held it ("arms": the 8 arm joints): applied, the arms are set as recorded and the
## hands land where they were. Without arms (a seed made by moving a recorded hand), the second arm is fitted from the
## pose as it is, and a hand the arm cannot reach is reported (e.g. a katana's from a T-pose: record it once instead).
class_name GripBook
extends RefCounted

const DIR := "res://data/grips/book"
const PALM_OFF_MAX := 0.05
## starts for the second arm's search when it stalls from where it is: [] = as it is, else upper arm (bend forward, side
## raise, roll) + elbow bend, degrees: across the chest low / high, out in front, up by the face
const ARM_STARTS := [[], [40, -60, 0, 70], [60, -50, 20, 90], [50, -40, -20, 60], [30, -70, 30, 100], [80, -20, 0, 50], [100, 0, -30, 80]]   # a palm further than this from the shaft's axis is not holding it (grip_from_pose's bar)


static var dir := DIR   # a test points it at a folder of its own


static func path_of(kind: String) -> String:
	return dir.path_join("%s.json" % kind)


static func grips(kind: String) -> Array:
	var p := path_of(kind)
	if not FileAccess.file_exists(p):
		return []
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	return (d.get("grips", []) as Array) if d is Dictionary else []


static func find(kind: String, name: String) -> Dictionary:
	for g in grips(kind):
		if String(g.get("name", "")) == name:
			return g
	return {}


## the part of the weapon at u (m from the butt): [name, from, to, hold] with from/to resolved; [] past either end
static func part_at(kind: String, L: float, u: float) -> Array:
	for p in Body.KINDS[kind].get("parts", []):
		var a := float(p[1])
		var b := float(p[2])
		a = L + a if a < 0.0 else a
		b = L + b if b < 0.0 else b
		if u >= a - 1e-6 and u <= b + 1e-6:
			return [p[0], a, b, p[3]]
	return []


static func holdable(kind: String, L: float, u: float, blade_ok := false) -> bool:
	var p := part_at(kind, L, u)
	return not p.is_empty() and (p[3] == "hold" or (blade_ok and p[3] == "blade"))


## the nearest u a hand may hold (the holdable parts only)
static func clamp_hold(kind: String, L: float, u: float) -> float:
	if holdable(kind, L, u):
		return u
	var best := u
	var bd := INF
	for p in Body.KINDS[kind].get("parts", []):
		if p[3] != "hold":
			continue
		var a := float(p[1])
		var b := float(p[2])
		a = L + a if a < 0.0 else a
		b = L + b if b < 0.0 else b
		var c := clampf(u, a, b)
		if absf(c - u) < bd:
			bd = absf(c - u)
			best = c
	return best


## a hand's wrist pose in the weapon frame for a grip hand: [lpos (body metres, at its u), lrot]
static func hand_xf(B: Body, hd: Dictionary, h: String) -> Array:
	var lp := Body._v(hd["lpos"]) * B.hand_s(h) + Vector3(0, float(hd["u"]), 0)
	var lr: Array = hd["lrot"]
	return [lp, Quaternion(lr[0], lr[1], lr[2], lr[3]).normalized()]


## the body's hand for a grip hand: the weapon's main hand is the grip's main ("main" role), the other the other
static func _hand_for(B: Body, hd: Dictionary, main_h: String) -> String:
	if String(hd.get("role", "main")) == "main":
		return main_h
	return "hand_l" if main_h == "hand_r" else "hand_r"


## a recorded hand put on the other side: the mirror (x flipped, rotation (x, -y, -z, w): Body.weapon_to_hand's rule)
static func mirrored(hd: Dictionary, side: String) -> Dictionary:
	if String(hd.get("side", "_r")) == side:
		return hd
	var o := hd.duplicate(true)
	var p: Array = o["lpos"]
	o["lpos"] = [-float(p[0]), p[1], p[2]]
	var q: Array = o["lrot"]
	o["lrot"] = [q[0], -float(q[1]), -float(q[2]), q[3]]
	var f := {}
	for j in (o.get("fingers", {}) as Dictionary):
		var a: Array = o["fingers"][j]
		f[String(j).left(String(j).length() - 2) + side] = [a[0], a[1], -float(a[2])]
	o["fingers"] = f
	o["side"] = side
	return o


## put the grip on: the weapon re-seated in the main hand exactly as recorded (the hand stays, the weapon moves), the
## other hand (if any) set as the second grip and its arm fitted. Returns {"ok", "miss" (m, the second wrist), "why"}
static func apply(B: Body, g: Dictionary) -> Dictionary:
	if not B.wep_on or B.wep_hand == "":
		return {"ok": false, "miss": 0.0, "why": "put the weapon in a hand first"}
	# "main_side": the hand the weapon is locked to (a katana's base hand is the LEFT one, at the pommel: the right goes
	# on above it); otherwise the hand holding it now
	var main_h := B.wep_hand if not g.has("main_side") else "hand" + String(g["main_side"])
	var main_sd := main_h.right(2)
	# the ARMS as recorded with the grip (when it has them): the hands go where the recording had them, no search
	var used_arms := false
	if g.has("arms"):
		for j in (g["arms"] as Dictionary):
			var a3: Array = g["arms"][j]
			B.ang[j] = B.clamp_ang(j, Vector3(a3[0], a3[1], a3[2]))
		B.fk()
		used_arms = true
	var oth_h := "hand_l" if main_h == "hand_r" else "hand_r"
	var hands: Array = g.get("hands", [])
	var mh := {}
	var oh := {}
	for hd in hands:
		if String(hd.get("role", "main")) == "main":
			mh = mirrored(hd, main_sd)
		else:
			oh = mirrored(hd, oth_h.right(2))
	if mh.is_empty():
		return {"ok": false, "miss": 0.0, "why": "the grip has no main hand"}
	for hd in [mh, oh]:
		if not hd.is_empty() and not holdable(B.wep_kind, B.wep_len, float(hd["u"]), true):
			return {"ok": false, "miss": 0.0, "why": "the grip puts a hand on the %s at %.0f cm: not a part a hand holds" % [part_at(B.wep_kind, B.wep_len, float(hd["u"])).get(0) if not part_at(B.wep_kind, B.wep_len, float(hd["u"])).is_empty() else "end", float(hd["u"]) * 100.0]}
	# the main hand: weapon frame W with  wrist = W.pos + W.rot * lp,  hand turn = W.rot * lr  ->  W from the hand now
	var xf := hand_xf(B, mh, main_h)
	var wr: Quaternion = ((B.G[main_h] as Quaternion) * (xf[1] as Quaternion).inverse()).normalized()
	var wp: Vector3 = (B.P[main_h] as Vector3) - wr * (xf[0] as Vector3)
	B.unlock_weapon()
	B.wep_pos = wp
	B.wep_rot = wr
	B.lock_weapon(main_h)
	for j in (mh.get("fingers", {}) as Dictionary):
		var a: Array = mh["fingers"][j]
		B.ang[j] = B.clamp_ang(j, Vector3(a[0], a[1], a[2]))
	B.fk()
	if oh.is_empty():
		B.grip = false
		B.grip2 = {}
		return {"ok": true, "miss": 0.0, "why": ""}
	B.grip2 = {"hand": oth_h, "u": float(oh["u"]), "lpos": oh["lpos"], "lrot": oh["lrot"], "fingers": oh.get("fingers", {})}
	B.grip = true
	B.grip_u = float(oh["u"])
	var keep := B.fast
	B.fast = false
	B.apply_grip()
	var m := B.grip_miss()
	if m > 0.03:
		# the arm's search starts where the arm is and can stall far off (from a wide grip to a close one: 18-39 cm):
		# the wrist first brought to its spot by the elbow + shoulder alone, then the whole-arm fit again from there
		var best := B.state()
		var xo := hand_xf(B, oh, oth_h)
		var wx := B.wep_xform()
		var tgt: Vector3 = (wx[0] as Vector3) + (wx[1] as Quaternion) * (xo[0] as Vector3)
		var sd := oth_h.right(2)
		for sa in ARM_STARTS:
			B.set_state(best if sa.is_empty() else B.state())
			if not sa.is_empty():
				B.ang["upperarm" + sd] = B.clamp_ang("upperarm" + sd, Vector3(sa[0], sa[1], sa[2]))
				B.ang["lowerarm" + sd] = B.clamp_ang("lowerarm" + sd, Vector3(sa[3], 0, 0))
				B.fk()
			B.reach(oth_h, tgt)
			B.apply_grip()
			if B.grip_miss() < m:
				m = B.grip_miss()
				best = B.state()
			if m <= 0.01:
				break
		B.set_state(best)
	B.fast = keep
	return {"ok": true, "miss": m, "arms": used_arms, "why": "" if m <= 0.03 else "the %s can't reach its place on the shaft from this pose (%.0f cm short): bring the weapon in front of the body, then apply the grip again" % [oth_h.replace("hand_", "").replace("l", "left hand").replace("r", "right hand"), m * 100.0]}


## the grip in the pose now, as a book entry (every hand ON the weapon: palm within PALM_OFF_MAX of the axis, on a part a
## hand may hold). Returns the entry, or {"why": ...} when a hand is not on it
static func capture(B: Body, name: String, label := "", ref := "") -> Dictionary:
	if not B.wep_on or B.wep_hand == "":
		return {"why": "put the weapon in a hand first"}
	var x := B.wep_xform()
	var k: Vector3 = x[0]
	var q: Quaternion = x[1]
	var hands := []
	for h in [B.wep_hand, "hand_l" if B.wep_hand == "hand_r" else "hand_r"]:
		var pl := q.inverse() * (B.palm_point(h) - k)
		var off := Vector2(pl.x, pl.z).length()
		if off > PALM_OFF_MAX or pl.y < -0.02 or pl.y > B.wep_len + 0.02:
			if h == B.wep_hand:
				return {"why": "the main hand's palm is %.0f cm off the shaft" % (off * 100.0)}
			continue   # the other hand is not on it: a one-hand grip
		if not holdable(B.wep_kind, B.wep_len, pl.y, true):
			return {"why": "the %s holds the %s (at %.0f cm): not a part a hand holds" % [h, part_at(B.wep_kind, B.wep_len, pl.y)[0] if not part_at(B.wep_kind, B.wep_len, pl.y).is_empty() else "end", pl.y * 100.0]}
		var wl := q.inverse() * ((B.P[h] as Vector3) - k)
		var fing := {}
		for j in Body.FINGERS:
			if String(j).ends_with(h.right(2)):
				var v: Vector3 = B.ang[j]
				fing[j] = [snappedf(v.x, 0.1), snappedf(v.y, 0.1), snappedf(v.z, 0.1)]
		hands.append({"role": "main" if h == B.wep_hand else "other", "side": h.right(2), "u": snappedf(pl.y, 0.001),
			"lpos": Body._p((wl - Vector3(0, pl.y, 0)) / B.hand_s(h)), "lrot": Body._q((q.inverse() * (B.G[h] as Quaternion)).normalized()),
			"fingers": fing})
	var arms := {}
	if hands.size() > 1:   # a two-hand grip keeps the arms that held it: applied, they put both hands back exactly
		for sd in ["_l", "_r"]:
			for j in ["clavicle", "upperarm", "lowerarm", "hand"]:
				var v: Vector3 = B.ang[j + sd]
				arms[j + sd] = [snappedf(v.x, 0.1), snappedf(v.y, 0.1), snappedf(v.z, 0.1)]
	var e := {"name": name, "label": label if label != "" else name.replace("_", " "), "ref": ref, "hands": hands}
	if not arms.is_empty():
		e["arms"] = arms
	if B.wep_hand != "hand_r":
		e["main_side"] = B.wep_hand.right(2)
	return e


## add (or replace by name) an entry in the kind's book; returns the file written
static func record(kind: String, entry: Dictionary) -> String:
	var p := path_of(kind)
	var d := {"weapon": kind, "grips": []}
	if FileAccess.file_exists(p):
		var r = JSON.parse_string(FileAccess.get_file_as_string(p))
		if r is Dictionary:
			d = r
	var gs: Array = d.get("grips", [])
	var out := []
	for g in gs:
		if String(g.get("name", "")) != String(entry["name"]):
			out.append(g)
	out.append(entry)
	d["grips"] = out
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, " "))
	f.close()
	return p


## the moves that keep a recorded hand exactly on a round shaft: slide to u, roll round the shaft (deg), end for end
static func moved(hd: Dictionary, u: float, roll_deg := 0.0, reverse := false) -> Dictionary:
	var o := hd.duplicate(true)
	var lp := Body._v(o["lpos"])
	var lr: Array = o["lrot"]
	var q := Quaternion(lr[0], lr[1], lr[2], lr[3])
	if reverse:
		var rx := Quaternion(Vector3.RIGHT, PI)
		lp = rx * lp
		q = rx * q
	if roll_deg != 0.0:
		var ry := Quaternion(Vector3.UP, deg_to_rad(roll_deg))
		lp = ry * lp
		q = ry * q
	o["lpos"] = Body._p(lp)
	o["lrot"] = Body._q(q.normalized())
	o["u"] = snappedf(u, 0.001)
	return o
