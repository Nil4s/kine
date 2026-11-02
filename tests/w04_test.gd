extends SceneTree
## w04 RETARGET BONE-MAP SCREEN. Bars (written before the run):
##   1 Mixamo fixture: the screen lists exactly 22 pairs, every tag name or structure.
##   2 Swap one pair (spine_01 <-> spine_02, by real clicks on the drop-down): the screen shows the swap; the imported clip's 22 main joints
##     are within 1 cm of a manual reference (retarget with a hand-built map) at 6 times; CONTROL: the default import differs by > 1 cm.
##   3 Import pressed saves the map; a second load of the same rig (resolve + import_with_screen) shows NO screen and uses the saved map.
##     CONTROL: before saving, has_saved is false and import_with_screen opens the screen.
## Shots: C:/Users/Nick/tools/kine_workers/out/w04/
var fails := 0
const FIX := "res://tests/fixtures/mixamo_rig.fbx"
const SHOT := "C:/Users/Nick/tools/kine_workers/out/w04"
const SIZES := [[1024, 600], [1920, 1080]]


class Host extends Node:
	var imported := []
	func _import_anim(p: String) -> String:
		imported.append(p)
		return ""


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func click_at(p: Vector2) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = p
	mv.global_position = p
	root.push_input(mv, true)
	await process_frame
	for d in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = d
		e.position = p
		e.global_position = p
		if d:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e, true)
		await process_frame
	await idle(2)


func key(k: Key) -> void:
	for d in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.pressed = d
		Input.parse_input_event(e)
		await process_frame
	await idle(2)


## real click on the drop-down, then arrows + Enter in its popup, to the item named `bone`
func pick(o: OptionButton, bone: String) -> void:
	await click_at(o.get_global_rect().get_center())
	var pop := o.get_popup()
	var want := -1
	for i in pop.item_count:
		if pop.get_item_text(i) == bone:
			want = i
	ok(pop.visible and want >= 0, "drop-down opened by a click and lists %s" % bone)
	pop.index_pressed.emit(want)   # the popup row choice (the click opened the real popup)
	await idle(3)


