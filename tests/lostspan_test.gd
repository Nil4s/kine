## godot --headless --path . -s tests/lostspan_test.gd     (LOST SPANS, scripts/video_iq.gd: VideoIQ.repair's joint-angle fill)
## A hand or a foot the tracker loses for a span is filled by its JOINT ANGLES (each bone turns along the arc between its two good
## ends, cosine ease in / out, the bone keeps its length), not by a straight line between the points. A foot lost while the other
## foot is planted and the pelvis steady stays where it was. A span at a clip's start holds the first good pose.
## THE TRUTH is a known motion, built here (no file): a right arm swinging in the image plane (upper arm 0.30 m, forearm 0.27 m,
## shoulder fixed) and a standing body. The tracker's landmarks are dropped for 0.5 s (visibility 0.1, the points thrown 25 cm).
## Bars, stated before measuring:
##   1 HAND   the filled wrist stays within 5 cm of the truth at EVERY frame of the clip. The instrument must be able to move: the
##            pre-fix straight-line fill (VideoIQ.ANGLE_FILL = false) is printed, and its error is asserted > 5 cm
##   2 KEEP   the frames outside the span are bit-identical to the pre-fix repair (and to the raw import)
##   3 START  a span at the clip's first frame holds the first good pose (wrist = the good pose's, relative to the shoulder)
##   4 FOOT   the left foot lost 0.5 s while the right foot is planted and the pelvis steady: the ankle stays within 2 cm of the truth
##   5 CLIP   the jumping-jack ComfyUI clip (its tracker json, if present; C:/Temp/claude/comfy_e2e): the feet-lost spans and the
##            verdict text before and after, printed (not a bar)
extends SceneTree

const FPS := 30.0
const N := 91            # 3.0 s
const SPAN := [30, 45]   # frames: 1.0 s .. 1.5 s (0.5 s)
const BAR := 0.05
const JJ := "C:/Temp/claude/comfy_e2e/jumping_jack.pose.json"

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	_run.call_deferred()


## the truth: frame k's 33 world points (our axes, hips at 0). The right wrist (16) and elbow (14) and the ankle (28) move in the
## image plane; everything else stands still
func truth(k: int) -> Array:
	var t := k / FPS
	var th := 0.9 * sin(TAU * t / 2.4)
	var ph := 0.6 + 0.5 * sin(TAU * t / 1.6 + 1.0)
	var d1 := Vector3(sin(th), -cos(th), 0.0)
	var d2 := Vector3(sin(th + ph), -cos(th + ph), 0.0)
	var w := []
	w.resize(33)
	w.fill(Vector3.ZERO)
	var S_r := Vector3(0.18, 0.45, 0.0)
	w[0] = Vector3(0.0, 0.75, 0.10)
	w[7] = Vector3(-0.08, 0.75, 0.0)
	w[8] = Vector3(0.08, 0.75, 0.0)
	w[11] = Vector3(-0.18, 0.45, 0.0)
	w[12] = S_r
	w[13] = Vector3(-0.18, 0.15, 0.0)
	w[15] = Vector3(-0.18, -0.12, 0.0)
	w[14] = S_r + d1 * 0.30
	w[16] = w[14] + d2 * 0.27
	w[23] = Vector3(-0.09, 0.0, 0.0)
	w[24] = Vector3(0.09, 0.0, 0.0)
	for sd in [[23, 25, 27, 29, 31, -0.09], [24, 26, 28, 30, 32, 0.09]]:
		var x: float = sd[5]
		w[sd[1]] = Vector3(x, -0.45, 0.0)
		w[sd[2]] = Vector3(x, -0.90, 0.0)
		w[sd[3]] = Vector3(x, -0.92, -0.05)
		w[sd[4]] = Vector3(x, -0.92, 0.12)
	return w


