extends SceneTree
## godot --headless --path . -s tests/ch15_test.gd   (CH15: an Angra 2 class PWR plant, its blueprints, its one-line diagram and its construction section video; docs/CH15_BRIEF.md, docs/CH15_REFERENCE.md)
## Bars (written and committed before any number was run; each has a PLANTED control that must fail):
##  1 PRIMARY   Q = m cp dT over the vessel (m = 4 x 4700 kg/s, dT = 326.1 - 291.3 K, cp = IF97 region 1 at 308.6 C and 15.5 MPa) is within 3 pct of 3771 MWt.
##              PLANTED: the flow of ONE loop misses.
##  2 CYCLE     2a IF97 regions 1, 2, 4 reproduce the verification tables 5, 15, 35, 36 of IAPWS R7-97(2012) (30 numbers, relative 1e-6).
##              2b the ideal Rankine cycle between the SG outlet (6.2959 MPa, x 0.9975) and the condenser (p_sat of 27 C seawater + its rise + 3 K TTD) has a gross
##              efficiency within 35.80 +- 3 points and below Carnot between the same temperatures. PLANTED: steam as an ideal gas misses the band (or beats Carnot).
##  3 ELECTRIC  S = P / pf; I = S / (sqrt3 V) at 25 kV by hand; main transformer >= the generator's S (computed and nameplate); unit auxiliary transformers and the
##              standby transformer each >= the house load (gross - net at pf 0.85); (diesels - 2) x 5.4 MW >= the safety load (4 x 50 pct, N+2).
##              PLANTED: three diesels fail the N+2 check.
##  4 DECAY     Way-Wigner at 10 s, 1 h, 1 day after 13 months at power equal their hand values; the 1 h fraction lies in 0.5..2 pct; the emergency feedwater that boils
##              off the 1 h decay heat (30 C water to saturated steam at 6.2959 MPa) is <= the 36 kg/s cited. PLANTED: operating time 0 s leaves the band.
##  5 SPHERE    sigma = p R / (2 t) at 0.53 MPa, D 56 m: Angra 2 (WStE 51, 30 mm) <= 0.67 Rp(145 C) and the Angra 3 cross-check (WStE 370, 38 mm) <= the cited 214 MPa.
##              PLANTED: the cylinder formula p R / t at 38 mm is flagged (twice the sphere value and over the allowable).
##  6 LAYOUT    every Part record of the plant builds; every building's footprint and height (its built box) is within 5 pct of the reference table, and no two buildings
##              share volume (KCad.overlap_volume of the posed exact solids, CH13 bar j style); the primary equipment (vessel, SGs, pumps, pressurizer) do not overlap
##              each other or the internal concrete. PLANTED: the turbine hall moved into the reactor building is caught.
##  7 BUILD     each construction stage only adds parts that rest on parts already built (bottom face on a built top face, footprints overlapping) or hang between
##              built parts; (windowed) the video frames come in stage order, each frame differs from the one before, the stage's own colour appears in its frame,
##              and the section frame shows the primary circuit (red) that the closed building hides. PLANTED: the dome placed before the walls fails the support check.
##  8 HAND      every number of bars 1-5 equals its hand value to 1e-9. PLANTED: Way-Wigner with exponent -0.25 differs.
##  9 DRAWINGS  (extra) the site plan, the reactor building section and the one-line diagram write as SVG with a title block and a scale; every bus of the one-line has
##              its voltage and every transformer its MVA on the sheet. PLANTED: a one-line with a transformer stripped of its MVA is caught.
var fails := 0
const W := preload("res://scripts/build/ch15_if97.gd")
const P := preload("res://scripts/build/ch15_plant.gd")
const S := preload("res://scripts/build/ch15_site.gd")
const D := preload("res://scripts/build/ch15_draw.gd")
const SC := preload("res://scripts/build/ch15_scene.gd")
const KCad := preload("res://scripts/kcad.gd")
const TMP := "C:/Temp/claude/ch15"


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func rel(a: float, b: float) -> float:
	return absf(a - b) / maxf(absf(b), 1e-300)


func out_dir() -> String:
	return ProjectSettings.globalize_path("res://docs/ch15") if OS.get_environment("CH15_PUBLISH") == "1" else TMP


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(TMP)
	DirAccess.make_dir_recursive_absolute(out_dir())
	bar1()
	bar2()
	bar3()
	bar4()
	bar5()
	bar8()
	bar9()
	if not Part.available():
		ok(false, "6/7 the CAD kernel (KineCAD) is missing")
	else:
		bar6()
		bar7()
		await bar7_video()
	print("ch15: %d fail" % fails)
	quit(1 if fails > 0 else 0)


