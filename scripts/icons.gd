## RIBBON ICONS (round 9, GATES P5): drawn in code, no image files. Each icon is a few shapes on a 24-unit grid,
## painted WHITE by signed distance (coverage = 0.5 - distance: anti-aliased edges with no supersampling). The theme
## tints them (Button icon_*_color), so a light/dark switch needs no redraw.
class_name Icons

const SIZE := 22

## shape: ["seg", a, b, width] | ["arc", centre, radius, width, from_deg, to_deg] | ["disc", centre, radius]
##        ["ring", centre, radius, width] | ["box", rect(pos, size), width (0 = filled)]
const DRAW := {
	"reset": [["arc", Vector2(12, 12), 7.5, 2.2, -60, 210], ["seg", Vector2(19.5, 5), Vector2(18.5, 10), 2.2], ["seg", Vector2(18.5, 10), Vector2(13.5, 9), 2.2]],
	"arms": [["disc", Vector2(12, 4.5), 2.6], ["seg", Vector2(12, 8), Vector2(12, 16), 2.4], ["seg", Vector2(12, 9.5), Vector2(5, 15), 2.0],
		["seg", Vector2(12, 9.5), Vector2(19, 15), 2.0], ["seg", Vector2(12, 16), Vector2(8.5, 22), 2.0], ["seg", Vector2(12, 16), Vector2(15.5, 22), 2.0]],
	"mirror": [["seg", Vector2(12, 2), Vector2(12, 6), 1.5], ["seg", Vector2(12, 9), Vector2(12, 15), 1.5], ["seg", Vector2(12, 18), Vector2(12, 22), 1.5],
		["seg", Vector2(9, 6), Vector2(3, 18), 1.8], ["seg", Vector2(3, 18), Vector2(9, 18), 1.8], ["seg", Vector2(9, 18), Vector2(9, 6), 1.8],
		["seg", Vector2(15, 6), Vector2(21, 18), 1.8], ["seg", Vector2(21, 18), Vector2(15, 18), 1.8], ["seg", Vector2(15, 18), Vector2(15, 6), 1.8]],
	"collision": [["ring", Vector2(9, 12), 6, 1.8], ["ring", Vector2(15, 12), 6, 1.8]],
	"trail": [["disc", Vector2(3, 19), 1.4], ["disc", Vector2(5.5, 13.5), 1.6], ["disc", Vector2(9.5, 8.5), 1.8], ["disc", Vector2(15, 5.5), 2.0], ["disc", Vector2(21, 4.5), 2.4]],
	"onion": [["ring", Vector2(6.5, 12), 4.5, 1.2], ["ring", Vector2(12, 12), 4.5, 1.6], ["disc", Vector2(17.5, 12), 4.5]],
	"spacing": [["seg", Vector2(2, 19), Vector2(22, 19), 1.2], ["disc", Vector2(3, 12), 1.7], ["disc", Vector2(6, 12), 1.7], ["disc", Vector2(9.5, 12), 1.7],
		["disc", Vector2(14.5, 12), 1.7], ["disc", Vector2(21, 12), 1.7]],
	"graph": [["seg", Vector2(3, 3), Vector2(3, 21), 1.5], ["seg", Vector2(3, 21), Vector2(22, 21), 1.5], ["seg", Vector2(5, 17), Vector2(10, 16), 1.8],
		["seg", Vector2(10, 16), Vector2(13, 5), 1.8], ["seg", Vector2(13, 5), Vector2(16, 16), 1.8], ["seg", Vector2(16, 16), Vector2(21, 15), 1.8]],
	"stepped": [["seg", Vector2(3, 20), Vector2(8, 20), 2], ["seg", Vector2(8, 20), Vector2(8, 14), 2], ["seg", Vector2(8, 14), Vector2(14, 14), 2],
		["seg", Vector2(14, 14), Vector2(14, 8), 2], ["seg", Vector2(14, 8), Vector2(21, 8), 2]],
	"holds": [["arc", Vector2(7, 14), 4, 2, 180, 360], ["arc", Vector2(15, 10), 4, 2, 0, 180], ["seg", Vector2(19, 10), Vector2(22, 10), 2], ["seg", Vector2(2, 14), Vector2(3, 14), 2]],
	"tools": [["seg", Vector2(4, 6), Vector2(20, 6), 2], ["seg", Vector2(4, 12), Vector2(20, 12), 2], ["seg", Vector2(4, 18), Vector2(20, 18), 2]],
	"check": [["seg", Vector2(4, 13), Vector2(9.5, 18.5), 2.6], ["seg", Vector2(9.5, 18.5), Vector2(20, 6), 2.6]],
	"polish": [["seg", Vector2(10, 2), Vector2(10, 18), 1.6], ["seg", Vector2(2, 10), Vector2(18, 10), 1.6], ["seg", Vector2(5, 5), Vector2(15, 15), 1.2],
		["seg", Vector2(15, 5), Vector2(5, 15), 1.2], ["disc", Vector2(19, 19), 1.8]],
	"fix": [["disc", Vector2(12, 14), 4.5], ["arc", Vector2(12, 14), 8, 2, 180, 360], ["seg", Vector2(20, 14), Vector2(17.5, 10.5), 2], ["seg", Vector2(20, 14), Vector2(22.5, 10.5), 2]],
	"dummy": [["disc", Vector2(9, 4.5), 2.4], ["seg", Vector2(9, 8), Vector2(9, 15), 2.2], ["seg", Vector2(9, 15), Vector2(6, 21), 2], ["seg", Vector2(9, 15), Vector2(12, 21), 2],
		["seg", Vector2(9, 10), Vector2(4, 13), 1.8], ["ring", Vector2(17.5, 11), 4, 1.6], ["disc", Vector2(17.5, 11), 1.3]],
	"front": [["box", Rect2(4, 4, 16, 16), 1.6], ["disc", Vector2(12, 12), 3]],
	"right": [["box", Rect2(4, 4, 16, 16), 1.6], ["box", Rect2(14, 6, 4, 12), 0]],
	"left": [["box", Rect2(4, 4, 16, 16), 1.6], ["box", Rect2(6, 6, 4, 12), 0]],
	"top": [["box", Rect2(4, 4, 16, 16), 1.6], ["box", Rect2(6, 6, 12, 4), 0]],
	"back": [["box", Rect2(4, 4, 16, 16), 1.6], ["ring", Vector2(12, 12), 3, 1.4]],
	"big": [["seg", Vector2(3, 3), Vector2(9, 3), 2], ["seg", Vector2(3, 3), Vector2(3, 9), 2], ["seg", Vector2(21, 3), Vector2(15, 3), 2], ["seg", Vector2(21, 3), Vector2(21, 9), 2],
		["seg", Vector2(3, 21), Vector2(9, 21), 2], ["seg", Vector2(3, 21), Vector2(3, 15), 2], ["seg", Vector2(21, 21), Vector2(15, 21), 2], ["seg", Vector2(21, 21), Vector2(21, 15), 2]],
	"light": [["disc", Vector2(12, 12), 4], ["seg", Vector2(12, 2), Vector2(12, 5), 1.8], ["seg", Vector2(12, 19), Vector2(12, 22), 1.8], ["seg", Vector2(2, 12), Vector2(5, 12), 1.8],
		["seg", Vector2(19, 12), Vector2(22, 12), 1.8], ["seg", Vector2(5, 5), Vector2(7, 7), 1.8], ["seg", Vector2(17, 17), Vector2(19, 19), 1.8],
		["seg", Vector2(19, 5), Vector2(17, 7), 1.8], ["seg", Vector2(5, 19), Vector2(7, 17), 1.8]],
	"undo": [["arc", Vector2(13, 14), 7, 2.2, 180, 360], ["seg", Vector2(6, 14), Vector2(2.5, 10), 2.2], ["seg", Vector2(6, 14), Vector2(10, 10.5), 2.2]],
	"redo": [["arc", Vector2(11, 14), 7, 2.2, 180, 360], ["seg", Vector2(18, 14), Vector2(21.5, 10), 2.2], ["seg", Vector2(18, 14), Vector2(14, 10.5), 2.2]],
	"history": [["ring", Vector2(13, 12), 8, 2], ["seg", Vector2(13, 12), Vector2(13, 7), 2], ["seg", Vector2(13, 12), Vector2(16.5, 14), 2],
		["seg", Vector2(2, 9), Vector2(5, 12.5), 2], ["seg", Vector2(5, 12.5), Vector2(8, 9.5), 2]],
	"size": [["box", Rect2(2, 12, 8, 8), 1.6], ["box", Rect2(11, 4, 11, 16), 1.8], ["seg", Vector2(5, 9), Vector2(9, 5), 1.4], ["seg", Vector2(9, 5), Vector2(9, 8), 1.4]],
	"search": [["ring", Vector2(10, 10), 6, 2.2], ["seg", Vector2(14.5, 14.5), Vector2(21, 21), 2.8]],
	"help": [["arc", Vector2(12, 8.5), 4.5, 2.2, 160, 420], ["seg", Vector2(12, 13), Vector2(12, 16), 2.2], ["disc", Vector2(12, 20.5), 1.5]],
}

