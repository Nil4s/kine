extends SceneTree
## godot --path . -s tests/g8bom_test.gd     (G8BOM: the bill of materials of an Assembly, gap G8 of docs/CHALLENGE_FEEDBACK.md;
## scripts/build/assembly_bom.gd, assembly_bom_ui.gd, data/prices.json, ch14_bom.gd assembly()). Bars committed before the first run; every
## bar has a planted control (a "CONTROL" line that must be caught):
##   a MASS       a 40 x 20 x 10 mm steel box, an r 5 x 30 mm aluminium cylinder and an r 10 / 8 x 50 mm PLA+ tube in an Assembly: each line's
##                volume (the exact solid) and mass equal the hand volume x density (7850, 2700, 1240 kg/m3) to 1e-9 relative, the total is their
##                sum. CONTROL: PLA+'s density typed as 1.24 (g/cm3 as kg/m3) is named by AssemblyBom.validate and its mass misses by > 50 pct
##   b GROUP      four identical M4 bolts are ONE line of qty 4 (mass 4 x the solid x 7850, cost 4 x the item price).
##                CONTROL: one bolt 1 mm longer splits it into two lines (3 + 1)
##   c CH14       the CH14 arm as an Assembly (ch14_bom.assembly) through the new BOM: every line group except the boom links equals CH14's own
##                bom() line to 1e-9 USD (syringes, tubes, printed parts, base, dowels, pads, sundries), and the total differs from CH14's
##                (29.37) by exactly the boom difference (1e-9): CH14 prices a 30 mm section x length, the new BOM the CAD solid (printed).
##                The cheaper view's design costs no more than CH14's own cheapest-design search (BOM.cheapest, 26.49), passes CH14's working bars
##                (ch14_bom.check_asm, re-run on the applied copy) and every line's own needs, and bom() of the applied copy costs what it said.
##                CONTROL: all tube soft PVC fails the CH14 bars, and the runs line's E >= 50 MPa need refuses PVC
##   d CSV        write_csv to disk, read back with this file's own parser: one row per line + TOTAL; the rows' cost and mass add up to the TOTAL row
##                within the written digits ((n + 1) x 0.5e-6 USD; (parts + 1) x 0.5e-9 kg, the mass column being one part's) and the TOTAL
##                row equals bom() to 0.5e-6.
##                CONTROL: the file with one line 0.01 USD dearer does not add up
##   e SOURCES    every entry of data/prices.json has a source and a YYYY-MM-DD date (ASSUMED counted); AssemblyBom.validate is clean.
##                CONTROL: a copy with one source erased and one date missing gives exactly those two problems
##   f UI         the CH14 assembly in the Assembly screen: BOM opens the table (one row per line, the totals); Cost sorts it up then down, Part by
##                name; the upper arm's Cheaper button puts its cheapest material in (ONE undo step, the total falls by the saving shown); Copy
##                puts bom()'s CSV on the clipboard; Ctrl+Z gives back the identical record. CONTROL: after the change the record differs.
##                Shots C:/Temp/claude/g8bom/bom_open.png, bom_cheaper.png
##   g OLD        tests/assets/g1motion/old_assembly.json, g2loop/drive_199.json (#199), g7time/joint_204.json (#204) and g8bom/anim_205.json
##                (written by the #205 code before this branch) open in the screen, the BOM opens, sorts and closes, and they save back equal.
##                CONTROL: the #205 record with one material applied does not compare equal
const BOM := preload("res://scripts/build/ch14_bom.gd")
const A14 := preload("res://scripts/build/ch14_arm.gd")
const PT := preload("res://scripts/build/ch14_parts.gd")
const OUT := "C:/Temp/claude/g8bom"
const OLD := ["res://tests/assets/g1motion/old_assembly.json", "res://tests/assets/g2loop/drive_199.json", "res://tests/assets/g7time/joint_204.json", "res://tests/assets/g8bom/anim_205.json"]
var fails := 0
var m: Node
var A: AssemblyUI


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func ctl(c: bool, w: String) -> void:
	ok(c, "CONTROL " + w)


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func sci(x: float) -> String:
	if x == 0.0:
		return "0"
	var e := floori(log(absf(x)) / log(10.0))
	return "%.2fe%d" % [x / pow(10.0, e), e]


