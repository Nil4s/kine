## godot --path . -s tests/customattr_test.gd     (ROADMAP 82: custom attributes on parts)
## CUSTOM ATTRIBUTES (scripts/custom_attr.gd): a part's named float ("grip" on hand_r, min 0, max 1, default 0), keyed per
## card like a joint angle, read between keys by the part-key curve, saved in the scene, exported as glTF node extras.
##   1 "+ attribute" in the inspector adds hand_r.grip: one undo step; Ctrl+Z takes it back; a bad name, a bad range or a
##     duplicate says what to type and changes nothing (the _say line names the fix)
##   2 a drag of the grip slider at card 1 (value 0) and at card 3 (value 1) keys the two: one undo step per drag
##   3 the value at the midpoint time between card 1 and card 3 equals the same curve a JOINT angle keyed at those two cards
##     gets (PartKeys on hand_r's bend, 0 and 1 at the same times): within 1e-6 (bar)
##   4 saved and loaded: the scene's text is identical, and the value at the midpoint is the same (within 1e-9)
##   5 a scene without attributes writes no "attrs" key (old files save as before); Nick's scenes/ and poses/ read-only
##   6 Mirror (M, the pose's right to left) copies hand_r.grip to hand_l.grip with the same keys: one undo step; the
##     scene's Mirror moves the id to the twin part; mirrored twice it is the original
##   7 the glTF export puts the attribute on the node "hand_r" as extras.poser_attrs.grip (min, max, default, keys [t, v])
##   8 the inspector: the ATTRIBUTES rows sit inside the right panel, the grip slider is drawn in it, and the screenshot
##     tmp/customattr.png is saved (placement bar: both rects inside the panel's rect)
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _said() -> String:
	return m.ui_status.text if m.get("ui_status") != null else ""


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 6:
		await process_frame
	m.tour_step = -1
	# a made scene: 3 cards that differ in the right arm
	var S := Scene.new()
	S.name = "zz_customattr"
	S.fps = 30
	S.add("a", B.to_dict())
	B.ang["upperarm_r"] = Vector3(40, 30, 0)
	B.fk()
	S.add("b", B.to_dict())
	B.ang["upperarm_r"] = Vector3(-10, 60, 20)
	B.fk()
	S.add("c", B.to_dict())
	S.cards[1]["move"] = 0.45
	S.cards[2]["move"] = 0.4
	m.S = S
	m._rebuild_cards()
	m.sel = "hand_r"
	m._refresh()
	await process_frame
	var t1: float = S.times()[0][1]
	var t3: float = S.times()[2][1]
	var tm := (t1 + t3) * 0.5
	var id := CustomAttr.id_of("hand_r", "grip")

	# 1 add: one undo step, bad input changes nothing
	m.ui_attr_name.text = "Grip!"
	var u0: int = m.undo.size()
	m._attr_add()
	ok(not S.attrs.has(id) and m.undo.size() == u0, "1a a bad name ('Grip!') changes nothing; said: %s" % _said())
	m.ui_attr_name.text = "grip"
	m.ui_attr_min.text = "1"
	m.ui_attr_max.text = "0"
	m._attr_add()
	ok(not S.attrs.has(id) and m.undo.size() == u0, "1b min not below max changes nothing; said: %s" % _said())
	m.ui_attr_min.text = "0"
	m.ui_attr_max.text = "1"
	m.ui_attr_def.text = "0"
	u0 = m.undo.size()
	m._attr_add()
	ok(S.attrs.has(id) and m.undo.size() == u0 + 1, "1c '+ attribute' adds hand_r.grip (0 .. 1, default 0): one undo step %s" % (m.undo.size() - u0))
	m._undo()
	ok(not S.attrs.has(id), "1d Ctrl+Z takes the attribute back")
	m.ui_attr_name.text = "grip"
	m._attr_add()
	ok(S.attrs.has(id) and (S.attrs[id]["keys"] as Array).is_empty(), "1e the same form adds it again, with no keys")
	m._refresh()
	await process_frame

	# 2 keys by the slider: a drag at card 1 (0) and at card 3 (1), one undo step per drag
	var sl: HSlider = m.ui_attr_sliders[id][0]
	m.playhead = t1
	m._refresh()
	u0 = m.undo.size()
	sl.drag_started.emit()
	sl.value_changed.emit(0.0)
	ok(m.undo.size() == u0 + 1, "2a a drag at card 1 is one undo step (%d)" % (m.undo.size() - u0))
	m.playhead = t3
	m._refresh()
	u0 = m.undo.size()
	sl.drag_started.emit()
	sl.value_changed.emit(1.0)
	ok(m.undo.size() == u0 + 1 and (S.attrs[id]["keys"] as Array).size() == 2, "2b a drag at card 3 (1) is one undo step; the attribute has %d keys" % (S.attrs[id]["keys"] as Array).size())

	# 3 the midpoint is the joint's curve, to 1e-6
	var ref := {}
	PartKeys.put(ref, "hand_r", t1, Vector3(0, 0, 0))
	PartKeys.put(ref, "hand_r", t3, Vector3(1, 0, 0))
	var joint_mid: float = PartKeys.value_at(ref["hand_r"], tm).x
	var attr_mid := CustomAttr.value_at(S.attrs, id, tm)
	ok(absf(attr_mid - joint_mid) < 1e-6 and attr_mid > 0.0 and attr_mid < 1.0,
		"3 grip at the midpoint %.6f = the joint curve %.6f (diff %s, bar 1e-6); at card 1 %.3f, at card 3 %.3f" % [
			attr_mid, joint_mid, str(absf(attr_mid - joint_mid)), CustomAttr.value_at(S.attrs, id, t1), CustomAttr.value_at(S.attrs, id, t3)])

	# 4 save / load round trip
	var txt1 := JSON.stringify(S.to_dict(m.B))
	var S2 := Scene.new()
	S2.from_dict(JSON.parse_string(txt1))
	var txt2 := JSON.stringify(S2.to_dict(m.B))
	var mid2 := CustomAttr.value_at(S2.attrs, id, tm)
	ok(txt1 == txt2 and absf(mid2 - attr_mid) < 1e-9, "4 saved, loaded, saved again: the text is identical %s; the midpoint %.9f (was %.9f)" % [txt1 == txt2, mid2, attr_mid])

	# 5 old files: no attrs key, and the bundled scenes read without one
	var plain := Scene.new()
	plain.add("p", B.to_dict())
	ok(not JSON.stringify(plain.to_dict(B)).contains("\"attrs\""), "5a a scene with no attribute writes no 'attrs' key")
	var seen := 0
	var bad := 0
	for dir in ["res://scenes/", "res://poses/"]:
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".json"):
				continue
			var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir + f))
			if d is Dictionary and d.has("cards"):
				var Sx := Scene.new()
				Sx.from_dict(d)
				seen += 1
				if not Sx.attrs.is_empty() or JSON.stringify(Sx.to_dict(B)).contains("\"attrs\""):
					bad += 1
	ok(seen > 0 and bad == 0, "5b the %d scenes in scenes/ and poses/ load with no attributes and save with no 'attrs' key (bad %d)" % [seen, bad])

	# 6 mirror: the pose's M copies the attribute to hand_l; the scene's mirror moves the id; twice is the original
	u0 = m.undo.size()
	m._do(func(): m._mirror_side("_r"))
	var idl := CustomAttr.id_of("hand_l", "grip")
	ok(S.attrs.has(idl) and m.undo.size() == u0 + 1 and JSON.stringify(S.attrs[idl]["keys"]) == JSON.stringify(S.attrs[id]["keys"]),
		"6a M copies hand_r.grip to hand_l.grip with the same keys, one undo step")
	var dm := S.to_dict(m.B)
	var mir := CustomAttr.mirror_file(dm["attrs"])
	ok(JSON.stringify(mir[idl]) == JSON.stringify(dm["attrs"][id]) and JSON.stringify(mir[id]) == JSON.stringify(dm["attrs"][idl]) and JSON.stringify(CustomAttr.mirror_file(mir)) == JSON.stringify(dm["attrs"]),
		"6b the scene's mirror moves each id to its twin part (hand_r.grip <-> hand_l.grip); mirrored twice it is the original")

	# 7 glTF extras
	var path := "user://customattr_test.glb"
	var err := GltfExport.write(S, m.B, path, false)
	var bytes := FileAccess.get_file_as_bytes(path)
	var jlen := bytes.decode_u32(12)
	var gj: Dictionary = JSON.parse_string(bytes.slice(20, 20 + jlen).get_string_from_utf8())
	var hit := {}
	for nd in gj.get("nodes", []):
		if String(nd.get("name", "")) == "hand_r":
			hit = nd
	var pa: Dictionary = hit.get("extras", {}).get("poser_attrs", {})
	var g: Dictionary = pa.get("grip", {})
	var kk: Array = g.get("keys", [])
	ok(err == OK and not hit.is_empty() and g.size() == 4 and float(g.get("max", -1)) == 1.0 and kk.size() == 2
		and absf(float(kk[0][1]) - 0.0) < 1e-9 and absf(float(kk[1][1]) - 1.0) < 1e-9,
		"7 glb export: node hand_r carries extras.poser_attrs.grip (min %s, max %s, keys %s)" % [g.get("min"), g.get("max"), kk])

	# 8 the inspector: the rows are in the right panel, the slider is drawn in it
	m.playhead = t1
	m.sel = "hand_r"
	m._sec_open("ATTRIBUTES", true)
	m._refresh()
	for i in 4:
		await process_frame
	var rp: Control = m.ui_insp
	var rr: Rect2 = Rect2(rp.get_global_rect())
	var inside: bool = rr.encloses(Rect2(sl.get_global_rect()))
	var name_row_in: bool = rr.encloses(Rect2(m.ui_attr_name.get_global_rect()))
	var box_ok: bool = m.ui_attr_box.get_child_count() == 1 and sl.is_visible_in_tree()
	m.get_viewport().get_texture().get_image().save_png("C:/Users/Nick/.claude/jobs/9afc22db/tmp/customattr.png")
	ok(inside and name_row_in and box_ok, "8 the grip slider and the attribute form sit inside the right inspector panel (slider %s, form %s); screenshot saved" % [inside, name_row_in])

	print("CUSTOMATTR %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)
