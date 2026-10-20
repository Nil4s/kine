## qr_share.gd - SHARE BY QR CODE (ROADMAP R26, Nick's idea): a pose, or a short scene, packed into the smallest text that
## still opens exactly, drawn as a QR image anyone can photograph, and read back from a picture or the webcam. No server,
## no account: the picture IS the file.
##
## THE FORM  "KINE1:" + base45( flag + [raw length] + body )          (the tag carries the version; KINE2: would be a new form)
##   flag 0 = body as is, 1 = body deflated (the smaller of the two is kept); base45 (RFC 9285) because its 45 characters
##   are exactly the QR ALPHANUMERIC set, which packs 5.5 bits a character: 4296 characters (2864 bytes of data) in the
##   biggest code (version 40-L) against 2953 bytes in binary mode that would have to be base64'd (2214 bytes of data).
##   body = kind (1 pose | 2 scene) then
##     pose : block                                        block = the joints that CHANGED, then the hips
##     scene: ncards, fps, name, then per card: name, move (cs, zigzag), hold (cs), block
##   block = a bit per joint of Body.ORDER (set = differs from the card before; the first card is compared with REST, so a
##           pose carries only the joints that are not at rest), then for each set joint bend/side/twist as zigzag varints of
##           the change in TENTHS of a degree; then the hips' offset as zigzag varints of the change in millimetres.
## QUANTISATION: 0.1 deg (each angle is within 0.05 deg of the original), 1 mm for the hips. NOT carried: weapons, contacts,
## props, face, shots, layers (a QR is for a pose or a combo; the .kinepack file carries a whole scene).
## CAPACITY (ISO 18004, version 40): alphanumeric mode L 4296 / M 3391 / Q 2420 / H 1852 characters. The drawer uses level M
## (a phone photo survives a dirty or tilted print) and falls back to L when M is too small.
## READING: tools/qr_tool.py (segno draws, zxing-cpp reads; BSD / Apache). Needs  pip install segno zxing-cpp pillow.
class_name QrShare
extends RefCounted

const TAG := "KINE1:"
const B45 := "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:"
const CAP_L := 4296            # alphanumeric characters in a version 40-L QR
const CAP_M := 3391
const MAX_CARDS := 300
const MAX_RAW := 65536         # the unpacked body, checked before it is read (a deflate bomb is refused)
const MAX_ANG := 360.0
const OUT_DIR := "user://qr"   # the pictures (and their temporary text) live here; never scenes/, poses/ or data/


# ---------------------------------------------------------------- base45 (RFC 9285)
static func b45_encode(b: PackedByteArray) -> String:
	var s := ""
	var i := 0
	while i + 1 < b.size():
		var n := b[i] * 256 + b[i + 1]
		s += B45[n % 45] + B45[(n / 45) % 45] + B45[n / 2025]
		i += 2
	if i < b.size():
		s += B45[b[i] % 45] + B45[b[i] / 45]
	return s


## "" bytes + ok=false when the text has a character outside the 45 or a group that is too big
static func b45_decode(s: String) -> Variant:
	var out := PackedByteArray()
	var i := 0
	var n := s.length()
	if n % 3 == 1:
		return null
	while i < n:
		var c := B45.find(s[i])
		var d := B45.find(s[i + 1])
		if c < 0 or d < 0:
			return null
		if i + 2 < n:
			var e := B45.find(s[i + 2])
			if e < 0:
				return null
			var v := c + d * 45 + e * 2025
			if v > 65535:
				return null
			out.append(v / 256)
			out.append(v % 256)
			i += 3
		else:
			var v2 := c + d * 45
			if v2 > 255:
				return null
			out.append(v2)
			i += 2
	return out


# ---------------------------------------------------------------- varints
static func _zz(v: int) -> int:
	return (v << 1) ^ (v >> 63)


static func _unzz(u: int) -> int:
	return (u >> 1) ^ -(u & 1)


static func _put(b: PackedByteArray, u: int) -> void:
	while u >= 128:
		b.append((u & 127) | 128)
		u >>= 7
	b.append(u)


