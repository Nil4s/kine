extends SceneTree
## godot --position -30000,-30000 --path . -s tests/uiexp_test.gd     (lane L2, docs/UIEXP_DESIGN.md; needs the CAD DLL)
## Bars, written before the first run; each has a PLANTED control that must fail (the probe is shown to catch what it claims to):
##   1 OUTSIDE   0 visible controls outside the viewport, on Part / Assembly / Engineering at 1920x1080, 1600x900, 1366x768, 1280x720.
##               Planted: a panel pushed 50 px off the right edge is found.
##   2 OVERLAP   0 overlapping top-level panels at the same 12 screens. Planted: the rail dropped onto another panel is found.
##   3 REACH     every function the old layout exposed (docs/uiexp/functions_old.json, listed from the 1280x720 ribbon and panel before
##               the rail existed) is reachable at all 4 sizes (a visible button, a rail button, or its group's "more" menu).
##               Planted: one action removed is reported unreachable.
##   4 ICONS     every icon-only button has an icon and a tooltip (rail and more menus included); every icon file exists, is not blank,
##               and no two are the same picture. Planted: a rail button with its tooltip cleared is found.
##   5 WINDOW    UiExpShell.start_rect lies inside the usable screen rect for 6 usable rects (the real one among them) and wanted sizes.
##               Planted: the unclamped rect (the old start) leaves a 1366x728 usable screen.
##   6 VIEW      at 1920x1080 the 3D view keeps at least 60 % of the window on each screen. Planted: a 1920x700 panel drops it under.
##   7 COUNT     the visible interactive controls per screen, now (the "before" numbers are docs/uiexp/audit_before.json).
##   8 LABELS    (L15) at 1920x1080 every rail button shows a label equal to its tool's name, and nothing is clipped (the label's rect lies inside the
##               button, one line); at 1600x900 the rail is icons only. Planted: a truncated label, and a button squeezed under its label, are found.
## Only user:// is written (and screenshots under C:/Temp/claude/uiexp).
const PartCad := preload("res://scripts/kcad.gd")
var fails := 0
var d: UiExpDrive
var m: Node
var old_fns := {}
var counts := {}


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


## the function is reachable in the current layout of this screen
func reach(label: String, kind: String) -> bool:
	var sh: UiExpShell = m.bld.shell
	if sh.active() and sh.proxies.has(label):
		var p: Dictionary = sh.proxies[label]
		if p["rail"] != null:
			return (p["rail"] as Control).is_visible_in_tree()
		var mb := sh.vb.find_child("rail_more_" + String(p["group"]), true, false) as MenuButton
		return mb != null and mb.is_visible_in_tree() and int(p["id"]) < mb.get_popup().item_count
	var src: Button = sh._src_of(label) if sh.kind == kind else _src(label, kind)
	if src == null:
		return false
	if src.is_visible_in_tree():
		return true
	for pair in m.ui_caps.get("BUILD", []):   # the rarer tools: their group's caption menu
		if (pair[1] as Array).has(src) and (pair[0] as Control).is_visible_in_tree():
			return true
	return m._more_tools.has(src) and m.ui_more.is_visible_in_tree()


func _src(label: String, kind: String) -> Button:
	if kind == "part":
		return m.bld.part.finish_btn if label == "Finish sketch" else m.bld.part.tool_btns.get(label, null)
	var nm: String = UiExpShell.ASM_NAMES.get(label, "")
	return m.bld.asm.panel.find_child(nm, true, false) as Button if nm != "" else null


