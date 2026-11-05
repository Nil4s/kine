extends RefCounted
## s229 AUTHORING SPEED + SAFETY (the Kine-vs-Blender hall duel, ranked gaps 4, 5, 9, 10): three things that Blender does by typing numbers and
## that Kine needed plane + sketch + extrude (3-4 features) for, or did not guard.
##
## 1 PRIMITIVE (one feature, one undo step): {"t": "prim", "id", "name", "kind": "box"|"cylinder"|"tube"|"cone"|"sphere"|"wedge", "op": "new"|"join"|"cut"|"intersect",
##   ["into": body], ["targets": [bodies]], ...numbers in MILLIMETRES in world axes (X right, Y up, Z toward the viewer)}
##     box       "x","y","z" = the corner with the smallest x, y, z (or the middle with "centre": true), "w","h","d" = the sizes along X, Y, Z
##     wedge     the same box cut by a slope: full height "h" at x, falling to 0 at x + w (a triangle in X-Y, "d" deep along Z)
##     cylinder  "x","y","z" = the middle of the START cap, "axis": "x"|"y"|"z", "r" (radius), "len" (length along +axis)
##     tube      a cylinder with a round bore: "r" outside, "r_in" inside
##     cone      a cylinder whose end radius is "r2" (default 0 = a point): "r" at the start cap
##     sphere    "x","y","z" = the middle, "r"
##   Part.replay makes it (PartPrim.apply); Part.prim(rec, kind, fields) appends one and returns its id: the whole box is ONE call.
## 2 ANY PLANE: a "plane" feature (the offset plane's record) with "from" = "pts" (3 points: origin = the first, x towards the second, normal = (p2-p1) x (p3-p1)),
##   "angle" (base plane/id turned about an edge: "edge": "x"|"y" = that axis of the base plane, or [[ax,ay,az],[bx,by,bz]] mm; "deg": right-hand turn; "mm": the base moved first),
##   "edge" (the plane through the edge a-b at "deg" degrees from the half plane that holds the edge and straight up (or "ref": a point mm)), "face" (the plane on a face: "o","n" mm).
##   A sketch whose "plane" is that id sits on it, and an Extrude of it runs along its normal.
## 3 SAFETY: scoped_intersect (an Extrude or a Combine with op intersect trims only the bodies the solid touches; the bodies it misses stay; an "into" /
##   "targets" list names the bodies; "scope": "all" is the old behaviour (bodies that miss are removed) and says how many); crossing() finds a
##   self-crossing (bow-tie) outline of a closed sketch.

const KCad := preload("res://scripts/kcad.gd")
const MM := 0.001
const KINDS := ["box", "cylinder", "tube", "cone", "sphere", "wedge"]
const AXES := {"x": Vector3(1, 0, 0), "y": Vector3(0, 1, 0), "z": Vector3(0, 0, 1)}
const PLANE_KINDS := ["pts", "angle", "edge", "face"]
const HIT_VOL := 1e-9   # m3: an overlap this small is contact, not shared volume (the same as Part.HIT_VOL)

## the words of the last scoped intersect (replay copies them to its "warnings" list; cleared by replay before each step)
static var last_warning := ""
static var checks_off := false   # a test's switch: the sketch checks (crossing, plane) off, to show an old part replays the same with them on


static func _v3(a: Variant) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


# ---------------------------------------------------------------- 1 PRIMITIVES

