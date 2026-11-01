## BUILD THEN ACT (Friday 146): a part built in Easy Part arrives in the scene as a prop the character can use.
##   size   the prop's mesh is the part's own mesh (metres, as built: 30 cm stays 0.30 m); it rests on the floor
##   grip   an automatic grip point, in the prop's own frame: the THINNEST stretch of a long part (a sword's handle, a stick's
##          middle) on its long axis; for a part that is not long (a box, a cup) the top centre
##   place  a new part is put on the floor beside the character (his right side), not on top of him
##   again  a part reopened from its prop (Back to your part, Change the part) and used again REPLACES that prop (same spot, size measured again)
##   reach  "Pick up" on a part that is out of his hands: a card where he crouches and his right hand is on the grip, then holds it
## Everything here is static and takes the scene / the body / the main node as arguments; main.gd and build_ui.gd call in.
class_name PartScene
extends RefCounted

const SLICES := 16           # planes cut across a long part to find its thinnest stretch
const LONG := 2.0            # a part is "long" when its longest side is this many times its second longest
const BESIDE := 0.40         # m, the part's centre to the side of the hips
const AHEAD := 0.10          # m, and in front of them
const HAND_NEAR := 0.03      # m, the bar for "his hand is on the grip" (palm centre to grip point)

static var trace := false    # tests: print each crouch tried
static var editing := ""    # the name of the part a prop was reopened from (Back to your part / Change the part): its next Use replaces that prop
static var _grips := {}      # kind -> grip in the prop's frame (a kind never changes: a changed part is a new kind)


## the grip point of a Part prop's kind, in the prop's own frame (the frame of its xf: origin on the floor under the part's centre)
static func grip_local(kind: String) -> Vector3:
	if _grips.has(kind):
		return _grips[kind]
	var g := Vector3(0, 0.05, 0)
	if Props.has_kind(kind) and Props.kind_of(kind).has("mesh"):
		var k: Dictionary = Props.kind_of(kind)
		g = _grip_of_mesh(k["mesh"] as ArrayMesh) + (k["mesh_at"] as Vector3)
	_grips[kind] = g
	return g


## the grip point in the world, for a prop of the set
static func grip_world(p: Dictionary) -> Vector3:
	return (p["xf"] as Transform3D) * grip_local(String(p["kind"]))


static func has_grip(p: Dictionary) -> bool:
	return String(p.get("kind", "")).begins_with("part:") and Props.has_kind(String(p["kind"])) and Props.kind_of(String(p["kind"])).has("mesh")


## the grip in the mesh's own frame
static func _grip_of_mesh(mesh: ArrayMesh) -> Vector3:
	var tris := _triangles(mesh)
	var bb := mesh.get_aabb()
	var sz := bb.size
	var ax := 0
	for i in 3:
		if sz[i] > sz[ax]:
			ax = i
	var second := 0.0
	for i in 3:
		if i != ax:
			second = maxf(second, sz[i])
	if tris.is_empty() or sz[ax] < LONG * maxf(second, 1e-6):
		return Vector3(bb.get_center().x, bb.end.y, bb.get_center().z)   # not long: the top centre
	var others: Array = [0, 1, 2]
	others.erase(ax)
	var lo := bb.position[ax]
	var best_ext := INF
	var cuts := []   # per slice: [u, extent, cross centre (Vector2)]
	for s in SLICES:
		var u := lo + sz[ax] * (s + 0.5) / float(SLICES)
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		var n := 0
		for t in range(0, tris.size(), 3):
			for e in 3:
				var a: Vector3 = tris[t + e]
				var b: Vector3 = tris[t + (e + 1) % 3]
				if (a[ax] - u) * (b[ax] - u) < 0.0:
					var f := (u - a[ax]) / (b[ax] - a[ax])
					var q := a.lerp(b, f)
					var c := Vector2(q[others[0]], q[others[1]])
					mn = Vector2(minf(mn.x, c.x), minf(mn.y, c.y))
					mx = Vector2(maxf(mx.x, c.x), maxf(mx.y, c.y))
					n += 1
		if n == 0:
			continue
		var ext := maxf(mx.x - mn.x, mx.y - mn.y)
		best_ext = minf(best_ext, ext)
		cuts.append([u, ext, (mn + mx) * 0.5])
	if cuts.is_empty():
		return bb.get_center()
	var mid := lo + sz[ax] * 0.5   # among equally thin slices (a plain stick): the one nearest the middle
	var pick: Array = []
	for c in cuts:
		if float(c[1]) <= best_ext * 1.05 + 1e-5 and (pick.is_empty() or absf(float(c[0]) - mid) < absf(float(pick[0]) - mid)):
			pick = c
	var g := Vector3.ZERO
	g[ax] = pick[0]
	g[others[0]] = (pick[2] as Vector2).x
	g[others[1]] = (pick[2] as Vector2).y
	return g


