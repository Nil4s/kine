## LIVE WEBCAM PUPPET (roadmap 21: Nick poses the mannequin with his own body, in real time, and records it).
## THE LINK: this listens on 127.0.0.1 at a port it picks (listen), starts tools/live_pose.py with that port (spawn), and the
## script connects and sends one JSON line per camera frame: {"i", "t" (capture time, unix s), "w": 33 world landmarks in
## MediaPipe's layout, or null when no body is in view}. Nothing else crosses the socket, and nothing listens beyond this machine.
## THE POSE, per frame, the video import's own path (scripts/video_import.gd, the same tracker's layout):
##   each landmark's coordinate through a ONE EURO FILTER (Casiez, Roussel & Vogel, CHI 2012): a low cutoff while the body is
##   still (the tracker's jitter is gone) and a cutoff that rises with the landmark's speed (a fast move is not smeared)
##   VideoImport.fit: the pose only, from the rest pose; the hips stay at 0, so the person does not travel: he stands where he is
##   B.ground(): the lower sole on the floor
## THE TAKE: each fitted frame is kept while recording; record_stop turns them into a scene the way the video import does
## (VideoImport.to_scene, then thin every_for(fps)): one card per kept frame, a new file, never over one that exists.
## Commands, as main.gd wires them: "Live: start the webcam puppet" and "Live: record / stop".
class_name LivePuppet
extends RefCounted

const TOOL := "res://tools/live_pose.py"
# One Euro settings (scripts/live_one_euro.gd). Chosen by a sweep on walk_bat's exact landmarks: with a 1 Hz speed
# estimate the cutoff rises after a toe step, so the filter lagged 11 cm; a 10 Hz speed estimate with beta 30 brings the
# worst landmark to 2.3 cm, which is the fit's own 2.1 cm floor on that clip (beta 100 gave 2.16 cm but stops smoothing
# webcam jitter at 0.3 m/s). Still-body smoothing: cutoff 1 Hz.
const MIN_CUT := 1.0     # Hz: the cutoff while still
const BETA := 30.0       # Hz per m/s of a landmark's speed
const D_CUT := 10.0      # Hz: the smoothing of the speed estimate
const PORT_LO := 49152   # the dynamic port range: a port is picked at random from it, and another if it is taken
const PORT_HI := 65000
const WINDOW := 60       # frames the fps and latency readouts average over
const N_LM := 33

var rec_dir := UserPaths.w("res://scenes/_wip")   # where a take is kept (a test points it at user:// so it never writes scenes/)
var python := "python"               # the interpreter that has mediapipe + opencv-python (as the video import's)
var port := 0
var pid := -1
var running := false     # listening, and the tracker was started
var recording := false
var error := ""          # the tracker's last complaint (one line from tools/live_pose.py)
var ended := false       # the tracker has gone (its replay ended, its camera stopped, or it was closed)

var _server: TCPServer
var _peer: StreamPeerTCP
var _buf := ""
var _filters := []       # N_LM x 3 LiveOneEuro, one per coordinate
var _last_t := -1.0
var _take := []          # recorded frames: {"i", "t", "lm", "ang", "offset"}
var _lat := []           # camera-to-pose milliseconds, the last WINDOW frames
var _stamps := []        # msec the body was posed, the last WINDOW frames
var frames_posed := 0
var frames_lost := 0     # frames with no body in view (the pose is held)


## a port on 127.0.0.1 that nothing else holds: the listener is the only thing that ever binds it
func listen() -> bool:
	_server = TCPServer.new()
	for k in 60:
		var p := randi_range(PORT_LO, PORT_HI)
		if _server.listen(p, "127.0.0.1") == OK:
			port = p
			return true
	_server = null
	port = 0
	return false


## starts the tracker on the webcam. "" when it is starting, else the reason (the caller says it on the status line)
func start(tool_path: String, camera := 0, model := "D:/pose_models/pose_landmarker_heavy.task") -> String:
	return _start(tool_path, PackedStringArray(["--camera", str(camera), "--model", model]))


## the same socket and fit, fed a recorded pose file (tools/see_video.py's or export_landmarks.gd's) at real time: the test's
func start_replay(tool_path: String, file: String) -> String:
	return _start(tool_path, PackedStringArray(["--replay", file]))


func _start(tool_path: String, extra: PackedStringArray) -> String:
	stop()
	if not listen():
		return "could not open a local port on 127.0.0.1 (every port in the range is in use)"
	var args := PackedStringArray([tool_path, "--port", str(port)])
	args.append_array(extra)
	pid = OS.create_process(python, args)
	Children.add(pid)
	if pid < 0:
		var why := "\"%s\" did not start (it needs Python with mediapipe and opencv-python: run pip install mediapipe opencv-python)" % python
		stop()
		return why
	running = true
	ended = false
	error = ""
	return ""


## closes the socket, stops the tracker. A take in progress is dropped: record_stop first to keep it
func stop() -> void:
	if _peer != null:
		_peer.disconnect_from_host()
	if _server != null:
		_server.stop()
	if pid >= 0 and OS.is_process_running(pid):
		OS.kill(pid)
	Children.done(pid)
	pid = -1
	port = 0
	running = false
	recording = false
	ended = false
	_peer = null
	_server = null
	_buf = ""
	_filters = []
	_last_t = -1.0
	_take = []
	_lat = []
	_stamps = []


