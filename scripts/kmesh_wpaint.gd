class_name KMeshWPaint
extends KMeshSculpt
## H02 (docs/ROADMAP_400.md): WEIGHT PAINT on a KMesh's skin weights, the two H01 vertex channels "skin_bones" (Color:
## four bone ids, -1 = none) and "skin_weights" (Color: their weights), scripts/kmesh_autoweights.gd.
## A stroke is the sculpt core's (KMeshSculpt: dabs every spacing * radius along the way, the spatial hash, the falloffs,
## the pen pressure); only the dab is new. Pure: no nodes. begin(mesh, params) ... to(point, normal, pressure) ... end();
## the caller brackets it with KMeshUndo.begin / commit so one stroke is one undo step (the channels are A09 attributes,
## which KMeshUndo diffs). flush() writes the working weights to the channels (end() does it; the UI does it per event).
##   params: {"brush": add | subtract | set | smooth, "bone" (the skeleton bone id painted), "radius" (m), "strength"
##            (weight per dab at the centre at full pressure), "value" (set's target), "falloff", "spacing",
##            "mirror" (X mirror), "mirror_of" {bone id: its _l <-> _r partner}, "locks" {bone id: true}}
##   BRUSHES, per vertex inside the radius, s = strength * falloff(d / radius) * pressure:
##     add: B += s     subtract: B -= s     set: B moves toward value by min(s, 1) of the way (s = 1: B = value)
##     smooth: every unlocked bone's weight moves toward the mean of the vertex's neighbours (read before the dab) by
##     min(s, 1) of the way
##   NORMALISE (every touched vertex, every dab, so it holds after every stroke): LOCKED bones never change; the painted
##   bone B gets its target, clamped to [0, 1 - the locked weights]; the OTHER unlocked bones rescale together to fill
##   what is left (so an add of s raises B by exactly s and the sum stays 1). When no other unlocked bone is there to take
##   the rest, B takes it (a vertex with no weights painted B is all B; a subtract on a vertex that is only B does
##   nothing). At most MAX_INFL influences: the smallest unlocked others are dropped and the rest rescale again; weights
##   under EPS are dropped. A painted bone that is locked leaves the vertex alone.
##   X MIRROR: each dab is laid again at the mirrored point (-x, y, z, mesh space) on the mirrored bone (mirror_name:
##   _l <-> _r, .l <-> .r, left <-> right); a centre bone painted on the plane is not laid twice.
##   HEAT: heat_color(w) blue (0) -> cyan -> green -> yellow -> red (1), the colours Blender paints weights in.

const ADD := "add"
const SUB := "subtract"
const SET := "set"
const SMOOTH_W := "smooth"
const MODES := [ADD, SUB, SET, SMOOTH_W]
const MAX_INFL := 4
const EPS := 1e-6
const CH_BONES := KMeshAutoWeights.CH_BONES
const CH_WEIGHTS := KMeshAutoWeights.CH_WEIGHTS
const WDEFAULTS := {"brush": ADD, "bone": -1, "radius": 0.05, "strength": 0.2, "value": 1.0, "falloff": F_SMOOTH,
	"spacing": 0.1, "mirror": false, "mirror_of": {}, "locks": {}, "sym_x": false, "invert": false}

var cb := PackedColorArray()   # working bone ids (one Color per vertex)
var cw := PackedColorArray()   # working weights
var touched := {}              # vertex -> true, this stroke


static func heat_color(x: float) -> Color:
	var t := clampf(x, 0.0, 1.0) * 4.0
	if t < 1.0:
		return Color(0.0, t, 1.0)
	if t < 2.0:
		return Color(0.0, 1.0, 2.0 - t)
	if t < 3.0:
		return Color(t - 2.0, 1.0, 0.0)
	return Color(1.0, 4.0 - t, 0.0)


## the left / right partner of a bone name ("" = it has none): _l <-> _r, .l <-> .r (either case), left <-> right
static func mirror_name(n: String) -> String:
	for pr in [["_l", "_r"], ["_L", "_R"], [".l", ".r"], [".L", ".R"]]:
		if n.ends_with(pr[0]):
			return n.trim_suffix(pr[0]) + pr[1]
		if n.ends_with(pr[1]):
			return n.trim_suffix(pr[1]) + pr[0]
	for pr in [["left", "right"], ["Left", "Right"], ["LEFT", "RIGHT"]]:
		if n.contains(pr[0]):
			return n.replace(pr[0], pr[1])
		if n.contains(pr[1]):
			return n.replace(pr[1], pr[0])
	return ""


