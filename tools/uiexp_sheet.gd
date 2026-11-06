extends SceneTree
## godot --path . -s tools/uiexp_sheet.gd : the icon contact sheet docs/uiexp/icons.png (each icon beside its name, dark and light cells)
## and a duplicate check: two icons whose 48 px rasters are identical are reported (exit 1).

func _init() -> void:
	var ids: Array = UiExpIconList.IDS
	var cols := 6
	var sub := SubViewport.new()
	sub.size = Vector2i(cols * 250, int(ceil(ids.size() / float(cols))) * 64 + 8)
	sub.transparent_bg = false
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sub)
	var bg := ColorRect.new()
	bg.color = Color(0.086, 0.09, 0.106)
	bg.size = Vector2(sub.size)
	sub.add_child(bg)
	var g := GridContainer.new()
	g.columns = cols
	g.position = Vector2(4, 4)
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	sub.add_child(g)
	var seen := {}
	var dups := []
	var blank := []
	for id in ids:
		var h := HBoxContainer.new()
		h.custom_minimum_size = Vector2(240, 58)
		var pc := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.165, 0.176, 0.212)
		sb.set_corner_radius_all(6)
		sb.set_content_margin_all(4)
		pc.add_theme_stylebox_override("panel", sb)
		var tr := TextureRect.new()
		tr.texture = UiExpIcons.tex(id, 48)
		tr.custom_minimum_size = Vector2(48, 48)
		pc.add_child(tr)
		h.add_child(pc)
		var l := Label.new()
		l.text = "  " + id
		l.add_theme_font_size_override("font_size", 15)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(l)
		g.add_child(h)
		var img := (tr.texture as Texture2D).get_image() if tr.texture != null else null
		if img == null:
			blank.append(id)
			continue
		var lit := 0
		for y in img.get_height():
			for x in img.get_width():
				if img.get_pixel(x, y).a > 0.3:
					lit += 1
		if lit < 40:
			blank.append(id)
		var hsh := str(hash(img.get_data()))
		if seen.has(hsh):
			dups.append([id, seen[hsh]])
		seen[hsh] = id
	await process_frame
	await process_frame
	await process_frame
	DirAccess.make_dir_recursive_absolute("docs/uiexp")
	sub.get_texture().get_image().save_png("docs/uiexp/icons.png")
	print("icons %d, blank %s, duplicates %s" % [ids.size(), str(blank), str(dups)])
	quit(1 if (not blank.is_empty() or not dups.is_empty()) else 0)
