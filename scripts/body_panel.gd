## body_panel.gd - THE BODY PAGE'S PANEL (docs/PAGES_PLAN.md step 2): make the person from real measurements.
## Sex blend + stature + body mass + four proportions, each a percentile of ANSUR II (scripts/body_model.gd has the
## numbers). A drag PREVIEWS on the live body (bones and skin rescaled, no history); letting go is ONE undo step
## (Main.proportions_set). Keys / clicks on a slider commit at once. Nothing writes data/skeleton.json.
class_name BodyPanel
extends PanelContainer

signal begin()
signal preview(body: Dictionary)
signal commit(body: Dictionary)

const LABELS := {"stat": "Stature", "mass": "Body mass", "arm": "Arm length", "leg": "Leg length", "trunk": "Trunk length", "head": "Head size"}
const TIPS := {
	"stat": "how tall, as a percentile of the ANSUR II survey (US Army 2012: 4082 men, 1986 women). The standing height is exact",
	"mass": "body mass, as a percentile of ANSUR II. It sets the centre of mass, the readouts and the girth: the skin thickens across each bone, most at the waist, least at the forearm (ANSUR II)",
	"arm": "the arms' length relative to height (upper arm, forearm and hand together); 50th = the textbook proportion (Drillis & Contini)",
	"leg": "the legs' length relative to height (thigh and shank); 50th = the textbook proportion",
	"trunk": "the torso's length relative to height; it carries the shoulder and hip width",
	"head": "the head's size relative to height",
}
var m: Node                   # the Main node (its labels, buttons and Tok colours)
var pr := BodyModel.DEFAULT.duplicate()
var dragging := false
var sliders := {}
var vals := {}                 # key -> its value label
var head_lab: Label
var sub_lab: Label
var meas_lab: Label
var blend_lab: Label
var _sync := false
var _pending := false
var _key := ""                 # the last body synced (a refresh of the same body does nothing)
var last_measures := {}
var chars_dir := "user://characters"   # R12: named characters, one <name>.json each (tests point this at a scratch dir)
var name_edit: LineEdit
var list_box: VBoxContainer


