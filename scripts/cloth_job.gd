## cloth_job.gd - ROADMAP 86b: a cape bake that does not freeze the UI.
##
## TWO STAGES. (0) SAMPLING, on the main thread in small slices (sample_for, a time budget per call): the scene is cloned
## and the clone's body is moved frame by frame (S.apply), so the UI's own scene and body are never touched; it is the only
## stage that runs the scene. (1) SIMULATION, on a WorkerThreadPool task: Cloth.simulate is pure math on the arrays the
## sampling made, it touches no node and no Body. The worker reports progress and checks for a cancel through this object
## (a Mutex guards both). The main thread polls: when the task is done it takes the result on its own thread.
##
## THE SCENE KEEPS ITS LAST GOOD CAPE until a result is applied (main.gd applies it in one undo step). Cancel stops it at
## the next frame of the sim, and the partial result is dropped.
class_name ClothJob
extends RefCounted

var mutex := Mutex.new()
var _progress := 0.0      # 0..1 of the whole bake (the sim's share is reported by the worker)
var _cancel := false
var _done := false
var _result: Dictionary = {}

var owner: Scene          # the scene the bake is for (main.gd applies the result only while it is still the open scene)
var S: Scene              # the clone the sampling moves
var B: Body
var n := 0                # frames
var fps := 30
var k := 0                # frames sampled so far
var A: Array = []
var C: Array = []
var rads := PackedFloat64Array()
var stage := 0            # 0 = sampling (main thread), 1 = simulating (worker), 2 = done
var task := -1


## a new bake of scene src over its frames, with a private clone and body
static func start(src: Scene) -> ClothJob:
	var j := ClothJob.new()
	j.owner = src
	j.S = src.clone()
	j.B = Body.new()
	j.B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	j.B.fk()
	j.fps = src.fps
	j.n = maxi(int(ceil(src.length() * float(src.fps) - 1e-6)), 1) + 1
	j.rads = Cloth.radii(j.B, j.B.cap0.keys())
	return j


## the sampling for at most budget_usec on this thread. True when every frame is sampled
func sample_for(budget_usec: int) -> bool:
	var end := Time.get_ticks_usec() + budget_usec
	var names: Array = B.cap0.keys()
	var length := S.length()
	while k < n and Time.get_ticks_usec() < end:
		S.apply(B, minf(float(k) / float(fps), length))
		B.fk()
		A.append(Cloth.anchors(B))
		C.append(Cloth.caps_of(B, names))
		k += 1
		_set_progress(0.3 * float(k) / float(n))
	return k >= n


## starts the sim on a worker thread (after every frame is sampled)
func start_sim() -> void:
	stage = 1
	task = WorkerThreadPool.add_task(_run)


## the worker's body: the sim, then the result (or nothing, if cancelled)
func _run() -> void:
	var r := Cloth.simulate(A, C, rads, fps, self)
	mutex.lock()
	_result = r
	_done = true
	mutex.unlock()


## main thread: advances the stage. Returns the stage (2 = finished; then take_result)
func poll() -> int:
	if stage == 1 and task >= 0 and WorkerThreadPool.is_task_completed(task):
		WorkerThreadPool.wait_for_task_completion(task)   # already complete: returns at once
		stage = 2
		_set_progress(1.0)
	return stage


## the cape, once stage is 2. Empty when the bake was cancelled. Name and frames are complete here
func take_result() -> Dictionary:
	if _cancel or _result.is_empty():
		return {}
	var out := _result.duplicate()
	out["name"] = "cape"
	return out


## the whole bake's progress (0..1), read from any thread
func progress() -> float:
	mutex.lock()
	var f := _progress
	mutex.unlock()
	return f


## asks the bake to stop: the sampling stops at once, the worker at its next frame
func cancel() -> void:
	mutex.lock()
	_cancel = true
	mutex.unlock()


## the worker asks this every frame (Cloth.simulate calls ctl.cancelled())
func cancelled() -> bool:
	mutex.lock()
	var c := _cancel
	mutex.unlock()
	return c


## the worker reports the sim's fraction (0..1): the whole bake is 30 % sampling, 70 % sim
func report(f: float) -> void:
	_set_progress(0.3 + 0.7 * f)


func _set_progress(f: float) -> void:
	mutex.lock()
	_progress = f
	mutex.unlock()
