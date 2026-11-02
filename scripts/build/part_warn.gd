## part_warn.gd - WARNING LEVELS (item 221): one list of plain warnings about the part, at the level the maker asked for, the same list for the
## people (the Warnings panel, scripts/build/part_warn_ui.gd) and the AI (agent_tools "part_warn"). Builds on item 220: the facts, the contact graph and the
## touching / inside / clearance numbers come from PartFacts (scripts/part_facts.gd) and the existing checks (PrintCheck, MeshExport.check, PartStand); this
## file is only the rules that turn those numbers into words. Nothing here measures a second time.
##
## LEVELS  off < look < print < engineering. A level shows its own warnings AND the ones of the levels below it (look is inside print is inside engineering).
##   LOOK  (art, games)  look.broken_solid    a step of the timeline failed, or a body has no volume
##                       look.floating        a piece touches nothing else and is not resting on the floor (the lowest point of the part)
##                       look.floats          s237: a small piece (an ornament) that touches nothing but lies within its own size of another piece: it looks attached and is not (names the gap in mm)
##                       look.hidden_overlap  a body lies wholly inside another (95 % or more of its volume): nobody can see it
##                       look.no_name         a body still has its automatic name (Body3, Extrude2 ...)
##                       look.dark_material   a body's colour is darker than 6 % luminance: it vanishes in shading
##   PRINT               print.thin_wall      a wall thinner than 0.8 mm (PrintCheck.THIN_MM)
##                       print.overhang       a face pointing down steeper than 45 degrees that nothing holds up (PrintCheck.OVERHANG_DEG)
##                       print.not_watertight a body whose skin has an open or doubled edge (MeshExport.check)
##                       print.small_detail   a body no bigger than 1 mm in any direction (a speck the printer will lose)
##   ENGINEERING         eng.fit              a round shaft in a round hole: its ISO 286 class and the clearance range of the table, or "no standard fit"
##                       eng.bolt             a bolt (a body named Bolt / Screw / Stud / M6 ...) bites less than the engagement the material needs
##                       eng.tips             the centre of mass lies outside the feet (PartStand), with the part's weight from its material
##                       eng.stress           a slender body as a cantilever (fixed at one end, the load at the other) passes the material's yield / 1.5
##                       eng.deflection       ... or bends the free end more than length / 100
##                       eng.draft            a wall within 1 degree of the pull direction (up): a moulded part would stick in the mould
## MUTES  rec["warn_mute"] is a list of "<warning id>@<part>" strings; "<id>@*" mutes that warning on every part, "*@<part>" every warning of that
##   part; a whole-part warning (the tip-over) has the part "". rec["warn_level"] is the level ("off" when unset: the checks cost a replay).
## The record keys travel through Part.to_file / from_file, so save, reload and undo (a snapshot of the record) keep them.
class_name PartWarn
extends RefCounted

const KCad := preload("res://scripts/kcad.gd")
const LEVELS := ["off", "look", "print", "engineering"]
const LEVEL_WORDS := {"off": "Off", "look": "Look", "print": "Print", "engineering": "Engineering"}
const BADGES := {"look": "LOOK", "print": "PRINT", "engineering": "ENG"}
const LEVEL_HELP := {
	"off": "No warnings.",
	"look": "Looks: broken solid, floating, hidden overlap, no name, dark material.",
	"print": "Looks + printing: wall too thin, overhang, not watertight, too small a detail.",
	"engineering": "Looks + printing + engineering: ISO 286 fits, bolt engagement, weight and tipping, beam stress and bend, draft for moulding.",
}
const HIDDEN_FRAC := 0.95         # a body with this share of its volume inside another is hidden
const DARK_LUM := 0.06            # a colour below this luminance (0.2126 R + 0.7152 G + 0.0722 B) is dark
const SPECK_MM := 1.0             # a body no bigger than this in every direction is too small a detail
const FLOOR_TOL := 0.05           # mm: a body this close to the lowest point of the part rests on the floor
const DRAFT_DEG := 1.0            # a wall within this angle of the pull direction (up) has no draft
const DRAFT_MIN_MM2 := 1.0        # ... and the sum of such wall must be at least this to be said
const SLENDER := 4.0              # a body this many times longer than it is wide is a beam
const DEFLECT_DIV := 100.0        # a cantilever may bend its free end by length / 100
const SAFETY := 1.5               # the yield stress is divided by this
const FIT_TOL_UM := 1.5           # micrometres: measuring slack when a measured size is matched to a tolerance band
const FIT_LOOSE := 0.03           # a round shaft in a hole looser than this share of the size is not an engineered fit
const G := 9.80665
## ISO 286-1 / 286-2 (hole-basis preferred fits), micrometres, for the basic sizes over 1 up to and including 50 mm: the size steps are
## (1,3] (3,6] (6,10] (10,18] (18,30] (30,50]; IT = the standard tolerance grade, FD = the fundamental deviation of a shaft:
## d, f, g, h are the UPPER deviation es (negative or 0), k, n, p, s are the LOWER deviation ei (positive); the hole H has EI = 0, ES = +IT.
const STEPS := [[1.0, 3.0], [3.0, 6.0], [6.0, 10.0], [10.0, 18.0], [18.0, 30.0], [30.0, 50.0]]
const IT := {6: [6, 8, 9, 11, 13, 16], 7: [10, 12, 15, 18, 21, 25], 8: [14, 18, 22, 27, 33, 39], 9: [25, 30, 36, 43, 52, 62]}
const FD := {"d": [-20, -30, -40, -50, -65, -80], "f": [-6, -10, -13, -16, -20, -25], "g": [-2, -4, -5, -6, -7, -9], "h": [0, 0, 0, 0, 0, 0],
	"k": [0, 1, 1, 1, 2, 2], "n": [4, 8, 10, 12, 15, 17], "p": [6, 12, 15, 18, 22, 26], "s": [14, 19, 23, 28, 35, 43]}
