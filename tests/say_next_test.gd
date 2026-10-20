## godot --path . -s tests/say_next_test.gd     (GATES S2; headless is fine)
## SAY WHAT NEXT: every message main.gd shows on its way OUT of an action (a _say right before a `return`: a refusal or
## a failure) names a next step the user can take: a verb from NEXT. Two of those exits are successes, listed in DONE
## with their reason. A new refusal with no way forward fails this test.
extends SceneTree

var fails := 0
const NEXT := ["pick", "click", "press", "open", "lock", "put", "add", "turn", "move", "type", "tick", "untick", "use",
	"select", "drag", "choose", "copy", "make", "free", "try", "give", "save", "close", "run"]
## exits that report something DONE (no next step is owed)
const DONE := {"fatigue at fitness %.2f": "reports the retime it just made (ROADMAP 39)", "range %.2f-%.2f s at": "reports the retime it just made (ROADMAP 67)", "the weapon slid in the hand": "reports the slide it just made", "second hand off the weapon": "reports the toggle it just made",
	"(in trash/ if you want it back)": "reports the delete it just made",
	"posed: %s%s": "reports the pose it just made (and where a limit stopped it)",
	"weight key at %s = %.2f": "reports the weight key it just changed (NA1)",
	"copied a card to %.2f s": "reports the copy it just made (NA0)",
	"body: %s, %.1f cm tall": "reports the proportions it just set (PR1)",
	# tonight's merges: these report what was just done (successes on the way out of a branch)
	"Auto-key: card %d takes the body": "reports the body it just put on the card (auto-key)",
	"all %d cards are on the floor now": "reports the snap it just made (floor snap; Ctrl+Z is named)",
	"the body is on the floor now (Ctrl+Z": "reports the snap it just made (floor snap; Ctrl+Z is named)",
	"_say(msg)": "forwards trail_edit.begin's message: each names the drag to do next (trail_edit.gd lines 122-139)",
	"_say(r[\"error\"])": "forwards PoseWords' error: each names the words to type instead (pose_words_test checks 5)",
	# the cape bake's success line (it reports the cape it just put on; Ctrl+Z is named)
	"the cape is on the back:": "reports the cape it just baked (Ctrl+Z is named)",
	# forwarders: the caller's message names the next step (_rp_straighten / _rp_scale name the handle or the slider;
	# CustomAttr.define names what to type or pick: custom_attr.gd check_name / check_range / define)
	"_say(none)": "forwards _rp_edit's message: each caller names the handle or the slider to move next (_rp_straighten, _rp_scale)",
	"_say(e)": "forwards CustomAttr.define's error: each names what to type or pick next (custom_attr.gd)",
	"reaction picker closed": "reports that the picker was just closed",
	"the clip now keeps your timing": "reports the retime it just made (Ctrl+Z is named)",
	"now has your pose (the 36 joint angles": "reports the pose it just put on the card (Ctrl+Z is named)",
	"reacts to the hit at %s": "reports the reaction it just made (Ctrl+Z is named)",
	"opened the shared scene": "reports the scene it just opened (Ctrl+Z is named)",
	"to its mirror depth": "reports the flip it just made (Ctrl+Z is named)",
	"msg + \".  Ctrl+Z undoes\"": "reports the sketch fit it just made (Ctrl+Z is named)",
	"posed '%s': %d placed": "reports the pose it just made (Ctrl+Z is named)",
	"cards x%s: the scene is now": "reports the retime it just made (Ctrl+Z is named)",
	"cards hold %s s: the scene": "reports the hold it just made (Ctrl+Z is named)",
	"%d cards deleted.": "reports the delete it just made (Ctrl+Z is named)",
	"cards pasted after card": "reports the paste it just made (Ctrl+Z is named)",
	"it runs in the background, the window stays yours": "reports that the job started (Cancel on the bar is named)",
	"next pose %d of %d": "reports the pose it just showed (Enter, Tab and Esc are named)"}


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
	# >=: "_say(msg)" is one DONE key matching two exits (the trail press)
	ok(exits.size() > 15 and done.size() >= DONE.size(), "the scan finds the exits (%d) and every listed success" % exits.size())
	ok(bad.is_empty(), "every refusal / failure names what to do next (%d without)" % bad.size())
	print("SAY NEXT TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
