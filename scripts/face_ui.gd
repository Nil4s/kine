## THE FACE PANEL (ROADMAP 74; the maths: scripts/face.gd). Kept out of main.gd like ClipsUI: main makes one of these
## (main.face_ui) and lists its command. The panel's sliders are the head's preview while it is open (main._face_draw); OK
## keys every channel at the playhead as ONE undo step (main._do). Nothing is keyed by moving a slider.
##   "Face: key the face at the playhead..."   brows L/R, jaw, eye look (yaw / pitch), blink, the four visemes M A O E
##   Mirror L/R (a button)                      the sliders' brows swap and the eye yaw negates (preview; OK keys it)
##   The lip sync (Lip-sync: from the audio track) drives the jaw and visemes at the playhead when it is baked.
class_name FaceUI
extends RefCounted

var m: Node            # main.gd
var dlg: ConfirmationDialog
var _sl := {}         # channel -> HSlider
var _lb := {}         # channel -> Label (the value and its reading)
var _note: Label
const LABEL := {"brow_l": "Brow left (raise +, furrow -)", "brow_r": "Brow right (raise +, furrow -)", "jaw": "Jaw open (0 = shut, 1 = max)",
	"eye_yaw": "Eyes look left (+) / right (-)", "eye_pitch": "Eyes look up (+) / down (-)", "blink": "Blink (1 = shut)",
	"vis_M": "Viseme M: lips shut (M, B, P)", "vis_A": "Viseme A: open (A)", "vis_O": "Viseme O: round (O, U)", "vis_E": "Viseme E: wide (E, I)",
	"squint": "Lids tight (AU6/7)", "widen": "Upper lid raised (AU5)", "press": "Lips pressed (AU23/24)"}


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Face: key the face at the playhead...", "", open, "face expression brow eyebrow eyes look blink jaw mouth viseme visemes lip key",
		false, "the head's face at the playhead: brows L/R, jaw, eye look (yaw, pitch; +-45 / 30 deg), blink, visemes M A O E; OK keys it (one undo step); Mirror L/R swaps the brows and negates the eye yaw")


## true while the panel is up: the head shows its sliders (a preview, not the keys)
func live() -> bool:
	return dlg != null and dlg.visible


## the sliders' raw channel values (face.gd channels)
func values() -> Dictionary:
	var out := {}
	for ch in Face.CHANNELS:
		out[ch] = float(_sl[ch].value) if _sl.has(ch) else 0.0
	return out


func _set_values(v: Dictionary) -> void:
	for ch in Face.CHANNELS:
		if _sl.has(ch):
			(_sl[ch] as HSlider).set_value_no_signal(float(v.get(ch, 0.0)))
			_show(ch)


func _build() -> void:
	dlg = ConfirmationDialog.new()
	dlg.name = "face_dialog"
	dlg.min_size = Vector2i(460, 0)
	dlg.exclusive = false
	dlg.ok_button_text = "Key at playhead"
	dlg.add_button("Mirror L/R", false, "mirror")
	var col := VBoxContainer.new()
	_note = Label.new()
	_note.name = "face_note"
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_note)
	for ch in Face.CHANNELS:
		var r := Face.range_of(ch)
		var row := VBoxContainer.new()
		var lb := Label.new()
		lb.name = "lbl_" + ch
		row.add_child(lb)
		var sl := HSlider.new()
		sl.name = "sl_" + ch
		sl.min_value = r.x
		sl.max_value = r.y
		sl.step = 0.01
		sl.custom_minimum_size = Vector2(420, 18)
		sl.value_changed.connect(_slid.bind(ch))
		row.add_child(sl)
		col.add_child(row)
		_sl[ch] = sl
		_lb[ch] = lb
	# BODYWALK: the 17 sliders scroll inside a 430 px box, so the dialog's own buttons (Key at playhead, Mirror, Cancel) fit a 720 px window
	var scroll := ScrollContainer.new()
	scroll.name = "face_scroll"
	scroll.custom_minimum_size = Vector2(440, 430)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)
	dlg.add_child(scroll)
	dlg.confirmed.connect(_ok)
	dlg.custom_action.connect(_action)
	dlg.visibility_changed.connect(_vis)
	m.add_child(dlg)


## the readout of one channel: its value and what it reads on the head
func _show(ch: String) -> void:
	var v := float(_sl[ch].value)
	var t: String = LABEL[ch] + ":  %.2f" % v
	match ch:
		"jaw":
			t += "   (%.1f deg of %.1f max)" % [v * Face.JAW_MAX_DEG, Face.JAW_MAX_DEG]
		"eye_yaw":
			t += "   (%.0f deg; range +-%.0f)" % [v * Face.EYE_YAW_MAX, Face.EYE_YAW_MAX]
		"eye_pitch":
			t += "   (%.0f deg; range +-%.0f)" % [v * Face.EYE_PITCH_MAX, Face.EYE_PITCH_MAX]
	(_lb[ch] as Label).text = t


func _slid(_v: float, ch: String) -> void:
	_show(ch)
	m._face_draw()


## the panel shows or hides: the head goes back to the keys when it closes
func _vis() -> void:
	if not dlg.visible:
		m._face_draw()


func _changed() -> void:
	m._face_draw()


func open() -> void:
	var S: Scene = m.S
	if dlg == null:
		_build()
	_set_values(Face.values_at(S.face, float(m.playhead)))
	_note.text = ("Lip sync is baked on this scene: it drives the jaw and the visemes at the playhead, so OK keys only the brows, eyes and blink for them."
		if not S.lip.is_empty() else "Sliders preview on the head. OK keys all of them at the playhead as one undo step.")
	if S.cards.is_empty():   # BODYWALK: a body with no clips is one still face for the whole scene (time 0)
		_note.text = "No clips yet: this face is the body's face for the whole scene. Sliders preview on the head; OK keys it (one undo step)."
	dlg.title = "Face at %.2f s" % float(m.playhead)
	dlg.popup_centered()
	for ch in Face.CHANNELS:
		_show(ch)
	m._face_draw()


func _action(name: StringName) -> void:
	if name == &"mirror":
		_set_values(Face.mirror_values(values()))
		_changed()
		m._say("mirrored on the sliders: the brows swapped, the eye yaw negated (OK keys it)")


func _ok() -> void:
	key(float(m.playhead), values())


## the edit (the dialog's OK, agents and tests): every channel keyed at t as ONE undo step
func key(t: float, vals: Dictionary) -> void:
	var S: Scene = m.S
	var tt := clampf(t, 0.0, S.length())
	m._do(func(): Face.key(S.face, tt, vals))
	m._say("face keyed at %.2f s  (%d channel%s; Ctrl+Z takes it back)" % [tt, Face.CHANNELS.size(), "" if Face.CHANNELS.size() == 1 else "s"])
