## safety_sheet.gd - I28 SAFETY SHEET. One pre-shoot report for the stunt crew over the whole scene (every fighter), built from the judges the app
## already has; nothing is re-implemented here, only gathered, timed and written up. Each item: {"kind", "t", "frame", "who" (names), "sev"
## ("red" / "amber"), "text" (one line with the number), "num" (the number), "at" (where, hero space, or null)}.
##  CONTACT   a real contact between two fighters (Dummy.fighter_hits, the report the Check already shows): its time, the speed of the striking
##            spot (m/s). RED from CONTACT_RED = 2 m/s up, AMBER under it (a brush). The 2 m/s is a HEURISTIC: stage-combat practice is NO contact at
##            all, so every contact is listed; no paper gives a speed that is safe to take on a body, so this only orders them.
##  TIP NEAR HEAD  a weapon's tip passing within TIP_NEAR = 15 cm of the other fighter's head (the surface of the head capsule), measured on
##            every frame; one item per pass, at its closest frame, with the distance. The 15 cm is a HEURISTIC (a stunt rule of thumb of "a hand's
##            breadth"; I found no stunt-safety source that fixes a number). RED under SellHit.SAFE = 10 cm (or touching), AMBER from 10 to 15 cm.
##  CLOSE PASS  a strike (SellHit.row, I21) whose 3D miss is under SellHit.SAFE = 10 cm without a contact: AMBER. Left out when another item of the
##            same attacker already covers the strike's span (a tip pass near the head is the same event).
##  FALL      Breakfall.analyze (I25) if scripts/breakfall.gd exists: each landing that is not OK (WARN = amber, FAIL = red), with its failing rules.
##            If it is absent, the falls are listed by the centre of mass alone (HOOK: Breakfall) - a drop of FALL_DROP = 40 % of the standing
##            height within 1 s (I25's own definition of a knockdown, not a standard) - as AMBER "fall, landing not judged".
##  RUSHED    FightRhythm.analyze flags of type "rush" (a strike again before the fighter has recovered): AMBER, its own sentence with the numbers.
class_name SafetySheet
extends RefCounted

const CONTACT_RED := 2.0
const TIP_NEAR := 0.15
const FALL_DROP := 0.4
const BLOW := 0.15
const BREAKFALL := "res://scripts/breakfall.gd"


static func _frame(t: float, fps: int) -> int:
	return int(round(t * float(fps)))


static func _item(kind: String, t: float, fps: int, who: Array, sev: String, text: String, num: float, at: Variant) -> Dictionary:
	return {"kind": kind, "t": t, "frame": _frame(t, fps), "who": who, "sev": sev, "text": text, "num": num, "at": at}


static func _body() -> Body:
	return DistanceKeeper.new_body()


## the head capsule of body b in the hero's space: [a, b, r]
static func _head(b: Body, xf: Transform3D) -> Array:
	var c: Array = b.cap("head")
	return [xf * (c[0] as Vector3), xf * (c[1] as Vector3), float(b.rad["head"])]


