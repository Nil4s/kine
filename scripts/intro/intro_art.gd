## THE INTRO'S ARTWORK (scripts/intro/intro.gd plays it): the stencil K and the "Kine" wordmark as polygons on the brand's
## 64-unit grid (assets/brand/README.md, kine_logo.svg; y down), the easing curves every concept moves on, and the END
## CARD all three land on: the mark slides left, the whole wordmark glides out of it in one motion, and
## "TESCHIMA STUDIOS" settles underneath in the default font. Everything is drawn as geometry, so it is crisp at any size.
class_name IntroArt
extends RefCounted

const BG := Color("16171B")
const BONE := Color("ECEFF4")
const BLUE := Color("73BFFF")
const GOLD := Color("FFC733")
const STUDIO := "Teschima Studios"

# THE MARK. Stem 9 wide; each chevron limb is a 9.5-wide stroke from the apex (31, 32) at 45 deg, butt-ended there and cut
# flat at y 12 and 52 (H = 4.75 / sqrt 2). The diamond sits on the apex with a half-diagonal of 8.
const STEM := [Vector2(10, 12), Vector2(19, 12), Vector2(19, 52), Vector2(10, 52)]
const UPPER := [Vector2(27.641243, 28.641243), Vector2(34.358757, 35.358757), Vector2(57.717514, 12), Vector2(44.282486, 12)]
const LOWER := [Vector2(34.358757, 28.641243), Vector2(57.717514, 52), Vector2(44.282486, 52), Vector2(27.641243, 35.358757)]
const DIAMOND := [Vector2(31, 24), Vector2(39, 32), Vector2(31, 40), Vector2(23, 32)]
const APEX := Vector2(31, 32)
const MARK_C := Vector2(33.858757, 32)   # the middle of what is drawn (x 10 .. 57.7, y 12 .. 52)
const LOCK_C := 91.358757   # the lock-up's drawn middle (x 10 .. 172.7)
const LOCK_W := 162.717514

# THE WORDMARK, in the logo's units (translate 80 14, scale 0.9 already applied by word_pts). One entry per letter as it
# types in: [polygons, gold?]. The e's counter is cut into four solid pieces (a filled polygon has no holes).
const WORD := [
	[[[Vector2(0, 0), Vector2(7, 0), Vector2(7, 40), Vector2(0, 40)],
		[Vector2(7, 9), Vector2(16, 0), Vector2(26, 0), Vector2(7, 19)],
		[Vector2(7, 19), Vector2(28, 40), Vector2(18, 40), Vector2(7, 29)]], 14.0],
	[[[Vector2(34, 11), Vector2(41, 11), Vector2(41, 40), Vector2(34, 40)]], 37.5],
	[[[Vector2(48, 40), Vector2(48, 11), Vector2(65, 11), Vector2(72, 18), Vector2(72, 40), Vector2(65, 40), Vector2(65, 18),
		Vector2(55, 18), Vector2(55, 40)]], 60.0],
	[[[Vector2(79, 11), Vector2(86, 11), Vector2(86, 40), Vector2(79, 40)],
		[Vector2(86, 11), Vector2(96, 11), Vector2(103, 18), Vector2(86, 18)],
		[Vector2(96, 18), Vector2(103, 18), Vector2(103, 29), Vector2(86, 29), Vector2(86, 22), Vector2(96, 22)],
		[Vector2(86, 33), Vector2(103, 33), Vector2(103, 40), Vector2(86, 40)]], 91.0],
]
const I_DOT := [Vector2(34, 0), Vector2(41, 0), Vector2(41, 7), Vector2(34, 7)]


static func word_pt(p: Vector2) -> Vector2:
	return Vector2(80, 14) + p * 0.9


# ---------------------------------------------------------------- easing (no linear tweens anywhere)

static func c01(x: float) -> float:
	return clampf(x, 0.0, 1.0)