static func _triangles(mesh: ArrayMesh) -> PackedVector3Array:
	var out := PackedVector3Array()
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx = arr[Mesh.ARRAY_INDEX]
		if idx != null and (idx as PackedInt32Array).size() > 0:
			for i in idx:
				out.append(v[i])
		else:
			out.append_array(v)
	return out


## the part's name, as the scene's prop list shows it: "Stick" (the kind is part:Stick#hash)
static func name_of(kind: String) -> String:
	return kind.trim_prefix("part:").get_slice("#", 0)


## the index of the prop made from a part of this name (-1 none)
static func index_named(S: Scene, nm: String) -> int:
	for i in S.props.size():
		var p: Dictionary = S.props[i]
		if String(p["kind"]).begins_with("part:") and p.get("part_rec") is Dictionary and String((p["part_rec"] as Dictionary).get("name", "")) == nm:
			return i
	return -1


## a part into the set: a part of this name already there is REPLACED (same place and turn, its size measured again); else a new prop
## on the floor beside the character. Returns the kind ("" when the part has no solid)
static func put(S: Scene, B: Body, rec: Dictionary) -> String:
	var nm := String(rec.get("name", "Part"))
	var at := index_named(S, nm) if editing == nm else -1   # a part used again as a NEW part (not reopened from its prop) is another prop
	editing = ""
	var xf := Transform3D.IDENTITY
	if at >= 0:
		xf = S.props[at]["xf"]
		S.props.remove_at(at)
		for c in S.cards:   # the cards' take / drop marks follow the props' new numbers (as Delete does)
			if c.has("take") and int(c["take"]["prop"]) > at:
				c["take"]["prop"] = int(c["take"]["prop"]) - 1
	var kind := BuildStage.use(S, rec)
	if kind == "":
		return ""
	var np: Dictionary = S.props[S.props.size() - 1]
	if at >= 0:
		np["xf"] = xf
		S.props.remove_at(S.props.size() - 1)
		S.props.insert(at, np)
		for c in S.cards:
			if c.has("take") and int(c["take"]["prop"]) >= at:
				c["take"]["prop"] = int(c["take"]["prop"]) + 1
	else:
		np["xf"] = Transform3D(Basis.IDENTITY, beside(B))
	return kind


## the floor spot beside the character: to his right, a little in front
static func beside(B: Body) -> Vector3:
	B.fk()
	var pel: Vector3 = B.P["pelvis"]
	var side: Vector3 = (B.P["hand_r"] as Vector3) - (B.P["hand_l"] as Vector3)
	side.y = 0.0
	side = side.normalized() if side.length() > 0.01 else Vector3.RIGHT
	var fwd: Vector3 = (B.G["pelvis"] as Quaternion) * Vector3(0, 0, 1)
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.BACK
	var o := Vector3(pel.x, 0.0, pel.z) + side * BESIDE + fwd * AHEAD
	return o


## the palm centre of a hand (the middle of its capsule)
static func palm(B: Body, sd := "_r") -> Vector3:
	var c := B.cap("hand" + sd)
	return ((c[0] as Vector3) + (c[1] as Vector3)) * 0.5


