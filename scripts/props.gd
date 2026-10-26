## props.gd - A STARTER SET OF PROPS at real sizes, built from boxes (ours: CC0 by construction). A prop is a kind plus
## a transform: {"kind": "table", "xf": Transform3D}. Props turn about Y only (yaw) and sit where their origin says: the
## origin is on the floor, at the middle of the prop's footprint. Units metres, Y up, the floor is y = 0.
##
## Each kind is DATA in KINDS:
##   "solids":   [center, size] or [center, size, pitch_deg]   boxes in the prop's local frame (pitch tilts a box about X,
##               positive = rising toward +Z; only the ramp uses it, as ONE sloped slab, not stairs)
##   "wedges":   [centre, size W x H x L]                      triangular prisms, rising toward +Z from a flat underside (the
##               ramps): the slope is walkable, nothing is under it, no support (ROADMAP 93)
##   "supports": [height, centre_xz, size_xz]                   flat tops a body can rest on (the ramps have none)
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
## SIZE and COLOUR (Easy's prop bar: Bigger / Smaller / Colour; Expert and the file read the same fields): "scale" (a
## uniform factor about the prop's middle on the floor, 1 = its real size) and "colour" (a name in COLOURS, "grey" = the
## default). Both are written to the scene only when they differ from the default, so an older file reads the same
const SIZE_MIN := 0.25
const SIZE_MAX := 4.0
const COLOURS := {"grey": Color(0.70, 0.67, 0.62), "blue": Color(0.15, 0.36, 0.88), "red": Color(0.84, 0.14, 0.12),
	"green": Color(0.16, 0.62, 0.24), "yellow": Color(0.95, 0.80, 0.12), "white": Color(0.95, 0.95, 0.93), "black": Color(0.08, 0.08, 0.09)}
const COLOUR_ORDER := ["blue", "red", "green", "yellow", "white", "black", "grey"]   # Colour cycles these; the first press gives blue


## the prop's size factor (clamped to SIZE_MIN..SIZE_MAX); 1 for a prop without one
static func scale_of(p: Dictionary) -> float:
	return clampf(float(p.get("scale", 1.0)), SIZE_MIN, SIZE_MAX)


## the prop's colour name ("grey" for the default)
static func colour_of(p: Dictionary) -> String:
	var c := String(p.get("colour", "grey"))
	return c if COLOURS.has(c) else "grey"

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
	# THE RAMP is a WEDGE (ROADMAP 93): a triangular prism, its underside flat on the floor, its top a plane from the floor
	# at the low end up to 50 cm at the high end (2 m long, 90 cm wide). Nothing is under the slope and it has no support
	# (a capsule on a slope is not "resting on a flat"). "wedges": [centre, size W x H x L]; the centre is H/2 up
	"ramp": {"label": "200 cm long, 90 cm wide, rising 50 cm toward +Z (a wedge: flat underside on the floor)", "solids": [],
		"wedges": [[Vector3(0, 0.25, 0), Vector3(0.9, 0.5, 2.0)]], "supports": []},
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
	# a 15 degree ramp: the same wedge, H = 2.0 tan 15 = 0.535898 m, centre H/2 up (0.267949)
	"ramp15": {"label": "15 deg wedge ramp, 200 cm long, 90 cm wide, rising toward +Z", "solids": [],
		"wedges": [[Vector3(0, 0.267949, 0), Vector3(0.9, 0.535898, 2.0)]], "supports": []},
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
	# ROADMAP 85: a sword, a steel rod 0.90 m between its end centres, radius 1.5 cm (RigidDrop.sword_body). Its origin is
	# on the floor like every kind, the box is 1.5 cm above it (the centre of mass when it lies flat) and its long axis
	# runs along the prop's local X. "rod" marks it: let go over the floor it falls as a rigid body (RigidDrop, 240 Hz)
	"sword": {"label": "sword, 90 cm blade and grip, 1.1 kg steel (drops as a rigid body)", "solids": [[Vector3(0, 0.015, 0), Vector3(0.93, 0.03, 0.03)]],
		"supports": [], "mass": 1.1, "rod": true},
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


