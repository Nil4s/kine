## part_assert.gd - PART ASSERTIONS (item 220): a blind agent writes checks about a modelled part like tests, one line each, and gets
## pass / fail with the worst miss in mm, deg or mm3 and where. Same design as body_assert.gd (N002): a small FIXED grammar (GRAMMAR; an
## unread line gets it back), one verdict per line, the numbers re-derivable from part_facts.gd's header.
##   "piston touches barrel clearance 0.0-0.2 mm"      "pushrod touches crankcase"        "body 5 inside body 3"
##   "no overlaps except pistons/barrels"              "count bodies like fin = 36"       "pipe 1 ends at cage 1 within 1 mm"
##   "axis of body 6 at 120 deg to axis of body 7 +-0.5"   "one solid"                    "all bodies above the floor"
## BODIES are named "body N" (1-based, the numbers part_facts prints) or by name: "piston" = every body whose name has "piston" in it,
## "piston 2" = the body named "Piston 2" (else the 2nd body with "piston" in its name). A name that matches several bodies is checked
## for EACH of them against the best partner among the other side's matches (the worst of those verdicts is the line's).
## WHAT EACH KIND MEASURES (mm, deg, mm3; a pass is miss <= 0 with 1e-9 slack):
##   inside      volume of A minus B (the kernel's cut), mm3: the part of A that sticks out; miss = that volume (exact);
##   touches     gap = the shortest distance between the two surfaces (PartFacts.tri_gap), mm; holds when gap <= TOUCH_MM (0.05) or they
##               overlap; miss = the gap. With "clearance a-b mm" the gap must lie in [a, b]: miss = max(a - gap, gap - b); an overlap of
##               more than HIT_MM3 mm3 is interference, which fails any clearance (miss = the overlap volume, mm3). "clearance at least x mm"
##               / "at most x mm" are the same with one end open;
##   distance    "A at least|at most D mm from B": the same gap against D;
##   overlaps    "no overlaps [except a/b, c/d]": every pair of bodies whose common volume is above HIT_MM3 (1 mm3), except the listed
##               name pairs (a name matches a body whose name contains it, either order); miss = the largest overlap, mm3;
##   count       "count bodies like W = N" (also >= <= > <, at least / at most / exactly): bodies whose name contains W; miss = how many off;
##   ends        "A ends at B within X mm": A's two end caps (its triangles within 2 % of A's length from each end along its axis) against B;
##               holds when either end is within X; miss = the nearer end's gap - X;
##   reaches     "A reaches B [within X mm]": a ray from each end of A's axis (the axis line through its centroid, out past the end cap) to the
##               first triangle of B it meets, mm (0 when that end cap already touches B); holds when the nearer end is within X (default
##               TOUCH_MM); miss = that distance - X. This is the "how far short is it" a drawing shows, along the rod, where `touches` is the
##               shortest distance in any direction;
##   axis        "axis of A at D deg to axis of B +-T" (T default 0.5): the angle between the two directed principal axes (PartFacts header:
##               directed away from the part's centre); miss = |angle - D| - T. "axis of A along x|y|z +-T": the angle between the axis LINE and
##               that world axis; miss = angle - T;
##   one solid   the bodies form one piece: joined when they overlap or touch (gap <= TOUCH_MM); miss = pieces - 1;
##   floor       "all bodies above the floor" / "<A> above the floor": the lowest point (y, mm) must be >= -0.01; miss = -lowest;
##   size        "<A> length|diameter|radius|volume = X [+-T]": the principal-axis length / 2 x radius / radius (PartFacts) or the kernel volume;
##               T default 0.1 mm (volume 0.1 %); miss = |value - X| - T;
##   ridges      "<A> has N fins|ridges|ribs": the number of separate raised bands at A's outermost radius along its axis (each band's tip is a
##               cylinder strip with two edge positions: the distinct axis positions of the vertices at that radius, divided by 2); miss = |count - N|.
## Saved assertions: the part record's "asserts" list of lines (Part.from_file keeps it); agent_tools part_assert {save: true} adds the lines that read.
class_name PartAssert
extends RefCounted

const EPS := 1e-9
const NUM := "(-?\\d+(?:\\.\\d+)?)"
const FLOOR_TOL := 0.01   # mm
const TOUCH_MM := PartFacts.TOUCH_MM
const GRAMMAR := [
	"One check per line. Bodies: 'body N' (1-based, as part_facts numbers them) or a name ('piston' = all bodies named piston, 'piston 2').",
	"  <A> inside <B>                                   e.g. body 5 inside body 3",
	"  <A> touches <B> [clearance a-b mm]               e.g. piston touches barrel clearance 0.0-0.2 mm   (also: clearance at least|at most x mm)",
	"  <A> at least|at most D mm from <B>               e.g. pushrod at most 2 mm from crankcase",
	"  no overlaps [except a/b, c/d]                    e.g. no overlaps except pistons/barrels",
	"  count bodies like <word> = N                     e.g. count bodies like fin = 36   (also >= <= > <, at least, at most)",
	"  <A> ends at <B> within X mm                      e.g. pipe 1 ends at cage 1 within 1 mm",
	"  <A> reaches <B> [within X mm]                    e.g. pushrod reaches crankcase   (the distance ALONG A's axis from either end to B)",
	"  axis of <A> at D deg to axis of <B> [+-T]        e.g. axis of body 6 at 120 deg to axis of body 7 +-0.5",
	"  axis of <A> along x|y|z [+-T]                    e.g. axis of crankshaft along z +-0.5",
	"  one solid                                        (every body touches or overlaps the others, directly or through a chain)",
	"  all bodies above the floor | <A> above the floor (lowest point y >= 0)",
	"  <A> length|diameter|radius|volume = X [+-T]      e.g. piston diameter = 105 +-0.1   (mm, volume mm3)",
	"  <A> has N fins|ridges|ribs                       e.g. body 9 has 12 fins",
	"Units: mm, deg, mm3. A miss is in mm, deg or mm3 and says which body or pair and where."]