# ------------------------------------------------ 1
func bar1() -> void:
	var pr := P.primary()
	print("     primary: m %.1f kg/s, cp %.6f kJ/kg K at %.2f C %.1f MPa, dT %.2f K -> Q %.2f MWt (ref %.0f, %.2f pct); enthalpy route %.2f MWt" % [pr["m"], pr["cp"], P.T_MEAN, P.P_PRIM, pr["dT"], pr["Q"], P.Q_TH, 100.0 * pr["err"], pr["Q_h"]])
	ok(float(pr["err"]) <= 0.03, "1 Q = m cp dT = %.1f MWt within 3 pct of %.0f MWt (%.2f pct)" % [pr["Q"], P.Q_TH, 100.0 * pr["err"]])
	var one := P.primary({"loops": 1})
	ok(float(one["err"]) > 0.03, "1 PLANTED one loop's flow gives %.1f MWt, %.1f pct off (caught)" % [one["Q"], 100.0 * one["err"]])


# ------------------------------------------------ 2
const T5 := [[3.0, 300.0, 0.100215168e-2, 0.115331273e3, 0.392294792, 0.417301218e1], [80.0, 300.0, 0.971180894e-3, 0.184142828e3, 0.368563852, 0.401008987e1],
	[3.0, 500.0, 0.120241800e-2, 0.975542239e3, 0.258041912e1, 0.465580682e1]]
const T15 := [[0.0035, 300.0, 0.394913866e2, 0.254991145e4, 0.852238967e1, 0.191300162e1], [0.0035, 700.0, 0.923015898e2, 0.333568375e4, 0.101749996e2, 0.208141274e1],
	[30.0, 700.0, 0.542946619e-2, 0.263149474e4, 0.517540298e1, 0.103505092e2]]
const T35 := [[300.0, 0.353658941e-2], [500.0, 0.263889776e1], [600.0, 0.123443146e2]]
const T36 := [[0.1, 0.372755919e3], [1.0, 0.453035632e3], [10.0, 0.584149488e3]]


func bar2() -> void:
	var worst := 0.0
	var n := 0
	for row in T5 + T15:
		var st: Dictionary = W.r1(row[0], row[1]) if T5.has(row) else W.r2(row[0], row[1])
		for k in 4:
			worst = maxf(worst, rel(float(st[["v", "h", "s", "cp"][k]]), float(row[2 + k])))
			n += 1
	for row in T35:
		worst = maxf(worst, rel(W.psat(row[0]), row[1]))
		n += 1
	for row in T36:
		worst = maxf(worst, rel(W.tsat(row[0]), row[1]))
		n += 1
	ok(worst < 1e-6 and n == 30, "2a IF97 regions 1, 2, 4 against the R7-97 verification tables: %d numbers, worst relative %s" % [n, str(worst)])
	var rk := P.rankine()
	var cd := P.condenser()
	print("     condenser: seawater rise %.3f K, condensing %.3f C, p_c %.6f MPa; cycle h1 %.3f h2 %.3f h3 %.3f h4 %.3f kJ/kg, x4 %.4f" % [cd["dT_sw"], cd["Tc"], cd["pc"], rk["h1"], rk["h2"], rk["h3"], rk["h4"], rk["x4"]])
	var target := P.P_GROSS / P.Q_TH
	ok(absf(float(rk["eta"]) - target) <= 0.03, "2b ideal Rankine gross efficiency %.2f pct within 35.80 +- 3 points (gross / thermal %.2f pct)" % [100.0 * rk["eta"], 100.0 * target])
	ok(float(rk["eta"]) < float(rk["carnot"]), "2b below Carnot %.2f pct between %.2f K and %.2f K" % [100.0 * rk["carnot"], rk["Th"], rk["Tc"]])
	var ig := P.rankine("ideal_gas")
	ok(absf(float(ig["eta"]) - target) > 0.03 or float(ig["eta"]) >= float(ig["carnot"]), "2b PLANTED ideal-gas steam gives %.1f pct (Carnot %.1f): caught" % [100.0 * ig["eta"], 100.0 * ig["carnot"]])


