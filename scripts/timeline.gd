## TIMELINE (round 6, Nick 10-14): the scene as one strip, the way an editor shows clips. Each card is a block: its MOVE
## (solid: the body travelling into the card's pose) then its HOLD (hatched: standing in it). The tick at the end of a
## move is the pose itself. Drag a card's arrival edge = its move time; drag the end of its hold = its hold time; every
## later card slides along (ripple). A card with no hold: drag its edge RIGHT to pull a hold out, LEFT to shorten the
## move. Each card has a HANDLE on its right edge (ROADMAP 47: 12 px wide, lit on hover and while dragged); the drag snaps
## to whole frames (S.fps; Shift: 0.01 s) and reads "+4 f (0.13 s)" beside the edge. ALT-drag a handle changes only that
## gap: the card's hold and the next card's move trade the time, so no card after the pair moves (clamped, never crossing).
## Click a block = pick that card at its pose; click or drag the ruler = scrub.
## This file only draws and reads the mouse; main.gd owns the scene, undo and the caches (the signals below).
class_name Timeline
extends Control

signal scrubbed(t: float)
signal picked(i: int)
signal retime_started
signal retimed(final: bool)
signal range_set(which: String, t: float)   # WW4: Shift+click on the ruler = in point, Alt+click = out point
signal finding_picked(i: int)   # a finding's mark clicked: the index into m.findings
signal box_picked(i: int)   # ROADMAP 36: a box on the boxes lane clicked: the index into S.boxes

## FRAME DATA (ROADMAP 12; scripts/frame_data.gd): main.gd sets `fd` (the analysis, {} = off) and the strip shows its
## startup (green), active (red) and recovery (blue) in frames, under the ruler. Drawn only; the numbers are FrameData's.
const FD_H := 11.0   # px: the strip's height
var fd: Dictionary = {}

## HIT / HURT BOXES (ROADMAP 36; scripts/hit_boxes.gd lanes): main.gd sets `bx` ([] = none). Two rows under the frame strip:
## the attack boxes in red (top), the vulnerable edits in blue and the invincible ranges in gold (bottom). Drawn only.
const BX_H := 9.0   # px: the lane's height (two rows of 4 px)
var bx: Array = []

const RULER := 12.0      # px: the seconds ruler on top (RR4: 12, the track is on the one strip; was 16)
const PAD := 8.0         # px each side
const GRAB := 6.0        # px: how close counts as "on an edge"
const HANDLE_W := 12.0   # px: a card's right-edge handle (ROADMAP 47); hit within half of it either side
const SNAP := 0.05       # s: the clips' snap (a retime snaps to frames, see _retime_to)
const FINE := 0.01
const AUDIO_H := 20.0    # px: the sound's waveform strip under the cards (only when the scene has a sound)
const MIN_MOVE := 0.04   # s: a move can't be shorter (a 1-frame move at 30 fps is 0.033)
const CLIP_H := 12.0     # px: one row per placed CLIP (scripts/clips.gd), under the cards

var m: Node              # main.gd: reads m.S, m.playhead, m.sel_card

var _drag := {}          # {"kind": "move"/"hold"/"edge0"/"scrub", "i", "x0", "v0", "pps", "t0"}
var _hover := {}

## FINDINGS ON THE TIMELINE (round 23, GATES DD3, UPGRADES #30): after Check each finding is a diamond in the ruler at
## its time (FAIL red, WARN amber); findings within MARK_PX of each other share one mark with their count; a click on
## one goes to the first. Only while Check is fresh (m.findings_live()): an edit clears them until Check runs again
const MARK_PX := 7.0


## [[x, [finding indices]], ...] left to right
func marks() -> Array:
	if m == null or not m.findings_live():
		return []
	var out := []
	var order := range(m.findings.size())
	order.sort_custom(func(a, b): return float(m.findings[a]["t"]) < float(m.findings[b]["t"]))
	for i in order:
		var x := x_of(float(m.findings[i]["t"]))
		if not out.is_empty() and x - float(out[-1][0]) < MARK_PX:
			out[-1][1].append(i)
		else:
			out.append([x, [i]])
	return out