## A BUILD house as a kind (docs/BUILD_PLAN.md 1d): its solids are Building.collision_boxes (the walls in runs, the door gap open),
## its supports the floor slabs' tops. "hidden": the house itself is drawn by BUILD (build_ui.gd), so the prop's node is empty.
## Re-registered after every BUILD edit, so the set follows the house. boxes: [{"xf", "half"}] (a room turned by a yaw is a
## box of its bounding size: BUILD draws rooms without yaw)
## 1f: ramps = [{"origin": Vector3 (on the floor), "yaw": deg, "poly": PackedVector2Array in (z, y) from the origin, counter-clockwise and
## convex, "w": half width}]: the stairs' walkable slopes (a wedge with its own profile; solids() turns each into a "poly" solid)
static func register_building(kind: String, boxes: Array, supports: Array, ramps := []) -> void:
	var sol := []
	for bx in boxes:
		sol.append([(bx["xf"] as Transform3D).origin, (bx["half"] as Vector3) * 2.0])
	EXTRA[kind] = {"label": "%s (from BUILD)" % kind.trim_prefix("building:"), "solids": sol, "supports": supports, "hidden": true, "building": true}
	if not ramps.is_empty():
		EXTRA[kind]["ramps"] = ramps


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
		if not bool(EXTRA[k].get("hidden", false)) and not bool(EXTRA[k].get("piece", false)):   # a BUILD house is a set, not a library prop; a BUILD piece is the library's own tile
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
	if p.has("mat"):
		d["mat"] = String(p["mat"])   # a photo material (user://materials/<name>, E15)
	if scale_of(p) != 1.0:
		d["scale"] = snappedf(scale_of(p), 0.0001)
	if colour_of(p) != "grey":
		d["colour"] = colour_of(p)
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
	if d.has("mat") and String(d["mat"]) != "":
		p["mat"] = String(d["mat"])
	if d.has("scale"):
		p["scale"] = clampf(float(d["scale"]), SIZE_MIN, SIZE_MAX)
	if d.has("colour") and COLOURS.has(String(d["colour"])):
		p["colour"] = String(d["colour"])
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
	for f in ["scale", "colour"]:   # a mirror keeps the size and the colour
		if q.has(f):
			out[f] = q[f]
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
	var k := scale_of(p)   # every local length of the kind is scaled about the origin (the floor): the box, its place, its half size
	var local := Transform3D(Basis(Vector3.RIGHT, -pitch), (s[0] as Vector3) * k)
	return {"xf": (p["xf"] as Transform3D) * leaf_xf(p) * local, "half": (s[1] as Vector3) * (0.5 * k)}


## the prop's solid boxes in world space: [{"xf": Transform3D at the box centre, "half": Vector3}]; a sphere (the ball)
## is one more entry with "r" (its half sizes are r, so a box test is its bounding cube; _sd measures the sphere)
static func solids(p: Dictionary) -> Array:
	var out := []
	var kd := kind_of(p["kind"])
	for s in kd["solids"]:
		out.append(_solid_world(p, s))
	var k := scale_of(p)
	for sp in kd.get("spheres", []):
		var r: float = float(sp[1]) * k
		out.append({"xf": (p["xf"] as Transform3D) * Transform3D(Basis(), (sp[0] as Vector3) * k), "half": Vector3(r, r, r), "r": r})
	for w in kd.get("wedges", []):
		var size: Vector3 = (w[1] as Vector3) * k
		out.append({"xf": (p["xf"] as Transform3D) * leaf_xf(p) * Transform3D(Basis(), (w[0] as Vector3) * k), "half": size * 0.5,
			"poly": wedge_profile(size), "w": size.x * 0.5})
	for rp in kd.get("ramps", []):   # BUILD stairs: a convex profile on its own frame
		var poly := PackedVector2Array()
		for q in (rp["poly"] as PackedVector2Array):
			poly.append(q * k)
		out.append({"xf": (p["xf"] as Transform3D) * Transform3D(Basis(Vector3.UP, deg_to_rad(float(rp["yaw"]))), (rp["origin"] as Vector3) * k),
			"half": Vector3(float(rp["w"]) * k, 1.0, 1.0), "poly": poly, "w": float(rp["w"]) * k})
	return out


