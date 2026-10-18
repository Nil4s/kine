## curve_editor.gd - CURVE EDITOR (round 42, GATES XX2, UPGRADES_300 #240).
## A panel that draws the picked joint's PART KEYS (scripts/part_keys.gd) as curves against time: one per angle,
## X (bend) red, Y (side) green, Z (twist) blue, a dot at every key, a line at the playhead.
## The curves are PartKeys.at() sampled many times, so whatever the interpolation is, the line drawn is the line played.
## Click a key to pick it; drag it: up/down changes that angle (within the joint's limits when `limit` is set), left/right
## moves the whole key in time (snapped to whole frames at `fps`, never past its neighbours). One undo step per drag
## (`begin` is called once, on the first move). Esc or a click on nothing lets go. "Frame all" fits the view to the keys.
## This node owns no data: it edits `scene.part_keys` in place and calls `changed` after every edit.
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


func keys() -> Array:
	if scene == null or joint == "" or not scene.part_keys.has(joint):
		return []
	return scene.part_keys[joint]


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
			var v := PartKeys.at(ks, t0 + (t1 - t0) * float(i) / 60.0)
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
	queue_redraw()


## the drawn line of angle c: PartKeys.at() at a point every 2 px (and at every key's time), as local pixel positions
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
		pts.append(Vector2(t_to_x(t), v_to_y(PartKeys.at(ks, t)[c])))
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
	return Vector2(t_to_x(float(k["t"])), v_to_y((k["v"] as Vector3)[c]))


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
	draw_string(f, Vector2(PAD_L + 76, 15), ("%s: %d key%s" % [joint, ks.size(), "" if ks.size() == 1 else "s"]) if joint != "" else "pick a part", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Tok.dim(0.8))
	for c in 3:
		draw_string(f, Vector2(size.x - 150 + c * 48, 15), ["X bend", "Y side", "Z twist"][c], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, _col(c))
	# grid: a line every nice step in degrees, the zero line stronger
	var step := _nice((v1 - v0) / 4.0)
	var g := ceilf(v0 / step) * step
	while g <= v1:
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
	if ks.is_empty() and band.get("ok", false):
		return
	if ks.is_empty():
		draw_string(f, Vector2(p.position.x + 20, p.position.y + p.size.y * 0.5), "no part keys on this part: pick it and press K at a time to key it", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Tok.dim(0.8))
		return
	for c in 3:
		draw_polyline(polyline(c), _col(c), 2.0, true)
	for i in ks.size():
		for c in 3:
			var q := key_pos(c, i)
			var on := c == sel_ch and i == sel_i
			draw_circle(q, 5.5 if on else 4.0, ink if on else _col(c))
			draw_arc(q, 5.5 if on else 4.0, 0.0, TAU, 16, _col(c) if on else Tok.c("tl_bg"), 1.5)


func _nice(x: float) -> float:
	var e: float = pow(10.0, floorf(log(maxf(x, 1e-6)) / log(10.0)))
	for m in [1.0, 2.0, 5.0, 10.0]:
		if m * e >= x:
			return m * e
	return 10.0 * e


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			var hit := pick(ev.position)
			sel_ch = hit[0]
			sel_i = hit[1]
			_press = ev.position
			_dragging = false
			queue_redraw()
			accept_event()
		else:
			_dragging = false
	elif ev is InputEventMouseMotion and (ev as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT and sel_i >= 0:
		if not _dragging and ev.position.distance_to(_press) < MOVE_MIN:
			return
		if not _dragging:
			_dragging = true
			if begin.is_valid():
				begin.call()
		move_key(sel_ch, sel_i, x_to_t(ev.position.x), y_to_v(ev.position.y))
		accept_event()
	elif ev is InputEventKey and ev.pressed and (ev as InputEventKey).keycode == KEY_ESCAPE and sel_i >= 0:
		sel_ch = -1
		sel_i = -1
		queue_redraw()
		accept_event()


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