func mark_at(p: Vector2) -> Array:
	if p.y >= RULER:
		return []
	for mk in marks():
		if absf(p.x - float(mk[0])) <= MARK_PX * 0.5 + 1.0:
			return mk[1]
	return []


func _get_tooltip(at: Vector2) -> String:
	var fs := mark_at(at)
	var ck := clip_at(at) if at.y >= RULER else -1
	if ck >= 0:
		var c: Dictionary = _S().clips[ck]
		return "clip %s from %.2f s (%s, blend in %.2f s / out %.2f s)\ndrag: move it in time; click, then 'Clip: edit the picked clip...' to change it" % [
			Clips.label(c), float(c["start"]), c["type"], float(c["bin"]), float(c["bout"])]
	var hv := hit(at) if at.y >= RULER and fs.is_empty() else {}
	if hv.get("kind", "") in ["hold", "edge0"]:
		return "card %d's right edge: drag = retime it in frames (every later card follows)\nAlt-drag = this gap only (the next card's move gives or takes the time)" % (int(hv["i"]) + 1)
	if fs.is_empty():
		return tooltip_text
	var lines := []
	for i in fs:
		var f: Dictionary = m.findings[i]
		lines.append("%s %s at %.2f s: %s" % ["MUST FIX" if f["sev"] == "FAIL" else "look", f["rule"], f["t"], f["msg"]])
	return "
".join(lines) + "
(click: jump there)"


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0, 46)
	clip_contents = true


func _S() -> Scene:
	return m.S if m != null else null


## THE SHOT CAMERA's keys on the strip (scripts/shot_gizmo.gd draws the camera itself): a camera-coloured diamond on the
## strip's bottom edge at each key's time, above the sound's strip. Only the scene's own keys (main.gd _hero_scene)
const CAM_R := 4.0   # px: the diamond's half-size


func cam_times() -> Array:
	var out := []
	if m == null or _S() == null:
		return out
	for k in m._hero_scene().camera:
		out.append(float(k["t"]))
	return out


## the diamonds' centre line (y)
func _cam_y() -> float:
	var ah := AUDIO_H if not _S().audio.is_empty() else 0.0
	return size.y - ah - CAM_R - 2.0


## the time of the camera key whose diamond is at p, or -1.0
func cam_key_at(p: Vector2) -> float:
	if cam_times().is_empty() or absf(p.y - _cam_y()) > CAM_R + 2.0:
		return -1.0
	for t in cam_times():
		if absf(p.x - x_of(float(t))) <= CAM_R + 1.0:
			return float(t)
	return -1.0


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
	var ck := clip_at(p)
	if ck >= 0:
		return {"kind": "clip", "i": ck}
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
			var kt := cam_key_at(ev.position)   # THE SHOT CAMERA: a click on its diamond = the playhead to that key
			if kt >= 0.0:
				scrubbed.emit(kt)
				accept_event()
				return
			var fs := mark_at(ev.position)
			if not fs.is_empty():
				finding_picked.emit(fs[0])
				accept_event()
				return
			var bxi := box_at(ev.position)   # ROADMAP 36: a click on the boxes lane picks that box
			if bxi >= 0:
				box_picked.emit(bxi)
				accept_event()
				return
			var h := hit(ev.position)
			if h.is_empty():
				return
			match h["kind"]:
				"clip":
					_clip_press(h["i"], ev.position.x)
				"ruler" when ev.shift_pressed or ev.alt_pressed:
					range_set.emit("in" if ev.shift_pressed else "out", t_of(ev.position.x))
				"ruler":
					_drag = {"kind": "scrub"}
					scrubbed.emit(t_of(ev.position.x))
				"block":
					picked.emit(h["i"])
				_:
					var i: int = h["i"]
					# retime_started (the one undo step) is emitted at the first real change, not the press: a click moves nothing
					_drag = {"kind": h["kind"], "i": i, "x0": ev.position.x, "pps": pps(), "moved": false, "d": 0.0,
						"alt": ev.alt_pressed, "move0": S.move_time(i), "hold0": float(S.cards[i]["hold"]),
						"nmove0": S.move_time(i + 1) if i + 1 < S.cards.size() else 0.0}
			accept_event()
		elif not _drag.is_empty():
			var was: String = _drag.get("kind", "")
			var moved: bool = _drag.get("moved", true)
			_drag = {}
			if was != "scrub" and moved:
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
		if _drag["kind"] == "clip":
			_clip_drag(ev.position.x, ev.shift_pressed)
			accept_event()
			return
		_retime_to(ev.position.x, ev.shift_pressed)
		accept_event()


