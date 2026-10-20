## godot --path . -s tests/archetypes_test.gd     (ROADMAP_400 G23: fighter archetypes; needs a window)
## Sources: scripts/archetypes.gd (each row cites its study); ape index of elite boxers 1.02-1.06 (Chaabene et al. 2015).
## BARS, written before measuring:
##  1 SOURCES: every archetype has a non-empty source string and its stature / mass / ape are inside sane human bounds
##  2 ORDER + REACH: the applied heavyweight is taller and heavier than the flyweight; for each boxer preset the T-pose
##    fingertip-to-fingertip span / stature (measured on the posed skeleton) is within its cited range +-0.01 AND within
##    0.01 of the preset's own ape index; the stature is within 5 mm of the table's
##  3 UNDO: choosing an archetype through the list popup is ONE undo step; Ctrl+Z gives the scene JSON and body state back
##    exactly; the status line carries the source
##  4 PLACEMENT (whole-body view): four archetypes (flyweight, heavyweight, sumo, gymnast) each stand with the lowest sole
##    within 1 cm of the floor, head top and soles inside the view, and the heavyweight is taller on screen than the flyweight
## Screenshot: the four side by side, one camera: jobs/9afc22db/tmp/archetypes.png
extends SceneTree

var m: Node
var fails := 0
const OUT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/archetypes.png"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func fresh(d: Dictionary) -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.set_proportions(d)
	return b


func screen_box() -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for j in Body.ORDER:
		var q: Vector2 = m.cam.unproject_position(m.B.P[j])
		lo = lo.min(q)
		hi = hi.max(q)
	return Rect2(lo, hi - lo)