func rel(a: float, b: float) -> float:
	return absf(a - b) / maxf(absf(b), 1e-300)


func rec_of(nm: String, feats: Array, bom: Dictionary) -> Dictionary:
	var fs: Array = []
	for i in feats.size():
		var f: Dictionary = (feats[i] as Dictionary).duplicate()
		f["id"] = "f%d" % (i + 1)
		f["name"] = "Prim%d" % (i + 1)
		fs.append(f)
	return {"version": 1, "name": nm, "seq": 1, "features": fs, "bom": bom}


func line_named(b: Dictionary, nm: String) -> Dictionary:
	for ln in b["lines"]:
		if String(ln["part"]) == nm:
			return ln
	return {}


# ------------------------------------------------------------------ a
func bars_mass() -> void:
	var asm := Assembly.make("Three solids")
	var box := rec_of("Steel box", [{"t": "prim", "kind": "box", "op": "new", "x": 0, "y": 0, "z": 0, "w": 40, "h": 20, "d": 10}], {"material": "steel"})
	var cyl := rec_of("Aluminium rod", [{"t": "prim", "kind": "cylinder", "op": "new", "x": 0, "y": 0, "z": 0, "axis": "y", "r": 5, "len": 30}], {"material": "aluminium"})
	var tub := rec_of("PLA tube", [{"t": "prim", "kind": "tube", "op": "new", "x": 0, "y": 0, "z": 0, "axis": "y", "r": 10, "r_in": 8, "len": 50}], {"material": "pla"})
	for r in [box, cyl, tub]:
		Assembly.add_part(asm, r)
	var hand := {"Steel box": [40.0 * 20.0 * 10.0 * 1e-9, 7850.0], "Aluminium rod": [PI * 25.0 * 30.0 * 1e-9, 2700.0], "PLA tube": [PI * (100.0 - 64.0) * 50.0 * 1e-9, 1240.0]}
	var b := AssemblyBom.bom(asm)
	var worst := 0.0
	var tot := 0.0
	for nm in hand:
		var ln := line_named(b, nm)
		var hv: float = hand[nm][0]
		var hm: float = hv * float(hand[nm][1])
		var e := maxf(rel(float(ln.get("volume_m3", 0.0)), hv), rel(float(ln.get("mass_kg", 0.0)), hm)) if not ln.is_empty() else 1.0
		worst = maxf(worst, e)
		tot += hm
		print("     a %-14s volume %.6f cm3 (hand %.6f)  mass %.9f kg (hand %.9f)  rel %s" % [nm, float(ln.get("volume_m3", 0.0)) * 1e6, hv * 1e6, float(ln.get("mass_kg", 0.0)), hm, sci(e)])
	ok(worst < 1e-9 and rel(float(b["mass_kg"]), tot) < 1e-9 and (b["lines"] as Array).size() == 3, "a three solids: mass = exact volume x density to %s (bar 1e-9), total %.9f kg = %.9f" % [sci(worst), float(b["mass_kg"]), tot])
	var bad: Dictionary = AssemblyBom.prices().duplicate(true)
	bad["materials"]["pla"]["density_kg_m3"] = 1.24
	var probs := AssemblyBom.validate(bad)
	var bl := line_named(AssemblyBom.bom(asm, bad), "PLA tube")
	var hm_t: float = float(hand["PLA tube"][0]) * 1240.0
	var named := false
	for p in probs:
		named = named or String(p).begins_with("materials pla: density")
	ctl(named and rel(float(bl.get("mass_kg", 0.0)), hm_t) > 0.5, "a density 1.24 'kg/m3' (a g/cm3 number): validate says '%s'; mass %.9f kg vs %.9f (off %.0f pct)" % [", ".join(PackedStringArray(probs)), float(bl.get("mass_kg", 0.0)), hm_t, 100.0 * rel(float(bl.get("mass_kg", 0.0)), hm_t)])


# ------------------------------------------------------------------ b
func bolt(ln: float) -> Dictionary:
	return rec_of("Hex bolt M4 x 16", [{"t": "prim", "kind": "cylinder", "op": "new", "x": 0, "y": 0, "z": 0, "axis": "y", "r": 2.0, "len": ln},
		{"t": "prim", "kind": "cylinder", "op": "join", "into": 0, "x": 0, "y": ln, "z": 0, "axis": "y", "r": 3.5, "len": 2.8}], {"buy": "bolt_m4x16", "material": "steel"})


