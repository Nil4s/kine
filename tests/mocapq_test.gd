## godot --headless --path . -s tests/mocapq_test.gd     (MOCAP QUALITY, scripts/mocap_metrics.gd + scripts/video_iq.gd + tools/see_video.py)
## VIDEO -> MOCAP, quality and speed, on four fixed fixtures: the first 45 frames of a generated walk, punch, kick and turn clip
## after tools/see_video.py (tests/fixtures/mocapq_*.json, keypoints only, no video). "Before" is the pipeline with the new flip
## repair off (VideoIQ.flip_fix = false: the old output exactly). The new stage: VideoIQ.fix_flips, a left/right limb swap of a few
## frames swapped back by continuity. THE NUMBERS (MocapMetrics: skate cm, jitter in 1000 deg/s^2, pen cm), measured 2026-10-26:
##   clean clips (flip repair on = off, to 1e-3)      a 4-frame leg swap seeded at frames 20-23: flips left, jitter, skate
##   clip    skate worst   jitter   pen               no repair                    repair
##   walk    3.09          0.33     6.68
##   punch   0.01          0.10     0.06
##   kick    0.00          1.19     1.48              8 flips, jitter 2.53         0 flips, jitter 1.19
##   turn    7.97          8.85     10.92             6 flips, jitter 10.73        0 flips, jitter 8.85 (= the clean clip)
## Bars, stated before the run: 1 CLEAN no clip's jitter, skate or pen worse than before (1e-3), each at or under its measured value
## + 10 % (+ 0.5 cm for skate and pen); 2 FLIPS the seeded swap goes through without the repair (flips left, or jitter 3x), is
## swapped back with it (4 frames repaired, no flip left, the jitter and skate within 2 % / 0.1 cm of the unseeded clip, the
## jitter at most 85 % of the unrepaired one) and the clean clips repair 0 frames; 3 BONES the cleaned landmarks' bone lengths vary
## under 1 % (raw: 2.5-11 %); 4 SPEED the work (Scene.apply calls: process and the metrics' replay) of each clip at or under its
## measured count + 10 %, and tools/see_video.py's seam check (the chunked whole-picture tracker) is true for a continuous run
## and false for a jump.
## Skate and sinking come from the plants and the stance height, not from this change: they are bars so that no later change makes
## them worse, not claims that they are good (the turn clip sinks 11 cm: the leg is shorter than the tracked stride).
## JOINT-ANGLE SMOOTHING (VideoIQ.angle_smooth, off): it cut the punch's jitter 0.10 -> 0.02 and the turn's 8.85 -> 8.16, but it moves
## the hands' peak speed, which tests/video_import_test.gd 10b-10h hold to the old values (10h: 3.34 +- 0.1 m/s), so it stays off.
extends SceneTree

const CLIPS := ["walk", "punch", "kick", "turn"]
const J_NOW := {"walk": 0.33, "punch": 0.10, "kick": 1.19, "turn": 8.85}
const SKATE_NOW := {"walk": 3.09, "punch": 0.01, "kick": 0.0, "turn": 7.97}
const PEN_NOW := {"walk": 6.68, "punch": 0.06, "kick": 1.48, "turn": 10.92}
const APPLY_NOW := {"walk": 1817, "punch": 1882, "kick": 1501, "turn": 1919}   # process + the metrics' own replay (45 applies)

var fails := 0
var B: Body


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func run(clip: String, smooth: bool, flipfix: bool, seed_flip := "") -> Dictionary:
	VideoIQ.angle_smooth = smooth
	VideoIQ.flip_fix = flipfix
	var P := VideoImport.load_file("res://tests/fixtures/mocapq_%s.json" % clip)
	if seed_flip != "":
		var prs: Array = [[25, 26], [27, 28], [29, 30], [31, 32]] if seed_flip == "legs" else [[13, 14], [15, 16], [17, 18], [19, 20], [21, 22]]
		for i in range(20, 24):
			var w: Array = P["frames"][i]["w"]
			for pr in prs:
				var tmp: Vector3 = w[pr[0]]
				w[pr[0]] = w[pr[1]]
				w[pr[1]] = tmp
	var R := VideoIQ.process(B, P, "", "mocapq", true)
	var times := []
	for fr in R["fitted"]:
		times.append(fr["t"])
	var F := MocapMetrics.play(B, R["scene"], times)
	return {"skate": float(MocapMetrics.skate(F)["worst"]), "jitter": MocapMetrics.jitter(F["frames"]), "pen": float(MocapMetrics.penetration(F)["deepest"]),
		"flips_clean": MocapMetrics.flips(R["frames"]), "bones": MocapMetrics.bones(R["frames"]), "repaired": int(R.get("limb_flips", 0)),
		"foot_flips": MocapMetrics.foot_flips(F)}


