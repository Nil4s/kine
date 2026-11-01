## part_fasten.gd - FASTEN THESE TWO (Friday plan 63, Kine's own). Two pieces lie face to face (one on the other, overlapping): Kine picks the screw
## size, the screw length and the hole places, then cuts a clearance hole through the first piece, a pilot hole in the second, and puts the screws
## in (ISO 4762 socket screws, the head and shank sizes from PartTemplates.SCREW_HEAD, the clearance from Cut a hole's M3..M6 chips).
## The rule (printed in the panel, RULE_WORDS):
##   size    from the THINNER piece: M3 under 6 mm, M4 under 10 mm, M5 from 10 mm
##   length  both pieces' thickness together, rounded DOWN to a stock length (6 8 10 12 16 20 25 mm)
##   places  two screws along the long side of the overlap, each at least 2 x the screw's diameter from every edge of the overlap
##           (one screw in the middle when the overlap is too short for two; none, in words, when it is too small for one)
## Holes: clearance (M3 3.4 / M4 4.5 / M5 5.5 mm, + the part's fit) in the first piece, pilot (M3 2.5 / M4 3.3 / M5 4.2 mm) in the second,
## cut with "into" so each cut touches only its own piece. Everything is features appended to the record (one undo step in the UI).
class_name PartFasten
extends RefCounted

const LENGTHS := [6, 8, 10, 12, 16, 20, 25]   # mm: stock screw lengths (under the head)
const PILOT := {3: 2.5, 4: 3.3, 5: 4.2}       # mm: the hole the screw cuts its own thread in
const CLEAR := {3: 3.4, 4: 4.5, 5: 5.5}       # mm: the clearance hole (the same as Cut a hole's screw chips)
const AXES := ["right", "top", "front"]       # the sketch plane whose normal is X, Y, Z: the pieces are stacked along that axis
const RULE_WORDS := "Size from the thinner piece: M3 under 6 mm, M4 under 10 mm, M5 otherwise. Length: both pieces together, rounded down to 6 8 10 12 16 20 25 mm. Two screws along the overlap, 2 x their size from every edge."


## the size for the thinner piece's thickness (mm)
static func size_for(thin: float) -> int:
	return 3 if thin < 6.0 else (4 if thin < 10.0 else 5)


## the longest stock length that is not more than the total thickness (mm); 0 when the pieces are thinner than the shortest screw
static func length_for(total: float) -> int:
	var best := 0
	for x in LENGTHS:
		if float(x) <= total + 0.01:
			best = int(x)
	return best