## the tracker's file as VideoImport.parse reads it: frames of {"t", "w", "vis"}; the points of `lost` parts in the SPAN are
## thrown 25 cm away and their visibility drops to 0.1 (the tracker's own words for a lost point)
func tracked(lost: Array) -> Array:
	var fr := []
	for k in N:
		var w := truth(k)
		var vis := []
		vis.resize(33)
		vis.fill(1.0)
		if k >= SPAN[0] and k <= SPAN[1]:
			for part in lost:
				for j in part[0]:
					w[j] = (w[j] as Vector3) + Vector3(0.25, 0.10, -0.20)
					vis[j] = 0.1
		fr.append({"t": k / FPS, "w": w, "vis": vis})
	return fr


## the pipeline's repair on a copy, with the fill chosen; returns the repaired frames
func repaired(src: Array, angle: bool) -> Array:
	var fr := []
	for f in src:
		fr.append({"t": f["t"], "w": (f["w"] as Array).duplicate(), "vis": f["vis"]})
	var Rw := VideoIQ.fill_gaps(fr, FPS)
	var cf := VideoIQ.confidence(Rw, FPS)
	VideoIQ.ANGLE_FILL = angle
	VideoIQ.repair(Rw, cf)
	VideoIQ.ANGLE_FILL = true
	return Rw


func err_at(R: Array, j: int, k: int) -> float:
	return ((R[k]["w"] as Array)[j] as Vector3).distance_to((truth(k))[j] as Vector3)


func max_err(R: Array, j: int) -> float:
	var m := 0.0
	for k in N:
		m = maxf(m, err_at(R, j, k))
	return m


