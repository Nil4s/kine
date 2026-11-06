class_name KMeshTPaintFile
extends RefCounted
## Texture paint saved with the scene (L55). The painted RGBA8 texture is written as a PNG beside the scene JSON (<scene>_tpaint.png) and the scene
## dict records {"png", "size", "sha", "uv"}: sha = SHA-256 of the texture bytes, uv = SHA-256 of the mesh's "uv" attribute ("none" without one).
## Open: the PNG is read back and its SHA-256 must equal the record; the texture is then held until Texture mode meets a mesh with the same UVs
## (the unwrap is deterministic, so the same mesh gets the same UVs). A missing or altered PNG is a warning, never a crash, and paints nothing.

const KEY := "tpaint"


static func sha(bytes: PackedByteArray) -> String:
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_SHA256)
	hc.update(bytes)
	return hc.finish().hex_encode()


static func uv_hash(mesh: KMesh) -> String:
	if mesh == null or not mesh.has_attr("uv"):
		return "none"
	return sha(mesh.attr_data("uv").to_byte_array())


## src: {"data", "size", "uv"} from KMeshVPaintUI.texture_source(); {} = nothing painted (the scene drops its record)
static func record(d: Dictionary, src: Dictionary, png_name: String) -> void:
	if src.is_empty() or not src.has("data"):
		d.erase(KEY)
		return
	d[KEY] = {"png": png_name, "size": int(src["size"]), "sha": sha(src["data"]), "uv": String(src["uv"])}


static func write_png(src: Dictionary, abs_path: String) -> bool:
	if src.is_empty() or not src.has("data"):
		return false
	var n := int(src["size"])
	var img := Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, src["data"])
	return img.save_png(abs_path) == OK


## {} = the scene has no texture; {"warn"} = it cannot be used (the text says why); {"data", "size", "uv", "sha"} = ready to apply
static func load_for(scene_dir: String, d: Dictionary) -> Dictionary:
	if not d.has(KEY):
		return {}
	var k: Dictionary = d[KEY]
	var png := String(k.get("png", ""))
	var abs_png := scene_dir.path_join(png)
	if png == "" or not FileAccess.file_exists(abs_png):
		return {"warn": "texture paint: %s is missing beside the scene, so the scene opens without its painted texture" % png}
	var img := Image.load_from_file(abs_png)
	if img == null or img.is_empty():
		return {"warn": "texture paint: %s could not be read, so the painted texture is not used" % png}
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var data := img.get_data()
	if sha(data) != String(k.get("sha", "")):
		return {"warn": "texture paint: %s is not the texture the scene recorded (its SHA-256 differs), so it is not used" % png}
	return {"data": data, "size": img.get_width(), "uv": String(k.get("uv", "")), "sha": String(k.get("sha", ""))}


## paint the loaded texture into tp when it is the same size and was made on the same UVs; true = applied
static func apply(tp: KMeshTPaint, got: Dictionary, uv: String) -> bool:
	if tp == null or not got.has("data"):
		return false
	if int(got["size"]) != tp.size or String(got["uv"]) != uv:
		return false
	tp.set_data(got["data"])
	return true


## the scene's load step: the loaded texture waits in the paint UI for Texture mode; a warning goes to the status line
static func from_scene(m: Node, d: Dictionary, scene_file: String) -> void:
	var v: Node = m.get_node_or_null(KMeshVPaintUI.NODE)
	var got := load_for(scene_file.get_base_dir(), d)
	if got.has("warn"):
		m._say(String(got["warn"]))
		got = {}
	if got.is_empty():
		if v != null:
			v.tex_pending = {}
		return
	KMeshVPaintUI.of(m).tex_pending = got