const FILLER := ["the", "must", "should", "is", "are", "stays", "stay", "remains", "be", "always", "of the"]


static func _re(p: String) -> RegEx:
	return RegEx.create_from_string(p)


static func _bad(line: String, why: String) -> Dictionary:
	return {"ok": false, "line": line, "error": why, "grammar": GRAMMAR}


static func norm(line: String) -> String:
	var s := line.strip_edges().to_lower().replace("±", "+-").replace("+/-", "+-").replace("°", " deg").replace("mm³", "mm3")
	s = s.rstrip(".")
	s = s.replace(">=", " qqge ").replace("<=", " qqle ").replace("==", " qqeq ").replace("=", " = ")
	s = s.replace("qqge", ">=").replace("qqle", "<=").replace("qqeq", "==")
	var out := []
	for w in s.split(" ", false):
		if not w in FILLER:
			out.append(w)
	return " ".join(out)


## a body reference -> {"kind": "idx"|"name"|"all", ...}
static func ref(raw: String) -> Dictionary:
	var s := raw.strip_edges()
	if s in ["all bodies", "every body", "all", "bodies", "everything"]:
		return {"ok": true, "kind": "all", "text": "all bodies"}
	var m := _re("^(?:body|#)\\s*(\\d+)$").search(s)
	if m != null:
		return {"ok": true, "kind": "idx", "n": int(m.get_string(1)), "text": "body " + m.get_string(1)}
	if s == "":
		return {"ok": false, "error": "a body is missing"}
	var n := 0
	var words := s
	m = _re("^(.+?)\\s+(\\d+)$").search(s)
	if m != null:
		words = m.get_string(1)
		n = int(m.get_string(2))
	return {"ok": true, "kind": "name", "words": words, "n": n, "full": s, "text": s}


## the 0-based bodies a reference names: [] with an error text as the second element when none
static func resolve(M: PartFacts.Model, r: Dictionary) -> Array:
	match r["kind"]:
		"all":
			var a := []
			for i in M.n:
				a.append(i)
			return [a, ""]
		"idx":
			if int(r["n"]) < 1 or int(r["n"]) > M.n:
				return [[], "there is no body %d (the part has %d)" % [r["n"], M.n]]
			return [[int(r["n"]) - 1], ""]
	var full := String(r["full"]).to_lower()
	for i in M.n:
		if String(M.labels[i]).to_lower() == full:
			return [[i], ""]
	var matches := M.like(String(r["words"]))
	if matches.is_empty():
		return [[], "no body is named like '%s' (names: %s)" % [r["words"], ", ".join(M.labels.slice(0, 12)) + (", ..." if M.n > 12 else "")]]
	if int(r["n"]) > 0:
		if int(r["n"]) > matches.size():
			return [[], "only %d bodies are named like '%s'" % [matches.size(), r["words"]]]
		return [[matches[int(r["n"]) - 1]], ""]
	return [matches, ""]


static func _op(w: String) -> String:
	return "ge" if w in [">=", ">", "at least", "least", "more than", "over"] else "le" if w in ["<=", "<", "at most", "most", "less than", "under"] else "eq"


