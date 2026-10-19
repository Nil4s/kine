## MOTION MATCHING PREVIEW (ROADMAP 33; the maths and the database: scripts/motion_match.gd). Kept out of main.gd: main
## makes one of these (main.mm_ui), lists its commands and calls tick() each frame.
##   "Motion matching: preview"          toggles the preview. W / A / S / D steer the target (forward, left, back, right);
##                                       hold Shift to run. The body plays the nearest frame of your scenes, cross-faded
##                                       over 0.2 s, searched every 0.1 s. The status line shows the clip, the frame, the
##                                       match cost (good = at most 1.0 sd) and whether it is a good match.
##                                       The root moves by the clip's own root motion; the heading is held (no turning).
##   "Motion matching: coverage report"  the directions and speeds with no good match: the clips to add (the list is
##                                       printed to the console too).
## Read only: the database is built from scenes/ and moves/ (about 20 s, once) and kept until the app closes.
class_name MotionMatchUI
extends RefCounted

const WALK := 1.0   # m/s: the preview's walk (inside the coverage: the walk's forward speeds are good)
const RUN := 2.0    # m/s: with Shift (the coverage report says where this is a gap)

var m: Node         # main.gd
var db: Dictionary = {}
var player: MotionMatch.Player = null
var _acc := 0.0     # s since the status line was written


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Motion matching: preview", "", toggle, "motion matching preview wasd steer locomotion blend trajectory game controller run walk",
		false, "steer a target with W A S D (Shift runs): the body plays the nearest frame of your scenes, cross-fading every 0.1 s; the status line shows the clip, the frame and the match cost (your scenes are only read)")
	add.call("Motion matching: coverage report", "", coverage_report, "motion matching coverage gaps report directions speeds clips missing",
		false, "which directions and speeds have no good match in your scenes (cost above 1.0 sd): the clips to add")


## the database, built once (about 20 s for Nick's scenes: each frame is applied through the whole rig)
func _database() -> bool:
	if int(db.get("n", 0)) == 0:
		m._say("motion matching: reading your scenes (once, about 20 s)...")
		db = MotionMatch.build()
	return int(db.get("n", 0)) > 0


func toggle() -> void:
	if player != null:
		player = null
		m._ps().apply(m.B, m.playhead)   # the scene at the playhead again
		m._refresh()
		m._say("motion matching preview: off")
		return
	if not _database():
		m._say("motion matching: none of your scenes has cards to match")
		return
	m.playing = false
	player = MotionMatch.Player.new(db, 0)
	_acc = 1.0
	m._say("motion matching preview: W A S D steer, Shift runs; toggle it again to stop")


func tick(dt: float) -> void:
	if player == null:
		return
	var fo: Control = m.get_viewport().gui_get_focus_owner()
	var typing: bool = fo is LineEdit or fo is SpinBox
	var x := 0.0
	var z := 0.0
	if not typing:
		x = float(Input.is_key_pressed(KEY_A)) - float(Input.is_key_pressed(KEY_D))   # A = the hero's left, +X
		z = float(Input.is_key_pressed(KEY_W)) - float(Input.is_key_pressed(KEY_S))
	var running := Input.is_key_pressed(KEY_SHIFT)
	var want := Vector3(x, 0.0, z)
	if want.length() > 0.0:
		want = want.normalized() * (RUN if running else WALK)
	var out: Dictionary = player.step(dt, want)
	var ang: PackedVector3Array = out["ang"]
	var B: Body = m.B
	for k in Body.ORDER.size():
		B.ang[Body.ORDER[k]] = ang[k]
	B.offset = out["offset"]
	B.fk()
	m._refresh()
	_acc += dt
	if _acc >= 0.25:
		_acc = 0.0
		m._say("MOTION MATCH  %s  frame %d  cost %.2f sd %s  (%s, %d searches, last %.2f ms, %d switches)" % [
			out["clip"], out["frame"], out["cost"], "good" if out["good"] else "NO GOOD MATCH: add a clip for this",
			"running" if running else "walking", player.searches, out["ms"], out["switches"]])


func coverage_report() -> void:
	if not _database():
		m._say("motion matching: none of your scenes has cards to match")
		return
	var cov := MotionMatch.coverage(db)
	print(cov["text"])
	var gaps: Array = cov["gaps"]
	var rows: Array = cov["rows"]
	var first := ""
	for k in mini(3, gaps.size()):
		var g: Dictionary = gaps[k]
		first += "%.1f m/s %d deg (cost %.1f); " % [g["speed"], int(g["deg"]), g["cost"]]
	m._say("motion matching coverage: %d of %d queries have a good match; %d gaps (worst cost %.1f sd). Gaps: %s(full list in the console)" % [
		rows.size() - gaps.size(), rows.size(), gaps.size(), cov["worst"], first])