func bars_group() -> void:
	var asm := Assembly.make("Bolts")
	for i in 4:
		Assembly.add_part(asm, bolt(16.0))
	var b := AssemblyBom.bom(asm)
	var ls: Array = b["lines"]
	var vol := float(Assembly.built(bolt(16.0))["volume"])
	var price := float(AssemblyBom.prices()["items"]["bolt_m4x16"]["price"])
	ok(ls.size() == 1 and int(ls[0]["count"]) == 4 and rel(float(ls[0]["line_mass_kg"]), 4.0 * vol * 7850.0) < 1e-9 and rel(float(ls[0]["line_cost"]), 4.0 * price) < 1e-12,
		"b four identical bolts: %d line, qty %s, mass %.6f kg (4 x %.4f cm3 x 7850), cost %.2f" % [ls.size(), str(ls[0].get("count", "?")) if not ls.is_empty() else "?", float(ls[0]["line_mass_kg"]) if not ls.is_empty() else 0.0, vol * 1e6, float(ls[0]["line_cost"]) if not ls.is_empty() else 0.0])
	var asm2 := Assembly.make("Bolts 2")
	for i in 3:
		Assembly.add_part(asm2, bolt(16.0))
	Assembly.add_part(asm2, bolt(17.0))
	var l2: Array = AssemblyBom.bom(asm2)["lines"]
	var counts: Array = l2.map(func(l): return int(l["count"]))
	counts.sort()
	ctl(l2.size() == 2 and counts == [1, 3], "b one bolt 1 mm longer: %d lines, counts %s" % [l2.size(), str(counts)])


# ------------------------------------------------------------------ c
func cat_new(ln: Dictionary) -> String:
	var it := String(ln["item"])
	var b: Dictionary = ln["bom"]
	if it.begins_with("syr"):
		return "syringes"
	if it.begins_with("tube_"):
		return "tubes"
	if String(b.get("role", "")) == "boom":
		return "boom"
	if it == "ply18_base_set" or b.has("included"):
		return "base"
	if it == "dowel_4x40":
		return "dowels"
	if it == "pad_pair":
		return "pads"
	if it == "sundries":
		return "sundries"
	if String(ln["material"]) == "pla":
		return "printed"
	return "other: " + String(ln["part"])


func cat_14(item: String) -> String:
	for p in [["Luer", "syringes"], ["Tube", "tubes"], ["Boom", "boom"], ["PLA+ printed", "printed"], ["Baseboard", "base"], ["Steel dowel", "dowels"], ["Jaw pads", "pads"], ["Screws", "sundries"]]:
		if item.begins_with(String(p[0])):
			return String(p[1])
	return "other: " + item


func ch14_vols() -> Dictionary:
	var vols := {}
	var recs := {"turntable": PT.turntable(), "pinion": PT.pinion(), "rack": PT.rack(), "gripper_body": PT.gripper_body(), "jaw": PT.jaw()}
	for k in recs:
		vols[k] = float(Assembly.built(recs[k])["volume"]) * 1e9
	vols["jaw_2"] = vols["jaw"]
	return vols


var ch14_asm := {}


