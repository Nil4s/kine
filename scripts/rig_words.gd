## rig_words.gd - RIG FROM WORDS (ROADMAP J24): "add a tail with 8 bones", "add a 60 cm tail", "add a cape with 3x4 bones",
## "add 2 ears", "remove the tail", and posing it: "curl the tail 40", "wag the tail left 30".
## The extra parts are DATA in the scene (Scene.rigx, in the file as "rigx" only when there is one): a list of chains, each
## {"kind", "name", "parent" (a body joint), "root" (metres, in the parent's rest axes: x = his left, y up, z forward),
##  "dir" (the unit rest direction, same axes), "side_axis", "bones" (lengths, m), "ang" ([bend, side] deg per bone), "r0", "r1"}.
## A chain of n bones has n JOINTS (a bone's start) and n+1 points (the last is the tip). FK: each joint turns the rest
## direction of everything after it by its bend (about the parent's x) and side, on top of the parent's own pose.
## DEFAULTS are design choices, written here so they can be argued with (none is a measured dataset except the ear):
##   tail  parent pelvis, root = the SACRUM point, 9 cm behind the pelvis joint (the pelvis is ~20 cm deep front to back, the
##         sacrum/coccyx is its back wall); points back and 20 deg down (dir = 0,-0.34,-0.94) and droops 3 deg a bone
##         (a relaxed cat/dragon-like tail). Length 0.40 x stature (0.70 m for a 1.75 m body) unless "60 cm" is said.
##   ears  2 (or 1), parent head, 6.3 cm long = the adult human auricle length (Farkas 1994, ~6.3 cm male, ~5.9 cm female), 3 bones,
##         on the head's sides 7.5 cm from the midline, pointing up and 20 deg outward.
##   cape  parent spine_03 (upper chest), a grid of cols x rows bones: cols chains side by side across 0.40 m (about the biacromial
##         breadth of an adult, ~0.37-0.40 m), each rows bones hanging 0.90 m (to the knees), 11 cm behind the chest joint.
## parse(text) -> {"ok", "op": "add"/"remove"/"pose", ...} or {"ok": false, "error": "... what to type instead"}
class_name RigWords
extends RefCounted

const KINDS := ["tail", "ears", "cape"]
const SACRUM := Vector3(0.0, 0.0, -0.09)   # pelvis joint -> the back of the pelvis (see above)
const NOUN := {"tail": "tail", "tails": "tail", "ear": "ears", "ears": "ears", "cape": "cape", "cloak": "cape"}
const MAX_BONES := {"tail": 24, "ears": 6, "cape": 12}
const POSE_VERBS := ["bend", "curl", "raise", "lift", "lower", "drop", "swing", "wag", "sway", "swish"]


static func stature(B: Body) -> float:
	return (B.p0["head"] as Vector3).y * 1.12   # the head joint is the skull base: the crown is ~12 % higher


static func _num(rx: RegEx, t: String, g := 1) -> float:
	var m := rx.search(t)
	return float(m.get_string(g)) if m != null else NAN


