class_name PartOrnament
extends RefCounted
## s227 ORNAMENTS (ranked gap #2 of the hall duel: Blender made ridge beasts by sculpt + modifiers, Kine drew a yellow polygon extrude).
## A library of ornaments made in code: chiwen ridge-end dragon (curling tail), corner beast row (a leading figure + small beasts), finial / spire,
## dragon head, guardian lion, cloud scroll bracket, lotus base, scroll (volute), ball finial, onion dome. Each is a seeded, parametric KMesh
## (scripts/build/ornament_shapes.gd: soft primitives -> surface nets -> Catmull-Clark -> pulled back onto the field) that PartMeshSolid sews into
## one closed solid. The Part record step (plain data, replayed, saved, one undo step):
##   {"t": "ornament", "id", "name", "kind": "chiwen" | ..., "seed": int, "size": [w, h, d] mm (x along the ridge, y up, z across: the box the
##    ornament fills EXACTLY, its bottom-centre at the placing point),
##    "places": [{"at": [x, y, z] mm, "dir": [x, y, z] (its +x, the way it looks, turned along this direction; up stays up)}, ...],
##    "row": {"n": count, "gap": mm, "along": [x, y, z], "shrink": 0.55} (kind "corner_row": a leading figure at the place, then n - 1 small beasts)}
## Every place is ONE new body. place_on_edge() turns a ridge or an edge (two points, mm) into places: along the edge to +-0.01 deg.
## The mesh stays in the record only as these numbers; "Sculpt this into the part" (part_sculpt.gd) turns one into a meshsolid step that keeps the mesh.

const MM := 0.001
const CELLS := 40   # surface-net cells along the longest side
const KINDS := {
	"chiwen": {"name": "Chiwen (ridge-end dragon)", "size": [700.0, 1100.0, 300.0], "words": ["chiwen", "chi wen", "ridge beast", "ridge dragon", "ridge-end dragon", "chiwens"]},
	"ridge_dragon": {"name": "Ridge dragon (chiwen head, mouth open)", "size": [1000.0, 1300.0, 420.0], "words": ["dragon head ridge", "ridge dragon head", "chiwen head", "ridge dragon"]},
	"corner_sprite": {"name": "Corner sprite (light, upturned)", "size": [300.0, 420.0, 140.0], "words": ["corner sprite", "light corner beast", "eave sprite"]},
	"corner_beast": {"name": "Corner beast", "size": [260.0, 300.0, 130.0], "words": ["corner beast", "eave beast", "small beast"]},
	"corner_lead": {"name": "Leading figure (rider on a phoenix)", "size": [520.0, 640.0, 260.0], "words": ["leading figure", "rider", "immortal"]},
	"corner_row": {"name": "Corner beast row", "size": [520.0, 640.0, 260.0], "words": ["corner beasts", "corner beast row", "eave beasts", "beast row"]},
	"finial": {"name": "Finial / spire", "size": [260.0, 950.0, 260.0], "words": ["finial", "spire", "pinnacle"]},
	"dragon_head": {"name": "Dragon head", "size": [700.0, 460.0, 520.0], "words": ["dragon head", "dragon"]},
	"lion": {"name": "Guardian lion", "size": [520.0, 760.0, 300.0], "words": ["guardian lion", "lion", "foo dog", "shishi"]},
	"cloud_bracket": {"name": "Cloud scroll bracket", "size": [420.0, 520.0, 90.0], "words": ["cloud scroll bracket", "cloud bracket", "cloud scroll", "cloud"]},
	"lotus_base": {"name": "Lotus base", "size": [620.0, 260.0, 620.0], "words": ["lotus base", "lotus"]},
	"scroll": {"name": "Scroll (volute)", "size": [560.0, 380.0, 140.0], "words": ["scroll", "volute"]},
	"ball_finial": {"name": "Ball finial", "size": [240.0, 440.0, 240.0], "words": ["ball finial", "ball"]},
	"onion_dome": {"name": "Onion dome", "size": [640.0, 940.0, 640.0], "words": ["onion dome", "dome"]},
}
const ORDER := ["chiwen", "ridge_dragon", "corner_row", "corner_sprite", "corner_beast", "corner_lead", "finial", "dragon_head", "lion", "cloud_bracket", "lotus_base", "scroll", "ball_finial", "onion_dome"]

static var _meshes := {}   # key -> {"km": KMesh (metres, bottom-centre at the origin), "f": the meshsolid fields, "vol": mm3, "ms": build time}
static var builds := 0     # how many meshes were built (tests read it: a replay builds none twice)


static func v(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, y, z)


static func is_kind(k: String) -> bool:
	return KINDS.has(k)


static func default_size(k: String) -> Vector3:
	var s: Array = KINDS[k]["size"]
	return Vector3(float(s[0]), float(s[1]), float(s[2]))


