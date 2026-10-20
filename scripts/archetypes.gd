## archetypes.gd - FIGHTER ARCHETYPES (ROADMAP_400 G23): body presets from published athlete measurements, not invented.
## Each row: stature (m), mass (kg), ape = arm span / stature, sex, and a source string naming where the numbers come from.
## They go through the BODY page's own model (BodyModel.base_scales + Proportions.clean): stature and mass are exact, the
## ARM scale is solved so the T-pose fingertip-to-fingertip span = ape x stature. Shoulder and hip breadth are NOT free
## here: a segment scale is uniform (the clavicles ride the trunk, the hip width the pelvis), so breadth follows stature
## and the trunk; mass thickens the skin through the R11 girth model. Nothing writes data/.
## Values are group MEANS of the cited studies, rounded; "approx" in a source = rounded from the review's tables, not a
## single athlete. Ape index of elite boxers is 1.02-1.06 (Chaabene et al. 2015); where a study gives no arm span the
## ape index is the sport's literature mean or the population norm (stated in the row).
class_name Archetypes
extends RefCounted

const SH_FRAC := 0.2059   # shoulder joints apart / stature, this skeleton (body_model.gd ARM SPAN CALIBRATION)
const SPAN_FRAC := 1.030   # the BODY page's median arm gives this span / stature (ARM_K)