func _init() -> void:
	var skel0 := FileAccess.get_file_as_bytes("res://data/skeleton.json")
	# ---- 1 sources
	var allsrc := true
	for id in Archetypes.ORDER:
		var a: Dictionary = Archetypes.TABLE[id]
		allsrc = allsrc and String(a.get("src", "")).length() > 20 and float(a["stature"]) > 1.4 and float(a["stature"]) < 2.1 and float(a["mass"]) > 35.0 and float(a["ape"]) > 0.95 and float(a["ape"]) < 1.1
	ok(allsrc and Archetypes.ORDER.size() >= 12 and Archetypes.TABLE.size() == Archetypes.ORDER.size(), "1 every one of %d archetypes has a source string and sane stature / mass / ape" % Archetypes.ORDER.size())
	# ---- 2 measured on the posed skeleton
	var meas := {}
	for id in Archetypes.ORDER:
		var a: Dictionary = Archetypes.TABLE[id]
		var me := BodyModel.measures(fresh(Archetypes.body_for(id)))
		meas[id] = me
		var ape: float = float(me["span"]) / float(me["stature"])
		var inr: bool = ape >= float(a["lo"]) - 0.01 and ape <= float(a["hi"]) + 0.01
		var own: bool = absf(ape - float(a["ape"])) <= 0.01
		var st_ok: bool = absf(float(me["stature"]) - float(a["stature"])) < 0.005
		print("     %-13s stature %.1f cm (table %.1f), span %.1f cm, ape %.3f (table %.2f, range %.2f-%.2f)" % [id, float(me["stature"]) * 100.0, float(a["stature"]) * 100.0, float(me["span"]) * 100.0, ape, float(a["ape"]), float(a["lo"]), float(a["hi"])])
		ok(inr and own and st_ok, "2 %s: ape %.3f inside %.2f-%.2f +-0.01 and within 0.01 of %.2f; stature within 5 mm" % [id, ape, float(a["lo"]), float(a["hi"]), float(a["ape"])])
	var fly := Archetypes.body_for("boxer_fly")
	var hvy := Archetypes.body_for("boxer_heavy")
	ok(float(hvy["stature"]) > float(fly["stature"]) + 0.2 and float(hvy["mass"]) > float(fly["mass"]) + 30.0 and float(meas["boxer_heavy"]["stature"]) > float(meas["boxer_fly"]["stature"]), "2 heavyweight %.1f cm / %.0f kg is taller and heavier than flyweight %.1f cm / %.0f kg" % [float(hvy["stature"]) * 100.0, float(hvy["mass"]), float(fly["stature"]) * 100.0, float(fly["mass"])])
	# ---- the app
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m._page_set("BODY", false)
	await idle(4)
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var scene0 := JSON.stringify(m.S.to_dict(m.B))
	var state0 := JSON.stringify(m.B.state())
	var u0: int = m.undo.size()
	# ---- 3 the list popup, one undo step
	m._archetype_dialog()
	await idle(2)
	var li: ItemList = m.ui_arch_list
	ok(li != null and li.item_count == Archetypes.ORDER.size() and m.ui_arch_dlg.visible, "3 the popup lists %d archetypes" % (li.item_count if li != null else -1))
	li.item_activated.emit(Archetypes.ORDER.find("boxer_heavy"))
	await idle(3)
	ok(m.undo.size() == u0 + 1 and absf(float(m.S.body["stature"]) - float(hvy["stature"])) < 1e-6 and float(m.S.body["mass"]) == float(hvy["mass"]), "3 one list pick = ONE undo step (%d -> %d), the scene's body is the heavyweight" % [u0, m.undo.size()])
	var st_txt: String = m.ui_status.text
	ok(st_txt.contains("Source:") and st_txt.contains("Chaabene"), "3 the status line says the source: '%s'" % st_txt.left(90))
	m._undo()
	await idle(3)
	ok(JSON.stringify(m.S.to_dict(m.B)) == scene0 and JSON.stringify(m.B.state()) == state0 and m.undo.size() == u0, "3 Ctrl+Z gives back the scene JSON and the body state exactly")
	ok(FileAccess.get_file_as_bytes("res://data/skeleton.json") == skel0, "3 data/skeleton.json is byte-identical")
	# ---- 4 placement + screenshot
	if m.dummy_on:
		m._dummy_toggle()
	m.sel = "pelvis"
	m._do(func(): m._arms_relaxed())
	var picks := ["boxer_fly", "boxer_heavy", "sumo", "gymnast"]
	var pic := {}
	var boxes := {}
	var tops := {}
	var view_r := Rect2(m.lw(), 60.0, vs.x - m.lw() - m.rw(), vs.y - m.bottom_h - 60.0)
	for id in picks:
		m.archetype_set(id)
		await idle(3)
		m._view(1)
		await idle(6)
		await RenderingServer.frame_post_draw
		pic[id] = m.get_viewport().get_texture().get_image()
		boxes[id] = screen_box()
		var top: Vector2 = m.cam.unproject_position(Proportions.head_top(m.B))
		var lo: float = m.B.sole_low()
		ok(absf(lo) < 0.01 and view_r.has_point(top) and view_r.has_point((boxes[id] as Rect2).end), "4 %s: lowest sole %.1f mm off the floor, head top (%.0f,%.0f) and body box %s inside the view" % [id, lo * 1000.0, top.x, top.y, boxes[id]])
	ok((boxes["boxer_heavy"] as Rect2).size.y > (boxes["boxer_fly"] as Rect2).size.y * 1.08, "4 the heavyweight is taller on screen: %.0f px vs %.0f px" % [(boxes["boxer_heavy"] as Rect2).size.y, (boxes["boxer_fly"] as Rect2).size.y])
	var sc: float = float((pic[picks[0]] as Image).get_width()) / vs.x
	var half := int(120.0 * sc)
	var y0 := int(60.0 * sc)
	var hh := int((vs.y - m.bottom_h - 60.0) * sc)
	var out := Image.create(8 * half, hh, false, (pic[picks[0]] as Image).get_format())
	out.fill(Color(0.1, 0.1, 0.12))
	var k := 0
	for id in picks:
		var cx := int((boxes[id] as Rect2).get_center().x * sc)
		out.blit_rect(pic[id], Rect2i(clampi(cx - half, 0, (pic[id] as Image).get_width() - 2 * half), y0, 2 * half, hh), Vector2i(k * 2 * half, 0))
		k += 1
	out.save_png(OUT)
	print("     screenshot: %s (%dx%d): flyweight, heavyweight, sumo, gymnast, one camera" % [OUT, out.get_width(), out.get_height()])
	print("ARCHETYPES %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(1 if fails > 0 else 0)
