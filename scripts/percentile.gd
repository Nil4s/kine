## percentile.gd - PERCENTILE READOUT (ROADMAP_400 G16): where each measurable dimension of the body sits among ANSUR II men and women.
## Normal approximation: percentile = Phi((x - mean) / sd) (BodyModel.cdf). Values outside the 1st-99th percentile are flagged.
## SOURCE: ANSUR II 2012 report, Gordon et al. 2014 (US Army NATICK/TR-15/007). Not checked against PubMed/DOI here:
##   UNVERIFIED (from memory). Stature rows are BodyModel.ANSUR's. The other rows are rounded estimates and are marked as such:
##   span = 1.03 x stature (BodyModel.ARM_K calibration), sd 4.7 % of the mean; biacromial breadth men 399 mm sd 19, women
##   355 mm sd 17 (ratios 0.227 / 0.218 of stature as in BodyFromNumbers); bitrochanteric breadth men 362 mm sd 21, women 370 mm sd 24.
## The skeleton has joint CENTRES, not skin landmarks, so a joint distance is turned into the landmark breadth by a factor of MINE
##   (an estimate, not from ANSUR): shoulders 1.10 (biacromial / joint distance), hips 2.16 (bitrochanteric / hip-joint distance).
class_name Percentile
extends RefCounted

const SOURCE := "ANSUR II 2012 (Gordon et al. 2014, NATICK/TR-15/007), UNVERIFIED (from memory); non-stature rows are rounded estimates"
## dim -> sex -> [mean mm, sd mm]
const TABLE := {
	"stature": {"male": [1756.2, 68.6], "female": [1628.5, 64.2]},
	"span": {"male": [1809.0, 85.0], "female": [1677.0, 78.0]},
	"shoulders": {"male": [399.0, 19.0], "female": [355.0, 17.0]},
	"hips": {"male": [362.0, 21.0], "female": [370.0, 24.0]},
}
const K := {"stature": 1.0, "span": 1.0, "shoulders": 1.10, "hips": 2.16}   # measured -> survey landmark (MINE)
const LABEL := {"stature": "Stature", "span": "Arm span", "shoulders": "Shoulder breadth", "hips": "Hip breadth"}
const DIMS := ["stature", "span", "shoulders", "hips"]
const LO := 1.0
const HI := 99.0


## percentile (0..100) of a survey-scale value in mm
static func of(dim: String, sex: String, mm: float) -> float:
	var e: Array = TABLE[dim][sex]
	return BodyModel.pct((mm - float(e[0])) / float(e[1]))


## one row per dimension from BodyModel.measures: value (m, as measured), survey-scale mm, both percentiles, both flags
static func rows(meas: Dictionary) -> Array:
	var out := []
	for d in DIMS:
		var v := float(meas[d])
		var mm := v * 1000.0 * float(K[d])
		var pm := of(d, "male", mm)
		var pf := of(d, "female", mm)
		out.append({"dim": d, "label": LABEL[d], "value": v, "mm": mm, "pct_male": pm, "pct_female": pf,
			"flag_male": pm < LO or pm > HI, "flag_female": pf < LO or pf > HI})
	return out


static func _p(p: float) -> String:
	if p > HI:
		return "above 99th"
	if p < LO:
		return "below 1st"
	return BodyModel.ordinal(p)


static func text(r: Dictionary) -> String:
	var s := "%s %.1f cm: men %s, women %s" % [r["label"], float(r["value"]) * 100.0, _p(float(r["pct_male"])), _p(float(r["pct_female"]))]
	if r["flag_male"] or r["flag_female"]:
		s += " (outside 1st-99th)"
	return s


const NOTE := "Percentiles by normal approximation from ANSUR II means and SDs (men, women). Shoulder and hip joint distances are scaled to survey breadths (estimate). Outside 1st-99th is flagged."
