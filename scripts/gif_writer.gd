class_name GifWriter
## GIF EXPORT (W13): our own encoder, no ffmpeg needed. TWO PASSES over the whole clip: pass 1 counts every pixel's colour (5 bits per channel)
## across ALL frames, median-cut splits that histogram into ONE 256-colour palette for the clip (a per-clip palette, so colours do not
## shimmer between frames); pass 2 maps each pixel through the cut's lookup and LZW-packs it. Loops forever (NETSCAPE2.0, count 0).
## Written from the GIF89a spec; no third-party code.

const BITS := 5
const NBIN := 32768   # 1 << (3 * BITS)


## frames: Array of Image (all one size). fps: frames per second (delay is whole 1/100 s, so 12 fps plays at 8 cs = 12.5 fps).
## loops: 0 = forever. fixed: the 3-3-2 palette instead (the control the per-clip palette is measured against)
## progress: optional Callable(text: String, fraction: float); a coroutine: it yields one frame per clip frame so the window repaints, so AWAIT it
static func encode(frames: Array, fps: int, loops := 0, fixed := false, progress := Callable()) -> PackedByteArray:
	var out := PackedByteArray()
	if frames.is_empty() or fps < 1:
		return out
	var w: int = (frames[0] as Image).get_width()
	var h: int = (frames[0] as Image).get_height()
	var datas: Array = []
	for f in frames:
		var im: Image = (f as Image).duplicate()
		if im.get_width() != w or im.get_height() != h:
			im.resize(w, h, Image.INTERPOLATE_BILINEAR)
		im.convert(Image.FORMAT_RGB8)
		datas.append(im.get_data())
	var pal: PackedByteArray
	var lut: PackedByteArray
	if fixed:
		pal = PackedByteArray()
		pal.resize(768)
		for i in 256:
			pal[i * 3] = int(round(((i >> 5) & 7) * 255.0 / 7.0))
			pal[i * 3 + 1] = int(round(((i >> 2) & 7) * 255.0 / 7.0))
			pal[i * 3 + 2] = int(round((i & 3) * 255.0 / 3.0))
		lut = PackedByteArray()
		lut.resize(NBIN)
		for b in NBIN:
			var r := (b >> 10) & 31
			var g := (b >> 5) & 31
			var bl := b & 31
			lut[b] = ((r >> 2) << 5) | ((g >> 2) << 2) | (bl >> 3)
	else:
		var hist := PackedInt32Array()   # pass 1
		hist.resize(NBIN)
		var fi := 0
		for d in datas:
			if progress.is_valid():
				progress.call("Choosing the colours", 0.4 * fi / datas.size())
				await Engine.get_main_loop().process_frame
			fi += 1
			var dd: PackedByteArray = d
			var n := dd.size()
			var i := 0
			while i < n:
				hist[((dd[i] >> 3) << 10) | ((dd[i + 1] >> 3) << 5) | (dd[i + 2] >> 3)] += 1
				i += 3
		var cut := _median_cut(hist, 256)
		pal = cut[0]
		lut = cut[1]
	out.append_array("GIF89a".to_ascii_buffer())
	_u16(out, w)
	_u16(out, h)
	out.append(0xF7)   # global table, 8 bits colour res, 256 entries
	out.append(0)
	out.append(0)
	out.append_array(pal)
	out.append(0x21); out.append(0xFF); out.append(11)   # NETSCAPE2.0 loop count
	out.append_array("NETSCAPE2.0".to_ascii_buffer())
	out.append(3); out.append(1)
	_u16(out, loops)
	out.append(0)
	var delay := maxi(2, int(round(100.0 / fps)))
	var fj := 0
	for d in datas:   # pass 2
		if progress.is_valid():
			progress.call("Writing the GIF", 0.4 + 0.6 * fj / datas.size())
			await Engine.get_main_loop().process_frame
		fj += 1
		var dd: PackedByteArray = d
		var idx := PackedByteArray()
		var np := w * h
		idx.resize(np)
		var j := 0
		for p in np:
			idx[p] = lut[((dd[j] >> 3) << 10) | ((dd[j + 1] >> 3) << 5) | (dd[j + 2] >> 3)]
			j += 3
		out.append(0x21); out.append(0xF9); out.append(4); out.append(0)   # graphic control: no disposal, no transparency
		_u16(out, delay)
		out.append(0); out.append(0)
		out.append(0x2C)
		_u16(out, 0); _u16(out, 0); _u16(out, w); _u16(out, h)
		out.append(0)
		out.append(8)
		var lz := _lzw(idx)
		var k := 0
		while k < lz.size():
			var n := mini(255, lz.size() - k)
			out.append(n)
			out.append_array(lz.slice(k, k + n))
			k += n
		out.append(0)
	out.append(0x3B)
	return out