## scenes[0] is the hero (identity); xfs[k] places scene k in the hero's space. names[k] its name.
## {"items", "msg", "red", "amber", "fps"}. The scenes are cloned, nothing is touched.
static func analyze(scenes: Array, names: Array, xfs: Array, fps := 30) -> Dictionary:
	var sc := []
	for s in scenes:
		sc.append((s as Scene).clone())
	var items := []
	# CONTACTS
	var HB := _body()
	for k in range(1, sc.size()):
		var OB := _body()
		for h in Dummy.fighter_hits(sc[0], HB, sc[k], OB, xfs[k], fps):
			var by_hero: bool = h["by"] == "hero"
			var a: String = names[0] if by_hero else names[k]
			var d: String = names[k] if by_hero else names[0]
			var sp := float(h["speed"])
			var what := "weapon" if Body.is_wep(String(h["part"])) else String(h["part"]).replace("_", " ")
			var it := _item("contact", float(h["t"]), fps, [a, d], "red" if sp >= CONTACT_RED else "amber",
				"real contact: %s's %s on %s's %s at %.1f m/s, %.1f cm deep" % [a, what, d, String(h["on"]).replace("_", " "), sp, float(h["depth"]) * 100.0],
				sp, h["at"])
			# ONE blow touches several parts at once: the same two fighters within BLOW = 0.15 s are one item, the fastest part stands for it
			var merged := false
			for o in items:
				if o["kind"] == "contact" and o["who"] == it["who"] and absf(float(o["t"]) - float(it["t"])) <= BLOW:
					o["more"] = int(o.get("more", 0)) + 1
					if sp > float(o["num"]):
						var more: int = o["more"]
						o.merge(it, true)
						o["more"] = more
					merged = true
					break
			if not merged:
				items.append(it)
	for o in items:
		if o["kind"] == "contact" and int(o.get("more", 0)) > 0:
			o["text"] = String(o["text"]) + " (+%d more part%s touched in the same blow)" % [int(o["more"]), "" if int(o["more"]) == 1 else "s"]
	# TIP NEAR HEAD, every ordered pair, every frame
	for a in sc.size():
		for d in sc.size():
			if a == d:
				continue
			items.append_array(_tip_passes(sc[a], sc[d], names[a], names[d], xfs[a], xfs[d], fps))
	# CLOSE PASSES (SellHit.row; the contacts and the head passes already cover theirs)
	for a in sc.size():
		for d in sc.size():
			if a == d:
				continue
			var xf: Transform3D = (xfs[a] as Transform3D).affine_inverse() * (xfs[d] as Transform3D)
			var BA := _body()
			var BD := _body()
			for i in BeatFight.contacts(sc[a]):
				var r := SellHit.row(sc[a], BA, sc[d], BD, xf, i, fps, [], Transform3D.IDENTITY)
				if bool(r["contact"]) or float(r["miss"]) >= SellHit.SAFE:
					continue
				var covered := false
				for it in items:
					if (it["who"] as Array)[0] == names[a] and float(it["t"]) >= float(r["t0"]) - 0.5 / fps and float(it["t"]) <= float(r["t1"]) + 0.5 / fps:
						covered = true
				if covered:
					continue
				items.append(_item("close", float(r["t"]), fps, [names[a], names[d]], "amber",
					"close pass: %s's %s misses %s by %.1f cm (under the %.0f cm margin, too near to pull with certainty)" % [names[a], String(r["tip"]).replace("_", " "), names[d], float(r["miss"]) * 100.0, SellHit.SAFE * 100.0],
					float(r["miss"]) * 100.0, null))
	# FALLS
	for k in sc.size():
		items.append_array(_falls(sc[k], names[k], fps))
	# RUSHED STRIKES
	if sc.size() >= 1:
		for f in FightRhythm.analyze(sc, names, fps)["flags"]:
			if f["type"] == "rush":
				items.append(_item("rush", float(f["t1"]), fps, [names[int(f["who"])]], "amber", String(f["text"]), float(f["t1"]) - float(f["t0"]), null))
	items.sort_custom(func(x, y): return float(x["t"]) < float(y["t"]) if float(x["t"]) != float(y["t"]) else String(x["kind"]) < String(y["kind"]))
	var red := items.filter(func(i): return i["sev"] == "red").size()
	var amber := items.size() - red
	var msg := "safety sheet: nothing to flag (no contact, no tip near a head, no unjudged fall, no rushed strike)" if items.is_empty() else \
		"safety sheet: %d item%s, %d red, %d amber" % [items.size(), "" if items.size() == 1 else "s", red, amber]
	return {"items": items, "msg": msg, "red": red, "amber": amber, "fps": fps, "breakfall": ResourceLoader.exists(BREAKFALL)}