static func parse(text: String) -> Dictionary:
	var t := text.to_lower().strip_edges().replace(",", " ").replace("-", " ")
	for w in ["please ", "could you ", "can you "]:
		t = t.trim_prefix(w)
	var kind := ""
	for w in t.split(" ", false):
		var wd := w.trim_suffix(".")
		if NOUN.has(wd):
			kind = NOUN[wd]
			break
	var verb := t.get_slice(" ", 0)
	if verb in ["remove", "delete", "clear"] or t.begins_with("take off") or t.begins_with("take away"):
		if kind == "" and ("rig" in t or "extras" in t or " all" in t or t.ends_with("everything")):
			return {"ok": true, "op": "remove", "kind": "all"}
		if kind == "":
			return {"ok": false, "error": "remove which part? Say: remove the tail (or the ears, the cape, or: remove the whole rig)"}
		return {"ok": true, "op": "remove", "kind": kind}
	if verb in ["add", "give", "attach", "grow", "make"]:
		if kind == "":
			return {"ok": false, "error": "add what? Say: add a tail with 8 bones, add 2 ears, or add a cape with 3x4 bones"}
		var rx_len := RegEx.create_from_string("(\\d+(?:\\.\\d+)?)\\s*(mm|cm|m|metres?|meters?)\\b")
		var rx_grid := RegEx.create_from_string("(\\d+)\\s*x\\s*(\\d+)\\s*bones?")
		var rx_bones := RegEx.create_from_string("(\\d+)\\s*bones?")
		var rx_cnt := RegEx.create_from_string("(\\d+)\\s*(?:long\\s+)?(?:tails?|ears?|capes?|cloaks?)")
		var length := 0.0
		var lm := rx_len.search(t)
		if lm != null:
			var u := lm.get_string(2)
			var v := float(lm.get_string(1))
			length = v * (0.001 if u == "mm" else 0.01 if u == "cm" else 1.0)
			t = t.replace(lm.get_string(), " ")
			if length < 0.02 or length > 3.0:
				return {"ok": false, "error": "a %s of %s is out of range: say a length between 2 cm and 3 m, e.g. add a 60 cm tail" % [kind, lm.get_string().strip_edges()]}
		var cols := 0
		var rows := 0
		var gm := rx_grid.search(t)
		if gm != null:
			cols = int(gm.get_string(1))
			rows = int(gm.get_string(2))
			t = t.replace(gm.get_string(), " ")
			if kind != "cape":
				return {"ok": false, "error": "a CxR grid is for a cape: say add a cape with 3x4 bones, or add a tail with 8 bones"}
		var bones := 0
		var bm := rx_bones.search(t)
		if bm != null:
			bones = int(bm.get_string(1))
			t = t.replace(bm.get_string(), " ")
		var count := 0
		var cm := rx_cnt.search(t)
		if cm != null:
			count = int(cm.get_string(1))
		if cols > 0 or kind == "cape":
			if cols == 0:
				cols = 3
				rows = bones if bones > 0 else 4
			if cols < 1 or rows < 1 or cols > 9 or rows > int(MAX_BONES["cape"]):
				return {"ok": false, "error": "a cape grid is 1 to 9 chains of 1 to %d bones: say add a cape with 3x4 bones" % int(MAX_BONES["cape"])}
			return {"ok": true, "op": "add", "kind": "cape", "cols": cols, "rows": rows, "len": length}
		if bones == 0:
			bones = 8 if kind == "tail" else 3
		if bones < 1 or bones > int(MAX_BONES[kind]):
			return {"ok": false, "error": "a %s takes 1 to %d bones: say add a %s with %d bones" % [kind, int(MAX_BONES[kind]), kind, mini(bones, int(MAX_BONES[kind])) if bones > 0 else 4]}
		if kind == "tail" and count > 1:
			return {"ok": false, "error": "one tail only: say add a tail with 8 bones"}
		if kind == "ears":
			if count == 0:
				count = 2 if (" ears" in t) else 1
			if count < 1 or count > 2:
				return {"ok": false, "error": "ears come as 1 or 2: say add 2 ears"}
		return {"ok": true, "op": "add", "kind": kind, "bones": bones, "count": maxi(count, 1), "len": length}
	if verb in POSE_VERBS and kind != "":
		var rx_deg := RegEx.create_from_string("(-?\\d+(?:\\.\\d+)?)")
		var dm := rx_deg.search(t)
		if dm == null:
			return {"ok": false, "error": "by how much? Say: curl the tail 40 (degrees), or wag the tail left 30"}
		var deg := float(dm.get_string(1))
		var side := ("left" in t.split(" ") or "right" in t.split(" ")) or verb in ["wag", "sway", "swish", "swing"] and not ("up" in t.split(" ") or "down" in t.split(" "))
		var sgn := 1.0
		if "right" in t.split(" "):
			sgn = -1.0
		if verb in ["lower", "drop"] or "down" in t.split(" "):
			sgn = -sgn
		return {"ok": true, "op": "pose", "kind": kind, "deg": deg * sgn, "side": side, "to": " to " in t}
	return {"ok": false, "error": "rig words: add a tail with 8 bones, add 2 ears, add a cape with 3x4 bones, remove the tail, curl the tail 40. Nothing was changed"}


## the chains a command creates, for this body (B at rest: the roots are in the parent's rest axes)
static func make(B: Body, r: Dictionary) -> Array:
	var H := stature(B)
	var out := []
	match String(r["kind"]):
		"tail":
			var n := int(r["bones"])
			var L := float(r["len"]) if float(r["len"]) > 0.0 else 0.40 * H
			out.append(_chain("tail", "tail", "pelvis", SACRUM, Vector3(0.0, -0.34, -0.94).normalized(), Vector3.UP, n, L, 0.025, 0.008, -3.0))
		"ears":
			var n := int(r["bones"])
			var L := float(r["len"]) if float(r["len"]) > 0.0 else 0.063
			var sides := [1.0] if int(r["count"]) == 1 else [1.0, -1.0]
			for s in sides:
				var d := Vector3(0.34 * s, 0.94, -0.0).normalized()
				out.append(_chain("ears", "ear_" + ("l" if s > 0 else "r"), "head", Vector3(0.075 * s, 0.10, -0.01), d, Vector3.BACK, n, L, 0.012, 0.004, 0.0))
		"cape":
			var cols := int(r["cols"])
			var rows := int(r["rows"])
			var L := float(r["len"]) if float(r["len"]) > 0.0 else 0.90
			for c in cols:
				var x := 0.0 if cols == 1 else lerpf(0.20, -0.20, float(c) / float(cols - 1))
				out.append(_chain("cape", "cape_%d" % (c + 1), "spine_03", Vector3(x, 0.02, -0.11), Vector3(0.0, -1.0, -0.08).normalized(), Vector3.BACK, rows, L, 0.012, 0.012, 0.0))
	return out


