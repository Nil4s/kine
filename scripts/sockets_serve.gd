## sockets_serve.gd - SERVE `sockets` (agent_tools.gd; the CLI serve, the MCP server and the AI box share it) (N089).
##   {preset?: a Proportions preset (male_50), mass?: kg}. Replies {"preset", "stature", "sockets": [{"name", "parent", "local": [x,y,z] (m, in the
##   parent bone's rest frame), "world": [x,y,z] (m, skeleton space)}]}: the five engine sockets placed from the anatomy of that body (scripts/sockets.gd).
class_name SocketsServe
extends RefCounted


static func serve(_m: Node, p: Dictionary) -> Dictionary:
	var pname := String(p.get("preset", "male_50"))
	if not Proportions.PRESETS.has(pname):
		return {"ok": false, "error": "preset is one of %s" % str(Proportions.PRESETS.keys())}
	var body := Proportions.preset(pname)
	if p.has("mass"):
		body["mass"] = float(p["mass"])
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.set_proportions(body)
	var man := GltfExport._mannequin(true)
	var sk: Skeleton3D = man.find_children("*", "Skeleton3D", true, false)[0]
	Proportions.bake_mannequin(man, sk, B)
	var sock := Sockets.compute(man, sk)
	var out := []
	for n in Sockets.NAMES:
		var o: Vector3 = (sock[n]["local"] as Transform3D).origin
		var w := Sockets.world(sk, sock[n])
		out.append({"name": n, "parent": sock[n]["parent"], "local": [o.x, o.y, o.z], "world": [w.x, w.y, w.z]})
	man.free()
	return {"ok": true, "result": {"preset": pname, "stature": float(body["stature"]), "sockets": out}}
