class_name KMeshNatDoor
extends RefCounted
## L60: the door to KineKMeshNative (KMesh topology, Catmull-Clark subdivide, boolean in C++). on() is false with no DLL or with the
## environment variable KINE_NO_NATIVE=1 (read on every call: the comparison test switches it in-process). door() is the script to call.

static var _door = null
static var _tried := false


static func on() -> bool:
	if OS.get_environment("KINE_NO_NATIVE") == "1":
		return false
	if not _tried:
		_tried = true
		if NativeExt.ensure("kine_native", "KineKMeshNative"):
			_door = load("res://scripts/kmesh_native.gd")
	return _door != null


static func door():
	return _door
