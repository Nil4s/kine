extends RefCounted


func command(api, id: String) -> bool:
	api.set_joint(0, "head", Vector3(33, 0, 0))
	api.add_card("Half")
	api.fail("stopped halfway on purpose: two edits were already made")
	return false
