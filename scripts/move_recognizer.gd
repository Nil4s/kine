## move_recognizer.gd - THE MOVE RECOGNIZER (docs/INNOVATIONS.md N016): "is this a hook?" Kine names the strike a clip (or a
## card, or a t0-t1 span) shows, FROM THE BODY, and says how far it is from the textbook form:
##     "a hook (left hand, lead) ... form: the elbow drops 25 deg below shoulder height; a textbook hook keeps it level"
## WHY: a blind agent that asked for "a hook" cannot see whether it got one. The keys and card names say what was MEANT;
## this reads what the played body DOES (the same frames `events` reads: EventQuery.sample, Scene.apply at 60 fps).
##
## WHAT IS READ (one move per call: the fastest striking point in the window):
##   striking point  the wrists and elbows, the balls of the feet and the knees, and the weapon tip; the one
##                   whose speed RELATIVE TO THE PELVIS peaks highest (a step or a walk's carry does not count as a strike).
##                   A foot / knee counts only if its ball rises LEG_RISE in the window (else it is a step).
##                   Slower than Rulebook.STRIKE_MIN (3 m/s, the Check's own "no strike in it") = not a strike.
##   the delivery    from the speed's last low point before the peak to its first low point after it (the arrival: on
##                   key-framed cards, the strike card itself). Its posture is read at the arrival ("contact").
##   path            over the strike's core (the frames above half the peak, Rulebook.strikes's span): chord, length, straightness (chord / length), rise (the chord's up share), the plane of the arc (the
##                   normal of the widest triangle the path makes), each said in the BODY FRAME (N007, body_frame.gd: left
##                   = hip line + shoulder line laid flat, forward = left x up) taken at the delivery's start
##   limb            elbow / knee inner angle at contact, the arm's extension gain, the upper arm's elevation (elbow above /
##                   below shoulder height), the knee's lift and the leg's extension direction in the PELVIS's frame at contact
##   chain           the I8 power chain read from points (force_view.gd reads it from joint frames): the peak turning speed
##                   of hips (hip line yaw) -> trunk (shoulder line yaw) -> upper segment -> lower segment within the 0.8 s up
##                   to the peak (ForceView.WINDOW); in order = proximal to distal within 1 frame (Putnam 1993, J Biomech 26
##                   Suppl 1:125, as force_view.gd cites)
##   speed           the striking point's peak world speed, beside the cited human number (fist 11.95 m/s, Stanley et al.
##                   2018; foot 14.66 m/s, Gavagan & Sayers 2017; both in docs/physics_constants_i47.md)
##   feet            which foot is planted through the delivery (EventQuery.foot_down, the footprint test of balance.gd)
##   lead / rear     the foot further forward in the body frame at the start is the lead (8 cm or more apart; else square)
##
## THE CLASSES and what makes each one (SHAPE: the class's criteria; distance = the summed violation, each in units of its
## scale; ALL the ranges and scales below are HEURISTIC, set from the textbook descriptions in FORM before any clip was read):
##   arm      jab / cross   a straight path (straightness >= 0.8) that EXTENDS the arm, not rising; lead hand = jab, rear = cross
##            hook          a curved path in a level plane, the arm keeping its bend (60-130 deg), moving toward the midline
##            uppercut      a rising path (rise >= 0.5), the arm bent
##            elbow         the forearm folded (elbow inner angle <= 60 deg) and the elbow moving as fast as the wrist
##   leg      front kick    the knee straightens to >= 140 deg along a straight path, extending to the pelvis's FRONT
##            side kick     the same, extending to the pelvis's SIDE (the kicking side)
##            roundhouse    the hips turn 60+ deg through the kick and the foot sweeps a level arc toward the midline
##            knee          the knee stays bent (<= 90 deg) and rises to within 15 cm of hip height
##   weapon   thrust        the tip moves along the weapon (|axis . velocity| >= 0.6 at the peak, text_blocking.gd's own test)
##            overhead weapon strike   a vertical swing plane facing forward, the tip moving down at the peak
##            horizontal weapon swing  a level swing plane
## The best class of the striking limb's group wins; a best distance over UNKNOWN_AT is "unknown", with the nearest class
## and its distance. FORM (how far from the textbook one) is separate from SHAPE: a hook with a dropped elbow is still a
## hook, and its form list says "the elbow drops 25 deg below shoulder height".
##
## Sources opened for FORM (10-23): Peloton, "How to throw a hook" (https://www.onepeloton.com/blog/hook-punch): "With your
## front arm bent at about 90 degrees ... your fist and elbow level with your shoulder", "rotate your hips into the hook";
## Boxing News 2015, "The science behind the hook" (https://boxingnewsonline.net/features/the-science-behind-the-hook/):
## "Jab and cross punches are thrown straight utilising elbow extension, while the hook sweeps round and up", "connects
## before full elbow extension"; Gavagan & Sayers 2017, PLoS ONE 12(8):e0182645 (PMC5571909), roundhouse: the pelvis
## "rotated through approximately 130 deg" (citing Kim et al.), "maximum knee extension velocity occurred before contact";
## Wasik 2011, J Hum Kinet (PMC3588635), side kick: the foot moves "in the direction of the intended impact", "the knee
## and hip joints are extended". A number from none of these is labelled HEURISTIC in its entry.
class_name MoveRecognizer
extends RefCounted