## a wedge's profile in its own (z, y) plane, about its centre, counter-clockwise: the flat underside from the low end to
## the high end, the high end's back, and the slope from the top back down to the low end. Rises toward +Z (the low end at -Z)
static func wedge_profile(size: Vector3) -> PackedVector2Array:
	var hz := size.z * 0.5
	var hy := size.y * 0.5
	return PackedVector2Array([Vector2(-hz, -hy), Vector2(hz, -hy), Vector2(hz, hy)])


## 2D signed distance to a convex counter-clockwise polygon (negative inside)
static func _sdf2(q: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	var inside := true
	var n := poly.size()
	for i in n:
		var a: Vector2 = poly[i]
		var e: Vector2 = poly[(i + 1) % n] - a
		var t := clampf((q - a).dot(e) / maxf(e.length_squared(), 1e-12), 0.0, 1.0)
		best = minf(best, (q - (a + e * t)).length())
		if e.x * (q - a).y - e.y * (q - a).x < 0.0:
			inside = false
	return -best if inside else best


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
	var k := scale_of(p)
	return (p["xf"] as Transform3D) * leaf_xf(p) * Vector3(float(kd.get("width", 0.0)) * k, (s[0] as Vector3).y * k, 0.0)


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
	if p.has("mat"):
		out["mat"] = p["mat"]
	if p.has("scale"):
		out["scale"] = p["scale"]
	if p.has("colour"):
		out["colour"] = p["colour"]
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
	var k := scale_of(p)
	for s in kind_of(p["kind"])["supports"]:
		out.append({"y": xf.origin.y + float(s[0]) * k, "xf": xf, "c": (s[1] as Vector2) * k, "half": (s[2] as Vector2) * (0.5 * k)})
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
	root.transform = (p["xf"] as Transform3D).scaled_local(Vector3.ONE * scale_of(p))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLOURS[colour_of(p)]
	mat.roughness = 0.9
	if p.has("mat"):
		var pm := PhotoMaterial.load_material(String(p["mat"]))
		if pm != null:
			mat = pm
	var kd := kind_of(p["kind"])
	if bool(kd.get("hidden", false)):
		return root
	if String(kd.get("glb", "")).get_extension().to_lower() == "obj" and not model_missing(p):   # an imported OBJ (N01): its meshes, same placement as a .glb
		var n := Node3D.new()
		for o in ObjIO.import_file(kd["glb"]):
			var mi := MeshInstance3D.new()
			mi.name = String(o["name"])
			mi.mesh = o["mesh"]
			mi.material_override = mat
			n.add_child(mi)
		var bx: AABB = kd["aabb"]
		var f: float = kd["factor"]
		n.scale = Vector3.ONE * f
		n.position = -Vector3(bx.get_center().x, bx.position.y, bx.get_center().z) * f
		root.add_child(n)
		_tint_models(n, colour_of(p), p)
		return root
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
				_tint_models(n, colour_of(p), p)
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
	for w in kd.get("wedges", []):
		var mi := MeshInstance3D.new()
		mi.mesh = _wedge_mesh(w[1], mat)
		mi.position = w[0]
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


## an imported model keeps its own materials unless it is coloured (then one plain material in that colour, the same as a box)
static func _tint_models(n: Node, colour: String, p: Dictionary) -> void:
	if colour == "grey" or p.has("mat"):
		return
	var m := StandardMaterial3D.new()
	m.albedo_color = COLOURS[colour]
	m.roughness = 0.9
	for c in n.find_children("*", "MeshInstance3D", true, false):
		(c as MeshInstance3D).material_override = m


## a wedge's triangular prism as a mesh: two triangles at each end, two per profile edge along the length; each face's
## normal is turned away from the prism's middle, so the faces point outward whatever their winding
static func _wedge_mesh(size: Vector3, mat: Material) -> ArrayMesh:
	var poly := wedge_profile(size)
	var w := size.x * 0.5
	var pts := []   # pts[2k] is profile point k at x = -w, pts[2k+1] the same at x = +w
	for v in poly:
		pts.append(Vector3(-w, v.y, v.x))
		pts.append(Vector3(w, v.y, v.x))
	var mid := Vector3.ZERO
	for q in pts:
		mid += q
	mid /= float(pts.size())
	var tris := []
	tris.append([pts[0], pts[2], pts[4]])
	tris.append([pts[1], pts[5], pts[3]])
	for i in 3:
		var j := (i + 1) % 3
		tris.append([pts[2 * i], pts[2 * j], pts[2 * j + 1]])
		tris.append([pts[2 * i], pts[2 * j + 1], pts[2 * i + 1]])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in tris:
		var a: Vector3 = t[0]
		var b: Vector3 = t[1]
		var c: Vector3 = t[2]
		var n := (b - a).cross(c - a).normalized()
		if n.dot((a + b + c) / 3.0 - mid) < 0.0:
			n = -n
		for v in t:
			st.set_normal(n)
			st.add_vertex(v)
	var am := st.commit()
	am.surface_set_material(0, mat)
	return am


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
	if sw.has("poly"):
		var d2 := _sdf2(Vector2(l.z, l.y), sw["poly"])
		var q := Vector2(d2, absf(l.x) - float(sw["w"]))
		return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0)
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
		# SNAP_UP caps a surface the point is OUTSIDE of (a table top over a foot). A point INSIDE the solid whose top this
		# is (a sole sunk into a 40 cm box, put at the floor by the ground pass) is lifted onto that top at any height
		var inside: bool = c.has("sw") and _sd(c["sw"], pt) < -REST_SINK
		if h > pt.y + SNAP_UP and not inside:
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
			if sw.has("poly"):
				cands.append_array(_wedge_faces_under(sw, x, z))
				continue
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
						cands.append({"y": y, "n": n, "sw": sw})
	return cands


