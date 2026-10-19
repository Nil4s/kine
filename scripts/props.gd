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
	"ramp": {"label": "200 cm long, 90 cm wide, rising 50 cm toward +Z", "solids": [
		[Vector3(0, 0.247, 0), Vector3(0.9, 0.08, 2.0), 12.0]], "supports": []},
	# GROUND PROPS (ROADMAP 93): the stair and step defaults are the building code's: a riser (rise) of 17.8 cm (7 in, under
	# the IRC R311.7.5.1 maximum of 19.7 cm, 7 3/4 in) and a tread (run) of 28 cm (11 in, over the 25.4 cm / 10 in minimum)
	"step_code": {"label": "box step, 60 x 40 cm, 17.8 cm riser (IRC R311.7.5.1)", "solids": [[Vector3(0, 0.089, 0), Vector3(0.6, 0.178, 0.4)]],
		"supports": [[0.178, Vector2(0, 0), Vector2(0.6, 0.4)]]},
	# 4 steps: tread k spans z (k-1) x 28 .. k x 28 cm, its top k x 17.8 cm; the stair rises toward +Z, its first riser at z = 0
	"stairs_code": {"label": "4 steps, 17.8 cm risers, 28 cm treads, 90 cm wide, rising toward +Z (IRC R311.7)", "solids": [
		[Vector3(0, 0.089, 0.14), Vector3(0.9, 0.178, 0.28)], [Vector3(0, 0.178, 0.42), Vector3(0.9, 0.356, 0.28)],
		[Vector3(0, 0.267, 0.70), Vector3(0.9, 0.534, 0.28)], [Vector3(0, 0.356, 0.98), Vector3(0.9, 0.712, 0.28)]],
		"supports": [[0.178, Vector2(0, 0.14), Vector2(0.9, 0.28)], [0.356, Vector2(0, 0.42), Vector2(0.9, 0.28)],
		[0.534, Vector2(0, 0.70), Vector2(0.9, 0.28)], [0.712, Vector2(0, 0.98), Vector2(0.9, 0.28)]]},
	# a 15 degree ramp, the same slab as "ramp" (2 m long, 90 cm wide, 8 cm thick); its low end's top is at the floor
	# the slab rests on the floor by its low corner (0.04 cos15 + 1.0 sin15 = 0.2975 m up), so no part of the mesh is under the floor
	"ramp15": {"label": "15 degree ramp, 200 cm long, 90 cm wide, rising toward +Z", "solids": [
		[Vector3(0, 0.2975, 0), Vector3(0.9, 0.08, 2.0), 15.0]], "supports": []},
	"wall": {"label": "300 x 240 cm, 15 cm thick", "solids": [[Vector3(0, 1.2, 0), Vector3(3.0, 2.4, 0.15)]], "supports": []},
	"door_frame": {"label": "90 x 200 cm opening, frame 210 cm high, 12 cm deep", "solids": [
		[Vector3(0.5, 1.0, 0), Vector3(0.1, 2.0, 0.12)], [Vector3(-0.5, 1.0, 0), Vector3(0.1, 2.0, 0.12)],
		[Vector3(0, 2.05, 0), Vector3(1.1, 0.1, 0.12)]], "supports": []},
	"railing": {"label": "150 cm long, handrail at 90 cm", "solids": [
		[Vector3(0.725, 0.45, 0), Vector3(0.05, 0.9, 0.05)], [Vector3(-0.725, 0.45, 0), Vector3(0.05, 0.9, 0.05)],
		[Vector3(0, 0.875, 0), Vector3(1.5, 0.05, 0.05)], [Vector3(0, 0.45, 0), Vector3(1.4, 0.03, 0.03)]], "supports": []},
	# GENERIC PROPS (GAP_ANALYSIS row 22; sizes and sources: docs/research/PROPS.md)
	"moving_box": {"label": "moving box 41.6 x 32.1 x 32.1 cm (U-Haul Small)", "solids": [[Vector3(0, 0.1604, 0), Vector3(0.4159, 0.3207, 0.3207)]],
		"supports": [[0.3207, Vector2(0, 0), Vector2(0.4159, 0.3207)]]},
	# a size 5 football: circumference 68-70 cm, 410-450 g (IFAB Law 2): the middle, 69 cm (d = 21.96 cm), 430 g
	"ball": {"label": "football, size 5: 22 cm, 430 g (IFAB Law 2)", "solids": [], "spheres": [[Vector3(0, 0.1098, 0), 0.1098]],
		"supports": [], "mass": 0.43},
	# a door LEAF, 32 x 80 in (0.813 x 2.032 m), 1 3/8 in (35 mm) thick (US interior standard): the origin is the HINGE
	# axis on the floor, the leaf runs along +X from it; "swing" (deg, keyable) turns it about the hinge, + toward +Z
	"door": {"label": "door 81 x 203 cm, hinged at its left edge (US 32 x 80 in)", "solids": [[Vector3(0.4064, 1.016, 0), Vector3(0.8128, 2.032, 0.035)]],
		"supports": [], "hinged": true, "width": 0.8128},
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
	var d := {"kind": p["kind"], "pos": [snappedf(o.x, 0.0001), snappedf(o.y, 0.0001), snappedf(o.z, 0.0001)],
		"yaw": snappedf(yaw, 0.0001)}
	if p.has("swing") and hinged(p) and float(p["swing"]) != 0.0:
		d["swing"] = snappedf(float(p["swing"]), 0.0001)
	if animated(p):
		var hg := hinged(p)
		d["keys"] = (p["keys"] as Array).map(func(k):
			var q: Vector3 = k["pos"]
			var e := {"t": snappedf(float(k["t"]), 0.0001), "pos": [snappedf(q.x, 0.0001), snappedf(q.y, 0.0001), snappedf(q.z, 0.0001)],
				"yaw": snappedf(float(k["yaw"]), 0.0001)}
			if hg:
				e["swing"] = snappedf(float(k.get("swing", 0.0)), 0.0001)
			return e)
	return d


