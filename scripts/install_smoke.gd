## install_smoke.gd - L16: `Kine.console.exe --headless -- --install-smoke` (the clean-machine install test's launch). Writes nothing.
## Checks the data an install must hold and that both native libraries loaded; exit 0 = OK, 3 = FAIL. --install-need=<path> adds a
## required file (the test plants a missing one).
class_name InstallSmoke
extends RefCounted


static func wanted(args: PackedStringArray) -> bool:
	return args.has("--install-smoke")


static func run(args: PackedStringArray) -> int:
	var need := ["res://data/skeleton.json", "res://data/body_limits.json", "res://main.tscn", "res://assets/mannequin.glb"]
	for a in args:
		if a.begins_with("--install-need="):
			need.append(a.substr(15))
	var bad := []
	for p in need:
		if not ResourceLoader.exists(p) and not FileAccess.file_exists(p):
			bad.append("missing " + p)
	for c in [["kine_cad", "KineCAD"], ["kine_native", "KineSkinNative"]]:
		if not NativeExt.ensure(c[0], c[1]):   # the app's own loader, so an installed build's flat-beside-the-exe lookup is the thing tested
			bad.append("native class not loaded: " + c[1])
	if bad.is_empty():
		print("INSTALL_SMOKE OK version=%s" % str(ProjectSettings.get_setting("application/config/version", "")))
		return 0
	print("INSTALL_SMOKE FAIL " + "; ".join(bad))
	return 3