## the preferred fits of ISO 286-2 (without the very loose H11/c11): [hole grade, shaft position, shaft grade, name]
const FITS := [[9, "d", 9, "loose running"], [8, "f", 7, "close running"], [7, "g", 6, "sliding"], [7, "h", 6, "locational clearance"],
	[7, "k", 6, "locational transition"], [7, "n", 6, "tight transition"], [7, "p", 6, "locational interference"], [7, "s", 6, "medium drive"]]
## mechanical properties (room temperature, handbook values): E in GPa, yield or bending strength in MPa
const MATERIAL := {"steel": {"E": 200.0, "yield": 235.0, "name": "steel S235"}, "aluminium": {"E": 69.0, "yield": 240.0, "name": "aluminium 6061-T6"},
	"wood": {"E": 9.0, "yield": 40.0, "name": "pine"}, "plastic": {"E": 2.2, "yield": 40.0, "name": "ABS"}}
## the thread engagement a bolt needs, in bolt diameters, by the material it screws into
const ENGAGE := {"steel": 1.0, "aluminium": 1.5, "wood": 2.0, "plastic": 2.0}
const AUTO_NAME := "^(Body ?\\d+|(Sketch|Extrude|Revolve|Fillet|Chamfer|Mirror|Hinge|Split|Shell|Loft|Sweep|Plane|Canvas|Appear|Pattern|Combine|Offset_face|Offset Face|Draft|Lay|Align|Lattice|Fitobj|Move|Offset|Meshsolid|Pipe3d|Prim|Ornament|Bname)\\d*)( \\d+)?$"
const CODES := {
	"look.broken_solid": "look", "look.floating": "look", "look.floats": "look", "look.hidden_overlap": "look", "look.no_name": "look", "look.dark_material": "look",
	"print.thin_wall": "print", "print.overhang": "print", "print.not_watertight": "print", "print.small_detail": "print",
	"eng.fit": "engineering", "eng.bolt": "engineering", "eng.tips": "engineering", "eng.stress": "engineering", "eng.deflection": "engineering", "eng.draft": "engineering",
}

static var _cache_key := ""
static var _cache := {}


# ------------------------------------------------------------------------------------------------ the level and the mutes (record edits)
static func level_of(rec: Dictionary) -> String:
	var l := String(rec.get("warn_level", "off"))
	return l if l in LEVELS else "off"


static func rank(level: String) -> int:
	return maxi(0, LEVELS.find(level))


static func set_level(rec: Dictionary, level: String) -> bool:
	if not level in LEVELS:
		return false
	if level == "off":
		rec.erase("warn_level")
	else:
		rec["warn_level"] = level
	return true


static func muted(rec: Dictionary, code: String, part: String) -> bool:
	for m in rec.get("warn_mute", []):
		if m == "%s@%s" % [code, part] or m == "%s@*" % code or m == "*@%s" % part:
			return true
	return false


