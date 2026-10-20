## body_from_numbers.gd - BODY FROM 5 NUMBERS (ROADMAP_400 G13): height, weight, sex, age, build -> a whole plausible body.
## Sources:
##   SEGMENT LENGTHS  Winter, Biomechanics and Motor Control of Human Movement (2009) Fig. 4.1 (Drillis & Contini 1966), the same
##            fractions of stature the presets use (Proportions.DRILLIS): upper arm 0.186 H, forearm 0.146 H, hand 0.108 H, thigh
##            0.245 H, shank 0.246 H (knee -> ankle), foot length 0.152 H, shoulder height 0.818 H, hip height 0.530 H.
##   STATURE  ANSUR II 2012 (Gordon et al. 2014, NATICK/TR-15/007): men mean 175.62 cm sd 6.86, women 162.85 sd 6.42 (the
##            percentile readout; BodyModel.ANSUR holds the same numbers).
##   MASS     ANSUR II median/log-sigma (BodyModel.ANSUR); the body's segment masses are de Leva 1996 (J Biomech 29:1223) via
##            Proportions.masses, which renormalises them to the body's mass (so the weight you give is the weight it has).
##   BREADTHS ANSUR II biacromial breadth / stature, rounded from the summary tables: men 0.227, women 0.218; hip breadth
##            (bitrochanteric region) / stature men 0.206, women 0.227. APPROXIMATE (not re-read from the raw files: stated).
##            They grow with the person's BMI relative to the ANSUR sex mean (men 27.0, women 25.5) to the power 0.25 (a
##            breadth is a length, mass goes as length^3-4: MINE, an estimate) and a build step (lean 0.97, average 1, heavy 1.04,
##            MINE). They are REPORTED; the skeleton's segment scale is uniform (see BodyModel), so what reaches the body is the
##            weight: the skin thickens across each bone by the ANSUR II girth elasticities (Proportions.girth_lambda).
##   AGE      the spine shortens, the long bones do not: from 40 on, 0.08 cm of stature per year is lost in the trunk (about
##            half of the 0.1-0.15 cm/yr older-adult surveys report; kept light on purpose). The limbs are therefore taken from
##            the young-adult height H + loss, and the trunk gives back what the requested height leaves.
class_name BodyFromNumbers
extends RefCounted

const WINTER := {"upper_arm": 0.186, "forearm": 0.146, "hand": 0.108, "thigh": 0.245, "shank": 0.246, "foot": 0.152}
const BREADTH := {"male": {"shoulder": 0.227, "hip": 0.206}, "female": {"shoulder": 0.218, "hip": 0.227}}
const BMI_MEAN := {"male": 27.0, "female": 25.5}
const BUILD_K := {"lean": 0.97, "average": 1.0, "heavy": 1.04}
const BUILDS := ["lean", "average", "heavy"]
const LOSS_PER_YEAR_CM := 0.08
const LOSS_FROM := 40.0


static func age_loss_cm(age: float) -> float:
	return maxf(0.0, age - LOSS_FROM) * LOSS_PER_YEAR_CM


## everything the five numbers say: lengths (m, per segment), breadths (m), bmi, percentile readout. No scene is touched.
static func predict(height_cm: float, weight_kg: float, sex: String, age: float, build: String) -> Dictionary:
	var sx := "female" if sex == "female" else "male"
	var h := clampf(height_cm, 100.0, 230.0) / 100.0
	var kg := clampf(weight_kg, 20.0, 250.0)
	var loss := age_loss_cm(age) / 100.0
	var h0 := h + loss   # the young-adult height the long bones belong to
	var lengths := {}
	for s in WINTER:
		lengths[s] = float(WINTER[s]) * h0
	lengths["trunk"] = float(Proportions.DRILLIS["trunk"]) * h - loss
	lengths["head"] = float(Proportions.DRILLIS["head"]) * h
	var bmi := kg / (h * h)
	var bk: float = float(BUILD_K.get(build, 1.0)) * pow(bmi / float(BMI_MEAN[sx]), 0.25)
	var br := {"shoulder": float(BREADTH[sx]["shoulder"]) * h * bk, "hip": float(BREADTH[sx]["hip"]) * h * bk}
	var bl := 1.0 if sx == "male" else 0.0
	var other := 0.0 if sx == "male" else 1.0
	return {"stature": h, "mass": kg, "sex": sx, "age": age, "build": build, "bmi": bmi, "lengths": lengths, "breadths": br,
		"height_pct": BodyModel.stature_pct(bl, h), "height_pct_other": BodyModel.stature_pct(other, h),
		"mass_pct": BodyModel.mass_pct(bl, kg)}


## the scene's body dict (Proportions.clean'd) for these numbers: the segment scales make each long bone its predicted length;
## the trunk takes what the stature leaves (the same solve as Proportions.preset, so the measured stature is the request).
static func body_for(height_cm: float, weight_kg: float, sex: String, age: float, build: String) -> Dictionary:
	var p := predict(height_cm, weight_kg, sex, age, build)
	var st := float(p["stature"])
	var L := Proportions.default_lengths()
	var sc := {}
	for s in Proportions.SEGS:
		sc[s] = float(p["lengths"][s]) / float(L[s])
	var tmp := Body.new()
	tmp.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	tmp.body = {"stature": st, "scale": sc}
	tmp.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var g: float = float(tmp.seg_s["pelvis"]) / float(sc["trunk"])
	sc["trunk"] = float(sc["trunk"]) + (st - st / g) / Proportions.TRUNK_RISE
	return Proportions.clean({"stature": st, "scale": sc, "sex": p["sex"], "mass": p["mass"]})


## "168th... " -> "your 175.0 cm is the 50th percentile of ANSUR II men (the 96th of women); 85 kg is the 52nd of men"
static func readout(p: Dictionary) -> String:
	var mine := "men" if p["sex"] == "male" else "women"
	var other := "women" if p["sex"] == "male" else "men"
	return "%.1f cm is the %s percentile of ANSUR II %s (the %s of %s); %.0f kg is the %s of %s, BMI %.1f" % [
		float(p["stature"]) * 100.0, BodyModel.ordinal(float(p["height_pct"])), mine, BodyModel.ordinal(float(p["height_pct_other"])), other,
		float(p["mass"]), BodyModel.ordinal(float(p["mass_pct"])), mine, float(p["bmi"])]
