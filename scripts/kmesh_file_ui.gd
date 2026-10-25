class_name KMeshFileUI
extends Node
## THE MESH FILE ON THE MODEL PAGE (Blender's Save / Open). Ctrl+S, the ribbon's "Save" and the S box's "save mesh" write the
## open mesh as a .kmesh in meshes/ (UserPaths.w, beside scenes/ and bodies/). The first time, a small box asks the name
## (main.safe_file, the app's file-name rule); after that Ctrl+S writes the same file again, silently, and the status line says
## "Saved chair.kmesh". A name that exists is never written over. "Open..." (the ribbon, "open mesh") lists the saved meshes
## and loads the pick into the editor as ONE undo step (KMeshUndo: Ctrl+Z gives the mesh back). Nothing is removed here.
## The mesh object the file belongs to is remembered: a new test cube (another object) asks a name again.

const EXT := "kmesh"

var ui                        # KMeshEditUI (the owner; ui.m is main)
var path := ""                # the file this mesh was saved to or opened from ("" = not yet)
var _mesh_ref: KMesh = null   # the mesh object `path` belongs to
var _name_dlg: ConfirmationDialog
var _name_edit: LineEdit
var _open_dlg: ConfirmationDialog
var _list: ItemList
var _open_files: Array = []


## the folder the meshes live in (a test points UserPaths at its own folder)
static func dir() -> String:
	return UserPaths.w("res://meshes")


## every .kmesh in dir(), by name
static func list() -> Array:
	var out := []
	var d := dir()
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(d)):
		return out
	for f in DirAccess.get_files_at(d):
		if f.get_extension() == EXT:
			out.append(d.path_join(f))
	out.sort()
	return out


func setup(owner) -> void:
	ui = owner
	_name_dlg = ConfirmationDialog.new()
	_name_dlg.name = "mesh_save_dialog"
	_name_dlg.title = "Save the mesh as"
	_name_dlg.ok_button_text = "Save mesh"
	_name_dlg.min_size = Vector2i(340, 0)
	_name_edit = LineEdit.new()
	_name_edit.name = "edit_name"
	_name_edit.placeholder_text = "name for the mesh, e.g. chair"
	_name_dlg.add_child(_name_edit)
	_name_dlg.register_text_enter(_name_edit)
	_name_dlg.confirmed.connect(_save_named)
	ui.m.ui_root.add_child(_name_dlg)
	_open_dlg = ConfirmationDialog.new()
	_open_dlg.name = "mesh_open_dialog"
	_open_dlg.title = "Open a saved mesh"
	_open_dlg.ok_button_text = "Open"
	_open_dlg.min_size = Vector2i(340, 0)
	_list = ItemList.new()
	_list.name = "mesh_list"
	_list.custom_minimum_size = Vector2(320, 180)
	_open_dlg.add_child(_list)
	_open_dlg.confirmed.connect(_open_selected)
	_list.item_activated.connect(func(_i): _open_dlg.hide(); _open_selected())
	ui.m.ui_root.add_child(_open_dlg)


## the mesh this file belongs to; a different object (a new test cube) has no file yet
func _sync() -> void:
	if ui.mesh != _mesh_ref:
		_mesh_ref = ui.mesh
		path = ""


## Ctrl+S / Save: the first time asks the name, then writes the same file silently
func save_cmd() -> void:
	if ui.mesh == null:
		return
	_sync()
	if path == "" or not FileAccess.file_exists(path):
		_ask_name("")
		return
	_write(path)


func _ask_name(note: String) -> void:
	if note != "":
		ui.m._say(note)
	_name_edit.text = ""
	_name_dlg.popup_centered()
	_name_edit.grab_focus.call_deferred()


func _save_named() -> void:
	var nm := String(ui.m.safe_file(_name_edit.text)).strip_edges()
	if nm.to_lower().ends_with("." + EXT):
		nm = nm.substr(0, nm.length() - EXT.length() - 1)
	if nm == "":
		_ask_name("Save: the mesh needs a name (letters, digits, - or _): type one, then Enter")
		return
	var p := dir().path_join(nm + "." + EXT)
	if FileAccess.file_exists(p):
		_ask_name("Save: a mesh called %s already exists: type another name, or Open... it" % p.get_file())
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir()))
	_write(p)


func _write(p: String) -> void:
	var err: int = ui.mesh.save(p)
	if err != OK:
		ui.m._say("Save: NOT SAVED: " + KMesh.last_error)
		return
	path = p
	_mesh_ref = ui.mesh
	ui.m._say("Saved %s (%d verts, %d faces) in %s. Ctrl+S saves it again" % [p.get_file(), ui.mesh.vert_count(), ui.mesh.face_count(), p.get_base_dir()])


## Open...: the list of saved meshes (a click or Enter on one, then Open, loads it)
func open_cmd() -> void:
	_open_files = list()
	if _open_files.is_empty():
		ui.m._say("Open: no saved meshes yet. Ctrl+S (Save) writes the mesh to meshes/, and Open... lists it here")
		return
	_list.clear()
	for f in _open_files:
		_list.add_item(String(f).get_file().get_basename())
	_list.select(0)
	_open_dlg.popup_centered()
	_list.grab_focus.call_deferred()


func _open_selected() -> void:
	var s := _list.get_selected_items()
	if s.is_empty():
		ui.m._say("Open: pick a mesh in the list")
		return
	load_file(String(_open_files[s[0]]))


## the file's mesh goes into the open editor as one undo step (the same object, its content replaced)
func load_file(p: String) -> bool:
	var tmp := KMesh.load_file(p)
	if tmp == null:
		ui.m._say("Open: NOT OPENED: " + KMesh.last_error)
		return false
	ui.undo.begin(ui.mesh)
	ui.mesh.from_dict(tmp.to_dict())
	ui.undo.commit("Open %s" % p.get_file())
	ui.sel.clear()
	ui.view.mark_dirty()
	_mesh_ref = ui.mesh
	path = p
	ui.m._say("Opened %s (%d verts, %d faces); Ctrl+Z takes the mesh before it back" % [p.get_file(), ui.mesh.vert_count(), ui.mesh.face_count()])
	return true