## a wedge's upward faces under (x, z): each profile edge whose outward normal points up (the slope) gives the height of its
## plane on the vertical through (x, z), if that point is inside the edge's extent and within the wedge's width
static func _wedge_faces_under(sw: Dictionary, x: float, z: float) -> Array:
	var out := []
	var X: Transform3D = sw["xf"]
	var poly: PackedVector2Array = sw["poly"]
	var inv := X.affine_inverse()
	for i in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		var e := b - a
		# the outward normal of a counter-clockwise edge in (z, y) is (e.y, -e.x): as a 3D local vector (0, -e.x, e.y)
		var n := (X.basis * Vector3(0.0, -e.x, e.y).normalized()).normalized()
		if n.y < 0.5:
			continue
		var mid := (a + b) * 0.5
		var c := X * Vector3(0.0, mid.y, mid.x)
		var y := c.y - (n.x * (x - c.x) + n.z * (z - c.z)) / n.y
		var lp := inv * Vector3(x, y, z)
		var tpar := ((lp.z - a.x) * e.x + (lp.y - a.y) * e.y) / maxf(e.length_squared(), 1e-12)
		if absf(lp.x) <= float(sw["w"]) + 1e-6 and tpar >= -1e-6 and tpar <= 1.0 + 1e-6:
			out.append({"y": y, "n": n, "sw": sw})
	return out


## GROUNDSPEED: the cached twins of surface_below and its helpers (Body._sole_low_set reads these; the legacy functions above
## are unchanged and Body.legacy_ground runs them). The same arithmetic on the same numbers: each solid's inverse transform and
## box axes are computed once per cache, not per point. A box or sphere the point is beyond the bounding radius of is not
## inside it (its sd is >= 0 there), so the column test skips it without changing any answer.
static func solid_cache(props: Array) -> Array:
	var out := []
	for p in props:
		for sw in solids(p):
			var X: Transform3D = sw["xf"]
			sw["inv"] = X.affine_inverse()
			if sw.has("poly"):
				sw["rad"] = INF
			elif sw.has("r"):
				sw["rad"] = float(sw["r"])
			else:
				var h: Vector3 = sw["half"]
				sw["rad"] = h.length()
				sw["ax"] = [X.basis.x.normalized(), X.basis.y.normalized(), X.basis.z.normalized()]
			out.append(sw)
	return out


## _sd of a point given in the solid's own frame
static func _sd_local(sw: Dictionary, l: Vector3) -> float:
	if sw.has("r"):
		return l.length() - float(sw["r"])
	if sw.has("poly"):
		var d2 := _sdf2(Vector2(l.z, l.y), sw["poly"])
		var q2 := Vector2(d2, absf(l.x) - float(sw["w"]))
		return Vector2(maxf(q2.x, 0.0), maxf(q2.y, 0.0)).length() + minf(maxf(q2.x, q2.y), 0.0)
	var h: Vector3 = sw["half"]
	var q := Vector3(absf(l.x) - h.x, absf(l.y) - h.y, absf(l.z) - h.z)
	return Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0)).length() + minf(maxf(q.x, maxf(q.y, q.z)), 0.0)


