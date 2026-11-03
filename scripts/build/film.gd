class_name Film
extends RefCounted
## ITEM 269 FILM KEYS (the GPU film's animation lived in a hand-written driver, hall_compare/gpu/kine/gpu_render.gd; now it is data on the part).
## A part record may carry  rec["film"] = {"looks": [...], "spins": [...], "moves": [...]}  (written only when there is one; a part without it saves,
## replays and draws exactly as before). Time is in seconds, bodies are the part's body indices (the same numbers as an appear / hinge step's "body").
##   LOOK KEYS  {"body": i, "extrap": "constant" | "cycle", "keys": [{"t": s, "c": [r,g,b]?, "glow": [r,g,b]?, "k": strength?}, ...]} sorted by t.
##              Each field (colour, emission colour, emission strength) is read on its own keys; colours blend in HSV the short way round the hue wheel
##              (so a key at red and one at green pass through yellow, not grey), strength linearly. Before the first key / after the last: held
##              ("cycle": the keyed span repeats). No keys for a field = the part's own look (the appear step) for it.
##   HUE CYCLE  hue_cycle() writes the keys of a colour wheel turn: hue(t) = h0 + cycles * (t - t0) / (t1 - t0), in `steps` keys per cycle.
##   SPINS      {"body": i, "axis": [x,y,z], "o": [x,y,z] mm (pivot; none = the body's box centre), "track": [[t, deg], ...], "extrap": "linear", "rpm": r}
##              spin() writes the track [[t0, a0], [t0 + 1, a0 + rpm * 6]] with linear extrapolation (s260: Curves.eval), so the angle at t is
##              a0 + rpm * 6 * (t - t0) degrees for ever; it is turned mod 360 only when the matrix is made (no float drift at 18000 deg).
##   MOVES      {"body": i, "track": [[t, [x, y, z] mm], ...], "extrap": "constant" | "linear" | "cycle"}: the body's offset from where it was built.
## xform_at() = move * spin about the pivot: the body's transform at t, metres, applied on top of the replayed (built) mesh.

const MM := 0.001
const DEFAULT_LEN := 4.0


static func data(rec: Dictionary) -> Dictionary:
	var d: Variant = rec.get("film", null)
	return d if d is Dictionary else {}


static func has_any(rec: Dictionary) -> bool:
	var d := data(rec)
	return not (d.get("looks", []) as Array).is_empty() or not (d.get("spins", []) as Array).is_empty() or not (d.get("moves", []) as Array).is_empty()


static func _ensure(rec: Dictionary) -> Dictionary:
	if not (rec.get("film") is Dictionary):
		rec["film"] = {}
	var d: Dictionary = rec["film"]
	for k in ["looks", "spins", "moves"]:
		if not (d.get(k) is Array):
			d[k] = []
	return d


static func _entry(list: Array, body: int) -> int:
	for i in list.size():
		if int((list[i] as Dictionary).get("body", -1)) == body:
			return i
	return -1


# ---------------------------------------------------------------- look keys

static func _col(c: Color) -> Array:
	return [snappedf(c.r, 0.00001), snappedf(c.g, 0.00001), snappedf(c.b, 0.00001)]


## key body's look at time t: any of colour c, emission colour glow, strength k (null = this key leaves that field to the part's own look). A key
## already within 1 ms is changed (fields given replace, others stay).
static func key_look(rec: Dictionary, body: int, t: float, c: Variant = null, glow: Variant = null, k: Variant = null) -> void:
	var d := _ensure(rec)
	var li := _entry(d["looks"], body)
	if li < 0:
		(d["looks"] as Array).append({"body": body, "keys": []})
		li = (d["looks"] as Array).size() - 1
	var keys: Array = d["looks"][li]["keys"]
	var ki := -1
	for i in keys.size():
		if absf(float(keys[i]["t"]) - t) < 0.001:
			ki = i
	if ki < 0:
		keys.append({"t": snappedf(t, 0.0001)})
		ki = keys.size() - 1
	if c is Color:
		keys[ki]["c"] = _col(c)
	if glow is Color:
		keys[ki]["glow"] = _col(glow)
	if k != null:
		keys[ki]["k"] = clampf(float(k), 0.0, PartGlow.MAX_K)
	keys.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))


