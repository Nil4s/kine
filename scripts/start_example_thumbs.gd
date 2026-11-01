class_name StartExampleThumbs
extends Node
## THE PICTURES OF THE BUILDING EXAMPLES (bug7): each is drawn from the REAL geometry of its file, never a placeholder: a part is replayed and drawn
## with the Nice picture (NiceRender, Friday 105); the room with the house picture (Houses.picture_node through LibraryThumbs). One draw per frame,
## cached as user://thumbs/ex/<sha of the file>_<VERSION>.png, so the second open reads the disk. made(path) says a picture is ready.

signal made(path: String)

const SIZE := Vector2i(432, 244)
const VERSION := "v1"
const DIR := "user://thumbs/ex"

var renders := 0
var disk_hits := 0
var _tex := {}
var _queue: Array = []
var _busy := false
var _lt: LibraryThumbs


func picture(path: String) -> Texture2D:
	return _tex.get(path)


static func cache_path(sha: String) -> String:
	return "%s/%s_%s.png" % [DIR, sha, VERSION]


func request(path: String) -> void:
	if _tex.has(path) or _queue.has(path) or not FileAccess.file_exists(path):
		return
	var sha := FileAccess.get_sha256(path)
	var cp := cache_path(sha)
	if FileAccess.file_exists(cp):
		var img := Image.load_from_file(cp)
		if img != null and not img.is_empty():
			_tex[path] = ImageTexture.create_from_image(img)
			disk_hits += 1
			made.emit.call_deferred(path)
			return
	_queue.append(path)
	_pump()


func _pump() -> void:
	if _busy:
		return
	_busy = true
	while not _queue.is_empty():
		var path: String = _queue.pop_front()
		await _draw(path)
		await get_tree().process_frame
	_busy = false


func _draw(path: String) -> void:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary):
		return
	var img: Image = null
	if (d as Dictionary).has("part") and not ((d as Dictionary)["part"] as Dictionary).is_empty():
		img = await NiceRender.draw(self, Part.from_file((d as Dictionary)["part"]), SIZE)
	elif (d as Dictionary).has("building"):
		var node := Houses.picture_node((d as Dictionary)["building"])
		if node != null:
			if _lt == null:
				_lt = LibraryThumbs.new()
				_lt.name = "example_house_thumbs"
				add_child(_lt)
			img = await _lt.draw_node(node, SIZE)
	if img == null or img.is_empty() or not is_inside_tree():
		return
	_tex[path] = ImageTexture.create_from_image(img)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	img.save_png(ProjectSettings.globalize_path(cache_path(FileAccess.get_sha256(path))))
	renders += 1
	made.emit(path)
