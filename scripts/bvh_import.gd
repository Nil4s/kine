## BVH IMPORT (round 41, GATES WW7; UPGRADES_300 #296, UPGRADES_200 #209 "animation import"). The reader that goes with
## bvh_export.gd. Two steps, so each is testable alone:
##   parse(text)             a BVH file -> {"ok", "why", "joints", "frames", "fps", "dt", "channels"}
##   to_scene(bvh, B, every) a parsed BVH whose joint names are Poser's (one Poser exported) -> {"ok", "scene", "not_mapped",
##                           "missing", "every", ...}
## FORMAT (HIERARCHY / ROOT / JOINT / End Site / OFFSET / CHANNELS / MOTION / Frames: / Frame Time:): the Biovision
## format as Blender's importer reads it (https://projects.blender.org/blender/blender-manual/raw/branch/main/manual/files/import_export/bvh.rst)
## and described in https://research.cs.wisc.edu/graphics/Courses/cs-838-1999/Jeff/BVH.html (read in round 41). A joint's
## rotation is the product of its rotation channels IN THE ORDER LISTED, the first listed outermost (Zrotation Xrotation
## Yrotation = Rz * Rx * Ry), the signs and axes are the exporter's (checked by the round trip, not by the page).
## The channels may come in ANY order, with or without position channels, on any joint.
## WHAT THE EXPORTER WROTE, INVERTED (bvh_export.gd text()): every joint's rotation channels are compose(j, ang[j]) as
## Z-X-Y Euler angles, the root's position channels are B.P["pelvis"] = p0[pelvis] + B.offset. So the import is
##   q = Rz(z) Rx(x) Ry(y)   ->   ang[j] = decompose(B, j, q)   (compose's own inverse, swing-twist)
##   B.offset = root position (+ the root's OFFSET) - p0[pelvis]
## Units are metres (the exporter's); a BVH in centimetres takes scale = 0.01.
## THE CARDS: ONE CARD PER FRAME by default (every = 1). That is the only setting that reproduces the file's motion
## exactly (a frame is a card and sampling at a frame's time returns it unchanged: round-trip tests/bvh_import_test.gd,
## 0.000 deg). A sparse import (every = n: a card every n frames, the last frame always a card; every_for(fps) gives n so
## the cards sit about 0.1 s apart) is the animator's editable form: the in-betweens are the scene's own ease, not the
## file's. The imported scene is LINEAR and unplanted (on_floor off, pin off, natural off, ease "linear"): the file's
## root height and feet are already what the exporter wrote (floor contact and planted feet included), and a second
## floor solve or foot pin on top would move them.
## NOT IN SCOPE: retargeting another skeleton. A joint name Poser does not have is listed in "not_mapped" ("weapon" and
## "weapon2" are the exporter's weapon joints: listed too, the weapon is not rebuilt); a Poser joint the file lacks stays
## at rest and is listed in "missing".
class_name BvhImport
extends RefCounted

const CHAN := ["Xposition", "Yposition", "Zposition", "Xrotation", "Yrotation", "Zrotation"]


static func _fail(why: String) -> Dictionary:
	return {"ok": false, "why": why}


