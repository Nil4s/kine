## godot --path . -s tests/r7_test.gd     (ROADMAP round 2, R7; needs a window: the final shot is a real frame)
## COLD START: a "naive agent" that knows NOTHING about the UI reaches "a punch that lands" from an empty scene.
## What it may see: the command registry's public listing (the `commands` method: id, name, keys, edits, desc; the same rows the
## command palette and poser_cli show) and the "Next:" line (next_step(), R6) which it may also click. It picks by KEYWORD SCORE only
## (the goal's words against each command's name x2 and description x1, rarer words in the registry weigh more); no command id is
## written in this agent. It reads the status line after a step, not the scene.
## Goal (the ORACLE, which the agent cannot see): the CONTACT card = the card the fist travels fastest into; the fist (hand capsule)
## ends within 5 cm of the dummy's head capsule's skin (gap = capsule distance - radii, in [-4 cm, +5 cm]: touching or just short,
## not buried) AND the Check is fresh with no must-fix.
## BARS (written before measuring): 1 goal reached in <= 40 steps; 2 every dead end is listed with what the agent saw (this test
## prints them; the bar is that each one found was fixed or is named as a limit in the report); 3 PLACEMENT: in the final frame the
## hero's feet and head, the dummy's feet and head and the fist are all inside the 3D view (below the ribbon, above the page bar).
extends SceneTree

const GOAL := "a punch that lands on the dummy's head"
const STOP := ["a", "an", "the", "that", "whose", "to", "of", "and", "in", "on", "it", "is", "for", "with", "from", "at", "by", "or", "as", "this", "its", "one", "are", "be", "any", "into", "then", "now"]
const BUDGET := 40
const HARD := 70
const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/r7.png"
## test hygiene, not agent knowledge: a command whose id has any of these would write outside scenes/_wip or user:// or open hardware
const UNSAFE := ["export", "save", "webcam", "live", "video", "import", "audio", "co_edit", "share", "restore", "plugin", "ask_ai", "review", "playblast", "render", "batch", "camera_", "lip_sync", "version"]

var m: Node
var A: AgentTools
var fails := 0
var Bs := Body.new()
var cmds: Array = []
var idf := {}
var goal_words: Array = []
var tried := {}        # command id -> times run
var dead_ids := {}     # command id -> true: run once and moved nothing
var next_dead := {}    # Next text -> times it was clicked and moved nothing
var trace: Array = []
var dead_ends: Array = []
var wip_before := []
var stuck := false
var said_last := ""


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


# ---- the agent's reading -----------------------------------------------------------------------------------------------
func stem(w: String) -> String:
	if w.ends_with("ches") or w.ends_with("shes"):
		return w.left(-2)
	if w.length() > 3 and w.ends_with("s") and not w.ends_with("ss"):
		return w.left(-1)
	return w


func words(t: String) -> Array:
	var out := []
	var cur := ""
	for ch in t.to_lower() + " ":
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			cur += ch
		else:
			if cur.length() >= 3 and not cur in STOP:
				var s := stem(cur)
				if not s in out:
					out.append(s)
			cur = ""
	return out


func learn_registry() -> void:
	var r: Dictionary = await A.request(1, "commands", {})
	cmds = r["result"]
	var df := {}
	for c in cmds:
		c["nw"] = words(String(c["name"]))
		c["dw"] = words(String(c["desc"]))
		for w in (c["nw"] + c["dw"]):
			df[w] = int(df.get(w, 0)) + 1
	for w in df:
		idf[w] = log((cmds.size() + 1.0) / (float(df[w]) + 1.0))
	goal_words = words(GOAL)


func score_text(nw: Array, dw: Array) -> float:
	var s := 0.0
	for w in goal_words:
		var k: float = float(idf.get(w, 0.0))
		if w in nw:
			s += 2.0 * k
		if w in dw:
			s += k
	return s


func next_text() -> String:
	return String(m.ui_next.text).trim_prefix("Next:  ")


## the agent's pick: {"kind": "cmd"/"next", "id", "score"}
func choose() -> Dictionary:
	var nt := next_text()
	var nw := words(nt)
	var best := {"kind": "next", "id": "", "score": 12.0 + 2.0 * score_text([], nw) - 8.0 * int(next_dead.get(nt, 0))}
	for c in cmds:
		var id: String = c["id"]
		if dead_ids.has(id):
			continue
		var s := score_text(c["nw"], c["dw"]) - 6.0 * int(tried.get(id, 0))
		if String(c["name"]).to_lower() in said_last.to_lower():
			s += 10.0   # the last status line names this command: the app is saying what to press
		# the Next line names a step in words: a command whose NAME is in the line is that step
		if s > float(best["score"]) and s > 0.0:
			best = {"kind": "cmd", "id": id, "score": s}
	if best["kind"] == "next" and float(best["score"]) <= 0.0:
		return {"kind": "stuck", "id": "", "score": 0.0}   # the Next line was followed and led nowhere, and no command matches the goal
	return best