## the drag, as card values. The DELTA from where the drag began snaps to whole frames (S.fps; Shift: FINE seconds).
## A plain drag RIPPLES: the card's hold (or its move) takes the delta and every later card shifts by it. ALT (gap mode)
## moves only the gap: a hold handle gives the delta to the NEXT card's move (its arrival stays put), an arrival edge
## gives it to the card's own hold. Each side is clamped so no hold or move goes negative and no card crosses another.
func _retime_to(x: float, fine: bool) -> void:
	var S := _S()
	var i: int = _drag["i"]
	var n := S.cards.size()
	var dx: float = x - float(_drag["x0"])
	if _drag["kind"] == "edge0":
		if absf(dx) < 3.0:
			return
		_drag["kind"] = "hold" if dx > 0.0 else "move"   # no hold yet: right pulls one out, left shortens the move
	var fps := float(S.fps)
	var dt: float = dx / float(_drag["pps"])
	var d: float = snappedf(dt, FINE) if fine else roundf(dt * fps) / fps
	var kind: String = _drag["kind"]
	var h0: float = _drag["hold0"]
	var m0: float = _drag["move0"]
	var gap: bool = bool(_drag["alt"]) and (kind == "move" or i < n - 1)   # the last card has no next gap: alt = plain
	if kind == "hold" and gap:
		d = clampf(d, -h0, float(_drag["nmove0"]) - MIN_MOVE)
	elif kind == "hold":
		d = maxf(d, -h0)
	elif gap:
		d = clampf(d, MIN_MOVE - m0, h0)
	else:
		d = maxf(d, MIN_MOVE - m0)
	if not _drag["moved"]:
		if is_zero_approx(d):
			return
		_drag["moved"] = true
		retime_started.emit()   # main pushes the ONE undo step here, before anything changes
	if kind == "hold" and gap:
		S.cards[i]["hold"] = h0 + d
		S.cards[i + 1]["move"] = float(_drag["nmove0"]) - d
	elif kind == "hold":
		S.cards[i]["hold"] = h0 + d
	elif gap:
		S.cards[i]["move"] = m0 + d
		S.cards[i]["hold"] = h0 - d
	else:
		S.cards[i]["move"] = m0 + d
	_drag["d"] = d
	_drag["gap"] = gap
	retimed.emit(false)
	queue_redraw()


## the sound under the cards: its peak envelope from the offset on (computed once by AudioTrack.envelope), or a flat bar
## with the file name when it cannot be decoded (ogg / mp3) or the file is gone
func _draw_audio(S: Scene, font: Font, y: float, h: float) -> void:
	var env: Dictionary = m.audio_env
	var off := float(S.audio.get("offset", 0.0))
	var len_s := float(env.get("length", 0.0))
	var x0 := x_of(off)
	var nm := String(S.audio.get("path", "")).get_file()
	draw_rect(Rect2(0, y, size.x, h), Tok.of("ink:0.06"))
	if env.get("ok", false):
		var mid := y + h * 0.5
		var col := Tok.of("ink:0.55")
		var x := maxf(x0, 0.0)
		var x1 := minf(x_of(off + len_s), size.x)
		while x < x1:
			var p := AudioTrack.peak(env, t_of(x) - off, t_of(x + 1.0) - off)
			var hh := maxf(p * h * 0.5, 0.5)
			draw_line(Vector2(x, mid - hh), Vector2(x, mid + hh), col, 1.0)
			x += 1.0
		draw_string(font, Vector2(maxf(x0, 0.0) + 3, y + 10), nm, HORIZONTAL_ALIGNMENT_LEFT, 160, 9, Tok.of("ink:0.5"))
	else:
		var wbar := maxf(x_of(off + len_s) - x0, 40.0) if len_s > 0.0 else 40.0
		draw_rect(Rect2(maxf(x0, 0.0), y + h * 0.5 - 2.0, minf(wbar, size.x), 4.0), Tok.of("ink:0.4"))
		var why := ": no waveform for this format" if len_s > 0.0 else " (file missing)"
		draw_string(font, Vector2(maxf(x0, 0.0) + 3, y + h * 0.5 - 4.0), nm + why, HORIZONTAL_ALIGNMENT_LEFT, size.x, 9, Tok.of("ink:0.6"))
	draw_line(Vector2(x0, y), Vector2(x0, y + h), Tok.of("ink:0.6"), 1.0)