# ------------------------------------------------ 3
func bar3() -> void:
	var e := P.electrical()
	print("     generator S %.1f MVA (nameplate %.0f), I %.1f A (nameplate %.1f A); main transformer %.0f MVA; house %.1f MW = %.2f MVA; UAT %.0f, standby %.0f MVA; diesels %d x %.1f MW, %d needed of redundancy, %.1f MW >= %.1f MW" % [e["S_gen"], e["S_name"], e["I"], e["I_name"], e["S_mt"], e["house_MW"], e["house_MVA"], e["S_uat"], e["S_sst"], e["n_dg"], e["dg_MW"], e["redund"], e["dg_avail"], e["P_safe"]])
	ok(rel(e["S_gen"], P.P_GROSS / P.PF) < 1e-12, "3 generator S = P / pf = %.3f MVA" % e["S_gen"])
	ok(rel(e["I"], e["S_gen"] * 1e6 / (sqrt(3.0) * P.V_GEN * 1e3)) < 1e-12, "3 terminal current I = S / (sqrt3 V) = %.3f A at %.0f kV" % [e["I"], P.V_GEN])
	ok(float(e["S_mt"]) >= maxf(e["S_gen"], e["S_name"]), "3 main step-up transformer %.0f MVA >= generator %.0f MVA (computed) and %.0f MVA (nameplate)" % [e["S_mt"], e["S_gen"], e["S_name"]])
	ok(float(e["S_uat"]) >= float(e["house_MVA"]) and float(e["S_sst"]) >= float(e["house_MVA"]), "3 unit auxiliary %.0f MVA and standby %.0f MVA each >= house load %.2f MVA" % [e["S_uat"], e["S_sst"], e["house_MVA"]])
	ok(bool(e["dg_ok"]), "3 diesels N+2: (%d - %d) x %.1f MW = %.1f MW >= %.1f MW safety load" % [e["n_dg"], e["redund"], e["dg_MW"], e["dg_avail"], e["P_safe"]])
	var e3 := P.electrical({"diesels": 3})
	ok(not bool(e3["dg_ok"]), "3 PLANTED three diesels: %.1f MW < %.1f MW (caught)" % [e3["dg_avail"], e3["P_safe"]])


# ------------------------------------------------ 4
func bar4() -> void:
	var f1h := P.decay(3600.0, P.T_OP)
	print("     decay: 10 s %.6f, 1 h %.6f, 1 day %.6f of %.0f MWt" % [P.decay(10.0, P.T_OP), f1h, P.decay(86400.0, P.T_OP), P.Q_TH])
	ok(f1h >= 0.005 and f1h <= 0.02, "4 decay fraction at 1 h %.4f pct inside 0.5..2 pct" % (100.0 * f1h))
	var bo := P.boiloff(3600.0, P.T_OP)
	ok(float(bo["m"]) <= float(bo["cap"]), "4 boil-off at 1 h: %.2f MW / %.2f kJ/kg = %.2f kg/s <= %.0f kg/s emergency feedwater" % [bo["P_MW"], bo["dh"], bo["m"], bo["cap"]])
	var f0 := P.decay(3600.0, 0.0)
	ok(not (f0 >= 0.005 and f0 <= 0.02), "4 PLANTED operating time 0 s gives %.6f at 1 h: outside the band (caught)" % f0)


# ------------------------------------------------ 5
func bar5() -> void:
	var a2 := P.containment("angra2")
	var a3 := P.containment("angra3")
	ok(float(a2["sigma"]) <= float(a2["allow"]), "5 Angra 2 sphere %.0f mm WStE 51: sigma %.2f MPa <= %.2f MPa" % [a2["t"], a2["sigma"], a2["allow"]])
	ok(float(a3["sigma"]) <= float(a3["allow"]), "5 Angra 3 cross-check 38 mm WStE 370: sigma %.2f MPa <= %.0f MPa (cited)" % [a3["sigma"], a3["allow"]])
	var cy := P.containment("angra3", "cylinder")
	ok(rel(cy["sigma"], a3["sigma"]) > 0.5 and float(cy["sigma"]) > float(cy["allow"]), "5 PLANTED cylinder formula p R / t = %.2f MPa: %.1f x the sphere and over %.0f (flagged)" % [cy["sigma"], cy["sigma"] / a3["sigma"], cy["allow"]])


