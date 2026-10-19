## LIVE CO-EDITING (ROADMAP 30, scripts/co_edit.gd). Host and guest in ONE process on 127.0.0.1 and a random port.
## godot --headless --path . -s tests/co_edit_test.gd
## Bars, written before running:
##   1 RANDOM EDITS: 20 random edits on each side's own fighter (interleaved, with playhead moves): after the ops drain,
##     both sides' copies of BOTH fighters are byte-identical, no hash mismatch (no resync), and each side's peer
##     playhead is the other's last t.
##   2 PEER READ ONLY: an edit to the peer's fighter is refused with a message, and its cards do not change.
##   3 DISCONNECT KEEPS WORK: the guest leaves mid-session; the host sees it; both sides keep every card they had, the
##     local edits made while apart apply locally, and nothing is sent.
##   4 VERSION MISMATCH REFUSED: a guest on another version is refused with the version in the reason, and the host
##     goes back to listening; neither side's fighters change.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func scene_of(nm: String) -> Scene:
	var s := Scene.new()
	s.from_dict({"scene": nm, "fps": 30, "cards": [
		{"name": "a", "pose": {"hip": [0.1, 0.0, 0.0]}, "move": -1.0, "hold": 2.0},
		{"name": "b", "pose": {"hip": [0.2, 0.0, 0.0]}, "move": 0.5, "hold": 3.0}]})
	return s


func rand_cards(cards: Array) -> Array:
	var out: Array = cards.duplicate(true)
	var r := randf()
	if out.is_empty() or r < 0.35:
		out.insert(randi_range(0, out.size()), {"name": "n%d" % randi(), "pose": {"hip": [randf(), randf(), randf()]},
			"move": randf(), "hold": randf() * 2.0})
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


func fighters_text(s: CoEdit) -> String:
	var t := ""
	for f in s.fighters.size():
		t += JSON.stringify(CoEdit.norm(s.fighters[f].cards)) + "|"
	return t


## the pumps: both sides poll (the sockets move) and the frame passes
func pump(n: int) -> void:
	for i in n:
		host.poll()
		guest.poll()
		await process_frame


func until(cond: Callable, frames := 300) -> bool:
	for i in frames:
		if cond.call():
			return true
		await pump(1)
	return cond.call()


var host: CoEdit
var guest: CoEdit


func _initialize() -> void:
	_run()