## the text -> {"ok": true, "joints": [{"name", "parent" (index, -1 = root), "offset", "channels" [names], "start" (first
## column of the joint in a frame row), "end" (End Site offset or null)}], "frames": [PackedFloat64Array row per frame],
## "dt", "fps", "n_channels"}, or {"ok": false, "why": a sentence}. Never crashes on a bad file.
static func parse(txt: String) -> Dictionary:
	var tok := PackedStringArray()
	for w in txt.replace("\t", " ").replace("\r", " ").replace("\n", " ").replace("{", " { ").replace("}", " } ").split(" ", false):
		tok.append(w)
	if tok.is_empty():
		return _fail("the file is empty")
	var i := 0
	if tok[0].to_upper() != "HIERARCHY":
		return _fail("not a BVH file: it does not start with HIERARCHY (it starts with \"%s\")" % tok[0].left(20))
	i = 1
	var joints := []
	var stack := []   # indices of the open joints; -1 for an open End Site
	var n_ch := 0
	var sawmotion := false
	while i < tok.size():
		var t := tok[i]
		if t == "MOTION":
			sawmotion = true
			break
		if t == "ROOT" or t == "JOINT":
			if i + 2 >= tok.size() or tok[i + 2] != "{":
				return _fail("%s %s is not followed by {" % [t, tok[i + 1] if i + 1 < tok.size() else ""])
			if t == "JOINT" and (stack.is_empty() or stack.back() < 0):
				return _fail("JOINT %s sits outside any joint" % tok[i + 1])
			if t == "ROOT" and not stack.is_empty():
				return _fail("ROOT %s inside another joint" % tok[i + 1])
			joints.append({"name": tok[i + 1], "parent": -1 if t == "ROOT" else stack.back(), "offset": Vector3.ZERO,
				"channels": [], "start": 0, "end": null})
			stack.append(joints.size() - 1)
			i += 3
		elif t == "End":
			if i + 2 >= tok.size() or tok[i + 1] != "Site" or tok[i + 2] != "{":
				return _fail("End is not followed by Site {")
			if stack.is_empty() or stack.back() < 0:
				return _fail("End Site outside any joint")
			if i + 7 >= tok.size() or tok[i + 3] != "OFFSET" or tok[i + 7] != "}":
				return _fail("the End Site of %s is not OFFSET x y z }" % joints[stack.back()]["name"])
			for k in 3:
				if not tok[i + 4 + k].is_valid_float():
					return _fail("the End Site of %s has a bad number \"%s\"" % [joints[stack.back()]["name"], tok[i + 4 + k]])
			joints[stack.back()]["end"] = Vector3(tok[i + 4].to_float(), tok[i + 5].to_float(), tok[i + 6].to_float())
			i += 8
		elif t == "OFFSET":
			if stack.is_empty() or stack.back() < 0 or i + 3 >= tok.size():
				return _fail("an OFFSET in the wrong place (or cut off)")
			for k in 3:
				if not tok[i + 1 + k].is_valid_float():
					return _fail("the OFFSET of %s has a bad number \"%s\"" % [joints[stack.back()]["name"], tok[i + 1 + k]])
			joints[stack.back()]["offset"] = Vector3(tok[i + 1].to_float(), tok[i + 2].to_float(), tok[i + 3].to_float())
			i += 4
		elif t == "CHANNELS":
			if stack.is_empty() or stack.back() < 0 or i + 1 >= tok.size() or not tok[i + 1].is_valid_int():
				return _fail("a CHANNELS line without a count, or outside a joint")
			var n := tok[i + 1].to_int()
			var jn: String = joints[stack.back()]["name"]
			if n < 0 or n > 24 or i + 1 + n >= tok.size():
				return _fail("%s: CHANNELS %d is cut off or absurd" % [jn, n])
			var names := []
			for k in n:
				var c := tok[i + 2 + k]
				if not c in CHAN:
					return _fail("%s: CHANNELS says %d but \"%s\" is not a channel name (is the count wrong?)" % [jn, n, c])
				if c in names:
					return _fail("%s: the channel %s is listed twice" % [jn, c])
				names.append(c)
			joints[stack.back()]["channels"] = names
			joints[stack.back()]["start"] = n_ch
			n_ch += n
			i += 2 + n
		elif t == "}":
			if stack.is_empty():
				return _fail("a } with no joint open")
			stack.pop_back()
			i += 1
		else:
			return _fail("unexpected \"%s\" in HIERARCHY" % t.left(30))
	if not sawmotion:
		return _fail("the file has no MOTION section (cut off in the HIERARCHY?)")
	if not stack.is_empty():
		return _fail("HIERARCHY: %d joint(s) are never closed with }" % stack.size())
	if joints.is_empty():
		return _fail("HIERARCHY has no joints")
	# MOTION  Frames: N  Frame Time: dt  rows
	i += 1
	if i + 4 >= tok.size() or not tok[i].begins_with("Frames") or not tok[i + 1].is_valid_int():
		if i < tok.size() and tok[i].begins_with("Frames:") and tok[i].length() > 7:
			return _fail("MOTION: write Frames: N with a space")
		return _fail("MOTION is cut off before \"Frames: N\"")
	var nf := tok[i + 1].to_int()
	if tok[i + 2] != "Frame" or tok[i + 3] != "Time:" or not tok[i + 4].is_valid_float():
		return _fail("MOTION: \"Frame Time: seconds\" is missing or cut off")
	var dt := tok[i + 4].to_float()
	if nf < 1:
		return _fail("MOTION: Frames: %d (a motion needs at least one frame)" % nf)
	if dt <= 0.0:
		return _fail("MOTION: Frame Time %s is not positive" % tok[i + 4])
	i += 5
	var have := tok.size() - i
	if have != nf * n_ch:
		var whole := have / maxi(1, n_ch)
		return _fail("MOTION: Frames: %d with %d channels needs %d numbers, the file has %d (%s, %d whole frames)" % [nf, n_ch, nf * n_ch, have,
			"truncated" if have < nf * n_ch else "too many", whole])
	var rows := []
	for f in nf:
		var r := PackedFloat64Array()
		for k in n_ch:
			var s := tok[i + k]
			if not s.is_valid_float():
				return _fail("MOTION frame %d: \"%s\" is not a number" % [f, s.left(20)])
			r.append(s.to_float())
		rows.append(r)
		i += n_ch
	return {"ok": true, "why": "", "joints": joints, "frames": rows, "dt": dt, "fps": 1.0 / dt, "n_channels": n_ch}


