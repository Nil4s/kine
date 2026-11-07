extends RefCounted
## a planted infinite loop that keeps editing through the api (it ends only when the test makes the stop file)


func command(api, id: String) -> bool:
	var i := 0
	while true:
		i += 1
		api.set_joint(0, "head", Vector3(i % 90, 0, 0))
		if FileAccess.file_exists("user://zz_plugins2_stop"):
			break
	return true