## the numbers a kind needs, in the order the dialogs show them: [key, label, default]
static func fields_of(kind: String) -> Array:
	match kind:
		"box":
			return [["x", "X", 0.0], ["y", "Y", 0.0], ["z", "Z", 0.0], ["w", "Width (X)", 100.0], ["h", "Height (Y)", 100.0], ["d", "Depth (Z)", 100.0]]
		"wedge":
			return [["x", "X", 0.0], ["y", "Y", 0.0], ["z", "Z", 0.0], ["w", "Width (X)", 100.0], ["h", "Height (Y)", 100.0], ["d", "Depth (Z)", 100.0]]
		"cylinder":
			return [["x", "X", 0.0], ["y", "Y", 0.0], ["z", "Z", 0.0], ["r", "Radius", 50.0], ["len", "Length", 100.0]]
		"tube":
			return [["x", "X", 0.0], ["y", "Y", 0.0], ["z", "Z", 0.0], ["r", "Radius", 50.0], ["r_in", "Bore radius", 40.0], ["len", "Length", 100.0]]
		"cone":
			return [["x", "X", 0.0], ["y", "Y", 0.0], ["z", "Z", 0.0], ["r", "Radius", 50.0], ["r2", "End radius", 0.0], ["len", "Length", 100.0]]
		"sphere":
			return [["x", "X", 0.0], ["y", "Y", 0.0], ["z", "Z", 0.0], ["r", "Radius", 50.0]]
	return []


## "" when the numbers make a solid, else the sentence why not
static func problem(f: Dictionary) -> String:
	var kind := String(f.get("kind", "box"))
	if not KINDS.has(kind):
		return "%s is not a shape (box, cylinder, tube, cone, sphere or wedge)" % kind
	for row in fields_of(kind):
		var k := String(row[0])
		if f.has(k) and (not (f[k] is float or f[k] is int) or is_nan(float(f[k])) or is_inf(float(f[k]))):
			return "%s needs a number" % String(row[1])
	if kind == "box" or kind == "wedge":
		for k in ["w", "h", "d"]:
			if float(f.get(k, 0.0)) <= 0.0:
				return "a %s needs a width, height and depth above 0 mm" % kind
	if kind != "box" and kind != "wedge" and float(f.get("r", 0.0)) <= 0.0:
		return "a %s needs a radius above 0 mm" % kind
	if kind in ["cylinder", "tube", "cone"] and float(f.get("len", 0.0)) <= 0.0:
		return "a %s needs a length above 0 mm" % kind
	if kind in ["cylinder", "tube", "cone"] and not AXES.has(String(f.get("axis", "z"))):
		return "the axis is x, y or z"
	if kind == "tube" and (float(f.get("r_in", 0.0)) <= 0.0 or float(f.get("r_in", 0.0)) >= float(f.get("r", 0.0))):
		return "the bore radius must be above 0 and smaller than the radius"
	if kind == "cone" and (float(f.get("r2", 0.0)) < 0.0 or float(f.get("r2", 0.0)) >= float(f.get("r", 0.0)) * 1000.0):
		return "the end radius cannot be below 0"
	return ""


## the primitive's solid (kernel metres, already in place); 0 on failure (KCad.last_error())
static func solid_of(f: Dictionary) -> int:
	var kind := String(f.get("kind", "box"))
	var o := Vector3(float(f.get("x", 0.0)), float(f.get("y", 0.0)), float(f.get("z", 0.0))) * MM
	match kind:
		"box":
			# G8BOM / G4: the sizes go to the kernel as doubles (a float32 Vector3 made a 40 x 20 x 10 mm box 8.0000017 cm3); only the place is a Vector3
			var w := float(f["w"]) * MM
			var h := float(f["h"]) * MM
			var dd := float(f["d"]) * MM
			var b := KCad.box(w, h, dd)   # the kernel's box is centred on the origin
			if b == 0:
				return 0
			var at := o if bool(f.get("centre", false)) else o + Vector3(w, h, dd) * 0.5
			var t := KCad.translate(b, at)
			KCad.release(b)
			return t
		"sphere":
			var s := KCad.sphere(float(f["r"]) * MM)
			if s == 0:
				return 0
			var ts := KCad.translate(s, o)
			KCad.release(s)
			return ts
		"wedge":
			var w := float(f["w"])
			var h := float(f["h"])
			var d := float(f["d"]) * MM
			var face := KCad.sketch_face(KCad.polygon(PackedVector2Array([Vector2(0, 0), Vector2(w * MM, 0), Vector2(0, h * MM)])), Vector3.ZERO, Vector3.RIGHT, Vector3.BACK)
			if face == 0:
				return 0
			var wd := KCad.extrude(face, d, false, 0.0)   # the triangle in X-Y, pulled along +Z
			KCad.release(face)
			if wd == 0:
				return 0
			var tw := KCad.translate(wd, o)
			KCad.release(wd)
			return tw
	if exact_round and kind in ["cylinder", "tube"]:
		return _round_exact(f, o)
	return _round_revolve(f, o, kind)


