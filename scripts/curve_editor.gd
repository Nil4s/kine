## curve_editor.gd - CURVE EDITOR (round 42, GATES XX2, UPGRADES_300 #240).
## A panel that draws the picked joint's PART KEYS (scripts/part_keys.gd) as curves against time: one per angle,
## X (bend) red, Y (side) green, Z (twist) blue, a dot at every key, a line at the playhead.
## The curves are PartKeys.value_at() sampled many times (the keys plus any modifier stack, DD2), so whatever the
## interpolation is, the line drawn is the line played.
## Click a key to pick it; drag it: up/down changes that angle (within the joint's limits when `limit` is set), left/right
## moves the whole key in time (snapped to whole frames at `fps`, never past its neighbours). One undo step per drag
## (`begin` is called once, on the first move). Esc or a click on nothing lets go. "Frame all" fits the view to the keys.
## This node owns no data: it edits `scene.part_keys` in place and calls `changed` after every edit.
## MANY KEYS AT ONCE (round 48, GATES DD0, UPGRADES_300 #243): the selection is a set of key dots ([angle, key index]);
## Shift+click adds / removes one, a drag on empty plot draws a box and selects every dot inside it. Dragging any
## selected dot moves EVERY selected one by the same change: the time of each selected key (whole frames; Ctrl snaps the
## dragged key to the nearest card's time), the angle of each selected dot; no key passes an unselected neighbour.
## Alt+drag SCALES the selection: time about the playhead (left/right), each angle about the selected dots' mean
## (up/down). One undo step per gesture (`begin`, on the first move).
class_name CurveEditor
extends Control

const PAD_L := 44.0
const PAD_R := 10.0
const PAD_T := 22.0
const PAD_B := 20.0
const HIT := 9.0       # px: how close a click must be to a key's dot to pick it
const MOVE_MIN := 3.0  # px: a drag starts after this much movement (a click that does not move changes nothing)

var scene: Scene = null
var joint := ""
var au := false             # L94: `joint` names a face AU channel (scene.face), drawn clamped to its range
var playhead := 0.0
var fps := 24
var limit: Callable = Callable()    # (joint, Vector3) -> Vector3, the legal angles
var begin: Callable = Callable()    # called once at the start of a drag: the undo step
var changed: Callable = Callable()  # called after every edit
var t0 := 0.0
var t1 := 1.0
var v0 := -1.0
var v1 := 1.0
var sel_ch := -1
var sel_i := -1
var _press := Vector2.ZERO
var _dragging := false
var _btn: Button
var _shape: MenuButton      # DD1: Blender's Key > Blend tools on the selection (scripts/key_blend.gd)
var _factor: SpinBox        # DD1: their factor
var why := []              # DD5: this joint's Check spans [{"rule", "t0", "t1", "parts", "msg"}] (scripts/why.gd), painted red
var view := "plain"         # DD3: "plain" (degrees, one plot) | "normal" (each angle fitted to -1..1) | "stacked" (a lane each)
const VIEWS := ["plain", "normal", "stacked"]
const VIEW_NAMES := {"plain": "View: degrees", "normal": "View: -1..1", "stacked": "View: lanes"}
var _rng := [Vector2(-1, 1), Vector2(-1, 1), Vector2(-1, 1)]   # DD3: each angle's range (lo, hi) in the fitted views
var _view_btn: Button
var _mods: MenuButton       # DD2: the curve modifiers (Blender's F-Curve modifiers: noise, stepped, limits)
const MOD_ITEMS := ["Add noise", "Add stepped (on twos)", "Add limits (the keys' range)", "Mix of the last = factor (0..1)", "Remove the last"]
var last_shape := {}        # DD1: the last tool's report {"tool", "changed", "skipped"}
var picked := []        # DD0: the selected dots, [[angle, key index], ...]; sel_ch / sel_i = the one under the mouse
var card_times := []    # DD0: each card's start time (s), for Ctrl-snap
var _mode := ""         # the gesture: "move" | "scale" | "box"
var _box := Rect2()
var _snap := []         # the keys as they were when the gesture began: [[t, v], ...]
var say: Callable = Callable()      # (text) -> void: the status line (the Unify / Break buttons name what to do next)
var _hd := []           # ROADMAP 65: the handle being dragged [angle, key index, "in" | "out"], [] = none
var _unify: Button
var _break: Button
var band := {}   # YY7: GaitBand.for_part() of the picked part (the people's band + the body's own line), {} = none


