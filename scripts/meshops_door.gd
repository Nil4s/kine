class_name MeshOpsDoor
extends RefCounted
## n03: the door to KineMeshOpsNative (decimate, voxel remesh, STL / 3MF / OBJ packing). on() is false with no DLL or with the
## environment variable KINE_NO_NATIVE=1 (forces the GDScript paths, for the comparison test). door() is the script to call.

static var _door = null
static var _tried := false


static func on() -> bool:
	if OS.get_environment("KINE_NO_NATIVE") == "1":
		return false
	if not _tried:
		_tried = true
		if NativeExt.ensure("kine_native", "KineMeshOpsNative"):
			_door = load("res://scripts/kmesh_meshops_native.gd")
	return _door != null


static func door():
	return _door