static func write(path: String, frames: Array, fps: int, loops := 0, progress := Callable()) -> bool:
	var b: PackedByteArray = await encode(frames, fps, loops, false, progress)
	if b.is_empty():
		return false
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(b)
	f.close()
	return true


## the PNG frames of a Save video folder (frame_0000.png ...) -> one GIF, width px wide (0 = as filmed)
static func from_dir(dir: String, fps: int, gif: String, width := 480, progress := Callable()) -> bool:
	var names: Array = []
	for n in DirAccess.get_files_at(dir):
		if String(n).begins_with("frame_") and String(n).ends_with(".png"):
			names.append(n)
	names.sort()
	var frames: Array = []
	for n in names:
		var im := Image.load_from_file(dir.path_join(n))
		if im == null or im.is_empty():
			continue
		if width > 0 and im.get_width() > width:
			im.resize(width, maxi(1, int(round(im.get_height() * width / float(im.get_width())))), Image.INTERPOLATE_LANCZOS)
		frames.append(im)
	return await write(gif, frames, fps, 0, progress)


static func _u16(b: PackedByteArray, v: int) -> void:
	b.append(v & 255)
	b.append((v >> 8) & 255)


## median cut over the 5-bit histogram -> [palette (768 bytes), lut (NBIN bin -> palette index)]
static func _median_cut(hist: PackedInt32Array, ncol: int) -> Array:
	var used := PackedInt32Array()
	for b in NBIN:
		if hist[b] > 0:
			used.append(b)
	var boxes: Array = [used]
	var done: Array = []   # boxes that cannot split (one bin)
	while boxes.size() + done.size() < ncol:
		var bi := -1
		var best := -1.0
		for i in boxes.size():
			var bx: PackedInt32Array = boxes[i]
			if bx.size() < 2:
				continue
			var tot := 0
			for b in bx:
				tot += hist[b]
			var sc := float(tot)   # split the most populated box
			if sc > best:
				best = sc
				bi = i
		if bi < 0:
			break
		var box: PackedInt32Array = boxes[bi]
		var lo: Array[int] = [31, 31, 31]
		var hi: Array[int] = [0, 0, 0]
		for b in box:
			var c: Array[int] = [(b >> 10) & 31, (b >> 5) & 31, b & 31]
			for k in 3:
				lo[k] = mini(lo[k], c[k])
				hi[k] = maxi(hi[k], c[k])
		var ax := 0   # widest channel, green weighted (eye is most sensitive)
		var wid: int = (hi[0] - lo[0]) * 3
		if (hi[1] - lo[1]) * 4 > wid:
			ax = 1
			wid = (hi[1] - lo[1]) * 4
		if (hi[2] - lo[2]) * 2 > wid:
			ax = 2
		var sh := 10 - 5 * ax
		var arr: Array = Array(box)
		arr.sort_custom(func(a: int, b: int) -> bool: return ((a >> sh) & 31) < ((b >> sh) & 31))
		var tot2 := 0
		for b in arr:
			tot2 += hist[b]
		var acc := 0
		var cutk := 1
		for i in arr.size():
			acc += hist[arr[i]]
			if acc * 2 >= tot2:
				cutk = clampi(i + 1, 1, arr.size() - 1)
				break
		boxes.remove_at(bi)
		boxes.append(PackedInt32Array(arr.slice(0, cutk)))
		boxes.append(PackedInt32Array(arr.slice(cutk)))
	boxes.append_array(done)
	var pal := PackedByteArray()
	pal.resize(768)
	var lut := PackedByteArray()
	lut.resize(NBIN)
	for i in boxes.size():
		var bx: PackedInt32Array = boxes[i]
		var sr := 0.0
		var sg := 0.0
		var sb := 0.0
		var tot := 0.0
		for b in bx:
			var n: float = hist[b]
			sr += ((b >> 10) & 31) * n
			sg += ((b >> 5) & 31) * n
			sb += (b & 31) * n
			tot += n
			lut[b] = i
		if tot > 0.0:
			pal[i * 3] = clampi(int(round((sr / tot) * 8.0 + 3.5)), 0, 255)
			pal[i * 3 + 1] = clampi(int(round((sg / tot) * 8.0 + 3.5)), 0, 255)
			pal[i * 3 + 2] = clampi(int(round((sb / tot) * 8.0 + 3.5)), 0, 255)
	# bins never seen get the nearest palette entry (only matters for the fixed-LUT shape; pass 2 only reads seen bins)
	return [pal, lut]


