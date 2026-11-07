## graph_editor.gd - GRAPH EDITOR DEPTH (round 51, GATES GE1..GE4, docs/GAP_ANALYSIS.md #7; definitions in
## docs/research/GRAPH_EDITOR.md, learned from Blender's manual, no Blender code).
## The curve editor (scripts/curve_editor.gd) shows ONE part's three angles. This subclass adds Blender's Graph Editor
## habits on top, and with `multi` off it IS the curve editor (every call goes to the parent unchanged):
##   CHANNELS (GE1)  `multi` on: every part with part keys is shown at once, one CHANNEL per part and angle, each in its
##                   own colour (Blender's "Auto Rainbow": channel k of N gets hue k / N), listed in a channel region at
##                   the left; a click on a row hides / shows that channel (Blender's eye), Ctrl+click shows only it (solo).
##   SELECT + TRANSFORM (GE2)  a click picks a key dot, Shift+click adds / removes, a drag on empty plot draws a box that
##                   selects every VISIBLE channel's dot inside it. Dragging a selected dot moves all selected keys
##                   (time in whole frames, value per channel); Alt+drag or the Keys menu SCALES them about the PIVOT:
##                   the 2D cursor (playhead time, `cursor_v`; right click sets cursor_v) or the selection's bounding box
##                   centre. scale_sel: t' = pivot_t + ft * (t - pivot_t), v' = pivot_v + fv * (v - pivot_v), exactly (no
##                   snapping), refused whole when a key would go below 0 s or reach a neighbour. One undo step each.
##   NORMALIZE (GE3) `normalize` on: each channel drawn scaled so its lowest point sits on the -1 row and its highest on
##                   the +1 row (the rows NM px inside the plot's bottom / top; outside them darkened). Display only: the
##                   keys and the file are not touched; a drag in this view edits the real angle by that channel's scale.
##   CYCLES (GE4)    the Mods menu gets "Add cycles": Blender's Cycles modifier (PartKeys header). The drawn line is
##                   value_at, so the repeats (and any noise) are drawn as they play; a channel with modifiers says so
##                   in its row.
##   SHAPE (GE5)     with Channels on, the Shape menu reshapes the selected dots of EVERY channel (each part's own keys,
##                   KeyBlend's tools, one undo step); the single-part view keeps its own picked dots.
##   RANGE (GE5)     the Mods menu's last four items set the last modifier's Restrict Frame Range on the picked part:
##                   start / end at the playhead, blend 0.25 s in and out, clear. A ranged modifier shades the plot
##                   outside its range and marks its start and end (the curve drawn is value_at, so it shows the ramp).
class_name GraphEditor
extends CurveEditor

const CH_W := 132.0   # px: the channel region's width
const ROW_H := 15.0
const NM := 8.0       # px: the normalized view's +1 / -1 rows, this far inside the plot's top / bottom

var multi := false
var normalize := false
var off_ch := {}        # "joint:c" -> true
var msel := []          # the selected dots, [[joint, c, key index], ...]
var cursor_v := 0.0     # the 2D cursor's value (deg); its time is the playhead
var pivot_mode := "cursor"   # "cursor" | "box"
var dots := true        # draw the key dots (a test turns them off to read the bare curve's pixels)
var last_scale := {}    # the last scale's report {"ok", "why", "keys", "clamped"}
var _grng := {}         # "joint:c" -> Vector2(lo, hi) in the normalized view
var _gmode := ""        # "move" | "scale" | "box"
var _gpress := Vector2.ZERO
var _gsnap := {}        # joint -> [[t, v], ...] when the gesture began
var _ghit := []         # the dot the gesture began on
var _gpivot := Vector2.ZERO
var _gbox := Rect2()
var _gscene: Scene = null
var _multi_btn: Button
var _keys_menu: MenuButton
const RANGE_ITEMS := ["Range of the last modifier: start at the playhead", "Range of the last modifier: end at the playhead", "Range of the last modifier: blend 0.25 s in and out", "Range of the last modifier: clear"]   # GE5
const KEY_ITEMS := ["Scale time x factor (about the pivot)", "Scale value x factor (about the pivot)", "Pivot: 2D cursor / box centre", "Cursor value to selection", "Normalize view on / off", "Select all keys", "Show every channel", "Euler filter (selected parts)"]


