## key_blend.gd - SHAPE TOOLS (round 48, GATES DD1, UPGRADES_300 #246). Blender's Graph Editor Key > Blend set, on the
## selected key dots of one joint's part keys. Definitions from Blender's manual source (projects.blender.org/blender/
## blender-manual, editors/graph_editor/fcurves/editing.rst, read 10-18). As in Blender, the selected keys of each angle
## are split into CONTIGUOUS RUNS; each run's NEIGHBOURS are the unselected keys just before (L) and after (R) it.
##   breakdown        "sets the value of the selected keyframes to an interpolation of their neighbors": -1 = L's value,
##                    1 = R's, 0 = the middle.                               v = L + (R - L) (f + 1) / 2
##   blend_neighbor   "moves each selected keyframe towards the value of the left or right neighbor by a percentage":
##                    v += (L - v) |f| for f < 0, (R - v) f for f > 0
##   push_pull        "towards, or away from, the straight line through the first and last selected key": 0 = on the
##                    line, 1 = unchanged, 2 = twice as far.                 v = line(t) + (v - line(t)) f
##   ease             "follow an S-curve" from L to R; f = the curve's bend (< 0 more weight left, > 0 right, 0 balanced),
##                    `sharp` its steepness.  x = (t - tL) / (tR - tL), x' = x^(2^-f), v = L + (R - L) x'^p / (x'^p +
##                    (1 - x')^p), p = 1 + sharp (our S-curve; the manual gives its shape, not its formula)
##   match_slope      "blends the selected keys towards a straight line going through two keys just outside the
##                    selection": f < 0 the two keys to the left, f > 0 the two to the right.  v += (line(t) - v) |f|
##   scale_neighbor   "scales the selected keyframes vertically, using a keyframe just outside the selection as the
##                    pivot", the left one (right with `right`).         v = P + (v - P) f
##   blend_offset     "moves the selected keyframes up or down, all by the same amount, until the first/last one
##                    matches the left/right neighbor": f = -1 the first meets L, 1 the last meets R.
## A run without the neighbour(s) a tool needs is left as it is and counted in the report's "skipped".
class_name KeyBlend
extends RefCounted

const TOOLS := ["breakdown", "blend_neighbor", "push_pull", "ease", "match_slope", "scale_neighbor", "blend_offset"]
const NAMES := {"breakdown": "Breakdown", "blend_neighbor": "Blend to neighbour", "push_pull": "Push / pull",
	"ease": "Ease", "match_slope": "Match slope", "scale_neighbor": "Scale from neighbour", "blend_offset": "Blend offset"}


## the runs: {angle: [[first index, last index], ...]} from the selected dots [[angle, index], ...]
static func runs(sel: Array) -> Dictionary:
	var by := {}
	for q in sel:
		if not by.has(q[0]):
			by[q[0]] = []
		if not (by[q[0]] as Array).has(q[1]):
			by[q[0]].append(q[1])
	var out := {}
	for c in by:
		var ids: Array = by[c]
		ids.sort()
		var rs := []
		var a: int = ids[0]
		var b: int = ids[0]
		for k in range(1, ids.size()):
			if ids[k] == b + 1:
				b = ids[k]
			else:
				rs.append([a, b])
				a = ids[k]
				b = ids[k]
		rs.append([a, b])
		out[c] = rs
	return out


static func _time(keys: Array, i: int) -> float:
	return float(keys[i]["t"])


static func _val(keys: Array, i: int, c: int) -> float:
	return (keys[i]["v"] as Vector3)[c]


static func _put(keys: Array, i: int, c: int, x: float) -> void:
	var v: Vector3 = keys[i]["v"]
	v[c] = x
	keys[i]["v"] = v


static func _line(t0: float, v0: float, t1: float, v1: float, t: float) -> float:
	if absf(t1 - t0) < 1e-9:
		return v0
	return v0 + (v1 - v0) * (t - t0) / (t1 - t0)


## apply `tool` with factor f to the selected dots of `keys` (in place). Returns {"changed": dots changed, "skipped": runs
## left alone for want of a neighbour}
static func apply(keys: Array, sel: Array, tool: String, f: float, sharp := 2.0, right := false) -> Dictionary:
	var changed := 0
	var skipped := 0
	var n := keys.size()
	var rs := runs(sel)
	for c in rs:
		for r in rs[c]:
			var a: int = r[0]
			var b: int = r[1]
			var L := a - 1
			var R := b + 1
			var has_l := L >= 0
			var has_r := R < n
			var need_both := tool in ["breakdown", "ease"]
			if (need_both and not (has_l and has_r)) \
					or (tool == "blend_neighbor" and ((f < 0.0 and not has_l) or (f > 0.0 and not has_r))) \
					or (tool == "scale_neighbor" and not (has_r if right else has_l)) \
					or (tool == "blend_offset" and ((f < 0.0 and not has_l) or (f > 0.0 and not has_r))) \
					or (tool == "match_slope" and ((f < 0.0 and L - 1 < 0) or (f > 0.0 and R + 1 >= n))):
				skipped += 1
				continue
			var old := []
			for i in range(a, b + 1):
				old.append(_val(keys, i, c))
			var delta := 0.0
			if tool == "blend_offset":
				delta = (_val(keys, L, c) - old[0]) * absf(f) if f < 0.0 else ((_val(keys, R, c) - old[-1]) * f if f > 0.0 else 0.0)
			for i in range(a, b + 1):
				var v: float = old[i - a]
				var t := _time(keys, i)
				var nv := v
				match tool:
					"breakdown":
						nv = _val(keys, L, c) + (_val(keys, R, c) - _val(keys, L, c)) * (f + 1.0) * 0.5
					"blend_neighbor":
						if f < 0.0:
							nv = v + (_val(keys, L, c) - v) * absf(f)
						elif f > 0.0:
							nv = v + (_val(keys, R, c) - v) * f
					"push_pull":
						var ln := _line(_time(keys, a), old[0], _time(keys, b), old[-1], t)
						nv = ln + (v - ln) * f
					"ease":
						var x := clampf((t - _time(keys, L)) / maxf(_time(keys, R) - _time(keys, L), 1e-9), 0.0, 1.0)
						var xb := pow(x, pow(2.0, -f))
						var p := 1.0 + sharp
						var s := pow(xb, p) / maxf(pow(xb, p) + pow(1.0 - xb, p), 1e-12)
						nv = _val(keys, L, c) + (_val(keys, R, c) - _val(keys, L, c)) * s
					"match_slope":
						var ln: float
						if f < 0.0:
							ln = _line(_time(keys, L - 1), _val(keys, L - 1, c), _time(keys, L), _val(keys, L, c), t)
						else:
							ln = _line(_time(keys, R), _val(keys, R, c), _time(keys, R + 1), _val(keys, R + 1, c), t)
						nv = v + (ln - v) * absf(f)
					"scale_neighbor":
						var pv := _val(keys, R if right else L, c)
						nv = pv + (v - pv) * f
					"blend_offset":
						nv = v + delta
				if nv != v:
					changed += 1
				_put(keys, i, c, nv)
	return {"changed": changed, "skipped": skipped}
