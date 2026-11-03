class_name HandShapeCheck
extends RefCounted
## C05 (complaint #619, "warped hands on imported meshes"): the hand-shape check on an imported mesh, before rigging.
## Looks only at the mesh near one hand: the verts within REACH of the wrist bone, each given to its nearest hand / finger
## bone segment (bones as KMeshAutoWeights.bones_from_skeleton gives them: {"name","a","ends"}). Findings (the shape of
## scripts/model_checks.gd's: kind, title, next, mode, items, count):
##   missing_finger : a finger bone with fewer than FINGER_MIN_VERTS mesh verts on it (the finger is gone or fused)
##   stretched      : an edge longer than STRETCH x the median edge of the hand (a pulled-out sliver)
##   spike          : a vert farther than OUT_R from every hand / finger bone
##   thin_finger / fat_finger : a finger whose mean radius is under R_MIN or over R_MAX (collapsed or bloated)
## Nothing here changes a mesh; HandShapeCheck.check() is read-only.

const FINGERS := ["thumb", "index", "middle", "ring", "pinky"]
const REACH := 0.16            # m from the wrist: the hand's region
const FINGER_MIN_VERTS := 6
const STRETCH := 4.0
const OUT_R := 0.045           # m
const R_MIN := 0.002           # m
const R_MAX := 0.03            # m
const SEL_VERT := 0
const SEL_EDGE := 1


## "thumb".."pinky" when the bone name has a finger in it, else ""
static func finger_of(nm: String) -> String:
	var l := nm.to_lower()
	if l.contains("little"):
		return "pinky"
	for f in FINGERS:
		if l.contains(f):
			return f
	return ""


## "l" / "r" / "" from the name (_l, .l, -l, left)
static func side_of(nm: String) -> String:
	var l := nm.to_lower()
	if l.contains("left") or l.ends_with("_l") or l.ends_with(".l") or l.ends_with("-l") or l.contains("_l_"):
		return "l"
	if l.contains("right") or l.ends_with("_r") or l.ends_with(".r") or l.ends_with("-r") or l.contains("_r_"):
		return "r"
	return ""


static func _seg_d(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := 0.0 if ab.length_squared() < 1e-12 else clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## the sides that have a hand bone in `bones`
static func sides(bones: Array) -> Array:
	var out := []
	for b in bones:
		var nm := String(b["name"])
		if nm.to_lower().contains("hand") and finger_of(nm) == "" and not out.has(side_of(nm)):
			out.append(side_of(nm))
	return out


static func _f(kind: String, items: Array, mode: int, title: String, next: String) -> Dictionary:
	return {"kind": kind, "count": items.size(), "items": items, "mode": mode, "title": title, "next": next, "pts": 0.0}


## the hand of `side` ("l" / "r" / ""): {"ok", "region", "fingers": {name: {"verts", "radius"}}, "findings": [...]}.
## xf takes the mesh's verts into the bones' space.
static func check(mesh: KMesh, bones: Array, side := "l", xf := Transform3D.IDENTITY) -> Dictionary:
	var segs := []   # {finger, a, b}
	var wrist := Vector3.INF
	for b in bones:
		var nm := String(b["name"])
		var low := nm.to_lower()
		if side_of(nm) != side:
			continue
		var fg := finger_of(nm)
		if fg == "" and not low.contains("hand"):
			continue
		if fg == "" and wrist == Vector3.INF:
			wrist = b["a"]
		for e in (b["ends"] as PackedVector3Array):
			segs.append({"finger": fg, "a": b["a"], "b": e})
	var out := {"ok": true, "region": 0, "fingers": {}, "findings": [], "error": ""}
	if wrist == Vector3.INF or mesh == null or mesh.verts.is_empty():
		out["error"] = "no hand bone '%s' / no mesh" % side
		return out
	var nv := mesh.verts.size()
	var P := PackedVector3Array()
	P.resize(nv)
	var region := {}
	var owner_f := {}
	var dist := {}
	for v in nv:
		P[v] = xf * mesh.verts[v]
		if P[v].distance_to(wrist) > REACH:
			continue
		var best := 1e9
		var bf := ""
		for s in segs:
			var d := _seg_d(P[v], s["a"], s["b"])
			if d < best:
				best = d
				bf = s["finger"]
		region[v] = true
		owner_f[v] = bf
		dist[v] = best
	out["region"] = region.size()
	var present := {}
	for s in segs:
		if s["finger"] != "":
			present[s["finger"]] = true
	var per := {}
	for f in present:
		per[f] = {"verts": [], "radius": 0.0}
	for v in region:
		var f: String = owner_f[v]
		if f != "" and dist[v] <= OUT_R:
			per[f]["verts"].append(v)
			per[f]["radius"] += dist[v]
	for f in per:
		var n: int = (per[f]["verts"] as Array).size()
		per[f]["radius"] = per[f]["radius"] / maxf(1, n)
	out["fingers"] = per
	var fs: Array = out["findings"]
	var all_region: Array = region.keys()
	for f in FINGERS:
		if present.has(f) and (per[f]["verts"] as Array).size() < FINGER_MIN_VERTS:
			fs.append(_f("missing_finger", all_region, SEL_VERT, "the %s finger has %d verts on it (needs %d): it is missing or fused" % [f, (per[f]["verts"] as Array).size(), FINGER_MIN_VERTS],
				"rebuild that finger in the mesh, or re-import from the source; the hand verts are selected"))
	var lens := []
	var ed := {}
	for fc in mesh.faces:
		var ff: PackedInt32Array = fc
		for i in ff.size():
			var a := ff[i]
			var b := ff[(i + 1) % ff.size()]
			if region.has(a) and region.has(b) and a != b:
				ed[Vector2i(mini(a, b), maxi(a, b))] = P[a].distance_to(P[b])
	for k in ed:
		lens.append(ed[k])
	lens.sort()
	var med: float = lens[lens.size() / 2] if not lens.is_empty() else 0.0
	var st := []
	for k in ed:
		if med > 1e-9 and ed[k] > STRETCH * med:
			st.append(k)
	out["median_edge"] = med
	if not st.is_empty():
		fs.append(_f("stretched", st, SEL_EDGE, "%d hand edges are over %.0f x the hand's median edge (%.1f mm): stretched slivers" % [st.size(), STRETCH, med * 1000.0],
			"move or delete the pulled-out verts; the edges are selected"))
	var sp := []
	for v in region:
		if dist[v] > OUT_R:
			sp.append(v)
	if not sp.is_empty():
		fs.append(_f("spike", sp, SEL_VERT, "%d hand verts are over %.0f cm from every finger bone: spikes" % [sp.size(), OUT_R * 100.0],
			"pull them back onto the hand, or delete them; the verts are selected"))
	for f in FINGERS:
		if not present.has(f) or (per[f]["verts"] as Array).size() < FINGER_MIN_VERTS:
			continue
		var r: float = per[f]["radius"]
		if r < R_MIN:
			fs.append(_f("thin_finger", per[f]["verts"], SEL_VERT, "the %s finger is collapsed: mean radius %.1f mm (under %.0f mm)" % [f, r * 1000.0, R_MIN * 1000.0], "scale the finger's verts out; they are selected"))
		elif r > R_MAX:
			fs.append(_f("fat_finger", per[f]["verts"], SEL_VERT, "the %s finger is bloated: mean radius %.1f cm (over %.0f cm)" % [f, r * 100.0, R_MAX * 100.0], "scale the finger's verts in; they are selected"))
	out["ok"] = fs.is_empty()
	return out