func _init() -> void:
	d = UiExpDrive.new()
	await d.boot(self)
	m = d.m
	if not Part.available():
		print("FAIL: no KineCAD DLL")
		quit(1)
		return
	await d.start_building()
	var f := FileAccess.open("res://docs/uiexp/functions_old.json", FileAccess.READ)
	old_fns = JSON.parse_string(f.get_as_text()) if f != null else {}
	ok(not old_fns.is_empty() and (old_fns.get("part", []) as Array).size() >= 25 and (old_fns.get("asm", []) as Array).size() >= 15, "0 the frozen list of the old layout's functions is loaded (%d on a Part, %d on an Assembly)" % [(old_fns.get("part", []) as Array).size(), (old_fns.get("asm", []) as Array).size()])
	DirAccess.make_dir_recursive_absolute("C:/Temp/claude/uiexp")
	for sc in UiExpDrive.SCREENS:
		await d.screen(sc)
		var kind := "part" if sc == "part" else "asm"
		for sz in UiExpDrive.SIZES:
			await d.set_size(sz)
			await d.idle(6)
			var vs: Vector2 = m.get_viewport().get_visible_rect().size
			var vp := Rect2(Vector2.ZERO, vs)
			var tag := "%s %dx%d" % [sc, sz.x, sz.y]
			ok(vs == Vector2(sz), "%s: layout pinned (viewport %s)" % [tag, str(vs)])
			var ctls := UiExpProbe.controls(m)
			var r := UiExpProbe.report(m, vp)
			counts[tag] = r["interactive"]
			var wide: bool = m.bld.shell.active()
			ok(wide == (sz.x >= 1600 and sz.y >= 900), "%s: the rail is %s" % [tag, "on" if wide else "off (the compact ribbon, as before)"])
			for o in r["outside"]:
				print("     out: %s %s" % [o[0], str(o[1])])
			ok((r["outside"] as Array).is_empty(), "1 %s: 0 controls outside the viewport (%d checked)" % [tag, ctls.size()])
			for o in r["overlaps"]:
				print("     overlap: %s x %s = %d px2" % [o[0], o[1], int(o[2])])
			ok((r["overlaps"] as Array).is_empty(), "2 %s: 0 overlapping top-level panels (%d panels)" % [tag, r["panels"]])
			var missing := []
			for lab in old_fns.get(kind, []):
				if not reach(String(lab), kind):
					missing.append(lab)
			ok(missing.is_empty(), "3 %s: every old function reachable (%d of %d%s)" % [tag, (old_fns.get(kind, []) as Array).size() - missing.size(), (old_fns.get(kind, []) as Array).size(), (", missing " + str(missing)) if not missing.is_empty() else ""])
			for o in r["icon_bad"]:
				print("     icon: %s" % str(o))
			ok((r["icon_bad"] as Array).is_empty(), "4 %s: every icon button has an icon and a tooltip" % tag)
			if sz.x == 1920:
				ok(float(r["view_share"]) >= 0.60, "6 %s: the 3D view keeps %.0f %% of the window" % [tag, float(r["view_share"]) * 100.0])
				get_root().get_texture().get_image().save_png("C:/Temp/claude/uiexp/test_%s_%dx%d.png" % [sc, sz.x, sz.y])
			if sz.x == 1920 or sz.x == 1600:
				await rail_labels(sc, sz)
			if sz.x == 1280:
				get_root().get_texture().get_image().save_png("C:/Temp/claude/uiexp/test_%s_%dx%d.png" % [sc, sz.x, sz.y])
			# PLANTED controls, on the first screen at each size (the probe must catch what it claims to)
			if sc == "assembly":
				await planted(sz, vp, kind)
	await windows_and_icons()
	for k in counts:
		print("COUNT %s interactive %d" % [k, counts[k]])
	ok(true, "7 visible interactive controls reported for %d screen-sizes (before numbers: docs/uiexp/audit_before.json)" % counts.size())
	print("uiexp: %d fail" % fails)
	quit(1 if fails > 0 else 0)


## what is wrong with a labelled rail button b of tool `label` if it were `w` px wide: "" when fine
func lab_bad(b: Button, label: String, w: float) -> String:
	if b.text != label:
		return "text '%s' != '%s'" % [b.text, label]
	if not b.is_visible_in_tree():
		return "not visible"
	var font: Font = b.get_theme_font("font")
	var fs := b.get_theme_font_size("font_size")
	var sb: StyleBox = b.get_theme_stylebox("normal")
	var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var iw := float(b.icon.get_width()) + float(b.get_theme_constant("h_separation")) if b.icon != null else 0.0
	var need := sb.get_margin(SIDE_LEFT) + iw + tw + sb.get_margin(SIDE_RIGHT)
	if need > w + 0.5:
		return "label needs %.0f px, button is %.0f" % [need, w]
	if font.get_height(fs) > b.size.y:
		return "label taller than the button"
	if fs < 11 or fs > 12:
		return "font size %d" % fs
	if "