## one line -> {"ok", "line", "kind", ...} or {"ok": false, "error", "grammar"}
static func parse(line: String) -> Dictionary:
	var s := norm(line)
	if s == "":
		return _bad(line, "an empty line")
	var q := {"ok": true, "line": line}
	if s in ["one solid", "1 solid", "one piece", "single solid", "single piece", "one body"]:
		q["kind"] = "one"
		return q
	var m := _re("^no overlaps?(?:\\s+except\\s+(.+))?$").search(s)
	if m != null:
		var ex := []
		if m.get_string(1) != "":
			for part in m.get_string(1).replace(" and ", ",").split(",", false):
				var ab := part.strip_edges().split("/", false)
				if ab.size() != 2:
					return _bad(line, "'except' wants name pairs like pistons/barrels (got '%s')" % part.strip_edges())
				ex.append([ab[0].strip_edges(), ab[1].strip_edges()])
		q.merge({"kind": "overlaps", "except": ex})
		return q
	m = _re("^count bodies like (.+?)\\s*(>=|<=|==|=|>|<|at least|at most|exactly)\\s*" + NUM + "$").search(s)
	if m != null:
		q.merge({"kind": "count", "word": m.get_string(1).strip_edges(), "op": _op(m.get_string(2)), "n": int(float(m.get_string(3)))})
		return q
	m = _re("^axis (?:of )?(.+?) at " + NUM + "\\s*(?:deg|degrees)?\\s*to axis (?:of )?(.+?)(?:\\s*\\+-\\s*" + NUM + "\\s*(?:deg|degrees)?)?$").search(s)
	if m != null:
		var ra := ref(m.get_string(1))
		var rb := ref(m.get_string(3))
		if not ra["ok"] or not rb["ok"]:
			return _bad(line, String(ra.get("error", rb.get("error", ""))))
		q.merge({"kind": "axis_angle", "a": ra, "b": rb, "deg": float(m.get_string(2)), "tol": float(m.get_string(4)) if m.get_string(4) != "" else 0.5})
		return q
	m = _re("^axis (?:of )?(.+?) along ([xyz])(?:\\s*\\+-\\s*" + NUM + "\\s*(?:deg|degrees)?)?$").search(s)
	if m != null:
		var ra2 := ref(m.get_string(1))
		if not ra2["ok"]:
			return _bad(line, ra2["error"])
		q.merge({"kind": "axis_along", "a": ra2, "w": m.get_string(2), "tol": float(m.get_string(3)) if m.get_string(3) != "" else 0.5})
		return q
	m = _re("^(.+?) reaches (.+?)(?:\\s+within " + NUM + "\\s*mm)?$").search(s)
	if m != null:
		var rr1 := ref(m.get_string(1))
		var rr2 := ref(m.get_string(2))
		if not rr1["ok"] or not rr2["ok"]:
			return _bad(line, String(rr1.get("error", rr2.get("error", ""))))
		q.merge({"kind": "reaches", "a": rr1, "b": rr2, "x": float(m.get_string(3)) if m.get_string(3) != "" else TOUCH_MM})
		return q
	m = _re("^(.+?) ends at (.+?) within " + NUM + "\\s*mm$").search(s)
	if m != null:
		var re1 := ref(m.get_string(1))
		var re2 := ref(m.get_string(2))
		if not re1["ok"] or not re2["ok"]:
			return _bad(line, String(re1.get("error", re2.get("error", ""))))
		q.merge({"kind": "ends", "a": re1, "b": re2, "x": float(m.get_string(3))})
		return q
	m = _re("^(.+?) has (\\d+) (?:fins?|ridges?|ribs?|bands?)(?: along axis)?$").search(s)
	if m != null:
		var rr := ref(m.get_string(1))
		if not rr["ok"]:
			return _bad(line, rr["error"])
		q.merge({"kind": "ridges", "a": rr, "n": int(m.get_string(2))})
		return q
	m = _re("^(.+?) (length|diameter|radius|volume) (?:=|==) " + NUM + "\\s*(?:mm3|mm)?(?:\\s*\\+-\\s*" + NUM + "\\s*(?:mm3|mm|%)?)?$").search(s)
	if m != null:
		var rs := ref(m.get_string(1))
		if not rs["ok"]:
			return _bad(line, rs["error"])
		var what := m.get_string(2)
		q.merge({"kind": "size", "a": rs, "what": what, "x": float(m.get_string(3)), "tol": float(m.get_string(4)) if m.get_string(4) != "" else (0.0 if what == "volume" else 0.1)})
		return q
	m = _re("^(.+?) above floor$").search(s)
	if m != null:
		var rf := ref(m.get_string(1))
		if not rf["ok"]:
			return _bad(line, rf["error"])
		q.merge({"kind": "floor", "a": rf})
		return q
	m = _re("^(.+?) (at least|at most|no closer than|no further than|within) " + NUM + "\\s*mm (?:away )?(?:from|of|to) (.+)$").search(s)
	if m != null:
		var rd1 := ref(m.get_string(1))
		var rd2 := ref(m.get_string(4))
		if not rd1["ok"] or not rd2["ok"]:
			return _bad(line, String(rd1.get("error", rd2.get("error", ""))))
		var w := m.get_string(2)
		q.merge({"kind": "distance", "a": rd1, "b": rd2, "op": "ge" if w in ["at least", "no closer than"] else "le", "x": float(m.get_string(3))})
		return q
	m = _re("^(.+?) (?:touches|touch|contacts|meets)\\s+(.+?)(?:\\s+clearance\\s+(?:" + NUM + "\\s*(?:-|to)\\s*" + NUM + "|(at least|at most|min|max)\\s*" + NUM + ")\\s*mm)?$").search(s)
	if m != null:
		var rt1 := ref(m.get_string(1))
		var rt2 := ref(m.get_string(2))
		if not rt1["ok"] or not rt2["ok"]:
			return _bad(line, String(rt1.get("error", rt2.get("error", ""))))
		q.merge({"kind": "touches", "a": rt1, "b": rt2, "lo": null, "hi": null})
		if m.get_string(3) != "":
			q["lo"] = minf(float(m.get_string(3)), float(m.get_string(4)))
			q["hi"] = maxf(float(m.get_string(3)), float(m.get_string(4)))
		elif m.get_string(5) != "":
			if m.get_string(5) in ["at least", "min"]:
				q["lo"] = float(m.get_string(6))
			else:
				q["hi"] = float(m.get_string(6))
		return q
	m = _re("^(.+?) inside (.+)$").search(s)
	if m != null:
		var ri1 := ref(m.get_string(1))
		var ri2 := ref(m.get_string(2))
		if not ri1["ok"] or not ri2["ok"]:
			return _bad(line, String(ri1.get("error", ri2.get("error", ""))))
		q.merge({"kind": "inside", "a": ri1, "b": ri2})
		return q
	return _bad(line, "I can't read '%s'" % line.strip_edges())