## MUSIC BEATS (ROADMAP 32): a thin mark per beat across the sound strip; a bar's first beat (down) is full height and warm
func _draw_beats(S: Scene, y: float, h: float) -> void:
	if S.beats_audio.is_empty() or S.audio.is_empty():
		return
	var off := float(S.audio.get("offset", 0.0))
	for b in S.beats_audio:
		var x := x_of(float(b["t"]) + off)
		if x < -1.0 or x > size.x + 1.0:
			continue
		if b["down"]:
			draw_line(Vector2(x, y), Vector2(x, y + h), Tok.c("beat_down"), 1.5)
		else:
			draw_line(Vector2(x, y + h * 0.55), Vector2(x, y + h), Tok.of("ink:0.45"), 1.0)


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
	var fdh := FD_H + 3.0 if not fd.is_empty() else 0.0   # FRAME DATA (ROADMAP 12): the strip sits under the ruler
	var bxh := bx_px()   # HIT / HURT BOXES (ROADMAP 36): the lane sits under the frame strip
	var y0 := RULER + 2.0 + fdh + bxh
	var ah := AUDIO_H if not S.audio.is_empty() else 0.0
	_clip_fit(S)
	var h := size.y - y0 - 2.0 - ah - _clip_px
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
	# ROADMAP 47: the right-edge handle of every card, HANDLE_W px wide (the hit area is the same width). Idle = a muted strip
	# with two grip lines; lit (focus colour) while the pointer is on it or it is being dragged
	var hov_i := int(_hover.get("i", -1)) if _hover.get("kind", "") in ["hold", "edge0"] else -1
	var drag_i := int(_drag.get("i", -1)) if _drag.get("kind", "") in ["hold", "edge0"] else -1
	for i in S.cards.size():
		var hx := x_of(ts[i][2])
		var lit: bool = i == hov_i or i == drag_i
		draw_rect(Rect2(hx - HANDLE_W * 0.5, y0, HANDLE_W, h), Tok.c("focus") if lit else Tok.of("ink:0.3"))
		for g in [-1.5, 1.5]:
			draw_line(Vector2(hx + g, y0 + h * 0.35), Vector2(hx + g, y0 + h * 0.65), Tok.c("tl_bg"), 1.0)
	if ah > 0.0:
		_draw_audio(S, font, size.y - ah, ah - 1.0)
		_draw_beats(S, size.y - ah, ah - 1.0)
	_draw_clips(S, font)
	if not fd.is_empty():
		_draw_fd_strip(font, RULER + 2.0)
	if not bx.is_empty():
		_draw_bx_lane(RULER + 2.0 + (FD_H + 3.0 if not fd.is_empty() else 0.0))
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
	if not _drag.is_empty() and _drag["kind"] in ["move", "hold"] and _drag.get("moved", false):
		var di: int = _drag["i"]
		var ex := x_of(ts[di][2] if _drag["kind"] == "hold" else ts[di][1])
		var dd := float(_drag["d"])
		var txt := "%s%+d f (%.2f s)" % ["gap " if _drag.get("gap", false) else "", roundi(dd * float(S.fps)), dd]
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var bx := clampf(ex + 6, 2, size.x - tw - 10)
		draw_rect(Rect2(bx - 3, y0 + 2, tw + 8, 18), Color(0, 0, 0, 0.85))
		draw_string(font, Vector2(bx + 1, y0 + 16), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.95, 0.5))
	# the findings' marks, over the ruler
	# COMPARE WITH (ROADMAP 28): the frames where the compared version differs (a joint over 2 deg): magenta ticks on the ruler
	if m != null and not m.vdiff.is_empty():
		for mk in m.vdiff["marks"]:
			var xv := x_of(float(mk["t"]))
			draw_line(Vector2(xv, 0.0), Vector2(xv, RULER + 2.0), Tok.c("vdiff"), 2.0)
	for mk in marks():
		var fail: bool = mk[1].any(func(i): return m.findings[i]["sev"] == "FAIL")
		var c := Tok.c("fail") if fail else Tok.c("warn")
		var x: float = mk[0]
		draw_colored_polygon(PackedVector2Array([Vector2(x, 1), Vector2(x + 5, 7), Vector2(x, 13), Vector2(x - 5, 7)]), c)
		if mk[1].size() > 1:
			draw_string(font, Vector2(x + 6, 12), str(mk[1].size()), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, c)
	# the preview range (WW4): shaded outside, edges marked
	var pr := PreviewRange.span(float(m.pv_in), float(m.pv_out), L)
	if not pr.is_empty():
		var xa0 := x_of(pr[0])
		var xb0 := x_of(pr[1])
		draw_rect(Rect2(0, 0, maxf(xa0, 0.0), size.y), Color(0, 0, 0, 0.45))
		draw_rect(Rect2(xb0, 0, maxf(size.x - xb0, 0.0), size.y), Color(0, 0, 0, 0.45))
		draw_rect(Rect2(xa0, 0, xb0 - xa0, 3), Tok.c("warn"))
		draw_line(Vector2(xa0, 0), Vector2(xa0, size.y), Tok.c("warn"), 1.0)
		draw_line(Vector2(xb0, 0), Vector2(xb0, size.y), Tok.c("warn"), 1.0)
	# MARKERS (round 41, WW5): a small flag on the ruler at each marker's time, coloured by its kind
	for mk in S.markers:
		var fx := x_of(float(mk["t"]))
		var fc: Color = Markers.COLORS.get(String(mk["kind"]), Color.WHITE)
		draw_line(Vector2(fx, 0), Vector2(fx, RULER), fc, 1.0)
		draw_colored_polygon(PackedVector2Array([Vector2(fx, 0), Vector2(fx + 6, 3), Vector2(fx, 6)]), fc)
	# THE SHOT CAMERA's keys: a camera-coloured diamond at each key's time (cam_key_at takes a click on it)
	var cy := _cam_y()
	for t in cam_times():
		var cx := x_of(float(t))
		draw_colored_polygon(PackedVector2Array([Vector2(cx, cy - CAM_R), Vector2(cx + CAM_R, cy), Vector2(cx, cy + CAM_R), Vector2(cx - CAM_R, cy)]), ShotGizmo.COLOR)
	# playhead
	var px := x_of(clampf(float(m.playhead), 0.0, L))
	draw_line(Vector2(px, 0), Vector2(px, size.y), Tok.c("ink"), 2.0)
	draw_colored_polygon(PackedVector2Array([Vector2(px - 5, 0), Vector2(px + 5, 0), Vector2(px, 7)]), Tok.c("ink"))


