## scene_diff.gd - what changed between two scene files (round 13, GATES T2; poser_cli `diff a.json b.json`).
## Cards are matched by NAME in order (a longest common subsequence), so deleting one card does not make every card
## after it "different". An unmatched card on each side of the same gap with the same pose is a RENAME. For each matched
## pair: the timing fields that changed, the offset (over 1 mm), the weapon's kind / hand, and every joint whose bend,
## side or twist moved more than TOL degrees, largest first.
class_name SceneDiff
extends RefCounted

const TOL := 0.5            # degrees: the files round to 0.01, a drag moves whole degrees
const OFFSET_TOL := 0.001   # metres
const SETTINGS := ["scene", "natural", "spline", "moving_holds", "on_floor", "floor_body", "pin", "fps"]
const TIMING := ["move", "hold", "ease", "plant", "steps", "lift", "flow"]
## the loader's own defaults, so a field written in one file and left out of the other is not a difference
const DEFAULTS := {"natural": true, "spline": false, "moving_holds": false, "on_floor": true, "floor_body": false, "pin": true,
	"fps": 30, "move": -1.0, "hold": 0.3, "ease": "smooth", "plant": [], "steps": {}, "lift": 0.0, "flow": false}


static func files(pa: String, pb: String) -> Dictionary:
	return diff(JSON.parse_string(FileAccess.get_file_as_string(pa)), JSON.parse_string(FileAccess.get_file_as_string(pb)))