static func _chain(kind: String, nm: String, parent: String, root: Vector3, dir: Vector3, side_axis: Vector3, n: int, L: float, r0: float, r1: float, droop: float) -> Dictionary:
	var bones := []
	var ang := []
	for i in n:
		bones.append(_q(L / float(n)))
		ang.append([droop, 0.0])
	return {"kind": kind, "name": nm, "parent": parent, "root": _v(root), "dir": _v(dir),
		"side_axis": _v(side_axis), "bones": bones, "ang": ang, "r0": r0, "r1": r1}


## the numbers go into the file as JSON: snapped to a micrometre so a save + load gives back the very same values
## (a Vector3 is float32; its 0.0750000029... would come back from the text as 0.075)
static func _q(x: float) -> float:
	return ("%.6f" % x).to_float()   # through text: snappedf's n * step is not always the double the text reads back as


static func _v(v: Vector3) -> Array:
	return [_q(v.x), _q(v.y), _q(v.z)]


## the n+1 points of a chain in world space for the body's present pose (B.fk() done): the root, each joint, the tip
static func points(B: Body, c: Dictionary) -> PackedVector3Array:
	var pj: String = c["parent"]
	var q: Quaternion = B.G[pj]
	var rt: Array = c["root"]
	var d0: Array = c["dir"]
	var sa: Array = c["side_axis"]
	var base := Vector3(d0[0], d0[1], d0[2])
	var ax := Vector3(sa[0], sa[1], sa[2])
	var p: Vector3 = B.P[pj] + q * Vector3(rt[0], rt[1], rt[2])
	var out := PackedVector3Array([p])
	var bones: Array = c["bones"]
	var ang: Array = c["ang"]
	var local := Quaternion.IDENTITY
	for i in bones.size():
		var a: Array = ang[i]
		local = local * Quaternion(Vector3.RIGHT, deg_to_rad(float(a[0]))) * Quaternion(ax, deg_to_rad(float(a[1])))
		p += (q * (local * base)).normalized() * float(bones[i])
		out.append(p)
	return out


static func length(c: Dictionary) -> float:
	var s := 0.0
	for b in c["bones"]:
		s += float(b)
	return s


## a pose op: the total bend (or side swing) is shared evenly by the chain's bones. "by" adds, "to" sets the total on top of
## the rest droop. Ears / cape: the same words, the same maths (up = the bone's +bend)
static func pose(chains: Array, r: Dictionary) -> int:
	var hit := 0
	for c in chains:
		if c["kind"] != r["kind"]:
			continue
		hit += 1
		var ang: Array = c["ang"]
		var n := ang.size()
		var per := float(r["deg"]) / float(n)
		var sgn := -1.0 if String(c["kind"]) != "cape" else 1.0   # left = +x of the body for every kind
		var k := 1 if bool(r["side"]) else 0
		for i in n:
			var a: Array = ang[i]
			a[k] = _q((per * (sgn if k == 1 else 1.0)) if bool(r["to"]) else float(a[k]) + per * (sgn if k == 1 else 1.0))
	return hit


## the file's block: a chain without its numbers is dropped; the bone and angle lists are made the same length
static func from_file(d: Variant) -> Array:
	var out := []
	if not (d is Array):
		return out
	for x in d:
		if not (x is Dictionary):
			continue
		var c := x as Dictionary
		if not (c.has("kind") and c.has("parent") and c.has("root") and c.has("dir") and c.has("bones") and c.has("ang") and c.has("side_axis")):
			continue
		if not (c["bones"] is Array) or (c["bones"] as Array).is_empty() or (c["ang"] as Array).size() != (c["bones"] as Array).size():
			continue
		var k := {}   # the keys in the order make() writes them (the JSON writer sorts them), so a loaded rig equals the saved one
		for key in ["kind", "name", "parent", "root", "dir", "side_axis", "bones", "ang", "r0", "r1"]:
			if c.has(key):
				k[key] = c[key]
		out.append(k.duplicate(true))
	return out


## does this phrase belong to the rig (a rig verb and a rig noun)? The pose words keep everything they parse themselves
static func is_rig(text: String) -> bool:
	var ws := text.to_lower().replace(",", " ").split(" ", false)
	if ws.is_empty():
		return false
	var v: String = ws[0]
	if not (v in ["add", "give", "attach", "grow", "make", "remove", "delete", "clear", "take"] or v in POSE_VERBS):
		return false
	for w in ws:
		if NOUN.has(String(w).trim_suffix(".")):
			return true
	return v in ["remove", "delete", "clear", "take"] and ("rig" in ws or "extras" in ws)   # "remove the rig", "clear the extras"
