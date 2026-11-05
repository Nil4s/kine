## G8BOM: the BILL OF MATERIALS of an Assembly, with mass from the exact CAD solids, prices from data/prices.json, a CSV, and a "make it
## cheaper" view (the screen is scripts/build/assembly_bom_ui.gd). Generalises the CH14 lane's own BOM and cheapest-design search
## (scripts/build/ch14_bom.gd). Nothing here changes a record unless apply() / apply_design() is called (the screen makes that ONE undo step).
## What a record may carry (all optional; a record without them is read as "no material: not priced" and is never written to):
##   part record  "bom": {"material": key of prices.materials, "fill": fraction of the solid that is material (0.45 = a print at 45 pct),
##                        "buy": key of prices.items (a bought part: priced per piece, mass from the item or from the solid x density),
##                        "qty": units of the item per part (default 1; metres for a tube), "included": "words" (priced in another line),
##                        "alt": [material or item keys the part may use], "need": {"sigma_MPa": min, "E_MPa": min, "max_mass_kg": max},
##                        "role": a tag the assembly's system check reads, "name": the line's name}
##   assembly     "bom_extra": [{"name", "bom": {...}}]: bought things with no solid (a hose, glue); "bom_check": a named whole-design check
##                (CHECKS below; "ch14_works" = the CH14 arm's working bars)
## Identical parts (the same record text, keys sorted) are one line with a count. Mass = solid volume (KCad.volume, m3) x density (kg/m3) x fill.
class_name AssemblyBom
extends RefCounted

const PRICES := "res://data/prices.json"
const CHECKS := {"ch14_works": "res://scripts/build/ch14_bom.gd"}   # name -> a script with static check_asm(asm) -> {"ok", "why"}
const MAX_COMBOS := 4096
const DENSITY_MIN := 30.0   # kg/m3: a density below this is a g/cm3 number typed as kg/m3 (foam is about 30, PLA 1240, steel 7850)
const DENSITY_MAX := 23000.0
const COLS := ["part", "item", "qty", "unit", "material", "volume_cm3", "mass_kg", "unit_price", "line_cost", "source"]

static var _cache := {}
static var _stamp := -1


# ---------------------------------------------------------------- prices

static func prices(path := PRICES) -> Dictionary:
	var st := int(FileAccess.get_modified_time(path)) if FileAccess.file_exists(path) else 0
	if st == _stamp and not _cache.is_empty():
		return _cache
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	_cache = v if v is Dictionary else {"materials": {}, "items": {}}
	_stamp = st
	return _cache


## every problem of a price table: an entry without a source or a date (YYYY-MM-DD), a price that is not a number >= 0, a density that is
## not kg/m3. [] = clean
static func validate(p: Dictionary) -> Array:
	var out: Array = []
	for sect in ["materials", "items"]:
		var d: Dictionary = p.get(sect, {})
		for k in d:
			var e: Dictionary = d[k]
			var src := String(e.get("source", "")).strip_edges()
			if src == "":
				out.append("%s %s: no source (write ASSUMED: ... when there is none)" % [sect, k])
			var dt := String(e.get("date", ""))
			if not RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2}$").search(dt):
				out.append("%s %s: no date (YYYY-MM-DD)" % [sect, k])
			var pk := "price_per_kg" if sect == "materials" else "price"
			if not (e.get(pk) is float or e.get(pk) is int) or float(e.get(pk, -1.0)) < 0.0:
				out.append("%s %s: %s is not a number >= 0" % [sect, k, pk])
			if sect == "materials":
				var rho := float(e.get("density_kg_m3", 0.0))
				if rho < DENSITY_MIN or rho > DENSITY_MAX:
					out.append("materials %s: density %s kg/m3 is not a solid's (a g/cm3 number? 1.24 g/cm3 = 1240 kg/m3)" % [k, str(rho)])
	return out


static func is_assumed(e: Dictionary) -> bool:
	return String(e.get("source", "")).strip_edges().to_upper().begins_with("ASSUMED")


# ---------------------------------------------------------------- the lines

## the record's grouping key: identical records (keys sorted) are one line
static func key_of(rec: Dictionary) -> String:
	return JSON.stringify(rec, "", true).md5_text()


