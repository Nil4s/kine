## godot --path . -s tests/silsheet_test.gd     (the silhouette sheet, ROADMAP_400 K26; needs a window)
## BARS (written before measuring):
##  1 combo3's sheet has ONE tile per card (12), the picture has the size columns x rows of tiles + gutters, and the PNG is in
##    user://silhouettes/<scene>_sheet.png (and reads back at that size)
##  2 PLACEMENT: every tile's black pixels are only inside that tile (none in the gutters), each tile has > 2 % black (the body is
##    drawn), the figure's box does not touch the tile's edge (not cropped) and its centre is in the middle half of the tile
##  3 a T-pose has more negative-space regions than a pose with the arms crossed on the chest (both built from joint angles), the
##    crossed pose is flagged "arms inside the torso" and the T-pose is not
##  4 nothing in scenes/ is written (every file's size + hash is the same after), and the scene in memory, the playhead, the
##    shading, the figure's materials and layers and the undo depth are what they were
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func scenes_digest() -> String:
	var out := []
	var stack := ["res://scenes"]
	while not stack.is_empty():
		var d: String = stack.pop_back()
		for f in DirAccess.get_files_at(d):
			out.append("%s/%s:%s" % [d, f, FileAccess.get_sha256("%s/%s" % [d, f])])
		for s in DirAccess.get_directories_at(d):
			stack.append("%s/%s" % [d, s])
	out.sort()
	return "\n".join(out).sha256_text()


