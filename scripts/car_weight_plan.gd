class_name CarWeightPlan
extends Control
## VEHICLE, STEP 4 WEIGHT AND BALANCE, the drawings: the placeable parts as labelled blocks over the side view and the top view of the
## package (the same scale and panels as CarPlan), the centre of gravity (a red cross with its height), and the axle loads as arrows at the
## tyres with their kg. Drag a block with the mouse on either view: on the side view it moves along the length and the height, on the top
## view along the length and across. Releasing the mouse emits moved(id, place) once (the screen makes one undo step of it). Drawing only
## otherwise; the numbers are CarWeight's. Set the data with set_data, then queue_redraw runs by itself.

signal moved(id: String, place: Vector3)

const PANEL_BG := Color(0.09, 0.1, 0.13, 0.0)
const ARROW := Color(1.0, 0.85, 0.3)
const LINE := Color(0.75, 0.85, 0.95)
const SNAP_PX := 3.0          # px the mouse must move before a press counts as a drag
const LABEL_SZ := 12

var p := {}
var c := {}
var susp := {}
var w := {}
var side_r := Rect2()
var top_r := Rect2()
var mm_px := 0.0
var blocks := []              # the placed blocks: {id, view, rect (px), place (Vector3 mm)} of the last draw, for the tests and the hits
var labels := []              # the placed text rects (px), for the tests
var s := {}                   # the readouts drawn (CarWeight.analyse)
var drag_id := ""
var drag_view := -1
var drag_from := Vector2.ZERO
var drag_start := Vector3.ZERO
var drag_now := Vector3.ZERO
var dragging := false
var under: CarPlan = null     # the package drawing under this one (its outlines and labels are kept off)


func set_data(p_: Dictionary, c_: Dictionary, susp_: Dictionary, w_: Dictionary) -> void:
	p = p_.duplicate(true)
	c = c_.duplicate(true)
	susp = susp_.duplicate(true)
	w = w_.duplicate(true)
	if not p.is_empty():
		s = CarWeight.summary(p, c, susp, w)
	queue_redraw()


## the px of a mm point on the side view (x = lon, z = height) and on the top view (x = lon, y = lateral)
func _side_px(x_mm: float, z_mm: float) -> Vector2:
	var foh := float(p["front_oh"])
	return Vector2(side_r.position.x + CarPlan.LM + (foh + x_mm) * mm_px, side_r.position.y + side_r.size.y - 40.0 - z_mm * mm_px)


func _top_px(x_mm: float, y_mm: float) -> Vector2:
	var foh := float(p["front_oh"])
	var cy := top_r.position.y + top_r.size.y * 0.5
	return Vector2(top_r.position.x + CarPlan.LM + (foh + x_mm) * mm_px, cy + y_mm * mm_px)


## the view (0 side, 1 top) under a point, -1 when none
func view_at(pt: Vector2) -> int:
	if side_r.has_point(pt):
		return 0
	if top_r.has_point(pt):
		return 1
	return -1


## the block under a point in a view ("" when none); the passengers and the wheels are not dragged
func block_at(view: int, pt: Vector2) -> String:
	for b in blocks:
		if int(b["view"]) == view and bool(b["drag"]) and (b["rect"] as Rect2).has_point(pt):
			return String(b["id"])
	return ""


func _gui_input(ev: InputEvent) -> void:
	if p.is_empty():
		return
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := ev as InputEventMouseButton
		if mb.pressed:
			var v := view_at(mb.position)
			var id := block_at(v, mb.position) if v >= 0 else ""
			if id != "":
				drag_id = id
				drag_view = v
				drag_from = mb.position
				drag_start = _place_of(id)
				drag_now = drag_start
				dragging = false
				accept_event()
		elif drag_id != "":
			var moved_far := dragging
			if moved_far:
				emit_signal("moved", drag_id, drag_now)
			drag_id = ""
			drag_view = -1
			dragging = false
			queue_redraw()
			accept_event()
	elif ev is InputEventMouseMotion and drag_id != "":
		var mm := ev as InputEventMouseMotion
		if not dragging and mm.position.distance_to(drag_from) >= SNAP_PX:
			dragging = true
		if dragging:
			var dx := (mm.position.x - drag_from.x) / mm_px
			var dy := (mm.position.y - drag_from.y) / mm_px
			if drag_view == 0:
				drag_now = CarWeight.clamp_pos(p, Vector3(drag_start.x + dx, drag_start.y, drag_start.z - dy))
			else:
				drag_now = CarWeight.clamp_pos(p, Vector3(drag_start.x + dx, drag_start.y + dy, drag_start.z))
			queue_redraw()
		accept_event()


## a block's place (mm): the drag's preview while dragging it, else its stored or default place
func _place_of(id: String) -> Vector3:
	var it := _item(id)
	return Vector3(float(it.get("x", 0.0)), float(it.get("y", 0.0)), float(it.get("z", 0.0)))


