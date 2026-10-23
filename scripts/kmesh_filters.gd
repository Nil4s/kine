class_name KMeshFilters
extends RefCounted
## Mesh filters (ROADMAP_400 C18): inflate / smooth / sharpen the WHOLE mesh at once, one undo step each.
##   inflate(d)   every vert moves d metres along its own (area-weighted) normal; d < 0 deflates
##   smooth(s)    HC Laplacian (Vollmer, Mencl & Mueller 1999, alpha 0, beta 0.5): each vert moves to the mean of its
##                neighbours, then the push is partly taken back by the mean push of the neighbours. A plain Laplacian
##                SHRINKS a curved surface, and unevenly where the verts are unevenly spaced: on the sculpt sphere 6 plain
##                passes made a clean sphere's radius variance 1.2 mm^2 (lumpier, not smoother); HC keeps it < 0.001.
##                s = passes (s = 0.5 is one half pass, s = 2.5 is three passes of 0.833), so a drag gives a smooth ramp
##   sharpen(s)   unsharp mask, the inverse step: each vert moves AWAY from the mean of its neighbours by s times the
##                gap (s up to 1 per pass, as smooth); bumps stand higher, dents sink deeper
## MASK: when the mesh has a per-vert float channel "mask" (A09), a vert moves by (1 - mask) of its push, so mask = 1 is
## frozen. Nothing else of the masking tools is needed: the channel is just read. C09: the verts of a hidden face set
## (KMeshFaceSets.frozen) are frozen too.
## Pure functions below; the SESSION (begin / set_amount / commit / cancel) is the interactive part: the filter is
## previewed from a snapshot while the strength is dragged or typed, and commit closes one KMeshUndo step.
## In sculpt (scripts/kmesh_sculpt_ui.gd): L starts a filter (L again: inflate -> smooth -> sharpen), drag left / right sets
## the strength (inflate 0.1 mm per px, smooth / sharpen 0.01 per px) or type it (inflate in mm), Enter or a left click
## applies, Esc or a right click cancels.

const INFLATE := "inflate"
const SMOOTH := "smooth"
const SHARPEN := "sharpen"
const KINDS := [INFLATE, SMOOTH, SHARPEN]
const PX_INFLATE := 0.0001   # metres per pixel of drag
const PX_FACTOR := 0.01      # smooth / sharpen strength per pixel of drag

var active := false
var kind := INFLATE
var amount := 0.0            # inflate: metres; smooth / sharpen: strength
var typed := ""
var mesh: KMesh
var undo: KMeshUndo
var _v0 := PackedVector3Array()
var _n0 := PackedVector3Array()
var _x0 := NAN


## 1 - mask per vert (all 1 when there is no per-vert float "mask" channel)
static func free_of(m: KMesh) -> PackedFloat32Array:
	var w := PackedFloat32Array()
	w.resize(m.verts.size())
	w.fill(1.0)
	if m.has_attr("mask"):
		var info := m.attr_info("mask")
		if info.get("domain", "") == "vert" and int(info.get("type", -1)) == TYPE_FLOAT:
			var mk: PackedFloat32Array = m.attr_data("mask")
			for v in mini(mk.size(), w.size()):
				w[v] = 1.0 - clampf(mk[v], 0.0, 1.0)
	var lk := KMeshFaceSets.frozen(m)   # C09: the verts of a hidden face set stay put
	for v in lk.size():
		if lk[v]:
			w[v] = 0.0
	return w


static func _refresh(m: KMesh, vs: PackedVector3Array) -> void:
	m.verts = vs
	m._fresh()
	m._compute_normals()


## every vert d metres along its normal (normals: given, or the mesh's own)
static func inflate(m: KMesh, d: float, normals := PackedVector3Array()) -> void:
	var vn := normals if normals.size() == m.verts.size() else m.vert_normals
	var w := free_of(m)
	var vs := m.verts
	for v in vs.size():
		vs[v] += vn[v] * d * w[v]
	_refresh(m, vs)


## one Laplacian pass: v += f * (mean of neighbours - v) * (1 - mask); f < 0 sharpens
static func _pass(m: KMesh, f: float, w: PackedFloat32Array) -> void:
	var vs := m.verts
	var out := vs.duplicate()
	for v in vs.size():
		if w[v] <= 0.0:
			continue
		var nb := m.vert_neighbors(v)
		if nb.is_empty():
			continue
		var mean := Vector3.ZERO
		for u in nb:
			mean += vs[u]
		out[v] = vs[v] + (mean / nb.size() - vs[v]) * f * w[v]
	m.verts = out


## one HC pass blended by f: p = mean of the neighbours, b = p - q, q' = p - (b / 2 + mean of the neighbours' b / 2)
static func _hc_pass(m: KMesh, f: float, w: PackedFloat32Array, nbs: Array) -> void:
	var q := m.verts
	var n := q.size()
	var pp := PackedVector3Array()
	pp.resize(n)
	var b := PackedVector3Array()
	b.resize(n)
	for v in n:
		var nb: PackedInt32Array = nbs[v]
		if nb.is_empty():
			pp[v] = q[v]
			continue
		var sm := Vector3.ZERO
		for u in nb:
			sm += q[u]
		pp[v] = sm / nb.size()
		b[v] = pp[v] - q[v]
	var out := q.duplicate()
	for v in n:
		var nb: PackedInt32Array = nbs[v]
		if w[v] <= 0.0 or nb.is_empty():
			continue
		var sb := Vector3.ZERO
		for u in nb:
			sb += b[u]
		var t := pp[v] - (b[v] * 0.5 + sb / nb.size() * 0.5)
		out[v] = q[v] + (t - q[v]) * f * w[v]
	m.verts = out


