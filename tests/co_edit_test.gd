## LIVE CO-EDITING (ROADMAP 30, scripts/co_edit.gd + the Co-edit commands in main.gd). Host and guest are TWO Kine
## mains in one process; the host and join commands are run from the command list, the confirm accepted by the test,
## everything over 127.0.0.1 on a random port. godot --headless --path . -s tests/co_edit_test.gd
## Bars, written before running:
##   1 HOST: "Co-edit: host" opens a confirm first (nothing listens before it); accepted, the status prints address:port
##     and the status line says who animates which fighter. JOIN: "Co-edit: join" asks for address:port; joined, both
##     status lines show "connected" and each side's fighter.
##   2 RANDOM EDITS: 20 random edits per side on its own fighter (each an undo step through _push_undo): after the ops
##     drain, both mains' copies of BOTH fighters are byte-identical, and each side draws the other's playhead.
##   3 PEER READ ONLY: the other fighter cannot be made active (refused with a message) and its cards do not change.
##   4 STOP / DISCONNECT KEEPS WORK: the guest stops; the host sees the peer leave (listening again); both keep every
##     card; edits made while apart apply locally; "Co-edit: stop" on the host ends its session.
##   5 VERSION MISMATCH REFUSED: a guest on another protocol version is refused with the version in the reason, the host
##     listens again, and no fighter changes (CoEdit level: the join command speaks the current version).
extends SceneTree

var fails := 0
var m: Node
var g: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func until(cond: Callable, frames := 300) -> bool:
	for i in frames:
		if cond.call():
			return true
		await process_frame
	return cond.call()


## a command of this Kine by its name, from its command list (what the command palette runs)
func cmd(node: Node, name: String) -> Callable:
	for c in node._commands():
		if c["name"] == name:
			return c["run"]
	return Callable()


## a card list with new cards and edits made from real cards (the pose is a real one), so the peer applies real data
func rand_cards(cards: Array) -> Array:
	var out: Array = cards.duplicate(true)
	var r := randf()
	if out.is_empty() or r < 0.35:
		var src: Dictionary = out[randi() % out.size()].duplicate(true) if not out.is_empty() else {"name": "x", "pose": {}, "move": 0.0, "hold": 1.0}
		src["name"] = "n%d" % randi()
		src["hold"] = randf() * 2.0
		out.insert(randi_range(0, out.size()), src)
	elif r < 0.5 and out.size() > 1:
		out.remove_at(randi() % out.size())
	elif r < 0.65 and out.size() > 1:
		var c = out.pop_at(randi() % out.size())
		out.insert(randi() % (out.size() + 1), c)
	else:
		var i := randi() % out.size()
		var c: Dictionary = out[i]
		c["hold"] = randf() * 3.0
		out[i] = c
	return out


## one local edit of the active fighter, as an undo step
func edit_active(node: Node) -> void:
	node.S.cards = rand_cards(node.S.cards)
	node._push_undo()


func text_of(node: Node) -> String:
	node._actors_sync()
	var t := ""
	for a in node.actors_rt:
		t += JSON.stringify(CoEdit.norm((a["S"] as Scene).cards)) + "|"
	return t


func host_port_try(port: int) -> bool:
	m.ui_co_port.text = str(port)
	m.ui_co_dlg.confirmed.emit()
	m.ui_co_dlg.hide()   # the real dialog closes on its OK
	return m.co != null and m.co.state == "listening"


func _initialize() -> void:
	_run()


