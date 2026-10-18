## DOPE SHEET (round 42, GATES XX3, UPGRADES_300 #252 + #253): the scene's keys as rows of diamonds, the way Blender's
## Dope Sheet shows them. The TOP row is the cards: one diamond at each card's ARRIVAL (Scene.times() row [move start,
## arrive, leave], element 1). Under it one row per BODY PART GROUP, with a diamond at every PART KEY (scripts/part_keys.gd)
## of the joints in that group. The groups (every Body.BODY joint is in exactly one; the fingers have no row):
##   pelvis | spine (spine_01-03) | head (neck_01, head) | arm_l / arm_r (clavicle, upperarm, lowerarm)
##   | hands (hand_l, hand_r) | leg_l / leg_r (thigh, calf, foot, ball)
## KEY TYPES, as Blender marks them (KEY / BREAKDOWN / MOVING HOLD / EXTREME): a card's type is card["ktype"], written
## ONLY when it is not a plain key (a scene that never uses a type saves byte for byte as before; the file stores
## "breakdown", "moving_hold" or "extreme"). The type changes how the diamond is drawn (size, colour, hollow), not the motion.
## DRAG a card diamond left or right: its arrival moves by whole frames (Scene.fps), the way the timeline's arrival edge
## does (it sets the card's MOVE, so every later card and every marker follows). One undo step per drag. A click without
## a drag picks the card. The first card arrives at 0 and cannot be moved.
## COPY AND PART KEYS (round 49, GATES NA0; Blender's Dope Sheet: Shift+D duplicates keys, G moves them):
##   Shift-drag a card diamond: a COPY of that card lands where it is dropped (main._dope_copy): it must land inside a
##   card's MOVE; that move is split in two, so every card after it arrives exactly when it did.
##   Drag a part-key diamond: its keys (every joint in that diamond) move by whole frames, never onto or past a
##   neighbour key of the same joint; Shift-drag leaves them and puts copies at the drop (main._dope_part).
##   Both happen on release (a ghost diamond shows where), one undo step each.
##   STEPPED PREVIEW on (Scene.stepped): the card row shows only keys and extremes, as Blender's stepped view does.
## This file draws and reads the mouse; main.gd owns the scene, the undo and the caches (the signals below).
class_name DopeSheet
extends PanelContainer

signal retime_started
signal retimed(final: bool)
signal picked(i: int)

const TYPED := ["breakdown", "moving_hold", "extreme"]   # what card["ktype"] may hold; absent = a plain key
const KINDS := ["key", "breakdown", "moving_hold", "extreme"]
const GROUPS := [
	["pelvis", ["pelvis"]], ["spine", ["spine_01", "spine_02", "spine_03"]], ["head", ["neck_01", "head"]],
	["arm_l", ["clavicle_l", "upperarm_l", "lowerarm_l"]], ["arm_r", ["clavicle_r", "upperarm_r", "lowerarm_r"]],
	["hands", ["hand_l", "hand_r"]], ["leg_l", ["thigh_l", "calf_l", "foot_l", "ball_l"]],
	["leg_r", ["thigh_r", "calf_r", "foot_r", "ball_r"]]]

var m: Node              # main.gd: reads m.S, m.playhead, m.sel_card
var canvas: DopeCanvas
var _btns := {}


static func next_kind(k: String) -> String:
	return KINDS[(KINDS.find(k) + 1) % KINDS.size()]


static func kind_of(card: Dictionary) -> String:
	return String(card.get("ktype", "key"))


static func label_of(k: String) -> String:
	return k.replace("_", " ")