# --------------------------------------------------------------------------------------------------- designs
## the primitives of one ornament, in design units (about 1 tall); the seed moves a few proportions by up to 8 %
static func design(g: OrnShapes, kind: String) -> void:
	var j := func(a: float) -> float: return 1.0 + g.rng.randf_range(-a, a)
	match kind:
		"chiwen":
			var sc: float = j.call(0.08)
			g.ell(v(0.62, 0.2, 0), v(0.3, 0.19, 0.17), Vector3.ZERO, 0.06)
			g.cone(v(0.8, 0.28, 0), v(1.04, 0.33, 0), 0.115, 0.09, 0.04)
			g.cone(v(0.74, 0.09, 0), v(1.0, 0.1, 0), 0.07, 0.05, 0.03)
			for s in [-1.0, 1.0]:
				g.sph(v(1.03, 0.4, 0.05 * s), 0.035, 0.03)
				g.cone(v(0.62, 0.4, 0.12 * s), v(0.88, 0.42, 0.1 * s), 0.045, 0.035, 0.03)
				g.tube([v(0.5, 0.4, 0.07 * s), v(0.42, 0.62, 0.09 * s), v(0.28, 0.8, 0.1 * s), v(0.14, 0.82, 0.1 * s)], 0.05, 0.015, 0.03)
				g.tube([v(0.95, 0.12, 0.05 * s), v(1.1, 0.05, 0.12 * s), v(1.2, 0.1, 0.2 * s)], 0.02, 0.012, 0.02)   # whiskers
			g.ell(v(0.4, 0.04, 0), v(0.62, 0.07, 0.2), Vector3.ZERO, 0.04)   # the foot that sits on the ridge
			# the body: from the head back and up, then the tail curls forward over the top into a small spiral
			var body: Array = [v(0.5, 0.24, 0), v(0.22, 0.26, 0), v(0.06, 0.45, 0), v(0.04, 0.72, 0), v(0.14, 0.98 * sc, 0), v(0.36, 1.14 * sc, 0), v(0.6, 1.13 * sc, 0), v(0.72, 0.98 * sc, 0), v(0.66, 0.84 * sc, 0), v(0.53, 0.83 * sc, 0), v(0.48, 0.92 * sc, 0)]
			var pts := g.tube(body, 0.17, 0.035, 0.07, 1.0, 5)
			var n := pts.size()
			var k := 4
			while k < n - 6:   # back spines: small horns on the outside of the curl
				var p := pts[k]
				var q := pts[k + 1] - pts[k - 1]
				var out := Vector3(-q.y, q.x, 0.0).normalized()
				if k > 20:
					out = -out
				var r := lerpf(0.17, 0.035, float(k) / float(n - 1))
				g.cone(p + out * r * 0.5, p + out * (r + 0.13) + Vector3(0, 0.03, 0), r * 0.55, 0.012, 0.03)
				k += 4
		"ridge_dragon":
			# item 236: the ridge end as a DRAGON HEAD, like the reference's spiky crest: a neck rising from the ridge, a head with an OPEN MOUTH (a cut between
			# the upper and lower jaw), two horns swept back, eye sockets, a row of mane spikes down the neck and a tail curling up behind.
			var hh: float = j.call(0.06)
			g.ell(v(0.34, 0.05, 0), v(0.42, 0.06, 0.2), Vector3.ZERO, 0.04)   # the foot on the ridge
			g.tube([v(0.3, 0.05, 0), v(0.2, 0.28, 0), v(0.18, 0.5, 0), v(0.3, 0.7 * hh, 0)], 0.17, 0.12, 0.06, 1.0, 5)   # the neck
			g.ell(v(0.45, 0.86 * hh, 0), v(0.2, 0.15, 0.15), Vector3.ZERO, 0.05)   # the skull
			g.cone(v(0.5, 0.92 * hh, 0), v(0.9, 0.86 * hh, 0), 0.11, 0.07, 0.04)   # the upper jaw
			g.tube([v(0.88, 0.88 * hh, 0), v(0.98, 0.94 * hh, 0), v(1.0, 1.02 * hh, 0)], 0.05, 0.018, 0.03)   # the nose curls up
			g.cone(v(0.44, 0.7 * hh, 0), v(0.84, 0.64 * hh, 0), 0.08, 0.045, 0.04)   # the lower jaw
			for s in [-1.0, 1.0]:
				g.tube([v(0.4, 0.98 * hh, 0.08 * s), v(0.22, 1.12 * hh, 0.11 * s), v(0.04, 1.2 * hh, 0.14 * s), v(-0.1, 1.16 * hh, 0.15 * s)], 0.05, 0.012, 0.03)   # horns swept back
				g.tube([v(0.8, 0.8 * hh, 0.07 * s), v(0.95, 0.72 * hh, 0.18 * s), v(1.05, 0.6 * hh, 0.3 * s)], 0.02, 0.01, 0.02)   # whiskers
				g.cone(v(0.66, 0.8 * hh, 0.07 * s), v(0.68, 0.7 * hh, 0.07 * s), 0.018, 0.005, 0.01)   # fangs
			for q in 6:   # the mane: long flame spikes down the back of the neck, swept back
				var qy := 0.2 + 0.11 * float(q)
				g.cone(v(0.15, qy, 0), v(-0.16 - 0.03 * float(q), qy + 0.2, 0), 0.055, 0.008, 0.03)
			for q in 3:   # a crest of three prongs on the skull
				g.cone(v(0.34 + 0.07 * float(q), 0.98 * hh, 0), v(0.12 + 0.07 * float(q), 1.26 * hh + 0.04 * float(q), 0), 0.05, 0.008, 0.03)
			var tl := g.tube([v(0.26, 0.06, 0), v(0.0, 0.1, 0), v(-0.18, 0.34, 0), v(-0.1, 0.58, 0), v(0.06, 0.56, 0)], 0.1, 0.03, 0.05, 1.0, 5)   # the tail curls up behind
			var tk := 3
			while tk < tl.size() - 4:   # tail fins
				var tq := tl[tk + 1] - tl[tk - 1]
				var tout := Vector3(-tq.y, tq.x, 0.0).normalized()
				g.cone(tl[tk] + tout * 0.05, tl[tk] + tout * 0.2, 0.04, 0.008, 0.02)
				tk += 3
			g.begin_cut()
			g.cone(v(0.54, 0.78 * hh, 0), v(1.15, 0.75 * hh, 0), 0.03, 0.05, 0.01)   # the mouth, open between the jaws
			for s in [-1.0, 1.0]:
				g.sph(v(0.58, 0.93 * hh, 0.13 * s), 0.04, 0.015)   # eye sockets
		"corner_sprite":
			# item 236: a light eave figure: a slim body arching up and out on a small seat, a small horned head, a thin tail flick
			g.ell(v(0.12, 0.03, 0), v(0.16, 0.035, 0.07), Vector3.ZERO, 0.02)
			g.tube([v(0.1, 0.04, 0), v(0.06, 0.28, 0), v(0.16, 0.52, 0), v(0.34, 0.62, 0)], 0.075, 0.045, 0.04, 1.0, 4)
			g.ell(v(0.42, 0.66, 0), v(0.1, 0.07, 0.065), Vector3.ZERO, 0.03)
			g.cone(v(0.46, 0.7, 0), v(0.5, 0.86, 0), 0.025, 0.006, 0.01)   # horn
			g.cone(v(0.5, 0.64, 0), v(0.58, 0.62, 0), 0.04, 0.02, 0.02)   # snout
			g.tube([v(0.08, 0.1, 0), v(-0.06, 0.2, 0), v(-0.12, 0.4, 0)], 0.04, 0.008, 0.02)   # tail flick
		"corner_beast":
			g.ell(v(0, 0.28, 0), v(0.3, 0.22, 0.17), Vector3.ZERO, 0.07)
			g.ell(v(-0.14, 0.24, 0), v(0.22, 0.2, 0.2), Vector3.ZERO, 0.07)
			g.ell(v(0.16, 0.36, 0), v(0.2, 0.24, 0.16), Vector3.ZERO, 0.07)
			g.ell(v(0.38, 0.58, 0), v(0.17, 0.15, 0.14), Vector3.ZERO, 0.05)
			g.cone(v(0.5, 0.55, 0), v(0.64, 0.52, 0), 0.075, 0.055, 0.04)
			for s in [-1.0, 1.0]:
				g.tube([v(0.34, 0.68, 0.07 * s), v(0.3, 0.8, 0.08 * s), v(0.22, 0.9, 0.08 * s)], 0.045, 0.015, 0.03)
				g.cone(v(0.2, 0.22, 0.11 * s), v(0.3, 0.04, 0.11 * s), 0.065, 0.05, 0.04)
				g.ell(v(0.34, 0.04, 0.11 * s), v(0.1, 0.045, 0.06), Vector3.ZERO, 0.03)
				g.ell(v(-0.12, 0.05, 0.13 * s), v(0.14, 0.05, 0.07), Vector3.ZERO, 0.03)
			g.tube([v(-0.28, 0.3, 0), v(-0.46, 0.38, 0), v(-0.54, 0.58, 0), v(-0.42, 0.74, 0), v(-0.32, 0.64, 0)], 0.08, 0.03, 0.04)
		"corner_lead":
			var tail: float = j.call(0.1)
			g.ell(v(0, 0.3, 0), v(0.34, 0.25, 0.2), Vector3.ZERO, 0.07)
			g.ell(v(0.2, 0.36, 0), v(0.2, 0.22, 0.17), Vector3.ZERO, 0.07)
			g.tube([v(0.3, 0.45, 0), v(0.42, 0.62, 0), v(0.45, 0.8, 0)], 0.09, 0.06, 0.04)
			g.sph(v(0.5, 0.88, 0), 0.075, 0.03)
			g.cone(v(0.55, 0.88, 0), v(0.68, 0.85, 0), 0.04, 0.012, 0.02)
			g.tube([v(0.48, 0.95, 0), v(0.44, 1.05, 0), v(0.36, 1.1, 0)], 0.03, 0.012, 0.02)
			for d in [-0.16, 0.0, 0.16]:   # tail feathers fan out and up
				g.tube([v(-0.28, 0.36, 0), v(-0.46, 0.5 + d * 0.6, d), v(-0.58, 0.72 * tail + d * 0.4, d * 1.5)], 0.07, 0.02, 0.03)
			for s in [-1.0, 1.0]:
				g.cone(v(0.05, 0.12, 0.1 * s), v(0.06, 0.02, 0.12 * s), 0.035, 0.03, 0.02)
				g.ell(v(0.1, 0.03, 0.12 * s), v(0.1, 0.035, 0.05), Vector3.ZERO, 0.02)
			g.cone(v(0.0, 0.52, 0), v(0.0, 0.92, 0), 0.19, 0.11, 0.06)   # the rider's robe
			g.sph(v(0.02, 1.04, 0), 0.1, 0.04)
			g.cone(v(0.02, 1.1, 0), v(0.02, 1.24, 0), 0.05, 0.02, 0.03)
			g.tube([v(0.04, 0.88, 0.1), v(0.16, 0.84, 0.13), v(0.26, 0.9, 0.12)], 0.05, 0.035, 0.03)
		"finial":
			g.ell(v(0, 0.04, 0), v(0.5, 0.05, 0.5), Vector3.ZERO, 0.02)
			g.lathe([[0.36, 0.05], [0.3, 0.18], [0.3, 0.3], [0.22, 0.4], [0.27, 0.55], [0.2, 0.7], [0.13, 0.85], [0.08, 1.1], [0.05, 1.45], [0.04, 1.85]], 0.03)
			for y in [0.3, 0.55, 0.92]:
				g.ell(v(0, y, 0), v(0.34 if y < 0.9 else 0.17, 0.035, 0.34 if y < 0.9 else 0.17), Vector3.ZERO, 0.03)
			g.sph(v(0, 1.9, 0), 0.07, 0.03)
		"dragon_head":
			var horn: float = j.call(0.1)
			g.ell(v(0, 0.45, 0), v(0.36, 0.3, 0.3), Vector3.ZERO, 0.07)
			g.cone(v(0.25, 0.52, 0), v(0.78, 0.5, 0), 0.2, 0.13, 0.05)
			g.sph(v(0.78, 0.6, 0), 0.1, 0.04)
			g.cone(v(0.1, 0.2, 0), v(0.66, 0.2, 0), 0.15, 0.09, 0.04)   # the lower jaw
			g.cone(v(-0.1, 0.25, 0), v(-0.35, 0.05, 0), 0.3, 0.27, 0.06)   # the neck
			g.ell(v(-0.15, 0.03, 0), v(0.55, 0.06, 0.42), Vector3.ZERO, 0.04)
			for s in [-1.0, 1.0]:
				g.tube([v(-0.02, 0.7, 0.18 * s), v(-0.3, 0.92 * horn, 0.25 * s), v(-0.62, 0.98 * horn, 0.28 * s), v(-0.85, 0.86 * horn, 0.3 * s)], 0.08, 0.015, 0.04)
				g.cone(v(0.1, 0.72, 0.2 * s), v(0.42, 0.7, 0.13 * s), 0.07, 0.04, 0.03)
				g.ell(v(-0.08, 0.55, 0.36 * s), v(0.06, 0.2, 0.15), Vector3.ZERO, 0.03)
				g.tube([v(0.66, 0.32, 0.1 * s), v(0.9, 0.2, 0.3 * s), v(1.1, 0.12, 0.46 * s)], 0.025, 0.012, 0.02)
				g.cone(v(0.5, 0.36, 0.1 * s), v(0.52, 0.28, 0.1 * s), 0.022, 0.006, 0.01)   # upper fangs
				g.cone(v(0.55, 0.3, 0.1 * s), v(0.57, 0.38, 0.1 * s), 0.02, 0.006, 0.01)
			for d in [-0.15, 0.0, 0.15]:   # the mane: flame tongues swept back
				g.tube([v(-0.12, 0.55 + d, 0), v(-0.45, 0.6 + d * 1.4, d * 0.5), v(-0.8, 0.5 + d * 1.2, d * 0.6)], 0.06, 0.015, 0.03)
			g.begin_cut()
			g.cone(v(0.2, 0.355, 0), v(1.1, 0.36, 0), 0.02, 0.035, 0.01)   # the mouth
			for s in [-1.0, 1.0]:
				g.sph(v(0.3, 0.62, 0.23 * s), 0.05, 0.02)   # eye sockets
				g.sph(v(0.86, 0.58, 0.05 * s), 0.025, 0.01)   # nostrils
		"lion":
			g.rbox(v(0, 0.07, 0), v(0.55, 0.07, 0.3), 0.03, 0.02)
			g.ell(v(-0.15, 0.38, 0), v(0.3, 0.27, 0.24), Vector3.ZERO, 0.07)
			g.cone(v(-0.15, 0.4, 0), v(0.16, 0.64, 0), 0.2, 0.22, 0.06)
			g.ell(v(0.2, 0.55, 0), v(0.2, 0.3, 0.22), Vector3.ZERO, 0.06)
			for s in [-1.0, 1.0]:
				g.cone(v(0.22, 0.5, 0.11 * s), v(0.3, 0.2, 0.11 * s), 0.085, 0.07, 0.04)
				g.ell(v(0.36, 0.18, 0.11 * s), v(0.11, 0.05, 0.07), Vector3.ZERO, 0.03)
				g.sph(v(0.15, 1.14, 0.1 * s), 0.05, 0.03)
				g.sph(v(-0.28, 0.18, 0.2 * s), 0.1, 0.03)
			g.ell(v(0.2, 0.98, 0), v(0.19, 0.17, 0.17), Vector3.ZERO, 0.05)
			for a in 12:   # the mane: a ruff of lobes round the head
				var an := TAU * float(a) / 12.0
				g.ell_dir(v(0.1, 0.98 + 0.2 * sin(an), 0.21 * cos(an)), v(0.2, sin(an), cos(an)), 0.12, 0.09, 0.07, 0.05)
			g.cone(v(0.34, 0.95, 0), v(0.44, 0.9, 0), 0.08, 0.065, 0.04)
			g.sph(v(0.47, 0.93, 0), 0.04, 0.03)
			g.tube([v(-0.4, 0.3, 0), v(-0.52, 0.5, 0), v(-0.44, 0.72, 0), v(-0.3, 0.68, 0)], 0.06, 0.04, 0.03)
			g.begin_cut()
			g.cone(v(0.38, 0.86, 0), v(0.6, 0.86, 0), 0.012, 0.02, 0.01)
			for s in [-1.0, 1.0]:
				g.sph(v(0.36, 1.03, 0.09 * s), 0.03, 0.01)
		"cloud_bracket":
			var sw: float = j.call(0.1)
			var zf := 2.6
			var sp := PackedVector3Array()
			for i in 22:   # the big curl on top: a spiral, 1.7 turns
				var a := -0.6 + TAU * 1.7 * float(i) / 21.0
				var r := lerpf(0.3, 0.07, float(i) / 21.0) * sw
				sp.append(v(0.45 + r * cos(a), 0.78 + r * sin(a), 0))
			for i in range(sp.size() - 1):
				g.cone(sp[i], sp[i + 1], lerpf(0.075, 0.04, float(i) / 21.0), lerpf(0.075, 0.04, float(i + 1) / 21.0), 0.03, zf)
			var sp2 := PackedVector3Array()
			for i in 16:   # the small curl below, turning the other way
				var a := PI + 0.4 - TAU * 1.3 * float(i) / 15.0
				var r := lerpf(0.2, 0.06, float(i) / 15.0)
				sp2.append(v(0.0 + r * cos(a), 0.38 + r * sin(a), 0))
			for i in range(sp2.size() - 1):
				g.cone(sp2[i], sp2[i + 1], lerpf(0.065, 0.038, float(i) / 15.0), lerpf(0.065, 0.038, float(i + 1) / 15.0), 0.03, zf)
			g.tube([v(0.22, 0.06, 0), v(0.3, 0.3, 0), v(0.15, 0.55, 0), v(0.18, 0.78, 0)], 0.1, 0.075, 0.04, zf)
			g.tube([v(0.28, 0.5, 0), v(0.1, 0.5, 0), v(0.0, 0.46, 0)], 0.07, 0.06, 0.04, zf)
			g.ell(v(0.28, 0.03, 0), v(0.34, 0.05, 0.05), Vector3.ZERO, 0.03)
		"lotus_base":
			g.lathe([[0.55, 0.0], [0.58, 0.1], [0.5, 0.2], [0.42, 0.28]], 0.03)
			for layer in 2:
				var n := 12 if layer == 0 else 9
				var tilt := 0.55 if layer == 0 else 0.95
				var rr := 0.42 if layer == 0 else 0.3
				for i in n:
					var an := TAU * (float(i) + 0.5 * layer) / float(n)
					var dir := v(sin(tilt) * cos(an), cos(tilt), sin(tilt) * sin(an))
					g.ell_dir(v(rr * cos(an), 0.3 + 0.1 * layer, rr * sin(an)) + dir * 0.1, dir, 0.17, 0.085, 0.045, 0.03)
			g.cone(v(0, 0.3, 0), v(0, 0.52, 0), 0.2, 0.17, 0.04)
			g.ell(v(0, 0.55, 0), v(0.2, 0.05, 0.2), Vector3.ZERO, 0.02)
		"scroll":
			var pts := PackedVector3Array()
			for i in 30:
				var a := PI + TAU * 2.1 * float(i) / 29.0
				var r := lerpf(0.5, 0.07, float(i) / 29.0)
				pts.append(v(0.0 + r * cos(a), 0.55 + r * sin(a), 0))
			for i in range(pts.size() - 1):
				g.cone(pts[i], pts[i + 1], lerpf(0.1, 0.05, float(i) / 29.0), lerpf(0.1, 0.05, float(i + 1) / 29.0), 0.03, 0.7)
			g.tube([pts[0], v(0.4, 0.06, 0), v(0.85, 0.08, 0), v(1.1, 0.1, 0)], 0.1, 0.1, 0.04, 0.7)
			g.ell(v(0.5, 0.03, 0), v(0.65, 0.05, 0.12), Vector3.ZERO, 0.03)
		"ball_finial":
			g.ell(v(0, 0.04, 0), v(0.38, 0.05, 0.38), Vector3.ZERO, 0.02)
			g.lathe([[0.2, 0.05], [0.14, 0.25], [0.2, 0.4]], 0.03)
			g.sph(v(0, 0.82, 0), 0.4, 0.04)
			g.ell(v(0, 0.45, 0), v(0.27, 0.035, 0.27), Vector3.ZERO, 0.02)
			g.cone(v(0, 1.2, 0), v(0, 1.4, 0), 0.07, 0.03, 0.03)
		"onion_dome":
			var rows: Array = [[0.5, 0.0], [0.5, 0.2], [0.42, 0.24], [0.52, 0.34], [0.62, 0.5], [0.6, 0.66], [0.48, 0.82], [0.3, 0.96], [0.17, 1.08], [0.1, 1.17], [0.07, 1.27]]
			g.lathe(rows, 0.03)
			g.cone(v(0, 1.2, 0), v(0, 1.5, 0), 0.07, 0.035, 0.03)
			g.sph(v(0, 1.3, 0), 0.085, 0.03)
			g.ell(v(0, 0.22, 0), v(0.56, 0.03, 0.56), Vector3.ZERO, 0.02)
		_:
			g.sph(v(0, 0.5, 0), 0.5, 0.05)