# ------------------------------------------------------------------------------------------------ running
## check lines on a part record -> {"pass", "passed", "failed", "unread", "bodies", "results": [...]}
static func run(rec: Dictionary, lines: Array) -> Dictionary:
	var M := PartFacts.build(rec)
	if not M.ok:
		var res := []
		for l in lines:
			res.append({"line": String(l), "ok": true, "pass": false, "kind": "part", "say": "FAIL  %s:  %s" % [String(l).strip_edges(), M.why], "miss": {"value": null, "unit": "", "where": M.why}})
		return {"pass": false, "passed": 0, "failed": lines.size(), "unread": 0, "bodies": 0, "results": res, "error": M.why}
	var r := run_on(M, lines)
	M.release()
	return r


static func run_on(M: PartFacts.Model, lines: Array) -> Dictionary:
	var results := []
	var passed := 0
	var failed := 0
	var unread := 0
	for l in lines:
		var q := parse(String(l))
		if not q["ok"]:
			unread += 1
			results.append({"line": String(l), "ok": false, "pass": false, "error": q["error"], "grammar": GRAMMAR})
			continue
		var r := judge(M, q)
		results.append(r)
		if r["pass"]:
			passed += 1
		else:
			failed += 1
	return {"pass": failed == 0 and unread == 0, "passed": passed, "failed": failed, "unread": unread, "bodies": M.n, "results": results}


static func _nm(M: PartFacts.Model, i: int) -> String:
	return "#%d %s" % [i + 1, M.labels[i]]


static func _out(q: Dictionary, ok: bool, miss: float, unit: String, said: String, where: String, extra := {}) -> Dictionary:
	var r := {"line": q["line"], "ok": true, "pass": ok, "kind": q["kind"], "worst": {"miss": snappedf(miss, 0.001), "unit": unit, "where": where}}
	r.merge(extra)
	if not ok:
		r["miss"] = {"value": snappedf(miss, 0.001), "unit": unit, "where": where}
	r["say"] = ("PASS  " if ok else "FAIL  ") + String(q["line"]).strip_edges() + ":  " + said + \
		("" if ok else "; misses by %s %s%s" % [_n(miss), unit, (" at " + where) if where != "" else ""])
	return r


static func _n(v: float) -> String:
	if is_inf(v):
		return "inf"
	return "%.3f" % v if absf(v) < 1000.0 else "%.0f" % v


static func _fail(q: Dictionary, why: String) -> Dictionary:
	return {"line": q["line"], "ok": true, "pass": false, "kind": q["kind"], "miss": {"value": null, "unit": "", "where": why}, "say": "FAIL  %s:  %s" % [String(q["line"]).strip_edges(), why]}


static func judge(M: PartFacts.Model, q: Dictionary) -> Dictionary:
	var A: Array = []
	var B: Array = []
	if q.has("a"):
		var ra := resolve(M, q["a"])
		if (ra[0] as Array).is_empty():
			return _fail(q, ra[1])
		A = ra[0]
	if q.has("b"):
		var rb := resolve(M, q["b"])
		if (rb[0] as Array).is_empty():
			return _fail(q, rb[1])
		B = rb[0]
	match q["kind"]:
		"one":
			var comps := M.components()
			var miss := float(comps.size() - 1)
			var said := "%d bodies in %d piece%s" % [M.n, comps.size(), "" if comps.size() == 1 else "s"]
			var where := ""
			if comps.size() > 1:
				where = "pieces " + "; ".join(comps.map(func(g): return "{" + ",".join((g as Array).map(func(i): return str(int(i) + 1))) + "}"))
				said += " (" + where + ")"
			return _out(q, comps.size() <= 1, miss, "pieces", said, where, {"pieces": comps.size()})
		"count":
			var w: String = q["word"]
			var cnt := M.like(w).size()
			var ok := (cnt == int(q["n"])) if q["op"] == "eq" else (cnt >= int(q["n"])) if q["op"] == "ge" else (cnt <= int(q["n"]))
			var miss2 := 0.0 if ok else float(absi(cnt - int(q["n"])))
			return _out(q, ok, miss2, "bodies", "%d bodies are named like '%s'" % [cnt, w], "bodies " + ",".join(M.like(w).map(func(i): return str(int(i) + 1))), {"count": cnt})
		"overlaps":
			var worst := 0.0
			var wp := ""
			var listed := []
			for pr in M.near_pairs(1e-6):   # s233: only the pairs whose boxes meet (overlap() is 0 for the others), in the same (i, j) order
				var i: int = pr[0]
				var j: int = pr[1]
				var o := M.overlap(i, j)
				if o <= PartFacts.HIT_MM3 or _excepted(M, q["except"], i, j):
					continue
				listed.append([i, j, o])
				if o > worst:
					worst = o
					wp = "%s x %s" % [_nm(M, i), _nm(M, j)]
			listed.sort_custom(func(x, y): return x[2] > y[2])
			var said2 := "no unexcepted overlap" if listed.is_empty() else "%d overlap%s: %s%s" % [listed.size(), "" if listed.size() == 1 else "s",
				"; ".join(listed.slice(0, 5).map(func(t): return "%s x %s %.0f mm3" % [_nm(M, t[0]), _nm(M, t[1]), t[2]])), "" if listed.size() <= 5 else "; +%d more" % (listed.size() - 5)]
			return _out(q, listed.is_empty(), worst, "mm3", said2, wp, {"overlaps": listed.map(func(t): return {"a": int(t[0]) + 1, "b": int(t[1]) + 1, "mm3": snappedf(t[2], 0.01)})})
		"inside":
			var wm := -1.0
			var who := ""
			var said3 := ""
			for a in A:
				var rest: int = M.ids[a]
				var owned := []
				for b in B:
					if b == a:
						continue
					var c: int = KCadHelper.cut(rest, int(M.ids[b]))
					if c != 0:
						owned.append(c)
						rest = c
				var v: float = KCadHelper.vol(rest) / (PartFacts.MM * PartFacts.MM * PartFacts.MM)
				for c2 in owned:
					KCadHelper.rel(int(c2))
				if v <= PartFacts.HIT_MM3 * 1e-3:
					v = 0.0
				if v > wm:
					wm = v
					who = _nm(M, a)
					said3 = "%.0f mm3 of %s lies outside %s" % [v, _nm(M, a), ", ".join(B.slice(0, 3).map(func(b): return _nm(M, b)))]
			return _out(q, wm <= 0.0, wm, "mm3", said3, who if wm > 0.0 else "")
		"touches", "distance":
			return _judge_gap(M, q, A, B)
		"ends":
			return _judge_ends(M, q, A, B)
		"reaches":
			return _judge_reaches(M, q, A, B)
		"axis_angle", "axis_along":
			return _judge_axis(M, q, A, B)
		"floor":
			var low := INF
			var lw := ""
			for a in A:
				var y := M.box(a).position.y
				if y < low:
					low = y
					lw = _nm(M, a)
			var ok2 := low >= -FLOOR_TOL
			return _out(q, ok2, -low if not ok2 else 0.0, "mm", "the lowest point is y = %.3f mm (%s)" % [low, lw], lw if not ok2 else "")
		"size":
			return _judge_size(M, q, A)
		"ridges":
			return _judge_ridges(M, q, A)
	return _fail(q, "no judge for " + String(q["kind"]))


