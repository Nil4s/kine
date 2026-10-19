## hit_boxes.gd - HIT AND HURT BOXES PER FRAME (ROADMAP 36). The data and the maths; the dialogs are hit_boxes_ui.gd.
##
## A scene keeps its boxes in Scene.boxes (the file's "boxes" key, written only when there is one). Each entry covers an
## INCLUSIVE range of frames f0..f1 at the frame data's fps (frame_data.gd: frame f is the pose at t = f / fps):
##   {"kind": "hit", "part": P, "f0", "f1", "damage": D, "hitstun": H}
##       an ATTACK capsule riding on part P: any body capsule (Body.BODY, Body.WIDE) or the bat (bat_handle, bat_barrel)
##       or the off-hand weapon (wep2_handle, wep2_blade). Its ends are the part's own capsule ends moved by the optional
##       "da" (the start end) and "db" (the finish end), [x, y, z] metres in the PART'S frame, so the box moves with the part.
##       The optional "r" is the radius (default: the part's own radius). Damage in points, hitstun in frames.
##   {"kind": "hurt", "part": P or "*", "f0", "f1", "scale": S}
##       a VULNERABLE capsule's radius times S (shrink below 1, grow above 1). "*" = every body capsule.
##   {"kind": "hurt", "part": P or "*", "f0", "f1", "off": true}
##       that capsule is OFF for those frames. part "*" with off = INVINCIBLE (no hurtbox at all).
## Without an edit the hurtboxes are one capsule per body segment: Body.BODY + Body.WIDE, the same as before the editor.
## An empty list is no edit: the analysis and every export are then those of the scene without this key, bit for bit.
## The exported frame data (FrameData.to_json) carries the hit boxes in "hitboxes" with "src": "box" (and part, damage,
## hitstun) on the frames they cover, and the edited hurtboxes in "hurtboxes"; the scene's entries are at the top as "boxes".
## Units: metres, +Y up (the body's own space). Frames are the frame data's fps (24 / 30 / 60 / 120).
class_name HitBoxes
extends RefCounted

const KINDS := ["hit", "hurt"]
const SCALE_MIN := 0.05
const SCALE_MAX := 4.0
const DAMAGE_MAX := 9999.0
const HITSTUN_MAX := 240
const ALL := "*"   # the hurt part for every body capsule


## the parts an attack box may ride on: every body capsule and both weapons
static func hit_parts() -> Array:
	return Body.BODY + Body.WIDE.keys() + Body.WEAPON + Body.WEAPON2


## the parts a vulnerable box may name: every body capsule (ALL = all of them)
static func hurt_parts() -> Array:
	return Body.BODY + Body.WIDE.keys()


static func is_invincible(e: Dictionary) -> bool:
	return String(e.get("kind", "")) == "hurt" and bool(e.get("off", false)) and String(e.get("part", "")) == ALL


static func _v3(a) -> Vector3:
	if a is Vector3:
		return a
	if a is Array and (a as Array).size() == 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO


static func _arr(v: Vector3) -> Array:
	return [snappedf(v.x, 1e-6), snappedf(v.y, 1e-6), snappedf(v.z, 1e-6)]


## the list as the scene keeps it: unknown kinds and parts dropped, numbers clamped, frames ordered, keys in a fixed order
static func clean(list) -> Array:
	var out := []
	if not (list is Array):
		return out
	for e in list:
		if not (e is Dictionary):
			continue
		var kind := String(e.get("kind", ""))
		var part := String(e.get("part", ""))
		var f0 := maxi(0, int(e.get("f0", 0)))
		var f1 := maxi(f0, int(e.get("f1", f0)))
		if kind == "hit":
			if not (part in hit_parts()):
				continue
			var c := {"kind": "hit", "part": part, "f0": f0, "f1": f1,
				"damage": clampf(float(e.get("damage", 0.0)), 0.0, DAMAGE_MAX),
				"hitstun": clampi(int(e.get("hitstun", 0)), 0, HITSTUN_MAX)}
			if e.has("da"):
				c["da"] = _arr(_v3(e["da"]))
			if e.has("db"):
				c["db"] = _arr(_v3(e["db"]))
			if e.has("r") and float(e["r"]) > 0.0:
				c["r"] = snappedf(float(e["r"]), 1e-6)
			out.append(c)
		elif kind == "hurt":
			if not (part == ALL or part in hurt_parts()):
				continue
			var h := {"kind": "hurt", "part": part, "f0": f0, "f1": f1}
			if bool(e.get("off", false)):
				h["off"] = true
			else:
				h["scale"] = clampf(float(e.get("scale", 1.0)), SCALE_MIN, SCALE_MAX)
			out.append(h)
	return out


## the file's form (the same as clean: a box list is its own file form)
static func to_file(list) -> Array:
	return clean(list)


static func from_file(list) -> Array:
	return clean(list)


