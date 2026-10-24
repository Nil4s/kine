## ouch_meter.gd - THE OUCH METER (docs/INNOVATIONS.md N064). While the user drags a joint on the POSE page, the dragged part
## glows by how far into its range the joint is, so you feel where a real body starts to hurt:
##   OK   (token "ok")    inside the comfortable range
##   WARN (token "warn")  past comfortable, inside the max
##   FAIL (token "fail")  at or past the max: the one-joint table (data/body_limits.json) or, for the legs, the two-joint muscle
##                        bar of N028 (CoupledLimits: a straight knee stops the hip at 90, not 120)
## plus a one-line readout beside the cursor ("right hip 88°: past comfortable (84°), max 120°; 90° with the knee straight
## (hamstrings)"). Drag only; nothing is drawn when no drag is on or the POSE toolbar's "Ouch meter" is off (saved, default on).
## Numbers, sources and their trust: docs/research/OUCH_METER.md.
##
## THE COMFORTABLE BAR, per joint:
##   ELBOW (lowerarm bend)  120 deg: LUBA's elbow-flexion classes (Kee & Karwowski 2001, Appl Ergon 32(4):357-366,
##                          doi:10.1016/S0003-6870(01)00006-0), read in INSST NTP 674 Table 2 (which reproduces them): 0-45 deg
##                          discomfort score 1, 45-120 deg 2 (sitting) / 3 (standing), > 120 deg 5. The jump from 3 to 5 is the
##                          comfortable edge (our reading of the scores: HEURISTIC cut on a MEASURED scale)
##   every other joint      neutral + COMFORT_FRAC x (the table's stop - neutral), each side: HEURISTIC. 0.7 is anchored on RULA's
##                          elbow cut (McAtamney & Corlett 1993, Appl Ergon 24(2):91-99, doi:10.1016/0003-6870(93)90080-S, the
##                          lower arm scores 1 at 60-100 deg, more past 100: 100 / 145 = 0.69); applying one fraction to every
##                          joint is ours. No per-joint comfortable-ROM table was opened (Kee & Karwowski 2001 Ergonomics 44:614
##                          and Naddeo et al. 2019 Work 63:219 have them, paywalled): the hip's comfortable share is said to be
##                          the SMALLEST of the joints there, so 0.7 is lenient for the hip (stated, not fitted)
## NEUTRAL: 0 (Kine's rest) on every axis except the upper arm's side axis, whose rest is the arm down at the side (-90,
## data/body_limits.json "say"). A stop AT neutral is not judged: an elbow or knee straight (bend 0) is the bone's own stop and
## the rest, not a strain, so a one-way joint is green there.
## THE PELVIS is not judged: its angles are the whole body's orientation in the world, not a joint.
## A HAND OR FOOT pulled on IK moves the elbow / knee and shoulder / hip: the worst joint of its chain lights (its part).
## COST: no Check, no allocation of findings: a handful of comparisons per axis plus the N028 curves (built once, cached).
## tests/ouch_test.gd measures it under 0.5 ms per drag frame.
class_name OuchMeter
extends Node

const SECTION := "pose"
const KEY := "ouch_meter"
const TOL := 0.5            # deg: "at the max" = within the joint's own rounding of the stop (Body.at_limit's 0.5)
const COMFORT_FRAC := 0.7   # HEURISTIC: the comfortable share of each side's range from neutral (RULA's elbow 100 / 145)
const ELBOW_COMFORT := 120.0   # LUBA: elbow flexion > 120 deg scores 5 (from 2-3 at 45-120) (Kee & Karwowski 2001, via NTP 674)
const ELBOW_COMFORT_RULA := 100.0   # RULA's own elbow cut (lower arm 60-100 = score 1): the fraction's anchor, kept for the doc
const ZONES := ["ok", "warn", "fail"]
## the part a hand / foot drag really bends: its chain, nearest joint first
const CHAIN := {"hand_r": ["lowerarm_r", "upperarm_r"], "hand_l": ["lowerarm_l", "upperarm_l"],
	"foot_r": ["calf_r", "thigh_r"], "foot_l": ["calf_l", "thigh_l"]}
const JOINT_WORD := {"thigh": "hip", "calf": "knee", "foot": "ankle", "ball": "toes", "upperarm": "shoulder", "lowerarm": "elbow",
	"hand": "wrist", "clavicle": "collarbone", "neck_01": "neck", "head": "head", "spine_01": "lower back", "spine_02": "mid back",
	"spine_03": "upper back"}

var on := true
var lit := {}          # part -> "ok" / "warn" / "fail": what the last apply lit (tests read it)
var last := {}         # the last judgement (judge()'s dictionary), {} when nothing was drawn
var last_us := 0       # microseconds the last apply took (judge + look + readout)
var readout: PanelContainer
var _label: Label
var _host: Node

static var _cpl := []   # [{c, warn curve}] from CoupledLimits.couplings(), built once


func setup(host: Node) -> void:
	_host = host
	name = "ouch_meter"


# ---------------------------------------------------------------- the judgement (pure: the test calls it directly)

