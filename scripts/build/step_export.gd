## STEP EXPORT of a built Part (Friday plan 115: "Export STEP for real CAD users"). The kernel's exact solids (Part.replay keep), fused into one shape
## when the part has several bodies, written by KCad.export_step (Open CASCADE's STEP writer: a real ISO-10303-21 file with MANIFOLD_SOLID_BREP).
## UNITS: the kernel works in metres (Kine's unit) and OCCT's writer labels every number as millimetres. So the file's length unit is re-declared as METRE
## (one text edit in the header: SI_UNIT(.MILLI.,.METRE.) -> SI_UNIT($,.METRE.)): SolidWorks, Fusion, FreeCAD and Onshape then read the part at its true size
## (a 20 mm box is 20 mm), and the kernel's own importer converts to millimetres (KCad.import_step then gives millimetre numbers: 20.0 for that box).
class_name StepExport
extends RefCounted

const KCad := preload("res://scripts/kcad.gd")
const MILLI_UNIT := "SI_UNIT(.MILLI.,.METRE.)"
const METRE_UNIT := "SI_UNIT($,.METRE.)"


## the Export dialog's road: the part record -> dir/<name>.step. Answers {"ok", "path", "why", "bodies", "text": one plain sentence}
static func export_part(rec: Dictionary, dir: String) -> Dictionary:
	if rec.is_empty() or not Part.available():
		var w := "Nothing to export: " + ("make a part first" if Part.available() else Part.why_not())
		return {"ok": false, "path": "", "why": w, "bodies": 0, "text": "NOT DONE: " + w}
	var res := Part.replay(rec, -1, {"keep": true})
	var ids: Array = res.get("ids", [])
	if ids.is_empty():
		return {"ok": false, "path": "", "why": "no solid", "bodies": 0, "text": "NOT DONE: Nothing to export: this part has no solid yet"}
	var shape := int(ids[0])
	var extra: Array = []   # fused intermediates to release
	for i in range(1, ids.size()):
		var u := KCad.union(shape, int(ids[i]))
		if u == 0:
			break
		if shape != int(ids[0]):
			extra.append(shape)
		shape = u
	var gdir := ProjectSettings.globalize_path(dir)
	DirAccess.make_dir_recursive_absolute(gdir)
	var path := "%s/%s.step" % [gdir, MeshExport.stem(String(rec.get("name", "Part")))]
	var ok := KCad.export_step(shape, path)
	var err := KCad.last_error()
	if shape != int(ids[0]):
		extra.append(shape)
	for e in extra:
		KCad.release(int(e))
	for id in ids:
		KCad.release(int(id))
	if not ok:
		return {"ok": false, "path": path, "why": err, "bodies": ids.size(), "text": "NOT DONE: the .step could not be written (%s)" % err}
	var s := FileAccess.get_file_as_string(path)
	if s.contains(MILLI_UNIT):
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(s.replace(MILLI_UNIT, METRE_UNIT))
			f.close()
	return {"ok": true, "path": path, "why": "", "bodies": ids.size(), "text": "exported %s: the exact solid (%d piece%s), true size in millimetres, for SolidWorks, Fusion, FreeCAD, Onshape" % [path.get_file(), ids.size(), "" if ids.size() == 1 else "s"]}


## the dialog's checklist for the part on screen
static func check_lines(rec: Dictionary) -> Array:
	if rec.is_empty() or not Part.available():
		return ["WARN  Nothing to export: make a part first"]
	var res := Part.replay(rec, -1, {})
	var n := int(res.get("bodies", 0))
	if n == 0:
		return ["WARN  Nothing to export: this part has no solid yet"]
	return ["OK    exact solid: %d piece%s as true curves and faces (not a mesh), volume %.1f cm3" % [n, "" if n == 1 else "s", float(res.get("volume", 0.0)) * 1.0e6],
		"OK    size: %.1f x %.1f x %.1f mm (the file says metres, so every CAD program reads the true size)" % [(res["aabb"] as AABB).size.x * 1000.0, (res["aabb"] as AABB).size.z * 1000.0, (res["aabb"] as AABB).size.y * 1000.0]]
