class_name UiExpProbe
extends RefCounted
## UIEXP PROBE (lane L2, docs/UIEXP_AUDIT.md): pure measurements over a live UI tree, shared by tools/uiexp_audit.gd and
## tests/uiexp_test.gd. Nothing here changes the tree. Rects are in the viewport's own (content-scaled) pixels.

const TOL := 1.0
const MIN_PANEL := Vector2(48, 28)   # a top-level panel is at least this big; smaller boxes are chips, not panels


static func interactive(c: Control) -> bool:
	return c is BaseButton or c is LineEdit or c is TextEdit or c is Slider or c is SpinBox or c is OptionButton or c is MenuButton


static func shown(c: Control) -> bool:
	return c.is_visible_in_tree() and c.get_global_rect().size.x > 0.5 and c.get_global_rect().size.y > 0.5


## every shown Control (not inside a popup Window; a ScrollContainer's content is clipped, so only the scroller itself counts)
static func controls(n: Node, out: Array = []) -> Array:
	for c in n.get_children():
		if c is Window:
			continue
		if c is Control:
			var ctl := c as Control
			if not ctl.is_visible_in_tree():
				continue
			if shown(ctl):
				out.append(ctl)
			if not (ctl is ScrollContainer):
				controls(ctl, out)
		elif c is CanvasLayer or (c is CanvasItem and (c as CanvasItem).visible):
			controls(c, out)
		elif not (c is CanvasItem) and not (c is Node3D):
			controls(c, out)
	return out


static func inside(r: Rect2, vp: Rect2) -> bool:
	return r.position.x >= vp.position.x - TOL and r.position.y >= vp.position.y - TOL and r.end.x <= vp.end.x + TOL and r.end.y <= vp.end.y + TOL


## [path, rect] of every shown control whose rect leaves the viewport
static func outside(root_node: Node, vp: Rect2, ctls: Array = []) -> Array:
	var out := []
	if ctls.is_empty():
		ctls = controls(root_node)
	for c in ctls:
		var r: Rect2 = (c as Control).get_global_rect()
		if not inside(r, vp):
			out.append([str(root_node.get_path_to(c)), r])
	return out


static func count_interactive(ctls: Array) -> int:
	var n := 0
	for c in ctls:
		if interactive(c):
			n += 1
	return n


## the OUTERMOST shown PanelContainers (none inside another): the side panels, the timeline, the ribbon bar, the dialogs
static func top_panels(ctls: Array) -> Array:
	var ps := []
	for c in ctls:
		if c is PanelContainer and (c as Control).get_global_rect().size.x >= MIN_PANEL.x and (c as Control).get_global_rect().size.y >= MIN_PANEL.y:
			ps.append(c)
	var out := []
	for p in ps:
		var nested := false
		var a: Node = p.get_parent()
		while a != null:
			if a is PanelContainer and ps.has(a):
				nested = true
				break
			a = a.get_parent()
		if not nested:
			out.append(p)
	return out


## [[nameA, nameB, overlap area px]] over every pair of top-level panels (an overlap under 4 px2 is a shared edge, not an overlap)
static func overlaps(panels: Array, root_node: Node) -> Array:
	var out := []
	for i in panels.size():
		for j in range(i + 1, panels.size()):
			var a: Rect2 = (panels[i] as Control).get_global_rect()
			var b: Rect2 = (panels[j] as Control).get_global_rect()
			var x := a.intersection(b)
			if x.get_area() >= 4.0:
				out.append([str(root_node.get_path_to(panels[i])), str(root_node.get_path_to(panels[j])), x.get_area()])
	return out


static func _text_of(c: Control) -> String:
	if c is Label:
		return (c as Label).text
	if c is Button:
		return (c as Button).text
	return ""


## text whose drawn width is wider than the room its control gives it (clip_text / ellipsis / a squeezed manual rect)
static func clipped(ctls: Array, root_node: Node) -> Array:
	var out := []
	for c in ctls:
		var t := _text_of(c)
		if t == "" or t.contains("\n"):
			continue
		var wraps: bool = (c is Label and (c as Label).autowrap_mode != TextServer.AUTOWRAP_OFF) or (c is Button and (c as Button).autowrap_mode != TextServer.AUTOWRAP_OFF)
		if wraps:
			continue
		var f: Font = c.get_theme_font("font")
		var fs: int = c.get_theme_font_size("font_size")
		var w: float = f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pad := 0.0
		if c is Button:
			var sb: StyleBox = c.get_theme_stylebox("normal")
			pad = (sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT)) if sb != null else 0.0
			if (c as Button).icon != null:
				pad += 4.0
		if w + pad > (c as Control).size.x + 2.0 and (c as Control).size.x > 0.0:
			out.append([str(root_node.get_path_to(c)), t.left(40), w + pad, (c as Control).size.x])
	return out


static func small_fonts(ctls: Array, root_node: Node, min_px := 12) -> Array:
	var out := []
	for c in ctls:
		if _text_of(c) == "":
			continue
		if c.get_theme_font_size("font_size") < min_px:
			out.append([str(root_node.get_path_to(c)), _text_of(c).left(24), c.get_theme_font_size("font_size")])
	return out


## icon-only buttons (no text) that lack an icon or a tooltip
static func icon_buttons_bad(ctls: Array, root_node: Node) -> Array:
	var out := []
	for c in ctls:
		if c is Button and not (c is OptionButton) and not (c is CheckBox) and not (c is CheckButton):
			var b := c as Button
			if b.text.strip_edges() == "" and (b.icon == null or b.tooltip_text.strip_edges() == ""):
				out.append([str(root_node.get_path_to(b)), b.icon != null, b.tooltip_text.left(20)])
	return out


## the share of the window the 3D view keeps: the window minus the area covered by the given panels (union, on a 4 px grid)
static func view_share(vp: Rect2, panels: Array) -> float:
	var cell := 4.0
	var nx := int(vp.size.x / cell)
	var ny := int(vp.size.y / cell)
	var free := 0
	var rects := []
	for p in panels:
		rects.append((p as Control).get_global_rect())
	for iy in ny:
		for ix in nx:
			var pt := Vector2((ix + 0.5) * cell, (iy + 0.5) * cell)
			var hit := false
			for r in rects:
				if (r as Rect2).has_point(pt):
					hit = true
					break
			if not hit:
				free += 1
	return float(free) / float(maxi(1, nx * ny))


## the whole report of one screen at one size
static func report(root_node: Node, vp: Rect2) -> Dictionary:
	var ctls := controls(root_node)
	var panels := top_panels(ctls)
	return {"controls": ctls.size(), "interactive": count_interactive(ctls), "outside": outside(root_node, vp, ctls), "panels": panels.size(),
		"overlaps": overlaps(panels, root_node), "clipped": clipped(ctls, root_node), "small_fonts": small_fonts(ctls, root_node),
		"icon_bad": icon_buttons_bad(ctls, root_node), "view_share": view_share(vp, panels)}
