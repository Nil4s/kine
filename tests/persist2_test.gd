## godot --path . -s tests/persist2_test.gd     (w4 autosave2: what a crash must not lose; needs a window: main.tscn)
## The fighter's own work that the scene file, the autosave and the journal did not hold, checked against the code as it is.
## Bars, stated before the run:
##   (a) ARMOUR: a plate made on the fighter (ArmourFromBody.make) is in the scene file under "armour" and validates against
##       docs/scene.schema.json; saved then reopened: the plate's verts, faces and every attribute are the same bytes, the
##       same label and node name. The autosave, then a crash (the plates gone) and a restore: the same bytes again.
##   (b) CUSTOM BODY, saved as a file: an edited body (one vertex moved, applied) saved (before_save writes the .kbody) and
##       the scene reopened: the fighter's body has the same vertex, face and weight bytes. An edit after that, autosaved
##       (the inline form: no file yet), then restored from the autosave alone: the same bytes; saved then, it names a new
##       .kbody that reopens to the same bytes.
##   (c) OLD FILES: a scene file without "armour" or "body_mesh" still opens with the same cards.
##   (d) UNSAVED: a plate made counts as unsaved work (so the autosave writes it); a freshly opened scene is saved.
##   Writes only under user:// (bodies, scenes, autosave): BodyFile.dir and the scene paths are the test's own; no res://bodies.
##   CURVES are not checked here: a curve is the model preview's transient object (kmesh_curves_ui.gd drops it when the preview
##   closes), not scene data; the mesh it converts into is the applied body, which (b) covers.
extends SceneTree

var fails := 0
var m: Node
var mannequin_verts := PackedByteArray()
const ROOT := "user://persist2"
const BODIES := "user://persist2/bodies"
const ARM := "user://persist2/armour.json"
const ARM_OLD := "user://persist2/armour_old.json"
const BODY := "user://persist2/body.json"
const BODY_OLD := "user://persist2/body_old.json"
const INL := "user://persist2/inline.json"
const AS := "user://persist2/autosave.json"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func _rm(p: String) -> void:
	for f in DirAccess.get_files_at(p):
		DirAccess.remove_absolute(p.path_join(f))
	for d in DirAccess.get_directories_at(p):
		_rm(p.path_join(d))
	DirAccess.remove_absolute(p)


func wipe() -> void:
	var g := ProjectSettings.globalize_path(ROOT)
	if DirAccess.dir_exists_absolute(g):
		_rm(g)


## a mesh as bytes: positions, faces and every attribute (by name), so two meshes compare bit for bit
func kmesh_sig(k: KMesh) -> Array:
	var names := k.list_attrs()
	names.sort()
	var out := [var_to_bytes(k.verts), var_to_bytes(k.faces), names.size()]
	for nm in names:
		out.append(nm)
		out.append(var_to_bytes(k.attr_data(nm)))
	return out


func plates_sig() -> Array:
	var out := []
	for mi in ArmourFromBody.parts(m):
		var n := mi as Node
		out.append([String(n.get_meta("armour_label", "")), String(n.name), kmesh_sig(n.get_meta("armour_kmesh"))])
	return out


func is_mannequin() -> bool:
	return var_to_bytes(BaseBody.read(m).verts) == mannequin_verts


func body_sig() -> Array:
	return kmesh_sig(BaseBody.read(m))


func read_json(p: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(p))


## a file with the given keys taken out (an old file: written before the key existed)
func strip_keys(src: String, dst: String, keys: Array) -> void:
	var d := read_json(src)
	for k in keys:
		d.erase(k)
	m._write(dst, d)


## one vertex moved 1 cm and applied (no undo step: the test's own edit)
func edit_body(which: int) -> void:
	var k := BaseBody.read(m)
	k.verts[which] = k.verts[which] + Vector3(0.01, 0.0, 0.0)
	var r := BaseBody.apply(m, k, false)
	ok(r["ok"], "an edit of the body is applied (%s)" % str(r.get("error", "")))