## 0 .. 1 over [a, b]
static func k(t: float, a: float, b: float) -> float:
	return c01((t - a) / (b - a))


static func out_cubic(x: float) -> float:
	x = c01(x)
	return 1.0 - pow(1.0 - x, 3.0)


static func out_quint(x: float) -> float:
	x = c01(x)
	return 1.0 - pow(1.0 - x, 5.0)


static func in_cubic(x: float) -> float:
	x = c01(x)
	return x * x * x


static func in_out_cubic(x: float) -> float:
	x = c01(x)
	return 4.0 * x * x * x if x < 0.5 else 1.0 - pow(-2.0 * x + 2.0, 3.0) / 2.0


static func in_out_sine(x: float) -> float:
	x = c01(x)
	return -(cos(PI * x) - 1.0) / 2.0


## fast start, overshoots by about s/10, settles at 1
static func out_back(x: float, s := 1.70158) -> float:
	if x <= 0.0 or x >= 1.0:
		return 0.0 if x <= 0.0 else 1.0
	var c3 := s + 1.0
	return 1.0 + c3 * pow(x - 1.0, 3.0) + s * pow(x - 1.0, 2.0)


## anticipation (dips below 0) then overshoot (past 1), then home
static func in_out_back(x: float, s := 1.70158) -> float:
	if x <= 0.0 or x >= 1.0:
		return 0.0 if x <= 0.0 else 1.0
	var c2 := s * 1.525
	if x < 0.5:
		return (pow(2.0 * x, 2.0) * ((c2 + 1.0) * 2.0 * x - c2)) / 2.0
	return (pow(2.0 * x - 2.0, 2.0) * ((c2 + 1.0) * (x * 2.0 - 2.0) + c2) + 2.0) / 2.0


static func out_bounce(x: float) -> float:
	x = c01(x)
	const N := 7.5625
	const D := 2.75
	if x < 1.0 / D:
		return N * x * x
	if x < 2.0 / D:
		x -= 1.5 / D
		return N * x * x + 0.75
	if x < 2.5 / D:
		x -= 2.25 / D
		return N * x * x + 0.9375
	x -= 2.625 / D
	return N * x * x + 0.984375


# ---------------------------------------------------------------- drawing

static func pts(a: Array) -> PackedVector2Array:
	var p := PackedVector2Array()
	for v in a:
		p.append(v)
	return p


