class_name NativeExt
extends RefCounted
## The optional C++ plug-ins (native/: the sculpt core, the CAD kernel). Their configs are *.gdext, not *.gdextension, on
## purpose: Godot loads every *.gdextension at start-up and prints red "library not found" errors when its DLL was never
## built (the DLLs are not in git). ensure() loads one only when its DLL is really there.

static func ensure(cfg_name: String, cls: String) -> bool:
	if ClassDB.class_exists(cls):
		return true
	var cfg := "res://native/%s.gdext" % cfg_name
	var c := ConfigFile.new()
	if c.load(cfg) != OK:
		return false
	var dll := String(c.get_value("libraries", "windows.release.x86_64", ""))
	if dll == "":
		return false
	if not FileAccess.file_exists(dll):
		# C78: in an installed (exported) build the DLLs sit flat beside Kine.exe, and Godot's loader looks there for a res:// library
		# that is not on disk. Same test, one place down.
		if not (OS.has_feature("template") and FileAccess.file_exists(OS.get_executable_path().get_base_dir().path_join(dll.get_file()))):
			return false
	GDExtensionManager.load_extension(cfg)
	return ClassDB.class_exists(cls)