func _init() -> void:
	name = "dope_sheet"
	visible = false
	var v := VBoxContainer.new()
	add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	var t := Label.new()
	t.text = "DOPE SHEET"
	t.add_theme_color_override("font_color", Tok.c("heading"))
	h.add_child(t)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(gap)
	for k in KINDS:
		var b := Button.new()
		b.text = label_of(k)
		b.tooltip_text = "make the picked card a %s key (Blender's mark; it only changes how it is drawn)" % label_of(k)
		b.pressed.connect(func(): if m != null: m._ktype_set(k))
		h.add_child(b)
		_btns[k] = b
	var x := Button.new()
	x.text = "Close"
	x.pressed.connect(func(): visible = false)
	h.add_child(x)
	canvas = DopeCanvas.new()
	canvas.sheet = self
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(canvas)


func _process(_d: float) -> void:
	if visible and m != null:
		canvas.watch()


## the drawn grid. Everything it shows is read from the scene each time, so an undo or a Ctrl+Z redraws it right.
class DopeCanvas extends Control:
	const LBL := 64.0     # px: the row names
	const PAD := 10.0
	const RULER := 14.0
	const CARD_H := 22.0
	const ROW_H := 16.0
	const GRAB := 7.0     # px: how near a card diamond the mouse must be to take it

	var sheet: DopeSheet
	var _drag := {}       # {"i", "x0", "pps", "move0", "n", "started"}; NA0 adds "mode": "copy" | "part" (+ "row", "t", "joints", "x")
	var _sig := ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(0, RULER + CARD_H + ROW_H * DopeSheet.GROUPS.size() + 4.0)
		clip_contents = true

	func _S() -> Scene:
		return sheet.m.S if sheet != null and sheet.m != null else null

	## redraw when anything it shows changed (cheap: a short string, only while the sheet is open)
	func watch() -> void:
		var S := _S()
		if S == null:
			return
		var sig := "%s|%s|%s|%s|%d|%s" % [JSON.stringify(S.times()), JSON.stringify(S.cards.map(func(c): return DopeSheet.kind_of(c))),
			var_to_str(S.part_keys), sheet.m.playhead, sheet.m.sel_card, size]
		if sig != _sig:
			_sig = sig
			queue_redraw()

	func pps() -> float:
		if _drag.has("pps"):
			return _drag["pps"]
		var S := _S()
		var L := S.length() if S != null and not S.cards.is_empty() else 1.0
		return (size.x - LBL - PAD) / maxf(L, 0.5)

	func x_of(t: float) -> float:
		return LBL + t * pps()

	func row_y(r: int) -> float:   # the centre of row r: -1 = the cards, 0.. = GROUPS
		return RULER + CARD_H * 0.5 if r < 0 else RULER + CARD_H + ROW_H * (r + 0.5)

	## every diamond: {"row": -1 (card) or the group index, "i": card index or -1, "t", "x", "y", "kind", "joints": [names]}
	## Part keys of one group at one time are ONE diamond (several joints keyed together show once, with all their names)
	func diamonds() -> Array:
		var out := []
		var S := _S()
		if S == null:
			return out
		var ts := S.times()
		for i in S.cards.size():
			var t: float = ts[i][1]
			if S.stepped and DopeSheet.kind_of(S.cards[i]) in ["breakdown", "moving_hold"]:
				continue   # NA0: the stepped view shows only keys and extremes
			out.append({"row": -1, "i": i, "t": t, "x": x_of(t), "y": row_y(-1), "kind": DopeSheet.kind_of(S.cards[i]), "joints": []})
		for r in DopeSheet.GROUPS.size():
			var at := {}   # time (ms) -> index in out
			for j in DopeSheet.GROUPS[r][1]:
				for k in S.part_keys.get(j, []):
					var t: float = k["t"]
					var key := int(round(t * 1000.0))
					if at.has(key):
						out[at[key]]["joints"].append(j)
					else:
						at[key] = out.size()
						out.append({"row": r, "i": -1, "t": t, "x": x_of(t), "y": row_y(r), "kind": "part", "joints": [j]})
		return out

	func card_hit(p: Vector2) -> int:
		if p.y < RULER or p.y > RULER + CARD_H:
			return -1
		var best := -1
		var bd := GRAB
		for d in diamonds():
			if d["row"] == -1 and absf(p.x - float(d["x"])) <= bd:
				bd = absf(p.x - float(d["x"]))
				best = d["i"]
		return best

	func _gui_input(ev: InputEvent) -> void:
		var S := _S()
		if S == null or S.cards.is_empty():
			return
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				var i := card_hit(ev.position)
				if i >= 0 and ev.shift_pressed:
					_drag = {"mode": "copy", "i": i, "x0": ev.position.x, "x": ev.position.x, "pps": pps(), "started": false}
				elif i >= 0:
					_drag = {"i": i, "x0": ev.position.x, "pps": pps(), "move0": S.move_time(i), "n": 0, "started": false}
				else:
					var pd := part_hit(ev.position)
					if not pd.is_empty():
						_drag = {"mode": "part", "copy": ev.shift_pressed, "row": pd["row"], "t": pd["t"], "joints": pd["joints"],
							"x0": ev.position.x, "x": ev.position.x, "pps": pps(), "started": false}
				accept_event()
			elif not _drag.is_empty():
				var d := _drag
				_drag = {}
				if d.get("mode", "") == "copy":
					if d["started"]:
						sheet.m._dope_copy(int(d["i"]), snap_t(float(d["x"]), float(d["pps"])))
					queue_redraw()
					accept_event()
					return
				if d.get("mode", "") == "part":
					if d["started"]:
						sheet.m._dope_part(d["joints"], float(d["t"]), snap_t(float(d["x"]), float(d["pps"])), bool(d["copy"]))
					queue_redraw()
					accept_event()
					return
				if d["started"]:
					sheet.retimed.emit(true)
				else:
					sheet.picked.emit(d["i"])
				queue_redraw()
				accept_event()
		elif ev is InputEventMouseMotion and not _drag.is_empty():
			if _drag.has("mode"):   # NA0: a ghost follows the mouse; the edit happens on release
				_drag["x"] = ev.position.x
				_drag["started"] = _drag["started"] or absf(ev.position.x - float(_drag["x0"])) >= 3.0
				queue_redraw()
			else:
				drag_to(ev.position.x)
			accept_event()

	## NA0: the time under x, on a whole frame
	func snap_t(x: float, pp: float) -> float:
		var S := _S()
		var fps := float(maxi(1, S.fps))
		return maxf(0.0, roundf((x - LBL) / pp * fps) / fps)

	## NA0: the part-key diamond under p, or {}
	func part_hit(p: Vector2) -> Dictionary:
		var best := {}
		var bd := GRAB
		for d in diamonds():
			if d["row"] >= 0 and absf(p.y - float(d["y"])) <= ROW_H * 0.5 and absf(p.x - float(d["x"])) <= bd:
				bd = absf(p.x - float(d["x"]))
				best = d
		return best

	## the drag so far, in whole frames n: the card's move is its move at the press plus n / fps. The press can start
	## the drag only on a card after the first (it arrives at 0)
	func drag_to(x: float) -> void:
		var S := _S()
		var i: int = _drag["i"]
		if i <= 0:
			return
		var fps := float(S.fps)
		var n := int(round((x - float(_drag["x0"])) / float(_drag["pps"]) * fps))
		n = maxi(n, int(ceil((Timeline.MIN_MOVE - float(_drag["move0"])) * fps - 1e-9)))   # a move cannot be shorter than the timeline's
		if n == int(_drag["n"]):
			return
		if not _drag["started"]:
			_drag["started"] = true
			sheet.retime_started.emit()
		_drag["n"] = n
		S.cards[i]["move"] = float(_drag["move0"]) + float(n) / fps
		sheet.retimed.emit(false)
		queue_redraw()

	func _shape(c: Vector2, r: float, col: Color, hollow: bool) -> void:
		var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
		if hollow:
			pts.append(pts[0])
			draw_polyline(pts, col, 2.0)
		else:
			draw_colored_polygon(pts, col)

	func _draw() -> void:
		var S := _S()
		draw_rect(Rect2(Vector2.ZERO, size), Tok.c("tl_bg"))
		var font := get_theme_default_font()
		if S == null or S.cards.is_empty():
			draw_string(font, Vector2(PAD, 30), "DOPE SHEET: clip two poses and the scene's keys show here", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Tok.of("ink:0.5"))
			return
		var L := S.length()
		var fps := maxi(1, S.fps)
		var step := 0.5 if pps() * 0.5 > 40.0 else 1.0
		var k := 0
		while k * 0.1 <= L + 1e-6:   # the ruler: a tick every 0.1 s, a label on the majors
			var major := absf(fmod(k * 0.1 + 1e-6, step)) < 2e-5
			draw_line(Vector2(x_of(k * 0.1), RULER - (7.0 if major else 3.0)), Vector2(x_of(k * 0.1), RULER), Tok.of("ink:0.35" if major else "ink:0.18"), 1.0)
			if major:
				draw_string(font, Vector2(x_of(k * 0.1) + 2, 11), "%ss" % snappedf(k * 0.1, 0.1), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Tok.of("ink:0.5"))
			k += 1
		for r in range(-1, DopeSheet.GROUPS.size()):
			var y := row_y(r)
			var h := CARD_H if r < 0 else ROW_H
			if r % 2 == 0:
				draw_rect(Rect2(0, y - h * 0.5, size.x, h), Tok.of("ink:0.05"))
			draw_string(font, Vector2(4, y + 4), "cards" if r < 0 else String(DopeSheet.GROUPS[r][0]), HORIZONTAL_ALIGNMENT_LEFT, LBL - 6, 11, Tok.of("ink:0.75"))
		for d in diamonds():
			var c := Vector2(d["x"], d["y"])
			if d["row"] < 0:
				var sel: bool = int(d["i"]) == int(sheet.m.sel_card)
				match String(d["kind"]):
					"breakdown":
						_shape(c, 4.5, Tok.c("info"), false)
					"moving_hold":
						_shape(c, 6.0, Tok.c("warn"), true)
					"extreme":
						_shape(c, 9.0, Tok.c("fail"), false)
					_:
						_shape(c, 6.5, Tok.c("accent"), false)
				if sel:
					draw_arc(c, 11.0, 0.0, TAU, 20, Tok.c("focus"), 1.5)
			else:
				_shape(c, 4.0, Tok.c("heading"), false)
		if not _drag.is_empty() and _drag.has("mode") and _drag["started"]:   # NA0: the ghost where it will land
			var gt := snap_t(float(_drag["x"]), float(_drag["pps"]))
			var gy := row_y(-1) if _drag["mode"] == "copy" else row_y(int(_drag["row"]))
			_shape(Vector2(x_of(gt), gy), 6.0, Tok.c("say"), true)
			var verb := "copy" if _drag["mode"] == "copy" or bool(_drag.get("copy", false)) else "move"
			draw_string(font, Vector2(x_of(gt) + 10, gy + 4), "%s to %.2f s" % [verb, gt], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Tok.c("say"))
		elif not _drag.is_empty() and _drag["started"]:   # the drag's frames, beside the diamond
			var di: int = _drag["i"]
			var n: int = _drag["n"]
			draw_string(font, Vector2(x_of(S.times()[di][1]) + 12, row_y(-1) + 4), "%+d fr" % n, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Tok.c("say"))
		var px := x_of(clampf(float(sheet.m.playhead), 0.0, L))
		draw_line(Vector2(px, 0), Vector2(px, size.y), Tok.c("say"), 1.0)
		draw_string(font, Vector2(size.x - 52, 11), "%d fps" % fps, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Tok.of("ink:0.5"))
