## props.gd - A STARTER SET OF PROPS at real sizes, built from boxes (ours: CC0 by construction). A prop is a kind plus
## a transform: {"kind": "table", "xf": Transform3D}. Props turn about Y only (yaw) and sit where their origin says: the
## origin is on the floor, at the middle of the prop's footprint. Units metres, Y up, the floor is y = 0.
##
## Each kind is DATA in KINDS:
##   "solids":   [center, size] or [center, size, pitch_deg]   boxes in the prop's local frame (pitch tilts a box about X,
##               positive = rising toward +Z; only the ramp uses it, as ONE sloped slab, not stairs)
##   "supports": [height, centre_xz, size_xz]                   flat tops a body can rest on (the ramp has none)
##   "label":    the real-world size in words
##
## A query takes a plain capsule (a, b, r), so a body part and a weapon are answered the same way:
##   depth(p, a, b, r)   how far the capsule is inside the prop's solids (0 = outside). The axis is sampled every 1 cm and
##                       each sample is a signed distance to the box, so it is right to 5 mm.
##   rests(p, a, b, r)   the capsule's lowest surface is 0..2 cm above a support (or 5 mm into it), over its rectangle,
##                       and it is not inside the prop (depth under 5 mm)
##   snap_y(p, others)   the height p should stand at: on the floor, or on the highest support of another prop it is over
## to_dict / from_dict are the scene's "props" list entries: {"kind", "pos": [x,y,z], "yaw": degrees}.
class_name Props
extends RefCounted

const STEP := 0.01        # the capsule axis is sampled every 1 cm
const REST_GAP := 0.02    # a capsule rests when its lowest point is within 2 cm above the surface
const REST_SINK := 0.005  # ...or up to 5 mm into it (and then depth is under this too)
const GREY := Color(0.70, 0.67, 0.62)   # warm neutral: scenery, not a second body (the dummy is blue-grey)