func _item(id: String) -> Dictionary:
	for it in CarWeight.items(p, c, susp, w):
		if String(it["id"]) == id:
			return it
	return {}


func _draw() -> void:
	blocks = []
	labels = []
	if p.is_empty():
		return
	var lay := CarPlan.layout(CarPackage.derive(p), size.x, size.y)
	side_r = lay["side_r"]
	top_r = lay["top_r"]
	mm_px = float(lay["s"])
	var list := CarWeight.items(p, c, susp, w)
	var res := CarWeight.analyse(list, p)
	s = res
	var dd := CarPackage.derive(p)
	var L := float(dd["length"])
	var H := float(dd["height"])
	var y0 := side_r.position.y + side_r.size.y - 40.0      # the package drawing's ground line
	# what the labels keep off, per panel: the package drawing's outlines and labels (the same panels), the blocks, the axle arrows,
	# the CG cross, and the leaders already drawn
	var obs_lines := [[], []]
	var obs_rects := [[], []]
	if under != null:
		for pi in 2:
			for pl in under.outline[pi]:
				obs_lines[pi].append(pl)
			for l in under.labels:
				if int(l["panel"]) == pi:
					obs_rects[pi].append(l["rect"])
	var parts := []
	for it in list:
		if String(it["kind"]) != "part":
			continue   # the chassis, the links and the wheels are drawn by CarPlan / CarChassis, not here
		var id := String(it["id"])
		var pos := Vector3(float(it["x"]), float(it["y"]), float(it["z"]))
		if id == drag_id and dragging:
			pos = drag_now
		var col: Color = CarWeight.COL.get(id.split("_")[0], Color.WHITE)
		var nm := "%s %d kg" % [String(it["name"]), int(round(float(it["kg"])))]
		# side view: the block's length along x, its height along z
		var bw := float(it["w"]) * mm_px
		var bh := float(it["h"]) * mm_px
		var sc := _side_px(pos.x, pos.z)
		var sr := Rect2(sc - Vector2(bw, bh) * 0.5, Vector2(maxf(bw, 6.0), maxf(bh, 6.0)))
		var tc := _top_px(pos.x, pos.y)
		var tr := Rect2(tc - Vector2(bw, CarWeight.BLOCK_ACROSS * mm_px) * 0.5, Vector2(maxf(bw, 6.0), maxf(CarWeight.BLOCK_ACROSS * mm_px, 6.0)))
		var drag := bool(it["placeable"])
		draw_rect(sr, Color(col.r, col.g, col.b, 0.55), true)
		draw_rect(sr, col, false, 1.5)
		draw_rect(tr, Color(col.r, col.g, col.b, 0.55), true)
		draw_rect(tr, col, false, 1.5)
		blocks.append({"id": id, "view": 0, "rect": sr, "place": pos, "drag": drag})
		blocks.append({"id": id, "view": 1, "rect": tr, "place": pos, "drag": drag})
		obs_rects[0].append(sr)
		obs_rects[1].append(tr)
		parts.append({"nm": nm, "col": col, "sr": sr})
	# the axle loads: arrows up into the body at each axle's tyre contact (length by the share of the total)
	var tot := maxf(float(res["total"]), 1.0)
	var wb := float(p["wheelbase"])
	var fx := float(res["front"]) / tot
	var rx := float(res["rear"]) / tot
	var f := ThemeDB.fallback_font
	for ax in [[0.0, fx, float(res["front"]), 1.0], [wb, rx, float(res["rear"]), -1.0]]:
		var base := _side_px(float(ax[0]), 0.0)
		var ln := 40.0 + 160.0 * float(ax[1])
		draw_line(base + Vector2(0, 24.0), base + Vector2(0, 24.0 - ln), ARROW, 2.0)
		draw_colored_polygon(PackedVector2Array([base + Vector2(0, 24.0 - ln), base + Vector2(-5, 30.0 - ln), base + Vector2(5, 30.0 - ln)]), ARROW)
		obs_lines[0].append(PackedVector2Array([base + Vector2(0, 24.0), base + Vector2(0, 24.0 - ln)]))
		var kt := "%d kg" % int(round(float(ax[2])))
		var kw := f.get_string_size(kt, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SZ).x
		var kr := Rect2(base + Vector2(6.0 if float(ax[3]) > 0.0 else -6.0 - kw, 20.0), Vector2(kw, f.get_height(LABEL_SZ)))
		obs_rects[0].append(kr)
		_put(0, kt, kr, ARROW, true)
	# the centre of gravity: a red cross in each view
	var cg_s := _side_px(float(res["cg_x"]), float(res["cg_z"]))
	var cg_t := _top_px(float(res["cg_x"]), float(res["cg_y"]))
	for q in [cg_s, cg_t]:
		draw_line(q + Vector2(-7, 0), q + Vector2(7, 0), CarWeight.CG_COL, 2.0)
		draw_line(q + Vector2(0, -7), q + Vector2(0, 7), CarWeight.CG_COL, 2.0)
	obs_rects[0].append(Rect2(cg_s - Vector2(8, 8), Vector2(16, 16)))
	obs_rects[1].append(Rect2(cg_t - Vector2(8, 8), Vector2(16, 16)))
	# the labels, each outside the car: side view above the roof line or below the ground line; top view left or right of the body
	var roof := y0 - H * mm_px
	var above := Rect2(side_r.position.x, side_r.position.y, side_r.size.x, roof - 2.0 - side_r.position.y)
	var below := Rect2(side_r.position.x, y0 + 2.0, side_r.size.x, side_r.end.y - y0 - 2.0)
	var bx0 := top_r.position.x + CarPlan.LM
	var bx1 := bx0 + L * mm_px
	var left := Rect2(top_r.position.x, top_r.position.y, bx0 - 2.0 - top_r.position.x, top_r.size.y)
	var right := Rect2(bx1 + 2.0, top_r.position.y, top_r.end.x - bx1 - 2.0, top_r.size.y)
	for pt in parts:
		var col: Color = pt["col"]
		var sr: Rect2 = pt["sr"]
		_place(0, [above, below], sr.get_center(), String(pt["nm"]), col.lightened(0.45), obs_lines[0], obs_rects[0], sr)
	var cgc := CarWeight.CG_COL.lightened(0.45)
	var cgs := Rect2(cg_s - Vector2(8, 8), Vector2(16, 16))
	_place(0, [above, below], cg_s, "CG %d mm high" % int(round(float(res["cg_z"]))), cgc, obs_lines[0], obs_rects[0], cgs)
	var cgt := Rect2(cg_t - Vector2(8, 8), Vector2(16, 16))
	_place(1, [left, right], cg_t, "CG %d mm back from the front axle" % int(round(float(res["cg_x"]))), cgc, obs_lines[1], obs_rects[1], cgt)