func bars_ch14() -> void:
	var d := A14.design()
	var vols := ch14_vols()
	var b14 := BOM.bom(d, vols)
	var asm := BOM.assembly(d)
	ch14_asm = asm
	var nb := AssemblyBom.bom(asm)
	var s14 := {}
	var snew := {}
	for l in b14["lines"]:
		var c := cat_14(String(l["item"]))
		s14[c] = float(s14.get(c, 0.0)) + float(l["cost"])
	for l in nb["lines"]:
		var c := cat_new(l)
		snew[c] = float(snew.get(c, 0.0)) + float(l["line_cost"])
		print("     c BOM %-52s %8.3f %-4s %-10s %8.4f kg %7.2f USD  %s" % [l["part"], l["qty"], l["unit"], String(l["item"]) if String(l["item"]) != "" else String(l["material"]), l["line_mass_kg"], l["line_cost"], String(l["source"]).left(60)])
	print("     c BOM total %.4f USD, %.4f kg, %d parts + %d items; CH14 bom() %.4f USD" % [nb["cost"], nb["mass_kg"], nb["parts"], nb["items"], b14["total"]])
	var same := true
	var keys: Array = s14.keys()
	for k in snew:
		if not keys.has(k):
			keys.append(k)
	for k in keys:
		var a14 := float(s14.get(k, 0.0))
		var an := float(snew.get(k, 0.0))
		print("     c %-9s CH14 %8.4f   new %8.4f   diff %+.4f" % [k, a14, an, an - a14])
		if k != "boom":
			same = same and absf(an - a14) < 1e-9 and s14.has(k) and snew.has(k)
	var dboom := float(snew.get("boom", 0.0)) - float(s14.get("boom", 0.0))
	var cad_kg := 0.0
	for l in nb["lines"]:
		if cat_new(l) == "boom":
			cad_kg += float(l["line_mass_kg"])
	var sec_kg := A14.link_mass("pla", d["L1"]) + A14.link_mass("pla", d["L2"])
	print("     c boom: CH14 prices a 30 mm square PLA+ section x (%.0f + %.0f) mm = %.4f kg; the CAD links (25 mm tube + cheeks + lugs + trunnions) are %.4f kg: %+.4f kg x 22 = %+.4f USD" % [d["L1"], d["L2"], sec_kg, cad_kg, cad_kg - sec_kg, dboom])
	ok(same and absf((float(nb["cost"]) - float(b14["total"])) - dboom) < 1e-9 and snprintf2(b14["total"]) == "29.37", "c CH14 through the new BOM: every group but the boom equals CH14's line to 1e-9; total %.4f = CH14 %.4f (%s) %+.4f (the boom, CAD solid vs section)" % [nb["cost"], b14["total"], snprintf2(b14["total"]), dboom])
	var ch := AssemblyBom.cheaper(asm)
	var dz: Dictionary = ch["design"]
	var best14: Dictionary = BOM.cheapest(vols)["best"]
	var cp: Dictionary = asm.duplicate(true)
	AssemblyBom.apply_design(cp, dz["changes"])
	var chk := BOM.check_asm(cp)
	var bcp := AssemblyBom.bom(cp)
	var needs_ok := true
	var pr := AssemblyBom.prices()
	for l in bcp["lines"]:
		var need: Dictionary = (l["bom"] as Dictionary).get("need", {})
		var props: Dictionary = pr["items"].get(String(l["item"]), {}) if String(l["item"]) != "" else pr["materials"].get(String(l["material"]), {})
		for k in need:
			if k == "max_mass_kg":
				needs_ok = needs_ok and float(l["mass_kg"]) <= float(need[k])
			else:
				needs_ok = needs_ok and props.has(k) and float(props[k]) >= float(need[k])
	var chs: Array = []
	for k in dz["changes"]:
		chs.append("%s -> %s" % [AssemblyBom_part(asm, String(k)), dz["changes"][k]])
	print("     c cheaper line by line: save %.4f; the design: %s (%d combinations tried)" % [ch["saving_lines"], "; ".join(PackedStringArray(chs)), dz["tried"]])
	ok(bool(dz["ok"]) and float(dz["cost"]) <= float(best14.get("cost", -1.0)) + 1e-9 and bool(chk["ok"]) and needs_ok and absf(float(bcp["cost"]) - float(dz["cost"])) < 1e-9,
		"c cheaper view: %.4f USD (save %.4f) <= CH14's search %.4f (%s boom, %s tube, joints %s); CH14 bars on the applied copy: %s; needs met: %s; bom() of the copy %.4f" % [dz["cost"], dz["saving"], float(best14.get("cost", -1.0)), best14.get("mat", "?"), best14.get("hose", "?"), str(best14.get("big", [])), "pass" if chk["ok"] else "FAIL " + String(chk["why"]), str(needs_ok), bcp["cost"]])
	var pvc: Dictionary = asm.duplicate(true)
	var runs_ln := {}
	for l in nb["lines"]:
		if String(l["item"]).begins_with("tube_"):
			AssemblyBom.apply(pvc, String(l["key"]), "tube_pvc")
			if String((l["bom"] as Dictionary).get("role", "")) == "hose_runs":
				runs_ln = l
	var cpv := BOM.check_asm(pvc)
	var tpv := AssemblyBom.try_alt(runs_ln, "tube_pvc", pr) if not runs_ln.is_empty() else {"ok": true, "why": ""}
	ctl(not cpv["ok"] and not tpv["ok"], "c all tube soft PVC: CH14 bars '%s'; the runs line's need: '%s'" % [cpv["why"], tpv["why"]])