# ---------------------------------------------------------------- CLIPS (GAP_ANALYSIS row 12; scripts/clips.gd)
## each placed clip is a bar on its own row under the cards: from its start to start + L x repeat / speed, a thin line
## at each repeat, the blend in / out drawn as darkened ramps. Click = pick it (m.clips_ui.sel); drag = move it in time
## (snapped to SNAP, FINE with Shift): ONE undo step, pushed on the first move (a click alone pushes none)
var _clip_px := 0.0      # px the clip rows take (added to the minimum height the caller set)


func _clip_fit(S: Scene) -> void:
	var want := S.clips.size() * CLIP_H + (2.0 if not S.clips.is_empty() else 0.0)
	if absf(want - _clip_px) > 0.1:
		set_deferred("custom_minimum_size", Vector2(custom_minimum_size.x, custom_minimum_size.y + want - _clip_px))
		_clip_px = want
		if m != null and m.has_method("_layout_bottom"):
			m.call_deferred("_layout_bottom")   # the bottom panel makes room for the rows


## the height the clip rows add (main adds it back when it sets the strip's height itself)
func clip_px() -> float:
	return _clip_px


func _clip_sel() -> int:
	var cu = m.get("clips_ui") if m != null else null
	return int(cu.sel) if cu != null else -1