# --------------------------------------------------------------------------------------------------- the mesh
static func _key(kind: String, seed: int, size: Vector3) -> String:
	return "%s|%d|%.3f|%.3f|%.3f" % [kind, seed, size.x, size.y, size.z]


## the closed mesh of one ornament, scaled to size (mm) exactly, bottom-centre at the origin (metres). null + why in `err`
static var err := ""


static func mesh(kind: String, seed: int, size_mm: Vector3) -> KMesh:
	var d := mesh_dict(kind, seed, size_mm)
	return d["km"] if not d.is_empty() else null


static func mesh_dict(kind: String, seed: int, size_mm: Vector3) -> Dictionary:
	err = ""
	var base := kind
	if kind == "corner_row":
		base = "corner_lead"
	if not KINDS.has(base):
		err = "Kine has no ornament called %s" % kind
		return {}
	var key := _key(base, seed, size_mm)
	if _meshes.has(key):
		return _meshes[key]
	var t0 := Time.get_ticks_msec()
	var km: KMesh = null
	var why := ""
	for attempt in 9:
		var g := OrnShapes.new()
		g.rng.seed = seed * 7919 + 13
		design(g, base)
		var bb := g.bounds()
		g.begin_cut()
		g._add(OrnShapes.T_BELOW, v(0, bb.position.y + 0.035 * bb.size.y, 0), Vector3.ZERO, 0.0, 0.0, 1.0, 0.0, Basis(), v(6, 6, 6))
		var cells := CELLS + (attempt % 3) * 5 + (attempt / 3) * 2
		var iso := 0.0012 * float(attempt % 4) * (1.0 if attempt % 2 == 0 else -1.0)
		km = g.nets(cells, iso)
		if km != null:
			km = OrnShapes.keep_largest(km)   # the specks a thin feature leaves are not part of the figure
		if km == null:
			why = "grid %d: the skin pinches (surface nets)" % cells
			continue
		var h := maxf(bb.size.x, maxf(bb.size.y, bb.size.z)) / float(cells)
		g.project(km, h * 0.25, 1)
		g.project(km, h * 0.12, 1)   # no subdivision: the kernel's sewing time grows with the square of the triangles (27k tris took 67 s, 8k took 7 s)
		if km.boundary_edge_count() == 0 and km.is_manifold() and OrnShapes._signed_volume(km) > 0.0:
			break
		why = "grid %d: not manifold after subdivide (boundary %d, vol %.3f)" % [cells, km.boundary_edge_count(), OrnShapes._signed_volume(km)]
		km = null
	if km == null:
		err = "The %s could not be made as one closed piece (try another seed): %s" % [KINDS[base]["name"], why]
		return {}
	# scale to the asked box: bottom-centre at the origin
	var lo := km.verts[0]
	var hi := km.verts[0]
	for p in km.verts:
		lo = lo.min(p)
		hi = hi.max(p)
	var ext := hi - lo
	var want := size_mm * MM
	for i in km.verts.size():
		var p := km.verts[i]
		km.verts[i] = Vector3((p.x - (lo.x + hi.x) * 0.5) * want.x / ext.x, (p.y - lo.y) * want.y / ext.y, (p.z - (lo.z + hi.z) * 0.5) * want.z / ext.z)
	km.rebuild()
	var got := PartMeshSolid.from_mesh(km)
	if not bool(got["ok"]):
		err = String(got["why"])
		return {}
	builds += 1
	var out := {"km": km, "f": got["f"], "vol": float(got["vol_mm3"]), "ms": Time.get_ticks_msec() - t0}
	_meshes[key] = out
	return out