## the colour wheel turned `cycles` times between t0 and t1 on body's emission colour (target "glow"), its colour ("c") or both ("both"), at saturation s,
## value v; k = emission strength written on every key (<= 0: leave it). Returns the number of keys written.
static func hue_cycle(rec: Dictionary, body: int, t0: float, t1: float, cycles: float, s := 1.0, v := 1.0, k := 0.0, h0 := 0.0, target := "glow", steps_per_cycle := 12) -> int:
	var n := maxi(1, int(ceil(absf(cycles) * float(steps_per_cycle))))
	for i in n + 1:
		var u := float(i) / float(n)
		var h := fposmod(h0 + cycles * u, 1.0)
		var col := Color.from_hsv(h, s, v)
		key_look(rec, body, lerpf(t0, t1, u), col if target != "glow" else null, col if target != "c" else null, k if k > 0.0 else null)
	return n + 1


static func hue_of(c: Color) -> float:
	return c.h


static func _hsv_lerp(a: Color, b: Color, u: float) -> Color:
	var dh := b.h - a.h
	if dh > 0.5:
		dh -= 1.0
	elif dh < -0.5:
		dh += 1.0
	if a.s < 1e-4:   # a grey has no hue of its own: take the other's, so a fade from white to red does not sweep the wheel
		dh = 0.0
		a.h = b.h
	elif b.s < 1e-4:
		dh = 0.0
	return Color.from_hsv(fposmod(a.h + dh * u, 1.0), lerpf(a.s, b.s, u), lerpf(a.v, b.v, u))


static func _fold(keys: Array, t: float, extrap: String) -> float:
	if extrap == "cycle" and keys.size() >= 2:
		var t0 := float(keys[0]["t"])
		var t1 := float(keys[-1]["t"])
		if t1 > t0 and (t < t0 or t > t1):
			return t0 + fposmod(t - t0, t1 - t0)
	return t


## one field's value at t over the keys that carry it (null when no key has it)
static func _field(keys: Array, f: String, t: float, extrap: String) -> Variant:
	var ks: Array = []
	for k in keys:
		if k.has(f):
			ks.append(k)
	if ks.is_empty():
		return null
	t = _fold(ks, t, extrap)
	if t <= float(ks[0]["t"]):
		return _val(ks[0], f)
	if t >= float(ks[-1]["t"]):
		return _val(ks[-1], f)
	var lo := 0
	while lo + 1 < ks.size() - 1 and float(ks[lo + 1]["t"]) <= t:
		lo += 1
	var a: Dictionary = ks[lo]
	var b: Dictionary = ks[lo + 1]
	var u := (t - float(a["t"])) / maxf(1e-12, float(b["t"]) - float(a["t"]))
	if f == "k":
		return lerpf(float(a["k"]), float(b["k"]), u)
	return _hsv_lerp(_val(a, f), _val(b, f), u)


static func _val(k: Dictionary, f: String) -> Variant:
	if f == "k":
		return float(k["k"])
	var a: Array = k[f]
	return Color(float(a[0]), float(a[1]), float(a[2]))


## the look of `body` at time t: `base` (the part's own look dict, Part.look_of) with the keyed fields replaced. No keys on the body: base itself.
static func look_at(rec: Dictionary, body: int, t: float, base: Dictionary) -> Dictionary:
	var d := data(rec)
	var li := _entry(d.get("looks", []), body)
	if li < 0:
		return base
	var e: Dictionary = d["looks"][li]
	var keys: Array = e.get("keys", [])
	var ex := String(e.get("extrap", "constant"))
	var out := base.duplicate()
	var c: Variant = _field(keys, "c", t, ex)
	if c is Color:
		out["c"] = c
	var g: Variant = _field(keys, "glow", t, ex)
	if g is Color:
		out["glow"] = g
		if not PartGlow.has(base):
			out["glow_k"] = maxf(float(base.get("glow_k", 0.0)), 1.0)   # a keyed colour on a part that did not glow: lit at 1 unless k is keyed
	var k: Variant = _field(keys, "k", t, ex)
	if k != null:
		out["glow_k"] = float(k)
		if not (out.get("glow") is Color) and float(k) > 0.0:
			out["glow"] = out.get("c", Color.WHITE)
	return out


# ---------------------------------------------------------------- spins and moves

## body turns at `rpm` about `axis` (through pivot_mm, or its box centre): angle a0 + rpm * 6 * (t - t0) degrees, for ever (linear extrapolation)
static func spin(rec: Dictionary, body: int, rpm: float, axis := Vector3.UP, pivot_mm: Variant = null, a0 := 0.0, t0 := 0.0) -> void:
	var d := _ensure(rec)
	var e := {"body": body, "axis": [axis.x, axis.y, axis.z], "track": [[t0, a0], [t0 + 1.0, a0 + rpm * 6.0]], "extrap": "linear", "rpm": rpm}
	if pivot_mm is Vector3:
		e["o"] = [pivot_mm.x, pivot_mm.y, pivot_mm.z]
	var i := _entry(d["spins"], body)
	if i >= 0:
		d["spins"][i] = e
	else:
		(d["spins"] as Array).append(e)


