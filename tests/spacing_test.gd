## godot --headless --path . -s tests/spacing_test.gd     (L96, ROADMAP_400 L24: a spacing chart from a real reference)
## SpacingChart (scripts/spacing_chart.gd) reads one joint's spacing from a TRACKED file (VideoImport.parse: the landmarks' world points) and from
## the user's clip (the joint's part keys, sampled at the scene's own frames), as the animator's spacing chart: where each frame's tick falls along
## the move (0..1 of the path length), by TIME (the move's normalised time), so a 30 fps reference and a 24 fps clip compare fairly. A per-frame
## difference is the step gap, in % of an EVEN step (one frame's share if the move were uniform). "Match spacing" (tool `spacing`, action match)
## re-times the in-betweens inside each key-to-key segment to the reference's ease: in-between keys (ktype inbetween) at the clip's frames; the keys
## themselves are never touched. The reference here is a synthetic tracker file written in the tracker's own format (tools/see_video.py pose.json:
## fps, frames[{t, world[33][3] MediaPipe axes y down, image}]) whose wrist (landmark 15) moves 0.6 m along x on a cubic ease-in-out sampled at 30 fps.
## The clip: joint upperarm_l, two LINEAR keys, 0 -> 60 deg.
##   1 REFERENCE   the spacing recovered from the file matches the known ease at its own 30 frames: every step within 2 % of an even step
##   2 CONTROL     the linear clip against that reference differs by more than 20 % of an even step (before matching)
##   3 MATCH       after Match spacing the 24 fps clip is within 5 % of an even step per frame of the known ease AND of the reference chart;
##                 the shape reads in-out (peak step 2.7..3.3 x an even step; the linear clip reads 1.0)
##   4 KEYS        the key poses are byte-identical (var_to_str of every ktype-key dict), in-between keys are ktype inbetween and sit on frames
##   5 TIME        a 1.5 s clip at 24 fps, and a 2.0 s clip at 60 fps, against the same 1.0 s / 30 fps reference: within 5 % each
##   6 UNDO        match adds exactly ONE undo step; read adds none; a second match is idempotent (same in-between count, within 5 %), one step
##   7 STRIP       SpacingStrip's ticks: reference row x == progress, clip row x == progress, every tick inside the strip, rows apart
##   8 REFUSALS    no file, an unknown joint, a landmark out of range, a joint with one key: refused with a sentence, no undo step, scene unchanged
extends SceneTree

var fails := 0
const LM := 15


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func ease_io(t: float) -> float:
	return 4.0 * t * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0


## the tracker's pose.json: standing person (hips 23/24, shoulders 11/12, ankles 27/28; y DOWN), the wrist travelling 0.6 m on x by the ease
func write_ref(path: String, fps: float, dur: float) -> void:
	var frames := []
	var n := int(round(dur * fps))
	for i in n + 1:
		var t := float(i) / fps
		var w := []
		for k in 33:
			w.append([0.0, 0.0, 0.0])
		w[23] = [0.1, 0.0, 0.0]
		w[24] = [-0.1, 0.0, 0.0]
		w[11] = [0.2, -0.5, 0.0]
		w[12] = [-0.2, -0.5, 0.0]
		w[27] = [0.1, 0.9, 0.0]
		w[28] = [-0.1, 0.9, 0.0]
		w[LM] = [0.3 + 0.6 * ease_io(t / dur), -0.2, 0.0]
		frames.append({"t": t, "world": w, "image": []})
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"fps": fps, "video": "synthetic cubic ease-in-out", "size": [640, 480], "frames": frames}))
	f.close()


func mk(fps: int, dur: float, interp: String) -> Scene:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	var S := Scene.new()
	S.add("a", B.to_dict())
	S.fps = fps
	S.part_keys = {"upperarm_l": [{"t": 0.0, "v": Vector3(0, 0, 0), "interp": interp}, {"t": dur, "v": Vector3(60, 0, 0)}]}
	return S


func key_dump(S: Scene) -> String:
	var o := []
	for k in S.part_keys["upperarm_l"]:
		if PartKeys.ktype_of(k) == "key":
			o.append(k)
	return var_to_str(o)


