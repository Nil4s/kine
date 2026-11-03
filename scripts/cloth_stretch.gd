## cloth_stretch.gd - C13 (complaint 655): how far the baked cape stretched. Every structural edge (row and column neighbour) is
## compared with its rest length (frame 0, as tests/cloth_test.gd does) at every baked frame. report() gives the MAX and the MEAN
## relative stretch (0.03 = 3 %) and names the worst spot (frame, time, row and column of the edge, in words).
class_name ClothStretch
extends RefCounted


## {"ok", "max", "mean", "frame", "time", "edge": [i, j], "spot": words, "frames": n}; ok = false when there is no cape
static func report(cape: Dictionary) -> Dictionary:
	var fr: Array = cape.get("frames", [])
	if fr.is_empty():
		return {"ok": false, "max": 0.0, "mean": 0.0, "frame": -1, "time": 0.0, "edge": [-1, -1], "spot": "", "frames": 0}
	var topo := Cloth.topology()
	var E: PackedInt32Array = topo["edges"]
	var ns: int = topo["n_struct"]
	var r0: PackedVector3Array = fr[0]
	var L0 := PackedFloat64Array()
	for k in ns:
		L0.append(maxf(r0[E[2 * k]].distance_to(r0[E[2 * k + 1]]), 1e-9))
	var worst := -1.0
	var wf := 0
	var we := 0
	var sum := 0.0
	var n := 0
	for f in fr.size():
		var v: PackedVector3Array = fr[f]
		for k in ns:
			var s := absf(v[E[2 * k]].distance_to(v[E[2 * k + 1]]) / L0[k] - 1.0)
			sum += s
			n += 1
			if s > worst:
				worst = s
				wf = f
				we = k
	var fps := float(int(cape.get("fps", 30)))
	var i := E[2 * we]
	var j := E[2 * we + 1]
	return {"ok": true, "max": worst, "mean": sum / float(maxi(n, 1)), "frame": wf, "time": float(wf) / fps, "edge": [i, j],
		"spot": spot(i, j), "frames": fr.size()}


## the edge i-j in words: where on the cape (its top row is at the shoulders, its last row the hem)
static func spot(i: int, j: int) -> String:
	var r := float(i / Cloth.COLS + j / Cloth.COLS) * 0.5
	var c := float(i % Cloth.COLS + j % Cloth.COLS) * 0.5
	var h := "near the shoulders" if r < Cloth.ROWS * 0.33 else ("at the middle" if r < Cloth.ROWS * 0.66 else "near the hem")
	var cm := (Cloth.COLS - 1) * 0.5
	var sd := "in the centre" if absf(c - cm) < Cloth.COLS * 0.12 else ("on the left side" if c < cm else "on the right side")
	return "%s, %s (row %d, column %d)" % [h, sd, int(floor(r)) + 1, int(floor(c)) + 1]


static func words(rep: Dictionary) -> String:
	if not rep["ok"]:
		return "there is no cape to measure: click 'Cape: add to the back' first"
	return "cape stretch: worst edge %.2f %% of its rest length, average %.2f %%; worst %s, at %.2f s (frame %d)" % [
		float(rep["max"]) * 100.0, float(rep["mean"]) * 100.0, rep["spot"], float(rep["time"]), int(rep["frame"])]
