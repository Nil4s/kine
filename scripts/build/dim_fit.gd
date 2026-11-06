class_name DimFit
extends RefCounted
## G3: ISO 286 fit classes as a real Part feature. A sketch dimension (kind r / w / h / len) carries "fit": "H7" (hole, upper case) or "g6" (shaft, lower case)
## in its record (Part.from_file keeps the dims whole, so it survives save, load, undo and replay). A radius dimension counts as its DIAMETER (2 x mm).
## An Assembly record may carry (all optional, old records unchanged):
##   "fits":   [{"name", "hole": {"part": id, "dim": "f1:d1"}, "shaft": {"part": id, "dim": "f2:d1"}, "motion": "" | "slide" | "rotate"}]
##   "stacks": [{"name", "links": [{"part": id, "dim": "f1:d1", "sign": 1 | -1, "tol": um (optional), "grade": 5..10 (optional)}]}]
## A dim key is "<sketch feature id>:<dim id>". The maths is IsoFits (scripts/build/iso_fits.gd); the panel (assembly_fits_ui.gd) and the agent call `fits` read only this.
const Iso := preload("res://scripts/build/iso_fits.gd")
const FIT_KINDS := ["r", "w", "h", "len"]
const SLIDING := ["slider", "revolute"]


static func value_mm(d: Dictionary) -> float:
	return float(d.get("mm", 0.0)) * (2.0 if String(d.get("kind", "")) == "r" else 1.0)


## sets (code) or clears ("") the fit class of dims[i] of a sketch feature; "" when done, else the words why not
static func set_fit(sk: Dictionary, i: int, code: String) -> String:
	var dims: Array = sk.get("dims", [])
	if i < 0 or i >= dims.size():
		return "there is no such dimension"
	var d: Dictionary = dims[i]
	var c := code.strip_edges()
	if c == "":
		d.erase("fit")
		return ""
	if not String(d.get("kind", "")) in FIT_KINDS:
		return "a fit class goes on a size (a diameter, width, height or length), not on a position"
	var lim := Iso.limits_of(value_mm(d), c)
	if not bool(lim["ok"]):
		return String(lim["why"])
	d["fit"] = c
	return ""


## the limits of a dimension that carries a fit class ({} when it does not): Iso.limits_of on its diameter / size
static func limits(d: Dictionary) -> Dictionary:
	if String(d.get("fit", "")) == "":
		return {}
	return Iso.limits_of(value_mm(d), String(d["fit"]))


## the text next to the dimension: "Ø20 H7 +21/0 um (20.000 to 20.021)" ("" without a class)
static func label(d: Dictionary) -> String:
	var l := limits(d)
	if l.is_empty():
		return ""
	if not bool(l["ok"]):
		return "%s: %s" % [String(d["fit"]), String(l["why"])]
	return ("Ø" if String(d.get("kind", "")) == "r" else "") + String(l["text"])


# ---------------------------------------------------------------- finding dimensions in a Part record

## what the dimension is called on screen: a radius dimension is read as a diameter
static func disp_name(d: Dictionary) -> String:
	var n := String(d.get("name", ""))
	return n.replace("radius", "diameter") if String(d.get("kind", "")) == "r" else n


static func key_of(f: Dictionary, d: Dictionary) -> String:
	return "%s:%s" % [String(f.get("id", "")), String(d.get("id", ""))]


static func find(rec: Dictionary, key: String) -> Dictionary:
	var sp := key.split(":")
	if sp.size() != 2:
		return {}
	for f in rec.get("features", []):
		if String(f.get("id", "")) == sp[0]:
			for d in f.get("dims", []):
				if String(d.get("id", "")) == sp[1]:
					return d
	return {}


## every size dimension of a part: [{"key", "name", "kind", "size_mm", "fit", "text"}]
static func dims_of(rec: Dictionary) -> Array:
	var out: Array = []
	for f in rec.get("features", []):
		for d in f.get("dims", []):
			if not String(d.get("kind", "")) in FIT_KINDS:
				continue
			out.append({"key": key_of(f, d), "name": disp_name(d), "kind": String(d["kind"]), "size_mm": value_mm(d), "fit": String(d.get("fit", "")), "text": label(d)})
	return out


static func _part(asm: Dictionary, id: String) -> Dictionary:
	for p in asm.get("parts", []):
		if String(p.get("id", "")) == id:
			return p
	return {}


