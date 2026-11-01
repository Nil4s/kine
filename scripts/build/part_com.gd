class_name PartCom
extends RefCounted
## part_com.gd - P128 CENTRE OF MASS + TIP-OVER WARNING (Friday plan item 128). Pure reading: nothing in the Part changes.
## The centre of mass is the volume-weighted middle of the kernel's mass properties per body (one density, so volume is the weight), in the
## Part frame, metres. Whether it tips is PartStand's rule (the middle against the convex hull of the feet): this file only adds the middle
## itself and the warning sentence, shown in the size line under the part.


## {"ok": bool, "com": Vector3 (Part frame, m), "tips": bool, "margin_mm": float (+ inside the feet, - past them), "warn": String ("" when it stands)}
static func read(rec: Dictionary) -> Dictionary:
	if not Part.available():
		return {"ok": false, "com": Vector3.ZERO, "tips": false, "margin_mm": 0.0, "warn": ""}
	var res := Part.replay_memo(rec, {"props": true, "inc": true})   # s168: from the cached steps
	var props: Array = res.get("props", [])
	if res.get("mesh", null) == null or props.is_empty() or float(res.get("volume", 0.0)) <= 0.0:
		return {"ok": false, "com": Vector3.ZERO, "tips": false, "margin_mm": 0.0, "warn": ""}
	var c := Vector3.ZERO
	var tot := 0.0
	for p in props:
		c += (p["center"] as Vector3) * float(p["volume"])
		tot += float(p["volume"])
	c /= tot
	var st := PartStand.check(rec)
	var mm := float(st.get("margin_mm", 0.0))
	var tips := mm < 0.0
	return {"ok": true, "com": c, "tips": tips, "margin_mm": mm, "warn": warning(mm)}


## the plain-words warning for a margin in mm ("" when the weight is over the feet)
static func warning(margin_mm: float) -> String:
	if margin_mm >= 0.0:
		return ""
	return "It will tip over: its weight is %d mm outside its feet" % roundi(-margin_mm)