func _init() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_CLICK
	mouse_filter = Control.MOUSE_FILTER_STOP
	_btn = Button.new()
	_btn.text = "Frame all"
	_btn.tooltip_text = "fit the view to this joint's keys (every angle, the whole time span)"
	_btn.focus_mode = Control.FOCUS_NONE
	_btn.pressed.connect(frame_all)
	add_child(_btn)
	_btn.position = Vector2(PAD_L, 1)
	_shape = MenuButton.new()
	_shape.text = "Shape"
	_shape.flat = false
	_shape.tooltip_text = "reshape the selected keys (Blender's Key > Blend): by the factor at its right"
	_shape.focus_mode = Control.FOCUS_NONE
	for k in KeyBlend.TOOLS.size():
		_shape.get_popup().add_item(KeyBlend.NAMES[KeyBlend.TOOLS[k]], k)
	_shape.get_popup().id_pressed.connect(func(id): shape(KeyBlend.TOOLS[id], _factor.value))
	add_child(_shape)
	_factor = SpinBox.new()
	_factor.min_value = -1.0
	_factor.max_value = 2.0
	_factor.step = 0.05
	_factor.value = 0.5
	_factor.tooltip_text = "the shape tool's factor: -1..1 toward the left / right neighbour; push / pull and scale: 1 = unchanged"
	add_child(_factor)
	# DD1: both fit the 22 px header (a taller control would cover the top of the plot and eat its clicks)
	var flat_box := StyleBoxFlat.new()
	flat_box.bg_color = Tok.c("tl_bg")
	flat_box.content_margin_left = 4
	flat_box.content_margin_right = 4
	flat_box.content_margin_top = 0
	flat_box.content_margin_bottom = 0
	_shape.add_theme_font_size_override("font_size", 11)
	for st in ["normal", "hover", "pressed", "focus"]:
		_shape.add_theme_stylebox_override(st, flat_box)
	var le := _factor.get_line_edit()
	le.add_theme_font_size_override("font_size", 11)
	for st in ["normal", "focus", "read_only"]:
		le.add_theme_stylebox_override(st, flat_box)
	_factor.custom_minimum_size = Vector2(64, 0)
	_btn.add_theme_font_size_override("font_size", 11)   # round 48: the header row's height (a 35 px button hid the
	for st in ["normal", "hover", "pressed", "focus"]:   # joint's name and the top lane's label)
		_btn.add_theme_stylebox_override(st, flat_box)
	_mods = MenuButton.new()
	_mods.text = "Mods"
	_mods.flat = false
	_mods.tooltip_text = "curve modifiers on this part (the keys stay as they are): noise, stepped, limits; each with a mix"
	_mods.focus_mode = Control.FOCUS_NONE
	_mods.add_theme_font_size_override("font_size", 11)
	for st in ["normal", "hover", "pressed", "focus"]:
		_mods.add_theme_stylebox_override(st, flat_box)
	for k in MOD_ITEMS.size():
		_mods.get_popup().add_item(MOD_ITEMS[k], k)
	_mods.get_popup().id_pressed.connect(func(id): mod_item(id))
	add_child(_mods)
	_view_btn = Button.new()
	_view_btn.text = VIEW_NAMES[view]
	_view_btn.tooltip_text = "degrees on one plot / every angle fitted to -1..1 (Maya's normalized view) / one lane per angle (stacked); keys stay draggable in all three"
	_view_btn.focus_mode = Control.FOCUS_NONE
	_view_btn.add_theme_font_size_override("font_size", 11)
	for st in ["normal", "hover", "pressed", "focus"]:
		_view_btn.add_theme_stylebox_override(st, flat_box)
	_view_btn.pressed.connect(func(): set_view(VIEWS[(VIEWS.find(view) + 1) % VIEWS.size()]))
	add_child(_view_btn)
	_unify = _tan_button("Unify", "the picked key's two tangent handles share one slope per angle (a smooth pass through the key); drag a handle's end to set its angle and its length (how long the curve keeps the slope)", true)
	_break = _tan_button("Break", "the picked key's two tangent handles move apart: a corner at the key (angle and length of each side on its own)", false)


func _tan_button(txt: String, tip: String, unify: bool) -> Button:
	var b := Button.new()
	b.text = txt
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 11)
	var fb := StyleBoxFlat.new()
	fb.bg_color = Tok.c("tl_bg")
	fb.content_margin_left = 4
	fb.content_margin_right = 4
	fb.content_margin_top = 0
	fb.content_margin_bottom = 0
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, fb)
	b.pressed.connect(tangent_cmd.bind(unify))
	add_child(b)
	return b


## ROADMAP 65: Unify / Break on the picked key (the key under the last click, else the first picked dot), one undo step
func tangent_cmd(unify: bool) -> bool:
	var i := sel_i
	if i < 0 and not picked.is_empty():
		i = picked_keys()[0]
	if scene == null or i < 0 or i >= keys().size():
		if say.is_valid():
			say.call("%s: pick a key first (click its dot), then press it again" % ("Unify" if unify else "Break"))
		return false
	if begin.is_valid():
		begin.call()
	var r := PartKeys.unify(_store(), joint, i) if unify else PartKeys.break_handles(_store(), joint, i)
	queue_redraw()
	if changed.is_valid():
		changed.call()
	if say.is_valid():
		say.call("key %d: tangent handles %s  (Ctrl+Z takes it back)" % [i + 1, "unified: one slope through the key" if unify else "broken: each side on its own"])
	return r


## the keys whose handles are drawn and can be grabbed: the picked dots' keys, and the one under the last click
func handle_keys() -> Array:
	var out := picked_keys()
	if sel_i >= 0 and sel_i < keys().size() and not out.has(sel_i):
		out.append(sel_i)
	return out


