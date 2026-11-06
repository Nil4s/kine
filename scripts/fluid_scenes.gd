class_name FluidScenes
extends RefCounted
## CH8: scenes shared by tests/ch8_test.gd and the video tool (tools/ch8_video.gd).

const MM_A := 0.2   # dam break: the column is a wide, 2a tall (Martin & Moyce n^2 = 2)


## Dam break: tank 4a long, column a x 2a x depth 8 cells at the left wall. res = cells across a.
static func dam_break(F: Object, res := 20) -> Dictionary:
	var h := MM_A / res
	var nx := 4 * res + 2
	var ny := 3 * res + 2
	var nz := 10
	F.setup(nx, ny, nz, h, Vector3.ZERO)
	F.set_params(9.81, 0.2, 0.5, 0.005, 300, 1e-7)
	F.add_fluid_box(Vector3(h, h, h), Vector3((res + 1) * h, (2 * res + 1) * h, 9 * h), Vector3.ZERO, 1)
	return {"h": h, "a": MM_A, "x0": h}


## CH8 bar c2 fixture: Martin & Moyce SQUARE column (n^2 = 1: width a, height a), a long dry floor (7 a) so the surge is never stopped by the far wall in the window.
static func dam_square(F: Object, res := 20) -> Dictionary:
	var h := MM_A / res
	var nx := 7 * res + 2
	var ny := 2 * res + 2
	var nz := 10
	F.setup(nx, ny, nz, h, Vector3.ZERO)
	F.set_params(9.81, 0.2, 0.5, 0.005, 300, 1e-7)
	F.add_fluid_box(Vector3(h, h, h), Vector3((res + 1) * h, (res + 1) * h, 9 * h), Vector3.ZERO, 1)
	return {"h": h, "a": MM_A, "x0": h}


## Triangles of the Part "mug" (metres), the mesh moved so the cup axis is at (cx, cz) and the underside sits at y0. Needs the CAD DLL.
static func mug_mesh() -> Dictionary:
	var rec := PartTemplates.make("mug")
	var res := Part.replay(rec)
	var mesh = res["mesh"]
	if mesh == null:
		return {}
	var verts := PackedVector3Array()
	var tris := PackedInt32Array()
	for s in mesh.get_surface_count():
		var arr: Array = mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx = arr[Mesh.ARRAY_INDEX]
		var base := verts.size()
		verts.append_array(vs)
		if idx != null and (idx as PackedInt32Array).size() > 0:
			for i in (idx as PackedInt32Array):
				tris.append(base + i)
		else:
			for i in vs.size():
				tris.append(base + i)
	var bb: AABB = res["aabb"]
	return {"verts": verts, "tris": tris, "aabb": bb}


## Mug scene at cell size h. Returns the numbers the checks need (independent of the voxels: from the mesh box and the template's sizes).
static func mug(F: Object, h := 0.003, voxelise := true) -> Dictionary:
	var m := mug_mesh()
	if m.is_empty():
		return {}
	var bb: AABB = m["aabb"]
	var margin := 0.035
	var size := Vector3(bb.size.x + 2 * margin, bb.size.y + 0.09, bb.size.z + 2 * margin)
	var nx := int(ceil(size.x / h)) + 2
	var ny := int(ceil(size.y / h)) + 2
	var nz := int(ceil(size.z / h)) + 2
	F.setup(nx, ny, nz, h, Vector3.ZERO)
	F.set_params(9.81, 0.2, 0.5, 0.004, 300, 1e-6)
	# the mesh's box centre (x, z) goes to the domain centre; its underside to y = 1.4 h (inside the first free row, which becomes cup wall)
	var shift := Vector3(nx * h * 0.5 - (bb.position.x + bb.size.x * 0.5), 1.4 * h - bb.position.y, nz * h * 0.5 - (bb.position.z + bb.size.z * 0.5))
	var vs: PackedVector3Array = m["verts"]
	for i in vs.size():
		vs[i] += shift
	var added := 0
	if voxelise:
		added = F.add_solid_mesh(vs, m["tris"])
	var axis_x := shift.x   # the template's circle is at the sketch origin: mesh (0, 0) in x and z
	var axis_z := shift.z
	# the axis is the circle centre of the template, not necessarily the box centre (the handle makes the box asymmetric): the body is round, 80 mm
	var R := 0.04
	var H := bb.size.y
	return {"verts": vs, "tris": m["tris"], "h": h, "rim": 1.4 * h + H, "R_out": R, "R_in": R - 0.004, "H": H, "floor": 0.004, "cx": axis_x, "cz": axis_z,
			"solid_added": added, "bb": bb, "shift": shift, "cap": PI * (R - 0.004) * (R - 0.004) * (H - 0.004)}


## L5 (11-05): the same mug scene with the mesh as a CUT solid (signed distance on the corners, open face fractions, particles pushed out by phi)
## instead of conservative voxels. Needs the native class (add_cut_mesh).
static func mug_cut(F: Object, h := 0.003) -> Dictionary:
	var m := mug_mesh()
	if m.is_empty():
		return {}
	var bb: AABB = m["aabb"]
	var margin := 0.035
	var size := Vector3(bb.size.x + 2 * margin, bb.size.y + 0.09, bb.size.z + 2 * margin)
	var nx := int(ceil(size.x / h)) + 2
	var ny := int(ceil(size.y / h)) + 2
	var nz := int(ceil(size.z / h)) + 2
	F.setup(nx, ny, nz, h, Vector3.ZERO)
	F.set_params(9.81, 0.2, 0.5, 0.004, 300, 1e-6)
	var shift := Vector3(nx * h * 0.5 - (bb.position.x + bb.size.x * 0.5), 1.4 * h - bb.position.y, nz * h * 0.5 - (bb.position.z + bb.size.z * 0.5))
	var vs: PackedVector3Array = m["verts"]
	for i in vs.size():
		vs[i] += shift
	var inside: int = F.add_cut_mesh(vs, m["tris"])
	var R := 0.04
	var H := bb.size.y
	return {"verts": vs, "tris": m["tris"], "h": h, "rim": 1.4 * h + H, "R_out": R, "R_in": R - 0.004, "H": H, "floor": 0.004, "cx": shift.x, "cz": shift.z,
			"corners_inside": inside, "bb": bb, "shift": shift, "cap": PI * (R - 0.004) * (R - 0.004) * (H - 0.004)}


## L5: the Martin & Moyce dam break in the named configuration. "ch8" = the CH8 scene (free slip, voxel walls). "mm" = the same tank with the no-slip
## wall condition water really has on glass (wall friction MM_WFR).
const MM_WFR := 1.0


static func dam_break_mm(F: Object, res := 20, cfg := "mm") -> Dictionary:
	var sc := dam_break(F, res)
	if cfg == "mm":
		F.set_wall_friction(MM_WFR)
	return sc
