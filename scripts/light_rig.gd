class_name LightRig
## LIGHTING PRESETS ON THE SHOT CAMERA (ROADMAP round 2, R1). Each shot may carry a "light": one of IDS. The rig is placed
## RELATIVE TO THE SHOT CAMERA: azimuth is measured from the camera's own axis (0 = a light at the camera, + = to the
## camera's left, 180 = behind the subject, facing the lens), elevation above the horizon. So whatever way the camera is
## keyed, "key light on the camera-facing side, a little to the left" holds. Pure maths; main.gd _light_apply sets the
## KEY ANGLES (standard practice): three-point key ~45 deg off the camera axis and 30-45 deg up (Brown, Cinematography: Theory and
## Practice, the three-point chapter); noir = side/split lighting, key at ~90 deg, low, no fill (Brown, the chiaroscuro / low-key
## section); daylight = a sun ~60 deg round and high plus sky fill (Brown, exterior lighting).
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
const NAMES := {"three_point": "Light: three-point", "rim": "Light: rim", "noir": "Light: noir", "daylight": "Light: daylight",
	"studio": "Light: studio", "overcast": "Light: overcast", "sunset": "Light: sunset", "night": "Light: night"}
## L25 LIGHT RIG PANEL: the five looks the panel offers (the four above stay as they were; overcast, sunset and night are new)
## and their panel names. studio is a new, gentle 3-point (the older three_point look is crushed by its contrast 3.6), dramatic = noir. IDS is NOT extended (tests/r1_test.gd loops it with four bars).
const ALL_IDS := ["studio", "noir", "overcast", "sunset", "night"]
const PANEL_NAMES := {"studio": "Studio 3-point", "noir": "Dramatic", "overcast": "Overcast", "sunset": "Sunset", "night": "Night"}
const EXTRA_IDS := ["studio", "overcast", "sunset", "night"]
const SUNSET := Color(1.0, 0.55, 0.3)
const MOON := Color(0.55, 0.65, 1.0)
const WARM := Color(1.0, 0.95, 0.88)
const NEUTRAL := Color(1.0, 1.0, 1.0)
const COOL := Color(0.86, 0.92, 1.0)
const SKY := Color(0.6, 0.7, 0.85)
const GREY := Color(0.55, 0.57, 0.62)