## does key i have a handle on `side`: a bezier segment on that side
func has_handle(i: int, side: String) -> bool:
	var ks := keys()
	var nb := i - 1 if side == "in" else i + 1
	if nb < 0 or nb >= ks.size():
		return false
	return PartKeys.interp_of(ks[nb] if side == "in" else ks[i]) == "bezier"


## the handle's end in local pixels for angle c of key i ("in" / "out"): key + (length in time, change in angle)
func handle_pos(c: int, i: int, side: String) -> Vector2:
	var ks := keys()
	var hs: Array = PartKeys.handles_of(ks, i)
	var hv: Vector4 = hs[0 if side == "in" else 1]
	var k: Dictionary = ks[i]
	var v: Vector3 = k["v"]
	return Vector2(t_to_x(float(k["t"]) + hv.x), cv_to_y(c, v[c] + hv[c + 1]))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_READY:
		if _shape != null:
			_shape.reset_size()
			_factor.reset_size()
			_mods.reset_size()
			_btn.reset_size()
			_view_btn.reset_size()
			_shape.position = Vector2(PAD_L + _btn.size.x + 160, 1)
			_factor.position = Vector2(_shape.position.x + _shape.size.x + 4, 1)
			_mods.position = Vector2(_factor.position.x + _factor.size.x + 8, 1)
			_view_btn.position = Vector2(_mods.position.x + _mods.size.x + 8, 1)
			_unify.reset_size()
			_break.reset_size()
			_unify.position = Vector2(_view_btn.position.x + _view_btn.size.x + 8, 1)
			_break.position = Vector2(_unify.position.x + _unify.size.x + 2, 1)


## DD1: reshape the selected dots with a Key > Blend tool (KeyBlend), one undo step; the angles kept legal
func shape(tool: String, f: float) -> Dictionary:
	if picked.is_empty() or keys().is_empty():
		last_shape = {"tool": tool, "changed": 0, "skipped": 0}
		return last_shape
	if begin.is_valid():
		begin.call()
	var ks := keys()
	var r := KeyBlend.apply(ks, picked, tool, f)
	if limit.is_valid():
		for q in picked:
			var v: Vector3 = ks[q[1]]["v"]
			var lv: Vector3 = limit.call(joint, v)
			v[q[0]] = lv[q[0]]
			ks[q[1]]["v"] = v
	last_shape = {"tool": tool, "changed": r["changed"], "skipped": r["skipped"]}
	queue_redraw()
	if changed.is_valid():
		changed.call()
	return last_shape


## DD2: the Mods menu. A modifier acts on the angle under the mouse's last pick (all three when none); one undo step.
## noise: 4 deg peak to peak, a bump every 0.3 s; stepped: held 2 frames (animation "on twos"); limits: the keys' own range
## on that angle (so an overshooting curve or the noise stays inside what was keyed)
func mod_item(id: int) -> int:
	var ks := keys()
	if ks.is_empty() or scene == null:
		return -1
	var ch := sel_ch
	var ms := PartKeys.mods_of(ks)
	if (id == 3 or id == 4) and ms.is_empty():
		return -1
	if begin.is_valid():
		begin.call()
	var r := 0
	match id:
		0:
			r = PartKeys.add_mod(_store(), joint, {"type": "noise", "ch": ch, "strength": 4.0, "scale": 0.3, "phase": 0.0, "seed": ks.size(), "mix": 1.0})
		1:
			r = PartKeys.add_mod(_store(), joint, {"type": "stepped", "ch": ch, "step": 2.0 / float(maxi(fps, 1)), "offset": 0.0, "mix": 1.0})
		2:
			var lo := INF
			var hi := -INF
			for k in ks:
				for c in 3:
					if ch < 0 or c == ch:
						lo = minf(lo, (k["v"] as Vector3)[c])
						hi = maxf(hi, (k["v"] as Vector3)[c])
			r = PartKeys.add_mod(_store(), joint, {"type": "limits", "ch": ch, "min": lo, "max": hi, "mix": 1.0})
		3:
			ms[-1]["mix"] = clampf(_factor.value, 0.0, 1.0)
			r = ms.size() - 1
		4:
			PartKeys.remove_mod(_store(), joint, ms.size() - 1)
	queue_redraw()
	if changed.is_valid():
		changed.call()
	return r


func keys() -> Array:
	if scene == null or joint == "" or not _store().has(joint):
		return []
	return _store()[joint]


func _store() -> Dictionary:
	return scene.face if au else scene.part_keys


func _val(ks: Array, t: float, c: int) -> float:
	var v: float = PartKeys.value_at(ks, t)[c]
	if au:
		var r := Face.range_of(joint)
		v = clampf(v, r.x, r.y)
	return v


func plot() -> Rect2:
	return Rect2(PAD_L, PAD_T, maxf(size.x - PAD_L - PAD_R, 10.0), maxf(size.y - PAD_T - PAD_B, 10.0))


func t_to_x(t: float) -> float:
	var p := plot()
	return p.position.x + (t - t0) / maxf(t1 - t0, 1e-6) * p.size.x


func x_to_t(x: float) -> float:
	var p := plot()
	return t0 + (x - p.position.x) / p.size.x * (t1 - t0)


func v_to_y(v: float) -> float:
	var p := plot()
	return p.position.y + (v1 - v) / maxf(v1 - v0, 1e-6) * p.size.y


