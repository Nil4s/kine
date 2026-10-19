## root_path.gd - ROADMAP 91: THE ROOT MOTION EDITOR (the path curve on the floor). Pure data + geometry, no UI: main.gd
## wraps the edits in one undo step each and draws / drags through the functions below.
##
## THE ROOT of a card is the pelvis's floor point: x and z of P["pelvis"] (the rest pelvis + the card's hips offset), and the
## HEADING is the facing the hips point along, atan2(x, z) of G["pelvis"] * (0, 0, 1) in degrees (0 = +Z, 90 = +X).
## A card's pose holds the hips' offset, so moving the root is writing that offset; turning the facing is turning the pelvis
## about world up (Body.turn_world), which leaves the pelvis's own point where it is.
##
## EDITS (posed): the card's pose with its root at xz and its heading at `heading`. A translation alone copies the pose and
## changes "offset" only (no re-rounding: every other number in the card stays as it was). A turn goes through Body.to_dict.
## The planted feet are NOT re-solved here: a plant's anchor is read at PLAY time (Scene._planted: held where the card before
## the run put the foot), so the played body re-solves each planted leg from the new root on every frame (the "feet re-solve"
## of the spec). A leg that cannot reach its anchor reports its miss through the plant pass, as it always has.
##
## THE PATH: the root the body PLAYS, sampled through the scene at SAMPLE_HZ (Scene.apply on a body of its own), so the curve
## is the travel the viewer sees, not a straight line between cards. The handles sit on the cards' own roots.
##   root handle (yellow cross on the floor): drag = move the card's root on the floor (the grab point stays under the mouse)
##   heading handle (red arrow tip): drag = turn the card's facing to the mouse's bearing from the root
## STRAIGHTEN: each card between the first and last root moves to the chord between them, keeping its place along it
##   (its projection on the chord); the ends stay, and the headings stay.
## SCALE LENGTH: every root moves away from (or toward) the first card's root by the factor k; the headings stay.
## EXPORT: nothing to write: the glTF / FBX exports take the pelvis's travel from the same poses (the "root" bone under the
## engine presets, GltfExport._animate), so the exported root follows the edited path.
class_name RootPath
extends RefCounted

const FLOOR := 0.012          # m: the path and the handles drawn this high over the floor (no z-fight)
const HEAD := 0.22            # m: the heading handle's length from its root
const PICK_PX := 14.0         # px: a press this close to a handle takes it
const SAMPLE_HZ := 8.0        # the played path is sampled at this rate (the curve between the cards)
const SIZE := 0.03            # m: half edge of a handle's cross
const SCALE_MIN := 0.25       # the scale command's range (a factor on the path length)
const SCALE_MAX := 3.0
const COL_PATH := Color(0.25, 0.85, 1.0)
const COL_ROOT := Color(1.0, 0.85, 0.2)
const COL_HEAD := Color(1.0, 0.42, 0.32)

static var _work: Body = null   # a body of its own: reading and editing roots never touches the main body


## the body the root functions use (made once; loads the skeleton like every Body)
static func work() -> Body:
	if _work == null:
		_work = Body.new()
		_work.load_files("res://data/skeleton.json", "res://data/body_limits.json")
		_work.fk()
	return _work


## the root of a pose: {"p": pelvis world point, "xz": Vector2 floor point, "heading": deg}. Loads the pose into B.
static func root_of(B: Body, pose: Dictionary) -> Dictionary:
	B.from_dict(pose)
	var p: Vector3 = B.P["pelvis"]
	var hf: Vector3 = (B.G["pelvis"] as Quaternion) * Vector3(0, 0, 1)
	return {"p": p, "xz": Vector2(p.x, p.z), "heading": rad_to_deg(atan2(hf.x, hf.z))}


## the roots of every card, in card order (each card's pose read on its own; nothing is edited)
static func roots(S: Scene) -> Array:
	var B := work()
	var out := []
	for c in S.cards:
		out.append(root_of(B, c["pose"]))
	return out


## the card's pose with its root moved to xz and its facing set to heading (deg). A copy: the scene is not touched.
static func posed(B: Body, pose: Dictionary, xz: Vector2, heading: float) -> Dictionary:
	var r := root_of(B, pose)
	var dh := wrapf(heading - float(r["heading"]), -180.0, 180.0)
	var d: Vector2 = xz - (r["xz"] as Vector2)
	var off: Array = pose["offset"]
	var out: Dictionary
	if absf(dh) < 1e-9:
		out = pose.duplicate(true)
	else:
		B.turn_world("pelvis", Quaternion(Vector3.UP, deg_to_rad(dh)))
		B.fk()
		out = B.to_dict()
	out["offset"] = [float(off[0]) + d.x, float(off[1]), float(off[2]) + d.y]
	return out


## the path length on the floor, metres (the chord of each step between cards, summed)
static func length_m(rs: Array) -> float:
	var L := 0.0
	for i in range(1, rs.size()):
		L += ((rs[i]["xz"] as Vector2) - (rs[i - 1]["xz"] as Vector2)).length()
	return L


