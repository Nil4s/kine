class_name LightRig
## LIGHTING PRESETS ON THE SHOT CAMERA (ROADMAP round 2, R1). Each shot may carry a "light": one of IDS. The rig is placed
## RELATIVE TO THE SHOT CAMERA: azimuth is measured from the camera's own axis (0 = a light at the camera, + = to the
## camera's left, 180 = behind the subject, facing the lens), elevation above the horizon. So whatever way the camera is
## keyed, "key light on the camera-facing side, a little to the left" holds. Pure maths; main.gd _light_apply sets the
## three DirectionalLight3Ds (key, fill, rim) and the ambient from rig().
##
## LIGHT RATIOS (the real numbers): Blain Brown, "Cinematography: Theory and Practice" (3rd ed., Focal Press 2016), the
## chapter on lighting and contrast: a three-point key:fill of about 2:1 (flat, bright, TV and comedy) to 4:1 (drama);
## 8:1 and beyond is the low-key, chiaroscuro look of film noir. Millerson, "Lighting for Film and Electronic
## Cinematography" (Focal Press), gives the same family: key 1, fill 1/2 to 1/4, backlight about equal to the key.
## Exterior sun: the shaded side is lit by sky and bounce, about 1/4 of the sun's light on the subject (a 2-stop fill).
## WHY THE AMBIENT IS LOW: the stage's own ambient (0.6) lifts the shadow side as much as the key lights the lit side, so the
## looks collapse; a preset REPLACES the stage lights and ambient (main.gd _light_apply) with its own low ambient. The screen
## is sRGB-encoded, so a linear ratio r reads as r^(1/2.2) in pixels: noir's bar of 4 in pixels is about 25:1 in light.
## "adj" = [brightness, contrast] of the environment's colour adjustment (Godot: out = (v*brightness - 0.5)*contrast + 0.5 on the
## screen value): the cosine falloff of a lit cylinder alone cannot give noir its crushed shadow side with a key kept on the lens
## side, so each look also carries its own contrast, put back to 1/off by "back to default".
## RATIO here is key energy : fill energy of the two lights (before the ambient, which the viewer adds to the fill side).

const IDS := ["three_point", "rim", "noir", "daylight"]
const NAMES := {"three_point": "Light: three-point", "rim": "Light: rim", "noir": "Light: noir", "daylight": "Light: daylight"}
const WARM := Color(1.0, 0.95, 0.88)
const NEUTRAL := Color(1.0, 1.0, 1.0)
const COOL := Color(0.86, 0.92, 1.0)
const SKY := Color(0.6, 0.7, 0.85)
const GREY := Color(0.55, 0.57, 0.62)

## role -> [azimuth deg (+ = camera left), elevation deg, energy, colour]; "amb" -> [energy, colour]
const PRESETS := {
	"three_point": {"key": [70.0, 25.0, 2.0, WARM], "fill": [-30.0, 45.0, 0.55, COOL], "rim": [180.0, 50.0, 1.2, NEUTRAL], "amb": [0.03, GREY], "adj": [0.9, 2.4]},   # key:fill 3.6:1
	"rim": {"key": [30.0, 20.0, 0.3, WARM], "fill": [-30.0, 10.0, 0.15, COOL], "rim": [150.0, 25.0, 3.0, COOL], "amb": [0.03, GREY], "adj": [1.0, 1.6]},         # 2:1 front, the rim 10x the key: a bright edge, a dim front
	"noir": {"key": [72.0, 28.0, 1.8, WARM], "fill": [-60.0, 0.0, 0.02, COOL], "rim": [160.0, 45.0, 0.5, NEUTRAL], "amb": [0.01, GREY], "adj": [1.0, 2.0]},       # 90:1: one hard side light in a black room
	"daylight": {"key": [60.0, 40.0, 2.4, WARM], "fill": [-40.0, 15.0, 0.48, SKY], "rim": [180.0, 30.0, 0.0, NEUTRAL], "amb": [0.08, SKY], "adj": [1.0, 1.5]},   # sun : sky 5:1
}


## the horizontal unit vector the camera looks along (aim - pos with y dropped); a straight-down camera looks "north"
static func forward_h(pos: Vector3, aim: Vector3) -> Vector3:
	var f := aim - pos
	f.y = 0.0
	return Vector3(0, 0, -1) if f.length() < 1e-4 else f.normalized()


## the unit vector from the subject TOWARD a light at (azimuth, elevation) relative to the camera
static func source_dir(f: Vector3, az_deg: float, el_deg: float) -> Vector3:
	var right := f.cross(Vector3.UP)
	var az := deg_to_rad(az_deg)
	var el := deg_to_rad(el_deg)
	var h := -f * cos(az) - right * sin(az)   # az 0 = at the camera; + = to the left of the lens
	return (h * cos(el) + Vector3.UP * sin(el)).normalized()


## the rig for preset id about a camera at pos looking at aim (hero-world): {"key"|"fill"|"rim": {"dir" (the way the
## light POINTS), "energy", "color"}, "ambient": {"energy", "color"}}; {} for an unknown id
static func rig(id: String, pos: Vector3, aim: Vector3) -> Dictionary:
	if not PRESETS.has(id):
		return {}
	var f := forward_h(pos, aim)
	var out := {}
	for role in ["key", "fill", "rim"]:
		var p: Array = PRESETS[id][role]
		out[role] = {"dir": -source_dir(f, p[0], p[1]), "energy": float(p[2]), "color": p[3]}
	out["adjust"] = {"brightness": float(PRESETS[id]["adj"][0]), "contrast": float(PRESETS[id]["adj"][1])}
	out["ambient"] = {"energy": float(PRESETS[id]["amb"][0]), "color": PRESETS[id]["amb"][1]}
	return out


## key energy : fill energy
static func ratio(id: String) -> float:
	if not PRESETS.has(id):
		return 0.0
	return float(PRESETS[id]["key"][2]) / maxf(1e-6, float(PRESETS[id]["fill"][2]))


## one line for the tooltip and the status bar
static func tip(id: String) -> String:
	var p: Dictionary = PRESETS[id]
	return "key %.1f at %d deg left of the lens, fill %.2f (key:fill %.0f:1), %s; placed relative to the shot camera, on the shot at the playhead (one undo step)" % [
		p["key"][2], int(p["key"][0]), p["fill"][2], ratio(id), "no back light" if float(p["rim"][2]) <= 0.0 else "back light %.2f" % float(p["rim"][2])]
