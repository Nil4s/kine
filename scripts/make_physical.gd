## MAKE IT PHYSICAL (ROADMAP Innovations I1; tools/physics/judge.py is the judge). The CHECK page's "Make it physical":
##   1. clip_dict(): the scene sampled at 30 fps as joint angles + the pelvis (what judge.py reads), written under user://make_physical/.
##   2. begin(): plain `python judge.py clip out --progress file` as a child process (OS.create_process, like the video import and
##      R13's worker: the window keeps drawing); poll() reads the progress file and, when the process ends, the result.
##   3. The result: red spans with a reason each (airborne / outside force / torque / foot slide / falls), yellow notes (the clip's own
##      authored foot slide) and the PHYSICAL version of every frame (the same joints, tracked by a 75 kg body in MuJoCo).
##   4. ghost_pose(): the physical body at a time, for the ghost mannequin you scrub with the playhead.
##   5. accept(): the cards inside one red span are replaced by the physical version keyed at card density (the scene's own median
##      gap between cards, never denser than 0.1 s); the cards outside, and the time of everything after, are untouched.
## Files only under user:// (policy in tests/confirm_test.gd).
class_name MakePhysical
extends RefCounted

const DIR := "user://make_physical"
const FPS := 30

var pid := -1
var out_path := ""
var prog_path := ""
var progress := 0.0
var done := false
var failed := ""
var spans: Array = []      # red: [{"f0","f1","t0","t1","kind","reason"}]
var notes: Array = []      # yellow: the clip's own authored slide
var summary := {}
var phys: Array = []       # per frame {"pelvis": [x,y,z], "ang": {joint: [bend, side, twist]}}
var offs: Array = []       # per frame: the clip's own pelvis offset (Vector3) and position (Vector3), to turn the physical pelvis into an offset
var fps := FPS
var t_started := 0
var judged := []          # A1: the cards as the judge read them (see _sim); [] = no finished judge on this scene
var judged_scene: Scene = null
var judged_len := 0.0     # A1: the clip's length the judge read
var _pending := {}        # A1: the same three, taken when the judge starts; they become `judged` when its result lands
var tweak := Callable()   # TESTS ONLY: f(frames, offs) edits the sampled clip before it is judged (the app cannot author a hover: it grounds the body)


## the scene as the judge wants it: {"fps", "frames": [{"t", "pelvis": [x,y,z], "ang": {j: [bend, side, twist]}}]}
func clip_dict(S: Scene, Bx: Body) -> Dictionary:
	var n := int(ceil(S.length() * FPS - 1e-6)) + 1
	var frames := []
	offs = []
	for i in n:
		var t := minf(float(i) / FPS, S.length())
		S.apply(Bx, t)
		Bx.fk()
		var ang := {}
		for j in Body.ORDER:
			var v: Vector3 = Bx.ang[j]
			ang[j] = [v.x, v.y, v.z]
		var pp: Vector3 = Bx.P["pelvis"]
		frames.append({"t": t, "pelvis": [pp.x, pp.y, pp.z], "ang": ang})
		offs.append([Bx.offset, pp])
	if tweak.is_valid():
		tweak.call(frames, offs)
	return {"fps": FPS, "frames": frames}


## write the clip and start the judge. "" = started; else the sentence to say (what to do next)
func begin(S: Scene, Bx: Body, python := "python") -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	var keep := Bx.state()
	var clip := clip_dict(S, Bx)
	Bx.set_state(keep)
	var cp := ProjectSettings.globalize_path(DIR.path_join("clip.json"))
	out_path = ProjectSettings.globalize_path(DIR.path_join("result.json"))
	prog_path = ProjectSettings.globalize_path(DIR.path_join("progress.txt"))
	for p in [out_path, prog_path]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	var f := FileAccess.open(cp, FileAccess.WRITE)
	if f == null:
		return "could not write the clip under the user folder: check that the disk is not full, then press Make it physical again"
	f.store_string(JSON.stringify(clip))
	f.close()
	var tool := ProjectSettings.globalize_path("res://tools/physics/judge.py")
	pid = OS.create_process(python, PackedStringArray([tool, cp, out_path, "--progress", prog_path]))
	Children.add(pid)
	done = false
	failed = ""
	progress = 0.0
	t_started = Time.get_ticks_msec()
	if pid >= 0:
		_pending = {"scene": S, "cards": S.cards.map(func(c): return _sim(c)), "len": S.length()}
	if pid < 0:
		return "could not start Python (\"%s\"): install Python 3 with mujoco and scipy (pip install mujoco scipy), then press Make it physical again" % python
	return ""