static var exact_round := true   # G8BOM / G4: cylinder and tube from KCad.cylinder in doubles (false = the old float32 revolve, for comparison)


## a cylinder or tube from the kernel's own cylinder (r, len in doubles), turned onto the axis and moved so its start cap's middle is at o
static func _round_exact(f: Dictionary, o: Vector3) -> int:
	var r := float(f["r"]) * MM
	var ln := float(f["len"]) * MM
	var c := KCad.cylinder(r, ln)   # along z, from z = -len/2 to +len/2
	if c == 0:
		return 0
	if String(f.get("kind", "")) == "tube":
		var bore := KCad.cylinder(float(f["r_in"]) * MM, ln)
		var t := KCad.cut(c, bore) if bore != 0 else 0
		KCad.release(c)
		if bore != 0:
			KCad.release(bore)
		if t == 0:
			return 0
		c = t
	var axis := String(f.get("axis", "z"))
	if axis == "x":   # the seam where the revolve had it: on +z (the turn onto x alone puts it on -z)
		var hz := KCad.rotate(c, Vector3(0, 0, 1), PI)
		KCad.release(c)
		if hz == 0:
			return 0
		c = hz
	if axis != "z":
		var rt := KCad.rotate(c, Vector3(0, 1, 0) if axis == "x" else Vector3(1, 0, 0), PI / 2.0 if axis == "x" else -PI / 2.0)   # z -> +x about y; z -> +y about x
		KCad.release(c)
		if rt == 0:
			return 0
		c = rt
	var mv := KCad.translate(c, o + (AXES[axis] as Vector3) * (ln * 0.5))
	KCad.release(c)
	return mv


## cylinder / tube / cone: the profile (radius across, length up) turned once about the axis through o
static func _round_revolve(f: Dictionary, o: Vector3, kind: String) -> int:
	var ax: Vector3 = AXES[String(f.get("axis", "z"))]
	var xd := Vector3(0, 0, 1) if ax.is_equal_approx(Vector3(1, 0, 0)) else Vector3(1, 0, 0)   # across the axis
	var nrm := xd.cross(ax)   # so that y = n x xd = the axis
	var r := float(f["r"]) * MM
	var ln := float(f["len"]) * MM
	var pts: PackedVector2Array
	if kind == "tube":
		var ri := float(f["r_in"]) * MM
		pts = PackedVector2Array([Vector2(ri, 0), Vector2(r, 0), Vector2(r, ln), Vector2(ri, ln)])
	elif kind == "cone":
		pts = PackedVector2Array([Vector2(0, 0), Vector2(r, 0), Vector2(float(f.get("r2", 0.0)) * MM, ln), Vector2(0, ln)]) if float(f.get("r2", 0.0)) > 0.0 \
			else PackedVector2Array([Vector2(0, 0), Vector2(r, 0), Vector2(0, ln)])
	else:
		pts = PackedVector2Array([Vector2(0, 0), Vector2(r, 0), Vector2(r, ln), Vector2(0, ln)])
	var pf := KCad.sketch_face(KCad.polygon(pts), o, xd, nrm)
	if pf == 0:
		return 0
	var rv := KCad.revolve(pf, o, ax, TAU)
	KCad.release(pf)
	return rv


## the replay step: the primitive becomes a body (or joins / cuts / intersects the bodies). "" = done, else the sentence for the error list
static func apply(bodies: Array, f: Dictionary) -> String:
	var why := problem(f)
	if why != "":
		return why
	var s := solid_of(f)
	if s == 0:
		return KCad.last_error() if KCad.last_error() != "" else "the shape could not be made"
	var op := String(f.get("op", "new"))
	return Part._combine(bodies, s, op, int(f.get("into", -1)), f)


