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
signal shot_cut(i: int, t: float, final: bool)   # ROADMAP 75: shot i's cut dragged to t (final = the mouse went up)
signal marker_moved(i: int, t: float, done: bool)   # ROADMAP 97: marker i dragged to t (whole frames; done = the mouse went up)
signal marker_picked(i: int)   # ROADMAP 97: a marker clicked without a drag: the index into S.markers (main opens its popover)

## THE SHOTS LANE (ROADMAP 75; main.gd _shot_*): one row under the boxes lane, a segment per shot from its cut to the next
## (the shot on at the playhead is lit). A cut is its segment's left edge: drag it (whole frames, between its neighbours) to
## move it; a click on the lane scrubs. Drawn only when the scene has shots (main sets nothing: it reads the hero's list).
const SHOTS_H := 12.0   # px: the lane's height
signal audio_picked_lane(i: int)   # ROADMAP 77: a sound lane clicked (not its name): the index into S.audio_tracks
signal audio_name(i: int)   # ROADMAP 77: a sound lane's NAME clicked: that track is muted / unmuted
signal audio_drag_started(i: int)   # ROADMAP 77: a lane dragged past 3 px: main pushes the ONE undo step here

## FRAME DATA (ROADMAP 12; scripts/frame_data.gd): main.gd sets `fd` (the analysis, {} = off) and the strip shows its
## startup (green), active (red) and recovery (blue) in frames, under the ruler. Drawn only; the numbers are FrameData's.
const FD_H := 11.0   # px: the strip's height
const RX_ROW := 12.0   # px: the reactable row under the strip (L15: its own labelled row, cells ReactableCells.H tall)
var fd: Dictionary = {}:
	set(v):
		fd = v
		_rx_sync()
var rx: ReactableCells = null   # N082 wired (L11): one cell per frame under the strip, tell green / red (scripts/reactable_cells.gd)
var _rx_src: Dictionary = {}

## HIT / HURT BOXES (ROADMAP 36; scripts/hit_boxes.gd lanes): main.gd sets `bx` ([] = none). Two rows under the frame strip:
## the attack boxes in red (top), the vulnerable edits in blue and the invincible ranges in gold (bottom). Drawn only.
const BX_H := 9.0   # px: the lane's height (two rows of 4 px)
var bx: Array = []

## IK SPACES (ROADMAP 63; LimbIK.space_lane): main.gd sets `sp` ([] = none). One row per limb that has a key in a space, under
## the boxes lane: a block per run of keys in one space, labelled with the limb and the space (world dim). Drawn only.
const SP_H := 11.0   # px: one limb's row
var sp: Array = []

## MAKE IT PHYSICAL (I1; scripts/make_physical.gd lane()): main.gd sets `ph` ([] = none). One lane under the boxes lane: a RED block per span
## the body cannot do (the reason in its tooltip), a thin gold block for the clip's own authored foot slide (a note, not red).
const PH_H := 12.0
var ph: Array = []
signal ph_picked(i: int)   # I1: a red block clicked: its index in main's spans (-1 = a note)
var bf: Array = []        # FIGHT TO THE BEAT (I15; beat_fight_ui.gd): [{"t", "ok", "why"}] the contacts: fitted on a beat, or flagged
var bk: Array = []        # BREAKFALL CHECK (I25; breakfall_ui.gd): [{"t0", "t1", "cls": ok / warn / fail, "txt"}] a badge per fall
var sh: Array = []        # SELL THE HIT (I21; sell_hit_ui.gd): [{"t0", "t1", "cls": sold / notsold / unsafe}] a badge per strike
var rh: Array = []        # FIGHT RHYTHM (I19; fight_rhythm_ui.gd): [{t, who, type: strike / block / step / feint}] one tick per action
var sc: Array = []        # SOUND CUES (I35; sound_cues_ui.gd): [{t, kind (whoosh / hit_head / hit_body / hit_weapon / step), strength 0..1}] a mark each, its size the strength
var pc: Array = []        # PRECOG CHECK (I31; precog_ui.gd): [{t (the reaction's start), status: precog / late / both / ok}] a badge each
var fa: Array = []        # FATIGUE (I34; exertion_ui.gd): [{who, t0, t1, f 0..1}] a green-to-red strip per fighter along the bottom of the track
var fa_n := 0
var ml: Array = []        # MOMENTUM LEDGER (I36; momentum_ui.gd): [{t (the arrival of the card), flag, kind: linear / spin}] a STOP badge each flagged transition
var spn: Array = []        # AIRBORNE SPIN (I43; spin_check_ui.gd): [{t0, t1, ys, ps (COM height actual / free-fall parabola, m), flag, txt}] a box per flight with its arc
var rh_flags: Array = []  # [{t0, t1}] the stretches the rhythm flags
var rd: Array = []        # REACTION DIRECTION (I33; reaction_dir_ui.gd): [{"t0", "t1", "cls": ok / bad, "txt"}] a badge per hit
var dk: Array = []        # FIGHT DISTANCE KEEPER (I18; distance_keeper_ui.gd): [{"t0", "t1", "cls": jammed / out / in}] a colour band per strike
var cg: Array = []        # CHOREOGRAPH (I22): the music energy per beat [{"t0","t1","e" 0..1}], a strip along the cards
var cg_peak := -1.0      # the loudest downbeat strike time (marked BIG)
var bf_grid: Array = []   # the beats (scene time) the fit lands on: ticks down the track
var ph_sel := -1   # the red span picked (a click on it), -1 = none


func ph_px() -> float:
	return PH_H + 3.0 if not ph.is_empty() else 0.0


func _ph_y() -> float:
	return RULER + 2.0 + fd_px() + (BX_H + 3.0 if not bx.is_empty() else 0.0)


## the block under p on the physical lane (an index into ph), or -1
func ph_at(p: Vector2) -> int:
	if ph.is_empty() or p.y < _ph_y() or p.y > _ph_y() + PH_H:
		return -1
	for i in range(ph.size() - 1, -1, -1):
		var b: Dictionary = ph[i]
		if p.x >= x_of(float(b["t0"])) and p.x <= maxf(x_of(float(b["t1"])), x_of(float(b["t0"])) + 3.0):
			return i
	return -1


func _draw_ph_lane(font: Font) -> void:
	var y := _ph_y()
	for i in ph.size():
		var b: Dictionary = ph[i]
		var x0 := x_of(float(b["t0"]))
		var x1 := maxf(x_of(float(b["t1"])), x0 + 3.0)
		var tone := String(b.get("tone", "yellow" if bool(b["yellow"]) else "red"))
		if tone == "yellow":
			draw_rect(Rect2(x0, y + PH_H - 4.0, x1 - x0, 3.0), Tok.c("beat_down"))
			continue
		# A1: red = no solution, blue = edited since the judge read it (not simulated), gray = not processed yet
		var col: String = {"red": "fd_active", "blue": "fd_recovery", "gray": "pick_lock"}[tone]
		draw_rect(Rect2(x0, y, x1 - x0, PH_H - 1.0), Tok.c(col))
		if i == ph_sel:
			draw_rect(Rect2(x0, y, x1 - x0, PH_H - 1.0), Tok.c("focus"), false, 2.0)
		if x1 - x0 > 40.0:
			draw_string(font, Vector2(x0 + 3.0, y + PH_H - 3.0), String(b["kind"]), HORIZONTAL_ALIGNMENT_LEFT, x1 - x0 - 4.0, 9, Tok.c("fd_ink"))

const RULER := 12.0      # px: the seconds ruler on top (RR4: 12, the track is on the one strip; was 16)
const PAD := 8.0         # px each side
const GRAB := 6.0        # px: how close counts as "on an edge"
const HANDLE_W := 12.0   # px: a card's right-edge handle (ROADMAP 47); hit within half of it either side
const SNAP := 0.05       # s: the clips' snap (a retime snaps to frames, see _retime_to)
const FINE := 0.01
const LANE_H := 14.0     # px: one sound lane (ROADMAP 77: one thin lane per track, under the cards, track 0 on top)
const MIN_MOVE := 0.04   # s: a move can't be shorter (a 1-frame move at 30 fps is 0.033)
const CLIP_H := 20.0     # px: one row per placed CLIP (scripts/clips.gd), under the cards
const WARP_H := 58.0     # px: the picked clip's row is taller by this: its TIME WARP panel (ROADMAP 83; scripts/clips.gd warp_*)

var m: Node              # main.gd: reads m.S, m.playhead, m.sel_card