static func _sd_c(sw: Dictionary, pt: Vector3) -> float:
	return _sd_local(sw, (sw["inv"] as Transform3D) * pt)


## is a point inside any cached solid (by more than REST_SINK)? A solid whose bounding radius the point is beyond is skipped
static func _inside_c(cache: Array, q: Vector3) -> bool:
	for sw in cache:
		var l: Vector3 = (sw["inv"] as Transform3D) * q
		if l.length() > float(sw["rad"]):
			continue
		if _sd_local(sw, l) < -REST_SINK:
			return true
	return false


## _column_blocked over the cache: the same points, the same test
static func _column_blocked_c(cache: Array, x: float, z: float, y0: float, y1: float) -> bool:
	if y1 < y0:
		return false
	var n := maxi(1, ceili((y1 - y0) / 0.01))
	for k in n + 1:
		var q := Vector3(x, minf(y0 + k * 0.01, y1), z)
		if _inside_c(cache, q):
			return true
	return false


## _faces_under over the cache (same candidates, same order)
static func _faces_under_c(cache: Array, x: float, z: float) -> Array:
	var cands := [{"y": 0.0, "n": Vector3.UP}]
	for sw in cache:
		if sw.has("r"):
			continue
		if sw.has("poly"):
			cands.append_array(_wedge_faces_c(sw, x, z))
			continue
		var X: Transform3D = sw["xf"]
		var h: Vector3 = sw["half"]
		var ax: Array = sw["ax"]
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
					cands.append({"y": y, "n": n, "sw": sw})
	return cands


## _wedge_faces_under over a cached wedge
static func _wedge_faces_c(sw: Dictionary, x: float, z: float) -> Array:
	var out := []
	var X: Transform3D = sw["xf"]
	var poly: PackedVector2Array = sw["poly"]
	var inv: Transform3D = sw["inv"]
	for i in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		var e := b - a
		var n := (X.basis * Vector3(0.0, -e.x, e.y).normalized()).normalized()
		if n.y < 0.5:
			continue
		var mid := (a + b) * 0.5
		var c := X * Vector3(0.0, mid.y, mid.x)
		var y := c.y - (n.x * (x - c.x) + n.z * (z - c.z)) / n.y
		var lp := inv * Vector3(x, y, z)
		var tpar := ((lp.z - a.x) * e.x + (lp.y - a.y) * e.y) / maxf(e.length_squared(), 1e-12)
		if absf(lp.x) <= float(sw["w"]) + 1e-6 and tpar >= -1e-6 and tpar <= 1.0 + 1e-6:
			out.append({"y": y, "n": n, "sw": sw})
	return out


## surface_below(props, pt) over a cached solid list: the same answer, {"y", "n"}
static func surface_below_c(cache: Array, pt: Vector3) -> Dictionary:
	var cands := _faces_under_c(cache, pt.x, pt.z)
	cands.sort_custom(func(a, b): return float(a["y"]) > float(b["y"]))
	for c in cands:
		var h := float(c["y"])
		var inside: bool = c.has("sw") and _sd_c(c["sw"], pt) < -REST_SINK
		if h > pt.y + SNAP_UP and not inside:
			continue
		if not _column_blocked_c(cache, pt.x, pt.z, h + 0.01, pt.y):
			return c
	return {"y": 0.0, "n": Vector3.UP}


## _over with the support's inverse transform cached (sup["inv"] = the affine inverse of its xf)
static func _over_c(sup: Dictionary, pt: Vector3) -> bool:
	var l: Vector3 = (sup["inv"] as Transform3D) * pt
	var c: Vector2 = sup["c"]
	var h: Vector2 = sup["half"]
	return absf(l.x - c.x) <= h.x and absf(l.z - c.y) <= h.y


## the height p should stand at: the floor (0), or the highest support of another prop that p's origin is over
static func snap_y(p: Dictionary, others: Array) -> float:
	var o: Vector3 = (p["xf"] as Transform3D).origin
	var y := 0.0
	for q in others:
		for sup in supports(q):
			if _over(sup, o):
				y = maxf(y, float(sup["y"]))
	return y
