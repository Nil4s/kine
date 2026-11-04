class_name HandsDock
## C66: where the hands card (Right hand holds the ..., Both hands / Weapon in hand / Flip blade) goes in the Expert view.
## It is placed on the first free spot of the 3D view: the rect touches no visible Button (the view tool buttons, the shade / light
## menus, the tip's close) and no status / mouse-hint Label, and the body is not under it. A wider card is tried when the narrow one
## finds no spot (wider = fewer button rows = shorter). Nothing is hidden: every button and the full state line stay.

const WIDTHS := [350.0, 335.0, 320.0, 450.0, 560.0, 300.0]   # plain widths, widest-looking first; the wider ones wrap to fewer rows
const PLAIN := 99   # entries from this index on would be tried compact (12 px type): none now, the plain card fits a free corner
const STEP := 10.0


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
	return Vector2(w, h + pm.y + 8.0)


## sets the card's width (via `hb`, the buttons' flow) and its position; returns true when a spot with no overlap was found
static func place(card: Control, hb: Control, view: Rect2, blk: Array, body: Rect2, pts: Array = []) -> bool:
	for avoid_body in [true, false]:
		for wi in WIDTHS.size():
			var w: float = WIDTHS[wi]
			var ps := measure(card, hb, w, wi >= PLAIN)
			if ps.x > view.size.x or ps.y > view.size.y:
				continue
			var y := view.end.y - ps.y
			while y >= view.position.y - 0.5:
				var x := view.end.x - ps.x
				while x >= view.position.x - 0.5:
					var r := Rect2(x, y, ps.x, ps.y)
					var hit := false
					for b in blk:
						if r.intersects(b):
							hit = true
							break
					if not hit and not (avoid_body and r.intersects(body)) and not PickDodge.covers(r, pts, 8.0):
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