## the part's frame: a rotation the box's offsets are read in (the joint's, the bat's, the off-hand weapon's)
static func part_frame(B: Body, part: String) -> Quaternion:
	if part in Body.WEAPON:
		return (B.wep_xform()[1] as Quaternion)
	if part in Body.WEAPON2:
		return (B.wep2_xform()[1] as Quaternion)
	var jn: String = Body.WIDE[part][0] if Body.WIDE.has(part) else part
	return B.G[jn]


## an attack box's capsule now: {a, b, r} in metres (the part's capsule, its ends moved by da / db in the part's frame)
static func hit_cap(B: Body, e: Dictionary) -> Dictionary:
	var part := String(e["part"])
	var c: Array = B.cap(part)
	var q := part_frame(B, part)
	var a: Vector3 = (c[0] as Vector3) + q * _v3(e.get("da", [0.0, 0.0, 0.0]))
	var b: Vector3 = (c[1] as Vector3) + q * _v3(e.get("db", [0.0, 0.0, 0.0]))
	var r := float(e["r"]) if e.has("r") else float(B.rad[part])
	return {"a": a, "b": b, "r": r}


static func _in(e: Dictionary, f: int) -> bool:
	return f >= int(e["f0"]) and f <= int(e["f1"])


## the attack boxes on frame f: each {a, b, r, part, damage, hitstun, src: "box"}
static func hit_list(B: Body, boxes: Array, f: int) -> Array:
	var out := []
	for e in boxes:
		if String(e.get("kind", "")) != "hit" or not _in(e, f):
			continue
		var c := hit_cap(B, e)
		c["part"] = e["part"]
		c["damage"] = float(e["damage"])
		c["hitstun"] = int(e["hitstun"])
		c["src"] = "box"
		out.append(c)
	return out


## the vulnerable capsules on frame f: one per body capsule (Body.BODY + Body.WIDE), radius scaled, the off ones left out.
## With no edits this is the same list FrameData drew before the editor (the same parts, order, radii).
static func hurt_list(B: Body, boxes: Array, f: int) -> Array:
	var out := []
	for part in Body.BODY + Body.WIDE.keys():
		var c: Array = B.cap(part)
		var r := float(B.rad[part])
		var on := true
		for e in boxes:
			if String(e.get("kind", "")) != "hurt" or not _in(e, f):
				continue
			if String(e["part"]) != ALL and String(e["part"]) != part:
				continue
			if bool(e.get("off", false)):
				on = false
			else:
				r *= float(e.get("scale", 1.0))
		if on:
			out.append({"a": c[0], "b": c[1], "r": r})
	return out


## the timeline's lane: [{"row": 0 (attack) / 1 (vulnerable), "kind": "hit" / "hurt" / "inv", "t0", "t1"}] in seconds
## (t = frame / fps; t1 is the END of the last frame, so a 10-14 range is [10 / fps, 15 / fps))
static func lanes(boxes: Array, fps: float) -> Array:
	var out := []
	for i in boxes.size():
		var e: Dictionary = boxes[i]
		var kind := "hit"
		var row := 0
		if String(e.get("kind", "")) == "hurt":
			row = 1
			kind = "inv" if is_invincible(e) else "hurt"
		out.append({"row": row, "kind": kind, "t0": float(e["f0"]) / fps, "t1": float(int(e["f1"]) + 1) / fps, "i": i})
	return out


## the boxes as a side-swapped copy (Scene.mirror_file): a part to its twin (_l <-> _r; a weapon or "*" stays), an
## attack box's offsets reflected across x = 0 (x negated, as Body.mirror_pose does to a part's frame). Ranges and numbers free.
static func mirror_file(list) -> Array:
	var out := []
	for e in clean(list):
		var c: Dictionary = e.duplicate(true)
		if String(c["part"]) != ALL:
			c["part"] = Body.twin(String(c["part"]))
		for k in ["da", "db"]:
			if c.has(k):
				var v := _v3(c[k])
				c[k] = _arr(Vector3(-v.x, v.y, v.z))
		out.append(c)
	return out


## the frame range of one entry as text, for the lists: "10-14"
static func range_text(e: Dictionary) -> String:
	return "%d-%d" % [int(e["f0"]), int(e["f1"])] if int(e["f0"]) != int(e["f1"]) else str(int(e["f0"]))


## one entry as a line for the lists and the export's notes
static func describe(e: Dictionary) -> String:
	if String(e["kind"]) == "hit":
		return "hit %s  frames %s  damage %.0f  hitstun %d" % [e["part"], range_text(e), float(e["damage"]), int(e["hitstun"])]
	if is_invincible(e):
		return "invincible  frames %s" % range_text(e)
	if bool(e.get("off", false)):
		return "hurt off %s  frames %s" % [e["part"], range_text(e)]
	return "hurt %s x%.2f  frames %s" % [e["part"], float(e.get("scale", 1.0)), range_text(e)]
