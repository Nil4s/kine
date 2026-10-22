## "Surface: material from a photo...": the picker, the name / strength dialog, and the application of the result
## (the maths and the files are scripts/photo_material.gd). The target is the picked prop, else the picked body part; the
## material is a PREVIEW on it: a prop keeps the folder name in its scene entry ("mat"), a body part in Main.body_mats
## (view state, undone with the rest). Applying is ONE undo step that puts the old material back.
class_name PhotoMaterialUI
extends RefCounted

var m: Node
var last := {}   # the last run: {"ms", "name", "target", "mean"}


func _init(main: Node) -> void:
	m = main


## what the material would go on: {"kind": "prop", "i"} or {"kind": "part", "part"}; {} when nothing is picked
func target() -> Dictionary:
	if m.sel_prop >= 0 and m.sel_prop < m.S.props.size():
		return {"kind": "prop", "i": m.sel_prop}
	if m.pieces.has(m.sel):
		return {"kind": "part", "part": m.sel}
	return {}


func ask() -> void:
	if target().is_empty():
		m._say("pick a prop (click it in the view) or a body part first, then run Surface: material from a photo... again")
		return
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.bmp ; pictures"])
	fd.use_native_dialog = true
	fd.title = "Material from a photo: a picture of a surface (brick, wood, cloth, stone)"
	fd.file_selected.connect(func(p): options(p); fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	m.add_child(fd)
	fd.popup_centered(Vector2i(800, 500))


## the name + normal strength dialog for a picked picture
func options(path: String) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "Material from a photo"
	dlg.ok_button_text = "Make and apply"
	var box := VBoxContainer.new()
	var name_e := LineEdit.new()
	name_e.text = PhotoMaterial.clean_name(path.get_file().get_basename())
	name_e.tooltip_text = "the folder name under user://materials"
	var sl := HSlider.new()
	sl.min_value = 0.25
	sl.max_value = 12.0
	sl.step = 0.25
	sl.value = PhotoMaterial.STRENGTH
	sl.custom_minimum_size = Vector2(280, 24)
	var lab := Label.new()
	lab.text = "name, then normal strength %.2f" % sl.value
	sl.value_changed.connect(func(v): lab.text = "name, then normal strength %.2f" % v)
	box.add_child(lab)
	box.add_child(name_e)
	box.add_child(sl)
	dlg.add_child(box)
	dlg.confirmed.connect(func(): apply(path, name_e.text, sl.value); dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	m.add_child(dlg)
	dlg.popup_centered()


## the whole job; false (and a said reason) when it could not be done. One undo step.
func apply(path: String, name: String, strength := PhotoMaterial.STRENGTH) -> bool:
	var tg := target()
	if tg.is_empty():
		m._say("pick a prop (click it in the view) or a body part first, then run Surface: material from a photo... again")
		return false
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		m._say("could not read %s as a picture; pick a PNG, JPG or WEBP with Surface: material from a photo..." % path.get_file())
		return false
	var t0 := Time.get_ticks_msec()
	var maps := PhotoMaterial.make(img, strength)
	var nm := PhotoMaterial.clean_name(name)
	if PhotoMaterial.save(nm, maps) == "":
		m._say("could not write user://materials/%s: check the disk, or pick another name with Surface: material from a photo..." % nm)
		return false
	m._step_hint = "Material from a photo"
	m._push_undo()
	if tg["kind"] == "prop":
		m.S.props[tg["i"]]["mat"] = nm
		m._props_show()
	else:
		m.body_mats[tg["part"]] = nm
		sync_body()
	last = {"ms": Time.get_ticks_msec() - t0, "name": nm, "target": tg, "mean": PhotoMaterial.mean_lum(maps["albedo"], Rect2i(0, 0, maps["albedo"].get_width(), maps["albedo"].get_height()))}
	m._doc_line()
	m._say("material %s on the %s (%d ms; saved in user://materials/%s: albedo, rough, normal and material.tres); Ctrl+Z puts the old surface back" % [nm, m._prop_name(tg["i"]) if tg["kind"] == "prop" else String(tg["part"]).replace("_", " "), last["ms"], nm])
	return true


## the body parts' pieces drawn with their materials (a part without one: the mannequin's own)
func sync_body() -> void:
	for j in m.pieces:
		var mi: MeshInstance3D = m.pieces[j]
		mi.material_override = PhotoMaterial.load_material(m.body_mats[j]) if m.body_mats.has(j) else null
