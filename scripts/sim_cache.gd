## sim_cache.gd - L35 SIM CACHE: one sim object's vertex positions for every frame, in one compact binary file (a point cache).
## Blender's "Bake" on a cloth / soft-body modifier, Maya's "Create Geometry Cache": the timeline reads the file, it never re-simulates.
##
## FILE (little endian): HEADER bytes, then frames x verts x (float32 x, y, z) = 12 bytes a vertex, frame after frame.
##   0  "KSIM"            magic
##   4  u32 version (1)
##   8  u32 vertices      12 u32 frames      16 u32 fps
##  24  key, 32 bytes, zero padded: the md5 hex of the scene inputs the sim was made from (the app compares it to mark a cache stale)
##  56  data md5, 16 raw bytes: over every byte after the header. Checked ONCE when the file opens (a corrupted byte refuses the file),
##      not per frame.
## So the file size is exactly HEADER + 12 x vertices x frames; open() refuses any other length.
## The positions are Godot's own float32 Vector3, so a read-back is bit-exact. A frame read is one slice of the loaded bytes and a
## typed copy (to_vector3_array), no per-vertex GDScript: measured under 0.5 ms for 5041 vertices (tests/simcache_test.gd bar 4), so no
## native door was needed.
class_name SimCache
extends RefCounted

const HEADER := 80
const VERSION := 1

var verts := 0
var frames := 0
var fps := 30
var key := ""
var buf := PackedByteArray()   # the whole file


static func size_for(v: int, f: int) -> int:
	return HEADER + 12 * v * f


## writes `frames` (an Array of PackedVector3Array, all the same size) to path. false on any problem (nothing is left half written)
static func write(path: String, frames_in: Array, fps_in: int, key_in: String) -> bool:
	if frames_in.is_empty():
		return false
	var v: int = (frames_in[0] as PackedVector3Array).size()
	var data := PackedByteArray()
	for f in frames_in:
		var pf := f as PackedVector3Array
		if pf.size() != v:
			return false
		var b := pf.to_byte_array()
		if b.size() != 12 * v:
			return false   # a double-precision build: the format is float32
		data.append_array(b)
	var h := PackedByteArray()
	h.resize(HEADER)
	h.fill(0)
	h.encode_u8(0, 75)
	h.encode_u8(1, 83)
	h.encode_u8(2, 73)
	h.encode_u8(3, 77)
	h.encode_u32(4, VERSION)
	h.encode_u32(8, v)
	h.encode_u32(12, frames_in.size())
	h.encode_u32(16, fps_in)
	var kb := key_in.to_utf8_buffer()
	for i in mini(kb.size(), 32):
		h.encode_u8(24 + i, kb[i])
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_MD5)
	hc.update(data)
	var dh := hc.finish()
	for i in 16:
		h.encode_u8(56 + i, dh[i])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var tmp := path + ".tmp"
	var fa := FileAccess.open(tmp, FileAccess.WRITE)
	if fa == null:
		return false
	fa.store_buffer(h)
	fa.store_buffer(data)
	fa.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path)) == OK


## the cache in path, or null when it is missing, the wrong length, not a KSIM file, or (check) any byte after the header changed
static func open(path: String, check := true) -> SimCache:
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return null
	var b := fa.get_buffer(fa.get_length())
	fa.close()
	if b.size() < HEADER or b[0] != 75 or b[1] != 83 or b[2] != 73 or b[3] != 77 or b.decode_u32(4) != VERSION:
		return null
	var v := b.decode_u32(8)
	var f := b.decode_u32(12)
	if f == 0 or b.size() != size_for(v, f):
		return null
	if check:
		var hc := HashingContext.new()
		hc.start(HashingContext.HASH_MD5)
		hc.update(b.slice(HEADER))
		var dh := hc.finish()
		for i in 16:
			if dh[i] != b[56 + i]:
				return null
	var c := SimCache.new()
	c.buf = b
	c.verts = v
	c.frames = f
	c.fps = b.decode_u32(16)
	var kb := b.slice(24, 56)
	var n := 0
	while n < 32 and kb[n] != 0:
		n += 1
	c.key = kb.slice(0, n).get_string_from_utf8()
	return c


## frame k (clamped to the file)
func frame(k: int) -> PackedVector3Array:
	return raw_frame(buf, verts, HEADER, clampi(k, 0, frames - 1))


## the bytes of frame k as vertices, for a header of `header` bytes (a wrong one reads wrong numbers: the test's planted control)
static func raw_frame(b: PackedByteArray, v: int, header: int, k: int) -> PackedVector3Array:
	var o := header + 12 * v * k
	return b.slice(o, o + 12 * v).to_vector3_array()
