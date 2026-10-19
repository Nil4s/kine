## hit_boxes_ui.gd - HIT / HURT BOXES IN THE APP (ROADMAP 36). Kept out of main.gd like clips_ui.gd: main makes one of these
## (main.hitbox_ui), lists its commands, and the undo snapshot carries S.boxes. Every OK / Delete here is ONE undo step (main._do).
## The maths and the file form: scripts/hit_boxes.gd. The view draws the boxes (fd boxes), the timeline has the lane.
##   "Hit box: add on the picked part..."        an attack box over frames f0..f1 on the picked part (damage, hitstun, radius)
##   "Hurt box: shrink, grow or switch off..."   a vulnerable edit on the picked part (scale %, or off for those frames)
##   "Box: invincible over these frames..."      every vulnerable capsule off over frames f0..f1
##   "Box: edit or delete a box..."              pick one of the scene's boxes: its fields, OK or Delete
## Frames are the frame data's (60 fps unless the fps button says otherwise); the default range starts at the playhead.
class_name HitBoxesUI
extends RefCounted

var m: Node            # main.gd
var dlg: ConfirmationDialog
var _edit := -1        # the index of the box being edited, -1 = a new one
var _kind := "hit"     # "hit" / "hurt" / "inv" of the dialog as it is
var _rows := {}        # field name -> [Label, Control]: shown or hidden by the kind
var ui_kind: OptionButton
var ui_part: OptionButton
var ui_pick: OptionButton
var ui_f0: SpinBox
var ui_f1: SpinBox
var ui_dmg: SpinBox
var ui_stun: SpinBox
var ui_scale: SpinBox
var ui_rad: SpinBox
var ui_del: Button     # Delete: only when a box is being edited
const KIND_WORDS := {"hit": "attack: hit box", "hurt": "vulnerable: shrink, grow or off", "inv": "invincible: no hurt box"}
const KIND_ORDER := ["hit", "hurt", "inv"]


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Hit box: add on the picked part...", "", open.bind("hit"), "hit box attack hitbox damage hitstun strike frames active bat hand foot draw",
		true, "an attack box on the picked part over a range of frames: its damage and hitstun, a radius if it should differ from the part's; it moves with the part (ROADMAP 36)")
	add.call("Hurt box: shrink, grow or switch off the picked part...", "", open.bind("hurt"), "hurt box vulnerable hurtbox shrink grow off scale frames",
		true, "the picked body part's vulnerable capsule over a range of frames: its radius times a scale, or off for those frames (ROADMAP 36)")
	add.call("Box: invincible over these frames...", "", open.bind("inv"), "invincible invulnerable no hurt box frames i-frames",
		true, "every vulnerable capsule off over a range of frames: the body cannot be hit then (ROADMAP 36)")
	add.call("Box: edit or delete a box...", "", open_edit, "box edit delete remove change hit hurt frames",
		true, "one of the scene's hit or hurt boxes: its part, frames, damage, hitstun, scale, or delete it (ROADMAP 36)")


func _build() -> void:
	dlg = ConfirmationDialog.new()
	dlg.name = "hit_box_dialog"
	dlg.min_size = Vector2i(440, 0)
	dlg.exclusive = false
	var g := GridContainer.new()
	g.columns = 2
	var row := func(field: String, words: String, c: Control):
		var l := Label.new()
		l.text = words
		g.add_child(l)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(c)
		_rows[field] = [l, c]
	ui_pick = OptionButton.new()
	ui_pick.name = "opt_box_pick"
	ui_pick.item_selected.connect(_pick_changed)
	row.call("pick", "box", ui_pick)
	ui_kind = OptionButton.new()
	ui_kind.name = "opt_box_kind"
	for k in KIND_ORDER:
		ui_kind.add_item(KIND_WORDS[k])
	ui_kind.item_selected.connect(func(_i): _set_kind(KIND_ORDER[ui_kind.selected], true))
	row.call("kind", "kind", ui_kind)
	ui_part = OptionButton.new()
	ui_part.name = "opt_box_part"
	row.call("part", "part", ui_part)
	ui_f0 = _spin("spin_box_f0", 0, 9999, 1)
	row.call("f0", "first frame", ui_f0)
	ui_f1 = _spin("spin_box_f1", 0, 9999, 1)
	row.call("f1", "last frame (included)", ui_f1)
	ui_dmg = _spin("spin_box_damage", 0, HitBoxes.DAMAGE_MAX, 1)
	row.call("dmg", "damage", ui_dmg)
	ui_stun = _spin("spin_box_hitstun", 0, HitBoxes.HITSTUN_MAX, 1)
	row.call("stun", "hitstun (frames)", ui_stun)
	ui_rad = _spin("spin_box_radius", 0, 30, 0.5)
	row.call("rad", "radius (cm, 0 = the part's own)", ui_rad)
	ui_scale = _spin("spin_box_scale", HitBoxes.SCALE_MIN * 100.0, HitBoxes.SCALE_MAX * 100.0, 5)
	row.call("scale", "size (% of the part's own)", ui_scale)
	dlg.add_child(g)
	dlg.confirmed.connect(_ok)
	dlg.custom_action.connect(func(a): if a == "delete": _delete())
	ui_del = dlg.add_button("Delete", true, "delete")
	m.add_child(dlg)


func _spin(nm: String, lo: float, hi: float, st: float) -> SpinBox:
	var s := SpinBox.new()
	s.name = nm
	s.min_value = lo
	s.max_value = hi
	s.step = st
	return s