func _init() -> void:
	B = Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var before := {}
	var after := {}
	var work := {}
	for c in CLIPS:
		before[c] = run(c, false, false)
		var n0 := Scene.apply_calls
		after[c] = run(c, false, true)
		work[c] = Scene.apply_calls - n0
		print("     %s before: skate %.2f jitter %.2f pen %.2f | after: skate %.2f jitter %.2f pen %.2f | repaired %d, bones %.2f %%, %d Scene.apply calls" % [c,
			before[c]["skate"], before[c]["jitter"], before[c]["pen"], after[c]["skate"], after[c]["jitter"], after[c]["pen"], after[c]["repaired"], after[c]["bones"], work[c]])
	# 1 CLEAN
	for c in CLIPS:
		ok(float(after[c]["jitter"]) <= float(before[c]["jitter"]) + 1e-3, "1 CLEAN %s jitter not worse than before (%.3f -> %.3f)" % [c, before[c]["jitter"], after[c]["jitter"]])
		ok(float(after[c]["jitter"]) <= float(J_NOW[c]) * 1.1 + 0.01, "1 CLEAN %s jitter at or under %.2f + 10 %%" % [c, J_NOW[c]])
		ok(float(after[c]["skate"]) <= float(before[c]["skate"]) + 1e-3, "1 CLEAN %s skate not worse than before (%.2f -> %.2f cm)" % [c, before[c]["skate"], after[c]["skate"]])
		ok(float(after[c]["skate"]) <= float(SKATE_NOW[c]) + 0.5, "1 CLEAN %s skate at or under %.2f + 0.5 cm" % [c, SKATE_NOW[c]])
		ok(float(after[c]["pen"]) <= float(before[c]["pen"]) + 1e-3, "1 CLEAN %s pen not worse than before (%.2f -> %.2f cm)" % [c, before[c]["pen"], after[c]["pen"]])
		ok(float(after[c]["pen"]) <= float(PEN_NOW[c]) + 0.5, "1 CLEAN %s pen at or under %.2f + 0.5 cm" % [c, PEN_NOW[c]])
		ok(int(after[c]["repaired"]) == 0, "2 FLIPS the clean %s repairs 0 frames (%d)" % [c, after[c]["repaired"]])
	# 2 FLIPS
	for pair in [["turn", "legs"], ["kick", "legs"]]:
		var c: String = pair[0]
		var bad := run(c, false, false, pair[1])
		var fix := run(c, false, true, pair[1])
		print("     %s seeded %s swap: no repair -> %d flips, jitter %.2f | repair -> %d flips, jitter %.2f, skate %.2f" % [c, pair[1], bad["flips_clean"], bad["jitter"], fix["flips_clean"], fix["jitter"], fix["skate"]])
		ok(int(bad["flips_clean"]) > 0 or float(bad["jitter"]) >= 3.0 * float(fix["jitter"]), "2 FLIPS control: the seeded %s swap on %s goes through without the repair (%d flips, jitter %.2f)" % [pair[1], c, bad["flips_clean"], bad["jitter"]])
		ok(int(fix["repaired"]) == 4 and int(fix["flips_clean"]) == 0, "2 FLIPS %s: 4 frames swapped back, %d flips left" % [c, fix["flips_clean"]])
		ok(float(fix["jitter"]) <= float(after[c]["jitter"]) * 1.02 + 0.005, "2 FLIPS %s: jitter %.3f within 2 %% of the unseeded %.3f" % [c, fix["jitter"], after[c]["jitter"]])
		ok(float(fix["jitter"]) <= 0.85 * float(bad["jitter"]), "2 FLIPS %s: jitter at most 85 %% of the unrepaired (%.2f against %.2f)" % [c, fix["jitter"], bad["jitter"]])
		ok(absf(float(fix["skate"]) - float(after[c]["skate"])) <= 0.1, "2 FLIPS %s: skate %.2f within 0.1 cm of the unseeded %.2f" % [c, fix["skate"], after[c]["skate"]])
	# 3 BONES
	for c in CLIPS:
		ok(float(after[c]["bones"]) < 1.0, "3 BONES %s: cleaned bone lengths vary %.2f %% (< 1 %%)" % [c, after[c]["bones"]])
	# 4 SPEED: the work (Scene.apply calls; a wall clock moves with every other program on the PC)
	for c in CLIPS:
		ok(int(work[c]) <= int(float(APPLY_NOW[c]) * 1.1), "4 SPEED %s: %d Scene.apply calls (measured %d, bar +10 %%)" % [c, work[c], APPLY_NOW[c]])
	_seams()
	VideoIQ.flip_fix = true
	print("")
	print("%d FAIL" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)


## tools/see_video.py's seam check on made-up frames: a continuous run holds, a jump of the hips does not
func _seams() -> void:
	var code := "import importlib.util as u,sys\nsp=u.spec_from_file_location('sv',sys.argv[1])\nm=u.module_from_spec(sp)\nsp.loader.exec_module(m)\n" \
		+ "def fr(x):\n  im=[[0,0,1]]*33\n  im[23]=[x,0.5,1]\n  im[24]=[x,0.5,1]\n  return {'image':im}\n" \
		+ "ok=m._seams_hold([(i,fr(0.4+0.01*i)) for i in range(30)])\n" \
		+ "bad=m._seams_hold([(i,fr(0.4+0.01*i if i<15 else 0.8)) for i in range(30)])\n" \
		+ "print('SEAMS',ok,bad)\n"
	var out := []
	var code_run := OS.execute("python", ["-I", "-c", code, ProjectSettings.globalize_path("res://tools/see_video.py")], out, true)
	var txt := "" if out.is_empty() else String(out[0])
	ok(code_run == 0 and txt.contains("SEAMS True False"), "4 SPEED the chunked tracker's seam check: true for a continuous run, false for a jump (%s)" % txt.strip_edges())