## {bone id: partner id} over a bone list ({"name", "id"} each: KMeshAutoWeights.bones_from_skeleton)
static func mirror_map(bones: Array) -> Dictionary:
	var by := {}
	for b in bones:
		by[String(b["name"])] = int(b["id"])
	var out := {}
	for b in bones:
		var mn := mirror_name(String(b["name"]))
		if mn != "" and by.has(mn):
			out[int(b["id"])] = by[mn]
	return out


## the weight of `bone` on vertex v as the mesh stores it (0 when the mesh has no channels)
static func weight_of(m: KMesh, v: int, bone: int) -> float:
	if not (m.has_attr(CH_BONES) and m.has_attr(CH_WEIGHTS)):
		return 0.0
	var b: Color = (m.attr_data(CH_BONES) as PackedColorArray)[v]
	var w: Color = (m.attr_data(CH_WEIGHTS) as PackedColorArray)[v]
	var s := 0.0
	for q in MAX_INFL:
		if roundi(b[q]) == bone:
			s += w[q]
	return s


## the channels the mesh will be painted on, added (empty) when missing
static func ensure_channels(m: KMesh) -> void:
	if not m.has_attr(CH_BONES):
		m.add_attr(CH_BONES, KMesh.AD_VERT, TYPE_COLOR, Color(-1, -1, -1, -1))
	if not m.has_attr(CH_WEIGHTS):
		m.add_attr(CH_WEIGHTS, KMesh.AD_VERT, TYPE_COLOR, Color(0, 0, 0, 0))


func begin(m: KMesh, params := {}) -> void:
	var pp := WDEFAULTS.duplicate()
	pp.merge(params, true)
	pp["sym_x"] = false   # the mirror here is a second dab, not the sculpt's displacement mirror
	super.begin(m, pp)
	touched = {}
	var nv := m.verts.size()
	if m.has_attr(CH_BONES) and m.has_attr(CH_WEIGHTS):
		cb = (m.attr_data(CH_BONES) as PackedColorArray).duplicate()
		cw = (m.attr_data(CH_WEIGHTS) as PackedColorArray).duplicate()
	else:
		cb = PackedColorArray()
		cb.resize(nv)
		cb.fill(Color(-1, -1, -1, -1))
		cw = PackedColorArray()
		cw.resize(nv)
		cw.fill(Color(0, 0, 0, 0))


## the working weights onto the mesh's channels (added when missing). Nothing is written when no vertex changed.
func flush() -> void:
	if touched.is_empty() or mesh == null:
		return
	ensure_channels(mesh)
	mesh.set_attr_data(CH_BONES, cb)
	mesh.set_attr_data(CH_WEIGHTS, cw)


func end() -> void:
	flush()
	super.end()


## vertex v's influences as {bone: weight} (weights above zero only)
func infl(v: int) -> Dictionary:
	var out := {}
	var b := cb[v]
	var w := cw[v]
	for q in MAX_INFL:
		var id := roundi(b[q])
		if id >= 0 and w[q] > 0.0:
			out[id] = float(out.get(id, 0.0)) + w[q]
	return out


func _store(v: int, d: Dictionary) -> void:
	var keys := d.keys()
	keys.sort_custom(func(a, c): return d[a] > d[c] or (d[a] == d[c] and a < c))
	var b := Color(-1, -1, -1, -1)
	var w := Color(0, 0, 0, 0)
	for q in mini(keys.size(), MAX_INFL):
		b[q] = float(keys[q])
		w[q] = float(d[keys[q]])
	cb[v] = b
	cw[v] = w
	touched[v] = true


# ---------------------------------------------------------------- the per-vertex rules (static: testable alone)

## paint bone `bone` on influences `inf` to `target`, then normalise by the lock rule. Returns the new influences
## ({} = leave the vertex as it is)
static func paint_rule(inf: Dictionary, bone: int, target: float, locks: Dictionary) -> Dictionary:
	if locks.has(bone):
		return {}
	var lsum := 0.0
	for k in inf:
		if locks.has(k):
			lsum += float(inf[k])
	var avail := 1.0 - lsum
	if avail <= EPS:
		return {}
	var t := clampf(target, 0.0, avail)
	var out := {}
	for k in inf:
		if locks.has(k):
			out[k] = inf[k]
	var others := {}
	for k in inf:
		if k != bone and not locks.has(k) and float(inf[k]) > EPS:
			others[k] = float(inf[k])
	return _fill(out, bone, t, others, avail)