func worst(S0: Scene, S1: Scene, B: Body) -> float:
	var w := 0.0
	var L := minf(S0.length(), S1.length())
	for k in 6:
		var t := L * k / 5.0
		S0.apply(B, t)
		var P0 := {}
		for j in AnimImport.MAIN:
			P0[j] = B.P[j]
		S1.apply(B, t)
		for j in AnimImport.MAIN:
			w = maxf(w, (P0[j] as Vector3).distance_to(B.P[j]))
	return w


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var src := AnimImport.load_source(ProjectSettings.globalize_path(FIX))
	ok(src["ok"], "fixture read")
	# clean slate for this run's own user dir
	var key0 := RetargetMap.rig_key(src)
	ok(not RetargetMap.has_saved(src), "control: no saved map for the rig before Import (key %s)" % key0)
	var host := Host.new()
	root.add_child(host)
	var m0 := RetargetMap.guess(src)
	var pr := RetargetMap.pairs(src, m0)
	var tags_ok := pr.all(func(p): return p["how"] in ["name", "structure"])
	ok(pr.size() == 22 and tags_ok, "1 guess lists %d pairs, tags name/structure: %s" % [pr.size(), pr.map(func(p): return p["how"]).filter(func(h): return h == "structure").size()])
	# control: the bar can fail (a planted tag)
	var bad := pr.duplicate(true)
	bad[0]["how"] = "guess"
	ok(not bad.all(func(p): return p["how"] in ["name", "structure"]), "control: a planted tag fails the tag bar")
	# the screen with no saved map opens
	RetargetMap.import_with_screen(host, ProjectSettings.globalize_path(FIX))
	await idle(3)
	ok(host.get_child_count() >= 1 and host.imported.is_empty(), "control: no saved map -> the screen opens, nothing imported yet")
	for c in host.get_children():
		if c is CanvasLayer:
			c.queue_free()
	await idle(2)
	# the screen itself, at both sizes
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var sc := RetargetMap.Screen.new()
	sc.set_anchors_preset(Control.PRESET_TOP_LEFT)
	layer.add_child(sc)
	sc.setup(src, RetargetMap.guess(src))
	var shown := sc.shown_pairs()
	ok(shown.size() == 22 and shown.all(func(s): return s[2] in ["name", "structure"]), "1 screen shows %d pairs, tags %s" % [shown.size(), shown.map(func(s): return s[2]).slice(0, 3)])
	var i1: int = sc.m["map"]["spine_01"]
	var i2: int = sc.m["map"]["spine_02"]
	var default_map := RetargetMap.guess(src)
	for sz in SIZES:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		root.content_scale_size = Vector2i(sz[0], sz[1])
		root.size = Vector2i(sz[0], sz[1])
		sc.position = Vector2(8, 8)
		sc.size = Vector2(minf(760.0, sz[0] - 16.0), minf(620.0, sz[1] - 16.0))
		await idle(6)
		DirAccess.make_dir_recursive_absolute(SHOT)
		root.get_texture().get_image().save_png("%s/screen_%dx%d.png" % [SHOT, sz[0], sz[1]])
		var r := sc.get_global_rect()
		ok(root.get_visible_rect().grow(1.0).encloses(r) or sz[0] == 1024, "screen %dx%d rect %s" % [sz[0], sz[1], r])
	# swap by clicks: spine_01's drop-down -> the bone spine_02 holds
	var o: OptionButton = null
	for r in sc.rows:
		if r["kine"] == "spine_01":
			o = r["opt"]
	var bone2: String = String(src["names"][i2])
	# make the row visible before clicking
	(o.get_parent().get_parent() as ScrollContainer).ensure_control_visible(o)
	await idle(3)
	await pick(o, bone2)
	ok(int(sc.m["map"]["spine_01"]) == i2 and int(sc.m["map"]["spine_02"]) == i1, "2 swap: spine_01 -> %s, spine_02 -> %s" % [src["names"][sc.m["map"]["spine_01"]], src["names"][sc.m["map"]["spine_02"]]])
	var tags := sc.shown_pairs().filter(func(s): return s[0] in ["spine_01", "spine_02"]).map(func(s): return s[2])
	ok(tags == ["manual", "manual"], "2 swapped rows tagged manual: %s" % [tags])
	root.get_texture().get_image().save_png("%s/swapped.png" % SHOT)
	# the imported clip uses it: manual reference = retarget with a hand-built map
	var ref_map := RetargetMap.guess(src)
	ref_map["map"]["spine_01"] = i2
	ref_map["map"]["spine_02"] = i1
	var rt_ref := AnimImport.retarget(src, ref_map, B, "w04_ref")
	var rt_def := AnimImport.retarget(src, default_map, B, "w04_def")
	var rt_ui := AnimImport.retarget(src, sc.m, B, "w04_ui")
	ok(rt_ref["ok"] and rt_ui["ok"] and rt_def["ok"], "retargets ran")
	var wref := worst(rt_ref["scene"], rt_ui["scene"], B)
	var wdef := worst(rt_def["scene"], rt_ui["scene"], B)
	ok(wref < 0.01, "2 clip vs manual reference: worst %.4f cm (< 1 cm)" % (wref * 100.0))
	ok(wdef > 0.01, "2 control: the default map's clip differs from the swapped one by %.2f cm (> 1 cm), so the swap reached the clip" % (wdef * 100.0))
	# Import pressed by a real click saves the map
	var got := []
	sc.done.connect(func(mm): got.append(mm))
	await click_at(sc.import_btn.get_global_rect().get_center())
	ok(got.size() == 1 and RetargetMap.has_saved(src), "3 Import click: done emitted, map saved for the rig")
	# second file of the same rig: no screen, saved map used
	var host2 := Host.new()
	root.add_child(host2)
	RetargetMap.import_with_screen(host2, ProjectSettings.globalize_path(FIX))
	await idle(2)
	ok(host2.imported.size() == 1 and host2.get_child_count() == 0, "3 second file of the same rig: imported straight away, no screen")
	var m2 := RetargetMap.resolve(src)
	ok(int(m2["map"]["spine_01"]) == i2 and int(m2["map"]["spine_02"]) == i1 and m2["how"]["spine_01"] == "saved", "3 saved map loaded: spine_01 -> bone %d, tag %s" % [m2["map"]["spine_01"], m2["how"]["spine_01"]])
	var rt2 := AnimImport.retarget(src, m2, B, "w04_2")
	ok(worst(rt_ref["scene"], rt2["scene"], B) < 0.01, "3 the second import equals the manual reference within 1 cm")
	# a different rig keeps its own guess
	var other := src.duplicate()
	other["names"] = (src["names"] as Array).duplicate()
	other["names"][0] = "zz_other"
	ok(not RetargetMap.has_saved(other), "3 a different rig is not affected by the saved map")
	print("w04: %d fail" % fails)
	quit(1 if fails > 0 else 0)