func _ready() -> void:   # the parent's header controls exist by now (they are made in its _init)
	var flat_box := StyleBoxFlat.new()
	flat_box.bg_color = Tok.c("tl_bg")
	flat_box.content_margin_left = 4
	flat_box.content_margin_right = 4
	flat_box.content_margin_top = 0
	flat_box.content_margin_bottom = 0
	_multi_btn = Button.new()
	_multi_btn.text = "Channels"
	_multi_btn.toggle_mode = true
	_multi_btn.tooltip_text = "every part with keys at once, one coloured channel per part and angle; click a channel's row to hide / show it (Ctrl+click: only it)"
	_multi_btn.focus_mode = Control.FOCUS_NONE
	_multi_btn.add_theme_font_size_override("font_size", 11)
	for st in ["normal", "hover", "pressed", "focus"]:
		_multi_btn.add_theme_stylebox_override(st, flat_box)
	_multi_btn.toggled.connect(func(on): set_multi(on))
	add_child(_multi_btn)
	_keys_menu = MenuButton.new()
	_keys_menu.text = "Keys"
	_keys_menu.flat = false
	_keys_menu.tooltip_text = "scale the selected keys about the pivot by the factor box, set the pivot, normalize"
	_keys_menu.focus_mode = Control.FOCUS_NONE
	_keys_menu.add_theme_font_size_override("font_size", 11)
	for st in ["normal", "hover", "pressed", "focus"]:
		_keys_menu.add_theme_stylebox_override(st, flat_box)
	for k in KEY_ITEMS.size():
		_keys_menu.get_popup().add_item(KEY_ITEMS[k], k)
	_keys_menu.get_popup().id_pressed.connect(func(id): key_item(id))
	add_child(_keys_menu)
	_mods.get_popup().add_item("Add cycles (repeat before and after)", MOD_ITEMS.size())
	for k in RANGE_ITEMS.size():   # GE5
		_mods.get_popup().add_item(RANGE_ITEMS[k], MOD_ITEMS.size() + 1 + k)
	_place.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _multi_btn != null:
		_place.call_deferred()


func _place() -> void:
	_multi_btn.reset_size()
	_keys_menu.reset_size()
	_multi_btn.position = Vector2(_break.position.x + _break.size.x + 8, 1)   # ROADMAP 65: after Unify / Break
	_keys_menu.position = Vector2(_multi_btn.position.x + _multi_btn.size.x + 8, 1)


func set_multi(on: bool) -> void:
	multi = on
	if _multi_btn != null and _multi_btn.button_pressed != on:
		_multi_btn.set_pressed_no_signal(on)
	msel = []
	frame_all()


func set_normalize(on: bool) -> void:
	normalize = on
	set_view("normal" if on else "plain")   # the parent's own view (one part) follows, so its button says it
	_refit_multi()
	queue_redraw()


## the Mods menu's extra item: the Cycles modifier on the picked part (repeat before and after, for ever)
func mod_item(id: int) -> int:
	if id > MOD_ITEMS.size():
		return _range_item(id - MOD_ITEMS.size() - 1)
	if id != MOD_ITEMS.size():
		return super.mod_item(id)
	if keys().is_empty() or scene == null:
		return -1
	if PartKeys.mods_of(keys()).any(func(x): return String(x.get("type", "")) == "cycles"):
		return -1
	if begin.is_valid():
		begin.call()
	var r := PartKeys.add_mod(scene.part_keys, joint, {"type": "cycles", "ch": -1, "before": "repeat", "after": "repeat", "before_n": 0, "after_n": 0, "mix": 1.0})
	frame_all()
	if changed.is_valid():
		changed.call()
	return r


## GE5: the last modifier of the picked part gets / loses a frame range (Blender's Restrict Frame Range). An unset start or
## end takes the keyed span's first / last time; one undo step. Returns the modifier's index or -1
func _range_item(k: int) -> int:
	if keys().is_empty() or scene == null:
		return -1
	var ms := PartKeys.mods_of(keys())
	if ms.is_empty():
		return -1
	var idx := ms.size() - 1
	var md: Dictionary = ms[idx]
	var tf := float(keys()[0]["t"])
	var tl := float(keys()[-1]["t"])
	var s := float(md["range_start"]) if md.has("range_start") else tf
	var e := float(md["range_end"]) if md.has("range_end") else tl
	var bi := float(md.get("blend_in", 0.0))
	var bo := float(md.get("blend_out", 0.0))
	match k:
		0:
			s = playhead
		1:
			e = playhead
		2:
			bi = 0.25
			bo = 0.25
		3:
			if begin.is_valid():
				begin.call()
			PartKeys.clear_range(scene.part_keys, joint, idx)
			_after_mod()
			return idx
	if begin.is_valid():
		begin.call()
	PartKeys.set_range(scene.part_keys, joint, idx, s, e, bi, bo)
	_after_mod()
	return idx