static func _bom_of(d: Dictionary) -> Dictionary:
	var b = d.get("bom", {})
	return b if b is Dictionary else {}


## the cost and mass of ONE part (or one extra) with bom b and solid volume vol (m3; < 0 = no solid): {"unit", "amount", "each" (price per unit),
## "unit_cost" (one part), "mass" (kg, one part), "source", "item", "material", "priced": bool, "why"}
static func price_one(b: Dictionary, vol: float, p: Dictionary) -> Dictionary:
	var mats: Dictionary = p.get("materials", {})
	var items: Dictionary = p.get("items", {})
	var mk := String(b.get("material", ""))
	var bk := String(b.get("buy", ""))
	var fill := float(b.get("fill", 1.0))
	var r := {"unit": "pcs", "amount": 1.0, "each": 0.0, "unit_cost": 0.0, "mass": 0.0, "mass_known": vol >= 0.0 and mk != "" and mats.has(mk), "source": "", "item": "", "material": mk, "priced": false, "why": ""}
	var mass_solid := -1.0
	if mk != "" and mats.has(mk) and vol >= 0.0:
		mass_solid = vol * float(mats[mk]["density_kg_m3"]) * fill
	if bk != "":
		if not items.has(bk):
			r["why"] = "no price for the item %s" % bk
			r["source"] = "NOT PRICED"
			r["mass"] = maxf(mass_solid, 0.0)
			return r
		var it: Dictionary = items[bk]
		var amt := float(b.get("qty", 1.0))
		r["unit"] = String(it.get("unit", "pcs"))
		r["amount"] = amt
		r["each"] = float(it["price"])
		r["unit_cost"] = amt * float(it["price"])
		r["item"] = bk
		r["mass"] = amt * float(it["mass_kg"]) if it.has("mass_kg") else maxf(mass_solid, 0.0)
		r["mass_known"] = it.has("mass_kg") or mass_solid >= 0.0
		r["source"] = String(it.get("source", "")) + " (" + String(it.get("date", "")) + ")"
		r["priced"] = true
		if b.has("included"):
			r["unit_cost"] = 0.0
			r["each"] = 0.0
			r["source"] = "included: " + String(b["included"])
		return r
	if mk == "" or not mats.has(mk):
		r["why"] = "no material: not priced" if mk == "" else "no price for the material %s" % mk
		r["source"] = "NOT PRICED"
		return r
	var m: Dictionary = mats[mk]
	r["mass"] = maxf(mass_solid, 0.0)
	r["each"] = r["mass"] * float(m["price_per_kg"])
	r["unit_cost"] = r["each"]
	r["source"] = String(m.get("source", "")) + " (" + String(m.get("date", "")) + ")"
	r["priced"] = true
	if b.has("included"):
		r["unit_cost"] = 0.0
		r["each"] = 0.0
		r["source"] = "included: " + String(b["included"])
	return r