const FPS := 60.0
const UNKNOWN_AT := 1.0     # HEURISTIC: a best shape distance above this (one whole scale of violation) = "unknown"
const LEAD_MIN := 0.08      # m, HEURISTIC: feet closer than this along the body's front = a square stance (no lead)
const LEG_RISE := 0.25      # m, HEURISTIC: a foot that never rises this far in the window is stepping, not kicking (a walk's
                            # toe clears the floor by centimetres; the lowest kick here, a knee, lifts the ball ~0.5 m)
const ARMED_SHARE := 0.8    # HEURISTIC: an armed fighter strikes with the weapon when its tip peaks at 80 %+ of the fastest point
const FLAT_AREA := 0.04     # HEURISTIC: a path whose widest triangle is under 4 % of chord^2 has no plane (it is straight)
const WINDOW := 0.8         # s before the peak in which the chain's peaks are looked for (ForceView.WINDOW)
const TIE := 1              # frames: chain peaks this close count as in order (ForceView.TIE, at 60 fps here)
const FIST_CITED := 11.95   # m/s, Stanley et al. 2018 (Rulebook.FIST_WARN; docs/physics_constants.md)
const FOOT_CITED := 14.66   # m/s, Gavagan & Sayers 2017 Table 2, taekwondo roundhouse (docs/physics_constants_i47.md)
const GROUPS := {"arm": ["jab", "cross", "hook", "uppercut", "elbow"], "leg": ["front kick", "side kick", "roundhouse", "knee"],
	"weapon": ["thrust", "overhead weapon strike", "horizontal weapon swing"]}
const CLASSES := ["jab", "cross", "hook", "uppercut", "elbow", "front kick", "side kick", "roundhouse", "knee",
	"overhead weapon strike", "horizontal weapon swing", "thrust"]
const SRC_HOOK := "Peloton, How to throw a hook (onepeloton.com/blog/hook-punch)"
const SRC_STRAIGHT := "Boxing News 2015, The science behind the hook (boxingnewsonline.net)"
const SRC_ROUND := "Gavagan & Sayers 2017, PLoS ONE 12:e0182645 (PMC5571909)"
const SRC_SIDE := "Wasik 2011, J Hum Kinet (PMC3588635)"
const SRC_CHAIN := "Putnam 1993, J Biomech 26 Suppl 1:125"

static var _ix := {}


static func _i(nm: String) -> int:
	if _ix.is_empty():
		var pn := EventQuery.point_names()
		for k in pn.size():
			_ix[pn[k]] = k
	return int(_ix[nm])


static func _p(clip: Dictionary, me: int, f: int, nm: String) -> Vector3:
	var row: PackedVector3Array = clip["pts"][me][clampi(f, 0, int(clip["n"]) - 1)]
	return row[_i(nm)]


static func _v(clip: Dictionary, me: int, f: int, nm: String) -> Vector3:
	var n: int = clip["n"]
	var a := maxi(f - 1, 0)
	var b := mini(f + 1, n - 1)
	if b == a:
		return Vector3.ZERO
	return (_p(clip, me, b, nm) - _p(clip, me, a, nm)) * float(clip["fps"]) / float(b - a)


static func _angle(u: Vector3, v: Vector3) -> float:
	if u.length() < 1e-9 or v.length() < 1e-9:
		return 0.0
	return rad_to_deg(u.angle_to(v))


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## the body frame at frame f (body_frame.gd's rule on the sampled points): [left, fwd]
static func frame_at(clip: Dictionary, me: int, f: int, hips_only := false) -> Array:
	var hip := _p(clip, me, f, "thigh_l") - _p(clip, me, f, "thigh_r")
	var left := hip.normalized()
	if not hips_only:
		left += (_p(clip, me, f, "upperarm_l") - _p(clip, me, f, "upperarm_r")).normalized()
	left = _flat(left)
	if left.length() < 1e-4:
		left = Vector3(1, 0, 0)
	left = left.normalized()
	return [left, left.cross(Vector3.UP).normalized()]


static func _yaw(v: Vector3) -> float:
	return rad_to_deg(atan2(v.x, v.z))


## a line's yaw over frames a..b, unwrapped: the total turn (deg, signed: + = turns to his left as body.gd's twist)
static func _turn(clip: Dictionary, me: int, a: int, b: int, pl: String, pr: String) -> float:
	var tot := 0.0
	var prev := _yaw(_flat(_p(clip, me, a, pl) - _p(clip, me, a, pr)))
	for f in range(a + 1, b + 1):
		var y := _yaw(_flat(_p(clip, me, f, pl) - _p(clip, me, f, pr)))
		tot += wrapf(y - prev, -180.0, 180.0)
		prev = y
	return tot