func _run() -> void:
	randomize()
	host = CoEdit.new()
	guest = CoEdit.new()
	host.fighters = [scene_of("h0"), scene_of("h1")]
	guest.fighters = [scene_of("h0"), scene_of("h1")]
	var port := 0
	var err := ""
	for attempt in 10:
		port = randi_range(20000, 60000)
		err = host.host(port, CoEdit.LOOPBACK, 0)
		if err == "":
			break
	ok(err == "" and host.state == "listening", "host listens on 127.0.0.1:%d (%s)" % [port, err])
	err = guest.join(CoEdit.LOOPBACK, port, 1)
	ok(err == "", "guest joins as fighter 1")
	ok(await until(func(): return host.connected() and guest.connected()), "handshake: both connected (host state %s, guest %s)" % [host.state, guest.state])
	ok(host.peer_own == 1 and guest.peer_own == 0, "each side knows the other's fighter")
	await pump(5)

	# 1 RANDOM EDITS
	var t_host := -1.0
	var t_guest := -1.0
	var ops_before := host.applied + guest.applied
	var order: Array = []
	for i in 20:
		order.append(0)
		order.append(1)
	order.shuffle()
	for side in order:
		var s: CoEdit = host if side == 0 else guest
		var cards: Array = s.fighters[s.own].cards
		var why := s.set_cards(s.own, rand_cards(cards))
		if why != "":
			print("     edit refused: " + why)
		if randf() < 0.5:
			var t := randf() * 2.0
			s.set_t(t)
			if side == 0:
				t_host = t
			else:
				t_guest = t
		await pump(1)
	host.set_t(0.75)
	guest.set_t(1.25)
	t_host = 0.75
	t_guest = 1.25
	await pump(30)
	var a := fighters_text(host)
	var b := fighters_text(guest)
	ok(a == b and a.length() > 0, "1 random edits: both sides' scenes byte-identical (%d bytes, %d ops applied, %d resyncs)" % [a.length(), host.applied + guest.applied - ops_before, host.resyncs + guest.resyncs])
	ok(host.resyncs + guest.resyncs == 0, "1 every op's hash matched on arrival")
	ok(is_equal_approx(guest.peer_t, t_host) and is_equal_approx(host.peer_t, t_guest), "1 each side shows the other's playhead (%.3f, %.3f)" % [guest.peer_t, host.peer_t])
	var h_before := fighters_text(host)
	var g_before := fighters_text(guest)

	# 2 PEER READ ONLY
	var why_h := host.set_cards(1, [])
	var why_g := guest.set_cards(0, [])
	ok(why_h.find("read only") >= 0 and why_g.find("read only") >= 0, "2 an edit to the peer's fighter is refused with a message: '%s'" % why_h)
	ok(fighters_text(host) == h_before and fighters_text(guest) == g_before, "2 the refused edits changed nothing")

	# 3 DISCONNECT KEEPS WORK
	guest.close()
	ok(await until(func(): return not host.connected()), "3 the host notices the guest left (host state %s: %s)" % [host.state, host.note])
	var h_kept := fighters_text(host)
	var g_kept := fighters_text(guest)
	ok(h_kept == h_before and g_kept == g_before, "3 both sides keep their scenes at the disconnect")
	var h_r := host.set_cards(0, rand_cards(host.fighters[0].cards))
	var g_r := guest.set_cards(guest.own, rand_cards(guest.fighters[guest.own].cards))
	await pump(10)
	ok(h_r == "" and fighters_text(host) != h_kept, "3 a host edit while apart applies locally")
	ok(g_r == "" and fighters_text(guest) != g_kept, "3 a guest edit while apart applies locally")
	ok(fighters_text(host).split("|")[1] == h_kept.split("|")[1] and fighters_text(guest).split("|")[0] == g_kept.split("|")[0], "3 nothing crossed while apart: each peer copy kept as it was")
	ok(guest.state != "connected" and host.state == "listening", "3 states after the drop: guest %s, host %s" % [guest.state, host.state])

	# 4 VERSION MISMATCH REFUSED (a new host, a guest on another version)
	host.close()
	var h2 := CoEdit.new()
	h2.fighters = [scene_of("h0"), scene_of("h1")]
	var before2 := fighters_text(h2)
	var port2 := 0
	for attempt in 10:
		port2 = randi_range(20000, 60000)
		if h2.host(port2, CoEdit.LOOPBACK, 0) == "":
			break
	var g2 := CoEdit.new()
	g2.fighters = [scene_of("h0"), scene_of("h1")]
	host = h2   # the pumps drive host and guest: these two now
	guest = g2
	var ce := g2.join(CoEdit.LOOPBACK, port2, 1, CoEdit.PROTO + 1)
	ok(ce == "", "4 the mismatched guest tries to join")
	ok(await until(func(): return g2.state == "closed", 300), "4 the guest is turned away (state %s)" % g2.state)
	ok(g2.note.find("version mismatch") >= 0, "4 the reason names the version: '%s'" % g2.note)
	ok(h2.note.find("version mismatch") >= 0 and h2.state == "listening", "4 the host refused it and listens again: '%s'" % h2.note)
	ok(fighters_text(h2) == before2 and not h2.connected() and not g2.connected(), "4 no fighter changed, nothing connected")
	h2.close()
	g2.close()

	host.close()
	guest.close()
	print("CO EDIT: %d failed" % fails)
	quit(1 if fails > 0 else 0)