## mute or unmute "<id>@<part>" (also "<id>@*", "*@<part>"); false when the text is not that shape
static func set_mute(rec: Dictionary, key: String, on: bool) -> bool:
	var at := key.find("@")
	if at <= 0:
		return false
	var code := key.substr(0, at)
	if code != "*" and not CODES.has(code):
		return false
	var l: Array = (rec.get("warn_mute", []) as Array).duplicate()
	if on and not key in l:
		l.append(key)
	elif not on:
		l.erase(key)
	if l.is_empty():
		rec.erase("warn_mute")
	else:
		rec["warn_mute"] = l
	return true


# ------------------------------------------------------------------------------------------------ the report
## {"ok", "level", "level_word", "warnings": [{"id", "level", "badge", "part", "key", "text"}] (the ones the level shows, not muted),
##  "muted": [the same, for the ones a mute hides], "fits": [ISO 286 classes found], "numbers": {...}, "lines": ["[LOOK] ...", ...], "error"?}
## opts: "level" (override the record's), "bodies" (precomputed print bodies, MeshExport.bodies_of's, so a caller with a mesh in hand can judge it)
static func report(rec: Dictionary, opts := {}) -> Dictionary:
	var level := String(opts.get("level", level_of(rec)))
	var out := {"ok": true, "level": level, "level_word": LEVEL_WORDS.get(level, "Off"), "warnings": [], "muted": [], "fits": [], "numbers": {}, "lines": []}
	if level == "off" or rec.is_empty():
		return out
	if not Part.available():
		out["ok"] = false
		out["error"] = "the CAD kernel is not installed (%s)" % Part.why_not()
		return out
	var base := rec.duplicate()
	base.erase("warn_mute")
	base.erase("warn_level")
	var ck := "%s|%s|%d" % [level, str(hash(JSON.stringify(base))), (opts.get("bodies", []) as Array).size()]
	var raw: Dictionary
	if opts.is_empty() or (opts.size() == 1 and opts.has("level")):
		if ck == _cache_key and not _cache.is_empty():
			raw = _cache
		else:
			raw = _compute(rec, rank(level), opts)
			_cache_key = ck
			_cache = raw
	else:
		raw = _compute(rec, rank(level), opts)
	out["ok"] = bool(raw.get("ok", true))
	if raw.has("error"):
		out["error"] = raw["error"]
	out["fits"] = raw.get("fits", [])
	out["numbers"] = raw.get("numbers", {})
	for w in raw.get("warnings", []):
		var d: Dictionary = (w as Dictionary).duplicate()
		if muted(rec, String(d["id"]), String(d["part"])):
			out["muted"].append(d)
		else:
			out["warnings"].append(d)
	for w in out["warnings"]:
		out["lines"].append("[%s] %s" % [w["badge"], w["text"]])
	return out


static func _w(code: String, part: String, text: String) -> Dictionary:
	var lv: String = CODES[code]
	return {"id": code, "level": lv, "badge": BADGES[lv], "part": part, "key": "%s@%s" % [code, part], "text": text}


static func _compute(rec: Dictionary, upto: int, opts: Dictionary) -> Dictionary:
	var M := PartFacts.build(rec)
	var res := {"ok": true, "warnings": [], "fits": [], "numbers": {}}
	if not M.ok:
		if not M.errors.is_empty():
			res["warnings"].append(_w("look.broken_solid", "", "A step failed and left no solid: %s. Open the timeline and fix or delete that step." % _errs_words(M.errors)))
		else:
			res["ok"] = false
			res["error"] = M.why
		M.release()
		return res
	var W: Array = res["warnings"]
	var C := PartFacts.contacts(M)
	_look(rec, M, C, W)
	if upto >= 2:
		var bodies: Array = opts.get("bodies", [])
		if bodies.is_empty():
			bodies = MeshExport.bodies_of(rec).get("bodies", [])
		_print(M, bodies, W)
	if upto >= 3:
		_engineering(rec, M, res)
	M.release()
	return res


static func _errs_words(errs: Dictionary) -> String:
	var bits: Array = []
	for k in errs:
		bits.append("%s (%s)" % [k, String(errs[k]).left(60)])
	return ", ".join(bits)