## GIF LZW, minimum code size 8
static func _lzw(idx: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	var cur := 0
	var nb := 0
	var clear := 256
	var eoi := 257
	var dict := {}
	var next := 258
	var size := 9
	# emit clear
	cur = clear
	nb = size
	var prefix := -1
	for v in idx:
		if prefix < 0:
			prefix = v
			continue
		var key := (prefix << 8) | v
		var hit = dict.get(key)
		if hit != null:
			prefix = hit
			continue
		cur |= prefix << nb
		nb += size
		while nb >= 8:
			out.append(cur & 255)
			cur >>= 8
			nb -= 8
		if next < 4096:
			dict[key] = next
			next += 1
			if next - 1 == (1 << size) and size < 12:
				size += 1
		else:
			cur |= clear << nb
			nb += size
			while nb >= 8:
				out.append(cur & 255)
				cur >>= 8
				nb -= 8
			dict.clear()
			next = 258
			size = 9
		prefix = v
	if prefix >= 0:
		cur |= prefix << nb
		nb += size
		while nb >= 8:
			out.append(cur & 255)
			cur >>= 8
			nb -= 8
	cur |= eoi << nb
	nb += size
	while nb > 0:
		out.append(cur & 255)
		cur >>= 8
		nb -= 8
	return out


## DECODER (an independent check that the file reads back): -> {w, h, loops, delay_cs, frames: [PackedByteArray RGB]}; {} = not a GIF we wrote
static func decode(b: PackedByteArray) -> Dictionary:
	if b.size() < 13 or b.slice(0, 6).get_string_from_ascii() != "GIF89a":
		return {}
	var w := b[6] | (b[7] << 8)
	var h := b[8] | (b[9] << 8)
	var pos := 13
	var pal := PackedByteArray()
	if b[10] & 0x80:
		var n := 3 * (1 << ((b[10] & 7) + 1))
		pal = b.slice(pos, pos + n)
		pos += n
	var res := {"w": w, "h": h, "loops": -1, "delay_cs": 0, "frames": []}
	while pos < b.size():
		var t := b[pos]
		pos += 1
		if t == 0x3B:
			break
		if t == 0x21:
			var lab := b[pos]
			pos += 1
			if lab == 0xF9:
				res["delay_cs"] = b[pos + 2] | (b[pos + 3] << 8)
			elif lab == 0xFF and b.slice(pos + 1, pos + 12).get_string_from_ascii() == "NETSCAPE2.0":
				res["loops"] = b[pos + 14] | (b[pos + 15] << 8)
			while b[pos] != 0:
				pos += b[pos] + 1
			pos += 1
		elif t == 0x2C:
			pos += 8
			var fl := b[pos]
			pos += 1
			var lp := pal
			if fl & 0x80:
				var n2 := 3 * (1 << ((fl & 7) + 1))
				lp = b.slice(pos, pos + n2)
				pos += n2
			var mcs := b[pos]
			pos += 1
			var data := PackedByteArray()
			while b[pos] != 0:
				data.append_array(b.slice(pos + 1, pos + 1 + b[pos]))
				pos += b[pos] + 1
			pos += 1
			var ix := _unlzw(data, mcs, w * h)
			var rgb := PackedByteArray()
			rgb.resize(w * h * 3)
			for i in mini(ix.size(), w * h):
				rgb[i * 3] = lp[ix[i] * 3]
				rgb[i * 3 + 1] = lp[ix[i] * 3 + 1]
				rgb[i * 3 + 2] = lp[ix[i] * 3 + 2]
			(res["frames"] as Array).append(rgb)
		else:
			return {}
	return res


static func _unlzw(data: PackedByteArray, mcs: int, want: int) -> PackedByteArray:
	var out := PackedByteArray()
	var clear := 1 << mcs
	var eoi := clear + 1
	var table: Array = []
	var size := mcs + 1
	var next := eoi + 1
	var cur := 0
	var nb := 0
	var prev := PackedByteArray()
	var have_prev := false
	var p := 0
	while true:
		while nb < size and p < data.size():
			cur |= data[p] << nb
			nb += 8
			p += 1
		if nb < size:
			break
		var code := cur & ((1 << size) - 1)
		cur >>= size
		nb -= size
		if code == clear:
			table.clear()
			size = mcs + 1
			next = eoi + 1
			have_prev = false
			continue
		if code == eoi:
			break
		var ent: PackedByteArray
		if code < clear:
			ent = PackedByteArray([code])
		elif code - eoi - 1 < table.size():
			ent = table[code - eoi - 1]
		elif have_prev:
			ent = prev.duplicate()
			ent.append(prev[0])
		else:
			break
		out.append_array(ent)
		if have_prev and next < 4096:
			var ne := prev.duplicate()
			ne.append(ent[0])
			table.append(ne)
			next += 1
			if next == (1 << size) and size < 12:
				size += 1
		prev = ent
		have_prev = true
		if out.size() >= want:
			break
	return out
