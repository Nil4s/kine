## godot --headless --path . -s tests/breakdowner_test.gd     (GATES XX4; headless is fine)
## BREAKDOWNER + PASTE FLIPPED options. Bars: factor 0.5 = the slerp midpoint of the neighbours (checked against an
## independent axis-angle slerp) to 1e-4 deg on every joint; 0 = the card before, 1 = the card after; selected-only
## leaves unselected joints bit for bit; overshoot goes past the neighbour; paste flipped at factor 1, all parts =
## Body.pose_paste exactly; factor 0 changes nothing; a scene without the feature is untouched (cards not edited).
extends SceneTree

var fails := 0
var n_ok := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if c:
		n_ok += 1
	else:
		fails += 1


func body() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	return B


func posed(vals: Dictionary) -> Dictionary:
	var B := body()
	for j in vals:
		B.set_ang(j, vals[j])
	B.fk()
	return B.to_dict()


## degrees between the rotations of two angle triples of joint j
func gap(B: Body, j: String, a: Vector3, b: Vector3) -> float:
	return qgap(B.compose(j, a), B.compose(j, b))


## independent slerp: a * axis-angle(a^-1 b) scaled by f
func ref(B: Body, j: String, a: Vector3, b: Vector3, f: float) -> Quaternion:
	var qa := B.compose(j, a)
	var d := qa.inverse() * B.compose(j, b)
	if d.w < 0.0:
		d = Quaternion(-d.x, -d.y, -d.z, -d.w)
	var ang := 2.0 * acos(clampf(d.w, -1.0, 1.0))
	if ang < 1e-9:
		return qa
	var ax := Vector3(d.x, d.y, d.z).normalized()
	return qa * Quaternion(ax, ang * f)


func qgap(p: Quaternion, q: Quaternion) -> float:
	var d := p.inverse() * q   # atan2, not acos: acos loses 0.04 deg of float noise near the identity
	return rad_to_deg(2.0 * atan2(Vector3(d.x, d.y, d.z).length(), absf(d.w)))