const KINDS := {
	"box": {"label": "40 cm cube", "solids": [[Vector3(0, 0.2, 0), Vector3(0.4, 0.4, 0.4)]],
		"supports": [[0.4, Vector2(0, 0), Vector2(0.4, 0.4)]]},
	"crate": {"label": "60 x 40 cm, 50 cm high", "solids": [[Vector3(0, 0.25, 0), Vector3(0.6, 0.5, 0.4)]],
		"supports": [[0.5, Vector2(0, 0), Vector2(0.6, 0.4)]]},
	"table": {"label": "120 x 70 cm, top at 75 cm", "solids": [
		[Vector3(0, 0.73, 0), Vector3(1.2, 0.04, 0.7)],
		[Vector3(0.54, 0.365, 0.29), Vector3(0.06, 0.73, 0.06)], [Vector3(-0.54, 0.365, 0.29), Vector3(0.06, 0.73, 0.06)],
		[Vector3(0.54, 0.365, -0.29), Vector3(0.06, 0.73, 0.06)], [Vector3(-0.54, 0.365, -0.29), Vector3(0.06, 0.73, 0.06)]],
		"supports": [[0.75, Vector2(0, 0), Vector2(1.2, 0.7)]]},
	"chair": {"label": "42 cm seat at 45 cm, back to 90 cm (back at -Z)", "solids": [
		[Vector3(0, 0.435, 0), Vector3(0.42, 0.03, 0.42)],
		[Vector3(0, 0.675, -0.195), Vector3(0.42, 0.45, 0.03)],
		[Vector3(0.18, 0.21, 0.18), Vector3(0.04, 0.42, 0.04)], [Vector3(-0.18, 0.21, 0.18), Vector3(0.04, 0.42, 0.04)],
		[Vector3(0.18, 0.21, -0.18), Vector3(0.04, 0.42, 0.04)], [Vector3(-0.18, 0.21, -0.18), Vector3(0.04, 0.42, 0.04)]],
		"supports": [[0.45, Vector2(0, 0), Vector2(0.42, 0.42)]]},
	"stool": {"label": "32 cm seat at 50 cm", "solids": [
		[Vector3(0, 0.485, 0), Vector3(0.32, 0.03, 0.32)],
		[Vector3(0.13, 0.235, 0.13), Vector3(0.035, 0.47, 0.035)], [Vector3(-0.13, 0.235, 0.13), Vector3(0.035, 0.47, 0.035)],
		[Vector3(0.13, 0.235, -0.13), Vector3(0.035, 0.47, 0.035)], [Vector3(-0.13, 0.235, -0.13), Vector3(0.035, 0.47, 0.035)]],
		"supports": [[0.5, Vector2(0, 0), Vector2(0.32, 0.32)]]},
	"bench": {"label": "140 x 35 cm, seat at 45 cm", "solids": [
		[Vector3(0, 0.43, 0), Vector3(1.4, 0.04, 0.35)],
		[Vector3(0.6, 0.205, 0.13), Vector3(0.05, 0.41, 0.05)], [Vector3(-0.6, 0.205, 0.13), Vector3(0.05, 0.41, 0.05)],
		[Vector3(0.6, 0.205, -0.13), Vector3(0.05, 0.41, 0.05)], [Vector3(-0.6, 0.205, -0.13), Vector3(0.05, 0.41, 0.05)]],
		"supports": [[0.45, Vector2(0, 0), Vector2(1.4, 0.35)]]},
	"step": {"label": "90 x 30 cm, one 18 cm riser", "solids": [[Vector3(0, 0.09, 0), Vector3(0.9, 0.18, 0.3)]],
		"supports": [[0.18, Vector2(0, 0), Vector2(0.9, 0.3)]]},
	"stairs": {"label": "5 steps, 18 cm risers, 28 cm treads, 90 cm wide, rising toward +Z", "solids": [
		[Vector3(0, 0.09, -0.56), Vector3(0.9, 0.18, 0.28)], [Vector3(0, 0.18, -0.28), Vector3(0.9, 0.36, 0.28)],
		[Vector3(0, 0.27, 0.0), Vector3(0.9, 0.54, 0.28)], [Vector3(0, 0.36, 0.28), Vector3(0.9, 0.72, 0.28)],
		[Vector3(0, 0.45, 0.56), Vector3(0.9, 0.9, 0.28)]],
		"supports": [[0.18, Vector2(0, -0.56), Vector2(0.9, 0.28)], [0.36, Vector2(0, -0.28), Vector2(0.9, 0.28)],
		[0.54, Vector2(0, 0.0), Vector2(0.9, 0.28)], [0.72, Vector2(0, 0.28), Vector2(0.9, 0.28)],
		[0.9, Vector2(0, 0.56), Vector2(0.9, 0.28)]]},
	# the ramp is ONE sloped slab (12 degrees, 2 m long, 8 cm thick, 90 cm wide, about 50 cm high at the top), not a
	# wedge: nothing under it is solid, and it has no support (a capsule on a slope is not "resting on a flat")
	"ramp": {"label": "2 m long, 90 cm wide, rising 50 cm toward +Z", "solids": [
		[Vector3(0, 0.247, 0), Vector3(0.9, 0.08, 2.0), 12.0]], "supports": []},
	"wall": {"label": "3 m x 2.4 m, 15 cm thick", "solids": [[Vector3(0, 1.2, 0), Vector3(3.0, 2.4, 0.15)]], "supports": []},
	"door_frame": {"label": "90 cm x 2 m opening, frame 2.1 m high, 12 cm deep", "solids": [
		[Vector3(0.5, 1.0, 0), Vector3(0.1, 2.0, 0.12)], [Vector3(-0.5, 1.0, 0), Vector3(0.1, 2.0, 0.12)],
		[Vector3(0, 2.05, 0), Vector3(1.1, 0.1, 0.12)]], "supports": []},
	"railing": {"label": "1.5 m long, handrail at 90 cm", "solids": [
		[Vector3(0.725, 0.45, 0), Vector3(0.05, 0.9, 0.05)], [Vector3(-0.725, 0.45, 0), Vector3(0.05, 0.9, 0.05)],
		[Vector3(0, 0.875, 0), Vector3(1.5, 0.05, 0.05)], [Vector3(0, 0.45, 0), Vector3(1.4, 0.03, 0.03)]], "supports": []},
	"bed": {"label": "95 x 205 cm, mattress top at 50 cm, headboard at -Z", "solids": [
		[Vector3(0, 0.15, 0), Vector3(0.95, 0.3, 2.0)], [Vector3(0, 0.4, 0.0), Vector3(0.9, 0.2, 1.9)],
		[Vector3(0, 0.45, -1.025), Vector3(0.95, 0.9, 0.05)]],
		"supports": [[0.5, Vector2(0, 0.0), Vector2(0.9, 1.9)]]},
}


