class_name KMeshRedoPanel
extends PanelContainer
## P03 (docs/ROADMAP_400.md): the last-op redo panel of the model preview. After extrude, inset, bevel or subdivide a small
## panel shows the op's parameters. Changing one takes the op's undo step back (the mesh returns to the PRE-op state), runs the
## op again with the new value and keeps that as the one undo step: the result is replaced, never stacked. The panel closes as
## soon as anything else edits the mesh (the op's step is no longer the newest, or the mesh is no longer what it made).
## The ops tell it what they did with note(); bevel and subdivide re-run through their own paths, which call note() again.

## kind -> [[param, label, min, max, step, scale (100 = shown in cm), is_int]]
const FIELDS := {
	"extrude": [["distance", "distance (cm)", 0.01, 1000.0, 0.01, 100.0, false]],
	"inset": [["amount", "amount (cm)", 0.01, 1000.0, 0.01, 100.0, false]],
	"bevel": [["width", "width (cm)", 0.1, 1000.0, 0.01, 100.0, false], ["segments", "segments", 1, 32, 1, 1.0, true], ["profile", "profile", 0.05, 1.0, 0.01, 1.0, false]],
	"subdivide": [["levels", "levels", 1, 3, 1, 1.0, true]],
}

var ui: Node
var rec := {}                  # {kind, params, step, sel0}
var _spins := {}               # param -> SpinBox
var _kind := ""
var _box: GridContainer
var _title: Label


func setup(u: Node) -> void:
	ui = u
	name = "redo_panel"
	visible = false
	var vb := VBoxContainer.new()
	_title = Label.new()
	vb.add_child(_title)
	_box = GridContainer.new()
	_box.columns = 2
	vb.add_child(_box)
	add_child(vb)


## the SpinBox of a parameter (null when this op has none of that name)
func spin(param: String) -> SpinBox:
	return _spins.get(param)


## an op just ran: `step` is its undo step, `sel0` the selection it started from
func note(kind: String, params: Dictionary, step: Dictionary, sel0: Dictionary) -> void:
	if step.is_empty() or not FIELDS.has(kind):
		close()
		return
	rec = {"kind": kind, "params": params.duplicate(), "step": step, "sel0": sel0}
	if kind != _kind:
		_build(kind)
	for f in FIELDS[kind]:
		var s: SpinBox = _spins[f[0]]
		s.set_value_no_signal(float(params.get(f[0], s.value / f[5])) * f[5])
	visible = ui.on
	reset_size()
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)


func _build(kind: String) -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	_spins = {}
	_kind = kind
	_title.text = "Last op: " + kind
	for f in FIELDS[kind]:
		var l := Label.new()
		l.text = f[1]
		_box.add_child(l)
		var s := SpinBox.new()
		s.name = "spin_redo_" + f[0]
		s.min_value = f[2]
		s.max_value = f[3]
		s.step = f[4]
		var pname: String = f[0]
		s.value_changed.connect(func(v): set_param(pname, v))
		_box.add_child(s)
		_spins[f[0]] = s


func close() -> void:
	rec = {}
	visible = false


## the op's step is still the newest and the mesh is exactly what it made
func is_live() -> bool:
	if rec.is_empty() or not ui.on:
		return false
	var u: KMeshUndo = ui.undo
	var st: Dictionary = rec["step"]
	if u.steps.is_empty() or not is_same(u.steps[u.steps.size() - 1], st) or not st.has("new_v"):
		return false
	return is_same(st["mesh"], ui.mesh) and ui.mesh.verts == st["new_v"] and KMeshUndo._same_faces(ui.mesh.faces, st["new_f"])


func _process(_dt: float) -> void:
	if not rec.is_empty() and not is_live():
		close()
	elif not rec.is_empty():
		visible = ui.showing


## change one parameter (in the units the field shows: cm for lengths) and re-run the op from the pre-op state.
## false = the panel is not live any more (nothing changed)
func set_param(param: String, shown: float) -> bool:
	if not is_live():
		close()
		return false
	var kind: String = rec["kind"]
	var scale := 1.0
	var is_int := false
	for f in FIELDS[kind]:
		if f[0] == param:
			scale = f[5]
			is_int = f[6]
	if not _spins.has(param):
		return false
	var p: Dictionary = rec["params"].duplicate()
	p[param] = int(round(shown)) if is_int else shown / scale
	var sel0: Dictionary = rec["sel0"]
	match kind:
		"bevel":
			KMeshBevel.set_live(ui, float(p["width"]), int(p["segments"]), float(p["profile"]))   # undoes, re-bevels, note()s
		"subdivide":
			ui.undo.undo()
			ui.sel.restore(sel0)
			ui.subdivide(int(p["levels"]))   # note()s
		_:
			ui.undo.undo()
			ui.sel.restore(sel0)
			ui.undo.begin(ui.mesh)
			var r: Dictionary
			if kind == "extrude":
				r = KMeshExtrude.extrude(ui.mesh, ui.sel, float(p["distance"]), bool(p.get("each", false)))
			else:
				r = KMeshExtrude.inset(ui.mesh, ui.sel, float(p["amount"]), bool(p.get("each", false)))
			var st: Dictionary = ui.undo.commit("Extrude" if kind == "extrude" else "Inset")
			ui.view.mark_dirty()
			if String(r.get("error", "")) != "":
				close()
				ui.m._say("Model: %s: %s" % [kind, r["error"]])
				return true
			note(kind, p, st, sel0)
	return true
