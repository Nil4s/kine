## red_spots.gd - RED SPOTS ON THE BODY (INNOVATIONS N074): Check's problems glow ON the body part they are about, in the
## 3D view, at the frames they cover. Click the glowing part: the finding's line and its Fix button (the same Fix the
## Check panel has, Fixer.label / main._fix: one undo step).
## CHEAP BY DESIGN: nothing here re-runs Check. set_findings() turns Check's cached list into spots ONCE (main._check calls
## it, also after a Fix re-checks); each refresh only asks which spots cover the playhead (a few comparisons per spot) and
## writes their parts into the skin's look table that main already fills for the pick light (SkinPick.set_looks: one
## small texture, written only when it changed). The weapon is not skinned, so its spot is a soft capsule halo (one mesh).
##
## WHICH FINDINGS GET A PART (part_map(); the rest stay in the Check panel only). Read from the finding's own data first
## (foot / joint fields), then from the words its rule always writes ("the left foot", "the hips turn LATE", ...):
##   FOOT SLIDE, FEASIBLE SLIDE      the foot (and its toes) of the side named           over [t, t1]
##   FIST SPEED                      the hand named                                       around t
##   HEAD QUIET                      the head                                             around t
##   HIPS TURN                       the hips                                             around t
##   SEQUENCE                        the hips (they turn late) or the chest (after the weapon)   around t
##   HITCH                           each part that stutters: weapon tip -> the weapon, hand, hips, head   around t
##   TIP SPEED                       the weapon (its barrel: the tip)                     around t
##   JOINT SPEED                     the joint's moving part (HumanLimits.TURN: knee -> shin, shoulder -> upper arm, trunk -> chest)   [t, t1]
##   JOINT TORQUE                    the shoulder named -> the upper arm                  [t, t1]
##   COUPLED LIMIT                   the joint it names (a body part already)             [t, t1]
##   LOOP SEAM                       the joint / point that pops at the seam              around t (the end)
##   THROUGH A PROP                  the part the message names                           [the run's start, t1]
##   FEASIBLE PENETRATION            both parts of the pair that pass through each other  [t, t1]
##   FLOATS                          the hips                                             [t, t1]
##   CARRY FORM                      both upper arms and forearms                         [t, t1]
##   LIFT FORM                       the lower and middle back                            [t, t1]
## NO PART (whole body or whole clip; the panel only): BALANCE, TIPPING, FEASIBLE (the verdict), FEASIBLE BALANCE,
## FEASIBLE FLIGHT (the centre of mass, not a segment), GAIT, JUMP (the whole stride / flight), STRIKE FRAMES (the
## swing's duration), ASSERT (the line names its own thing; not mapped yet). A bent wrist at impact has no Check rule
## today (Rulebook has none), so nothing to map.
## "AROUND t": a finding at one moment (a peak) glows POINT_HALF either side of it: the realism score's own window for a
## finding (RealismScore.WINDOW = 0.5 s, "about a human reaction time"; ours, not a citation), so the glow and the score
## agree on which frames a finding covers.
## LOOK: MUST FIX = the "fail" token, a look = the "warn" token (Tok; both palettes). FILL / RIM are ours (HEURISTIC):
## between the joint-limit tint (0.28, no rim) and the pick (0.42, full rim), with a rim so it reads as a glow, not a pick.
## The picked part keeps the pick look (main decides; a picked foot shows it is picked) and its spots still open on click.
class_name RedSpots
extends Node3D

const POINT_HALF := RealismScore.WINDOW * 0.5   # s each side of a one-moment finding
const FILL := 0.40
const RIM := 0.7
const HALO_FILL := 0.55   # the weapon halo's strength (additive, so softer than a fill on skin)
const HALO_GROW := 1.8    # x the weapon capsule's radius
const HALO_PAD := 0.012   # m added to that radius (a thin bat still gets a visible glow)
const SECTION := "view"
const KEY := "problems_on_body"