static func diff(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := {"settings": [], "added": [], "removed": [], "renamed": [], "cards": []}
	for k in SETTINGS:
		var va: Variant = a.get(k, DEFAULTS.get(k))
		var vb: Variant = b.get(k, DEFAULTS.get(k))
		if not _eq(va, vb):
			out["settings"].append({"key": k, "a": va, "b": vb})
	var ca: Array = a.get("cards", [])
	var cb: Array = b.get("cards", [])
	var pairs := _lcs(ca.map(func(c): return c["name"]), cb.map(func(c): return c["name"]))
	# the gaps between matched pairs: unmatched cards there are removed / added, or renamed when the pose is the same
	var ia := 0
	var ib := 0
	for p in pairs + [[ca.size(), cb.size()]]:
		var ra := range(ia, p[0])
		var rb := range(ib, p[1])
		var used := {}
		for i in ra:
			var hit := -1
			for j in rb:
				if not used.has(j) and _joints(ca[i]["pose"], cb[j]["pose"]).is_empty():
					hit = j
					break
			if hit >= 0:
				used[hit] = true
				out["renamed"].append({"a": i + 1, "b": hit + 1, "from": ca[i]["name"], "to": cb[hit]["name"]})
				var cd := _card(ca[i], cb[hit], i, hit)
				if not cd.has("same"):
					out["cards"].append(cd)
			else:
				out["removed"].append({"a": i + 1, "name": ca[i]["name"]})
		for j in rb:
			if not used.has(j):
				out["added"].append({"b": j + 1, "name": cb[j]["name"]})
		if p[0] < ca.size():
			var cd := _card(ca[p[0]], cb[p[1]], p[0], p[1])
			if not cd.has("same"):
				out["cards"].append(cd)
		ia = p[0] + 1
		ib = p[1] + 1
	out["same"] = out["settings"].is_empty() and out["added"].is_empty() and out["removed"].is_empty() and out["renamed"].is_empty() and out["cards"].is_empty()
	return out


## one matched pair: {a, b, name, ...only what changed}, or {a, b, name, "same": true}
static func _card(x: Dictionary, y: Dictionary, i: int, j: int) -> Dictionary:
	var d := {"a": i + 1, "b": j + 1, "name": y["name"], "joints_moved": 0}
	var t := {}
	for k in TIMING:
		var vx: Variant = x.get(k, DEFAULTS[k])
		var vy: Variant = y.get(k, DEFAULTS[k])
		if not _eq(vx, vy):
			t[k] = {"a": vx, "b": vy}
	if not t.is_empty():
		d["timing"] = t
	var js := _joints(x["pose"], y["pose"])
	d["joints_moved"] = js.size()
	if not js.is_empty():
		d["joints"] = js
	var oa: Array = x["pose"].get("offset", [0, 0, 0])
	var ob: Array = y["pose"].get("offset", [0, 0, 0])
	var od := Vector3(ob[0] - oa[0], ob[1] - oa[1], ob[2] - oa[2])
	if od.length() > OFFSET_TOL:
		d["offset_mm"] = [snappedf(od.x * 1000.0, 0.1), snappedf(od.y * 1000.0, 0.1), snappedf(od.z * 1000.0, 0.1)]
	var wa: Dictionary = x["pose"].get("weapon", {})
	var wb: Dictionary = y["pose"].get("weapon", {})
	for k in ["kind", "hand"]:
		if str(wa.get(k, "")) != str(wb.get(k, "")):
			d["weapon_" + k] = {"a": wa.get(k, ""), "b": wb.get(k, "")}
	if d["joints_moved"] == 0:
		d.erase("joints_moved")
		if d.size() == 3:
			return {"a": i + 1, "b": j + 1, "name": y["name"], "same": true}
	return d


## joints whose bend / side / twist differ by more than TOL, largest first: {joint, d: [bend, side, twist], max}
static func _joints(pa: Dictionary, pb: Dictionary) -> Array:
	var ja: Dictionary = pa.get("joints", {})
	var jb: Dictionary = pb.get("joints", {})
	var out := []
	for j in Body.ORDER:
		var x: Dictionary = ja.get(j, {})
		var y: Dictionary = jb.get(j, {})
		var dv := []
		var mx := 0.0
		for k in ["bend", "side", "twist"]:
			var v := float(y.get(k, 0.0)) - float(x.get(k, 0.0))
			dv.append(snappedf(v, 0.01))
			mx = maxf(mx, absf(v))
		if mx > TOL:
			out.append({"joint": j, "d": dv, "max": snappedf(mx, 0.01)})
	out.sort_custom(func(p, q): return p["max"] > q["max"])
	return out


## the longest common subsequence of two name lists, as [i, j] index pairs in order
static func _lcs(a: Array, b: Array) -> Array:
	var n := a.size()
	var m := b.size()
	var L := []
	for i in n + 1:
		var row := PackedInt32Array()
		row.resize(m + 1)
		L.append(row)
	for i in range(n - 1, -1, -1):
		for j in range(m - 1, -1, -1):
			L[i][j] = L[i + 1][j + 1] + 1 if a[i] == b[j] else maxi(L[i + 1][j], L[i][j + 1])
	var out := []
	var i := 0
	var j := 0
	while i < n and j < m:
		if a[i] == b[j]:
			out.append([i, j])
			i += 1
			j += 1
		elif L[i + 1][j] >= L[i][j + 1]:
			i += 1
		else:
			j += 1
	return out


static func _eq(x: Variant, y: Variant) -> bool:
	if (x is float or x is int) and (y is float or y is int):
		return absf(float(x) - float(y)) < 1e-6
	return JSON.stringify(x) == JSON.stringify(y)


## the readable lines poser_cli prints
static func lines(d: Dictionary) -> Array:
	var out := []
	if d["same"]:
		return ["SAME: no differences (joints within %.1f deg, offsets within 1 mm)" % TOL]
	for s in d["settings"]:
		out.append("setting %s: %s -> %s" % [s["key"], s["a"], s["b"]])
	for r in d["removed"]:
		out.append("card %d '%s': removed" % [r["a"], r["name"]])
	for r in d["added"]:
		out.append("card %d '%s': added" % [r["b"], r["name"]])
	for r in d["renamed"]:
		out.append("card %d: renamed '%s' -> '%s'" % [r["b"], r["from"], r["to"]])
	for c in d["cards"]:
		var bits := []
		for k in c.get("timing", {}):
			bits.append("%s %s -> %s" % [k, c["timing"][k]["a"], c["timing"][k]["b"]])
		if c.has("offset_mm"):
			bits.append("offset %s mm" % [c["offset_mm"]])
		for k in ["weapon_kind", "weapon_hand"]:
			if c.has(k):
				bits.append("%s %s -> %s" % [k, c[k]["a"], c[k]["b"]])
		for jd in c.get("joints", []).slice(0, 6):
			bits.append("%s %+.1f/%+.1f/%+.1f" % [jd["joint"], jd["d"][0], jd["d"][1], jd["d"][2]])
		if c.get("joints", []).size() > 6:
			bits.append("+%d more joints" % (c["joints"].size() - 6))
		out.append("card %d '%s': %s" % [c["b"], c["name"], ", ".join(bits)])
	return out