## the bill of materials: {"lines": [line], "cost", "mass_kg", "parts" (solid parts), "items" (extras), "unpriced": n, "currency", "warnings"}.
## line = {"key", "part", "count", "qty", "unit", "material", "item", "volume_m3" (one part), "mass_kg" (one part), "line_mass_kg",
##         "unit_price" (per unit of qty), "line_cost", "source", "ids" (part ids; extras: "x<i>"), "extra": bool, "bom", "priced", "why"}
static func bom(asm: Dictionary, p := {}) -> Dictionary:
	var pr: Dictionary = p if not p.is_empty() else prices()
	var groups := {}
	var order: Array = []
	for part in asm.get("parts", []):
		var rec: Dictionary = part["rec"]
		var k := key_of(rec)
		if not groups.has(k):
			groups[k] = {"rec": rec, "name": String(_bom_of(rec).get("name", rec.get("name", part.get("name", "Part")))), "ids": [], "extra": false}
			order.append(k)
		groups[k]["ids"].append(String(part["id"]))
	var ex: Array = asm.get("bom_extra", [])
	for i in ex.size():
		var e: Dictionary = ex[i]
		var k := "x" + JSON.stringify(e, "", true).md5_text()
		if not groups.has(k):
			groups[k] = {"rec": e, "name": String(e.get("name", "Item")), "ids": [], "extra": true}
			order.append(k)
		groups[k]["ids"].append("x%d" % i)
	var lines: Array = []
	var cost := 0.0
	var mass := 0.0
	var parts := 0
	var items := 0
	var unpriced := 0
	var warn: Array = []
	for k in order:
		var g: Dictionary = groups[k]
		var b := _bom_of(g["rec"])
		var vol := -1.0
		if not g["extra"]:
			vol = float(Assembly.built(g["rec"])["volume"])
		var one := price_one(b, vol, pr)
		var n: int = (g["ids"] as Array).size()
		var qty: float = n * float(one["amount"])
		var lc: float = n * float(one["unit_cost"])
		var ln := {"key": k, "part": g["name"], "count": n, "qty": qty, "unit": one["unit"], "material": one["material"], "item": one["item"],
			"volume_m3": maxf(vol, 0.0), "mass_kg": one["mass"], "mass_known": one["mass_known"], "line_mass_kg": n * float(one["mass"]), "unit_price": lc / qty if qty > 0.0 else 0.0,
			"line_cost": lc, "source": one["source"], "ids": g["ids"], "extra": g["extra"], "bom": b, "priced": one["priced"], "why": one["why"]}
		lines.append(ln)
		cost += lc
		mass += float(ln["line_mass_kg"])
		if g["extra"]:
			items += n
		else:
			parts += n
		if not one["priced"]:
			unpriced += 1
			warn.append("%s: %s" % [g["name"], one["why"]])
	return {"lines": lines, "cost": cost, "mass_kg": mass, "parts": parts, "items": items, "unpriced": unpriced, "currency": String(pr.get("currency", "USD")), "warnings": warn}


## lines sorted by "part" | "qty" | "mass" | "cost" (a copy)
static func sorted_lines(lines: Array, col: String, asc: bool) -> Array:
	var out := lines.duplicate()
	var f := func(l: Dictionary):
		match col:
			"qty":
				return float(l["qty"])
			"mass":
				return float(l["line_mass_kg"])
			"cost":
				return float(l["line_cost"])
		return String(l["part"]).to_lower()
	out.sort_custom(func(a, b): return f.call(a) < f.call(b) if asc else f.call(a) > f.call(b))
	return out


# ---------------------------------------------------------------- cheaper

## the candidates a line may use: its "alt" list, else the materials of its material's family (a bought part without "alt" has none)
static func candidates(ln: Dictionary, p: Dictionary) -> Array:
	var b: Dictionary = ln["bom"]
	if b.has("included"):
		return []
	if b.get("alt") is Array:
		return (b["alt"] as Array).duplicate()
	var mk := String(b.get("material", ""))
	if String(b.get("buy", "")) != "" or mk == "" or not (p.get("materials", {}) as Dictionary).has(mk):
		return []
	var fam := String(p["materials"][mk].get("family", ""))
	var out: Array = []
	for k in p["materials"]:
		if fam != "" and String(p["materials"][k].get("family", "")) == fam:
			out.append(k)
	return out


## one line with candidate c: {"key": c, "name", "line_cost", "mass_kg" (one part), "ok": needs met, "why"}
static func try_alt(ln: Dictionary, c: String, p: Dictionary) -> Dictionary:
	var b: Dictionary = (ln["bom"] as Dictionary).duplicate(true)
	var mats: Dictionary = p.get("materials", {})
	var items: Dictionary = p.get("items", {})
	var props := {}
	if items.has(c):
		b["buy"] = c
		props = items[c]
	elif mats.has(c):
		b["material"] = c
		props = mats[c]
	else:
		return {"key": c, "name": c, "line_cost": INF, "mass_kg": 0.0, "ok": false, "why": "%s has no price" % c}
	var one := price_one(b, float(ln["volume_m3"]) if not ln["extra"] else -1.0, p)
	var why: Array = []
	var need: Dictionary = b.get("need", {}) if b.get("need") is Dictionary else {}
	for nk in need:
		if String(nk) == "max_mass_kg":
			if float(one["mass"]) > float(need[nk]) + 1e-12:
				why.append("mass %.4f kg > %.4f" % [one["mass"], float(need[nk])])
		elif not props.has(nk):
			why.append("%s unknown" % nk)
		elif float(props[nk]) < float(need[nk]):
			why.append("%s %s < %s" % [nk, str(props[nk]), str(need[nk])])
	return {"key": c, "name": String(props.get("name", c)), "line_cost": int(ln["count"]) * float(one["unit_cost"]), "mass_kg": one["mass"], "ok": why.is_empty() and bool(one["priced"]), "why": ", ".join(PackedStringArray(why))}


