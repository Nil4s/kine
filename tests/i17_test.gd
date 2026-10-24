## godot --path . -s tests/i17_test.gd     (ROADMAP I17: learn my style, scripts/style_print.gd + style_ui.gd; needs a window)
## Four synthetic clips with KNOWN timings (written under user:// with the PID; the real scenes/ are only hashed). Bars, before measuring:
##  (1) the fingerprint recovers each kind's median move within 1 frame (1/30 s) and the median hold within 1 frame; from 4 clips;
##      every adjacent pair of the 4 clips is counted: guard>windup, windup>strike, strike>recover, recover>step, 4 times each; guard hands and stance are finite and plausible
##  (2) fewer than 3 clips: "not enough to learn from yet", and target() gives nothing
##  (3) like Nick: a new strike card (Add card) gets the learned strike time (within 1 frame); neutral: it keeps the default (-1 = auto)
##  (4) Use my style on a clip far from the medians: every changed card moves TOWARD its median (never away), every strike move
##      stays inside the timing coach's range (BeatFight.strike_range), every move >= the coach's minimum; >= 3 cards change
##  (5) Preview plays to its end and the scene JSON is byte-identical before and after
##  (6) Accept is ONE undo step; Ctrl+Z restores cards and scene JSON exactly
##  (7) the files: the real scenes/, poses/, data/ hash the same before and after; the panel is on screen with a row per kind
extends SceneTree

const FRAME := 1.0 / 30.0
var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func hashes() -> Dictionary:
	var out := {}
	for dir in ["res://scenes/", "res://poses/", "res://data/"]:
		var stack := [dir]
		while not stack.is_empty():
			var d: String = stack.pop_back()
			for fn in DirAccess.get_files_at(d):
				if fn.ends_with(".import") or fn.ends_with(".uid"):
					continue   # the engine's own import/uid files: any Godot run beside this one rewrites them (not the app's writes)
				out[d + fn] = FileAccess.get_md5(d + fn)
			for sub in DirAccess.get_directories_at(d):
				stack.append(d + sub + "/")
	return out


func med(v: Array) -> float:
	var a := v.duplicate()
	a.sort()
	return float(a[a.size() / 2]) if a.size() % 2 == 1 else 0.5 * (float(a[a.size() / 2 - 1]) + float(a[a.size() / 2]))


## a clip: [name, pose key, move, hold] per card
func clip_dict(cards: Array, poses: Dictionary, nm: String) -> Dictionary:
	var cs := []
	for c in cards:
		cs.append({"name": c[0], "pose": (poses[c[1]] as Dictionary).duplicate(true), "move": c[2], "hold": c[3]})
	return {"scene": nm, "fps": 30, "cards": cs}


