## units.gd - the one place that writes a length, an angle or a time the user sees (ROADMAP 56: UNITS EVERYWHERE).
## Lengths are metres inside the app and centimetres on screen (millimetres under 1 cm); angles are degrees with the
## degree sign; times are seconds with the frame in brackets wherever the timeline is involved: "0.40 s (12 f)".
## Speeds, masses, impulses, frequencies keep their own units written in the format string (m/s, kg, BPM).
class_name Units


## metres -> "50 cm", "4 mm", "123 cm". Under 1 cm it is millimetres ("4 mm"); under 10 cm one decimal ("8.5 cm").
static func len(m: float) -> String:
	if absf(m) < 0.01:
		return "%d mm" % roundi(m * 1000.0)
	if absf(m) < 0.1:
		return "%.1f cm" % (m * 100.0)
	return "%.0f cm" % (m * 100.0)


## degrees -> "12.3°" (one decimal under 10 degrees, else whole degrees: "45°")
static func ang(deg: float) -> String:
	if absf(deg) < 10.0:
		return "%.1f°" % deg
	return "%.0f°" % deg


## seconds and the frame rate -> "0.40 s (12 f)". The frame is rounded to the nearest whole frame.
static func time(s: float, fps: float) -> String:
	return "%.2f s (%d f)" % [s, roundi(s * fps)]