func _after_mod() -> void:
	_refit_multi()
	queue_redraw()
	if changed.is_valid():
		changed.call()


## GE5: the Shape menu (KeyBlend's tools) on the selected dots of every channel in the channels view: each part's dots go
## to the tool as its own keys, one undo step, the joint limits kept. The single-part view is the parent's
func shape(tool: String, f: float) -> Dictionary:
	if not multi:
		return super.shape(tool, f)
	if msel.is_empty() or scene == null:
		last_shape = {"tool": tool, "changed": 0, "skipped": 0}
		return last_shape
	if begin.is_valid():
		begin.call()
	var by := {}
	for q in msel:
		if not by.has(q[0]):
			by[q[0]] = []
		(by[q[0]] as Array).append([q[1], q[2]])
	var n_ch := 0
	var n_skip := 0
	for j in by:
		var ks: Array = scene.part_keys[j]
		var r := KeyBlend.apply(ks, by[j], tool, f)
		n_ch += int(r["changed"])
		n_skip += int(r["skipped"])
		if limit.is_valid():
			for q in by[j]:
				var v: Vector3 = ks[q[1]]["v"]
				v[q[0]] = (limit.call(j, v) as Vector3)[q[0]]
				ks[q[1]]["v"] = v
	last_shape = {"tool": tool, "changed": n_ch, "skipped": n_skip}
	queue_redraw()
	if changed.is_valid():
		changed.call()
	return last_shape


## GE5: shade the plot outside a modifier's frame range and mark its start and end (every ranged modifier of part j)
func _draw_ranges(j: String, col: Color) -> void:
	if scene == null or not scene.part_keys.has(j):
		return
	var p := plot()
	for md in PartKeys.mods_of(scene.part_keys[j]):
		if not md.has("range_start") or not md.has("range_end"):
			continue
		var s := float(md["range_start"])
		var e := maxf(float(md["range_end"]), s)
		var xs := t_to_x(s)
		var xe := t_to_x(e)
		var shade := Color(0.0, 0.0, 0.0, 0.22)
		if xs > p.position.x:
			draw_rect(Rect2(p.position.x, p.position.y, minf(xs, p.end.x) - p.position.x, p.size.y), shade)
		if xe < p.end.x:
			draw_rect(Rect2(maxf(xe, p.position.x), p.position.y, p.end.x - maxf(xe, p.position.x), p.size.y), shade)
		for x in [xs, xe]:
			if x >= p.position.x and x <= p.end.x:
				draw_dashed_line(Vector2(x, p.position.y), Vector2(x, p.end.y), Color(col, 0.7), 1.0, 3.0)


## L86: the Euler filter on the parts of the selected dots (the picked part when none), ONE undo step. Returns QuatCurve's report
func euler_sel() -> Dictionary:
	if scene == null:
		return {}
	var js := []
	for q in msel:
		if not q[0] in js:
			js.append(q[0])
	if js.is_empty() and joint != "":
		js.append(joint)
	if js.is_empty():
		return {}
	if begin.is_valid():
		begin.call()
	var r := QuatCurve.euler_filter_parts(scene.part_keys, js)
	queue_redraw()
	if changed.is_valid():
		changed.call()
	return r


func key_item(id: int) -> void:
	match id:
		0:
			scale_sel(_factor.value, 1.0)
		1:
			scale_sel(1.0, _factor.value)
		2:
			pivot_mode = "box" if pivot_mode == "cursor" else "cursor"
		3:
			if not msel.is_empty():
				var s := 0.0
				for q in msel:
					s += _val(q)
				cursor_v = s / msel.size()
		4:
			set_normalize(not normalize)
		5:
			msel = []
			for ch in chans():
				if not is_hidden(ch[0], ch[1]):
					for i in (scene.part_keys[ch[0]] as Array).size():
						msel.append([ch[0], ch[1], i])
		6:
			off_ch = {}
		7:
			euler_sel()
	queue_redraw()


# ---------------------------------------------------------------- channels

## the parts shown: the picked part first (when it has keys), then every other keyed part by name
func parts() -> Array:
	if scene == null:
		return []
	var out := []
	if scene.part_keys.has(joint) and not (scene.part_keys[joint] as Array).is_empty():
		out.append(joint)
	var rest := []
	for j in scene.part_keys:
		if j != joint and not (scene.part_keys[j] as Array).is_empty():
			rest.append(String(j))
	rest.sort()
	return out + rest


