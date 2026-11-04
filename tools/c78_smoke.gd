extends Node
## C78 smoke test, started by main.gd when the command line has the user arg --c78-smoke:
##   Kine.console.exe --headless -- --c78-smoke          (an installed Kine; also works from source)
## Opens Part (BUILD), builds a 2x1x1 box through KineCAD (OpenCASCADE), meshes it, checks the volume, quits 0.
## Any failure prints "C78_SMOKE_FAIL <why>" and quits 1. Success prints "C78_SMOKE_OK ms=<ms since engine start>".
const KCad := preload("res://scripts/kcad.gd")


func _fail(why: String) -> void:
	print("C78_SMOKE_FAIL ", why)
	get_tree().quit(1)


func run(m: Node) -> void:
	print("C78_SMOKE_START ms=", Time.get_ticks_msec())
	for i in 6:
		await get_tree().process_frame
	m.tour_step = -1
	var pu = m.bld.part
	pu.set_on(true)
	for i in 4:
		await get_tree().process_frame
	if not pu.on:
		_fail("Part did not open")
		return
	if not KCad.available():
		_fail("KineCAD not available: " + KCad.last_error())
		return
	var id := KCad.box(2.0, 1.0, 1.0)
	if id == 0:
		_fail("box failed: " + KCad.last_error())
		return
	var vol := KCad.volume(id)
	if absf(vol - 2.0) > 1e-6:
		_fail("box volume %f" % vol)
		return
	var mesh := KCad.tessellate(id, 0.01, 0.3)
	if mesh == null or mesh.get_surface_count() == 0:
		_fail("tessellate gave no mesh")
		return
	var tris := 0
	for s in mesh.get_surface_count():
		tris += mesh.surface_get_array_index_len(s) / 3
	if tris < 12:
		_fail("mesh has %d triangles" % tris)
		return
	print("C78_GATE=", VideoAddon.gate("tracking a video"))
	print("C78_SMOKE_OK ms=%d tris=%d vol=%f" % [Time.get_ticks_msec(), tris, vol])
	get_tree().quit(0)
