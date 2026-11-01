class_name CutList
extends RefCounted
## s081 CUT LIST FROM BOARDS (Friday plan 81) + s081 COST READOUT in BRL (plan 58).
## A build made of wood boards (Parts > Wood boards, or solids painted Wood): each solid is a board. Its box is read from the built triangles
## (whole mm): length = longest side, width = middle, thickness = shortest. Boards of the same size share one row with a count. The total is in
## board-metres (sum of count x length). Written as a CSV (dot decimals, comma between columns) from the Export dialog's "Cut list" target.
## The cost line: PLA (every solid that is not wood) = volume x density x R$ per kg; wood = board length x R$ per metre. The prices are a small
## editable table in user://kine_prices.json (the Export dialog's Prices row edits it). Shown as "about R$ 4,20" (Brazilian decimal comma).

const PRICES_FILE := "user://kine_prices.json"
const DEFAULT_PRICES := {"pla_brl_kg": 120.0, "pla_g_cm3": 1.24, "pine_brl_m": 14.0}
const WOOD_COLOUR := Color("#9a6b3f")   # the same brown as the Colour > Wood chip (easy_part_base.gd)
const BOARD_NAMES := {"89x38": "2x4 board"}   # width x thickness in mm -> the Parts > Wood boards chip's name

static var _prices_cache := {}
static var _prices_stamp := -1
static var _wood_key := -1
static var _wood_val := false


## ---------- prices ----------

## the price table now: the defaults, over-written by whatever the file holds (a missing, broken or non-number entry keeps the default)
static func prices() -> Dictionary:
	var stamp := int(FileAccess.get_modified_time(PRICES_FILE)) if FileAccess.file_exists(PRICES_FILE) else 0
	if stamp == _prices_stamp and not _prices_cache.is_empty():
		return _prices_cache
	var out := DEFAULT_PRICES.duplicate()
	if FileAccess.file_exists(PRICES_FILE):
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(PRICES_FILE))
		if v is Dictionary:
			for k in DEFAULT_PRICES:
				if (v as Dictionary).has(k) and ((v as Dictionary)[k] is float or (v as Dictionary)[k] is int) and float((v as Dictionary)[k]) >= 0.0:
					out[k] = float((v as Dictionary)[k])
	_prices_cache = out
	_prices_stamp = stamp
	return out


## one price changed (and kept in the file). Returns true when written
static func set_price(key: String, value: float) -> bool:
	if not DEFAULT_PRICES.has(key) or value < 0.0:
		return false
	var cur := prices().duplicate()
	cur[key] = value
	var f := FileAccess.open(PRICES_FILE, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(cur, "\t"))
	f.close()
	_prices_stamp = -2   # read again (the file's clock may not move inside one second)
	_prices_cache = cur
	return true


## a key that changes whenever the price table does (the readout's cache)
static func prices_key() -> int:
	return prices().hash()


## ---------- the boards ----------

static func _is_wood_look(look: Dictionary) -> bool:
	var c: Color = look.get("c", Color.WHITE)
	return String(look.get("preset", "")) == "Paint" and absf(c.r - WOOD_COLOUR.r) < 0.02 and absf(c.g - WOOD_COLOUR.g) < 0.02 and absf(c.b - WOOD_COLOUR.b) < 0.02


## each solid of the part: {"wood": bool, "dims": [thickness, width, length] whole mm, sorted, "vol_cm3": float}. Empty when there is no solid
static func solids(rec: Dictionary) -> Array:
	var out := []
	if not Part.available() or (rec.get("features", []) as Array).is_empty():
		return out
	var res := Part.replay(rec, -1, {})
	var vols: Array = res.get("volumes", [])
	var looks: Array = res.get("body_looks", [])
	var tpl_board := String((rec.get("easy", {}) as Dictionary).get("t", "")) == "board"
	var faces := Part.body_faces(rec)
	for i in faces.size():
		var tris: PackedVector3Array = faces[i]
		if tris.is_empty():
			continue
		var lo: Vector3 = tris[0]
		var hi: Vector3 = tris[0]
		for p in tris:
			lo = lo.min(p)
			hi = hi.max(p)
		var d := (hi - lo) / Part.MM
		var dims := [roundi(d.x), roundi(d.y), roundi(d.z)]
		dims.sort()
		out.append({"wood": tpl_board or _is_wood_look(Part.look_at(looks, i)), "dims": dims, "vol_cm3": (float(vols[i]) * 1.0e6) if i < vols.size() else 0.0})
	return out


## true when the part has a solid and every solid is wood (a Wood boards part, or solids painted Wood)
static func is_wood_build(rec: Dictionary) -> bool:
	var key: int = [rec.get("features", []), (rec.get("easy", {}) as Dictionary).get("t", "")].hash()
	if key == _wood_key:
		return _wood_val
	var ss := solids(rec)
	var all := not ss.is_empty()
	for s in ss:
		all = all and bool(s["wood"])
	_wood_key = key
	_wood_val = all
	return all


