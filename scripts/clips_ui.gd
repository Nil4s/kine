## CLIPS in the app (GAP_ANALYSIS row 12; the maths: scripts/clips.gd). Kept out of main.gd: main makes one of these
## (main.clips_ui), lists its commands, and its undo snapshot carries S.clips. Every edit here is ONE undo step (main._do).
##   "Clip: place a scene here..."   a dialog: a scene file + repeat, speed, blend in / out, replace / add, the parts, extrapolation;
##                                    OK places it at the playhead
##   "Clip: place a move here..."    the same for a pose / move from moves/ (or poses/)
##   "Clip: edit the picked clip..." the same dialog on the picked clip (click its bar on the timeline to pick it)
##   "Clip: remove the picked clip"
##   "Clip: warp ..."                 ROADMAP 83: the picked clip's time curve as a preset (linear, ease in, ease out, slow-mo
##                                    middle). The curve itself is on the strip when picked: drag a knot, click empty space
##                                    to add one, right-click a knot to take it out (timeline.gd; scripts/clips.gd warp_*)
##   "Clip: match pose to the clip before"  ROADMAP 84: the picked clip starts at the source frame (within 0.5 s) whose pose is
##                                    closest to the clip before's end, its walk is moved and turned onto that end, and the blend
##                                    across the seam is 0.2 s; the clip before holds into the seam (scripts/pose_match.gd)
## The timeline (timeline.gd) draws the bars and drags them in time.
class_name ClipsUI
extends RefCounted

var m: Node            # main.gd
var sel := -1          # the picked clip (index into S.clips), -1 = none
var dlg: ConfirmationDialog
var _mode := ""        # "scene" / "move" / "edit"
var _files := []       # the dialog's source paths, in the list's order
var ui_src: OptionButton
var ui_rep: SpinBox
var ui_speed: SpinBox
var ui_bin: SpinBox
var ui_bout: SpinBox
var ui_type: OptionButton
var ui_mask: OptionButton
var ui_extra: OptionButton
const MASK_WORDS := {"all": "the whole body", "legs": "legs and hips only", "upper": "upper body only", "arms": "both arms only",
	"arm_l": "left arm only", "arm_r": "right arm only"}
const EXTRA_WORDS := {"nothing": "nothing outside the strip", "hold": "hold the first / last frame", "hold_forward": "hold the last frame after"}


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Clip: place a scene here...", "", open.bind("scene"), "clip strip nla action reuse walk cycle place insert scene reference time editor track loop repeat",
		false, "another scene used by reference as a strip at the playhead: repeat, speed, blend in / out, replace or add, which body parts (e.g. a walk on the legs only)")
	add.call("Clip: place a move here...", "", open.bind("move"), "clip strip nla action reuse place pose move library reference",
		false, "a saved pose or move (moves/, poses/) used by reference as a strip at the playhead, with the same choices")
	add.call("Clip: edit the picked clip...", "", open.bind("edit"), "clip strip nla repeat speed scale blend mask edit",
		false, "the picked clip's repeat, speed, blend in / out, blend type, parts and extrapolation (click a clip's bar on the timeline to pick it)")
	add.call("Clip: remove the picked clip", "", remove, "clip strip nla delete remove",
		true, "the picked clip leaves this scene (its file stays as it is)")
	add.call("Clip: in place / travelling", "", toggle_inplace.bind(-1), "clip strip root motion in place travelling travel treadmill walk cycle toggle hips slide",
		false, "the picked clip (or the last one) walks on the spot, or travels again: flip it while you look at the clip (ONE undo step)")
	add.call("Clip: warp linear", "", warp_preset.bind("linear"), "clip strip warp time curve linear straight none reset",
		false, "the picked clip plays at a constant rate again (its time curve is straight)")
	add.call("Clip: warp ease in", "", warp_preset.bind("ease_in"), "clip strip warp time curve ease in slow start",
		false, "the picked clip starts slow and speeds up (its time curve bows down)")
	add.call("Clip: warp ease out", "", warp_preset.bind("ease_out"), "clip strip warp time curve ease out slow end",
		false, "the picked clip starts fast and slows down at its end (its time curve bows up)")
	add.call("Clip: warp slow-mo middle", "", warp_preset.bind("slow_mid"), "clip strip warp time curve slow motion middle",
		false, "the picked clip is slow in the middle and fast at both ends (slow motion through the middle of the strip)")
	add.call("Clip: match pose to the clip before", "", match_pose.bind(-1), "clip strip match pose transition seam blend foot walk smooth pop join",
		false, "the picked clip starts at the frame (within 0.5 s) whose pose is closest to the clip before's end, moved onto its place and turned to its heading, with a 0.2 s blend (no pop at the seam)")


