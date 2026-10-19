## scene_report.gd - SCENE DIFF REPORT (ROADMAP 98): what changed between two versions of a scene, in words. Pure data, no node,
## no window, and it never writes: the scene (A, B) is read, the report is a list of rows.
##   report(A, B) -> rows in this order:
##     1 cards added (in B's order), removed (in A's order), moved (a kept card whose place changed: the cards that
##       are not in the longest run that keeps the order)
##     2 per card in B's order: timing (move / hold / ease / flow / walk), the weapon in hand, then each joint whose
##       angle changed by MORE than JOINT_MIN degrees, largest first (the body-part name users see, the biggest component
##       of the change, wrapped)
##     3 props (added, removed, moved, turned), markers (added, removed, moved), notes (added, removed, changed)
##     4 scene settings (natural, spline, loop, floor, pin, moving holds, fitness, breath, fps)
##   Cards are matched in two steps: first the cards that are identical (name and content) in the longest common run,
##   then the rest by name in order. A card that is only inserted is one "added", not a change of every card after it.
## Each row: {"kind", "card" (index in B, -1 when none), "ia" (index in A, -1 when none), "t" (B's arrival time of the card,
##   -1 when none), "ta" (A's arrival time of the matched card, -1 when none), "joint" (joint id, "" when none),
##   "deg" (joints only), "text" (the line the panel shows)}.
class_name SceneReport
extends RefCounted

const JOINT_MIN := 0.5   # deg: a joint that changed by this much or less is not reported (the file rounds to 0.01)
const POS_MIN := 0.01    # m: a prop that moved by less than this did not move
const TIME_MIN := 0.0005 # s: a marker or a card time that differs by less than this did not change


## the rows that say what changed from scene A to scene B (see the header). part_name: joint id -> the name users see
static func report(A: Scene, B: Scene, part_name := Callable()) -> Array:
	var rows := []
	var ta: Array = A.times()
	var tb: Array = B.times()
	var m := _match(A.cards, B.cards)
	var a2b: Array = m[0]
	var b_used: Array = m[1]
	# 1 structure: added (B's order), removed (A's order), moved (kept cards out of the longest run that keeps the order)
	for j in B.cards.size():
		if not b_used[j]:
			rows.append({"kind": "added", "card": j, "ia": -1, "t": float(tb[j][1]), "ta": -1.0, "joint": "", "deg": 0.0,
				"text": "+ added    %s  (card %d)" % [B.cards[j]["name"], j + 1]})
	var kept_a := []
	for i in A.cards.size():
		if a2b[i] < 0:
			rows.append({"kind": "removed", "card": -1, "ia": i, "t": -1.0, "ta": float(ta[i][1]), "joint": "", "deg": 0.0,
				"text": "- removed  %s  (was card %d)" % [A.cards[i]["name"], i + 1]})
		else:
			kept_a.append(i)
	var keep := _lis_pairs(kept_a, a2b)
	for i in kept_a:
		var j: int = a2b[i]
		if not keep.has(i):
			rows.append({"kind": "moved", "card": j, "ia": i, "t": float(tb[j][1]), "ta": float(ta[i][1]), "joint": "", "deg": 0.0,
				"text": "> moved    %s  (card %d -> %d)" % [B.cards[j]["name"], i + 1, j + 1]})
	# 2 per card, in B's order: the content of each kept card
	var nm := func(j: String) -> String:
		return part_name.call(j) if part_name.is_valid() else j
	for j in B.cards.size():
		var i := -1
		for k in kept_a:
			if a2b[k] == j:
				i = k
				break
		if i < 0:
			continue
		rows.append_array(_card_rows(A.cards[i], B.cards[j], i, j, float(ta[i][1]), float(tb[j][1]), nm))
	# 3 props, markers, notes; 4 settings
	rows.append_array(_props_rows(A.props, B.props))
	rows.append_array(_marker_rows(A.markers, B.markers))
	rows.append_array(_note_rows(A.notes, B.notes))
	rows.append_array(_setting_rows(A, B))
	return rows


## a card as a key: the name and the whole card (sorted keys), so an identical card has the same key in both scenes
static func _key(c: Dictionary) -> String:
	return JSON.stringify(c, "", true)


## the card pairs of A and B: a2b[i] = j or -1 (and b_used[j]). Step 1: the longest run of identical cards (name and
## content); step 2: the rest of A's cards take the first unused card of B with the same name, in order
static func _match(CA: Array, CB: Array) -> Array:
	var ka := []
	var kb := []
	for c in CA:
		ka.append(_key(c))
	for c in CB:
		kb.append(_key(c))
	var a2b := []
	a2b.resize(CA.size())
	a2b.fill(-1)
	var b_used := []
	b_used.resize(CB.size())
	b_used.fill(false)
	for p in _lcs(ka, kb):
		a2b[p[0]] = p[1]
		b_used[p[1]] = true
	for i in CA.size():
		if a2b[i] >= 0:
			continue
		for j in CB.size():
			if not b_used[j] and CB[j]["name"] == CA[i]["name"]:
				a2b[i] = j
				b_used[j] = true
				break
	return [a2b, b_used]