func pose_with(angs: Dictionary) -> Dictionary:
	for j in m.B.ang:
		m.B.ang[j] = Vector3.ZERO
	for j in angs:
		m.B.ang[j] = angs[j]
	m.B.fk()
	return m.B.to_dict()


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(2)
	root.get_window().size = Vector2i(1600, 900)
	await idle(6)
	var digest0 := scenes_digest()
	m._load_scene("res://scenes/combo3.json")
	m._page_set("ANIMATE", false)
	await idle(3)
	var json0 := JSON.stringify(m.S.to_dict(m.B), "", true)
	var play0: float = m.playhead
	var shade0: String = m.shading.mode
	var undo0: int = m.undo.size()
	m._refresh()   # the weapon's drawn pieces (WeaponMesh) are built on a refresh: snapshot the figure as it is drawn, all of it
	var mats0 := []
	for mi in Shading.bodies(m):
		mats0.append([mi.material_override, mi.layers, mi.material_overlay])

	# 1 + 2
	m._silsheet()
	while m.sil_last.is_empty():
		await process_frame
	await idle(3)
	var res: Dictionary = m.sil_last
	var cols: int = res["cols"]
	var n: int = res["tiles"].size()
	var img: Image = res["image"]
	var g := SilSheet.GUTTER
	var T := SilSheet.TILE
	var rows := int(ceil(float(n) / float(cols)))
	var wantw := cols * (T.x + g) + g
	var wanth := rows * (T.y + g) + g
	var back := Image.load_from_file(ProjectSettings.globalize_path(res["path"]))
	ok(n == 12 and n == m.S.cards.size() and res["results"].size() == 12, "one tile per card: %d tiles for %d cards" % [n, m.S.cards.size()])
	ok(img.get_width() == wantw and img.get_height() == wanth and back != null and back.get_width() == wantw and String(res["path"]) == "user://silhouettes/combo3_sheet.png",
		"the sheet is %d x %d (%d x %d tiles) and %s reads back at that size" % [img.get_width(), img.get_height(), cols, rows, res["path"]])
	var mask := SilSheet.mask_of(img)
	var in_tiles := 0
	var total := 0
	for v in mask:
		total += v
	var worst_share := 1.0
	var edge_ok := true
	var centre_ok := true
	var line := []
	for k in n:
		var ox := g + (k % cols) * (T.x + g)
		var oy := g + (k / cols) * (T.y + g)
		var cnt := 0
		var x0 := T.x
		var x1 := -1
		var y0 := T.y
		var y1 := -1
		for y in T.y:
			for x in T.x:
				if mask[(oy + y) * img.get_width() + ox + x] == 1:
					cnt += 1
					x0 = mini(x0, x)
					x1 = maxi(x1, x)
					y0 = mini(y0, y)
					y1 = maxi(y1, y)
		in_tiles += cnt
		var share := float(cnt) / float(T.x * T.y)
		worst_share = minf(worst_share, share)
		if not (cnt > 0 and x0 > 1 and y0 > 1 and x1 < T.x - 2 and y1 < T.y - 2):
			print("     edge: tile %d box %d,%d..%d,%d" % [k, x0, y0, x1, y1])
		if cnt == 0 or x0 <= 1 or y0 <= 1 or x1 >= T.x - 2 or y1 >= T.y - 2:
			edge_ok = false
		var cx := 0.5 * float(x0 + x1) / float(T.x)
		var cy := 0.5 * float(y0 + y1) / float(T.y)
		if cx < 0.25 or cx > 0.75 or cy < 0.25 or cy > 0.75:
			centre_ok = false
		var r: Dictionary = res["results"][k]
		line.append("%s %.0f%%/%d" % [r["name"], 100.0 * share, r["regions"]])
	print("     tile black share / negative-space regions: ", ", ".join(line))
	ok(in_tiles == total and total > 0, "all %d black pixels are inside tiles (0 in the gutters)" % total)
	ok(worst_share > 0.02, "every tile is > 2 %% black (smallest %.1f %%)" % (100.0 * worst_share))
	ok(edge_ok and centre_ok, "placement: every figure is whole inside its tile (no edge contact) and centred (box centre in the middle half)")
	var dlg := m.get_node_or_null("silsheet_dialog") as AcceptDialog
	ok(dlg != null and dlg.visible, "the popup is open with the sheet")
	root.get_viewport().get_texture().get_image().save_png("user://silsheet_shot.png")

	# 3 a T-pose and arms crossed on the chest, both built here
	m.B.wep_on = false
	var tpose := pose_with({})
	m.B.wep_on = false
	var crossed := pose_with({"upperarm_l": Vector3(60, -75, 60), "lowerarm_l": Vector3(75, 30, 0), "upperarm_r": Vector3(60, -75, -60), "lowerarm_r": Vector3(75, 30, 0)})
	var hl: Vector3 = m.B.P["hand_l"]
	var hr: Vector3 = m.B.P["hand_r"]
	ok(hl.x < 0.0 and hr.x > 0.0, "the crossed pose crosses: left hand at x %.2f, right hand at x %.2f" % [hl.x, hr.x])
	dlg.hide()
	m.S.cards = [{"arrive_s": 0.0, "hold": 0.3, "leave_s": 0.3, "move": -1.0, "name": "T", "pose": tpose, "steps": {}}, {"arrive_s": 0.0, "hold": 0.3, "leave_s": 0.3, "move": -1.0, "name": "crossed", "pose": crossed, "steps": {}}]
	var two: Dictionary = await SilSheet.make(m, false)
	(two["image"] as Image).save_png("user://silsheet_two.png")
	var rt: Dictionary = two["results"][0]
	var rc: Dictionary = two["results"][1]
	print("     T: fill %.2f regions %d holes %d hidden %s | crossed: fill %.2f regions %d holes %d hidden %s" % [rt["fill"], rt["regions"], rt["holes"], rt["arms_hidden"], rc["fill"], rc["regions"], rc["holes"], rc["arms_hidden"]])
	ok(rt["regions"] > rc["regions"], "T-pose has more negative-space regions than arms crossed (%d vs %d)" % [rt["regions"], rc["regions"]])
	ok(rc["arms_hidden"] and not rt["arms_hidden"], "arms crossed is flagged arms-inside-torso, the T-pose is not")

	# 4 nothing written to scenes/, nothing left changed
	m._load_scene("res://scenes/combo3.json")
	await idle(3)
	ok(scenes_digest() == digest0, "scenes/ is byte for byte what it was (no file written)")
	ok(JSON.stringify(m.S.to_dict(m.B), "", true) == json0 and is_equal_approx(m.playhead, play0) and m.shading.mode == shade0 and m.undo.size() == undo0,
		"the scene, playhead, shading and undo depth are as before")
	var same := true
	var k2 := 0
	for mi in Shading.bodies(m):
		if mi.material_override != mats0[k2][0] or mi.layers != mats0[k2][1] or mi.material_overlay != mats0[k2][2]:
			same = false
		k2 += 1
	ok(same, "the figure's materials and layers are put back")
	print("silsheet: %d failures" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