## the files a dialog offers: scenes (scene files: scenes/, scenes/_wip, moves/ with cards) or moves (poses and keyed moves)
static func files(kind: String) -> Array:
	var out := []
	var dirs := ["res://scenes", "res://scenes/_wip", "res://moves"] if kind == "scene" else ["res://moves", "res://poses/lib", "res://poses"]
	for dir in dirs.reduce(func(a, x): return a + UserPaths.dirs(x), []):   # + the user's folders (an exported build)
		var d := DirAccess.open(dir)
		if d == null:
			continue
		var fs := Array(d.get_files())
		fs.sort()
		for f in fs:
			if not f.ends_with(".json"):
				continue
			var path: String = dir + "/" + f
			var is_scene := FileAccess.get_file_as_string(path).contains("\"cards\"")
			if is_scene == (kind == "scene"):
				out.append(path.trim_prefix("res://"))
	return out


func _build() -> void:
	dlg = ConfirmationDialog.new()
	dlg.name = "clip_dialog"
	dlg.min_size = Vector2i(420, 0)
	dlg.exclusive = false   # not modal: another dialog (Body: proportions...) can still open while it is up
	var g := GridContainer.new()
	g.columns = 2
	var row := func(words: String, c: Control):
		var l := Label.new()
		l.text = words
		g.add_child(l)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(c)
	ui_src = OptionButton.new()
	ui_src.name = "opt_clip_source"
	row.call("source", ui_src)
	ui_rep = _spin("spin_clip_repeat", 1, 50, 1)
	row.call("repeat (times)", ui_rep)
	ui_speed = _spin("spin_clip_speed", 0.05, 20, 0.05)
	row.call("speed (2 = twice as fast)", ui_speed)
	ui_bin = _spin("spin_clip_blend_in", 0, 10, 0.05)
	row.call("blend in (s)", ui_bin)
	ui_bout = _spin("spin_clip_blend_out", 0, 10, 0.05)
	row.call("blend out (s)", ui_bout)
	ui_type = OptionButton.new()
	ui_type.name = "opt_clip_type"
	ui_type.add_item("replace (takes over by its weight)")
	ui_type.add_item("add (its angles added on top)")
	row.call("blend", ui_type)
	ui_mask = OptionButton.new()
	ui_mask.name = "opt_clip_parts"
	for k in Clips.MASK_NAMES:
		ui_mask.add_item(MASK_WORDS[k])
	row.call("parts", ui_mask)
	ui_extra = OptionButton.new()
	ui_extra.name = "opt_clip_extrapolation"
	for k in Clips.EXTRA:
		ui_extra.add_item(EXTRA_WORDS[k])
	row.call("outside the strip", ui_extra)
	dlg.add_child(g)
	dlg.confirmed.connect(_ok)
	m.add_child(dlg)


func _spin(nm: String, lo: float, hi: float, st: float) -> SpinBox:
	var s := SpinBox.new()
	s.name = nm
	s.min_value = lo
	s.max_value = hi
	s.step = st
	return s