## the text at a rect's top-left, recorded as a label (the tests read them)
func _put(pi: int, t: String, r: Rect2, col: Color, fits: bool) -> void:
	var f := ThemeDB.fallback_font
	draw_string(f, Vector2(r.position.x, r.position.y + f.get_ascent(LABEL_SZ)), t, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SZ, col)
	labels.append({"rect": r, "panel": pi, "text": t, "fits": fits})


## the label's placer (the rules of CarPlan's): the first spot nearest its block, inside one of its zones and its panel, touching no
## outline, no block (but its own), no other label and no leader; its leader (a thin line from the label to the block) is kept
func _place(pi: int, zones: Array, anchor: Vector2, t: String, col: Color, obs_lines: Array, obs_rects: Array, own: Rect2) -> void:
	var f := ThemeDB.fallback_font
	var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SZ).x
	var th := f.get_height(LABEL_SZ)
	var cands := []
	for z in zones:
		var zr: Rect2 = z
		var x := zr.position.x
		while x + tw <= zr.end.x:
			var y := zr.position.y
			while y + th <= zr.end.y:
				cands.append(Rect2(x, y, tw, th))
				y += 3.0
			x += 6.0
	cands.sort_custom(func(a: Rect2, b: Rect2) -> bool: return a.get_center().distance_squared_to(anchor) < b.get_center().distance_squared_to(anchor))
	var panel: Rect2 = side_r if pi == 0 else top_r
	var pick := Rect2(anchor, Vector2(tw, th))
	var lead := anchor
	var found := false
	for cnd in cands:
		var r: Rect2 = cnd
		var ld := Vector2(clampf(anchor.x, r.position.x, r.end.x), clampf(anchor.y, r.position.y, r.end.y))
		if _free(pi, r, ld, anchor, own, panel, obs_lines, obs_rects):
			pick = r
			lead = ld
			found = true
			break
	draw_line(lead, anchor, Color(col.r, col.g, col.b, 0.8), 1.0)
	obs_lines.append(PackedVector2Array([lead, anchor]))
	_put(pi, t, pick, col, found)


func _free(pi: int, r: Rect2, ld: Vector2, anchor: Vector2, own: Rect2, panel: Rect2, obs_lines: Array, obs_rects: Array) -> bool:
	if not panel.grow(-2.0).encloses(r):
		return false
	for ob in obs_rects:
		if (ob as Rect2).grow(2.0).intersects(r):
			return false
	for pl in obs_lines:
		if CarPlan.line_hits(r.grow(1.0), pl):
			return false
	for l in labels:
		if int(l["panel"]) == pi and (l["rect"] as Rect2).grow(2.0).intersects(r):
			return false
		if int(l["panel"]) == pi and CarPlan.seg_hits_rect(ld, anchor, (l["rect"] as Rect2).grow(1.0)):
			return false
	return true
