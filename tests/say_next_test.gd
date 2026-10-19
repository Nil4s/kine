## godot --path . -s tests/say_next_test.gd     (GATES S2; headless is fine)
## SAY WHAT NEXT: every message main.gd shows on its way OUT of an action (a _say right before a `return`: a refusal or
## a failure) names a next step the user can take: a verb from NEXT. Two of those exits are successes, listed in DONE
## with their reason. A new refusal with no way forward fails this test.
extends SceneTree

var fails := 0
const NEXT := ["pick", "click", "press", "open", "lock", "put", "add", "turn", "move", "type", "tick", "untick", "use",
	"select", "drag", "choose", "copy", "make", "free", "try", "give", "save", "close", "run"]
## exits that report something DONE (no next step is owed)
const DONE := {"fatigue at fitness %.2f": "reports the retime it just made (ROADMAP 39)", "the weapon slid in the hand": "reports the slide it just made", "second hand off the weapon": "reports the toggle it just made",
	"(in trash/ if you want it back)": "reports the delete it just made",
	"posed: %s%s": "reports the pose it just made (and where a limit stopped it)",
	"weight key at %s = %.2f": "reports the weight key it just changed (NA1)",
	"copied a card to %.2f s": "reports the copy it just made (NA0)",
	"body: %s, %.1f cm tall": "reports the proportions it just set (PR1)",
	# tonight's merges: these report what was just done (successes on the way out of a branch)
	"Auto-key: card %d takes the body": "reports the body it just put on the card (auto-key)",
	"all %d cards are on the floor now": "reports the snap it just made (floor snap; Ctrl+Z is named)",
	"the body is on the floor now (Ctrl+Z": "reports the snap it just made (floor snap; Ctrl+Z is named)",
	"_say(r[\"error\"])": "forwards PoseWords' error: each names the words to type instead (pose_words_test checks 5)"}


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/main.gd").split("\n")
	var exits := []
	for i in src.size() - 1:
		var nx := src[i + 1].strip_edges()
		if src[i].contains("_say(") and (nx == "return" or nx.begins_with("return ")):
			exits.append([i + 1, src[i].strip_edges()])
	var done := exits.filter(func(e): return DONE.keys().any(func(k): return e[1].contains(k)))
	var bad := []
	for e in exits:
		if e in done:
			continue
		var words := {}
		for w in RegEx.create_from_string("[a-z]+").search_all(e[1].to_lower()):
			words[w.get_string()] = true
		var has := NEXT.any(func(v): return words.has(v))
		if not has:
			bad.append("%d: %s" % [e[0], e[1].left(120)])
	print("     %d exits with a message, %d of them successes (%s)" % [exits.size(), done.size(), DONE.keys()])
	for b in bad:
		print("     no next step: " + b)
	ok(exits.size() > 15 and done.size() == DONE.size(), "the scan finds the exits (%d) and every listed success" % exits.size())
	ok(bad.is_empty(), "every refusal / failure names what to do next (%d without)" % bad.size())
	print("SAY NEXT TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
