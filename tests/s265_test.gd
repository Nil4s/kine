extends SceneTree
## S265 one lane of small Part fixes from the GPU build (NOTES.md gaps). A section per item, in commit order: 271, 268, 266, 270, 267, 265, 272.
var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func boot() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1


func status() -> String:
	return String(m.ui_status.text) if m.ui_status != null else ""


## 271 BAR: a scripted Save over a shipped scene says "not saved", leaves the file and scene_path alone. CONTROL: a zz_ name saves and says saved.
func s271() -> void:
	var shipped := UserPaths.w("res://scenes/bo_spin.json")
	ok(FileAccess.file_exists(shipped), "271 fixture: a shipped scene exists")
	var t0 := FileAccess.get_modified_time(shipped)
	var sp0: String = m.scene_path
	m._save_scene_now("bo_spin")
	ok(status().begins_with("not saved"), "271 BAR the status line says it skipped: '%s'" % status().substr(0, 60))
	ok(m.scene_path == sp0 and FileAccess.get_modified_time(shipped) == t0, "271 BAR scene_path and the file are as they were")
	m._save_scene_now("zz_s265_ctl")
	var made := UserPaths.w("res://scenes/zz_s265_ctl.json")
	ok(FileAccess.file_exists(made) and m.scene_path == made and not status().begins_with("not saved"), "271 CONTROL a zz_ name writes, sets scene_path, says '%s'" % status().substr(0, 40))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(made))


func _init() -> void:
	if not Part.available():
		print("FAIL: no KineCAD DLL")
		quit(1)
		return
	await boot()
	await s271()
	print("s265: %d fail" % fails)
	quit(1 if fails > 0 else 0)
