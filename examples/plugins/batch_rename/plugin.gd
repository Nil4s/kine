## EXAMPLE PLUGIN: rename every card "<prefix> NN". The prefix comes from get_setting (default "Take").
extends RefCounted


func command(api, id: String) -> bool:
	var prefix := String(api.get_setting("prefix", "Take"))
	var n: int = api.card_count()
	for i in n:
		var r: Dictionary = api.rename_card(i, "%s %02d" % [prefix, i + 1])
		if not r["ok"]:
			api.fail(String(r["why"]))
			return false
	api.log("renamed %d cards" % n)
	return true
