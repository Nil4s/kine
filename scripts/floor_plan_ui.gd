## floor_plan_ui.gd - I42 FLOOR PLAN panel (the plan: scripts/floor_plan.gd, the drawing: floor_plan_view.gd). Opens in the findings panel like the
## safety sheet. "Export page" writes the printable HTML (the plan as inline SVG, tables of footprints, strikes, safety margins) and a PNG of the plan
## to user://floor_plan/ (FloorPlan.DIR; a test passes another folder). Read-only: the open body is saved with B.state() and put back exactly.
class_name FloorPlanUI
extends RefCounted

const PNG_SIZE := Vector2i(1400, 1000)
const VIEW_W := 560.0

var m: Node
var plan: Dictionary = {}
var view: FloorPlanView
var last_path := ""
var last_png := ""
var forced: Dictionary = {}   # {"scenes", "names", "xfs"}: plan these instead of the open scene (a test's fighters)


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Floor plan", "", show, "floor plan top view rehearsal stunt crew footprints foot steps path centre of mass strike lines safety margins grid scale print html png",
		false, "a top-down rehearsal plan of the fight: every foot placement numbered with its time, each fighter's path, the strike lines and the safety margins on a 100 cm grid; Export writes a printable page and a picture")


func gather() -> Dictionary:
	if not forced.is_empty():
		return forced
	m._actors_sync()
	var sc := []
	var nm := []
	var xs := []
	if m.actors_rt.size() >= 2:
		for k in m.actors_rt.size():
			sc.append(m.actors_rt[k]["S"])
			nm.append("the hero" if k == 0 else String(m.actors_rt[k]["name"]))
			xs.append(m.actors_rt[k]["xf"])
	else:
		sc.append(m._hero_scene())
		nm.append("the hero")
		xs.append(Transform3D.IDENTITY)
	return {"scenes": sc, "names": nm, "xfs": xs}


func compute() -> void:
	var keep: Dictionary = m.B.state()
	var g := gather()
	var S: Scene = g["scenes"][0]
	plan = FloorPlan.analyze(g["scenes"], g["names"], g["xfs"], maxi(1, S.fps))
	m.B.set_state(keep)


func show() -> void:
	if m.S.cards.is_empty():
		m._say("the floor plan needs a scene with cards: add a pose card first (or open a scene from the list)")
		return
	compute()
	_panel()


func _title() -> String:
	return String((gather()["scenes"][0] as Scene).name)


func _panel() -> void:
	var L: VBoxContainer = m.ui_find_list
	for c in L.get_children():
		L.remove_child(c)
		c.queue_free()
	var head := HBoxContainer.new()
	L.add_child(head)
	var title: Label = m._label("FLOOR PLAN  -  %s" % FloorPlan.summary(plan), 14, "heading", true)
	title.name = "fp_title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.custom_minimum_size = Vector2(300, 0)
	head.add_child(title)
	var eb: Button = m._button("Export page", export_page, "write the printable floor plan page and a PNG of the plan to user://floor_plan/")
	eb.name = "fp_export"
	head.add_child(eb)
	head.add_child(m._button("Close", m._close_findings))
	view = FloorPlanView.new()
	view.name = "fp_view"
	view.plan = plan
	var b: Rect2 = plan["bounds"]
	view.custom_minimum_size = Vector2(VIEW_W, clampf(VIEW_W * b.size.y / b.size.x, 240.0, 420.0))
	L.add_child(view)
	var legend := "Numbered footprints: where each foot is placed and when. Lines: each fighter's centre of mass, a dot each second; dashed arrows: strikes from the wind-up to the contact; rings: safety margins."
	L.add_child(m._label(legend, 13, "text:0.6", true))
	(m.ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(VIEW_W + 24.0, view.custom_minimum_size.y + 120.0)
	m.ui_find.visible = true
	m._say("floor plan: " + FloorPlan.summary(plan) + ".  'Export page' writes the printable page and a picture")


## the plan as a PNG (PNG_SIZE), drawn in a SubViewport of its own
func render_png(host: Node) -> PackedByteArray:
	var vp := SubViewport.new()
	vp.size = PNG_SIZE
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var v := FloorPlanView.new()
	v.plan = plan
	v.size = Vector2(PNG_SIZE)
	vp.add_child(v)
	host.add_child(vp)
	await (Engine.get_main_loop() as SceneTree).process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return img.save_png_to_buffer() if img != null and not img.is_empty() else PackedByteArray()


## write the page and the PNG. dir: where (FloorPlan.DIR; a test passes its own user:// folder). Returns the page path ("" on failure)
func write_page(host: Node, dir := FloorPlan.DIR) -> String:
	if plan.is_empty():
		compute()
	var png := await render_png(host)
	var nm := _title().validate_filename().replace(" ", "_")
	var abs := ProjectSettings.globalize_path(dir)
	DirAccess.make_dir_recursive_absolute(abs)
	var path := "%s/%s_floor_plan.html" % [abs, nm]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(FloorPlan.to_html(plan, _title(), "%s_floor_plan.png" % nm))
	f.close()
	last_path = path
	last_png = ""
	if not png.is_empty():
		var pp := "%s/%s_floor_plan.png" % [abs, nm]
		var g := FileAccess.open(pp, FileAccess.WRITE)
		if g != null:
			g.store_buffer(png)
			g.close()
			last_png = pp
	return path


func export_page() -> void:
	if plan.is_empty():
		compute()
	m._say("floor plan: drawing the picture and writing the page...")
	var p := await write_page(m)
	if p == "":
		m._say("could not write the floor plan: check that the user folder is writable, then press Export page again")
		return
	m._say("floor plan written to %s (open it in a browser, print from there; the picture is next to it)" % p)
