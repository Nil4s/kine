## LIVE WEBCAM PUPPET, WITHOUT A CAMERA (roadmap 21: godot --path . -s tests/live_puppet_test.gd, a window; tools/run_all.sh live_puppet)
## walk_bat's 33 landmarks (read only, from scenes/walk_bat.json) stream to the window as tools/live_pose.py --replay sends a
## recorded pose: real time, over the socket LivePuppet listens on, the way a webcam would send them. Checks:
##   1 the socket is on 127.0.0.1 only: netstat shows the port LISTENING on 127.0.0.1 and nowhere else
##   2 the body follows the source: every landmark within 2 cm of the source, after the filter's delay (the delay is found, in ms)
##   3 recording keeps the take as a new scene that replays it within 2 cm of what the body showed
##   4 a take never overwrites a file (unique_path)
##   5 the tracker is gone once its replay ends
extends SceneTree

const WALK := "res://scenes/walk_bat.json"   # READ ONLY
const FPS := 30.0
const TOL := 0.02       # m: the bar
const SETTLE := 8       # frames (a quarter second): the filter's start-up is not judged
const REC_DIR := "user://live_test"

var fails := 0
var B: Body
var live := LivePuppet.new()
var src := []           # walk_bat's landmarks per frame, ours (hips at 0)
var got := {}           # the tracker's frame index -> the frame LivePuppet returned
var n_frames := 0
var state := 0
var elapsed := 0.0
var pid := -1
var rec := {}
var rec_scene: Scene
var replay_path := ""


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	B = Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string(WALK)))
	n_frames = int(S.length() * FPS) + 1
	var frames := []
	for i in n_frames:
		S.apply(B, minf(i / FPS, S.length()))
		B.fk()
		var lm: Array = VideoImport.landmarks_of(B)
		src.append(lm)
		# MediaPipe's layout (y and z negated back), rounded to 0.1 mm as tools/live_pose.py rounds the tracker's
		var w := []
		for p in lm:
			w.append([snappedf(p.x, 0.0001), snappedf(-p.y, 0.0001), snappedf(-p.z, 0.0001)])
		frames.append({"t": snappedf(i / FPS, 0.0001), "world": w})
	replay_path = "user://live_src_test.json"
	FileAccess.open(replay_path, FileAccess.WRITE).store_string(JSON.stringify({"fps": FPS, "frames": frames}))
	# takes from an earlier run are cleared first, so the name check starts from nothing
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REC_DIR))
	var old := DirAccess.open(REC_DIR)
	for f in old.get_files():
		old.remove(f)
	live.rec_dir = REC_DIR
	print("walk_bat: %d frames at 30 fps (%.2f s) -> %s" % [n_frames, S.length(), replay_path])


## the socket: the port is LISTENING on 127.0.0.1 and on no other address (netstat, Windows)
func _bind_check(port: int) -> void:
	var out := []
	OS.execute("netstat", ["-an", "-p", "TCP"], out)
	var here := false
	var elsewhere := false
	for line in str(out[0]).split("\n"):
		var parts := line.strip_edges().split(" ", false)
		if parts.size() < 4 or parts[parts.size() - 1] != "LISTENING":
			continue
		var local: String = parts[1]
		if local == "127.0.0.1:%d" % port:
			here = true
		elif local.ends_with(":%d" % port):
			elsewhere = true
	ok(here and not elsewhere, "the socket listens on 127.0.0.1:%d only (netstat: here %s, anywhere else %s)" % [port, here, elsewhere])