## the plan for two pieces (triangle corners in metres, as the view holds them): {"why": "" or the words, and, when "why" is "":
## "axis", "plane", "s", "oa", "t", "ta", "tb", "swap", "d", "L", "pts" (the screws' places, sketch mm), "clear", "pilot", "through"}.
## "swap" true: the head goes on the second piece (the first one is too thick for the screw to bite the second)
static func plan(a: PackedVector3Array, b: PackedVector3Array) -> Dictionary:
	if a.is_empty() or b.is_empty():
		return {"why": "Click two pieces first, then press Fasten these two"}
	var la := box_mm(a)
	var lb := box_mm(b)
	var axis := -1
	var best := 1.0
	for k in 3:
		var j := (k + 1) % 3
		var l := (k + 2) % 3
		if absf(la[1][k] - lb[0][k]) > 0.1 and absf(lb[1][k] - la[0][k]) > 0.1:
			continue
		var oj := minf(la[1][j], lb[1][j]) - maxf(la[0][j], lb[0][j])
		var ol := minf(la[1][l], lb[1][l]) - maxf(la[0][l], lb[0][l])
		if oj > 0.5 and ol > 0.5 and oj * ol > best:
			best = oj * ol
			axis = k
	if axis < 0:
		return {"why": "Those two pieces do not lie face to face with an overlap: lay one flat on the other, overlapping, then press Fasten these two"}
	var k := axis
	var j := (k + 1) % 3
	var l := (k + 2) % 3
	var a_low: bool = la[1][k] <= lb[0][k] + 0.1   # the first piece is below (lower along the axis) the second
	var ta: float = la[1][k] - la[0][k]
	var tb: float = lb[1][k] - lb[0][k]
	var total := ta + tb
	var d := size_for(minf(ta, tb))
	var L := length_for(total)
	if L == 0:
		return {"why": "The two pieces are only %.1f mm thick together: too thin for the shortest screw (6 mm). Pick thicker pieces" % total}
	var swap := false
	if L - ta < float(d) and L - tb >= float(d):   # the first piece is so thick the screw would barely bite the second: the head goes on the second
		swap = true
	if L - (tb if swap else ta) < 1.0:
		return {"why": "The screw would not reach the second piece: pick pieces that are about as thick as each other"}
	# the overlap on the two other axes
	var lo := Vector2(maxf(la[0][j], lb[0][j]), maxf(la[0][l], lb[0][l]))
	var hi := Vector2(minf(la[1][j], lb[1][j]), minf(la[1][l], lb[1][l]))
	var ext := hi - lo
	var jlong := ext.x > ext.y + 0.01
	if absf(ext.x - ext.y) <= 0.01:   # a square overlap: the long side of the two pieces together
		jlong = (maxf(la[1][j], lb[1][j]) - minf(la[0][j], lb[0][j])) >= (maxf(la[1][l], lb[1][l]) - minf(la[0][l], lb[0][l]))
	var e_long: float = ext.x if jlong else ext.y
	var e_short: float = ext.y if jlong else ext.x
	var mg := 2.0 * float(d)
	if e_short < 2.0 * mg or e_long < 2.0 * mg:
		return {"why": "The overlap is %.0f x %.0f mm: too small for an M%d screw, which needs %.0f mm clear of every edge. Overlap the pieces more, then press Fasten these two" % [e_long, e_short, d, mg]}
	var along: Array = []   # the places along the long side, mm from the overlap's low end
	if e_long - 2.0 * mg >= 2.0 * float(d):
		var p := maxf(mg, 0.25 * e_long)
		along = [p, e_long - p]
	else:
		along = [e_long * 0.5]
	var pl := Part.plane(AXES[k])
	var t_pos: float = la[1][k] if a_low else la[0][k]
	var pts: Array = []
	for u in along:
		var c := Vector3.ZERO   # mm, world
		var lo_long: float = (lo.x if jlong else lo.y)
		var lo_short: float = (lo.y if jlong else lo.x)
		var cj: float = (lo_long + float(u)) if jlong else (lo_short + e_short * 0.5)
		var cl: float = (lo_short + e_short * 0.5) if jlong else (lo_long + float(u))
		c[j] = cj
		c[l] = cl
		c[k] = t_pos
		pts.append(Part.to_plane(pl, c * Part.MM))
	# the head side: the first piece's outer face (the second's when swapped); s = which way the axis runs from the head into the pieces
	var s := 1.0 if a_low else -1.0
	var oa: float
	if swap:
		s = -s
		oa = lb[1][k] if a_low else lb[0][k]
	else:
		oa = la[0][k] if a_low else la[1][k]
	var thick_head := tb if swap else ta
	var thick_far := ta if swap else tb
	return {"why": "", "axis": k, "plane": AXES[k], "s": s, "oa": oa, "t": t_pos, "ta": thick_head, "tb": thick_far, "swap": swap, "d": d, "L": L, "pts": pts,
		"through": L - thick_head >= thick_far - 0.01, "long_mm": e_long, "short_mm": e_short}


## the box of a piece's corners in mm: [lowest corner, highest corner]
static func box_mm(tris: PackedVector3Array) -> Array:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for v in tris:
		lo = lo.min(v)
		hi = hi.max(v)
	return [lo / Part.MM, hi / Part.MM]


