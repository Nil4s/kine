extends SceneTree
## godot --headless --path . -s tests/pagehot_test.gd   (lane L107: P06 per-page hotkeys, P07 per-page workspaces, P18 learn-from-me hotkeys)
## Bars written BEFORE the code (scripts/page_keys.gd, scripts/page_spaces.gd, scripts/cmd_learn.gd). Each has a planted control.
##   SCOPE  "J" bound to cmd_x globally and to cmd_y on sculpt: resolve(J, sculpt) = cmd_y, resolve(J, animate) = cmd_x, resolve(J, model) = cmd_x.
##          A second command on the same key AND same scope is refused with {conflict}, the old binding stays (not silently overwritten);
##          the same key on another scope is not a conflict; confirm=true moves it. Planted: with the sculpt binding removed, sculpt resolves to cmd_x.
##   SAVE   to_json -> from_json -> to_json is byte-identical (also through a file in user://). An old schema-1 file {"schema":1,"keys":{cmd:key}}
##          loads with every binding global and resolves on every page exactly as before. Planted: a changed word in the file is found.
##   SPACE  model layout changed (browser docked right, timeline closed), leave model, enter animate (own layout), a reset in between (factory),
##          enter model again: every panel rect equals the one before leaving within 1 px, and the open flags match. Planted: without the
##          store, the rects after the reset differ from the model layout by more than 1 px for at least one panel. Saved file reloads to the same rects.
##   LEARN  C runs 10 times and 5 others once: suggestions = [C] first; C's suggested key is free (bound to nothing, globally or on any page).
##          dismiss(C): it never comes back, also after save + reload into a new object and after 100 more runs. A command that already has a key
##          (run 20 times) is never suggested. Planted: before the dismiss, C IS suggested; the keyed command has the most runs.
## Only user:// is written (wtest gives each run its own APPDATA).

var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func rm(p: String) -> void:
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _initialize() -> void:
	scope_bars()
	save_bars()
	space_bars()
	learn_bars()
	print("pagehot: %d fail" % fails)
	quit(1 if fails > 0 else 0)


func scope_bars() -> void:
	var k := PageKeys.new()
	ok(k.bind("J", "cmd_x")["ok"], "SCOPE bind J global -> cmd_x")
	ok(k.bind("J", "cmd_y", "sculpt")["ok"], "SCOPE bind J on sculpt -> cmd_y (another scope: no conflict)")
	ok(k.resolve("J", "sculpt") == "cmd_y", "SCOPE sculpt fires cmd_y (got %s)" % k.resolve("J", "sculpt"))
	ok(k.resolve("J", "animate") == "cmd_x", "SCOPE animate fires cmd_x (got %s)" % k.resolve("J", "animate"))
	ok(k.resolve("J", "model") == "cmd_x", "SCOPE model fires cmd_x (global)")
	ok(k.resolve("Q", "model") == "", "SCOPE an unbound key resolves to nothing")
	var r := k.bind("J", "cmd_z", "sculpt")
	ok(not r["ok"] and r.get("conflict", "") == "cmd_y", "SCOPE same key + same scope is reported (conflict=%s)" % r.get("conflict", "none"))
	ok(k.resolve("J", "sculpt") == "cmd_y", "SCOPE the refused bind did not overwrite")
	var r2 := k.bind("J", "cmd_w")
	ok(not r2["ok"] and r2.get("conflict", "") == "cmd_x", "SCOPE global conflict is reported too")
	ok(k.bind("J", "cmd_z", "sculpt", true)["ok"] and k.resolve("J", "sculpt") == "cmd_z", "SCOPE confirm=true moves the key")
	ok(k.conflicts().is_empty(), "SCOPE a clean map has 0 conflicts")
	var bad := PageKeys.from_json("{\"schema\":2,\"bindings\":[{\"cmd\":\"a\",\"key\":\"K\",\"scope\":\"model\"},{\"cmd\":\"b\",\"key\":\"K\",\"scope\":\"model\"}]}")
	ok(bad["ok"] and (bad["keys"] as PageKeys).conflicts().size() == 1, "SCOPE a loaded file with a same-scope clash reports 1 conflict")
	var k2 := PageKeys.new()
	k2.bind("J", "cmd_x")
	ok(k2.resolve("J", "sculpt") == "cmd_x", "SCOPE planted: without the sculpt binding, sculpt resolves to cmd_x")
	ok(k.unbind("J", "sculpt") and k.resolve("J", "sculpt") == "cmd_x", "SCOPE unbind page scope falls back to global")


