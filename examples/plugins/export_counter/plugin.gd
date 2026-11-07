## EXAMPLE PLUGIN: export the scene as BVH (permission "export") and keep a count in a setting. It edits nothing, so it is no undo step.
extends RefCounted


func command(api, id: String) -> bool:
	var r: Dictionary = api.export("bvh")
	if not r["ok"]:
		api.fail(String(r["why"]))
		return false
	var n := int(api.get_setting("exports", 0)) + 1
	api.set_setting("exports", n)
	api.log("export %d: %d bytes written to %s" % [n, int(r["bytes"]), String(r["path"]).get_file()])
	return true
