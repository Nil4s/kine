class_name PckImage
extends RefCounted
## C78: Image.load_from_file(globalize_path("res://x.png")) reads the DISK, which an exported build does not have for res:// files
## (they are inside the pck). Read the bytes through FileAccess (works in the pck and on disk), fall back to the old disk read.

static func load_res(path: String) -> Image:
	var b := FileAccess.get_file_as_bytes(path)
	if not b.is_empty():
		var img := Image.new()
		var err := img.load_png_from_buffer(b) if path.get_extension().to_lower() == "png" else ERR_FILE_UNRECOGNIZED
		if err == OK:
			return img
	return Image.load_from_file(ProjectSettings.globalize_path(path))