static func _excepted(M: PartFacts.Model, ex: Array, i: int, j: int) -> bool:
	var li := String(M.labels[i]).to_lower()
	var lj := String(M.labels[j]).to_lower()
	for p in ex:
		var x := String(p[0])
		var y := String(p[1])
		var xs := x.trim_suffix("s") if x.length() > 3 else x
		var ys := y.trim_suffix("s") if y.length() > 3 else y
		if (li.contains(x) or li.contains(xs)) and (lj.contains(y) or lj.contains(ys)):
			return true
		if (lj.contains(x) or lj.contains(xs)) and (li.contains(y) or li.contains(ys)):
			return true
	return false


## touches / clearance / at least|at most D from: for each A the best partner in B; the worst of those is the verdict
static func _judge_gap(M: PartFacts.Model, q: Dictionary, A: Array, B: Array) -> Dictionary:
	var worst_miss := -INF
	var said := ""
	var where := ""
	var gap_v := 0.0
	var interf := false
	for a in A:
		var best_miss := INF
		var best_say := ""
		var best_where := ""
		var best_gap := 0.0
		var best_int := false
		for b in B:
			if b == a:
				continue
			var ov := M.overlap(a, b)
			var eg: Dictionary = M.exact_gap(a, b)
			var g: float = eg["gap"]
			var miss := 0.0
			var said_i := ""
			var is_int := false
			if q["kind"] == "touches":
				var lo: Variant = q["lo"]
				var hi: Variant = q["hi"]
				if lo == null and hi == null:
					miss = 0.0 if g <= PartFacts.TOUCH_MM else g
					said_i = "the gap between %s and %s is %s mm%s" % [_nm(M, a), _nm(M, b), PartFacts._gap_s(g), (" (overlap %.0f mm3)" % ov) if ov > PartFacts.HIT_MM3 else ""]
				else:
					if ov > PartFacts.HIT_MM3:
						miss = ov
						is_int = true
						said_i = "%s and %s INTERFERE by %.1f mm3 (clearance %s)" % [_nm(M, a), _nm(M, b), ov, _range_s(lo, hi)]
					else:
						miss = maxf((float(lo) - g) if lo != null else -INF, (g - float(hi)) if hi != null else -INF)
						said_i = "the clearance between %s and %s is %s mm (wanted %s)" % [_nm(M, a), _nm(M, b), PartFacts._gap_s(g), _range_s(lo, hi)]
			else:
				miss = (float(q["x"]) - g) if q["op"] == "ge" else (g - float(q["x"]))
				said_i = "the gap between %s and %s is %s mm" % [_nm(M, a), _nm(M, b), PartFacts._gap_s(g)]
			if miss < best_miss:
				best_miss = miss
				best_say = said_i
				best_gap = g
				best_int = is_int
				best_where = "%s / %s at %s" % [_nm(M, a), _nm(M, b), PartFacts._v3(_mid(M, a, b))]
		if best_miss > worst_miss:
			worst_miss = best_miss
			said = best_say
			where = best_where
			gap_v = best_gap
			interf = best_int
	var ok := worst_miss <= EPS
	var unit := "mm3" if interf else "mm"
	return _out(q, ok, maxf(worst_miss, 0.0) if not ok else worst_miss, unit, said, where, {"gap_mm": snappedf(gap_v, 0.001)})