func y_to_v(y: float) -> float:
	var p := plot()
	return v1 - (y - p.position.y) / p.size.y * (v1 - v0)


## DD3: switch the view (plain / normal / stacked) and refit each angle's range
func set_view(v: String) -> void:
	if not v in VIEWS:
		return
	view = v
	if _view_btn != null:
		_view_btn.text = VIEW_NAMES[v]
		_view_btn.reset_size()
	refit()
	queue_redraw()


## DD3: each angle's own range over the view's time span (the keys and the curve sampled, modifiers included); an angle
## that does not move (< 0.01 deg: a held angle, float dust) gets 1 deg round its middle, so a flat line is not blown up
## into noise; anything that moves is fitted, however small (a 0.6 deg twist fills the plot like a 60 deg bend)
func refit() -> void:
	var ks := keys()
	for c in 3:
		var lo := INF
		var hi := -INF
		for k in ks:
			lo = minf(lo, (k["v"] as Vector3)[c])
			hi = maxf(hi, (k["v"] as Vector3)[c])
		if not ks.is_empty():
			for i in 121:
				var x := PartKeys.value_at(ks, t0 + (t1 - t0) * float(i) / 120.0)[c]
				lo = minf(lo, x)
				hi = maxf(hi, x)
		if not is_finite(lo):
			lo = -1.0
			hi = 1.0
		if hi - lo < 0.01:
			var mid := (hi + lo) * 0.5
			lo = mid - 0.5
			hi = mid + 0.5
		_rng[c] = Vector2(lo, hi)


## DD3: the rect angle c is drawn in (the whole plot, or its lane in the stacked view)
func lane(c: int) -> Rect2:
	var p := plot()
	if view != "stacked":
		return p
	var gap := 6.0
	var h := (p.size.y - 2.0 * gap) / 3.0
	return Rect2(p.position.x, p.position.y + c * (h + gap), p.size.x, h)


## DD3: angle c's value -> y and back, in the current view (plain = v_to_y; fitted: the range lo..hi plus 7.5 % each side
## fills the lane, so in the normal view lo is -1 and hi is +1 on one shared scale)
func cv_to_y(c: int, v: float) -> float:
	if view == "plain":
		return v_to_y(v)
	var r := lane(c)
	var lo: float = _rng[c].x
	var hi: float = _rng[c].y
	var a := lo - (hi - lo) * 0.075
	var b := hi + (hi - lo) * 0.075
	return r.position.y + (b - v) / (b - a) * r.size.y


func cy_to_v(c: int, y: float) -> float:
	if view == "plain":
		return y_to_v(y)
	var r := lane(c)
	var lo: float = _rng[c].x
	var hi: float = _rng[c].y
	var a := lo - (hi - lo) * 0.075
	var b := hi + (hi - lo) * 0.075
	return b - (y - r.position.y) / r.size.y * (b - a)


## fit the view: all keys' times and every curve's range (sampled, so a curve's bulge between keys is inside too)
func frame_all() -> void:
	var ks := keys()
	if ks.is_empty() and band.get("ok", false):
		# no keys, a walk: the view is the band's cycle, every point of it inside (YY7)
		var pad := (float(band["t1"]) - float(band["t0"])) * 0.04
		t0 = float(band["t0"]) - pad
		t1 = float(band["t1"]) + pad
		var lo := 1e9
		var hi := -1e9
		for i in 101:
			lo = minf(lo, minf(float(band["mean"][i]) - 2.0 * float(band["sd"][i]), float(band["you"][i])))
			hi = maxf(hi, maxf(float(band["mean"][i]) + 2.0 * float(band["sd"][i]), float(band["you"][i])))
		v0 = lo - 4.0
		v1 = hi + 4.0
	elif ks.is_empty():
		t0 = 0.0
		t1 = maxf(scene.length() if scene != null else 1.0, 0.1)
		v0 = -30.0
		v1 = 30.0
	else:
		t0 = float(ks[0]["t"])
		t1 = float(ks[-1]["t"])
		if t1 - t0 < 0.1:
			t0 -= 0.25
			t1 += 0.25
		var pad := (t1 - t0) * 0.06
		t0 -= pad
		t1 += pad
		var lo := 1e9
		var hi := -1e9
		for i in 61:
			var v := PartKeys.value_at(ks, t0 + (t1 - t0) * float(i) / 60.0)
			for c in 3:
				lo = minf(lo, v[c])
				hi = maxf(hi, v[c])
		for k in ks:
			for c in 3:
				lo = minf(lo, (k["v"] as Vector3)[c])
				hi = maxf(hi, (k["v"] as Vector3)[c])
		if hi - lo < 10.0:
			var mid := (hi + lo) * 0.5
			lo = mid - 5.0
			hi = mid + 5.0
		var vp := (hi - lo) * 0.1
		v0 = lo - vp
		v1 = hi + vp
	refit()
	queue_redraw()


## the drawn line of angle c: PartKeys.value_at() at a point every 2 px (and at every key's time), as local pixel positions
## L84 BUFFER CURVE GHOST: keys of a stored curve (CurveBuffer.keys_of) drawn faintly behind the live one; [] = none
var ghost_keys: Array = []