## IMPORTED KINDS (round 37, SS6): a model from the library (user://library/props) is a kind too: its solid is its
## bounding box (scaled by the importer's factor), standing on the floor, centred; its support is the box's top. The
## node shows the model itself. Registered at start and on an import; a scene naming one not registered loads it
## as a box of the same name's last known size, or skips it (main.gd says so)
static var EXTRA := {}


static func register(kind: String, aabb: AABB, glb: String, factor := 1.0) -> void:
	var sz := aabb.size * factor
	EXTRA[kind] = {"label": "%s (%.0f x %.0f x %.0f cm, yours)" % [kind.trim_prefix("my "), sz.x * 100, sz.y * 100, sz.z * 100],
		"solids": [[Vector3(0, sz.y * 0.5, 0), sz]], "supports": [[sz.y, Vector2.ZERO, Vector2(sz.x, sz.z)]],
		"glb": glb, "factor": factor, "aabb": aabb}


static func has_kind(kind: String) -> bool:
	return KINDS.has(kind) or EXTRA.has(kind)


static func kind_of(kind: String) -> Dictionary:
	return KINDS[kind] if KINDS.has(kind) else EXTRA[kind]


## every kind's name and label, the built-in set first
static func catalogue() -> Array:
	var out := []
	for k in KINDS:
		out.append([k, KINDS[k]["label"]])
	for k in EXTRA:
		out.append([k, EXTRA[k]["label"]])
	return out


## a prop = kind + transform (position and yaw; roll and pitch are ignored by the queries)
static func make(kind: String, xf := Transform3D.IDENTITY) -> Dictionary:
	assert(has_kind(kind), "unknown prop kind " + kind)
	return {"kind": kind, "xf": xf}


## a transform from a position and a yaw in degrees
static func xf_at(pos: Vector3, yaw_deg := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), pos)


## the scene's "props" entry: plain JSON numbers
static func to_dict(p: Dictionary) -> Dictionary:
	var xf: Transform3D = p["xf"]
	var yaw := rad_to_deg(atan2(-xf.basis.x.z, xf.basis.x.x))
	var o := xf.origin
	return {"kind": p["kind"], "pos": [snappedf(o.x, 0.0001), snappedf(o.y, 0.0001), snappedf(o.z, 0.0001)],
		"yaw": snappedf(yaw, 0.0001)}


## the other way; a missing field is the origin / no turn
static func from_dict(d: Dictionary) -> Dictionary:
	var a: Array = d.get("pos", [0, 0, 0])
	return make(String(d["kind"]), xf_at(Vector3(float(a[0]), float(a[1]), float(a[2])), float(d.get("yaw", 0.0))))


## one solid's frame in the world (its centre, tilted by its pitch) and its half sizes
static func _solid_world(p: Dictionary, s: Array) -> Dictionary:
	var pitch := deg_to_rad(float(s[2])) if s.size() > 2 else 0.0
	var local := Transform3D(Basis(Vector3.RIGHT, -pitch), s[0])
	return {"xf": (p["xf"] as Transform3D) * local, "half": (s[1] as Vector3) * 0.5}


## the prop's solid boxes in world space: [{"xf": Transform3D at the box centre, "half": Vector3}]
static func solids(p: Dictionary) -> Array:
	var out := []
	for s in kind_of(p["kind"])["solids"]:
		out.append(_solid_world(p, s))
	return out


## the prop's support surfaces in world space: [{"y": world height, "xf": the prop's transform, "c": local centre xz,
## "half": local half size xz}]. A point is over one when it is inside the rectangle in the prop's own frame.
static func supports(p: Dictionary) -> Array:
	var xf: Transform3D = p["xf"]
	var out := []
	for s in kind_of(p["kind"])["supports"]:
		out.append({"y": xf.origin.y + float(s[0]), "xf": xf, "c": s[1], "half": (s[2] as Vector2) * 0.5})
	return out


