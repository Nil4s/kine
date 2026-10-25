## godot --headless --path . -s tests/weightxfer_test.gd     (N029 WEIGHT TRANSFER, scripts/weight_xfer.gd)
## In a combo, each strike needs the weight where it starts. Bars, stated before measuring:
##   1 BAD CROSS: a hand-posed orthodox cross (rear right hand) whose guard card carries 70 % (65-75) on the LEAD (left)
##     foot is flagged WEIGHT TRANSFER (WARN) at the cross, with its rear share under 0.45; the finding has a Fix label.
##   2 THE FIX: Fixer.apply on it is kept, the finding is gone, and the cross now STARTS with at least 55 % on the rear
##     (right) foot (measured again by WeightXfer.strikes on the fixed scene); no card added, removed or renamed.
##   3 GOOD CROSS: the same cross from a guard with 60 % (55-65) on the rear foot is not flagged.
##   4 ROUNDHOUSE: a right (rear) roundhouse whose guard card carries 75 % on the kicking (right) leg is flagged at lift-off
##     with under 50 % on the support (left) foot; the same kick from a guard with 70 % on the support foot is not.
##   5 LEAD HOOK: a left (lead) hook from a guard with 75 % on the rear foot is flagged; from 60 % on the lead it is not.
##   6 THE SCENES: combo3 and every scenes/*.json (read only; and the recognizer test's text-blocked clips when it left them): each graded strike and each finding is PRINTED with its
##     numbers (class, side, moment, share, bar) to be judged by eye in the report; the bar here is only that the run
##     completes and nothing is written (the files' bytes are unchanged).
##   7 ONE UNDO STEP: in the app (main.tscn, headless), the bad cross opened, Check lists WEIGHT TRANSFER, its Fix (the
##     panel's own m._fix) adds exactly ONE undo step, and one Ctrl+Z (m._undo) brings the cards back byte for byte.
##   8 SERVE: AgentTools.findings() lists the rule with its fix words (what `check` serves).
extends SceneTree

var fails := 0
var t_start := Time.get_ticks_msec()
var B: Body
var stance := {"_l": [Vector3(0.12, 0.0152, 0.28), 0.0], "_r": [Vector3(-0.14, 0.0152, -0.18), 0.5]}
const BOTH := ["_l", "_r"]
const LEFT := ["_l"]


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what + "   [%.0f s]" % ((Time.get_ticks_msec() - t_start) / 1000.0))
	if not c:
		fails += 1


## the recognizer test's guard stance (tests/recognize_test.gd): left foot forward, both fists at the chin
## dz: both stance spots moved this far along z (forward = +), so the same pose stands with its weight further back
## (dz > 0) or further over the lead foot (dz < 0): the clip's weight split is set by where the feet are, not by a lean
func pose(angs: Dictionary, plant := ["_l", "_r"], dz := 0.0) -> Dictionary:
	for j in B.ang:
		B.ang[j] = Vector3.ZERO
	B.offset = Vector3(0, -0.04, 0)
	var base := {"thigh_l": Vector3(20, 0, 0), "calf_l": Vector3(15, 0, 0), "thigh_r": Vector3(-15, 0, 0), "calf_r": Vector3(10, 0, 0),
		"upperarm_l": Vector3(35, -55, 0), "lowerarm_l": Vector3(135, 0, 0), "upperarm_r": Vector3(35, -55, 0), "lowerarm_r": Vector3(135, 0, 0)}
	for j in base:
		B.ang[j] = base[j]
	for j in angs:
		B.ang[j] = B.clamp_ang(j, angs[j])
	B.fk()
	for sd in plant:
		B.plant(sd, stance[sd][0] + Vector3(0, 0, dz), stance[sd][1], true)
	return B.to_dict()


## the stance shift dz that gives the guard `left` of its weight on the LEFT (lead) foot (bisection, 16 steps)
func dz_for(left: float) -> float:
	var lo := -0.4
	var hi := 0.4
	for i in 16:
		var mid := (lo + hi) * 0.5
		if left_of(pose({}, BOTH, mid)) > left:
			lo = mid   # still too much on the lead: the feet go further forward
		else:
			hi = mid
	return (lo + hi) * 0.5


func left_of(p: Dictionary) -> float:
	Scene.put(B, Moves._flat(p))
	B.fk()
	return TextView.left_share(B, Balance.com(B))


func clip(nm: String, keys: Array, dz := 0.0) -> Scene:
	var S := Scene.new()
	S.name = nm
	for k in keys:
		var p: Dictionary = pose(k[1], k[2], dz)
		S.cards.append({"name": k[0], "pose": p, "move": k[3], "hold": k[4]})
	S.cards[0]["move"] = -1.0
	return S