## role -> [azimuth deg (+ = camera left), elevation deg, energy, colour]; "amb" -> [energy, colour]
const PRESETS := {
	"three_point": {"key": [55.0, 30.0, 2.0, WARM], "fill": [0.0, 10.0, 0.5, COOL], "rim": [180.0, 50.0, 1.2, NEUTRAL], "amb": [0.01, GREY], "adj": [0.58, 4.4]},   # key:fill 3.6:1
	"rim": {"key": [30.0, 20.0, 0.3, WARM], "fill": [-30.0, 10.0, 0.15, COOL], "rim": [150.0, 25.0, 3.0, COOL], "amb": [0.03, GREY], "adj": [1.0, 1.6]},         # 2:1 front, the rim 10x the key: a bright edge, a dim front
	"noir": {"key": [90.0, 15.0, 1.8, WARM], "fill": [-60.0, 0.0, 0.02, COOL], "rim": [160.0, 45.0, 0.5, NEUTRAL], "amb": [0.01, GREY], "adj": [1.0, 2.0]},       # 90:1: one hard side light in a black room
	"daylight": {"key": [60.0, 35.0, 2.4, WARM], "fill": [-40.0, 15.0, 0.48, SKY], "rim": [180.0, 30.0, 0.0, NEUTRAL], "amb": [0.05, SKY], "adj": [0.85, 3.2]},   # sun : sky 5:1
	# L25: studio = the textbook 3-point with NO contrast crush, so a grey sphere reads key:fill about 2.5:1 (Brown's 2:1 to 4:1)
	"studio": {"key": [45.0, 35.0, 2.0, WARM], "fill": [-30.0, 10.0, 0.65, COOL], "rim": [180.0, 45.0, 1.2, NEUTRAL], "amb": [0.08, GREY], "adj": [1.0, 1.0]},
	# L25: overcast = a big soft source: two near-equal high lights either side and a strong ambient (Brown: ratios of 1.5:1 and under are flat, shadowless light)
	"overcast": {"key": [20.0, 55.0, 0.9, NEUTRAL], "fill": [-20.0, 45.0, 0.85, COOL], "rim": [180.0, 40.0, 0.0, NEUTRAL], "amb": [0.35, GREY], "adj": [1.0, 1.0]},
	# sunset = a low orange sun, a blue sky fill; golden hour is warm key ~2000-3500 K against a cool sky
	"sunset": {"key": [75.0, 8.0, 2.2, SUNSET], "fill": [-40.0, 15.0, 0.5, Color(0.45, 0.5, 0.8)], "rim": [170.0, 12.0, 0.8, SUNSET], "amb": [0.04, Color(0.45, 0.35, 0.55)], "adj": [1.0, 1.0]},
	# night = a dim cool moon and a very low ambient (day-for-night practice: blue, low key, soft fill)
	"night": {"key": [60.0, 40.0, 0.5, MOON], "fill": [-40.0, 10.0, 0.12, Color(0.4, 0.5, 0.9)], "rim": [170.0, 35.0, 0.35, MOON], "amb": [0.02, Color(0.2, 0.25, 0.4)], "adj": [1.0, 1.0]},
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


## L25: put a rig() dictionary on three lights and an environment (what main.gd _light_apply does for the stage; tests use it on their own stage)
static func apply_rig(r: Dictionary, key: DirectionalLight3D, fill: DirectionalLight3D, rim: DirectionalLight3D, env: Environment) -> void:
	for pair in [[key, "key"], [fill, "fill"], [rim, "rim"]]:
		var L: DirectionalLight3D = pair[0]
		var d: Dictionary = r[pair[1]]
		L.basis = Basis.looking_at(d["dir"], Vector3.UP)
		L.light_energy = d["energy"]
		L.light_color = d["color"]
	env.ambient_light_energy = r["ambient"]["energy"]
	env.ambient_light_color = r["ambient"]["color"]
	env.adjustment_enabled = true
	env.adjustment_brightness = r["adjust"]["brightness"]
	env.adjustment_contrast = r["adjust"]["contrast"]


## ---- LIGHT LINKING (Godot render layers + Light3D.light_cull_mask). The stage's floor is on WORLD_BIT (layer 19) ONLY (a light lights an
## object when mask AND layers is not zero, so the floor must not also sit on layer 1); the character, props and everything
## else are on layer 1. A light that lights "everything" has the full mask; one that lights "the character only" has every
## layer except WORLD_BIT, so the floor ignores it (the floor still gets the ambient
## light and the lights that are not linked). Shadows are unaffected by the cull mask in Godot.
const WORLD_BIT := 1 << 18
const ALL_MASK := 0xFFFFF


static func link_mask(char_only: bool) -> int:
	return ALL_MASK & ~WORLD_BIT if char_only else ALL_MASK


static func set_link(light: Light3D, char_only: bool) -> void:
	light.light_cull_mask = link_mask(char_only)


## ---- THE SKY PICKER. No .hdr / .exr ships in the repo (and none with a clear CC0 licence is vendored), so the maps are
## procedural skies (ProceduralSkyMaterial): [top, horizon, ground horizon, ground bottom, sky curve]. They are generated here,
## so there is nothing to license. A picture file of the user's own is still available through the View menu's picture background.
const SKY_IDS := ["clear_day", "overcast", "sunset", "night", "studio_grey"]
const SKY_NAMES := {"clear_day": "Clear day", "overcast": "Overcast sky", "sunset": "Sunset", "night": "Night", "studio_grey": "Studio grey"}
const SKIES := {
	"clear_day": [Color(0.20, 0.38, 0.75), Color(0.70, 0.80, 0.92), Color(0.62, 0.68, 0.74), Color(0.35, 0.36, 0.38), 0.15],
	"overcast": [Color(0.55, 0.58, 0.62), Color(0.68, 0.70, 0.72), Color(0.58, 0.59, 0.60), Color(0.40, 0.40, 0.42), 0.4],
	"sunset": [Color(0.25, 0.20, 0.45), Color(1.0, 0.55, 0.25), Color(0.55, 0.30, 0.20), Color(0.25, 0.15, 0.12), 0.25],
	"night": [Color(0.01, 0.02, 0.06), Color(0.05, 0.07, 0.15), Color(0.03, 0.04, 0.08), Color(0.02, 0.02, 0.03), 0.2],
	"studio_grey": [Color(0.22, 0.22, 0.24), Color(0.30, 0.29, 0.28), Color(0.20, 0.20, 0.20), Color(0.12, 0.12, 0.12), 0.3],
}
static var _skies := {}


static func make_sky(id: String) -> Sky:
	if not SKIES.has(id):
		return null
	if not _skies.has(id):
		var d: Array = SKIES[id]
		var pm := ProceduralSkyMaterial.new()
		pm.sky_top_color = d[0]
		pm.sky_horizon_color = d[1]
		pm.ground_horizon_color = d[2]
		pm.ground_bottom_color = d[3]
		pm.sky_curve = d[4]
		pm.sun_angle_max = 0.0   # no sun disc: the three directional lights are the lights, the map is the world behind them
		var sk := Sky.new()
		sk.sky_material = pm
		sk.radiance_size = Sky.RADIANCE_SIZE_128
		_skies[id] = sk
	return _skies[id]


## the map id as the world environment's background and ambient light, turned deg about the vertical, scaled by intensity
## (background and ambient). id "" = no map: the sky is taken off (the caller puts its flat colour back)
static func apply_hdri(env: Environment, id: String, rot_deg: float, intensity: float) -> void:
	if id == "" or not SKIES.has(id):
		env.sky = null
		env.background_mode = Environment.BG_COLOR
		env.background_energy_multiplier = 1.0
		env.sky_rotation = Vector3.ZERO
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		return
	env.sky = make_sky(id)
	env.background_mode = Environment.BG_SKY
	env.sky_rotation = Vector3(0.0, deg_to_rad(rot_deg), 0.0)
	env.background_energy_multiplier = intensity
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = intensity
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