# ---- the oracle (the agent never reads it) -----------------------------------------------------------------------------
func fist_state() -> Dictionary:
	if m.S.cards.size() < 2:
		return {}
	var ts: Array = m.S.times()
	var prev := {}
	var best := {}
	for i in m.S.cards.size():
		m.S.apply(Bs, float(ts[i][1]))
		var cur := {"hand_r": Bs.P["hand_r"], "hand_l": Bs.P["hand_l"]}
		if i > 0:
			var dt := maxf(m.S.move_time(i), 1.0 / 30.0)
			for h in ["hand_r", "hand_l"]:
				var v: float = ((cur[h] as Vector3) - (prev[h] as Vector3)).length() / dt
				if best.is_empty() or v > float(best["v"]):
					var hc: Array = Bs.cap(h)
					var hd: Array = m.T.cap("head")
					var gap: float = Body.seg_seg(hc[0], hc[1], hd[0], hd[1]) - float(Bs.rad[h]) - float(m.T.D.rad["head"])
					best = {"card": i, "hand": h, "v": v, "gap": gap, "t": float(ts[i][1]), "tip": (hc[1] as Vector3)}
		prev = cur
	return best


func nfails() -> int:
	return m.findings.filter(func(f): return f["sev"] == "FAIL").size()


func fresh() -> bool:
	return m.check_ran and m.check_at == m.undo.size()


func score() -> float:
	var s := float(mini(m.S.cards.size(), 2))
	var f := fist_state()
	if not f.is_empty() and float(f["v"]) >= 3.0:
		s += 1.0 + 2.0 * (1.0 - minf(maxf(float(f["gap"]), 0.0), 1.5) / 1.5)
	if fresh():
		s -= 0.3 * nfails()
	if landed():
		s += 3.0
	return s


func landed() -> bool:
	var f := fist_state()
	if f.is_empty() or float(f["v"]) < 3.0:
		return false
	return float(f["gap"]) <= 0.05 and float(f["gap"]) >= -0.04 and fresh() and nfails() == 0


func open_dialogs() -> Array:
	var out := []
	for w in root.find_children("*", "Window", true, false):
		if w != root and (w as Window).visible:
			out.append(w)
	return out


func wip_files() -> Array:
	var out := []
	var d := DirAccess.open("res://scenes/_wip")
	if d != null:
		for f in d.get_files():
			out.append(f)
	return out