# ------------------------------------------------ 8
func bar8() -> void:
	var pr := P.primary()
	var cp: float = W.r1(15.5, 308.6 + 273.15)["cp"]
	ok(rel(pr["Q"], 18800.0 * cp * (326.1 - 291.3) / 1000.0) < 1e-9, "8 Q = 18800 x %.9f x 34.8 / 1000 by hand" % cp)
	# the cycle by hand: the saturated states again, straight from the IF97 functions
	var pc: float = W.psat(P.SW_T + 273.15 + (P.Q_TH - P.P_GROSS) / (74.4 * 1023.0 * 3.99e-3) + 3.0)
	var tc := W.tsat(pc)
	var th := W.tsat(64.2 * 0.0980665)
	var f: Dictionary = W.r1(pc, tc)
	var g: Dictionary = W.r2(pc, tc)
	var fh: Dictionary = W.r1(64.2 * 0.0980665, th)
	var gh: Dictionary = W.r2(64.2 * 0.0980665, th)
	var h3 := float(fh["h"]) + 0.9975 * (float(gh["h"]) - float(fh["h"]))
	var s3 := float(fh["s"]) + 0.9975 * (float(gh["s"]) - float(fh["s"]))
	var x4 := (s3 - float(f["s"])) / (float(g["s"]) - float(f["s"]))
	var h4 := float(f["h"]) + x4 * (float(g["h"]) - float(f["h"]))
	var h2 := float(f["h"]) + float(f["v"]) * (64.2 * 0.0980665 - pc) * 1000.0
	var eta := (h3 - h4 - (h2 - float(f["h"]))) / (h3 - h2)
	var rk := P.rankine()
	ok(rel(rk["eta"], eta) < 1e-9 and rel(rk["carnot"], 1.0 - tc / th) < 1e-9, "8 Rankine eta %.9f and Carnot %.9f by hand" % [eta, 1.0 - tc / th])
	ok(rel(P.condenser()["dT_sw"], 7.972110770730629) < 1e-9, "8 seawater rise 2421 / (74.4 x 1023 x 3.99e-3) = 7.972110771 K")
	var e := P.electrical()
	ok(rel(e["S_gen"], 1500.0) < 1e-9 and rel(e["I"], 34641.01615137755) < 1e-9 and rel(e["I_name"], 33671.06769913898) < 1e-9, "8 S 1500 MVA, I 34641.016151 A, nameplate I 33671.067699 A")
	ok(rel(e["house_MVA"], 82.3529411764706) < 1e-9 and rel(e["dg_avail"], 10.8) < 1e-9, "8 house 70 / 0.85 = 82.352941 MVA, diesels 2 x 5.4 = 10.8 MW")
	ok(rel(P.decay(10.0, P.T_OP), 0.03730908022669287) < 1e-9 and rel(P.decay(3600.0, P.T_OP), 0.010156457996154555) < 1e-9 and rel(P.decay(86400.0, P.T_OP), 0.00446904599527785) < 1e-9, "8 Way-Wigner 0.037309080, 0.010156458, 0.004469046")
	var bo := P.boiloff(3600.0, P.T_OP)
	var dh := float(W.r2(64.2 * 0.0980665, th)["h"]) - float(W.r1(64.2 * 0.0980665, 303.15)["h"])
	ok(rel(bo["m"], 0.010156457996154555 * 3771.0 * 1000.0 / dh) < 1e-9, "8 boil-off %.9f kg/s by hand" % (0.010156457996154555 * 3771.0 * 1000.0 / dh))
	var wrong := 0.0622 * (pow(3600.0, -0.25) - pow(3600.0 + P.T_OP, -0.25))
	ok(rel(wrong, 0.010156457996154555) > 1e-3, "8 PLANTED exponent -0.25 gives %.6f (%.0f pct off): caught" % [wrong, 100.0 * rel(wrong, 0.010156457996154555)])
	ok(rel(P.containment("angra2")["sigma"], 247.33333333333334) < 1e-9 and rel(P.containment("angra3")["sigma"], 195.26315789473685) < 1e-9 and rel(P.containment("angra3", "cylinder")["sigma"], 390.5263157894737) < 1e-9, "8 sphere 247.333333 / 195.263158 MPa, cylinder 390.526316 MPa")
	ok(rel(P.containment("angra2")["allow"], 289.72972972972974) < 1e-9, "8 allowable 0.67 x 500 x 320/370 = 289.729730 MPa")


