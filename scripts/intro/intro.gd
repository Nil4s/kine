## THE OPENING INTRO (Nick 10-23): when Kine opens, the K is made in front of you and lands as the logo, "Kine" types in,
## "Teschima Studios" settles underneath, and it fades into the app. Three concepts to choose from:
##   A  MODELED      a block in the dark viewport is scaled, extruded and its verts snapped into the 3D stencil K, as on the
##                   MODEL page; the camera settles front-on and the K flattens into the mark (scripts/intro/intro_modeled.gd)
##   B  JOINT CHAIN  a two-bone leg chambers and strikes; its trails freeze, the bones snap into the chevron, the spine grows
##                   into the stem and the gold centre of mass lands on the knee (scripts/intro/intro_chain.gd)
##   C  LINE OF ACTION  a pen sketches one gesture curve and a stroke; they snap straight to 45 deg, thicken into the stencil
##                   and the pen's gold nib becomes the diamond (scripts/intro/intro_sketch.gd)
## Real time, drawn as geometry (crisp at any size, no video file). main.gd adds it at the end of the start, OVER the
## finished app, so it never delays loading: any key or click takes it away at once (that event goes no further).
## Settings file [intro]: show = true / false, concept = "B" (default; Nick picked it 10-23) / "A" / "C". Command line: --intro B (this run, that one),
## --no-intro. Never in a test (main.gd's `testing`), headless, a --shot or a --tour run. A dialog that opens under it
## (unsaved work found) cuts it to its fade.
class_name KineIntro
extends CanvasLayer

signal finished

const CONCEPTS := ["A", "B", "C"]
const BUILD := 1.0   # the end card: slide, letters, dot, studio line
const HOLD := 0.3
const CLEAR := 0.22   # the end card fades to the bare background first: no frame shows the app through the logo
const FADE := 0.32   # then the background lets the app through
const MAX_STEP := 0.05   # a long frame (the first one after loading) does not skip animation

var concept := "B"
var t := 0.0
var play: RefCounted   # the concept: paint(ci, t, L), the time it hands over the flat mark (mark_at)
var group: CanvasGroup
var canvas: Node2D
var last := {}   # what the end card drew last frame (screen rects): the placement checks read it
var _started := false
var _done := false


## the intro, if this start should have one
static func wanted(cf: ConfigFile, testing: bool, args: PackedStringArray) -> bool:
	if testing or DisplayServer.get_name() == "headless":
		return false
	for a in ["--shot", "--tour", "--no-intro"]:
		if args.has(a):
			return false
	if args.has("--intro"):
		return true
	return cf == null or bool(cf.get_value("intro", "show", true))


static func concept_from(cf: ConfigFile, args: PackedStringArray) -> String:
	var i := args.find("--intro")
	var c := String(args[i + 1]).to_upper() if i >= 0 and i + 1 < args.size() else ""
	if c not in CONCEPTS and cf != null:
		c = String(cf.get_value("intro", "concept", "B")).to_upper()
	return c if c in CONCEPTS else "B"


## main.gd's one hook: plays over `host` when wanted, returns it (or null)
static func maybe_start(host: Node, cf: ConfigFile, testing: bool) -> KineIntro:
	var args := OS.get_cmdline_user_args()
	if not wanted(cf, testing, args):
		return null
	var k := make(concept_from(cf, args))
	host.add_child(k)
	return k


static func make(c: String) -> KineIntro:
	var k: KineIntro = load("res://scenes/intro/intro.tscn").instantiate()
	k.concept = c if c in CONCEPTS else "B"
	return k


func _ready() -> void:
	name = "intro"
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_play()
	group = CanvasGroup.new()   # fades as ONE picture: overlapping shapes never show through each other
	add_child(group)
	canvas = Node2D.new()
	canvas.draw.connect(_paint)
	group.add_child(canvas)


func _ensure_play() -> void:
	if play != null:
		return
	match concept:
		"B":
			play = IntroChain.new()
		"C":
			play = IntroSketch.new()
		_:
			play = IntroModeled.new()


func mark_at() -> float:
	_ensure_play()
	return play.mark_at()


func length() -> float:
	return mark_at() + BUILD + HOLD + CLEAR + FADE


func _process(delta: float) -> void:
	if _done:
		return
	if _started:
		t += minf(delta, MAX_STEP)
	_started = true
	if _dialog_up():
		t = maxf(t, mark_at() + BUILD + HOLD)
	if t >= length():
		_finish()
		return
	var f := IntroArt.k(t, length() - FADE, length())
	group.self_modulate.a = 1.0 - IntroArt.in_out_cubic(f)
	var vs := _size()
	var push := 1.0 + 0.035 * IntroArt.in_cubic(f)   # a small push in as it lets go
	canvas.position = vs * 0.5 * (1.0 - push)
	canvas.scale = Vector2(push, push)
	canvas.queue_redraw()


func _paint() -> void:
	var vs := _size()
	canvas.draw_rect(Rect2(Vector2.ZERO, vs), IntroArt.BG)
	var L := IntroArt.layout(vs)
	if t < mark_at():
		play.paint(canvas, t, L)
		last = {}
	else:
		last = IntroArt.draw_end(canvas, L, t - mark_at())
		var clear := IntroArt.in_out_cubic(IntroArt.k(t, length() - FADE - CLEAR, length() - FADE))
		if clear > 0.0:
			canvas.draw_rect(Rect2(Vector2.ZERO, vs), Color(IntroArt.BG, clear))


func _size() -> Vector2:
	return get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1600, 900)


## any key, mouse button, touch or pad button: gone this frame, and the event stops here
func _input(event: InputEvent) -> void:
	if _done:
		return
	var press: bool = (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventScreenTouch and event.pressed) or (event is InputEventJoypadButton and event.pressed)
	if press:
		get_viewport().set_input_as_handled()
		skip()


func skip() -> void:
	_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	visible = false
	set_process(false)
	finished.emit()
	queue_free()


func _dialog_up() -> bool:
	for w in get_viewport().get_embedded_subwindows():
		if (w as Window).visible:
			return true
	return false
