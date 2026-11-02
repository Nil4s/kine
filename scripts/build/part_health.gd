class_name PartHealth
extends RefCounted
## W02: sketch health. Reads a sketch's rules and sizes and says, in plain words and per shape, whether it is
##   "free"    : something can still move (n free = how many independent ways, not counting sliding the whole drawing),
##   "defined" : fully defined (nothing can move but the whole drawing as one piece),
##   "over"    : over-constrained (rules that cannot all hold; the clashing ones are named and marked).
## It only READS: it works on copies and never changes the sketch, and Part.solve / con_put / set_dim_held are untouched.
## Lines are counted from the solver's own residuals (Part._res_all): the Jacobian's rank at the solved sketch gives the free
## count; one rule that cannot hold is found by dropping each rule in turn and solving again. Rectangles (width, height) and
## circles (radius) count their own sizes; arcs and splines are drawn as free.

const FREE_C := Color("#73BFFF")   # same blue as before: a shape nothing pins stays the colour it always was
const DEFINED_C := Color("#4cd964")
const OVER_C := Color("#ff3b3b")
const CLASH_C := Color("#ff9f0a")

const TOL := 1e-7   # rank tolerance on the Jacobian (central differences of doubles)


## {"state": "free"|"defined"|"over", "free": int, "ent": {i: "free"|"defined"|"over"}, "clash": [names], "clash_cons": [ci],
##  "clash_dims": [di], "text": plain words}
static func analyze(sk: Dictionary) -> Dictionary:
	var ents: Array = sk.get("ents", [])
	var out := {"state": "free", "free": 0, "ent": {}, "clash": [], "clash_cons": [], "clash_dims": [], "text": ""}
	if ents.is_empty():
		out["text"] = "nothing drawn yet"
		return out
	var work: Dictionary = sk.duplicate(true)
	var worst := Part.solve(work)
	var over := worst > Part.CON_TOL
	var line_free := 0
	var ent_free := {}
	if over:
		_clash(sk, out)
		work = sk.duplicate(true)   # the sketch as drawn: no number of the solve is trusted when it cannot hold
	else:
		var r := _line_freedom(work)
		line_free = int(r["free"])
		ent_free = r["ent"]
	var free := line_free
	var dims: Array = sk.get("dims", [])
	for i in ents.size():
		var e: Dictionary = ents[i]
		var n := 0
		match String(e.get("k", "")):
			"rect":
				n = 2 - (1 if _has_dim(dims, i, "w") else 0) - (1 if _has_dim(dims, i, "h") else 0)
			"circle":
				n = 1 - (1 if _has_dim(dims, i, "r") else 0)
			"line":
				n = int(ent_free.get(i, 1 if over else 0))
			_:
				n = 1
		if String(e.get("k", "")) in ["rect", "circle"]:
			free += n
		(out["ent"] as Dictionary)[i] = "free" if n > 0 else "defined"
	if over:
		for i in ents.size():
			if String(ents[i].get("k", "")) == "line":
				(out["ent"] as Dictionary)[i] = "over"
		out["state"] = "over"
		out["free"] = 0
		var names: Array = out["clash"]
		out["text"] = "over-constrained: " + (" and ".join(PackedStringArray(names)) if names.size() > 1 else (String(names[0]) if names.size() == 1 else "some rules cannot all hold")) + (" clash" if names.size() > 1 else "")
		return out
	out["free"] = free
	if free <= 0:
		out["state"] = "defined"
		out["text"] = "fully defined"
	else:
		out["state"] = "free"
		out["text"] = "%d free" % free
	return out


static func _has_dim(dims: Array, ent: int, kind: String) -> bool:
	for d in dims:
		if int(d.get("ent", -1)) == ent and String(d.get("kind", "")) == kind:
			return true
	return false


## names for one rule or length, with the line it sits on ("Horizontal (line 2)")
static func _con_words(c: Dictionary) -> String:
	var w := Part.con_name(c)
	var a := int(c.get("a", -1))
	if c.has("b") and String(c.get("k", "")) != "h" and String(c.get("k", "")) != "v":
		return "%s (lines %d, %d)" % [w, a + 1, int(c["b"]) + 1]
	return "%s (line %d)" % [w, a + 1]


static func _dim_words(d: Dictionary) -> String:
	return "length %s mm (line %d)" % [Part._short(float(d.get("mm", 0.0))), int(d.get("ent", -1)) + 1]


## the rules that clash: a smallest set that still cannot hold (each rule is tried out in turn, rules before sizes; one that is not
## needed to keep the clash is dropped). Two lengths on one line come out as exactly those two.
static func _clash(sk: Dictionary, out: Dictionary) -> void:
	var cons: Array = sk.get("cons", [])
	var dims: Array = sk.get("dims", [])
	var kc: Array = range(cons.size())
	var kd: Array = []
	for i in dims.size():
		if String(dims[i].get("kind", "")) == "len":
			kd.append(i)
	var items: Array = []
	for i in cons.size():
		items.append({"c": i})
	for i in kd:
		items.append({"d": i})
	for it in items:
		var tc: Array = kc.duplicate()
		var td: Array = kd.duplicate()
		if it.has("c"):
			tc.erase(it["c"])
		else:
			td.erase(it["d"])
		if _holds(sk, tc, td):
			continue   # without it everything holds: it is part of the clash
		kc = tc
		kd = td
	for i in kc:
		(out["clash_cons"] as Array).append(int(i))
		(out["clash"] as Array).append(_con_words(cons[int(i)]))
	for i in kd:
		(out["clash_dims"] as Array).append(int(i))
		(out["clash"] as Array).append(_dim_words(dims[int(i)]))


