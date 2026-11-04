extends SceneTree
## godot --headless --path . -s tests/ch10_period_test.gd   (CH10 bar c, moved out of tests/ch10_test.gd on 2026-11-03 as an OPEN FINDING; the band is exactly as registered)
## Bar c: the longest of the first x-sway and z-sway periods of the CH1 house lies within [0.5 Ta, 1.7 Ta], Ta = 0.02 hn^0.75, hn = 12.96 ft (ridge): band 0.0683 .. 0.2322 s.
## Why it is open: the model reads 0.2898 s (sheathing only) and 0.2841 s with the gypsum skin added (SDPWS 2015 Table 4.3C, Ga 5.5 kips/in, interior face, sheathed segments only).
##   Both exceed 1.7 Ta = 0.232 s, and also ASCE 7-16 12.8.2's analytical upper limit Cu Ta: Table 12.8-1 Cu 1.6 (SD1 0.133 g) to 1.7 (SD1 <= 0.1 g; the house's SDC B means SD1 < 0.133 g;
##   SD1 itself is not looked up, UNVERIFIED SITE) -> Cu Ta = 0.219 .. 0.232 s. The period is too long, so the model is too soft or too heavy: Ga 11 kips/in is the house_check row (7/16 OSB, 6d common,
##   6 in edges; docs/CH10_REFERENCE.md section 8) and not a choice; corner returns can shorten the period by at most ~4 pct (the chord term is 8 pct of the wall shear term); gypsum on the walls
##   shortened it by 2 pct; partitions, strips above and below windows, hold-down slip (which lengthens it) and the 19 psf lumped mass are the remaining unmodelled terms. The bar is NOT loosened:
##   it stays registered and failing here until the model is made stiffer from a source, or the reading of the bar is changed by the lead.
## The test is registered in tools/run_all.sh as an open finding (it is expected to fail); it does not belong in the gate.
const HO := preload("res://scripts/build/ch10_house.gd")
const SIM := preload("res://scripts/build/ch10_sim.gd")
const FR := preload("res://scripts/build/ch10_frame.gd")
var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func period(opts: Dictionary, dir: int) -> float:
	var mj = JSON.parse_string(FileAccess.get_file_as_string("res://out/ch1/members.json"))
	var bld := HO.build(mj, opts)
	var mm := HO.to_model(bld)
	var ms := HO.masses(bld)
	var model: Dictionary = mm["model"]
	model["mass"] = ms["mass"]
	var n: int = bld["nodes"].size()
	var load := PackedFloat64Array()
	load.resize(n * 6)
	for i in SIM.top_nodes(bld):
		load[i * 6 + dir] = 1.0
	var st := FR.solve(model, {"type": "static", "loads": load})
	var md := FR.solve(model, {"type": "modal", "start": st["u"], "iters": 3})
	return TAU / float(md["omega"])


func _init() -> void:
	if not FR.native_ok():
		print("FAIL the native frame class is not loaded")
		quit(1)
		return
	var Ta := SIM.ta(12.96)
	var t0 := maxf(period({}, 2), period({}, 0))
	var t1 := maxf(period({"gypsum": true}, 2), period({"gypsum": true}, 0))
	print("sheathing only: longest %.4f s; with gypsum skin: longest %.4f s; Ta %.4f s, Cu Ta %.4f .. %.4f s" % [t0, t1, Ta, 1.6 * Ta, 1.7 * Ta])
	ok(t1 >= 0.5 * Ta and t1 <= 1.7 * Ta, "c longest first sway period %.4f s in [%.4f, %.4f] (best model: gypsum skin on; sheathing-only %.4f s)" % [t1, 0.5 * Ta, 1.7 * Ta, t0])
	print("ch10_period: %d fail" % fails)
	quit(1 if fails > 0 else 0)