## the other way; a missing field is the origin / no turn
static func from_dict(d: Dictionary) -> Dictionary:
	var a: Array = d.get("pos", [0, 0, 0])
	var p := make(String(d["kind"]), xf_at(Vector3(float(a[0]), float(a[1]), float(a[2])), float(d.get("yaw", 0.0))))
	if d.has("swing"):
		p["swing"] = float(d["swing"])
	if d.get("keys") is Array and not (d["keys"] as Array).is_empty():
		var ks := []
		for k in d["keys"]:
			var q: Array = k.get("pos", [0, 0, 0])
			ks.append({"t": float(k.get("t", 0.0)), "pos": Vector3(float(q[0]), float(q[1]), float(q[2])),
				"yaw": float(k.get("yaw", 0.0)), "swing": float(k.get("swing", 0.0))})
		ks.sort_custom(func(x, y): return float(x["t"]) < float(y["t"]))
		p["keys"] = ks
	return p


## a prop's FILE entry mirrored (Scene.mirror: x negated, yaw negated). A hinged kind's leaf runs along +X from its
## hinge, so its reflection is the leaf turned the other way: yaw -> 180 - yaw, swing -> -swing (the leaf direction
## R(yaw) R(-swing) X reflects to R(180 - yaw) R(swing) X). Keys the same, each one. Twice = the original
static func mirror_dict(q: Dictionary) -> Dictionary:
	var h := has_kind(String(q["kind"])) and bool(kind_of(String(q["kind"])).get("hinged", false))
	var out := {"kind": q["kind"], "pos": [-float(q["pos"][0]), q["pos"][1], q["pos"][2]], "yaw": _mirror_yaw(float(q["yaw"]), h)}
	if q.has("swing"):
		out["swing"] = -float(q["swing"])
	if q.has("keys"):
		out["keys"] = (q["keys"] as Array).map(func(k):
			var e := {"t": k["t"], "pos": [-float(k["pos"][0]), k["pos"][1], k["pos"][2]], "yaw": _mirror_yaw(float(k["yaw"]), h)}
			if k.has("swing"):
				e["swing"] = -float(k["swing"])
			return e)
	return out