# ------------------------------------------------------------------------------------------------ LOOK
static func _look(rec: Dictionary, M: PartFacts.Model, C: Dictionary, W: Array) -> void:
	if not M.errors.is_empty():
		W.append(_w("look.broken_solid", "", "%d step%s failed: %s. The solid may be missing a cut or a join." % [M.errors.size(), "" if M.errors.size() == 1 else "s", _errs_words(M.errors)]))
	for i in M.n:
		if M.vol_mm3[i] <= 1e-6:
			W.append(_w("look.broken_solid", String(M.labels[i]), "%s has no volume: it is an empty or inside-out solid." % M.labels[i]))
	# floating: a piece that touches nothing else and is not resting on the floor (the part's lowest point)
	var comps := M.components()
	if comps.size() > 1:
		var low := INF
		for i in M.n:
			low = minf(low, M.box(i).position.y)
		for g in comps:
			var glow := INF
			var big := int(g[0])
			for i in g:
				glow = minf(glow, M.box(int(i)).position.y)
				if M.vol_mm3[int(i)] > M.vol_mm3[big]:
					big = int(i)
			if glow > low + FLOOR_TOL:
				W.append(_w("look.floating", String(M.labels[big]), "%s floats: it touches no other piece and its lowest point is %.1f mm above the floor." % [M.labels[big], glow - low]))
	# floats (s237): a small piece that looks attached to another and is not (a gap of more than 0.05 mm, up to its own size)
	for fw in PartFacts.floats(M, comps):
		W.append(_w("look.floats", String(fw["label"]), String(fw["text"])))
	# hidden: wholly inside another body
	for p in C["overlaps"]:
		var a := int(p[0])
		var b := int(p[1])
		var small := a if M.vol_mm3[a] <= M.vol_mm3[b] else b
		var bigger := b if small == a else a
		if M.vol_mm3[small] > 1e-6 and float(p[2]) >= HIDDEN_FRAC * M.vol_mm3[small]:
			W.append(_w("look.hidden_overlap", String(M.labels[small]), "%s is hidden inside %s (%.0f mm3 of its %.0f mm3 are inside): it cannot be seen." % [M.labels[small], M.labels[bigger], float(p[2]), M.vol_mm3[small]]))
	var rx := RegEx.new()
	rx.compile(AUTO_NAME)
	for i in M.n:
		if rx.search(String(M.labels[i])) != null:
			W.append(_w("look.no_name", String(M.labels[i]), "%s has no name of its own: double-click it in the browser and name it." % M.labels[i]))
	for i in M.n:
		if i >= M.looks.size() or M.looks[i] == null or String((M.looks[i] as Dictionary).get("preset", "Default")) == "Default":
			continue
		var c: Color = (M.looks[i] as Dictionary)["c"]
		var lum := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
		if lum < DARK_LUM:
			W.append(_w("look.dark_material", String(M.labels[i]), "%s is almost black (luminance %.3f, under %.2f): it will vanish in shaded views. Lighten its colour." % [M.labels[i], lum, DARK_LUM]))


# ------------------------------------------------------------------------------------------------ PRINT
static func _print(M: PartFacts.Model, bodies: Array, W: Array) -> void:
	if not bodies.is_empty():
		var sc := PrintCheck.scan(bodies)
		var one := bodies.size() == 1
		if int(sc["walls"]) > 0:
			var named := false
			if not one:
				for i in mini(bodies.size(), M.n):
					var s1 := PrintCheck.scan([bodies[i]])
					if int(s1["walls"]) > 0:
						named = true
						W.append(_w("print.thin_wall", String(M.labels[i]), "%s has %d wall%s thinner than %.1f mm (thinnest %.2f mm): a printer may leave it out or break it. Thicken it." % [M.labels[i], int(s1["walls"]), "" if int(s1["walls"]) == 1 else "s", PrintCheck.THIN_MM, float(s1["thinnest"])]))
			if one or not named:
				W.append(_w("print.thin_wall", String(M.labels[0]) if one else "", "%d wall%s thinner than %.1f mm (thinnest %.2f mm): a printer may leave it out or break it. Thicken it." % [int(sc["walls"]), "" if int(sc["walls"]) == 1 else "s", PrintCheck.THIN_MM, float(sc["thinnest"])]))
		var over_cm2 := float(sc["over_mm2"]) / 100.0
		if over_cm2 > 0.005:
			var oname := ""
			if not one:
				var best := 0.0
				for i in mini(bodies.size(), M.n):
					var o1 := float(PrintCheck.scan([bodies[i]])["over_mm2"])
					if o1 > best:
						best = o1
						oname = String(M.labels[i])
			elif M.n > 0:
				oname = String(M.labels[0])
			W.append(_w("print.overhang", oname, "%.2f cm2 of faces point down steeper than %d degrees with nothing under them: they need supports, or turn the part." % [over_cm2, int(PrintCheck.OVERHANG_DEG)]))
		for i in mini(bodies.size(), M.n):
			var ck := MeshExport.check(bodies[i])
			if not bool(ck["closed"]):
				W.append(_w("print.not_watertight", String(M.labels[i]), "%s is not watertight: %d open and %d doubled edges in its skin. A slicer may print it wrong." % [M.labels[i], int(ck["open"]), int(ck["bad"])]))
	for i in M.n:
		var sz := M.box(i).size
		if maxf(sz.x, maxf(sz.y, sz.z)) <= SPECK_MM:
			W.append(_w("print.small_detail", String(M.labels[i]), "%s is only %.2f x %.2f x %.2f mm: too small a detail for a printer, it will be lost." % [M.labels[i], sz.x, sz.y, sz.z]))