func _init() -> void:
	var B := body()
	var S := Scene.new()
	S.name = "zz_breakdowner"
	S.add("a", posed({"thigh_l": Vector3(10, 0, 0), "calf_l": Vector3(20, 0, 0), "upperarm_r": Vector3(-30, 10, 5), "spine_01": Vector3(5, 3, 2), "head": Vector3(-5, 8, 4)}))
	S.add("mid", posed({"thigh_l": Vector3(30, 0, 0)}))
	S.add("c", posed({"thigh_l": Vector3(60, 5, 0), "calf_l": Vector3(70, 0, 0), "upperarm_r": Vector3(40, -20, 25), "spine_01": Vector3(-8, 10, 6), "head": Vector3(10, -12, 9)}))
	var A: Dictionary = Moves._flat(S.cards[0]["pose"])["ang"]
	var C: Dictionary = Moves._flat(S.cards[2]["pose"])["ang"]
	ok(Breakdowner.refuse(S, 0) != "" and Breakdowner.refuse(S, 2) != "" and Breakdowner.refuse(S, 1) == "", "first and last cards refuse, the middle one runs")
	var js := ["thigh_l", "calf_l", "upperarm_r", "spine_01", "head", "pelvis", "hand_r"]
	# 0.5: slerp midpoint on every joint
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var r := Breakdowner.run(B, S, 1, 0.5, [])
	var worst := 0.0
	for j in B.ang:
		worst = maxf(worst, qgap(B.compose(j, B.ang[j]), ref(B, j, A[j], C[j], 0.5)))
	print("BAR 0.5: worst joint gap to the independent slerp midpoint %.6f deg (bar 1e-4), %d joints moved, stopped %d" % [worst, r["n"], r["stopped"].size()])
	ok(r["ok"] and worst < 1e-4, "factor 0.5 = slerp midpoint on all %d joints (%.6f deg)" % [B.ang.size(), worst])
	# 0 and 1
	var w0 := 0.0
	var w1 := 0.0
	Breakdowner.run(B, S, 1, 0.0, [])
	for j in B.ang:
		w0 = maxf(w0, gap(B, j, B.ang[j], A[j]))
	Breakdowner.run(B, S, 1, 1.0, [])
	for j in B.ang:
		w1 = maxf(w1, gap(B, j, B.ang[j], C[j]))
	print("BAR 0/1: worst gap to the card before %.6f deg, to the card after %.6f deg (bar 1e-4)" % [w0, w1])
	ok(w0 < 1e-4, "factor 0 = the card before (%.6f deg)" % w0)
	ok(w1 < 1e-4, "factor 1 = the card after (%.6f deg)" % w1)
	# overshoot
	Breakdowner.run(B, S, 1, 1.5, [])
	var over: float = gap(B, "thigh_l", B.ang["thigh_l"], C["thigh_l"])
	var span: float = gap(B, "thigh_l", A["thigh_l"], C["thigh_l"])
	print("OVERSHOOT 1.5: thigh_l is %.2f deg past the card after; the span is %.2f deg (want ~%.2f unless a limit stops it)" % [over, span, span * 0.5])
	ok(over > 1.0, "factor 1.5 goes past the card after (%.2f deg past)" % over)
	var rc := Breakdowner.run(B, S, 1, 9.0, [])
	var cl: float = gap(B, "thigh_l", B.ang["thigh_l"], B.clamp_ang("thigh_l", B.decompose("thigh_l", ref(B, "thigh_l", A["thigh_l"], C["thigh_l"], 1.5))))
	ok(cl < 1e-3, "factor 9 is held to 1.5 (%.6f deg from the 1.5 result)" % cl)
	ok(String(Breakdowner.describe(1.5, rc, "x")).contains("overshoot"), "the status line says overshoot")
	# selected only
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.set_ang("hand_r", Vector3(7, 0, 0))
	B.set_ang("calf_r", Vector3(33, 0, 0))
	var snap := {}
	for j in B.ang:
		snap[j] = B.ang[j]
	Breakdowner.run(B, S, 1, 0.5, ["thigh_l", "head"])
	var same := true
	var moved := 0
	for j in B.ang:
		if j in ["thigh_l", "head"]:
			if B.ang[j] != snap[j]:
				moved += 1
		elif B.ang[j] != snap[j]:
			same = false
	ok(same and moved == 2, "selected only: %d selected joints moved, every other joint bit-identical" % moved)
	# PASTE FLIPPED
	var src := body()
	src.set_ang("upperarm_l", Vector3(-40, 15, 10))
	src.set_ang("thigh_r", Vector3(45, 4, 0))
	src.set_ang("spine_02", Vector3(10, 6, 3))
	src.offset = Vector3(0.1, 0, 0.2)
	var clip := src.pose_copy()
	var X := body()
	X.set_ang("calf_l", Vector3(15, 0, 0))
	var Y := body()
	Y.set_ang("calf_l", Vector3(15, 0, 0))
	X.pose_paste(clip, true, [])
	Breakdowner.paste(Y, clip, true, [], 1.0)
	var eq := Y.offset == X.offset
	for j in X.ang:
		eq = eq and X.ang[j] == Y.ang[j]
	ok(eq, "paste flipped, factor 1, all parts = Body.pose_paste mirrored exactly (offset too)")
	var Z := body()
	Z.set_ang("calf_l", Vector3(15, 0, 0))
	Z.set_ang("head", Vector3(3, 4, 5))
	var z0 := {}
	for j in Z.ang:
		z0[j] = Z.ang[j]
	var off0 := Z.offset
	var nz := Breakdowner.paste(Z, clip, true, [], 0.0)
	var unchanged := nz == 0 and Z.offset == off0
	for j in Z.ang:
		unchanged = unchanged and Z.ang[j] == z0[j]
	ok(unchanged, "paste flipped, factor 0 changes nothing (%d joints moved)" % nz)
	# selected-only paste
	var P := body()
	P.set_ang("calf_l", Vector3(15, 0, 0))
	var p0 := {}
	for j in P.ang:
		p0[j] = P.ang[j]
	var np := Breakdowner.paste(P, clip, true, ["upperarm_r", "thigh_l"], 1.0)
	var untouched := true
	for j in P.ang:
		if not j in ["upperarm_r", "thigh_l"] and P.ang[j] != p0[j]:
			untouched = false
	var Xs := body()
	Xs.pose_paste(clip, true, ["upperarm_r", "thigh_l"])
	ok(untouched and P.ang["upperarm_r"] == Xs.ang["upperarm_r"] and np == 2, "paste flipped selected only: 2 joints moved (%d), the rest bit-identical, same as pose_paste with that list" % np)
	# half-way paste: slerp midpoint between now and flipped
	var H := body()
	H.set_ang("upperarm_r", Vector3(10, 0, 0))
	var h0: Vector3 = H.ang["upperarm_r"]
	Breakdowner.paste(H, clip, true, [], 0.5)
	var full := body()
	full.set_ang("upperarm_r", Vector3(10, 0, 0))
	full.pose_paste(clip, true, [])
	var hw := qgap(H.compose("upperarm_r", H.ang["upperarm_r"]), ref(H, "upperarm_r", h0, full.ang["upperarm_r"], 0.5))
	print("PASTE 0.5: upperarm_r from %s toward %s gives %s; gap to the independent midpoint %.6f deg" % [h0, full.ang["upperarm_r"], H.ang["upperarm_r"], hw])
	ok(hw < 1e-3, "paste flipped 50%% = the slerp midpoint of now and flipped (%.6f deg)" % hw)
	print("BREAKDOWNER TEST %s %d (ok %d)" % ["PASS" if fails == 0 else "FAIL", fails, n_ok])
	quit(fails)