func cross(left: float) -> Scene:
	var g := {}
	var dz := dz_for(left)
	return clip("cross", [["guard", g, BOTH, 0, 0.3], ["cross", {"upperarm_r": Vector3(85, -5, 0), "lowerarm_r": Vector3(5, 0, 0),
		"pelvis": Vector3(0, 0, 30), "spine_03": Vector3(0, 0, 15)}, BOTH, 0.15, 0.1], ["guard", g, BOTH, 0.3, 0.3]], dz)


func hook(left: float) -> Scene:
	var g := {}
	var dz := dz_for(left)
	return clip("hook", [["guard", g, BOTH, 0, 0.3], ["load", {"upperarm_l": Vector3(20, -5, 0), "lowerarm_l": Vector3(90, 0, 0), "pelvis": Vector3(0, 0, 15)}, BOTH, 0.2, 0.05],
		["hook", {"upperarm_l": Vector3(75, 0, 0), "lowerarm_l": Vector3(90, 0, 0), "pelvis": Vector3(0, 0, -30), "spine_03": Vector3(0, 0, -15)}, BOTH, 0.15, 0.1],
		["guard", g, BOTH, 0.3, 0.3]], dz)


func roundhouse(left: float) -> Scene:
	var g := {}
	var dz := dz_for(left)
	return clip("roundhouse", [["guard", g, BOTH, 0, 0.3], ["chamber", {"pelvis": Vector3(0, 20, 20), "thigh_r": Vector3(40, 45, 0), "calf_r": Vector3(120, 0, 0)}, LEFT, 0.2, 0.0],
		["roundhouse", {"pelvis": Vector3(0, 35, 110), "thigh_r": Vector3(20, 45, 0), "calf_r": Vector3(5, 0, 0)}, LEFT, 0.15, 0.1],
		["guard", g, BOTH, 0.35, 0.3]], dz)


func wx(S: Scene) -> Array:
	return Rulebook.check(S, B).filter(func(f): return f["rule"] == "WEIGHT TRANSFER")


func graded(S: Scene, cls: String) -> Dictionary:
	for it in WeightXfer.strikes(S, B):
		if it["class"] == cls:
			return it
	return {}


func show(it: Dictionary) -> String:
	if it.is_empty():
		return "(not graded)"
	return "%s %s, %s at %.2f s: %.0f %% on the %s (%s) foot, bar %.0f %%" % [it["class"], "left" if it["side"] == "_l" else "right", it["when"], it["t"],
		float(it["share"]) * 100.0, it["role"], "left" if it["need"] == "_l" else "right", float(it["bar"]) * 100.0]