# ------------------------------------------------------------------------------------------------ ENGINEERING
static func _engineering(rec: Dictionary, M: PartFacts.Model, res: Dictionary) -> void:
	var W: Array = res["warnings"]
	var mat := PartWeapon.material_at(rec)
	var vol := 0.0
	for i in M.n:
		vol += M.vol_mm3[i]
	var kg := vol * 1e-9 * float(PartWeapon.DENSITY[mat])
	var num: Dictionary = res["numbers"]
	num["material"] = mat
	num["weight_kg"] = snappedf(kg, 0.0001)
	num["centre_mm"] = M.centre_mm
	_fits(M, W, res["fits"])
	_bolts(M, mat, W, num)
	var st := PartStand.check(rec)
	if not String(st.get("say", "")).begins_with("No solid"):   # PartStand answers ok = false when it tips: the margin is still the number
		num["margin_mm"] = snappedf(float(st["margin_mm"]), 0.01)
		if float(st["margin_mm"]) < 0.0:
			var side := String(st["say"])
			var toward := side.substr(side.find("toward the ") + 11, 8).get_slice(".", 0).strip_edges()
			W.append(_w("eng.tips", "", "It tips over toward the %s: the centre of mass is %.1f mm past its feet. It weighs %.3f kg in %s. Widen the foot or move the weight in." % [toward, -float(st["margin_mm"]), kg, mat]))
	_beams(rec, M, mat, kg, W, num)
	_draft(M, W)


## the ISO 286 size step of a basic size (mm), or -1
static func _step_of(n: float) -> int:
	for k in STEPS.size():
		if n > STEPS[k][0] and n <= STEPS[k][1]:
			return k
	return -1


## the band [low, high] in micrometres of a hole H<grade>, or of a shaft <pos><grade>, for the size step k
static func band(hole: bool, pos: String, grade: int, k: int) -> Array:
	var it: float = IT[grade][k]
	if hole:
		return [0.0, it]
	var fd: float = FD[pos][k]
	if pos in ["k", "n", "p", "s"]:
		return [fd, fd + it]
	return [fd - it, fd]


## the basic size a measured pair sits on: whole mm from 10 up, half mm below
static func nominal_of(mid: float) -> float:
	return roundf(mid) if mid >= 10.0 else roundf(mid * 2.0) / 2.0


## classify a measured shaft diameter d and hole diameter D (mm): {"class": "H7/g6", "name", "nominal", "cmin_um", "cmax_um", ...}, or {} when no preferred fit holds
static func classify(d: float, D: float) -> Dictionary:
	var n := nominal_of((d + D) * 0.5)
	var k := _step_of(n)
	if k < 0 or absf((d + D) * 0.5 - n) > 0.1:
		return {}
	var dh := (D - n) * 1000.0
	var ds := (d - n) * 1000.0
	var best := {}
	var best_score := INF
	for f in FITS:
		var hb := band(true, "H", int(f[0]), k)
		var sb := band(false, String(f[1]), int(f[2]), k)
		if dh < hb[0] - FIT_TOL_UM or dh > hb[1] + FIT_TOL_UM or ds < sb[0] - FIT_TOL_UM or ds > sb[1] + FIT_TOL_UM:
			continue
		var score := absf(dh - (hb[0] + hb[1]) * 0.5) + absf(ds - (sb[0] + sb[1]) * 0.5)
		if score < best_score:
			best_score = score
			best = {"class": "H%d/%s%d" % [int(f[0]), String(f[1]), int(f[2])], "name": String(f[3]), "nominal": n, "cmin_um": hb[0] - sb[1], "cmax_um": hb[1] - sb[0],
				"hole_um": [hb[0], hb[1]], "shaft_um": [sb[0], sb[1]]}
	return best


