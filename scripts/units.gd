## units.gd - the one place that writes a length, an angle or a time the user sees (ROADMAP 56: UNITS EVERYWHERE).
## Lengths are metres inside the app and centimetres on screen (millimetres under 1 cm); angles are degrees with the
## degree sign; times are seconds with the frame in brackets wherever the timeline is involved: "0.40 s (12 f)".
## Speeds, masses, impulses, frequencies keep their own units written in the format string (m/s, kg, BPM).
class_name Units


## The user's length unit: "cm" (default), "m" or "in". Metres inside, always; this only changes what is shown and what a bare number means.
static var unit := "cm"
const UNITS := ["cm", "m", "in"]
const M_PER := {"mm": 0.001, "cm": 0.01, "m": 1.0, "in": 0.0254, "ft": 0.3048}


static func set_unit(u: String) -> bool:
	if not UNITS.has(u):
		return false
	unit = u
	return true


## metres -> a number in unit u (default: the user's unit); from_unit is the exact inverse
static func to_unit(m: float, u: String = "") -> float:
	return m / float(M_PER[u if u != "" else unit])


static func from_unit(v: float, u: String = "") -> float:
	return v * float(M_PER[u if u != "" else unit])


## metres in a named unit with its suffix, 4 decimals trimmed: "70.0787 in", "12 in", "0.3048 m"
static func fmt_as(m: float, u: String) -> String:
	return "%s %s" % [String.num(to_unit(m, u), 4), u]


## a length typed by the user -> metres; "12 in", "30 cm", 12" , 1.5ft; a bare number is in the user's unit. NAN when it is no length.
static func parse_m(text: String) -> float:
	var sp := LengthParse.split_unit(text)
	var n := LengthParse.number_of(String(sp[1]))
	if is_nan(n):
		return NAN
	var u: String = sp[0] if String(sp[0]) != "" else unit
	return n * float(M_PER.get(u, M_PER[unit]))


## the suffix a length field shows next to its number
static func suffix() -> String:
	return unit


## metres -> "50 cm", "4 mm", "123 cm" (cm unit). Under 1 cm it is millimetres ("4 mm"); under 10 cm one decimal ("8.5 cm").
## In "m" and "in" the number is the length in that unit, 4 decimals trimmed: "1.78 m", "70.0787 in".
static func len(m: float) -> String:
	if unit != "cm":
		return fmt_as(m, unit)
	if absf(m) < 0.01:
		return "%d mm" % roundi(m * 1000.0)
	if absf(m) < 0.1:
		return "%.1f cm" % (m * 100.0)
	return "%.0f cm" % (m * 100.0)


## a stature (m) as the user's unit shows it: "178.0 cm", "70.0787 in", "1.78 m"
static func stature(m: float) -> String:
	return "%.1f cm" % (m * 100.0) if unit == "cm" else Units.len(m)


## a position (m) with a millimetre of detail in cm: "12.3 cm"; m and in as len()
static func len_fine(m: float) -> String:
	return "%.1f cm" % (m * 100.0) if unit == "cm" else Units.len(m)


## degrees -> "12.3°" (one decimal under 10 degrees, else whole degrees: "45°")
static func ang(deg: float) -> String:
	if absf(deg) < 10.0:
		return "%.1f°" % deg
	return "%.0f°" % deg


## seconds and the frame rate -> "0.40 s (12 f)". The frame is rounded to the nearest whole frame.
static func time(s: float, fps: float) -> String:
	return "%.2f s (%d f)" % [s, roundi(s * fps)]


## L118: a length that used to print as bare metres ("%.2f m"): cm mode keeps that text, m / in write the unit's own number
static func metres(m: float, dp: int) -> String:
	return ("%." + str(dp) + "f m") % m if unit == "cm" else fmt_as(m, unit)


## a length that used to print as bare centimetres ("%.1f cm", "%.0f cm"): cm mode keeps that text
static func fixed(m: float, dp: int) -> String:
	return ("%." + str(dp) + "f cm") % (m * 100.0) if unit == "cm" else fmt_as(m, unit)


## an area (m^2): "500.0 cm²", "0.05 m²", "77.5 in²" (m / in: 8 decimals trimmed, so small areas keep 1e-6 relative)
static func area(m2: float) -> String:
	if unit == "cm":
		return "%.1f cm²" % (m2 * 10000.0)
	var f := float(M_PER[unit])
	return "%s %s²" % [String.num(m2 / (f * f), 8), unit]


## a volume (m^3): "500 cm³ (0.500 L)", "0.0005 m³ (0.500 L)", "30.5 in³ (0.500 L)"
static func vol(m3: float) -> String:
	var lit := " (%.3f L)" % (m3 * 1000.0)
	if unit == "cm":
		return "%.0f cm³" % (m3 * 1000000.0) + lit
	var f := float(M_PER[unit])
	return "%s %s³" % [String.num(m3 / (f * f * f), 8), unit] + lit


## the shot-camera banner: lens in mm, f-stop, and the focus distance as a length (NAN focus = none keyed)
static func shot_readout(mm: float, fstop: float, focus_m: float) -> String:
	var s := "SHOT CAMERA  %.0f mm  16:9" % mm
	if not is_nan(focus_m):
		s += "  f/%.1f  focus %s" % [fstop, metres(focus_m, 2)]
	return s


## the number typed after E / I: metres in cm mode (as always: "E 0.3 Enter"), else in the user's unit. NAN when it is no number.
static func typed_m(text: String) -> float:
	if not text.is_valid_float():
		return NAN
	return text.to_float() if unit == "cm" else from_unit(text.to_float())


static func typed_text(text: String) -> String:
	return "type %s" % text if unit == "cm" else "type %s %s" % [text, unit]
