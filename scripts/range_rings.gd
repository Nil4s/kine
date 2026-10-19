## range_rings.gd - ROADMAP 38: DISTANCE-TO-OPPONENT GUIDE. Floor rings around the picked fighter at its reach, a View toggle
## (main.gd: "Range rings on/off"). Pure geometry in report() (the test reads it with no window); the drawing is draw().
##   CENTRE: the picked fighter's shoulder line (the midpoint of its two upper-arm joints) carried to the floor (y = 0).
##   RINGS (radii from the body's OWN segment lengths, read off the posed joints; a bone keeps its length under any pose):
##     arm     = upper arm + forearm + hand (shoulder joint to the end of the hand)
##     weapon  = arm + the held prop's length (wep_len), drawn only when the picked fighter holds one
##     step-in = (weapon, or arm with no prop) + one stride; stride = 0.4 x body height. Hof (1996) and Gait Posture 2009
##               (PMID 19502061): people step 0.415 +- 0.038 of their height per step at 1.33 m/s, so 0.4 is the
##               ordinary step. Height is the stature the body was built to (B.body "stature", else the mannequin's).
##   GAP: the other fighter's nearest body part, measured on the floor: the horizontal distance from the centre to each
##     of its capsules' axes, minus the capsule radius (weapons and fingers are not body parts here). A ring is BRIGHT
##     when that gap is <= its radius (the other fighter's nearest part is inside it); dim otherwise.
##   LABEL: the current distance in metres, from the centre to the nearest part, and the name of that fighter.
class_name RangeRings
extends Node3D

const STEP_FRAC := 0.4        # one stride over the body height (Gait Posture 2009, PMID 19502061: 0.415 +- 0.038)
const N_RING := 96            # points per circle
const LIFT := 0.004           # m above the floor, so the rings do not z-fight it

var on := false               # the View toggle
var _mesh: MeshInstance3D
var _label: Label3D
var last: Dictionary = {}     # the last report (tests read it)


func setup() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.name = "range_rings"
	_mesh.mesh = ImmediateMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = true
	m.render_priority = 2
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mesh.material_override = m
	add_child(_mesh)
	_label = Label3D.new()
	_label.name = "range_label"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 40
	_label.pixel_size = 0.0025
	_label.outline_size = 8
	add_child(_label)


# ---- geometry (pure) ------------------------------------------------------------------------------------------

## the body's height in m: its stature (Proportions sets it), else the mannequin's
static func height_of(B: Body) -> float:
	return float(B.body.get("stature", Proportions.DEFAULT_STATURE))


## the reaches from the body's own segment lengths: {"upper", "fore", "hand", "arm", "weapon", "step", "step_in", "height"}.
## "weapon" is arm + the held prop (wep_len) or arm when none is held (has_weapon says which)
static func reaches(B: Body) -> Dictionary:
	var up := 0.0
	var fore := 0.0
	var hand := 0.0
	for s in ["_l", "_r"]:
		up += (B.P["lowerarm" + s] as Vector3).distance_to(B.P["upperarm" + s])
		fore += (B.P["hand" + s] as Vector3).distance_to(B.P["lowerarm" + s])
		hand += (B.E["hand" + s] as Vector3).distance_to(B.P["hand" + s])
	up *= 0.5
	fore *= 0.5
	hand *= 0.5
	var arm := up + fore + hand
	var has := B.wep_on
	var weapon := arm + (B.wep_len if has else 0.0)
	var h := height_of(B)
	var step := STEP_FRAC * h
	return {"upper": up, "fore": fore, "hand": hand, "arm": arm, "weapon": weapon, "has_weapon": has,
		"step": step, "step_in": (weapon if has else arm) + step, "height": h}


## the shoulder line's midpoint, body space
static func shoulder_mid(B: Body) -> Vector3:
	return ((B.P["upperarm_l"] as Vector3) + (B.P["upperarm_r"] as Vector3)) * 0.5


## the horizontal (floor) distance from c to the other fighter's nearest body part, minus that part's radius.
## W carries the body's space into the world. Returns {"gap", "part"}
static func gap_flat(c: Vector3, B: Body, W: Transform3D) -> Dictionary:
	var best := {"gap": INF, "part": ""}
	var p2 := Vector2(c.x, c.z)
	for part in Choreo.body_parts(B):
		var seg: Array = B.cap(part)
		var a: Vector3 = W * (seg[0] as Vector3)
		var b: Vector3 = W * (seg[1] as Vector3)
		var d := _seg2(p2, Vector2(a.x, a.z), Vector2(b.x, b.z)) - float(B.rad[part])
		if d < float(best["gap"]):
			best = {"gap": d, "part": part}
	return best


static func _seg2(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	var t := 0.0 if l2 < 1e-12 else clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## the whole report for the picked fighter (B, its world transform pW) and the others [{"name", "B", "W"}]:
## {"centre" (Vector3 on the floor), "reaches" (see reaches), "rings": [{"name", "r", "inside", "shown"}], "near": {name, part, gap}}
static func report(B: Body, pW: Transform3D, others: Array) -> Dictionary:
	var R := reaches(B)
	var c := pW * shoulder_mid(B)
	c.y = 0.0
	var near := {"name": "", "part": "", "gap": INF}
	for o in others:
		var g := gap_flat(c, o["B"], o["W"])
		if float(g["gap"]) < float(near["gap"]):
			near = {"name": String(o["name"]), "part": String(g["part"]), "gap": float(g["gap"])}
	var rings := [{"name": "arm", "r": R["arm"], "shown": true},
		{"name": "arm + weapon", "r": R["weapon"], "shown": bool(R["has_weapon"])},
		{"name": "step-in", "r": R["step_in"], "shown": true}]
	for ring in rings:
		ring["inside"] = bool(ring["shown"]) and not others.is_empty() and float(near["gap"]) <= float(ring["r"])
	return {"centre": c, "reaches": R, "rings": rings, "near": near}


# ---- the picture ----------------------------------------------------------------------------------------------

## draws the rings and the label, or hides them when off. others = [] hides them too (one fighter: nothing to measure)
func update(B: Body, pW: Transform3D, others: Array) -> void:
	if _mesh == null:
		return
	_mesh.visible = on and not others.is_empty()
	_label.visible = _mesh.visible
	if not _mesh.visible:
		(_mesh.mesh as ImmediateMesh).clear_surfaces()
		return
	last = report(B, pW, others)
	var c: Vector3 = last["centre"]
	var im := _mesh.mesh as ImmediateMesh
	im.clear_surfaces()
	for ring in last["rings"]:
		if not bool(ring["shown"]):
			continue
		var col: Color = Tok.c("warn") if bool(ring["inside"]) else Tok.of("ink:0.4")
		im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for k in N_RING + 1:
			var a := TAU * float(k) / float(N_RING)
			im.surface_set_color(col)
			im.surface_add_vertex(c + Vector3(cos(a) * float(ring["r"]), LIFT, sin(a) * float(ring["r"])))
		im.surface_end()
	var near: Dictionary = last["near"]
	_label.text = "%.2f m to %s" % [float(near["gap"]), near["name"]]
	_label.position = c + Vector3(0, 2.0, 0)
	_label.modulate = Tok.c("warn") if String(near["name"]) != "" and float(near["gap"]) <= float(last["reaches"]["step_in"]) else Tok.of("ink:0.7")
