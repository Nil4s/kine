extends RefCounted
var last := {}


func command(api, id: String) -> bool:
	last = {"inside": api.write_file("exports/n.txt", "x"), "up": api.write_file("../n.txt", "x"),
		"abs": api.write_file("C:/Temp/kine_plugin_escape_n.txt", "x"), "read": api.read_file("exports/n.txt"),
		"export": api.export("bvh"), "tool": api.run_tool("sel=head")}
	return true
