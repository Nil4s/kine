extends SceneTree
## L5 round 2, item 4: ONE gate-lift experiment on the Martin & Moyce dam break (coordinator, 11-06). Information only: it does not change any bar.
##   instant : the column is released at once (what CH8 (c)/(h) and liq2 (M) do): the reference arm of the experiment.
##   gate    : a gate one cell thick at the column's right face is pulled up at GATE_V m/s as a cut-cell moving wall (clear_cut + add_cut_box each step).
## GATE_V = 1.5 m/s is an ASSUMED lift speed: no speed is cited in the verified notes of docs/CH8_REFERENCE.md (the paper gives a lift by a falling weight).
## The result is therefore a bound on how much a finite gate can move the front, not a fit. The comparison is the same 14 verified Table 2 points.
## Run: godot --path . -s tools/liq2_gate_probe.gd

const G := 9.81
const GATE_V := 1.5


func _front(F: Object, h: float, a: float) -> float:
	var xf := 0.0   # the same front definition as tests/liq2_test.gd _front
	for p in F.positions():
		if p.y < h + 0.15 * a:
			xf = maxf(xf, p.x)
	return (xf - h) / a


func _run(mode: String) -> float:
	var T := [0.41, 0.84, 1.19, 1.43, 1.63, 1.83, 1.98, 2.20, 2.32, 2.51, 2.65, 2.83, 2.97, 3.11]
	var Z := [1.11, 1.22, 1.44, 1.67, 1.89, 2.11, 2.33, 2.56, 2.78, 3.00, 3.22, 3.44, 3.67, 3.89]
	var F = Fluid.make()
	F.set_threads(4)
	var sc: Dictionary = FluidScenes.dam_break_mm(F, 20, "mm")
	var a: float = sc["a"]
	var h: float = sc["h"]
	var res := 20
	var xg := (res + 1) * h
	var top := (3 * res + 1) * h
	var tscale := sqrt(a / (2.0 * G))
	var t := 0.0
	var worst := 0.0
	var line := []
	var dt := 0.002
	for i in T.size():
		var tend: float = T[i] * tscale
		while t < tend - 1e-9:
			var d := minf(dt, tend - t)
			if mode == "gate":
				var y0 := GATE_V * t
				F.clear_cut()
				if y0 < top:
					F.add_cut_box(Vector3(xg, y0, 0.0), Vector3(xg + h, top + h, 10.0 * h))
			F.advance(d)
			t += d
		var z := _front(F, h, a)
		var e: float = absf(z - Z[i]) / Z[i]
		worst = maxf(worst, e)
		line.append("%.2f:%.2f" % [T[i], z])
	print("GATE ", mode, " v=", GATE_V if mode == "gate" else INF, " worst ", worst, "  Z(T) ", " ".join(line))
	return worst


func _init() -> void:
	await process_frame
	_run("instant")
	_run("gate")
	quit(0)
