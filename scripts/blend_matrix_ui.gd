## blend_matrix_ui.gd - BLEND MATRIX IN THE APP (N084; the maths: scripts/blend_matrix.gd, the grid: scripts/blend_matrix_panel.gd). Kept out of main.gd:
## main makes one of these (main.bm_ui), lists its command and calls tick() each frame.
##   "Blend matrix: check my clips..."  a window: the blend time and a button; it reads your scenes and moves (scenes/ and moves/, the ones with motion),
##                                      crossfades every clip into every other and shows the heat grid and the worst pairs in words.
##                                      Click a cell to PREVIEW that blend on the body (the end of the row's clip into the start of the column's, at the
##                                      real speed; the status line says the numbers). Starting a preview is one undo step: Ctrl+Z gives the pose back.
## Read only: scenes and moves are read, never written.
class_name BlendMatrixUI
extends RefCounted

var m: Node            # main.gd
var dlg: AcceptDialog
var panel: BlendMatrixPanel
var spin: SpinBox
var info: Label
var worst: Label
var clips: Array = []
var M: Dictionary = {}
var play: Array = []   # the preview's frames (BlendMatrix.frames) while one runs
var play_i := 0
var play_acc := 0.0
var play_name := ""


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Blend matrix: check my clips...", "", open, "blend matrix crossfade clips moveset transition limit clash foot skate slide pairs bad heat grid",
		false, "every clip of your scenes crossfaded into every other: a heat grid of which transitions break a joint limit, clash with the body or slide a planted foot; click a cell to preview that blend (your scenes are only read)")


func _build() -> void:
	dlg = AcceptDialog.new()
	dlg.name = "blend_matrix_dialog"
	dlg.title = "Blend matrix"
	dlg.exclusive = false
	dlg.min_size = Vector2i(560, 440)
	var v := VBoxContainer.new()
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = "blend time (s)"
	h.add_child(l)
	spin = SpinBox.new()
	spin.name = "spin_blend_s"
	spin.min_value = 0.03
	spin.max_value = 2.0
	spin.step = 0.01
	spin.value = 0.2
	h.add_child(spin)
	var b := Button.new()
	b.name = "btn_blend_run"
	b.text = "Check my clips"
	b.pressed.connect(run)
	h.add_child(b)
	v.add_child(h)
	info = Label.new()
	info.name = "lbl_blend_info"
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(520, 0)
	v.add_child(info)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(520, 260)
	panel = BlendMatrixPanel.new()
	panel.name = "blend_matrix_grid"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.picked.connect(preview)
	sc.add_child(panel)
	v.add_child(sc)
	worst = Label.new()
	worst.name = "lbl_blend_worst"
	worst.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	worst.custom_minimum_size = Vector2(520, 0)
	v.add_child(worst)
	dlg.add_child(v)
	m.add_child(dlg)


func open() -> void:
	if dlg == null:
		_build()
	dlg.popup_centered()
	info.text = "Press Check my clips: it reads the scenes and moves with motion and checks every crossfade."


func run() -> void:
	if dlg == null:
		_build()
	info.text = "reading your clips..."
	clips = BlendMatrix.clips_of_dirs(["res://scenes/", "res://moves/"])
	if clips.is_empty():
		info.text = "none of your scenes has motion to blend"
		return
	set_matrix(BlendMatrix.matrix(clips, spin.value))


func set_matrix(mx: Dictionary) -> void:
	M = mx
	if dlg == null:
		_build()
	panel.set_matrix(M)
	info.text = BlendMatrix.words(M, 0)
	worst.text = "\n".join(BlendMatrix.words(M, 6).split("\n").slice(1))
	m._say(String(info.text))


## preview the blend of cell (i, j) on the body at the real speed
func preview(i: int, j: int) -> void:
	if clips.size() <= maxi(i, j) or i < 0 or j < 0:
		return
	m.playing = false
	m._step_hint = "Blend matrix preview"
	m._push_undo()   # one undo step; it also ends any running preview, so the frames are set after it
	play = BlendMatrix.frames(clips[i], clips[j], float(M.get("blend_s", 0.2)))
	play_i = 0
	play_acc = 0.0
	play_name = "%s -> %s" % [clips[i]["name"], clips[j]["name"]]
	var c: Dictionary = M["cells"][i][j]
	m._say("BLEND %s: %s (%s)" % [play_name, c["verdict"], c["why"]])
	_show(0)


func halt() -> void:
	play = []


func _show(k: int) -> void:
	var f: Dictionary = play[k]
	var B: Body = m.B
	for j in Body.ORDER:
		B.ang[j] = f["ang"][j]
	B.offset = f["offset"]
	B.fk()
	m._refresh()


func tick(dt: float) -> void:
	if play.is_empty():
		return
	play_acc += dt
	var k := int(play_acc / BlendMatrix.DT)
	if k >= play.size():
		_show(play.size() - 1)
		play = []
		return
	if k != play_i:
		play_i = k
		_show(k)
