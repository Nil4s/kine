class_name KMeshCutTool
extends RefCounted
## The model preview's cut keys (ROADMAP_400 B04; the ops are scripts/kmesh_cut.gd). KMeshEditUI.input hands every
## event here first (handle()); while a tool is running it takes the keys and the left / right clicks:
##   Ctrl+R  loop cut: move over an edge, the new loop across its quad ring is drawn; the wheel (or + / -) sets how many
##           cuts; click cuts at once (one undo step); Shift+click starts the slide instead: the mouse along the hovered
##           edge slides the loop (or type a factor -1..1); click / Enter cuts, right click / Esc cancels
##   Shift+K knife: click points on the surface (near an edge or a corner snaps to it), the cut is drawn between them;
##           Backspace takes the last point back, Enter cuts (one undo step), right click / Esc cancels
##   V       edge split: the selected edges (vertex mode: between selected verts; face mode: the region's border) are
##           split, the faces either side get their own verts (one undo step)
## The drawing (the loop preview, the knife's points and lines) goes on the preview's overlay, in Tok "pick_hover".

const PICK_SNAP_PX := 12.0   # a knife click this close to an edge (on screen) lands on it
const VERT_SNAP_PX := 6.0    # ... and this close to a corner, on the corner

var ui   # KMeshEditUI
var mode := ""   # "", "loop", "slide", "knife"
var edge := Vector2i(-1, -1)   # loop: the hovered edge, ordered: slide > 0 goes toward edge.y
var cuts := 1
var slide := 0.0
var typed := ""
var pts: Array = []   # knife: [{"face", "point" (mesh-local)}]
var mouse := Vector2.ZERO
var preview := {}   # loop: KMeshCut.loop_preview
var _mesh: KMesh   # the mesh the tool state belongs to (a new test cube drops it)


## KMeshEditUI.input calls this first; true = used. The tool lives on the UI as meta "kcut" (made on first use)
static func handle(u, ev: InputEvent) -> bool:
	var t: KMeshCutTool = u.get_meta("kcut") if u.has_meta("kcut") else null
	if t == null:
		t = KMeshCutTool.new()
		t.ui = u
		u.set_meta("kcut", t)
		u._ov.draw.connect(t._draw)
	if t._mesh != u.mesh:
		t._mesh = u.mesh
		t.mode = ""
		t.pts = []
		t.preview = {}
	return t.input(ev)


static func of(u) -> KMeshCutTool:
	return u.get_meta("kcut") if u.has_meta("kcut") else null


func _say(s: String) -> void:
	ui.m._say("Model: " + s)


func input(ev: InputEvent) -> bool:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		if not k.pressed or k.echo:
			return mode != ""
		var kc := k.keycode & KEY_CODE_MASK
		var ctrl := k.ctrl_pressed or (k.keycode & KEY_MASK_CTRL) != 0
		var shift := k.shift_pressed or (k.keycode & KEY_MASK_SHIFT) != 0
		var alt := k.alt_pressed or (k.keycode & KEY_MASK_ALT) != 0
		if mode == "":
			if kc == KEY_R and ctrl and not shift and not alt:
				start_loop()
				return true
			if kc == KEY_K and shift and not ctrl and not alt:
				start_knife()
				return true
			if kc == KEY_V and not ctrl and not shift and not alt:
				split_selected()
				return true
			return false
		_modal_key(kc)
		return true
	if mode == "":
		return false
	if ev is InputEventMouseMotion:
		move((ev as InputEventMouseMotion).position)
		return false   # the camera keeps its drags
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
		var mb := ev as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if mode == "knife":
					return false
				set_cuts(cuts + (1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1))
				return true
			MOUSE_BUTTON_RIGHT:
				cancel()
				return true
			MOUSE_BUTTON_LEFT:
				click(mb.position, mb.shift_pressed)
				return true
	return ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT


func _modal_key(kc: int) -> void:
	match kc:
		KEY_ESCAPE:
			cancel()
		KEY_ENTER, KEY_KP_ENTER:
			confirm()
		KEY_BACKSPACE:
			if mode == "knife" and not pts.is_empty():
				pts.pop_back()
				_say("knife: %d points (Backspace takes one back, Enter cuts, Esc cancels)" % pts.size())
			elif mode == "slide" and typed != "":
				typed = typed.left(typed.length() - 1)
				_typed_slide()
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			if mode == "loop":
				set_cuts(cuts + 1)
		KEY_MINUS, KEY_KP_SUBTRACT:
			if mode == "loop":
				set_cuts(cuts - 1)
			elif mode == "slide":
				typed = "-" if typed == "" else ("" if typed == "-" else typed)
				_typed_slide()
		KEY_PERIOD, KEY_KP_PERIOD:
			if mode == "slide" and not typed.contains("."):
				typed += "."
				_typed_slide()
		_:
			if mode == "slide" and ((kc >= KEY_0 and kc <= KEY_9) or (kc >= KEY_KP_0 and kc <= KEY_KP_9)):
				typed += str(kc - KEY_0 if kc <= KEY_9 else kc - KEY_KP_0)
				_typed_slide()
	ui._ov.queue_redraw()