func open(kind: String) -> void:
	var S: Scene = m.S
	if S.cards.is_empty():
		m._say("a clip is placed on a scene's timeline: open a scene, or press Enter to add the body as a card first")
		return
	if kind == "edit" and (sel < 0 or sel >= S.clips.size()):
		m._say("no clip picked: click a clip's bar under the cards on the timeline, or use 'Clip: place a scene here...' first")
		return
	if dlg == null:
		_build()
	_mode = kind
	var c: Dictionary = S.clips[sel] if kind == "edit" else Clips.make("", 0.0)
	_files = [c["src"]] if kind == "edit" else files(kind)
	if _files.is_empty():
		m._say("there is no %s file to place: save one first (Save scene / Save pose), then place it" % kind)
		return
	ui_src.clear()
	for f in _files:
		ui_src.add_item(String(f))
	ui_src.disabled = kind == "edit"
	ui_rep.value = int(c["repeat"])
	ui_speed.value = float(c["speed"])
	ui_bin.value = float(c["bin"])
	ui_bout.value = float(c["bout"])
	ui_type.select(Clips.TYPES.find(c["type"]))
	ui_mask.select(Clips.MASK_NAMES.find(c["mask"]))
	ui_extra.select(Clips.EXTRA.find(c["extra"]))
	dlg.title = "Clip: edit %s" % Clips.label(c) if kind == "edit" else "Clip: place a %s at %.2f s" % [kind, float(m.playhead)]
	dlg.popup_centered()


func _opts() -> Dictionary:
	return {"repeat": int(ui_rep.value), "speed": ui_speed.value, "bin": ui_bin.value, "bout": ui_bout.value,
		"type": Clips.TYPES[maxi(ui_type.selected, 0)], "mask": Clips.MASK_NAMES[maxi(ui_mask.selected, 0)],
		"extra": Clips.EXTRA[maxi(ui_extra.selected, 0)]}


func _ok() -> void:
	if _mode == "edit":
		edit(sel, _opts())
	elif ui_src.selected >= 0:
		place(String(_files[ui_src.selected]), float(m.playhead), _opts())


## the edits (the dialog's OK, agents and tests): each ONE undo step. place returns the new clip's index (-1 = refused)
func place(src: String, start: float, opts := {}) -> int:
	var S: Scene = m.S
	src = src.trim_prefix("res://")
	if Clips.source(src).is_empty():
		m._say("NOT PLACED: %s is not a scene, pose or move file this can play; pick another in the list" % src)
		return -1
	if m.scene_path != "" and String(m.scene_path).trim_prefix("res://") == src:
		m._say("NOT PLACED: a scene cannot place itself (it would play itself forever); pick another scene")
		return -1
	var c := Clips.make(src, start, opts)
	m._do(func():
		S.clips.append(c)
		_replay())
	sel = S.clips.size() - 1
	var e := Clips.source(src)
	m._say("clip %s at %.2f s to %.2f s (%s); drag its bar on the timeline to move it, Ctrl+Z takes it back" % [Clips.label(c), float(c["start"]),
		float(c["start"]) + Clips.length_of(c, float(e["len"])), MASK_WORDS[c["mask"]]])
	return sel


func edit(k: int, opts: Dictionary) -> void:
	var S: Scene = m.S
	var c := (S.clips[k] as Dictionary).duplicate()
	for x in opts:
		c[x] = opts[x]
	c = Clips.clean(c)
	if c == S.clips[k]:
		m._say("the clip already plays that way: change a value in 'Clip: edit the picked clip...' to edit it")
		return
	m._do(func():
		S.clips[k] = c
		_replay())
	m._say("clip %s changed (Ctrl+Z takes it back)" % Clips.label(c))


## W08: the picked clip's (or clip k's) hips travel over the floor or stay on the spot, applied live: ONE undo step
func toggle_inplace(k := -1, on = null) -> void:
	var S: Scene = m.S
	if S.clips.is_empty():
		m._say("this scene has no clip: use 'Clip: place a scene here...' to place one")
		return
	if k < 0:
		k = sel if sel >= 0 and sel < S.clips.size() else S.clips.size() - 1
	var c: Dictionary = S.clips[k]
	var want: bool = (not bool(c.get("inplace", false))) if on == null else bool(on)
	var d := c.duplicate()
	d["inplace"] = want
	d = Clips.clean(d)
	m._do(func():
		S.clips[k] = d
		_replay())
	m._say("clip %s: %s (Ctrl+Z takes it back)" % [Clips.label(d), "walks in place" if want else "travels"])


