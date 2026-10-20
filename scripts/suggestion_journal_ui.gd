## "What I learned from you" (ROADMAP I26): the panel over scripts/suggestion_journal.gd. Lists the top lessons with their counts and has a
## Reset button. main makes one (main.sj_ui); the journal itself is main.sj.
class_name SuggestionJournalUI
extends RefCounted

var m: Node


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("What I learned from you", "", show, "learned suggestions edits journal kept undone rate reset",
		false, "which suggestions you keep, undo or reshape: the top lessons with their counts (a timing you always shorten comes pre-applied); Reset forgets them")


func show() -> void:
	var L: VBoxContainer = m.ui_find_list
	for c in L.get_children():
		L.remove_child(c)
		c.queue_free()
	var ls: Array = m.sj.lessons()
	var head := HBoxContainer.new()
	L.add_child(head)
	var title: Label = m._label("WHAT I LEARNED FROM YOU  -  " + ("nothing yet" if ls.is_empty() else "%d lessons" % ls.size()), 18, "heading")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(m._button("Close", m._close_findings))
	L.add_child(m._label("Accept a suggestion and I watch: undone within 30 s counts against it, a change to its own number within 2 minutes is a lesson. Three edits the same way and I apply them for you.", 13, "text:0.6", true))
	for k in ls.size():
		var lb: Label = m._label(String(ls[k]["text"]), 14, "text:0.85", true)
		lb.name = "sj_lesson_%d" % (k + 1)
		lb.custom_minimum_size = Vector2(380, 0)
		L.add_child(lb)
	var rb: Button = m._button("Reset what I learned", reset, "forget every lesson and start from 50% for every suggestion; the file is emptied")
	rb.name = "sj_reset"
	L.add_child(rb)
	(m.ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(420, clampf(190.0 + 56.0 * ls.size(), 200.0, 440.0))
	m.ui_find.visible = true
	m._say("what I learned: " + ("nothing yet: accept a few suggestions and edit or undo them" if ls.is_empty() else "%d lessons. Reset forgets them" % ls.size()))


func reset() -> void:
	m.sj.reset()
	show()
	m._say("what I learned: forgotten. Every suggestion starts from 50% again")
