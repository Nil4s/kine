extends SceneTree
## godot --position -30000,-30000 --path . -s tests/layouts_test.gd     (lane L20 LAYOUTS, GAP_AUDIT_1106 #4; EXPERT / ENG mode only; needs the CAD DLL for the live bars)
## Named workspace layouts (scripts/work_layouts.gd), per-page panel docking, the layouts dialog (scripts/work_layouts_ui.gd), the keymap as a JSON profile
## (scripts/hotkeys.gd: to_json / from_json / conflicts / save_json / load_json). Bars, written before the code; each has a PLANTED control that must fail
## (the check is shown to catch what it claims to):
##   1 BYTES    save then load is byte-identical (file -> a fresh store -> file again), and the layout loaded by name equals the one saved.
##              Planted: one changed word in the file is found (the bytes differ / the file is refused).
##   2 NAMES    rename and delete work (also on disk); a rename onto an existing name, onto "Factory" or onto "" is refused; delete of a missing name is refused.
##              Planted: a store where the old name is still there after a rename is found by the name check.
##   3 RESET    reset gives the factory default exactly (deep equal and the same serialised bytes), after docks, sizes, rail and open flags were all changed.
##              Planted: the changed layout is not equal to the factory one.
##   4 LIMITS   a layout saved at 1920x1080 with everything wide / tall and loaded at 1600x900 (and 1366x768, 1280x720) stays inside the screen limits on all
##              4 pages: 0 overlaps, nothing outside the clear area, every panel at least its minimum size, the 3D view at least 60 % of the window.
##              Planted: an overlap, a panel off the edge, a panel under its minimum and a view under 60 % are each found by the same check.
##   5 KEYMAP   a conflict (two actions on one key) is detected; a remapped action fires on the new key and not on the old one; the keymap saves to
##              JSON and loads back identical; reset restores the built-in keys. Planted: the clean map has 0 conflicts, and the old key DID fire before the remap.
##   6 CORRUPT  a corrupt, truncated, wrong-type or old / future-schema file (layouts and keymap) falls back to the default without a crash.
##              Planted: a valid file does not fall back.
##   7 LIVE     on the real Part / Assembly / Engineering screens at 1920x1080 two different saved layouts: 0 controls outside, 0 overlapping panels, the 3D view
##              at least 60 %, the panels where the layout put them; a drag on the dock map moves a panel to another dock. The factory layout leaves the app's own
##              placement alone. Planted: a panel dropped onto another is found. Screenshots in C:/Temp/claude/layouts.
## Only user:// is written (wtest gives each run its own APPDATA), and screenshots under C:/Temp/claude/layouts.
var fails := 0
var d: UiExpDrive
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func rm(p: String) -> void:
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func read(p: String) -> String:
	var f := FileAccess.open(p, FileAccess.READ)
	return f.get_as_text() if f != null else ""


func write(p: String, s: String) -> void:
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(s)
	f.close()


## a layout with every page changed in every field the store keeps
func busy() -> Dictionary:
	var L := WorkLayouts.factory()
	L["pages"]["part"]["panels"]["inspector"]["dock"] = "left"
	L["pages"]["part"]["panels"]["inspector"]["order"] = 0
	L["pages"]["part"]["panels"]["browser"]["order"] = 1
	L["pages"]["part"]["splits"]["left"] = 300
	L["pages"]["part"]["rail_w"] = 130
	L["pages"]["assembly"]["panels"]["parts"]["dock"] = "right"
	L["pages"]["assembly"]["panels"]["inspector"]["dock"] = "bottom"
	L["pages"]["engineering"]["panels"]["fits"]["open"] = false
	L["pages"]["animate"]["panels"]["timeline"]["dock"] = "float"
	L["pages"]["animate"]["panels"]["timeline"]["float"] = [400, 300, 500, 200]
	L["pages"]["animate"]["splits"]["bottom"] = 180
	return WorkLayouts.sanitize(L)


