## THE MULTI-CAMERA IMPORT PANEL (roadmap 89): the cameras it used (name, where it stands, how far its picture misses the
## reconstructed joints, how many joints it saw) on the left; the rig seen from above (the cameras and the person) under it;
## the reconstructed pose from the front on the right. Drawn only: set_result() takes MultiCam's output, nothing is read here.
class_name MultiCamPanel
extends Control

var cams: Array = []          # [{"name", "C": Vector3 (m), "rms": px, "views": int}]
var pose: Array = []          # 33 world points (y up, hips at 0) of the frame shown
var rms_frame := -1.0         # px: that frame's mean reprojection error
var frame_t := 0.0
const LIST_W := 300.0
const PAD := 16.0
const BONES := [[11, 13], [13, 15], [12, 14], [14, 16], [23, 25], [25, 27], [24, 26], [26, 28], [11, 23], [12, 24], [11, 12], [23, 24], [0, 11], [0, 12]]


func set_result(cam_list: Array, frame: Array, t: float, rms: float) -> void:
	cams = cam_list
	pose = frame
	frame_t = t
	rms_frame = rms
	queue_redraw()


## the front view's box: the right of the panel below the title
func skel_rect() -> Rect2:
	return Rect2(LIST_W + PAD * 2.0, 56.0, maxf(0.0, size.x - LIST_W - PAD * 3.0), maxf(0.0, size.y - 72.0))


## the figure's fit: the lowest and highest of the reconstructed points (y up, metres) over the box's height less 60 px
## for the title and the feet, scale in px per metre. Returns [scale, lowest y]
func fit(r: Rect2) -> Array:
	var lo := 1e9
	var hi := -1e9
	for p in pose:
		if p is Vector3 and (p as Vector3).length() > 0.0:
			lo = minf(lo, (p as Vector3).y)
			hi = maxf(hi, (p as Vector3).y)
	if hi < lo:
		return [1.0, 0.0]
	return [(r.size.y - 60.0) / maxf(hi - lo, 0.1), lo]


## a world point (x right, y up) to the front view's pixel: the figure centred in the box, its feet 16 px above the box's bottom
func to_screen(p: Vector3, r: Rect2) -> Vector2:
	var f := fit(r)
	var sc: float = f[0]
	return Vector2(r.position.x + r.size.x * 0.5 + p.x * sc, r.position.y + r.size.y - 16.0 - (p.y - float(f[1])) * sc)


func _draw() -> void:
	var bg := Tok.of("panel")
	draw_rect(Rect2(Vector2.ZERO, size), bg)
	var font := get_theme_default_font()
	draw_string(font, Vector2(PAD, 28.0), "Multi-camera import: %d cameras" % cams.size(), HORIZONTAL_ALIGNMENT_LEFT, LIST_W, 16, Tok.of("heading"))
	# the camera list
	var y := 56.0
	for c in cams:
		draw_rect(Rect2(PAD, y, LIST_W - PAD, 46.0), Tok.of("card"))
		draw_string(font, Vector2(PAD + 10.0, y + 18.0), "%s  %d joints seen" % [c["name"], int(c["views"])], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Tok.of("text"))
		var C: Vector3 = c["C"]
		draw_string(font, Vector2(PAD + 10.0, y + 36.0), "at %.2f, %.2f, %.2f m   reprojection %.2f px" % [C.x, C.y, C.z, float(c["rms"])],
			HORIZONTAL_ALIGNMENT_LEFT, LIST_W - PAD - 20.0, 12, Tok.of("info"))
		y += 54.0
	# the rig from above: the person at the centre, each camera where it stood, its name by it
	var top := Rect2(PAD, y + 8.0, LIST_W - PAD, 150.0)
	draw_rect(top, Tok.of("graph_bg"))
	var mid := top.position + top.size * 0.5
	var k := 0.5 * minf(top.size.x, top.size.y) / 3.0   # px per metre: the rig fits its 3 m radius
	draw_circle(mid, 4.0, Tok.of("s_hips"))
	for c in cams:
		var C: Vector3 = c["C"]
		var q := mid + Vector2(C.x, C.z) * k
		draw_line(mid, q, Tok.of("grid"), 1.0)
		draw_circle(q, 6.0, Tok.of("s_tip"))
		draw_string(font, q + Vector2(8.0, 4.0), str(c["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Tok.of("text"))
	# the reconstructed pose, front view
	var r := skel_rect()
	draw_rect(r, Tok.of("graph_bg"))
	draw_string(font, Vector2(r.position.x + 8.0, r.position.y + 18.0), "reconstructed at %.2f s, %.2f px" % [frame_t, rms_frame], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Tok.of("info"))
	if pose.size() < 33:
		return
	for b in BONES:
		draw_line(to_screen(pose[b[0]], r), to_screen(pose[b[1]], r), Tok.of("s_head"), 3.0)
	for j in [0, 11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28, 31, 32]:
		draw_circle(to_screen(pose[j], r), 4.0, Tok.of("s_tip") if j in [25, 26] else Tok.of("s_hips"))
