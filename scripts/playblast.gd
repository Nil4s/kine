class_name Playblast
## PLAYBLAST (round 41, GATES WW6): the burn-in drawn into every recorded frame, and the read-back of an AVI.
## The burn-in is a Label on a CanvasLayer that exists only while recording, so it lands in the saved image.

const AREA := Rect2i(0, 0, 420, 34)   # where the burn-in sits, top left; the test compares inside and outside it


static func text(scene_name: String, f: int, t: float, finds: int) -> String:
	return "%s   frame %04d   %.2f s   check: %s" % [scene_name if scene_name != "" else "untitled", f, t, str(finds) if finds >= 0 else "-"]


## the overlay; add it to the main node, set .text each frame, free it when the recording ends
static func make_overlay() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 100
	var lab := Label.new()
	lab.name = "burn"
	lab.position = Vector2(AREA.position)
	lab.size = Vector2(AREA.size)
	lab.add_theme_font_size_override("font_size", 18)
	lab.add_theme_color_override("font_color", Color.WHITE)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 1)
	bg.content_margin_left = 8
	bg.content_margin_top = 4
	lab.add_theme_stylebox_override("normal", bg)
	layer.add_child(lab)
	return layer


## the frames of an AVI back out as JPEG byte arrays, plus its header numbers; {} if it is not an MJPEG AVI
static func read_avi(path: String) -> Dictionary:
	var b := FileAccess.get_file_as_bytes(path)
	if b.size() < 12 or b.slice(0, 4).get_string_from_ascii() != "RIFF" or b.slice(8, 12).get_string_from_ascii() != "AVI ":
		return {}
	var out := {"riff_size": b.decode_u32(4), "size": b.size(), "frames": [], "avih_frames": -1, "w": 0, "h": 0, "us": 0, "idx": 0}
	var pos := 12
	while pos + 8 <= b.size():
		var id := b.slice(pos, pos + 4).get_string_from_ascii()
		var sz := b.decode_u32(pos + 4)
		if id == "LIST":
			pos += 12   # step into the list
			continue
		if id == "avih":
			out["us"] = b.decode_u32(pos + 8)
			out["avih_frames"] = b.decode_u32(pos + 8 + 16)
			out["w"] = b.decode_u32(pos + 8 + 32)
			out["h"] = b.decode_u32(pos + 8 + 36)
		elif id == "00dc":
			out["frames"].append(b.slice(pos + 8, pos + 8 + sz))
		elif id == "idx1":
			out["idx"] = sz / 16
		pos += 8 + sz + (sz % 2)
	return out