## STRAIGHTEN: every card between the first and the last moves onto the chord between their roots, keeping its place along
## it. Returns how many cards moved (0 when the ends are the same point or there are fewer than three cards).
static func straighten(S: Scene) -> int:
	var n := S.cards.size()
	if n < 3:
		return 0
	var B := work()
	var rs := roots(S)
	var a: Vector2 = rs[0]["xz"]
	var ab: Vector2 = (rs[n - 1]["xz"] as Vector2) - a
	var L2 := ab.length_squared()
	if L2 < 1e-10:
		return 0
	var moved := 0
	for i in range(1, n - 1):
		var x: Vector2 = rs[i]["xz"]
		var s := clampf((x - a).dot(ab) / L2, 0.0, 1.0)
		var want := a + ab * s
		if (want - x).length() < 1e-9:
			continue
		S.cards[i]["pose"] = posed(B, S.cards[i]["pose"], want, float(rs[i]["heading"]))
		moved += 1
	return moved


## SCALE LENGTH: every card's root moves about the first card's root by factor k (2 = twice as far from the start).
## Returns how many cards moved (0 when k is 1, or there is nothing to move).
static func scale_length(S: Scene, k: float) -> int:
	var n := S.cards.size()
	if n < 2 or absf(k - 1.0) < 1e-9 or k <= 0.0:
		return 0
	var B := work()
	var rs := roots(S)
	var a: Vector2 = rs[0]["xz"]
	var moved := 0
	for i in range(1, n):
		var x: Vector2 = rs[i]["xz"]
		var want := a + (x - a) * k
		if (want - x).length() < 1e-9:
			continue
		S.cards[i]["pose"] = posed(B, S.cards[i]["pose"], want, float(rs[i]["heading"]))
		moved += 1
	return moved


## the played root path: the floor point of the pelvis at every SAMPLE_HZ tick through the scene (Scene.apply on work())
static func played(S: Scene) -> Array:
	var B := work()
	var out := []
	var L := S.length()
	var n := int(ceilf(L * SAMPLE_HZ - 1e-6)) + 1
	for k in n:
		var t := minf(float(k) / SAMPLE_HZ, L)
		S.apply(B, t)
		var p: Vector3 = B.P["pelvis"]
		out.append(Vector3(p.x, FLOOR, p.z))
	return out


## the handles: one per card: {"card", "root": Vector3 (floor), "tip": Vector3 (heading handle, floor), "heading": deg}
static func handles(rs: Array) -> Array:
	var out := []
	for i in rs.size():
		var xz: Vector2 = rs[i]["xz"]
		var h := deg_to_rad(float(rs[i]["heading"]))
		var root := Vector3(xz.x, FLOOR, xz.y)
		out.append({"card": i, "root": root, "tip": root + Vector3(sin(h), 0.0, cos(h)) * HEAD, "heading": float(rs[i]["heading"])})
	return out


## the handle under a press at mp: {"card", "kind": "root" | "head"}, or {} (the nearest within PICK_PX, in front of the camera)
static func hit(cam: Camera3D, mp: Vector2, hs: Array) -> Dictionary:
	var best := {}
	var best_d := PICK_PX
	for h in hs:
		for kind in ["root", "head"]:
			var p: Vector3 = h["root"] if kind == "root" else h["tip"]
			if cam.is_position_behind(p):
				continue
			var d := cam.unproject_position(p).distance_to(mp)
			if d <= best_d:
				best_d = d
				best = {"card": int(h["card"]), "kind": kind}
	return best


## where the mouse's ray meets the floor (y = 0), or null (the ray points up, or away)
static func floor_hit(cam: Camera3D, mp: Vector2):
	var o := cam.project_ray_origin(mp)
	var d := cam.project_ray_normal(mp)
	if absf(d.y) < 1e-6:
		return null
	var t := -o.y / d.y
	if t < 0.0:
		return null
	return o + d * t


## the path and its handles into `im` (lines). `active` = {card, kind} drawn bright; {} = none.
static func draw(im: ImmediateMesh, path: Array, hs: Array, active: Dictionary) -> void:
	if path.size() >= 2:
		im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, Overlays._mat())
		im.surface_set_color(COL_PATH)
		for p in path:
			im.surface_add_vertex(p)
		im.surface_end()
	for h in hs:
		var on := int(h["card"]) == int(active.get("card", -1))
		var root: Vector3 = h["root"]
		var tip: Vector3 = h["tip"]
		var s := SIZE * (1.4 if on and active.get("kind", "") == "root" else 1.0)
		var c := COL_ROOT
		c.a = 1.0 if on else 0.8
		im.surface_begin(Mesh.PRIMITIVE_LINES, Overlays._mat())
		im.surface_set_color(c)
		for ax in [Vector3.RIGHT, Vector3.BACK]:
			im.surface_add_vertex(root - ax * s)
			im.surface_add_vertex(root + ax * s)
		im.surface_end()
		var hc := COL_HEAD
		hc.a = 1.0 if on else 0.8
		im.surface_begin(Mesh.PRIMITIVE_LINES, Overlays._mat())
		im.surface_set_color(hc)
		im.surface_add_vertex(root)
		im.surface_add_vertex(tip)
		for ax in [Vector3.RIGHT, Vector3.BACK]:
			im.surface_add_vertex(tip - ax * s * 0.8)
			im.surface_add_vertex(tip + ax * s * 0.8)
		im.surface_end()
