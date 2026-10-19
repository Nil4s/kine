## BATCH EXPORT (ROADMAP 80): many scene files, one format, one folder. Each file is read into a FRESH Scene and a fresh
## Body, set the way main's _load_scene sets them (S.apply(B, 0.0)), so the open scene is never read or changed. The writers
## are the ones the Export dialog runs (GltfExport, BvhExport, UsdExport, FbxExport), so each file's bytes are the bytes of
## exporting that scene alone. A scene that cannot be exported is named in the summary with its next step; the others still go.
## The dialog (scripts/batch_dialog.gd) is the Batch... button of the Export dialog.
class_name BatchExport
extends RefCounted

const FORMATS := [
	{"id": "glb", "name": "glTF 2.0 (.glb)", "ext": ".glb"},
	{"id": "bvh", "name": "BVH (.bvh): motion capture", "ext": ".bvh"},
	{"id": "usda", "name": "USD (.usda): UsdSkel", "ext": ".usda"},
	{"id": "fbx", "name": "FBX 7.4 (.fbx), centimetres", "ext": ".fbx"},
]
const DEFAULT_DIR := "res://scenes/_wip/batch"


static func formats() -> Array:
	return FORMATS


static func format_of(id: String) -> Dictionary:
	for f in FORMATS:
		if String((f as Dictionary)["id"]) == id:
			return f
	return {}


## "" when a batch may write into dir; else the sentence to show (with its next step). A batch writes into
## scenes/_wip (any folder under it), user:// or a folder outside the project; never into scenes/ itself.
static func check_dir(dir: String) -> String:
	var d := dir.strip_edges().replace("\\", "/").trim_suffix("/")
	if d == "":
		return "NOT NOW: type an output folder first (the default is res://scenes/_wip/batch)"
	if d.split("/").has(".."):
		return "NOT NOW: the output folder may not contain '..': give the folder's full path"
	var full := ""
	if d.begins_with("res://") or d.begins_with("user://"):
		full = ProjectSettings.globalize_path(d).replace("\\", "/").trim_suffix("/")
	elif d.begins_with("/") or d.substr(1, 1) == ":":
		full = d
	else:
		return "NOT NOW: give the output folder as res://scenes/_wip/<name>, user://<name> or a full path"
	var root := ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/").to_lower()
	var low := full.to_lower()
	var scenes := root + "/scenes"
	if low == scenes or low.begins_with(scenes + "/"):
		if not (low == scenes + "/_wip" or low.begins_with(scenes + "/_wip/")):
			return "NOT NOW: a batch never writes into scenes/ except scenes/_wip: use res://scenes/_wip/batch or a folder outside the project"
	return ""


## one scene file -> one file in dir (named as the writers name it: <scene name>.<ext>). taken: names already written in
## this batch (two scenes with one name would overwrite each other, so the second is refused). Returns
## {ok, scene, file, msg}; msg is the line for the summary (named, with a next step, when not ok).
static func export_one(scene_path: String, fmt: String, dir: String, taken: Dictionary = {}) -> Dictionary:
	var r := {"ok": false, "scene": scene_path.get_file(), "file": "", "msg": ""}
	var f := format_of(fmt)
	if f.is_empty():
		r["msg"] = "NOT NOW: %s is not a format of the batch (glb, bvh, usda, fbx)" % fmt
		return r
	if not FileAccess.file_exists(scene_path):
		r["msg"] = "NOT DONE: %s is not there (moved or deleted): tick it again from the list" % r["scene"]
		return r
	var txt := FileAccess.get_file_as_string(scene_path)
	var probe: Variant = JSON.parse_string(txt) if txt != "" else null
	if not (probe is Dictionary) or not (probe as Dictionary).has("cards"):
		r["msg"] = "NOT DONE: %s is not a scene file (empty, not JSON, or no cards): open it in the app and Save scene, or leave it out" % r["scene"]
		return r
	var d: Dictionary = probe
	if d.has("actors") and not (d["actors"] as Array).is_empty():
		r["msg"] = "NOT DONE: %s has %d fighters: a batch writes one scene per file. Open it and use Export... for all of them" % [r["scene"], (d["actors"] as Array).size() + 1]
		return r
	var S := Scene.new()
	S.from_dict(d)
	if S.cards.size() < 2:
		r["msg"] = "NOT DONE: %s has %d card%s; an animation needs at least 2 (a move): add the cards in the app, then tick it again" % [r["scene"], S.cards.size(), "" if S.cards.size() == 1 else "s"]
		return r
	var nm := S.name if S.name != "" else "scene"
	if nm.validate_filename() != nm:
		r["msg"] = "NOT DONE: the scene's name '%s' has a character a file name cannot take: open it and Save scene under a plain name" % nm
		return r
	var target := "%s/%s%s" % [dir.strip_edges().replace("\\", "/").trim_suffix("/"), nm, String(f["ext"])]
	if taken.has(target):
		r["msg"] = "NOT DONE: another scene in this batch is also named %s: open one and Save scene under a new name" % nm
		return r
	taken[target] = true
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")   # the rig, as main's own body has it
	S.apply(B, 0.0)   # what main's _load_scene does to the body; the writers sample from here
	var err: int = FAILED
	match fmt:
		"glb":
			err = GltfExport.write(S, B, target)
		"bvh":
			err = (BvhExport.write(S, B, target) as Array)[0]
		"usda":
			err = (UsdExport.write(S, B, target) as Array)[0]
		"fbx":
			err = int((FbxExport.write(S, B, target, false) as Dictionary)["err"])
	if err != OK:
		r["msg"] = "NOT DONE: %s could not be written (%s): check the folder can be written and no program has the file open" % [target.get_file(), error_string(err)]
		return r
	r["ok"] = true
	r["file"] = target
	r["msg"] = "%s: exported as %s" % [r["scene"], target.get_file()]
	return r


## every scene in the list, one after another. progress (optional) is called as progress(i, n, file name) before each one.
## Returns {done, files, failed (the not-ok results), lines (the summary, one line each)}. A bad folder stops the batch
## before anything is written, with its sentence in lines.
static func run(scene_paths: Array, fmt: String, dir: String, progress := Callable()) -> Dictionary:
	var bad := check_dir(dir)
	if bad != "":
		return {"done": 0, "files": [], "failed": [], "lines": [bad]}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir.strip_edges().replace("\\", "/").trim_suffix("/")))
	var files := []
	var failed := []
	var taken := {}
	for i in scene_paths.size():
		var p := String(scene_paths[i])
		if progress.is_valid():
			progress.call(i, scene_paths.size(), p.get_file())
		var r := export_one(p, fmt, dir, taken)
		if r["ok"]:
			files.append(r["file"])
		else:
			failed.append(r)
	return {"done": files.size(), "files": files, "failed": failed, "lines": summary_lines(files.size(), failed)}


## the summary: "n done", then one line per failure with its named message
static func summary_lines(done: int, failed: Array) -> Array:
	var out := ["batch: %d done, %d failed" % [done, failed.size()]]
	for r in failed:
		out.append("  - " + String((r as Dictionary)["msg"]))
	return out