func snprintf2(x: float) -> String:
	return "%.2f" % x


func AssemblyBom_part(asm: Dictionary, key: String) -> String:
	for l in AssemblyBom.bom(asm)["lines"]:
		if String(l["key"]) == key:
			return String(l["part"])
	return key


# ------------------------------------------------------------------ d
## this file's own CSV reader (quotes, doubled quotes): rows of fields
func parse_csv(t: String) -> Array:
	var rows: Array = []
	var row: Array = []
	var cur := ""
	var q := false
	var i := 0
	while i < t.length():
		var c := t[i]
		if q:
			if c == "\"":
				if i + 1 < t.length() and t[i + 1] == "\"":
					cur += "\""
					i += 1
				else:
					q = false
			else:
				cur += c
		elif c == "\"":
			q = true
		elif c == ",":
			row.append(cur)
			cur = ""
		elif c == "\n":
			row.append(cur)
			rows.append(row)
			row = []
			cur = ""
		else:
			cur += c
		i += 1
	if cur != "" or not row.is_empty():
		row.append(cur)
		rows.append(row)
	return rows


func adds_up(t: String, nlines: int) -> Dictionary:
	var rows := parse_csv(t)
	var sc := 0.0
	var n := 0
	var tot: Array = []
	for r in rows.slice(1):
		if String(r[0]) == "TOTAL":
			tot = r
			continue
		n += 1
		sc += float(r[8])
	var tc := float(tot[8]) if tot.size() > 8 else -1.0
	return {"rows": n, "sum": sc, "total": tc, "ok": n == nlines and not tot.is_empty() and absf(sc - tc) <= (n + 1) * 0.5e-6 + 1e-12}


func bars_csv() -> void:
	var asm: Dictionary = ch14_asm
	var path := OUT + "/ch14_bom.csv"
	var w := AssemblyBom.write_csv(asm, path)
	var t := FileAccess.get_file_as_string(path)
	var b: Dictionary = w["bom"]
	var r := adds_up(t, (b["lines"] as Array).size())
	# the mass column is ONE part's mass (a bought tube: its metres' mass): the line's mass is count x that
	var rows := parse_csv(t)
	var msum := 0.0
	var mtot := -1.0
	var ncount := 0
	for row in rows.slice(1):
		if String(row[0]) == "TOTAL":
			mtot = float(row[6])
	var li := 0
	for row in rows.slice(1):
		if String(row[0]) == "TOTAL" or li >= (b["lines"] as Array).size():
			continue
		var cnt := int(b["lines"][li]["count"])
		msum += float(row[6]) * cnt
		ncount += cnt
		li += 1
	ok(bool(w["ok"]) and bool(r["ok"]) and absf(float(r["total"]) - float(b["cost"])) <= 0.5e-6 and absf(msum - mtot) <= (ncount + 1) * 0.5e-9 + 1e-15,
		"d CSV %s re-read: %d rows + TOTAL; rows add to %.6f, TOTAL %.6f, bom() %.6f USD; mass rows %.9f vs TOTAL %.9f kg" % [path.get_file(), int(r["rows"]), float(r["sum"]), float(r["total"]), float(b["cost"]), msum, mtot])
	var lines := t.split("\n")
	var f1 := parse_csv(lines[1] + "\n")[0] as Array
	f1[8] = "%.6f" % (float(f1[8]) + 0.01)
	var q := PackedStringArray()
	for s in f1:
		q.append(("\"" + String(s).replace("\"", "\"\"") + "\"") if String(s).contains(",") or String(s).contains("\"") else String(s))
	lines[1] = ",".join(q)
	var r2 := adds_up("\n".join(lines), (b["lines"] as Array).size())
	ctl(not r2["ok"], "d one line 0.01 USD dearer: rows %.6f vs TOTAL %.6f" % [float(r2["sum"]), float(r2["total"])])