## clip k's bar on the timeline
func clip_rect(k: int) -> Rect2:
	var S := _S()
	var c: Dictionary = S.clips[k]
	var e := Clips.source(String(c["src"]))
	var L := float(e.get("len", 0.5))
	var y := size.y - (AUDIO_H if not S.audio.is_empty() else 0.0) - _clip_px + k * CLIP_H
	var x0 := x_of(float(c["start"]))
	return Rect2(x0, y, maxf(x_of(float(c["start"]) + Clips.length_of(c, L)) - x0, 6.0), CLIP_H - 2.0)


func clip_at(p: Vector2) -> int:
	var S := _S()
	if S == null:
		return -1
	for k in S.clips.size():
		if clip_rect(k).grow(1.0).has_point(p):
			return k
	return -1


func _clip_press(k: int, x: float) -> void:
	var cu = m.get("clips_ui")
	if cu != null:
		cu.sel = k
	_drag = {"kind": "clip", "i": k, "x0": x, "pps": pps(), "start0": float(_S().clips[k]["start"]), "moved": false}
	queue_redraw()


func _clip_drag(x: float, fine: bool) -> void:
	if not _drag["moved"]:
		if absf(x - float(_drag["x0"])) < 3.0:
			return
		_drag["moved"] = true
		retime_started.emit()   # main pushes the ONE undo step here
	var q := FINE if fine else SNAP
	var t := maxf(0.0, snappedf(float(_drag["start0"]) + (x - float(_drag["x0"])) / float(_drag["pps"]), q))
	_S().clips[int(_drag["i"])]["start"] = t
	retimed.emit(false)
	queue_redraw()


## the index (into S.boxes) of the box on the boxes lane under p, or -1
func box_at(p: Vector2) -> int:
	if bx.is_empty():
		return -1
	var y0 := RULER + 2.0 + (FD_H + 3.0 if not fd.is_empty() else 0.0)
	if p.y < y0 or p.y > y0 + BX_H:
		return -1
	for b in bx:
		var x0 := x_of(float(b["t0"]))
		var x1 := maxf(x_of(float(b["t1"])), x0 + 2.0)
		if p.x >= x0 and p.x <= x1:
			return int(b["i"])
	return -1


## the lane's height on the timeline (0 with no boxes)
func bx_px() -> float:
	return BX_H + 3.0 if not bx.is_empty() else 0.0


## the boxes lane: attack boxes on the top row (red), vulnerable edits below (blue), invincible ranges (gold, hatched)
func _draw_bx_lane(y: float) -> void:
	var cols := {"hit": Color(0.92, 0.28, 0.26), "hurt": Color(0.3, 0.52, 0.95), "inv": Color(0.95, 0.8, 0.25)}
	for b in bx:
		var x0 := x_of(float(b["t0"]))
		var x1 := x_of(float(b["t1"]))
		var row_y := y + (0.0 if int(b["row"]) == 0 else 5.0)
		draw_rect(Rect2(x0, row_y, maxf(x1 - x0 - 1.0, 2.0), 4.0), cols[b["kind"]])
		if b["kind"] == "inv":
			var hx := x0
			while hx < x1:   # hatching: invincible reads as a different thing from a blue edit
				draw_line(Vector2(hx, row_y + 4.0), Vector2(minf(hx + 4.0, x1), row_y), Color(0.05, 0.05, 0.07, 0.7), 1.0)
				hx += 6.0


