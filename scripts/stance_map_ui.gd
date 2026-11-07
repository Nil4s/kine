## stance_map_ui.gd - N038 panel: "Stance strength map". The polar picture (PolarView) of the push each direction takes before a step, from the
## pose at the playhead (scripts/stance_map.gd). Forward is up, his left is to the left. Reads only: no undo step.
class_name StanceMapUI
extends RefCounted

var m: Node
var mp: Dictionary = {}
var polar: PolarView


func _init(main: Node) -> void:
	m = main
	polar = PolarView.new()


func commands(add: Callable) -> void:
	add.call("Stance strength map", "", show, "stance strength map push force direction before a step capture point support polygon feet balance polar",
		false, "a polar picture of how hard a push this stance takes from each direction before a step is needed (from the feet and the capture point)")


func compute() -> void:
	m._actors_sync()
	var B := DistanceKeeper.new_body()
	(m.S as Scene).apply(B, float(m.playhead))
	mp = StanceMap.compute(B)
	polar.set_map(mp)


func show() -> void:
	compute()
	var L: VBoxContainer = m.ui_find_list
	for c in L.get_children():
		L.remove_child(c)
		if c != polar:
			c.queue_free()
	var head := HBoxContainer.new()
	L.add_child(head)
	var title: Label = m._label("STANCE STRENGTH MAP", 14, "heading", true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(m._button("Close", m._close_findings))
	if not bool(mp.get("ok", false)):
		L.add_child(m._label(String(mp.get("why", "")), 13, "warn", true))
	else:
		L.add_child(m._label("The impulse this stance takes before a step is needed, by push direction (forward is up). The capture point leaves the feet when speed = omega0 x edge distance (Hof 2005); force = impulse over %.1f s. Weakest %.0f N s, strongest %.0f N s." % [StanceMap.PUSH_T, StanceMap.lowest(mp), StanceMap.highest(mp)], 13, "text:0.6", true))
		L.add_child(polar)
	m.ui_find.visible = true
