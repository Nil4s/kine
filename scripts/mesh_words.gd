## mesh_words.gd - MODELING FROM WORDS (ROADMAP_400 B29): the words box (scripts/command_search.gd -> main._pose_words) runs
## plain phrases on the model preview's mesh (scripts/kmesh_edit_ui.gd):
##   "extrude the top 5 cm"        the faces pulled out along their normal, new side faces between (KMeshExtrude)
##   "make it 2 cm thicker"        the faces moved out along their normals so the planes stay parallel (see offset_faces);
##                                 the WHOLE mesh grows 2 cm across (each side 1 cm), a part (the top...) moves 2 cm
##   "subdivide it twice"          Catmull-Clark, the whole mesh (KMeshSubdiv via kmed.subdivide)
##   "add a cylinder 30 cm tall"   a primitive beside the mesh (KMeshPrims via kmed.add_prim); its size from the words
##   "triangulate" / "make it quads"   F06 (KMeshTopo via kmed.topo)
##   "how big is it" / "measure it"    the bounding box in cm (and the volume of a closed mesh); changes nothing
##   "delete the selected faces" / "dissolve the selected edges"   KMeshDissolve
##   "scale it up 20%" / "make it twice as big"   about the centre of what is named
##   "inset the top 1 cm"          KMeshExtrude.inset
## SELECTION WORDS: "the top" (faces whose normal is within 30 deg of +Y, in the upper half of the mesh), "the bottom" (the
## same, -Y, lower half), "the selected" / "the selection" / "these" (what is selected now), "all" / "everything" / "the whole
## mesh"; "it" (or nothing) = the selection when there is one, else all.
## UNITS: mm, cm, m (and millimetres...), inches; a bare length is cm (the reply says so); % for scale; numbers as words
## ("two", "twice", "half").
## Every edit is ONE KMeshUndo step (the model preview's Ctrl+Z) and the reply says what was done, with units.
## ROUTING (no stealing): a phrase the rig words take (RigWords.is_rig), that names a face (FaceWords.route) or that is a
## pose (PoseWords.parse) is theirs; claims() says when it is ours.
## A NEW OP is one line of OPS (its words and an example); "do" = "" means the words parse but the op is not built yet
## (the reply says so), and building it is the line's "do" plus a branch in run().
class_name MeshWords
extends RefCounted

const OPS := [
	{"id": "add", "do": "add", "words": ["add", "create", "insert", "new", "spawn"], "ex": "add a cylinder 30 cm tall"},
	{"id": "extrude", "sure": true, "do": "extrude", "words": ["extrude", "pull", "push"], "ex": "extrude the top 5 cm"},
	{"id": "inset", "sure": true, "do": "inset", "words": ["inset"], "ex": "inset the top 1 cm"},
	{"id": "thicker", "sure": true, "do": "thicker", "words": ["thicker", "thinner", "thicken", "thin", "offset", "solidify", "fatter"], "ex": "make it 2 cm thicker"},
	{"id": "subdivide", "sure": true, "do": "subdivide", "words": ["subdivide", "subdivision", "subdiv", "catmull"], "ex": "subdivide it twice"},
	{"id": "triangulate", "sure": true, "do": "triangulate", "words": ["triangulate", "triangles", "tris", "triangulated"], "ex": "triangulate"},
	{"id": "quads", "sure": true, "do": "quads", "words": ["quads", "quadrangulate", "untriangulate"], "ex": "make it quads"},
	{"id": "scale", "do": "scale", "words": ["scale", "bigger", "smaller", "larger", "grow", "shrink", "resize", "double", "halve"], "ex": "scale it up 20%"},
	{"id": "measure", "do": "measure", "words": ["measure", "big", "size", "dimensions", "large", "tall", "wide", "high", "volume"], "ex": "how big is it"},
	{"id": "delete", "do": "delete", "words": ["delete", "remove", "erase"], "ex": "delete the selected faces"},
	{"id": "dissolve", "do": "dissolve", "words": ["dissolve"], "ex": "dissolve the selected edges"},
	{"id": "bevel", "sure": true, "do": "", "words": ["bevel", "chamfer", "fillet"], "ex": "bevel the edges 1 cm"},
	{"id": "loopcut", "sure": true, "do": "", "words": ["loopcut", "loop cut"], "ex": "loop cut it"},
	{"id": "fill", "do": "", "words": ["fill", "bridge"], "ex": "fill the hole"},
]
## more phrases the help lists as close matches (besides each op's "ex")
const EXAMPLES := ["extrude the selected 2 cm", "make the top 1 cm thinner", "subdivide it once", "add a sphere 20 cm wide",
	"add a cube 10 cm", "measure it", "scale it down 10%", "make it twice as big", "delete the top", "push the top in 1 cm"]