# ------------------------------------------------ 6
func bar6() -> void:
	var asm := S.assembly()
	var bad := []
	for p in asm["parts"]:
		var b := Assembly.built(p["rec"])
		if int(b["bodies"]) < 1 or float(b["volume"]) <= 0.0:
			bad.append(p["name"])
	ok(bad.is_empty() and (asm["parts"] as Array).size() >= 30, "6 all %d part records of the plant build %s" % [(asm["parts"] as Array).size(), "" if bad.is_empty() else str(bad)])
	var worst := 0.0
	var worst_nm := ""
	for p in S.buildings(asm):
		var fp := S.footprint(p)
		var rf: Dictionary = p["ref"]
		for k in ["w", "d", "h"]:
			var e := rel(fp[k], rf[k])
			if e > worst:
				worst = e
				worst_nm = "%s %s %.2f vs %.2f m" % [p["name"], k, fp[k], rf[k]]
		print("     %-34s %7.2f x %7.2f x %6.2f m (ref %6.1f x %6.1f x %5.1f, %s)" % [p["name"], fp["w"], fp["d"], fp["h"], rf["w"], rf["d"], rf["h"], rf["src"]])
	ok(worst <= 0.05, "6 every building within 5 pct of its reference (worst %.2f pct: %s)" % [100.0 * worst, worst_nm])
	var cl := S.clashes(S.buildings(asm))
	ok(cl["pairs"] > 0 and (cl["hits"] as Array).is_empty(), "6 no two of the buildings share volume (%d pairs checked) %s" % [cl["pairs"], str(cl["hits"])])
	var ce := S.clashes(S.equipment(asm))
	ok(ce["pairs"] > 0 and (ce["hits"] as Array).is_empty(), "6 primary equipment and internal concrete: no overlaps (%d pairs) %s" % [ce["pairs"], str(ce["hits"])])
	var moved := S.assembly({"th_into_rb": true})
	var cm := S.clashes(S.buildings(moved))
	ok(not (cm["hits"] as Array).is_empty(), "6 PLANTED the turbine hall moved into the reactor building is caught %s" % str(cm["hits"]))


# ------------------------------------------------ 7
func bar7() -> void:
	var asm := S.assembly()
	var st := S.stages()
	var sup := S.support_check(asm, st)
	print("     stages: " + " | ".join(st.map(func(s): return "%s (%d)" % [s["name"], (s["parts"] as Array).size()])))
	ok(bool(sup["ok"]) and int(sup["placed"]) == (asm["parts"] as Array).size(), "7 every stage adds parts resting on built parts: %d of %d placed %s" % [sup["placed"], (asm["parts"] as Array).size(), str(sup["bad"])])
	var bad := S.support_check(asm, S.stages({"dome_first": true}))
	ok(not bool(bad["ok"]), "7 PLANTED the dome before the walls fails: %s" % str(bad["bad"]))


func grab() -> Image:
	for i in 4:
		await process_frame
	var im: Image = root.get_texture().get_image()
	im.convert(Image.FORMAT_RGBA8)
	return im


func diff(a: Image, b: Image) -> float:
	var s := 0.0
	var n := 0
	for y in range(0, a.get_height(), 4):
		for x in range(0, a.get_width(), 4):
			var c := a.get_pixel(x, y)
			var e := b.get_pixel(x, y)
			s += absf(c.r - e.r) + absf(c.g - e.g) + absf(c.b - e.b)
			n += 3
	return s / maxf(n, 1)


func count_col(img: Image, want: Color, tol: float) -> int:
	var n := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			if absf(c.r - want.r) < tol and absf(c.g - want.g) < tol and absf(c.b - want.b) < tol:
				n += 1
	return n


func red_px(img: Image) -> int:
	var n := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			if c.r > 0.55 and c.g < 0.3 and c.b < 0.25:
				n += 1
	return n


