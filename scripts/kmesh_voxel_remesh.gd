class_name KMeshVoxelRemesh
extends RefCounted
## M1 voxel remesh (plan M1; ROADMAP_400 gap: no general remesh): a closed mesh becomes an even-sized quad mesh at a chosen
## voxel size. Steps: the mesh's signed distance on a voxel grid (AnyGrip.MeshField.build_banded, the grip's own field
## type), then SURFACE NETS on that grid: one vertex per cell the surface crosses (the average of its edge crossings),
## one quad per grid edge the surface crosses. No table, so no hole cases to get wrong; the quads are the output faces.
## Pure: no nodes. remesh(m, voxel) -> {"ok": true, "mesh": KMesh, "voxels": int} or {"ok": false, "why": String}.
## The input must be closed (no boundary edges): an open mesh has no inside to fill, so it is refused, with the words to say why.

const MAX_VOXELS := 8000000   # the grid's cell count cap (memory): a finer remesh of a big mesh is refused, with the size to use

## the corner offsets of a cell, and its 12 edges as corner pairs
const CORNERS := [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(1, 1, 0),
	Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(0, 1, 1), Vector3i(1, 1, 1)]
const EDGES := [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]


## the remeshed copy of m at `voxel` metres (m itself is not changed)
static func remesh(m: KMesh, voxel: float) -> Dictionary:
	if m == null or m.faces.is_empty() or m.verts.is_empty():
		return {"ok": false, "why": "there is no mesh to remesh"}
	if voxel <= 0.0:
		return {"ok": false, "why": "the voxel size must be more than 0 m"}
	if not m.is_closed():
		return {"ok": false, "why": "the mesh has a hole: close it first (Repair), then remesh"}
	var tris := PackedVector3Array()
	for f in m.faces:
		var fa := f as PackedInt32Array
		for k in range(1, fa.size() - 1):
			tris.append(m.verts[fa[0]])
			tris.append(m.verts[fa[k]])
			tris.append(m.verts[fa[k + 1]])
	var lo := m.verts[0]
	var hi := m.verts[0]
	for p in m.verts:
		lo = lo.min(p)
		hi = hi.max(p)
	var cells := ((hi - lo) / voxel + Vector3.ONE * 6.0)
	var count := (cells.x + 1.0) * (cells.y + 1.0) * (cells.z + 1.0)
	if count > MAX_VOXELS:
		var need := maxf((hi - lo).x, maxf((hi - lo).y, (hi - lo).z)) / pow(float(MAX_VOXELS), 1.0 / 3.0)
		return {"ok": false, "why": "too fine for this mesh: use a voxel of %.1f mm or bigger" % (need * 1000.0)}
	var field := AnyGrip.MeshField.build_banded(tris, voxel)
	var verts := PackedVector3Array()
	var faces: Array = []
	surface_nets(field, verts, faces)
	var out := KMesh.new().from_arrays(verts, faces)
	return {"ok": true, "mesh": out, "voxels": field.nx * field.ny * field.nz, "cell": field.h}


## the unit normal of the field at p (its gradient by central differences; zero where the field is flat)
static func _normal(field: AnyGrip.MeshField, p: Vector3) -> Vector3:
	var e := field.h * 0.25
	var g := Vector3(
		field.sd(p + Vector3(e, 0, 0)) - field.sd(p - Vector3(e, 0, 0)),
		field.sd(p + Vector3(0, e, 0)) - field.sd(p - Vector3(0, e, 0)),
		field.sd(p + Vector3(0, 0, e)) - field.sd(p - Vector3(0, 0, e)))
	return g.normalized() if g.length() > 1e-9 else Vector3.ZERO


## dual contouring's QEF vertex: the point that best lies on every crossing's tangent plane (the least squares of
## n . (x - p) = 0), pulled a little toward the crossings' mean and kept inside the cell. A sharp edge or corner of the
## surface then stays sharp; averaging the crossings alone cuts it (surface nets lose volume ~ h on a box)
static func _qef_vertex(pts: Array, mass: Vector3, lo: Vector3, h: float) -> Vector3:
	var ata := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	var atb := Vector3.ZERO
	const LAMBDA := 0.1
	for pn in pts:
		var n: Vector3 = pn[1]
		var p: Vector3 = pn[0]
		if n == Vector3.ZERO:
			continue
		ata.x += Vector3(n.x * n.x, n.x * n.y, n.x * n.z)
		ata.y += Vector3(n.y * n.x, n.y * n.y, n.y * n.z)
		ata.z += Vector3(n.z * n.x, n.z * n.y, n.z * n.z)
		atb += n * n.dot(p)
	ata.x.x += LAMBDA
	ata.y.y += LAMBDA
	ata.z.z += LAMBDA
	atb += mass * LAMBDA
	var x := mass
	if absf(ata.determinant()) > 1e-12:
		x = ata.inverse() * atb
	return x.clamp(lo, lo + Vector3.ONE * h)