## the passes of A's weapon tip within TIP_NEAR of D's head (the head capsule's surface): one item per pass, at its closest frame
static func _tip_passes(A: Scene, D: Scene, na: String, nd: String, xa: Transform3D, xd: Transform3D, fps: int) -> Array:
	var BA := _body()
	var BD := _body()
	var out := []
	var n := int(ceil(maxf(A.length(), D.length()) * fps))
	var best := INF
	var best_f := -1
	var best_at := Vector3.ZERO
	var inside := false
	for f in n + 2:
		var t := float(f) / fps
		var dist := INF
		var at := Vector3.ZERO
		if f <= n:
			A.apply(BA, t)
			D.apply(BD, t)
			if BA.wep_on:
				var tip: Vector3 = xa * BA.wep_point(BA.wep_len)
				var h := _head(BD, xd)
				dist = DistanceKeeper._seg_dist(tip, h[0], h[1]) - float(h[2])
				at = tip
		if dist < TIP_NEAR:
			inside = true
			if dist < best:
				best = dist
				best_f = f
				best_at = at
		elif inside:   # the pass ended
			var sp := _tip_speed(A, BA, best_f, fps)
			out.append(_item("tip", float(best_f) / fps, fps, [na, nd], "red" if best < SellHit.SAFE else "amber",
				"weapon tip passes %.1f cm from %s's head (%s of %.0f cm; the tip moves at %.1f m/s)" % [maxf(best, 0.0) * 100.0, nd, "inside the margin" if best < SellHit.SAFE else "over the margin", SellHit.SAFE * 100.0, sp],
				maxf(best, 0.0) * 100.0, best_at))
			inside = false
			best = INF
	return out


static func _tip_speed(A: Scene, BA: Body, f: int, fps: int) -> float:
	A.apply(BA, float(maxi(f - 1, 0)) / fps)
	var p0: Vector3 = BA.wep_point(BA.wep_len) if BA.wep_on else Vector3.ZERO
	A.apply(BA, float(f) / fps)
	var p1: Vector3 = BA.wep_point(BA.wep_len) if BA.wep_on else Vector3.ZERO
	return p0.distance_to(p1) * fps if f > 0 else 0.0


## falls of one scene: Breakfall's verdicts when I25 is installed, else the centre-of-mass drops
static func _falls(S: Scene, nm: String, fps: int) -> Array:
	var out := []
	if ResourceLoader.exists(BREAKFALL):
		var rep: Dictionary = (load(BREAKFALL) as GDScript).call("analyze", S)
		for f in rep.get("falls", []):
			if f["cls"] == "ok":
				continue
			var bad := []
			if f["a"] != "ok":
				bad.append("head %.0f cm clear, chin %.0f deg" % [float(f["head_clear"]) * 100.0, float(f["chin"])])
			if f["b"] != "ok":
				bad.append("elbow %.0f deg" % float(f["elbow"]))
			if f["c"] != "ok":
				bad.append("spread over %s" % (", ".join(f["regions"]) if not (f["regions"] as Array).is_empty() else "no good surface"))
			if f["d"] != "ok":
				bad.append("lands at %.1f m/s" % float(f["speed"]))
			out.append(_item("fall", float(f["t_c"]), fps, [nm], "red" if f["cls"] == "fail" else "amber",
				"fall, breakfall %s: %s lands on its %s (%s)" % [String(f["cls"]).to_upper(), nm, String(f["part"]).replace("_", " "), "; ".join(bad)], float(f["speed"]), null))
		return out
	# HOOK: Breakfall absent. The centre of mass alone.
	var B := _body()
	var n := int(ceil(S.length() * fps))
	var com := []
	var top := 0.0
	for f in n + 1:
		S.apply(B, float(f) / fps)
		com.append(Balance.com(B).y)
		var hc: Array = B.cap("head")
		top = maxf(top, maxf((hc[0] as Vector3).y, (hc[1] as Vector3).y) + float(B.rad["head"]))
	var w := fps
	var f := 0
	while f < com.size():
		var hit := -1
		for g in range(f + 1, mini(com.size(), f + w + 1)):
			if float(com[f]) - float(com[g]) > FALL_DROP * top:
				hit = g
				break
		if hit >= 0:
			out.append(_item("fall", float(hit) / fps, fps, [nm], "amber",
				"fall (landing not judged: no breakfall check installed): %s's centre of mass drops %.0f cm in %.1f s" % [nm, (float(com[f]) - float(com[hit])) * 100.0, float(hit - f) / fps],
				(float(com[f]) - float(com[hit])) * 100.0, null))
			f = hit + w
		else:
			f += 1
	return out