" in label or b.autowrap_mode != TextServer.AUTOWRAP_OFF:
		return "not one line"
	return ""


func rail_labels(sc: String, sz: Vector2i) -> void:
	var sh: UiExpShell = m.bld.shell
	var tag := "%s %dx%d" % [sc, sz.x, sz.y]
	var n := 0
	var bad := []
	var texted := 0
	for lab in sh.proxies:
		var b: Button = sh.proxies[lab]["rail"]
		if b == null:
			continue
		n += 1
		if sz.x >= 1920:
			var why := lab_bad(b, String(lab), b.size.x)
			if why == "" and not sh.rail.get_global_rect().encloses(b.get_global_rect()):
				why = "outside the rail"
			if why != "":
				bad.append("%s: %s" % [lab, why])
		elif b.text != "":
			texted += 1
	if sz.x >= 1920:
		ok(n >= 8 and bad.is_empty(), "8 %s: all %d rail buttons carry their tool's name inside the button (%s)" % [tag, n, str(bad)])
		var first := ""
		for lab in sh.proxies:
			if sh.proxies[lab]["rail"] != null:
				first = String(lab)
				break
		var fb: Button = sh.proxies[first]["rail"]
		var keep := fb.text
		fb.text = first.left(max(first.length() - 3, 1)) + "."
		var caught_trunc := lab_bad(fb, first, fb.size.x) != ""
		fb.text = keep
		var caught_squeeze := lab_bad(fb, first, 30.0) != ""
		ok(caught_trunc and caught_squeeze, "8 PLANTED %s: a truncated label (%s) and a button squeezed to 30 px are both found" % [tag, str(caught_trunc)])
		get_root().get_texture().get_image().save_png("C:/Temp/claude/uiexp/test_labels_%s_%dx%d.png" % [sc, sz.x, sz.y])
	else:
		ok(n >= 8 and texted == 0, "8 %s: the rail is icons only (%d buttons, %d with text)" % [tag, n, texted])


func planted(sz: Vector2i, vp: Rect2, kind: String) -> void:
	var tag := "%dx%d" % [sz.x, sz.y]
	var panel: Control = m.bld.asm.panel
	var old := panel.position
	panel.position = Vector2(vp.end.x - panel.size.x + 50.0, old.y)
	var out := UiExpProbe.outside(m, vp)
	panel.position = old
	ok(out.size() >= 1, "1 PLANTED %s: a panel pushed 50 px off the right edge is found (%d outside)" % [tag, out.size()])
	var anchor: Control = m.bld.shell.rail if m.bld.shell.rail.is_visible_in_tree() else m.bld.asm.panel
	var other: Control = m.bld.asm.panel if anchor != m.bld.asm.panel else (m.get_node("%d" % 0) if false else null)
	if other == null:
		other = m.ui_page_bar
	var ps := other.position
	other.position = anchor.global_position + Vector2(4, 4)
	var ov := UiExpProbe.overlaps(UiExpProbe.top_panels(UiExpProbe.controls(m)), m)
	other.position = ps
	ok(ov.size() >= 1, "2 PLANTED %s: a panel dropped onto another is found (%d overlaps)" % [tag, ov.size()])
	var labs: Array = (old_fns.get(kind, []) as Array).duplicate()
	var gone := String(labs[0])
	var sh: UiExpShell = m.bld.shell
	var saved: Variant = sh.proxies.get(gone, null)
	var src: Button = sh._src_of(gone) if sh.kind == kind else _src(gone, kind)
	var was_vis := src.visible if src != null else false
	sh.proxies.erase(gone)
	if src != null:
		src.visible = false
	ok(not reach(gone, kind), "3 PLANTED %s: the removed action '%s' is reported unreachable" % [tag, gone])
	if saved != null:
		sh.proxies[gone] = saved
	if src != null:
		src.visible = was_vis
	var tb := Button.new()   # an icon-only button with no icon and no tooltip, as a careless change would add one
	tb.custom_minimum_size = Vector2(30, 30)
	tb.position = Vector2(300, 300)
	m.ui_root.add_child(tb)
	var bad := UiExpProbe.icon_buttons_bad(UiExpProbe.controls(m), m)
	tb.queue_free()
	ok(bad.size() >= 1, "4 PLANTED %s: an icon button with no icon or tooltip is found (%d)" % [tag, bad.size()])
	if sz.x == 1920:
		var big := PanelContainer.new()
		big.size = Vector2(1920, 700)
		big.position = Vector2(0, 200)
		m.ui_root.add_child(big)
		var share := UiExpProbe.view_share(vp, UiExpProbe.top_panels(UiExpProbe.controls(m)))
		big.queue_free()
		ok(share < 0.60, "6 PLANTED: a 1920x700 panel drops the view to %.0f %% (under 60)" % [share * 100.0])


