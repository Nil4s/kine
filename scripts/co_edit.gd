## LIVE CO-EDITING (ROADMAP 30): one animator per fighter, over TCP on a LAN.
##
## One Kine HOSTS (listens on a port; the app binds it to the LAN address only after the user confirms, loopback
## otherwise) and one JOINS by address. Each side OWNS one fighter (its index in `fighters`, the scene's actors in
## order). The owner's card edits leave as small splice ops: one op per undo step (the undo snapshot's granularity),
## `{"t":"op","f","at","del","ins","h"}` = replace `del` cards at `at` by `ins`, `h` = the hash of the fighter's cards
## after the op, so the receiver can check its copy. The other fighter is read only here: set_cards refuses it with a
## message, and the app does not make it the active actor. The owner's playhead goes as {"t":"t","v"}.
##
## Handshake (newline-delimited JSON): guest -> {"t":"hello","v","own","n"}; host -> {"t":"welcome","v","own"} or
## {"t":"refused","why"} (version, fighter count, or a fighter already taken), then each side sends its whole owned
## fighter ({"t":"full","f","cards"}), so both copies start identical. A receiver whose hash does not match asks for
## the whole fighter again ({"t":"need_full"}). Ownership makes conflicts impossible: no op ever targets a fighter the
## sender does not own.
##
## Nothing here touches the disk: the host saves the scene (the app refuses the guest's save), and a disconnect keeps
## both sides' in-memory work. Driven by poll() each frame; the app calls sync_owned() after every undo step.
class_name CoEdit
extends RefCounted

const PROTO := 1                 # the wire version: a guest on another version is refused
const LOOPBACK := "127.0.0.1"

var fighters: Array = []         # the Scene of each fighter, actor order (set by the app before it hosts / joins)
var own := -1                    # the fighter this side animates
var peer_own := -1               # the fighter the other side animates (-1 until the handshake)
var is_host := false
var state := "idle"             # idle / listening / connecting / handshaking / connected / closed
var note := ""                   # why the connection last ended, or the refusal text
var peer_t := 0.0                # the other side's playhead (its last "t")
var applied := 0                 # peer ops applied
var resyncs := 0                 # peer ops whose hash did not match: the whole fighter was asked for again
var on_applied := Callable()     # (fighter index, "cards" | "t"): the peer's data changed here, the app repaints

var _server: TCPServer = null
var _peer: StreamPeerTCP = null
var _buf := ""
var _sent: Array = []            # the owned fighter's cards as last synced (normalised), the base of the next diff
var _t_sent := -1.0
var _hello_v := PROTO


## HOST: listen on `bind` (LOOPBACK until the user confirms the LAN; the app passes this machine's LAN address then).
## "" when listening, else why not.
func host(port: int, bind := LOOPBACK, own_index := 0) -> String:
	close()
	if own_index < 0 or own_index >= fighters.size():
		return "fighter %d does not exist (the scene has %d)" % [own_index, fighters.size()]
	_server = TCPServer.new()
	var err := _server.listen(port, bind)
	if err != OK:
		_server = null
		return "could not listen on %s:%d (error %d): the port is taken, or %s is not an address of this machine" % [bind, port, err, bind]
	own = own_index
	is_host = true
	state = "listening"
	_sent = norm(fighters[own].cards)
	return ""


## GUEST: connect to a host. `proto` is the version this side speaks (the test makes it differ). "" when connecting.
func join(addr: String, port: int, own_index: int, proto := PROTO) -> String:
	close()
	if own_index < 0 or own_index >= fighters.size():
		return "fighter %d does not exist (the scene has %d)" % [own_index, fighters.size()]
	_peer = StreamPeerTCP.new()
	if _peer.connect_to_host(addr, port) != OK:
		_peer = null
		return "could not reach %s:%d" % [addr, port]
	own = own_index
	is_host = false
	_hello_v = proto
	_sent = norm(fighters[own].cards)
	state = "connecting"
	return ""