static func _mirror_yaw(y: float, hinge: bool) -> float:
	return (180.0 - y) if hinge else -y


## one solid's frame in the world (its centre, tilted by its pitch) and its half sizes
static func _solid_world(p: Dictionary, s: Array) -> Dictionary:
	var pitch := deg_to_rad(float(s[2])) if s.size() > 2 else 0.0
	var local := Transform3D(Basis(Vector3.RIGHT, -pitch), s[0])
	return {"xf": (p["xf"] as Transform3D) * leaf_xf(p) * local, "half": (s[1] as Vector3) * 0.5}


## the prop's solid boxes in world space: [{"xf": Transform3D at the box centre, "half": Vector3}]; a sphere (the ball)
## is one more entry with "r" (its half sizes are r, so a box test is its bounding cube; _sd measures the sphere)
static func solids(p: Dictionary) -> Array:
	var out := []
	var kd := kind_of(p["kind"])
	for s in kd["solids"]:
		out.append(_solid_world(p, s))
	for sp in kd.get("spheres", []):
		var r: float = sp[1]
		out.append({"xf": (p["xf"] as Transform3D) * Transform3D(Basis(), sp[0]), "half": Vector3(r, r, r), "r": r})
	return out


# ---------------------------------------------------------------- GENERIC PROPS: hinge, keys over time (row 22)
## A prop may also hold (all optional; a prop without them is exactly as before, in memory and in the file):
##   "swing": deg   a hinged kind's (the door's) leaf turned about its hinge (the origin's vertical), + toward +Z
##   "keys":  [{"t": s, "pos": Vector3, "yaw": deg, "swing": deg}, ...] sorted by t: its place over time. Played as
##            PartKeys plays a joint (the same monotone cubic: eases out of the first key and into the last, never
##            overshoots, held past the ends), position and (yaw, swing) as two curves. A keyed prop's "xf" / "swing"
##            are only where it was last put: the keys win.
const SAME_T := 0.001


static func hinged(p: Dictionary) -> bool:
	return bool(kind_of(p["kind"]).get("hinged", false))


## the leaf's turn about the hinge (identity for every kind without one)
static func leaf_xf(p: Dictionary) -> Transform3D:
	if not p.has("swing") or not hinged(p):
		return Transform3D.IDENTITY
	return Transform3D(Basis(Vector3.UP, -deg_to_rad(float(p["swing"]))), Vector3.ZERO)


## the door's free edge (the middle of its edge away from the hinge, at half height) in the world
static func free_edge(p: Dictionary) -> Vector3:
	var kd := kind_of(p["kind"])
	var s: Array = kd["solids"][0]
	return (p["xf"] as Transform3D) * leaf_xf(p) * Vector3(float(kd.get("width", 0.0)), (s[0] as Vector3).y, 0.0)


static func animated(p: Dictionary) -> bool:
	return not (p.get("keys", []) as Array).is_empty()


static func any_animated(props: Array) -> bool:
	for p in props:
		if animated(p):
			return true
	return false


static func yaw_of(xf: Transform3D) -> float:
	return rad_to_deg(atan2(-xf.basis.x.z, xf.basis.x.x))


