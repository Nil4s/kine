## godot --path . -s tests/exportwalk_test.gd     (EXPORTWALK: a fighter walk exported as FBX and GLB, re-imported; 1280x720)
## Starts at the REAL start screen: Easy (a real click), build walk (a real click), Switch to Expert, the EXPORT page, Export...
## (real clicks). The dialog target and format are chosen by select (as deliverwalk does), and the files are written to user://
## through the dialog writers (export_now): the dialog Export button writes to res://exports in the editor, not here.
## Bars, stated before the numbers:
##   1 start   the walk clip is built from the start screen by real clicks (at least 2 cards)
##   2 dialog  Export... (real click) opens the dialog; the Unreal Engine 5 target offers FBX (root motion) and glTF
##   3 fbx     the .fbx is written (binary) and re-imports (FBXDocument) with a skeleton and an animation
##   4 glb     the .glb is written and re-imports (GLTFDocument) with a skeleton and an animation
##   5 bones   the FBX and the GLB have the same bone count and the same bone names in the same order
##   6 frames  every curve of both files has the scene frame count (ceil(length * fps) + 1 keys)
##   7 root    the root bone travels the same in both (within 2 mm at every frame) and the travel is real (> 5 cm)
##   8 root    the pelvis own sideways extent stays under a fifth of the root travel (the travel is off the pelvis)
##   9 preflight the engine pre-flight drift figure equals the .glb pelvis extent (within 2 mm)
## Screenshots: C:/Temp/claude/exportwalk/. Only user:// is written; the user:// folder is removed at the end.
extends SceneTree

const OUT := "C:/Temp/claude/exportwalk/"
const DIR := "user://zz_exportwalk"

var m: Node
var fails := 0
var clicks := 0


