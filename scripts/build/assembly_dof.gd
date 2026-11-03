## DEGREES OF FREEDOM LEFT PER ASSEMBLY PART (C15, complaint #633: "cannot see degrees of freedom left in an assembly").
## A part has 6: slide along X, Y, Z and turn about X, Y, Z. Locking is opt-in: p["lock"] = {"pos": [bx, by, bz], "rot": [bx, by, bz]} (true = locked);
## a part with no "lock" key has all 6 free, so nothing existing changes. A locked axis refuses the typed number and the gizmo drag (enforce()).
class_name AssemblyDof
extends RefCounted

const PN := ["X", "Y", "Z"]


static func lock_of(p: Dictionary) -> Dictionary:
	var l: Dictionary = p.get("lock", {})
	return {"pos": (l.get("pos", [false, false, false]) as Array).duplicate(), "rot": (l.get("rot", [false, false, false]) as Array).duplicate()}


static func is_locked(p: Dictionary, kind: String, axis: int) -> bool:
	return bool(lock_of(p)[kind][axis])


static func set_lock(p: Dictionary, kind: String, axis: int, v: bool) -> void:
	var l := lock_of(p)
	l[kind][axis] = v
	if l["pos"].has(true) or l["rot"].has(true):
		p["lock"] = l
	else:
		p.erase("lock")   # all free again: the record is as it was


static func lock_all(p: Dictionary, v: bool) -> void:
	if v:
		p["lock"] = {"pos": [true, true, true], "rot": [true, true, true]}
	else:
		p.erase("lock")


static func free_count(p: Dictionary) -> int:
	var l := lock_of(p)
	var n := 0
	for k in ["pos", "rot"]:
		for b in l[k]:
			n += 0 if bool(b) else 1
	return n


## "free" | "partly" | "locked"
static func state(p: Dictionary) -> String:
	var n := free_count(p)
	return "free" if n == 6 else ("locked" if n == 0 else "partly")


static func colour(p: Dictionary) -> Color:
	match state(p):
		"free": return Color(0.45, 0.9, 0.5)
		"partly": return Color(0.95, 0.8, 0.35)
	return Color(0.95, 0.4, 0.4)


static func _join(a: Array) -> String:
	if a.is_empty():
		return ""
	if a.size() == 1:
		return a[0]
	return ", ".join(a.slice(0, a.size() - 1)) + " and " + a[a.size() - 1]


## "5 of 6 free: slides along X and Y, turns about X, Y and Z; Z slide is locked."
static func words(p: Dictionary) -> String:
	var l := lock_of(p)
	var fs := []; var ft := []; var ls := []; var lt := []
	for i in 3:
		(ls if bool(l["pos"][i]) else fs).append(PN[i])
		(lt if bool(l["rot"][i]) else ft).append(PN[i])
	var n := free_count(p)
	if n == 6:
		return "6 of 6 free: slides along X, Y and Z, turns about X, Y and Z."
	if n == 0:
		return "0 of 6 free: fixed in place."
	var free_bits := []
	if not fs.is_empty():
		free_bits.append("slides along " + _join(fs))
	if not ft.is_empty():
		free_bits.append("turns about " + _join(ft))
	var lock_bits := []
	if not ls.is_empty():
		lock_bits.append("slide along " + _join(ls))
	if not lt.is_empty():
		lock_bits.append("turn about " + _join(lt))
	return "%d of 6 free: %s. Locked: %s." % [n, ", ".join(free_bits), " and ".join(lock_bits)]


## the whole assembly: [{"id", "name", "free", "state", "words"}], and the sum
static func report(asm: Dictionary) -> Dictionary:
	var rows := []
	var tot := 0
	for p in asm["parts"]:
		var d: Dictionary = p
		rows.append({"id": String(d["id"]), "name": String(d["name"]), "free": free_count(d), "state": state(d), "words": words(d)})
		tot += free_count(d)
	return {"rows": rows, "total": tot, "of": 6 * rows.size()}


## after a pose change: put every locked axis back to its value before. (pos0 / rot0 are the arrays/vectors from before the change)
static func enforce(p: Dictionary, pos0: Array, rot0: Array) -> void:
	var l := lock_of(p)
	for i in 3:
		if bool(l["pos"][i]):
			p["pos"][i] = pos0[i]
		if bool(l["rot"][i]):
			p["rot"][i] = rot0[i]