func _init() -> void:
	wipe()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BODIES))
	BodyFile.dir = BODIES
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	m.autosave = AS
	m._load_scene("res://scenes/combo3.json")
	await idle(2)
	var cards: int = m._hero_scene().cards.size()
	# the mannequin is compared by its positions: restoring gen 0 re-reads the skin weights (painted ones canonical), so the
	# weights of the mannequin are not the same bytes as the start; the positions are
	mannequin_verts = var_to_bytes(BaseBody.read(m).verts)

	# ---- (a) ARMOUR
	ok(plates_sig().is_empty(), "start: no armour plates on the fighter")
	var r: Dictionary = ArmourFromBody.make(m, "forearm_extensors_r, forearm_flexors_r", {})
	ok(r["ok"], "a plate is made on the fighter (%s)" % str(r.get("said", r.get("error", ""))))
	var want_plates := plates_sig()
	ok(want_plates.size() == 1, "one plate on the fighter (%d)" % want_plates.size())
	# the autosave of the unsaved plate (it is unsaved work: the autosave writes it)
	m._as_last = ""
	ok(m.autosave_now(), "AUTOSAVE: an unsaved plate is written (the plate is unsaved work)")
	var a := read_json(AS)
	ok((a.get("scene", {}) as Dictionary).get("armour", []).size() == 1, "the autosave holds the plate")
	m._write(ARM, m._scene_dict())
	var v := Validate.file(ARM)
	ok(v.is_empty(), "the scene with a plate validates against docs/scene.schema.json (%s)" % str(v))
	ok((read_json(ARM).get("armour", []) as Array).size() == 1, "the scene file holds the plate under \"armour\"")
	ArmourFromBody.from_scene(m, {})
	ok(plates_sig().is_empty(), "the plates are taken off (the reopen must put them back)")
	m._load_scene(ARM)
	await idle(2)
	ok(plates_sig() == want_plates, "SAVE / REOPEN: the plate is back, same label, node name and bytes (verts, faces, attributes)")
	ok(m._hero_scene().cards.size() == cards, "the reopened scene has its %d cards" % cards)

	# the crash: the fighter starts again without the plate, and the autosave brings it back
	ArmourFromBody.from_scene(m, {})
	ok(plates_sig().is_empty(), "CRASH: no plate on the fighter")
	m._restore_work({"scene": a["scene"], "path": ""})
	await idle(2)
	ok(plates_sig() == want_plates, "AUTOSAVE / RESTORE: the plate is back, same bytes")

	# old file without the key
	strip_keys(ARM, ARM_OLD, ["armour"])
	m._load_scene(ARM_OLD)
	await idle(2)
	ok(plates_sig().is_empty() and m._hero_scene().cards.size() == cards, "OLD FILE: a scene without \"armour\" opens (%d cards, no plate)" % cards)

	# ---- (b) CUSTOM BODY, saved as a file
	m._load_scene("res://scenes/combo3.json")
	await idle(2)
	edit_body(0)
	var want_body := body_sig()
	ok(not is_mannequin(), "the edited body differs from the mannequin")
	BodyFile.before_save(m, "persist2")
	var f1: String = BodyFile.scene_key(m).get("file", "")
	ok(f1 != "" and FileAccess.file_exists(f1), "SAVE: the applied body is written as a .kbody under user:// (%s)" % f1.get_file())
	m._write(BODY, m._scene_dict())
	v = Validate.file(BODY)
	ok(v.is_empty(), "the scene with the body validates against docs/scene.schema.json (%s)" % str(v))
	ok(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://bodies")) or DirAccess.get_files_at("res://bodies").is_empty(), "no body file was written to res://bodies")
	BaseBody.restore_gen(m, 0)
	ok(is_mannequin(), "the mannequin is back on the fighter before the reopen")
	m._load_scene(BODY)
	await idle(2)
	ok(body_sig() == want_body, "SAVE / REOPEN: the body's verts, faces and weights are the same bytes")

	# an edit, autosaved (no file yet: the inline form), then restored from the autosave alone
	edit_body(1)
	var want_body2 := body_sig()
	m._as_last = ""
	ok(m.autosave_now(), "AUTOSAVE: the edited body is unsaved work and is written")
	a = read_json(AS)
	ok(((a.get("scene", {}) as Dictionary).get("body_mesh", {}) as Dictionary).has("kbody"), "the autosave holds the body itself (no file yet)")
	BaseBody.restore_gen(m, 0)   # the crash: the mannequin on the fighter
	ok(is_mannequin(), "CRASH: the mannequin is on the fighter")
	m._restore_work({"scene": a["scene"], "path": ""})
	await idle(2)
	ok(body_sig() == want_body2, "AUTOSAVE / RESTORE: the body's bytes are back, from the autosave alone")

	# the restored body, saved: a new .kbody, and the scene reopens to it
	BodyFile.before_save(m, "persist2_inline")
	var f2: String = BodyFile.scene_key(m).get("file", "")
	ok(f2 != "" and f2 != f1 and FileAccess.file_exists(f2), "SAVE of the restored body: a new .kbody (%s)" % f2.get_file())
	m._write(INL, m._scene_dict())
	BaseBody.restore_gen(m, 0)
	m._load_scene(INL)
	await idle(2)
	ok(body_sig() == want_body2, "SAVE / REOPEN of the restored body: the same bytes")

	# old file without the body key still opens
	strip_keys(BODY, BODY_OLD, ["body_mesh"])
	m._load_scene(BODY_OLD)
	await idle(2)
	ok(m._hero_scene().cards.size() == cards, "OLD FILE: a scene without \"body_mesh\" opens (%d cards)" % cards)

	# ---- (d) unsaved work
	m._load_scene("res://scenes/combo3.json")
	await idle(2)
	ok(not m._unsaved(), "a freshly opened scene is saved")
	ArmourFromBody.make(m, "deltoid_l", {})
	ok(m._unsaved(), "a plate made counts as unsaved work")

	wipe()
	print("persist2: %d failed" % fails)
	quit(1 if fails > 0 else 0)
