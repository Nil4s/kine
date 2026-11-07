## percentile.gd - PERCENTILE READOUT (ROADMAP_400 G16): where each measurable dimension of the body sits among ANSUR II men and women.
## Normal approximation: percentile = Phi((x - mean) / sd) (BodyModel.cdf). Values outside the 1st-99th percentile are flagged.
## SOURCE: ANSUR II 2012 public data (openlab.psu.edu/ansur2), summary stats in data/ansur2_summary.json (L138, VERIFIED 11-07):
##   span, biacromialbreadth, hipbreadth (standing). ANSUR II has no bitrochanteric breadth, so "hips" is the standing hip breadth;
##   the hips factor K below was chosen against the old bitrochanteric estimate, so the hips percentile stays approximate.
## The skeleton has joint CENTRES, not skin landmarks, so a joint distance is turned into the landmark breadth by a factor of MINE
##   (an estimate, not from ANSUR): shoulders 1.10 (biacromial / joint distance), hips 2.16 (bitrochanteric / hip-joint distance).
class_name Percentile
extends RefCounted

const SOURCE := "ANSUR II 2012 (Gordon et al. 2014, NATICK/TR-15/007): values VERIFIED 11-07 against the public data (openlab.psu.edu/ansur2, data/ansur2_summary.json); report citation UNVERIFIED (no DOI/PMID); hips = standing hip breadth"
## dim -> sex -> [mean mm, sd mm]
const TABLE := {
	"stature": {"male": [1756.2, 68.6], "female": [1628.5, 64.2]},
	"span": {"male": [1814.2, 84.6], "female": [1660.3, 83.0]},
	"shoulders": {"male": [415.7, 19.2], "female": [365.3, 18.3]},
	"hips": {"male": [345.7, 24.2], "female": [353.8, 26.7]},
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