## every dimension of every part of the assembly: [{"part", "part_name", + dims_of fields}]
static func all_dims(asm: Dictionary) -> Array:
	var out: Array = []
	for p in asm.get("parts", []):
		for e in dims_of(p.get("rec", {})):
			e["part"] = String(p["id"])
			e["part_name"] = String(p.get("name", ""))
			out.append(e)
	return out


# ---------------------------------------------------------------- mating pairs

static func _end(asm: Dictionary, e: Dictionary, role: String) -> Dictionary:
	var p := _part(asm, String(e.get("part", "")))
	if p.is_empty():
		return {"ok": false, "why": "%s part '%s' is not in the assembly" % [role, String(e.get("part", ""))]}
	var d := find(p.get("rec", {}), String(e.get("dim", "")))
	if d.is_empty():
		return {"ok": false, "why": "%s dimension '%s' is not on %s" % [role, String(e.get("dim", "")), String(p.get("name", ""))]}
	if String(d.get("fit", "")) == "":
		return {"ok": false, "why": "%s dimension %s of %s has no fit class (type one, e.g. %s)" % [role, String(d.get("name", "")), String(p.get("name", "")), "H7" if role == "hole" else "g6"]}
	return {"ok": true, "part": String(p["id"]), "part_name": String(p.get("name", "")), "dim": String(e["dim"]), "code": String(d["fit"]), "d": value_mm(d)}


## a joint of the assembly that lets the two parts slide or turn on each other
static func sliding_joint(asm: Dictionary, a: String, b: String) -> String:
	for j in asm.get("joints", []):
		var ja := String(j.get("a", ""))
		var jb := String(j.get("b", ""))
		if String(j.get("kind", "")) in SLIDING and ((ja == a and jb == b) or (ja == b and jb == a)):
			return String(j.get("name", j.get("kind", "")))
	return ""


## one mating pair as data: {"ok", "name", "d", "hole", "shaft", "kind", "cmin_um", "cmax_um", "flag", "flag_why", "why"}
static func pair_report(asm: Dictionary, fx: Dictionary) -> Dictionary:
	var out := {"name": String(fx.get("name", "")), "ok": false, "flag": false, "flag_why": ""}
	var h := _end(asm, fx.get("hole", {}), "hole")
	var s := _end(asm, fx.get("shaft", {}), "shaft")
	out["hole"] = h
	out["shaft"] = s
	if not bool(h["ok"]):
		out["why"] = h["why"]
		return out
	if not bool(s["ok"]):
		out["why"] = s["why"]
		return out
	if absf(float(h["d"]) - float(s["d"])) > 0.0005:
		out["why"] = "the hole is %s mm and the shaft %s mm: a fit needs one nominal size" % [String.num(float(h["d"]), 4), String.num(float(s["d"]), 4)]
		return out
	var f := Iso.mate(float(h["d"]), String(h["code"]), String(s["code"]))
	if not bool(f["ok"]):
		out["why"] = f["why"]
		return out
	out["ok"] = true
	out["d"] = float(h["d"])
	out["fit"] = f["name"]
	out["kind"] = f["kind"]
	out["cmin_um"] = f["cmin"]
	out["cmax_um"] = f["cmax"]
	out["hole_limits"] = Iso.hole_limits(float(h["d"]), f["hole"])
	out["shaft_limits"] = Iso.shaft_limits(float(h["d"]), f["shaft"])
	var mv := String(fx.get("motion", ""))
	var jn := sliding_joint(asm, String(h["part"]), String(s["part"]))
	if String(f["kind"]) == "interference" and (jn != "" or mv in ["slide", "rotate"]):
		out["flag"] = true
		out["flag_why"] = "INTERFERENCE FIT DRAWN AS A SLIDING JOINT: %s is a press fit (%s to %s um) but %s" % [out["fit"], String.num(float(f["cmin"]), 0), String.num(float(f["cmax"]), 0), ("the assembly joins them with '%s'" % jn) if jn != "" else ("the pair is marked '%s'" % mv)]
	return out


static func pair_text(r: Dictionary) -> String:
	if not bool(r["ok"]):
		return "%s: %s" % [String(r["name"]), String(r["why"])]
	var t := "%s  %s %s  clearance %s to %s um" % [String(r["name"]), Iso.fmt(float(r["d"])), String(r["fit"]), String.num(float(r["cmin_um"]), 0), String.num(float(r["cmax_um"]), 0)]
	t += "  [%s]" % String(r["kind"]).to_upper()
	if bool(r["flag"]):
		t += "  !! " + String(r["flag_why"])
	return t