# ---------------------------------------------------------------- 2 ANY PLANE

## the plane (the replay's o, x, n, y) of a plane feature with one of PLANE_KINDS; {} when its numbers make no plane (plane_problem says why)
static func plane_of(rec: Dictionary, f: Dictionary) -> Dictionary:
	var kind := String(f.get("from", ""))
	var o := Vector3.ZERO
	var x := Vector3.RIGHT
	var n := Vector3.BACK
	match kind:
		"pts":
			var p: Array = f.get("p", [])
			if p.size() < 3:
				return {}
			var p0 := _v3(p[0])
			var d1 := _v3(p[1]) - p0
			var d2 := _v3(p[2]) - p0
			n = d1.cross(d2)
			if d1.length() < 1e-6 or n.length() < 1e-6 * maxf(d1.length() * d2.length(), 1e-12):
				return {}
			n = n.normalized()
			x = d1.normalized()
			o = p0 * MM
		"angle":
			var base := Part.resolve_plane(rec, String(f.get("base", "front")))
			var bo: Vector3 = (base["o"] as Vector3) + (base["n"] as Vector3) * float(f.get("mm", 0.0)) * MM
			var ad := Vector3.RIGHT
			var edge: Variant = f.get("edge", "x")
			if edge is Array:
				var ea := _v3(edge[0])
				var eb := _v3(edge[1])
				if (eb - ea).length() < 1e-6:
					return {}
				bo = ea * MM
				ad = (eb - ea).normalized()
			else:
				ad = (base["y"] as Vector3) if String(edge) == "y" else (base["x"] as Vector3)
			n = (base["n"] as Vector3).rotated(ad, deg_to_rad(float(f.get("deg", 0.0)))).normalized()
			x = ad - n * ad.dot(n)
			if x.length() < 1e-6:
				return {}
			x = x.normalized()
			o = bo
		"edge":
			var a := _v3(f.get("a", [0, 0, 0]))
			var b := _v3(f.get("b", [0, 0, 0]))
			var d := b - a
			if d.length() < 1e-6:
				return {}
			d = d.normalized()
			var ref := Vector3.UP
			if f.has("ref"):
				ref = _v3(f["ref"]) - a
			elif absf(d.dot(Vector3.UP)) > 0.999:
				ref = Vector3.RIGHT
			var u := ref - d * ref.dot(d)
			if u.length() < 1e-9:
				return {}
			u = u.normalized().rotated(d, deg_to_rad(float(f.get("deg", 0.0))))
			n = d.cross(u).normalized()
			x = d
			o = a * MM
		"face":
			n = _v3(f.get("n", [0, 0, 1]))
			if n.length() < 1e-6:
				return {}
			n = n.normalized()
			o = _v3(f.get("o", [0, 0, 0])) * MM
			if f.has("x"):
				x = _v3(f["x"]) - n * _v3(f["x"]).dot(n)
			else:
				x = (Vector3.RIGHT if absf(n.dot(Vector3.RIGHT)) < 0.9 else Vector3.UP)
				x = x - n * x.dot(n)
			if x.length() < 1e-9:
				return {}
			x = x.normalized()
		_:
			return {}
	return {"o": o, "x": x, "n": n, "y": n.cross(x)}


## "" when the plane feature (or a base plane name) is a real plane, else the words why not
static func plane_problem(rec: Dictionary, name: String) -> String:
	if checks_off:
		return ""
	if Part.PLANES.has(name):
		return ""
	var f := Part.feature(rec, name)
	if String(f.get("t", "")) != "plane":
		return ""
	var kind := String(f.get("from", ""))
	if kind == "angle":
		var bp := plane_problem(rec, String(f.get("base", "front")))
		if bp != "":
			return bp
	if PLANE_KINDS.has(kind) and plane_of(rec, f).is_empty():
		match kind:
			"pts":
				return "%s: the three points are in a line (or two are the same): pick three points that are not in a line" % String(f.get("name", "the plane"))
			"angle", "edge":
				return "%s: the edge has no length (its two ends are the same point)" % String(f.get("name", "the plane"))
		return "%s: the face has no direction" % String(f.get("name", "the plane"))
	return ""


