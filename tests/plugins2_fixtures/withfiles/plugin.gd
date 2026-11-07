extends RefCounted
var last := {}


func command(api, id: String) -> bool:
	last = {"ok": api.write_file("exports/w.txt", "x"), "scenes": api.write_file("scenes/w/deep.txt", "x"),
		"up": api.write_file("../w.txt", "x"), "up2": api.write_file("exports/../../w.txt", "x"),
		"abs": api.write_file("C:/Temp/kine_plugin_escape_w.txt", "x"), "slash": api.write_file("/tmp/kine_plugin_escape_w.txt", "x"),
		"back": api.write_file("exports\\..\\w.txt", "x"), "scripts": api.write_file("scripts/main.gd", "x"),
		"root": api.write_file("w.txt", "x"), "res": api.write_file("res://w.txt", "x"), "user": api.write_file("user://w.txt", "x"),
		"read_up": api.read_file("../state.json"), "read_ok": api.read_file("exports/w.txt"),
		"export": api.export("bvh")}
	return true
