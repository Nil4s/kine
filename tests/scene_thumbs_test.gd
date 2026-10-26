## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/scene_thumbs_test.gd     (ROADMAP 51; a window)
## SCENE THUMBNAILS (scripts/scene_thumbs.gd) in the scene list on the real poser:
##   pictures    opening the list: every listed scene has a picture within 3 s, not blank (pixel variance > 0)
##   first frame the first frame after the list opens takes < 50 ms (measured, cache cleared first)
##   cache       a second open loads every picture from user://thumbs with NO draws (counted)
##   changed     a user:// copy of combo3 whose bytes change is drawn again, and only that one (counted)
## Screenshot of the open list: C:/Users/Nick/.claude/jobs/9afc22db/tmp/thumbs.png
extends SceneTree

const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/thumbs.png"
const COPY_DIR := "user://zz_thumbs_test"

var fails := 0
var m: Node
var th: SceneThumbs


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## the listed scene files, in the list's order
func listed() -> Array:
	var out := []
	for i in m.ui_scenes.item_count:
		if not String(m.ui_scenes.get_item_metadata(i)).begins_with("#"):   # the Drafts group's rows are not scenes (no picture)
			out.append(m.ui_scenes.get_item_metadata(i))
	return out


## the picture the list shows for each scene file (null = none yet)
func icons() -> Dictionary:
	var pop: PopupMenu = m.ui_scenes.get_popup()
	var out := {}
	for i in m.ui_scenes.item_count:
		if not String(m.ui_scenes.get_item_metadata(i)).begins_with("#"):
			out[m.ui_scenes.get_item_metadata(i)] = pop.get_item_icon(i)
	return out


func all_pictures() -> bool:
	for p in icons():
		if icons()[p] == null:
			return false
	return true


## pixel variance of a picture's brightness: 0 = one flat colour (blank)
func variance(t: Texture2D) -> float:
	var img := t.get_image()
	var n := img.get_width() * img.get_height()
	var s := 0.0
	var s2 := 0.0
	for y in img.get_height():
		for x in img.get_width():
			var v := img.get_pixel(x, y).get_luminance()
			s += v
			s2 += v * v
	return s2 / n - (s / n) * (s / n)


func wait_pictures(secs: float) -> float:
	var t0 := Time.get_ticks_msec()
	while not all_pictures() and Time.get_ticks_msec() - t0 < secs * 1000.0:
		await process_frame
	return (Time.get_ticks_msec() - t0) / 1000.0


## the list's vertical scroll bar (null when it has none)
func _vscroll(pop: PopupMenu) -> VScrollBar:
	var l := pop.find_children("*", "VScrollBar", true, false)
	return l[0] as VScrollBar if not l.is_empty() else null


func clear_cache() -> void:
	var d := DirAccess.open("user://thumbs")
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://thumbs/" + f))


