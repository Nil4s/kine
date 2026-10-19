## REAL SPEED / EVERY FRAME (ROADMAP 48). The playback clock: how far the playhead moves on each rendered frame.
## REAL SPEED: the playhead moves by the wall-clock time since the last frame, so the scene keeps real time. A slow
##   machine skips scene frames: each frame index a step jumps over (and does not show) is a DROPPED frame.
## EVERY FRAME: each scene frame is shown once, in order. The playhead moves one frame index per rendered frame, once a
##   frame's period (1 / fps) of wall time has been spent. On a slow machine it runs below real time (speed < 1) and
##   nothing is skipped; on a fast one it waits, so it never runs above real time.
## A VIEW setting: not saved in the scene, not an undo step. The pass counters (dropped, shown, wall) restart each time
## Play starts or the mode changes.
class_name PlaySpeed
extends RefCounted

const REAL := "real"
const EVERY := "every"
const MODES := [REAL, EVERY]
const EPS := 1e-6   # frames: a time this close to a whole frame counts as on it

var mode := REAL
var dropped := 0   # real: scene frame indices a step jumped over this pass
var shown := 0     # every: frame indices the playhead moved onto this pass
var wall := 0.0    # s of wall time this pass (the frame deltas while playing)
var _acc := 0.0    # every: wall time spent since the last frame was shown
var _fps := 0


static func next_mode(cur: String) -> String:
	return MODES[(MODES.find(cur) + 1) % MODES.size()]


## the words on the bar: "Real speed", "Real speed: dropping 3 frames", "Every frame: 0.6x speed" ("Every frame" before
## any frame has been timed). The speed is the scene time shown per second of wall time.
static func label(m: String, n_dropped: int, speed: float) -> String:
	if m == REAL:
		return "Real speed" if n_dropped <= 0 else "Real speed: dropping %d frames" % n_dropped
	return "Every frame" if speed <= 0.0 else "Every frame: %.1f× speed" % speed


func start(m: String) -> void:
	mode = m if m in MODES else REAL
	dropped = 0
	shown = 0
	wall = 0.0
	_acc = 0.0


## the speed of this pass: scene seconds shown per wall second (1.0 = real time). 0 until a frame has been timed.
func speed() -> float:
	if wall <= 0.0 or _fps <= 0:
		return 0.0
	return float(shown) / float(_fps) / wall


func label_now() -> String:
	return label(mode, dropped, speed())


## one rendered frame: moves t by what this mode allows and returns PreviewRange.tick's {"t", "stop"}.
## dt is the wall time since the last frame (seconds); fps the scene's frame rate.
func advance(t: float, dt: float, fps: int, length: float, pv_in: float, pv_out: float, loop: bool) -> Dictionary:
	_fps = fps
	wall += maxf(dt, 0.0)
	var step := dt
	if mode == EVERY:
		step = _every_step(dt, fps)
	var r := PreviewRange.tick(t, step, length, pv_in, pv_out, loop)
	var nt: float = r["t"]
	if mode == REAL and nt > t:
		# the frame indices reached by this step, less the one that is shown: the rest were skipped
		var reached := floori(nt * fps + EPS) - floori(t * fps + EPS)
		dropped += maxi(reached - 1, 0)
	if mode == EVERY and step > 0.0 and absf(nt - t) > EPS:
		shown += 1
	return r


## EVERY FRAME's step: one frame period once the wall time owed to the next frame has been spent, else nothing.
## Behind real time the owed time is not carried over (a frame that took long shows the next frame, not two),
## so every index is shown once and in order.
func _every_step(dt: float, fps: int) -> float:
	if fps <= 0:
		return 0.0
	var period := 1.0 / float(fps)
	_acc += maxf(dt, 0.0)
	if _acc < period - EPS:
		return 0.0
	_acc -= period
	if _acc >= period - EPS:
		_acc = 0.0
	return period