func write(path: String, d: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()


func _init() -> void:
	var before_files := hashes()
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var B: Body = m.B
	var th: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scenes/thrust.json"))
	var poses := {"ready": th["cards"][0]["pose"], "chamber": th["cards"][6]["pose"], "thrust": th["cards"][9]["pose"]}
	var tmp := "user://zz_i17_%d/" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(tmp)
	# known timings: [wind-up, strike, recover, step] moves per clip; holds
	var W := [0.30, 0.34, 0.40, 0.36]
	var Sx := [0.10, 0.12, 0.14, 0.12]
	var R := [0.50, 0.60, 0.50, 0.70]
	var T := [0.40, 0.44, 0.36, 0.40]
	var SH := [0.05, 0.10, 0.05, 0.10]
	var paths := []
	for k in 4:
		var d := clip_dict([["guard ready", "ready", -1.0, 0.25], ["wind-up", "chamber", W[k], 0.10], ["strike", "thrust", Sx[k], SH[k]],
			["recover", "ready", R[k], 0.20], ["step forward", "ready", T[k], 0.15]], poses, "syn%d" % k)
		var p := tmp + "syn%d.json" % k
		write(p, d)
		paths.append(p)
	var tpath := tmp + "fp.json"

	# (1) the fingerprint
	var t0 := Time.get_ticks_usec()
	var fp := StylePrint.compute(paths, B)
	print("     fingerprint of 4 clips in %.0f ms: %s" % [(Time.get_ticks_usec() - t0) / 1000.0, JSON.stringify(fp)])
	var kinds: Dictionary = fp["kinds"]
	var want := {"windup": [W, [0.10]], "strike": [Sx, SH], "recover": [R, [0.20]], "step": [T, [0.15]]}
	var worst := 0.0
	for k in want:
		worst = maxf(worst, absf(float(kinds[k]["move"]) - med(want[k][0])))
		worst = maxf(worst, absf(float(kinds[k]["hold"]) - med(want[k][1])))
	var tr: Array = fp["transitions"]
	var g: Dictionary = fp["guard"]
	ok(int(fp["clips"]) == 4 and bool(fp["enough"]) and worst <= FRAME, "(1) from 4 clips; the worst median (move or hold) is %.1f ms off the known one (<= %.1f ms)" % [worst * 1000.0, FRAME * 1000.0])
	var tmap := {}
	for e in tr:
		tmap[String(e[0])] = int(e[1])
	ok(tmap.get("guard>windup", 0) == 4 and tmap.get("windup>strike", 0) == 4 and tmap.get("strike>recover", 0) == 4 and tmap.get("recover>step", 0) == 4, "(1) transitions %s" % [JSON.stringify(tr)])
	ok(absf(float(g["hand_cm"])) < 60.0 and float(g["stance"]) > 0.3 and float(g["stance"]) < 4.0 and int(g["n"]) == 4, "(1) guard hands %.1f cm from the chin, stance %.2f x hip width (%d guard cards)" % [g["hand_cm"], g["stance"], g["n"]])
	ok(StylePrint.save(fp, tpath) and JSON.stringify(StylePrint.load_print(tpath)) == JSON.stringify(JSON.parse_string(JSON.stringify(fp))), "(1) saved to a temp path under user:// and read back equal")

	# (2) not enough
	var fp2 := StylePrint.compute(paths.slice(0, 2), B)
	ok(not bool(fp2["enough"]) and StylePrint.source_text(2).contains("not enough") and StylePrint.target(fp2, "strike").is_empty() and StylePrint.source_text(4) == "from 4 clips", "(2) 2 clips: '%s'; 4 clips: '%s'" % [StylePrint.source_text(2), StylePrint.source_text(4)])

	# (3) a new strike card
	m.style_ui.dirs = [tmp]
	m.style_ui.path = tmpath_for(tmp)
	m.style_ui.fp = {}
	m.S.from_dict(clip_dict([["guard ready", "ready", -1.0, 0.25], ["wind-up", "chamber", 0.30, 0.10]], poses, "mine"))
	m._rebuild_cards()
	m.sel_card = 1
	m.ui_pose_name.text = "strike"
	m.style_ui.on = false
	m._card_add()
	var neutral_mv := float(m.S.cards[2]["move"])
	m.sel_card = 1
	m.S.cards.remove_at(2)
	m.style_ui.on = true
	m.ui_pose_name.text = "strike"
	m._card_add()
	var learned := float(m.S.cards[2]["move"])
	ok(absf(learned - float(kinds["strike"]["move"])) <= FRAME and neutral_mv < 0.0, "(3) new strike card: like Nick %.3f s (learned %.3f s); neutral %.1f (the default, auto)" % [learned, float(kinds["strike"]["move"]), neutral_mv])
	m.style_ui.on = false

	# (4) Use my style on a clip far from the medians
	var far := clip_dict([["guard ready", "ready", -1.0, 0.25], ["wind-up", "chamber", 0.90, 0.40], ["strike", "thrust", 0.30, 0.30],
		["recover", "ready", 0.20, 0.50], ["step forward", "ready", 1.00, 0.30]], poses, "far")
	m.S.from_dict(far)
	m._rebuild_cards()
	await idle()
	var S: Scene = m.S
	m.style_ui.fp = fp
	var rg := BeatFight.strike_range(S, B, 2)
	print("     the strike's human range: %.3f .. %.3f s (fist travel %.2f m)" % [rg[0], rg[1], rg[2]])
	var cards0 := JSON.stringify(S.cards)
	var before := JSON.stringify(S.to_dict(B, false))
	m.style_ui.use_style()
	await idle()
	var pl: Array = m.style_ui.pl
	var toward := true
	var inside := true
	for p in pl:
		var k := String(p["kind"])
		var md := float(kinds[k]["move"])
		toward = toward and absf(float(p["mv_to"]) - md) <= absf(float(p["mv_from"]) - md) + 0.0006
		toward = toward and absf(float(p["hd_to"]) - float(kinds[k]["hold"])) <= absf(float(p["hd_from"]) - float(kinds[k]["hold"])) + 0.0006
		inside = inside and float(p["mv_to"]) >= TimingCoach.MIN_MOVE
		if k == "strike":
			var r2 := BeatFight.strike_range(S, B, int(p["card"]))
			inside = inside and float(p["mv_to"]) >= float(r2[0]) - TimingCoach.TOL and float(p["mv_to"]) <= float(r2[1]) + TimingCoach.TOL
		print("       card %d %s move %.3f -> %.3f (median %.3f), hold %.2f -> %.2f" % [int(p["card"]) + 1, k, p["mv_from"], p["mv_to"], md, p["hd_from"], p["hd_to"]])
	ok(pl.size() >= 3 and toward and inside, "(4) %d cards planned; each moves toward its median (%s), strikes inside the coach's range, moves >= %.2f s (%s)" % [pl.size(), str(toward), TimingCoach.MIN_MOVE, str(inside)])
	ok(m.ui_find.visible and m.ui_find_list.find_child("style_accept", true, false) != null, "panel: Use my style shows Preview and Accept")

	# (5) preview
	m.style_ui.preview()
	var ticks := 0
	while m.style_ui.pv != null and ticks < 900:
		await process_frame
		ticks += 1
	ok(m.style_ui.pv == null and ticks > 5 and JSON.stringify(S.to_dict(B, false)) == before and JSON.stringify(S.cards) == cards0, "(5) the preview played %d frames; the scene JSON is byte-identical" % ticks)

	# (6) accept = one undo step
	var u0: int = m.undo.size()
	m.style_ui.accept()
	await idle()
	var changed := JSON.stringify(m.S.cards) != cards0
	ok(m.undo.size() == u0 + 1 and changed, "(6) Accept is one undo step (%d -> %d) and the cards changed" % [u0, m.undo.size()])
	var after_strike := float(m.S.cards[2]["move"])
	m._undo()
	await idle()
	ok(JSON.stringify(m.S.cards) == cards0 and JSON.stringify(m.S.to_dict(m.B, false)) == before, "(6) Ctrl+Z: cards and scene JSON exact (the strike was %.3f s, back to 0.300)" % after_strike)

	# (7) the panel and the files
	m.style_ui.show()
	await idle(3)
	var rows_ok := true
	for k in ["strike", "windup", "recover", "step"]:
		rows_ok = rows_ok and m.ui_find_list.find_child("style_row_" + k, true, false) != null
	var title: Label = m.ui_find_list.find_child("style_title", true, false)
	var pr: Rect2 = (m.ui_find.get_child(0) as Control).get_global_rect()
	var vr := Rect2(Vector2.ZERO, m.get_viewport().get_visible_rect().size)
	ok(rows_ok and title != null and title.text.contains("from 4 clips") and vr.encloses(pr.grow(-1.0)) and m.ui_find.visible, "(7) panel on screen at %s with a row per kind; title '%s'" % [str(pr), title.text if title != null else ""])
	var after_files := hashes()
	var same := after_files.size() == before_files.size()
	for k in before_files:
		same = same and after_files.get(k, "") == before_files[k]
	ok(same, "(7) %d files under scenes/, poses/, data/ hash the same before and after" % before_files.size())
	for fn in DirAccess.get_files_at(tmp):
		DirAccess.remove_absolute(tmp + fn)
	DirAccess.remove_absolute(tmp)
	print("I17 LEARN MY STYLE %s" % ("FAIL" if fails > 0 else "PASS") + (" (%d failed)" % fails if fails > 0 else ""))
	quit(1 if fails > 0 else 0)


func tmpath_for(dir: String) -> String:
	return dir + "fp_ui.json"