## do the kept rules (indexes) and lengths (indexes) hold together? (a copy is solved)
static func _holds(sk: Dictionary, kc: Array, kd: Array) -> bool:
	var t: Dictionary = sk.duplicate(true)
	var tc: Array = []
	for i in kc:
		tc.append(sk["cons"][int(i)])
	var td: Array = []
	for d in sk.get("dims", []):
		if String(d.get("kind", "")) != "len":
			td.append(d)
	var all_d: Array = sk.get("dims", [])
	td = []
	for i in all_d.size():
		if String(all_d[i].get("kind", "")) != "len" or kd.has(i):
			td.append(all_d[i])
	t["cons"] = tc
	t["dims"] = td
	return Part.solve(t) <= Part.CON_TOL


## the free count of the lines (nullity of the residual Jacobian minus 2 per piece of drawing that slides as a whole) and, per
## line, whether its own length or direction can still change
static func _line_freedom(sk: Dictionary) -> Dictionary:
	var X := Part._pts_of(sk)
	var ents: Array = sk.get("ents", [])
	var cols: Array = []
	for i in ents.size():
		if String(ents[i].get("k", "")) == "line":
			for q in 4:
				cols.append(4 * i + q)
	var res := {"free": 0, "ent": {}}
	if cols.is_empty():
		return res
	const H := 1e-6
	var rows: Array = []   # one row per residual component, a column per line coordinate
	var base := Part._flat(Part._res_all(sk, X))
	for _q in base.size():
		rows.append(PackedFloat64Array())
	for k in cols.size():
		var Xp := X.duplicate()
		var Xm := X.duplicate()
		Xp[cols[k]] += H
		Xm[cols[k]] -= H
		var rp := Part._flat(Part._res_all(sk, Xp))
		var rm := Part._flat(Part._res_all(sk, Xm))
		for q in base.size():
			var rq: PackedFloat64Array = rows[q]
			rq.append((rp[q] - rm[q]) / (2.0 * H))
			rows[q] = rq
	var n := cols.size()
	var piv: Array = []   # RREF
	var M: Array = []
	for r in rows:
		M.append(PackedFloat64Array(r))
	var row := 0
	for c in n:
		var best := row
		var bv := 0.0
		for rr in range(row, M.size()):
			if absf(M[rr][c]) > bv:
				bv = absf(M[rr][c])
				best = rr
		if bv < 1e-5:
			continue
		var tmp = M[row]
		M[row] = M[best]
		M[best] = tmp
		var pv: float = M[row][c]
		for cc in n:
			M[row][cc] = M[row][cc] / pv
		for rr in M.size():
			if rr != row and absf(M[rr][c]) > 0.0:
				var f: float = M[rr][c]
				for cc in n:
					M[rr][cc] -= f * M[row][cc]
		piv.append(c)
		row += 1
		if row >= M.size():
			break
	var nullity := n - piv.size()
	# the pieces that slide as a whole: lines joined by a Coincident rule
	var parent := {}
	for i in ents.size():
		parent[i] = i
	for c in sk.get("cons", []):
		if String(c.get("k", "")) == "coin" and parent.has(int(c.get("a", -1))) and parent.has(int(c.get("b", -1))):
			var ra := _root(parent, int(c["a"]))
			var rb := _root(parent, int(c["b"]))
			parent[ra] = rb
	var roots := {}
	for i in ents.size():
		if String(ents[i].get("k", "")) == "line":
			roots[_root(parent, i)] = true
	res["free"] = maxi(0, nullity - 2 * roots.size())
	# null vectors: one per non-pivot column
	var ent_free := {}
	for i in ents.size():
		if String(ents[i].get("k", "")) == "line":
			ent_free[i] = 0
	for fc in n:
		if piv.has(fc):
			continue
		var v := PackedFloat64Array()
		v.resize(n)
		v[fc] = 1.0
		for r in piv.size():
			v[piv[r]] = -M[r][fc]
		for k in range(0, n, 4):
			var i := int(cols[k]) / 4
			var dx: float = v[k + 2] - v[k]
			var dy: float = v[k + 3] - v[k + 1]
			if absf(dx) > 1e-6 or absf(dy) > 1e-6:
				ent_free[i] = 1
	res["ent"] = ent_free
	return res


static func _root(parent: Dictionary, i: int) -> int:
	while int(parent[i]) != i:
		i = int(parent[i])
	return i


## the colour a shape is drawn in: blue free, green fully defined, red over-constrained
static func color_of(h: Dictionary, i: int) -> Color:
	match String((h.get("ent", {}) as Dictionary).get(i, "free")):
		"defined":
			return DEFINED_C
		"over":
			return OVER_C
	return FREE_C
