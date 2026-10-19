## EXAMPLE PLUGIN (ROADMAP 100): mirror every card's pose left <-> right, as ONE undo step.
## It reads the cards through api.cards() (copies) and proposes each change through api.set_joint(), which clamps to
## the joint limits. The rule is the app's own for pairs (Body.mirror_side): the twin takes (bend, side, -twist);
## a middle joint (spine, neck, head) takes (bend, -side, -twist) as the whole-body mirror does.
## A command returns true when it is done (docs/PLUGINS.md): anything else disables the plugin.
extends RefCounted


func command(api, id: String) -> bool:
	if id == "mirror_all":
		return mirror_all(api)
	api.fail("there is no command '%s' in this plugin: the manifest lists mirror_all" % id)
	return false


func mirror_all(api) -> bool:
	var cards: Array = api.cards()
	if cards.is_empty():
		api.log("the scene has no cards to mirror: clip a pose first (Enter), then run this again")
		return true
	var changed := 0
	for i in cards.size():
		var joints: Dictionary = cards[i]["joints"]
		for j in joints:
			var r: Dictionary = api.set_joint(i, String(j), mirrored(String(j), joints))
			if not r["ok"]:
				api.fail(String(r["why"]))
				return false
		changed += 1
	api.log("mirrored %d card%s left <-> right" % [changed, "" if changed == 1 else "s"])
	return true


## the value joint j takes after the mirror, read from the card's own joints (before the change)
func mirrored(j: String, joints: Dictionary) -> Vector3:
	var twin := twin_of(j)
	var src: Vector3 = joints.get(twin, Vector3.ZERO)
	if twin == j:
		return Vector3(src.x, -src.y, -src.z)
	return Vector3(src.x, src.y, -src.z)


func twin_of(j: String) -> String:
	if j.ends_with("_l"):
		return j.substr(0, j.length() - 2) + "_r"
	if j.ends_with("_r"):
		return j.substr(0, j.length() - 2) + "_l"
	return j
