class_name SculptPoseUI
extends Node
## C19 (docs/ROADMAP_400.md): "Model: sculpt the body in pose" (Search; mesh_tools.gd "op:sculpt_pose"). With the fighter's
## body open in the model preview (G01, "Model: edit the body mesh"), the body is shown skinned at the CURRENT FRAME's pose
## and every sculpt brush works on it (the sculpt UI, scripts/kmesh_sculpt_ui.gd: D C I S F P E G K, M mask, W face sets,
## [ ] radius ...); each stroke lands in the rest mesh (scripts/sculpt_pose.gd has the map), ONE undo step. Moving to
## another frame skins the edited rest again. "Model: sculpt in pose as a corrective (on / off)" sends the strokes into a
## corrective shape key tied to the bent elbow / knee instead (the rest stays bit-exact).
## Esc leaves: the model preview is back on the edited body (its Ctrl+Z takes the strokes back one by one), and "Model:
## apply the body mesh to the fighter" writes it as before.
## Symmetry is off while posed (a bent arm has no mirror partner at this frame); it comes back on leaving.

const META := "sculpt_pose"

var m: Node
var sp: SculptPose
var undo: SculptPose.PoseUndo
var _sig := 0
var _sym := []
var reskins := 0          # how many times the posed body was skinned again for a new pose (tests)


static func get_ui(main: Node) -> SculptPoseUI:
	if main.has_meta(META):
		return main.get_meta(META)
	var u := SculptPoseUI.new()
	u.m = main
	u.name = "sculpt_pose"
	main.add_child(u)
	main.set_meta(META, u)
	return u


## the mesh_tools ops: "sculpt_pose" (open / leave), "sculpt_pose_corr" (the corrective mode on / off)
static func op(name: String, main: Node) -> String:
	var u := get_ui(main)
	var said := u.toggle() if name == "sculpt_pose" else u.toggle_corrective()
	main._say(said)
	return said


func is_on() -> bool:
	return sp != null and m.get("ksc") != null and m.ksc.on and m.ksc.source.is_valid()


func _pose_sig() -> int:
	return hash([DqSkin.bind_mats(m.skel, sp.skin), float(m.S.dq_skin), (m.B as Body).ang])


func toggle() -> String:
	if is_on():
		m.ksc.stop()
		return String(m.ui_status.text) if m.get("ui_status") != null else ""
	return open()


func toggle_corrective() -> String:
	if sp == null:
		return "Model: open the pose sculpt first (Search \"Model: sculpt the body in pose\"), then turn the corrective mode on"
	sp.corrective = not sp.corrective
	return ("Model: sculpt in pose: strokes now go into a CORRECTIVE shape tied to the bent elbow / knee (the rest mesh stays as it is; the shape fades out as the joint straightens)"
		if sp.corrective else "Model: sculpt in pose: strokes now edit the REST mesh (every frame shows them)")


func open() -> String:
	if not BaseBody.is_open(m):
		return "Model: open the fighter's body first (Search \"Model: edit the body mesh\"), then sculpt it in pose"
	if m.get("ksc") == null:
		m.ksc = load("res://scripts/kmesh_sculpt_ui.gd").new()
		m.add_child(m.ksc)
		m.ksc.setup(m)
	if m.ksc.on:
		return "Model: leave the test sphere first (Esc), then sculpt the body in pose"
	var kmed = m.kmed
	var skin := BaseBody.skin_of(m)
	KMeshMask.ensure(kmed.mesh)   # the channel the sculpt UI makes, made on rest first: no undo step of its own
	var corr := sp.corrective if sp != null else false
	sp = SculptPose.new().setup(kmed.mesh, skin, m.skel)
	sp.corrective = corr
	sp.set_pose(float(m.S.dq_skin), KMeshShapes.body_inputs(m.B))
	sp.reskin()
	_sig = _pose_sig()
	undo = SculptPose.PoseUndo.new(sp)
	var ksc = m.ksc
	_sym = [ksc.sym_x, ksc.sym_y, ksc.sym_z, ksc.radial]
	ksc.sym_x = false
	ksc.sym_y = false
	ksc.sym_z = false
	ksc.radial = 1
	var at: Transform3D = kmed.view.transform
	var say := "Model: sculpting the body IN POSE (%s, %s): every stroke lands in the rest mesh, one undo step each%s. D C I S F P E G K brushes, M mask, W face sets, [ ] radius, Esc back to the model preview" % [
		"frame %d" % int(m.get("frame")) if m.get("frame") != null else "this frame", DqSkin.describe(sp.k), "; as a corrective" if sp.corrective else ""]
	ksc.source = func(): return {"mesh": sp.posed, "at": at, "undo": undo, "say": say}
	ksc.left = _leave
	kmed.on = false            # the preview keeps its state; its keys and clicks wait until Esc
	kmed.view.visible = false  # the posed body stands in for it
	ksc.start()
	return say


## Esc in the sculpt UI: the model preview back on the edited rest body, the strokes on its undo stack
func _leave() -> void:
	var ksc = m.ksc
	ksc.source = Callable()
	ksc.left = Callable()
	if _sym.size() == 4:
		ksc.sym_x = _sym[0]
		ksc.sym_y = _sym[1]
		ksc.sym_z = _sym[2]
		ksc.radial = _sym[3]
	var kmed = m.kmed
	var n := undo.steps.size() if undo != null else 0
	if kmed != null and kmed.view != null:
		kmed.on = true
		kmed.view.visible = true
		kmed.view.mark_dirty()
		if n > 0:
			kmed.undo.steps.append_array(undo.steps)   # the steps name the rest mesh: the preview's Ctrl+Z takes them back
			kmed.undo.redos.clear()
	undo = null
	m._say("Model: left the pose sculpt: %d stroke%s on the rest body (Ctrl+Z takes them back one by one); Search \"Model: apply the body mesh to the fighter\" writes it" % [n, "" if n == 1 else "s"])


## a new frame (or a new pose, the skinning switched): the edited rest is skinned again
func _process(_dt: float) -> void:
	if not is_on() or m.ksc._stroking:
		return
	var s := _pose_sig()
	if s == _sig:
		return
	_sig = s
	sp.set_pose(float(m.S.dq_skin), KMeshShapes.body_inputs(m.B))
	sp.reskin()
	reskins += 1
	m.ksc.view.mark_dirty()
