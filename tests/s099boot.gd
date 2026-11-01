extends SceneTree
## helper of tests/s099_test.gd (a fresh process = a restart): boots the app, writes the language it came up in to the file named by KINE_BOOT_OUT


func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 8:
		await process_frame
	var b := root.find_child("tab_animate", true, false) as Button
	var f := FileAccess.open(OS.get_environment("KINE_BOOT_OUT"), FileAccess.WRITE)
	f.store_line("%s|%s|%s" % [TranslationServer.get_locale(), b.text if b != null else "?", b.atr(b.text) if b != null else "?"])
	f.close()
	quit()
