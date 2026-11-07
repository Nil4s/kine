## ARENA FIT panel (ROADMAP I1; the maths: scripts/arena_fit.gd). With two or more fighters: a ring of the size set in the panel (3 m to 20 m a
## side, centred between the fighters where they start), and for each fighter the wall or corner he is pushed toward through the fight and the
## steps of room left. Read only: nothing in the scene changes.
class_name ArenaFitUI
extends RefCounted

var m: Node
var size := 3.0
var rep: Dictionary = {}


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Fit the ring", "", show, "arena ring room fit fighters wall corner steps space size fight fits",
		false, "with two fighters: does the fight fit a ring of the size you set (3 m to 20 m): the wall or corner each fighter is pushed toward and the steps of room left")


func show() -> void:
	m._actors_sync()
	if m.actors_rt.size() < 2:
		m._say("the ring check needs two fighters: 'Actor: add a second fighter' first")
		return
	compute()


func compute() -> void:
	m._actors_sync()
	var scenes := []
	var xfs := []
	for a in m.actors_rt:
		scenes.append(a["S"])
		xfs.append(a["xf"])
	rep = ArenaFit.analyze(scenes, xfs, size, (scenes[0] as Scene).fps)
	_panel()


func _line(f: Dictionary) -> String:
	var who := "fighter %d" % (int(f["i"]) + 1)
	var wall := String(f["corner"]) if String(f["corner"]).contains(" ") else String(f["wall"])
	if float(f["room"]) < 0.0:
		return "%s is pushed into the %s %s: %s past it, at %.2f s" % [who, wall, "corner" if wall.contains(" ") else "wall", Units.metres(float(f["over"]), 2), float(f["t"])]
	return "%s has %s to the %s wall = %d steps, at its tightest (%.2f s)" % [who, Units.metres(float(f["room"]), 2), wall, int(f["steps"]), float(f["t"])]


func _panel() -> void:
	var L: VBoxContainer = m.ui_find_list
	for c in L.get_children():
		L.remove_child(c)
		c.queue_free()
	var head := HBoxContainer.new()
	L.add_child(head)
	var fits: bool = bool(rep.get("fits", true))
	var title: Label = m._label("ARENA FIT  -  %s" % String(rep.get("msg", "")), 14, "heading" if fits else "warn", true)
	title.name = "arena_title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.custom_minimum_size = Vector2(380, 0)
	head.add_child(title)
	head.add_child(m._button("Close", _close))
	var row := HBoxContainer.new()
	L.add_child(row)
	row.add_child(m._label("Ring side", 13, "text:0.6"))
	var sp := SpinBox.new()
	sp.name = "arena_size"
	var fk := 1.0 if Units.unit == "cm" else float(Units.M_PER[Units.unit])   # metres in cm / m mode, the unit itself in inches
	sp.min_value = 3.0 / fk
	sp.max_value = 20.0 / fk
	sp.step = 0.5 / fk
	sp.suffix = " " + ("m" if Units.unit == "cm" else Units.unit)
	sp.value = size / fk
	sp.tooltip_text = "the ring's side in metres; the fight is checked again at each change"
	sp.value_changed.connect(_size_changed)
	row.add_child(sp)
	L.add_child(m._label("The ring is centred between the fighters where they start. Each fighter's farthest reach (body and weapon, the volume's radius included) is measured through the whole fight. One walking step is 0.7 m.", 13, "text:0.6", true))
	for f in rep.get("fighters", []):
		var lb: Label = m._label(_line(f), 13, "fail" if float(f["room"]) < 0.0 else "text:0.85", true)
		lb.name = "arena_f%d" % (int(f["i"]) + 1)
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lb.custom_minimum_size = Vector2(380, 0)
		L.add_child(lb)
	(m.ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(420, 220.0)
	m.ui_find.visible = true
	m._say("arena fit: " + String(rep.get("msg", "")))


func _size_changed(v: float) -> void:
	size = v * (1.0 if Units.unit == "cm" else float(Units.M_PER[Units.unit]))
	compute()


func _close() -> void:
	rep = {}
	m._close_findings()
