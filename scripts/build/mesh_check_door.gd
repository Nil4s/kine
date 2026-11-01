class_name MeshCheckDoor
extends RefCounted
## The one door to KineMeshCheckNative (native/src/kine_meshcheck_native.cpp): the Export dialog's mesh scans (Ready to print?, the closed-edge
## count, signed volume, the size box) and the tip-over feet hull. door() is the native script, or null: no DLL, the env switch
## KINE_NO_NATIVE=1, or MeshCheckDoor.force_gd = true (the comparison test). A null door means every caller runs its GDScript, unchanged.

static var force_gd := false
static var _door = null
static var _tried := false


static func native_on() -> bool:
	return door() != null


static func door():
	if force_gd or OS.get_environment("KINE_NO_NATIVE") == "1":
		return null
	if not _tried:
		_tried = true
		if NativeExt.ensure("kine_native", "KineMeshCheckNative"):
			_door = load("res://scripts/build/mesh_check_native.gd")
	return _door