# ------------------------------------------------------------------ e
func bars_sources() -> void:
	var p: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AssemblyBom.PRICES))
	var re := RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2}$")
	var n := 0
	var bad: Array = []
	var assumed := 0
	for sect in ["materials", "items"]:
		for k in p[sect]:
			var e: Dictionary = p[sect][k]
			n += 1
			if String(e.get("source", "")).strip_edges() == "" or re.search(String(e.get("date", ""))) == null:
				bad.append(k)
			if AssemblyBom.is_assumed(e):
				assumed += 1
	var v := AssemblyBom.validate(p)
	ok(n > 0 and bad.is_empty() and v.is_empty(), "e %d price entries, every one with a source and a date (%d ASSUMED, %d cited); validate: %s" % [n, assumed, n - assumed, "clean" if v.is_empty() else str(v)])
	var c: Dictionary = p.duplicate(true)
	c["materials"]["steel"]["source"] = ""
	(c["items"]["syr5"] as Dictionary).erase("date")
	var v2 := AssemblyBom.validate(c)
	ctl(v2.size() == 2 and String(v2[0]).contains("steel") and String(v2[1]).contains("syr5"), "e source erased + date missing: %s" % str(v2))


# ------------------------------------------------------------------ f
func ev_mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func ev_move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func key(code: int, uni := 0, ctrl := false) -> void:
	for dn in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.unicode = uni
		e.ctrl_pressed = ctrl
		e.pressed = dn
		root.push_input(e, true)
		await process_frame


func shot(nm: String) -> void:
	await idle(4)
	DirAccess.make_dir_recursive_absolute(OUT)
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, nm])


func nd(nm: String) -> Node:
	return root.find_child(nm, true, false)


func open_screen() -> void:
	var ss: StartScreen = m.start_screen
	ss.dirs_override = ["user://g8bom_test"]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	m.bld.part.set_on(false)
	m.S.part = {}
	await idle(6)
	A = m.bld.asm
	m.build_choose.show_chooser()
	await idle(4)
	await click_ctl(nd("build_choose_assembly") as Button)
	await idle(4)


func costs_on_screen() -> Array:
	return A.bom.rows.map(func(l): return float(l["line_cost"]))


func names_on_screen() -> Array:
	return A.bom.rows.map(func(l): return String(l["part"]).to_lower())


func is_sorted(xs: Array, up: bool) -> bool:
	for i in range(1, xs.size()):
		if (up and xs[i] < xs[i - 1]) or (not up and xs[i] > xs[i - 1]):
			return false
	return true