## the preferred fit whose clearance range is nearest the measured diametral clearance (um) at basic size n, for the advice
static func nearest_fit(n: float, clear_um: float) -> Dictionary:
	var k := _step_of(n)
	if k < 0:
		return {}
	var best := {}
	var bd := INF
	for f in FITS:
		var hb := band(true, "H", int(f[0]), k)
		var sb := band(false, String(f[1]), int(f[2]), k)
		var mid: float = ((hb[0] - sb[1]) + (hb[1] - sb[0])) * 0.5
		if absf(mid - clear_um) < bd:
			bd = absf(mid - clear_um)
			best = {"class": "H%d/%s%d" % [int(f[0]), String(f[1]), int(f[2])], "name": String(f[3]), "hole_um": hb, "shaft_um": sb, "cmin_um": hb[0] - sb[1], "cmax_um": hb[1] - sb[0]}
	return best


static func _is_bolt(label: String) -> bool:
	var l := label.to_lower()
	return l.begins_with("bolt") or l.begins_with("screw") or l.begins_with("stud") or l.begins_with("m") and l.length() > 1 and l[1].is_valid_int()


static func _fits(M: PartFacts.Model, W: Array, fits: Array) -> void:
	for i in M.n:
		var ax := M.axis(i)
		if String(ax["kind"]) != "round" or _is_bolt(String(M.labels[i])):
			continue
		var r := float(ax["radius"])
		if r <= 0.1 or float(ax["len"]) < r:
			continue
		var a: Vector3 = ax["axis"]
		var o := M.centroid(i)
		var u := a.cross(Vector3.UP if absf(a.y) < 0.9 else Vector3.RIGHT).normalized()
		var v := a.cross(u).normalized()
		for j in M.n:
			if j == i or M.box_gap(i, j) > 0.5:
				continue
			var P := PartFacts.tess_mm(int(M.ids[j]), 2e-7, 0.02)   # a tight mesh of the possible hole: its chord error is about a micrometre
			var Rh := -1.0
			var lo := INF
			var hi := 0.0
			for s in 36:
				var th := PI * float(s) / 36.0
				var d := u * cos(th) + v * sin(th)
				var h1 := PartFacts.ray_hit(P, o, d)
				var h2 := PartFacts.ray_hit(P, o, -d)
				if is_inf(h1) or is_inf(h2):
					Rh = -1.0
					lo = INF
					break
				var avg := (h1 + h2) * 0.5   # opposite rays: an off-centre shaft's error cancels
				lo = minf(lo, avg)
				hi = maxf(hi, avg)
			if is_inf(lo) or hi - lo > 0.01 + 0.002 * hi:
				continue   # not a round hole
			Rh = hi
			var dd := 2.0 * r
			var DD := 2.0 * Rh
			var n := nominal_of((dd + DD) * 0.5)
			if DD - dd > maxf(0.1, FIT_LOOSE * n) or dd - DD > 0.3 * n:
				continue   # far looser than a fit (or a shaft that is not in it)
			var c := classify(dd, DD)
			var a_nm := String(M.labels[i])
			var b_nm := String(M.labels[j])
			if not c.is_empty():
				c["shaft"] = a_nm
				c["hole"] = b_nm
				c["shaft_mm"] = snappedf(dd, 0.0001)
				c["hole_mm"] = snappedf(DD, 0.0001)
				c["clearance_um"] = snappedf((DD - dd) * 1000.0, 0.1)
				c["text"] = "%s in %s: diameter %s mm in a %s mm hole is the ISO 286 fit %s %d (%s), clearance %s to %s um by the table (this model: %s um)." % [
					a_nm, b_nm, _g(dd), _g(DD), c["class"], int(c["nominal"]), c["name"], _g(c["cmin_um"]), _g(c["cmax_um"]), _g(c["clearance_um"])]
				fits.append(c)
			else:
				var ne := nearest_fit(n, (DD - dd) * 1000.0)
				var adv := ""
				if not ne.is_empty():
					adv = " The nearest standard fit is %s %s (%s): hole %s to %s mm, shaft %s to %s mm, clearance %s to %s um." % [ne["class"], int(n), ne["name"],
						_g(n + float(ne["hole_um"][0]) / 1000.0), _g(n + float(ne["hole_um"][1]) / 1000.0), _g(n + float(ne["shaft_um"][0]) / 1000.0), _g(n + float(ne["shaft_um"][1]) / 1000.0), _g(ne["cmin_um"]), _g(ne["cmax_um"])]
				var ent := {"class": "", "shaft": a_nm, "hole": b_nm, "shaft_mm": snappedf(dd, 0.0001), "hole_mm": snappedf(DD, 0.0001), "clearance_um": snappedf((DD - dd) * 1000.0, 0.1), "nominal": n}
				ent["text"] = "%s in %s: %s mm in a %s mm hole (clearance %s um) is not a standard ISO 286 fit.%s" % [a_nm, b_nm, _g(dd), _g(DD), _g(ent["clearance_um"]), adv]
				fits.append(ent)
				W.append(_w("eng.fit", a_nm, String(ent["text"])))


