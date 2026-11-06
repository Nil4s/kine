extends SceneTree
## godot ... -s tools/uiexp_fns.gd : writes docs/uiexp/functions_old.json = every function the compact ribbon / Assembly panel exposes at
## 1280x720 (the layout the rail does not touch): a Part tool button (visible, or under its caption / More) and an Assembly button.
func _init() -> void:
	var d := UiExpDrive.new()
	await d.boot(self)
	await d.start_building()
	var out := {"part": [], "asm": []}
	await d.screen("part")
	await d.set_size(Vector2i(1280, 720))
	var m = d.m
	var pu: PartUI = m.bld.part
	var labs := pu.tool_btns.keys()
	labs.append("Finish sketch")
	for l in labs:
		var b: Button = pu.finish_btn if l == "Finish sketch" else pu.tool_btns[l]
		var vis: bool = b.is_visible_in_tree()
		for pair in m.ui_caps.get("BUILD", []):
			if (pair[1] as Array).has(b):
				vis = vis or (pair[0] as Control).is_visible_in_tree()
		vis = vis or m._more_tools.has(b)
		print("PART %s %s" % [l, vis])
		if vis:
			(out["part"] as Array).append(l)
	await d.screen("assembly")
	await d.set_size(Vector2i(1280, 720))
	for l in UiExpShell.ASM_NAMES:
		var b := m.bld.asm.panel.find_child(UiExpShell.ASM_NAMES[l], true, false) as Button
		var vis: bool = b != null and b.is_visible_in_tree()
		print("ASM %s %s" % [l, vis])
		if vis:
			(out["asm"] as Array).append(l)
	var f := FileAccess.open("docs/uiexp/functions_old.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	quit(0)