func windows_and_icons() -> void:
	var real := DisplayServer.screen_get_usable_rect(0)
	var cases := [real, Rect2i(0, 0, 1920, 1040), Rect2i(0, 0, 1366, 728), Rect2i(0, 30, 1280, 690), Rect2i(-1920, 0, 1920, 1040), Rect2i(0, 0, 3840, 2100)]
	var deco := Vector2i(16, 39)
	for u in cases:
		for want in [Vector2i(1600, 900), Vector2i(1920, 1080)]:
			for pos in [Vector2i(0, 0), Vector2i(500, 300), Vector2i(u.position.x + u.size.x - 100, u.position.y + u.size.y - 100)]:
				var r := UiExpShell.start_rect(u, pos, want, deco)
				if not u.encloses(r) and not (u.size.x - deco.x < 320 or u.size.y - deco.y < 240):
					ok(false, "5 start rect %s for usable %s want %s pos %s leaves the screen" % [str(r), str(u), str(want), str(pos)])
	var r2 := UiExpShell.start_rect(Rect2i(0, 0, 1366, 728), Vector2i(0, 0), Vector2i(1600, 900), deco)
	ok(Rect2i(0, 0, 1366, 728).encloses(r2) and r2.size.x <= 1366 and r2.size.y <= 728, "5 a 1600x900 start on a 1366x728 usable screen becomes %s (inside)" % str(r2))
	var naive := Rect2i(Vector2i(0, 0), Vector2i(1600, 900) + deco)
	ok(not Rect2i(0, 0, 1366, 728).encloses(naive), "5 PLANTED: the old unclamped start %s leaves a 1366x728 usable screen" % str(naive))
	var real_r := UiExpShell.start_rect(real, Vector2i(100, 100), Vector2i(1600, 900), deco)
	ok(real.encloses(real_r), "5 the real usable rect %s encloses the start rect %s" % [str(real), str(real_r)])
	# icons
	var ids: Array = UiExpIconList.IDS
	var seen := {}
	var blank := []
	var dup := []
	for id in ids:
		var t := UiExpIcons.tex(id, 48)
		if t == null:
			blank.append(id)
			continue
		var img := t.get_image()
		var lit := 0
		for y in img.get_height():
			for x in img.get_width():
				if img.get_pixel(x, y).a > 0.3:
					lit += 1
		if lit < 40:
			blank.append(id)
		var h := hash(img.get_data())
		if seen.has(h):
			dup.append([id, seen[h]])
		seen[h] = id
	ok(ids.size() >= 60 and blank.is_empty() and dup.is_empty(), "4 %d icon files: none blank (%s), none the same picture (%s)" % [ids.size(), str(blank), str(dup)])
	var sh: UiExpShell = m.bld.shell
	var no_icon := []
	for grp in UiExpShell.PART_GROUPS + UiExpShell.ASM_GROUPS:
		for t in grp[2]:
			var lab := String(t[0])
			var iid: String = UiExpShell.ICON_OF.get(lab, UiExpIcons.id_of(lab))
			if not ids.has(iid):
				no_icon.append(lab)
	ok(no_icon.is_empty(), "4 every function on the rail has its own icon file (missing %s)" % str(no_icon))
	var planted_blank := UiExpIcons.tex("no_such_icon", 24)
	ok(planted_blank == null, "4 PLANTED: an id with no file gives no texture")
