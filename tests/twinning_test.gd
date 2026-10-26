## godot --headless --path . -s tests/twinning_test.gd     (ROADMAP 19, TWINNING; scripts/twinning.gd)
## 1. a scene whose two arms swing as exact mirrors (both part keys mirrored by PartKeys.mirror_file) fires over the swing;
## 2. the same scene with the left arm 3 frames late does not fire;
## 3. a normal walk (scenes/walk_bat.json, read only) fires nothing;
## 4. the fix (Twinning.offset on the left side over the flagged range) removes the finding, and it is one undo step:
##    one snapshot of the part keys taken before the call puts the twin finding back.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func arm_keys() -> Dictionary:
	# the right arm swings forward and back twice; the bends are the file's [bend, side, twist]
	return {
		"upperarm_r": [{"t": 0.2, "v": [0, 0, 0]}, {"t": 0.7, "v": [110, 0, 0]}, {"t": 1.3, "v": [0, 0, 0]}, {"t": 1.8, "v": [-20, 0, 0]}],
		"lowerarm_r": [{"t": 0.2, "v": [0, 0, 0]}, {"t": 0.7, "v": [70, 0, 0]}, {"t": 1.3, "v": [0, 0, 0]}, {"t": 1.8, "v": [40, 0, 0]}],
	}


## the scene: rest, then a 2 s card span for the card blend; the arms are part keys (mirror_file gives the left arm)
func mirror_scene(B: Body, left_late_frames: int) -> Scene:
	var S := Scene.new()
	S.name = "zz_twin"
	var rest := B.to_dict()
	S.add("rest", rest)
	S.add("rest2", rest)
	S.add("rest3", rest)
	for i in S.cards.size():
		S.cards[i]["move"] = 0.6
	var fr := arm_keys()
	var fl := PartKeys.mirror_file(fr, B)
	if left_late_frames > 0:
		var late := left_late_frames / 30.0
		for j in fl:
			for k in fl[j]:
				k["t"] = float(k["t"]) + late
	var both := fr.duplicate()
	for j in fl:
		both[j] = fl[j]
	S.part_keys = PartKeys.from_file(both)
	return S


func arm_findings(fs: Array) -> Array:
	return fs.filter(func(f): return f["rule"] == "TWINNING" and f["kind"] == "arm")


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()

	# 1. the mirrored swings
	var S := mirror_scene(B, 0)
	var fs := Twinning.findings(S, B)
	var af := arm_findings(fs)
	print("     mirrored: %d arm finding(s), %s" % [af.size(), af[0]["msg"] if af.size() > 0 else "none"])
	ok(af.size() >= 1, "1 mirrored arms fire (%d)" % af.size())
	var over := af.size() >= 1 and float(af[0]["t0"]) < 1.3 and float(af[0]["t1"]) > 0.2
	ok(over, "1 the range overlaps the swings (0.2-1.3 s): %s" % (("%.2f-%.2f" % [af[0]["t0"], af[0]["t1"]]) if af.size() > 0 else "none"))

	# 2. the left arm 3 frames late
	var L := mirror_scene(B, 3)
	var lf := arm_findings(Twinning.findings(L, B))
	print("     3 frames late: %d arm finding(s)" % lf.size())
	ok(lf.is_empty(), "2 the same with the left arm 3 frames late does not fire")

	# 3. a normal walk
	var W := Scene.new()
	W.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/walk_bat.json")))
	var wf := Twinning.findings(W, B)
	print("     walk_bat: %d finding(s)" % wf.size())
	ok(wf.is_empty(), "3 a normal walk (walk_bat) fires nothing")

	# 4. the fix: offset the left side over the arm range; the finding goes; one snapshot restores it
	var before := S.part_keys.duplicate(true)   # the undo snapshot (main takes one, _snapshot's "pk")
	var ranges := af.map(func(f): return {"kind": f["kind"], "t0": f["t0"], "t1": f["t1"]})
	var n := Twinning.offset(S, B, "l", ranges)
	var after := arm_findings(Twinning.findings(S, B))
	print("     fix: %d joint(s) moved, %d arm finding(s) left" % [n, after.size()])
	ok(n == 2 * ranges.size(), "4 the fix moves the left upper and lower arm (%d joints)" % n)
	ok(after.is_empty(), "4 the fix removes the finding")
	S.part_keys = before   # one undo step puts the scene back
	var back := arm_findings(Twinning.findings(S, B))
	ok(back.size() >= 1, "4 one undo step brings the finding back")

	print("TWINNING TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