static func _couplings() -> Array:
	if _cpl.is_empty():
		for c in CoupledLimits.couplings():
			_cpl.append({"c": c, "w": CoupledLimits.shifted(c, "warn")})
	return _cpl


static func neutral(j: String, axis: int) -> float:
	return -90.0 if axis == 1 and j.begins_with("upperarm") else 0.0


## the comfortable bars [lo, hi] of joint j's axis (0 bend, 1 side, 2 twist), given its table stops L
static func comfort(j: String, axis: int, L: Vector2) -> Vector2:
	var n := neutral(j, axis)
	var lo := n + COMFORT_FRAC * (L.x - n)
	var hi := n + COMFORT_FRAC * (L.y - n)
	if axis == 0 and j.begins_with("lowerarm"):
		hi = ELBOW_COMFORT
	return Vector2(lo, hi)


## the N028 bars on joint j's bend as the body stands now: {lo, hi, lo_why, hi_why} (only the legs; {} = none binds)
static func coupled(B: Body, j: String) -> Dictionary:
	var ps := CoupledLimits.split(j)
	var part: String = ps[0]
	var sd: String = ps[1]
	if sd == "" or not part in ["thigh", "calf", "foot"]:
		return {}
	var out := {}
	for e in _couplings():
		var c: Dictionary = e["c"]
		var cv: Array = e["w"]
		if part == c["joint"]:
			var x: float = (B.ang[c["other"] + sd] as Vector3).x
			var bar := CoupledLimits.at(cv, x)
			var why := "%s (%s)" % ["with the knee straight" if x < 5.0 else "with the knee bent %.0f°" % x, c["muscle"]]
			if c["side"] == "max":
				if not out.has("hi") or bar < float(out["hi"]):
					out["hi"] = bar
					out["hi_why"] = why
			elif not out.has("lo") or bar > float(out["lo"]):
				out["lo"] = bar
				out["lo_why"] = why
		elif part == c["other"]:
			var a: float = (B.ang[c["joint"] + sd] as Vector3).x
			var why2 := "with the %s at %.0f°" % [JOINT_WORD[c["joint"]], a]
			if c["side"] == "max":
				var need := CoupledLimits.x_for(cv, a)   # the knee must stay bent at least this much
				if need != INF and (not out.has("lo") or need > float(out["lo"])):
					out["lo"] = need
					out["lo_why"] = "%s (%s)" % [why2, c["muscle"]]
			else:
				var most := CoupledLimits.x_upto(cv, a)   # the knee may bend at most this much
				if most != INF and most != -INF and (not out.has("hi") or most < float(out["hi"])):
					out["hi"] = most
					out["hi_why"] = "%s (%s)" % [why2, c["muscle"]]
	return out


## one joint now: {joint, part, axis, angle, comfort, max (the table's stop on that side), bar (the effective stop: table or
## coupled), coupled_why ("" = the table), zone "ok"/"warn"/"fail", rank 0..2, frac (0 neutral .. 1 at the stop)}. {} = not judged
static func judge(B: Body, j: String) -> Dictionary:
	if j == "pelvis" or not B.lim.has(j) or not B.ang.has(j):
		return {}
	var a3: Vector3 = B.ang[j]
	var cp := coupled(B, j)
	var best := {}
	for axis in 3:
		var L: Vector2 = B.lim[j][["bend", "side", "twist"][axis]]
		if L.y - L.x < 1e-3:
			continue   # a locked axis
		var a: float = a3[axis]
		var n := neutral(j, axis)
		var cf := comfort(j, axis, L)
		var hi := L.y
		var lo := L.x
		var hi_why := ""
		var lo_why := ""
		if axis == 0 and cp.has("hi") and float(cp["hi"]) < hi - TOL:
			hi = float(cp["hi"])
			hi_why = cp["hi_why"]
		if axis == 0 and cp.has("lo") and float(cp["lo"]) > lo + TOL:
			lo = float(cp["lo"])
			lo_why = cp["lo_why"]
		# the side a is on: past a coupled floor above neutral (a knee that must stay bent) counts as the low side
		var up := a >= n and not (lo_why != "" and a <= lo + TOL)
		var stop := hi if up else lo
		var table := L.y if up else L.x
		var why := hi_why if up else lo_why
		var c_bar := minf(cf.y, hi) if up else maxf(cf.x, lo)   # comfortable never past the effective stop
		var past := (a - c_bar) if up else (c_bar - a)
		var at_stop := (a >= hi - TOL) if up else (a <= lo + TOL)
		if absf(stop - n) < 1e-3 and why == "":
			at_stop = false   # the stop IS the rest (an elbow / knee straight): the bone's stop, not a strain
			past = -1.0
		var rank := 2 if at_stop else (1 if past > 1e-6 else 0)
		var span := absf(stop - n)
		var frac := absf(a - n) / span if span > 1e-6 else 0.0
		var r := {"joint": j, "part": j, "axis": ["bend", "side", "twist"][axis], "angle": a, "comfort": c_bar, "max": table,
			"bar": stop, "coupled_why": why, "zone": ZONES[rank], "rank": rank, "frac": frac}
		if best.is_empty() or rank > int(best["rank"]) or (rank == int(best["rank"]) and frac > float(best["frac"])):
			best = r
	return best