func bars_ui() -> void:
	await open_screen()
	A.open_record(BOM.assembly())
	await idle(6)
	var before := JSON.stringify(A.asm, "", true)
	await click_ctl(nd("asm_bom") as Button)
	await idle(4)
	var b := AssemblyBom.bom(A.asm)
	var nrow := 0
	while nd("asm_bom_part_%d" % nrow) != null:
		nrow += 1
	var tl := (nd("asm_bom_totals") as Label).text
	ok(A.bom.is_open() and nrow == (b["lines"] as Array).size() and tl.contains("%.2f" % float(b["cost"])), "f BOM opens: %d rows for %d lines; '%s'" % [nrow, (b["lines"] as Array).size(), tl])
	await shot("bom_open")
	await click_ctl(nd("asm_bom_sort_cost") as Button)
	var up := is_sorted(costs_on_screen(), true) and A.bom.sort_asc
	await click_ctl(nd("asm_bom_sort_cost") as Button)
	var down := is_sorted(costs_on_screen(), false) and not A.bom.sort_asc
	await click_ctl(nd("asm_bom_sort_part") as Button)
	var byname := is_sorted(names_on_screen(), true)
	ok(up and down and byname, "f Cost sorts up %s, again down %s; Part by name %s (first row now '%s')" % [str(up), str(down), str(byname), String(A.bom.rows[0]["part"]) if not A.bom.rows.is_empty() else ""])
	var idx := -1
	for i in A.bom.rows.size():
		if String(A.bom.rows[i]["part"]).begins_with("Upper arm"):
			idx = i
	var btn := nd("asm_bom_cheaper_%d" % idx) as Button if idx >= 0 else null
	var cost0 := float(b["cost"])
	var key0 := String(A.bom.rows[idx]["key"]) if idx >= 0 else ""
	var row: Dictionary = {}
	for r in A.bom.cheap["lines"]:
		if String(r["key"]) == key0:
			row = r
	var want := String(row.get("best", {}).get("key", ""))
	var sv := float(row.get("saving", 0.0))
	var had_btn := btn != null   # the click rebuilds the table: the button is freed after it
	if btn != null:
		(nd("asm_bom_scroll") as ScrollContainer).ensure_control_visible(btn)   # the user scrolls the table to the line
		await idle(3)
		await click_ctl(btn)
	await idle(3)
	var mat_now := ""
	for p in A.asm["parts"]:
		if String(p["rec"]["name"]).begins_with("Upper arm"):
			mat_now = String(p["rec"]["bom"]["material"])
	var cost1 := float(AssemblyBom.bom(A.asm)["cost"])
	ok(had_btn and want != "" and mat_now == want and A.asm_undo.size() == 1 and absf((cost0 - cost1) - sv) < 1e-9 and sv > 0.0, "f the upper arm's Cheaper button: material %s (the view's pick %s, cheapest meeting its need), 1 undo step (%d), total %.4f -> %.4f (saving shown %.4f, off by %s)" % [mat_now, want, A.asm_undo.size(), cost0, cost1, sv, sci((cost0 - cost1) - sv)])
	var after := JSON.stringify(A.asm, "", true)
	ctl(after != before, "f after the change the record differs from before")
	await shot("bom_cheaper")
	await click_ctl(nd("asm_bom_copy") as Button)
	var clip := DisplayServer.clipboard_get().replace("\r\n", "\n")   # the Windows clipboard hands text back with CRLF line ends
	ok(clip == AssemblyBom.csv(AssemblyBom.bom(A.asm)) and clip.begins_with("part,item,qty"), "f Copy: the clipboard holds bom()'s CSV (%d chars)" % clip.length())
	m.get_viewport().gui_release_focus()
	await key(KEY_Z, 0, true)
	await idle(3)
	var undone := JSON.stringify(A.asm, "", true)
	var tl2 := (nd("asm_bom_totals") as Label).text
	ok(undone == before and tl2.contains("%.2f" % cost0), "f Ctrl+Z: the record is identical to before (%s); the table shows %.2f again: '%s'" % [str(undone == before), cost0, tl2.left(80)])
	await click_ctl(nd("asm_bom_close") as Button)


# ------------------------------------------------------------------ g
func sorted_json(path: String) -> String:
	var j = JSON.parse_string(FileAccess.get_file_as_string(path))
	return JSON.stringify(j, "", true) if j != null else ""


func through_screen(path: String) -> String:
	var rec := Assembly.read(path)
	if rec.is_empty():
		return ""
	A.open_record(rec)
	await idle(4)
	A.bom.open()
	await idle(3)
	A.bom.sort_by("mass")
	A.bom.sort_by("part")
	await idle(2)
	A.bom.close()
	await idle(2)
	return Assembly.save(A.asm)


func bars_old() -> void:
	var keep := Assembly.dir
	Assembly.dir = "user://g8bom_old"
	var rows: Array = []
	var all_ok := true
	for p in OLD:
		var saved: String = await through_screen(p)
		var eq := saved != "" and sorted_json(saved) == sorted_json(p)
		all_ok = all_ok and eq
		var bb := AssemblyBom.bom(Assembly.read(p))
		rows.append("%s %s (%d lines, %d not priced)" % [String(p).get_file(), "equal" if eq else "DIFFERENT", (bb["lines"] as Array).size(), int(bb["unpriced"])])
	ok(all_ok, "g old records through the screen (BOM opened, sorted, closed) save back: %s" % ", ".join(PackedStringArray(rows)))
	var j := Assembly.read(OLD[3])
	var k0 := String(AssemblyBom.bom(j)["lines"][0]["key"])
	AssemblyBom.apply(j, k0, "pla")
	var pk := Assembly.save(j)
	ctl(sorted_json(pk) != sorted_json(OLD[3]), "g the #205 record with one material applied does not compare equal")
	Assembly.dir = keep


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	if not Part.available():
		ok(false, "the CAD DLL is missing")
		print("g8bom: %d fail" % fails)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUT)
	bars_mass()
	bars_group()
	bars_ch14()
	bars_csv()
	bars_sources()
	await bars_ui()
	await bars_old()
	print("g8bom: %d fail" % fails)
	quit(1 if fails > 0 else 0)
