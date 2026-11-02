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


func three(cut: Dictionary) -> Dictionary:
	var rec := Part.make("S268")
	for k in 3:
		Part.prim(rec, "box", {"x": 300.0 * k, "y": 0.0, "z": 0.0, "w": 200.0, "h": 100.0, "d": 100.0, "name": "B%d" % k})
	var c := {"op": "cut", "name": "Notch"}
	c.merge(cut)
	var cid := Part.prim(rec, "box", c)
	var r := Part.replay(rec)
	r["cid"] = cid
	return r


## 268 BAR: a cut with no into / targets cuts only the bodies it overlaps (body 1 of 3), the others keep their volume, and the words say which.
## CONTROL: a tool through all three cuts all three (so "unchanged" is not vacuous); a tool through none says it cut nothing.
func s268() -> void:
	var full := 200.0 * 100.0 * 100.0 * 1e-9
	var r := three({"x": 150.0, "y": 20.0, "z": 20.0, "w": 100.0, "h": 40.0, "d": 40.0})   # in body 0 and not 1 (x 150..250 vs body 1 from 300)
	var v: Array = r["volumes"]
	ok(int(r["bodies"]) == 3 and (r["errors"] as Dictionary).is_empty(), "268 fixture: 3 bodies, no errors %s" % str(r["errors"]))
	ok(v[0] < full * 0.99 and absf(v[1] - full) < full * 1e-6 and absf(v[2] - full) < full * 1e-6, "268 BAR body 1 cut (%s of %s), bodies 2 and 3 untouched (%s, %s)" % [v[0], full, v[1], v[2]])
	var w := String((r["warnings"] as Dictionary).get(r["cid"], ""))
	ok(w == "cut 1 body: Body1", "268 BAR the words: '%s'" % w)
	var ra := three({"x": -50.0, "y": 20.0, "z": 20.0, "w": 900.0, "h": 40.0, "d": 40.0})
	var va: Array = ra["volumes"]
	ok(va[0] < full * 0.99 and va[1] < full * 0.99 and va[2] < full * 0.99 and String((ra["warnings"] as Dictionary).get(ra["cid"], "")) == "cut 3 bodies: Body1, Body2, Body3", "268 CONTROL a tool through all three cuts all three: '%s'" % String((ra["warnings"] as Dictionary).get(ra["cid"], "")))
	var rn := three({"x": 5000.0, "y": 20.0, "z": 20.0, "w": 100.0, "h": 40.0, "d": 40.0})
	ok(String((rn["warnings"] as Dictionary).get(rn["cid"], "")).contains("nothing was cut") and absf(rn["volumes"][0] - full) < full * 1e-6, "268 CONTROL a tool in empty space says it cut nothing")
	var rt := three({"x": -50.0, "y": 20.0, "z": 20.0, "w": 900.0, "h": 40.0, "d": 40.0, "targets": [2]})
	ok(absf(rt["volumes"][0] - full) < full * 1e-6 and rt["volumes"][2] < full * 0.99, "268 CONTROL targets still names the only body: body 3 cut, body 1 not")


func _init() -> void:
	if not Part.available():
		print("FAIL: no KineCAD DLL")
		quit(1)
		return
	await boot()
	await s271()
	s268()
	print("s265: %d fail" % fails)
	quit(1 if fails > 0 else 0)