func save_bars() -> void:
	var k := PageKeys.new()
	k.bind("Ctrl+K", "c1")
	k.bind("J", "c2", "sculpt")
	k.bind("J", "c3")
	k.bind("Shift+M", "c4", "model")
	var t1 := k.to_json()
	var back := PageKeys.from_json(t1)
	ok(back["ok"], "SAVE reload parses")
	var t2: String = (back["keys"] as PageKeys).to_json()
	ok(t1 == t2, "SAVE to_json -> from_json -> to_json byte-identical (%d bytes)" % t1.length())
	rm("user://pagehot_keys.json")
	ok(k.save_file("user://pagehot_keys.json"), "SAVE file written")
	var k3 := PageKeys.new()
	ok(k3.load_file("user://pagehot_keys.json")["ok"] and k3.to_json() == t1, "SAVE file round trip byte-identical")
	var old := Hotkeys.to_json({"cmd_a": "Ctrl+1", "cmd_b": "F3"})   # the schema-1 profile as the app writes it today
	var o := PageKeys.from_json(old)
	ok(o["ok"], "SAVE old schema-1 file loads")
	var ok_all := true
	for pg in ["model", "sculpt", "animate", "pose", ""]:
		ok_all = ok_all and (o["keys"] as PageKeys).resolve("Ctrl+1", pg) == "cmd_a" and (o["keys"] as PageKeys).resolve("F3", pg) == "cmd_b"
	ok(ok_all, "SAVE old keys are global: same result on every page")
	ok((o["keys"] as PageKeys).global_map() == {"cmd_a": "Ctrl+1", "cmd_b": "F3"}, "SAVE old keys unchanged as a map")
	ok(t1.replace("sculpt", "sculps") != t1 and not PageKeys.from_json(t1.replace("schema", "schemo"))["ok"], "SAVE planted: a changed word is found")
	rm("user://pagehot_keys.json")


func rects_of(wl: WorkLayouts, page: String) -> Dictionary:
	var win := Vector2(1920, 1080)
	var P: Dictionary = wl.cur["pages"][page]
	var area := WorkLayouts.area_for(win, int(P["rail_w"]))
	return WorkLayouts.solve(P, page, win, area, WorkLayouts.chrome_px(win, int(P["rail_w"])))


func max_dev(a: Dictionary, b: Dictionary) -> float:
	if a.size() != b.size():
		return 9999.0
	var d := 0.0
	for id in a:
		if not b.has(id):
			return 9999.0
		var ra: Rect2 = a[id]
		var rb: Rect2 = b[id]
		d = maxf(d, maxf(maxf(absf(ra.position.x - rb.position.x), absf(ra.position.y - rb.position.y)), maxf(absf(ra.size.x - rb.size.x), absf(ra.size.y - rb.size.y))))
	return d


func panel_rects(s: Dictionary) -> Dictionary:
	return s["rects"] if s.has("rects") else s


func space_bars() -> void:
	var wl := WorkLayouts.new("user://pagehot_layouts.json")
	var ps := PageSpaces.new("user://pagehot_spaces.json")
	# model = the "part" page of WorkLayouts; animate keeps its own
	wl.set_dock("part", "browser", "right")
	wl.set_open("part", "timeline", false)
	wl.set_split("part", "right", 380)
	var before := panel_rects(rects_of(wl, "part"))
	var open_before := {}
	for id in wl.cur["pages"]["part"]["panels"]:
		open_before[id] = wl.cur["pages"]["part"]["panels"][id]["open"]
	ps.leave(wl, "part")
	wl.set_dock("animate", "inspector", "left")
	ps.leave(wl, "animate")
	wl.reset()   # something (a loaded layout, the factory button) wiped the working layout
	var wiped := panel_rects(rects_of(wl, "part"))
	ok(max_dev(before, wiped) > 1.0, "SPACE planted: without the store the reset layout differs from the model layout by %.1f px" % max_dev(before, wiped))
	ps.enter(wl, "animate")
	ok(String(wl.cur["pages"]["animate"]["panels"]["inspector"]["dock"]) == "left", "SPACE animate restores its own layout (inspector left)")
	ps.enter(wl, "part")
	var after := panel_rects(rects_of(wl, "part"))
	var dev := max_dev(before, after)
	ok(dev <= 1.0 and not before.is_empty(), "SPACE model panel rects restored within 1 px (max dev %.2f px, %d panels)" % [dev, before.size()])
	var same_open := true
	for id in open_before:
		same_open = same_open and wl.cur["pages"]["part"]["panels"][id]["open"] == open_before[id]
	ok(same_open, "SPACE open flags restored")
	ok(String(wl.cur["pages"]["part"]["panels"]["browser"]["dock"]) == "right", "SPACE browser still docked right")
	rm("user://pagehot_spaces.json")
	ok(ps.save_file(), "SPACE store saved")
	var ps2 := PageSpaces.new("user://pagehot_spaces.json")
	wl.reset()
	ps2.enter(wl, "part")
	ok(max_dev(before, panel_rects(rects_of(wl, "part"))) <= 1.0, "SPACE a reloaded store restores the same rects")
	var wl2 := WorkLayouts.new("user://pagehot_layouts2.json")
	ps2.enter(wl2, "engineering")   # a page never left: untouched, no crash
	ok(WorkLayouts.same(wl2.cur["pages"]["engineering"], WorkLayouts.factory()["pages"]["engineering"]), "SPACE a page never left stays factory")
	rm("user://pagehot_spaces.json")
	rm("user://pagehot_layouts.json")
	rm("user://pagehot_layouts2.json")


