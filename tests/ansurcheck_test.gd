extends SceneTree
## godot --headless --path . -s tests/ansurcheck_test.gd     (lane L138: ANSUR II constants checked against the real data)
## Several lanes typed ANSUR II numbers from memory. The data is public (ANSUR_II_MALE_Public.csv / ANSUR_II_FEMALE_Public.csv,
## https://www.openlab.psu.edu/ansur2/ ; Gordon et al. 2014, NATICK/TR-15/007; 4082 men, 1986 women). tools/ansur_stats.py
## computed the summary statistics (mean, SD, 1/5/50/95/99th percentile of every dimension, plus a few derived numbers) into
## data/ansur2_summary.json -- summary statistics only, not the raw dataset.
## BARS (written and committed before the code fixes; none is moved after a run):
##   1 TABLE     the summary file holds 4082 men and 1986 women and the known anchors (stature mean men 1756.2 mm, women 1628.5).
##   2 REGISTRY  registry() lists every ANSUR constant in scripts/ as [label, file:line, code value, sex, data path, scale]. Each
##               code value matches the data within 0.5 % (relative). A mismatch prints code value, data value and error.
##   3 PLANTED   a row with the old memory value of the flexed biceps (0.339 m against the data's 0.358) must be refused by the
##               same check; a value 0.4 % off must pass and 0.6 % off must be refused (the 0.5 % edge).
## Numbers outside the registry on purpose: Drillis / de Leva / Croskey segment ratios (other sources), GIRTH_E spine_02 (an
## interpolation between waist and chest), SPACING in crowd.gd and SPREAD_DEFAULT in say_it.gd (design values; their
## comments quote ANSUR breadths and are checked by hand in the lane report).
const TOL := 0.005
const SUMMARY := "res://data/ansur2_summary.json"
var fails := 0
var T: Dictionary = {}


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## one number out of the table. path "dims/stature/mean", "derived/bmi_mean", "derived/elasticity/waistcircumference";
## "a / b" divides two paths; sex "both" is the mean of the two sexes.
func data(sex: String, path: String) -> float:
	if path.contains(" / "):
		var p := path.split(" / ")
		return data(sex, p[0]) / data(sex, p[1])
	if sex == "both":
		return 0.5 * (data("male", path) + data("female", path))
	var cur: Variant = T[sex]
	for k in path.split("/"):
		cur = (cur as Dictionary)[k]
	return float(cur)


## true when code matches want within TOL (relative)
func close(code: float, want: float) -> bool:
	return absf(code - want) <= TOL * absf(want)