## every channel [joint, angle], shown or hidden, in list order
func chans() -> Array:
	var out := []
	for j in parts():
		for c in 3:
			out.append([j, c])
	return out


func is_hidden(j: String, c: int) -> bool:
	return off_ch.has("%s:%d" % [j, c])


func set_hidden(j: String, c: int, h: bool) -> void:
	if h:
		off_ch["%s:%d" % [j, c]] = true
	else:
		off_ch.erase("%s:%d" % [j, c])
	msel = msel.filter(func(q): return not is_hidden(q[0], q[1]))
	_refit_multi()
	queue_redraw()


## Blender's Auto Rainbow: channel k of N gets hue k / N (saturated, lighter on the dark theme)
func ch_col(j: String, c: int) -> Color:
	var cs := chans()
	var n := maxi(cs.size(), 1)
	var k := 0
	for i in cs.size():
		if cs[i][0] == j and cs[i][1] == c:
			k = i
	var dark := Tok.c("graph_bg").get_luminance() < 0.5
	return Color.from_hsv(float(k) / float(n), 0.75 if dark else 0.9, 1.0 if dark else 0.72)


func ch_rows_rect() -> Rect2:
	return Rect2(0, PAD_T, CH_W, size.y - PAD_T)


func row_of(j: String, c: int) -> Rect2:
	var cs := chans()
	for i in cs.size():
		if cs[i][0] == j and cs[i][1] == c:
			return Rect2(2, PAD_T + 2 + i * ROW_H, CH_W - 6, ROW_H)
	return Rect2()


# ---------------------------------------------------------------- mapping

func plot() -> Rect2:
	if not multi:
		return super.plot()
	return Rect2(CH_W + PAD_L, PAD_T, maxf(size.x - CH_W - PAD_L - PAD_R, 10.0), maxf(size.y - PAD_T - PAD_B, 10.0))


## the times a channel's line is drawn at: every 2 px across the plot plus every key time inside it (the normalized
## ranges are measured on these same times, so the drawn top and bottom ARE the range's ends)
func line_ts(ks: Array) -> Array:
	var p := plot()
	var ts := []
	var n := int(ceilf(p.size.x / 2.0))
	for i in n + 1:
		ts.append(t0 + (t1 - t0) * float(i) / float(n))
	for k in ks:
		if float(k["t"]) > t0 and float(k["t"]) < t1:
			ts.append(float(k["t"]))
	ts.sort()
	return ts


func _refit_multi() -> void:
	if scene == null:
		return
	_grng = {}
	for j in parts():
		var ks: Array = scene.part_keys[j]
		var ts := line_ts(ks)
		var vals := ts.map(func(t): return PartKeys.value_at(ks, t))
		for c in 3:
			var lo := INF
			var hi := -INF
			for v in vals:
				lo = minf(lo, (v as Vector3)[c])
				hi = maxf(hi, (v as Vector3)[c])
			if hi - lo < 0.01:
				var mid := (hi + lo) * 0.5
				lo = mid - 0.5
				hi = mid + 0.5
			_grng["%s:%d" % [j, c]] = Vector2(lo, hi)


func rng(j: String, c: int) -> Vector2:
	return _grng.get("%s:%d" % [j, c], Vector2(-1, 1))


## channel (j, c)'s value -> y and back: degrees on the shared scale, or normalized (lo on the -1 row, hi on the +1 row)
func ch_to_y(j: String, c: int, v: float) -> float:
	if not normalize:
		return v_to_y(v)
	var p := plot()
	var r := rng(j, c)
	var yb := p.end.y - NM
	var yt := p.position.y + NM
	return yb - (v - r.x) / maxf(r.y - r.x, 1e-9) * (yb - yt)


func y_to_ch(j: String, c: int, y: float) -> float:
	if not normalize:
		return y_to_v(y)
	var p := plot()
	var r := rng(j, c)
	var yb := p.end.y - NM
	var yt := p.position.y + NM
	return r.x + (yb - y) / (yb - yt) * (r.y - r.x)