# --------------------------------------------------------------------------------------------------- the record
static func vec(a: Variant) -> Vector3:
	var l: Array = a
	return Vector3(float(l[0]), float(l[1]), float(l[2]))


static func arr(p: Vector3) -> Array:
	return [snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)]


## the step's fields for `kind` (a record step: Part.new_feature(rec, "ornament", fields)); size_mm = (0, 0, 0) takes the default box
static func fields(kind: String, seed: int, places: Array, size_mm := Vector3.ZERO, row := {}) -> Dictionary:
	var f := {"name": String(KINDS[kind]["name"]), "kind": kind, "seed": seed, "size": arr(size_mm if size_mm != Vector3.ZERO else default_size(kind)), "places": places}
	if kind == "corner_row":
		var sz := size_mm if size_mm != Vector3.ZERO else default_size(kind)
		f["row"] = {"n": int(row.get("n", 5)), "gap": float(row.get("gap", sz.x * 0.62)), "along": row.get("along", [1.0, 0.0, 0.0]), "shrink": float(row.get("shrink", 0.5))}
	return f


## one place from a ridge or any edge (two points, mm): `t` along it (0..1); the ornament looks along the edge, from a toward b
static func place_on_edge(a: Vector3, b: Vector3, t: float) -> Dictionary:
	return {"at": arr(a.lerp(b, t)), "dir": arr((b - a).normalized())}


