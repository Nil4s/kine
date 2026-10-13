extends SceneTree
## ATTACK TIMING vs docs/ATTACK_RULES.md (Nick 10-13: learn what makes moves fast and impactful). Plays each scene at
## 60 fps, takes the weapon TIP's speed per frame; the STRIKE = the frames around the fastest one while the tip moves at
## more than half that peak; ANTICIPATION = from the start to the strike, RECOVERY = from the strike to the end. Prints
## them (s, and the strike in 30 fps frames) and grades each against the weapon's row of the rules.
##   godot --headless --path . -s tools/attack_timing.gd -- [scenes/a.json ...]      (no args: every scenes/*.json)
## --retime: also write scenes/_wip/<name>_timed.json, TIMES ONLY (poses untouched): a strike faster than a real tip
## gets a longer move in proportion; a recovery past the rule is scaled down to the middle of the weapon's range.

## kind -> [anticipation lo, hi], [strike frames at 30 fps hi], [recovery lo, hi]   (ATTACK_RULES.md, "Weapons")
const RULES := {
	"knife": [[0.1, 0.2], 4, [0.15, 0.25]],
	"metal_bat": [[0.25, 0.35], 6, [0.25, 0.4]],
	"hammer": [[0.4, 0.6], 6, [0.5, 0.8]],
	"staff": [[0.25, 0.4], 6, [0.3, 0.5]],
	"spear": [[0.2, 0.3], 4, [0.25, 0.4]],
}
## the fastest a real tip goes (m/s): a pro bat ~40, a staff end ~30 (2x the hands' ~15), a knife ~15 (the hand)
const TIP_MAX := {"knife": 15.0, "metal_bat": 40.0, "hammer": 30.0, "staff": 30.0, "spear": 20.0}
const FPS := 60.0
var retime := false
const NOT_ATTACKS := ["idle_bat", "walk_bat", "dodge_side", "hit_react"]   ## no strike in them: skipped


func _init() -> void:
	var files := Array(OS.get_cmdline_user_args())
	retime = files.has("--retime")
	files = files.filter(func(f): return not String(f).begins_with("--"))
	if files.is_empty():
		for f in DirAccess.get_files_at("res://scenes"):
			if f.ends_with(".json"):
				files.append("scenes/" + f)
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	for f in files:
		_one(B, String(f))
	quit()