## the longest common run of two key lists: [[i, j], ...] in order
static func _lcs(x: Array, y: Array) -> Array:
	var n := x.size()
	var m := y.size()
	var dp := []
	for i in n + 1:
		var row := []
		row.resize(m + 1)
		row.fill(0)
		dp.append(row)
	for i in range(n - 1, -1, -1):
		for j in range(m - 1, -1, -1):
			var best: int = maxi(dp[i + 1][j], dp[i][j + 1])
			if x[i] == y[j]:
				best = maxi(best, dp[i + 1][j + 1] + 1)
			dp[i][j] = best
	var out := []
	var i := 0
	var j := 0
	while i < n and j < m:
		if x[i] == y[j] and dp[i][j] == dp[i + 1][j + 1] + 1:
			out.append([i, j])
			i += 1
			j += 1
		elif dp[i + 1][j] >= dp[i][j + 1]:
			i += 1
		else:
			j += 1
	return out


## the A indices (of kept cards, in A's order) that stay in the longest run whose B positions also rise
static func _lis_pairs(kept_a: Array, a2b: Array) -> Array:
	var n := kept_a.size()
	var best := []
	var len := []
	var prev := []
	for k in n:
		len.append(1)
		prev.append(-1)
		for q in k:
			if a2b[kept_a[q]] < a2b[kept_a[k]] and len[q] + 1 > len[k]:
				len[k] = len[q] + 1
				prev[k] = q
	var end := -1
	for k in n:
		if end < 0 or len[k] > len[end]:
			end = k
	var idx := []
	while end >= 0:
		idx.append(kept_a[end])
		end = prev[end]
	return idx


## the rows of one kept card: timing, weapon, then its joints over JOINT_MIN, largest first
static func _card_rows(ca: Dictionary, cb: Dictionary, ia: int, ib: int, ta: float, tb: float, nm: Callable) -> Array:
	var out := []
	var name: String = cb["name"]
	var base := {"card": ib, "ia": ia, "t": tb, "ta": ta, "joint": "", "deg": 0.0}
	var parts := []
	if float(ca["move"]) != float(cb["move"]):
		parts.append("move %s -> %s" % [_secs(float(ca["move"])), _secs(float(cb["move"]))])
	if float(ca["hold"]) != float(cb["hold"]):
		parts.append("hold %s -> %s" % [_secs(float(ca["hold"])), _secs(float(cb["hold"]))])
	if String(ca.get("ease", "smooth")) != String(cb.get("ease", "smooth")):
		parts.append("ease %s -> %s" % [ca.get("ease", "smooth"), cb.get("ease", "smooth")])
	if bool(ca.get("flow", false)) != bool(cb.get("flow", false)):
		parts.append("flow %s -> %s" % [_onoff(bool(ca.get("flow", false))), _onoff(bool(cb.get("flow", false)))])
	if bool(ca.get("walk", false)) != bool(cb.get("walk", false)):
		parts.append("walk %s -> %s" % [_onoff(bool(ca.get("walk", false))), _onoff(bool(cb.get("walk", false)))])
	if not parts.is_empty():
		var r := base.duplicate()
		r["kind"] = "timing"
		r["text"] = "~ %s  timing: %s" % [name, ", ".join(parts)]
		out.append(r)
	var wa := _wep_word(ca["pose"].get("weapon", {}))
	var wb := _wep_word(cb["pose"].get("weapon", {}))
	if wa != wb:
		var r := base.duplicate()
		r["kind"] = "weapon"
		r["text"] = "~ %s  weapon: %s -> %s" % [name, wa, wb]
		out.append(r)
	var aa := VersionDiff.pose_angles(ca["pose"])
	var ab := VersionDiff.pose_angles(cb["pose"])
	var js := []
	for j in Body.ORDER:
		var v: Vector3 = ab[j] - aa[j]
		var d := maxf(absf(VersionDiff.wrap_deg(v.x)), maxf(absf(VersionDiff.wrap_deg(v.y)), absf(VersionDiff.wrap_deg(v.z))))
		if d > JOINT_MIN:
			js.append([d, j])
	js.sort_custom(func(p, q): return p[0] > q[0])
	for p in js:
		var r := base.duplicate()
		r["kind"] = "joint"
		r["joint"] = p[1]
		r["deg"] = float(p[0])
		r["text"] = "~ %s  %s  %.1f°" % [name, nm.call(p[1]), float(p[0])]
		out.append(r)
	return out


static func _wep_word(w: Variant) -> String:
	if not (w is Dictionary) or (w as Dictionary).is_empty():
		return "none"
	return "%s in %s hand" % [String((w as Dictionary).get("kind", "?")), String((w as Dictionary).get("hand", "?"))]


static func _secs(v: float) -> String:
	return "auto" if v < 0.0 else "%.2f s" % v


static func _onoff(b: bool) -> String:
	return "on" if b else "off"