## read a file: parse(), or a refusal that names the path
static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail("%s does not exist" % path)
	var r := parse(FileAccess.get_file_as_string(path))
	if not r["ok"]:
		r["why"] = "%s: %s" % [path.get_file(), r["why"]]
	return r


## one joint's rotation in one row: its rotation channels multiplied in the order listed (first outermost)
static func rotation(j: Dictionary, row: PackedFloat64Array) -> Quaternion:
	var q := Quaternion.IDENTITY
	for k in (j["channels"] as Array).size():
		var v := deg_to_rad(row[int(j["start"]) + k])
		match String(j["channels"][k]):
			"Xrotation": q = q * Quaternion(Vector3.RIGHT, v)
			"Yrotation": q = q * Quaternion(Vector3.UP, v)
			"Zrotation": q = q * Quaternion(Vector3.BACK, v)
	return q


## a joint's position channels in one row (zero for an axis it has no channel for), times scale
static func position(j: Dictionary, row: PackedFloat64Array, scale := 1.0) -> Vector3:
	var p := Vector3.ZERO
	for k in (j["channels"] as Array).size():
		var v := row[int(j["start"]) + k] * scale
		match String(j["channels"][k]):
			"Xposition": p.x = v
			"Yposition": p.y = v
			"Zposition": p.z = v
	return p


## Body.decompose, with the swing angle taken as 2 atan2(|v|, w) instead of 2 acos(w): acos of a float32 w within 1e-7
## of 1 is 0, so every swing under ~0.05 deg vanished (round 41: 0.03 deg at a pelvis, measured). Same split, same result
## elsewhere; Body.decompose itself is left as it was.
static func decompose(B: Body, j: String, q: Quaternion) -> Vector3:
	var t: Vector3 = B.t_ax[j]
	var pr := Vector3(q.x, q.y, q.z).dot(t) * t
	var qt := Quaternion(pr.x, pr.y, pr.z, q.w)
	qt = qt.normalized() if qt.length() > 1e-12 else Quaternion.IDENTITY
	var qs := q * qt.inverse()
	if qs.w < 0.0:
		qs = Quaternion(-qs.x, -qs.y, -qs.z, -qs.w)
	var v := Vector3(qs.x, qs.y, qs.z)
	var rv := Vector3.ZERO
	if v.length() > 1e-12:
		rv = v / v.length() * (2.0 * atan2(v.length(), qs.w))
	var tw := 2.0 * atan2(Vector3(qt.x, qt.y, qt.z).dot(t), qt.w)
	if tw > PI:
		tw -= TAU
	elif tw < -PI:
		tw += TAU
	return Vector3(rad_to_deg(rv.dot(B.b_ax[j])), rad_to_deg(rv.dot(B.a_ax[j])), rad_to_deg(tw))