# ---- one step ----------------------------------------------------------------------------------------------------------
func do_step(n: int) -> void:
	var nt := next_text()
	var pick := choose()
	if pick["kind"] == "stuck":
		dead_ends.append({"n": n, "did": "STUCK: no command's words match the goal and the Next line was already followed", "next_before": nt, "said": "", "dialog": "", "skipped": false})
		trace.append("%2d  STUCK (no candidate left); Next says '%s'" % [n, nt])
		stuck = true
		return
	var s0 := score()
	var f0 := fresh()
	var c0 := JSON.stringify(m.S.cards)
	var said := ""
	var label := ""
	var skipped := false
	if pick["kind"] == "next":
		label = "Next -> '%s'" % nt
		var nx: Dictionary = m.next_step()
		if String(nx["kind"]) == "export":
			skipped = true   # the harness will not write an export; the click only opens the dialog
		m.ui_next.pressed.emit()
		await idle(2)
		while m._fixing:
			await process_frame
	else:
		var id: String = pick["id"]
		var row: Dictionary = {}
		for c in cmds:
			if c["id"] == id:
				row = c
		label = "cmd '%s'" % row["name"]
		tried[id] = int(tried.get(id, 0)) + 1
		var unsafe := false
		for u in UNSAFE:
			if id.contains(u):
				unsafe = true
		if unsafe:
			skipped = true
			said = "(harness did not run it: writes outside scenes/_wip or user://)"
		else:
			var r: Dictionary = await A.step(id)
			said = String(r.get("said", ""))
			if r.has("error"):
				said += " [error: %s]" % r["error"]
	await idle(2)
	var dlg := open_dialogs()
	var dlg_t := ""
	for w in dlg:
		dlg_t += "'%s' " % (w as Window).title
		(w as Window).hide()
	if m.export_ui != null and m.export_ui.dlg != null and m.export_ui.dlg.visible:
		dlg_t += "'export' "
		m.export_ui.dlg.hide()
	await idle(2)
	m.playing = false
	said_last = String(m.ui_status.text) if m.ui_status != null else ""
	var s1 := score()
	var forward := s1 > s0 + 1e-4 or (fresh() and not f0)
	if said == "":
		said = String(m.ui_status.text) if m.ui_status != null else ""
	var rec := "%2d  %-62s score %.2f -> %.2f%s | next now: %s" % [n, label.left(62), s0, s1, "  [DIALOG %s]" % dlg_t.strip_edges() if dlg_t != "" else "", next_text()]
	trace.append(rec)
	if not forward:
		if pick["kind"] == "next":
			next_dead[nt] = int(next_dead.get(nt, 0)) + 1
		if pick["kind"] == "cmd":
			if JSON.stringify(m.S.cards) == c0 and s1 <= s0 + 1e-4:
				dead_ids[pick["id"]] = true
		dead_ends.append({"n": n, "did": label, "next_before": nt, "said": said.left(220), "dialog": dlg_t.strip_edges(), "skipped": skipped})


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	m.settings = "user://zz_r7.cfg"          # never the real poser.cfg
	m.autosave = "user://zz_r7_autosave.json"
	root.add_child(m)
	await idle(4)
	Bs.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	A = AgentTools.new(m)
	wip_before = wip_files()
	await A.request(0, "new", {})
	await idle(2)
	await learn_registry()
	print("registry: %d commands; goal words %s" % [cmds.size(), goal_words])
	print("start: Next = '%s'" % next_text())
	var steps := 0
	var reached := -1
	while steps < HARD:
		if landed():
			reached = steps
			break
		steps += 1
		await do_step(steps)
		if stuck:
			break
	if reached < 0 and landed():
		reached = steps
	print("---- the agent's log ----")
	for l in trace:
		print(l)
	print("---- dead ends (%d) ----" % dead_ends.size())
	for d in dead_ends:
		print("step %d: %s | Next said '%s' | status: %s%s" % [d["n"], d["did"], d["next_before"], d["said"], (" | dialog " + d["dialog"]) if d["dialog"] != "" else ""])
	var f := fist_state()
	print("final: cards %d, contact card %s, hand %s, v %.2f m/s, gap %.3f m, check fresh %s, must-fix %d" % [m.S.cards.size(), f.get("card", "-"), f.get("hand", "-"), float(f.get("v", 0.0)), float(f.get("gap", 9.0)), fresh(), nfails()])
	ok(reached >= 0 and reached <= BUDGET, "1 goal reached in %d steps (bar <= %d)" % [reached, BUDGET])
	# 3 placement + shot
	if reached >= 0:
		m.sel_card = int(f["card"])
		m.playhead = float(f["t"])
		await A.step("his_right_view")
		m._refresh()
		await idle(6)
		var vp: Vector2 = root.get_visible_rect().size
		var top: float = m.ui_top_bar.get_global_rect().end.y
		var bot: float = m.ui_bp.get_global_rect().position.y
		var T: Dummy = m.T
		var pts := {"hero feet": Vector3(0, 0, 0), "hero head": (m.B.P["head"] as Vector3) + Vector3(0, 0.15, 0), "dummy feet": T.xf * Vector3(0, 0, 0), "dummy head": (T.cap("head")[1] as Vector3) + Vector3(0, float(T.D.rad["head"]), 0), "fist": f["tip"]}
		var inside := true
		var why := ""
		for k in pts:
			var p: Vector2 = m.cam.unproject_position(pts[k])
			if p.x < 0 or p.x > vp.x or p.y < top or p.y > bot:
				inside = false
				why += " %s at (%.0f,%.0f)" % [k, p.x, p.y]
		ok(inside, "3 PLACEMENT: both bodies and the fist inside the 3D view (y %.0f..%.0f, x 0..%.0f)%s" % [top, bot, vp.x, why])
		(root.get_texture().get_image() as Image).save_png(SHOT)
		print("shot: " + SHOT)
	for fn in wip_files():
		if not fn in wip_before:
			DirAccess.remove_absolute(ProjectSettings.globalize_path("res://scenes/_wip/" + fn))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://zz_r7.cfg"))
	print("R7 %s (%d fails): %d steps, %d dead ends" % ["PASS" if fails == 0 else "FAIL", fails, steps, dead_ends.size()])
	quit(fails)
