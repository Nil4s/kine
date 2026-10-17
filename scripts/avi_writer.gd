class_name AviWriter
## MJPEG AVI, written by hand (round 41, GATES WW6). One video stream, every frame a JPEG, no audio.
## Layout and struct fields follow Microsoft's "AVI RIFF File Reference"
## (https://learn.microsoft.com/en-us/windows/win32/directshow/avi-riff-file-reference):
##   RIFF 'AVI ' ( LIST hdrl ( avih, LIST strl ( strh, strf ) ), LIST movi ( 00dc ... ), idx1 )
## Chunks are padded to a WORD boundary (the pad is not in ckSize); idx1 offsets count from the 'movi' fourcc.

static func _u32(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_u32(0, v)
	return b


static func _u16(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(2)
	b.encode_u16(0, v)
	return b


static func _chunk(id: String, data: PackedByteArray) -> PackedByteArray:
	var b := PackedByteArray()
	b.append_array(id.to_ascii_buffer())
	b.append_array(_u32(data.size()))
	b.append_array(data)
	if data.size() % 2 == 1:
		b.append(0)
	return b


static func _list(kind: String, data: PackedByteArray) -> PackedByteArray:
	var b := PackedByteArray()
	b.append_array("LIST".to_ascii_buffer())
	b.append_array(_u32(data.size() + 4))
	b.append_array(kind.to_ascii_buffer())
	b.append_array(data)
	return b


## the whole file as bytes: jpgs are the frames (each a complete JPEG), w x h their size, fps the rate
static func build(jpgs: Array, w: int, h: int, fps: int) -> PackedByteArray:
	var n := jpgs.size()
	var biggest := 0
	for j in jpgs:
		biggest = maxi(biggest, (j as PackedByteArray).size())
	# AVIMAINHEADER, 14 DWORDs: us per frame, max bytes/s, padding, flags (HASINDEX 0x10), frames, initial frames,
	# streams, suggested buffer, width, height, 4 reserved
	var avih := PackedByteArray()
	for v in [1000000 / maxi(fps, 1), biggest * fps, 0, 0x10, n, 0, 1, biggest, w, h, 0, 0, 0, 0]:
		avih.append_array(_u32(v))
	# AVISTREAMHEADER: 'vids' 'MJPG', flags, priority+language, initial frames, scale, rate, start, length,
	# suggested buffer, quality, sample size, rcFrame (4 WORDs)
	var strh := PackedByteArray()
	strh.append_array("vids".to_ascii_buffer())
	strh.append_array("MJPG".to_ascii_buffer())
	for v in [0, 0, 0, 1, fps, 0, n, biggest, 0xFFFFFFFF, 0]:
		strh.append_array(_u32(v))
	for v in [0, 0, w, h]:
		strh.append_array(_u16(v))
	# BITMAPINFOHEADER (40 bytes), compression 'MJPG'
	var strf := PackedByteArray()
	strf.append_array(_u32(40))
	strf.append_array(_u32(w))
	strf.append_array(_u32(h))
	strf.append_array(_u16(1))
	strf.append_array(_u16(24))
	strf.append_array("MJPG".to_ascii_buffer())
	strf.append_array(_u32(w * h * 3))
	for v in [0, 0, 0, 0]:
		strf.append_array(_u32(v))
	var strl := _chunk("strh", strh)
	strl.append_array(_chunk("strf", strf))
	var hdrl := _chunk("avih", avih)
	hdrl.append_array(_list("strl", strl))
	var movi := PackedByteArray()
	var idx := PackedByteArray()
	for j in jpgs:
		var off := movi.size() + 4   # past the 'movi' fourcc
		idx.append_array("00dc".to_ascii_buffer())
		idx.append_array(_u32(0x10))   # AVIIF_KEYFRAME: every JPEG stands alone
		idx.append_array(_u32(off))
		idx.append_array(_u32((j as PackedByteArray).size()))
		movi.append_array(_chunk("00dc", j))
	var body := PackedByteArray()
	body.append_array("AVI ".to_ascii_buffer())
	body.append_array(_list("hdrl", hdrl))
	body.append_array(_list("movi", movi))
	body.append_array(_chunk("idx1", idx))
	var file := PackedByteArray()
	file.append_array("RIFF".to_ascii_buffer())
	file.append_array(_u32(body.size()))
	file.append_array(body)
	return file


static func write(path: String, jpgs: Array, w: int, h: int, fps: int) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(build(jpgs, w, h, fps))
	f.close()
	return true