class Rd:
	var b: PackedByteArray
	var i := 0
	var bad := false

	func _init(bytes: PackedByteArray) -> void:
		b = bytes

	func u() -> int:
		var v := 0
		var sh := 0
		while true:
			if i >= b.size() or sh > 42:
				bad = true
				return 0
			var x := b[i]
			i += 1
			v |= (x & 127) << sh
			if x < 128:
				return v
			sh += 7
		return 0

	func z() -> int:
		return QrShare._unzz(u())

	func text() -> String:
		var n := u()
		if bad or n > 200 or i + n > b.size():
			bad = true
			return ""
		var s := b.slice(i, i + n).get_string_from_utf8()
		i += n
		return s


static func _put_str(b: PackedByteArray, s: String) -> void:
	var u := s.to_utf8_buffer()
	if u.size() > 120:
		u = u.slice(0, 120)
		while u.size() > 0 and (u[u.size() - 1] & 0xC0) == 0x80:   # do not cut a letter in half
			u = u.slice(0, u.size() - 1)
		if u.size() > 0 and u[u.size() - 1] >= 0xC0:
			u = u.slice(0, u.size() - 1)
	_put(b, u.size())
	b.append_array(u)


# ---------------------------------------------------------------- the pose block
static func _tenths(ang: Dictionary, j: String) -> Array:
	var a: Vector3 = ang.get(j, Vector3.ZERO)
	return [roundi(a.x * 10.0), roundi(a.y * 10.0), roundi(a.z * 10.0)]


static func _put_block(b: PackedByteArray, ang: Dictionary, off: Vector3, prev: Dictionary) -> void:
	var order: Array = Body.ORDER
	var mask := PackedByteArray()
	mask.resize((order.size() + 7) / 8)
	var body := PackedByteArray()
	for k in order.size():
		var j: String = order[k]
		var q := _tenths(ang, j)
		var p: Array = prev["t"].get(j, [0, 0, 0])
		if q != p:
			mask[k >> 3] |= 1 << (k & 7)
			for a in 3:
				_put(body, _zz(q[a] - p[a]))
		prev["t"][j] = q
	b.append_array(mask)
	b.append_array(body)
	var mm := [roundi(off.x * 1000.0), roundi(off.y * 1000.0), roundi(off.z * 1000.0)]
	var pm: Array = prev["mm"]
	for a in 3:
		_put(b, _zz(mm[a] - pm[a]))
	prev["mm"] = mm


static func _read_block(r: Rd, prev: Dictionary) -> Dictionary:
	var order: Array = Body.ORDER
	var nm := (order.size() + 7) / 8
	if r.i + nm > r.b.size():
		r.bad = true
		return {}
	var mask := r.b.slice(r.i, r.i + nm)
	r.i += nm
	var ang := {}
	for k in order.size():
		var j: String = order[k]
		if (mask[k >> 3] >> (k & 7)) & 1:
			var q: Array = (prev["t"].get(j, [0, 0, 0]) as Array).duplicate()
			for a in 3:
				q[a] += r.z()
			prev["t"][j] = q
		var t: Array = prev["t"].get(j, [0, 0, 0])
		if t != [0, 0, 0]:
			ang[j] = Vector3(t[0], t[1], t[2]) / 10.0
	var mm: Array = (prev["mm"] as Array).duplicate()
	for a in 3:
		mm[a] += r.z()
	prev["mm"] = mm
	return {"ang": ang, "off": Vector3(mm[0], mm[1], mm[2]) / 1000.0}


static func _prev0() -> Dictionary:
	return {"t": {}, "mm": [0, 0, 0]}


# ---------------------------------------------------------------- pack / unpack
static func _wrap(body: PackedByteArray) -> String:
	var z := body.compress(FileAccess.COMPRESSION_DEFLATE)
	var out := PackedByteArray()
	if z.size() + 3 < body.size():
		out.append(1)
		_put(out, body.size())
		out.append_array(z)
	else:
		out.append(0)
		out.append_array(body)
	return TAG + b45_encode(out)


## the pose (angles in degrees by joint, the hips' offset in metres) as KINE1: text
static func pack_pose(ang: Dictionary, off: Vector3) -> String:
	var b := PackedByteArray()
	b.append(1)
	_put_block(b, ang, off, _prev0())
	return _wrap(b)


