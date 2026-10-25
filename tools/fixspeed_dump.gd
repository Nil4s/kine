## godot --headless --path . -s tools/fixspeed_dump.gd -- OUTDIR
## Profiles the Fix buttons on scenes/axe_strike_pose.json (a copy in user://): every fixable finding on a FRESH copy
## (its own Fixer.apply, timed, with the FrameMemo stage times), then one Fix all (main's _fix_all, real). Writes into OUTDIR:
##   fix_<k>.var (the cards after that fix, var_to_str), summary.json (per fix: rule, time, kept, msg, stages), fixall.var
##   (the cards after Fix all), fixall_findings.var (the findings after it), fixall.json (the run's numbers).
extends SceneTree

const SRC := "res://scenes/axe_strike_pose.json"
const COPY := "user://fixspeed_dump_copy.json"

var m: Node


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func fresh() -> void:
	DirAccess.copy_absolute(ProjectSettings.globalize_path(SRC), ProjectSettings.globalize_path(COPY))
	m._load_scene(COPY)
	m._rebuild_cards()
	m._check()
	await idle(3)


func write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _init() -> void:
	var outdir := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			outdir = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(outdir)
	Rulebook.audit = "--audit" in OS.get_cmdline_user_args()   # every candidate's windowed sample vs a full one (counts in the log)
	root.size = Vector2i(1280, 720)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(5)
	await fresh()
	var n0: int = m.findings.size()
	var summary := []
	for k in n0:
		if Fixer.label(m.findings[k], m.S) == "":
			continue
		await fresh()
		var f: Dictionary = m.findings[k]
		FrameMemo.prof = {}
		var t0 := Time.get_ticks_usec()
		var r: Dictionary = Fixer.apply(f, m.S, m.ov.GB, m._sm)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		var cards := var_to_str(m.S.cards)
		write(outdir + "/fix_%d.var" % k, cards)
		var prof := {}
		for key in FrameMemo.prof:
			prof[key] = snappedf(float(FrameMemo.prof[key]), 0.1)
		summary.append({"k": k, "rule": f["rule"], "t": snappedf(f["t"], 0.01), "card": f["card"], "ms": snappedf(ms, 0.1),
			"kept": r["kept"], "msg": r["msg"], "md5": cards.md5_text(), "prof": prof})
		print("fix %d %s %.2f s card %d: %.0f ms kept=%s" % [k, f["rule"], f["t"], f["card"] + 1, ms, r["kept"]])
	write(outdir + "/summary.json", JSON.stringify(summary, "  "))

	await fresh()
	var t1 := Time.get_ticks_msec()
	await m._fix_all()
	var run: Dictionary = m.get("_fixall_last")
	var run_ms := Time.get_ticks_msec() - t1
	write(outdir + "/fixall.var", var_to_str(m.S.cards))
	write(outdir + "/fixall_findings.var", var_to_str(m.findings))
	write(outdir + "/fixall.json", JSON.stringify({"tried": run["tried"], "kept": run["kept"], "worst_ms": run["worst_ms"],
		"ms": run_ms, "refused": run["refused"], "not_reached": run["not_reached"], "no_fix": run["no_fix"],
		"findings_after": m.findings.size()}, "  "))
	print("fix all: tried %d kept %d worst %d ms total %d ms, findings after %d" % [run["tried"], run["kept"], run["worst_ms"], run_ms, m.findings.size()])
	print("audit: %d candidate samples/findings compared, %d differences" % [Rulebook.audit_n, Rulebook.audit_diff])
	if FileAccess.file_exists(COPY):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(COPY))
	quit(0)
