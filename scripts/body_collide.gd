## body_collide.gd - N046: BODY COLLISION. A shoulder charge / tackle shares momentum between two bodies. The masses that meet are the UPPER BODY
## (head, trunk, both arms: de Leva 1996 Table 4 shares, Proportions.DE_LEVA) of each; the legs stay with the floor. 1D along the line of impact with
## restitution e: va' = va - (1+e) mb/(ma+mb) u n, vb' = vb + (1+e) ma/(ma+mb) u n (u = closing speed), so momentum is conserved and the LIGHTER body
## changes speed more. Keys: each body's pelvis offset (m) after the hit, sliding against floor friction MU (a mid value, ours).
class_name BodyCollide
extends RefCounted

const MU := 0.6
const GRAV := 9.81
const KEY_T := [0.0, 0.1, 0.2, 0.4, 0.8]


static func upper_share(sex: String) -> float:
	var t: Dictionary = Proportions.DE_LEVA[sex]
	var tot := 0.0
	for s in Proportions.SEGS:
		tot += float(t[s][0]) * (1.0 if s in ["head", "trunk"] else 2.0)
	var up: float = float(t["head"][0]) + float(t["trunk"][0]) + 2.0 * (float(t["upper_arm"][0]) + float(t["forearm"][0]) + float(t["hand"][0]))
	return up / tot


static func _keys(v: Vector3) -> Array:
	var h := Vector3(v.x, 0, v.z)
	var sp := h.length()
	var ks := []
	var a := MU * GRAV
	var ts := sp / a
	for t in KEY_T:
		var tt := minf(t, ts)
		var d := sp * tt - 0.5 * a * tt * tt
		ks.append({"t": t, "pos": (h.normalized() * d) if sp > 1e-6 else Vector3.ZERO})
	return ks


static func charge(ma: float, va: Vector3, mb: float, vb: Vector3, sex := "male", e := 0.1) -> Dictionary:
	var sh := upper_share(sex)
	var ea := ma * sh
	var eb := mb * sh
	var rel := va - vb
	var u := rel.length()
	var n := rel / u if u > 1e-9 else Vector3(0, 0, 1)
	var va2 := va - n * ((1.0 + e) * eb / (ea + eb) * u)
	var vb2 := vb + n * ((1.0 + e) * ea / (ea + eb) * u)
	return {"m_eff_a": ea, "m_eff_b": eb, "va": va2, "vb": vb2,
		"p_before": (va * ea + vb * eb).length(), "p_after": (va2 * ea + vb2 * eb).length(),
		"dv_a": (va2 - va).length(), "dv_b": (vb2 - vb).length(), "keys_a": _keys(va2), "keys_b": _keys(vb2)}


static func to_json(r: Dictionary) -> Dictionary:
	var o := {}
	for k in r:
		var v: Variant = r[k]
		if v is Vector3:
			o[k] = [v.x, v.y, v.z]
		elif v is Array:
			var l := []
			for it in v:
				l.append({"t": it["t"], "pos": [it["pos"].x, it["pos"].y, it["pos"].z]})
			o[k] = l
		else:
			o[k] = v
	return o