## cards = [{name, move, hold, ang, off}] in order
static func pack_scene(scene_name: String, fps: int, cards: Array) -> String:
	var b := PackedByteArray()
	b.append(2)
	_put(b, cards.size())
	b.append(clampi(fps, 1, 255))
	_put_str(b, scene_name)
	var prev := _prev0()
	for c in cards:
		_put_str(b, String(c.get("name", "")))
		_put(b, _zz(roundi(float(c.get("move", -1.0)) * 100.0)))
		_put(b, maxi(0, roundi(float(c.get("hold", 0.3)) * 100.0)))
		_put_block(b, c["ang"], c["off"], prev)
	return _wrap(b)


## a scene's cards (scene.gd's dictionaries) read as angles: what pack_scene takes
static func view_cards(cards: Array) -> Array:
	var out := []
	for c in cards:
		var p: Dictionary = c.get("pose", {})
		var ang := {}
		for j in p.get("joints", {}):
			var x: Dictionary = p["joints"][j]
			ang[j] = Vector3(float(x.get("bend", 0)), float(x.get("side", 0)), float(x.get("twist", 0)))
		var o: Array = p.get("offset", [0, 0, 0])
		out.append({"name": c.get("name", ""), "move": float(c.get("move", -1.0)), "hold": float(c.get("hold", 0.3)),
			"ang": ang, "off": Vector3(o[0], o[1], o[2])})
	return out


## KINE1: text -> {ok, why, kind: "pose"|"scene", name, fps, cards: [{name, move, hold, ang, off}]}. Every refusal names a next step.
static func unpack(text: String) -> Dictionary:
	text = text.strip_edges()
	if not text.begins_with(TAG):
		if text.begins_with("KINE") and text.length() > 5 and text[4].is_valid_int():
			return {"ok": false, "why": "this code was made by a newer Kine (%s): update Kine, then open it again" % text.substr(0, 6)}
		return {"ok": false, "why": "that QR is not a Kine code (it does not start with KINE1:): ask your friend to send a Kine one, or open another picture"}
	var raw: Variant = b45_decode(text.substr(TAG.length()))
	if raw == null or (raw as PackedByteArray).is_empty():
		return {"ok": false, "why": "this Kine code is damaged (not valid base45): photograph it again, straight on and sharp"}
	var pb: PackedByteArray = raw
	var body := PackedByteArray()
	if pb[0] == 1:
		var r0 := Rd.new(pb)
		r0.i = 1
		var n := r0.u()
		if r0.bad or n <= 0 or n > MAX_RAW:
			return {"ok": false, "why": "this Kine code claims %d bytes unpacked, more than a pose or short scene ever is (limit %d): it is not a Kine code, or it is damaged" % [n, MAX_RAW]}
		body = pb.slice(r0.i).decompress(n, FileAccess.COMPRESSION_DEFLATE)
		if body.size() != n:
			return {"ok": false, "why": "this Kine code is damaged (it does not unpack): photograph it again, straight on and sharp"}
	elif pb[0] == 0:
		body = pb.slice(1)
	else:
		return {"ok": false, "why": "this Kine code has an unknown flag: update Kine, then open it again"}
	var r := Rd.new(body)
	if body.is_empty():
		return {"ok": false, "why": "this Kine code is empty: ask your friend to share again"}
	var kind := body[0]
	r.i = 1
	var res := {"ok": true, "why": "", "cards": []}
	var prev := _prev0()
	if kind == 1:
		res["kind"] = "pose"
		var blk := _read_block(r, prev)
		if r.bad:
			return {"ok": false, "why": "this Kine code is cut short: photograph the whole code and try again"}
		res["cards"].append({"name": "shared pose", "move": -1.0, "hold": 0.3, "ang": blk["ang"], "off": blk["off"]})
	elif kind == 2:
		res["kind"] = "scene"
		var n := r.u()
		var fps := r.i
		fps = body[r.i] if r.i < body.size() else 30
		r.i += 1
		res["fps"] = fps
		res["name"] = r.text()
		if r.bad or n < 1 or n > MAX_CARDS:
			return {"ok": false, "why": "this Kine code lists %d cards (1 to %d are allowed): it is damaged, ask your friend to share again" % [n, MAX_CARDS]}
		for _k in n:
			var nm := r.text()
			var mv := float(r.z()) / 100.0
			var hd := float(r.u()) / 100.0
			var blk := _read_block(r, prev)
			if r.bad:
				return {"ok": false, "why": "this Kine code is cut short: photograph the whole code and try again"}
			res["cards"].append({"name": nm, "move": mv, "hold": hd, "ang": blk["ang"], "off": blk["off"]})
	else:
		return {"ok": false, "why": "this Kine code holds something this Kine does not know (kind %d): update Kine" % kind}
	for c in res["cards"]:
		for j in c["ang"]:
			var a: Vector3 = c["ang"][j]
			if absf(a.x) > MAX_ANG or absf(a.y) > MAX_ANG or absf(a.z) > MAX_ANG:
				return {"ok": false, "why": "this Kine code holds an angle beyond %d degrees: it is damaged or not from Kine" % int(MAX_ANG)}
	return res


