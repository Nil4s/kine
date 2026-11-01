extends SceneTree
## godot --path . -s tests/s200_test.gd     (Friday plan 200: GAME EXPORT. A built level + characters as a playable Godot project)
## Walk: Export... (real dialog) > Godot 4 > "Playable game (Godot project folder)" > the OK button. The folder is then READ BACK from disk
## and RUN headless with Godot itself (--script tests/s200_sim.gd: 2 s of "move forward", then a jump). Bars:
##   G1 project.godot exists, names res://main.tscn as the main scene; README.txt says "F5"
##   G2 main.tscn loads with ResourceLoader; it holds N StaticBody3D for the N built parts (+ the one Ground slab), exactly 1 CharacterBody3D
##   G3 each part's StaticBody3D has a CollisionShape3D with a ConcavePolygonShape3D of >= 12 faces (trimesh) and a MeshInstance3D
##   G4 the other character is an idle Node3D (1 NPC), the lights are in (>= 1 DirectionalLight3D), a Camera3D follows the hero
##   G5 RUN with Godot 4.7.2: no SCRIPT ERROR, the hero moved > 1 m in 2 s of forward input
##   G6 the hero did not fall through the floor (y >= -0.05) and a jump rose > 0.5 m
##   G7 the folder is under 50 MB
const NAME_OUT := "s200house"
var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func cmd(name: String) -> void:
	for c in m._commands():
		if String(c["name"]).begins_with(name):
			(c["run"] as Callable).call()
			return
	ok(false, "command '%s' exists" % name)


func dir_size(d: String) -> int:
	var t := 0
	for f in DirAccess.get_files_at(d):
		t += FileAccess.open(d + "/" + f, FileAccess.READ).get_length()
	for s in DirAccess.get_directories_at(d):
		t += dir_size(d + "/" + s)
	return t


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle()
	m._load_scene("res://scenes/combo3.json")
	await idle(2)
	m.S.name = NAME_OUT
	cmd("Actor: add a second fighter")
	await idle(2)
	# the house stands 10 m away from the hero (open ground in front of the hero), plus two props
	var b := Building.make("s200 house")
	Building.add_room(b, 10.0, 10.0, 4.0, 3.0)
	m.S.building = b
	m.S.props = [Props.make("box", Transform3D(Basis.IDENTITY, Vector3(-6, 0, -12))), Props.make("crate", Transform3D(Basis(Vector3.UP, 0.5), Vector3(5, 0, 6)))]
	# the dialog, as a click sends it
	m._export_dialog_open()
	var ui: ExportDialog = m.export_ui
	var ti := -1
	for i in ui.ui_target.item_count:
		if ui.ui_target.get_item_text(i) == "Godot 4":
			ti = i
	ui.ui_target.select(ti)
	ui._on_target(ti)
	var fi := -1
	for i in ui.ui_format.item_count:
		if ui.ui_format.get_item_text(i).begins_with("Playable game"):
			fi = i
	ok(fi >= 0, "the Godot 4 target lists 'Playable game (Godot project folder)'")
	ui.ui_format.select(fi)
	ui._on_format(fi)
	await idle()
	DirAccess.make_dir_recursive_absolute("C:/Temp/claude/s200")
	var shot := root.get_viewport().get_texture().get_image()
	if shot != null:
		shot.save_png("C:/Temp/claude/s200/dialog.png")
	ui.dlg.get_ok_button().pressed.emit()
	await idle(3)
	var game := ProjectSettings.globalize_path("res://exports/%s_game" % NAME_OUT)
	# G1
	var pg := FileAccess.get_file_as_string(game + "/project.godot")
	ok(pg.contains("run/main_scene=\"res://main.tscn\"") and pg.contains("config_version=5"), "project.godot exists with main_scene res://main.tscn")
	ok(FileAccess.get_file_as_string(game + "/README.txt").contains("F5"), "README.txt says press F5")
	# G2
	var ps = ResourceLoader.load(game + "/main.tscn", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	ok(ps is PackedScene, "main.tscn loads with ResourceLoader")
	var inst: Node = (ps as PackedScene).instantiate()
	var bodies: Array = inst.find_children("*", "StaticBody3D", true, false)
	var parts: Array = bodies.filter(func(n): return n.name != "Ground")
	ok(parts.size() == 3 and bodies.size() == 4, "StaticBody3D: %d built parts (house + 2 props = 3) + Ground (total %d)" % [parts.size(), bodies.size()])
	var cbs: Array = inst.find_children("*", "CharacterBody3D", true, false)
	ok(cbs.size() == 1, "exactly 1 CharacterBody3D (%d)" % cbs.size())
	# G3
	var good := 0
	for p in parts:
		var cs: Array = p.find_children("*", "CollisionShape3D", false, false)
		var mis: Array = p.find_children("*", "MeshInstance3D", false, false)
		if not cs.is_empty() and not mis.is_empty() and cs[0].shape is ConcavePolygonShape3D and (cs[0].shape as ConcavePolygonShape3D).get_faces().size() >= 36:
			good += 1
	ok(good == parts.size() and good > 0, "every part has a mesh + a trimesh collision shape (%d of %d, >= 12 faces)" % [good, parts.size()])
	# G4
	var npcs: Array = inst.get_children().filter(func(n): return n.name.begins_with("NPC_"))
	ok(npcs.size() == 1 and npcs[0].get_class() == "Node3D", "1 idle NPC (%d)" % npcs.size())
	ok(inst.find_children("*", "DirectionalLight3D", true, false).size() >= 1 and inst.find_children("*", "Camera3D", true, false).size() == 1, "lights and a follow camera are in the scene")
	inst.free()
	ok(FileAccess.file_exists(game + "/hero.glb") and FileAccess.file_exists(game + "/npc_1.glb"), "hero.glb and npc_1.glb are written")
	# G5 / G6: run it with Godot itself
	var simdir := "C:/Temp/claude/s200/sim"
	DirAccess.make_dir_recursive_absolute(simdir)
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://tests/s200_sim.gd"), simdir + "/s200_sim.gd")
	var out := []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", game, "--script", simdir + "/s200_sim.gd", "--quit-after", "30000"], out, true)
	var txt := "\n".join(out)
	print(txt.substr(0, 1500))
	ok(not txt.contains("SCRIPT ERROR"), "the exported project runs headless with no script error (exit %d)" % code)
	var re := RegEx.create_from_string("SIM start=\\(([-\\d.e]+), ([-\\d.e]+), ([-\\d.e]+)\\) end=\\(([-\\d.e]+), ([-\\d.e]+), ([-\\d.e]+)\\)")
	var r := re.search(txt)
	var moved := 0.0
	if r != null:
		moved = Vector3(float(r.get_string(1)), 0, float(r.get_string(3))).distance_to(Vector3(float(r.get_string(4)), 0, float(r.get_string(6))))
	ok(moved > 1.0, "the hero moved %.2f m in 2 s of forward input (> 1 m)" % moved)
	var r2 := RegEx.create_from_string("SIM miny=([-\\d.e]+) jump=([-\\d.e]+)").search(txt)
	var miny := -99.0
	var jump := 0.0
	if r2 != null:
		miny = float(r2.get_string(1))
		jump = float(r2.get_string(2))
	ok(miny >= -0.05, "the hero never fell through the floor (lowest y %.3f >= -0.05)" % miny)
	ok(jump > 0.5, "a jump rose %.2f m (> 0.5)" % jump)
	var mb := dir_size(game) / 1048576.0
	ok(mb < 50.0, "the exported folder is %.2f MB (< 50)" % mb)
	print("s200: %d fail" % fails)
	quit()