static func _range_s(lo: Variant, hi: Variant) -> String:
	if lo != null and hi != null:
		return "%s-%s mm" % [str(snappedf(float(lo), 0.0001)), str(snappedf(float(hi), 0.0001))]
	return ("at least %s mm" % str(snappedf(float(lo), 0.0001))) if lo != null else ("at most %s mm" % str(snappedf(float(hi), 0.0001)))


## the middle of the straight line between the two bodies' closest triangle corners: a place to look at (mm)
static func _mid(M: PartFacts.Model, a: int, b: int) -> Vector3:
	var info: Dictionary = M.exact_gap(a, b)
	if info.has("a"):
		return ((info["a"] as Vector3) + (info["b"] as Vector3)) * 0.5
	return (M.box(a).get_center() + M.box(b).get_center()) * 0.5


static func _judge_axis(M: PartFacts.Model, q: Dictionary, A: Array, B: Array) -> Dictionary:
	var worst := -INF
	var said := ""
	var where := ""
	var val := 0.0
	for a in A:
		var ax: Dictionary = M.axis(a)
		if ax["kind"] == "cubic":
			return _fail(q, "%s has no axis (all three principal moments are equal: it is cubic)" % _nm(M, a))
		var best := INF
		var bs := ""
		var bv := 0.0
		var bw := ""
		var partners := B if q["kind"] == "axis_angle" else [-1]
		for b in partners:
			if b == a:
				continue
			var ang := 0.0
			var miss := 0.0
			var s2 := ""
			if q["kind"] == "axis_angle":
				var bx: Dictionary = M.axis(b)
				if bx["kind"] == "cubic":
					return _fail(q, "%s has no axis (cubic)" % _nm(M, b))
				ang = rad_to_deg(acos(clampf((ax["axis"] as Vector3).dot(bx["axis"] as Vector3), -1.0, 1.0)))
				miss = absf(ang - float(q["deg"])) - float(q["tol"])
				s2 = "the axes of %s %s and %s %s are %.3f deg apart (wanted %s +-%s)" % [_nm(M, a), PartFacts._u3(ax["axis"]), _nm(M, b), PartFacts._u3(bx["axis"]), ang, str(q["deg"]), str(q["tol"])]
				bw = "%s / %s" % [_nm(M, a), _nm(M, b)]
			else:
				var wv := Vector3(1, 0, 0) if q["w"] == "x" else Vector3(0, 1, 0) if q["w"] == "y" else Vector3(0, 0, 1)
				var d := absf((ax["axis"] as Vector3).dot(wv))
				ang = rad_to_deg(acos(clampf(d, 0.0, 1.0)))
				miss = ang - float(q["tol"])
				s2 = "the axis of %s %s is %.3f deg from the %s axis (allowed %s)" % [_nm(M, a), PartFacts._u3(ax["axis"]), ang, q["w"], str(q["tol"])]
				bw = _nm(M, a)
			if miss < best:
				best = miss
				bs = s2
				bv = ang
		if best > worst:
			worst = best
			said = bs
			where = bw
			val = bv
	return _out(q, worst <= EPS, maxf(worst, 0.0), "deg", said, where, {"angle_deg": snappedf(val, 0.001)})


static func _judge_ends(M: PartFacts.Model, q: Dictionary, A: Array, B: Array) -> Dictionary:
	var worst := -INF
	var said := ""
	var where := ""
	for a in A:
		var ax: Dictionary = M.axis(a)
		var dir: Vector3 = ax["axis"]
		if ax["kind"] == "cubic":
			dir = Vector3(0, 1, 0)
		var c := M.centroid(a)
		var T := M.tris_fine(a)
		var lo: float = ax["lo"] if ax["kind"] != "cubic" else -1e9
		var hi: float = ax["hi"] if ax["kind"] != "cubic" else 1e9
		if ax["kind"] == "cubic":
			lo = INF
			hi = -INF
			for p in T:
				lo = minf(lo, (p - c).dot(dir))
				hi = maxf(hi, (p - c).dot(dir))
		var span := hi - lo
		var e_lo := PackedVector3Array()
		var e_hi := PackedVector3Array()
		for t in range(0, T.size() - 2, 3):
			var al0 := (T[t] - c).dot(dir)
			var al1 := (T[t + 1] - c).dot(dir)
			var al2 := (T[t + 2] - c).dot(dir)
			var mn := minf(al0, minf(al1, al2))
			var mx := maxf(al0, maxf(al1, al2))
			if mn <= lo + 0.02 * span:
				e_lo.append_array(PackedVector3Array([T[t], T[t + 1], T[t + 2]]))
			if mx >= hi - 0.02 * span:
				e_hi.append_array(PackedVector3Array([T[t], T[t + 1], T[t + 2]]))
		var best := INF
		var bs := ""
		var ends := [e_lo, e_hi]
		for e in 2:
			for b in B:
				if b == a:
					continue
				var info := {}
				var g: float = PartFacts.tri_gap(ends[e], M.tris_fine(b), INF, info)
				if g > 0.0 and M.overlap(a, b) > PartFacts.HIT_MM3:   # the end cap may lie inside B (a pipe pushed into a head): then it is 0 away
					var cs := Vector3.ZERO
					for pt in (ends[e] as PackedVector3Array):
						cs += pt
					cs /= float(maxi((ends[e] as PackedVector3Array).size(), 1))
					if PartFacts.inside(M.tris_fine(b), cs):
						g = 0.0
						info = {"a": cs, "b": cs}
				var miss := g - float(q["x"])
				if miss < best:
					best = miss
					var pt := ((info["a"] as Vector3) + (info["b"] as Vector3)) * 0.5 if info.has("a") else Vector3.ZERO
					bs = "the %s end of %s is %s mm from %s (allowed %s)" % ["far" if e == 1 else "near", _nm(M, a), PartFacts._gap_s(g), _nm(M, b), str(q["x"])]
					where = "%s at %s" % [_nm(M, a), PartFacts._v3(pt)]
		if best > worst:
			worst = best
			said = bs
	return _out(q, worst <= EPS, maxf(worst, 0.0), "mm", said, where)