## mark units -> screen
static func tx(a: Array, o: Vector2, u: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	for v in a:
		p.append(o + (v as Vector2) * u)
	return p


static func area(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		var a := p[i]
		var b := p[(i + 1) % p.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5


## a filled polygon with a soft one-pixel edge (draw_colored_polygon itself has no antialiasing). Degenerate shapes
## (a piece at scale 0, a collapsed face) are skipped: triangulation would fail on them
static func fill(ci: CanvasItem, p: PackedVector2Array, col: Color) -> void:
	if p.size() < 3 or absf(area(p)) < 0.05 or col.a <= 0.002:
		return
	if Geometry2D.triangulate_polygon(p).is_empty():
		return
	ci.draw_colored_polygon(p, col)
	var c := p.duplicate()
	c.append(p[0])
	ci.draw_polyline(c, col, 1.0, true)


static func outline(ci: CanvasItem, p: PackedVector2Array, col: Color, w := 1.0) -> void:
	if p.size() < 2 or col.a <= 0.002:
		return
	var c := p.duplicate()
	c.append(p[0])
	ci.draw_polyline(c, col, w, true)


static func scaled(a: Array, about: Vector2, s: float) -> Array:
	var r := []
	for v in a:
		r.append(about + ((v as Vector2) - about) * s)
	return r


## the finished mark, flat, at origin o (unit 0 of the grid) and u px per unit
static func draw_mark(ci: CanvasItem, o: Vector2, u: float, a := 1.0) -> void:
	fill(ci, tx(STEM, o, u), Color(BONE, a))
	fill(ci, tx(UPPER, o, u), Color(BONE, a))
	fill(ci, tx(LOWER, o, u), Color(BLUE, a))
	fill(ci, tx(DIAMOND, o, u), Color(GOLD, a))


# ---------------------------------------------------------------- the layout and the end card

## where everything sits in a window of this size: u = px per mark unit, the hero origin (the mark alone, centred) and the
## final origin (the lock-up centred), the studio line's size and baseline. 16:9 or wider: sized by the height
static func layout(size: Vector2) -> Dictionary:
	var base := minf(size.x, size.y * 16.0 / 9.0)
	var u := base * 0.34 / LOCK_W
	var fs := maxi(14, int(round(base * 0.03)))
	var gap := base * 0.05
	var block := 40.0 * u + gap + fs
	var top := size.y * 0.5 - block * 0.5
	var y0 := top - 12.0 * u
	return {"size": size, "base": base, "u": u, "fs": fs, "gap": gap,
		"hero": Vector2(size.x * 0.5 - MARK_C.x * u, y0), "final": Vector2(size.x * 0.5 - LOCK_C * u, y0),
		"text_top": top + 40.0 * u + gap}


## the end card at e seconds after the concept handed over the flat mark (e < 0: not yet). Returns where the mark and the
## studio line were drawn (screen rects), for the placement checks
static func draw_end(ci: CanvasItem, L: Dictionary, e: float) -> Dictionary:
	var u: float = L["u"]
	var slide := in_out_back(k(e, 0.0, 0.55), 1.1)
	var o: Vector2 = (L["hero"] as Vector2).lerp(L["final"], slide)
	draw_mark(ci, o, u)
	var out := {"mark": Rect2(o + Vector2(10, 12) * u, Vector2(47.717514, 40) * u)}
	# the wordmark: all four letters and the i's gold dot as ONE motion, gliding out of the mark as it makes room and
	# settling with a small overshoot. Faded in as a colour (background -> bone), so touching pieces show no seams
	var word_rect := Rect2()
	var x := k(e, 0.12, 0.62)
	if x > 0.0:
		var shift := Vector2((1.0 - out_back(x, 1.5)) * -12.0, 0.0)
		var a := out_cubic(x * 1.7)
		for letter in WORD:
			for poly in letter[0]:
				var q := []
				for v in poly:
					q.append(word_pt(v) + shift)
				var sp := tx(q, o, u)
				fill(ci, sp, BG.lerp(BONE, a))
				for p2 in sp:
					word_rect = Rect2(p2, Vector2.ZERO) if word_rect.size == Vector2.ZERO and word_rect.position == Vector2.ZERO else word_rect.expand(p2)
		var dq := []
		for v in I_DOT:
			dq.append(word_pt(v) + shift)
		fill(ci, tx(dq, o, u), BG.lerp(GOLD, a))
	out["word"] = word_rect
	# the studio, underneath: the letters close in to their tracking as it fades up
	var sx := k(e, 0.42, 0.9)
	if sx > 0.0:
		var font := ThemeDB.fallback_font
		var fs: int = L["fs"]
		var track := fs * lerpf(0.5, 0.2, out_quint(sx))
		var text := STUDIO.to_upper()
		var widths := []
		var total := 0.0
		for ch in text:
			var wch := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			widths.append(wch)
			total += wch
		total += track * (text.length() - 1)
		var cx := o.x + LOCK_C * u
		var base_y: float = L["text_top"] + font.get_ascent(fs) + (1.0 - out_cubic(sx)) * fs * 0.5
		var x0 := cx - total * 0.5
		var col := Color(BONE, 0.9 * out_cubic(sx))
		for i in text.length():
			ci.draw_string(font, Vector2(x0, base_y), text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
			x0 += widths[i] + track
		out["studio"] = Rect2(cx - total * 0.5, L["text_top"], total, font.get_height(fs))
		out["studio_text"] = STUDIO
	return out