## the two ends of a ridge, each looking inward, `inset` mm in from the end
static func ends_of(a: Vector3, b: Vector3, inset := 0.0) -> Array:
	var d := (b - a).normalized()
	return [{"at": arr(a + d * inset), "dir": arr(d)}, {"at": arr(b - d * inset), "dir": arr(-d)}]


## `n` places spread along an edge, evenly, the first and last `inset` mm in from the ends
static func spread_on(a: Vector3, b: Vector3, n: int, inset := 0.0) -> Array:
	var out: Array = []
	var d := (b - a).normalized()
	var a2 := a + d * inset
	var b2 := b - d * inset
	for i in n:
		out.append({"at": arr(a2.lerp(b2, 0.5 if n == 1 else float(i) / float(n - 1))), "dir": arr(d)})
	return out


## the basis whose +x is dir and whose +y leans toward world up (a pitched ridge tilts the ornament with it)
static func basis_for(dir: Vector3) -> Basis:
	var x := dir.normalized()
	var up := Vector3.UP - x * Vector3.UP.dot(x)
	if up.length() < 1e-4:
		up = Vector3.BACK - x * Vector3.BACK.dot(x)
	var y := up.normalized()
	return Basis(x, y, x.cross(y).normalized())


## the pieces a step makes: [{"kind", "size": Vector3 mm, "at": Vector3 mm, "dir": Vector3}] (a row expands to its leading figure and small beasts)
static func pieces(f: Dictionary) -> Array:
	var out: Array = []
	var kind := String(f.get("kind", ""))
	var size := vec(f.get("size", arr(default_size(kind) if KINDS.has(kind) else Vector3.ONE * 100.0)))
	for pl in f.get("places", []):
		var at := vec(pl["at"])
		var dir := vec(pl.get("dir", [1.0, 0.0, 0.0]))
		if kind == "corner_row":
			var row: Dictionary = f.get("row", {})
			var n := maxi(1, int(row.get("n", 5)))
			var along := vec(row.get("along", [1.0, 0.0, 0.0])).normalized()
			var gap := float(row.get("gap", size.x * 0.62))
			var sh := float(row.get("shrink", 0.5))
			out.append({"kind": "corner_lead", "size": size, "at": at, "dir": dir})
			for k in range(1, n):
				out.append({"kind": "corner_beast", "size": size * sh, "at": at + along * (gap * float(k) + size.x * 0.5 * (1.0 - sh) * 0.0), "dir": dir})
		else:
			out.append({"kind": kind, "size": size, "at": at, "dir": dir})
	return out