## the speed of a point relative to the pelvis, per frame
static func rel_speed(clip: Dictionary, me: int, nm: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for f in int(clip["n"]):
		out.append((_v(clip, me, f, nm) - _v(clip, me, f, "pelvis")).length())
	return out


## the turning speed (deg/s) of the direction from point a to point b, per frame; flat = yaw only
static func _omega(clip: Dictionary, me: int, pa: String, pb: String, flat: bool) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n: int = clip["n"]
	for f in n:
		var f0 := maxi(f - 1, 0)
		var f1 := mini(f + 1, n - 1)
		var u := _p(clip, me, f0, pb) - _p(clip, me, f0, pa)
		var v := _p(clip, me, f1, pb) - _p(clip, me, f1, pa)
		if flat:
			u = _flat(u)
			v = _flat(v)
		out.append(_angle(u, v) * float(clip["fps"]) / maxf(float(f1 - f0), 1.0))
	return out


## one criterion: [name, value, lo, hi, scale] -> its violation in units of its scale
static func _viol(c: Array) -> float:
	var v: float = c[1]
	return (maxf(0.0, float(c[2]) - v) + maxf(0.0, v - float(c[3]))) / float(c[4])


## the shape criteria of every class of a group, from the features
static func criteria(group: String, ft: Dictionary) -> Dictionary:
	var out := {}
	match group:
		"arm":
			var straight := [["straightness", ft["straightness"], 0.8, 1.0, 0.15], ["extension (gain / chord)", ft["extend"], 0.5, 2.0, 0.3],
				["rise (up share of the chord)", ft["rise"], -0.4, 0.4, 0.3], ["elbow inner angle at contact (deg)", ft["elbow"], 110.0, 180.0, 30.0]]
			out["jab"] = straight + [["lead hand (1 lead, 0.5 square, 0 rear)", ft["lead"], 1.0, 1.0, 1.0]]
			out["cross"] = straight + [["lead hand (1 lead, 0.5 square, 0 rear)", ft["lead"], 0.0, 0.0, 1.0]]
			out["hook"] = [["straightness", ft["straightness"], 0.0, 0.85, 0.15], ["level plane (|normal . up|)", ft["plane_up"], 0.6, 1.0, 0.3],
				["rise (up share of the chord)", ft["rise"], -0.4, 0.4, 0.25],
				["extension (gain / chord)", ft["extend"], -2.0, 0.4, 0.3], ["elbow inner angle at contact (deg)", ft["elbow"], 60.0, 130.0, 25.0],
				["toward the midline (share of the chord)", ft["inward"], 0.3, 1.0, 0.3]]
			out["uppercut"] = [["rise (up share of the chord)", ft["rise"], 0.5, 1.0, 0.25], ["extension (gain / chord)", ft["extend"], -2.0, 0.6, 0.3],
				["elbow inner angle at contact (deg)", ft["elbow"], 60.0, 130.0, 25.0]]
			out["elbow"] = [["elbow inner angle at contact (deg)", ft["elbow"], 0.0, 60.0, 20.0], ["elbow speed / wrist speed at the peak", ft["elbow_lead"], 0.6, 3.0, 0.2]]
		"leg":
			var ext := [["knee inner angle at contact (deg)", ft["knee"], 140.0, 180.0, 30.0], ["straightness", ft["straightness"], 0.7, 1.0, 0.15]]
			out["front kick"] = ext + [["extension to the pelvis's front (share)", ft["ext_front"], 0.6, 1.0, 0.3], ["hip turn (deg)", absf(ft["hip_turn"]), 0.0, 60.0, 30.0]]
			out["side kick"] = ext + [["extension to the pelvis's kicking side (share)", ft["ext_side"], 0.6, 1.0, 0.3], ["hip turn (deg)", absf(ft["hip_turn"]), 0.0, 45.0, 30.0]]
			out["roundhouse"] = [["hip turn (deg)", absf(ft["hip_turn"]), 60.0, 360.0, 30.0], ["level plane (|normal . up|)", ft["plane_up"], 0.4, 1.0, 0.3],
				["toward the midline (share of the chord)", ft["inward"], 0.2, 1.0, 0.3]]
			out["knee"] = [["knee inner angle at contact (deg)", ft["knee"], 0.0, 90.0, 30.0], ["knee height - hip height (m)", ft["knee_lift"], -0.15, 1.0, 0.15]]
		"weapon":
			out["thrust"] = [["|weapon axis . tip velocity| at the peak", ft["along"], 0.6, 1.0, 0.2], ["straightness", ft["straightness"], 0.8, 1.0, 0.15]]
			out["overhead weapon strike"] = [["|weapon axis . tip velocity| at the peak", ft["along"], 0.0, 0.6, 0.2],
				["vertical plane facing forward (|normal . left|)", ft["plane_left"], 0.6, 1.0, 0.3], ["tip moving down at the peak (-v.up)", ft["descend"], 0.3, 1.0, 0.3]]
			out["horizontal weapon swing"] = [["|weapon axis . tip velocity| at the peak", ft["along"], 0.0, 0.6, 0.2], ["level plane (|normal . up|)", ft["plane_up"], 0.6, 1.0, 0.3]]
	return out


## one form entry: the textbook range of a measured thing, how far off, the words
static func _form(what: String, v: float, lo: float, hi: float, unit: String, trust: String, src: String, off_words: String, ok_words: String) -> Dictionary:
	var off := 0.0
	if v < lo:
		off = v - lo
	elif v > hi:
		off = v - hi
	return {"what": what, "value": snappedf(v, 0.1), "textbook": [lo, hi], "unit": unit, "off": snappedf(off, 0.1), "ok": off == 0.0,
		"trust": trust, "source": src, "text": ok_words if off == 0.0 else off_words}


## the form list of a class: how this move differs from the textbook one
static func form_of(cls: String, ft: Dictionary) -> Array:
	var out := []
	var H := "HEURISTIC"
	match cls:
		"hook":
			var e: float = ft["elbow_elev"]
			out.append(_form("elbow height (upper arm elevation, deg; + = above the shoulder)", e, -10.0, 10.0, "deg", "SOURCED (tolerance HEURISTIC)", SRC_HOOK,
				"the elbow %s %.0f deg %s shoulder height; a textbook hook keeps it level with the shoulder" % ["drops" if e < 0.0 else "rises", absf(e), "below" if e < 0.0 else "above"],
				"the elbow is level with the shoulder (%.0f deg), as a textbook hook" % e))
			out.append(_form("elbow inner angle at contact", ft["elbow"], 70.0, 110.0, "deg", "SOURCED (tolerance HEURISTIC)", SRC_HOOK,
				"the elbow is at %.0f deg; a textbook hook is bent about 90" % ft["elbow"], "the arm is bent about 90 deg (%.0f)" % ft["elbow"]))
			out.append(_form("hips turned into the punch", ft["hip_into"], 10.0, 360.0, "deg", "SOURCED (the 10 deg floor HEURISTIC)", SRC_HOOK,
				"the hips turn only %.0f deg into it; a textbook hook rotates the hips into the punch" % ft["hip_into"], "the hips turn %.0f deg into it" % ft["hip_into"]))
		"jab", "cross":
			out.append(_form("elbow inner angle at contact", ft["elbow"], 150.0, 180.0, "deg", "SOURCED (the 150 deg floor HEURISTIC)", SRC_STRAIGHT,
				"the arm ends bent at %.0f deg; a straight punch is thrown with elbow extension" % ft["elbow"], "the arm extends (%.0f deg)" % ft["elbow"]))
			out.append(_form("fist height - shoulder height at contact", ft["fist_vs_shoulder"] * 100.0, -15.0, 15.0, "cm", H, "",
				"the fist lands %.0f cm %s shoulder height" % [absf(ft["fist_vs_shoulder"]) * 100.0, "below" if ft["fist_vs_shoulder"] < 0.0 else "above"], "the fist lands at shoulder height"))
			out.append(_form("other hand's distance from the chin at contact", ft["guard"] * 100.0, 0.0, 20.0, "cm", H, "",
				"the other hand is %.0f cm from the chin: the guard drops" % (ft["guard"] * 100.0), "the other hand stays at the chin"))
			if cls == "cross":
				out.append(_form("hips turned into the punch", ft["hip_into"], 15.0, 360.0, "deg", H, "",
					"the hips turn only %.0f deg into the cross" % ft["hip_into"], "the hips turn %.0f deg into it" % ft["hip_into"]))
		"uppercut":
			out.append(_form("elbow inner angle at contact", ft["elbow"], 65.0, 115.0, "deg", H, "",
				"the elbow is at %.0f deg; an uppercut keeps the arm bent about 90" % ft["elbow"], "the arm stays bent (%.0f deg)" % ft["elbow"]))
			out.append(_form("fist rise through the delivery", ft["dU"] * 100.0, 20.0, 200.0, "cm", H, "",
				"the fist rises only %.0f cm" % (ft["dU"] * 100.0), "the fist rises %.0f cm" % (ft["dU"] * 100.0)))
		"elbow":
			out.append(_form("elbow height - shoulder height (deg of the upper arm)", ft["elbow_elev"], -15.0, 15.0, "deg", H, "",
				"the elbow is %.0f deg %s shoulder height" % [absf(ft["elbow_elev"]), "below" if ft["elbow_elev"] < 0.0 else "above"], "the elbow strikes at shoulder height"))
		"front kick":
			out.append(_form("knee chamber (highest knee - hip height before the peak)", ft["chamber"] * 100.0, -15.0, 100.0, "cm", H, "",
				"the knee only reaches %.0f cm under hip height before the kick: no chamber" % (-ft["chamber"] * 100.0), "the knee is chambered first"))
			out.append(_form("knee inner angle at contact", ft["knee"], 150.0, 180.0, "deg", H, "",
				"the leg ends bent at %.0f deg" % ft["knee"], "the leg extends (%.0f deg)" % ft["knee"]))
		"side kick":
			out.append(_form("knee inner angle at contact", ft["knee"], 150.0, 180.0, "deg", "SOURCED (the 150 deg floor HEURISTIC)", SRC_SIDE,
				"the leg ends bent at %.0f deg; the side kick extends knee and hip" % ft["knee"], "the leg extends (%.0f deg)" % ft["knee"]))
			out.append(_form("foot height - hip height at contact", ft["foot_vs_hip"] * 100.0, -25.0, 50.0, "cm", H, "",
				"the foot lands %.0f cm under hip height" % (-ft["foot_vs_hip"] * 100.0), "the foot lands near hip height"))
		"roundhouse":
			out.append(_form("hip turn through the kick", absf(ft["hip_turn"]), 90.0, 360.0, "deg", "SOURCED (~130 deg; the 90 deg floor HEURISTIC)", SRC_ROUND,
				"the hips turn %.0f deg; the pelvis of a textbook roundhouse rotates about 130" % absf(ft["hip_turn"]), "the hips turn over (%.0f deg)" % absf(ft["hip_turn"])))
			out.append(_form("knee extension speed peaks before contact (frames before)", ft["knee_ext_lead"], 1.0, 999.0, "frames", "SOURCED", SRC_ROUND,
				"the knee's fastest straightening comes %d frames after contact" % int(-ft["knee_ext_lead"]), "the knee snaps out before contact"))
		"knee":
			out.append(_form("knee height - hip height at contact", ft["knee_lift"] * 100.0, 0.0, 100.0, "cm", H, "",
				"the knee stays %.0f cm under hip height" % (-ft["knee_lift"] * 100.0), "the knee drives up to hip height"))
		"thrust":
			out.append(_form("tip path straightness", ft["straightness"], 0.9, 1.0, "", H, "",
				"the tip wanders (straightness %.0f %%)" % (ft["straightness"] * 100.0), "the tip travels straight"))
		"overhead weapon strike":
			out.append(_form("swing plane facing forward (|normal . left|)", ft["plane_left"], 0.8, 1.0, "", H, "",
				"the swing plane leans %.0f deg off vertical-forward" % rad_to_deg(acos(clampf(ft["plane_left"], 0.0, 1.0))), "the swing plane is vertical"))
		"horizontal weapon swing":
			out.append(_form("swing plane level (|normal . up|)", ft["plane_up"], 0.8, 1.0, "", H, "",
				"the swing plane tilts %.0f deg off level" % rad_to_deg(acos(clampf(ft["plane_up"], 0.0, 1.0))), "the swing plane is level"))
	return out


## the move in frames f0..f1 of fighter `me` of a sampled clip (EventQuery.sample) -> the answer
static func analyze(clip: Dictionary, me: int, f0: int, f1: int) -> Dictionary:
	var n: int = clip["n"]
	f0 = clampi(f0, 0, n - 1)
	f1 = clampi(f1, 0, n - 1)
	var fps: float = clip["fps"]
	var out := {"ok": true, "fighter": me + 1, "window_s": [snappedf(f0 / fps, 0.001), snappedf(f1 / fps, 0.001)], "classes": CLASSES,
		"trust": "HEURISTIC (the class ranges); the form entries carry their own"}
	if f1 - f0 < 4:
		out.merge({"strike": false, "class": "unknown", "text": "unknown: the window is under 5 frames"})
		return out
	# the striking point
	var cands := ["hand_l", "hand_r", "lowerarm_l", "lowerarm_r", "ball_l", "ball_r", "calf_l", "calf_r"]
	var tip_ok := true
	for f in range(f0, f1 + 1):
		if is_nan(_p(clip, me, f, "weapon_tip").x):
			tip_ok = false
			break
	if tip_ok:
		cands.append("weapon_tip")
	var eff := ""
	var sp := PackedFloat32Array()
	var pk := f0
	var top := -1.0
	for c in cands:
		if c.begins_with("ball") or c.begins_with("calf"):
			var lo := INF
			var hi := -INF
			for f in range(f0, f1 + 1):
				var y := _p(clip, me, f, "ball" + c.right(2)).y
				lo = minf(lo, y)
				hi = maxf(hi, y)
			if hi - lo < LEG_RISE:
				continue   # a step: this foot is not a striking point
		var s := rel_speed(clip, me, c)
		for f in range(f0, f1 + 1):
			if s[f] > top:
				top = s[f]
				pk = f
				eff = c
				sp = s
	# armed: the weapon is the striking point when its tip is nearly as fast as the fastest point (a dagger's tip moves with
	# the hand, and the free hand can out-run it); a kick with a weapon in hand leaves the tip far behind the foot
	if tip_ok and eff != "weapon_tip":
		var ts := rel_speed(clip, me, "weapon_tip")
		var bt := f0
		for f in range(f0, f1 + 1):
			if ts[f] > ts[bt]:
				bt = f
		if ts[bt] >= ARMED_SHARE * top:
			eff = "weapon_tip"
			sp = ts
			pk = bt
			top = ts[bt]
	# the feet: alternating single support over the window = a gait
	var dn: PackedByteArray = clip["down"][me]
	var switches := 0
	var last := 0
	for f in range(f0, f1 + 1):
		var d := int(dn[f])
		if d == 1 or d == 2:
			if last != 0 and d != last:
				switches += 1
			last = d
	out["feet_alternate"] = switches
	if top < Rulebook.STRIKE_MIN:
		out.merge({"strike": false, "class": "unknown", "peak_rel_speed": snappedf(top, 0.01),
			"text": "unknown / not a strike: nothing moves faster than %.1f m/s against the pelvis (fastest: %s at %.1f m/s)%s" % [
				Rulebook.STRIKE_MIN, eff, top, ("; the feet alternate %d times: a walk or run" % switches) if switches >= 2 else ""]})
		return out
	# the delivery: from the last low point before the peak to the first after it
	var a := pk
	while a > f0 and (sp[a - 1] < sp[a] or sp[a - 1] > 0.5 * top):
		a -= 1
	var c := pk
	while c < f1 and (sp[c + 1] < sp[c] or sp[c + 1] > 0.5 * top):
		c += 1
	var group := "weapon" if eff == "weapon_tip" else ("arm" if eff.begins_with("hand") or eff.begins_with("lowerarm") else "leg")
	var sd := "_l"
	if group == "weapon":
		var kn := _p(clip, me, pk, "weapon_knob")
		sd = "_l" if kn.distance_to(_p(clip, me, pk, "hand_l")) < kn.distance_to(_p(clip, me, pk, "hand_r")) else "_r"
	else:
		sd = eff.right(2)
	var side_w := "left" if sd == "_l" else "right"
	var fr := frame_at(clip, me, a)
	var L: Vector3 = fr[0]
	var F: Vector3 = fr[1]
	# the path: over the strike's core, the run of frames above half the peak (Rulebook.strikes's own span of a strike); the
	# wind-up's turn-around and the arrival's slow end are left out of its shape (the posture is still read at the arrival)
	var ha := pk
	while ha > a and sp[ha - 1] > 0.5 * top:
		ha -= 1
	var hb := pk
	while hb < c and sp[hb + 1] > 0.5 * top:
		hb += 1
	var pa := _p(clip, me, ha, eff)
	var pc := _p(clip, me, hb, eff)
	var d := pc - pa
	var length := 0.0
	var wide := 0.0
	var nrm := Vector3.ZERO
	for f in range(ha + 1, hb + 1):
		length += (_p(clip, me, f, eff) - _p(clip, me, f - 1, eff)).length()
		var q := _p(clip, me, f, eff)
		var cr := (q - pa).cross(pc - q)
		if cr.length() > wide:
			wide = cr.length()
			nrm = cr
	var chord := d.length()
	var ft := {}
	ft["straightness"] = chord / length if length > 1e-6 else 1.0
	ft["rise"] = d.y / chord if chord > 1e-6 else 0.0
	ft["dU"] = d.y
	var planar := chord > 1e-6 and wide / (chord * chord) >= FLAT_AREA
	var nn := nrm.normalized() if planar else Vector3.ZERO
	ft["plane_up"] = absf(nn.y)
	ft["plane_left"] = absf(nn.dot(L))
	var sgn := 1.0 if sd == "_r" else -1.0   # toward the midline: a right limb moves to his left (+L)
	ft["inward"] = sgn * d.dot(L) / chord if chord > 1e-6 else 0.0
	ft["hip_turn"] = _turn(clip, me, a, c, "thigh_l", "thigh_r")
	ft["hip_into"] = sgn * ft["hip_turn"]   # a right-hand punch turns the hips to his left (+ yaw)
	# lead / rear: the foot further forward in the last stance (both feet down) at or before the delivery's start
	var st := a
	while st > f0 and int(clip["down"][me][st]) != 3:
		st -= 1
	if int(clip["down"][me][st]) != 3:
		st = f0   # no frame with both feet down: the window's first
	var fl := _p(clip, me, st, "ball_l").dot(F)
	var frr := _p(clip, me, st, "ball_r").dot(F)
	var lead_sd := "" if absf(fl - frr) < LEAD_MIN else ("_l" if fl > frr else "_r")
	ft["lead"] = 0.5 if lead_sd == "" else (1.0 if lead_sd == sd else 0.0)
	# the limb at contact
	var S := _p(clip, me, c, "upperarm" + sd)
	var E := _p(clip, me, c, "lowerarm" + sd)
	var W := _p(clip, me, c, "hand" + sd)
	ft["elbow"] = _angle(S - E, W - E)
	ft["elbow_elev"] = rad_to_deg(asin(clampf((E - S).y / maxf((E - S).length(), 1e-9), -1.0, 1.0)))
	ft["extend"] = ((W - S).length() - (_p(clip, me, a, "hand" + sd) - _p(clip, me, a, "upperarm" + sd)).length()) / maxf((_p(clip, me, c, eff) - _p(clip, me, a, eff)).length(), 1e-6)   # over the whole delivery
	ft["elbow_lead"] = (_v(clip, me, pk, "lowerarm" + sd) - _v(clip, me, pk, "pelvis")).length() / maxf((_v(clip, me, pk, "hand" + sd) - _v(clip, me, pk, "pelvis")).length(), 1e-6)
	ft["fist_vs_shoulder"] = W.y - S.y
	var osd := "_r" if sd == "_l" else "_l"
	ft["guard"] = _p(clip, me, c, "hand" + osd).distance_to(_p(clip, me, c, "chin"))
	var Hh := _p(clip, me, c, "thigh" + sd)
	var K := _p(clip, me, c, "calf" + sd)
	var A := _p(clip, me, c, "foot" + sd)
	ft["knee"] = _angle(Hh - K, A - K)
	ft["knee_lift"] = K.y - Hh.y
	ft["foot_vs_hip"] = A.y - Hh.y
	var chamber := -INF
	for f in range(a, pk + 1):
		chamber = maxf(chamber, _p(clip, me, f, "calf" + sd).y - _p(clip, me, f, "thigh" + sd).y)
	ft["chamber"] = chamber
	var pfr := frame_at(clip, me, c, true)
	var ext := _flat(A - Hh)
	var el := ext.normalized() if ext.length() > 1e-4 else Vector3.ZERO
	ft["ext_front"] = el.dot(pfr[1])
	ft["ext_side"] = -sgn * el.dot(pfr[0])   # the kicking side: a right leg extends to his right (-left)
	# the knee's fastest straightening (deg/s) vs contact, for the roundhouse's form
	var best_k := -INF
	var kf := c
	for f in range(maxi(a, 1), mini(c + 6, n - 1) + 1):
		var k0 := _angle(_p(clip, me, f - 1, "thigh" + sd) - _p(clip, me, f - 1, "calf" + sd), _p(clip, me, f - 1, "foot" + sd) - _p(clip, me, f - 1, "calf" + sd))
		var k1 := _angle(_p(clip, me, f, "thigh" + sd) - _p(clip, me, f, "calf" + sd), _p(clip, me, f, "foot" + sd) - _p(clip, me, f, "calf" + sd))
		if k1 - k0 > best_k:
			best_k = k1 - k0
			kf = f
	ft["knee_ext_lead"] = float(c - kf)
	# the weapon at the peak
	ft["along"] = 0.0
	ft["descend"] = 0.0
	if group == "weapon":
		var wd := (_p(clip, me, pk, "weapon_tip") - _p(clip, me, pk, "weapon_knob")).normalized()
		var vh := _v(clip, me, pk, "weapon_tip").normalized()
		ft["along"] = absf(wd.dot(vh))
		ft["descend"] = -vh.y
	# classify: the best class of the group
	var crit := criteria(group, ft)
	var ranked := []
	for cl in GROUPS[group]:
		var dist := 0.0
		var why := []
		for cr in crit[cl]:
			var v := _viol(cr)
			dist += v
			if v > 0.0:
				why.append(_miss_words(cr))
		ranked.append({"class": cl, "distance": snappedf(dist, 0.01), "misses": why})
	ranked.sort_custom(func(x, y): return x["distance"] < y["distance"])
	var best: Dictionary = ranked[0]
	var unknown: bool = float(best["distance"]) > UNKNOWN_AT
	var cls: String = "unknown" if unknown else String(best["class"])
	# the chain: hips -> trunk -> upper segment -> lower segment
	var segs := []
	if group == "leg":
		segs = [["hips", "thigh_r", "thigh_l", true], ["thigh", "thigh" + sd, "calf" + sd, false], ["shank", "calf" + sd, "foot" + sd, false]]
	else:
		segs = [["hips", "thigh_r", "thigh_l", true], ["trunk", "upperarm_r", "upperarm_l", true], ["upper arm", "upperarm" + sd, "lowerarm" + sd, false],
			["forearm", "lowerarm" + sd, "hand" + sd, false]]
		if group == "weapon":
			segs.append(["weapon", "weapon_knob", "weapon_tip", false])
	var w0 := maxi(f0, pk - int(WINDOW * fps))
	var w1 := mini(f1, pk + 3)
	var peaks := {}
	var order := []
	var in_order := true
	var prev := -1
	for sg in segs:
		var om := _omega(clip, me, sg[1], sg[2], sg[3])
		var bi := w0
		for f in range(w0, w1 + 1):
			if om[f] > om[bi]:
				bi = f
		peaks[sg[0]] = {"t": snappedf(bi / fps, 0.001), "deg_s": snappedf(om[bi], 1.0)}
		order.append(sg[0])
		if prev >= 0 and bi < prev - TIE:
			in_order = false
		prev = bi
	# planted foot through the delivery
	var cnt := [0, 0]
	for f in range(a, c + 1):
		if int(dn[f]) & 1:
			cnt[0] += 1
		if int(dn[f]) & 2:
			cnt[1] += 1
	var nfr := c - a + 1
	var planted := []
	if cnt[0] >= 0.8 * nfr:
		planted.append("left")
	if cnt[1] >= 0.8 * nfr:
		planted.append("right")
	var world_peak := 0.0
	for f in range(a, c + 1):
		world_peak = maxf(world_peak, _v(clip, me, f, eff).length())
	var shape := "straight" if ft["straightness"] >= 0.9 else "arc"
	if ft["rise"] >= 0.5:
		shape = "rising " + shape
	var plane := "none (straight)"
	if planar:
		plane = "level" if ft["plane_up"] >= 0.6 else ("vertical, facing forward" if ft["plane_left"] >= 0.6 else ("vertical, across the body" if absf(nn.dot(F)) >= 0.6 else "tilted"))
	var dir := _dir_words(d, L, F)
	var form := form_of(cls if not unknown else String(best["class"]), ft)
	form.append({"what": "power chain " + " -> ".join(order), "value": 1.0 if in_order else 0.0, "ok": in_order, "trust": "SOURCED", "source": SRC_CHAIN,
		"text": "the chain runs %s in order, proximal to distal" % " -> ".join(order) if in_order else "the chain is OUT OF ORDER (%s): a textbook strike peaks proximal to distal" % _peak_words(peaks, order)})
	var pt_w: String = {"hand": "fist", "lowerarm": "elbow", "ball": "foot", "calf": "knee", "weapon": "weapon tip"}[eff.split("_")[0]]
	var limb := ("weapon in the %s hand" % side_w) if group == "weapon" else ("%s %s" % [side_w, {"fist": "hand"}.get(pt_w, pt_w)])
	var lead_w := "square stance" if lead_sd == "" else ("lead" if lead_sd == sd else "rear")
	var cited := FIST_CITED if group == "arm" else (FOOT_CITED if group == "leg" else 0.0)
	out.merge({"strike": true, "class": cls, "point": eff, "unknown": unknown, "group": group, "side": side_w, "limb": limb, "stance": lead_w,
		"distance": best["distance"], "nearest": ranked.slice(0, 3),
		"t": {"start": snappedf(a / fps, 0.001), "core": [snappedf(ha / fps, 0.001), snappedf(hb / fps, 0.001)], "peak": snappedf(pk / fps, 0.001), "contact": snappedf(c / fps, 0.001)},
		"frames": {"start": a, "peak": pk, "contact": c, "fps": fps},
		"path": {"shape": shape, "chord_cm": snappedf(chord * 100.0, 0.1), "length_cm": snappedf(length * 100.0, 0.1),
			"straightness": snappedf(ft["straightness"], 0.01), "plane": plane, "direction": dir},
		"speed": {"peak_ms": snappedf(world_peak, 0.01), "peak_rel_pelvis_ms": snappedf(top, 0.01), "cited_ms": cited,
			"cited": "fist 11.95 m/s, Stanley et al. 2018" if group == "arm" else ("foot 14.66 m/s, Gavagan & Sayers 2017" if group == "leg" else "")},
		"chain": {"order": order, "peaks": peaks, "in_order": in_order},
		"planted": planted, "features": _round(ft), "form": form})
	var bad := form.filter(func(x): return not x["ok"])
	var head := ("%s %s" % ["an" if cls[0] in "aeiou" else "a", cls]) if not unknown else ("unknown: nearest %s (distance %.2f; %s)" % [("an " if String(best["class"])[0] in "aeiou" else "a ") + String(best["class"]), best["distance"], "; ".join(best["misses"])])
	out["text"] = "%s (%s, %s): the %s travels %.0f cm on a%s path %s, %.1f m/s at the peak (t %.2f s); %s planted. Form: %s." % [
		head, limb, lead_w, pt_w, chord * 100.0,
		"n " + shape if shape.begins_with("a") else " " + shape, dir, world_peak, pk / fps,
		(" and ".join(planted) + " foot") if not planted.is_empty() else "no foot",
		"; ".join(bad.map(func(x): return x["text"])) if not bad.is_empty() else "as the textbook one"]
	return out


## a missed criterion in words, with its unit: deg, m, else a share / ratio said in %
static func _miss_words(cr: Array) -> String:
	var nm: String = cr[0]
	if nm.ends_with("(deg)"):
		return "%s %.0f deg (wants %.0f-%.0f deg)" % [nm.trim_suffix(" (deg)"), cr[1], cr[2], cr[3]]
	if nm.ends_with("(m)"):
		return "%s %.0f cm (wants %.0f-%.0f cm)" % [nm.trim_suffix(" (m)"), float(cr[1]) * 100.0, float(cr[2]) * 100.0, float(cr[3]) * 100.0]
	return "%s %.0f %% (wants %.0f-%.0f %%)" % [nm, float(cr[1]) * 100.0, float(cr[2]) * 100.0, float(cr[3]) * 100.0]


static func _round(ft: Dictionary) -> Dictionary:
	var o := {}
	for k in ft:
		o[k] = snappedf(float(ft[k]), 0.001)
	return o


static func _peak_words(peaks: Dictionary, order: Array) -> String:
	return ", ".join(order.map(func(k): return "%s %.3f s" % [k, peaks[k]["t"]]))


## a chord in the body's words: "forward 40 cm, toward his left 12 cm, up 5 cm" (the parts over 3 cm)
static func _dir_words(d: Vector3, L: Vector3, F: Vector3) -> String:
	var parts := []
	var f := d.dot(F)
	var l := d.dot(L)
	if absf(f) >= 0.03:
		parts.append("%s %.0f cm" % ["forward" if f > 0.0 else "back", absf(f) * 100.0])
	if absf(l) >= 0.03:
		parts.append("toward his %s %.0f cm" % ["left" if l > 0.0 else "right", absf(l) * 100.0])
	if absf(d.y) >= 0.03:
		parts.append("%s %.0f cm" % ["up" if d.y > 0.0 else "down", absf(d.y) * 100.0])
	return ", ".join(parts) if not parts.is_empty() else "in place"


## a scene played on a body (no window, nothing else) -> the answer over [t0, t1] (t1 < 0 = the end)
static func of_scene(S: Scene, B: Body, t0 := 0.0, t1 := -1.0) -> Dictionary:
	var clip := EventQuery.sample([{"S": S, "B": B, "xf": Transform3D.IDENTITY, "name": String(S.name)}], FPS, {"cross": false, "bal": false})
	var e := float(clip["L"]) if t1 < 0.0 else t1
	return analyze(clip, 0, int(round(t0 * FPS)), int(round(e * FPS)))


## serve's `recognize {card?, t0?, t1?, fighter?}` on the live poser. card = N (1 = the first, as `run`'s card=N): the move
## INTO that card and its hold. -> {"ok", ...} or {"ok": false, "error"}
static func serve(m: Node, p: Dictionary) -> Dictionary:
	if m.S.cards.size() < 2:
		return {"ok": false, "error": "recognize needs a scene of 2+ cards: open one first"}
	var fs := EventQuery.fighters_of(m)
	if fs.size() == 1:
		await m.dummy_settle()
		fs = EventQuery.fighters_of(m)
	var me := int(p.get("fighter", 1)) - 1
	if me < 0 or me >= fs.size():
		return {"ok": false, "error": "no fighter %d (the scene has %d)" % [me + 1, fs.size()]}
	var S: Scene = fs[me]["S"]
	var t0 := float(p.get("t0", 0.0))
	var t1 := float(p.get("t1", -1.0))
	if p.has("card"):
		var k := int(p["card"]) - 1
		if k < 1 or k >= S.cards.size():
			return {"ok": false, "error": "card %d: pick 2..%d (the move INTO the card is read; card 1 has none)" % [k + 1, S.cards.size()]}
		var ts := S.times()
		t0 = float(ts[k][0])
		t1 = float(ts[k][2])
	var clip := EventQuery.sample(fs, FPS, {"cross": false, "bal": false})
	var L: float = clip["L"]
	if t1 < 0.0 or t1 > L:
		t1 = L
	if t0 < 0.0 or t0 >= t1:
		return {"ok": false, "error": "t0 %.3f must be under t1 %.3f (the clip is %.3f s)" % [t0, t1, L]}
	var r := analyze(clip, me, int(round(t0 * FPS)), int(round(t1 * FPS)))
	if p.has("card"):
		r["card"] = int(p["card"])
	return r