## ---- the page ----

static func _esc(s: String) -> String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")


## one self-contained printable page: inline CSS, the thumbnails as data: URIs (pics[i] = PNG bytes of item i, or empty)
static func to_html(rep: Dictionary, title: String, pics: Array) -> String:
	var items: Array = rep["items"]
	var h := "<!doctype html>\n<html lang=\"en\"><head><meta charset=\"utf-8\"><title>Safety sheet - %s</title>\n<style>\n" % _esc(title)
	h += "body{font:14px/1.45 system-ui,Segoe UI,sans-serif;margin:24px auto;max-width:860px;color:#1b1d22;background:#fff}\n"
	h += "h1{font-size:22px;margin:0 0 4px}.sub{color:#555;margin:0 0 16px}\n"
	h += ".item{display:flex;gap:14px;border:1px solid #ccd;border-left:8px solid #999;border-radius:4px;padding:10px;margin:0 0 10px;break-inside:avoid}\n"
	h += ".item.red{border-left-color:#c62828}.item.amber{border-left-color:#e08a00}\n"
	h += ".item img{width:240px;height:135px;border:1px solid #bbb;flex:none;background:#3b3d45}\n"
	h += ".tag{display:inline-block;font-weight:700;font-size:12px;color:#fff;border-radius:3px;padding:1px 7px;margin-right:6px}.red .tag{background:#c62828}.amber .tag{background:#e08a00}\n"
	h += ".when{font-weight:700}.who{color:#444}.note{color:#555;font-size:12px;margin-top:18px}\n"
	h += "@media print{body{margin:8mm}.item{border-color:#999}}\n</style></head><body>\n"
	h += "<h1>Safety sheet - %s</h1>\n<p class=\"sub\">%s. Times are at %d fps.</p>\n" % [_esc(title), _esc(String(rep["msg"])), int(rep["fps"])]
	for i in items.size():
		var it: Dictionary = items[i]
		h += "<div class=\"item %s\">" % it["sev"]
		var png: PackedByteArray = pics[i] if i < pics.size() else PackedByteArray()
		if not png.is_empty():
			h += "<img alt=\"frame %d\" src=\"data:image/png;base64,%s\">" % [int(it["frame"]), Marshalls.raw_to_base64(png)]
		h += "<div><div><span class=\"tag\">%s</span><span class=\"when\">%.2f s (frame %d)</span> <span class=\"who\">%s</span></div><div>%s</div></div></div>\n" % [
			String(it["sev"]).to_upper(), float(it["t"]), int(it["frame"]), _esc(" / ".join(it["who"])), _esc(String(it["text"]))]
	if items.is_empty():
		h += "<p>Nothing to flag.</p>\n"
	h += "<p class=\"note\">Thresholds are heuristics, not a safety standard: contact red from %.0f m/s, weapon tip within %.0f cm of a head (red under %.0f cm), strike miss under %.0f cm. %s Thumbnails: one fixed 3/4 view of the whole scene at the item's frame; the marker is where it happens.</p>\n" % [
		CONTACT_RED, TIP_NEAR * 100.0, SellHit.SAFE * 100.0, SellHit.SAFE * 100.0,
		"Falls are judged by the breakfall check." if bool(rep.get("breakfall", false)) else "The breakfall check is not installed: falls are listed by the centre of mass only."]
	return h + "</body></html>\n"