func _init() -> void:
	clear_cache()
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for _i in 3:
		await process_frame
	th = m.thumbs
	var files := listed()
	ok(th != null and files.size() >= 11, "the scene list has %d scenes (the 11 shipped ones are listed)" % files.size())
	await th.settle()
	var r0 := th.renders

	# OPEN 1: the cache is empty, so every picture is drawn after the list opens
	var t0 := Time.get_ticks_usec()
	m.ui_scenes.show_popup()
	await process_frame
	var first_ms := (Time.get_ticks_usec() - t0) / 1000.0
	ok(first_ms < 50.0, "first frame after the list opens: %.1f ms (< 50)" % first_ms)
	var secs := await wait_pictures(3.0)
	ok(all_pictures(), "every listed scene has a picture within 3 s (all %d, in %.2f s)" % [files.size(), secs])
	var blank := []
	for p in icons():
		if icons()[p] == null or variance(icons()[p]) <= 0.0:
			blank.append(p.get_file())
	ok(blank.is_empty(), "no blank picture (pixel variance > 0) %s" % [blank])
	var drawn := th.renders - r0
	ok(drawn == files.size(), "first open drew %d pictures (one per scene)" % drawn)
	var ms := th.render_ms
	var avg := 0.0
	for x in ms:
		avg += x
	print("     draw time: %d draws, mean %.1f ms, max %.1f ms" % [ms.size(), avg / maxf(1.0, ms.size()), ms.max() if not ms.is_empty() else 0.0])
	for _i in 2:
		await process_frame
	root.get_texture().get_image().save_png(SHOT)

	# CACHE: close the list, drop the pictures in memory, open again: all read from disk, no draw
	m.ui_scenes.get_popup().hide()
	await process_frame
	th.forget()
	var r1 := th.renders
	var h1 := th.disk_hits
	m.ui_scenes.show_popup()
	await process_frame
	await wait_pictures(3.0)
	await th.settle()   # the cache reads are lazy now (a few per frame after the list is up); the old icons still show meanwhile
	ok(all_pictures(), "second open: every picture is back")
	ok(th.renders - r1 == 0, "second open drew %d pictures (0 = all from the cache)" % (th.renders - r1))
	ok(th.disk_hits - h1 == files.size(), "second open read %d pictures from user://thumbs" % (th.disk_hits - h1))
	m.ui_scenes.get_popup().hide()
	await process_frame

	# CHANGED: a user:// copy of combo3, its bytes changed -> drawn again, and only that one
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(COPY_DIR))
	var src := FileAccess.get_file_as_string("res://scenes/combo3.json")
	var copy := COPY_DIR + "/combo3_copy.json"
	var f := FileAccess.open(copy, FileAccess.WRITE)
	f.store_string(src)
	f.close()
	th.request(copy)
	await th.settle()
	var c0 := th.renders
	ok(th.picture(copy) != null, "the user:// copy has a picture")
	var sha_before := FileAccess.get_sha256(copy)
	f = FileAccess.open(copy, FileAccess.WRITE)
	f.store_string(src + "\n")
	f.close()
	ok(FileAccess.get_sha256(copy) != sha_before, "the copy's bytes changed (new hash)")
	th.request(copy)
	for p in files:
		th.request(p)
	await th.settle()
	var c1 := th.renders - c0
	ok(c1 == 1 and th.picture(copy) != null, "changed copy: %d draw(s) (1 = that copy only)" % c1)
	ok(FileAccess.file_exists(SceneThumbs.cache_path(FileAccess.get_sha256(copy))), "its new picture is cached under its new hash")

	# SMALL WINDOW: the list is never taller than the window, scrolls to every scene, and opens on the open scene
	m.ui_scenes.get_popup().hide()
	m.get_window().size = Vector2i(1024, 600)
	for _i in 4:
		await process_frame
	# the Drafts group is expanded here: the list must be long enough to scroll (collapsed, the saved scenes fit)
	m._drafts_open = true
	m._fill_scene_list()
	m._show_open_scene()
	files = listed()
	var pop: PopupMenu = m.ui_scenes.get_popup()
	m.ui_scenes.select(m.ui_scenes.item_count - 1)
	m.ui_scenes.show_popup()
	for _i in 4:
		await process_frame
	var vp := Vector2(root.get_visible_rect().size)
	var r := Rect2(Vector2(pop.position), Vector2(pop.size))
	ok(r.position.x >= 0 and r.position.y >= 0 and r.end.x <= vp.x and r.end.y <= vp.y,
		"small window %s: the list %s lies inside it" % [vp, r])
	var sb := _vscroll(pop)
	ok(sb != null and sb.max_value > sb.page, "the list scrolls (content %.0f, shown %.0f)" % [sb.max_value if sb else 0.0, sb.page if sb else 0.0])
	ok(sb != null and sb.value > 0.0, "opened with the last (open) scene in view (scroll %.0f)" % (sb.value if sb else 0.0))
	sb.value = 0.0
	await process_frame
	pop.scroll_to_item(m.ui_scenes.item_count - 1)
	for _i in 3:
		await process_frame
	ok(sb.value > 0.0, "the last scene is reachable: scrolled down to it (value %.0f of max %.0f)" % [sb.value, sb.max_value])
	sb.value = sb.max_value
	await process_frame
	ok(sb.value + sb.page >= sb.max_value - 0.5, "...and the list's end (the last scene) is in view at the bottom (value %.0f, page %.0f)" % [sb.value, sb.page])
	pop.hide()
	m.get_window().size = Vector2i(1152, 648)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(copy))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(COPY_DIR))
	print("SCENE THUMBS %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
