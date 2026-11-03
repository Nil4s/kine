class_name FingerBleedCheck
extends RefCounted
## C05 (complaint #618, "one finger's bones pull neighbours and deform the mesh"): the per-finger weight check, run on the
## stored weights (KMeshAutoWeights.read, the H01 channels) after autoweights. A vert belongs to the finger whose bones
## hold most of its finger weight (thumb_l, index_l ... each side apart). Every other finger's bones holding more than
## BLEED_MAX of that vert's weight is bleed: the vert is flagged, to the neighbour it bleeds into. Palm and hand bones
## are not fingers, so weight on them is not bleed. Read-only.

const BLEED_MAX := 0.05
const OWN_MIN := 0.5   # of a vert's weight, the share on finger bones under which it is a palm vert, not a finger vert
const SEL_VERT := 0


static func key_of(nm: String) -> String:
	var f := HandShapeCheck.finger_of(nm)
	return "" if f == "" else "%s_%s" % [f, HandShapeCheck.side_of(nm)]


## {"skinned": bool, "fingers": {key: {"owned", "bleeding": [verts], "to": {key: n}, "worst": w}}, "findings": [...]}
static func check(mesh: KMesh, bones: Array) -> Dictionary:
	var out := {"skinned": false, "fingers": {}, "findings": []}
	var rd := KMeshAutoWeights.read(mesh)
	if rd.is_empty():
		return out
	out["skinned"] = true
	var kid := {}   # bone id -> finger key
	for b in bones:
		var k := key_of(String(b["name"]))
		if k != "":
			kid[int(b["id"])] = k
	var ids: PackedInt32Array = rd["ids"]
	var w: PackedFloat32Array = rd["w"]
	var per: Dictionary = out["fingers"]
	for k in kid.values():
		if not per.has(k):
			per[k] = {"owned": 0, "bleeding": [], "to": {}, "worst": 0.0}
	var nv := ids.size() / 4
	for v in nv:
		var by := {}
		var tot := 0.0
		for q in 4:
			var id := ids[v * 4 + q]
			var wt := w[v * 4 + q]
			if wt > 0.0:
				tot += wt
				if kid.has(id):
					by[kid[id]] = float(by.get(kid[id], 0.0)) + wt
		var on := 0.0
		var own := ""
		for k in by:
			on += by[k]
			if own == "" or by[k] > by[own]:
				own = k
		if own == "" or tot <= 1e-6 or on / tot < OWN_MIN:
			continue
		per[own]["owned"] += 1
		var bleed := 0.0
		var to := ""
		for k in by:
			if k != own:
				bleed += by[k]
				if to == "" or by[k] > by[to]:
					to = k
		bleed /= tot
		if bleed > BLEED_MAX:
			per[own]["bleeding"].append(v)
			per[own]["to"][to] = int(per[own]["to"].get(to, 0)) + 1
			per[own]["worst"] = maxf(per[own]["worst"], bleed)
	for k in per:
		var bl: Array = per[k]["bleeding"]
		if bl.is_empty():
			continue
		var tos: Dictionary = per[k]["to"]
		var names := []
		for t in tos:
			names.append("%s (%d)" % [t, tos[t]])
		out["findings"].append({"kind": "finger_bleed", "count": bl.size(), "items": bl, "mode": SEL_VERT, "pts": 0.0,
			"title": "%s bleeds weight into %s: %d of %d verts, worst %d %%" % [k, ", ".join(names), bl.size(), per[k]["owned"], roundi(per[k]["worst"] * 100.0)],
			"next": "paint those verts back onto the %s bones (weight paint, Subtract on the neighbour), then re-check" % k})
	return out


## the one-line summary of the check, for the step after autoweights ("" when the mesh has no finger weights)
static func say(mesh: KMesh, bones: Array) -> String:
	var r := check(mesh, bones)
	if not r["skinned"] or r["fingers"].is_empty():
		return ""
	var fs: Array = r["findings"]
	return "finger weights clean" if fs.is_empty() else "finger bleed: " + "; ".join(fs.map(func(f): return f["title"]))
