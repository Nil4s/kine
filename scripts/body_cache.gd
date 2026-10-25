class_name BodyCache
extends RefCounted
## THE BODY CACHE: the body build's deterministic results (the split-parts triangle classification, the corrective weights
## and girth shapes) saved under user://cache, so a later start loads them instead of recomputing. The key is a digest of
## the INPUTS themselves (the mesh arrays, the skin binds, the joint rests), not of the files: a painted skin sidecar changes
## the inputs, and the key must follow it. A missing, corrupt or stale file (signature mismatch) falls back to computing.
## Only pure data (numbers, strings, arrays, dictionaries, packed arrays) is cached; anything else is computed every time.

const VERSION := 1
static var dir := "user://cache"   # a test points this at its own folder
static var enabled := true
static var stats := {"hit": 0, "miss": 0, "bad": 0}


## the value of compute(), from the cache when the inputs match and the file checks out
static func fetch(name: String, inputs: Array, compute: Callable) -> Variant:
	if not enabled:
		return compute.call()
	var path := "%s/%s_%s.bin" % [dir, name, md5(var_to_bytes([VERSION, inputs]))]
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var b := f.get_buffer(f.get_length())
			f.close()
			var env = bytes_to_var(b) if b.size() > 0 else null
			if env is Dictionary and env.has("v") and env.has("sig") and String(env["sig"]) == _sig(env["v"]):
				stats["hit"] += 1
				return env["v"]
		stats["bad"] += 1
	var v = compute.call()
	stats["miss"] += 1
	if _pure(v):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		var w := FileAccess.open(path, FileAccess.WRITE)
		if w != null:
			w.store_buffer(var_to_bytes({"v": v, "sig": _sig(v)}))
			w.close()
	return v


static func _sig(v) -> String:
	return md5(var_to_bytes(v))


## the md5 of bytes (a PackedByteArray has no digest method)
static func md5(b: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_MD5)
	h.update(b)
	return h.finish().hex_encode()


static func _pure(v) -> bool:
	if v == null or v is bool or v is int or v is float or v is String or v is StringName:
		return true
	if v is Array:
		for x in v:
			if not _pure(x):
				return false
		return true
	if v is Dictionary:
		for k in v:
			if not (_pure(k) and _pure(v[k])):
				return false
		return true
	return typeof(v) in [TYPE_VECTOR2, TYPE_VECTOR3, TYPE_TRANSFORM3D, TYPE_BASIS, TYPE_COLOR, TYPE_PACKED_BYTE_ARRAY,
		TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY,
		TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY, TYPE_PACKED_STRING_ARRAY]