## each frame: true when the result has just arrived
func poll() -> bool:
	if pid < 0 or done:
		return false
	if FileAccess.file_exists(prog_path):
		progress = clampf(FileAccess.get_file_as_string(prog_path).to_float(), 0.0, 1.0)
	if OS.is_process_running(pid):
		return false
	Children.done(pid)
	pid = -1
	return load_result(out_path)


## read a result file (also used by the test with a precomputed one)
func load_result(path: String) -> bool:
	done = true
	judged = []
	judged_scene = null
	if not FileAccess.file_exists(path):
		failed = "the judge ended without a result: run `python tools/physics/judge.py` by hand to see why (it needs mujoco and scipy)"
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary):
		failed = "the judge's result could not be read: press Make it physical again"
		return false
	judged = _pending.get("cards", [])
	judged_scene = _pending.get("scene", null)
	judged_len = float(_pending.get("len", 0.0))
	_pending = {}
	spans = d.get("spans", [])
	notes = d.get("notes", [])
	summary = d.get("summary", {})
	phys = d.get("physical", [])
	fps = int(d.get("fps", FPS))
	return true


func stop() -> void:
	if pid >= 0 and OS.is_process_running(pid):
		OS.kill(pid)
	Children.done(pid)
	pid = -1


func running() -> bool:
	return pid >= 0 and not done


## a card as the judge sees it: the priority flag ("keep", Keep this pose) is not physics, so it is not part of the key
static func _sim(c: Dictionary) -> Dictionary:
	var d := c.duplicate(true)
	d.erase("keep")
	return d


## the lane's blocks for the timeline: [{"t0","t1","kind","reason","yellow","tone"}]. tone: red (no solution, the one you can pick),
## yellow (the clip's own slide, a note), blue (a card edited since the judge read it), gray (not processed yet)
func lane(S: Scene) -> Array:
	var out := []
	for s in spans:
		out.append({"t0": float(s["t0"]), "t1": float(s["t1"]), "kind": s["kind"], "reason": s["reason"], "yellow": false, "tone": "red"})
	for s in notes:
		out.append({"t0": float(s["t0"]), "t1": float(s["t1"]), "kind": s["kind"], "reason": s["reason"], "yellow": true, "tone": "yellow"})
	if S == null or judged_scene != S:
		return out
	var ts: Array = S.times()
	for i in S.cards.size():
		if i < judged.size() and _sim(S.cards[i]) == judged[i]:
			continue
		out.append({"t0": float(ts[i][0]), "t1": float(ts[i][2]), "kind": "edited", "reason": "edited since the last physics run: not simulated yet (Make it physical checks it)", "yellow": false, "tone": "blue"})
	var t0 := judged_len
	var t1 := maxf(judged_len, S.length())
	var why := "added after the last physics run: not processed yet"
	if running():
		t0 = progress * judged_len   # the judge reads the clip up to judged_len, its progress along that; the time added after it waits too
		why = "not processed yet: the physics run has not reached this part of the motion"
	if t1 - t0 > 0.001:
		out.append({"t0": t0, "t1": t1, "kind": "not run", "reason": why, "yellow": false, "tone": "gray"})
	return out


func red_pct() -> float:
	return float(summary.get("red_pct", 0.0))


## the ghost: Gb posed as the physical version at time t. The pelvis: the clip's own offset moved by what the physics changed
func ghost_pose(Gb: Body, t: float) -> bool:
	if phys.is_empty():
		return false
	var k := clampi(int(round(t * fps)), 0, phys.size() - 1)
	var f: Dictionary = phys[k]
	for j in Body.ORDER:
		var a: Array = f["ang"].get(j, [0, 0, 0])
		Gb.ang[j] = Gb.clamp_ang(j, Vector3(a[0], a[1], a[2]))
	Gb.offset = _offset_at(k)
	Gb.fk()
	return true


