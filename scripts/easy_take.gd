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
## FROZEN (the statue): a take is BAD when more than half its clip is STILL (frozen_fraction). A still frame moves its wrists,
## hips and ankles less than STILL_STEP body heights from the frame before. Measured on the tracker files (image space: the
## mean movement of the 6 points per frame, in shoulder-mid to ankle-mid units; the still fraction over the clip's frames):
##   STILL_STEP 0.002 gives: the jab (cmb01_jab, tests/fixtures/easy_jab_frozen_pose.json) 0.914 still, against ffmpeg's
##   freezedetect 4.69 of 5 s = 0.938; the cheer (ges01_cheer) 0.284 still, against freezedetect's 1.4 of 5 s = 0.28. So the line
##   reproduces the ffmpeg freezes. A real moving take (tests/fixtures/vidspeed_pose_A.json, gen_hammer) reads 0.012 still.
##   At 0.001 the jab would read 0.444 (not frozen); at 0.005 the moving take would read 0.333 (frozen). 0.002 sits between.
##   BAD_FROZEN 0.5: half the clip still is a statue, a jab that is a pose. The walk (mov01_walk_B) reads 0.679 still: bad.
const STILL_STEP := 0.002
const BAD_FROZEN := 0.5
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


## the still fraction of one clip: xy holds one entry per frame the tracker looked at, in order: an Array of 33 [x, y] image
## points, or null for a frame with no body. A frame is STILL when the mean movement of the wrists, hips and ankles (15, 16,
## 23, 24, 27, 28) from the frame before is under STILL_STEP body heights (shoulder-mid to ankle-mid, this frame). The count of
## still frames over seen; 0 when the clip never sits still.
static func frozen_fraction(xy: Array, seen: int) -> float:
	if seen <= 0:
		return 0.0
	var still := 0
	for i in range(1, xy.size()):
		var a: Variant = xy[i - 1]
		var b: Variant = xy[i]
		if not (a is Array and b is Array) or (a as Array).size() < 33 or (b as Array).size() < 33:
			continue
		var h := _pt(b, 11).lerp(_pt(b, 12), 0.5).distance_to(_pt(b, 27).lerp(_pt(b, 28), 0.5))
		if h <= 0.0:
			continue
		var step := 0.0
		for k in [15, 16, 23, 24, 27, 28]:
			step += _pt(b, k).distance_to(_pt(a, k))
		if step / 6.0 / h < STILL_STEP:
			still += 1
	return minf(float(still) / float(seen), 1.0)


static func _pt(frame: Array, k: int) -> Vector2:
	var q: Array = frame[k]
	return Vector2(float(q[0]), float(q[1]))


## the score of one clip. frames: one Array of 33 visibilities per tracked frame (no body = not in frames);
## seen: the clip's frames the tracker looked at, the lost ones included; frozen: frozen_fraction of the clip.
## {found, mean_vis, lost, score, frozen, bad}
static func score(frames: Array, seen: int, frozen := 0.0) -> Dictionary:
	if seen <= 0 or frames.is_empty():
		return {"found": 0.0, "mean_vis": 0.0, "lost": 1.0, "score": 0.0, "frozen": 1.0, "bad": true}
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
	return {"found": found, "mean_vis": mean_vis, "lost": lost, "score": sc, "frozen": frozen,
			"bad": found < BAD_FOUND or sc < BAD_SCORE or frozen > BAD_FROZEN}


## the take's pose file (tools/see_video.py's output) judged. A missing or unreadable file is a take with no person.
static func judge(pose_path: String) -> Dictionary:
	if pose_path == "" or not FileAccess.file_exists(pose_path):
		return score([], 0)
	var d = JSON.parse_string(FileAccess.get_file_as_string(pose_path))
	if not d is Dictionary:
		return score([], 0)
	var frames := []
	var xy := []
	for f in (d as Dictionary).get("frames", []):
		if f is Dictionary and (f.get("image", []) as Array).size() >= 33:
			var vis := []
			var pts := []
			for q in f["image"]:
				vis.append(float(q[2]))
				pts.append([float(q[0]), float(q[1])])
			frames.append(vis)
			xy.append(pts)
		else:
			xy.append(null)
	var seen := int((d as Dictionary).get("seen", 0))
	return score(frames, seen, frozen_fraction(xy, seen))
