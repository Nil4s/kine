class_name KMeshPen
extends RefCounted
## ROADMAP_400 P09: what a drawing tablet's pen says on a brush page. One per page; the page calls note() on every mouse motion
## (hover too, so the press, which carries no pressure, knows it) and asks for the factors. A mouse reports pressure 0, no
## eraser end and no tilt: every factor is then exactly 1 / false / 0, so a mouse stroke is unchanged.
##   target "strength": pressure scales what a dab does (default) | "radius": pressure scales the brush radius |
##          "both" | "off": the pen is ignored
##   inv    the eraser end of the pen: the brush's inverse (sculpt digs, ADD <-> subtract, lighten <-> darken)
##   tilt   (page option) the tilt direction rotates the stamp of a flat/alpha brush
const MIN_PR := 0.02

var target := "strength"
var tilt_on := false
var pr := 1.0
var inv := false
var tilt := Vector2.ZERO


func note(ev: InputEventMouseMotion) -> void:
	pr = ev.pressure if ev.pressure > 0.0 else 1.0
	inv = ev.pen_inverted
	tilt = ev.tilt


## the factor on a dab's strength
func sk() -> float:
	return maxf(pr, MIN_PR) if (target == "strength" or target == "both") and pr != 1.0 else 1.0


## the factor on the brush radius
func rk() -> float:
	return maxf(pr, MIN_PR) if (target == "radius" or target == "both") and pr != 1.0 else 1.0


## true when the eraser end is down and the pen is not switched off
func erasing() -> bool:
	return inv and target != "off"


## the stamp rotation (radians) from the pen tilt; 0 for a mouse or with the option off
func tilt_angle() -> float:
	return atan2(tilt.y, tilt.x) if tilt_on and tilt.length() > 0.001 else 0.0


## the inverse of a vertex-paint blend mode
static func inverse_vmode(mode: String) -> String:
	match mode:
		"add": return "subtract"
		"subtract": return "add"
		"lighten": return "darken"
		"darken": return "lighten"
	return mode