## the right hand on the grip: he crouches (knees, hips and back bend by `s`, feet kept where they stood) and the arm is fitted so the
## palm centre meets the point. The least crouch that reaches wins. Returns the palm's miss (m); the body is left in that pose
static func reach(B: Body, grip: Vector3) -> float:
	var keep := B.state()
	B.fk()
	var was_fast := B.fast
	B.fast = true   # limits only, contacts measured: the full arm search costs a body's FK per step (minutes over a few tries)
	var balls := {}
	var heads := {}
	for sd in ["_l", "_r"]:
		var fs := B.foot_state(sd)
		balls[sd] = fs[0]
		heads[sd] = fs[1]
	var best := INF
	var best_state := {}
	for pitch in [0.0, 30.0, 55.0, 80.0, 100.0]:
		B.set_state(keep)
		if pitch > 0.0:
			var s: float = minf(1.0, pitch / 80.0)
			for sp in ["spine_01", "spine_02"]:
				B.set_ang(sp, (B.ang[sp] as Vector3) + Vector3(20.0 * s, 0, 0))   # the back bends as far as it goes
			for sd in ["_l", "_r"]:
				B.set_ang("thigh" + sd, (B.ang["thigh" + sd] as Vector3) + Vector3(120.0 * s, 0, 0))
				B.set_ang("calf" + sd, (B.ang["calf" + sd] as Vector3) + Vector3(140.0 * s, 0, 0))
			B.set_ang("pelvis", (B.ang["pelvis"] as Vector3) + Vector3(pitch, 0, 0))   # the hips tip forward: the back leans over the floor
			B.fk()
			B.ground()
			for sd in ["_l", "_r"]:   # the feet back flat where they stood
				var bl: Vector3 = balls[sd]
				B.plant(sd, Vector3(bl.x, (B.p0["ball" + sd] as Vector3).y, bl.z), float(heads[sd]), true)
		var miss := _fit(B, grip)
		if trace:
			print("  reach pitch ", pitch, " miss ", miss, " palm ", palm(B), " grip ", grip, " pelvis ", B.P["pelvis"], " shoulder ", B.P["upperarm_r"])
		if miss < best:
			best = miss
			best_state = B.state()
		if miss <= 0.01:
			break
	B.set_state(best_state)
	B.fk()
	B.fast = was_fast
	return best


static func _fit(B: Body, grip: Vector3) -> float:
	for it in 4:
		var off := palm(B) - (B.P["hand_r"] as Vector3)   # wrist -> palm centre in the hand's present turn
		B.fit_hand("hand_r", grip - off, B.G["hand_r"] as Quaternion)
	return palm(B).distance_to(grip)


## "Pick up" on the picked card with a built part out of his hands: a NEW card after it where he crouches and the right hand is on the
## grip, the right hand taking the part from there on. True when this handled the press (done, or refused in words); false when a hand
## is already close (the plain Pick up takes it from there). One undo step; a miss over 3 cm puts everything back
static func pick_up_card(m: Node, i: int) -> bool:
	var p: Dictionary = m.S.props[i]
	if not has_grip(p) or m.sel_card < 0:
		return false
	var g := grip_world(p)
	if palm(m.B).distance_to(g) <= 0.12 or palm(m.B, "_l").distance_to(g) <= 0.12:
		return false
	m._push_undo()
	var before: Dictionary = m.B.state()
	var miss := reach(m.B, g)
	if miss > HAND_NEAR:
		m.B.set_state(before)
		m._drop_undo()
		m._say("his right hand cannot get to the %s (%.0f cm short): move it closer, then Pick up" % [name_of(String(p["kind"])), miss * 100.0])
		return true
	m._use_card("pick up the %s" % name_of(String(p["kind"])), before)
	m.S.cards[m.sel_card]["take"] = {"prop": i, "hands": ["_r"]}
	m._rebuild_cards()
	m._props_show()
	m._refresh()
	m._doc_line()
	m._say("card %d: the right hand holds the %s by its grip from here on. Ctrl+Z takes it back" % [m.sel_card + 1, name_of(String(p["kind"]))])
	return true