static var _cache := {}


## the icon as a texture (made once)
static func tex(name: String) -> ImageTexture:
	if not _cache.has(name):
		_cache[name] = ImageTexture.create_from_image(paint(DRAW[name]))
	return _cache[name]


static func paint(shapes: Array) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var k := 24.0 / SIZE   # pixels -> grid units
	for y in SIZE:
		for x in SIZE:
			var p := Vector2(x + 0.5, y + 0.5) * k
			var d := INF
			for s in shapes:
				d = minf(d, dist(s, p))
			var a := clampf(0.5 - d / k, 0.0, 1.0)   # distance in PIXELS: one pixel of soft edge
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return img


## signed distance from p to the shape's ink (negative inside)
static func dist(s: Array, p: Vector2) -> float:
	match s[0]:
		"seg":
			var a: Vector2 = s[1]
			var ab: Vector2 = s[2] - a
			var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			return p.distance_to(a + ab * t) - s[3] * 0.5
		"disc":
			return p.distance_to(s[1]) - s[2]
		"ring":
			return absf(p.distance_to(s[1]) - s[2]) - s[3] * 0.5
		"arc":
			var c: Vector2 = s[1]
			var r: float = s[2]
			var a0 := deg_to_rad(s[4])
			var a1 := deg_to_rad(s[5])
			var ang := fposmod(atan2(p.y - c.y, p.x - c.x) - a0, TAU)
			if ang <= a1 - a0:
				return absf(p.distance_to(c) - r) - s[3] * 0.5
			var e0 := c + Vector2(cos(a0), sin(a0)) * r
			var e1 := c + Vector2(cos(a1), sin(a1)) * r
			return minf(p.distance_to(e0), p.distance_to(e1)) - s[3] * 0.5
		"box":
			var r: Rect2 = s[1]
			var q := (p - r.get_center()).abs() - r.size * 0.5
			var out := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0)
			return out if s[2] == 0 else absf(out) - s[2] * 0.5
	return INF