## the quads of the zero set of field's distance grid: appends to verts and faces (faces of 4 vert indices, outward)
static func surface_nets(field: AnyGrip.MeshField, verts: PackedVector3Array, faces: Array) -> void:
	var nx := field.nx
	var ny := field.ny
	var nz := field.nz
	var cell_vert := PackedInt32Array()
	cell_vert.resize(maxi(nx - 1, 0) * maxi(ny - 1, 0) * maxi(nz - 1, 0))
	cell_vert.fill(-1)
	var sx := nx - 1
	var sy := ny - 1
	for k in range(nz - 1):
		for j in range(ny - 1):
			for i in range(nx - 1):
				var val := PackedFloat32Array()
				val.resize(8)
				var inside := 0
				for c in 8:
					var o: Vector3i = CORNERS[c]
					val[c] = field.d[(i + o.x) + nx * ((j + o.y) + ny * (k + o.z))]
					if val[c] < 0.0:
						inside += 1
				if inside == 0 or inside == 8:
					continue
				var pts := []   # the crossings (world) and their normals: the QEF's planes
				var mass := Vector3.ZERO
				for e in EDGES:
					var a: int = e[0]
					var b: int = e[1]
					if (val[a] < 0.0) == (val[b] < 0.0):
						continue
					var t := val[a] / (val[a] - val[b])
					var cc := Vector3(i, j, k) + Vector3(CORNERS[a]).lerp(Vector3(CORNERS[b]), t)
					var pw := field.gmin + cc * field.h
					pts.append([pw, _normal(field, pw)])
					mass += pw
				mass /= float(pts.size())
				var at := _qef_vertex(pts, mass, field.gmin + Vector3(i, j, k) * field.h, field.h)
				cell_vert[i + sx * (j + sy * k)] = verts.size()
				verts.append(at)
	# every grid edge the surface crosses makes one quad from the four cells that share it
	for k in range(nz):
		for j in range(ny):
			for i in range(nx):
				var here := i + nx * (j + ny * k)
				for axis in 3:
					var step := Vector3i.ZERO
					step[axis] = 1
					var ni: int = i + step.x
					var nj: int = j + step.y
					var nk: int = k + step.z
					if ni >= nx or nj >= ny or nk >= nz:
						continue
					var there := ni + nx * (nj + ny * nk)
					if (field.d[here] < 0.0) == (field.d[there] < 0.0):
						continue
					# the four cells around this edge, in order about the axis; the two cells along the other axes
					var u := (axis + 1) % 3
					var w := (axis + 2) % 3
					var ring := []
					for q in [[0, 0], [1, 0], [1, 1], [0, 1]]:
						var cc := Vector3i(i, j, k)   # the cell whose low corner is this grid point, shifted back on the other two axes
						cc[u] += q[0] - 1
						cc[w] += q[1] - 1
						if cc.x < 0 or cc.y < 0 or cc.z < 0 or cc.x >= sx or cc.y >= sy or cc.z >= nz - 1:
							ring = []
							break
						ring.append(cell_vert[cc.x + sx * (cc.y + sy * cc.z)])
					if ring.is_empty() or ring.has(-1):
						continue
					var q_ids := PackedInt32Array(ring)
					var want := Vector3.ZERO
					want[axis] = 1.0 if field.d[here] < 0.0 else -1.0   # outward: the field grows from inside to outside
					var nrm := (verts[q_ids[2]] - verts[q_ids[0]]).cross(verts[q_ids[3]] - verts[q_ids[1]])   # the quad's area normal (its diagonals)
					if nrm.dot(want) < 0.0:
						q_ids = PackedInt32Array([q_ids[0], q_ids[3], q_ids[2], q_ids[1]])
					faces.append(q_ids)


## the sculpt's version: m itself becomes the remeshed mesh (the view and the undo keep their reference), one undo step.
## The new verts have no mask or other channel, so the mask channel starts again (KMeshMask.ensure), as on a fresh mesh
static func apply(m: KMesh, voxel: float, undo: KMeshUndo) -> Dictionary:
	var r := remesh(m, voxel)
	if not r["ok"]:
		return r
	var out: KMesh = r["mesh"]
	undo.begin(m)
	m.attrs = {}
	m.from_arrays(out.verts, out.faces)
	KMeshMask.ensure(m)
	undo.commit("remesh")
	return r