func ghost_line(c: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if ghost_keys.is_empty():
		return pts
	var n := int(ceilf(plot().size.x / 2.0))
	for i in n + 1:
		var t := t0 + (t1 - t0) * float(i) / float(n)
		pts.append(Vector2(t_to_x(t), cv_to_y(c, _val(ghost_keys, t, c))))
	return pts


func polyline(c: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var ks := keys()
	if ks.is_empty():
		return pts
	var p := plot()
	var ts := []
	var n := int(ceilf(p.size.x / 2.0))
	for i in n + 1:
		ts.append(t0 + (t1 - t0) * float(i) / float(n))
	for k in ks:
		if float(k["t"]) > t0 and float(k["t"]) < t1:
			ts.append(float(k["t"]))
	ts.sort()
	for t in ts:
		pts.append(Vector2(t_to_x(t), cv_to_y(c, _val(ks, t, c))))
	return pts


## REAL WALKERS' BAND (YY7): the people's mean +- k SD over the band's cycle, as one closed outline (upper edge left to
## right, lower edge back), in local pixels; the body's own line over the same cycle with k = NAN
func band_poly(k: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if not band.get("ok", false):
		return pts
	for i in 101:
		var t := lerpf(float(band["t0"]), float(band["t1"]), i / 100.0)
		var v: float = float(band["you"][i]) if is_nan(k) else float(band["mean"][i]) + k * float(band["sd"][i])
		pts.append(Vector2(t_to_x(t), v_to_y(v)))
	if not is_nan(k):
		for i in range(100, -1, -1):
			var t := lerpf(float(band["t0"]), float(band["t1"]), i / 100.0)
			pts.append(Vector2(t_to_x(t), v_to_y(float(band["mean"][i]) - k * float(band["sd"][i]))))
	return pts


func _draw_band() -> void:
	if not band.get("ok", false):
		return
	var ink := Tok.c("ink")
	draw_colored_polygon(band_poly(2.0), Color(ink, 0.07))
	draw_colored_polygon(band_poly(1.0), Color(ink, 0.12))
	draw_polyline(band_poly(NAN), Color(Tok.c("say"), 0.95), 2.5, true)
	var name := "%s %s" % ["right" if band["side"] == "_r" else "left", band["joint"]]
	var txt := "%s vs 42 real walkers (mean +-1 / 2 SD, Fukuchi 2018), one step %.2f-%.2f s: " % [name, band["t0"], band["t1"]]
	txt += ("OUTSIDE 2 SD for %d %% of the step" % int(round(float(band["out"]) * 100.0))) if band["listed"] else ("inside (%d %% out)" % int(round(float(band["out"]) * 100.0)))
	draw_string(get_theme_default_font(), Vector2(PAD_L + 4, plot().end.y - 6), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Tok.c("say") if band["listed"] else Tok.dim(0.85))


func key_pos(c: int, i: int) -> Vector2:
	var k: Dictionary = keys()[i]
	return Vector2(t_to_x(float(k["t"])), cv_to_y(c, (k["v"] as Vector3)[c]))


## the key dot under a point -> [channel, index] or [-1, -1]
func pick(at: Vector2) -> Array:
	var best := [-1, -1]
	var bd := HIT
	var ks := keys()
	for i in ks.size():
		for c in 3:
			var d := key_pos(c, i).distance_to(at)
			if d <= bd:
				bd = d
				best = [c, i]
	return best


func _col(c: int) -> Color:
	return Tok.c(["ch_x", "ch_y", "ch_z"][c])


func _draw() -> void:
	var p := plot()
	draw_rect(Rect2(Vector2.ZERO, size), Tok.c("graph_bg"))
	var f := get_theme_default_font()
	var ink := Tok.c("ink")
	var ks := keys()
	draw_string(f, Vector2(PAD_L + _btn.size.x + 8, 15), ("%s: %d key%s" % [joint, ks.size(), "" if ks.size() == 1 else "s"]) if joint != "" else "pick a part", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Tok.dim(0.8))
	for c in 3:
		draw_string(f, Vector2(size.x - 150 + c * 48, 15), ["X bend", "Y side", "Z twist"][c], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, _col(c))
	if view != "plain" and _mode == "":
		refit()   # DD3: the fitted ranges follow the keys (not during a gesture: the scale would slide under the mouse)
	if view == "normal":
		for g in [-1.0, 0.0, 1.0]:   # the shared -1 / 0 / +1 rows (angle 0's map: every angle's lo / mid / hi land there)
			var y := cv_to_y(0, lerpf(_rng[0].x, _rng[0].y, (g + 1.0) * 0.5))
			draw_line(Vector2(p.position.x, y), Vector2(p.end.x, y), Tok.c("grid_major") if g == 0.0 else Tok.c("grid"), 1.0)
			draw_string(f, Vector2(2, y + 4), "%+d" % int(g) if g != 0.0 else "0", HORIZONTAL_ALIGNMENT_LEFT, PAD_L - 6, 11, Tok.dim(0.7))
	elif view == "stacked":
		for c in 3:
			var r := lane(c)
			draw_rect(r, Color(_col(c), 0.05), true)
			draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.end.y), Tok.c("grid"), 1.0)
			draw_string(f, Vector2(r.position.x + 4, r.position.y + 12), "%s  %.1f..%.1f deg" % [["X bend", "Y side", "Z twist"][c], _rng[c].x, _rng[c].y], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, _col(c))
	# grid: a line every nice step in degrees, the zero line stronger
	var step := _nice((v1 - v0) / 4.0)
	var g := ceilf(v0 / step) * step
	while g <= v1 and view == "plain":
		var y := v_to_y(g)
		draw_line(Vector2(p.position.x, y), Vector2(p.end.x, y), Tok.c("grid_major") if absf(g) < 1e-6 else Tok.c("grid"), 1.0)
		draw_string(f, Vector2(2, y + 4), "%d" % int(round(g)), HORIZONTAL_ALIGNMENT_LEFT, PAD_L - 6, 11, Tok.dim(0.7))
		g += step
	var ph := t_to_x(playhead)
	if ph >= p.position.x and ph <= p.end.x:
		draw_line(Vector2(ph, p.position.y), Vector2(ph, p.end.y), Tok.c("say"), 1.5)
	draw_string(f, Vector2(p.position.x, size.y - 5), "%.2f s" % t0, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Tok.dim(0.7))
	draw_string(f, Vector2(p.end.x - 40, size.y - 5), "%.2f s" % t1, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Tok.dim(0.7))
	_draw_band()
	_draw_why()
	if ks.is_empty() and band.get("ok", false):
		return
	if ks.is_empty():
		draw_string(f, Vector2(p.position.x + 20, p.position.y + p.size.y * 0.5), "no part keys on this part: pick it and press K at a time to key it", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Tok.dim(0.8))
		return
	for c in 3:
		if not ghost_keys.is_empty():
			draw_polyline(ghost_line(c), Color(_col(c), 0.35), 1.5, true)
		draw_polyline(polyline(c), _col(c), 2.0, true)
	_draw_why_lines()
	for i in ks.size():
		var kt := PartKeys.ktype_of(ks[i])   # ROADMAP 66: a breakdown is a small diamond, an in-between a small ring; a key a dot
		for c in 3:
			var q := key_pos(c, i)
			var on := (c == sel_ch and i == sel_i) or is_picked(c, i)
			var r := 5.5 if on else 4.0
			if kt == "breakdown":
				var dm := PackedVector2Array([q + Vector2(0, -r), q + Vector2(r, 0), q + Vector2(0, r), q + Vector2(-r, 0)])
				draw_colored_polygon(dm, ink if on else _col(c))
				draw_polyline(PackedVector2Array([dm[0], dm[1], dm[2], dm[3], dm[0]]), Tok.c("kt_break"), 1.5)
			elif kt == "inbetween":
				draw_arc(q, r * 0.75, 0.0, TAU, 16, ink if on else _col(c), 2.0)
			else:
				draw_circle(q, r, ink if on else _col(c))
				draw_arc(q, r, 0.0, TAU, 16, _col(c) if on else Tok.c("tl_bg"), 1.5)
	for i in handle_keys():   # ROADMAP 65: the picked keys' tangent handles, a line and a square at each end
		for c in 3:
			for side in ["in", "out"]:
				if has_handle(i, side):
					var q := key_pos(c, i)
					var e := handle_pos(c, i, side)
					draw_line(q, e, Color(_col(c), 0.7), 1.0)
					var on: bool = _hd == [c, i, side]
					draw_rect(Rect2(e - Vector2(3, 3), Vector2(6, 6)), ink if on else _col(c), true)
	if _mode == "box":
		draw_rect(_box.abs(), Tok.dim(0.15), true)
		draw_rect(_box.abs(), Tok.dim(0.6), false, 1.0)


## DD5: each span of a Check rule this joint moves: a red band over its time with the rule's name, and the curves inside
## it drawn again in red (drawn after the lines: see _draw_why_lines)
func why_rect(s: Dictionary) -> Rect2:
	var p := plot()
	var x0 := clampf(t_to_x(float(s["t0"])), p.position.x, p.end.x)
	var x1 := clampf(t_to_x(float(s["t1"])), p.position.x, p.end.x)
	return Rect2(x0, p.position.y, maxf(x1 - x0, 2.0), p.size.y)


func _draw_why() -> void:
	var f := get_theme_default_font()
	var red := Tok.c("fail")
	var taken := []   # [x0, x1, row] of the names already written: a name that would overlap one goes a row up
	for s in why:
		var r := why_rect(s)
		if r.end.x <= plot().position.x or r.position.x >= plot().end.x:
			continue
		draw_rect(r, Color(red, 0.16), true)
		var w := f.get_string_size(String(s["rule"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var x0 := r.position.x + 3
		var row := 0
		while taken.any(func(q): return q[2] == row and x0 < q[1] + 4 and x0 + w > q[0] - 4):
			row += 1
		taken.append([x0, x0 + w, row])
		draw_string(f, Vector2(x0, r.end.y - 6 - 14 * row), String(s["rule"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, red)


func _draw_why_lines() -> void:
	var red := Tok.c("fail")
	for s in why:
		for c in 3:
			var seg := PackedVector2Array()
			for q in polyline(c):
				if q.x >= t_to_x(float(s["t0"])) and q.x <= t_to_x(float(s["t1"])):
					seg.append(q)
			if seg.size() >= 2:
				draw_polyline(seg, red, 3.0, true)


func _nice(x: float) -> float:
	var e: float = pow(10.0, floorf(log(maxf(x, 1e-6)) / log(10.0)))
	for m in [1.0, 2.0, 5.0, 10.0]:
		if m * e >= x:
			return m * e
	return 10.0 * e


func is_picked(c: int, i: int) -> bool:
	for q in picked:
		if q[0] == c and q[1] == i:
			return true
	return false


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := ev as InputEventMouseButton
		if mb.pressed:
			var hit := pick(mb.position)
			_press = mb.position
			_dragging = false
			var hh := pick_handle(mb.position)
			if not hh.is_empty() and hit[1] < 0:
				_hd = hh
				_mode = "handle"
				queue_redraw()
				accept_event()
				return
			if hit[1] >= 0:
				if mb.shift_pressed:
					if is_picked(hit[0], hit[1]):
						picked = picked.filter(func(q): return not (q[0] == hit[0] and q[1] == hit[1]))
					else:
						picked.append(hit)
				elif not is_picked(hit[0], hit[1]):
					picked = [hit]
				sel_ch = hit[0]
				sel_i = hit[1]
				_mode = "scale" if mb.alt_pressed else "move"
				_snap = keys().map(func(k): return [float(k["t"]), k["v"]])
			else:
				if not mb.shift_pressed:
					picked = []
				sel_ch = -1
				sel_i = -1
				_mode = "box"
				_box = Rect2(mb.position, Vector2.ZERO)
			queue_redraw()
			accept_event()
		else:
			if _mode == "box":
				var r := _box.abs()
				if r.size.length() >= MOVE_MIN:
					for i in keys().size():
						for c in 3:
							if r.has_point(key_pos(c, i)) and not is_picked(c, i):
								picked.append([c, i])
			_mode = ""
			_hd = []
			_dragging = false
			queue_redraw()
	elif ev is InputEventMouseMotion and (ev as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT and _mode != "":
		var mm := ev as InputEventMouseMotion
		if _mode == "box":
			_box.size = mm.position - _box.position
			queue_redraw()
			accept_event()
			return
		if not _dragging and mm.position.distance_to(_press) < MOVE_MIN:
			return
		if not _dragging:
			_dragging = true
			if begin.is_valid():
				begin.call()
		if _mode == "handle":
			drag_handle(mm.position)
		elif _mode == "scale":
			scale_picked(1.0 + (mm.position.x - _press.x) / 150.0, 1.0 - (mm.position.y - _press.y) / 150.0)
		else:
			var dvs := Vector3.ZERO
			for c in 3:   # DD3: each angle by its own scale (one in the plain view)
				dvs[c] = cy_to_v(c, mm.position.y) - cy_to_v(c, _press.y)
			move_picked(x_to_t(mm.position.x) - x_to_t(_press.x), dvs, mm.ctrl_pressed)
		accept_event()
	elif ev is InputEventKey and ev.pressed and (ev as InputEventKey).keycode == KEY_ESCAPE and (sel_i >= 0 or not picked.is_empty()):
		sel_ch = -1
		sel_i = -1
		picked = []
		queue_redraw()
		accept_event()


## the handle end under a point -> [angle, key index, side] or []
func pick_handle(at: Vector2) -> Array:
	var best := []
	var bd := HIT * 0.8
	for i in handle_keys():
		for c in 3:
			for side in ["in", "out"]:
				if has_handle(i, side):
					var d := handle_pos(c, i, side).distance_to(at)
					if d <= bd:
						bd = d
						best = [c, i, side]
	return best


## ROADMAP 65: the grabbed handle follows the mouse: its end's distance in time from the key is the WEIGHT, its height the
## angle. The weight stays inside the key's interval (PartKeys.set_tangent), so the curve never runs back in time
func drag_handle(at: Vector2) -> void:
	if _hd.is_empty() or scene == null:
		return
	var c: int = _hd[0]
	var i: int = _hd[1]
	var side: String = _hd[2]
	var k: Dictionary = keys()[i]
	var len := absf(x_to_t(at.x) - float(k["t"]))
	var dv := cy_to_v(c, at.y) - (k["v"] as Vector3)[c]
	if (x_to_t(at.x) < float(k["t"])) != (side == "in"):
		len = 0.0   # a handle dragged across its key has no length: it stops at the shortest
	PartKeys.set_tangent(_store(), joint, i, side, c, len, dv)
	queue_redraw()
	if changed.is_valid():
		changed.call()


## the key indices with any selected dot, rising
func picked_keys() -> Array:
	var out := []
	for q in picked:
		if not out.has(q[1]):
			out.append(q[1])
	out.sort()
	return out


## ROADMAP 66: "pick only main keys": the picks become every "key" (not a breakdown or in-between) on all three angles,
## so a drag or scale retimes just the keys and the breakdowns stay where they are
func pick_main_keys() -> int:
	var ks := keys()
	picked = []
	var n := 0
	for i in ks.size():
		if PartKeys.ktype_of(ks[i]) == "key":
			n += 1
			for c in 3:
				picked.append([c, i])
	sel_ch = -1
	sel_i = -1
	queue_redraw()
	return n


## move every selected dot from where the gesture began: dt (s) to each selected key's time, dv (deg) to each selected
## angle. The dragged key's new time is snapped (a whole frame, or with `to_card` the nearest card's time) and the same
## change goes to all; it is cut back so no moved key reaches an unselected neighbour.
func move_picked(dt: float, dv: Variant, to_card := false) -> void:
	var dv3: Vector3 = dv if dv is Vector3 else Vector3(float(dv), float(dv), float(dv))   # DD3: per angle
	var ks := keys()
	if _snap.size() != ks.size() or picked.is_empty():
		return
	var ids := picked_keys()
	var fr := 1.0 / float(maxi(fps, 1))
	var a: int = sel_i if ids.has(sel_i) else ids[0]
	var ta := float(_snap[a][0]) + dt
	if to_card and not card_times.is_empty():
		var best: float = card_times[0]
		for ct in card_times:
			if absf(float(ct) - ta) < absf(best - ta):
				best = float(ct)
		ta = best
	else:
		ta = snappedf(ta, fr)
	dt = ta - float(_snap[a][0])
	var gap := PartKeys.SAME_T * 2.0
	var lo := -INF
	var hi := INF
	for i in ids:
		lo = maxf(lo, -float(_snap[i][0]))
		if i > 0 and not ids.has(i - 1):
			lo = maxf(lo, float(_snap[i - 1][0]) + gap - float(_snap[i][0]))
		if i < ks.size() - 1 and not ids.has(i + 1):
			hi = minf(hi, float(_snap[i + 1][0]) - gap - float(_snap[i][0]))
	dt = clampf(dt, lo, hi)
	for i in ids:
		ks[i]["t"] = float(_snap[i][0]) + dt
	for q in picked:
		var nv: Vector3 = ks[q[1]]["v"]
		nv[q[0]] = (_snap[q[1]][1] as Vector3)[q[0]] + dv3[q[0]]
		if limit.is_valid():
			nv[q[0]] = (limit.call(joint, nv) as Vector3)[q[0]]
		ks[q[1]]["v"] = nv
	queue_redraw()
	if changed.is_valid():
		changed.call()


## scale the selection from where the gesture began: times about the playhead by ft, each selected angle about the
## selected dots' mean on that angle by fv. Times land on whole frames; a scale that would put a key on or past a
## neighbour (selected or not) is refused (the last good one stays). A key the scale does not move in time (the one on
## the playhead, or every key when only the angles are scaled) keeps its time exactly.
func scale_picked(ft: float, fv: float) -> void:
	var ks := keys()
	if _snap.size() != ks.size() or picked.is_empty():
		return
	ft = maxf(ft, 0.0)
	var ids := picked_keys()
	var fr := 1.0 / float(maxi(fps, 1))
	var nt := []
	for i in ks.size():
		nt.append(float(_snap[i][0]))
	for i in ids:
		var off := (float(_snap[i][0]) - playhead) * ft
		if absf(ft - 1.0) > 1e-6 and absf(off) > 1e-9:   # a key the scale does not move in time stays where it is
			nt[i] = maxf(0.0, snappedf(playhead + off, fr))
	for i in range(1, nt.size()):
		if float(nt[i]) - float(nt[i - 1]) < PartKeys.SAME_T * 2.0:
			return
	var mean := [0.0, 0.0, 0.0]
	var n := [0, 0, 0]
	for q in picked:
		mean[q[0]] += (_snap[q[1]][1] as Vector3)[q[0]]
		n[q[0]] += 1
	for i in ids:
		ks[i]["t"] = nt[i]
	for q in picked:
		var c: int = q[0]
		var mu: float = mean[c] / maxi(n[c], 1)
		var nv: Vector3 = ks[q[1]]["v"]
		nv[c] = mu + ((_snap[q[1]][1] as Vector3)[c] - mu) * fv
		if limit.is_valid():
			nv[c] = (limit.call(joint, nv) as Vector3)[c]
		ks[q[1]]["v"] = nv
	queue_redraw()
	if changed.is_valid():
		changed.call()


## put key i's angle c at v (clamped legal) and the key at time t (whole frames, between its neighbours); keeps selection
func move_key(c: int, i: int, t: float, v: float) -> void:
	var ks := keys()
	if i < 0 or i >= ks.size():
		return
	var k: Dictionary = ks[i]
	var fr := 1.0 / float(maxi(fps, 1))
	var nt := maxf(0.0, snappedf(t, fr))
	var gap := PartKeys.SAME_T * 2.0
	if i > 0:
		nt = maxf(nt, float(ks[i - 1]["t"]) + gap)
	if i < ks.size() - 1:
		nt = minf(nt, float(ks[i + 1]["t"]) - gap)
	var nv: Vector3 = k["v"]
	nv[c] = v
	if limit.is_valid():
		nv[c] = (limit.call(joint, nv) as Vector3)[c]
	k["t"] = nt
	k["v"] = nv
	queue_redraw()
	if changed.is_valid():
		changed.call()