## the physical pelvis as an OFFSET: the judge's pelvis minus the clip's pelvis at this frame (and at frame 0, which is the floor
## the judge seated the body on) added to the clip's own offset
func _offset_at(k: int) -> Vector3:
	if offs.size() <= k:
		return Vector3.ZERO
	var p: Array = phys[k]["pelvis"]
	var p0: Array = phys[0]["pelvis"]
	var c: Vector3 = offs[k][1]
	var c0: Vector3 = offs[0][1]
	var d := Vector3(p[0] - c.x, p[1] - c.y, p[2] - c.z) - Vector3(p0[0] - c0.x, p0[1] - c0.y, p0[2] - c0.z)
	return (offs[k][0] as Vector3) + d


## the median gap between the scene's cards (s), 0.1 .. 0.5: the density the physical version is keyed at
static func density(S: Scene) -> float:
	var ts: Array = S.times()
	var gaps := []
	for i in range(1, ts.size()):
		gaps.append(float(ts[i][1]) - float(ts[i - 1][1]))
	if gaps.is_empty():
		return 0.25
	gaps.sort()
	return clampf(float(gaps[gaps.size() / 2]), 0.1, 0.5)


## how many cards in the span Accept span may replace (the priority cards are kept)
static func replaceable(S: Scene, sp: Dictionary) -> int:
	return cards_in(S, sp).filter(func(i): return not bool(S.cards[i].get("keep", false))).size()


## indices of the cards whose arrival lies in the span
static func cards_in(S: Scene, sp: Dictionary) -> Array:
	var ts: Array = S.times()
	var out := []
	for i in S.cards.size():
		var a := float(ts[i][1])
		if a >= float(sp["t0"]) - 1e-4 and a < float(sp["t1"]) - 1e-4:
			out.append(i)
	return out


## replace the cards inside span si by the physical version. The caller has pushed the ONE undo step. Returns the number of new cards
## (0 = nothing to replace, with the reason in `failed`). The timing outside the span is kept: the first card after the span gets an
## explicit move that lands it where it landed before
func accept(S: Scene, Bx: Body, si: int) -> int:
	if si < 0 or si >= spans.size() or phys.is_empty():
		failed = "pick a red span on the timeline first (Make it physical must have finished)"
		return 0
	var sp: Dictionary = spans[si]
	var idx := cards_in(S, sp)
	if idx.is_empty():
		failed = "no card lies inside this span (the red part is between two cards): drag the playhead there and add a card, then accept"
		return 0
	var ts: Array = S.times()
	# PRIORITY cards ("keep") inside the span are fixed points: the span's other cards are replaced in the runs between them
	var runs := []   # [first, last] card indices, each a run of replaceable cards
	for i in idx:
		if bool(S.cards[i].get("keep", false)):
			continue
		if runs.is_empty() or runs[-1][1] != i - 1:
			runs.append([i, i])
		else:
			runs[-1][1] = i
	if runs.is_empty():
		failed = "every card in this span is a priority card (Keep this pose): there is nothing here to replace"
		return 0
	var dt := density(S)
	var keep := Bx.state()
	var cards: Array = S.cards.duplicate()
	var total := 0
	for r in range(runs.size() - 1, -1, -1):   # last run first: the indices of the runs before it do not move
		var i0: int = runs[r][0]
		var i1: int = runs[r][1]
		var t_prev := float(ts[i0 - 1][2]) if i0 > 0 else 0.0   # the end of the previous card's hold
		var t_end := float(ts[i1][1])                            # where the last replaced card landed
		var n := maxi(1, int(round((t_end - t_prev) / dt)))
		var fresh := []
		for j in n:
			var t := t_prev + (t_end - t_prev) * float(j + 1) / float(n)
			var k := clampi(int(round(t * fps)), 0, phys.size() - 1)
			var f: Dictionary = phys[k]
			for jn in Body.ORDER:
				var a: Array = f["ang"].get(jn, [0, 0, 0])
				Bx.ang[jn] = Bx.clamp_ang(jn, Vector3(a[0], a[1], a[2]))
			Bx.offset = _offset_at(k)
			Bx.fk()
			var hold := float(S.cards[i1]["hold"]) if j == n - 1 else 0.0
			fresh.append({"name": "physical %d" % (j + 1), "pose": Bx.to_dict(), "move": (t_end - t_prev) / float(n), "hold": hold})
		Bx.set_state(keep)
		for j in range(i1, i0 - 1, -1):
			cards.remove_at(j)
		for j in fresh.size():
			cards.insert(i0 + j, fresh[j])
		total += fresh.size()
	S.cards = cards
	# the cards after a run are untouched: each run's last new card gets the hold of the card it replaced, so the next arrival holds
	return total
