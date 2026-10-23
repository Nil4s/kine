## bone_editor.gd - BONE EDITOR, the data (ROADMAP_400 J01). The UI is scripts/bone_editor_ui.gd.
## EXTRA bones only: the user's bones hang under the core UE5 skeleton (Body.ORDER) or under each other, like J24's words-made
## chains (rig_words.gd). The core skeleton's rest pose is NOT edited here: the whole app (limits, contacts, the glTF / BVH
## writers, the mesh skin) is built on it, so a core bone can be a parent, a pick and an extrude source, never a target.
## The bones are DATA in the scene (Scene.bones, in the file as "bones" only when there is one), a list of
##   {"name", "parent" (a core joint or another extra bone), "head", "tail" (metres, in the PARENT's rest frame: its head is the
##    origin, its rest axes the axes), "roll" (degrees, about the bone's own axis, armature space), "connect" (only when true)}
## REST FRAME of a bone (Blender's convention): +Y along the bone (head -> tail), turned from the world's +Y by the shortest arc,
## then rolled about that axis by "roll". A core joint's rest frame is the world's axes at its rest position (Body.p0): that is
## the frame Body's FK turns (G = identity at rest), and the frame J24's chain roots are written in.
## Parent-relative head / tail: a bone follows its parent when the body's proportions change (PR1) or the parent is edited.
## Roll in armature space: reparenting keeps the roll's value, and the world frame is kept exactly.
## EDITS keep every OTHER bone where it is in the world (Blender's edit mode): editing a bone recomputes its children's
## parent-relative numbers; a child marked "connect" (made by extrude) keeps its head on the parent's tail.
## POSED frame = the parent's posed frame * the bone's rest frame in its parent (extra bones carry no pose of their own yet:
## a posed hand_r carries its chain along).
## The numbers go into the file snapped to 1e-9 (through text: JSON gives back exactly what it was given; see _q).
class_name BoneEdit
extends RefCounted

const KEYS := ["name", "parent", "head", "tail", "roll", "connect"]
const MIN_LEN := 0.002   # 2 mm: a shorter bone has no direction worth the name
const MAX_LEN := 3.0


static func _q(x: float) -> float:
	return ("%.9f" % x).to_float()


static func _a(v: Vector3) -> Array:
	return [_q(v.x), _q(v.y), _q(v.z)]