## smooth: every unlocked bone toward `mean` ({bone: weight}, the neighbours' average) by f of the way; locked bones keep
static func smooth_rule(inf: Dictionary, mean: Dictionary, f: float, locks: Dictionary) -> Dictionary:
	var lsum := 0.0
	var out := {}
	for k in inf:
		if locks.has(k):
			lsum += float(inf[k])
			out[k] = inf[k]
	var avail := 1.0 - lsum
	if avail <= EPS:
		return {}
	var keys := {}
	for k in inf:
		keys[k] = true
	for k in mean:
		keys[k] = true
	var mix := {}
	var tot := 0.0
	for k in keys:
		if locks.has(k):
			continue
		var x := lerpf(float(inf.get(k, 0.0)), float(mean.get(k, 0.0)), clampf(f, 0.0, 1.0))
		if x > EPS:
			mix[k] = x
			tot += x
	if tot <= EPS:
		return {}
	for k in mix:
		mix[k] = float(mix[k]) * avail / tot
	return _fill(out, -1, 0.0, mix, avail)


## out (the locked bones) + bone at t + the others rescaled to fill avail - t, at most MAX_INFL, tiny ones dropped
static func _fill(out: Dictionary, bone: int, t: float, others: Dictionary, avail: float) -> Dictionary:
	var keys := others.keys()
	keys.sort_custom(func(a, c): return others[a] > others[c] or (others[a] == others[c] and a < c))
	var room := MAX_INFL - out.size() - (1 if bone >= 0 and t > EPS else 0)
	if keys.size() > maxi(room, 0):
		keys.resize(maxi(room, 0))
	var osum := 0.0
	for k in keys:
		osum += float(others[k])
	var rest := avail - t
	if osum > EPS:
		for k in keys:
			out[k] = float(others[k]) * rest / osum
	elif bone >= 0:
		t = avail   # nobody else to take the rest: the painted bone does
	if bone >= 0 and t > EPS:
		out[bone] = t
	for k in out.keys():
		if float(out[k]) <= EPS:
			out.erase(k)
	return out


# ---------------------------------------------------------------- one dab

## one dab at `hit` (mesh space); with mirror on, again at the mirrored point on the mirrored bone. Returns the
## vertices changed (both sides)
func dab(hit: Vector3, _normal: Vector3, pressure := 1.0) -> int:
	var bone := int(p["bone"])
	var n := _dab_one(hit, bone, pressure)
	if p["mirror"]:
		var hm := Vector3(-hit.x, hit.y, hit.z)
		var bm := int((p["mirror_of"] as Dictionary).get(bone, bone))
		if not (bm == bone and hit.distance_to(hm) < 1e-6):
			n += _dab_one(hm, bm, pressure)
	_has_last = true
	_last = hit
	dabs += 1
	return n


func _dab_one(c: Vector3, bone: int, pressure: float) -> int:
	var br := String(p["brush"])
	if bone < 0 and br != SMOOTH_W:
		return 0
	var r := float(p["radius"])
	var a := float(p["strength"]) * clampf(pressure, 0.0, 1.0)
	var fk := String(p["falloff"])
	var locks: Dictionary = p["locks"]
	var ids := verts_in(c, r)
	var vp := mesh.verts
	var news := {}
	for v in ids:
		var s := a * falloff(fk, vp[v].distance_to(c) / r)
		if s <= 0.0:
			continue
		var inf := infl(v)
		var nd := {}
		match br:
			ADD, SUB, SET:
				var cur := float(inf.get(bone, 0.0))
				var target := cur + s
				if br == SUB:
					target = cur - s
				elif br == SET:
					target = cur + (float(p["value"]) - cur) * minf(s, 1.0)
				nd = paint_rule(inf, bone, target, locks)
			SMOOTH_W:
				var nb := mesh.vert_neighbors(v)
				if nb.is_empty():
					continue
				var mean := {}
				for u in nb:
					var iu := infl(u)
					for k in iu:
						mean[k] = float(mean.get(k, 0.0)) + float(iu[k]) / nb.size()
				nd = smooth_rule(inf, mean, s, locks)
		if not nd.is_empty():
			news[v] = nd
	for v in news:   # written after every vertex has been read: smooth reads the neighbours as they were
		_store(v, news[v])
	return news.size()
