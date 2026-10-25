## godot --headless --path . -s tests/toes_walk_test.gd     (GATES toes; Nick: "nobody moves foot fingers all the way up to walk")
## THE TOE JOINT (ball_l / ball_r, bend + = toes up) ON A WALK, against real walkers:
##   first MTP (big toe) dorsiflexion peaks at about 40-45 deg at toe-off in walking (Miana 2021; Nawoczenski et al. 1999,
##   about 42 deg); near 0 (+-10) in swing and mid-stance (Perry 1992, Gait Analysis).
## Bars, over every scenes/*walk*.json (read only) and a generated walk (the walk_bat cards re-timed to 0.8x and 1.25x speed):
##   1 the toe bend <= 45 deg at EVERY frame (120 Hz)
##   2 |toe bend| <= 10 deg in swing (the foot more than 2 cm above the floor, measured from its rest height)
## CONTROL (anti-vacuity): the walk_bat walk must have swing frames at all (else bar 2 would pass by emptiness).
extends SceneTree

const MAX_TOE := 45.0    # deg, the first MTP at push-off (real peak 40-45)
const MAX_SWING := 10.0  # deg, |bend| with the foot in the air
const AIR := 0.02        # m: the foot counts as in swing above this height
const HZ := 120.0
const EPS := 1e-3

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## one walk: {"name", "max": most bent toe (deg) over every frame, "max_swing": largest |bend| in swing, "swing_frames"}
func measure(name: String, d: Dictionary) -> Dictionary:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var S := Scene.new()
	S.from_dict(d)
	var mx := -INF
	var mx_swing := 0.0
	var n_swing := 0
	var k := 0
	while k / HZ <= S.length():
		S.apply(B, k / HZ)
		for sd in ["_l", "_r"]:
			var toe: String = "ball" + sd
			var b: float = (B.ang[toe] as Vector3).x
			var lift: float = (B.P[toe] as Vector3).y - (B.p0[toe] as Vector3).y
			mx = maxf(mx, b)
			if lift > AIR:
				n_swing += 1
				mx_swing = maxf(mx_swing, absf(b))
		k += 1
	return {"name": name, "max": mx, "max_swing": mx_swing, "swing_frames": n_swing}


## the walk cards re-timed: every move (and hold) x f, so the same walk at another speed
func retimed(d: Dictionary, f: float) -> Dictionary:
	var out: Dictionary = d.duplicate(true)
	for c in out["cards"]:
		if float(c.get("move", -1.0)) > 0.0:
			c["move"] = float(c["move"]) * f
		c["hold"] = float(c.get("hold", 0.3)) * f
	return out


func check(r: Dictionary) -> void:
	var n: String = r["name"]
	print("     %s: max toe bend %.1f deg over the scene (bar <= %.0f); largest |bend| in swing %.1f deg over %d foot-frames (bar <= %.0f)" % [n, r["max"], MAX_TOE, r["max_swing"], r["swing_frames"], MAX_SWING])
	ok(float(r["max"]) <= MAX_TOE + EPS, "1 %s: the toe bends at most %.1f deg (bar <= %.0f, first MTP peak 40-45 walking, Miana 2021)" % [n, r["max"], MAX_TOE])
	ok(float(r["max_swing"]) <= MAX_SWING + EPS, "2 %s: the toe is within %.1f deg of level in swing (bar <= %.0f, MTP ~0 in swing, Perry)" % [n, r["max_swing"], MAX_SWING])


func _init() -> void:
	var files := []
	for f in DirAccess.get_files_at("res://scenes"):
		if f.contains("walk") and f.ends_with(".json"):
			files.append(f)
	files.sort()
	var base: Dictionary = {}
	for f in files:
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scenes/" + f))
		if base.is_empty():
			base = d
		check(measure(f, d))
	var fast := retimed(base, 0.8)
	var slow := retimed(base, 1.25)
	check(measure("generated walk 0.8x", fast))
	check(measure("generated walk 1.25x", slow))
	# CONTROL: the walk has swing frames, so bar 2 is not passed by emptiness
	var c := measure("control walk_bat", base)
	ok(int(c["swing_frames"]) > 100, "control: walk_bat has %d foot-frames in swing (bar > 100)" % int(c["swing_frames"]))
	print("RESULT toes_walk fails=%d" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