## the whole-design check the assembly names ({"ok": true, "why": "", "name": ""} when it names none)
static func system_check(asm: Dictionary) -> Dictionary:
	var nm := String(asm.get("bom_check", ""))
	if nm == "":
		return {"ok": true, "why": "", "name": ""}
	if not CHECKS.has(nm):
		return {"ok": false, "why": "unknown check %s" % nm, "name": nm}
	var r: Dictionary = load(String(CHECKS[nm])).check_asm(asm)
	r["name"] = nm
	return r


## the cheaper view: {"lines": [{"key", "part", "now", "best": try_alt row or {}, "saving", "alts": [rows]}], "saving_lines",
##  "design": {"changes": {line key: candidate}, "cost", "saving", "ok", "why", "check", "tried", "now_ok", "now_why"}}
## A line's best is the cheapest candidate that meets the part's own needs. The design is the cheapest combination of every line's choices
## (its current pick included) that meets them AND the assembly's named check (every combination when there are <= MAX_COMBOS)
static func cheaper(asm: Dictionary, p := {}) -> Dictionary:
	var pr: Dictionary = p if not p.is_empty() else prices()
	var b := bom(asm, pr)
	var rows: Array = []
	var saving := 0.0
	var axes: Array = []
	for ln in b["lines"]:
		var cur := String(ln["item"]) if String(ln["item"]) != "" else String(ln["material"])
		var alts: Array = []
		var best := {}
		var opts: Array = [{"key": cur, "line_cost": float(ln["line_cost"])}]
		for c in candidates(ln, pr):
			if String(c) == cur:
				continue
			var t := try_alt(ln, String(c), pr)
			alts.append(t)
			if t["ok"]:
				opts.append(t)
				if float(t["line_cost"]) < float(ln["line_cost"]) - 1e-9 and (best.is_empty() or float(t["line_cost"]) < float(best["line_cost"])):
					best = t
		var sv := float(ln["line_cost"]) - float(best["line_cost"]) if not best.is_empty() else 0.0
		saving += sv
		rows.append({"key": ln["key"], "part": ln["part"], "now": cur, "best": best, "saving": sv, "alts": alts})
		if opts.size() > 1:
			axes.append({"key": ln["key"], "now": float(ln["line_cost"]), "opts": opts})
	var now_chk := system_check(asm)
	var design := {"changes": {}, "cost": b["cost"], "saving": 0.0, "ok": bool(now_chk["ok"]), "why": now_chk["why"], "check": String(asm.get("bom_check", "")), "tried": 0, "now_ok": now_chk["ok"], "now_why": now_chk["why"]}
	var n := 1
	for a in axes:
		n *= (a["opts"] as Array).size()
	var combos: Array = []
	if n <= MAX_COMBOS:
		for i in n:
			var r := i
			var ch := {}
			var c := float(b["cost"])
			for a in axes:
				var o: Dictionary = a["opts"][r % (a["opts"] as Array).size()]
				r /= (a["opts"] as Array).size()
				c += float(o["line_cost"]) - float(a["now"])
				if String(o["key"]) != String((a["opts"][0] as Dictionary)["key"]):
					ch[a["key"]] = o["key"]
			combos.append({"changes": ch, "cost": c})
	else:   # too many: each line's own best, then the check
		var ch := {}
		var c := float(b["cost"])
		for rw in rows:
			if not (rw["best"] as Dictionary).is_empty():
				ch[rw["key"]] = rw["best"]["key"]
				c -= float(rw["saving"])
		combos.append({"changes": ch, "cost": c})
	combos.sort_custom(func(x, y): return float(x["cost"]) < float(y["cost"]))
	var tried := 0
	for cb in combos:
		if float(cb["cost"]) >= float(b["cost"]) - 1e-9 and bool(now_chk["ok"]):
			break   # nothing cheaper passes: keep the design as it is
		tried += 1
		var chk := {"ok": true, "why": ""}
		if design["check"] != "":
			var cp: Dictionary = asm.duplicate(true)
			apply_design(cp, cb["changes"])
			chk = system_check(cp)
		if chk["ok"]:
			design = {"changes": cb["changes"], "cost": cb["cost"], "saving": float(b["cost"]) - float(cb["cost"]), "ok": true, "why": "", "check": design["check"], "tried": tried, "now_ok": now_chk["ok"], "now_why": now_chk["why"]}
			break
	design["tried"] = tried
	return {"lines": rows, "saving_lines": saving, "design": design, "bom": b}