static func _p3(a: Variant) -> String:
	return "(%s, %s, %s)" % [Part._short(float(a[0])), Part._short(float(a[1])), Part._short(float(a[2]))]


static func plane_words(rec: Dictionary, f: Dictionary) -> String:
	var nm := String(f.get("name", "Plane"))
	match String(f.get("from", "")):
		"pts":
			var p: Array = f.get("p", [])
			return "%s (through 3 points %s)" % [nm, ", ".join(p.map(func(q): return _p3(q)))] if p.size() >= 3 else nm
		"angle":
			var e: Variant = f.get("edge", "x")
			return "%s (the %s plane turned %s deg about %s)" % [nm, Part.plane_words(rec, String(f.get("base", "front"))).trim_suffix(" plane"), Part._short(float(f.get("deg", 0.0))),
				("its %s axis" % String(e)) if not (e is Array) else "the edge %s to %s" % [_p3(e[0]), _p3(e[1])]]
		"edge":
			return "%s (through the edge %s to %s, at %s deg)" % [nm, _p3(f.get("a", [0, 0, 0])), _p3(f.get("b", [0, 0, 0])), Part._short(float(f.get("deg", 0.0)))]
		"face":
			return "%s (on the face at %s)" % [nm, _p3(f.get("o", [0, 0, 0]))]
	return nm


# ---------------------------------------------------------------- 3 SAFETY

## Extrude / Combine intersect that cannot eat a body it does not touch. The solid is used up. Bodies stay in their places (the list never shifts).
##   a body the solid overlaps becomes the overlap; a body it misses stays as it was (f["scope"] = "all": removed, the old behaviour, and said);
##   "into" / "targets" name the only bodies to trim (a named body that misses is an error: it would vanish).
## "" = done, else the sentence why nothing changed. PartPrim.last_warning says what happened to the other bodies.
static func scoped_intersect(bodies: Array, solid: int, f: Dictionary) -> String:
	last_warning = ""
	if bodies.is_empty():
		KCad.release(solid)
		return "there is no body to intersect with"
	var only: Array = []
	if int(f.get("into", -1)) >= 0:
		only.append(int(f["into"]))
	for t in f.get("targets", []):
		only.append(int(t))
	var scope_all := String(f.get("scope", "")) == "all" and only.is_empty()
	var made: Array = []   # per body: the overlap id, or 0
	var miss: Array = []
	for i in bodies.size():
		var c := 0
		if only.is_empty() or only.has(i):
			c = KCad.intersect(bodies[i], solid)
			if c != 0 and KCad.volume(c) <= HIT_VOL:
				KCad.release(c)
				c = 0
			if c == 0:
				miss.append(i)
		made.append(c)
	var any := made.any(func(c): return int(c) != 0)
	var named_miss := miss.filter(func(i): return only.has(i))
	if not any or not named_miss.is_empty():
		for c in made:
			if int(c) != 0:
				KCad.release(int(c))
		KCad.release(solid)
		if not named_miss.is_empty() and any:
			return "Body%d shares no volume with the new solid, so it would vanish: leave it out of the list" % (int(named_miss[0]) + 1)
		return "nothing is shared: the solid misses %s" % ("Body%d" % (int(only[0]) + 1) if only.size() == 1 else "every body")
	KCad.release(solid)
	var kept: Array = []
	var removed: Array = []
	var out: Array = []
	for i in bodies.size():
		if int(made[i]) != 0:
			KCad.release(bodies[i])
			out.append(int(made[i]))
		elif scope_all and not only.has(i):
			KCad.release(bodies[i])
			removed.append(i)
		else:
			out.append(bodies[i])
			kept.append(i)
	var trimmed := bodies.size() - kept.size() - removed.size()
	bodies.clear()
	bodies.append_array(out)
	var nm := func(l: Array) -> String: return ", ".join(l.map(func(i): return "Body%d" % (int(i) + 1)))
	if not removed.is_empty():
		last_warning = "Intersect removed %d body(ies) that miss the new solid (%s); %d trimmed. Use a target list to keep them" % [removed.size(), nm.call(removed), trimmed]
	else:
		last_warning = "Intersect trimmed %d body(ies); %d other body(ies) the solid does not touch stay as they are%s" % [trimmed, kept.size(), (" (" + nm.call(kept) + ")") if not kept.is_empty() else ""]
	return ""