# ---------------------------------------------------------------- stack-ups

## one link of a chain as IsoFits wants it: {"name", "nom" (mm), "tol" (um, +-), "sign", "grade"}, or {"ok": false, "why"}
static func link_of(asm: Dictionary, lk: Dictionary) -> Dictionary:
	var p := _part(asm, String(lk.get("part", "")))
	if p.is_empty():
		return {"ok": false, "why": "part '%s' is not in the assembly" % String(lk.get("part", ""))}
	var d := find(p.get("rec", {}), String(lk.get("dim", "")))
	if d.is_empty():
		return {"ok": false, "why": "dimension '%s' is not on %s" % [String(lk.get("dim", "")), String(p.get("name", ""))]}
	var sg := -1 if int(lk.get("sign", 1)) < 0 else 1
	var nm := "%s: %s" % [String(p.get("name", "")), disp_name(d)]
	var v := value_mm(d)
	if String(d.get("fit", "")) != "":   # a fit class: the nominal moves to the middle of the zone, the tolerance is half its width
		var l := Iso.limits_of(v, String(d["fit"]))
		if not bool(l["ok"]):
			return {"ok": false, "why": String(l["why"])}
		return {"ok": true, "name": nm, "nom": (float(l["lo"]) + float(l["hi"])) / 2.0, "tol": (float(l["es"]) - float(l["ei"])) / 2.0, "sign": sg, "grade": Iso.parse_code(String(d["fit"]))["grade"], "src": String(d["fit"])}
	if lk.has("tol"):
		return {"ok": true, "name": nm, "nom": v, "tol": absf(float(lk["tol"])), "sign": sg, "grade": "", "src": "+-%s um" % String.num(absf(float(lk["tol"])), 3)}
	if lk.has("grade"):
		if v <= 6.0 or v > 180.0 or not Iso.IT.has(int(lk["grade"])):
			return {"ok": false, "why": "IT%d at %s mm is outside the tables (6..180 mm, IT5..IT10)" % [int(lk["grade"]), String.num(v, 3)]}
		return {"ok": true, "name": nm, "nom": v, "tol": Iso.it(int(lk["grade"]), v) / 2.0, "sign": sg, "grade": int(lk["grade"]), "src": "IT%d" % int(lk["grade"])}
	return {"ok": true, "name": nm, "nom": v, "tol": 0.0, "sign": sg, "grade": "", "src": "no tolerance"}


## a chain as data: nominal, worst case, RSS (Iso.stack), plus the corner enumeration. {"ok", "name", "links", "chain", + Iso.stack_report fields} or {"ok": false, "why"}
static func stack_report(asm: Dictionary, st: Dictionary) -> Dictionary:
	var chain: Array = []
	var links: Array = []
	for lk in st.get("links", []):
		var l := link_of(asm, lk)
		if not bool(l["ok"]):
			return {"ok": false, "name": String(st.get("name", "")), "why": String(l["why"])}
		chain.append({"name": l["name"], "nom": l["nom"], "tol": l["tol"], "sign": l["sign"], "grade": l["grade"]})
		links.append(l)
	if chain.is_empty():
		return {"ok": false, "name": String(st.get("name", "")), "why": "the chain has no links yet: pick dimensions"}
	var r := Iso.stack_report(chain)
	r["ok"] = true
	r["name"] = String(st.get("name", ""))
	r["links"] = links
	r["chain"] = chain
	return r


static func stack_text(r: Dictionary) -> String:
	if not bool(r["ok"]):
		return "%s: %s" % [String(r["name"]), String(r["why"])]
	return "%s  nominal %.4f mm   worst case +-%.1f um (%.4f to %.4f)   RSS +-%.2f um (%.4f to %.4f)" % [String(r["name"]), float(r["nominal"]), float(r["tol_worst"]), float(r["min_worst"]), float(r["max_worst"]), float(r["tol_rss"]), float(r["min_rss"]), float(r["max_rss"])]


static func stack_csv(r: Dictionary) -> String:
	return Iso.stack_csv(r["chain"]) if bool(r["ok"]) else ""