## decoded cards as scene.gd cards (a pose dictionary each, built on a scratch body so pos / G / A are the real ones)
static func to_scene_cards(cards: Array) -> Array:
	var tmp := Body.new()
	tmp.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var out := []
	for c in cards:
		var joints := {}
		for j in c["ang"]:
			var a: Vector3 = c["ang"][j]
			joints[j] = {"bend": a.x, "side": a.y, "twist": a.z}
		var o: Vector3 = c["off"]
		tmp.from_dict({"offset": [o.x, o.y, o.z], "joints": joints})
		out.append({"name": c["name"], "pose": tmp.to_dict(), "move": c["move"], "hold": c["hold"]})
	return out


# ---------------------------------------------------------------- capacity
## {chars, limit, fits, level, bytes_data}: how big this text is against the biggest QR
static func capacity(text: String) -> Dictionary:
	var n := text.length()
	return {"chars": n, "limit": CAP_L, "fits": n <= CAP_L, "level": "M" if n <= CAP_M else ("L" if n <= CAP_L else ""),
		"data_bytes": n * 2 / 3, "pct": 100.0 * n / CAP_L}


## the most cards from the start of `cards` (view_cards form) that fit one code
static func max_cards(scene_name: String, fps: int, cards: Array) -> int:
	var lo := 0
	var hi := cards.size()
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if pack_scene(scene_name, fps, cards.slice(0, mid)).length() <= CAP_L:
			lo = mid
		else:
			hi = mid - 1
	return lo


# ---------------------------------------------------------------- the picture (tools/qr_tool.py)
static func _tool() -> String:
	return ProjectSettings.globalize_path("res://tools/qr_tool.py")


static func _run(python: String, args: PackedStringArray) -> Dictionary:
	var o := []
	var rc := OS.execute(python, args, o, true)
	if rc == -1:
		return {"ok": false, "why": "\"%s\" did not start: install Python, then  pip install segno zxing-cpp pillow" % python}
	var txt := ""
	for line in (String(o[0]) if o.size() > 0 else "").split("\n"):
		if line.strip_edges().begins_with("{"):
			txt = line.strip_edges()
	var d: Variant = JSON.parse_string(txt) if txt != "" else null
	if not (d is Dictionary):
		return {"ok": false, "why": "the QR helper gave no answer (%s): run  pip install segno zxing-cpp pillow  and try again" % String(o[0] if o.size() > 0 else "").left(120)}
	return d


## draws `text` as a PNG at png_path (under user://qr/ or a path the caller chose). {ok, why, version, ecc, modules, side_px}
static func make_png(text: String, png_path: String, python := "python") -> Dictionary:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var tf := OUT_DIR + "/_text.txt"
	var f := FileAccess.open(tf, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "why": "could not write in user://qr: check the disk has room, then try again"}
	f.store_string(text)
	f.close()
	var res := _run(python, PackedStringArray([_tool(), "encode", ProjectSettings.globalize_path(tf), ProjectSettings.globalize_path(png_path)]))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tf))
	return res


## reads a QR from a picture file. {ok, why, text}
static func read_png(path: String, python := "python") -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "why": "%s is not there: pick the picture again" % path.get_file()}
	return _run(python, PackedStringArray([_tool(), "decode", ProjectSettings.globalize_path(path)]))