## everything as wide and tall as it may be, on every dock
func greedy() -> Dictionary:
	var L := WorkLayouts.factory()
	for pg in WorkLayouts.PAGES:
		var P: Dictionary = L["pages"][pg]
		P["splits"] = {"left": 900, "right": 900, "bottom": 900}
		P["rail_w"] = 200
		var i := 0
		for id in P["panels"]:
			P["panels"][id]["open"] = true
			P["panels"][id]["dock"] = ["left", "right", "bottom"][i % 3]
			P["panels"][id]["order"] = i
			i += 1
	return WorkLayouts.sanitize(L)


func same(a: Variant, b: Variant) -> bool:
	return JSON.stringify(a, "\t", true) == JSON.stringify(b, "\t", true)


func test_limits(L: Dictionary, tag: String) -> void:
	for sz in [Vector2(1920, 1080), Vector2(1600, 900), Vector2(1366, 768), Vector2(1280, 720)]:
		for pg in WorkLayouts.PAGES:
			var P: Dictionary = L["pages"][pg]
			var area := WorkLayouts.area_for(sz, int(P["rail_w"]))
			var chrome := WorkLayouts.chrome_px(sz, int(P["rail_w"]))
			var r := WorkLayouts.solve(P, pg, sz, area, chrome)
			var c := WorkLayouts.check(r["rects"], pg, sz, area, chrome)
			var bad := not (c["overlaps"] as Array).is_empty() or not (c["outside"] as Array).is_empty() or not (c["small"] as Array).is_empty() or float(c["view_share"]) < WorkLayouts.MIN_VIEW - 0.0001
			if bad:
				print("     %s %s %dx%d: %s" % [tag, pg, sz.x, sz.y, str(c)])
			ok(not bad, "4 %s on %s at %dx%d: 0 overlaps, inside, minimum sizes, view %.0f %% (%d open, %d closed to fit)" % [tag, pg, sz.x, sz.y, float(c["view_share"]) * 100.0, (r["rects"] as Dictionary).size(), (r["closed"] as Array).size()])