func bar7_video() -> void:
	if DisplayServer.get_name() == "headless":
		print("skip 7 video and pictures (headless: no pixels)")
		return
	var od := out_dir()
	# the video itself is the SECTION video (the reactor building and the turbine hall cut on their middle planes, the brief's deliverable 4)
	var sc: Dictionary = SC.build(root, S.assembly(), true)
	var st := S.stages()
	var frames := []
	var labels := []
	var in_order := true
	var own_ok := true
	var own_txt := []
	for k in st.size():
		SC.show_stage(sc, k)
		var im: Image = await grab()
		frames.append(im)
		labels.append("%d %s" % [k + 1, st[k]["name"]])
		im.save_png("%s/frame_%02d.png" % [TMP, k])
		in_order = in_order and SC.shown_stage(sc) == k
		var c: Color = SC.stage_color(k)
		var nc := count_col(im, c, 0.06)
		var np := 0 if k == 0 else count_col(frames[k - 1], c, 0.06)
		own_txt.append("%d:%d>%d" % [k + 1, nc, np])
		own_ok = own_ok and nc > np
	var moves := true
	var low := 1e9
	for k in range(1, frames.size()):
		var dd := diff(frames[k - 1], frames[k])
		low = minf(low, dd)
		moves = moves and dd > 0.0005
	ok(in_order and frames.size() == st.size(), "7 video: %d stage frames in order" % frames.size())
	ok(moves, "7 video: each frame differs from the one before (smallest mean diff %.4f)" % low)
	ok(own_ok, "7 video: each stage's own colour grows in its frame (%s)" % ", ".join(own_txt))
	var w: int = (frames[0] as Image).get_width() / 4
	var h: int = (frames[0] as Image).get_height() / 4
	var rows := int(ceil(frames.size() / 4.0))
	var sheet := Image.create(4 * w, rows * h, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.WHITE)
	for k in frames.size():
		var im2: Image = (frames[k] as Image).duplicate()
		im2.resize(w, h, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(im2, Rect2i(0, 0, w, h), Vector2i((k % 4) * w, (k / 4) * h))
	sheet.save_png(od + "/ch15_build_sheet.png")
	print("     frames: " + " | ".join(labels))
	SC.camera_section(sc)
	var simg: Image = await grab()
	simg.save_png(od + "/ch15_section.png")
	var sr := red_px(simg)
	(sc["root"] as Node).queue_free()
	await process_frame
	var cs: Dictionary = SC.build(root, S.assembly(), false)
	SC.show_stage(cs, st.size() - 1)
	SC.camera_section(cs)
	var cimg: Image = await grab()
	cimg.save_png(TMP + "/closed.png")
	var closed_red := red_px(cimg)
	ok(sr > 400 and closed_red < sr / 20, "7 the section frame shows the primary circuit: %d red px, the same view of the closed building %d" % [sr, closed_red])
	(cs["root"] as Node).queue_free()
	await process_frame
	# the three sheets as PNG, to look at
	for nm in ["site", "section", "oneline"]:
		var sh: Dictionary = D.sheet(nm)
		var png: Image = await D.render_png(root, sh, 4.0)
		png.save_png("%s/ch15_%s.png" % [od, nm])
	print("     pictures in %s" % od)


# ------------------------------------------------ 9
func bar9() -> void:
	var od := out_dir()
	var all_ok := true
	for nm in ["site", "section", "oneline"]:
		var sh: Dictionary = D.sheet(nm)
		var svg := Blueprint.to_svg(sh)
		var path := "%s/ch15_%s.svg" % [od, nm]
		var fa := FileAccess.open(path, FileAccess.WRITE)
		fa.store_string(svg)
		fa.close()
		var good := svg.contains("SCALE") and svg.contains("data-scale=") and FileAccess.file_exists(path) and svg.length() > 2000
		all_ok = all_ok and good
		print("     %s: %d entities, scale %s, %s" % [path, (sh["ents"] as Array).size(), "1:%d" % int(sh["denom"]) if int(sh["denom"]) > 0 else "NTS", "ok" if good else "BAD"])
	ok(all_ok, "9 site plan, reactor building section and one-line written as SVG with a title block and a scale")
	var site := D.sheet("site")
	var dims := 0
	for e in site["ents"]:
		if String(e["cls"]) == "dim-text":
			dims += 1
	ok(dims >= 8, "9 the site plan carries %d dimensions" % dims)
	var ol := P.one_line()
	var miss := D.oneline_missing(ol, D.sheet("oneline"))
	ok(miss.is_empty() and (ol["buses"] as Array).size() >= 10 and (ol["xfmrs"] as Array).size() >= 4, "9 one-line: %d buses with their kV and %d transformers with their MVA on the sheet %s" % [(ol["buses"] as Array).size(), (ol["xfmrs"] as Array).size(), str(miss)])
	var stripped := P.one_line()
	(stripped["xfmrs"] as Array)[0]["mva"] = 0.0
	var miss2 := D.oneline_missing(P.one_line(), D.sheet("oneline", {"model": stripped}))
	ok(not miss2.is_empty(), "9 PLANTED a transformer without its MVA is caught: %s" % str(miss2))