static func _v(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


static func is_core(B: Body, n: String) -> bool:
	return B.p0.has(n)


static func find(bones: Array, n: String) -> int:
	for i in bones.size():
		if bones[i]["name"] == n:
			return i
	return -1


static func get_bone(bones: Array, n: String) -> Dictionary:
	var i := find(bones, n)
	return bones[i] if i >= 0 else {}


static func children(bones: Array, n: String) -> Array:
	return bones.filter(func(b): return b["parent"] == n).map(func(b): return String(b["name"]))


## every bone below n (children first found, then theirs)
static func below(bones: Array, n: String) -> Array:
	var out := []
	var todo := [n]
	while not todo.is_empty():
		var k: String = todo.pop_front()
		for c in children(bones, k):
			out.append(c)
			todo.append(c)
	return out


## extra bones between this bone and the core skeleton (0 = hangs on a core joint)
static func depth(bones: Array, n: String) -> int:
	var d := 0
	var b := get_bone(bones, n)
	while not b.is_empty():
		b = get_bone(bones, String(b["parent"]))
		if not b.is_empty():
			d += 1
		if d > bones.size():
			break
	return d


## the bone's frame from its head, tail and roll (deg): +Y along the bone (shortest arc from the world's +Y), rolled about it
static func basis_from(h: Vector3, t: Vector3, roll: float) -> Basis:
	var y := (t - h).normalized()
	var q0 := Quaternion(Vector3.UP, y) if y.dot(Vector3.UP) > -0.999999 else Quaternion(Vector3.RIGHT, PI)
	return Basis(Quaternion(y, deg_to_rad(roll)) * q0)


## [head, tail] in the world at rest (core: the joint and its end point)
static func rest_ht(B: Body, bones: Array, n: String) -> Array:
	if is_core(B, n):
		return [B.p0[n], B.e0[n]]
	var b := get_bone(bones, n)
	if b.is_empty():
		return [Vector3.ZERO, Vector3.UP * 0.1]
	var px := rest_xf(B, bones, String(b["parent"]))
	return [px * _v(b["head"]), px * _v(b["tail"])]


## the bone's rest frame in the world (origin = its head)
static func rest_xf(B: Body, bones: Array, n: String) -> Transform3D:
	if is_core(B, n):
		return Transform3D(Basis(), B.p0[n])
	var b := get_bone(bones, n)
	if b.is_empty():
		return Transform3D()
	var ht := rest_ht(B, bones, n)
	return Transform3D(basis_from(ht[0], ht[1], float(b["roll"])), ht[0])


## the bone's frame for the body's present pose (B.fk() done)
static func posed_xf(B: Body, bones: Array, n: String) -> Transform3D:
	if is_core(B, n):
		return Transform3D(Basis(B.G[n] as Quaternion), B.P[n])
	var b := get_bone(bones, n)
	if b.is_empty():
		return Transform3D()
	var pn := String(b["parent"])
	return posed_xf(B, bones, pn) * rest_xf(B, bones, pn).affine_inverse() * rest_xf(B, bones, n)


## [head, tail] for the present pose
static func posed_ht(B: Body, bones: Array, n: String) -> Array:
	if is_core(B, n):
		return [B.P[n], B.E[n]]
	var b := get_bone(bones, n)
	var pn := String(b["parent"])
	var m := posed_xf(B, bones, pn) * rest_xf(B, bones, pn).affine_inverse()
	var ht := rest_ht(B, bones, n)
	return [m * ht[0], m * ht[1]]


## a world point of the present pose -> the same point at rest, in the frame that carries bone n's parent
static func posed_to_rest(B: Body, bones: Array, n: String, p: Vector3) -> Vector3:
	var pn := String(get_bone(bones, n).get("parent", "pelvis"))
	return rest_xf(B, bones, pn) * posed_xf(B, bones, pn).affine_inverse() * p


static func length(B: Body, bones: Array, n: String) -> float:
	var ht := rest_ht(B, bones, n)
	return (ht[1] as Vector3).distance_to(ht[0])


## put bone n at these WORLD rest points (and roll); every other bone stays where it is in the world, except that a child
## made "connect" keeps its head on its parent's tail. The bone must exist (an extra bone). The whole subtree's world places
## are read BEFORE anything is written (a grandchild's place read after its parent moved would be the moved one)
static func set_world(B: Body, bones: Array, n: String, h: Vector3, t: Vector3, roll: float) -> void:
	var sub := below(bones, n)
	var was := {}
	for c in [n] + sub:
		was[c] = rest_ht(B, bones, c)
	var now := {n: [h, t]}
	_put(B, bones, n, h, t, roll)
	for c in sub:
		var b := get_bone(bones, c)
		var pn := String(b["parent"])
		var k: Array = was[c]
		var ch: Vector3 = k[0]
		if bool(b.get("connect", false)) and ch.distance_to(was[pn][1]) < 1e-5:
			ch = now[pn][1]
		now[c] = [ch, k[1]]
		_put(B, bones, c, ch, k[1], float(b["roll"]))


static func _put(B: Body, bones: Array, n: String, h: Vector3, t: Vector3, roll: float) -> void:
	var b := get_bone(bones, n)
	var px := rest_xf(B, bones, String(b["parent"])).affine_inverse()
	b["head"] = _a(px * h)
	b["tail"] = _a(px * t)
	b["roll"] = _q(roll)


## the bone moves to another parent and stays where it is in the world (no cycles: not under itself)
static func reparent(B: Body, bones: Array, n: String, np: String) -> String:
	var b := get_bone(bones, n)
	if b.is_empty():
		return "%s is not one of your bones (the body's own skeleton is not edited here)" % n
	if np == n or np in below(bones, n):
		return "%s cannot hang under itself or under one of its own children" % n
	if not is_core(B, np) and find(bones, np) < 0:
		return "there is no bone called %s" % np
	var ht := rest_ht(B, bones, n)
	var roll := float(b["roll"])
	b["parent"] = np
	b.erase("connect")
	set_world(B, bones, n, ht[0], ht[1], roll)
	return ""


## the bone goes; its children hang on its parent instead, where they are in the world
static func delete(B: Body, bones: Array, n: String) -> String:
	var i := find(bones, n)
	if i < 0:
		return "%s is not one of your bones (the body's own skeleton is not edited here)" % n
	var gp := String(bones[i]["parent"])
	for c in children(bones, n):
		reparent(B, bones, c, gp)
	bones.remove_at(i)
	return ""


## a free name: the wanted one if it is free, else its stem with the next number ("tail_3" -> "tail_4", "bone" -> "bone_1")
static func free_name(B: Body, bones: Array, want: String) -> String:
	var w := clean_name(want)
	if w == "":
		w = "bone"
	if find(bones, w) < 0 and not is_core(B, w):
		return w
	var stem := w
	var n := 1
	var rx := RegEx.create_from_string("^(.*)_(\\d+)$")
	var mt := rx.search(w)
	if mt != null:
		stem = mt.get_string(1)
		n = int(mt.get_string(2)) + 1
	while find(bones, "%s_%d" % [stem, n]) >= 0 or is_core(B, "%s_%d" % [stem, n]):
		n += 1
	return "%s_%d" % [stem, n]


static func clean_name(s: String) -> String:
	var out := ""
	for ch in s.strip_edges().to_lower().replace(" ", "_"):
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_":
			out += ch
	return out.left(40)


## a new bone under parent p from world rest points h -> t
static func make(B: Body, bones: Array, nm: String, p: String, h: Vector3, t: Vector3, roll := 0.0, connect := false) -> Dictionary:
	var px := rest_xf(B, bones, p).affine_inverse()
	var b := {"name": free_name(B, bones, nm), "parent": p, "head": _a(px * h), "tail": _a(px * t), "roll": _q(roll)}
	if connect:
		b["connect"] = true
	return b


## E: a child from the bone's tail, the same way on, as long as it (a core bone: half its length, at most 10 cm)
static func extrude(B: Body, bones: Array, n: String) -> Dictionary:
	var ht := rest_ht(B, bones, n)
	var d: Vector3 = ht[1] - ht[0]
	var L := d.length()
	if is_core(B, n):
		L = minf(L * 0.5, 0.10)
	L = clampf(L, 0.01, MAX_LEN)
	var dir := d.normalized() if d.length() > 1e-6 else Vector3.UP
	var nm := n if not is_core(B, n) else "bone_1"
	var b := make(B, bones, nm, n, ht[1], ht[1] + dir * L, float(get_bone(bones, n).get("roll", 0.0)), true)
	bones.append(b)
	return b


## Shift+A: a 10 cm bone under p, from its tail straight up (rest)
static func add(B: Body, bones: Array, p: String) -> Dictionary:
	var t: Vector3 = rest_ht(B, bones, p)[1]
	var b := make(B, bones, "bone_1", p, t, t + Vector3.UP * 0.10)
	bones.append(b)
	return b


## the length along the bone's own direction, the head and the roll kept (children kept in the world, connected ones follow)
static func set_length(B: Body, bones: Array, n: String, L: float) -> void:
	var ht := rest_ht(B, bones, n)
	var dir: Vector3 = ((ht[1] as Vector3) - (ht[0] as Vector3)).normalized()
	set_world(B, bones, n, ht[0], ht[0] + dir * clampf(L, MIN_LEN, MAX_LEN), float(get_bone(bones, n)["roll"]))


static func set_roll(B: Body, bones: Array, n: String, deg: float) -> void:
	var ht := rest_ht(B, bones, n)
	set_world(B, bones, n, ht[0], ht[1], wrapf(deg, -180.0, 180.0))


static func rename(bones: Array, n: String, nn: String) -> void:
	for b in bones:
		if b["name"] == n:
			b["name"] = nn
		elif b["parent"] == n:
			b["parent"] = nn


## a J24 chain (rig_words.gd) as editable bones: the chain's shape now (its angles baked in), roll 0, each bone on the one
## before ("connect"), the first on the chain's body joint. Names: <chain name>_1 .. _n
static func from_chain(B: Body, bones: Array, c: Dictionary) -> Array:
	var pj := String(c["parent"])
	var back := rest_xf(B, bones, pj) * posed_xf(B, bones, pj).affine_inverse()
	var pts := RigWords.points(B, c)
	var out := []
	var p := pj
	for i in pts.size() - 1:
		var b := make(B, bones, "%s_%d" % [c["name"], i + 1], p, back * pts[i], back * pts[i + 1], 0.0, i > 0)
		bones.append(b)
		out.append(b["name"])
		p = b["name"]
	return out


static func to_file(bones: Array) -> Array:
	return bones.duplicate(true)


## the file's block: a bone without its numbers, a second bone of one name, a bone on no known parent (or in a loop) is dropped;
## the keys in KEYS order so a loaded list equals the saved one
static func from_file(d: Variant) -> Array:
	var out := []
	if not (d is Array):
		return out
	var names := {}
	for x in d:
		if not (x is Dictionary):
			continue
		var c := x as Dictionary
		if not (c.get("name") is String and c.get("parent") is String and c.get("head") is Array and c.get("tail") is Array and (c.get("roll") is float or c.get("roll") is int)):
			continue
		if (c["head"] as Array).size() != 3 or (c["tail"] as Array).size() != 3 or names.has(c["name"]) or Body.ORDER.has(c["name"]) or String(c["name"]) == "":
			continue
		var k := {"name": String(c["name"]), "parent": String(c["parent"]), "head": (c["head"] as Array).map(func(v): return float(v)),
			"tail": (c["tail"] as Array).map(func(v): return float(v)), "roll": float(c["roll"])}
		if bool(c.get("connect", false)):
			k["connect"] = true
		names[k["name"]] = true
		out.append(k)
	# every bone must reach the core skeleton
	var good := {}
	for j in Body.ORDER:
		good[j] = true
	var grew := true
	while grew:
		grew = false
		for b in out:
			if not good.has(b["name"]) and good.has(b["parent"]):
				good[b["name"]] = true
				grew = true
	return out.filter(func(b): return good.has(b["name"]))