## the prop as it is at time t: {"kind", "xf", "swing"} (a new dict; an unkeyed prop is returned itself)
static func posed(p: Dictionary, t: float) -> Dictionary:
	if not animated(p):
		return p
	var pk := []
	var ak := []
	for k in p["keys"]:
		pk.append({"t": float(k["t"]), "v": k["pos"]})
		ak.append({"t": float(k["t"]), "v": Vector3(float(k["yaw"]), float(k.get("swing", 0.0)), 0.0)})
	var pos := PartKeys.at(pk, t)
	var a := PartKeys.at(ak, t)
	var out := {"kind": p["kind"], "xf": xf_at(pos, a.x)}
	if hinged(p):
		out["swing"] = a.y
	return out


static func posed_all(props: Array, t: float) -> Array:
	return props.map(func(p): return posed(p, t))


## a key at t from a transform (and swing): replaces one within SAME_T. The yaw is taken the short way from the key
## before it, so a turn through 180 deg does not spin the long way round
static func key_at(p: Dictionary, t: float, xf: Transform3D, swing := 0.0) -> void:
	var ks: Array = p.get("keys", [])
	var yaw := yaw_of(xf)
	var prev := -1
	for i in ks.size():
		if float(ks[i]["t"]) < t - SAME_T:
			prev = i
	if prev >= 0:
		yaw = float(ks[prev]["yaw"]) + rad_to_deg(angle_difference(deg_to_rad(float(ks[prev]["yaw"])), deg_to_rad(yaw)))
	var k := {"t": t, "pos": xf.origin, "yaw": yaw, "swing": swing if hinged(p) else 0.0}
	for i in ks.size():
		if absf(float(ks[i]["t"]) - t) < SAME_T:
			ks[i] = k
			p["keys"] = ks
			return
	ks.append(k)
	ks.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
	p["keys"] = ks


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
## true when the prop is an imported model whose file is not there any more (it is drawn as its box instead)
static func model_missing(p: Dictionary) -> bool:
	var g := String(kind_of(p["kind"]).get("glb", ""))
	return g != "" and not FileAccess.file_exists(g)


