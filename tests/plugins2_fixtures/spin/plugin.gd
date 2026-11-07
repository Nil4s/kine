extends RefCounted
## a planted infinite loop (it ends only when the test makes the stop file, at the very end of the suite)


func command(api, id: String) -> bool:
	api.set_joint(0, "head", Vector3(44, 0, 0))
	var i := 0
	while true:
		i += 1
		if i % 200000 == 0 and FileAccess.file_exists("user://zz_plugins2_stop"):
			break
	return true