## is a world point over the support's rectangle?
static func _over(sup: Dictionary, pt: Vector3, margin := 0.0) -> bool:
	var l: Vector3 = (sup["xf"] as Transform3D).affine_inverse() * pt
	var c: Vector2 = sup["c"]
	var h: Vector2 = sup["half"]
	return absf(l.x - c.x) <= h.x + margin and absf(l.z - c.y) <= h.y + margin


## the prop as a node: one MeshInstance3D box per solid, one neutral material. Add it to the scene as a child.
static func mesh(p: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = String(p["kind"])
	root.transform = p["xf"]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = GREY
	mat.roughness = 0.9
	var kd := kind_of(p["kind"])
	if kd.has("glb"):   # an imported model: the model itself, on the floor, centred, at the importer's scale
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		if doc.append_from_file(ProjectSettings.globalize_path(kd["glb"]), st) == OK:
			var n := doc.generate_scene(st) as Node3D
			if n != null:
				var bx: AABB = kd["aabb"]
				var f: float = kd["factor"]
				n.scale = Vector3.ONE * f
				n.position = -Vector3(bx.get_center().x, bx.position.y, bx.get_center().z) * f
				root.add_child(n)
				return root
	for s in kd["solids"]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = s[1]
		bm.material = mat
		mi.mesh = bm
		var pitch := deg_to_rad(float(s[2])) if s.size() > 2 else 0.0
		mi.transform = Transform3D(Basis(Vector3.RIGHT, -pitch), s[0])
		root.add_child(mi)
	return root


## signed distance from a world point to an oriented box (negative inside)
static func _sd(sw: Dictionary, pt: Vector3) -> float:
	var l: Vector3 = (sw["xf"] as Transform3D).affine_inverse() * pt
	var h: Vector3 = sw["half"]
	var q := Vector3(absf(l.x) - h.x, absf(l.y) - h.y, absf(l.z) - h.z)
	return Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0)).length() + minf(maxf(q.x, maxf(q.y, q.z)), 0.0)


## points along the capsule axis, at most STEP apart, both ends included
static func _samples(a: Vector3, b: Vector3) -> Array:
	var n := maxi(1, ceili(a.distance_to(b) / STEP))
	var out := []
	for i in n + 1:
		out.append(a.lerp(b, float(i) / n))
	return out


## how deep the capsule (a, b, r) is inside the prop's solids, in metres (0 = outside or just touching)
static func depth(p: Dictionary, a: Vector3, b: Vector3, r: float) -> float:
	var worst := 0.0
	var sol := solids(p)
	for pt in _samples(a, b):
		for sw in sol:
			worst = maxf(worst, r - _sd(sw, pt))
	return worst


## the support the capsule rests on ({} = none): its lowest surface 0..2 cm above the top (or under 5 mm into it), over
## the support's rectangle, and the capsule is not inside the prop
static func rests_on(p: Dictionary, a: Vector3, b: Vector3, r: float) -> Dictionary:
	if depth(p, a, b, r) > REST_SINK:
		return {}
	var best := {}
	var best_gap := INF
	for sup in supports(p):
		for pt in _samples(a, b):
			var gap: float = (pt.y - r) - float(sup["y"])
			if gap >= -REST_SINK and gap <= REST_GAP and _over(sup, pt) and gap < best_gap:
				best_gap = gap
				best = sup
	return best


## does the capsule rest on any support of the prop?
static func rests(p: Dictionary, a: Vector3, b: Vector3, r: float) -> bool:
	return not rests_on(p, a, b, r).is_empty()


## the height p should stand at: the floor (0), or the highest support of another prop that p's origin is over
static func snap_y(p: Dictionary, others: Array) -> float:
	var o: Vector3 = (p["xf"] as Transform3D).origin
	var y := 0.0
	for q in others:
		for sup in supports(q):
			if _over(sup, o):
				y = maxf(y, float(sup["y"]))
	return y