## the frame strip: one block per phase over its frames (time = frame / fps), its count in the block
func _draw_fd_strip(font: Font, y: float) -> void:
	var fps := float(fd["fps"])
	var cols := {"startup": Tok.c("fd_startup"), "active": Tok.c("fd_active"), "recovery": Tok.c("fd_recovery")}
	for sp in FrameData.spans(fd):
		var x0 := x_of(float(sp["f0"]) / fps)
		var x1 := x_of(float(sp["f1"]) / fps)
		var n := int(sp["f1"]) - int(sp["f0"])
		if sp["kind"] == "active":
			# a multi-hit span: the frames with a hitbox out are full red, the gaps between them dim
			draw_rect(Rect2(x0, y, maxf(x1 - x0 - 1.0, 1.0), FD_H), Color(Tok.c("fd_active"), 0.22))
			for f in range(int(sp["f0"]), int(sp["f1"])):
				if fd["frames"][f]["active"]:
					var fx := x_of(float(f) / fps)
					draw_rect(Rect2(fx, y, maxf(x_of(float(f + 1) / fps) - fx - 1.0, 1.0), FD_H), cols["active"])
		else:
			draw_rect(Rect2(x0, y, maxf(x1 - x0 - 1.0, 1.0), FD_H), cols[sp["kind"]])
		if x1 - x0 > 46.0:
			draw_string(font, Vector2(x0 + 3, y + FD_H - 2.0), "%s %d" % [sp["kind"], n], HORIZONTAL_ALIGNMENT_LEFT, x1 - x0 - 4, 10, Tok.c("fd_ink"))
		elif x1 - x0 > 14.0:
			draw_string(font, Vector2(x0 + 2, y + FD_H - 2.0), str(n), HORIZONTAL_ALIGNMENT_LEFT, x1 - x0 - 3, 10, Tok.c("fd_ink"))


func _draw_clips(S: Scene, font: Font) -> void:
	var sel := _clip_sel()
	for k in S.clips.size():
		var c: Dictionary = S.clips[k]
		var r := clip_rect(k)
		var e := Clips.source(String(c["src"]))
		draw_rect(r, Tok.c("accent") if not bool(c.get("mute", false)) else Tok.of("ink:0.3"))
		if e.is_empty():
			draw_string(font, Vector2(r.position.x + 3, r.position.y + 9), String(c["src"]).get_file() + ": file missing", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Tok.c("on_accent"))
			continue
		var L := float(e["len"])
		var shade := Tok.of("tl_bg:0.55")
		var bi := float(c["bin"]) * pps()
		var bo := float(c["bout"]) * pps()
		if bi > 1.0:   # the blend in: a ramp from no weight at the start to the full weight
			draw_colored_polygon(PackedVector2Array([r.position, r.position + Vector2(minf(bi, r.size.x), 0), r.position + Vector2(0, r.size.y)]), shade)
		if bo > 1.0:
			var xr := r.end.x
			draw_colored_polygon(PackedVector2Array([Vector2(xr, r.position.y), Vector2(xr, r.end.y), Vector2(xr - minf(bo, r.size.x), r.position.y)]), shade)
		for i in range(1, int(c["repeat"])):   # each repeat's seam
			var xs := x_of(float(c["start"]) + L * i / float(c["speed"]))
			draw_line(Vector2(xs, r.position.y), Vector2(xs, r.end.y), Tok.of("on_accent:0.6"), 1.0)
		draw_string(font, Vector2(r.position.x + 3, r.position.y + 9), Clips.label(c), HORIZONTAL_ALIGNMENT_LEFT, maxf(r.size.x - 4, 1.0), 9, Tok.c("on_accent"))
		if k == sel:
			draw_rect(r.grow(0.5), Tok.c("focus"), false, 1.5)