## line `key` uses candidate c (a material or an item key): every part (or extra) of the line gets it in its "bom". false when nothing matched
static func apply(asm: Dictionary, key: String, c: String, p := {}) -> bool:
	var pr: Dictionary = p if not p.is_empty() else prices()
	var field := "buy" if (pr.get("items", {}) as Dictionary).has(c) else ("material" if (pr.get("materials", {}) as Dictionary).has(c) else "")
	if field == "":
		return false
	var hit := false
	if key.begins_with("x"):
		for e in asm.get("bom_extra", []):
			if "x" + JSON.stringify(e, "", true).md5_text() == key:
				if not (e as Dictionary).has("bom"):
					e["bom"] = {}
				e["bom"][field] = c
				hit = true
		return hit
	for part in asm.get("parts", []):
		if key_of(part["rec"]) == key:
			var rec: Dictionary = part["rec"]
			if not (rec.get("bom") is Dictionary):
				rec["bom"] = {}
			rec["bom"][field] = c
			hit = true
	return hit


static func apply_design(asm: Dictionary, changes: Dictionary, p := {}) -> void:
	for k in changes:
		apply(asm, String(k), String(changes[k]), p)


# ---------------------------------------------------------------- CSV

static func _q(s: String) -> String:
	if s.contains(",") or s.contains("\"") or s.contains("\n"):
		return "\"" + s.replace("\"", "\"\"") + "\""
	return s


## the BOM as CSV (comma, dot decimals; money to 6 decimals so the rows add up to the TOTAL row within the written digits)
static func csv(b: Dictionary) -> String:
	var out := PackedStringArray([",".join(PackedStringArray(COLS))])
	for ln in b["lines"]:
		var row := [String(ln["part"]), String(ln["item"]), "%.6f" % float(ln["qty"]), String(ln["unit"]), String(ln["material"]), "%.6f" % (float(ln["volume_m3"]) * 1e6),
			"%.9f" % float(ln["mass_kg"]), "%.6f" % float(ln["unit_price"]), "%.6f" % float(ln["line_cost"]), String(ln["source"]) if ln["priced"] else "NOT PRICED: " + String(ln["why"])]
		var q := PackedStringArray()
		for s in row:
			q.append(_q(String(s)))
		out.append(",".join(q))
	out.append(",".join(PackedStringArray(["TOTAL", "", "%d parts + %d items" % [int(b["parts"]), int(b["items"])], "", "", "", "%.9f" % float(b["mass_kg"]), "", "%.6f" % float(b["cost"]), String(b["currency"])])))
	return "\n".join(out) + "\n"


## write the BOM of asm as <exports>/<name>_bom.csv (or path): {"ok", "path", "why", "text", "bom"}
static func write_csv(asm: Dictionary, path := "", p := {}) -> Dictionary:
	var b := bom(asm, p)
	if (b["lines"] as Array).is_empty():
		return {"ok": false, "path": "", "why": "Nothing to list: put a part in the assembly first", "text": "NOT DONE: Nothing to list: put a part in the assembly first", "bom": b}
	if path == "":
		var g := ProjectSettings.globalize_path(Assembly.export_dir)
		DirAccess.make_dir_recursive_absolute(g)
		path = "%s/%s_bom.csv" % [g, MeshExport.stem(String(asm.get("name", "Assembly")))]
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "path": path, "why": error_string(FileAccess.get_open_error()), "text": "NOT DONE: the file could not be written. Check the folder is writable", "bom": b}
	f.store_string(csv(b))
	f.close()
	return {"ok": true, "path": path, "why": "", "text": "BOM written to %s: %d lines, %s %.2f" % [path.get_file(), (b["lines"] as Array).size(), String(b["currency"]), float(b["cost"])], "bom": b}
