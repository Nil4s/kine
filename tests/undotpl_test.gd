## godot --path . -s tests/undotpl_test.gd     (L24; needs a window: the real poser UI is built)
## NEW FROM TEMPLATE is ONE undo step, for EVERY template (Templates.NAMES). It replaces the open scene, so it used to push
## no step (only walk / run / jump / punch / sword swing hid that, in undo_audit's SKIP list; sit_down / wave / fall were
## the first to be audited and failed "NOT marked edits but CHANGED the scene").
##   UNDO   after the template, one Ctrl+Z puts the scene that was open back, byte for byte (body + scene fingerprint, the path)
##   REDO   one Ctrl+Y brings the template scene back, byte for byte
##   ONE    the template pushed exactly one undo step, and the command is marked as an edit in the registry
## CONTROL (planted): the same template with its undo step taken out (the step popped, as if the push was never made) FAILS
## the undo, the redo and the one-step bars. A bar that cannot fail proves nothing.
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## the body and the scene as it would be saved (as undo_audit's fp: not S.to_dict, which poses the body)
func fp() -> String:
	var S: Scene = m.S
	var sd := {"cards": S.cards, "name": S.name, "natural": S.natural, "spline": S.spline, "on_floor": S.on_floor,
		"floor_body": S.floor_body, "pin": S.pin, "fps": S.fps, "moving_holds": S.moving_holds,
		"part_keys": var_to_str(S.part_keys), "markers": S.markers, "notes": S.notes,
		"props": JSON.stringify(S.props.map(func(q): return Props.to_dict(q))), "shots": var_to_str(S.shots),
		"clips": var_to_str(S.clips), "body": var_to_str(S.body), "p0": var_to_str(m.B.p0), "path": m.scene_path}
	return JSON.stringify(m.B.to_dict()) + "|" + JSON.stringify(sd)


func fresh() -> void:
	m.playing = false
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m._card_pick(2)
	m.undo.clear()
	m.redo.clear()
	await process_frame


## one template from a fresh combo3; planted = the undo step is taken out again. Returns the three bar results.
func trial(nm: String, planted: bool) -> Dictionary:
	await fresh()
	var f0 := fp()
	var u0: int = m.undo.size()
	m._template_build_now(nm, Templates.read(nm))
	await process_frame
	await process_frame
	var made: String = m.scene_path
	if planted:
		m.undo.pop_back()   # the template path with its undo push removed
	var f1 := fp()
	var steps: int = m.undo.size() - u0
	var changed := f1 != f0
	m._undo()
	await process_frame
	var back := fp() == f0
	m._redo()
	await process_frame
	var fwd := fp() == f1
	for p in [made]:   # the scene file the template wrote (a work copy in _wip): not left behind
		if p != "" and FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	return {"changed": changed, "steps": steps, "back": back, "fwd": fwd}


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	var marked := {}
	for c in m._commands():
		marked[c["id"]] = c["edits"]
	ok(Templates.NAMES.size() == 8, "the picker lists %d templates" % Templates.NAMES.size())
	# CONTROL first: the planted failure is seen by every bar
	for nm in ["wave", "sit_down"]:
		var r: Dictionary = await trial(nm, true)
		ok(r["changed"], "control %s: the template changes the scene" % nm)
		ok(not r["back"], "control %s: with the undo push removed, the undo bar FAILS (it does not put the scene back)" % nm)
		ok(r["steps"] != 1, "control %s: with the undo push removed, the one-step bar FAILS (%d steps)" % [nm, r["steps"]])
	for nm in Templates.NAMES:
		var r: Dictionary = await trial(nm, false)
		ok(r["changed"], "%-12s the template changed the scene (the bars have something to undo)" % nm)
		ok(r["steps"] == 1, "%-12s ONE undo step (%d)" % [nm, r["steps"]])
		ok(r["back"], "%-12s undo puts the earlier scene back, byte for byte" % nm)
		ok(r["fwd"], "%-12s redo brings the template scene back, byte for byte" % nm)
		var cid: String = "new_from_template_" + nm
		ok(marked.has(cid) and marked[cid] == true, "%-12s the command %s is marked as an edit" % [nm, cid])
	print("UNDOTPL %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