func _init() -> void:
	B = Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var g0 := pose({})
	print("the plain guard: %.0f %% on the left (lead) foot" % (left_of(g0) * 100.0))

	# 1 + 2
	var bad := cross(0.70)
	var gl := left_of(bad.cards[0]["pose"])
	var it0 := graded(bad, "cross")
	print("bad cross: guard %.0f %% lead; %s" % [gl * 100.0, show(it0)])
	var fs := wx(bad)
	ok(gl >= 0.65 and gl <= 0.75 and fs.size() == 1 and fs[0]["sev"] == "WARN" and float(fs[0]["v"]) < 0.45 and Fixer.label(fs[0], bad) != "",
		"1 the cross from %.0f %% on the lead foot is flagged (%d finding: %s) [fix: %s]" % [gl * 100.0, fs.size(), fs[0]["msg"] if fs.size() > 0 else "-", Fixer.label(fs[0], bad) if fs.size() > 0 else "-"])
	if fs.size() > 0:
		var names := bad.cards.map(func(c): return c["name"])
		var r := Fixer.apply(fs[0], bad, B)
		var it1 := graded(bad, "cross")
		print("  %s" % r["msg"])
		print("  after: %s" % show(it1))
		ok(r["kept"] and wx(bad).is_empty() and not it1.is_empty() and float(it1["share"]) >= 0.55 and bad.cards.map(func(c): return c["name"]) == names,
			"2 the fix is kept, the finding gone, the cross starts with %.0f %% on the rear foot (bar 55 %%)" % (float(it1.get("share", 0.0)) * 100.0))
	else:
		ok(false, "2 no finding to fix")

	# 3
	var good := cross(0.40)
	print("good cross: guard %.0f %% lead; %s" % [left_of(good.cards[0]["pose"]) * 100.0, show(graded(good, "cross"))])
	ok(wx(good).is_empty() and not graded(good, "cross").is_empty(), "3 the cross from 60 %% on the rear foot is graded and not flagged")

	# 4
	var rb := roundhouse(0.25)
	var rg := roundhouse(0.70)
	var ib := graded(rb, "roundhouse")
	var ig := graded(rg, "roundhouse")
	print("roundhouse, weight on the kicking leg: %s" % show(ib))
	print("roundhouse, weight on the support: %s" % show(ig))
	var fb := wx(rb)
	ok(fb.size() == 1 and float(fb[0]["v"]) < 0.5 and fb[0]["role"] == "support" and wx(rg).is_empty() and not ig.is_empty(),
		"4 the roundhouse lifting off with the weight on the kicking leg is flagged (%s); with 70 %% on the support it is not" % (fb[0]["msg"] if fb.size() > 0 else "no finding"))
	if fb.size() > 0:
		var r4 := Fixer.apply(fb[0], rb, B)
		print("  roundhouse fix: %s; after: %s" % [r4["msg"], show(graded(rb, "roundhouse"))])

	# 5
	var hb := hook(0.25)
	var hg := hook(0.60)
	print("lead hook from the rear foot: %s" % show(graded(hb, "hook")))
	print("lead hook from the lead foot: %s" % show(graded(hg, "hook")))
	ok(wx(hb).size() == 1 and wx(hg).is_empty() and not graded(hg, "hook").is_empty(), "5 the lead hook from 75 %% on the rear foot is flagged; from 60 %% on the lead it is not")

	# 6
	var files := []
	for f in DirAccess.get_files_at("res://scenes"):
		if String(f).ends_with(".json"):
			files.append("res://scenes/" + f)
	files.sort()
	var nscenes := files.size()
	# the recognizer test's text-blocked clips (tests/recognize_test.gd keeps them in user://recognize_tb/<key>/), when present:
	# the only UNARMED clips on this machine built by Kine itself (every scenes/ file holds a weapon)
	if DirAccess.dir_exists_absolute("user://recognize_tb"):
		for dk in DirAccess.get_directories_at("user://recognize_tb"):
			for f in DirAccess.get_files_at("user://recognize_tb/" + dk):
				if String(f).ends_with(".json"):
					files.append("user://recognize_tb/%s/%s" % [dk, f])
	var ran := true
	for path in files:
		var bytes := FileAccess.get_file_as_bytes(path)
		var S := Scene.new()
		S.from_dict(JSON.parse_string(bytes.get_string_from_utf8()))
		if S.cards.size() < 2:
			continue
		var t0 := Time.get_ticks_msec()
		var st := WeightXfer.strikes(S, B)
		var ff := WeightXfer.findings(S, B)
		print("  %s: %d graded, %d flagged [%d ms]" % [path.get_file(), st.size(), ff.size(), Time.get_ticks_msec() - t0])
		for it in st:
			print("    card %d: %s" % [int(it["card"]) + 1, show(it)])
		for f in ff:
			print("    FLAG %s" % f["msg"])
		ran = ran and FileAccess.get_file_as_bytes(path) == bytes
	ok(ran, "6 every scene in scenes/ graded and listed above, no file written (%d scenes + %d text-blocked clips)" % [nscenes, files.size() - nscenes])

	# 7 + 8
	var path := "res://scenes/_wip/zz_weightxfer.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://scenes/_wip"))   # gitignored: a fresh clone has none
	var src := cross(0.70)
	var fw := FileAccess.open(path, FileAccess.WRITE)
	fw.store_string(JSON.stringify(src.to_dict(B)))
	fw.close()
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	m._load_scene(path)
	m._rebuild_cards()
	var T := AgentTools.new(m)
	var served: Array = T.findings().filter(func(x): return x["rule"] == "WEIGHT TRANSFER")
	ok(served.size() == 1 and String(served[0]["fix"]).begins_with("Fix: shift the weight"), "8 serve's check lists it: %s" % [served])
	var mf: Array = m.findings.filter(func(x): return x["rule"] == "WEIGHT TRANSFER")
	if mf.size() == 1:
		var c0 := JSON.stringify(m.S.cards)
		var u0: int = m.undo.size()
		await m._fix(mf[0])
		var u1: int = m.undo.size()
		var changed := JSON.stringify(m.S.cards) != c0
		m._undo()
		ok(changed and u1 - u0 == 1 and JSON.stringify(m.S.cards) == c0, "7 the Fix in the app: cards changed %s, undo steps +%d, one Ctrl+Z restores the cards %s" % [changed, u1 - u0, JSON.stringify(m.S.cards) == c0])
	else:
		ok(false, "7 the app's Check did not list one WEIGHT TRANSFER (%d)" % mf.size())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	m.queue_free()
	await process_frame
	print("WEIGHTXFER TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