## worst |step - known step| over the clip's frames, in % of an even step, the known ease at the clip's frame times
func vs_truth(S: Scene, dur: float) -> float:
	var c := SpacingChart.clip_track(S, "upperarm_l")
	var pr := SpacingChart.progress(c)
	var n := pr.size() - 1
	var worst := 0.0
	for i in n:
		var known := ease_io(float(c["t"][i + 1]) / dur) - ease_io(float(c["t"][i]) / dur)
		worst = maxf(worst, absf((pr[i + 1] - pr[i]) - known) * float(n) * 100.0)
	return worst


func _init() -> void:
	var gs := GDScript.new()
	gs.source_code = "extends Node\nvar S\nvar undo := []\nfunc _push_undo() -> void:\n\tundo.append(var_to_str(S.part_keys))\n"
	gs.reload()
	var m: Node = gs.new()
	var rp := "user://spacing_ref30.json"
	write_ref(rp, 30.0, 1.0)
	var P := VideoImport.load_file(rp)
	ok(P["ok"], "0 the synthetic tracker file reads (%s)" % P.get("why", ""))
	if not P["ok"]:
		quit(1)
		return
	# 1 reference
	var R := SpacingChart.ref_track(P, LM)
	var rpg := SpacingChart.progress(R)
	var nr := rpg.size() - 1
	var w1 := 0.0
	for i in nr:
		var known := ease_io(float(i + 1) / float(nr)) - ease_io(float(i) / float(nr))
		w1 = maxf(w1, absf((rpg[i + 1] - rpg[i]) - known) * float(nr) * 100.0)
	ok(nr == 30 and w1 <= 2.0, "1 reference recovered from the file: %d steps, worst step error %.3f %% of an even step (<= 2)" % [nr, w1])
	# 2 control
	var S := mk(24, 1.0, "linear")
	m.S = S
	var cmp0 := SpacingChart.compare(R, SpacingChart.clip_track(S, "upperarm_l"))
	ok(float(cmp0["max_pct"]) > 20.0 and absf(float(cmp0["clip_peak"]) - 1.0) < 0.01, "2 CONTROL the linear clip differs by %.1f %% of an even step (> 20); its peak step is %.3f x even" % [cmp0["max_pct"], cmp0["clip_peak"]])
	# 3 match, 4 keys
	var keys0 := key_dump(S)
	var u0: int = m.undo.size()
	var rd: Dictionary = SpacingChart.serve(m, {"action": "read", "joint": "upperarm_l", "ref": rp, "landmark": LM})
	var u_read: int = m.undo.size() - u0
	var r: Dictionary = SpacingChart.serve(m, {"action": "match", "joint": "upperarm_l", "ref": rp, "landmark": LM})
	var u_match: int = m.undo.size() - u0 - u_read
	var truth := vs_truth(S, 1.0)
	var cmp1 := SpacingChart.compare(R, SpacingChart.clip_track(S, "upperarm_l"))
	ok(rd["ok"] and r["ok"] and truth <= 5.0 and float(cmp1["max_pct"]) <= 5.0, "3 MATCH 24 fps clip: %.3f %% vs the known ease, %.3f %% vs the reference chart (both <= 5); before %.1f %%" % [truth, cmp1["max_pct"], cmp0["max_pct"]])
	ok(float(cmp1["clip_peak"]) > 2.7 and float(cmp1["clip_peak"]) < 3.3 and String(cmp1["clip_shape"]) == "in-out", "3 the shape reads %s, clip peak %.3f x even, reference peak %.3f x even (2.7..3.3)" % [cmp1["clip_shape"], cmp1["clip_peak"], cmp1["ref_peak"]])
	var ib := 0
	var on_frame := true
	for k in S.part_keys["upperarm_l"]:
		if PartKeys.ktype_of(k) == "inbetween":
			ib += 1
			on_frame = on_frame and absf(float(k["t"]) * 24.0 - roundf(float(k["t"]) * 24.0)) < 1e-6
	ok(key_dump(S) == keys0 and ib == 23 and on_frame, "4 KEYS the 2 key poses are byte-identical; %d in-between keys (23), all on 24 fps frames" % ib)
	# 6 undo
	ok(u_read == 0 and u_match == 1, "6 UNDO read adds %d steps (0), match adds %d (1)" % [u_read, u_match])
	var u1: int = m.undo.size()
	var r2: Dictionary = SpacingChart.serve(m, {"action": "match", "joint": "upperarm_l", "ref": rp, "landmark": LM})
	var ib2 := 0
	for k in S.part_keys["upperarm_l"]:
		if PartKeys.ktype_of(k) == "inbetween":
			ib2 += 1
	var cmp2 := SpacingChart.compare(R, SpacingChart.clip_track(S, "upperarm_l"))
	ok(r2["ok"] and m.undo.size() - u1 == 1 and ib2 == ib and float(cmp2["max_pct"]) <= 5.0 and key_dump(S) == keys0, "6 a second match is idempotent: %d in-betweens (%d), %.3f %%, one step" % [ib2, ib, cmp2["max_pct"]])
	# 7 strip
	var strip := SpacingStrip.new()
	strip.size = Vector2(600, 80)
	strip.set_data(cmp1)
	var tk: Array = strip.ticks()
	var okx := true
	var inside := true
	var rows := {}
	var nref := 0
	var nclip := 0
	for t in tk:
		var rc: Rect2 = t["rect"]
		inside = inside and Rect2(Vector2.ZERO, strip.size).encloses(rc)
		rows[snappedf(rc.position.y, 0.01)] = true
		if t["row"] == "ref":
			okx = okx and absf(rc.get_center().x - float((cmp1["ticks_ref"] as Array)[nref]) * strip.size.x) < 3.0
			nref += 1
		else:
			okx = okx and absf(rc.get_center().x - float((cmp1["ticks_clip"] as Array)[nclip]) * strip.size.x) < 3.0
			nclip += 1
	ok(okx and inside and rows.size() == 2 and nref == 31 and nclip == 25, "7 STRIP %d reference ticks (31), %d clip ticks (25), x == progress within 3 px, all inside, 2 rows" % [nref, nclip])
	strip.free()
	# 5 time
	for cs in [[24, 1.5], [60, 2.0]]:
		var S2 := mk(int(cs[0]), float(cs[1]), "linear")
		m.S = S2
		var r5: Dictionary = SpacingChart.serve(m, {"action": "match", "joint": "upperarm_l", "ref": rp, "landmark": LM})
		var tr := vs_truth(S2, float(cs[1]))
		var c5 := SpacingChart.compare(R, SpacingChart.clip_track(S2, "upperarm_l"))
		ok(r5["ok"] and tr <= 5.0 and float(c5["max_pct"]) <= 5.0, "5 TIME %d fps, %.1f s clip vs 30 fps, 1.0 s reference: %.3f %% vs known, %.3f %% vs chart (<= 5)" % [cs[0], cs[1], tr, c5["max_pct"]])
	# 8 refusals
	var S3 := mk(24, 1.0, "linear")
	S3.part_keys["hand_l"] = [{"t": 0.0, "v": Vector3(1, 0, 0)}]
	m.S = S3
	var before := var_to_str(S3.part_keys)
	var u3: int = m.undo.size()
	var bad := [
		{"action": "match", "joint": "upperarm_l", "ref": "user://no_such_file.json", "landmark": LM},
		{"action": "match", "joint": "no_such_joint", "ref": rp, "landmark": LM},
		{"action": "match", "joint": "upperarm_l", "ref": rp, "landmark": 99},
		{"action": "match", "joint": "hand_l", "ref": rp, "landmark": LM},
	]
	var refused := 0
	for b in bad:
		var rb: Dictionary = SpacingChart.serve(m, b)
		if not rb["ok"] and String(rb["error"]).length() > 10:
			refused += 1
	ok(refused == 4 and m.undo.size() == u3 and var_to_str(S3.part_keys) == before, "8 REFUSALS %d of 4 refused with a sentence, %d undo steps (0), scene unchanged" % [refused, m.undo.size() - u3])
	print("spacing_test: %d fail" % fails)
	quit(1 if fails > 0 else 0)