func _typed_slide() -> void:
	if typed.is_valid_float():
		set_slide(typed.to_float())
	_say("loop cut: slide %s (a factor -1..1; Enter cuts)" % (typed if typed != "" else "%.2f" % slide))


# ---------------------------------------------------------------- loop cut

func start_loop() -> void:
	mode = "loop"
	edge = Vector2i(-1, -1)
	preview = {}
	slide = 0.0
	typed = ""
	_say("loop cut: move over an edge (the new loop is drawn), the wheel sets the cuts (%d), click cuts, Shift+click slides first, Esc cancels" % cuts)
	move(mouse)


func set_cuts(n: int) -> void:
	cuts = clampi(n, 1, KMeshCut.MAX_CUTS)
	_refresh()
	_say("loop cut: %d cut%s" % [cuts, "" if cuts == 1 else "s"])


func set_slide(f: float) -> void:
	slide = clampf(f, -1.0, 1.0)
	_refresh()


func _refresh() -> void:
	if edge.x >= 0 and mode in ["loop", "slide"]:
		preview = KMeshCut.loop_preview(ui.mesh, edge.x, edge.y, cuts, slide)
	ui._ov.queue_redraw()


func _cam() -> Camera3D:
	return ui.m.cam


func move(p: Vector2) -> void:
	mouse = p
	match mode:
		"loop":
			var h: Dictionary = ui.view.pick(_cam(), p, 1e9)
			var e := Vector2i(-1, -1)
			if not h.is_empty():
				e = h["edge"]
				var f: PackedInt32Array = ui.mesh.faces[h["face"]]
				var i := f.find(e.x)
				if f[(i + 1) % f.size()] != e.y:
					e = Vector2i(e.y, e.x)   # the face's own direction: the same hover gives the same slide sign
			if e != edge:
				edge = e
				_refresh()
		"slide":
			if typed == "":
				var a: Variant = ui.view._screen(_cam(), ui.view._to_world(edge.x))
				var b: Variant = ui.view._screen(_cam(), ui.view._to_world(edge.y))
				if a != null and b != null and (b - a).length_squared() > 1.0:
					var t: float = (p - a).dot(b - a) / (b - a).length_squared()
					set_slide((t - 0.5) * 2.0)
	ui._ov.queue_redraw()


func click(p: Vector2, shift := false) -> void:
	mouse = p
	match mode:
		"loop":
			move(p)
			if edge.x < 0 or (preview.get("lines", []) as Array).is_empty() or (preview["lines"][0] as PackedVector3Array).is_empty():
				_say("loop cut: no quad ring under the mouse. Move over an edge with a quad beside it (Esc cancels)")
				return
			if not shift:
				confirm()   # a click cuts at the middle of the edge (one undo step)
				return
			mode = "slide"
			slide = 0.0
			typed = ""
			_refresh()
			_say("loop cut: slide along the edge (or type -1..1), click / Enter cuts, Esc cancels")
		"slide":
			confirm()
		"knife":
			add_point(p)


func confirm() -> void:
	match mode:
		"loop", "slide":
			if edge.x < 0:
				cancel()
				return
			var e := edge
			var n := cuts
			var f := slide
			mode = ""
			ui.undo.begin(ui.mesh)
			var r := KMeshCut.loop_cut(ui.mesh, e.x, e.y, n, f)
			_finish(r, "Loop cut", "loop cut: %d new loop%s across %d edges (slide %.2f); the new edges are selected. Ctrl+Z takes it back" % [n, "" if n == 1 else "s", int(r.get("ring", 0)), clampf(f, -KMeshCut.SLIDE_MAX, KMeshCut.SLIDE_MAX)])
		"knife":
			if pts.size() < 2:   # one point cuts nothing: the knife keeps running, and says how many it needs
				_say("knife: needs 2 points, you have %d. Click two points on the model's faces (Backspace takes one back, Esc cancels)" % pts.size())
				return
			var p := pts.duplicate()
			mode = ""
			pts = []
			ui.undo.begin(ui.mesh)
			var r := KMeshCut.knife(ui.mesh, p)
			_finish(r, "Knife", "knife: %d face%s cut, %d verts on the cut; the cut is selected. Ctrl+Z takes it back" % [int(r.get("chords", 0)), "" if int(r.get("chords", 0)) == 1 else "s", (r["verts"] as Array).size()])
	preview = {}
	ui._ov.queue_redraw()


