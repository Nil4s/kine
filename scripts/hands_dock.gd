class_name HandsDock
## C66: where the hands card (Right hand holds the ..., Both hands / Weapon in hand / Flip blade) goes in the Expert view.
## It is placed on the first free spot of the 3D view: the rect touches no visible Button (the view tool buttons, the shade / light
## menus, the tip's close) and no status / mouse-hint Label, and the body is not under it. A wider card is tried when the narrow one
## finds no spot (wider = fewer button rows = shorter). Nothing is hidden: every button and the full state line stay.

const WIDTHS := [350.0, 335.0, 320.0, 450.0, 560.0, 300.0, 400.0, 380.0, 420.0, 360.0]   # the first six are the plain card, the rest are tried compact (12 px type, tighter rows): the same words in a card 30 px lower
const PLAIN := 6
const STEP := 6.0


## every visible Button and the named labels in `root` that are not inside `card` (global rects clipped to `view`)
static func blockers(root: Node, card: Control, view: Rect2, labels: Array) -> Array:
	var out := []
	var stack := [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CanvasItem and not (n as CanvasItem).visible:
			continue
		if n == card:
			continue
		if (n is MeshInstance3D or n is Skeleton3D) and not PerfDoc.slow:
			continue   # L12: the body's pieces and bones (most of the tree) hold no Button; the equality bar in tests/perf60_test.gd checks the list is the same
		if n is Button:
			var r := (n as Control).get_global_rect()
			if r.intersects(view):
				out.append(r)
		for c in n.get_children():
			stack.append(c)
	for lb in labels:
		if lb != null and is_instance_valid(lb) and (lb as Control).is_visible_in_tree():
			out.append((lb as Control).get_global_rect())
	return out


## the card's size at the width `w`, worked out from the fonts (a container's wrapped height is only known a frame after a width is set)
static func measure(card: Control, hb: Control, w: float, compact: bool) -> Vector2:
	var box := hb.get_parent() as Control
	var pm: Vector2 = card.get_theme_stylebox("panel").get_minimum_size() if card.has_theme_stylebox("panel") else Vector2(20, 20)
	var inner := w - pm.x
	var sep := 2.0 if compact else 4.0
	var h := 0.0
	var n := 0
	for c in box.get_children():
		if c is Label:
			var lb := c as Label
			var fs: int = 12 if compact else lb.get_theme_font_size("font_size")
			h += lb.get_theme_font("font").get_multiline_string_size(lb.text, HORIZONTAL_ALIGNMENT_LEFT, inner, fs).y + sep
			n += 1
	var x := 0.0
	var row_h := 0.0
	var rows := 0
	var hs := 3.0 if compact else 4.0
	for c in hb.get_children():
		var b := c as Button
		if b == null or not b.visible:
			continue
		var fs2: int = 12 if compact else b.get_theme_font_size("font_size")
		var sb := b.get_theme_stylebox("normal").get_minimum_size()
		var bw := b.get_theme_font("font").get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x + sb.x + 4.0
		var bh := b.get_theme_font("font").get_height(fs2) + sb.y
		bh = maxf(bh, 24.0 if compact else 0.0)
		if x > 0.0 and x + hs + bw > inner:
			rows += 1
			x = 0.0
		x += (hs if x > 0.0 else 0.0) + bw
		row_h = maxf(row_h, bh)
	rows += 1
	h += rows * row_h + (rows - 1) * (2.0 if compact else 4.0)
	return Vector2(w, h + pm.y + 10.0)


## L12 PERF60: THE PLACEMENT CACHE. Where the card can go depends on the blockers (visible Buttons and the status labels), the view,
## the card's size at a width, and then the body and the pick points. The first three change only when the layout does, the last two
## every frame of a playback. So, once the same blockers and view have been seen on two calls in a row (a layout that is changing
## every frame is never cached), the blocker-free grid positions of a width are listed once, in scan order, and each call only
## tests those against the body and the points: the first that passes is the answer the full scan gives. A changed signature (the
## view, or the set and rects of the blockers) drops the lists. place_fresh() is the uncached scan (PerfDoc.slow selects it).
static var _sig: Array = []
static var _stable := 0
static var _lists := {}      # "wi|size" -> PackedFloat64Array [x0, y0, x1, y1, ...]: the grid spots no blocker touches, in scan order
static var rebuilds := 0     # tests: how many lists were built
static var cached_calls := 0 # tests: calls answered from the lists
static var recomputes := 0   # tests: how many times the signature changed


## the grid spots of a card of size ps that no blocker touches, in the order the scan visits them
static func free_spots(view: Rect2, blk: Array, ps: Vector2) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var y := view.end.y - ps.y
	while y >= view.position.y - 0.5:
		var row_blk: Array = []
		for b0 in blk:
			if (b0 as Rect2).position.y < y + ps.y and (b0 as Rect2).end.y > y:
				row_blk.append(b0)
		var x := view.end.x - ps.x
		while x >= view.position.x - 0.5:
			var r := Rect2(x, y, ps.x, ps.y)
			var hit := false
			for b in row_blk:
				if r.intersects(b):
					hit = true
					break
			if not hit:
				out.append(x)
				out.append(y)
			x -= STEP
		y -= STEP
	return out


## sets the card's width (via `hb`, the buttons' flow) and its position; returns true when a spot with no overlap was found
static func place(card: Control, hb: Control, view: Rect2, blk: Array, body: Rect2, pts: Array = []) -> bool:
	if PerfDoc.slow:
		return place_fresh(card, hb, view, blk, body, pts)
	var sig := [view, blk]
	if sig == _sig:
		_stable += 1
	else:
		_sig = sig
		_stable = 0
		_lists.clear()
		recomputes += 1
	if _stable < 1:
		return place_fresh(card, hb, view, blk, body, pts)
	cached_calls += 1
	for avoid_body in [true, false]:
		for wi in WIDTHS.size():
			var w: float = WIDTHS[wi]
			var _t0 := PerfDoc.t()
			_compact(card, hb, wi >= PLAIN)
			PerfDoc.add("hd_cm", _t0)
			_t0 = PerfDoc.t()
			var ps := measure(card, hb, w, wi >= PLAIN)
			PerfDoc.add("hd_ms", _t0)
			if ps.x > view.size.x or ps.y > view.size.y:
				continue
			var key := "%d|%s" % [wi, str(ps)]
			if not _lists.has(key):
				_lists[key] = free_spots(view, blk, ps)
				rebuilds += 1
			var spots: PackedFloat64Array = _lists[key]
			var _t1 := PerfDoc.t()
			var hit := first_free(spots, ps, body, avoid_body, pts)
			PerfDoc.add("hd_ff", _t1)
			if hit >= 0:
				_compact(card, hb, wi >= PLAIN)
				hb.custom_minimum_size = Vector2(w - 20.0, 0)
				card.size = ps
				card.position = Vector2(spots[2 * hit], spots[2 * hit + 1])
				return true
	_compact(card, hb, false)
	hb.custom_minimum_size = Vector2(WIDTHS[0] - 20.0, 0)
	card.reset_size()
	return false


## L64: the first spot of the list (index into the pairs) that the body (when avoid) and the pick points do not reject, else -1.
## KineDockNative.first_free is the same loop in C++ (single-precision Rect2 steps); _first_free_gd is the GDScript twin and the reference
## (PerfDoc.refresh_full). The scan of a long list that is all rejected (a body wider than the room) was most of the card's cost.
static var _native := -1   # -1 not asked, 0 no, 1 yes
static var _door = null    # scripts/dock_native.gd once KineDockNative is known to exist
static var native_calls := 0   # tests


static func native_ok() -> bool:
	if _native < 0:
		_native = 1 if NativeExt.ensure("kine_native", "KineDockNative") else 0
		if _native == 1:
			_door = load("res://scripts/dock_native.gd")
	return _native == 1 and _door != null


static func first_free(spots: PackedFloat64Array, ps: Vector2, body: Rect2, avoid: bool, pts: Array) -> int:
	if PerfDoc.refresh_full or not native_ok():
		return _first_free_gd(spots, ps, body, avoid, pts)
	native_calls += 1
	return _door.first_free(spots, ps.x, ps.y, body, avoid, PackedVector2Array(pts), 2.0)


static func _first_free_gd(spots: PackedFloat64Array, ps: Vector2, body: Rect2, avoid: bool, pts: Array) -> int:
	for i in range(0, spots.size(), 2):
		var r := Rect2(spots[i], spots[i + 1], ps.x, ps.y)
		if not (avoid and r.intersects(body)) and not PickDodge.covers(r, pts, 2.0):
			return i / 2
	return -1


## sets the card's width (via `hb`, the buttons' flow) and its position; returns true when a spot with no overlap was found
static func place_fresh(card: Control, hb: Control, view: Rect2, blk: Array, body: Rect2, pts: Array = []) -> bool:
	for avoid_body in [true, false]:
		for wi in WIDTHS.size():
			var w: float = WIDTHS[wi]
			_compact(card, hb, wi >= PLAIN)   # the type size is part of what is measured (and a kept compact card must not skew the plain candidates)
			var ps := measure(card, hb, w, wi >= PLAIN)
			if ps.x > view.size.x or ps.y > view.size.y:
				continue
			var y := view.end.y - ps.y
			while y >= view.position.y - 0.5:
				# L12: only the blockers whose rows overlap this row of candidates can be hit by it (Rect2.intersects needs both axes
				# to overlap, strictly): the same answer from a short list
				var row_blk: Array = blk
				if not PerfDoc.slow:
					row_blk = []
					for b0 in blk:
						if (b0 as Rect2).position.y < y + ps.y and (b0 as Rect2).end.y > y:
							row_blk.append(b0)
				var x := view.end.x - ps.x
				while x >= view.position.x - 0.5:
					var r := Rect2(x, y, ps.x, ps.y)
					var hit := false
					for b in row_blk:
						if r.intersects(b):
							hit = true
							break
					if not hit and not (avoid_body and r.intersects(body)) and not PickDodge.covers(r, pts, 2.0):
						_compact(card, hb, wi >= PLAIN)
						hb.custom_minimum_size = Vector2(w - 20.0, 0)
						card.size = ps   # the flow wraps to this width on the next layout; reset_size would keep the old wrapped height
						card.position = Vector2(x, y)
						return true
					x -= STEP
				y -= STEP
	_compact(card, hb, false)
	hb.custom_minimum_size = Vector2(WIDTHS[0] - 20.0, 0)
	card.reset_size()
	return false


## compact: 12 px type on the buttons and the state line, 2 px between rows (the same words, a smaller card)
static func _compact(card: Control, hb: Control, on: bool) -> void:
	var box := hb.get_parent() as Control
	# L64: the overrides are the same for the same `on` (and the same children): setting them again changes nothing but costs a theme
	# notification per control (about 25 controls, up to 20 calls per placement). PerfDoc.refresh_full = the old, always-set path.
	var csig: Array = [on, hb.get_child_count(), box.get_child_count() if box != null else 0]
	if not PerfDoc.refresh_full and hb.has_meta("_dock_cs") and hb.get_meta("_dock_cs") == csig:
		return
	hb.set_meta("_dock_cs", csig)
	hb.add_theme_constant_override("h_separation", 3 if on else 4)
	hb.add_theme_constant_override("v_separation", 2 if on else 4)
	if box != null:
		box.add_theme_constant_override("separation", 2 if on else 4)
	var items: Array = hb.get_children()
	for c in box.get_children():
		if c is Label:
			items.append(c)
	for c in items:
		if on:
			(c as Control).add_theme_font_size_override("font_size", 12)
		elif c is Label:
			(c as Control).add_theme_font_size_override("font_size", 15)
		else:
			(c as Control).remove_theme_font_size_override("font_size")
		if c is Button:
			(c as Control).custom_minimum_size = Vector2(0, 24 if on else 0)


## the screen points the card must not cover: the pick point of every part (PickDodge) and both ends of every bone (C62)
static func points(m: Node) -> Array:
	var out: Array = PickDodge.points(m)
	for j in m.B.P.keys():
		var c: Array = m.B.cap(j)
		for k in 2:
			var w: Vector3 = c[k]
			if not m.cam.is_position_behind(w):
				out.append(m.cam.unproject_position(w))
	return out


## the card where it is now: inside the view, touching no blocker and covering no point
static func clear(card: Control, blk: Array, pts: Array, view: Rect2) -> bool:
	var r := card.get_global_rect()
	if not view.encloses(r):
		return false
	for b in blk:
		if r.intersects(b):
			return false
	return not PickDodge.covers(r, pts, 2.0)
