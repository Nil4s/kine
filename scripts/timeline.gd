## TIMELINE (round 6, Nick 10-14): the scene as one strip, the way an editor shows clips. Each card is a block: its MOVE
## (solid: the body travelling into the card's pose) then its HOLD (hatched: standing in it). The tick at the end of a
## move is the pose itself. Drag a card's arrival edge = its move time; drag the end of its hold = its hold time; every
## later card slides along (ripple). A card with no hold: drag its edge RIGHT to pull a hold out, LEFT to shorten the
## move. Snaps to 0.05 s (Shift: 0.01). Click a block = pick that card at its pose; click or drag the ruler = scrub.
## This file only draws and reads the mouse; main.gd owns the scene, undo and the caches (the signals below).
class_name Timeline
extends Control

signal scrubbed(t: float)
signal picked(i: int)
signal retime_started
signal retimed(final: bool)

const RULER := 16.0      # px: the seconds ruler on top
const PAD := 8.0         # px each side
const GRAB := 6.0        # px: how close counts as "on an edge"
const SNAP := 0.05
const FINE := 0.01
const MIN_MOVE := 0.04   # s: a move can't be shorter (a 1-frame move at 30 fps is 0.033)

var m: Node              # main.gd: reads m.S, m.playhead, m.sel_card

var _drag := {}          # {"kind": "move"/"hold"/"edge0"/"scrub", "i", "x0", "v0", "pps", "t0"}
var _hover := {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0, 46)
	clip_contents = true


func _S() -> Scene:
	return m.S if m != null else null


## seconds -> x. During a drag the scale is frozen (the strip would otherwise rescale under the mouse as it grows)
func pps() -> float:
	if _drag.has("pps"):
		return _drag["pps"]
	var S := _S()
	var L := S.length() if S != null and not S.cards.is_empty() else 1.0
	return (size.x - 2.0 * PAD) / maxf(L, 0.5)


func x_of(t: float) -> float:
	return PAD + t * pps()


func t_of(x: float) -> float:
	return maxf(0.0, (x - PAD) / pps())


## what is under x (and y): {"kind": "move", "i"} = card i's arrival edge, {"kind": "hold", "i"} = the end of its hold,
## {"kind": "edge0", "i"} = an arrival with no hold (direction decides), {"kind": "block", "i"}, {"kind": "ruler"}, {}
func hit(p: Vector2) -> Dictionary:
	var S := _S()
	if S == null or S.cards.is_empty():
		return {}
	if p.y < RULER:
		return {"kind": "ruler"}
	var ts := S.times()
	var best := {}
	var bd := GRAB
	for i in S.cards.size():
		var xa := x_of(ts[i][1])
		var xh := x_of(ts[i][2])
		var zero_hold: bool = ts[i][2] - ts[i][1] < 1e-4
		if i > 0 and absf(p.x - xa) <= bd:
			bd = absf(p.x - xa)
			best = {"kind": "edge0" if zero_hold else "move", "i": i}
		if not zero_hold and absf(p.x - xh) <= bd:
			bd = absf(p.x - xh)
			best = {"kind": "hold", "i": i}
	if not best.is_empty():
		return best
	for i in S.cards.size():
		if p.x >= x_of(ts[i][0]) and p.x < x_of(ts[i][2]) + (0.0 if i < S.cards.size() - 1 else GRAB):
			return {"kind": "block", "i": i}
	return {"kind": "ruler"}