func connected() -> bool:
	return state == "connected" and _peer != null


## the LAN IPv4 address the host should bind to and print (first private address), "" when there is none
static func lan_address() -> String:
	for a in IP.get_local_addresses():
		if a.is_valid_ip_address() and ":" not in a and (a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172.")):
			return a
	return ""


## every IPv4 address of this machine but loopback, comma separated (what the host prints)
static func addresses() -> String:
	var out: Array = []
	for a in IP.get_local_addresses():
		if a.is_valid_ip_address() and ":" not in a and a != LOOPBACK:
			out.append(a)
	return ", ".join(out)


## the reason `f` may not be edited here, "" when it may. The other side's fighter is read only.
func may_edit(f: int) -> String:
	if f == own:
		return ""
	if f < 0 or f >= fighters.size():
		return "there is no fighter %d" % f
	return "fighter %d is animated by the other side: read only here (you animate fighter %d)" % [f, own]


## an edit to a fighter: refused with a message unless it is the one this side owns. Returns "" when done.
func set_cards(f: int, cards: Array) -> String:
	var why := may_edit(f)
	if why != "":
		return why
	fighters[f].cards = cards.duplicate(true)
	sync_owned()
	return ""


## after the owner's cards changed (an edit or an undo step): one splice op for the difference, sent if connected.
## True when there was a difference
func sync_owned() -> bool:
	if own < 0 or own >= fighters.size():
		return false
	var now := norm(fighters[own].cards)
	var d := splice(_sent, now)
	_sent = now
	if d["del"] == 0 and (d["ins"] as Array).is_empty():
		return false
	if connected():
		_send({"t": "op", "f": own, "at": d["at"], "del": d["del"], "ins": d["ins"], "h": hash_of(now)})
	return true


## the owner's playhead: sent when it moved
func set_t(t: float) -> void:
	if connected() and absf(t - _t_sent) > 0.000001:
		_t_sent = t
		_send({"t": "t", "v": t})


func close() -> void:
	if _peer != null:
		_peer.disconnect_from_host()
	_peer = null
	_buf = ""
	if _server != null:
		_server.stop()
		_server = null
	state = "idle"


## one frame: accept, handshake, read the peer's messages, notice a disconnect (the work on both sides is kept)
func poll() -> void:
	if state == "listening" and _server != null and _server.is_connection_available():
		_peer = _server.take_connection()
		_buf = ""
		state = "handshaking"
	if _peer == null:
		return
	_peer.poll()
	var st := _peer.get_status()
	if state == "connecting":
		if st == StreamPeerTCP.STATUS_CONNECTED:
			state = "handshaking"
			_send({"t": "hello", "v": _hello_v, "own": own, "n": fighters.size()})
		elif st != StreamPeerTCP.STATUS_CONNECTING:
			note = "could not reach the host"
			_drop()
			return
	elif st != StreamPeerTCP.STATUS_CONNECTED:
		if state == "connected" or state == "handshaking":
			note = "the other side disconnected: both scenes keep their work"
		_drop()
		return
	_read()


func _drop() -> void:
	if _peer != null:
		_peer.disconnect_from_host()
	_peer = null
	_buf = ""
	peer_own = -1
	state = "listening" if (is_host and _server != null) else "closed"


func _send(d: Dictionary) -> void:
	if _peer != null:
		_peer.put_data((JSON.stringify(d) + "\n").to_utf8_buffer())


func _read() -> void:
	var n := _peer.get_available_bytes()
	if n > 0:
		var r := _peer.get_data(n)
		if r[0] == OK:
			_buf += (r[1] as PackedByteArray).get_string_from_utf8()
	var i := _buf.find("\n")
	while i >= 0:
		var line := _buf.substr(0, i)
		_buf = _buf.substr(i + 1)
		if line != "":
			_on_msg(line)
		if _peer == null:
			return
		i = _buf.find("\n")


func _on_msg(line: String) -> void:
	var d = JSON.parse_string(line)
	if typeof(d) != TYPE_DICTIONARY:
		return
	match String(d.get("t", "")):
		"hello":
			_on_hello(d)
		"welcome":
			if int(d.get("v", -1)) != PROTO:
				note = "refused: version mismatch (this Kine speaks %d, the host %d)" % [PROTO, int(d.get("v", -1))]
				_drop()
				state = "closed"
				return
			peer_own = int(d.get("own", -1))
			state = "connected"
			_send_full()
		"refused":
			note = "refused by the host: %s" % String(d.get("why", ""))
			_drop()
			state = "closed"
		"full":
			_on_full(d)
		"op":
			_on_op(d)
		"need_full":
			_send_full()
		"t":
			if peer_own >= 0:
				peer_t = float(d.get("v", 0.0))
				_applied(peer_own, "t")


func _on_hello(d: Dictionary) -> void:
	var v := int(d.get("v", -1))
	var f := int(d.get("own", -1))
	var why := ""
	if v != PROTO:
		why = "version mismatch: host %d, guest %d" % [PROTO, v]
	elif int(d.get("n", -1)) != fighters.size():
		why = "fighter count: host %d, guest %d" % [fighters.size(), int(d.get("n", -1))]
	elif f < 0 or f >= fighters.size() or f == own:
		why = "fighter %d is not free (the host animates fighter %d)" % [f, own]
	if why != "":
		note = why
		_send({"t": "refused", "why": why})
		_drop()   # back to listening: another guest may join
		return
	peer_own = f
	_send({"t": "welcome", "v": PROTO, "own": own, "n": fighters.size()})
	state = "connected"
	_send_full()


func _send_full() -> void:
	_sent = norm(fighters[own].cards)
	_send({"t": "full", "f": own, "cards": _sent})


func _on_full(d: Dictionary) -> void:
	var f := int(d.get("f", -1))
	if f != peer_own or not (d.get("cards") is Array):
		return
	fighters[f].cards = norm(d["cards"])
	_applied(f, "cards")


func _on_op(d: Dictionary) -> void:
	var f := int(d.get("f", -1))
	if f != peer_own:
		return   # never a fighter the peer does not own
	var cards: Array = fighters[f].cards
	var at := int(d.get("at", -1))
	var dl := int(d.get("del", -1))
	var ins = d.get("ins", [])
	if at < 0 or dl < 0 or at + dl > cards.size() or not (ins is Array):
		resyncs += 1
		_send({"t": "need_full"})
		return
	fighters[f].cards = cards.slice(0, at) + (ins as Array) + cards.slice(at + dl)
	if hash_of(fighters[f].cards) != String(d.get("h", "")):
		resyncs += 1
		_send({"t": "need_full"})
	else:
		applied += 1
	_applied(f, "cards")


func _applied(f: int, what: String) -> void:
	if on_applied.is_valid():
		on_applied.call(f, what)


## a normalised copy of a card list (what JSON makes of it), so both sides compare the same bytes
static func norm(cards) -> Array:
	return JSON.parse_string(JSON.stringify(cards))


static func hash_of(cards) -> String:
	return JSON.stringify(norm(cards)).md5_text()


## the splice that turns `old` into `new`: `del` cards at `at` replaced by `ins` (the common head and tail kept)
static func splice(old: Array, new: Array) -> Dictionary:
	var a: Array = []
	for c in old:
		a.append(JSON.stringify(c))
	var b: Array = []
	for c in new:
		b.append(JSON.stringify(c))
	var p := 0
	while p < a.size() and p < b.size() and a[p] == b[p]:
		p += 1
	var s := 0
	while s < a.size() - p and s < b.size() - p and a[a.size() - 1 - s] == b[b.size() - 1 - s]:
		s += 1
	return {"at": p, "del": a.size() - p - s, "ins": new.slice(p, b.size() - s)}
