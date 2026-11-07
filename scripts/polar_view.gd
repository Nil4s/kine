## polar_view.gd - the polar picture of a stance map: one spoke per direction, radius = impulse / the strongest, the support polygon drawn at the same scale.
## Forward (0 deg) is up, his left (90 deg) is to the left. points() are in the control pixels.
class_name PolarView
extends Control

var mp: Dictionary = {}


func _init() -> void:
	custom_minimum_size = Vector2(300, 300)
	size = Vector2(300, 300)


func set_map(p: Dictionary) -> void:
	mp = p
	queue_redraw()


func _radius() -> float:
	return minf(size.x, size.y) * 0.5 - 6.0


func points() -> PackedVector2Array:
	var out := PackedVector2Array()
	if not bool(mp.get("ok", false)):
		return out
	var hi := maxf(StanceMap.highest(mp), 1e-9)
	var ctr := size * 0.5
	var R := _radius()
	for k in (mp["impulse"] as Array).size():
		var a := deg_to_rad(float((mp["dirs"] as Array)[k]))
		var r := float(mp["impulse"][k]) / hi * R
		out.append(ctr + Vector2(-sin(a), -cos(a)) * r)
	return out


func _draw() -> void:
	var ctr := size * 0.5
	var R := _radius()
	for f in [0.5, 1.0]:
		draw_arc(ctr, R * f, 0.0, TAU, 48, Color(1, 1, 1, 0.15), 1.0)
	draw_line(ctr - Vector2(R, 0), ctr + Vector2(R, 0), Color(1, 1, 1, 0.12))
	draw_line(ctr - Vector2(0, R), ctr + Vector2(0, R), Color(1, 1, 1, 0.12))
	var pts := points()
	if pts.size() < 3:
		return
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_colored_polygon(pts, Color(0.3, 0.8, 0.5, 0.35))
	draw_polyline(closed, Color(0.4, 0.95, 0.6), 2.0)
	# the feet's support polygon at the spokes' scale: an edge distance d metres is impulse M w0 d, so px per metre = R / hi / (M w0)
	var k := R / maxf(StanceMap.highest(mp), 1e-9) / (float(mp["mass"]) * float(mp["w0"]))
	var hd := float(mp["heading"])
	var fwd := Vector2(sin(hd), cos(hd))
	var lef := Vector2(cos(hd), -sin(hd))
	var com: Vector2 = mp["com"]
	var poly := PackedVector2Array()
	for p in (mp["poly"] as PackedVector2Array):
		var rel: Vector2 = p - com
		poly.append(ctr + Vector2(-rel.dot(lef) * k, -rel.dot(fwd) * k))
	if poly.size() >= 3:
		var pc := poly.duplicate()
		pc.append(poly[0])
		draw_polyline(pc, Color(1, 0.85, 0.4), 1.5)
	draw_circle(ctr, 3.0, Color(1, 0.4, 0.4))