func registry() -> Array:
	var R: Array = []
	var BM = load("res://scripts/body_model.gd")
	var PR = load("res://scripts/proportions.gd")
	var BS = load("res://scripts/body_sliders.gd")
	var BN = load("res://scripts/body_from_numbers.gd")
	var CR = load("res://scripts/crowd.gd")
	var HS = load("res://scripts/hand_shape.gd")
	for sx in ["male", "female"]:
		var a: Dictionary = BM.ANSUR[sx]
		R.append(["stature mean mm", "body_model.gd:31", float(a["stat"][0]), sx, "dims/stature/mean", 1.0])
		R.append(["stature SD mm", "body_model.gd:31", float(a["stat"][1]), sx, "dims/stature/sd", 1.0])
		R.append(["mass median kg", "body_model.gd:31", float(a["mass"][0]), sx, "derived/mass_kg_p50", 1.0])
		R.append(["mass log-sigma", "body_model.gd:31", float(a["mass"][1]), sx, "derived/ln_mass_sd", 1.0])
		R.append(["MASS_STATURE_B", "proportions.gd:125", float(PR.MASS_STATURE_B[sx]), sx, "derived/b_lnmass_on_lnstat", 1.0])
		R.append(["CERV_FRAC median cervicale / stature", "proportions.gd:334", float(PR.CERV_FRAC[sx]), sx, "dims/cervicaleheight/p50 / dims/stature/p50", 1.0])
		R.append(["BREADTH shoulder / stature", "body_from_numbers.gd:23", float(BN.BREADTH[sx]["shoulder"]), sx, "derived/biacromial_over_stature", 1.0])
		R.append(["BREADTH hip / stature", "body_from_numbers.gd:23", float(BN.BREADTH[sx]["hip"]), sx, "derived/hipbreadth_over_stature", 1.0])
		R.append(["BMI_MEAN", "body_from_numbers.gd:24", float(BN.BMI_MEAN[sx]), sx, "derived/bmi_mean", 1.0])
		R.append(["biceps flexed mean m", "body_sliders.gd:19", float(BS.ANSUR["upperarm"][sx][0]), sx, "dims/bicepscircumferenceflexed/mean", 0.001])
		R.append(["biceps flexed SD m", "body_sliders.gd:19", float(BS.ANSUR["upperarm"][sx][1]), sx, "dims/bicepscircumferenceflexed/sd", 0.001])
	for k in PR.PRESETS:
		var p: Dictionary = PR.PRESETS[k]
		var pc := String(k).split("_")[1]
		R.append(["preset %s stature m" % k, "proportions.gd:78", float(p["stature"]), p["sex"], "derived/stature_m_p" + pc, 1.0])
		R.append(["preset %s mass kg" % k, "proportions.gd:78", float(p["mass"]), p["sex"], "derived/mass_kg_p" + pc, 1.0])
	var gi := {"pelvis": "buttockcircumference", "spine_01": "waistcircumference", "spine_03": "chestcircumference", "clavicle": "chestcircumference",
		"neck_01": "neckcircumference", "head": "headcircumference", "upperarm": "bicepscircumferenceflexed", "lowerarm": "forearmcircumferenceflexed",
		"hand": "wristcircumference", "thigh": "thighcircumference", "calf": "calfcircumference"}
	for j in gi:
		R.append(["GIRTH_E %s (mean of sexes)" % j, "proportions.gd:123", float(PR.GIRTH_E[j]), "both", "derived/elasticity/" + String(gi[j]), 1.0])
	R.append(["crowd STATURE_MEAN m", "crowd.gd:38", float(CR.STATURE_MEAN), "male", "dims/stature/mean", 0.001])
	R.append(["crowd STATURE_SD m", "crowd.gd:39", float(CR.STATURE_SD), "male", "dims/stature/sd", 0.001])
	R.append(["HAND_BREADTH m (median)", "hand_shape.gd:27", float(HS.HAND_BREADTH), "male", "dims/handbreadth/p50", 0.001])
	R.append(["PALM_LENGTH m (median)", "hand_shape.gd:28", float(HS.PALM_LENGTH), "male", "dims/palmlength/p50", 0.001])
	R.append(["HAND_CIRC m (median)", "hand_shape.gd:29", float(HS.HAND_CIRC), "male", "dims/handcircumference/p50", 0.001])
	R.append(["HAND_LENGTH m (median)", "hand_shape.gd:30", float(HS.HAND_LENGTH), "male", "dims/handlength/p50", 0.001])
	R.append(["WRIST_CIRC m (median)", "hand_shape.gd:46", float(HS.WRIST_CIRC), "male", "dims/wristcircumference/p50", 0.001])
	return R


func _init() -> void:
	var txt := FileAccess.get_file_as_string(SUMMARY)
	T = JSON.parse_string(txt) if txt != "" else {}
	ok(T.has("male") and T.has("female"), "1 the summary table loads (%d bytes)" % txt.length())
	if not (T.has("male") and T.has("female")):
		quit(1)
		return
	ok(int(T["male"]["n"]) == 4082 and int(T["female"]["n"]) == 1986, "1 n = %d men, %d women" % [int(T["male"]["n"]), int(T["female"]["n"])])
	ok(close(data("male", "dims/stature/mean"), 1756.2) and close(data("female", "dims/stature/mean"), 1628.5),
		"1 anchors: stature mean %.2f mm men, %.2f women" % [data("male", "dims/stature/mean"), data("female", "dims/stature/mean")])
	var R := registry()
	ok(R.size() >= 60, "2 the registry lists %d constants (>= 60)" % R.size())
	var bad := 0
	for r in R:
		var want := data(String(r[3]), String(r[4])) * float(r[5])
		var good := close(float(r[2]), want)
		if not good:
			bad += 1
		ok(good, "2 %s (%s, %s): code %.6g, data %.6g, off %.2f %%" % [r[0], r[1], r[3], float(r[2]), want, 100.0 * (float(r[2]) - want) / want])
	print("   registry: %d checked, %d off by more than 0.5 %%" % [R.size(), bad])
	# 3 planted controls: the same check must refuse these
	var bic := data("male", "dims/bicepscircumferenceflexed/mean") * 0.001
	ok(not close(0.339, bic), "3 PLANTED: the memory value 0.339 m vs data %.4f m is refused (%.1f %% off)" % [bic, 100.0 * (0.339 - bic) / bic])
	ok(close(bic * 1.004, bic) and not close(bic * 1.006, bic), "3 PLANTED edge: +0.4 % passes, +0.6 % is refused")
	print("ansurcheck: %d fail" % fails)
	quit(1 if fails > 0 else 0)