static func smooth(m: KMesh, s: float) -> void:
	if s <= 0.0:
		return
	var n := ceili(s - 1e-6)
	var w := free_of(m)
	var nbs := []
	for v in m.verts.size():
		nbs.append(m.vert_neighbors(v))
	for i in n:
		_hc_pass(m, s / n, w, nbs)
	_refresh(m, m.verts)


## unsharp mask: v moves away from the mean of its neighbours by s times the gap (passes of at most 1, as smooth)
static func sharpen(m: KMesh, s: float) -> void:
	if s <= 0.0:
		return
	var n := ceili(s - 1e-6)
	var w := free_of(m)
	for i in n:
		_pass(m, -s / n, w)
	_refresh(m, m.verts)


static func run(m: KMesh, k: String, a: float, normals := PackedVector3Array()) -> void:
	match k:
		INFLATE:
			inflate(m, a, normals)
		SMOOTH:
			smooth(m, maxf(a, 0.0))
		SHARPEN:
			sharpen(m, maxf(a, 0.0))


# ---------------------------------------------------------------- session (preview while dragging / typing)

func begin(m: KMesh, u: KMeshUndo, k := INFLATE) -> void:
	mesh = m
	undo = u
	kind = k
	amount = 0.0
	typed = ""
	_x0 = NAN
	_v0 = m.verts.duplicate()
	_n0 = m.vert_normals.duplicate()
	undo.begin(m)
	active = true


## the filter at strength a, from the state at begin (a preview: nothing is committed)
func set_amount(a: float) -> void:
	if not active:
		return
	amount = a
	mesh.verts = _v0.duplicate()
	if is_zero_approx(a):
		_refresh(mesh, mesh.verts)
		return
	run(mesh, kind, a, _n0)


func next_kind() -> void:
	kind = KINDS[(KINDS.find(kind) + 1) % KINDS.size()]
	amount = 0.0
	typed = ""
	_x0 = NAN
	set_amount(0.0)


## close the filter: one undo step (empty when it moved nothing)
func commit() -> Dictionary:
	if not active:
		return {}
	active = false
	return undo.commit("filter " + kind)


func cancel() -> void:
	if not active:
		return
	set_amount(0.0)
	active = false
	undo.commit("filter " + kind)   # nothing moved: no step is kept


func label() -> String:
	if kind == INFLATE:
		return "%s %.1f mm" % [kind, amount * 1000.0]
	return "%s %.2f" % [kind, amount]


## sculpt-mode input while the filter runs (or L to start one). ui: the KMeshSculptUI. true = used
func input(ev: InputEvent, ui) -> bool:
	if not active:
		if ev is InputEventKey and ev.pressed and not ev.echo and (ev as InputEventKey).keycode == KEY_L \
				and not (ev as InputEventKey).ctrl_pressed and not (ev as InputEventKey).alt_pressed:
			begin(ui.mesh, ui.undo, INFLATE)
			_say(ui, "Mesh filter: %s. Drag left / right or type the strength (mm), Enter or click applies, L next filter, Esc cancels" % kind)
			return true
		return false
	if ev is InputEventKey:
		var ke := ev as InputEventKey
		if not ke.pressed or ke.echo:
			return true
		var k := ke.keycode
		if k == KEY_L:
			next_kind()
			_say(ui, "Mesh filter: %s. Drag or type the strength%s" % [kind, " (mm)" if kind == INFLATE else ""])
		elif k == KEY_ESCAPE:
			cancel()
			_say(ui, "Mesh filter cancelled: nothing changed")
		elif k == KEY_ENTER or k == KEY_KP_ENTER:
			_finish(ui)
		elif k == KEY_BACKSPACE:
			typed = typed.substr(0, maxi(typed.length() - 1, 0))
			_typed(ui)
		else:
			var ch := ""
			if k >= KEY_0 and k <= KEY_9:
				ch = str(k - KEY_0)
			elif k >= KEY_KP_0 and k <= KEY_KP_9:
				ch = str(k - KEY_KP_0)
			elif k == KEY_PERIOD or k == KEY_KP_PERIOD or k == KEY_COMMA:
				ch = "."
			elif k == KEY_MINUS or k == KEY_KP_SUBTRACT:
				ch = "-"
			if ch != "":
				typed += ch
				_typed(ui)
		_redraw(ui)
		return true
	if ev is InputEventMouseMotion:
		var x := (ev as InputEventMouseMotion).position.x
		if is_nan(_x0):
			_x0 = x - (amount / PX_INFLATE if kind == INFLATE else amount / PX_FACTOR)
		if typed == "":
			set_amount((x - _x0) * (PX_INFLATE if kind == INFLATE else PX_FACTOR))
			_say(ui, "Mesh filter: " + label())
			_redraw(ui)
		return true
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
		var b := (ev as InputEventMouseButton).button_index
		if b == MOUSE_BUTTON_LEFT:
			_finish(ui)
		elif b == MOUSE_BUTTON_RIGHT:
			cancel()
			_say(ui, "Mesh filter cancelled: nothing changed")
			_redraw(ui)
		return true
	return false


func _typed(ui) -> void:
	var a := typed.to_float() if typed.is_valid_float() else 0.0
	set_amount(a / 1000.0 if kind == INFLATE else a)
	_say(ui, "Mesh filter: %s (typed %s)" % [label(), typed])


func _finish(ui) -> void:
	var st := commit()
	_say(ui, "Mesh filter: %s applied, one undo step (Ctrl+Z takes it back)" % label() if not st.is_empty() else "Mesh filter: strength 0, nothing changed")
	_redraw(ui)


static func _say(ui, s: String) -> void:
	if ui != null and ui.m != null and ui.m.has_method("_say"):
		ui.m._say(s)


static func _redraw(ui) -> void:
	if ui != null and ui.view != null:
		ui.view.mark_dirty()