static func _props_rows(PA: Array, PB: Array) -> Array:
	var out := []
	var used := {}
	var pairs := []
	for a in PA:
		var hit := -1
		for j in PB.size():
			if not used.has(j) and PB[j]["kind"] == a["kind"]:
				hit = j
				break
		if hit < 0:
			out.append({"kind": "prop", "card": -1, "ia": -1, "t": -1.0, "ta": -1.0, "joint": "", "deg": 0.0,
				"text": "props: - %s" % a["kind"]})
		else:
			used[hit] = true
			pairs.append([a, PB[hit]])
	for j in PB.size():
		if not used.has(j):
			out.append({"kind": "prop", "card": -1, "ia": -1, "t": -1.0, "ta": -1.0, "joint": "", "deg": 0.0,
				"text": "props: + %s" % PB[j]["kind"]})
	for p in pairs:
		var xa: Transform3D = p[0]["xf"]
		var xb: Transform3D = p[1]["xf"]
		var what := ""
		var moved := xa.origin.distance_to(xb.origin)
		if moved > POS_MIN:
			what = "moved %.2f m" % moved
		elif not xa.basis.is_equal_approx(xb.basis):
			what = "turned"
		if what != "":
			out.append({"kind": "prop", "card": -1, "ia": -1, "t": -1.0, "ta": -1.0, "joint": "", "deg": 0.0,
				"text": "props: %s %s" % [p[0]["kind"], what]})
	return out


static func _marker_rows(MA: Array, MB: Array) -> Array:
	var out := []
	var used := {}
	for a in MA:
		var hit := -1
		for j in MB.size():
			if not used.has(j) and MB[j]["name"] == a["name"] and MB[j].get("kind", "") == a.get("kind", ""):
				hit = j
				break
		if hit < 0:
			out.append({"kind": "marker", "card": -1, "ia": -1, "t": -1.0, "ta": -1.0, "joint": "", "deg": 0.0,
				"text": "markers: - '%s' at %.2f s" % [a["name"], float(a["t"])]})
			continue
		used[hit] = true
		var b: Dictionary = MB[hit]
		if absf(float(a["t"]) - float(b["t"])) > TIME_MIN:
			out.append({"kind": "marker", "card": -1, "ia": -1, "t": float(b["t"]), "ta": -1.0, "joint": "", "deg": 0.0,
				"text": "markers: '%s' %.2f s -> %.2f s" % [a["name"], float(a["t"]), float(b["t"])]})
	for j in MB.size():
		if not used.has(j):
			out.append({"kind": "marker", "card": -1, "ia": -1, "t": float(MB[j]["t"]), "ta": -1.0, "joint": "", "deg": 0.0,
				"text": "markers: + '%s' at %.2f s" % [MB[j]["name"], float(MB[j]["t"])]})
	return out


static func _note_rows(NA: Array, NB: Array) -> Array:
	var out := []
	var used := {}
	for a in NA:
		var hit := -1
		for j in NB.size():
			if not used.has(j) and int(NB[j]["frame"]) == int(a["frame"]):
				hit = j
				break
		if hit < 0:
			out.append({"kind": "note", "card": -1, "ia": -1, "t": -1.0, "ta": -1.0, "joint": "", "deg": 0.0,
				"text": "notes: - frame %d '%s'" % [int(a["frame"]), a["text"]]})
			continue
		used[hit] = true
		if String(NB[hit]["text"]) != String(a["text"]):
			out.append({"kind": "note", "card": -1, "ia": -1, "t": -1.0, "ta": -1.0, "joint": "", "deg": 0.0,
				"text": "notes: frame %d '%s' -> '%s'" % [int(a["frame"]), a["text"], NB[hit]["text"]]})
	for j in NB.size():
		if not used.has(j):
			out.append({"kind": "note", "card": -1, "ia": -1, "t": -1.0, "ta": -1.0, "joint": "", "deg": 0.0,
				"text": "notes: + frame %d '%s'" % [int(NB[j]["frame"]), NB[j]["text"]]})
	return out


static func _setting_rows(A: Scene, B: Scene) -> Array:
	var out := []
	for k in [["natural", "natural"], ["spline", "spline"], ["loop", "loop"], ["on_floor", "on the floor"],
			["floor_body", "whole body on the floor"], ["pin", "pinned feet"], ["moving_holds", "moving holds"],
			["fitness", "fitness"], ["breath", "breathing"], ["fps", "frames a second"]]:
		var va = A.get(k[0])
		var vb = B.get(k[0])
		if va == vb:
			continue
		var sa := _setting_text(va)
		var sb := _setting_text(vb)
		out.append({"kind": "setting", "card": -1, "ia": -1, "t": -1.0, "ta": -1.0, "joint": "", "deg": 0.0,
			"text": "scene: %s  %s -> %s" % [k[1], sa, sb]})
	return out


static func _setting_text(v: Variant) -> String:
	if v is bool:
		return _onoff(v)
	if v is float:
		return "%.2f" % v
	return str(v)