## ROADMAP 84: the picked clip (or clip k) matched to the clip before it: ONE undo step. Says what the match did
func match_pose(k := -1) -> void:
	var S: Scene = m.S
	if k < 0:
		k = _picked()
		if k < 0:
			return
	if k >= S.clips.size():
		return
	var r := PoseMatch.plan(S, k)
	if r.has("err"):
		m._say(String(r["err"]))
		return
	var A: Dictionary = S.clips[int(r["A"])]
	var B: Dictionary = S.clips[k]
	if r["A2"] == A and r["B2"] == B:
		m._say("the clip already starts matched to the clip before: drag or edit the clips to match again")
		return
	var ia: int = int(r["A"])
	var A2: Dictionary = r["A2"]
	var B2: Dictionary = r["B2"]
	m._do(func():
		S.clips[ia] = A2
		S.clips[k] = B2
		_replay())
	m._say("clip %s matched: starts at source %.2f s (pose %.1f deg from the clip before's end), turned %.1f deg, %.2f s blend (Ctrl+Z takes it back)" % [
		Clips.label(B2), float(B2["match"]["lt0"]), float(r["d"]), float(r["yaw"]), float(B2["bin"])])


## the picked clip, or the reason there is none (a message names the next step)
func _picked() -> int:
	var S: Scene = m.S
	if sel < 0 or sel >= S.clips.size():
		m._say("no clip picked: click a clip's bar under the cards on the timeline first, then pick its warp")
		return -1
	return sel


## a preset time curve for the picked clip: ONE undo step
func warp_preset(name: String) -> void:
	var k := _picked()
	if k >= 0:
		set_warp(k, Clips.WARP_PRESETS[name], name.replace("_", " "))


## clip k's time curve set to these knots (Clips.warp_norm'd): ONE undo step; the same curve again does nothing
func set_warp(k: int, knots: Array, what := "") -> void:
	var S: Scene = m.S
	var c := (S.clips[k] as Dictionary).duplicate(true)
	c["warp"] = Clips.warp_norm(knots)
	c = Clips.clean(c)
	if c == S.clips[k]:
		m._say("the clip already has that time curve: pick another preset, or drag a knot on the strip")
		return
	m._do(func():
		S.clips[k] = c
		_replay())
	m._say("clip %s time curve %s (Ctrl+Z takes it back)" % [Clips.label(c), what if what != "" else "changed"])


## one knot taken out of clip k's curve (right-click on the knot on the strip): ONE undo step
func warp_remove(k: int, j: int) -> void:
	var S: Scene = m.S
	var ks := Clips.warp_norm((S.clips[k] as Dictionary).get("warp", []))
	if j < 0 or j >= ks.size():
		return
	ks.remove_at(j)
	set_warp(k, ks, "knot taken out")


func remove() -> void:
	var S: Scene = m.S
	if sel < 0 or sel >= S.clips.size():
		if S.clips.is_empty():
			m._say("this scene has no clip: use 'Clip: place a scene here...' to place one")
			return
		sel = S.clips.size() - 1
	var c: Dictionary = S.clips[sel]
	var k := sel
	m._do(func():
		S.clips.remove_at(k)
		_replay())
	sel = mini(sel, S.clips.size() - 1)
	m._say("removed the clip %s (its file is untouched; Ctrl+Z puts it back)" % Clips.label(c))


func _replay() -> void:
	m.S.apply(m.B, minf(float(m.playhead), m.S.length()))
	m._dummy_hits()
	if m.ui_timeline != null:
		m.ui_timeline.queue_redraw()
