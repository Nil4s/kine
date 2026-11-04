extends SceneTree
## C78 smoke test, run by the INSTALLED Kine.exe:  Kine.console.exe --headless -s res://tools/c78_smoke.gd
## Boots main.tscn, opens Part (BUILD), builds a 2x1x1 box through KineCAD (OpenCASCADE), meshes it, checks the volume, quits 0.
## Any failure prints "C78_SMOKE_FAIL <why>" and quits 1. Success prints "C78_SMOKE_OK ms=<boot-to-ok>".
const KCad := preload("res://scripts/kcad.gd")


func _fail(why: String) -> void:
	print("C78_SMOKE_FAIL ", why)
	quit(1)


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 8:
		await process_frame
	m.tour_step = -1
	var pu = m.bld.part
	pu.set_on(true)
	for i in 4:
		await process_frame
	if not pu.on:
		return _fail("Part did not open")
	if not KCad.available():
		return _fail("KineCAD not available: " + KCad.last_error())
	var id := KCad.box(2.0, 1.0, 1.0)
	if id == 0:
		return _fail("box failed: " + KCad.last_error())
	var vol := KCad.volume(id)
	if absf(vol - 2.0) > 1e-6:
		return _fail("box volume %f" % vol)
	var mesh := KCad.tessellate(id, 0.01, 0.3)
	if mesh == null or mesh.get_surface_count() == 0:
		return _fail("tessellate gave no mesh")
	var tris := 0
	for s in mesh.get_surface_count():
		tris += mesh.surface_get_array_index_len(s) / 3
	if tris < 12:
		return _fail("mesh has %d triangles" % tris)
	print("C78_GATE=", VideoAddon.gate("tracking a video"))
	print("C78_SMOKE_OK ms=%d tris=%d vol=%f" % [Time.get_ticks_msec() - t0, tris, vol])
	quit(0)
