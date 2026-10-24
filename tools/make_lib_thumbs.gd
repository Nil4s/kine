extends SceneTree
## PRE-RENDERED ARMOUR PICTURES (w4-thumbs). Renders the object library's armour tiles (the plates on the default body) into
## res://data/thumbs/armour/<id>_<hash16>_128.png, so the panel shows them at once; the name's hash is of the plate builder's
## version and constants and the default body's rest vertices (LibraryThumbs.shipped_path). A changed builder or body gives
## a new name: the panel then renders that plate live, until this tool is run again.
##   godot --path . -s tools/make_lib_thumbs.gd        (a WINDOW is needed: a renderer; not --headless)
## Writes only res://data/thumbs/armour/. Re-run after a change to ArmourFromBody or the default body, then commit the PNGs.

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 6:
		await process_frame
	m._new_scene()
	m._library_toggle()
	var lib = m.ui_library
	for i in 3:
		await process_frame
	var out_dir := ProjectSettings.globalize_path("res://data/thumbs/armour")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var n := 0
	for it in lib.items:
		if String(it["how"]) != "armour":
			continue
		var src: Dictionary = lib.thumb_source(it)
		var node: Node3D = (src["build"] as Callable).call()
		var img: Image = await lib.thumbs.draw_node(node, LibraryThumbs.SIZE)
		if img == null or img.is_empty():
			printerr("NO PICTURE for %s" % it["id"])
			quit(1)
			return
		var path := LibraryThumbs.shipped_path(String(it["id"]), String(src["spec"]))
		img.save_png(ProjectSettings.globalize_path(path))
		print("WROTE %s" % path)
		n += 1
	var f := FileAccess.open(ObjectLibrary.DEFAULT_BODY, FileAccess.WRITE)   # the default body's hash (ObjectLibrary.body_hash)
	f.store_string(ObjectLibrary.body_sig(m) + "|" + ObjectLibrary.body_hash(m, false))
	f.close()
	print("MAKE_LIB_THUMBS wrote %d armour pictures" % n)
	quit(0)