## the dialog's fields for a kind: the part list, the attack-only and vulnerable-only rows
func _set_kind(kind: String, reset_part: bool) -> void:
	_kind = kind
	ui_kind.select(KIND_ORDER.find(kind))
	ui_part.clear()
	var parts: Array = HitBoxes.hit_parts() if kind == "hit" else ([HitBoxes.ALL] + HitBoxes.hurt_parts())
	for p in parts:
		ui_part.add_item("all body parts" if p == HitBoxes.ALL else String(p).replace("_", " "))
		ui_part.set_item_metadata(ui_part.item_count - 1, p)
	var want := String(m.sel) if kind == "hit" else HitBoxes.ALL
	if kind == "inv":
		want = HitBoxes.ALL
	if reset_part:
		var at := parts.find(want)
		ui_part.select(maxi(at, 0))
	ui_part.disabled = kind == "inv"
	for f in ["dmg", "stun", "rad"]:
		_show(f, kind == "hit")
	_show("scale", kind == "hurt")


func _show(field: String, on: bool) -> void:
	if _rows.has(field):
		for c in _rows[field]:
			(c as Control).visible = on


func _part() -> String:
	return String(ui_part.get_item_metadata(maxi(ui_part.selected, 0)))


## a box as the dialog's fields
func _fill(e: Dictionary) -> void:
	_set_kind(String(e["kind"]) if String(e["kind"]) == "hit" else ("inv" if HitBoxes.is_invincible(e) else "hurt"), false)
	var parts: Array = HitBoxes.hit_parts() if _kind == "hit" else ([HitBoxes.ALL] + HitBoxes.hurt_parts())
	ui_part.select(maxi(parts.find(String(e["part"])), 0))
	ui_f0.value = int(e["f0"])
	ui_f1.value = int(e["f1"])
	ui_dmg.value = float(e.get("damage", 0.0))
	ui_stun.value = int(e.get("hitstun", 0))
	ui_rad.value = float(e.get("r", 0.0)) * 100.0
	ui_scale.value = float(e.get("scale", 1.0)) * 100.0


## the dialog's fields as a box (clean makes it a valid one, or drops it)
func _entry() -> Dictionary:
	var e := {"f0": int(ui_f0.value), "f1": int(ui_f1.value), "part": _part()}
	if _kind == "hit":
		e["kind"] = "hit"
		e["damage"] = ui_dmg.value
		e["hitstun"] = int(ui_stun.value)
		if ui_rad.value > 0.0:
			e["r"] = ui_rad.value / 100.0
	else:
		e["kind"] = "hurt"
		if _kind == "inv":
			e["part"] = HitBoxes.ALL
			e["off"] = true
		else:
			e["scale"] = ui_scale.value / 100.0
	return e


## the frame at the playhead, in the frame data's fps
func _frame_now() -> int:
	return int(round(float(m.playhead) * float(m.fd_fps)))


func open(kind: String) -> void:
	if m.S.cards.is_empty():
		m._say("a box is drawn on a scene: open a scene, or press Enter to add the body as a card first")
		return
	if kind == "hit" and String(m.sel) == "":
		m._say("pick the part first: click it in the view, then Hit box")
		return
	if dlg == null:
		_build()
	_edit = -1
	ui_pick.visible = false
	_rows["pick"][0].visible = false
	_rows["pick"][1].visible = false
	ui_del.visible = false
	_fill_defaults(kind)
	dlg.title = "%s at %d" % [KIND_WORDS[kind], _frame_now()]
	dlg.popup_centered()


func _fill_defaults(kind: String) -> void:
	_set_kind(kind, true)
	var f := _frame_now()
	ui_f0.value = f
	ui_f1.value = f + (4 if kind == "hit" else 9)
	ui_dmg.value = 10
	ui_stun.value = 12
	ui_rad.value = 0
	ui_scale.value = 50 if kind == "hurt" else 100


## the scene's boxes listed, one of them picked for editing
func open_edit() -> void:
	var L: Array = m.S.boxes
	if L.is_empty():
		m._say("there are no hit or hurt boxes yet: Hit box or Hurt box adds one on the picked part")
		return
	if dlg == null:
		_build()
	ui_pick.clear()
	for i in L.size():
		ui_pick.add_item("%d  %s" % [i + 1, HitBoxes.describe(L[i])])
	ui_pick.visible = true
	_rows["pick"][0].visible = true
	_rows["pick"][1].visible = true
	ui_del.visible = true
	_pick_to(0)
	dlg.title = "Box: edit or delete"
	dlg.popup_centered()


func _pick_to(i: int) -> void:
	_edit = i
	ui_pick.select(i)
	_fill(m.S.boxes[i])


func _pick_changed(i: int) -> void:
	_pick_to(i)


## OK: a new box, or the picked one changed. ONE undo step.
func _ok() -> void:
	var e := HitBoxes.clean([_entry()])
	if e.is_empty():
		m._say("that box is not valid: its part is not one a box can ride on")
		return
	m._do(_put.bind(e[0], _edit))
	m._say("box saved: %s" % HitBoxes.describe(e[0]))


func _put(e: Dictionary, idx: int) -> void:
	var L: Array = m.S.boxes.duplicate(true)
	if idx < 0 or idx >= L.size():
		L.append(e)
	else:
		L[idx] = e
	m.S.boxes = HitBoxes.clean(L)
	m._refresh()


## Delete (edit mode): the picked box goes. ONE undo step.
func _delete() -> void:
	if _edit < 0 or _edit >= m.S.boxes.size():
		return
	m._do(_remove.bind(_edit))
	m._say("box removed")


func _remove(idx: int) -> void:
	var L: Array = m.S.boxes.duplicate(true)
	L.remove_at(idx)
	m.S.boxes = L
	m._refresh()