func _gui_input(ev: InputEvent) -> void:
	var S := _S()
	if S == null or S.cards.is_empty():
		return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			var h := hit(ev.position)
			if h.is_empty():
				return
			match h["kind"]:
				"ruler":
					_drag = {"kind": "scrub"}
					scrubbed.emit(t_of(ev.position.x))
				"block":
					picked.emit(h["i"])
				_:
					var i: int = h["i"]
					_drag = {"kind": h["kind"], "i": i, "x0": ev.position.x, "pps": pps(),
						"move0": S.move_time(i), "hold0": float(S.cards[i]["hold"])}
					retime_started.emit()
			accept_event()
		elif not _drag.is_empty():
			var was: String = _drag.get("kind", "")
			_drag = {}
			if was != "scrub":
				retimed.emit(true)
			queue_redraw()
			accept_event()
	elif ev is InputEventMouseMotion:
		if _drag.is_empty():
			var h := hit(ev.position)
			mouse_default_cursor_shape = Control.CURSOR_HSIZE if h.get("kind", "") in ["move", "hold", "edge0"] else Control.CURSOR_ARROW
			if h != _hover:
				_hover = h
				queue_redraw()
			return
		if _drag["kind"] == "scrub":
			scrubbed.emit(t_of(ev.position.x))
			return
		_retime_to(ev.position.x, ev.shift_pressed)
		accept_event()


## the drag, as card values: snapped to SNAP (FINE with Shift), measured from where the drag began
func _retime_to(x: float, fine: bool) -> void:
	var S := _S()
	var i: int = _drag["i"]
	var dt: float = (x - float(_drag["x0"])) / float(_drag["pps"])
	if _drag["kind"] == "edge0":
		if absf(x - float(_drag["x0"])) < 3.0:
			return
		_drag["kind"] = "hold" if dt > 0.0 else "move"   # no hold yet: right pulls one out, left shortens the move
	var q := FINE if fine else SNAP
	if _drag["kind"] == "move":
		var mv := maxf(MIN_MOVE, snappedf(float(_drag["move0"]) + dt, q))
		S.cards[i]["move"] = mv
	else:
		S.cards[i]["hold"] = maxf(0.0, snappedf(float(_drag["hold0"]) + dt, q))
	retimed.emit(false)
	queue_redraw()


