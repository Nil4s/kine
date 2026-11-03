## RIG PRE-CHECK (C14, complaint #520: an auto-rig "assumes a tight mesh convention; odd bones or a missing neck cause distortion").
## Before a character's skeleton is mapped onto Kine's, say what is odd: too many / too few bones, no neck, a left side that does not
## match the right. Words only; the import is unchanged. Pure functions on AnimImport.load_source's src and the bone mapping.
class_name RigPrecheck
extends RefCounted

const BONES_MAX := 160    # more than this many bones: heavier than a person needs (props, cloth, facial bones)
const BONES_MIN := 15     # fewer than this: too few to move a whole body
const SIDE_DEV := 0.15    # an arm or leg differing from the other side by more than this share of the longer


static func _len(rest: Array, mp: Dictionary, chain: Array) -> float:
	var t := 0.0
	for i in chain.size() - 1:
		if not mp.has(chain[i]) or not mp.has(chain[i + 1]):
			return -1.0
		t += ((rest[mp[chain[i]]] as Transform3D).origin - (rest[mp[chain[i + 1]]] as Transform3D).origin).length()
	return t


## {"ok", "findings": [{"kind", "text"}], "text": one line or ""}
static func check(src: Dictionary, mapping: Dictionary) -> Dictionary:
	var f := []
	var n := (src.get("names", []) as Array).size()
	if n > BONES_MAX:
		f.append({"kind": "many_bones", "text": "%d bones is a lot for one body (over %d): extra bones (props, cloth, face) are left out" % [n, BONES_MAX]})
	elif n < BONES_MIN:
		f.append({"kind": "few_bones", "text": "only %d bones (under %d): a whole body needs a spine, a neck, a head and four limbs" % [n, BONES_MIN]})
	var mp: Dictionary = mapping.get("map", {})
	if not mp.has("neck_01"):
		f.append({"kind": "no_neck", "text": "no neck bone found: the head will turn from the top of the spine, which can bend the shoulders; add a neck bone or check its name"})
	var rest: Array = src.get("rest", [])
	var sides := [["upperarm_l", "lowerarm_l", "hand_l", "upperarm_r", "lowerarm_r", "hand_r", "arm"], ["thigh_l", "calf_l", "foot_l", "thigh_r", "calf_r", "foot_r", "leg"]]
	for s in sides:
		var l := _len(rest, mp, [s[0], s[1], s[2]])
		var r := _len(rest, mp, [s[3], s[4], s[5]])
		if l < 0.0 and r < 0.0:
			continue
		if l < 0.0 or r < 0.0:
			f.append({"kind": "one_sided_" + s[6], "text": "the %s is found on one side only: the other side will stay at rest" % s[6]})
		elif absf(l - r) / maxf(l, r) > SIDE_DEV:
			f.append({"kind": "asym_" + s[6], "text": "the left and right %s differ by %d%%: the rig is not symmetrical" % [s[6], roundi(absf(l - r) / maxf(l, r) * 100.0)]})
	var words := []
	for x in f:
		words.append(x["text"])
	return {"ok": f.is_empty(), "findings": f, "text": ("Rig check: " + "; ".join(words)) if not f.is_empty() else ""}
