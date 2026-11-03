## SIDE CHECK (C47, complaint #274: a rig mirror "needs strict left/right joint naming"; detect the side from geometry, show a check).
## AnimImport.classify reads the side from the bone NAME. This checks the names against where the bones are: each mapped left bone
## must sit on the left of its right twin. Words only; the import is unchanged (as RigPrecheck).
##   a pair on the wrong side of the others   "<bone>_l is on the right of <bone>_r while the other pairs are the other way"
##   the whole rig named the other way round   the left bones are on the body's right (up x forward, the forward from foot -> ball)
## Pure function on AnimImport.load_source's src and the bone mapping.
class_name SideCheck
extends RefCounted

const PAIRS := ["thigh", "calf", "foot", "ball", "upperarm", "lowerarm", "hand", "clavicle"]
const MIN_SEP := 0.02   # metres: a pair closer than this across the body says nothing about its side


static func _pos(src: Dictionary, mp: Dictionary, j: String) -> Variant:
	if not mp.has(j):
		return null
	return ((src["rest"] as Array)[mp[j]] as Transform3D).origin


## {"ok", "findings": [{"kind", "bone", "text"}], "text": one line or ""}
static func check(src: Dictionary, mapping: Dictionary) -> Dictionary:
	var f := []
	var mp: Dictionary = mapping.get("map", {})
	var up := Vector3.ZERO
	if mp.has("pelvis"):
		for j in ["head", "neck_01", "spine_03", "spine_02", "spine_01"]:
			if mp.has(j):
				up = (_pos(src, mp, j) as Vector3) - (_pos(src, mp, "pelvis") as Vector3)
				break
	if up.length() < 1e-6:
		return {"ok": true, "findings": [], "text": ""}
	up = up.normalized()
	var ds := {}
	var sum := Vector3.ZERO
	for p in PAIRS:
		var a: Variant = _pos(src, mp, p + "_l")
		var b: Variant = _pos(src, mp, p + "_r")
		if a == null or b == null:
			continue
		var d: Vector3 = (a as Vector3) - (b as Vector3)
		d -= up * d.dot(up)
		if d.length() < MIN_SEP:
			continue
		ds[p] = d
		sum += d.normalized()
	if ds.size() < 2 or sum.length() < 1e-6:
		return {"ok": true, "findings": [], "text": ""}
	var ax := sum.normalized()   # the majority's idea of "left"
	var words := []
	for p in ds:
		if (ds[p] as Vector3).dot(ax) < 0.0:
			var t := "%s_l is on the right of %s_r while the other pairs are the other way: a left and right name swapped" % [p, p]
			f.append({"kind": "swapped_pair", "bone": p, "text": t})
			words.append(t)
	var fwd := Vector3.ZERO
	for s in ["_l", "_r"]:
		var fo: Variant = _pos(src, mp, "foot" + s)
		var ba: Variant = _pos(src, mp, "ball" + s)
		if fo != null and ba != null:
			fwd += (ba as Vector3) - (fo as Vector3)
	fwd -= up * fwd.dot(up)
	if fwd.length() > 1e-4:
		var geo_left := up.cross(fwd.normalized())   # up x forward = left (Kine: Y x Z = X)
		if ax.dot(geo_left) < 0.0:
			var t2 := "the bones named left are on the body's right (the feet point the other way): left and right are swapped in the whole rig"
			f.append({"kind": "swapped_rig", "bone": "", "text": t2})
			words.append(t2)
	return {"ok": f.is_empty(), "findings": f, "text": ("Side check: " + "; ".join(words)) if not f.is_empty() else ""}