func _finish(r: Dictionary, label: String, said: String) -> void:
	ui.undo.commit(label)
	if String(r.get("error", "")) != "":
		_say(label.to_lower() + ": " + r["error"])
	else:
		ui.sel.clear()
		ui.sel.mode = KMeshSelect.EDGE
		for e in r["edges"]:
			ui.sel.edges[e] = true
		_say(said)
	ui.view.mark_dirty()


func cancel() -> void:
	var was := mode
	mode = ""
	pts = []
	preview = {}
	typed = ""
	ui._ov.queue_redraw()
	_say("%s cancelled (nothing changed)" % ("knife" if was == "knife" else "loop cut"))


# ---------------------------------------------------------------- knife

func start_knife() -> void:
	mode = "knife"
	pts = []
	_say("knife: click points on the surface (near an edge or a corner snaps to it), Enter cuts, Backspace takes a point back, Esc cancels")


## a knife point at screen p: the face under the mouse; a corner / an edge of it within PICK_SNAP_PX lands exactly on it
func add_point(p: Vector2) -> bool:
	var h: Dictionary = ui.view.pick(_cam(), p, PICK_SNAP_PX)
	if h.is_empty():
		_say("knife: that click missed the model (%d points so far). Click on a visible face of the model itself, not the grid or the empty space; Enter cuts from 2 points" % pts.size())
		return false
	var r: Array = ui.view.ray_at(_cam(), p)
	var inv: Transform3D = ui.view.global_transform.affine_inverse()
	var lp: Vector3 = inv * ((r[0] as Vector3) + (r[1] as Vector3) * float(h["t"]))
	var m: KMesh = ui.mesh
	var vs: Variant = ui.view._screen(_cam(), ui.view._to_world(h["vert"])) if int(h["vert"]) >= 0 else null
	if vs != null and p.distance_to(vs) <= VERT_SNAP_PX:
		lp = m.verts[h["vert"]]
	elif (h["edge"] as Vector2i).x >= 0:
		var a: Vector3 = m.verts[h["edge"].x]
		var b: Vector3 = m.verts[h["edge"].y]
		lp = a + (b - a) * clampf((lp - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
	pts.append({"face": int(h["face"]), "point": lp})
	_say("knife: %d point%s (Enter cuts, Backspace takes one back, Esc cancels)" % [pts.size(), "" if pts.size() == 1 else "s"])
	ui._ov.queue_redraw()
	return true


# ---------------------------------------------------------------- V

func split_selected() -> Dictionary:
	var es := KMeshCut.selected_edges(ui.mesh, ui.sel)
	var nv: int = ui.mesh.vert_count()
	ui.undo.begin(ui.mesh)
	var r := KMeshCut.edge_split(ui.mesh, es)
	ui.undo.commit("Edge split")
	if String(r["error"]) != "":
		_say("edge split: " + r["error"])
		return r
	ui.sel.clear()
	ui.sel.mode = KMeshSelect.EDGE
	for e in r["edges"]:
		ui.sel.edges[e] = true
	ui.view.mark_dirty()
	_say("edge split: %d edges split, %d verts became %d (the faces either side are apart now). Ctrl+Z takes it back" % [es.size(), nv, ui.mesh.vert_count()])
	return r


# ---------------------------------------------------------------- drawing

## the screen points of a mesh-local polyline (null where behind the camera)
func screen_line(pl: PackedVector3Array) -> Array:
	var out := []
	for p in pl:
		out.append(ui.view._screen(_cam(), ui.view.global_transform * p))
	return out


func _draw() -> void:
	if mode == "" or not ui.on:
		return
	var ov: Control = ui._ov
	var c := Tok.c("pick_hover")
	if mode in ["loop", "slide"] and not preview.is_empty():
		for pl in preview["lines"]:
			var sp := screen_line(pl)
			var n := sp.size()
			for i in (n if preview["closed"] else n - 1):
				var a: Variant = sp[i]
				var b: Variant = sp[(i + 1) % n]
				if a != null and b != null:
					ov.draw_line(a, b, c, 2.0)
	elif mode == "knife":
		var prev: Variant = null
		for p in pts:
			var s: Variant = ui.view._screen(_cam(), ui.view.global_transform * (p["point"] as Vector3))
			if s != null:
				ov.draw_circle(s, 4.0, c)
				if prev != null:
					ov.draw_line(prev, s, c, 2.0)
			prev = s
		if prev != null:
			ov.draw_line(prev, mouse, Color(c, 0.5), 1.0)