func build(main) -> void:
	m = main
	name = "body_panel"
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(sc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	v.add_child(m._label("BODY", 13, "heading"))
	head_lab = m._label("", 17, "text", true)
	head_lab.name = "body_readout"
	v.add_child(head_lab)
	sub_lab = m._label("", 12, "text:0.7", true)
	v.add_child(sub_lab)
	v.add_child(HSeparator.new())
	blend_lab = m._label("", 12, "text:0.8")
	v.add_child(blend_lab)
	var bs := _slider("blend", 0.0, 100.0, 1.0)
	bs.tooltip_text = "woman <-> man: the survey sample the percentiles are read from (0 = ANSUR II women, 100 = men; between = a blend of the two)"
	v.add_child(bs)
	v.add_child(HSeparator.new())
	for k in BodyModel.KEYS:
		var l: Label = m._label("", 12, "text:0.8")
		vals[k] = l
		v.add_child(l)
		var s := _slider(k, 1.0, 99.0, 0.5)
		s.tooltip_text = TIPS[k]
		v.add_child(s)
	var qr := HBoxContainer.new()
	qr.add_theme_constant_override("separation", 4)
	for p in [5, 50, 95]:
		var b: Button = m._button("%dth" % p, _quick.bind(float(p)), "stature and mass both at the %dth percentile of the chosen sex; the proportions stay as they are" % p)
		b.name = "quick_%d" % p
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		qr.add_child(b)
	v.add_child(qr)
	var rb: Button = m._button("The mannequin as shipped", _reset, "the body back to the 183 cm mannequin (the cards keep their angles; Ctrl+Z undoes)")
	rb.name = "body_reset"
	v.add_child(rb)
	v.add_child(HSeparator.new())
	v.add_child(m._label("Saved characters", 12, "heading"))
	var sr := HBoxContainer.new()
	name_edit = LineEdit.new()
	name_edit.name = "char_name"
	name_edit.placeholder_text = "name this person"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_submitted.connect(func(_t): save_character(name_edit.text))
	sr.add_child(name_edit)
	var sb: Button = m._button("Save", func(): save_character(name_edit.text), "keep these seven sliders as a named character in user://characters (not in any scene)")
	sb.name = "char_save"
	sr.add_child(sb)
	v.add_child(sr)
	list_box = VBoxContainer.new()
	list_box.name = "char_list"
	list_box.add_theme_constant_override("separation", 2)
	v.add_child(list_box)
	refresh_list()
	v.add_child(HSeparator.new())
	meas_lab = m._label("", 12, "text:0.7", true)
	v.add_child(meas_lab)
	v.add_child(m._label("Scene only: data/skeleton.json is never changed. Percentiles: ANSUR II 2012 (Gordon et al.).", 11, "text:0.5", true))
	_show()


func _slider(key: String, lo: float, hi: float, step: float) -> HSlider:
	var s := HSlider.new()
	s.name = "sl_" + key
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(pr[key]) * (100.0 if key == "blend" else 1.0)
	s.focus_mode = Control.FOCUS_CLICK
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(0, 18)
	s.drag_started.connect(_drag_start)
	s.drag_ended.connect(func(_c): _drag_end())
	s.value_changed.connect(func(x): _moved(key, x))
	sliders[key] = s
	return s


func _drag_start() -> void:
	dragging = true
	begin.emit()


func _drag_end() -> void:
	if not dragging:
		return
	dragging = false
	commit.emit(BodyModel.body_for(pr))


func _moved(key: String, x: float) -> void:
	if _sync:
		return
	pr[key] = x / 100.0 if key == "blend" else x
	_show()
	if dragging:
		preview.emit(BodyModel.body_for(pr))
	elif not _pending:   # a key or a click: one commit for the burst
		_pending = true
		begin.emit()
		_flush.call_deferred()


func _flush() -> void:
	_pending = false
	if not dragging:
		commit.emit(BodyModel.body_for(pr))


func _quick(p: float) -> void:
	begin.emit()
	pr["stat"] = p
	pr["mass"] = p
	_set_sliders()
	_show()
	commit.emit(BodyModel.body_for(pr))


func _reset() -> void:
	begin.emit()
	commit.emit({})


func _set_sliders() -> void:
	_sync = true
	for k in sliders:
		(sliders[k] as HSlider).value = float(pr[k]) * (100.0 if k == "blend" else 1.0)
	_sync = false


## the labels from the sliders (the body they make, not the one on the stage: a drag shows at once)
func _show() -> void:
	var bl := float(pr["blend"])
	var d := BodyModel.body_for(pr)
	var st := float(d.get("stature", Proportions.DEFAULT_STATURE))
	var kg := float(d.get("mass", 0.0))
	var who := "man" if bl >= 0.999 else ("woman" if bl <= 0.001 else "%d%% man blend" % roundi(bl * 100.0))
	head_lab.text = "%s percentile %s" % [BodyModel.ordinal(pr["stat"]), who]
	sub_lab.text = "%.1f cm, %.1f kg (%s percentile), BMI %.1f kg/m^2" % [st * 100.0, kg, BodyModel.ordinal(pr["mass"]), kg / (st * st)]
	blend_lab.text = "Sample: %s" % ("ANSUR II women" if bl <= 0.001 else ("ANSUR II men" if bl >= 0.999 else "%d%% men, %d%% women" % [roundi(bl * 100.0), roundi((1.0 - bl) * 100.0)]))
	vals["stat"].text = "%s   %.1f cm   %s" % [LABELS["stat"], st * 100.0, BodyModel.ordinal(pr["stat"])]
	vals["mass"].text = "%s   %.1f kg   %s" % [LABELS["mass"], kg, BodyModel.ordinal(pr["mass"])]
	for k in ["arm", "leg", "trunk", "head"]:
		vals[k].text = "%s   %s   x%.3f" % [LABELS[k], BodyModel.ordinal(pr[k]), exp(BodyModel.zof(pr[k]) * float(BodyModel.CV[k]))]


## the stage's body changed (a load, an undo, a drag): show what it measures now, and move the sliders to it
func sync(body: Dictionary, B: Body, force := false) -> void:
	var key := str(body.hash()) + "|" + str(B.body.hash())
	if key == _key and not force:
		return
	_key = key
	if not BodyModel.body_for(pr) == body:   # not the body the sliders already make: take theirs from it
		pr = BodyModel.params_for(body, float(pr["blend"]))
		_set_sliders()
	_show()
	last_measures = BodyModel.measures(B)
	var L := last_measures
	meas_lab.text = "Measured on the skeleton (T pose): height %.1f cm, arm span %.1f cm (%.2f x height), shoulder joints %.1f cm apart, hip joints %.1f cm apart." % [
		float(L["stature"]) * 100.0, float(L["span"]) * 100.0, float(L["span"]) / float(L["stature"]), float(L["shoulders"]) * 100.0, float(L["hips"]) * 100.0]


## ---- R12: named characters. A character is the seven sliders (blend, stat, mass, arm, leg, trunk, head), nothing else;
## applying one is the same single commit as dragging a slider, so Ctrl+Z takes it back in one step.
static func clean_name(t: String) -> String:
	var out := ""
	for c in t.strip_edges():
		if c.is_valid_identifier() or c in " -" or (c >= "0" and c <= "9") or c.to_lower() != c.to_upper():
			out += c
	return out.strip_edges().left(40)


func _path(nm: String) -> String:
	return chars_dir.path_join(nm + ".json")


func character_names() -> Array:
	var out := []
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(chars_dir)):
		return out
	for f in DirAccess.get_files_at(chars_dir):
		if f.ends_with(".json"):
			out.append(f.get_basename())
	out.sort()
	return out