## s237 SEAT: an ornament placed ON a body (a roof) rests on it. Rays go straight down from over the base's footprint (a 3 x 3 grid inside the box, x along `bas`.x,
## z across) onto the bodies already built; the highest hit under each sample is the surface there. With 5 or more hits the base leans to their best plane
## (at most SEAT_TILT_DEG, so a curled hip carries a flat-footed beast without a wedge of air under it); then it drops (or rises) until its lowest footprint point is
## SEAT_SINK_MM under the highest surface point, so the gap to the roof is 0 and the base is buried by at most that. Nothing under it within the capture range
## (max(height, 500) mm below the base): free space, the place is returned unchanged. -> {"basis", "at", "seated": bool, "hits": int, "sink": mm}
const SEAT_SINK_MM := 20.0
const SEAT_TILT_DEG := 35.0
const SEAT_CAST_MM := 3000.0


## the mesh's own lowest points (local mm): the vertices in the bottom fifth of its height, at most 60 of them: what the seat drops onto the roof
static func _base_pts(km: KMesh, sz: Vector3) -> Array:
	var low: Array = []
	for p in km.verts:
		if p.y <= 0.2 * sz.y * MM:
			low.append(p / MM)
	if low.size() <= 60:
		return low
	var out: Array = []
	var step := float(low.size()) / 60.0
	for i in 60:
		out.append(low[int(float(i) * step)])
	return out


static func _foot(sz: Vector3) -> Array:
	var out: Array = []
	for i in 3:
		for k in 3:
			out.append(Vector3((float(i) - 1.0) * 0.45 * sz.x, 0.0, (float(k) - 1.0) * 0.45 * sz.z))
	return out


static func _surface_under(bodies: Array, pts: Array, top_y: float, low_y: float) -> Array:
	return PartFast.surface_under(bodies, pts, top_y, low_y)   # s249: same answers, a grid per host body (was 40 s of the temple build)


static func _surface_under_ref(bodies: Array, pts: Array, top_y: float, low_y: float) -> Array:   # the s237 original, kept as the control for tests/s249_test.gd
	var hits: Array = []   # per sample: the highest surface y in [low_y, top_y], or NAN
	var region := AABB()
	var first := true
	for q in pts:
		var qq: Vector3 = q
		var bx := AABB(Vector3(qq.x, low_y, qq.z), Vector3.ZERO)
		region = bx if first else region.merge(bx)
		first = false
	region = region.grow(1.0)
	region.size.y = maxf(region.size.y, top_y - low_y)
	var cand: Array = []
	for id in bodies:
		var t := PartFacts.tess_mm(int(id), 0.002, 0.8)
		if t.is_empty():
			continue
		var bb := PartFacts.box_of(t)
		if bb.position.x > region.end.x or bb.end.x < region.position.x or bb.position.z > region.end.z or bb.end.z < region.position.z or bb.end.y < low_y or bb.position.y > top_y:
			continue
		cand.append(t)
	for q in pts:
		var qq: Vector3 = q
		var best := NAN
		for t in cand:
			var d := PartFacts.ray_hit(t, Vector3(qq.x, top_y, qq.z), Vector3.DOWN)
			if is_inf(d):
				continue
			var y := top_y - d
			if y >= low_y and (is_nan(best) or y > best):
				best = y
		hits.append(best)
	return hits


static func seat(bodies: Array, size_mm: Vector3, bas: Basis, at: Vector3, foot_pts: Array = []) -> Dictionary:
	var out := {"basis": bas, "at": at, "seated": false, "hits": 0, "sink": 0.0}
	if bodies.is_empty():
		return out
	var foot: Array = foot_pts if foot_pts.size() >= 5 else _foot(size_mm)
	var cap := maxf(size_mm.y, 500.0)
	var cur := bas
	var pos := at
	var hits: Array = []
	var world: Array = []
	for pass_i in 2:
		world = foot.map(func(l): return cur * (l as Vector3) + pos)
		hits = _surface_under(bodies, world, pos.y + size_mm.y, pos.y - cap)
		var n := 0
		for h in hits:
			if not is_nan(float(h)):
				n += 1
		if n == 0:
			return out
		if n >= 5 and pass_i == 0:
			# the best plane y = p x + q z + c through the hits (normal equations)
			var sxx := 0.0
			var sxz := 0.0
			var szz := 0.0
			var sx := 0.0
			var sz := 0.0
			var sy := 0.0
			var sxy := 0.0
			var szy := 0.0
			for i in world.size():
				if is_nan(float(hits[i])):
					continue
				var w: Vector3 = world[i]
				var y: float = hits[i]
				sxx += w.x * w.x
				sxz += w.x * w.z
				szz += w.z * w.z
				sx += w.x
				sz += w.z
				sy += y
				sxy += w.x * y
				szy += w.z * y
			var m := Basis(Vector3(sxx, sxz, sx), Vector3(sxz, szz, sz), Vector3(sx, sz, float(n)))
			if absf(m.determinant()) > 1e-6:
				var sol := m.inverse() * Vector3(sxy, szy, sy)   # (p, q, c)
				var nrm := Vector3(-sol.x, 1.0, -sol.y).normalized()
				var lean := acos(clampf(nrm.dot(Vector3.UP), -1.0, 1.0))
				if lean > deg_to_rad(SEAT_TILT_DEG):
					nrm = Vector3.UP.slerp(nrm, deg_to_rad(SEAT_TILT_DEG) / lean).normalized()
				var dirx: Vector3 = cur.x - nrm * cur.x.dot(nrm)
				if dirx.length() > 1e-4 and lean > 1e-4:
					dirx = dirx.normalized()
					cur = Basis(dirx, nrm, dirx.cross(nrm).normalized())
	var dy := -INF
	world = foot.map(func(l): return cur * (l as Vector3) + pos)
	for i in world.size():
		if is_nan(float(hits[i])):
			continue
		dy = maxf(dy, float(hits[i]) - (world[i] as Vector3).y)
	var nh := 0
	for h in hits:
		if not is_nan(float(h)):
			nh += 1
	out["basis"] = cur
	out["at"] = pos + Vector3(0.0, dy - SEAT_SINK_MM, 0.0)
	out["seated"] = true
	out["hits"] = nh
	out["sink"] = SEAT_SINK_MM
	return out