const NUM_WORDS := {"zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
	"ten": 10, "eleven": 11, "twelve": 12, "fifteen": 15, "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "hundred": 100}
const COUNT_WORDS := {"once": 1, "twice": 2, "thrice": 3}
const UNIT_M := {"mm": 0.001, "millimetre": 0.001, "millimeter": 0.001, "cm": 0.01, "centimetre": 0.01, "centimeter": 0.01,
	"m": 1.0, "metre": 1.0, "meter": 1.0, "inch": 0.0254, "in.": 0.0254}
const PRIM := {"cube": "cube", "box": "cube", "block": "cube", "plane": "plane", "floor": "plane", "sheet": "plane",
	"sphere": "uv_sphere", "ball": "uv_sphere", "globe": "uv_sphere", "icosphere": "ico_sphere", "cylinder": "cylinder", "tube": "cylinder",
	"pipe": "cylinder", "rod": "cylinder", "pillar": "cylinder", "column": "cylinder", "capsule": "capsule", "pill": "capsule",
	"torus": "torus", "donut": "torus", "doughnut": "torus", "ring": "torus"}
## the word next to a length says which size it is
const DIM := {"tall": "h", "high": "h", "height": "h", "long": "h", "length": "h", "deep": "h", "depth": "h",
	"wide": "w", "across": "w", "diameter": "w", "width": "w", "radius": "r", "thick": "t"}
const TOP_COS := 0.866   # cos 30 deg: "the top" is the faces facing up within 30 deg
const DEFAULT_LEN := 0.05   # m: "extrude the top" with no amount = the E key's 5 cm (KMeshEditUI.EXTRUDE_D)
const MESH_NOUNS := ["faces", "face", "verts", "vertices", "vertex", "edges", "edge", "mesh", "cube", "top", "bottom"]
const SIMILAR := 0.5   # String.similarity of a typed word to an op word that counts as a typo of it
const SCALE_MIN := 0.01
static var _rx_num: RegEx
const SCALE_MAX := 100.0


static func _norm(text: String) -> String:
	var t := " " + text.to_lower().strip_edges().replace(",", " ").replace("?", " ").replace("!", " ").replace("%", " % ") + " "
	t = t.replace(" per cent ", " % ").replace(" percent ", " % ").replace(" loop cut ", " loopcut ").replace(" ico sphere ", " icosphere ")
	t = t.replace(" a half ", " half ").replace(" as big ", " bigger ").replace(" as large ", " bigger ").replace("-", " ")
	for w in NUM_WORDS:
		t = t.replace(" %s " % w, " %d " % NUM_WORDS[w])
	return " ".join(t.split(" ", false))


static func _words(t: String) -> PackedStringArray:
	return t.split(" ", false)


## the op a phrase names: the first OPS line one of whose words is in it ("" = none)
static func _op_of(ws: PackedStringArray) -> Dictionary:
	for o in OPS:
		for w in o["words"]:
			if w in ws:
				return o
	return {}


## every number in the phrase with its unit: [{"v", "unit" ("" / "%" / a UNIT_M key), "m" (metres, NAN when not a length),
## "at" (word index), "next", "prev" (the words around it)}]
static func numbers(t: String) -> Array:
	var ws := _words(t)
	var out := []
	var i := 0
	while i < ws.size():
		var w := ws[i]
		if not w[0].is_valid_int() and not (w.length() > 1 and w[0] == "-"):
			i += 1
			continue
		if _rx_num == null:
			_rx_num = RegEx.create_from_string("^(-?\\d+(?:\\.\\d+)?)([a-z%.]*)$")
		var mt := _rx_num.search(w)
		if mt == null:
			i += 1
			continue
		var v := float(mt.get_string(1))
		var u := mt.get_string(2)
		var used := i
		if u == "" and i + 1 < ws.size():
			var nx := ws[i + 1]
			if _unit(nx) != "":
				u = nx
				used = i + 1
		var un := _unit(u)
		out.append({"v": v, "unit": un, "m": v * float(UNIT_M[un]) if UNIT_M.has(un) else NAN, "at": i,
			"next": ws[used + 1] if used + 1 < ws.size() else "", "prev": ws[i - 1] if i > 0 else ""})
		i = used + 1
	return out


static func _unit(u: String) -> String:
	if u == "%":
		return "%"
	if u == "":
		return ""
	var s := u.trim_suffix("es") if u.ends_with("inches") else u.trim_suffix("s") if u.length() > 2 else u
	return s if UNIT_M.has(s) else ""


## the target the words name: "top", "bottom", "selected", "all", "it"
static func target_of(ws: PackedStringArray) -> String:
	if "top" in ws or "upper" in ws:
		return "top"
	if "bottom" in ws or "underside" in ws or "base" in ws:
		return "bottom"
	for w in ["selected", "selection", "these", "this", "those"]:
		if w in ws:
			return "selected"
	for w in ["all", "everything", "whole", "every", "entire"]:
		if w in ws:
			return "all"
	return "it"


## a length from the phrase in metres: {"m", "note"}; a bare number is cm (said in the note); none -> NAN
static func _length(nums: Array) -> Dictionary:
	for n in nums:
		if n["unit"] == "%":
			continue
		if n["unit"] == "":
			return {"m": float(n["v"]) * 0.01, "note": " (a bare %s is taken as cm)" % _g(n["v"])}
		return {"m": float(n["m"]), "note": ""}
	return {"m": NAN, "note": ""}


static func _g(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else str(v)


## parse a phrase: {"ok": true, "op", "do", "target", ...op fields} or {"ok": false, "op" ("" when no op word), "error"}
static func parse(text: String, with_help := true) -> Dictionary:
	var t := _norm(text)
	var ws := _words(t)
	var o := _op_of(ws)
	if o.is_empty():
		return {"ok": false, "op": "", "error": help(text) if with_help else "not a model edit"}
	var r := {"ok": true, "op": o["id"], "do": o["do"], "target": target_of(ws), "text": t}
	if o["do"] == "":
		r["ok"] = false
		r["error"] = "%s isn't built yet: the words parse, the op is coming on the MODEL page. Works now: %s" % [o["id"].replace("loopcut", "loop cut"), ", ".join(built())]
		return r
	var nums := numbers(t)
	match String(o["id"]):
		"extrude", "inset", "thicker":
			var L := _length(nums)
			r["note"] = L["note"]
			if is_nan(L["m"]):
				if o["id"] == "thicker":
					return {"ok": false, "op": o["id"], "error": "how much thicker? Say: make it 2 cm thicker (mm, cm or m)"}
				L["m"] = DEFAULT_LEN if o["id"] == "extrude" else 0.02
				r["note"] = " (no amount said: %s, the %s key's default)" % [Units.len(L["m"]), "E" if o["id"] == "extrude" else "I"]
			var d: float = L["m"]
			if o["id"] == "thicker" and ("thinner" in ws or "thin" in ws):
				d = -absf(d)
			if o["id"] == "extrude" and ("in" in ws or "inward" in ws or "inwards" in ws or "push" in ws):
				d = -absf(d)
			if absf(d) < 1e-5 or absf(d) > 10.0:
				return {"ok": false, "op": o["id"], "error": "%s by %s is out of range: say an amount between 0.01 mm and 10 m, e.g. %s" % [o["id"], Units.len(d), o["ex"]]}
			r["d"] = d
		"subdivide":
			var n := 1
			for w in COUNT_WORDS:
				if w in ws:
					n = COUNT_WORDS[w]
			for x in nums:
				if x["unit"] == "":
					n = int(x["v"])
			if n < 1 or n > 6:
				return {"ok": false, "op": "subdivide", "error": "subdivide 1 to 6 times: say subdivide it twice"}
			r["levels"] = n
		"add":
			var kind := ""
			for w in ws:
				if PRIM.has(w):
					kind = PRIM[w]
					break
			if kind == "":
				return {"ok": false, "op": "add", "error": "add what? Say: add a cylinder 30 cm tall (cube, plane, sphere, icosphere, cylinder, capsule, torus)"}
			r["kind"] = kind
			var pr := _prim_params(kind, nums)
			if pr.has("error"):
				return {"ok": false, "op": "add", "error": pr["error"]}
			r["params"] = pr["params"]
			r["note"] = pr["note"]
		"delete", "dissolve":
			r["what"] = "verts" if ("vertices" in ws or "verts" in ws or "vertex" in ws or "points" in ws) else "edges" if ("edges" in ws or "edge" in ws) else "faces"
		"scale":
			var f := NAN
			if "double" in ws or "twice" in ws:
				f = 2.0
			elif "halve" in ws or "half" in ws:
				f = 0.5
			var down := "down" in ws or "smaller" in ws or "shrink" in ws
			for x in nums:
				if x["unit"] == "%":
					var p := float(x["v"]) / 100.0
					f = (1.0 - p if down else 1.0 + p) if ("up" in ws or down or "bigger" in ws or "larger" in ws or "grow" in ws) else p
					break
				if x["unit"] == "":
					f = float(x["v"])
					if down and f > 1.0:
						f = 1.0 / f
					break
				return {"ok": false, "op": "scale", "error": "scale takes a % or a factor, not a length: say scale it up 20% or scale it by 1.5"}
			if is_nan(f):
				return {"ok": false, "op": "scale", "error": "by how much? Say: scale it up 20%, scale it down 10%, or make it twice as big"}
			if f < SCALE_MIN or f > SCALE_MAX:
				return {"ok": false, "op": "scale", "error": "a scale of %.3f is out of range (%.2f to %.0f): say scale it up 20%%" % [f, SCALE_MIN, SCALE_MAX]}
			r["f"] = f
	return r


## the primitive's params from its words (see DIM); {"params", "note"} or {"error"}
static func _prim_params(kind: String, nums: Array) -> Dictionary:
	var p := {}
	var note := ""
	var seg := -1
	for n in nums:
		var nx: String = n["next"]
		if n["unit"] == "" and (nx in ["sides", "segments", "side", "segment"] or n["prev"] in ["sides", "segments"]):
			seg = int(n["v"])
			continue
		if n["unit"] == "%":
			return {"error": "a primitive's size is a length: say add a cylinder 30 cm tall"}
		var m: float = float(n["m"]) if n["unit"] != "" else float(n["v"]) * 0.01
		if n["unit"] == "":
			note = " (a bare %s is taken as cm)" % _g(n["v"])
		var dim: String = DIM.get(nx, DIM.get(n["prev"], ""))
		match kind:
			"cube":
				p["size"] = m
			"plane":
				p["size_x"] = m
				p["size_z"] = m
			"uv_sphere", "ico_sphere":
				p["radius"] = m if dim == "r" else m * 0.5
			"cylinder":
				if dim == "w":
					p["radius"] = m * 0.5
				elif dim == "r":
					p["radius"] = m
				else:
					p["depth"] = m
			"capsule":
				if dim == "w":
					p["radius"] = m * 0.5
				elif dim == "r":
					p["radius"] = m
				else:
					p["_h"] = m   # the whole height: depth = h - 2 r (below)
			"torus":
				if dim == "r":
					p["major_radius"] = m
				elif dim in ["t", "h"]:
					p["minor_radius"] = m * 0.5
				else:
					p["_w"] = m   # the outer diameter
	if seg > 0:
		p["segments"] = seg
	if p.has("_h"):
		var r: float = p.get("radius", KMeshPrims.defaults("capsule")["radius"])
		p["depth"] = float(p["_h"]) - 2.0 * r
		p.erase("_h")
		if float(p["depth"]) < 0.0:
			return {"error": "a capsule %s tall can't have a %s radius (the two ends alone are %s): say a smaller radius" % [Units.len(float(p["depth"]) + 2.0 * r), Units.len(r), Units.len(2.0 * r)]}
	if p.has("_w"):
		var mr: float = p.get("minor_radius", KMeshPrims.defaults("torus")["minor_radius"])
		p["major_radius"] = float(p["_w"]) * 0.5 - mr
		p.erase("_w")
	return {"params": p, "note": note}


static func built() -> Array:
	return OPS.filter(func(o): return o["do"] != "").map(func(o): return o["ex"])


## the n phrases nearest the words (each op's example + EXAMPLES): the op word counts most, then the letters
static func close(text: String, n := 3) -> Array:
	var t := _norm(text)
	var ws := _words(t)
	var cand := []
	for o in OPS:
		cand.append([o["ex"], o])
	for e in EXAMPLES:
		cand.append([e, _op_of(_words(e))])
	var scored := []
	for c in cand:
		var s: float = t.similarity(c[0])
		for w in ws:
			if w.length() > 2 and w in _words(c[0]):
				s += 0.3
			for ow in (c[1] as Dictionary).get("words", []):
				if w.length() > 3 and (ow as String).similarity(w) >= SIMILAR:
					s += 0.5   # a typo of the op word: "extrdue", "subdivde"
		scored.append([s, c[0]])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	var out := []
	for s in scored:
		if not s[1] in out:
			out.append(s[1])
		if out.size() >= n:
			break
	return out


static func help(text: String) -> String:
	return "I don't know \"%s\" as a model edit. Close: %s. Nothing was changed" % [text.strip_edges(), "; ".join(close(text).map(func(x): return "\"" + x + "\""))]


## the pose words' own words (a verb or a body part): a phrase with one is theirs to refuse, not ours to guess at
static func _pose_ish(ws: PackedStringArray) -> bool:
	if ws.is_empty():
		return false
	if ws[0] in PoseWords.verbs():
		return true
	for w in ws:
		if PoseWords.PARTS.has(w):
			return true
	return false


## is this phrase the mesh words'? Never one the rig, the face or the pose words take. Ours when it parses, or names an
## op of ours (its error helps), or sounds like a model edit nobody else takes (mesh_ish: the close-matches help) - all
## three in the model preview; off it only a phrase that is surely modeling (_sure), so the S box keeps its commands
static func claims(text: String, model_on: bool) -> bool:
	var ws := _words(_norm(text))   # (this runs on every keystroke of the S box: the cheap test first)
	if ws.is_empty() or (_op_of(ws).is_empty() and not (model_on and mesh_ish(ws))):
		return false
	if RigWords.is_rig(text) or FaceWords.route(text)["face"] != "" or PoseWords.parse(text)["ok"]:
		return false
	var r := parse(text, false)   # (no close-matches help)
	if model_on:
		return r["ok"] or r["op"] != "" or (mesh_ish(ws) and not _pose_ish(ws))
	return (r["ok"] or r["op"] != "") and _sure(r, ws)


## the S box's words row ("Model: ..."): a phrase we claim of two words or more. One word ("extrude", "triangulate") is a
## search for the tool's own row (meshsearch: "extrude" finds Model: extrude with its key E), not a phrase to run
static func offers(text: String, model_on: bool) -> bool:
	return text.strip_edges().contains(" ") and claims(text, model_on)


## off the model page a phrase is ours only when it can't be anything else: an op word only modeling has ("extrude",
## "subdivide"...: "sure" in OPS), a primitive named ("add a cylinder"), or a mesh noun ("delete the selected faces").
## "delete all keys", "add a marker", "scale it" stay the S box's commands
static func _sure(r: Dictionary, ws: PackedStringArray) -> bool:
	for o in OPS:
		if o["id"] == r["op"] and o.get("sure", false):
			return true
	if r.has("kind"):
		return true
	for w in ws:
		if w in MESH_NOUNS:
			return true
	return false


## does it sound like a model edit: a near-miss of an op word ("extrdue"), or a selection / mesh word with a number
## ("the top 5 cm")? Only these get the close-matches help: any other text stays the S box's search
static func mesh_ish(ws: PackedStringArray) -> bool:
	var has_num := false
	var has_noun := false
	for w in ws:
		if w.is_valid_float():
			has_num = true
		if w in MESH_NOUNS or w in ["selected", "selection"]:
			has_noun = true
		if w.length() > 3:
			for o in OPS:
				for ow in o["words"]:
					if (ow as String).length() > 3 and (ow as String).similarity(w) >= SIMILAR:
						return true
	return has_noun and has_num


# ---------------------------------------------------------------- the ops on the model preview (main.kmed)

## the faces the target names on ui's mesh ([] = none)
static func faces_of(ui, target: String) -> Array:
	var mesh: KMesh = ui.mesh
	var sel: KMeshSelect = ui.sel
	if target == "it":
		target = "selected" if not sel.is_empty() else "all"
	match target:
		"all":
			return range(mesh.face_count())
		"selected":
			var s := KMeshSelect.new(mesh, sel.mode)
			s.verts = sel.verts.duplicate()
			s.edges = sel.edges.duplicate()
			s.faces = sel.faces.duplicate()
			s.set_mode(KMeshSelect.FACE)
			return s.faces.keys()
		_:
			var lo := INF
			var hi := -INF
			for v in mesh.verts:
				lo = minf(lo, v.y)
				hi = maxf(hi, v.y)
			var mid := (lo + hi) * 0.5
			var up := 1.0 if target == "top" else -1.0
			var out := []
			for fi in mesh.face_count():
				var c := mesh.face_center(fi)
				if (mesh.face_normals[fi] as Vector3).y * up >= TOP_COS and (c.y - mid) * up > 0.0:
					out.append(fi)
			return out


static func _verts_of(mesh: KMesh, fs: Array) -> Array:
	var vs := {}
	for fi in fs:
		for v in (mesh.faces[fi] as PackedInt32Array):
			vs[v] = true
	return vs.keys()


## what the target is called in a reply
static func _named(ui, target: String, nf: int) -> String:
	if target == "it":
		target = "selected" if not ui.sel.is_empty() else "all"
	var what: String = {"all": "the whole mesh", "selected": "the selection", "top": "the top", "bottom": "the bottom"}[target]
	return "%s (%d face%s)" % [what, nf, "" if nf == 1 else "s"]


## put these faces in ui's selection, face mode (the extrude / inset ops work on the selection)
static func _select_faces(ui, fs: Array) -> void:
	var sel: KMeshSelect = ui.sel
	sel.clear()
	sel.mode = KMeshSelect.FACE
	for f in fs:
		sel.faces[f] = true


## OFFSET along the normals: every vert of the faces moves so each of ITS faces' planes (among fs) moves d along its normal
## (the least-norm x with n_i . x = d for every distinct normal n_i at the vert): a cube corner moves d on all three axes, a
## vert inside a flat patch d along the normal, so flat faces stay flat and parallel. Returns how many verts moved.
static func offset_faces(mesh: KMesh, fs: Array, d: float) -> int:
	var at := {}   # vert -> [distinct normals]
	for fi in fs:
		var n: Vector3 = mesh.face_normals[fi]
		for v in (mesh.faces[fi] as PackedInt32Array):
			var ns: Array = at.get(v, [])
			var dup := false
			for q in ns:
				if (q as Vector3).dot(n) > 0.9999:
					dup = true
					break
			if not dup:
				ns.append(n)
			at[v] = ns
	var vs := mesh.verts.duplicate()
	for v in at:
		vs[v] = vs[v] + _solve(at[v], d)
	mesh.verts = vs
	mesh._compute_normals()
	return at.size()


static func _solve(ns: Array, d: float) -> Vector3:
	if ns.size() == 1:
		return (ns[0] as Vector3) * d
	if ns.size() == 2:
		var c: float = (ns[0] as Vector3).dot(ns[1])
		return ((ns[0] as Vector3) + (ns[1] as Vector3)) * (d / (1.0 + c)) if c > -0.99 else Vector3.ZERO
	var M := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)   # sum n n^T (symmetric: columns = rows)
	var rhs := Vector3.ZERO
	var avg := Vector3.ZERO
	for n: Vector3 in ns:
		M.x += n * n.x
		M.y += n * n.y
		M.z += n * n.z
		rhs += n * d
		avg += n
	if absf(M.determinant()) > 1e-4:
		return M.inverse() * rhs
	avg = avg.normalized()   # near-coplanar normals (a curved strip): along the mean, far enough for the average face
	var k := 0.0
	for n: Vector3 in ns:
		k += avg.dot(n)
	k /= float(ns.size())
	return avg * (d / maxf(k, 0.2))


static func bbox(mesh: KMesh, vs: Array = []) -> AABB:
	var ids := vs if not vs.is_empty() else range(mesh.vert_count())
	if ids.is_empty():
		return AABB()
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for i in ids:
		lo = lo.min(mesh.verts[i])
		hi = hi.max(mesh.verts[i])
	return AABB(lo, hi - lo)


static func _cm(v: float) -> String:
	return "%.1f" % (v * 100.0)


static func _dims(b: AABB) -> String:
	return "%s wide x %s tall x %s deep cm" % [_cm(b.size.x), _cm(b.size.y), _cm(b.size.z)]


## run a phrase on the model preview (opened first when it is not open). Returns {"ok", "op", "said", "steps" (KMeshUndo
## steps it made)} or {"ok": false, "error"}
static func run(m: Node, text: String) -> Dictionary:
	var p := parse(text)
	if not p["ok"]:
		var e: String = p["error"]
		m._say("Model: " + e)
		return {"ok": false, "op": p.get("op", ""), "error": e, "steps": 0}
	var opened := false
	if m.kmed == null or not m.kmed.on:
		m._kmesh_edit_start()
		opened = true
	var ui = m.kmed
	var mesh: KMesh = ui.mesh
	var n0: int = ui.undo.steps.size()
	var said := ""
	var ok := true
	var tg: String = p["target"]
	var nf0 := mesh.face_count()
	match String(p["do"]):
		"extrude", "inset":
			var fs := faces_of(ui, tg)
			if fs.is_empty():
				return _fail(m, "nothing to %s: %s. Select faces first, or say %s" % [p["op"], "no faces face that way" if tg in ["top", "bottom"] else "nothing is selected", "extrude the top 5 cm"])
			var nm := _named(ui, tg, fs.size())
			_select_faces(ui, fs)
			ui.undo.begin(mesh)
			var r: Dictionary = KMeshExtrude.extrude(mesh, ui.sel, p["d"]) if p["do"] == "extrude" else KMeshExtrude.inset(mesh, ui.sel, p["d"])
			ui.undo.commit("Extrude" if p["do"] == "extrude" else "Inset")
			ui.view.mark_dirty()
			if String(r.get("error", "")) != "":
				return _fail(m, "%s: %s" % [p["op"], r["error"]])
			said = "%s %s %s%s%s; the new part is selected, %d -> %d faces. One undo step (Ctrl+Z takes it back)" % [
				"extruded" if p["do"] == "extrude" else "inset", nm, Units.len(absf(p["d"])) if p["do"] == "inset" else KMeshMeasure.fmt_len(absf(p["d"])),
				(" in along its normal" if p["d"] < 0.0 else " out along its normal") if p["do"] == "extrude" else "", p.get("note", ""), nf0, mesh.face_count()]
		"thicker":
			var fs := faces_of(ui, tg)
			if fs.is_empty():
				return _fail(m, "nothing to thicken: %s" % ("no faces face that way" if tg in ["top", "bottom"] else "nothing is selected"))
			var whole: bool = fs.size() == mesh.face_count() and mesh.boundary_edge_count() == 0
			var each: float = p["d"] * (0.5 if whole else 1.0)   # a closed whole: both sides move, so each half
			var b0 := bbox(mesh)
			ui.undo.begin(mesh)
			var nv := offset_faces(mesh, fs, each)
			ui.undo.commit("Thicker" if p["d"] > 0.0 else "Thinner")
			ui.view.mark_dirty()
			var b1 := bbox(mesh)
			if whole:
				said = "made it %s %s%s: every face moved %s %s along its normal, so it is %s -> %s. One undo step (Ctrl+Z takes it back)" % [
					KMeshMeasure.fmt_len(absf(p["d"])), "thicker" if p["d"] > 0.0 else "thinner", p.get("note", ""), "out" if each > 0.0 else "in",
					KMeshMeasure.fmt_len(absf(each)), _dims(b0), _dims(b1)]
			else:
				said = "moved %s %s %s along its normals (%d verts; the faces stay parallel)%s. One undo step (Ctrl+Z takes it back)" % [
					_named(ui, tg, fs.size()), "out" if each > 0.0 else "in", KMeshMeasure.fmt_len(absf(each)), nv, p.get("note", "")]
		"subdivide":
			var lv: int = p["levels"]
			ui.subdivide(lv)
			if ui.undo.steps.size() == n0:
				return {"ok": false, "op": "subdivide", "error": String(m.ui_status.text) if m.get("ui_status") != null else "too many faces", "steps": 0}
			said = "subdivided the whole mesh %s (Catmull-Clark): %d -> %d faces%s. One undo step (Ctrl+Z takes it back)" % [
				"once" if lv == 1 else "twice" if lv == 2 else "%d times" % lv, nf0, mesh.face_count(), "" if tg in ["it", "all"] else " (subdivide works on all of it, not only " + tg + ")"]
		"add":
			var nv0 := mesh.vert_count()
			if not ui.add_prim(p["kind"], p["params"]):
				return _fail(m, "could not add a %s" % p["kind"])
			mesh = ui.mesh
			var b := bbox(mesh, range(nv0, mesh.vert_count()))
			said = "added a %s: %s%s, beside the mesh. One undo step (Ctrl+Z takes it back); its fields stay live in the Add primitive panel" % [
				KMeshPrims.NAMES[p["kind"]].to_lower(), _dims(b), p.get("note", "")]
		"triangulate", "quads":
			if tg != "it":
				var fs := faces_of(ui, tg)
				_select_faces(ui, fs)
				if tg == "all":
					ui.sel.clear()
			ui.topo("tri" if p["do"] == "triangulate" else "quad")
			if ui.undo.steps.size() == n0:
				said = String(m.ui_status.text).trim_prefix("Model: ")
				ok = false
			else:
				said = "%s: %d -> %d faces. One undo step (Ctrl+Z takes it back)" % ["triangulated" if p["do"] == "triangulate" else "joined triangles into quads", nf0, mesh.face_count()]
		"measure":
			var vs := [] if tg in ["it", "all"] and ui.sel.is_empty() or tg == "all" else _verts_of(mesh, faces_of(ui, tg))
			var b := bbox(mesh, vs)
			var vol := KMeshMeasure.volume(mesh)
			said = "%s is %s%s. Nothing was changed" % ["the whole mesh" if vs.is_empty() else _named(ui, tg, faces_of(ui, tg).size()), _dims(b),
				(", volume " + KMeshMeasure.fmt_vol(vol["m3"])) if vs.is_empty() and vol["ok"] else ""]
		"delete", "dissolve":
			var what: String = p["what"]
			var items := []
			if tg in ["top", "bottom", "all"]:
				what = "faces"
				items = faces_of(ui, tg)
			elif not ui.sel.is_empty():
				var s := KMeshSelect.new(mesh, ui.sel.mode)
				s.verts = ui.sel.verts.duplicate()
				s.edges = ui.sel.edges.duplicate()
				s.faces = ui.sel.faces.duplicate()
				s.set_mode({"verts": KMeshSelect.VERT, "edges": KMeshSelect.EDGE, "faces": KMeshSelect.FACE}[what])
				var it := KMeshDissolve.from_select(s)
				items = it[what]
			if items.is_empty():
				return _fail(m, "nothing to %s: select %s first, or say %s the top" % [p["op"], what, p["op"]])
			ui.undo.begin(mesh)
			if p["do"] == "delete":
				KMeshDissolve.delete(mesh, what, items)
			else:
				match what:
					"verts":
						KMeshDissolve.dissolve_verts(mesh, items)
					"edges":
						KMeshDissolve.dissolve_edges(mesh, items)
					_:
						KMeshDissolve.dissolve_faces(mesh, items)
			var st: Dictionary = ui.undo.commit(("Delete " if p["do"] == "delete" else "Dissolve ") + what)
			ui.sel.clear()
			ui.view.mark_dirty()
			if st.is_empty():
				return _fail(m, "%s changed nothing (%d %s)" % [p["op"], items.size(), what])
			said = "%s %d %s: %d -> %d faces. One undo step (Ctrl+Z takes it back)" % ["deleted" if p["do"] == "delete" else "dissolved", items.size(),
				what, nf0, mesh.face_count()]
		"scale":
			var fs := faces_of(ui, tg)
			var vs := _verts_of(mesh, fs) if not (tg == "all" or (tg == "it" and ui.sel.is_empty())) else range(mesh.vert_count())
			if vs.is_empty():
				return _fail(m, "nothing to scale: select something, or say scale it up 20%")
			var f: float = p["f"]
			var b0 := bbox(mesh, vs)
			var c := b0.get_center()
			ui.undo.begin(mesh)
			var nv := mesh.verts.duplicate()
			for v in vs:
				nv[v] = c + (nv[v] - c) * f
			mesh.verts = nv
			mesh._compute_normals()
			ui.undo.commit("Scale")
			ui.view.mark_dirty()
			said = "scaled %s by %s%% about its centre: %s -> %s. One undo step (Ctrl+Z takes it back)" % [
				"the whole mesh" if vs.size() == mesh.vert_count() else _named(ui, tg, fs.size()), _g(snappedf(f * 100.0, 0.01)), _dims(b0), _dims(bbox(mesh, vs))]
	var steps: int = ui.undo.steps.size() - n0
	if opened:
		said = "opened the test cube first (mesh words work on the MODEL page). " + said
	m._say("Model: " + said)
	return {"ok": ok, "op": p["op"], "said": said, "steps": steps}


static func _fail(m: Node, e: String) -> Dictionary:
	m._say("Model: " + e)
	return {"ok": false, "error": e, "steps": 0}
