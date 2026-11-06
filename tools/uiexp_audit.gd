extends SceneTree
## godot --position -30000,-30000 --path . -s tools/uiexp_audit.gd     (run with a temporary APPDATA, see tools/uiexp_audit.sh)
## UIEXP audit: every Expert screen (part / assembly / engineering) at 1920x1080, 1600x900, 1366x768, 1280x720: a screenshot and the
## UiExpProbe report. Env: UE_TAG (before / after), UE_OUT (default C:/Temp/claude/uiexp). Writes <out>/<tag>_<screen>_<w>x<h>.png and <out>/<tag>.json.


func _init() -> void:
	var tag := OS.get_environment("UE_TAG") if OS.get_environment("UE_TAG") != "" else "run"
	var out := OS.get_environment("UE_OUT") if OS.get_environment("UE_OUT") != "" else "C:/Temp/claude/uiexp"
	DirAccess.make_dir_recursive_absolute(out)
	var d := UiExpDrive.new()
	await d.boot(self)
	await d.start_building()
	var all := {}
	for sc in UiExpDrive.SCREENS:
		await d.screen(sc)
		for sz in UiExpDrive.SIZES:
			await d.set_size(sz)
			await d.idle(6)
			var vp := Rect2(Vector2.ZERO, Vector2(sz))
			var r := UiExpProbe.report(d.m, d.m.get_viewport().get_visible_rect())
			r["viewport"] = str(d.m.get_viewport().get_visible_rect().size)
			all["%s_%dx%d" % [sc, sz.x, sz.y]] = r
			root.get_texture().get_image().save_png("%s/%s_%s_%dx%d.png" % [out, tag, sc, sz.x, sz.y])
			print("%s %dx%d vp %s: controls %d interactive %d outside %d panels %d overlaps %d clipped %d small %d iconbad %d view %.2f" % [sc, sz.x, sz.y, r["viewport"], r["controls"], r["interactive"], (r["outside"] as Array).size(), r["panels"], (r["overlaps"] as Array).size(), (r["clipped"] as Array).size(), (r["small_fonts"] as Array).size(), (r["icon_bad"] as Array).size(), r["view_share"]])
	var f := FileAccess.open("%s/%s.json" % [out, tag], FileAccess.WRITE)
	f.store_string(JSON.stringify(all, "  "))
	f.close()
	quit(0)
