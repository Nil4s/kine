class_name UiExpIcons
extends RefCounted
## UIEXP ICONS (lane L2): the Expert / Engineering icon set. One original SVG per function in assets/icons/uiexp/ (24 px grid, 2 px
## stroke; drawn by tools/uiexp_icons.py). tex(id) rasterises it with Image.load_svg_from_string (no import step), the light theme
## swaps the two colours (body ink, amber accent) for dark ink and the light palette's blue. Cached per id, size and theme.

const DIR := "res://assets/icons/uiexp/"
const INK_DARK := "#ECEFF4"
const AMB_DARK := "#FFC733"
const INK_LIGHT := "#1A1C21"
const AMB_LIGHT := "#2A66CC"

static var _cache := {}
static var _svg := {}


static func has(id: String) -> bool:
	return FileAccess.file_exists(DIR + id + ".svg")


static func svg_text(id: String) -> String:
	if _svg.has(id):
		return _svg[id]
	var f := FileAccess.open(DIR + id + ".svg", FileAccess.READ)
	var s := f.get_as_text() if f != null else ""
	_svg[id] = s
	return s


## the icon as a texture at px pixels square ("" if the id has no file)
static func tex(id: String, px := 24) -> Texture2D:
	var dark: bool = Tok.dark
	var key := "%s|%d|%s" % [id, px, dark]
	if _cache.has(key):
		return _cache[key]
	var s := svg_text(id)
	if s == "":
		return null
	if not dark:
		s = s.replace(INK_DARK, INK_LIGHT).replace(AMB_DARK, AMB_LIGHT)
	var img := Image.new()
	if img.load_svg_from_string(s, float(px) / 24.0) != OK:
		return null
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t


## the id of a function name: "Offset plane" -> "offset_plane"
static func id_of(label: String) -> String:
	return label.strip_edges().to_lower().replace(" ", "_").replace("-", "_").replace("+", "plus")