static func _g(x: float) -> String:
	return ("%.4f" % x).rstrip("0").rstrip(".")


static func _bolts(M: PartFacts.Model, mat: String, W: Array, num: Dictionary) -> void:
	var rx := RegEx.new()
	rx.compile("[Mm](\\d+(?:\\.\\d+)?)")
	for i in M.n:
		if not _is_bolt(String(M.labels[i])):
			continue
		var ax := M.axis(i)
		if String(ax["kind"]) == "cubic":
			continue
		var a: Vector3 = ax["axis"]
		var c := M.centroid(i)
		var m := rx.search(String(M.labels[i]))
		var d := float(m.get_string(1)) if m != null else 2.0 * float(ax["radius"])
		var lo := float(ax["lo"])
		var hi := float(ax["hi"])
		var bite := {}
		var longest := 0.0
		for j in M.n:
			if j == i or M.box_gap(i, j) > 0.0:
				continue
			var P := M.tris_fine(j)
			var steps := int(ceil((hi - lo) / 0.25))
			var run := 0.0
			var best := 0.0
			var perp := a.cross(Vector3.UP if absf(a.y) < 0.9 else Vector3.RIGHT).normalized()
			for s in steps + 1:
				var t := lo + (hi - lo) * float(s) / float(maxi(steps, 1))
				# a point 0.45 d from the axis: inside the bolt's thread but outside a tap-drill hole (0.4 d), so it is in material only where the thread bites
				if PartFacts.inside(P, c + a * t + perp * (0.45 * d)):
					run += (hi - lo) / float(maxi(steps, 1))
					best = maxf(best, run)
				else:
					run = 0.0
			if best > longest:
				longest = best
				bite = {"name": String(M.labels[j])}
		var need: float = float(ENGAGE.get(mat, 1.0)) * d
		if longest > 0.0:
			if not num.has("bolts"):
				num["bolts"] = []
			num["bolts"].append({"bolt": String(M.labels[i]), "into": String(bite["name"]), "engaged_mm": snappedf(longest, 0.01), "needed_mm": need, "d_mm": d})
		if longest > 0.0 and longest < need - 0.01:
			W.append(_w("eng.bolt", String(M.labels[i]), "%s bites only %.1f mm into %s; a M%s bolt in %s needs %.1f mm (%.1f x its diameter). Use a longer bolt or a deeper thread." % [M.labels[i], longest, bite["name"], _g(d), mat, need, float(ENGAGE.get(mat, 1.0))]))