var on := true
var spots := []        # [{"k": index in the findings, "f": finding, "parts": [...], "t0", "t1", "fail": bool}]
var unmapped := []     # the rules of the findings that got no part (the panel only)
var last := {}         # part -> "FAIL" / "WARN": what the last refresh lit (tests read it)
var popup: PanelContainer
var popup_part := ""
var _host: Node        # main (its _fix, ui_root, Fixer's scene)
var _halo := {}        # weapon part -> MeshInstance3D
var _halo_mat: ShaderMaterial

const HALO_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;
uniform vec4 col : source_color;
void fragment() {
	float f = 1.0 - abs(dot(NORMAL, VIEW));
	ALBEDO = col.rgb;
	ALPHA = col.a * (0.25 + 0.75 * f * f);   // soft middle, bright rim: a halo, not a solid tube
}
"""


func setup(host: Node) -> void:
	_host = host
	name = "red_spots"


# ---------------------------------------------------------------- the mapping (pure: the test calls these directly)

## the parts finding f is about ([] = none, the panel only)
static func part_map(f: Dictionary) -> Array:
	var msg := String(f.get("msg", ""))
	var low := msg.to_lower()
	match String(f.get("rule", "")):
		"FOOT SLIDE", "FEASIBLE SLIDE":
			var sd := String(f["foot"]) if f.has("foot") else ("_l" if "the left foot" in low else "_r" if "the right foot" in low else "")
			return [] if sd == "" else ["foot" + sd, "ball" + sd]
		"FIST SPEED":
			return ["hand_l"] if "the left hand" in low else ["hand_r"] if "the right hand" in low else []
		"HEAD QUIET":
			return ["head"]
		"HIPS TURN", "FLOATS":
			return ["pelvis"]
		"SEQUENCE":
			return ["pelvis"] if "hips turn late" in low else ["spine_03"] if "chest turns" in low else []
		"HITCH":
			var out := []
			for w in [["the weapon tip", "bat_barrel"], ["the right hand", "hand_r"], ["the hips", "pelvis"], ["the head", "head"]]:
				if w[0] in low:
					out.append(w[1])
			return out
		"TIP SPEED":
			return ["bat_barrel"]
		"JOINT SPEED", "COUPLED LIMIT", "LOOP SEAM":
			return _joint_part(String(f.get("joint", "")))
		"JOINT TORQUE":
			var j := String(f.get("joint", ""))
			if j == "":
				j = "shoulder_l" if "shoulder l " in low else "shoulder_r" if "shoulder r " in low else ""
			return _joint_part(j)
		"THROUGH A PROP":
			var at := msg.find(": the ")
			var stop := msg.find(" goes ")
			if at < 0 or stop < at:
				return []
			var words := msg.substr(at + 6, stop - at - 6)
			for p in Body.ORDER + Body.WEAPON + Body.WEAPON2:
				if Rulebook.part_words(p) == words:
					return [p]
			return []
		"FEASIBLE PENETRATION":
			var a := msg.find("itself, ")
			if a < 0:
				return []
			var rest := msg.substr(a + 8)   # "hand l|thigh r 25 mm deep (bar 20 mm)."
			var cut := rest.find(" mm deep")
			if cut < 0:
				return []
			var pair := rest.left(cut)
			pair = pair.left(pair.rfind(" "))   # drop the number: "hand l|thigh r"
			var out := []
			for half in pair.split("|"):
				var p := String(half).strip_edges().replace(" ", "_")
				if p in Body.ORDER or p in Body.WEAPON or p in Body.WEAPON2:
					out.append(p)
			return out
		"CARRY FORM":
			return ["upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r"]
		"LIFT FORM":
			return ["spine_01", "spine_02"]
	return []


## a joint name as the human-limit rules write it -> the body part that moves at it
static func _joint_part(j: String) -> Array:
	if j == "":
		return []
	if HumanLimits.TURN.has(j):
		return [HumanLimits.TURN[j][0]]
	if j in Body.ORDER or j in Body.WEAPON or j in Body.WEAPON2:
		return [j]
	return []


## the seconds a finding covers: [t0, t1]. A run of frames: its own start (the message's "a-b s" when the finding's t is
## the run's worst frame, as THROUGH A PROP's is) to t1; one moment: POINT_HALF either side of t
static func span_of(f: Dictionary) -> Vector2:
	var t := float(f.get("t", 0.0))
	if not f.has("t1"):
		return Vector2(maxf(0.0, t - POINT_HALF), t + POINT_HALF)
	var t0 := t
	var head := String(f.get("msg", "")).get_slice(" ", 0)   # "1.00-1.65" (frames ... are written after it)
	if "-" in head and head.get_slice("-", 0).is_valid_float():
		t0 = minf(t0, head.get_slice("-", 0).to_float())
	var t1 := float(f["t1"])
	if t1 - t0 < 1.0 / 60.0:   # a run of one 60 fps frame (a 3.05-3.05 s joint speed): still a moment to see
		return Vector2(maxf(0.0, t0 - POINT_HALF), t1 + POINT_HALF)
	return Vector2(t0, t1)


static func build(findings: Array) -> Dictionary:
	var sp := []
	var none := []
	for k in findings.size():
		var f: Dictionary = findings[k]
		var ps := part_map(f)
		if ps.is_empty():
			if not String(f["rule"]) in none:
				none.append(String(f["rule"]))
			continue
		var s := span_of(f)
		sp.append({"k": k, "f": f, "parts": ps, "t0": s.x, "t1": s.y, "fail": String(f["sev"]) == "FAIL"})
	return {"spots": sp, "unmapped": none}


# ---------------------------------------------------------------- state

## Check ran (or a Fix re-checked): the spots from its list. Nothing else re-reads the findings
func set_findings(findings: Array) -> void:
	var b := build(findings)
	spots = b["spots"]
	unmapped = b["unmapped"]
	hide_popup()


## part -> "FAIL" / "WARN" for the spots covering time t (a part under a MUST FIX and a look is MUST FIX)
func active(t: float) -> Dictionary:
	var out := {}
	if not on:
		return out
	for s in spots:
		if t >= float(s["t0"]) - 1e-6 and t <= float(s["t1"]) + 1e-6:
			for p in s["parts"]:
				if s["fail"] or not out.has(p):
					out[p] = "FAIL" if s["fail"] else "WARN"
	return out


## the spots on part p at time t
func spots_at(p: String, t: float) -> Array:
	return spots.filter(func(s): return p in s["parts"] and t >= float(s["t0"]) - 1e-6 and t <= float(s["t1"]) + 1e-6)


static func look(sev: String) -> Array:
	return [Color(Tok.c("fail" if sev == "FAIL" else "warn"), FILL), RIM]


## one refresh: the skin looks of the lit body parts go into looks (main's table, before SkinPick.set_looks); a part
## main already lit as picked keeps the pick. live: Check is current for this scene (main.check_ran)
func apply(looks: Dictionary, t: float, B: Body, live: bool, keep := {}) -> void:
	last = active(t) if live else {}
	for p in last:
		if p in Body.WEAPON or p in Body.WEAPON2:
			continue
		if keep.has(p):
			continue
		looks[p] = look(last[p])
	for p in Body.WEAPON + Body.WEAPON2:
		var lit: bool = last.has(p) and ((B.wep_on and p in Body.WEAPON) or (B.wep2_on and p in Body.WEAPON2))
		if not lit:
			if _halo.has(p):
				_halo[p].visible = false
			continue
		_place_halo(p, B, last[p])


func _place_halo(p: String, B: Body, sev: String) -> void:
	if _halo_mat == null:
		_halo_mat = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = HALO_SHADER
		_halo_mat.shader = sh
	if not _halo.has(p):
		var mi := MeshInstance3D.new()
		mi.name = "halo_" + p
		mi.mesh = CapsuleMesh.new()
		mi.material_override = _halo_mat.duplicate()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_halo[p] = mi
	var mi: MeshInstance3D = _halo[p]
	var c: Array = B.cap(p)
	var a: Vector3 = c[0]
	var b: Vector3 = c[1]
	var r: float = float(B.rad[p]) * HALO_GROW + HALO_PAD
	var cm: CapsuleMesh = mi.mesh
	cm.radius = r
	cm.height = (b - a).length() + 2.0 * r
	var y := (b - a).normalized() if (b - a).length() > 1e-6 else Vector3.UP
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	mi.transform = Transform3D(Basis(x, y, x.cross(y)), (a + b) * 0.5)
	(mi.material_override as ShaderMaterial).set_shader_parameter("col", Color(Tok.c("fail" if sev == "FAIL" else "warn"), HALO_FILL))
	mi.visible = true


func halo_visible(p: String) -> bool:
	return _halo.has(p) and _halo[p].visible


# ---------------------------------------------------------------- the click

## a press on part p at screen point mp (main's own pick, so the click is exactly the part the pick light shows): if it
## glows now, the finding's line(s) and their Fix buttons open beside the click. The press goes on as usual (a drag)
func press(p: String, mp: Vector2, t: float) -> bool:
	if not on or p == "" or not last.has(p):
		return false
	var here := spots_at(p, t)
	if here.is_empty():
		return false
	_show_popup(p, here, mp)
	return true


func _show_popup(p: String, here: Array, mp: Vector2) -> void:
	hide_popup()
	popup = PanelContainer.new()
	popup.name = "redspot_popup"
	popup_part = p
	var v := VBoxContainer.new()
	popup.add_child(v)
	var head := Label.new()
	head.text = "%s: %d problem%s here" % [Rulebook.part_words(p), here.size(), "" if here.size() == 1 else "s"]
	head.add_theme_color_override("font_color", Tok.c("text"))
	head.add_theme_font_size_override("font_size", 14)
	v.add_child(head)
	var S: Scene = _host.S if _host != null else null
	for s in here:
		var f: Dictionary = s["f"]
		var l := Label.new()
		l.name = "redspot_line_%d" % (int(s["k"]) + 1)
		l.text = "%s  %s  %.2f s  -  %s" % ["MUST FIX" if s["fail"] else "look", f["rule"], f["t"], String(f["msg"]).get_slice("\n", 0)]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(360, 0)
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", Tok.c("fail" if s["fail"] else "warn"))
		v.add_child(l)
		var lbl := Fixer.label(f, S) if S != null else ""
		if lbl != "":
			var b := Button.new()
			b.name = "redspot_fix_%d" % (int(s["k"]) + 1)   # the same number as the Check panel's fix_N
			b.text = lbl
			b.focus_mode = Control.FOCUS_NONE
			b.pressed.connect(_fix.bind(f))
			v.add_child(b)
		else:
			var n := Label.new()
			n.text = "   no automatic fix (the Check panel says why)"
			n.add_theme_font_size_override("font_size", 12)
			n.add_theme_color_override("font_color", Tok.c("text"))
			v.add_child(n)
	var cl := Button.new()
	cl.name = "redspot_close"
	cl.text = "Close"
	cl.focus_mode = Control.FOCUS_NONE
	cl.pressed.connect(hide_popup)
	v.add_child(cl)
	var parent: Control = _host.ui_root if _host != null and _host.get("ui_root") != null else null
	if parent == null:
		return
	parent.add_child(popup)
	popup.reset_size()
	var vs := parent.get_viewport_rect().size
	popup.position = Vector2(clampf(mp.x + 16.0, 0.0, maxf(0.0, vs.x - popup.size.x)), clampf(mp.y + 16.0, 0.0, maxf(0.0, vs.y - popup.size.y)))


func _fix(f: Dictionary) -> void:
	hide_popup()
	if _host != null:
		_host._fix(f)   # Check's own Fix: one undo step, then main re-checks (set_findings follows)


func hide_popup() -> void:
	if popup != null and is_instance_valid(popup):
		popup.queue_free()
		if popup.get_parent() != null:
			popup.get_parent().remove_child(popup)
	popup = null
	popup_part = ""


# ---------------------------------------------------------------- the setting

func load_from(path: String) -> void:
	var cf := ConfigFile.new()
	if cf.load(path) == OK:
		on = bool(cf.get_value(SECTION, KEY, true))


func set_on(v: bool, path: String) -> void:
	on = v
	if not on:
		hide_popup()
	var cf := ConfigFile.new()
	cf.load(path)
	cf.set_value(SECTION, KEY, v)
	cf.save(path)