## the replay arm (Part.replay): every piece is one new body. "" or the plain reason it could not
static func add(bodies: Array, f: Dictionary) -> String:
	if not PartMeshSolid.KCad.has_mesh_solid():
		return "The part library is older than this step: restart Kine, or reinstall it"
	var kind := String(f.get("kind", ""))
	if not KINDS.has(kind):
		return "Kine has no ornament called %s" % kind
	var made: Array = []
	for pc in pieces(f):
		var sz: Vector3 = pc["size"]
		var d := mesh_dict(String(pc["kind"]), int(f.get("seed", 1)), sz)
		if d.is_empty():
			for id in made:
				PartMeshSolid.KCad.release(int(id))
			return err
		var id := PartMeshSolid.solid(d["f"])
		if id == 0:
			for mid in made:
				PartMeshSolid.KCad.release(int(mid))
			return PartMeshSolid.KCad.last_error() if PartMeshSolid.KCad.last_error() != "" else "The ornament could not become a solid"
		var bas := basis_for(pc["dir"])
		var at_mm: Vector3 = pc["at"]
		if bool(f.get("seat", false)) or bool(pc.get("seat", false)):
			var st := seat(bodies, sz, bas, at_mm, _base_pts(d["km"], sz))   # s237: rest the base on the host body under it
			bas = st["basis"]
			at_mm = st["at"]
		var q := bas.get_rotation_quaternion()
		var ang := q.get_angle()
		if absf(ang) > 1e-7:
			var r := PartMeshSolid.KCad.rotate(id, q.get_axis(), ang)
			PartMeshSolid.KCad.release(id)
			id = r
		if id != 0:
			var tr := PartMeshSolid.KCad.translate(id, at_mm * MM)
			PartMeshSolid.KCad.release(id)
			id = tr
		if id == 0:
			for mid in made:
				PartMeshSolid.KCad.release(int(mid))
			return PartMeshSolid.KCad.last_error()
		PartFast.hint_box(id, d["km"], bas, at_mm)   # s249n: its box is known without tessellating it (a later ornament's seat skips it by box)
		made.append(id)
	for id in made:
		bodies.append(id)
	return ""