static func _judge_reaches(M: PartFacts.Model, q: Dictionary, A: Array, B: Array) -> Dictionary:
	var worst := -INF
	var said := ""
	var where := ""
	for a in A:
		var ax: Dictionary = M.axis(a)
		if ax["kind"] == "cubic":
			return _fail(q, "%s has no axis to reach along" % _nm(M, a))
		var dir: Vector3 = ax["axis"]
		var c := M.centroid(a)
		var span: float = float(ax["hi"]) - float(ax["lo"])
		var T := M.tris_fine(a)
		var caps := [PackedVector3Array(), PackedVector3Array()]
		var e_lo := PackedVector3Array()
		var e_hi := PackedVector3Array()
		for t in range(0, T.size() - 2, 3):
			var al := [(T[t] - c).dot(dir), (T[t + 1] - c).dot(dir), (T[t + 2] - c).dot(dir)]
			if minf(al[0], minf(al[1], al[2])) <= float(ax["lo"]) + 0.02 * span:
				e_lo.append_array(PackedVector3Array([T[t], T[t + 1], T[t + 2]]))
			if maxf(al[0], maxf(al[1], al[2])) >= float(ax["hi"]) - 0.02 * span:
				e_hi.append_array(PackedVector3Array([T[t], T[t + 1], T[t + 2]]))
		var starts := [c + dir * float(ax["lo"]), c + dir * float(ax["hi"])]
		var dirs := [-dir, dir]
		var ends := [e_lo, e_hi]
		var best := INF
		var bs := ""
		var bw := ""
		for e in 2:
			for b in B:
				if b == a:
					continue
				var d := INF
				if PartFacts.tri_gap(ends[e], M.tris_fine(b), PartFacts.TOUCH_MM) <= PartFacts.TOUCH_MM or PartFacts.inside(M.tris_fine(b), starts[e]):
					d = 0.0
				else:
					d = PartFacts.ray_hit(M.tris_fine(b), starts[e], dirs[e])
				if d < best:
					best = d
					bs = "the %s end of %s is %s mm from %s along its axis %s" % ["far" if e == 1 else "near", _nm(M, a), "no hit" if is_inf(d) else PartFacts._gap_s(d), _nm(M, b), PartFacts._u3(dirs[e])]
					bw = "%s end at %s" % [_nm(M, a), PartFacts._v3(starts[e])]
		var miss := best - float(q["x"])
		if miss > worst:
			worst = miss
			said = bs
			where = bw
	return _out(q, worst <= EPS, maxf(worst, 0.0) if not is_inf(worst) else INF, "mm", said, where)


static func _judge_size(M: PartFacts.Model, q: Dictionary, A: Array) -> Dictionary:
	var worst := -INF
	var said := ""
	var where := ""
	for a in A:
		var v := 0.0
		var tol: float = q["tol"]
		var ax: Dictionary = M.axis(a)
		match q["what"]:
			"volume":
				v = M.vol_mm3[a]
				tol = float(q["tol"]) if float(q["tol"]) > 0.0 else absf(float(q["x"])) * 0.001   # default 0.1 %
			"length":
				v = ax["len"]
			"diameter":
				v = 2.0 * float(ax["radius"])
			"radius":
				v = ax["radius"]
		var miss := absf(v - float(q["x"])) - tol
		if miss > worst:
			worst = miss
			said = "%s %s is %.4f %s (wanted %s +-%s)" % [_nm(M, a), q["what"], v, "mm3" if q["what"] == "volume" else "mm", str(q["x"]), str(snappedf(tol, 0.0001))]
			where = _nm(M, a)
	return _out(q, worst <= EPS, maxf(worst, 0.0), "mm3" if q["what"] == "volume" else "mm", said, where)


## raised bands along the axis: the tip faces at the body's outermost radius. A band's tip is a cylinder strip whose vertices sit at its
## two edges, so the axis positions (0.01 mm) of the vertices within 0.5 % of the largest radius come in pairs: bands = positions / 2
static func ridge_count(M: PartFacts.Model, a: int) -> int:
	var ax: Dictionary = M.axis(a)
	var dir: Vector3 = ax["axis"]
	var c := M.centroid(a)
	var rmax := 0.0
	for p in M.tris(a):
		var q: Vector3 = p - c
		rmax = maxf(rmax, (q - dir * q.dot(dir)).length())
	var at := {}
	for p in M.tris(a):
		var q2: Vector3 = p - c
		var al := q2.dot(dir)
		if (q2 - dir * al).length() >= rmax * 0.995:
			at[roundi(al * 100.0)] = true
	var keys := at.keys()
	keys.sort()
	var merged := 0
	var last := -1000000
	for k in keys:
		if int(k) - last > 1:
			merged += 1
		last = int(k)
	return merged / 2