func _run() -> void:
	var src := tracked([[[14, 16], 0]])
	var raw := src.duplicate(true)
	var old := repaired(src, false)
	var new := repaired(src, true)

	# ---- 1 HAND
	var e_raw := max_err(raw, 16)
	var e_old := max_err(old, 16)
	var e_new := max_err(new, 16)
	var mean_old := 0.0
	var mean_new := 0.0
	for k in range(SPAN[0], SPAN[1] + 1):
		mean_old += err_at(old, 16, k)
		mean_new += err_at(new, 16, k)
	mean_old /= float(SPAN[1] - SPAN[0] + 1)
	mean_new /= float(SPAN[1] - SPAN[0] + 1)
	print("     wrist (16) error vs truth, every frame: raw %.1f cm | pre-fix straight line max %.1f cm (span mean %.1f) | joint-angle max %.2f cm (span mean %.2f)" % [e_raw * 100.0, e_old * 100.0, mean_old * 100.0, e_new * 100.0, mean_new * 100.0])
	ok(e_old > BAR, "1a the pre-fix straight-line fill misses the wrist by %.1f cm somewhere (must be > 5 cm: the instrument can move)" % (e_old * 100.0))
	ok(e_new <= BAR, "1b the joint-angle fill keeps the wrist within 5 cm of the truth at every frame: max %.2f cm (bar 5 cm)" % (e_new * 100.0))
	ok(max_err(new, 14) <= BAR, "1c the elbow (14) within 5 cm at every frame: max %.2f cm" % (max_err(new, 14) * 100.0))
	var bones_ok := true
	for k in range(SPAN[0], SPAN[1] + 1):
		var W: Array = new[k]["w"]
		bones_ok = bones_ok and absf((W[14] as Vector3).distance_to(W[12] as Vector3) - 0.30) < 1e-4 and absf((W[16] as Vector3).distance_to(W[14] as Vector3) - 0.27) < 1e-4
	ok(bones_ok, "1d the filled bones keep their lengths (0.30 m upper arm, 0.27 m forearm)")

	# ---- 2 KEEP
	var same := true
	var same_old := true
	for k in N:
		if k >= SPAN[0] and k <= SPAN[1]:
			continue
		for j in 33:
			if (new[k]["w"] as Array)[j] != (raw[k]["w"] as Array)[j]:
				same = false
			if (old[k]["w"] as Array)[j] != (raw[k]["w"] as Array)[j]:
				same_old = false
	ok(same and same_old, "2 the frames outside the span are bit-identical to the raw import and to the pre-fix repair")

	# ---- 3 START: the same arm lost from the first frame to 0.5 s
	var src3 := tracked([[[14, 16], 0]])
	for k in range(0, 16):
		var W3: Array = src3[k]["w"]
		var V3: Array = src3[k]["vis"]
		for j in [14, 16]:
			W3[j] = (truth(k)[j] as Vector3) + Vector3(0.25, 0.10, -0.20)
			V3[j] = 0.1
	var R3 := repaired(src3, true)
	var worst3 := 0.0
	for k in range(0, 16):
		var W: Array = R3[k]["w"]
		var rel: Vector3 = (W[16] as Vector3) - (W[12] as Vector3)
		var good: Vector3 = (truth(16)[16] as Vector3) - (truth(16)[12] as Vector3)
		worst3 = maxf(worst3, rel.distance_to(good))
	ok(worst3 < 1e-4, "3 a span at the start holds the first good pose: the wrist is the good pose's, relative to the shoulder (worst %.4f mm)" % (worst3 * 1000.0))

	# ---- 4 FOOT: the left foot lost, the right foot planted (static), the pelvis steady
	var src4 := tracked([[[25, 27, 29, 31], 0]])
	var old4 := repaired(src4, false)
	var new4 := repaired(src4, true)
	var ank_old := 0.0
	var ank_new := 0.0
	for k in range(SPAN[0], SPAN[1] + 1):
		ank_old = maxf(ank_old, ((old4[k]["w"] as Array)[27] as Vector3).distance_to(truth(k)[27] as Vector3))
		ank_new = maxf(ank_new, ((new4[k]["w"] as Array)[27] as Vector3).distance_to(truth(k)[27] as Vector3))
	print("     left ankle (27) in the span: pre-fix %.1f cm, planted hold %.2f cm" % [ank_old * 100.0, ank_new * 100.0])
	ok(ank_new <= 0.02, "4 the lost left foot stays planted (other foot planted, pelvis steady): ankle within 2 cm of the truth (worst %.2f cm)" % (ank_new * 100.0))

	# ---- 5 CLIP
	if FileAccess.file_exists(JJ):
		var P := VideoImport.parse(FileAccess.get_file_as_string(JJ))
		if not bool(P.get("ok", true)) or (P.get("frames", []) as Array).is_empty():
			print("     jumping jack: the pose file did not parse: %s" % str(P.get("why", "")))
		else:
			var B := Body.new()
			B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
			var P_old := VideoImport.parse(FileAccess.get_file_as_string(JJ))
			var P_new := VideoImport.parse(FileAccess.get_file_as_string(JJ))
			VideoIQ.ANGLE_FILL = false
			var R_old := VideoIQ.process(B, P_old, "", "jumping_jack_old")
			VideoIQ.ANGLE_FILL = true
			var R_new := VideoIQ.process(B, P_new, "", "jumping_jack")
			for lab in [["before (straight line)", R_old], ["after (joint angles)", R_new]]:
				var feet: Array = (lab[1]["conf"]["spans"] as Array).filter(func(s): return String(s["part"]).begins_with("foot"))
				print("     jumping jack %s: feet-lost spans %s" % [lab[0], "; ".join(feet.map(func(s): return s["text"])) if not feet.is_empty() else "none"])
				print("     jumping jack %s verdict: %s" % [lab[0], lab[1]["text"]])
			var n_changed := 0
			for k in (R_old["frames"] as Array).size():
				if (R_old["frames"][k]["w"] as Array) != (R_new["frames"][k]["w"] as Array):
					n_changed += 1
			print("     jumping jack: %d of %d frames differ between the two fills" % [n_changed, (R_old["frames"] as Array).size()])
	else:
		print("     jumping jack: no tracker json at %s (skipped, not a pass)" % JJ)

	print("LOST SPAN TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