func ch_polyline(j: String, c: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if scene == null or not scene.part_keys.has(j):
		return pts
	var ks: Array = scene.part_keys[j]
	for t in line_ts(ks):
		pts.append(Vector2(t_to_x(t), ch_to_y(j, c, PartKeys.value_at(ks, t)[c])))
	return pts


func dot_pos(j: String, c: int, i: int) -> Vector2:
	var k: Dictionary = scene.part_keys[j][i]
	return Vector2(t_to_x(float(k["t"])), ch_to_y(j, c, (k["v"] as Vector3)[c]))


func _val(q: Array) -> float:
	return (scene.part_keys[q[0]][q[2]]["v"] as Vector3)[q[1]]


func frame_all() -> void:
	if not multi:
		super.frame_all()
		return
	var ps := parts()
	if ps.is_empty():
		super.frame_all()
		return
	var lo_t := INF
	var hi_t := -INF
	for j in ps:
		lo_t = minf(lo_t, float(scene.part_keys[j][0]["t"]))
		hi_t = maxf(hi_t, float(scene.part_keys[j][-1]["t"]))
	if hi_t - lo_t < 0.1:
		lo_t -= 0.25
		hi_t += 0.25
	var pad := (hi_t - lo_t) * 0.06
	t0 = lo_t - pad
	t1 = hi_t + pad
	var lo := INF
	var hi := -INF
	for j in ps:
		var ks: Array = scene.part_keys[j]
		for t in line_ts(ks):
			var v := PartKeys.value_at(ks, t)
			for c in 3:
				if not is_hidden(j, c):
					lo = minf(lo, v[c])
					hi = maxf(hi, v[c])
	if not is_finite(lo):
		lo = -30.0
		hi = 30.0
	if hi - lo < 10.0:
		var mid := (hi + lo) * 0.5
		lo = mid - 5.0
		hi = mid + 5.0
	var vp := (hi - lo) * 0.1
	v0 = lo - vp
	v1 = hi + vp
	_refit_multi()
	queue_redraw()


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	if not multi:
		super._draw()
		if scene != null and joint != "" and scene.part_keys.has(joint):
			_draw_ranges(joint, Tok.c("say"))   # GE5
		return
	if scene != _gscene:
		_gscene = scene
		msel = []
	var p := plot()
	var f := get_theme_default_font()
	var ink := Tok.c("ink")
	draw_rect(Rect2(Vector2.ZERO, size), Tok.c("graph_bg"))
	if wave_on:
		draw_multiline(wave_lines(), Color(ink, 0.2), 1.0)   # L14
	var cs := chans()
	draw_string(f, Vector2(PAD_L + _btn.size.x + 8, 15), "%d part%s, %d channels" % [parts().size(), "" if parts().size() == 1 else "s", cs.size()], HORIZONTAL_ALIGNMENT_LEFT, 150, 12, Tok.dim(0.8))
	# the channel region
	draw_rect(ch_rows_rect(), Tok.c("tl_bg"), true)
	for ch in cs:
		var r := row_of(ch[0], ch[1])
		if r.end.y > size.y:
			break
		var hid := is_hidden(ch[0], ch[1])
		var col := ch_col(ch[0], ch[1])
		draw_rect(Rect2(r.position.x + 2, r.position.y + 3, 10, 9), col if not hid else Color(col, 0.2), not hid)
		var nm := "%s %s" % [ch[0], ["X", "Y", "Z"][ch[1]]]
		var ms := PartKeys.mods_of(scene.part_keys[ch[0]])
		if not ms.is_empty():
			nm += " ~" + ",".join(ms.map(func(x): return String(x.get("type", ""))))
		draw_string(f, Vector2(r.position.x + 16, r.position.y + 11), nm, HORIZONTAL_ALIGNMENT_LEFT, CH_W - 22, 10, Tok.dim(0.35 if hid else 0.85))
	if normalize:
		if _gmode == "":
			_refit_multi()   # not mid-gesture: the scale would slide under the mouse
		var yt := p.position.y + NM
		var yb := p.end.y - NM
		var shade := Color(Tok.c("graph_bg").darkened(0.6), 0.6)   # Blender darkens outside -1..1
		draw_rect(Rect2(p.position.x, p.position.y, p.size.x, NM), shade, true)
		draw_rect(Rect2(p.position.x, yb, p.size.x, NM), shade, true)
		for g in [[yt, "+1"], [(yt + yb) * 0.5, "0"], [yb, "-1"]]:
			draw_line(Vector2(p.position.x, g[0]), Vector2(p.end.x, g[0]), Tok.c("grid_major") if g[1] == "0" else Tok.c("grid"), 1.0)
			draw_string(f, Vector2(CH_W + 2, float(g[0]) + 4), g[1], HORIZONTAL_ALIGNMENT_LEFT, PAD_L - 6, 11, Tok.dim(0.7))
	else:
		var step := _nice((v1 - v0) / 4.0)
		var g := ceilf(v0 / step) * step
		while g <= v1:
			var y := v_to_y(g)
			draw_line(Vector2(p.position.x, y), Vector2(p.end.x, y), Tok.c("grid_major") if absf(g) < 1e-6 else Tok.c("grid"), 1.0)
			draw_string(f, Vector2(CH_W + 2, y + 4), "%d" % int(round(g)), HORIZONTAL_ALIGNMENT_LEFT, PAD_L - 6, 11, Tok.dim(0.7))
			g += step
		var cy := v_to_y(cursor_v)   # the 2D cursor's value line
		if cy > p.position.y and cy < p.end.y:
			draw_dashed_line(Vector2(p.position.x, cy), Vector2(p.end.x, cy), Color(Tok.c("say"), 0.5), 1.0, 4.0)
	var ph := t_to_x(playhead)
	if ph >= p.position.x and ph <= p.end.x:
		draw_line(Vector2(ph, p.position.y), Vector2(ph, p.end.y), Tok.c("say"), 1.5)
	draw_string(f, Vector2(p.position.x, size.y - 5), "%.2f s" % t0, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Tok.dim(0.7))
	draw_string(f, Vector2(p.end.x - 40, size.y - 5), "%.2f s" % t1, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Tok.dim(0.7))
	draw_string(f, Vector2(p.position.x + 50, size.y - 5), "pivot: %s" % ("2D cursor (%.2f s, %.1f)" % [playhead, cursor_v] if pivot_mode == "cursor" else "box centre"), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Tok.dim(0.6))
	if cs.is_empty():
		draw_string(f, Vector2(p.position.x + 20, p.position.y + p.size.y * 0.5), "no part keys in this scene: pick a part and press K to key it", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Tok.dim(0.8))
		return
	for ch in cs:
		if not is_hidden(ch[0], ch[1]):
			draw_polyline(ch_polyline(ch[0], ch[1]), ch_col(ch[0], ch[1]), 2.0, true)
	for j in parts():   # GE5
		_draw_ranges(j, Tok.c("say"))
	if dots:
		for ch in cs:
			if is_hidden(ch[0], ch[1]):
				continue
			var col := ch_col(ch[0], ch[1])
			for i in (scene.part_keys[ch[0]] as Array).size():
				var q := dot_pos(ch[0], ch[1], i)
				var on := is_msel(ch[0], ch[1], i)
				draw_circle(q, 5.5 if on else 4.0, ink if on else col)
				draw_arc(q, 5.5 if on else 4.0, 0.0, TAU, 16, col if on else Tok.c("tl_bg"), 1.5)
	if _gmode == "box":
		draw_rect(_gbox.abs(), Tok.dim(0.15), true)
		draw_rect(_gbox.abs(), Tok.dim(0.6), false, 1.0)


func is_msel(j: String, c: int, i: int) -> bool:
	for q in msel:
		if q[0] == j and q[1] == c and q[2] == i:
			return true
	return false


# ---------------------------------------------------------------- input

## the visible dot under a point -> [joint, c, i] or []
func mpick(at: Vector2) -> Array:
	var best := []
	var bd := HIT
	for ch in chans():
		if is_hidden(ch[0], ch[1]):
			continue
		for i in (scene.part_keys[ch[0]] as Array).size():
			var d := dot_pos(ch[0], ch[1], i).distance_to(at)
			if d <= bd:
				bd = d
				best = [ch[0], ch[1], i]
	return best


## every visible dot inside a rect (local px)
func dots_in(r: Rect2) -> Array:
	var out := []
	for ch in chans():
		if is_hidden(ch[0], ch[1]):
			continue
		for i in (scene.part_keys[ch[0]] as Array).size():
			if r.has_point(dot_pos(ch[0], ch[1], i)):
				out.append([ch[0], ch[1], i])
	return out


func _gui_input(ev: InputEvent) -> void:
	if not multi:
		super._gui_input(ev)
		return
	if scene == null:
		return
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		var mr := ev as InputEventMouseButton
		if plot().has_point(mr.position) and not normalize:
			cursor_v = y_to_v(mr.position.y)   # Blender: Shift+RMB places the 2D cursor; here its value (time = playhead)
			queue_redraw()
			accept_event()
		return
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := ev as InputEventMouseButton
		if mb.pressed:
			if mb.position.x < CH_W and mb.position.y > PAD_T:
				for ch in chans():
					if row_of(ch[0], ch[1]).has_point(mb.position):
						if mb.ctrl_pressed:   # solo
							off_ch = {}
							for o in chans():
								if not (o[0] == ch[0] and o[1] == ch[1]):
									off_ch["%s:%d" % [o[0], o[1]]] = true
							msel = msel.filter(func(q): return q[0] == ch[0] and q[1] == ch[1])
							_refit_multi()
							queue_redraw()
						else:
							set_hidden(ch[0], ch[1], not is_hidden(ch[0], ch[1]))
				accept_event()
				return
			var hit := mpick(mb.position)
			_gpress = mb.position
			_dragging = false
			if not hit.is_empty():
				if mb.shift_pressed:
					if is_msel(hit[0], hit[1], hit[2]):
						msel = msel.filter(func(q): return not (q[0] == hit[0] and q[1] == hit[1] and q[2] == hit[2]))
					else:
						msel.append(hit)
				elif not is_msel(hit[0], hit[1], hit[2]):
					msel = [hit]
				_ghit = hit
				_gmode = "scale" if mb.alt_pressed else "move"
				_gsnap = _snapshot()
				_gpivot = pivot()
			else:
				if not mb.shift_pressed:
					msel = []
				_gmode = "box"
				_gbox = Rect2(mb.position, Vector2.ZERO)
			queue_redraw()
			accept_event()
		else:
			if _gmode == "box" and _gbox.abs().size.length() >= MOVE_MIN:
				for q in dots_in(_gbox.abs()):
					if not is_msel(q[0], q[1], q[2]):
						msel.append(q)
			_gmode = ""
			_dragging = false
			queue_redraw()
	elif ev is InputEventMouseMotion and (ev as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT and _gmode != "":
		var mm := ev as InputEventMouseMotion
		if _gmode == "box":
			_gbox.size = mm.position - _gbox.position
			queue_redraw()
			accept_event()
			return
		if not _dragging and mm.position.distance_to(_gpress) < MOVE_MIN:
			return
		if not _dragging:
			_dragging = true
			if begin.is_valid():
				begin.call()
		if _gmode == "scale":
			_scale_from(_gsnap, 1.0 + (mm.position.x - _gpress.x) / 150.0, 1.0 - (mm.position.y - _gpress.y) / 150.0, _gpivot)
		else:
			_move_from(_gsnap, x_to_t(mm.position.x) - x_to_t(_gpress.x), mm.position.y - _gpress.y)
		accept_event()
	elif ev is InputEventKey and ev.pressed and (ev as InputEventKey).keycode == KEY_ESCAPE and not msel.is_empty():
		msel = []
		queue_redraw()
		accept_event()


# ---------------------------------------------------------------- transforms

func _snapshot() -> Dictionary:
	var out := {}
	for j in parts():
		out[j] = (scene.part_keys[j] as Array).map(func(k): return [float(k["t"]), k["v"]])
	return out


## the selected keys' indices per joint, rising
func sel_keys() -> Dictionary:
	var out := {}
	for q in msel:
		var a: Array = out.get(q[0], [])
		if not a.has(q[2]):
			a.append(q[2])
		out[q[0]] = a
	for j in out:
		(out[j] as Array).sort()
	return out


## the pivot: the 2D cursor (playhead, cursor_v) or the selected dots' bounding box centre (time, value)
func pivot() -> Vector2:
	if pivot_mode == "cursor" or msel.is_empty():
		return Vector2(playhead, cursor_v)
	var lt := INF
	var ht := -INF
	var lv := INF
	var hv := -INF
	for q in msel:
		var t := float(scene.part_keys[q[0]][q[2]]["t"])
		lt = minf(lt, t)
		ht = maxf(ht, t)
		lv = minf(lv, _val(q))
		hv = maxf(hv, _val(q))
	return Vector2((lt + ht) * 0.5, (lv + hv) * 0.5)


## GE2: scale the selected keys about the pivot (default: pivot()), ONE undo step. Time by ft, value by fv; see header
func scale_sel(ft: float, fv: float, pv: Variant = null) -> Dictionary:
	if msel.is_empty() or scene == null:
		last_scale = {"ok": false, "why": "no keys selected", "keys": 0, "clamped": 0}
		return last_scale
	var p: Vector2 = pv if pv is Vector2 else pivot()
	var snap := _snapshot()
	var test := _plan_times(snap, ft, p)
	if not test["ok"]:
		last_scale = {"ok": false, "why": test["why"], "keys": 0, "clamped": 0}
		return last_scale
	if begin.is_valid():
		begin.call()
	return _scale_from(snap, ft, fv, p)


func _plan_times(snap: Dictionary, ft: float, p: Vector2) -> Dictionary:
	var sk := sel_keys()
	var out := {}
	for j in sk:
		var nt := []
		for i in (snap[j] as Array).size():
			nt.append(float(snap[j][i][0]))
		if ft != 1.0:
			for i in sk[j]:
				nt[i] = p.x + ft * (float(snap[j][i][0]) - p.x)
		for i in nt.size():
			if float(nt[i]) < 0.0:
				return {"ok": false, "why": "%s's key %d would go to %.3f s, before the start" % [j, i + 1, nt[i]]}
			if i > 0 and float(nt[i]) - float(nt[i - 1]) < PartKeys.SAME_T * 2.0:
				return {"ok": false, "why": "%s's key %d and key %d would meet or swap" % [j, i, i + 1]}
		out[j] = nt
	return {"ok": true, "times": out}


func _scale_from(snap: Dictionary, ft: float, fv: float, p: Vector2) -> Dictionary:
	var plan := _plan_times(snap, ft, p)
	if not plan["ok"]:   # mid-drag: the last good scale stays
		last_scale = {"ok": false, "why": plan["why"], "keys": 0, "clamped": 0}
		return last_scale
	var clamped := 0
	for j in plan["times"]:
		var ks: Array = scene.part_keys[j]
		for i in ks.size():
			ks[i]["t"] = plan["times"][j][i]
			ks[i]["v"] = snap[j][i][1]
	for q in msel:
		var ks: Array = scene.part_keys[q[0]]
		var nv: Vector3 = ks[q[2]]["v"]
		if fv != 1.0:
			nv[q[1]] = p.y + fv * ((snap[q[0]][q[2]][1] as Vector3)[q[1]] - p.y)
		if limit.is_valid():
			var lv: float = (limit.call(q[0], nv) as Vector3)[q[1]]
			if lv != nv[q[1]]:
				clamped += 1
			nv[q[1]] = lv
		ks[q[2]]["v"] = nv
	last_scale = {"ok": true, "why": "", "keys": msel.size(), "clamped": clamped, "pivot": p}
	queue_redraw()
	if changed.is_valid():
		changed.call()
	return last_scale


## move the selection from the snapshot: dt seconds (the grabbed key lands on a whole frame; cut back so no key reaches an
## unselected neighbour or goes below 0), dy px up / down converted per channel (its own scale in the normalized view)
func _move_from(snap: Dictionary, dt: float, dy: float) -> void:
	var sk := sel_keys()
	var fr := 1.0 / float(maxi(fps, 1))
	if not _ghit.is_empty() and snap.has(_ghit[0]):
		var ta := float(snap[_ghit[0]][_ghit[2]][0])
		dt = snappedf(ta + dt, fr) - ta
	var lo := -INF
	var hi := INF
	var gap := PartKeys.SAME_T * 2.0
	for j in sk:
		var ids: Array = sk[j]
		var n := (snap[j] as Array).size()
		for i in ids:
			lo = maxf(lo, -float(snap[j][i][0]))
			if i > 0 and not ids.has(i - 1):
				lo = maxf(lo, float(snap[j][i - 1][0]) + gap - float(snap[j][i][0]))
			if i < n - 1 and not ids.has(i + 1):
				hi = minf(hi, float(snap[j][i + 1][0]) - gap - float(snap[j][i][0]))
	dt = clampf(dt, lo, hi)
	for j in sk:
		var ks: Array = scene.part_keys[j]
		for i in ks.size():
			ks[i]["t"] = float(snap[j][i][0]) + (dt if (sk[j] as Array).has(i) else 0.0)
			ks[i]["v"] = snap[j][i][1]
	for q in msel:
		var ks: Array = scene.part_keys[q[0]]
		var nv: Vector3 = ks[q[2]]["v"]
		var y0 := ch_to_y(q[0], q[1], (snap[q[0]][q[2]][1] as Vector3)[q[1]])
		nv[q[1]] = y_to_ch(q[0], q[1], y0 + dy)
		if limit.is_valid():
			nv[q[1]] = (limit.call(q[0], nv) as Vector3)[q[1]]
		ks[q[2]]["v"] = nv
	queue_redraw()
	if changed.is_valid():
		changed.call()
