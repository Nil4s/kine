extends SceneTree
## TWO HANDS -> ONE -> TWO in a video import (Nick 10-20: "moves the char holds with 2 hands, then 1 hand, then back to 2").
## The fixture: a generated sledgehammer strike (tests/fixtures/gen_hammer_pose.json, Wan 2.1 -> MediaPipe), both hands on
## the handle all clip, imported holding a bat (84 cm). Edited copy: from 1.5 s to 3.0 s the left arm is thrown straight out
## to the side at shoulder height (a one-handed swing's free arm), then goes back to the handle as tracked. The import lets
## go only when the wrists are further apart than the weapon is long (a let-go inside that is G on the card: one camera
## without the fingers cannot tell it from a hand sliding on the shaft).
##   1 the untouched clip stays two-handed on every card (no false let-go)
##   2 the edited clip: two hands before 1.5 s, one hand inside 1.75..2.75 s, two hands again after 3.25 s (the switch
##     waits GRIP_SWITCH_S, and a card blend is two-handed only when both its cards are)
##   3 one-handed: the left hand follows the tracker (out at the side, over 20 cm off the shaft), not glued to the weapon
const FIX := "res://tests/fixtures/gen_hammer_pose.json"
var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	return b


## the two-handed state per 0.25 s, sampled from the scene
func grips(S: Scene, B: Body) -> Array:
	var out := []
	var t := 0.0
	while t <= S.length() + 1e-6:
		S.apply(B, t)
		out.append([t, B.wep_on and B.grip])
		t += 0.25
	return out


func _init() -> void:
	# the clip's sledge is held right hand BELOW (a sledge hold); the bat's book grip is a batter's, right hand on top:
	# the clip's own order is said here (VideoImport.bat_on_top), as an importer would
	VideoImport.bat_on_top = 0
	var P := VideoImport.load_file(FIX)
	ok(P["ok"], "the fixture loads (%d frames)" % (P["frames"] as Array).size())
	var R := VideoIQ.process(body(), P, "metal_bat", "grip_a")
	var S: Scene = R["scene"]
	var g1 := grips(S, body())
	var all_two := true
	for g in g1:
		all_two = all_two and bool(g[1])
	ok(all_two, "(1) the two-handed clip stays two-handed at all %d samples" % g1.size())

	# the edit: the left arm hangs at the side from 1.5 s to 3.0 s (MediaPipe's layout: y down, metres, hips at 0)
	var Q := VideoImport.load_file(FIX)
	var hang := {}
	for f in Q["frames"]:
		var t := float(f["t"])
		if t < 1.5 or t >= 3.0:
			continue
		var w: Array = f["w"]
		var sh: Vector3 = w[11]
		var out := signf(sh.x - (w[12] as Vector3).x)
		w[13] = sh + Vector3(out * 0.28, 0.0, 0.0)
		w[15] = sh + Vector3(out * 0.55, 0.0, 0.0)
		for k in [17, 19, 21]:
			w[k] = sh + Vector3(out * 0.63, 0.0, 0.02)
		hang[snappedf(t, 0.001)] = w[15]
	var R2 := VideoIQ.process(body(), Q, "metal_bat", "grip_b")
	var S2: Scene = R2["scene"]
	var g2 := grips(S2, body())
	var row := ""
	var before := true
	var mid := true
	var after := true
	for g in g2:
		var t := float(g[0])
		row += "%s" % ("2" if g[1] else "1")
		if t < 1.5 - 1e-6:
			before = before and bool(g[1])
		elif t >= 1.75 and t <= 2.75:
			mid = mid and not bool(g[1])
		elif t >= 3.25:
			after = after and bool(g[1])
	ok(before and mid and after, "(2) two hands, then one, then two again: %s (per 0.25 s from 0)" % row)

	# (3) one-handed: the left hand off the shaft, hanging low at the side (not glued to the weapon)
	var B := body()
	var near := 1.0
	var n := 0
	var low := 0
	for t in hang:
		if t < 1.75 or t > 2.75:
			continue
		S2.apply(B, t)
		var x := B.wep_xform()
		var k: Vector3 = x[0]
		var ax: Vector3 = (x[1] as Quaternion) * Vector3.UP
		var lw: Vector3 = B.P["hand_l"]
		var u := clampf((lw - k).dot(ax), 0.0, B.wep_len)
		near = minf(near, lw.distance_to(k + ax * u))
		if absf(lw.y - (B.P["upperarm_l"] as Vector3).y) < 0.25:
			low += 1
		n += 1
	ok(n > 5 and near > 0.20 and low == n, "(3) one-handed: the left hand at least %.0f cm off the shaft and out at shoulder height at %d of %d frames" % [near * 100.0, low, n])
	print("GRIP SWITCH ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)