## one frame of the live loop: reads what the tracker has sent, fits every new frame to B (B is left posed at the last one)
## and returns the frames done this call, each {"i", "t", "lm" (the body's 33 landmarks, ours, hips at 0), "ang", "offset"}
func poll(B: Body) -> Array:
	var done := []
	if not running:
		return done
	if _peer == null and _server != null and _server.is_connection_available():
		_peer = _server.take_connection()
	if _peer == null:
		if pid >= 0 and not OS.is_process_running(pid):
			_gone("the tracker stopped before it connected")
		return done
	_peer.poll()
	if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:   # the tracker closed the socket: nothing to read (reading it is an engine error)
		_gone("")
		return done
	var n := _peer.get_available_bytes()
	if n > 0:
		var r := _peer.get_partial_data(n)
		if r[0] == OK:
			_buf += (r[1] as PackedByteArray).get_string_from_utf8()
	while true:
		var k := _buf.find("\n")
		if k < 0:
			break
		var line := _buf.substr(0, k).strip_edges()
		_buf = _buf.substr(k + 1)
		if line == "":
			continue
		var msg = JSON.parse_string(line)
		if not msg is Dictionary:
			continue
		if (msg as Dictionary).has("error"):
			error = str(msg["error"])
			continue
		var f := _frame(B, msg)
		if not f.is_empty():
			done.append(f)
	if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_gone("")
	return done


func _gone(why: String) -> void:
	ended = true
	if why != "" and error == "":
		error = why


func _frame(B: Body, msg: Dictionary) -> Dictionary:
	var w = msg.get("w")
	if not w is Array or (w as Array).size() < N_LM:
		frames_lost += 1
		return {}
	var t := float(msg.get("t", 0.0))
	var pts := []
	for p in w:
		pts.append(Vector3(float(p[0]), -float(p[1]), -float(p[2])))   # MediaPipe y down -> ours (VideoImport.parse's flip)
	if _filters.is_empty():
		for k in N_LM * 3:
			_filters.append(LiveOneEuro.new(MIN_CUT, BETA, D_CUT))
	var dt := (t - _last_t) if _last_t >= 0.0 else 1.0 / 30.0
	_last_t = t
	for k in N_LM:
		var v: Vector3 = pts[k]
		var fx := _filters[3 * k] as LiveOneEuro
		var fy := _filters[3 * k + 1] as LiveOneEuro
		var fz := _filters[3 * k + 2] as LiveOneEuro
		pts[k] = Vector3(fx.step(v.x, dt), fy.step(v.y, dt), fz.step(v.z, dt))
	VideoImport.fit(B, pts)
	B.offset = Vector3.ZERO
	B.fk()
	B.ground()
	var ang := {}
	for j in Body.BODY:
		ang[j] = B.ang[j]
	var f := {"i": int(msg.get("i", -1)), "t": t, "lm": VideoImport.landmarks_of(B), "ang": ang, "offset": B.offset}
	frames_posed += 1
	_lat.append(Time.get_unix_time_from_system() * 1000.0 - t * 1000.0)
	_stamps.append(Time.get_ticks_msec())
	if _lat.size() > WINDOW:
		_lat.pop_front()
		_stamps.pop_front()
	if recording:
		_take.append(f)
	return f


## the body's posing rate over the last WINDOW frames, and the camera-to-pose latency (mean, worst) in ms
func fps() -> float:
	if _stamps.size() < 2:
		return 0.0
	var span := float(_stamps[-1] - _stamps[0])
	return (_stamps.size() - 1) * 1000.0 / span if span > 0.0 else 0.0


func latency_ms() -> Array:
	if _lat.is_empty():
		return [0.0, 0.0]
	var s := 0.0
	var worst := 0.0
	for x in _lat:
		s += x
		worst = maxf(worst, x)
	return [s / _lat.size(), worst]


func record_start() -> void:
	_take = []
	recording = true


## stops the take and keeps it as a NEW scene in rec_dir: VideoImport.to_scene, then thinned as the video import does.
## Returns {"ok", "path", "cards", "frames", "fps", "why"}. Nothing is written for a take of under two frames
func record_stop(B: Body, name := "live_webcam") -> Dictionary:
	recording = false
	var n := _take.size()
	if n < 2:
		_take = []
		return {"ok": false, "why": "the take has %d frame(s): nothing to keep" % n, "path": "", "cards": 0, "frames": n, "fps": 0.0}
	var span := float(_take[-1]["t"]) - float(_take[0]["t"])
	var fps := (n - 1) / span if span > 0.0 else 30.0
	var V := VideoImport.to_scene(B, _take, fps, 1, name)
	# the video import's even spacing, REFINED as the FBX import refines it (AnimImport.refine: the frame the cards would
	# blend worst is kept, until every angle is within 1 deg and the hips within 5 mm of the straight blend)
	var every := VideoImport.every_for(V.fps)
	V = VideoImport.thin(V, every, AnimImport.refine(V, every))
	var d: Dictionary = V.to_dict(B)
	d["plan"] = "Live webcam take: %d frames in %.1f s (%.1f fps), tracked by MediaPipe (tools/live_pose.py) and fitted by VideoImport; %d cards" % [n, span, fps, V.cards.size()]
	var path := unique_path(rec_dir, name)
	var wrote := write(path, d)
	_take = []
	return {"ok": wrote, "why": "" if wrote else "could not write %s" % path, "path": path if wrote else "",
		"cards": V.cards.size(), "frames": n, "fps": fps}


## a path in dir that no file has yet: name.json, name_2.json ... (an earlier take is never overwritten)
static func unique_path(dir: String, base: String) -> String:
	var out := "%s/%s.json" % [dir, base]
	var k := 2
	while FileAccess.file_exists(out):
		out = "%s/%s_%d.json" % [dir, base, k]
		k += 1
	return out


static func write(path: String, d: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(d, " "))
	f.close()
	return true