func _process(delta: float) -> bool:
	elapsed += delta
	if state == 0:
		var why := live.start_replay(ProjectSettings.globalize_path(LivePuppet.TOOL), ProjectSettings.globalize_path(replay_path))
		ok(why == "", "the tracker starts and the socket opens (%s)" % (why if why != "" else "port %d" % live.port))
		if why != "":
			return true
		_bind_check(live.port)
		pid = live.pid
		live.record_start()
		state = 1
		return false
	if state == 1:
		for f in live.poll(B):
			got[int(f["i"])] = f
		if got.size() >= n_frames or (live.ended and elapsed > 1.0) or elapsed > 40.0:
			state = 2
			print("tracking: %d of %d frames in %.2f s; ended %s; %s" % [got.size(), n_frames, elapsed, live.ended, live.error])
			print("camera-to-pose latency (mean, worst) %.1f ms, %.1f ms; posed %.1f fps" % [live.latency_ms()[0], live.latency_ms()[1], live.fps()])
		return false
	if state == 2:
		_judge_tracking()
		rec = live.record_stop(B, "live_webcam")
		var rok: bool = rec["ok"]
		ok(rok and str(rec["path"]).begins_with(REC_DIR), "the take is kept as a new scene (%s, %d cards from %d frames)" % [rec["path"], rec["cards"], rec["frames"]])
		if rok:
			_judge_take(String(rec["path"]))
			var nxt := LivePuppet.unique_path(REC_DIR, "live_webcam")
			ok(nxt.ends_with("live_webcam_2.json"), "a second take of the same name does not overwrite the first (next free name %s)" % nxt.get_file())
		state = 3
		return false
	if state == 3:
		if elapsed < 2.0:
			return false
		ok(not OS.is_process_running(pid), "the tracker exited once its replay ended")
		live.stop()
		print("%s: %d fails" % ["PASS" if fails == 0 else "FAIL", fails])
		return true
	return true


## 2: the body's landmarks against the source, for every delay of the filter from 0 to 10 frames: the delay that fits best is the
## filter's lag (reported in ms); the bar is that landmark's error at that delay, every landmark, every frame after SETTLE
func _judge_tracking() -> void:
	var best_d := 0
	var best_mean := INF
	var rows := []
	for d in 11:
		var sum := 0.0
		var worst := 0.0
		var k := 0
		for i in range(SETTLE, n_frames):
			if not got.has(i) or i - d < 0:
				continue
			var lm: Array = got[i]["lm"]
			for j in 33:
				var e: float = (lm[j] as Vector3).distance_to(src[i - d][j])
				sum += e
				worst = maxf(worst, e)
				k += 1
		var mean := sum / maxf(1.0, k)
		rows.append("  delay %d frames (%d ms): mean %.2f cm, worst %.2f cm" % [d, d * 1000.0 / FPS, mean * 100.0, worst * 100.0])
		if mean < best_mean:
			best_mean = mean
			best_d = d
	print("\n".join(rows))
	var worst_best := 0.0
	var at := ""
	for i in range(SETTLE, n_frames):
		if not got.has(i) or i - best_d < 0:
			continue
		var lm: Array = got[i]["lm"]
		for j in 33:
			var e: float = (lm[j] as Vector3).distance_to(src[i - best_d][j])
			if e > worst_best:
				worst_best = e
				at = "frame %d landmark %d" % [i, j]
	ok(worst_best <= TOL, "the body matches the source within 2 cm after the filter's delay of %d ms: mean %.2f cm, worst %.2f cm (%s)"
		% [best_d * 1000.0 / FPS, best_mean * 100.0, worst_best * 100.0, at])


## 3: the scene the take became, replayed at each frame's time, against the landmarks the body showed for that frame
func _judge_take(path: String) -> void:
	rec_scene = Scene.new()
	rec_scene.from_dict(JSON.parse_string(FileAccess.get_file_as_string(path)))
	var Bc := Body.new()
	Bc.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var worst := 0.0
	var at := ""
	var n := 0
	for i in range(SETTLE, n_frames):
		if not got.has(i):
			continue
		rec_scene.apply(Bc, minf(i / FPS, rec_scene.length()))
		Bc.fk()
		var lm: Array = VideoImport.landmarks_of(Bc)
		var shown: Array = got[i]["lm"]
		for j in 33:
			var e: float = (lm[j] as Vector3).distance_to(shown[j])
			if e > worst:
				worst = e
				at = "frame %d landmark %d" % [i, j]
		n += 1
	ok(worst <= TOL, "the scene replays the take within 2 cm of what the body showed, %d frames: worst %.2f cm (%s), %d cards" % [n, worst * 100.0, at, rec_scene.cards.size()])
