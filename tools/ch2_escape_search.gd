extends SceneTree
func run(C, T: float, secs: float) -> Dictionary:
	var k: float = ClockCH2.dims["k"]
	var th := -1.0
	var a0 := ClockCH2.AMP * k
	var found := false
	for i in 480:
		var t := -TAU/30.0 * i/480.0
		if C.esc_overlap(t, a0) < 1e-9:
			th = t; found = true; break
	if not found: return {"ok": false}
	var dt := 1.0/240.0
	var ovl := 0
	var th0 := th
	for i in int(secs/dt):
		var alpha := k * ClockCH2.AMP * cos(TAU*i*dt/T)
		if C.esc_overlap(th, alpha) > 1e-6: ovl += 1
		th = C.wheel_drop(th, alpha, deg_to_rad(2.0))
	return {"ok": true, "ovl": ovl, "adv": rad_to_deg(th0 - th)}
func _init():
	var C := ClockCH2.new()
	var T := 2.0006
	for k in [1.6, 2.4]:
		for rho in [39.6, 40.0]:
			for al in [-1.0, -0.5, 0.0, 0.5, 1.0]:
				for ar in [-1.0, -0.5, 0.0, 0.5, 1.0]:
					var am := deg_to_rad(2.5 * k + 1.5)
					ClockCH2.dims = {"D": ClockCH2.ESC_R * sqrt(2.0), "rho": rho, "thick": 6.0, "l_lo": -am, "l_hi": -deg_to_rad(al), "r_lo": -deg_to_rad(ar), "r_hi": am, "k": k}
					var r := run(C, T, 4.0)
					if true:
						print("R k ", k, " rho ", rho, " al ", al, " ar ", ar, " ", r)
	print("done")
	quit()