func _draw() -> void:
	var S := _S()
	draw_rect(Rect2(Vector2.ZERO, size), Tok.c("tl_bg"))
	var font := get_theme_default_font()
	if S == null or S.cards.size() < 1:
		draw_string(font, Vector2(PAD, 30), "TIMELINE: clip two poses and the scene shows here", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Tok.of("ink:0.4"))
		return
	var ts := S.times()
	var L := S.length()
	# ruler: a tick every 0.1 s, a label every 0.5 s (every 1 s when crowded)
	var step := 0.5 if pps() * 0.5 > 34.0 else 1.0
	var k := 0
	while k * 0.1 <= L + 1e-6:
		var x := x_of(k * 0.1)
		var major := absf(fmod(k * 0.1 + 1e-6, step)) < 2e-6 * 10.0
		draw_line(Vector2(x, RULER - (7.0 if major else 3.0)), Vector2(x, RULER), Color(Tok.c("ink"), 0.35 if major else 0.18), 1.0)
		if major:
			draw_string(font, Vector2(x + 2, 11), str(snappedf(k * 0.1, 0.1)) + "s", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Tok.of("ink:0.45"))
		k += 1
	var y0 := RULER + 2.0
	var h := size.y - y0 - 2.0
	for i in S.cards.size():
		var sel: bool = i == int(m.sel_card)
		var base := Color(0.32, 0.5, 0.82) if i % 2 == 0 else Color(0.28, 0.6, 0.62)
		if sel:
			base = Color(0.95, 0.7, 0.3)
		var xm0 := x_of(ts[i][0])
		var xa := x_of(ts[i][1])
		var xh := x_of(ts[i][2])
		if xa - xm0 > 0.5:
			draw_rect(Rect2(xm0, y0, xa - xm0, h), base.darkened(0.15))
			if float(S.cards[i]["move"]) <= 0.0 and i > 0:   # auto timing: a dashed top edge says "not set by you"
				var dx := xm0
				while dx < xa:
					draw_line(Vector2(dx, y0 + 1), Vector2(minf(dx + 4, xa), y0 + 1), Color(1, 1, 1, 0.55), 1.0)
					dx += 8
		if xh - xa > 0.5:
			draw_rect(Rect2(xa, y0, xh - xa, h), base.darkened(0.55))
			var hx := xa - h
			while hx < xh:   # hatching, clipped to the hold
				var a := Vector2(maxf(hx, xa), y0 + h - (maxf(hx, xa) - hx))
				var b := Vector2(minf(hx + h, xh), y0 + h - (minf(hx + h, xh) - hx))
				draw_line(a, b, Color(base.r, base.g, base.b, 0.35), 1.0)
				hx += 7.0
		# the pose: a bright tick where the card arrives
		draw_line(Vector2(xa, y0), Vector2(xa, y0 + h), Color(1, 1, 1, 0.9 if sel else 0.6), 2.0)
		draw_line(Vector2(xh, y0), Vector2(xh, y0 + h), Color(0, 0, 0, 0.6), 1.0)
		var w := xh - xm0
		if w > 18.0:
			var name := "%d %s" % [i + 1, S.cards[i]["name"]]
			if not sel:   # a shadow: the name stays readable over the hold's hatching
				draw_string(font, Vector2(xm0 + 5, y0 + h * 0.5 + 6), name, HORIZONTAL_ALIGNMENT_LEFT, w - 6, 12, Color(0, 0, 0, 0.8))
			draw_string(font, Vector2(xm0 + 4, y0 + h * 0.5 + 5), name, HORIZONTAL_ALIGNMENT_LEFT, w - 6, 12, Color(0.05, 0.05, 0.07) if sel else Color(1, 1, 1, 0.95))
		elif w > 8.0:
			draw_string(font, Vector2(xm0 + 2, y0 + h * 0.5 + 5), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, w - 2, 11, Color(1, 1, 1, 0.9))
	# the dummy is solid and hit: what PLAYS is the landed copy, which stops at the hit and rebounds. Past its end the
	# cards are still yours but never play: shade them and say why (else the strip and the play time disagree silently)
	var P: Scene = m._ps()
	if P != S and P.length() < L - 1e-3:
		var xc := x_of(P.length())
		draw_rect(Rect2(xc, RULER, size.x - xc, size.y - RULER), Color(0.05, 0.05, 0.06, 0.88))
		draw_line(Vector2(xc, RULER), Vector2(xc, size.y), Color(1, 0.45, 0.35), 2.0)
		draw_string(font, Vector2(xc + 6, y0 + h * 0.5 + 5), ("hit at %.2f s: the rest won't play (H: dummy off)" if size.x - xc > 300.0 else "hit: won't play") % P.length() if size.x - xc > 300.0 else "hit: won't play", HORIZONTAL_ALIGNMENT_LEFT, size.x - xc - 10, 12, Color(1, 0.75, 0.65))
	# hovered edge
	if _hover.get("kind", "") in ["move", "hold", "edge0"] and _drag.is_empty():
		var hi: int = _hover["i"]
		var hxe := x_of(ts[hi][2] if _hover["kind"] == "hold" else ts[hi][1])
		draw_line(Vector2(hxe, y0), Vector2(hxe, y0 + h), Color(1, 0.95, 0.5), 3.0)
	# the value being dragged, beside the edge
	if not _drag.is_empty() and _drag["kind"] in ["move", "hold"]:
		var di: int = _drag["i"]
		var ex := x_of(ts[di][2] if _drag["kind"] == "hold" else ts[di][1])
		var txt := "%s %.2f s" % [_drag["kind"], S.move_time(di) if _drag["kind"] == "move" else float(S.cards[di]["hold"])]
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var bx := clampf(ex + 6, 2, size.x - tw - 10)
		draw_rect(Rect2(bx - 3, y0 + 2, tw + 8, 18), Color(0, 0, 0, 0.85))
		draw_string(font, Vector2(bx + 1, y0 + 16), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.95, 0.5))
	# playhead
	var px := x_of(clampf(float(m.playhead), 0.0, L))
	draw_line(Vector2(px, 0), Vector2(px, size.y), Tok.c("ink"), 2.0)
	draw_colored_polygon(PackedVector2Array([Vector2(px - 5, 0), Vector2(px + 5, 0), Vector2(px, 7)]), Tok.c("ink"))