static func _judge_ridges(M: PartFacts.Model, q: Dictionary, A: Array) -> Dictionary:
	var worst := -INF
	var said := ""
	var where := ""
	var cnt := 0
	for a in A:
		if M.axis(a)["kind"] == "cubic":
			return _fail(q, "%s has no axis to count along" % _nm(M, a))
		var c := ridge_count(M, a)
		var miss := float(absi(c - int(q["n"])))
		if miss > worst:
			worst = miss
			cnt = c
			said = "%s has %d raised band%s along its axis (wanted %d)" % [_nm(M, a), c, "" if c == 1 else "s", q["n"]]
			where = _nm(M, a)
	return _out(q, worst <= EPS, maxf(worst, 0.0), "bands", said, where, {"count": cnt})


## the saved lines: text only, trimmed, empty ones dropped
static func from_file(d: Variant) -> Array:
	var out := []
	if d is Array:
		for l in d:
			if l is String and String(l).strip_edges() != "":
				out.append(String(l).strip_edges())
	return out


## thin doors to the kernel (the preloaded script, as part.gd does)
class KCadHelper:
	const K := preload("res://scripts/kcad.gd")
	static func cut(a: int, b: int) -> int:
		return K.cut(a, b)
	static func vol(a: int) -> float:
		return K.volume(a) if a != 0 else 0.0
	static func rel(a: int) -> void:
		K.release(a)


## THE SERVE DOOR (agent_tools.gd "part_facts" / "part_assert", the CLI, the AI box): the record is {part: {...}} given, {path: a part
## file or a scene file with a "part"} read, or else the live part on screen (m.S.part). part_facts {cap?, near_mm?} -> {lines, ...};
## part_assert {lines: [...]} checks them; no lines = the record's saved "asserts"; {save: true} also keeps the lines that read in the
## record's "asserts" (the live part: one undo step; a path: the file is rewritten only in scenes/_wip or outside the project);
## {clear: true} drops the saved ones. -> {"ok": true, "result": {...}} or {"ok": false, "error": "...", "grammar"?}
static func serve(T: Object, method: String, p: Dictionary) -> Dictionary:
	var rec: Dictionary = {}
	var src := "live"
	var path := ""
	var whole: Dictionary = {}
	if p.get("part") is Dictionary:
		rec = Part.from_file(p["part"])
		if (p["part"] as Dictionary).get("asserts") is Array:
			rec["asserts"] = from_file(p["part"]["asserts"])
		src = "given"
	elif String(p.get("path", "")) != "":
		path = AgentTools.res(String(p["path"]))
		if not FileAccess.file_exists(path):
			return {"ok": false, "error": "no such file: %s (a part file, or a scene file with a part)" % p["path"]}
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (d is Dictionary):
			return {"ok": false, "error": "%s is not a JSON file" % p["path"]}
		whole = d
		var raw: Dictionary = d if (d as Dictionary).has("features") else (d as Dictionary).get("part", {})
		rec = Part.from_file(raw)
		if raw.get("asserts") is Array:
			rec["asserts"] = from_file(raw["asserts"])
		src = "file"
	else:
		var live: Dictionary = T.m.S.part
		rec = live
		src = "live"
	if rec.is_empty():
		return {"ok": false, "error": "there is no part: open one (Part workspace), or send {\"path\": \"part.json\"} or {\"part\": {...}}"}
	if method == "part_facts":
		var f := PartFacts.facts(rec, p)
		if not f["ok"]:
			return {"ok": false, "error": String(f["error"])}
		f["asserts"] = from_file(rec.get("asserts", []))
		return {"ok": true, "result": f}
	if bool(p.get("clear", false)):
		rec["asserts"] = []
	var al: Variant = p.get("lines", rec.get("asserts", []))
	if not (al is Array) or not (al as Array).all(func(s): return s is String):
		return {"ok": false, "error": "part_assert needs {\"lines\": [\"piston touches barrel clearance 0.0-0.2 mm\", ...]}", "grammar": GRAMMAR}
	var r := run(rec, al)
	if bool(p.get("save", false)) or bool(p.get("clear", false)):
		var saved: Array = from_file(rec.get("asserts", []))
		if bool(p.get("save", false)):
			for x in r["results"]:
				if x["ok"] and not String(x["line"]).strip_edges() in saved:
					saved.append(String(x["line"]).strip_edges())
		if src == "live":
			if T.m.has_method("_push_undo"):
				T.m._push_undo()
			if saved.is_empty():
				T.m.S.part.erase("asserts")
			else:
				T.m.S.part["asserts"] = saved
		elif src == "file":
			var why: String = T.out_refused(path)
			if why != "":
				r["save_refused"] = why
			else:
				var tgt: Dictionary = whole if whole.has("features") else whole["part"]
				if saved.is_empty():
					tgt.erase("asserts")
				else:
					tgt["asserts"] = saved
				var fw := FileAccess.open(path, FileAccess.WRITE)
				if fw != null:
					fw.store_string(JSON.stringify(whole, "\t"))
					fw.close()
		r["saved"] = saved
	else:
		r["saved"] = from_file(rec.get("asserts", []))
	if r["unread"] > 0:
		r["grammar"] = GRAMMAR
	return {"ok": true, "result": r}