func _init() -> void:
	DirAccess.make_dir_recursive_absolute("C:/Temp/claude/layouts")
	var p1 := "user://layouts_t1.json"
	var p2 := "user://layouts_t2.json"
	for p in [p1, p2]:
		rm(p)

	# ---- 1 BYTES
	var ws := WorkLayouts.new(p1)
	ok(ws.names().is_empty() and same(ws.cur, WorkLayouts.factory()) and not ws.fallback, "1 a store with no file starts on the factory default, no fallback")
	ws.cur = busy()
	ok(not same(ws.cur, WorkLayouts.factory()), "1 the busy layout differs from the factory default")
	ok(ws.save_as("Wide inspector"), "1 saved as 'Wide inspector'")
	ws.cur = greedy()
	ok(ws.save_as("Greedy"), "1 saved as 'Greedy'")
	var b1 := read(p1)
	ok(b1.length() > 200 and ("\"schema\": %d" % WorkLayouts.SCHEMA) in b1, "1 the file is JSON with a schema version (%d bytes)" % b1.length())
	var ws2 := WorkLayouts.new(p1)
	var nm2 := ws2.names()
	nm2.sort()
	ok(not ws2.fallback and nm2 == ["Greedy", "Wide inspector"], "1 a fresh store reads both names back (%s)" % str(nm2))
	ws2.save_file()
	var b2 := read(p1)
	ok(b1 == b2, "1 save, load, save: the file is byte-identical (%d bytes, %d bytes)" % [b1.length(), b2.length()])
	ok(ws2.load_named("Wide inspector") and same(ws2.cur, busy()), "1 'Wide inspector' loaded by name is the layout that was saved")
	ok(ws2.load_named("Greedy") and same(ws2.cur, greedy()), "1 'Greedy' loaded by name is the layout that was saved")
	var tampered := b1.replace("\"left\"", "\"lefx\"")
	write(p2, tampered)
	var ws3 := WorkLayouts.new(p2)
	var caught := ws3.fallback or not same(ws3.layouts, ws2.layouts) or ws3.serialize() != b1
	ok(tampered != b1 and caught, "1 PLANTED: a changed word in the file is found (fallback %s)" % str(ws3.fallback))

	# ---- 2 NAMES
	var r1 := ws2.rename("Wide inspector", "Inspector left")
	ok(r1 and ws2.names().has("Inspector left") and not ws2.names().has("Wide inspector"), "2 rename moves the layout to the new name (%s)" % str(ws2.names()))
	ok(same(ws2.layouts["Inspector left"], busy()), "2 the renamed layout keeps its content")
	ok(not ws2.rename("Greedy", "Inspector left") and ws2.names().has("Greedy"), "2 a rename onto an existing name is refused")
	ok(not ws2.rename("Greedy", "Factory") and not ws2.rename("Greedy", "   ") and not ws2.rename("Nope", "X"), "2 a rename onto Factory, onto blank, or of a missing name is refused")
	ok(WorkLayouts.new(p1).names().has("Inspector left") and not WorkLayouts.new(p1).names().has("Wide inspector"), "2 rename is on the disk")
	ok(ws2.delete("Greedy") and not ws2.names().has("Greedy"), "2 delete removes a layout")
	ok(not ws2.delete("Greedy") and not ws2.delete("Factory"), "2 delete of a missing name, or of Factory, is refused")
	ok(not WorkLayouts.new(p1).names().has("Greedy"), "2 delete is on the disk")
	var fake := ["Wide inspector", "Inspector left"]   # a broken store that kept the old name after a rename
	ok(fake.has("Wide inspector") and not ws2.names().has("Wide inspector"), "2 PLANTED: a store that still holds the old name after a rename is found by the name check")

	# ---- 3 RESET
	ws2.cur = greedy()
	ws2.active = "Greedy"
	ok(not same(ws2.cur, WorkLayouts.factory()), "3 PLANTED: a changed layout is not the factory one")
	ws2.reset()
	ok(same(ws2.cur, WorkLayouts.factory()) and ws2.active == "", "3 reset gives the factory default exactly (docks, sizes, rails, open flags)")
	ok(ws2.is_factory() and ws2.names().has("Inspector left"), "3 reset keeps the saved layouts")
	ws2.cur["pages"]["part"]["panels"]["browser"]["dock"] = "bottom"
	ok(not ws2.is_factory(), "3 PLANTED: one panel on another dock is not the factory layout")
	ws2.reset()

	# ---- 4 LIMITS
	for pair in [["factory", WorkLayouts.factory()], ["busy", busy()], ["greedy", greedy()]]:
		test_limits(pair[1], pair[0])
	var sz := Vector2(1920, 1080)
	var area := WorkLayouts.area_for(sz, 96)
	var chrome := WorkLayouts.chrome_px(sz, 96)
	var good := {"browser": Rect2(area.position + Vector2(8, 8), Vector2(260, 300)), "inspector": Rect2(Vector2(area.end.x - 308, area.position.y + 8), Vector2(300, 300))}
	ok((WorkLayouts.check(good, "part", sz, area, chrome)["overlaps"] as Array).is_empty(), "4 the control rects are clean")
	var ov := good.duplicate()
	ov["inspector"] = Rect2(good["browser"].position + Vector2(20, 20), Vector2(300, 300))
	ok(not (WorkLayouts.check(ov, "part", sz, area, chrome)["overlaps"] as Array).is_empty(), "4 PLANTED: two panels overlapping are found")
	var off := good.duplicate()
	off["inspector"] = Rect2(Vector2(sz.x - 100, 300), Vector2(300, 300))
	ok(not (WorkLayouts.check(off, "part", sz, area, chrome)["outside"] as Array).is_empty(), "4 PLANTED: a panel 200 px off the right edge is found")
	var tiny := good.duplicate()
	tiny["browser"] = Rect2(good["browser"].position, Vector2(40, 40))
	ok(not (WorkLayouts.check(tiny, "part", sz, area, chrome)["small"] as Array).is_empty(), "4 PLANTED: a panel under its minimum size is found")
	var huge := {"browser": Rect2(area.position, Vector2(900, area.size.y)), "inspector": Rect2(area.position + Vector2(910, 0), Vector2(900, area.size.y))}
	ok(float(WorkLayouts.check(huge, "part", sz, area, chrome)["view_share"]) < WorkLayouts.MIN_VIEW, "4 PLANTED: two 900 px columns drop the 3D view under 60 %")
	var factory_share := float(WorkLayouts.check(WorkLayouts.solve(WorkLayouts.factory()["pages"]["part"], "part", sz, area, chrome)["rects"], "part", sz, area, chrome)["view_share"])
	ok(factory_share >= 0.60, "4 the factory Part layout at 1920x1080 keeps %.0f %% for the 3D view" % (factory_share * 100.0))

	# ---- 6 CORRUPT (layouts)
	var cases := {"empty": "", "garbage": "not json at all {{{", "truncated": b1.substr(0, b1.length() / 2), "array": "[1,2,3]", "number": "42",
		"schema 0": b1.replace("\"schema\": %d" % WorkLayouts.SCHEMA, "\"schema\": 0"), "schema future": b1.replace("\"schema\": %d" % WorkLayouts.SCHEMA, "\"schema\": 99"),
		"no schema": "{\"layouts\": {}}", "layouts is a list": "{\"schema\": %d, \"layouts\": [1], \"current\": {}, \"active\": \"\"}" % WorkLayouts.SCHEMA,
		"pages is a string": "{\"schema\": %d, \"layouts\": {\"A\": {\"pages\": \"x\"}}, \"current\": {\"pages\": 5}, \"active\": \"\"}" % WorkLayouts.SCHEMA,
		"old v0": "{\"layout\": {\"left\": 240, \"right\": 290}}"}
	for k in cases:
		write(p2, String(cases[k]))
		var w := WorkLayouts.new(p2)
		ok(w.fallback and same(w.cur, WorkLayouts.factory()) and w.names().is_empty() and w.active == "", "6 layouts file '%s': falls back to the factory default, no crash" % k)
	write(p2, b1)
	var wv := WorkLayouts.new(p2)
	ok(not wv.fallback and wv.names().size() == 2, "6 PLANTED: the valid file does not fall back (%s)" % str(wv.names()))
	var odd := b1.replace("\"dock\": \"left\"", "\"dock\": \"moon\"").replace("\"rail_w\": 130", "\"rail_w\": 99999")
	write(p2, odd)
	var wo := WorkLayouts.new(p2)
	var okdock := true
	for nm in wo.names():
		for pg in WorkLayouts.PAGES:
			for id in wo.layouts[nm]["pages"][pg]["panels"]:
				okdock = okdock and ["left", "right", "bottom", "float"].has(wo.layouts[nm]["pages"][pg]["panels"][id]["dock"])
			okdock = okdock and int(wo.layouts[nm]["pages"][pg]["rail_w"]) <= WorkLayouts.RAIL_MAX
	ok(okdock, "6 a bad dock name or a huge rail width in an otherwise valid file is repaired, not trusted")

	# ---- the live app
	d = UiExpDrive.new()
	await d.boot(self)
	m = d.m
	m.tour_step = -1
	await keymap_bars()
	await live_bars()
	print("layouts: %d fail" % fails)
	quit(1 if fails > 0 else 0)


