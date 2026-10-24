class_name EasyTake
extends RefCounted
## EASY's MAKE IT WITH AI VIDEO takes: how good one take is (its tracker output, tools/see_video.py's pose file) and the
## one retake rule. A take is BAD when the tracker found a person in fewer than BAD_FOUND of its frames, or its score is
## below BAD_SCORE. A bad first take is made once more with the next seed (easy_home.gd); a bad second one imports nothing.
## score = mean visibility of the 33 landmarks over the tracked frames, minus the fraction of the clip's frames that are
## lost (no body, or a hand or a foot whose mean visibility is under SIDE_MIN). The same as takes/report.py.

## RESULTS.txt (C:/Temp/claude/comfy3), the fast takes of one prompt at seeds 1-3: the usable one scored 0.923 (punch s1);
## every other take scored below 0.5, most of them far below (-0.382 .. 0.225), and the nearest miss (jumping jack s3,
## 0.487) still lost a hand or foot for 37 % of its clip. 0.5 is the line between a take that tracked whole and one that did not.
const BAD_SCORE := 0.5
## RESULTS.txt, the same takes: a seed with NO detectable person wrote no frames for most of the clip ("stripe artifacts"),
## so a take the tracker found a person in fewer than half its frames is the "Couldn't find a person" case, not a poor fit.
const BAD_FOUND := 0.5
## a side (a foot or a hand) is lost in a frame when its mean visibility is under this (RESULTS.txt "lost span" rule)
const SIDE_MIN := 0.5
## FAST SETTING for EASY's takes only (Expert keeps the default 30 steps, 832x480). RESULTS.txt (C:/Temp/claude/comfy3): 20 steps at
## 640x368 made a 5 s clip in 148-160 s, against 505-655 s at 30 steps 832x480; the best of a pair of fast takes matched the slow
## takes' scores (punch 0.923 vs 0.878, jumping jack 0.487 vs 0.526). Their seed-to-seed swing is why Easy retakes once.
const FAST_STEPS := 20
const FAST_WIDTH := 640
const FAST_HEIGHT := 368
## the time said to the beginner per take: about 150 s (2.5 min) to make the clip, plus the tracker's read, said as "about 3 minutes"
const TAKE_MINUTES := 3
## the landmark indices of the four sides (MediaPipe pose): left foot, right foot, left hand, right hand
const SIDES := [[27, 29, 31], [28, 30, 32], [15, 17, 19, 21], [16, 18, 20, 22]]


## the score of one clip. frames: one Array of 33 visibilities per tracked frame (no body = not in frames);
## seen: the clip's frames the tracker looked at, the lost ones included. {found, mean_vis, lost, score, bad}
static func score(frames: Array, seen: int) -> Dictionary:
	if seen <= 0 or frames.is_empty():
		return {"found": 0.0, "mean_vis": 0.0, "lost": 1.0, "score": 0.0, "bad": true}
	var found := minf(float(frames.size()) / float(seen), 1.0)
	var total := 0.0
	var n := 0
	var good := 0
	for vis in frames:
		var v: Array = vis
		for q in v:
			total += float(q)
			n += 1
		var whole := true
		for s in SIDES:
			var mean := 0.0
			for k in s:
				mean += float(v[k])
			if mean / float((s as Array).size()) < SIDE_MIN:
				whole = false
		if whole:
			good += 1
	var mean_vis := total / float(n)
	var lost := float(seen - good) / float(seen)
	var sc := mean_vis - lost
	return {"found": found, "mean_vis": mean_vis, "lost": lost, "score": sc,
			"bad": found < BAD_FOUND or sc < BAD_SCORE}


## the take's pose file (tools/see_video.py's output) judged. A missing or unreadable file is a take with no person.
static func judge(pose_path: String) -> Dictionary:
	if pose_path == "" or not FileAccess.file_exists(pose_path):
		return score([], 0)
	var d = JSON.parse_string(FileAccess.get_file_as_string(pose_path))
	if not d is Dictionary:
		return score([], 0)
	var frames := []
	for f in (d as Dictionary).get("frames", []):
		if f is Dictionary and (f.get("image", []) as Array).size() >= 33:
			var vis := []
			for q in f["image"]:
				vis.append(float(q[2]))
			frames.append(vis)
	return score(frames, int((d as Dictionary).get("seen", 0)))