func learn_bars() -> void:
	var cmds := []
	for id in ["c_cmd", "a_cmd", "b_cmd", "d_cmd", "e_cmd", "f_cmd"]:
		cmds.append({"id": id, "name": id, "keys": ""})
	cmds.append({"id": "keyed", "name": "keyed", "keys": "Ctrl+9"})
	rm("user://pagehot_learn.json")
	var L := CmdLearn.new("user://pagehot_learn.json")
	for i in 10:
		L.record("c_cmd")
	for id in ["a_cmd", "b_cmd", "d_cmd", "e_cmd", "f_cmd"]:
		L.record(id)
	for i in 20:
		L.record("keyed")
	ok(L.runs("keyed") == 20 and L.runs("c_cmd") == 10 and L.runs("a_cmd") == 1, "LEARN counts: keyed 20, C 10, other 1")
	var keys := PageKeys.new()
	var s := L.suggest(cmds, keys)
	ok(s.size() >= 1 and String(s[0]["id"]) == "c_cmd", "LEARN planted: C is suggested first (got %s)" % (String(s[0]["id"]) if s.size() > 0 else "nothing"))
	ok(not s.any(func(x): return String(x["id"]) == "keyed"), "LEARN a command that already has a hotkey is never suggested")
	ok(not s.any(func(x): return String(x["id"]) == "a_cmd"), "LEARN a command run once is not suggested")
	var key := String(s[0]["key"]) if s.size() > 0 else ""
	ok(key != "" and key != "Ctrl+9" and keys.resolve(key, "model") == "", "LEARN the suggested key is free (%s)" % key)
	keys.bind("Ctrl+9", "x_other")
	ok(String(L.suggest(cmds, keys)[0]["key"]) != "Ctrl+9", "LEARN a key bound in PageKeys is not offered")
	L.dismiss("c_cmd")
	ok(not L.suggest(cmds, keys).any(func(x): return String(x["id"]) == "c_cmd"), "LEARN dismissed C is gone")
	for i in 100:
		L.record("c_cmd")
	ok(not L.suggest(cmds, keys).any(func(x): return String(x["id"]) == "c_cmd"), "LEARN dismissed C stays gone after 100 more runs")
	ok(L.save_file(), "LEARN saved")
	var L2 := CmdLearn.new("user://pagehot_learn.json")
	ok(L2.is_dismissed("c_cmd") and L2.runs("c_cmd") == 110, "LEARN reloaded: dismissed + counts kept (%d runs)" % L2.runs("c_cmd"))
	ok(not L2.suggest(cmds, keys).any(func(x): return String(x["id"]) == "c_cmd"), "LEARN dismissed C never comes back after a restart")
	var L3 := CmdLearn.new("user://pagehot_learn.json")
	var b := PageKeys.new()
	for i in 12:
		L3.record("d_cmd")
	var s3 := L3.suggest(cmds, b)
	ok(s3.size() > 0 and String(s3[0]["id"]) == "d_cmd", "LEARN accept path: d_cmd now top")
	ok(s3.size() > 0 and L3.accept("d_cmd", String(s3[0]["key"]), b)["ok"] and b.resolve(String(s3[0]["key"]), "model") == "d_cmd", "LEARN accept binds the key globally")
	rm("user://pagehot_learn.json")