func _one(B: Body, path: String, again := false) -> void:
	if path.get_file().get_basename() in NOT_ATTACKS:
		return
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://" + path)))
	S.apply(B, 0.0)
	if not B.wep_on:
		print("%-24s no weapon" % path.get_file())
		return
	var n := int(S.length() * FPS) + 1
	var tips := []
	for i in n:
		S.apply(B, minf(i / FPS, S.length()))
		tips.append(B.wep_point(B.wep_len))
	var sp := [0.0]
	for i in range(1, n):
		sp.append(((tips[i] as Vector3) - (tips[i - 1] as Vector3)).length() * FPS)
	# POPS: a frame far faster than both neighbours is the weapon jumping, not swinging (reported, then smoothed out)
	var pops := []
	for i in range(1, n - 1):
		if sp[i] > 3.0 * maxf(sp[i - 1], sp[i + 1]) and sp[i] > 8.0:
			pops.append("%.2f s (%.0f m/s)" % [i / FPS, sp[i]])
			sp[i] = maxf(sp[i - 1], sp[i + 1])
	var raw := sp.duplicate()
	for i in n:   # ~80 ms average: the swing, not a frame's jitter
		var acc := 0.0
		var c := 0
		for j in range(maxi(0, i - 2), mini(n, i + 3)):
			acc += raw[j]
			c += 1
		sp[i] = acc / c
	var pk := 0
	for i in n:
		if sp[i] > sp[pk]:
			pk = i
	var a := pk
	while a > 0 and sp[a - 1] > sp[pk] * 0.5:
		a -= 1
	var b := pk
	while b < n - 1 and sp[b + 1] > sp[pk] * 0.5:
		b += 1
	var st := 0   # the move starts when the tip first moves (the guard hold before it is not the wind-up)
	while st < a and sp[st] < 0.5:
		st += 1
	var ant := (a - st) / FPS
	var strike := (b - a + 1) / FPS
	var rec := (n - 1 - b) / FPS
	var r: Array = RULES.get(B.wep_kind, RULES["metal_bat"])
	var notes := []
	if ant < r[0][0]:
		notes.append("wind-up short")
	elif ant > r[0][1]:
		notes.append("wind-up long (input lag)")
	if strike * 30.0 > float(r[1]) + 0.5:
		notes.append("swing slow (%.0f fr > %d)" % [strike * 30.0, r[1]])
	if rec < r[2][0]:
		notes.append("recovery short (no weight)")
	elif rec > r[2][1]:
		notes.append("recovery long (sticky)")
	var cap: float = TIP_MAX.get(B.wep_kind, 40.0)
	if sp[pk] > cap:
		notes.append("TOO FAST: tip %.0f m/s > %.0f real (the strike card's move time too short for its arc)" % [sp[pk], cap])
	if not pops.is_empty():
		notes.append("POPS at " + ", ".join(pops))
	if again:
		path = "  -> " + path.get_file()
	print("%-24s %-9s wind-up %.2f s | strike %.2f s = %2.0f fr @30 (tip %.1f m/s) | recovery %.2f s  %s" % [path.get_file(),
		B.wep_kind, ant, strike, strike * 30.0, sp[pk], rec, "OK" if notes.is_empty() else ", ".join(notes)])

	if retime and not again:
		# measure -> fix -> measure, at most 6 rounds: the fastest card back under the real cap; the recovery cards after
		# the STRIKE card scaled toward the rule, but never so short that one of them out-runs the strike (a follow-through
		# faster than the hit would become the "strike" itself)
		var ks0 := S.span(pk / FPS)
		if ks0 < 0:
			return
		var rec_cards := {}
		for i in range(ks0 + 1, S.cards.size()):
			rec_cards[i] = [S.move_time(i), float(S.cards[i]["hold"])]
		var f: float = minf(1.0, (r[2][0] + r[2][1]) * 0.5 / maxf(rec, 0.01))
		for round in 6:
			for i in rec_cards:
				S.cards[i]["move"] = snappedf(maxf(rec_cards[i][0] * f, 0.08), 0.01)
				S.cards[i]["hold"] = snappedf(rec_cards[i][1] * f, 0.01)
			var m := _measure(S, B)
			var ksn := S.span(float(m["peak_t"]))
			if float(m["peak"]) > cap and ksn >= 0 and ksn <= ks0:   # the strike (or a spin before it) too fast
				S.cards[ksn]["move"] = snappedf(S.move_time(ksn) * float(m["peak"]) / cap * 0.95, 0.01)
			elif ksn > ks0:   # a recovery card became the fastest: give the recovery back some time
				f = minf(1.0, f * 1.3)
			else:
				break
		var out := "scenes/_wip/%s_timed.json" % path.get_file().get_basename()
		var d := S.to_dict(B)
		d["note"] = "TIMES ONLY retime of %s by tools/attack_timing.gd --retime (docs/ATTACK_RULES.md); poses untouched" % path
		FileAccess.open("res://" + out, FileAccess.WRITE).store_string(JSON.stringify(d, " "))
		_one(B, out, true)


## the tip's smoothed peak speed and when (pops flattened), for the retime loop
func _measure(S: Scene, B: Body) -> Dictionary:
	var n := int(S.length() * FPS) + 1
	var tips := []
	for i in n:
		S.apply(B, minf(i / FPS, S.length()))
		tips.append(B.wep_point(B.wep_len))
	var raw := [0.0]
	for i in range(1, n):
		raw.append(((tips[i] as Vector3) - (tips[i - 1] as Vector3)).length() * FPS)
	for i in range(1, n - 1):
		if raw[i] > 3.0 * maxf(raw[i - 1], raw[i + 1]) and raw[i] > 8.0:
			raw[i] = maxf(raw[i - 1], raw[i + 1])
	var best := 0.0
	var bt := 0.0
	for i in n:
		var acc := 0.0
		var c := 0
		for j in range(maxi(0, i - 2), mini(n, i + 3)):
			acc += raw[j]
			c += 1
		if acc / c > best:
			best = acc / c
			bt = i / FPS
	return {"peak": best, "peak_t": bt}
