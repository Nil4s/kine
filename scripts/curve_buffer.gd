class_name CurveBuffer
extends RefCounted
## L84 BUFFER CURVES (Maya buffer curve snapshot / swap; ROADMAP_400 L03). A SLOT holds a deep copy of one joint's part keys (keys, handles,
## weights and the modifier stack, which live on the keys). snapshot() stores one; swap() exchanges the live keys with the slot (so a second swap
## goes back, exactly); compare() reads both curves (value_at, modifiers included) on n+1 samples across the union of their spans; the stored
## keys are what the editor draws faintly behind the live curve (CurveEditor.ghost_keys). Slots are session data, not saved in the scene file.

static var slots: Array = []   # [{"joint", "name", "keys"}]


static func snapshot(pk: Dictionary, j: String, name := "") -> int:
	if not pk.has(j):
		return -1
	slots.append({"joint": j, "name": name if name != "" else "buffer %d" % (slots.size() + 1), "keys": (pk[j] as Array).duplicate(true)})
	return slots.size() - 1


static func keys_of(slot: int, j := "") -> Array:
	if slot < 0 or slot >= slots.size() or (j != "" and slots[slot]["joint"] != j):
		return []
	return slots[slot]["keys"]


static func swap(pk: Dictionary, j: String, slot: int) -> bool:
	if slot < 0 or slot >= slots.size() or slots[slot]["joint"] != j or not pk.has(j):
		return false
	var live: Array = pk[j]
	pk[j] = slots[slot]["keys"]
	slots[slot]["keys"] = live
	return true


## {"max", "rms", "max_ch": [bend, side, twist], "t_at_max", "keys_live", "keys_buffer", "n"} in degrees, over the union span
static func compare(pk: Dictionary, j: String, slot: int, n := 300) -> Dictionary:
	var b := keys_of(slot, j)
	var a: Array = pk.get(j, [])
	if a.is_empty() or b.is_empty():
		return {"max": INF, "rms": INF, "max_ch": [INF, INF, INF], "t_at_max": 0.0, "keys_live": a.size(), "keys_buffer": b.size(), "n": 0}
	var t0 := minf(float(a[0]["t"]), float(b[0]["t"]))
	var t1 := maxf(float(a[-1]["t"]), float(b[-1]["t"]))
	var mx := 0.0
	var at := t0
	var ss := 0.0
	var mc := [0.0, 0.0, 0.0]
	for i in n + 1:
		var t := t0 + (t1 - t0) * float(i) / float(n)
		var d: Vector3 = PartKeys.value_at(a, t) - PartKeys.value_at(b, t)
		var m := maxf(absf(d.x), maxf(absf(d.y), absf(d.z)))
		if m > mx:
			mx = m
			at = t
		ss += d.length_squared() / 3.0
		for c in 3:
			mc[c] = maxf(mc[c], absf(d[c]))
	return {"max": mx, "rms": sqrt(ss / float(n + 1)), "max_ch": mc, "t_at_max": at, "keys_live": a.size(), "keys_buffer": b.size(), "n": n + 1}