# --------------------------------------------------------------------------------------------------- words
const NUMBERS := {"a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10}

## "2 chiwen on the ridge ends", "5 corner beasts", "a lion 60 cm tall" -> {"ok", "why", "kind", "count", "where": "ends" | "ridge" | "", "height": mm or 0}
static func parse(text: String) -> Dictionary:
	var t := text.to_lower().strip_edges()
	var out := {"ok": false, "why": "", "kind": "", "count": 1, "where": "", "height": 0.0}
	if t == "":
		out["why"] = "Type an ornament, like: 2 chiwen on the ridge ends, or 5 corner beasts"
		return out
	var best := ""
	var best_len := 0
	for k in KINDS:
		for w in KINDS[k]["words"]:
			if t.find(String(w)) >= 0 and String(w).length() > best_len:
				best = k
				best_len = String(w).length()
	if best == "":
		return out
	out["kind"] = best
	var m := RegEx.create_from_string("(\\d+|\\ba\\b|\\ban\\b|\\bone\\b|\\btwo\\b|\\bthree\\b|\\bfour\\b|\\bfive\\b|\\bsix\\b|\\bseven\\b|\\beight\\b|\\bnine\\b|\\bten\\b)\\s+(?:small\\s+|little\\s+)?(?:" + "|".join(PackedStringArray(KINDS[best]["words"])) + ")").search(t)
	if m != null:
		var w := m.get_string(1)
		out["count"] = int(w) if w.is_valid_int() else int(NUMBERS.get(w, 1))
	if best == "corner_row" and m == null:
		out["count"] = 5
	if out["count"] < 1 or out["count"] > 40:
		out["why"] = "Ask for 1 to 40 ornaments"
		return out
	if t.find("ridge end") >= 0 or t.find("end of the ridge") >= 0 or t.find("ends of the ridge") >= 0:
		out["where"] = "ends"
	elif t.find("ridge") >= 0 or t.find("roof") >= 0:
		out["where"] = "ridge"
	var mh := RegEx.create_from_string("(\\d+(?:\\.\\d+)?)\\s*(mm|cm|m)\\s*(?:high|tall)").search(t)
	if mh != null:
		out["height"] = float(mh.get_string(1)) * (1.0 if mh.get_string(2) == "mm" else (10.0 if mh.get_string(2) == "cm" else 1000.0))
	out["ok"] = true
	return out


## the roof step of a part record that `ref` names (a step id or name; true / "" / "last" = the last roof step): the step dict, or {}
static func roof_step(rec: Dictionary, ref: Variant) -> Dictionary:
	var found := {}
	for f in rec.get("features", []):
		if String((f as Dictionary).get("t", "")) != "roof":
			continue
		if ref is String and String(ref) not in ["", "last", "true"] and String(f.get("id", "")) != String(ref) and String(f.get("name", "")) != String(ref):
			continue
		found = f
	return found


## the ridge of a part record: its highest level, from its left to its right end, down the middle of its depth (mm); {} when it has no body
static func ridge_of(rec: Dictionary) -> Dictionary:
	var res := Part.replay(rec)
	if int(res["bodies"]) == 0 or not (res["aabb"] is AABB):
		return {}
	var bb: AABB = res["aabb"]
	var c := bb.get_center() / MM
	var top := bb.end.y / MM
	var half := bb.size.x / MM * 0.5
	return {"a": Vector3(c.x - half, top, c.z), "b": Vector3(c.x + half, top, c.z)}


## the step for a typed sentence on a part record (the record is not changed): {"ok", "why", "fields", "said"}
static func from_words(text: String, rec: Dictionary, seed := 1) -> Dictionary:
	var p := parse(text)
	if not bool(p["ok"]):
		return {"ok": false, "why": String(p["why"]) if String(p["why"]) != "" else "Kine knows these ornaments: " + ", ".join(ORDER.map(func(k): return String(KINDS[k]["name"]).to_lower())), "fields": {}, "said": ""}
	var kind: String = p["kind"]
	var n: int = p["count"]
	var size := default_size(kind)
	if float(p["height"]) > 0.0:
		size *= float(p["height"]) / size.y
	var places: Array = []
	var where := String(p["where"])
	var ridge := ridge_of(rec)
	var row := {}
	if kind == "corner_row":
		row = {"n": n}
		n = 1
	if where != "" and not ridge.is_empty():
		var a: Vector3 = ridge["a"]
		var b: Vector3 = ridge["b"]
		var inset := minf(size.x * 0.5, (b - a).length() * 0.25)   # a short ridge: the pair stays apart
		if where == "ends" and n == 2:
			places = ends_of(a, b, inset)
		elif where == "ends":
			places = ends_of(a, b, inset).slice(0, 1) if n == 1 else spread_on(a, b, n, inset)
		else:
			places = spread_on(a, b, n, inset)
	else:
		var start := Vector3.ZERO
		if int(Part.replay(rec)["bodies"]) > 0:
			var bb: AABB = Part.replay(rec)["aabb"]
			start = Vector3(bb.end.x / MM + size.x * 0.75, 0.0, bb.get_center().z / MM)
		for i in n:
			places.append({"at": arr(start + Vector3(size.x * 1.3 * float(i), 0.0, 0.0)), "dir": [1.0, 0.0, 0.0]})
	var wf := fields(kind, seed, places, size, row)
	if where != "" and not ridge.is_empty():
		wf["seat"] = true   # s237: on the ridge means resting on it
	return {"ok": true, "why": "", "fields": wf, "said": "%d %s" % [n if kind != "corner_row" else int(row["n"]), String(KINDS[kind]["name"]).to_lower()]}


# --------------------------------------------------------------------------------------------------- for code and for the agent
## add an ornament step to the part of `m` (the main node): ONE undo step. p: {"words": "2 chiwen on the ridge ends"} or {"kind", "count", "size": [w, h, d],
## "seed", "at": [x, y, z], "dir": [x, y, z], "ridge": {"a": [..], "b": [..], "where": "ends" | "spread"}}. Returns {"ok", "error", "result": {...}}
static func serve(m: Node, p: Dictionary) -> Dictionary:
	if not Part.available():
		return {"ok": false, "error": Part.why_not()}
	var rec: Dictionary = m.S.part if not m.S.part.is_empty() else Part.make("Part")
	rec = rec.duplicate(true)
	var seed := int(p.get("seed", 1))
	var fl := {}
	if p.has("words"):
		var w := from_words(String(p["words"]), rec, seed)
		if not bool(w["ok"]):
			return {"ok": false, "error": String(w["why"])}
		fl = w["fields"]
	else:
		var kind := String(p.get("kind", ""))
		if not KINDS.has(kind):
			return {"ok": false, "error": "ornament needs words (like 2 chiwen on the ridge ends) or a kind from: " + ", ".join(ORDER)}
		var size := vec(p["size"]) if p.has("size") else default_size(kind)
		var n := clampi(int(p.get("count", 1)), 1, 40)
		var places: Array = []
		var row := {}
		var cnt := n
		if kind == "corner_row":
			row = {"n": n}
			cnt = 1
		if p.has("roof"):   # s237: the ridge (or the corners) of a roof step of the part, from the roof's own parameters; the pieces are seated on it
			var rf := roof_step(rec, p["roof"])
			if rf.is_empty():
				return {"ok": false, "error": "ornament: the part has no roof step called %s (give its name or id, or true for the last one)" % str(p["roof"])}
			var where := String(p.get("where", "ends"))
			if where == "corners":
				var cin := float(p.get("inset", size.x * 0.6))
				var rows: Array = []
				for k in cnt:
					rows.append(PartRoof.corner_points(rf, cin + size.x * 1.0 * float(k)))
				for c in 4:
					for k in cnt:
						var cp: Dictionary = rows[k][c]
						places.append({"at": arr(cp["at"]), "dir": arr(cp["dir"])})
			else:
				var rl := PartRoof.ridge_line(rf)
				if rl.is_empty():
					return {"ok": false, "error": "ornament: that roof has no ridge line (a flat, shed, pyramid or polygon roof): give the places by hand"}
				var ra: Vector3 = rl["a"]
				var rb: Vector3 = rl["b"]
				var rin := float(p.get("inset", size.x * 0.5))
				places = ends_of(ra, rb, rin) if where == "ends" and cnt == 2 else spread_on(ra, rb, cnt, rin)
		elif p.has("ridge"):
			var r: Dictionary = p["ridge"]
			var a := vec(r["a"])
			var b := vec(r["b"])
			var inset := float(r.get("inset", minf(size.x * 0.5, (b - a).length() * 0.25)))
			places = ends_of(a, b, inset) if String(r.get("where", "ends")) == "ends" and cnt == 2 else spread_on(a, b, cnt, inset)
		else:
			var at := vec(p.get("at", [0.0, 0.0, 0.0]))
			var dir := vec(p.get("dir", [1.0, 0.0, 0.0])).normalized()
			for i in cnt:
				places.append({"at": arr(at + dir * size.x * 1.3 * float(i)), "dir": arr(dir)})
		fl = fields(kind, seed, places, size, row)
		if p.has("roof") or bool(p.get("seat", false)):
			fl["seat"] = bool(p.get("seat", true))
	var feat := Part.new_feature(rec, "ornament", fl)
	rec["features"].append(feat)
	var res := Part.replay(rec, -1, {"effects": true})
	var errs: Dictionary = res["errors"]
	if errs.has(String(feat["id"])):
		return {"ok": false, "error": String(errs[String(feat["id"])])}
	m._step_hint = "Add " + String(feat["name"])
	m._push_undo()
	m.S.part = rec
	var bb: AABB = res["aabb"]
	return {"ok": true, "error": "", "result": PartFx.merge_into({"id": feat["id"], "kind": feat["kind"], "bodies": int(res["bodies"]), "volume_mm3": float(res["volume"]) / (MM * MM * MM),
		"box_mm": [bb.size.x / MM, bb.size.y / MM, bb.size.z / MM], "places": (feat["places"] as Array).size()}, res, String(feat["id"]))}