## writes the CSV of stack si; path "" = the exports folder. {"ok", "path", "text"}
static func write_stack_csv(asm: Dictionary, si: int, path := "") -> Dictionary:
	var sts: Array = asm.get("stacks", [])
	if si < 0 or si >= sts.size():
		return {"ok": false, "path": "", "text": "NOT DONE: there is no such stack-up"}
	var r := stack_report(asm, sts[si])
	if not bool(r["ok"]):
		return {"ok": false, "path": "", "text": "NOT DONE: " + String(r["why"])}
	if path == "":
		var g := ProjectSettings.globalize_path(Assembly.export_dir)
		DirAccess.make_dir_recursive_absolute(g)
		path = "%s/%s_stackup.csv" % [g, MeshExport.stem(String(asm.get("name", "Assembly")))]
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "path": path, "text": "NOT DONE: the file could not be written. Check the folder is writable"}
	f.store_string(stack_csv(r))
	f.close()
	return {"ok": true, "path": path, "text": "Stack-up written to %s: %d links" % [path.get_file(), (r["chain"] as Array).size()]}


# ---------------------------------------------------------------- editing the record (the panel wraps each in one undo step)

static func add_pair(asm: Dictionary, nm: String, hole_part: String, hole_dim: String, shaft_part: String, shaft_dim: String, motion := "") -> int:
	var fs: Array = (asm.get("fits", []) as Array).duplicate()
	fs.append({"name": nm if nm != "" else "Fit %d" % (fs.size() + 1), "hole": {"part": hole_part, "dim": hole_dim}, "shaft": {"part": shaft_part, "dim": shaft_dim}, "motion": motion})
	asm["fits"] = fs
	return fs.size() - 1


static func add_stack(asm: Dictionary, nm := "") -> int:
	var ss: Array = (asm.get("stacks", []) as Array).duplicate()
	ss.append({"name": nm if nm != "" else "Stack %d" % (ss.size() + 1), "links": []})
	asm["stacks"] = ss
	return ss.size() - 1


static func add_link(asm: Dictionary, si: int, part: String, dim: String, sign: int, extra := {}) -> void:
	var ss: Array = asm.get("stacks", [])
	if si < 0 or si >= ss.size():
		return
	var lk := {"part": part, "dim": dim, "sign": -1 if sign < 0 else 1}
	for k in ["tol", "grade"]:
		if extra.has(k):
			lk[k] = extra[k]
	(ss[si]["links"] as Array).append(lk)


# ---------------------------------------------------------------- the whole thing as data (the agent call `fits` and the panel's numbers)

static func report(asm: Dictionary) -> Dictionary:
	var fits: Array = []
	for fx in asm.get("fits", []):
		fits.append(pair_report(asm, fx))
	var stacks: Array = []
	for st in asm.get("stacks", []):
		stacks.append(stack_report(asm, st))
	return {"name": String(asm.get("name", "")), "dims": all_dims(asm), "fits": fits, "stacks": stacks}


## agent_tools "fits": {assembly: record | path: file} else the Assembly on screen; {part: record} or the live Part gives that part's dimensions; {csv: true} adds each stack's CSV
static func serve(m: Node, p: Dictionary) -> Dictionary:
	var asm: Dictionary = {}
	if p.get("assembly") is Dictionary:
		asm = p["assembly"]
	elif String(p.get("path", "")) != "":
		asm = Assembly.read(String(p["path"]))
		if asm.is_empty():
			return {"ok": false, "error": "no assembly at that path"}
	elif m != null and m.get("bld") != null and m.bld.get("asm") != null and bool(m.bld.asm.on):
		asm = m.bld.asm.asm
	if asm.is_empty():
		var rec: Dictionary = p["part"] if p.get("part") is Dictionary else (m.S.part if m != null else {})
		if rec.is_empty() or not rec.get("features") is Array:
			return {"ok": false, "error": "fits needs {\"assembly\": record}, {\"path\": file}, the Assembly on screen, or a part ({\"part\": record} or the live one)"}
		return {"ok": true, "result": {"dims": dims_of(rec)}}
	var r := report(asm)
	if bool(p.get("csv", false)):
		var csvs: Array = []
		for s in r["stacks"]:
			csvs.append(stack_csv(s))
		r["csv"] = csvs
	for s in r["stacks"]:
		s.erase("chain")
	return {"ok": true, "result": r}
