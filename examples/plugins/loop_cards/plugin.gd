## EXAMPLE PLUGIN: close the loop. Adds a card at the end that copies card 0, so the animation ends where it began.
extends RefCounted


func command(api, id: String) -> bool:
	if api.card_count() < 2:
		api.log("a loop needs at least 2 cards: clip a pose (Enter) first")
		return true
	var r: Dictionary = api.add_card("Loop", 0)
	if not r["ok"]:
		api.fail(String(r["why"]))
		return false
	api.log("added card %d, a copy of card 0" % (int(r["index"]) + 1))
	return true