## writes chars_dir/<name>.json (only there; a same name is replaced: it is the person being updated). Returns "" or why not.
func save_character(raw: String) -> String:
	var nm := clean_name(raw)
	if nm == "":
		m._say("name the character first: type a name in the box, then press Save")
		return "no name"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(chars_dir))
	var d := {"version": 1}
	for k in pr:
		d[k] = snappedf(float(pr[k]), 0.0001)
	var f := FileAccess.open(_path(nm), FileAccess.WRITE)
	if f == null:
		m._say("could not write the character: check that user://characters is writable, then try Save again")
		return "write failed"
	f.store_string(JSON.stringify(d, "	"))
	f.close()
	m._say("saved character '%s'; click its name in the list to put it back on the body" % nm)
	refresh_list()
	return ""


## the sliders of a saved character, or {} when the file is missing / unreadable
func read_character(nm: String) -> Dictionary:
	if not FileAccess.file_exists(_path(nm)):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(_path(nm)))
	if not d is Dictionary:
		return {}
	var out := BodyModel.DEFAULT.duplicate()
	for k in out:
		if d.has(k):
			out[k] = float(d[k])
	return out


## puts a saved character on the body: ONE undo step
func apply_character(nm: String) -> bool:
	var c := read_character(nm)
	if c.is_empty():
		m._say("the character '%s' could not be read: pick another one from the list, or save it again" % nm)
		return false
	begin.emit()
	pr = c
	_set_sliders()
	_show()
	commit.emit(BodyModel.body_for(pr))
	return true


func delete_character(nm: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_path(nm)))   # only a character file of ours
	refresh_list()


func refresh_list() -> void:
	if list_box == null:
		return
	for c in list_box.get_children():
		list_box.remove_child(c)
		c.queue_free()
	var names := character_names()
	if names.is_empty():
		list_box.add_child(m._label("none yet: set the sliders, name the person, press Save", 11, "text:0.5", true))
	for nm in names:
		var r := HBoxContainer.new()
		r.name = "char_" + String(nm)
		var c := read_character(nm)
		var b: Button = m._button(String(nm), apply_character.bind(nm), "put '%s' on the body (%s percentile, %s; Ctrl+Z undoes)" % [nm, BodyModel.ordinal(c.get("stat", 50.0)), "man" if float(c.get("blend", 1.0)) >= 0.5 else "woman"])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		r.add_child(b)
		var x: Button = m._button("x", delete_character.bind(nm), "delete the saved character '%s' (the file in user://characters only)" % nm)
		r.add_child(x)
		list_box.add_child(r)