## the features of the fastening, appended to rec: a clearance hole through the head piece (head_i), a pilot hole in the other (far_i), and for
## each screw a head (new body) and its shank (joined to the head). clear = the clearance hole's diameter in mm (the part's fit is added on each side).
## Returns "" or the words (the rec's features are then cut back to how they were: the caller restores its snapshot)
static func build(rec: Dictionary, p: Dictionary, head_i: int, far_i: int, clear: float, fit: float) -> String:
	var pn: String = p["plane"]
	var d: int = p["d"]
	var L := float(p["L"])
	var s: float = p["s"]
	var oa: float = p["oa"]
	var hh := float(PartTemplates.SCREW_HEAD[d][1])
	var hr := float(PartTemplates.SCREW_HEAD[d][0]) * 0.5
	var th: float = p["ta"]
	var tf: float = p["tb"]
	var pts: Array = p["pts"]
	var fl: Array = rec["features"]
	var n0 := fl.size()
	var seq0 := int(rec.get("seq", 0))
	var res0 := Part.replay(rec)
	var b0 := int(res0["bodies"])
	var v0: Array = res0["volumes"]
	# the clearance hole: from 1 mm outside the head piece to 1 mm past its inner face, cutting that piece only
	var ents := []
	for c in pts:
		ents.append({"k": "circle", "c": Part.arr2(c), "r": clear * 0.5 + fit})
	var p1 := Part.new_feature(rec, "plane", {"from": pn, "mm": oa - s})
	fl.append(p1)
	var s1 := Part.new_feature(rec, "sketch", {"plane": String(p1["id"]), "ents": ents, "dims": [], "fit": fit})
	fl.append(s1)
	fl.append(Part.new_feature(rec, "extrude", {"sketch": s1["id"], "dist": s * (th + 2.0), "both": false, "op": "cut", "into": head_i, "fasten": true}))
	# the pilot hole: from inside the first piece's hole (nothing of the second piece is there) to the screw's tip, or all the way through
	var depth: float = (tf + 1.0) if bool(p["through"]) else (L - th)
	var ents2 := []
	for c in pts:
		ents2.append({"k": "circle", "c": Part.arr2(c), "r": float(PILOT[d]) * 0.5})
	var p2 := Part.new_feature(rec, "plane", {"from": pn, "mm": oa + s * (th - 1.0)})
	fl.append(p2)
	var s2 := Part.new_feature(rec, "sketch", {"plane": String(p2["id"]), "ents": ents2, "dims": []})
	fl.append(s2)
	fl.append(Part.new_feature(rec, "extrude", {"sketch": s2["id"], "dist": s * (depth + 1.0), "both": false, "op": "cut", "into": far_i, "fasten": true}))
	# the screws: a head on the outer face, the shank from inside the head down to the tip
	var ph := Part.new_feature(rec, "plane", {"from": pn, "mm": oa})
	fl.append(ph)
	var psh := Part.new_feature(rec, "plane", {"from": pn, "mm": oa - s * 0.5})
	fl.append(psh)
	for c in pts:
		var sh := Part.new_feature(rec, "sketch", {"plane": String(ph["id"]), "ents": [{"k": "circle", "c": Part.arr2(c), "r": hr}], "dims": []})
		fl.append(sh)
		fl.append(Part.new_feature(rec, "extrude", {"sketch": sh["id"], "dist": -s * hh, "both": false, "op": "new", "fasten": true}))
		var sk := Part.new_feature(rec, "sketch", {"plane": String(psh["id"]), "ents": [{"k": "circle", "c": Part.arr2(c), "r": float(d) * 0.5}], "dims": []})
		fl.append(sk)
		fl.append(Part.new_feature(rec, "extrude", {"sketch": sk["id"], "dist": s * (L + 0.5), "both": false, "op": "join", "fasten": true}))
	var res := Part.replay(rec)
	var errs: Dictionary = res["errors"]
	for f in fl.slice(n0):
		if String(errs.get(String(f["id"]), "")) != "":
			return _undo_build(rec, n0, seq0, "The screws did not fit: nothing was changed. Pick two other pieces, or overlap them differently")
	var v1: Array = res["volumes"]
	if int(res["bodies"]) != b0 + pts.size() or v1.size() <= maxi(head_i, far_i) or float(v1[head_i]) > float(v0[head_i]) - 1e-12 or float(v1[far_i]) > float(v0[far_i]) - 1e-12:
		return _undo_build(rec, n0, seq0, "The holes missed a piece: nothing was changed. Overlap the two pieces more, then press Fasten these two again")
	return ""


static func _undo_build(rec: Dictionary, n0: int, seq0: int, why: String) -> String:
	(rec["features"] as Array).resize(n0)
	rec["seq"] = seq0
	return why


## the hardware of a record as lines: "2x M3 x 10" (the same size and length counted together). Empty when nothing was fastened
static func hardware_lines(rec: Dictionary) -> Array:
	var counts := {}
	var order: Array = []
	for f in rec.get("fasteners", []):
		var key := "M%d x %d" % [int(f["d"]), int(f["L"])]
		if not counts.has(key):
			order.append(key)
			counts[key] = 0
		counts[key] = int(counts[key]) + int(f["n"])
	var out: Array = []
	for key in order:
		out.append("%dx %s" % [int(counts[key]), key])
	return out