## the cut list: {"rows": [{name, length, width, thickness, count}], "boards": n, "total_m": float}. Only the wood solids are boards
static func boards(rec: Dictionary) -> Dictionary:
	var rows := []
	var idx := {}
	var n := 0
	var total := 0.0
	for s in solids(rec):
		if not bool(s["wood"]):
			continue
		var dims: Array = s["dims"]
		var key := "%d x %d x %d" % [dims[2], dims[1], dims[0]]
		if not idx.has(key):
			idx[key] = rows.size()
			var nm: String = String(BOARD_NAMES.get("%dx%d" % [dims[1], dims[0]], "Board"))
			rows.append({"name": nm, "length": int(dims[2]), "width": int(dims[1]), "thickness": int(dims[0]), "count": 0})
		rows[idx[key]]["count"] += 1
		n += 1
		total += float(dims[2]) / 1000.0
	return {"rows": rows, "boards": n, "total_m": total}


## the CSV text: a header, one line per row, a TOTAL line. Dots in numbers (a spreadsheet or a script reads them); no quoting needed (no commas in names)
static func csv_text(bl: Dictionary) -> String:
	var lines := ["name,length_mm,width_mm,thickness_mm,count,board_metres"]
	for r in bl["rows"]:
		lines.append("%s,%d,%d,%d,%d,%.3f" % [r["name"], r["length"], r["width"], r["thickness"], r["count"], float(r["length"]) * int(r["count"]) / 1000.0])
	lines.append("TOTAL,,,,%d,%.3f" % [bl["boards"], bl["total_m"]])
	return "\n".join(lines) + "\n"


## writes <dir>/<Part>_cutlist.csv. {"ok", "path", "text"}
static func export_csv(rec: Dictionary, dir: String) -> Dictionary:
	var bl := boards(rec)
	if int(bl["boards"]) == 0:
		return {"ok": false, "path": "", "text": "NOT DONE: no wood boards in this build. Pick one from Parts > Wood boards, or paint the solids Wood, then export the cut list"}
	var gdir := ProjectSettings.globalize_path(dir)
	DirAccess.make_dir_recursive_absolute(gdir)
	var path := "%s/%s_cutlist.csv" % [gdir, MeshExport.stem(String(rec.get("name", "Part")))]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		var e := FileAccess.get_open_error()
		return {"ok": false, "path": path, "text": "NOT DONE: the file could not be written (%s). Check that the folder is writable, then export again" % error_string(e)}
	f.store_string(csv_text(bl))
	f.close()
	return {"ok": true, "path": path, "text": "exported %s: %d board%s in %d size%s, %s of board in all" % [path.get_file(), bl["boards"], "" if int(bl["boards"]) == 1 else "s", (bl["rows"] as Array).size(), "" if (bl["rows"] as Array).size() == 1 else "s", metres_words(float(bl["total_m"]))]}


static func metres_words(m: float) -> String:
	return "%s m" % brl_num(m, 2, false)


## the dialog's checklist lines
static func check_lines(rec: Dictionary) -> Array:
	var bl := boards(rec)
	if int(bl["boards"]) == 0:
		return ["WARN  no wood boards in this build: pick one from Parts > Wood boards, or paint the solids Wood"]
	var out := []
	for r in bl["rows"]:
		out.append("OK    %d x %s %d x %d x %d mm" % [r["count"], String(r["name"]).to_lower(), r["length"], r["width"], r["thickness"]])
	out.append("OK    total: %d boards, %s of board" % [bl["boards"], metres_words(float(bl["total_m"]))])
	return out


## ---------- the cost ----------

## a number with a decimal comma and a dot between thousands: 1234.5 -> "1.234,50"
static func brl_num(v: float, decimals := 2, thousands := true) -> String:
	var s := ("%." + str(decimals) + "f") % v
	var parts := s.split(".")
	var whole := parts[0]
	if thousands and whole.length() > 3:
		var g := ""
		var cnt := 0
		for i in range(whole.length() - 1, -1, -1):
			g = whole[i] + g
			cnt += 1
			if cnt % 3 == 0 and i > 0 and whole[i - 1] != "-":
				g = "." + g
		whole = g
	return whole + ("," + parts[1] if parts.size() > 1 else "")


## "about R$ 4,20" for an amount
static func brl_words(v: float) -> String:
	return "about R$ " + brl_num(v)


## the cost of the part: {"brl": float, "pla_brl", "wood_brl", "text": "about R$ 2,98"}; {} when there is no solid
static func cost(rec: Dictionary) -> Dictionary:
	var ss := solids(rec)
	if ss.is_empty():
		return {}
	var pr := prices()
	var pla := 0.0
	var wood := 0.0
	for s in ss:
		if bool(s["wood"]):
			wood += float((s["dims"] as Array)[2]) / 1000.0 * float(pr["pine_brl_m"])
		else:
			pla += float(s["vol_cm3"]) * float(pr["pla_g_cm3"]) / 1000.0 * float(pr["pla_brl_kg"])
	return {"brl": pla + wood, "pla_brl": pla, "wood_brl": wood, "text": brl_words(pla + wood)}