static func _beams(rec: Dictionary, M: PartFacts.Model, mat: String, kg: float, W: Array, num: Dictionary) -> void:
	var prop: Dictionary = MATERIAL[mat]
	var E := float(prop["E"]) * 1e9
	var sy := float(prop["yield"]) * 1e6
	var load_n: float = float(rec.get("load_n", 0.0))
	var P := load_n if load_n > 0.0 else kg * G
	num["load_n"] = snappedf(P, 0.001)
	for i in M.n:
		var ax := M.axis(i)
		var L := 0.0
		var b := 0.0
		var h := 0.0
		var round_sec := false
		if String(ax["kind"]) == "round":
			L = float(ax["len"])
			b = 2.0 * float(ax["radius"])
			h = b
			round_sec = true
		elif String(ax["kind"]) == "general" and (ax["dims"] as Array).size() == 3:
			var dm: Array = (ax["dims"] as Array).duplicate()
			dm.sort()
			L = float(dm[2])
			b = float(dm[1])   # the wider side
			h = float(dm[0])   # the thinner side: the load bends it this way (the weakest direction)
		else:
			var s3 := M.box(i).size
			var a3 := [s3.x, s3.y, s3.z]
			a3.sort()
			L = float(a3[2])
			b = float(a3[1])
			h = float(a3[0])
		if L < SLENDER * maxf(b, h) or h <= 0.0:
			continue
		var Lm := L * 1e-3
		var bm := b * 1e-3
		var hm := h * 1e-3
		var I: float
		var Z: float
		if round_sec:
			I = PI * pow(bm, 4) / 64.0
			Z = PI * pow(bm, 3) / 32.0
		else:
			I = bm * pow(hm, 3) / 12.0
			Z = bm * hm * hm / 6.0
		var sigma := P * Lm / Z
		var delta := P * pow(Lm, 3) / (3.0 * E * I)
		var nm := String(M.labels[i])
		if not num.has("beams"):
			num["beams"] = []
		num["beams"].append({"part": nm, "L_mm": L, "sigma_mpa": snappedf(sigma / 1e6, 0.01), "deflection_mm": snappedf(delta * 1e3, 0.001), "load_n": snappedf(P, 0.001)})
		if sigma > sy / SAFETY:
			W.append(_w("eng.stress", nm, "%s as a cantilever %.0f mm long, %.1f x %.1f mm, under %.1f N: bending stress %.0f MPa is over %.0f MPa (%s yield %.0f MPa / %.1f). Make it thicker or shorter." % [nm, L, b, h, P, sigma / 1e6, sy / SAFETY / 1e6, prop["name"], sy / 1e6, SAFETY]))
		if delta > Lm / DEFLECT_DIV:
			W.append(_w("eng.deflection", nm, "%s as a cantilever %.0f mm long, %.1f x %.1f mm, under %.1f N: the free end bends %.1f mm, more than length / %d = %.1f mm (%s, E %.0f GPa)." % [nm, L, b, h, P, delta * 1e3, int(DEFLECT_DIV), L / DEFLECT_DIV, prop["name"], E / 1e9]))


static func _draft(M: PartFacts.Model, W: Array) -> void:
	var lim := sin(deg_to_rad(DRAFT_DEG))
	for i in M.n:
		var T := M.tris(i)
		var area := 0.0
		for k in range(0, T.size() - 2, 3):
			var cr := (T[k + 1] - T[k]).cross(T[k + 2] - T[k])
			var ar := cr.length() * 0.5
			if ar < 1e-12:
				continue
			if absf(cr.normalized().y) < lim:
				area += ar
		if area >= DRAFT_MIN_MM2:
			W.append(_w("eng.draft", String(M.labels[i]), "%s has %.0f mm2 of wall with less than %d degree of draft along the pull direction (up): a moulded part will stick. Taper the walls 1 to 3 degrees." % [M.labels[i], area, int(DRAFT_DEG)]))


# ------------------------------------------------------------------------------------------------ agent_tools
## "part_warn": {} reads the report; {level: "print"} sets it; {mute: "eng.tips@"} / {unmute: ...} (one undo step each). Same report as the panel.
static func serve(T: Object, p: Dictionary) -> Dictionary:
	var rec: Dictionary = {}
	var live := false
	if p.get("part") is Dictionary:
		rec = Part.from_file(p["part"])
	else:
		rec = T.m.S.part
		live = true
	if rec.is_empty():
		return {"ok": false, "error": "there is no part: open one (Part workspace), or send {\"part\": {...}}"}
	var changed := false
	var plan: Array = []
	if p.has("level"):
		if not String(p["level"]) in LEVELS:
			return {"ok": false, "error": "level is one of %s" % str(LEVELS)}
		plan.append(["level", String(p["level"])])
	for k in ["mute", "unmute"]:
		if p.has(k):
			var ks: Array = p[k] if p[k] is Array else [p[k]]
			for key in ks:
				var probe := rec.duplicate(true)
				if not set_mute(probe, String(key), k == "mute"):
					return {"ok": false, "error": "a mute is \"<warning id>@<part>\" (\"*\" for all), e.g. \"eng.tips@\", \"look.no_name@Body 2\", \"print.overhang@*\"; ids: %s" % str(CODES.keys())}
				plan.append([k, String(key)])
	if not plan.is_empty():
		if live and T.m.has_method("_push_undo"):
			T.m._push_undo()   # one undo step for the whole call
		for st in plan:
			if st[0] == "level":
				set_level(rec, st[1])
			else:
				set_mute(rec, st[1], st[0] == "mute")
		changed = true
		if live and T.m.has_method("sync_part_warn"):
			T.m.sync_part_warn()
	var r := report(rec)
	r["changed"] = changed
	r["levels"] = LEVELS
	r["ids"] = CODES.keys()
	r["muted_keys"] = rec.get("warn_mute", [])
	return {"ok": true, "result": r}