## a self-crossing outline: the first place two lines of a CLOSED chain cross, {} when none. Answers {"at": [x, y] mm, "a": entity index, "b": entity index}.
## Only straight lines are tested, and only inside a chain that closes (an open chain may still be drawn); lines that share an end are not a crossing.
static func crossing(ents: Array) -> Dictionary:
	if ents.size() < 3 or checks_off:
		return {}
	var groups := _closed_groups(ents)
	for g in groups:
		var idx: Array = g
		for ii in idx.size():
			var ea: Dictionary = ents[idx[ii]]
			if String(ea["k"]) != "line":
				continue
			for jj in range(ii + 1, idx.size()):
				var eb: Dictionary = ents[idx[jj]]
				if String(eb["k"]) != "line":
					continue
				var p := _seg_cross(Part.v2(ea["a"]), Part.v2(ea["b"]), Part.v2(eb["a"]), Part.v2(eb["b"]))
				if p.is_empty():
					continue
				return {"at": [snappedf(p[0], 0.01), snappedf(p[1], 0.01)], "a": int(idx[ii]), "b": int(idx[jj])}
	return {}


## the index lists of the chains that close: every end of every piece meets exactly one other end (lines, arcs; a circle / rect / closed spline is a chain by itself and closed)
static func _closed_groups(ents: Array) -> Array:
	var par: Array = []
	var ends: Array = []
	for i in ents.size():
		par.append(i)
		var e: Dictionary = ents[i]
		var k := String(e["k"])
		ends.append([Part.v2(e["a"]), Part.v2(e["b"])] if k == "line" or k == "arc" else [])
	for i in ents.size():
		for j in range(i + 1, ents.size()):
			if (ends[i] as Array).is_empty() or (ends[j] as Array).is_empty():
				continue
			var near := false
			for p in ends[i]:
				for q in ends[j]:
					near = near or (p as Vector2).distance_to(q as Vector2) < 0.01
			if near:
				par[Part._uf_root(par, i)] = Part._uf_root(par, j)
	var groups := {}
	for i in ents.size():
		if (ends[i] as Array).is_empty():
			continue
		var r: int = Part._uf_root(par, i)
		if not groups.has(r):
			groups[r] = []
		(groups[r] as Array).append(i)
	var out: Array = []
	for r in groups:
		var g: Array = groups[r]
		var closed := g.size() >= 3
		for i in g:
			for p in ends[i]:
				var meets := 0
				for j in g:
					if j == i:
						continue
					for q in ends[j]:
						if (p as Vector2).distance_to(q as Vector2) < 0.01:
							meets += 1
				if meets != 1:
					closed = false
		if closed:
			out.append(g)
	return out


## where segments ab and cd cross in their insides (not at a shared end), [x, y], or [] when they do not
static func _seg_cross(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> Array:
	var r := b - a
	var s := d - c
	var den := r.cross(s)
	if absf(den) < 1e-9:
		return []   # parallel (a fold-back along one line is not a crossing)
	var t := (c - a).cross(s) / den
	var u := (c - a).cross(r) / den
	var e := 1e-6
	if t <= e or t >= 1.0 - e or u <= e or u >= 1.0 - e:
		return []
	var p := a + r * t
	return [p.x, p.y]


static func crossing_words(ents: Array, c: Dictionary) -> String:
	return "the outline crosses itself at (%s, %s) mm, where line %d meets line %d: move a corner so the lines do not cross" % [Part._short(float(c["at"][0])), Part._short(float(c["at"][1])), int(c["a"]) + 1, int(c["b"]) + 1]