func bar(c: bool, what: String) -> void:
	print(("PASS " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 4) -> void:
	for i in n:
		await process_frame


func walk(n: Node, out: Array) -> Array:
	out.append(n)
	for c in n.get_children(true):
		walk(c, out)
	return out


func visible_nodes() -> Array:
	var out := []
	for n in walk(root, []):
		if n is CanvasItem and (n as CanvasItem).is_visible_in_tree():
			out.append(n)
	return out


## waits (up to limit frames) until cond holds; false if it never does
func wait_until(cond: Callable, limit: int) -> bool:
	for i in limit:
		if cond.call():
			return true
		await process_frame
	return false


## waits until a visible button with this tooltip start exists, and returns it (null if it never shows)
func wait_tip(tip: String, limit: int) -> Button:
	for i in limit:
		var b := by_tip(tip)
		if b != null:
			return b
		await process_frame
	return null


func mouse_at(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)


## a real click on a visible control (hover, press, release at its centre)
func click(c: Control) -> void:
	clicks += 1
	var p := c.get_global_rect().get_center()
	var hm := InputEventMouseMotion.new()
	hm.position = p
	hm.global_position = p
	root.push_input(hm)
	await process_frame
	mouse_at(p, true)
	await process_frame
	mouse_at(p, false)
	await idle(4)


## a visible button by its own text, or by a Label inside it
func by_text(txt: String) -> Control:
	for n in visible_nodes():
		if n is Button and (n as Button).text.strip_edges() == txt:
			return n
	for n in visible_nodes():
		if n is Label and (n as Label).text.strip_edges() == txt:
			var p: Node = n
			while p != null and not (p is Button):
				p = p.get_parent()
			return p as Control if p != null else null
	return null


## a visible button by the start of its tooltip
func by_tip(tip: String) -> Button:
	for n in visible_nodes():
		if n is Button and (n as Button).tooltip_text.begins_with(tip):
			return n
	return null


## the bone names and the key counts / root and pelvis positions of one imported scene (metres)
static func read_scene(path: String, fbx: bool) -> Dictionary:
	var doc: GLTFDocument = FBXDocument.new() if fbx else GLTFDocument.new()
	var st: GLTFState = FBXState.new() if fbx else GLTFState.new()
	var out := {"ok": false, "bones": PackedStringArray(), "anim": "", "keys": {}, "root_pos": [], "pelvis_pos": []}
	if doc.append_from_file(ProjectSettings.globalize_path(path), st) != OK:
		return out
	var sc := doc.generate_scene(st)
	if sc == null:
		return out
	var sks := sc.find_children("*", "Skeleton3D", true, false)
	var aps := sc.find_children("*", "AnimationPlayer", true, false)
	if sks.is_empty() or aps.is_empty():
		sc.free()
		return out
	var sk: Skeleton3D = sks[0]
	var ap: AnimationPlayer = aps[0]
	var names := ap.get_animation_list()
	var bones := PackedStringArray()
	for i in sk.get_bone_count():
		bones.append(sk.get_bone_name(i))
	out["bones"] = bones
	if names.size() > 0:
		var A: Animation = ap.get_animation(names[0])
		out["anim"] = String(names[0])
		var keys := {}
		for tr in A.get_track_count():
			var np := A.track_get_path(tr)
			if np.get_subname_count() == 0:
				continue
			var sub := String(np.get_subname(0))
			keys[sub + ":" + str(A.track_get_type(tr))] = A.track_get_key_count(tr)
			if A.track_get_type(tr) == Animation.TYPE_POSITION_3D and (sub == "root" or sub == "pelvis"):
				var rows := []
				for k in A.track_get_key_count(tr):
					rows.append(A.track_get_key_value(tr, k))
				out["root_pos" if sub == "root" else "pelvis_pos"] = rows
		out["keys"] = keys
	out["ok"] = true
	sc.free()
	return out


## the horizontal travel of a list of positions from its first one (metres)
static func travel(rows: Array) -> float:
	var t := 0.0
	for v in rows:
		var d: Vector3 = v - rows[0]
		t = maxf(t, Vector2(d.x, d.z).length())
	return t


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	DirAccess.make_dir_recursive_absolute(OUT)
	EasyMode.start_fresh = true
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(10)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.start_screen.show_screen(true)
	await idle(10)

	# 1. the start screen: Easy, then build walk (a real click each)
	var easy := by_text("Easy")
	if easy != null:
		await click(easy)
	await idle(20)
	var wb := by_tip("build walk and play it")
	var ok1 := wb != null
	if wb != null:
		await click(wb)
	await idle(60)
	var cards: int = m.S.cards.size()
	bar(ok1 and cards >= 2, "1 start: the start screen Easy, then build walk (real clicks): %d cards, clip %.2f s" % [cards, m.S.length()])
	if cards < 2:
		print("exportwalk: %d FAIL (no clip)" % fails)
		quit(1)
		return

	# switch to Expert (Easy's bar), the DELIVER page (Export... lives there), Export...
	var sw := by_text("Switch to Expert")
	if sw != null:
		await click(sw)
	await wait_until(func(): return not m.easy.on, 300)
	await idle(10)
	var pg: Button = m.ui_page_btns["DELIVER"] if m.ui_page_btns.has("DELIVER") else null
	await wait_until(func(): return pg != null and pg.is_visible_in_tree(), 300)
	if pg != null and pg.is_visible_in_tree():
		await click(pg)
	var ex := await wait_tip("Export...", 300)
	if ex != null:
		await click(ex)
	await wait_until(func(): return m.export_ui != null and m.export_ui.dlg != null and m.export_ui.dlg.visible, 300)
	var ui = m.export_ui
	bar(ui != null and ui.dlg != null and ui.dlg.visible, "2 dialog: Export... (real clicks) opens the export dialog")
	if ui == null or ui.dlg == null:
		print("exportwalk: %d FAIL" % fails)
		quit(1)
		return
	var ue_ti := -1
	for i in ExportDialog.targets().size():
		if String((ExportDialog.targets()[i] as Dictionary)["id"]) == "ue5":
			ue_ti = i
	ui.ui_target.select(ue_ti)
	ui._on_target(ue_ti)
	await idle(2)
	var fbx_fi := -1
	var glb_fi := -1
	for i in ui.ui_format.item_count:
		var t: String = ui.ui_format.get_item_text(i)
		if t.contains(".fbx") and t.contains("root motion"):
			fbx_fi = i
		if t.contains(".glb"):
			glb_fi = i
	root.get_texture().get_image().save_png(OUT + "exportwalk_dialog.png")
	bar(fbx_fi >= 0 and glb_fi >= 0, "2b the Unreal Engine 5 target offers the FBX (root motion) and the glTF format (fbx %d, glb %d)" % [fbx_fi, glb_fi])

	# 3-4. the writers, to user://, through the dialog road
	var nfr := int(ceil(m.S.length() * m.S.fps - 1e-6)) + 1
	var pf = ui.export_now("ue5", fbx_fi, DIR)
	var fbx_path := String(pf) if pf is String else ""
	var pg2 = ui.export_now("ue5", glb_fi, DIR)
	var glb_path := String(pg2) if pg2 is String else ""
	var fbx_ok := fbx_path != "" and FileAccess.file_exists(ProjectSettings.globalize_path(fbx_path))
	var glb_ok := glb_path != "" and FileAccess.file_exists(ProjectSettings.globalize_path(glb_path))
	var fbytes := FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(fbx_path)) if fbx_ok else PackedByteArray()
	var gbytes := FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(glb_path)) if glb_ok else PackedByteArray()
	var fhead := fbytes.slice(0, 20).get_string_from_ascii()
	var fr := read_scene(fbx_path, true) if fbx_ok else {"ok": false}
	var gr := read_scene(glb_path, false) if glb_ok else {"ok": false}
	print("fbx %s (%d bytes, head %s), glb %s (%d bytes)" % [fbx_path, fbytes.size(), fhead, glb_path, gbytes.size()])
	var fb: PackedStringArray = fr.get("bones", PackedStringArray())
	var gb: PackedStringArray = gr.get("bones", PackedStringArray())
	bar(fbx_ok and fbytes.size() > 1000 and fhead == "Kaydara FBX Binary  " and bool(fr["ok"]) and fb.size() > 0,
		"3 fbx: written (%d bytes, binary %s), re-imports with %d bones and an animation %s" % [fbytes.size(), str(fhead.begins_with("Kaydara")), fb.size(), str(fr.get("anim", ""))])
	bar(glb_ok and gbytes.size() > 1000 and bool(gr["ok"]) and gb.size() > 0,
		"4 glb: written (%d bytes), re-imports with %d bones and an animation %s" % [gbytes.size(), gb.size(), str(gr.get("anim", ""))])

	# 5. bones
	bar(fb.size() > 0 and fb == gb, "5 bones: the FBX has %d bones, the GLB %d, the same names in the same order: %s" % [fb.size(), gb.size(), str(fb == gb)])

	# 6. frames: every curve of each file has the scene frame count
	var fk: Dictionary = fr.get("keys", {})
	var gk: Dictionary = gr.get("keys", {})
	var f_all := not fk.is_empty()
	for k in fk.keys():
		f_all = f_all and int(fk[k]) == nfr
	var g_all := not gk.is_empty()
	for k in gk.keys():
		g_all = g_all and int(gk[k]) == nfr
	bar(f_all and g_all and fk.size() == gk.size(), "6 frames: scene %d frames; FBX %d curves, GLB %d curves, every curve has the scene keys in each file: %s" % [nfr, fk.size(), gk.size(), str(f_all and g_all)])

	# 7. root motion: the root bone travels the same in both files, and the travel is real
	var rpf: Array = fr.get("root_pos", [])
	var rpg: Array = gr.get("root_pos", [])
	var same := rpf.size() == rpg.size() and rpf.size() > 0
	var worst := 0.0
	if same:
		for i in rpf.size():
			var d: Vector3 = (rpf[i] - rpf[0]) - (rpg[i] - rpg[0])
			worst = maxf(worst, Vector2(d.x, d.z).length())
	var rt_f := travel(rpf)
	var rt_g := travel(rpg)
	bar(same and worst < 0.002 and rt_g > 0.05, "7 root: the root bone travels %.3f m (FBX) and %.3f m (GLB); worst difference at a frame %.4f m" % [rt_f, rt_g, worst])

	# 8. the travel is off the pelvis: its own sideways extent over the clip stays under a fifth of the root travel
	var pd_f := travel(fr.get("pelvis_pos", []))
	var pd_g := travel(gr.get("pelvis_pos", []))
	bar(pd_f < 0.2 * rt_f and pd_g < 0.2 * rt_g, "8 root motion: the pelvis's own sideways extent %.3f m (FBX), %.3f m (GLB) against a root travel of %.3f m" % [pd_f, pd_g, rt_f])

	# 9. the pre-flight line says what the file holds: its drift figure is the pelvis's extent in the .glb (within 2 mm)
	var pre: Array = EngineExport.preflight(m.S, m.B, "ue5", m.S.name if m.S.name != "" else "scene")
	var said := -1.0
	var rx := RegEx.new()
	rx.compile("drift ([0-9.]+) (mm|cm)")
	for l in pre:
		var s := String(l)
		if s.contains("root motion: the pelvis travels"):
			var mt := rx.search(s)
			if mt != null:
				var v := float(mt.get_string(1))
				said = v / 1000.0 if mt.get_string(2) == "mm" else v / 100.0
	bar(said >= 0.0 and absf(said - pd_g) < 0.002, "9 pre-flight: the root-motion line says drift %.4f m; the .glb pelvis extent is %.4f m (within 2 mm)" % [said, pd_g])


	root.get_texture().get_image().save_png(OUT + "exportwalk_end.png")
	print("exportwalk: %d FAIL, %d clicks" % [fails, clicks])
	m.free()
	var g := ProjectSettings.globalize_path(DIR)
	if DirAccess.dir_exists_absolute(g):
		for f in DirAccess.get_files_at(g):
			DirAccess.remove_absolute(g + "/" + f)
		DirAccess.remove_absolute(g)
	quit(1 if fails > 0 else 0)