## body moves along the keys [[t, Vector3 mm offset], ...]
static func move(rec: Dictionary, body: int, keys: Array, extrap := "constant") -> void:
	var d := _ensure(rec)
	var tr: Array = []
	for k in keys:
		var v: Vector3 = k[1]
		tr.append([float(k[0]), [v.x, v.y, v.z]])
	var e := {"body": body, "track": tr}
	if extrap != "constant":
		e["extrap"] = extrap
	var i := _entry(d["moves"], body)
	if i >= 0:
		d["moves"][i] = e
	else:
		(d["moves"] as Array).append(e)


static func clear_body(rec: Dictionary, body: int) -> void:
	var d := data(rec)
	for k in ["looks", "spins", "moves"]:
		var l: Array = d.get(k, [])
		var i := _entry(l, body)
		if i >= 0:
			l.remove_at(i)
	if not has_any(rec):
		rec.erase("film")


static func spin_deg(rec: Dictionary, body: int, t: float) -> float:
	var d := data(rec)
	var i := _entry(d.get("spins", []), body)
	if i < 0:
		return 0.0
	var e: Dictionary = d["spins"][i]
	return float(Curves.eval(e["track"], t, Curves.mode_of(e)))


static func offset_at(rec: Dictionary, body: int, t: float) -> Vector3:
	var d := data(rec)
	var i := _entry(d.get("moves", []), body)
	if i < 0:
		return Vector3.ZERO
	var e: Dictionary = d["moves"][i]
	var ch: Array = []
	for k in e["track"]:
		var a: Array = k[1]
		ch.append([float(k[0]), Vector3(float(a[0]), float(a[1]), float(a[2]))])
	return (Curves.eval(ch, t, Curves.mode_of(e)) as Vector3) * MM


## the body's transform at t (metres, on top of the built mesh); centre = the body's box centre (the default pivot)
static func xform_at(rec: Dictionary, body: int, t: float, centre: Vector3) -> Transform3D:
	var d := data(rec)
	var xf := Transform3D.IDENTITY
	var si := _entry(d.get("spins", []), body)
	if si >= 0:
		var e: Dictionary = d["spins"][si]
		var ax: Array = e.get("axis", [0, 1, 0])
		var axis := Vector3(float(ax[0]), float(ax[1]), float(ax[2])).normalized()
		var o := centre
		if e.get("o") is Array:
			o = Vector3(float(e["o"][0]), float(e["o"][1]), float(e["o"][2])) * MM
		var deg := fposmod(spin_deg(rec, body, t), 360.0)
		var r := Transform3D(Basis(axis, deg_to_rad(deg)), Vector3.ZERO)
		xf = Transform3D(Basis.IDENTITY, o) * r * Transform3D(Basis.IDENTITY, -o)
	xf.origin += offset_at(rec, body, t)
	return xf


## the film's length: the last key of any track (at least 1 s; DEFAULT_LEN when only a linear / cycle track runs for ever)
static func duration(rec: Dictionary) -> float:
	var d := data(rec)
	var last := 0.0
	var open := false
	for e in d.get("looks", []):
		var ks: Array = e.get("keys", [])
		if not ks.is_empty():
			last = maxf(last, float(ks[-1]["t"]))
	for k in ["spins", "moves"]:
		for e in d.get(k, []):
			var tr: Array = e.get("track", [])
			if not tr.is_empty():
				last = maxf(last, float(tr[-1][0]))
			if String(e.get("extrap", "constant")) != "constant":
				open = true
	if open and last < 2.0:
		return DEFAULT_LEN
	return maxf(last, 1.0)


## every key time on the film (the timeline's ticks), sorted, de-duplicated
static func key_times(rec: Dictionary) -> Array:
	var d := data(rec)
	var ts: Array = []
	for e in d.get("looks", []):
		for k in e.get("keys", []):
			ts.append(snappedf(float(k["t"]), 0.001))
	for k in ["spins", "moves"]:
		for e in d.get(k, []):
			for p in e.get("track", []):
				ts.append(snappedf(float(p[0]), 0.001))
	ts.sort()
	var out: Array = []
	for t in ts:
		if out.is_empty() or absf(float(out[-1]) - float(t)) > 0.0005:
			out.append(t)
	return out