func _run() -> void:
	randomize()
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	g = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(g)
	await idle(4)
	for node in [m, g]:
		node._load_scene("res://scenes/combo3.json")   # read only
		node._rebuild_cards()
		node._actor_add()   # fighter 2: a mirror of this one, facing it
		node._actor_set(0)
		node._refresh()
	await idle(2)
	g._actor_set(1)   # the guest animates fighter 2

	# 1 HOST: the confirm first
	var host_cmd := cmd(m, "Co-edit: host (one animator per fighter)...")
	ok(host_cmd.is_valid(), "1 the host command is in the command list")
	host_cmd.call()
	ok(m.co == null and m.ui_co_dlg.visible, "1 'Co-edit: host' opens the confirm and nothing listens yet")
	var port := 0
	var hosted := false
	for attempt in 10:
		port = randi_range(20000, 60000)
		if host_port_try(port):
			hosted = true
			break
	ok(hosted, "1 accepted: the host listens on port %d (state %s)" % [port, m.co.state if m.co != null else "none"])
	ok(m.ui_status.text.contains(":%d" % port), "1 the status prints address:port: '%s'" % m.ui_status.text)
	ok(m.ui_co_line.visible and m.ui_co_line.text.contains("you animate fighter 1") and m.ui_co_line.text.contains("waiting"), "1 host status line: '%s'" % m.ui_co_line.text)

	var join_cmd := cmd(g, "Co-edit: join...")
	join_cmd.call()
	ok(g.ui_co_join_dlg.visible, "1 'Co-edit: join' asks for address:port")
	g.ui_co_addr.text = "127.0.0.1:%d" % port
	g.ui_co_join_dlg.confirmed.emit()
	ok(await until(func(): return m.co != null and m.co.connected() and g.co != null and g.co.connected()),
		"1 joined: both connected (host %s, guest %s)" % [m.co.state if m.co else "-", g.co.state if g.co else "-"])
	await idle(3)
	ok(g.ui_co_line.text.contains("you animate fighter 2") and g.ui_co_line.text.contains("fighter 1") and g.ui_co_line.text.contains("connected"),
		"1 guest status line: '%s'" % g.ui_co_line.text)

	# 2 RANDOM EDITS: each its own fighter, interleaved
	var order: Array = []
	for i in 20:
		order.append(m)
		order.append(g)
	order.shuffle()
	for node in order:
		edit_active(node)
		await process_frame
	m.playhead = 0.75
	g.playhead = 1.25
	await idle(20)
	ok(text_of(m) == text_of(g) and text_of(m).length() > 0,
		"2 random edits: both mains' scenes byte-identical (%d bytes)" % text_of(m).length())
	ok(m.actors_rt[1]["pt"] == 1.25 and g.actors_rt[0]["pt"] == 0.75, "2 each side draws the other's playhead (%s, %s)" % [m.actors_rt[1].get("pt", "-"), g.actors_rt[0].get("pt", "-")])

	# 3 PEER READ ONLY
	var before := text_of(m)
	var refused: bool = m._actor_set(1)
	ok(not refused and m.actor_on == 0 and m.ui_status.text.contains("read only"), "3 the peer's fighter cannot be made active here: '%s'" % m.ui_status.text)
	ok(text_of(m) == before, "3 the refusal changed nothing")

	# 4 STOP / DISCONNECT KEEPS WORK
	var kept := text_of(m)
	var kept_g := text_of(g)
	cmd(g, "Co-edit: stop").call()
	ok(g.co == null and not g.ui_co_line.visible, "4 the guest's stop ends its session")
	ok(await until(func(): return m.co != null and not m.co.connected()), "4 the host sees the guest leave (state %s)" % (m.co.state if m.co else "-"))
	ok(m.co.state == "listening" and m.ui_co_line.text.contains("waiting"), "4 the host listens again, status: '%s'" % m.ui_co_line.text)
	ok(text_of(m) == kept and text_of(g) == kept_g, "4 both sides keep their work at the disconnect")
	edit_active(m)
	edit_active(g)
	await idle(5)
	ok(text_of(m) != kept and text_of(g) != kept_g, "4 edits while apart apply locally on both sides")
	cmd(m, "Co-edit: stop").call()
	ok(m.co == null and not m.ui_co_line.visible, "4 'Co-edit: stop' on the host ends its session")

	# 5 VERSION MISMATCH: the protocol level (the join command speaks the current version)
	var h2 := CoEdit.new()
	h2.fighters = [m.actors_rt[0]["S"], m.actors_rt[1]["S"]]
	var p2 := 0
	for attempt in 10:
		p2 = randi_range(20000, 60000)
		if h2.host(p2, CoEdit.LOOPBACK, 0) == "":
			break
	var g2 := CoEdit.new()
	g2.fighters = [m.actors_rt[0]["S"], m.actors_rt[1]["S"]]
	g2.join(CoEdit.LOOPBACK, p2, 1, CoEdit.PROTO + 1)
	var waited := 0
	while waited < 300 and g2.state != "closed":
		h2.poll()
		g2.poll()
		await process_frame
		waited += 1
	ok(g2.state == "closed" and g2.note.find("version mismatch") >= 0, "5 the mismatched guest is turned away: '%s'" % g2.note)
	ok(h2.state == "listening" and h2.note.find("version mismatch") >= 0, "5 the host refused it and listens again")
	h2.close()
	g2.close()

	m.queue_free()
	g.queue_free()
	await idle(2)
	print("CO EDIT: %d failed" % fails)
	quit(1 if fails > 0 else 0)