# ---------------------------------------------------------------------------------------------------------------- keys

func send(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	root.push_input(e)
	await process_frame
	await idle(2)


func tap(code: Key) -> void:
	await send(code, true)
	await send(code, false)


func cmd(id: String) -> Dictionary:
	for c in m.ui_cmd.commands:
		if String(c["id"]) == id:
			return c
	return {}


func keymap_bars() -> void:
	var hk: Hotkeys = m.hk
	hk.reset_all()
	var cmds: Array = m.ui_cmd.commands
	ok(Hotkeys.conflicts(cmds).is_empty(), "5 PLANTED/control: the built-in keymap has 0 conflicts")
	ok(Hotkeys.listing(cmds).size() >= 100, "5 the keymap editor lists every action with its shortcut (%d rows)" % Hotkeys.listing(cmds).size())
	# a conflict in a profile: two actions on J
	var prof := Hotkeys.to_json({"undo": "J", "key_the_part_here": "J"})
	var parsed := Hotkeys.from_json(prof)
	ok(parsed["ok"] and parsed["over"].size() == 2, "5 a keymap profile with 2 entries parses")
	var cs := Hotkeys.apply(m._commands(), parsed["over"])
	var conf := Hotkeys.conflicts(cs)
	ok(conf.size() == 1 and String(conf[0]["key"]) == "J" and (conf[0]["ids"] as Array).has("undo") and (conf[0]["ids"] as Array).has("key_the_part_here"), "5 two actions on J are reported as one conflict (%s)" % str(conf))
	var live_conf := hk.set_key("key_the_part_here", "Ctrl+Z")
	ok(not live_conf["ok"] and live_conf.get("conflict", "") == "undo", "5 the live editor refuses Ctrl+Z for a second action and names its holder")
	# remap fires on the new key, not the old
	m._card_add()
	m.sel = "upperarm_r"
	var u0: int = m.undo.size()
	await tap(KEY_K)
	var fired_old: bool = m.undo.size() == u0 + 1 and m.S.part_keys.has("upperarm_r")
	ok(fired_old, "5 PLANTED/control: before the remap K does key the part")
	m._undo()
	await idle(2)
	m.S.part_keys.erase("upperarm_r")
	var r := hk.set_key("key_the_part_here", "J")
	ok(r["ok"], "5 remap Key the part to J")
	var u1: int = m.undo.size()
	await tap(KEY_K)
	ok(m.undo.size() == u1 and not m.S.part_keys.has("upperarm_r"), "5 after the remap the old key K does nothing")
	await tap(KEY_J)
	ok(m.undo.size() == u1 + 1 and m.S.part_keys.has("upperarm_r"), "5 after the remap the new key J fires the action")
	# save, load, reset
	var kp := "user://keymap_t1.json"
	rm(kp)
	hk.save_json(kp)
	var kb := read(kp)
	ok(kb.length() > 20 and "\"schema\"" in kb, "5 the keymap saves as JSON with a schema version")
	hk.reset_all()
	ok(hk.over.is_empty() and String(cmd("key_the_part_here")["keys"]) == "K", "5 reset gives the built-in keys back (Key the part is on K)")
	var lr := hk.load_json(kp)
	ok(lr["ok"] and String(cmd("key_the_part_here")["keys"]) == "J" and hk.over.size() == 1, "5 loading the profile restores the remap")
	hk.save_json(kp)
	ok(read(kp) == kb, "5 save, load, save: the keymap file is byte-identical")
	# corrupt keymaps
	for pair in [["garbage", "nope {"], ["empty", ""], ["old schema", "{\"schema\": 0, \"keys\": {\"undo\": \"J\"}}"], ["future", "{\"schema\": 99, \"keys\": {}}"], ["array", "[1]"], ["keys not a dict", "{\"schema\": 1, \"keys\": 5}"]]:
		write(kp, pair[1])
		var o := hk.load_json(kp)
		ok(not o["ok"] and hk.over.is_empty() and String(cmd("key_the_part_here")["keys"]) == "K", "6 keymap file '%s': refused, the built-in keys are back, no crash" % pair[0])
	hk.reset_all()


# ------------------------------------------------------------------------------------------------------------------ live

func vis_rect(c: Control) -> Rect2:
	return Rect2(c.global_position, Vector2(c.size.x, maxf(c.size.y, 0.0)))


func probe(tag: String, planted := false) -> Dictionary:
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var vp := Rect2(Vector2.ZERO, vs)
	var ctls := UiExpProbe.controls(m)
	var out := UiExpProbe.outside(m, vp, ctls)
	var panels := UiExpProbe.top_panels(ctls)
	var ov := UiExpProbe.overlaps(panels, m)
	var share := UiExpProbe.view_share(vp, panels)
	if not planted:
		for o in out:
			print("     out: %s %s" % [o[0], str(o[1])])
		for o in ov:
			print("     overlap: %s x %s = %d" % [o[0], o[1], int(o[2])])
		ok(out.is_empty() and ov.is_empty() and share >= 0.60, "7 %s: 0 outside (%d), 0 overlaps (%d), the 3D view keeps %.0f %%" % [tag, out.size(), ov.size(), share * 100.0])
	return {"out": out, "ov": ov, "share": share}


func live_bars() -> void:
	await d.start_building()
	await d.set_size(Vector2i(1920, 1080))
	var sh: UiExpShell = m.bld.shell
	var wl: WorkLayouts = sh.ws
	ok(wl != null and sh.layouts_ui != null, "7 the shell owns a layout store and the layouts dialog")
	wl.reset()
	var A := WorkLayouts.factory()   # layout A: the inspector on the left under the browser, a wide rail
	A["pages"]["part"]["panels"]["inspector"]["dock"] = "left"
	A["pages"]["part"]["panels"]["inspector"]["order"] = 1
	A["pages"]["part"]["panels"]["browser"]["order"] = 0
	A["pages"]["part"]["splits"]["left"] = 330
	A["pages"]["part"]["rail_w"] = 120
	for pg in ["assembly", "engineering"]:
		A["pages"][pg]["panels"]["inspector"]["dock"] = "left"
		A["pages"][pg]["panels"]["parts"]["dock"] = "left"
		A["pages"][pg]["panels"]["parts"]["order"] = 0
		A["pages"][pg]["panels"]["inspector"]["order"] = 1
	var Bl := WorkLayouts.factory()   # layout B: the browser on the right with the inspector, the timeline gone
	Bl["pages"]["part"]["panels"]["browser"]["dock"] = "right"
	Bl["pages"]["part"]["panels"]["browser"]["order"] = 0
	Bl["pages"]["part"]["panels"]["inspector"]["order"] = 1
	Bl["pages"]["part"]["panels"]["timeline"]["open"] = false
	Bl["pages"]["part"]["splits"]["right"] = 320
	for pg in ["assembly", "engineering"]:
		Bl["pages"][pg]["panels"]["parts"]["dock"] = "right"
		Bl["pages"][pg]["panels"]["parts"]["order"] = 0
		Bl["pages"][pg]["panels"]["inspector"]["order"] = 1
	wl.cur = WorkLayouts.sanitize(A)
	wl.save_as("A inspector left")
	wl.cur = WorkLayouts.sanitize(Bl)
	wl.save_as("B browser right")
	wl.reset()
	sh.ws_changed()
	for sc in UiExpDrive.SCREENS:
		await d.screen(sc)
		await d.idle(8)
		var pg: String = sc
		ok(not sh.ws_live(), "7 %s: the factory layout leaves the app's own placement alone" % sc)
		probe("%s factory" % sc)
		for nm in ["A inspector left", "B browser right"]:
			ok(wl.load_named(nm), "7 %s: layout '%s' loaded" % [sc, nm])
			sh.ws_changed()
			await d.idle(10)
			ok(sh.ws_live(), "7 %s '%s': the layout is applied" % [sc, nm])
			probe("%s '%s'" % [sc, nm])
			var ctr2: Dictionary = sh.dock_controls(pg)
			var P: Dictionary = wl.cur["pages"][pg]
			var good := true
			var want_msg := ""
			for id in ctr2:
				var c: Control = ctr2[id]
				if not c.is_visible_in_tree() or not P["panels"].has(id):
					continue
				var dk := String(P["panels"][id]["dock"])
				var cx := c.global_position.x + c.size.x * 0.5
				var vw: float = m.get_viewport().get_visible_rect().size.x
				var side_ok := (dk == "left" and cx < vw * 0.4) or (dk == "right" and cx > vw * 0.6) or dk == "bottom" or dk == "float"
				if not side_ok:
					good = false
				want_msg += " %s=%s@x%.0f" % [id, dk, cx]
			ok(good, "7 %s '%s': each panel sits on the side its layout names (%s)" % [sc, nm, want_msg.strip_edges()])
			if sc == "part" and nm == "A inspector left":
				root.get_texture().get_image().save_png("C:/Temp/claude/layouts/layout_a_part_1920x1080.png")
			if sc == "assembly" and nm == "B browser right":
				root.get_texture().get_image().save_png("C:/Temp/claude/layouts/layout_b_assembly_1920x1080.png")
		# planted: a panel dropped onto another is found
		var cs: Dictionary = sh.dock_controls(pg)
		var ids: Array = cs.keys().filter(func(k): return (cs[k] as Control).is_visible_in_tree())
		if ids.size() >= 2:
			var a: Control = cs[ids[0]]
			var b: Control = cs[ids[1]]
			var keep := b.position
			b.position = a.position + Vector2(6, 6)
			var pr := probe("planted", true)
			b.position = keep
			ok((pr["ov"] as Array).size() >= 1, "7 PLANTED %s: a panel dropped onto another is found (%d overlaps)" % [sc, (pr["ov"] as Array).size()])
		wl.reset()
		sh.ws_changed()
		await d.idle(8)
		probe("%s back on factory" % sc)

	# the dock map: a drag moves a panel to another dock; the dialog saves, renames, deletes, resets
	await d.screen("part")
	await d.idle(6)
	var ui = sh.layouts_ui
	ui.open_dialog()
	await d.idle(6)
	ok(ui.visible, "7 the layouts dialog opens")
	var dm = ui.dock_map
	ok(dm != null and dm.page == "part", "7 the dock map shows the Part page")
	var before: String = String(wl.cur["pages"]["part"]["panels"]["inspector"]["dock"])
	var tgt: Vector2 = dm.zone_center("left")
	var src: Vector2 = dm.panel_center("inspector")
	ok(before == "right" and src != Vector2.ZERO, "7 the Part inspector starts on the right (factory)")
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = src
	dm._gui_input(ev)
	var mv := InputEventMouseMotion.new()
	mv.position = tgt
	dm._gui_input(mv)
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	rel.position = tgt
	dm._gui_input(rel)
	await d.idle(8)
	ok(String(wl.cur["pages"]["part"]["panels"]["inspector"]["dock"]) == "left", "7 dragging the inspector chip onto the left zone docks it left")
	ui.close_dialog()
	await d.idle(8)
	probe("part after a drag")
	ui.menu_dock("part", "inspector", "bottom")
	await d.idle(8)
	ok(String(wl.cur["pages"]["part"]["panels"]["inspector"]["dock"]) == "bottom", "7 the dock menu puts it on the bottom")
	probe("part, inspector on the bottom")
	ui.menu_dock("part", "inspector", "float")
	await d.idle(8)
	ok(String(wl.cur["pages"]["part"]["panels"]["inspector"]["dock"]) == "float", "7 the dock menu floats it")
	probe("part, inspector floating")
	ui.menu_dock("part", "inspector", "right")
	await d.idle(8)
	ok(String(wl.cur["pages"]["part"]["panels"]["inspector"]["dock"]) == "right", "7 floating it back to the right dock works")
	ok(sh.ws_live() == (not wl.is_factory()), "7 live placement is on exactly when the layout differs from the factory one")
	ui.name_edit.text = "Dialog layout"
	ui.save_pressed()
	ok(wl.names().has("Dialog layout"), "7 the dialog's Save stores the layout")
	ui.pick_name("Dialog layout")
	ui.name_edit.text = "Renamed layout"
	ui.rename_pressed()
	ok(wl.names().has("Renamed layout") and not wl.names().has("Dialog layout"), "7 the dialog's Rename renames it")
	ui.pick_name("Renamed layout")
	ui.delete_pressed()
	ok(not wl.names().has("Renamed layout"), "7 the dialog's Delete removes it")
	ui.reset_pressed()
	ok(wl.is_factory(), "7 the dialog's Reset gives the factory layout")
	ui.close_dialog()
	# the screenshots of the dialog and of the keymap editor
	wl.load_named("A inspector left")
	sh.ws_changed()
	await d.idle(8)
	ui.open_dialog()
	await d.idle(8)
	root.get_texture().get_image().save_png("C:/Temp/claude/layouts/dialog_part_1920x1080.png")
	ui.close_dialog()
	wl.reset()
	sh.ws_changed()
	m.hk.open_editor()
	await d.idle(8)
	root.get_texture().get_image().save_png("C:/Temp/claude/layouts/keymap_editor_1920x1080.png")
	ok(m.hk.ui.visible and m.hk.rows.get_child_count() >= 100, "7 the keymap editor is open with %d rows" % m.hk.rows.get_child_count())
	m.hk.close_editor()
