extends SceneTree
## godot --headless --path . -s tools/ch2_parts_build.gd   : replay every clock part from its Part feature list and cache the triangles
func _init() -> void:
	for sp in ClockParts.specs():
		var t0 := Time.get_ticks_msec()
		var tr := ClockParts.triangles(sp)
		print("%-14s %6d tris-verts %6d ms  features %d" % [sp["id"], tr.size(), Time.get_ticks_msec() - t0, (sp["feats"] as Array).size()])
	quit()