var _drag := {}          # {"kind": "move"/"hold"/"edge0"/"scrub", "i", "x0", "v0", "pps", "t0"}
var _hover := {}
var mark_sel := -1         # ROADMAP 97: the marker whose popover is open (outlined on the ruler), -1 = none

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
	var pi := ph_at(at)   # I1: a red block says why the body cannot do it
	if pi >= 0:
		var pb: Dictionary = ph[pi]
		return "%s (%.2f to %.2f s)%s" % [pb["reason"], float(pb["t0"]), float(pb["t1"]), "" if String(pb["tone"]) != "red" else "
click to pick this span; 'Accept span' (CHECK page) replaces its cards with the physical version"]
	if _in_shots_lane(at):   # ROADMAP 75: a shot on the lane names itself in full (its label may be cut to fit)
		var si := _shot_at_x(at.x)
		if si >= 0:
			var sh := _shots()
			var end_t := float(sh[si + 1]["t"]) if si + 1 < sh.size() else _S().length()
			return "shot %d: %s (%.2f s to %.2f s)
click to scrub there; drag a cut to move it" % [si + 1, String(sh[si]["name"]), float(sh[si]["t"]), end_t]
	var mi := marker_at(at) if m != null else -1   # ROADMAP 97: a marker's flag shows its note (its name when it has none)
	if mi >= 0:
		var mk: Dictionary = _S().markers[mi]
		if mk.has("note"):
			return String(mk["note"])
		return "%s (%s) at %s: click to edit it, drag to move it" % [mk["name"], mk["kind"], Units.time(mk["t"], _S().fps)]
	if rx != null and rx.visible and not fd.is_empty():   # L15: a cell of the react row says its frame and state
		var ry := RULER + 2.0 + FD_H + 2.0
		if at.y >= ry and at.y <= ry + RX_ROW:
			var tip := rx.tip_at(at.x)
			if tip != "":
				return tip
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
	_ph.mouse_filter = Control.MOUSE_FILTER_IGNORE   # ROADMAP 99: the playhead overlay (clicks go to the timeline)
	_ph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ph.draw.connect(_draw_playhead)
	add_child(_ph)


func _S() -> Scene:
	return m.S if m != null else null


## THE SHOT CAMERA's keys on the strip (scripts/shot_gizmo.gd draws the camera itself): a camera-coloured diamond on the
## strip's bottom edge at each key's time, above the sound's strip. Only the scene's own keys (main.gd _hero_scene)
const CAM_R := 4.0   # px: the diamond's half-size


func cam_times() -> Array:
	var out := []
	if m == null or _S() == null:
		return out
	for sh in m._hero_scene().shots:
		for k in sh["keys"]:
			out.append(float(k["t"]))
	return out


## THE SHOTS LANE (ROADMAP 75): the hero's shots ([] = none), the lane's height and top
func _shots() -> Array:
	return m._hero_scene().shots if m != null and _S() != null else []


func shots_px() -> float:
	return SHOTS_H + 3.0 if not _shots().is_empty() else 0.0


func _shots_y() -> float:
	return RULER + 2.0 + fd_px() + bx_px()


func _in_shots_lane(p: Vector2) -> bool:
	return not _shots().is_empty() and p.y >= _shots_y() and p.y <= _shots_y() + SHOTS_H


## the index of the shot whose cut is under p on the shots lane (within 6 px), or -1
func shot_cut_at(p: Vector2) -> int:
	if not _in_shots_lane(p):
		return -1
	var best := -1
	var bd := 6.0
	var sh := _shots()
	for i in sh.size():
		var d := absf(p.x - x_of(float(sh[i]["t"])))
		if d <= bd:
			best = i
			bd = d
	return best


## the lane's segments: a bar per shot from its cut to the next cut (or the end); the one on at the playhead is lit
func _draw_shots_lane(y: float) -> void:
	var sh := _shots()
	var font := get_theme_default_font()
	var L := _S().length()
	var on: int = m.shot_now_index()
	for i in sh.size():
		var sp := _shot_span(i)
		var x0 := sp.x
		var x1 := sp.y
		var act := i == on
		draw_rect(Rect2(x0, y, maxf(x1 - x0 - 1.0, 2.0), SHOTS_H), Tok.c("accent") if act else Tok.of("ink:0.22"))
		draw_line(Vector2(x0, y - 1.0), Vector2(x0, y + SHOTS_H + 1.0), Tok.c("ink"), 2.0 if i > 0 else 1.0)   # the cut
		if x1 - x0 > 16.0:
			draw_string(font, Vector2(x0 + 3, y + SHOTS_H - 3.0), shot_label_fit(i, x1 - x0), HORIZONTAL_ALIGNMENT_LEFT, x1 - x0 - 5.0, 9, Tok.c("on_accent") if act else Tok.c("ink"))


## shot i's segment on the lane in x: from its cut to the next cut (or the end of the scene)
func _shot_span(i: int) -> Vector2:
	var sh := _shots()
	var x0 := x_of(float(sh[i]["t"]))
	var x1 := x_of(float(sh[i + 1]["t"]) if i + 1 < sh.size() else _S().length())
	return Vector2(x0, x1)


## the shot whose segment covers x on the lane, or -1
func _shot_at_x(x: float) -> int:
	for i in _shots().size():
		var sp := _shot_span(i)
		if x >= sp.x and x < sp.y:
			return i
	return -1


## the label drawn on shot i's segment, "n name" (the first shot also says SHOTS). It is cut with an ellipsis ONLY when the
## segment is narrower than the label; the full name is then the tooltip (_get_tooltip)
func shot_label_fit(i: int, box_w: float) -> String:
	var font := get_theme_default_font()
	var full := "%s%d %s" % ["SHOTS  " if i == 0 else "", i + 1, String(_shots()[i]["name"])]
	var avail := box_w - 5.0
	if font.get_string_size(full, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x <= avail:
		return full
	var t := full
	while t.length() > 0 and font.get_string_size(t + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x > avail:
		t = t.substr(0, t.length() - 1)
	return t + "…" if t.length() > 0 else ""


## a shot's cut dragged to x: whole frames, never onto its neighbours' cuts (the order stays)
func _shot_cut_drag(x: float) -> void:
	var sh := _shots()
	var i: int = _drag["i"]
	if not _drag["moved"]:
		if absf(x - float(_drag["x0"])) < 3.0:
			return
		_drag["moved"] = true
	var fps := float(_S().fps)
	var lo := roundi(float(sh[i - 1]["t"]) * fps) + 1
	var hi := roundi(float(sh[i + 1]["t"]) * fps) - 1 if i + 1 < sh.size() else roundi(_S().length() * fps)
	var fr := clampi(roundi(t_of(x) * fps), lo, maxi(lo, hi))
	_drag["t"] = float(fr) / fps
	shot_cut.emit(i, float(_drag["t"]), false)
	queue_redraw()


## the diamonds' centre line (y)
func _cam_y() -> float:
	return size.y - audio_h() - iq_px() - CAM_R - 2.0


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
	if m != null and m.has_method("rig_len"):
		L = maxf(L if S != null and not S.cards.is_empty() else 0.0, m.rig_len())   # OWN RIG (L78): the rig's keys count toward the strip's length
		if L <= 0.0:
			L = 1.0
	return (size.x - 2.0 * PAD) / maxf(L, 0.5)


## the frame-data block's height: the strip, plus the reactable row under it while its cells are showing
func fd_px() -> float:
	if fd.is_empty():
		return 0.0
	return FD_H + 3.0 + (RX_ROW if rx != null and rx.visible else 0.0)


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
	var wh := warp_hit(p)   # the picked clip's time curve: a knot (j) or its empty panel (j = -1)
	if not wh.is_empty():
		return wh
	var ik := inplace_at(p)
	if ik >= 0:
		return {"kind": "inplace", "i": ik}
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
			var nt := note_t_at(ev.position)   # ROADMAP 29: a review note's mark on the ruler = the playhead to its frame
			if nt >= 0.0:
				scrubbed.emit(nt)
				accept_event()
				return
			var mki := marker_at(ev.position)   # ROADMAP 97: a marker's flag: a click opens it, a drag moves it by whole frames
			if mki >= 0:
				_drag = {"kind": "marker", "i": mki, "x0": ev.position.x, "f0": Markers.frame_of(float(S.markers[mki]["t"]), S.fps), "moved": false}
				accept_event()
				return
			var fs := mark_at(ev.position)
			if not fs.is_empty():
				finding_picked.emit(fs[0])
				accept_event()
				return
			var sci := shot_cut_at(ev.position)   # ROADMAP 75: a cut on the shots lane = scrub there; a later cut is dragged
			if sci > 0:
				_drag = {"kind": "shot", "i": sci, "x0": ev.position.x, "moved": false, "t": float(_shots()[sci]["t"])}
				scrubbed.emit(float(_shots()[sci]["t"]))
				accept_event()
				return
			if sci == 0 or _in_shots_lane(ev.position):
				_drag = {"kind": "scrub"}
				scrubbed.emit(float(_shots()[sci]["t"]) if sci >= 0 else t_of(ev.position.x))
				accept_event()
				return
			var pbi := ph_at(ev.position)   # I1: a click on a red block picks the span and moves the playhead to its start
			if pbi >= 0:
				ph_picked.emit(pbi if String(ph[pbi].get("tone", "red")) == "red" else -1)
				scrubbed.emit(float(ph[pbi]["t0"]))
				_drag = {"kind": "scrub"}
				accept_event()
				return
			var iqs := iq_span_at(ev.position)   # VIDEO IQ: a click on the confidence lane = the playhead goes there; on a span, to its start
			if iqs != -2:
				scrubbed.emit(float(S.iq["spans"][iqs]["t0"]) if iqs >= 0 else t_of(ev.position.x))
				_drag = {"kind": "scrub"}
				accept_event()
				return
			var bxi := box_at(ev.position)   # ROADMAP 36: a click on the boxes lane picks that box
			if bxi >= 0:
				box_picked.emit(bxi)
				accept_event()
				return
			var al := audio_lane_at(ev.position)   # ROADMAP 77: a sound lane; its name mutes, the rest picks and drags the offset
			if al >= 0:
				if audio_name_at(ev.position):
					audio_name.emit(al)
				else:
					audio_picked_lane.emit(al)
					_drag = {"kind": "audio", "i": al, "x0": ev.position.x, "pps": pps(), "moved": false, "off0": float(S.audio_tracks[al]["offset"])}
					queue_redraw()
				accept_event()
				return
			var h := hit(ev.position)
			if h.is_empty():
				return
			match h["kind"]:
				"inplace":   # W08: the clip's In place chip
					var cu = m.get("clips_ui")
					if cu != null:
						cu.sel = int(h["i"])
						cu.toggle_inplace(int(h["i"]))
				"clip":
					_clip_press(h["i"], ev.position.x)
				"warp":
					_warp_press(h["i"], h["j"], ev.position)
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
		elif not _drag.is_empty() and _drag["kind"] == "shot":
			if _drag["moved"]:
				shot_cut.emit(int(_drag["i"]), float(_drag["t"]), true)
			_drag = {}
			queue_redraw()
			accept_event()
		elif not _drag.is_empty() and _drag["kind"] == "marker":
			var mi: int = _drag["i"]
			if _drag["moved"]:
				marker_moved.emit(mi, Markers.time_of_frame(int(_drag["last"]), S.fps), true)
			else:
				marker_picked.emit(mi)
			_drag = {}
			queue_redraw()
			accept_event()
		elif not _drag.is_empty():
			var was: String = _drag.get("kind", "")
			var moved: bool = _drag.get("moved", true)
			_drag = {}
			if was != "scrub" and was != "audio" and moved:
				retimed.emit(true)
			queue_redraw()
			accept_event()
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed and m != null and m.get("clips_ui") != null:
		var wh := warp_hit(ev.position)   # right-click a knot of the picked clip's time curve = take it out (one undo step)
		if not wh.is_empty() and int(wh["j"]) >= 0:
			m.clips_ui.warp_remove(int(wh["i"]), int(wh["j"]))
			accept_event()
	elif ev is InputEventMouseMotion:
		if not _drag.is_empty() and _drag["kind"] == "shot":
			_shot_cut_drag(ev.position.x)
			accept_event()
			return
		if _drag.is_empty():
			var h := hit(ev.position)
			mouse_default_cursor_shape = Control.CURSOR_HSIZE if h.get("kind", "") in ["move", "hold", "edge0"] or shot_cut_at(ev.position) > 0 else Control.CURSOR_ARROW
			if h != _hover:
				_hover = h
				queue_redraw()
			return
		if _drag["kind"] == "scrub":
			scrubbed.emit(t_of(ev.position.x))
			return
		if _drag["kind"] == "marker":
			var f := clampi(Markers.frame_of(t_of(ev.position.x), S.fps), 0, Markers.frame_of(S.length(), S.fps))
			if f != int(_drag.get("last", _drag["f0"])):
				_drag["last"] = f
				_drag["moved"] = true
				marker_moved.emit(int(_drag["i"]), Markers.time_of_frame(f, S.fps), false)
			accept_event()
			return
		if _drag["kind"] == "clip":
			_clip_drag(ev.position.x, ev.shift_pressed)
			accept_event()
			return
		if _drag["kind"] == "warp":
			_warp_drag(ev.position)
			accept_event()
			return
		if _drag["kind"] == "audio":
			_audio_drag(ev.position.x, ev.shift_pressed)
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
	if i >= n:   # the cards were rebuilt under the drag (an undo, a Fix): nothing to drag any more
		_drag = {}
		return
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


## THE CONFIDENCE LANE (VIDEO IQ, scripts/video_iq.gd): one thin lane under the cards (above the sound lanes) when the scene came
## from a video (Scene.iq) and the lane is on (main.iq_show, the "Video: confidence lane and footprints" command). A block per
## frame coloured by the tracker's confidence (VideoIQ.lane_colour: green sure, gold unsure, red lost), the low spans named
## ("left hand lost 2.1-2.6 s"). A click on the lane moves the playhead (to a span's start when it is on one)
const IQ_H := 16.0   # px: the lane's height (a 5 px bar of confidence colours, the span names under it)
const IQ_BAR := 5.0


func iq_px() -> float:
	var S := _S()
	if S == null or m == null or not bool(m.get("iq_show")) or S.iq.is_empty() or not (S.iq.get("conf", null) is Array):
		return 0.0
	return IQ_H


## the lane's rectangle (zero-size when it is not shown)
func iq_rect() -> Rect2:
	var h := iq_px()
	return Rect2(0.0, size.y - audio_h() - h, size.x, h)


## -2 = p is not on the lane; -1 = on the lane, on no span; else the span's index in Scene.iq["spans"]
func iq_span_at(p: Vector2) -> int:
	var r := iq_rect()
	if r.size.y <= 0.0 or not r.has_point(p):
		return -2
	var t := t_of(p.x)
	var sp_ := _S().iq.get("spans", []) as Array
	for i in sp_.size():
		if t >= float(sp_[i]["t0"]) - 1e-6 and t <= float(sp_[i]["t1"]) + 1.0 / maxf(float(_S().iq.get("fps", 30.0)), 1.0):
			return i
	return -1


func _draw_iq_lane(S: Scene, font: Font) -> void:
	var r := iq_rect()
	var conf: Array = S.iq["conf"]
	var dt := float(S.iq.get("dt", 1.0 / 30.0))
	draw_rect(r, Tok.of("ink:0.08"))
	for i in conf.size():
		var xa := x_of(i * dt)
		var xb := x_of((i + 1) * dt)
		if xb < 0.0 or xa > size.x:
			continue
		draw_rect(Rect2(xa, r.position.y + 1.0, maxf(xb - xa, 1.0), IQ_BAR), VideoIQ.lane_colour(float(conf[i]) / 100.0))
	for sp_ in S.iq.get("spans", []):
		var xs := x_of(float(sp_["t0"]))
		draw_string(font, Vector2(xs + 3.0, r.position.y + r.size.y - 1.0), String(sp_["text"]), HORIZONTAL_ALIGNMENT_LEFT, maxf(x_of(float(sp_["t1"])) - xs + 120.0, 60.0), 9, Tok.of("ink:0.85"))


## ROADMAP 77: the height of the sound lanes under the cards (one LANE_H per track)
func audio_h() -> float:
	var S := _S()
	return LANE_H * S.audio_tracks.size() if S != null else 0.0


## the sound lane under p (an index into S.audio_tracks), or -1
func audio_lane_at(p: Vector2) -> int:
	var S := _S()
	if S == null or S.audio_tracks.is_empty():
		return -1
	var y0 := size.y - audio_h()
	if p.y < y0 or p.y >= size.y:
		return -1
	return clampi(int(floor((p.y - y0) / LANE_H)), 0, S.audio_tracks.size() - 1)


## the lane's name: a box from the lane's start (or the timeline's left edge) over the name's text
func audio_name_rect(i: int) -> Rect2:
	var S := _S()
	var t: Dictionary = S.audio_tracks[i]
	var y := size.y - audio_h() + i * LANE_H
	var x0 := maxf(x_of(float(t["offset"])), 0.0)
	var w := get_theme_default_font().get_string_size(AudioTrack.label(t), HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x + 8.0
	return Rect2(x0, y, w, LANE_H)


func audio_name_at(p: Vector2) -> bool:
	var i := audio_lane_at(p)
	return i >= 0 and audio_name_rect(i).has_point(p)


## the offset drag: snapped to whole frames (Shift: 1 ms), never before the scene's start
func _audio_drag(x: float, fine: bool) -> void:
	var S := _S()
	var i := int(_drag["i"])
	if not _drag["moved"]:
		if absf(x - float(_drag["x0"])) < 3.0:
			return
		_drag["moved"] = true
		audio_drag_started.emit(i)   # main pushes the ONE undo step here
	var q := 0.001 if fine else 1.0 / maxf(S.fps, 1)
	S.audio_tracks[i]["offset"] = maxf(0.0, snappedf(float(_drag["off0"]) + (x - float(_drag["x0"])) / float(_drag["pps"]), q))
	queue_redraw()


## the sound lanes, one per track. Each shows its peak envelope from its offset on (computed once by AudioTrack.envelope),
## or a flat bar with the file name when it cannot be decoded (ogg / mp3) or the file is gone. A picked lane is lit; a muted one is dim
func _draw_audio_lanes(S: Scene, font: Font) -> void:
	var y0 := size.y - audio_h()
	for i in S.audio_tracks.size():
		_draw_lane(S, font, i, y0 + i * LANE_H, LANE_H)
	# the music beats (ROADMAP 32) sit on the music track's lane
	var mi := AudioTrack.index_of_role(S.audio_tracks, "music")
	if mi >= 0:
		_draw_beats(S, y0 + mi * LANE_H, LANE_H - 1.0, float(S.audio_tracks[mi]["offset"]))


## L14: the lane's (x, peak) columns, the ones _draw_lane draws; the graph editor's waveform reads the same AudioTrack.columns
func lane_columns(S: Scene, i: int, env: Dictionary) -> PackedVector2Array:
	var off := float(S.audio_tracks[i].get("offset", 0.0))
	return AudioTrack.columns(env, off, maxf(x_of(off), 0.0), minf(x_of(off + float(env.get("length", 0.0))), size.x), t_of)


func _draw_lane(S: Scene, font: Font, i: int, y: float, h: float) -> void:
	var t: Dictionary = S.audio_tracks[i]
	var env: Dictionary = m.audio_envs[i] if i < m.audio_envs.size() else {}
	var off := float(t.get("offset", 0.0))
	var len_s := float(env.get("length", 0.0))
	var x0 := x_of(off)
	var muted: bool = not AudioTrack.audible(S.audio_tracks)[i]
	var picked: bool = i == int(m.audio_pick)
	draw_rect(Rect2(0, y, size.x, h), Tok.of("ink:0.14") if picked else Tok.of("ink:0.06"))
	if env.get("ok", false) and not muted:
		var mid := y + h * 0.5
		var col := Tok.of("ink:0.55")
		for c in lane_columns(S, i, env):
			var hh := maxf(c.y * h * 0.5, 0.5)
			draw_line(Vector2(c.x, mid - hh), Vector2(c.x, mid + hh), col, 1.0)
	elif not muted:
		var wbar := maxf(x_of(off + len_s) - x0, 40.0) if len_s > 0.0 else 40.0
		draw_rect(Rect2(maxf(x0, 0.0), y + h * 0.5 - 1.0, minf(wbar, size.x), 2.0), Tok.of("ink:0.4"))
	var why := ""
	if not env.get("ok", false):
		why = ": no waveform for this format" if len_s > 0.0 else " (file missing)"
	var label_c := Tok.c("focus") if picked else Tok.of("ink:0.6")
	draw_string(font, Vector2(maxf(x0, 0.0) + 3, y + h - 3.0), AudioTrack.label(t) + why, HORIZONTAL_ALIGNMENT_LEFT, size.x, 9, label_c)
	draw_line(Vector2(x0, y), Vector2(x0, y + h), Tok.of("ink:0.6"), 1.0)


## MUSIC BEATS (ROADMAP 32): a thin mark per beat across the music lane; a bar's first beat (down) is full height and warm
func _draw_beats(S: Scene, y: float, h: float, off: float) -> void:
	if S.beats_audio.is_empty():
		return
	for b in S.beats_audio:
		var x := x_of(float(b["t"]) + off)
		if x < -1.0 or x > size.x + 1.0:
			continue
		if b["down"]:
			draw_line(Vector2(x, y), Vector2(x, y + h), Tok.c("beat_down"), 1.5)
		else:
			draw_line(Vector2(x, y + h * 0.55), Vector2(x, y + h), Tok.of("ink:0.45"), 1.0)


## FIGHT TO THE BEAT (I15): the beats of the grid as ticks down the cards' band, each fitted contact a gold diamond with a line on its
## time, a FLAGGED contact a red diamond with "!" (the reason is in the panel)
func _draw_fit(font: Font, y0: float, h: float) -> void:
	if bf.is_empty() and bf_grid.is_empty():
		return
	for t in bf_grid:
		var x := x_of(float(t))
		if x < -1.0 or x > size.x + 1.0:
			continue
		draw_line(Vector2(x, RULER - 5.0), Vector2(x, y0 + h), Tok.of("ink:0.5"), 1.0)
		draw_line(Vector2(x, 0.0), Vector2(x, RULER), Tok.c("beat_down"), 1.5)
	for c in bf:
		var x := x_of(float(c["t"]))
		var ok: bool = c["ok"]
		var col := Tok.c("focus") if ok else Tok.c("fail")
		if ok:
			draw_line(Vector2(x, RULER), Vector2(x, y0 + h), col, 2.0)
		var cy := y0 + 7.0
		draw_colored_polygon(PackedVector2Array([Vector2(x, cy - 7.0), Vector2(x + 6.0, cy), Vector2(x, cy + 7.0), Vector2(x - 6.0, cy)]), col)
		if not ok:
			draw_rect(Rect2(x + 8.0, cy - 6.0, 78.0, 13.0), Tok.c("tl_bg"))
			draw_string(font, Vector2(x + 10.0, cy + 4.0), "! no beat fits", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)


## FIGHT DISTANCE KEEPER (I18): a band along the top of the cards for every strike span: red = jammed, amber = out of range, blue = in range
func _draw_cg(font: Font, y0: float, h: float) -> void:
	if cg.is_empty():
		return
	for b in cg:
		var x0 := x_of(float(b["t0"]))
		var x1 := x_of(float(b["t1"]))
		if x1 < 0.0 or x0 > size.x:
			continue
		var bh := maxf(2.0, (h - 4.0) * float(b["e"]))
		draw_rect(Rect2(x0 + 1.0, y0 + h - bh, maxf(1.0, x1 - x0 - 2.0), bh), Color(Tok.c("heading"), 0.5))
	if cg_peak >= 0.0:
		var x := x_of(cg_peak)
		draw_string(font, Vector2(x + 8.0, y0 + 22.0), "BIG", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Tok.c("focus"))


func _draw_dk(font: Font, y0: float) -> void:
	for b in dk:
		var x0 := x_of(float(b["t0"]))
		var x1 := maxf(x_of(float(b["t1"])), x0 + 4.0)
		var cls := String(b["cls"])
		var tk := "fail" if cls == "jammed" else ("warn" if cls == "out" else "heading")
		draw_rect(Rect2(x0, y0, x1 - x0, 12.0), Color(Tok.c(tk), 0.92))
		if cls != "in" and x1 - x0 > 40.0:
			draw_string(font, Vector2(x0 + 3.0, y0 + 9.5), "JAMMED" if cls == "jammed" else "TOO FAR", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Tok.c("tl_bg"))


## REACTION DIRECTION (I33): a badge per hit under the distance and sell-the-hit bands: blue = the reaction follows the blow, red = flagged; the numbers on it
func _draw_rd(font: Font, y0: float) -> void:
	var oy := 13.0 * (float(not dk.is_empty()) + float(not sh.is_empty()))
	for b in rd:
		var x0 := x_of(float(b["t0"]))
		var x1 := maxf(x_of(float(b["t1"])), x0 + 4.0)
		var tk := "fail" if String(b["cls"]) == "bad" else "heading"
		draw_rect(Rect2(x0, y0 + oy, x1 - x0, 12.0), Color(Tok.c(tk), 0.92))
		draw_string(font, Vector2(x1 + 3.0, y0 + oy + 9.5), String(b["txt"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Tok.c(tk))


## SELL THE HIT (I21): a badge under the distance band for every strike: blue = SOLD, amber = NOT SOLD, red = UNSAFE (the safety flag)
func _draw_sh(font: Font, y0: float) -> void:
	var oy := 13.0 if not dk.is_empty() else 0.0   # under the distance band when that one is on
	for b in sh:
		var x0 := x_of(float(b["t0"]))
		var x1 := maxf(x_of(float(b["t1"])), x0 + 4.0)
		var cls := String(b["cls"])
		var tk := "fail" if cls == "unsafe" else ("warn" if cls == "notsold" else "heading")
		draw_rect(Rect2(x0, y0 + oy, x1 - x0, 12.0), Color(Tok.c(tk), 0.92))
		if x1 - x0 > 40.0:
			draw_string(font, Vector2(x0 + 3.0, y0 + oy + 9.5), "UNSAFE" if cls == "unsafe" else ("NOT SOLD" if cls == "notsold" else "SOLD"), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Tok.c("tl_bg"))


## BREAKFALL CHECK (I25): a badge per fall under the strike badges: blue = every rule reads OK, amber = a warning, red = a failed rule
func _draw_bk(font: Font, y0: float) -> void:
	var oy := (13.0 if not dk.is_empty() else 0.0) + (13.0 if not sh.is_empty() else 0.0)
	for b in bk:
		var x0 := x_of(float(b["t0"]))
		var x1 := maxf(x_of(float(b["t1"])), x0 + 4.0)
		var cls := String(b["cls"])
		var tk := "fail" if cls == "fail" else ("warn" if cls == "warn" else "heading")
		draw_rect(Rect2(x0, y0 + oy, x1 - x0, 12.0), Color(Tok.c(tk), 0.92))
		if x1 - x0 > 40.0:
			draw_string(font, Vector2(x0 + 3.0, y0 + oy + 9.5), String(b.get("txt", "FALL")), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Tok.c("tl_bg"))


## FIGHT RHYTHM (I19): ticks over the cards, one per action coloured by fighter (fighter 1 amber, fighter 2 blue; more cycle):
## tall = strike, short = block or step, hollow = feint; a red band behind the flagged stretches
func _draw_rh(y0: float, y1: float) -> void:
	if rh.is_empty():
		return
	for b in rh_flags:
		var x0 := x_of(float(b["t0"]))
		draw_rect(Rect2(x0, y1 - 5.0, maxf(x_of(float(b["t1"])) - x0, 3.0), 5.0), Color(Tok.c("fail"), 0.9))
	for e in rh:
		var x := x_of(float(e["t"]))
		var col: Color = [Tok.c("focus"), Tok.c("heading"), Tok.c("warn"), Tok.c("fail")][int(e["who"]) % 4]
		var tp := String(e["type"])
		var top := y0 + 1.0 if tp == "strike" or tp == "feint" else y0 + (y1 - y0) * 0.5
		var r := Rect2(x - 2.0, top, 4.0, y1 - 6.0 - top)
		draw_rect(r.grow(1.5), Tok.c("tl_bg"))
		if tp == "feint":
			draw_rect(r, col, false, 1.5)
		else:
			draw_rect(r, col)


## PRECOG CHECK (I31): a badge at each flagged reaction's start: PRECOG (moved before it could have seen it), LATE (arrives after the hit)
## SOUND CUES (I35): a dark lane along the bottom of the card strip; a whoosh is a blue arc-bar, a hit a red disc (a head hit
## ringed, a weapon clash a diamond), a step a green tick. The SIZE of the mark is the cue's strength.
const SC_H := 16.0
func sc_px() -> float:
	return SC_H if not sc.is_empty() else 0.0


func _draw_sc(ly: float) -> void:
	if sc.is_empty():
		return
	draw_rect(Rect2(0, ly, size.x, SC_H), Color(Tok.c("tl_bg"), 0.72))
	draw_line(Vector2(0, ly), Vector2(size.x, ly), Color(Tok.c("ink"), 0.25), 1.0)
	var cy := ly + SC_H * 0.5
	var order: Array = sc.filter(func(c): return String(c["kind"]) != "whoosh") + sc.filter(func(c): return String(c["kind"]) == "whoosh")   # hits and steps first, the whoosh streaks over them (a swing and its hit share a moment)
	for c in order:
		var x := x_of(float(c["t"]))
		var s := float(c["strength"])
		var k := String(c["kind"])
		var r := 2.0 + 4.5 * s
		match k:
			"whoosh":
				var col: Color = Tok.c("mk_blue")
				draw_line(Vector2(x - r - 2.0, cy), Vector2(x + r + 2.0, cy), col, 1.5 + 2.0 * s)
				draw_line(Vector2(x - r - 2.0, cy - 2.0 - r * 0.4), Vector2(x, cy), Color(Tok.c("mk_blue"), 0.7), 1.0)
				draw_line(Vector2(x - r - 2.0, cy + 2.0 + r * 0.4), Vector2(x, cy), Color(Tok.c("mk_blue"), 0.7), 1.0)
			"step":
				draw_line(Vector2(x, cy - r), Vector2(x, cy + r), Tok.c("mk_green"), 2.0)
			"hit_weapon":
				draw_colored_polygon(PackedVector2Array([Vector2(x, cy - r - 1.0), Vector2(x + r + 1.0, cy), Vector2(x, cy + r + 1.0), Vector2(x - r - 1.0, cy)]), Tok.c("mk_gold"))
			_:
				draw_circle(Vector2(x, cy), r, Tok.c("mk_red"))
				if k == "hit_head":
					draw_arc(Vector2(x, cy), r + 2.0, 0.0, TAU, 16, Tok.c("ink"), 1.2)
	draw_string(get_theme_default_font(), Vector2(3, ly + 11), "SFX", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(Tok.c("ink"), 0.6))


func _draw_pc(font: Font, y0: float) -> void:
	for b in pc:
		var st := String(b["status"])
		if st == "ok":
			continue
		var txt := "PRECOG" if st == "precog" else ("LATE" if st == "late" else "PRECOG+LATE")
		var x := x_of(float(b["t"]))
		var w := 6.2 * txt.length() + 6.0
		var r := Rect2(x, y0 - 1.0, w, 11.0)
		draw_rect(r, Color(Tok.c("fail") if st != "late" else Tok.c("warn"), 0.95))
		draw_string(font, r.position + Vector2(3.0, 8.5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Tok.c("tl_bg"))


## FATIGUE (I34): one thin strip per fighter along the bottom of the track, green (fresh) to red (spent); the fighter's number at its left end
func _draw_fa(font: Font, y1: float) -> void:
	if fa.is_empty():
		return
	var hh := 6.0
	for b in fa:
		var yy := y1 - hh * (fa_n - int(b["who"])) - 1.0
		var x0 := x_of(float(b["t0"]))
		draw_rect(Rect2(x0, yy, maxf(x_of(float(b["t1"])) - x0 + 0.5, 1.0), hh - 1.0), Exertion.color(float(b["f"])))
	for w in fa_n:
		draw_string(font, Vector2(2.0, y1 - hh * (fa_n - w) + 3.0), "F%d" % (w + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Tok.c("text"))


## MOMENTUM LEDGER (I36): a red STOP badge at every card arrival whose momentum drops faster than a body can brace (amber = a spin), near the bottom of the track
func _draw_ml(font: Font, y1: float) -> void:
	for b in ml:
		if not bool(b["flag"]):
			continue
		var txt := "STOP" if String(b["kind"]) == "linear" else "SPIN"
		var x := x_of(float(b["t"])) - 14.0
		var r := Rect2(x, y1 - 21.0, 6.2 * txt.length() + 6.0, 11.0)
		draw_rect(r, Color(Tok.c("fail") if String(b["kind"]) == "linear" else Tok.c("warn"), 0.95))
		draw_string(font, r.position + Vector2(3.0, 8.5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Tok.c("tl_bg"))
		draw_line(Vector2(x_of(float(b["t"])), y1 - 10.0), Vector2(x_of(float(b["t"])), y1), Tok.c("fail"), 1.5)


## AIRBORNE SPIN (I43): over each flight the COM's height as drawn (solid) and the free-fall parabola through the same ends (dotted); red box = flagged
func _draw_sp(font: Font, y0: float, h: float) -> void:
	for b in spn:
		var x0 := x_of(float(b["t0"]))
		var x1 := x_of(float(b["t1"]))
		var col: Color = Tok.c("fail") if b["flag"] else Tok.c("fv_ok")
		var r := Rect2(x0, y0 + 2.0, maxf(x1 - x0, 2.0), h - 4.0)
		draw_rect(r, Color(col, 0.18))
		draw_rect(r, col, false, 1.5)
		var ys: Array = b["ys"]
		var ps: Array = b["ps"]
		var lo := INF
		var hi := -INF
		for v in ys + ps:
			lo = minf(lo, float(v))
			hi = maxf(hi, float(v))
		hi = maxf(hi, lo + 0.1)
		var pa := PackedVector2Array()
		var pb := PackedVector2Array()
		for k in ys.size():
			var x := lerpf(r.position.x, r.end.x, float(k) / maxf(ys.size() - 1.0, 1.0))
			pa.append(Vector2(x, r.end.y - 14.0 - (r.size.y - 28.0) * (float(ys[k]) - lo) / (hi - lo)))
			pb.append(Vector2(x, r.end.y - 14.0 - (r.size.y - 28.0) * (float(ps[k]) - lo) / (hi - lo)))
		if pa.size() >= 2:
			draw_polyline(pb, Color(Tok.c("ink"), 0.7), 1.2)
			draw_polyline(pa, col, 2.2)
		draw_string(font, Vector2(r.position.x + 3.0, r.position.y + 10.0), ("IMPOSSIBLE  " if b["flag"] else "FLIGHT  ") + String(b["txt"]), HORIZONTAL_ALIGNMENT_LEFT, maxf(r.size.x - 4.0, 8.0), 10, Tok.c("text"))


## the hover / drag hold a CARD INDEX: any rebuild of the cards under a still mouse (a Fix, an undo, a scene opened, Polish) can leave
## it past the end ('Out of bounds get index 28' every frame in _draw). Dropped here, at the one place that reads it, so no
## caller of a card change has to remember to reset the timeline.
func _drop_stale() -> void:
	var S := _S()
	var n := 0 if S == null else S.cards.size()
	if _hover.get("kind", "") in ["move", "hold", "edge0"] and int(_hover.get("i", -1)) >= n:
		_hover = {}
	if not _drag.is_empty() and _drag.get("kind", "") in ["move", "hold", "edge0"] and int(_drag.get("i", -1)) >= n:
		_drag = {}


var rk_drawn: Array = []   # OWN RIG (L78): the centre of each key diamond drawn on the own-rig key row (the test reads the x)


func rig_key_frames() -> Array:
	var S := _S()
	return CustomRig.key_frames(S.own_rig) if S != null and not S.own_rig.is_empty() else []


## the own-rig key row: a thin row along the bottom, one diamond per rig key at x_of(frame / fps)
func _draw_rig_row() -> void:
	rk_drawn = []
	var fr := rig_key_frames()
	if fr.is_empty():
		return
	var fps := float(_S().own_rig.get("fps", 30.0))
	var y := size.y - 8.0
	draw_rect(Rect2(0, y - 6.0, size.x, 12.0), Color(0.95, 0.75, 0.2, 0.12))
	draw_string(get_theme_default_font(), Vector2(2, y + 4.0), "rig", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.95, 0.75, 0.2, 0.8))
	for f in fr:
		var x := x_of(float(f) / fps)
		draw_colored_polygon(PackedVector2Array([Vector2(x, y - 5), Vector2(x + 5, y), Vector2(x, y + 5), Vector2(x - 5, y)]), Color(0.95, 0.75, 0.2))
		rk_drawn.append(Vector2(x, y))


func _draw() -> void:
	_draw_cards()
	_draw_rig_row()


func _draw_cards() -> void:
	_drop_stale()
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
	var fdh := fd_px()   # FRAME DATA (ROADMAP 12): the strip sits under the ruler
	var bxh := bx_px()   # HIT / HURT BOXES (ROADMAP 36): the lane sits under the frame strip
	var shp := shots_px()   # THE SHOTS LANE (ROADMAP 75): under the boxes lane
	if shp > 0.0:
		_draw_shots_lane(_shots_y())
	var y0 := RULER + 2.0 + fdh + bxh + shp
	var ah := audio_h()
	_clip_fit(S)
	var h := size.y - y0 - 2.0 - ah - iq_px() - _clip_px - sc_px()
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
		_draw_audio_lanes(S, font)
	_draw_cg(font, y0, h)
	_draw_fit(font, y0, h)
	_draw_dk(font, y0)
	_draw_sh(font, y0)
	_draw_bk(font, y0)
	_draw_rd(font, y0)
	_draw_rh(y0, y0 + h)
	_draw_pc(font, y0)
	_draw_sc(y0 + h)
	_draw_fa(font, y0 + h)
	_draw_ml(font, y0 + h)
	_draw_sp(font, y0, h)
	if iq_px() > 0.0:
		_draw_iq_lane(S, font)
	_draw_clips(S, font)
	if not fd.is_empty():
		_draw_fd_strip(font, RULER + 2.0)
	if not bx.is_empty():
		_draw_bx_lane(RULER + 2.0 + fd_px())
	if not ph.is_empty():
		_draw_ph_lane(font)
	if not sp.is_empty():
		_draw_sp_lane(RULER + 2.0 + fd_px() + bx_px(), font)
	# the dummy is solid and hit: what PLAYS is the landed copy, which stops at the hit and rebounds. Past its end the
	# cards are still yours but never play: shade them and say why (else the strip and the play time disagree silently)
	var P: Scene = m._ps()
	if P != S and P.length() < L - 1e-3:
		var xc := x_of(P.length())
		draw_rect(Rect2(xc, RULER, size.x - xc, size.y - RULER), Color(0.05, 0.05, 0.06, 0.88))
		draw_line(Vector2(xc, RULER), Vector2(xc, size.y), Color(1, 0.45, 0.35), 2.0)
		draw_string(font, Vector2(xc + 6, y0 + h * 0.5 + 5), ("hit at %.2f s: the rest won't play (H: dummy off)" if size.x - xc > 300.0 else "hit: won't play") % P.length() if size.x - xc > 300.0 else "hit: won't play", HORIZONTAL_ALIGNMENT_LEFT, size.x - xc - 10, 12, Color(1, 0.75, 0.65))
	# hovered edge
	# the hover / drag index can outlive its card (a fix or a words edit rebuilt the cards under the mouse): skip it then
	if _hover.get("kind", "") in ["move", "hold", "edge0"] and _drag.is_empty() and int(_hover.get("i", -1)) < ts.size():
		var hi: int = _hover["i"]
		var hxe := x_of(ts[hi][2] if _hover["kind"] == "hold" else ts[hi][1])
		draw_line(Vector2(hxe, y0), Vector2(hxe, y0 + h), Color(1, 0.95, 0.5), 3.0)
	# the value being dragged, beside the edge
	if not _drag.is_empty() and _drag["kind"] in ["move", "hold"] and _drag.get("moved", false) and int(_drag.get("i", -1)) < ts.size():
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
	# MARKERS (round 41, WW5): a small flag on the ruler at each marker's time, coloured by its colour (ROADMAP 97) or kind
	for mi in S.markers.size():
		var mk: Dictionary = S.markers[mi]
		var fx := x_of(float(mk["t"]))
		var fc: Color = Tok.c(Markers.token_of(mk))
		draw_line(Vector2(fx, 0), Vector2(fx, RULER), fc, 1.0)
		draw_rect(Rect2(fx, 0, 8, 10), fc)   # a filled flag, 10 px tall (ROADMAP 97: readable at a glance)
		if mi == mark_sel:   # the marker whose popover is open: an outline around its flag
			draw_rect(Rect2(fx - 1, -1, 10, 12), Tok.c("ink"), false, 1.5)
		# the name beside the flag, when the space up to the next marker (or the ruler's end) fits it
		var nxt := size.x if mi + 1 >= S.markers.size() else x_of(float(S.markers[mi + 1]["t"]))
		var nm := String(mk["name"])
		var tw := get_theme_default_font().get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
		if nxt - (fx + 10.0) >= tw + 4.0:
			draw_string(get_theme_default_font(), Vector2(fx + 10.0, 9.0), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, fc)
	# REVIEW NOTES (ROADMAP 29): a cyan square on the ruler at each comment's frame (note_t_at takes a click on it)
	for nt in S.notes:
		var nx := x_of(clampf(Review.time_of(int(nt["frame"]), S.fps), 0.0, L))
		draw_rect(Rect2(nx - 3, 0, 6, 6), Review.COLOR)
	# THE SHOT CAMERA's keys: a camera-coloured diamond at each key's time (cam_key_at takes a click on it)
	var cy := _cam_y()
	for t in cam_times():
		var cx := x_of(float(t))
		draw_colored_polygon(PackedVector2Array([Vector2(cx, cy - CAM_R), Vector2(cx + CAM_R, cy), Vector2(cx, cy + CAM_R), Vector2(cx - CAM_R, cy)]), ShotGizmo.COLOR)
	_ph.queue_redraw()   # the playhead is its own overlay (see _draw_playhead): a full redraw refreshes it too


## ROADMAP 99: THE PLAYHEAD OVERLAY. While a scene plays only the playhead moves, so the app redraws this small child (a line
## and a flag) every frame instead of the whole timeline (m._tl_play_redraw decides when nothing else changed).
var _ph := Control.new()
var ph_drawn_x := -1.0


func playhead_redraw() -> void:
	_ph.queue_redraw()


## R17: THE LINE FOLLOWS THE PLAYHEAD BY ITSELF. Many paths set m.playhead without a _refresh (the card strip follows it on its
## own, so its gold frame moved while the line stayed: status bar 2.90 s, card 9, line at 1.69 s). Each frame the overlay
## compares the time it last drew with the playhead; a change redraws the line, and (not playing) the whole timeline, whose
## lit shot / lanes read the playhead too. One float compare per frame.
var _ph_seen := -1.0


func _process(_dt: float) -> void:
	if m == null or not visible:
		return
	_drop_stale()
	var t := float(m.playhead)
	if t == _ph_seen:
		return
	_ph_seen = t
	if m.playing:
		_ph.queue_redraw()
	else:
		queue_redraw()


func _draw_playhead() -> void:
	var S := _S()
	if S == null or S.cards.size() < 1:
		return
	var px := x_of(clampf(float(m.playhead), 0.0, S.length()))
	ph_drawn_x = px   # what the overlay last drew (tests/r17_test.gd compares it with the status bar's time)
	_ph.draw_line(Vector2(px, 0), Vector2(px, size.y), Tok.c("autokey") if m.auto_key else Tok.c("ink"), 2.0)   # ROADMAP 42: red while auto-key is on
	_ph.draw_colored_polygon(PackedVector2Array([Vector2(px - 5, 0), Vector2(px + 5, 0), Vector2(px, 7)]), Tok.c("ink"))


## ROADMAP 97: the index of the marker whose flag is under p (on the ruler), or -1
func marker_at(p: Vector2) -> int:
	var S := _S()
	if S == null or S.cards.is_empty() or S.markers.is_empty() or p.y < 0.0 or p.y >= RULER:
		return -1
	var best := -1
	var bd := 4.0
	for i in S.markers.size():
		var d := absf(x_of(clampf(float(S.markers[i]["t"]), 0.0, S.length())) - p.x)
		if d <= bd:
			bd = d
			best = i
	return best


## ROADMAP 29: the time of the review note whose mark is under p (on the ruler), or -1
func note_t_at(p: Vector2) -> float:
	var S := _S()
	if S == null or S.cards.is_empty() or S.notes.is_empty() or p.y < 0.0 or p.y > RULER:
		return -1.0
	var L := S.length()
	for nt in S.notes:
		var t := clampf(Review.time_of(int(nt["frame"]), S.fps), 0.0, L)
		if absf(x_of(t) - p.x) <= 4.0:
			return t
	return -1.0


# ---------------------------------------------------------------- CLIPS (GAP_ANALYSIS row 12; scripts/clips.gd)
## each placed clip is a bar on its own row under the cards: from its start to start + L x repeat / speed, a thin line
## at each repeat, the blend in / out drawn as darkened ramps. Click = pick it (m.clips_ui.sel); drag = move it in time
## (snapped to SNAP, FINE with Shift): ONE undo step, pushed on the first move (a click alone pushes none)
var _clip_px := 0.0      # px the clip rows take (added to the minimum height the caller set)


func _clip_fit(S: Scene) -> void:
	var want := _clip_rows_h(S)
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


## the rows' height: one per clip, the picked clip's taller by its warp panel
func _clip_rows_h(S: Scene) -> float:
	if S.clips.is_empty():
		return 0.0
	var h := S.clips.size() * CLIP_H + 2.0
	if _clip_sel() >= 0 and _clip_sel() < S.clips.size():
		h += WARP_H
	return h


## the top of clip k's row (rows stack from the bottom up: each clip's row, the picked one's panel under its bar)
func _clip_y(k: int) -> float:
	var S := _S()
	var y := size.y - audio_h() - iq_px() - _clip_px
	var sel := _clip_sel()
	for j in k:
		y += CLIP_H + (WARP_H if j == sel else 0.0)
	return y


## clip k's bar on the timeline
func clip_rect(k: int) -> Rect2:
	var S := _S()
	var c: Dictionary = S.clips[k]
	var e := Clips.source(String(c["src"]))
	var L := float(e.get("len", 0.5))
	var y := _clip_y(k)
	var x0 := x_of(float(c["start"]))
	return Rect2(x0, y, maxf(x_of(float(c["start"]) + Clips.length_of(c, L)) - x0, 6.0), CLIP_H - 2.0)


## the TIME WARP panel under the picked clip's bar: as wide as the strip (at least 96 px). Input time runs left to right
## over the strip, the source's progress up
func warp_rect(k: int) -> Rect2:
	var r := clip_rect(k)
	return Rect2(r.position.x, _clip_y(k) + CLIP_H, maxf(r.size.x, 96.0), WARP_H - 4.0)


## the inner plot of the panel (6 px inside), and the mapping of a knot (x, y in 0..1) to px and back
func warp_px(k: int, n: Vector2) -> Vector2:
	var ir := warp_rect(k).grow(-6.0)
	return Vector2(ir.position.x + n.x * ir.size.x, ir.end.y - n.y * ir.size.y)


func warp_norm_of(k: int, p: Vector2) -> Vector2:
	var ir := warp_rect(k).grow(-6.0)
	return Vector2(clampf((p.x - ir.position.x) / ir.size.x, 0.0, 1.0), clampf((ir.end.y - p.y) / ir.size.y, 0.0, 1.0))


## the picked clip's warp panel under p: {"kind": "warp", "i": clip, "j": the knot within 7 px (-1 = the empty panel)}, else {}
func warp_hit(p: Vector2) -> Dictionary:
	var S := _S()
	var k := _clip_sel()
	if S == null or k < 0 or k >= S.clips.size() or not warp_rect(k).has_point(p):
		return {}
	var ks := Clips.warp_clean((S.clips[k] as Dictionary).get("warp", []))
	var best := -1
	var bd := 7.0
	for j in ks.size():
		var d := warp_px(k, Vector2(float(ks[j][0]), float(ks[j][1]))).distance_to(p)
		if d <= bd:
			bd = d
			best = j
	return {"kind": "warp", "i": k, "j": best}


## W08: clip k's "In place" chip, at the START of its bar (clamped to stay on the strip when the clip starts off-screen).
## Dark pill with light text when it travels; amber with dark text when in place (both >= 4.5:1, asserted in tests/w08_test.gd)
const CHIP_W := 68.0
const CHIP_OFF_FILL := Color(0.12, 0.12, 0.15)
const CHIP_OFF_INK := Color(0.96, 0.96, 0.98)
const CHIP_ON_FILL := Color(1.0, 0.76, 0.18)
const CHIP_ON_INK := Color(0.10, 0.08, 0.02)
func inplace_rect(k: int) -> Rect2:
	var r := clip_rect(k)
	return Rect2(clampf(r.position.x, 2.0, maxf(2.0, size.x - CHIP_W - 2.0)), r.position.y, CHIP_W, r.size.y)


func inplace_at(p: Vector2) -> int:
	var S := _S()
	if S == null:
		return -1
	for k in S.clips.size():
		if inplace_rect(k).has_point(p):
			return k
	return -1


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


## a knot grabbed (j) or a new knot made where the press was (j = -1): the undo step is pushed at the first change, as for a clip
func _warp_press(k: int, j: int, p: Vector2) -> void:
	var cu = m.get("clips_ui")
	if cu != null:
		cu.sel = k
	var S := _S()
	if j >= 0:
		_drag = {"kind": "warp", "i": k, "j": j, "p0": p, "moved": false}
		queue_redraw()
		return
	var ks := Clips.warp_clean((S.clips[k] as Dictionary).get("warp", []))
	var n := warp_norm_of(k, p)
	var nk := Clips.warp_add(ks, n.x, n.y)
	if nk.size() == ks.size():
		m._say("no knot added there: a curve keeps %d knots at most, and each stays clear of the ends and of the next knot" % Clips.WARP_MAX)
		return
	var bj := 0
	var bdx := INF
	for q in nk.size():
		var dx := absf(float(nk[q][0]) - n.x)
		if dx < bdx:
			bdx = dx
			bj = q
	retime_started.emit()   # main pushes the ONE undo step here
	S.clips[k]["warp"] = nk
	_drag = {"kind": "warp", "i": k, "j": bj, "p0": p, "moved": true}
	retimed.emit(false)
	queue_redraw()


## the knot follows the pointer, clamped so the curve stays monotone (Clips.warp_set)
func _warp_drag(p: Vector2) -> void:
	var k: int = _drag["i"]
	var j: int = _drag["j"]
	var S := _S()
	if k >= S.clips.size():
		return
	if not _drag["moved"]:
		if p.distance_to(_drag["p0"]) < 3.0:
			return
		_drag["moved"] = true
		retime_started.emit()   # main pushes the ONE undo step here
	var ks := Clips.warp_clean((S.clips[k] as Dictionary).get("warp", []))
	if j >= ks.size():
		return
	var n := warp_norm_of(k, p)
	S.clips[k]["warp"] = Clips.warp_set(ks, j, n.x, n.y)
	retimed.emit(false)
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
	var y0 := RULER + 2.0 + fd_px()
	if p.y < y0 or p.y > y0 + BX_H:
		return -1
	for b in bx:
		var x0 := x_of(float(b["t0"]))
		var x1 := maxf(x_of(float(b["t1"])), x0 + 2.0)
		if p.x >= x0 and p.x <= x1:
			return int(b["i"])
	return -1


## the space lane's height (0 with no space keyed)
func sp_px() -> float:
	if sp.is_empty():
		return 0.0
	var rows := 0
	for b in sp:
		rows = maxi(rows, int(b["row"]) + 1)
	return SP_H * rows + 3.0


## the space segments: a block per run, "R hand: chest" in it (the words are the space's own name; world is dim)
func _draw_sp_lane(y: float, font: Font) -> void:
	var cols := {"world": Tok.of("ink:0.3"), "chest": Tok.c("fd_startup"), "pelvis": Tok.c("fd_recovery"), "weapon": Tok.c("fd_active"),
		"hand_l": Tok.c("beat_down"), "hand_r": Tok.c("beat_down")}
	for b in sp:
		var x0 := x_of(float(b["t0"]))
		var x1 := x_of(float(b["t1"]))
		var ry := y + SP_H * int(b["row"])
		var blk: Color = cols.get(b["space"], Tok.c("fd_ink"))
		blk.a = 0.85   # (the alpha set on the token colour: the theme test wants no colour literals)
		draw_rect(Rect2(x0, ry, maxf(x1 - x0 - 1.0, 2.0), SP_H - 1.0), blk)
		var who := ("L " if String(b["tip"]).ends_with("_l") else "R ") + String(b["tip"]).split("_")[0]
		var what := String(b["space"]).replace("hand_l", "left hand").replace("hand_r", "right hand")
		if x1 - x0 > 36.0:
			draw_string(font, Vector2(x0 + 3.0, ry + SP_H - 2.5), "%s: %s" % [who, what], HORIZONTAL_ALIGNMENT_LEFT, x1 - x0 - 4.0, 9, Tok.c("fd_ink"))


## the lane's height on the timeline (0 with no boxes)
func bx_px() -> float:
	return (BX_H + 3.0 if not bx.is_empty() else 0.0) + ph_px()


## the boxes lane: attack boxes on the top row (red), vulnerable edits below (blue), invincible ranges (gold, hatched)
func _draw_bx_lane(y: float) -> void:
	var cols := {"hit": Tok.c("fd_active"), "hurt": Tok.c("fd_recovery"), "inv": Tok.c("beat_down")}
	for b in bx:
		var x0 := x_of(float(b["t0"]))
		var x1 := x_of(float(b["t1"]))
		var row_y := y + (0.0 if int(b["row"]) == 0 else 5.0)
		draw_rect(Rect2(x0, row_y, maxf(x1 - x0 - 1.0, 2.0), 4.0), cols[b["kind"]])
		if b["kind"] == "inv":
			var hx := x0
			while hx < x1:   # hatching: invincible reads as a different thing from a blue edit
				draw_line(Vector2(hx, row_y + 4.0), Vector2(minf(hx + 4.0, x1), row_y), Tok.c("fd_ink"), 1.0)
				hx += 6.0


var _fd_y := 0.0   # the strip's top as last drawn (cancel_rects)
const CANCEL_H := 6.0   # px: the cancel band along the top of the frame strip (POL1106b: was 4)


## N081: one Rect2 per cancel window of the frame data (timeline coordinates; where _draw_fd_strip draws the bands)
func cancel_rects() -> Array:
	var out := []
	if fd.is_empty() or not fd.has("cancel"):
		return out
	var fps := float(fd["fps"])
	for w in fd["cancel"]["windows"]:
		var x0 := x_of(float(w["f0"]) / fps)
		var x1 := x_of(float(w["f1"]) / fps)
		out.append(Rect2(x0, _fd_y, maxf(x1 - x0 - 1.0, 1.0), CANCEL_H))
	return out


func _rx_sync() -> void:
	if fd.is_empty() or (fd.get("frames", []) as Array).is_empty():
		_rx_src = {}
		if rx != null:
			rx.visible = false
		return
	if rx != null and is_same(_rx_src, fd):
		rx.visible = true
		return
	_rx_src = fd
	var made := ReactableCells.build(fd, Reactable.analyze(fd))
	if rx == null:
		rx = made
		rx.xmap = x_of
		add_child(rx)
	else:
		rx.set_data(fd, Reactable.analyze(fd))
	rx.visible = true


## the frame strip: one block per phase over its frames (time = frame / fps), its count in the block
func _draw_fd_strip(font: Font, y: float) -> void:
	if rx != null and rx.visible:   # L15: the tell cells have their own labelled row under the strip
		var ry := y + FD_H + 2.0
		rx.position = Vector2(0.0, ry + (RX_ROW - ReactableCells.H) * 0.5)
		rx.size = Vector2(size.x, ReactableCells.H)
		rx.queue_redraw()
		draw_rect(Rect2(PAD, ry, size.x - 2.0 * PAD, RX_ROW), Tok.of("ink:0.08"))
		var lw := font.get_string_size("react", HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
		draw_rect(Rect2(PAD, ry + 1.0, lw + 6.0, RX_ROW - 2.0), Tok.of("tl_bg:0.9"))
		draw_string(font, Vector2(PAD + 3.0, ry + RX_ROW - 3.0), "react", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Tok.of("ink:0.8"))
	var fps := float(fd["fps"])
	var cols := {"startup": Tok.c("fd_startup"), "active": Tok.c("fd_active"), "recovery": Tok.c("fd_recovery")}
	for sp in FrameData.spans(fd):
		var x0 := x_of(float(sp["f0"]) / fps)
		var x1 := x_of(float(sp["f1"]) / fps)
		var n := int(sp["f1"]) - int(sp["f0"])
		if sp["kind"] == "active":
			# a multi-hit span: the frames with a hitbox out are full red, the gaps between them dim
			draw_rect(Rect2(x0, y, maxf(x1 - x0 - 1.0, 1.0), FD_H), Tok.c("fd_tint"))   # POL1106b: an opaque token (was fd_active at 0.22 over the bg: 0.02 luminance in the dark theme)
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
	_fd_y = y
	for rc in cancel_rects():   # N081: the cancel windows, a band along the top of the strip (cancel_windows.gd)
		draw_rect(rc, CancelWindows.COL_BAND)
	if fd.has("exchange"):   # N080: on hit / on block after the strip's end (frame_advantage.gd)
		var xe := x_of(float(fd["n"]) / fps) + 4.0
		draw_string(font, Vector2(xe, y + FD_H - 2.0), FrameAdvantage.words(fd["exchange"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Tok.c("ink"))


## the picked clip's time curve on its panel: the dashed diagonal is linear (no warp), the curve is the warp (the source
## progress against the strip progress), each knot a dot. The ends are fixed and drawn small
func _draw_warp(k: int, S: Scene, font: Font) -> void:
	var r := warp_rect(k)
	draw_rect(r, Tok.of("tl_bg:0.9"))
	draw_rect(r, Tok.c("focus"), false, 1.0)
	draw_dashed_line(warp_px(k, Vector2(0, 0)), warp_px(k, Vector2(1, 1)), Tok.of("ink:0.35"), 1.0, 4.0)
	var wk := Clips.warp_norm((S.clips[k] as Dictionary).get("warp", []))
	var pts := PackedVector2Array()
	for i in 33:
		var x := i / 32.0
		pts.append(warp_px(k, Vector2(x, Clips.warp_f(wk, x))))
	draw_polyline(pts, Tok.c("focus"), 2.0)
	for kn in Clips.warp_clean((S.clips[k] as Dictionary).get("warp", [])):
		draw_circle(warp_px(k, Vector2(float(kn[0]), float(kn[1]))), 3.5, Tok.c("focus"))
	draw_circle(warp_px(k, Vector2(0, 0)), 2.0, Tok.of("ink:0.6"))
	draw_circle(warp_px(k, Vector2(1, 1)), 2.0, Tok.of("ink:0.6"))
	draw_string(font, r.position + Vector2(4, 10), "time warp", HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 8.0, 8, Tok.of("ink:0.6"))


func _draw_clips(S: Scene, font: Font) -> void:
	var sel := _clip_sel()
	for k in S.clips.size():
		var c: Dictionary = S.clips[k]
		var r := clip_rect(k)
		var e := Clips.source(String(c["src"]))
		draw_rect(r, Tok.c("accent") if not bool(c.get("mute", false)) else Tok.of("ink:0.3"))
		if k == sel:
			_draw_warp(k, S, font)
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
		draw_string(font, Vector2(inplace_rect(k).end.x + 4, r.position.y + 13), Clips.label(c), HORIZONTAL_ALIGNMENT_LEFT, maxf(r.end.x - inplace_rect(k).end.x - 6, 1.0), 11, Tok.c("on_accent"))
		var ir := inplace_rect(k)   # W08: the In place toggle, lit amber when on
		var ion := bool(c.get("inplace", false))
		var ink := CHIP_ON_INK if ion else CHIP_OFF_INK
		draw_rect(ir, CHIP_ON_FILL if ion else CHIP_OFF_FILL)
		draw_rect(ir, CHIP_ON_INK if ion else Color(1, 1, 1, 0.55), false, 1.5)   # an outline: the amber chip must not melt into the amber bar
		var cy := ir.position.y + ir.size.y * 0.5
		if ion:
			draw_arc(Vector2(ir.position.x + 9, cy), 3.5, 0.0, TAU, 12, ink, 1.6)   # a ring: stays put
		else:
			draw_line(Vector2(ir.position.x + 4, cy), Vector2(ir.position.x + 14, cy), ink, 1.6)   # an arrow: travels
			draw_line(Vector2(ir.position.x + 14, cy), Vector2(ir.position.x + 10, cy - 3), ink, 1.6)
			draw_line(Vector2(ir.position.x + 14, cy), Vector2(ir.position.x + 10, cy + 3), ink, 1.6)
		draw_string(font, Vector2(ir.position.x + 18, cy + 4), "In place" if ion else "Travels", HORIZONTAL_ALIGNMENT_LEFT, ir.size.x - 20, 11, ink)
		if k == sel:
			draw_rect(r.grow(0.5), Tok.c("focus"), false, 1.5)