## cards about every 0.1 s: the frame step for a sparse import at this fps
static func every_for(fps: float) -> int:
	return maxi(1, int(round(0.1 * fps)))


## a parsed BVH (Poser joint names) -> {"ok", "scene": Scene, "not_mapped": [names], "missing": [Poser joints the file lacks],
## "every", "cards", "text": a sentence to show}. B is only read (its rest skeleton and axes), its state is not changed.
static func to_scene(bvh: Dictionary, B: Body, every := 1, scale := 1.0, scene_name := "bvh_import") -> Dictionary:
	if not bvh.get("ok", false):
		return {"ok": false, "why": String(bvh.get("why", "not a parsed BVH"))}
	var joints: Array = bvh["joints"]
	var mapped := []   # [joint dict] for the joints Poser has
	var not_mapped := []
	var root_j = null
	for j in joints:
		if B.lim.has(j["name"]):
			mapped.append(j)
			if j["name"] == "pelvis":
				root_j = j
		else:
			not_mapped.append(j["name"])
	if root_j == null:
		return {"ok": false, "why": "the file has no joint named pelvis, so it is not a Kine export (joint names found: %s). Retargeting another skeleton is not supported yet" % ", ".join(PackedStringArray(joints.slice(0, 6).map(func(x): return x["name"])))}
	var missing := []
	for jn in Body.ORDER:
		var found := false
		for j in mapped:
			found = found or j["name"] == jn
		if not found:
			missing.append(jn)
	var rows: Array = bvh["frames"]
	var n := rows.size()
	var dt: float = bvh["dt"]
	every = maxi(1, every)
	var S := Scene.new()
	S.name = scene_name
	S.fps = maxi(1, int(round(bvh["fps"])))
	S.natural = false
	S.on_floor = false
	S.pin = false
	var pel: Vector3 = B.p0["pelvis"]
	var picks := []
	var f := 0
	while f < n:
		picks.append(f)
		f += every
	if picks[-1] != n - 1:
		picks.append(n - 1)
	var prev := 0
	for f2 in picks:
		var row: PackedFloat64Array = rows[f2]
		var joints_d := {}
		for j in mapped:
			var q := rotation(j, row)
			var a: Vector3 = decompose(B, j["name"], q)
			joints_d[j["name"]] = {"bend": a.x, "side": a.y, "twist": a.z}
		var rp: Vector3 = (root_j["offset"] as Vector3) * scale + position(root_j, row, scale) - pel
		S.add("f%d" % f2, {"joints": joints_d, "offset": [rp.x, rp.y, rp.z]})
		var c: Dictionary = S.cards[-1]
		c["move"] = float(f2 - prev) * dt if f2 > 0 else -1.0
		c["hold"] = 0.0
		c["ease"] = "linear"
		prev = f2
	var txt := "%d frames at %d fps -> %d cards (%s)" % [n, S.fps, picks.size(),
		"one per frame: exact" if every == 1 else "a card every %d frames, about %.2f s: the in-betweens are the scene's" % [every, every * dt]]
	if not not_mapped.is_empty():
		txt += "; not mapped: " + ", ".join(PackedStringArray(not_mapped))
	return {"ok": true, "why": "", "scene": S, "not_mapped": not_mapped, "missing": missing, "every": every, "cards": picks.size(), "text": txt}