static func mesh(p: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = String(p["kind"])
	root.transform = p["xf"]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = GREY
	mat.roughness = 0.9
	var kd := kind_of(p["kind"])
	if String(kd.get("glb", "")) != "" and not model_missing(p):   # an imported model: the model itself, on the floor, centred, at the importer's scale
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
	var holder := root
	if bool(kd.get("hinged", false)):   # the door: its solids under a "leaf" node turned about the hinge
		holder = Node3D.new()
		holder.name = "leaf"
		holder.transform = leaf_xf(p)
		root.add_child(holder)
	for s in kd["solids"]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = s[1]
		bm.material = mat
		mi.mesh = bm
		var pitch := deg_to_rad(float(s[2])) if s.size() > 2 else 0.0
		mi.transform = Transform3D(Basis(Vector3.RIGHT, -pitch), s[0])
		holder.add_child(mi)
	for sp in kd.get("spheres", []):
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = sp[1]
		sm.height = 2.0 * float(sp[1])
		sm.material = mat
		mi.mesh = sm
		mi.position = sp[0]
		holder.add_child(mi)
	return root


## a node made by mesh() put where the prop is now (a posed prop: its place and, for a door, its leaf)
static func pose_node(n: Node3D, p: Dictionary) -> void:
	n.transform = p["xf"]
	var lf := n.get_node_or_null("leaf")
	if lf != null:
		(lf as Node3D).transform = leaf_xf(p)


## signed distance from a world point to an oriented box (negative inside)
static func _sd(sw: Dictionary, pt: Vector3) -> float:
	var l: Vector3 = (sw["xf"] as Transform3D).affine_inverse() * pt
	if sw.has("r"):
		return l.length() - float(sw["r"])
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


## SETTLING (round 39, GATES UU1): every prop stands on the highest top under it that is not above it, or on the
## floor; lowest first, so a box on a table follows the table. Moves the props in place; returns how many moved
static func settle(props: Array) -> int:
	var order := range(props.size())
	order.sort_custom(func(a, b): return (props[a]["xf"] as Transform3D).origin.y < (props[b]["xf"] as Transform3D).origin.y)
	var done := []
	var moved := 0
	for i in order:
		var xf: Transform3D = props[i]["xf"]
		var y := 0.0
		for q in done:
			for sup in supports(q):
				if _over(sup, xf.origin) and float(sup["y"]) <= xf.origin.y + 0.001:
					y = maxf(y, float(sup["y"]))
		if absf(y - xf.origin.y) > 0.0001:
			xf.origin.y = y
			props[i]["xf"] = xf
			moved += 1
		done.append(props[i])
	return moved


## THE SURFACE A SOLE POINT IS ON (ROADMAP 93): the point is at pt.y (its real height). The surface is the HIGHEST candidate
## that is no higher than pt.y + SNAP_UP, with a clear column between it and the point (a slab's underside, a step's
## riser, a table top above a foot, all block the floor below them). A point inside a solid is lifted onto that solid's top.
## {"y": height, "n": the surface's normal}; the floor when nothing else qualifies
const SNAP_UP := 0.25   # m: the highest a sole is lifted onto a surface (a step of 17.8 cm and a foot's penetration)

static func surface_below(props: Array, pt: Vector3) -> Dictionary:
	var cands := _faces_under(props, pt.x, pt.z)
	cands.sort_custom(func(a, b): return float(a["y"]) > float(b["y"]))
	for c in cands:
		var h := float(c["y"])
		if h > pt.y + SNAP_UP:
			continue
		if not _column_blocked(props, pt.x, pt.z, h + 0.01, pt.y):
			return c
	return {"y": 0.0, "n": Vector3.UP}


## the column of points (x, z, y) for y from y0 up to y1, 1 cm apart: is any of them inside a solid (by more than REST_SINK)?
static func _column_blocked(props: Array, x: float, z: float, y0: float, y1: float) -> bool:
	if y1 < y0:
		return false
	var n := maxi(1, ceili((y1 - y0) / 0.01))
	for k in n + 1:
		var q := Vector3(x, minf(y0 + k * 0.01, y1), z)
		if _inside_any(props, q):
			return true
	return false


## is a point inside any solid of the set (by more than REST_SINK)?
static func _inside_any(props: Array, q: Vector3) -> bool:
	for p in props:
		for sw in solids(p):
			if _sd(sw, q) < -REST_SINK:
				return true
	return false


## every candidate surface under the (x, z) column: the floor (y = 0, normal up) and each box's upward-facing face whose
## rectangle the vertical through (x, z) meets. [{"y", "n"}]
static func _faces_under(props: Array, x: float, z: float) -> Array:
	var cands := [{"y": 0.0, "n": Vector3.UP}]
	for p in props:
		for sw in solids(p):
			if sw.has("r"):
				continue
			var X: Transform3D = sw["xf"]
			var h: Vector3 = sw["half"]
			var ax := [X.basis.x.normalized(), X.basis.y.normalized(), X.basis.z.normalized()]
			for i in 3:
				for s in [-1.0, 1.0]:
					var n: Vector3 = ax[i] * s
					if n.y < 0.5:
						continue
					var c: Vector3 = X.origin + n * h[i]
					var y := c.y - (n.x * (x - c.x) + n.z * (z - c.z)) / n.y
					var d := Vector3(x, y, z) - c
					var j := (i + 1) % 3
					var k := (i + 2) % 3
					if absf(d.dot(ax[j])) <= h[j] + 1e-6 and absf(d.dot(ax[k])) <= h[k] + 1e-6:
						cands.append({"y": y, "n": n})
	return cands


## the height p should stand at: the floor (0), or the highest support of another prop that p's origin is over
static func snap_y(p: Dictionary, others: Array) -> float:
	var o: Vector3 = (p["xf"] as Transform3D).origin
	var y := 0.0
	for q in others:
		for sup in supports(q):
			if _over(sup, o):
				y = maxf(y, float(sup["y"]))
	return y