## the dragged part p: itself, or for a hand / foot pulled on IK the worst joint of its chain (that joint's part lights)
static func judge_drag(B: Body, p: String) -> Dictionary:
	var cands: Array = [p]
	if CHAIN.has(p):
		cands = CHAIN[p] + [p]
	var best := {}
	for j in cands:
		var r := judge(B, j)
		if r.is_empty():
			continue
		if best.is_empty() or int(r["rank"]) > int(best["rank"]):   # a tie keeps the nearer joint (the elbow before the shoulder)
			best = r
	return best


static func joint_words(j: String) -> String:
	var ps := CoupledLimits.split(j)
	var base: String = ps[0]
	var sd: String = ps[1]
	var w: String = JOINT_WORD.get(base, JOINT_WORD.get(j, base.replace("_", " ")))
	if base.begins_with("finger") or base.begins_with("thumb"):
		w = base.replace("_0", " joint ")
	return ("right " if sd == "_r" else "left " if sd == "_l" else "") + w


## the readout: "right hip 88°: past comfortable (84°), max 120°; 90° with the knee straight (hamstrings)"
static func say(r: Dictionary) -> String:
	if r.is_empty():
		return ""
	var ax := "" if r["axis"] == "bend" else " (%s)" % r["axis"]
	var head := "%s%s %.0f°" % [joint_words(String(r["joint"])), ax, float(r["angle"])]
	var mx := "max %.0f°" % float(r["max"])
	if String(r["coupled_why"]) != "":
		mx += "; %.0f° %s" % [float(r["bar"]), r["coupled_why"]]
	match String(r["zone"]):
		"ok":
			return "%s: comfortable (up to %.0f°), %s" % [head, float(r["comfort"]), mx]
		"warn":
			return "%s: past comfortable (%.0f°), %s" % [head, float(r["comfort"]), mx]
	return "%s: AT THE MAX, it hurts here (comfortable %.0f°), %s" % [head, float(r["comfort"]), mx]


## N074's glow (RedSpots.look: its FILL and RIM), in the zone's token
static func look(zone: String) -> Array:
	return [Color(Tok.c(zone), RedSpots.FILL), RedSpots.RIM]


# ---------------------------------------------------------------- per drag frame (main's _refresh)

## dragging: a joint drag is on now; p the dragged part; mp the cursor. Writes the glow into main's looks table and moves the
## readout. Off or no drag: nothing drawn, the readout hidden
func apply(looks: Dictionary, B: Body, p: String, dragging: bool, mp: Vector2) -> void:
	var t0 := Time.get_ticks_usec()
	lit = {}
	last = {}
	if not on or not dragging or p == "" or not B.P.has(p):
		hide_readout()
		last_us = Time.get_ticks_usec() - t0
		return
	last = judge_drag(B, p)
	if last.is_empty():
		hide_readout()
		last_us = Time.get_ticks_usec() - t0
		return
	var part: String = last["part"]
	lit[part] = last["zone"]
	looks[part] = look(String(last["zone"]))
	_show_readout(say(last), String(last["zone"]), mp)
	last_us = Time.get_ticks_usec() - t0


func _show_readout(text: String, zone: String, mp: Vector2) -> void:
	var parent: Control = _host.ui_root if _host != null and _host.get("ui_root") != null else null
	if parent == null:
		return
	if readout == null or not is_instance_valid(readout):
		readout = PanelContainer.new()
		readout.name = "ouch_readout"
		readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		sb.corner_radius_top_left = 4
		sb.corner_radius_top_right = 4
		sb.corner_radius_bottom_left = 4
		sb.corner_radius_bottom_right = 4
		readout.add_theme_stylebox_override("panel", sb)
		_label = Label.new()
		_label.name = "ouch_text"
		_label.add_theme_font_size_override("font_size", 13)
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		readout.add_child(_label)
		parent.add_child(readout)
	(readout.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = Tok.c("say_bg")   # read each frame: a palette switch shows at once
	_label.add_theme_color_override("font_color", Tok.c(zone))
	if _label.text != text:
		_label.text = text
		readout.reset_size()
	var vs := parent.get_viewport_rect().size
	readout.position = Vector2(clampf(mp.x + 18.0, 0.0, maxf(0.0, vs.x - readout.size.x)), clampf(mp.y + 18.0, 0.0, maxf(0.0, vs.y - readout.size.y)))
	readout.visible = true


func hide_readout() -> void:
	if readout != null and is_instance_valid(readout):
		readout.visible = false


func readout_text() -> String:
	return _label.text if readout != null and is_instance_valid(readout) and readout.visible and _label != null else ""


# ---------------------------------------------------------------- the setting

func load_from(path: String) -> void:
	var cf := ConfigFile.new()
	if cf.load(path) == OK:
		on = bool(cf.get_value(SECTION, KEY, true))


func set_on(v: bool, path: String) -> void:
	on = v
	if not on:
		lit = {}
		last = {}
		hide_readout()
	var cf := ConfigFile.new()
	cf.load(path)
	cf.set_value(SECTION, KEY, v)
	cf.save(path)