## id -> {name, stature, mass, ape, lo, hi (the cited ape-index range), sex, src}
const TABLE := {
	"boxer_fly": {"name": "Boxer, flyweight (51 kg)", "stature": 1.66, "mass": 51.0, "ape": 1.03, "lo": 1.02, "hi": 1.06, "sex": "male",
		"src": "Olympic boxers, flyweight: ~166 cm, 51 kg (class limit), arm span 1.02-1.06 x height; Chaabene et al. 2015, Sports Med 45:1315 (physical and physiological attributes of Olympic boxers), approx"},
	"boxer_middle": {"name": "Boxer, middleweight (75 kg)", "stature": 1.78, "mass": 75.0, "ape": 1.04, "lo": 1.02, "hi": 1.06, "sex": "male",
		"src": "Olympic boxers, middleweight: ~178 cm, 75 kg (class limit), arm span 1.02-1.06 x height; Chaabene et al. 2015, Sports Med 45:1315, approx"},
	"boxer_heavy": {"name": "Boxer, heavyweight (95+ kg)", "stature": 1.91, "mass": 97.0, "ape": 1.05, "lo": 1.02, "hi": 1.06, "sex": "male",
		"src": "Olympic boxers, heavyweight: ~191 cm, ~97 kg, arm span 1.02-1.06 x height; Chaabene et al. 2015, Sports Med 45:1315, approx"},
	"mma_welter": {"name": "MMA welterweight (77 kg)", "stature": 1.79, "mass": 77.0, "ape": 1.03, "lo": 1.00, "hi": 1.07, "sex": "male",
		"src": "UFC welterweight roster means (UFC Stats: height ~179 cm, reach ~184 cm = 1.03 x height; weigh-in limit 77.1 kg), approx"},
	"sumo": {"name": "Sumo rikishi (makuuchi)", "stature": 1.82, "mass": 155.0, "ape": 1.01, "lo": 0.99, "hi": 1.03, "sex": "male",
		"src": "Japan Sumo Association makuuchi means ~182 cm, ~155 kg; arm span ~1.01 x height (Japanese norm), after Hattori et al. 1999 (body composition of sumo wrestlers), approx"},
	"judoka": {"name": "Judoka (-81 kg)", "stature": 1.77, "mass": 81.0, "ape": 1.03, "lo": 1.01, "hi": 1.05, "sex": "male",
		"src": "Elite judo -81 kg: ~177 cm, 81 kg (class limit); Franchini et al. 2011, Sports Med 41:147 (physiological profiles of elite judo athletes), approx"},
	"sprinter": {"name": "Sprinter (100 m)", "stature": 1.80, "mass": 77.0, "ape": 1.02, "lo": 1.00, "hi": 1.04, "sex": "male",
		"src": "World-class 100 m men: ~180 cm, ~77 kg; Uth 2005 (anthropometric comparison of world-class sprinters and normal populations), approx"},
	"marathoner": {"name": "Marathoner (elite)", "stature": 1.71, "mass": 59.0, "ape": 1.01, "lo": 0.99, "hi": 1.03, "sex": "male",
		"src": "Elite East African marathoners: ~171 cm, ~59 kg; Larsen 2003 (factors behind the dominance of Kenyan runners), approx"},
	"gymnast": {"name": "Gymnast (men's artistic)", "stature": 1.66, "mass": 63.0, "ape": 1.02, "lo": 1.00, "hi": 1.04, "sex": "male",
		"src": "Elite men's artistic gymnasts: ~166 cm, ~63 kg; Claessens/Lenoir/Malina kinanthropometry of gymnasts, approx"},
	"gymnast_w": {"name": "Gymnast (women's artistic)", "stature": 1.55, "mass": 46.0, "ape": 1.01, "lo": 0.99, "hi": 1.03, "sex": "female",
		"src": "Elite women's artistic gymnasts: ~155 cm, ~46 kg; Malina/Baxter-Jones/Claessens reviews of gymnasts, approx"},
	"kendoka": {"name": "Kendoka (university men)", "stature": 1.72, "mass": 68.0, "ape": 1.00, "lo": 0.98, "hi": 1.03, "sex": "male",
		"src": "Japanese university-age men (MEXT physical fitness survey: ~172 cm, ~66-68 kg); kendo athletes taken at the same values, ape index = the Japanese norm ~1.00, approx"},
	"medieval": {"name": "Medieval European man", "stature": 1.72, "mass": 66.0, "ape": 1.00, "lo": 0.98, "hi": 1.03, "sex": "male",
		"src": "Skeletal stature of medieval Europeans ~172 cm: Steckel 2004; Koepke & Baten 2005; mass from BMI ~22, approx"},
	"roman": {"name": "Roman legionary", "stature": 1.68, "mass": 66.0, "ape": 1.00, "lo": 0.98, "hi": 1.03, "sex": "male",
		"src": "Roman-period skeletons ~168 cm (Roberts & Cox 2003, Health and Disease in Britain); mass from BMI ~23, approx"},
	"edo_samurai": {"name": "Edo-period Japanese man", "stature": 1.57, "mass": 53.0, "ape": 1.00, "lo": 0.98, "hi": 1.03, "sex": "male",
		"src": "Edo-period skeletons ~157 cm (Hiramoto 1983; Hanihara); mass from BMI ~21.5, approx"},
}
const ORDER := ["boxer_fly", "boxer_middle", "boxer_heavy", "mma_welter", "sumo", "judoka", "sprinter", "marathoner", "gymnast", "gymnast_w", "kendoka", "medieval", "roman", "edo_samurai"]


## the scene's body dict for an archetype (Proportions.clean'd): exact stature and mass; arm scaled for the ape index
static func body_for(id: String) -> Dictionary:
	var a: Dictionary = TABLE[id]
	var st := float(a["stature"])
	var sc := BodyModel.base_scales(st)
	var m := (float(a["ape"]) - SH_FRAC) / (SPAN_FRAC - SH_FRAC)   # the page's median arm already gives SPAN_FRAC
	for s in BodyModel.GROUPS["arm"]:
		sc[s] = float(sc[s]) * m
	return Proportions.clean({"stature": st, "scale": sc, "sex": a["sex"], "mass": a["mass"]})


static func say(id: String) -> String:
	var a: Dictionary = TABLE[id]
	return "%s: %.0f cm, %.0f kg, arm span %.2f x height. Source: %s" % [a["name"], float(a["stature"]) * 100.0, float(a["mass"]), float(a["ape"]), a["src"]]
