## WHAT WENT WRONG? (ROADMAP 43): the last refusal or error the status line showed, in plain words.
## Pure logic, no nodes: main.gd keeps the last problem message (with its command, part and frame) and asks here
## which problems count, and what each one means. The table is keyed by a fragment of the message the app says
## (grep the _say calls): the first entry whose fragment is in the message wins, so the specific ones come first.
## Each entry: why = what it means, step = the one next step's words, cmd = a registry command that does that
## step ("" = a step only the user can do: the button then puts the words on the status line).
class_name WhyWrong

## messages that are not problems although they match a word below (successes that say "not" or "no")
const NOT_PROBLEMS := ["not saved yet", "no move goes through", "nothing to note"]

## words that make a status line a refusal or an error (lower case, matched anywhere in the message)
const PROBLEM_WORDS := ["nothing to", "no ", "there is no", "there are no", "needs ", "need ", "pick ", "click a ",
	"can't", "cannot", "could not", "not valid", "only your own", "already exists", "is not a ", "drag a range"]

const TABLE := [
	{"pat": "nothing to undo", "why": "Undo only takes back a change that was made, and none has been made since the scene opened (or all of them are already taken back).",
		"step": "Pick a part", "cmd": "Pick a part"},
	{"pat": "nothing to redo", "why": "Redo only puts back what Undo took back, and nothing has been undone.",
		"step": "Undo a change first (Ctrl+Z), then redo it", "cmd": ""},
	{"pat": "needs a scene of two cards or more", "why": "This tool compares one moment (a card) with the next, so the scene needs at least two cards.",
		"step": "Clip this pose (add a card)", "cmd": "CLIP this pose (add a card)"},
	{"pat": "needs two fighters", "why": "This tool works between two fighters, and the scene has only one.",
		"step": "Add a second fighter", "cmd": "Actor: add a second fighter (mirror of this one, facing it)"},
	{"pat": "pick a prop first", "why": "No prop is picked, so the command has no prop to act on.",
		"step": "Click a prop in the view, or add one with Add prop", "cmd": ""},
	{"pat": "pick a body part first", "why": "No body part is picked, and this tool acts on the picked part (and the parts below it).",
		"step": "Pick a part", "cmd": "Pick a part"},
	{"pat": "pick the part first", "why": "No body part is picked, and this tool acts on the picked part.",
		"step": "Pick a part", "cmd": "Pick a part"},
	{"pat": "pick a part first", "why": "No body part is picked, and this tool acts on the picked part.",
		"step": "Pick a part", "cmd": "Pick a part"},
	{"pat": "pick a card first", "why": "No card is picked, and this tool acts on one card (or on a card with a neighbour before or after it).",
		"step": "Click a card on the timeline", "cmd": ""},
	{"pat": "pick a card after the first", "why": "This tool needs a card with a card before it, so the first card cannot take it.",
		"step": "Click a later card on the timeline", "cmd": ""},
	{"pat": "no clip picked", "why": "No clip is picked on the timeline, so there is nothing for the command to change.",
		"step": "Click the clip's bar under the cards on the timeline", "cmd": ""},
	{"pat": "no sound on the timeline", "why": "There is no sound file under the timeline yet, so there is nothing to find beats in or to line up with.",
		"step": "Add a sound file (a wav)", "cmd": "Audio: add a sound file (wav / ogg / mp3)"},
	{"pat": "locked", "why": "The active layer is locked, and a locked layer refuses edits so that it cannot change by accident.",
		"step": "Unlock the layer", "cmd": "Layer: lock"},
	{"pat": "not placed", "why": "The file picked is not one this can play (a scene, a pose or a move file).",
		"step": "Pick another file in the list", "cmd": ""},
	{"pat": "cannot place itself", "why": "A scene cannot hold itself as a clip: it would play forever.",
		"step": "Pick another scene in the list", "cmd": ""},
	{"pat": "cannot move that far", "why": "The move would start before time 0 s, so the fighter cannot make it that early.",
		"step": "Move the playhead later, or shorten the move", "cmd": ""},
	{"pat": "no marker", "why": "No marker sits at the playhead (or within one frame of it), so there is none to step to or remove.",
		"step": "Add a marker at the playhead", "cmd": "Add marker at the playhead"},
	{"pat": "no card after the playhead", "why": "A foot plant runs to the next card, and there is no card after the playhead.",
		"step": "Put the playhead before a card", "cmd": ""},
	{"pat": "nothing to plant", "why": "The range has no time in it, so there is no foot to plant.",
		"step": "Drag a range on the timeline first", "cmd": ""},
	{"pat": "near the playhead", "why": "No key of the picked part is within 0.05 s of the playhead, so there is no key to set.",
		"step": "Move the playhead onto a key", "cmd": ""},
	{"pat": "nothing to bake", "why": "The scene has no cards, so there is nothing to bake.",
		"step": "Clip this pose (add a card)", "cmd": "CLIP this pose (add a card)"},
	{"pat": "no layers to merge", "why": "There is no layer to merge: the cards already play everything.",
		"step": "Keep a change as a layer first", "cmd": "Layer: keep this change through the whole scene"},
	{"pat": "no secondary motion", "why": "The scene has no secondary motion (a ponytail, a cloth strip, a weapon flex) yet.",
		"step": "Add a ponytail", "cmd": "Secondary: add a ponytail"},
	{"pat": "no beats yet", "why": "The beats of the sound have not been found yet.",
		"step": "Find the beats in the sound", "cmd": "Beats: find the beats in the sound"},
	{"pat": "no driver", "why": "The picked part has no driver to take off or change.",
		"step": "Pick a part", "cmd": "Pick a part"},
	{"pat": "no constraint on the picked part", "why": "The picked part has no constraint to take off or change.",
		"step": "Pick a part", "cmd": "Pick a part"},
	{"pat": "no hit or hurt boxes", "why": "This part has no hit or hurt box yet.",
		"step": "Add a hit box on the picked part", "cmd": ""},
	{"pat": "can't reach", "why": "The arm or leg is at its full length, so it cannot follow any further that way.",
		"step": "Turn the weapon or move the body", "cmd": ""},
	{"pat": "cannot reach", "why": "The hand or foot is at its full length, so it cannot reach that place from here.",
		"step": "Move the body nearer the place", "cmd": ""},
	{"pat": "could not add", "why": "The file is not a wav, ogg or mp3, or Godot cannot read it.",
		"step": "Pick a wav, ogg or mp3 file", "cmd": ""},
	{"pat": "only your own poses", "why": "The library poses keep their names, because the tools use them.",
		"step": "Pick one of your own poses (Save pose makes one)", "cmd": ""},
	{"pat": "already exists", "why": "A pose with that name is already saved, and two poses cannot share a name.",
		"step": "Type another name", "cmd": ""},
	{"pat": "no contact", "why": "No contact in the fighters' report lands on a body part to react to.",
		"step": "Swing into the other fighter, or pick a stronger hit", "cmd": ""},
	{"pat": "not one this can play", "why": "The file is not a kind this can play.",
		"step": "Pick another file", "cmd": ""},
	{"pat": "not valid", "why": "The box is on a part a box cannot ride on.",
		"step": "Pick another part", "cmd": ""},
	# the general fallbacks: a refusal that matched none of the above
	{"pat": "not ", "why": "The command refused: the words after NOT say why, in capitals.",
		"step": "Read the message and do what it names", "cmd": ""},
	{"pat": "no ", "why": "Something the command needs is not in the scene yet.",
		"step": "Read the message and add or pick what it names", "cmd": ""},
	{"pat": "needs ", "why": "The command needs something that is not there yet.",
		"step": "Read the message and add what it names first", "cmd": ""},
	{"pat": "cannot", "why": "In the scene as it is now, the command cannot do this.",
		"step": "Read the message and change what it names", "cmd": ""},
	{"pat": "pick ", "why": "The command acts on something that is not picked yet.",
		"step": "Click it in the view or on the timeline, then try again", "cmd": ""},
]


## is this status line a refusal or an error (what What went wrong? keeps)?
static func is_problem(t: String) -> bool:
	if t == "" or t.begins_with("undone") or t.begins_with("redone"):
		return false
	if t.begins_with("NOT ") or t.contains("LOCKED"):
		return true
	var low := t.to_lower()
	for n in NOT_PROBLEMS:
		if low.contains(n):
			return false
	for w in PROBLEM_WORDS:
		if low.contains(w):
			return true
	return false


## the table entry that explains a message (its first fragment, in table order); a problem with no entry
## gets the last generic one, so every problem has an explanation
static func explain(t: String) -> Dictionary:
	var low := t.to_lower()
	for e in TABLE:
		if low.contains(String(e["pat"])):
			return e
	return {"pat": "", "why": "The command could not finish what it was asked to do.",
		"step": "Read the message and do what it names", "cmd": ""}
