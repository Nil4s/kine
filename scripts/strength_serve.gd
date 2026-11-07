## strength_serve.gd - SERVE sway_trace, stance_map, strength_curve (agent_tools.gd; CLI, MCP and the AI box share it) (N037, N038, N039).
##  sway_trace {seed?, seconds? (30), hz? (10), on?: bool}: the quiet-standing sway of a seed as (ml_mm, ap_mm) with rms and dominant band; "on" (with seed) turns the
##    scene's real sway on or off = ONE undo step. Without "on" it only reads.
##  stance_map {}: the playhead pose's push map: per direction (deg from facing, 0 forward, 90 left) the impulse N s, speed m/s, force N, edge cm. Read only.
##  strength_curve {joint?, angle?, on?: bool}: the cap of a joint at an angle (the whole curve table when no angle); "on" turns the scene's strength curves on or off = ONE undo step.
class_name StrengthServe
extends RefCounted


static func serve(op: String, m: Node, p: Dictionary) -> Dictionary:
	match op:
		"sway_trace":
			var sd := int(p.get("seed", (m.S as Scene).sway_seed))
			var secs := clampf(float(p.get("seconds", 30.0)), 1.0, 600.0)
			var hz := clampf(float(p.get("hz", 10.0)), 1.0, 100.0)
			if p.has("on"):
				m._set_strength("sway", bool(p["on"]), int(p.get("seed", -1)))
			var tr := Sway.trace(sd, secs, hz)
			var sa := 0.0
			var sm := 0.0
			for v in tr:
				sa += (v as Vector2).y * (v as Vector2).y
				sm += (v as Vector2).x * (v as Vector2).x
			var n := maxf(tr.size(), 1)
			var out := {"seed": sd, "seconds": secs, "hz": hz, "rms_ap_mm": sqrt(sa / n), "rms_ml_mm": sqrt(sm / n), "band_hz": [Sway.BAND_LO, Sway.BAND_HI],
				"target_ap_mm": Sway.RMS_AP_MM, "target_ml_mm": Sway.RMS_ML_MM, "sway_on": (m.S as Scene).sway, "samples": tr.slice(0, 200).map(func(v): return [snappedf((v as Vector2).x, 0.001), snappedf((v as Vector2).y, 0.001)])}
			return {"ok": true, "result": out}
		"stance_map":
			var B := DistanceKeeper.new_body()
			(m.S as Scene).apply(B, float(m.playhead))
			var mp := StanceMap.compute(B)
			if not bool(mp["ok"]):
				return {"ok": false, "error": String(mp["why"])}
			var rows := []
			for k in (mp["dirs"] as Array).size():
				rows.append({"deg": mp["dirs"][k], "impulse_ns": snappedf(float(mp["impulse"][k]), 0.01), "speed_ms": snappedf(float(mp["speed"][k]), 0.001),
					"force_n": snappedf(float(mp["force"][k]), 0.1), "edge_cm": snappedf(float(mp["edge"][k]) * 100.0, 0.1)})
			return {"ok": true, "result": {"mass_kg": mp["mass"], "omega0": mp["w0"], "feet_down": mp["legs"], "push_s": StanceMap.PUSH_T, "lowest_ns": StanceMap.lowest(mp),
				"highest_ns": StanceMap.highest(mp), "mean_ns": StanceMap.mean(mp), "dirs": rows}}
		"strength_curve":
			if p.has("on"):
				m._set_strength("curves", bool(p["on"]))
			var mass := HumanLimits.mass_of(m.B)
			var j := String(p.get("joint", "calf_l"))
			if not StrengthCurves.has_curve(j):
				return {"ok": false, "error": "no torque-angle curve for '%s': it has the knee (calf_l / calf_r) and the elbow (lowerarm_l / lowerarm_r); the other joints keep one constant cap" % j}
			var out2 := {"joint": j, "mass_kg": mass, "peak_deg": StrengthCurves.TABLE[ForceView.kind_of(j)]["peak"], "peak_nm": ForceView.limit_nm(j, mass), "curves_on": (m.S as Scene).strength_curves}
			if p.has("angle"):
				var a := float(p["angle"])
				out2["angle"] = a
				out2["fraction"] = StrengthCurves.factor(j, a)
				out2["cap_nm"] = StrengthCurves.cap_nm(j, mass, a)
			else:
				out2["points"] = StrengthCurves.TABLE[ForceView.kind_of(j)]["pts"]
			return {"ok": true, "result": out2}
	return {"ok": false, "error": "unknown strength tool " + op}
