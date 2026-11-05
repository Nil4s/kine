class_name WetStreet
extends Node3D
## CH5c: wet cobblestone street at night, rebuilt on the engine's PBR (StandardMaterial3D), SSR, a reflection probe and real omni lights.
## No hand-written ground shader. The height field of the setts comes from a real CC0 photo texture (fix pass 2: Poly Haven "Cobblestone Floor 09",
## Charlotte Baglioni, https://polyhaven.com/a/cobblestone_floor_09: rectangular setts in running-bond rows with a lengthwise channel, like ref2;
## pass 1 used "Cobblestone Floor 04", Rob Tuytel, rounded cobbles): tools/ch5c_prep_tiles.py segments its sett outlines (a LABEL raster) and
## keeps its displacement map; the asphalt strip is Poly Haven "Worn Asphalt" (Amal Kumar, https://polyhaven.com/a/worn_asphalt), CC0.
## World: metres, +y up. Patch x in [X0, X0+SPAN_X], z in [Z0, Z0+SPAN_Z]; the camera stands on +z and looks toward -z.
## Data model (kept from CH5/CH5b so their bars A, C, E run unchanged): height(), himg (RF metres), mimg (RGBA8 wet albedo + wet roughness), bowls, level.

## LAYOUT AND CAMERA FROM THE PHOTO (fix pass 2, tools/ch5c_photo_estimates.py prints every number): ref2.jpg is a Nokia Lumia 920 frame
## (Wikimedia EXIF: Make Nokia, Model Lumia 920; 26 mm-equivalent lens, 1.4 um pixels, original 1994 px wide) -> f = 1630 px at the
## 1280 px copy. Horizon (lane vanishing point) row 975. Camera height from the left wall's brick courses (15 px at x 440, 8 px at x 560,
## wall base rows 1173 / 1079; a Victorian Liverpool course ~79 mm, the photo's GPS is 53.4166 N, 2.9497 W): 1.03 m (0.98-1.13 for
## 75-86 mm courses). Everything else follows from f, h and the horizon: wall, plinth, fence, lamp, gate, the flat tarmac patch, sett size.
const X0 := -1.6
const Z0 := -21.5
const SPAN_X := 3.2
const SPAN_Z := 23.0
const TEXEL := 0.006                 ## metres per baked pixel
const PITCH := 0.11                  ## nominal sett size (tests scale u, v with it)
const GAP := 0.014                   ## joint width scale
const GAP_FLOOR := -0.030            ## joint bottom below the stone tops
const TOP_SIG := 0.004               ## per-stone top height sigma
const DOME := 0.012                  ## extra per-stone dome on top of the photo's own relief
const JOINT_DARK := 0.35             ## wet joints: albedo x this at the joint centre
const ROUND := 0.012                 ## rounding width of a stone edge (metres from the outline)
const LEVEL := -0.034                ## THE water level
const ASPHALT_X := 0.85              ## (CH5/CH5b layout, unused since fix pass 2: the photo has no asphalt strip)
const PATCH_C := Vector2(-0.615, -4.43)   ## the photo's flat tarmac repair (px 430-610, rows 1235-1290): an ellipse on the ground
const PATCH_R := Vector2(0.325, 0.565)
const DRY_ROUGH_COBBLE := 0.85
const DRY_ROUGH_ASPHALT := 0.92
const WET_ROUGH_COBBLE := 0.03       ## the stone tops carry a water film: film roughness = WATER_ROUGH (Lagarde 2013, "Water drop 2b": a wet film is a water surface); domes end at ~0.11 after AMBIENT_WET
const WET_ROUGH_ASPHALT := 0.30
const WATER_ROUGH := 0.03
const DRY_ALB_COBBLE := 0.11         ## linear albedo of a dry stone top (night granite is dark; the photo's 0.5 grey is scaled to this)
const DRY_ALB_ASPHALT := 0.07
const WET_DARKEN := 0.7             ## wet albedo = dry * this (Lekner & Dorf 1988)
const AMBIENT_WET := 0.9
const EYE := 1.03                    ## camera height (brick courses, see the header)
const LAMP_POS := Vector3(-0.60, 5.24, -19.6)  ## the bulb of lamp 0: post base row 1055 -> 21.1 m from the camera (z = 1.5 - 21.1), head row 650 -> 5.24 m, head x 645 -> -0.60 m
const BULB_R := 0.3                  ## light_size (soft-shadow radius) of every lamp: a street luminaire emits from a ~0.6 m x 0.3 m window (typical cobra-head fixture, from memory, not re-fetched), so radius 0.3 m. NOT tuned to a bar.
const BULB_VIS := 0.3
const FOV := 61.0                    ## the photo's own camera: f = 1630 px over its 1922 px height = vertical 61.0 deg; the 1280x720 render holds the
                                     ## whole photo frame in its central 480 x 720 px (tools/ch5c_side.py crops it for the side-by-side)
const PITCH_DEG := 0.5               ## the photo's horizon is 14 px below its centre: atan(14 / 1630) = 0.5 deg up
const TILE_M := 1.49                 ## the CC0 tile (2.175 m real, sett rows 132 mm: 124 px of 2048 by autocorrelation of its displacement) drawn at
                                     ## 1.49 m so its rows are the photo's 90 mm: 16 joint rows between photo rows 1495 and 1910 (3.10 m -> 1.73 m from
                                     ## the camera); setts then 90 x ~140 mm (photo: 110-157 mm across)
const TILE_ALB_MEAN := 0.092         ## mean linear luminance of the tile's stone pixels (cf09 albedo); scaled to DRY_ALB_COBBLE
const TILE_N := 1024
const PX_M := TILE_M / float(TILE_N)
const TILT_X := 0.045               ## per-stone tilt (slope), from the photo's glitter streak: half-width 0.24 m at 3.2 m from the camera
const TILT_Z := 0.045               ## (x 560-800 at row 1500) needs a normal spread of (0.24/3.2 + 0.24/18) / 2 = 0.044

## lamp row: [bulb position, colour, light energy, post x offset, bulb emission]
## 0: the photo's lamp, colour from its halo ring rgb (172, 157, 166). ENERGY = EXPOSURE CALIBRATION on a surface no bar reads: the timber fence
##    (x 1.33, 11-17 m away, 0.8-1.4 m up, 12 points) in the dry render at energy 140 with a 0.5 albedo tint was 2.7x the photo in linear
##    luminance (median of 12 ratios 0.375); with the tint now 1.0 that is 5.3x -> 140 x 0.375 / 2 = 26
## 1: the photo's cyan light at the far right end (px 790, 875): 1.3 m right, 2.4 m up, at the gate
## 2, 3: NOT in the photo frame: the street beyond the end gate, whose white house front is lit in the photo (rgb 77, 69, 66); kept so the
##    CH5b bar S3 (>= 4 lamps) still describes the scene. Energy 25 lit the house to sRGB 0.58 vs the photo's 0.30: x (0.30/0.58)^2.2 -> 6
const LAMPS := [
	[Vector3(-0.60, 5.24, -19.6), Vector3(1.0, 0.91, 0.97), 26.0, 0.20, 60.0],
	[Vector3(1.3, 2.41, -20.8), Vector3(0.55, 1.0, 0.9), 1.0, 0.0, 12.0],
	[Vector3(-3.5, 5.0, -24.0), Vector3(1.0, 0.92, 0.8), 6.0, 0.0, 30.0],     ## behind the left wall's end, as seen from the camera
	[Vector3(-6.0, 5.0, -24.0), Vector3(1.0, 0.92, 0.8), 6.0, 0.0, 30.0],
]
const BOLLARD := Vector3(0.2, 0.0, -6.0)     ## the S2 shadow caster (NOT in the photo; kept for bar S2). At z = -6 the B mirror paths are 1.19 m up,
                                             ## above its 0.9 m top; x 0.2 keeps its shadow (x 0.2..0.36) off the tarmac patch (x <= -0.29) and the puddles
const WALL_X := 1.30                 ## left brick wall face at x = -1.30
const PLINTH_X := 1.02               ## right: a low brick plinth (face x 1.02, top 0.47 m) under a timber fence (face 1.33, top 1.83 m)
const PLINTH_H := 0.47
const FENCE_X := 1.33
const FENCE_H := 1.83
const END_Z := -21.0                 ## the gate wall closing the lane (row 1050 -> 22.5 m)
var light_r := BULB_R
var legacy := false
var env: Environment
var set_pieces: Array = []   ## walls, windows, bollards: hidden in the legacy (one-lamp, black-void) control
var probe := -1
var bowls: Array = []
var level := LEVEL
var himg: Image                      ## FORMAT_RF: height in metres
var mimg: Image                      ## RGBA8: wet albedo rgb (sRGB), wet roughness a
var wetimg: Image                    ## FORMAT_R8: wetness 0..1
var painted := false                 ## planted control: puddles from a texture that ignores the height
var dry := false
var ground: MeshInstance3D
var asphalt_mesh: MeshInstance3D
var water: MeshInstance3D
var refl_probe: ReflectionProbe
var lights: Array = []               ## OmniLight3D per lamp
var mat_wet: StandardMaterial3D
var mat_dry: StandardMaterial3D
var mat_probe: StandardMaterial3D
var mat_asph_wet: StandardMaterial3D
var mat_asph_dry: StandardMaterial3D
var diff_img_dry: Image
var _w := 0
var _h := 0
var _lab := PackedInt32Array()       ## sett label per tile pixel
var _edge := PackedByteArray()       ## distance to the sett outline (px x 4)
var _disp := PackedByteArray()
var _alb := PackedByteArray()        ## tile albedo rgb8
var _box := {}                       ## id -> [l, r, t, b] in tile px
var _lin8 := PackedFloat32Array()
var _d_lo := 0.25
var _d_hi := 0.85
var _loaded := false


static func hash2(i: int, j: int) -> float:
	return fposmod(sin(float(i) * 127.1 + float(j) * 311.7) * 43758.5453, 1.0)


static func reflection_point(eye: Vector3, bulb: Vector3, lvl: float) -> Vector3:
	var t := (eye.y - lvl) / ((eye.y - lvl) + (bulb.y - lvl))
	return Vector3(eye.x + (bulb.x - eye.x) * t, lvl, eye.z + (bulb.z - eye.z) * t)


static func grazing(eye: Vector3, x: Vector3) -> float:
	return asin((eye.y - x.y) / eye.distance_to(x))


static func default_bowls(eyes: Array) -> Array:
	var out := []
	for e in eyes:
		var x := reflection_point(e, LAMP_POS, LEVEL)
		## radius 0.3 m (was 0.62): ref2 has NO standing puddle on the lamp line (its streak is wet stone tops), and the three poses' bowls
		## are only 1 m apart in a 2.3 m lane, so 0.62 m bowls merged into one lane-wide pool whose lamp image was the "one glare blob"
		out.append([x.x, x.z, 0.3, 0.075])
	return out


func bowl_field(x: float, z: float) -> float:
	var b := 0.0
	for w in bowls:
		var dx: float = x - float(w[0])
		var dz: float = z - float(w[1])
		b -= float(w[3]) * exp(-(dx * dx + dz * dz) / (float(w[2]) * float(w[2])))
	return b


## the photo's flat tarmac patch (bar H samples it)
func is_asphalt(x: float, z: float) -> bool:
	var a := (x - PATCH_C.x) / PATCH_R.x
	var b := (z - PATCH_C.y) / PATCH_R.y
	return a * a + b * b < 1.0


# ---------------------------------------------------------------------------------------------------------------- the sett layout (photo)
func _load_tiles() -> void:
	if _loaded:
		return
	var base := ProjectSettings.globalize_path("res://assets/ch5c/")
	var li := Image.load_from_file(base + "cobble_label.png")
	li.convert(Image.FORMAT_RGB8)
	var ld := li.get_data()
	_lab.resize(TILE_N * TILE_N)
	for k in TILE_N * TILE_N:
		_lab[k] = int(ld[k * 3]) + 256 * int(ld[k * 3 + 1])
	var ei := Image.load_from_file(base + "cobble_edge.png")
	ei.convert(Image.FORMAT_L8)
	_edge = ei.get_data()
	var di := Image.load_from_file(base + "cobble_disp.png")
	di.convert(Image.FORMAT_L8)
	_disp = di.get_data()
	var ai := Image.load_from_file(base + "cobble_albedo.jpg")
	ai.convert(Image.FORMAT_RGB8)
	_alb = ai.get_data()
	var f := FileAccess.open(base + "cobble_stones.csv", FileAccess.READ)
	f.get_line()
	while not f.eof_reached():
		var ln := f.get_line().strip_edges()
		if ln == "":
			continue
		var p := ln.split(",")
		_box[int(p[0])] = [int(p[1]), int(p[2]), int(p[3]), int(p[4])]
	_lin8.resize(256)
	for k in 256:
		_lin8[k] = pow(float(k) / 255.0, 2.2)
	# calibrate the displacement: 10th..90th percentile over the stone pixels -> joint floor .. top
	var hist := PackedInt32Array()
	hist.resize(256)
	var n := 0
	for k in TILE_N * TILE_N:
		if _lab[k] > 0:
			hist[_disp[k]] += 1
			n += 1
	var acc := 0
	for v in 256:
		acc += hist[v]
		if float(acc) < 0.1 * float(n):
			_d_lo = float(v) / 255.0
		if float(acc) < 0.9 * float(n):
			_d_hi = float(v) / 255.0
	_loaded = true


## tile pixel + tile index of a world point
func _tile_px(x: float, z: float) -> Array:
	var fx := (x + 5.0) / TILE_M
	var fz := (z + 22.0) / TILE_M
	var ix := floori(fx)
	var iz := floori(fz)
	var px := clampi(int((fx - float(ix)) * float(TILE_N)), 0, TILE_N - 1)
	var pz := clampi(int((fz - float(iz)) * float(TILE_N)), 0, TILE_N - 1)
	return [px, pz, ix, iz]


## [stone id i, tile id j, u, v, e (m to the outline), left, right, top, bottom] in world metres; i = 0 on a joint (no stone)
func cobble_cell(x: float, z: float) -> Array:
	_load_tiles()
	var t := _tile_px(x, z)
	var px: int = t[0]
	var pz: int = t[1]
	var k := pz * TILE_N + px
	var id: int = _lab[k]
	var jt: int = int(t[2]) * 7919 + int(t[3]) * 104729
	if id == 0:
		return [0, jt, 0.0, 0.0, 0.0, x, x, z, z]
	var bx: Array = _box[id]
	# the box was measured around one copy of the stone: shift it by whole tiles until it holds this pixel
	var sx := 0
	for m in [0, -1, 1]:
		if px >= int(bx[0]) + m * TILE_N and px < int(bx[1]) + m * TILE_N:
			sx = m * TILE_N
			break
	var sz := 0
	for m in [0, -1, 1]:
		if pz >= int(bx[2]) + m * TILE_N and pz < int(bx[3]) + m * TILE_N:
			sz = m * TILE_N
			break
	var gx := x - (float(px) + 0.5) * PX_M            ## world x of tile pixel 0's left edge
	var gz := z - (float(pz) + 0.5) * PX_M
	var l := gx + float(int(bx[0]) + sx) * PX_M
	var r := gx + float(int(bx[1]) + sx) * PX_M
	var tp := gz + float(int(bx[2]) + sz) * PX_M
	var bt := gz + float(int(bx[3]) + sz) * PX_M
	var e := float(_edge[k]) * 0.25 * PX_M
	return [id, jt, (x - l) / PITCH, (z - tp) / PITCH, e, l, r, tp, bt]


func stone_top(i: int, j: int, _u: float, _v: float) -> float:
	return (hash2(i, j) - 0.5) * 2.0 * TOP_SIG


## the surface height in metres: the photo's displacement inside each outlined sett (rounded toward the joints), a hashed tilt and dome per
## sett, joints at the floor, or the asphalt strip; plus the settled bowls
func height(x: float, z: float) -> float:
	var h := 0.0
	if is_asphalt(x, z):
		var gx := x * 3.0
		var gz := z * 3.0
		h = 0.0015 * (sin(gx * 1.7 + sin(gz * 1.3)) * 0.6 + sin(gz * 2.1 - gx * 0.7) * 0.4)
	else:
		h = _cobble_h(x, z, cobble_cell(x, z))
	return h + bowl_field(x, z)


func _cobble_h(x: float, z: float, c: Array) -> float:
	var id: int = c[0]
	if id == 0:
		return GAP_FLOOR
	var i := id
	var j: int = c[1]
	var cx: float = 0.5 * (float(c[5]) + float(c[6]))
	var cz: float = 0.5 * (float(c[7]) + float(c[8]))
	var hw := maxf(0.5 * (float(c[6]) - float(c[5])), 0.02)
	var hd := maxf(0.5 * (float(c[8]) - float(c[7])), 0.02)
	var da := (x - cx) / hw
	var db := (z - cz) / hd
	var tx := (hash2(i + 7, j) - 0.5) * 2.0 * TILT_X
	var tz := (hash2(i, j + 9) - 0.5) * 2.0 * TILT_Z
	var t := _tile_px(x, z)
	var dd := float(_disp[int(t[1]) * TILE_N + int(t[0])]) / 255.0
	var rel := clampf((dd - _d_lo) / maxf(_d_hi - _d_lo, 0.05), 0.0, 1.0)
	var photo := lerpf(-0.012, 0.004, rel)
	var dome := DOME * (0.7 + 0.6 * hash2(i + 3, j + 5)) * (1.0 - 0.5 * (da * da + db * db))
	var top := stone_top(i, j, 0.0, 0.0) + tx * (x - cx) + tz * (z - cz) + dome + photo
	var s := smoothstep(0.0, ROUND, float(c[4]))
	return lerpf(GAP_FLOOR, top, s)


func joint_amount(x: float, z: float) -> float:
	if is_asphalt(x, z):
		return 0.0
	var c := cobble_cell(x, z)
	return 1.0 - smoothstep(0.0, ROUND, float(c[4]))


func stone_shade(x: float, z: float) -> float:
	if is_asphalt(x, z):
		return 0.85 + 0.3 * hash2(floori(x / 0.004), floori(z / 0.004))
	var c := cobble_cell(x, z)
	return 0.7 + 0.6 * hash2(int(c[0]) + 31, int(c[1]) % 9973 + 17)


func dry_albedo(x: float, z: float) -> float:
	return (DRY_ALB_ASPHALT if is_asphalt(x, z) else DRY_ALB_COBBLE) * stone_shade(x, z)


func dry_roughness(x: float, z: float) -> float:
	return DRY_ROUGH_ASPHALT if is_asphalt(x, z) else DRY_ROUGH_COBBLE


func wetness(x: float, z: float) -> float:
	var b := bowl_field(x, z)
	var rim := clampf((b + 0.003) / (level + 0.003), 0.0, 1.0)
	var w := maxf(AMBIENT_WET, rim)
	w = maxf(w, 0.9 * joint_amount(x, z))
	if height(x, z) < level:
		w = 1.0
	return w


func wet_roughness(x: float, z: float) -> float:
	var w := wetness(x, z)
	var wr := WET_ROUGH_ASPHALT if is_asphalt(x, z) else WET_ROUGH_COBBLE
	return lerpf(dry_roughness(x, z), wr, w)


func wet_albedo(x: float, z: float) -> float:
	return dry_albedo(x, z) * lerpf(1.0, WET_DARKEN, wetness(x, z))


func has_water(x: float, z: float) -> bool:
	if painted:
		return painted_mask(x, z)
	return height(x, z) < level


static func painted_mask(x: float, z: float) -> bool:
	var v := sin(x * 2.9 + 1.3) * sin(z * 2.3 - 0.7) + 0.5 * sin(x * 7.1 + z * 5.3)
	return v > 0.55


func tex_xy(x: float, z: float) -> Vector2i:
	return Vector2i(clampi(int((x - X0) / TEXEL), 0, _w - 1), clampi(int((z - Z0) / TEXEL), 0, _h - 1))


func texel_center(px: int, py: int) -> Vector2:
	return Vector2(X0 + (float(px) + 0.5) * TEXEL, Z0 + (float(py) + 0.5) * TEXEL)


# ---------------------------------------------------------------------------------------------------------------- bake
func _enc(v: float) -> int:
	return clampi(int(pow(clampf(v, 0.0, 1.0), 1.0 / 2.2) * 255.0 + 0.5), 0, 255)


## bake height, wet and dry albedo + roughness, wetness and the world normal map (GDScript: the data model and the render share one function)
func bake() -> void:
	_load_tiles()
	_w = int(SPAN_X / TEXEL)
	_h = int(SPAN_Z / TEXEL)
	var hd := PackedFloat32Array()
	hd.resize(_w * _h)
	var md := PackedByteArray()
	md.resize(_w * _h * 4)
	var dd := PackedByteArray()
	dd.resize(_w * _h * 4)
	var wd := PackedByteArray()
	wd.resize(_w * _h)
	var at := _lin8
	for py in _h:
		for px in _w:
			var x := X0 + (float(px) + 0.5) * TEXEL
			var z := Z0 + (float(py) + 0.5) * TEXEL
			var k := py * _w + px
			var asph := is_asphalt(x, z)
			var c: Array = [] if asph else cobble_cell(x, z)
			var hh := 0.0
			if asph:
				hh = height(x, z)
			else:
				hh = _cobble_h(x, z, c) + bowl_field(x, z)
			hd[k] = hh
			var ja := 0.0 if asph else 1.0 - smoothstep(0.0, ROUND, float(c[4]))
			var rim := clampf((bowl_field(x, z) + 0.003) / (level + 0.003), 0.0, 1.0)
			var w := 1.0 if hh < level else maxf(maxf(AMBIENT_WET, rim), 0.9 * ja)
			var r_d := DRY_ROUGH_ASPHALT if asph else DRY_ROUGH_COBBLE
			var r_w := WET_ROUGH_ASPHALT if asph else WET_ROUGH_COBBLE
			if hh < level:
				r_w = WATER_ROUGH
			var rr := lerpf(r_d, r_w, w)
			if not asph:
				rr = lerpf(rr, minf(0.55, rr + 0.35), ja)    # joints are rough (mud and sand), the stone top is smooth
			# albedo: the photo's own colour variation, desaturated and scaled to a night-dark granite
			var ar := 0.0
			var ag := 0.0
			var ab := 0.0
			if asph:
				var sh := stone_shade(x, z)
				ar = DRY_ALB_ASPHALT * sh * 1.05
				ag = DRY_ALB_ASPHALT * sh * 0.97
				ab = DRY_ALB_ASPHALT * sh * 0.9
			else:
				var t := _tile_px(x, z)
				var tk := (int(t[1]) * TILE_N + int(t[0])) * 3
				var lr := at[_alb[tk]]
				var lg := at[_alb[tk + 1]]
				var lb := at[_alb[tk + 2]]
				var lu := 0.3 * lr + 0.59 * lg + 0.11 * lb
				var sc := DRY_ALB_COBBLE / TILE_ALB_MEAN * (0.8 + 0.4 * hash2(int(c[0]) + 31, int(c[1]) % 9973 + 17))
				ar = lerpf(lu, lr, 0.5) * sc
				ag = lerpf(lu, lg, 0.5) * sc
				ab = lerpf(lu, lb, 0.5) * sc
			var wf := lerpf(1.0, WET_DARKEN, w) * lerpf(1.0, JOINT_DARK, ja)
			if hh < level:
				wf = 0.2
			md[k * 4] = _enc(ar * wf)
			md[k * 4 + 1] = _enc(ag * wf)
			md[k * 4 + 2] = _enc(ab * wf)
			md[k * 4 + 3] = clampi(int(rr * 255.0), 0, 255)
			dd[k * 4] = _enc(ar)
			dd[k * 4 + 1] = _enc(ag)
			dd[k * 4 + 2] = _enc(ab)
			dd[k * 4 + 3] = clampi(int(lerpf(r_d, minf(0.95, r_d + 0.05), ja) * 255.0), 0, 255)
			wd[k] = int(clampf(w * 255.0, 0.0, 255.0))
	himg = Image.create_from_data(_w, _h, false, Image.FORMAT_RF, hd.to_byte_array())
	mimg = Image.create_from_data(_w, _h, false, Image.FORMAT_RGBA8, md)
	diff_img_dry = Image.create_from_data(_w, _h, false, Image.FORMAT_RGBA8, dd)
	wetimg = Image.create_from_data(_w, _h, false, Image.FORMAT_R8, wd)
	# world normal map (OpenGL convention: r = +x slope, g = +z, b = up) from the height field
	var nd := PackedByteArray()
	nd.resize(_w * _h * 3)
	for py in _h:
		var y0 := maxi(py - 1, 0)
		var y1 := mini(py + 1, _h - 1)
		for px in _w:
			var x0 := maxi(px - 1, 0)
			var x1 := mini(px + 1, _w - 1)
			var gx := (hd[py * _w + x1] - hd[py * _w + x0]) / (float(x1 - x0) * TEXEL)
			var gz := (hd[y1 * _w + px] - hd[y0 * _w + px]) / (float(y1 - y0) * TEXEL)
			var il := 1.0 / sqrt(gx * gx + gz * gz + 1.0)
			var o := (py * _w + px) * 3
			nd[o] = clampi(int((-gx * il * 0.5 + 0.5) * 255.0 + 0.5), 0, 255)
			nd[o + 1] = clampi(int((-gz * il * 0.5 + 0.5) * 255.0 + 0.5), 0, 255)
			nd[o + 2] = clampi(int((il * 0.5 + 0.5) * 255.0 + 0.5), 0, 255)
	_nimg = Image.create_from_data(_w, _h, false, Image.FORMAT_RGB8, nd)
	_shadow_img = _lamp_shadow(hd)
	for im in [mimg, diff_img_dry, wetimg, _nimg, _shadow_img]:
		(im as Image).generate_mipmaps()


var _shadow_img: Image


## MICRO-SHADOWS (fix pass 2, Nick 11-04): the ground mesh is 20 mm and the joints are 10-15 mm wide and 30-46 mm deep, so they exist only in
## the normal map, which casts no shadow: every joint floor was lit as if the stone beside it were not there. Lamp 0 is static, so its
## visibility over the baked height field is exact to bake: march from each texel toward lamp 0 (6 mm steps) and mark it shadowed if the
## height field rises above the ray. Fed to the ground as an occlusion map with ao_light_affect = 1 (it also removes the ambient there:
## a joint 3x deeper than wide sees almost no sky, so that is the right direction too).
func _lamp_shadow(hd: PackedFloat32Array) -> Image:
	var sd := PackedByteArray()
	sd.resize(_w * _h)
	var hmax := -1.0
	for v in hd:
		hmax = maxf(hmax, v)
	var lp := LAMP_POS
	for py in _h:
		var z := Z0 + (float(py) + 0.5) * TEXEL
		for px in _w:
			var x := X0 + (float(px) + 0.5) * TEXEL
			var k := py * _w + px
			var h0 := hd[k]
			var d := Vector2(lp.x - x, lp.z - z)
			var dl := d.length()
			var rise := (lp.y - h0) / dl                  ## ray height gained per metre of ground
			var st := d / dl * TEXEL
			var lit := 255
			var t := 1
			while true:
				var yy := h0 + rise * TEXEL * float(t)
				if yy > hmax:
					break
				var qx := px + int(round(st.x / TEXEL * float(t)))
				var qy := py + int(round(st.y / TEXEL * float(t)))
				if qx < 0 or qy < 0 or qx >= _w or qy >= _h:
					break
				if hd[qy * _w + qx] > yy:
					lit = 0
					break
				t += 1
			sd[k] = lit
	return Image.create_from_data(_w, _h, false, Image.FORMAT_L8, sd)


var _nimg: Image


# ---------------------------------------------------------------------------------------------------------------- scene
func _grid_mesh(x0: float, x1: float, z0: float, z1: float, step: float) -> ArrayMesh:
	var nx := int(ceil((x1 - x0) / step))
	var nz := int(ceil((z1 - z0) / step))
	var vs := PackedVector3Array()
	var uvs := PackedVector2Array()
	var ns := PackedVector3Array()
	var ts := PackedFloat32Array()
	vs.resize((nx + 1) * (nz + 1))
	uvs.resize((nx + 1) * (nz + 1))
	ns.resize((nx + 1) * (nz + 1))
	ts.resize((nx + 1) * (nz + 1) * 4)
	var k := 0
	for iz in nz + 1:
		var z := z0 + (z1 - z0) * float(iz) / float(nz)
		for ix in nx + 1:
			var x := x0 + (x1 - x0) * float(ix) / float(nx)
			vs[k] = Vector3(x, bowl_field(x, z), z)
			uvs[k] = Vector2((x - X0) / SPAN_X, (z - Z0) / SPAN_Z)
			ns[k] = Vector3.UP
			ts[k * 4] = 1.0
			ts[k * 4 + 1] = 0.0
			ts[k * 4 + 2] = 0.0
			ts[k * 4 + 3] = -1.0
			k += 1
	var idx := PackedInt32Array()
	idx.resize(nx * nz * 6)
	var q := 0
	for iz in nz:
		for ix in nx:
			var a := iz * (nx + 1) + ix
			var b := a + 1
			var c := a + nx + 1
			var d := c + 1
			idx[q] = a
			idx[q + 1] = b
			idx[q + 2] = c
			idx[q + 3] = b
			idx[q + 4] = d
			idx[q + 5] = c
			q += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_NORMAL] = ns
	arr[Mesh.ARRAY_TANGENT] = ts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func _mk_ground_mat(alb: Image, nrm: Image) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var at := ImageTexture.create_from_image(alb)
	m.albedo_texture = at
	m.roughness = 1.0
	m.roughness_texture = at
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_ALPHA
	m.normal_enabled = true
	m.normal_texture = ImageTexture.create_from_image(nrm)
	m.normal_scale = 1.0
	m.metallic_specular = 0.5
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _asphalt_mat(wet: bool) -> StandardMaterial3D:
	var base := ProjectSettings.globalize_path("res://assets/ch5c/")
	var m := StandardMaterial3D.new()
	var d := Image.load_from_file(base + "asphalt_diff.jpg")
	d.generate_mipmaps()
	var n := Image.load_from_file(base + "asphalt_nor_gl.jpg")
	n.generate_mipmaps()
	var r := Image.load_from_file(base + "asphalt_rough.jpg")
	r.generate_mipmaps()
	m.albedo_texture = ImageTexture.create_from_image(d)
	var lum := 0.07 * (WET_DARKEN if wet else 1.0) / 0.075      ## the photo's asphalt is mid-dark; night asphalt is darker
	m.albedo_color = Color(lum, lum, lum)
	m.normal_enabled = true
	m.normal_texture = ImageTexture.create_from_image(n)
	m.roughness_texture = ImageTexture.create_from_image(r)
	m.roughness = WET_ROUGH_ASPHALT / 0.8 if wet else 1.0
	m.uv1_scale = Vector3(SPAN_X / 2.0, SPAN_Z / 2.0, 1.0)     ## the photo tile is 2 m
	m.uv1_triplanar = false
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func build(eyes: Array = [Vector3(0, EYE, 1.5)]) -> void:
	if bowls.is_empty():
		bowls = default_bowls(eyes)
	bake()
	env = Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.13, 0.14, 0.086)        ## the photo's haze: sRGB (33, 36, 22) olive green (sky colours are sRGB: pass 1 gave linear values -> black)
	psm.sky_horizon_color = Color(0.13, 0.14, 0.086)
	psm.ground_horizon_color = Color(0.13, 0.14, 0.086)
	psm.ground_bottom_color = Color(0.005, 0.006, 0.004)
	psm.sky_energy_multiplier = 1.0
	sky.sky_material = psm
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.36, 0.27)
	env.ambient_light_energy = 0.04
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.ssr_enabled = true
	env.ssr_max_steps = 256
	env.ssr_fade_in = 0.1
	env.ssr_fade_out = 1.5
	env.ssr_depth_tolerance = 0.3
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.5
	env.glow_hdr_scale = 1.5
	get_viewport().msaa_3d = Viewport.MSAA_4X
	get_viewport().positional_shadow_atlas_size = 8192
	get_viewport().positional_shadow_atlas_quad_0 = Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_1   ## lamp 0 (the largest light) gets a 4096 slot: at 21 m a
	                                                                                               ## 1024 slot's texel blurred a point light's shadow edge to 6.8 px (S2 control)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# ground: a displaced mesh (bowls are real geometry), world-baked PBR textures
	mat_wet = _mk_ground_mat(mimg, _nimg)
	mat_dry = _mk_ground_mat(diff_img_dry, _nimg)
	var stex := ImageTexture.create_from_image(_shadow_img)
	for m in [mat_wet, mat_dry]:
		(m as StandardMaterial3D).ao_enabled = true
		(m as StandardMaterial3D).ao_texture = stex
		(m as StandardMaterial3D).ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		(m as StandardMaterial3D).ao_light_affect = 1.0
	mat_probe = StandardMaterial3D.new()
	mat_probe.albedo_color = Color(1, 1, 1)
	mat_probe.roughness = 1.0
	mat_probe.metallic_specular = 0.0
	ground = MeshInstance3D.new()
	ground.mesh = _grid_mesh(X0, X0 + SPAN_X, Z0, Z0 + SPAN_Z, 0.02)
	ground.material_override = mat_wet
	add_child(ground)
	asphalt_mesh = MeshInstance3D.new()      ## no mesh since fix pass 2: the tarmac patch is baked into the ground
	mat_asph_wet = _asphalt_mat(true)
	mat_asph_dry = _asphalt_mat(false)
	asphalt_mesh.material_override = mat_asph_wet
	add_child(asphalt_mesh)
	# the water: one flat quad at the water level; the ground hides it except in the bowls
	var q := QuadMesh.new()
	q.size = Vector2(SPAN_X, SPAN_Z)
	q.orientation = PlaneMesh.FACE_Y
	water = MeshInstance3D.new()
	water.mesh = q
	water.position = Vector3(X0 + SPAN_X * 0.5, level, Z0 + SPAN_Z * 0.5)
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.012, 0.013, 0.016)
	wm.roughness = WATER_ROUGH
	wm.metallic_specular = 0.4
	var nz := FastNoiseLite.new()
	nz.frequency = 0.045
	nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var ni := nz.get_seamless_image(256, 256)
	ni.bump_map_to_normal_map(3.0)
	wm.normal_enabled = true
	wm.normal_texture = ImageTexture.create_from_image(ni)
	wm.normal_scale = 0.35
	wm.uv1_scale = Vector3(SPAN_X / 0.5, SPAN_Z / 0.5, 1.0)
	wm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	water.material_override = wm
	add_child(water)
	# far field
	var far := MeshInstance3D.new()
	var fq := QuadMesh.new()
	fq.size = Vector2(120, 120)
	fq.orientation = PlaneMesh.FACE_Y
	far.mesh = fq
	far.position = Vector3(0, -0.12, -40)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.05, 0.04, 0.035)
	fm.roughness = 0.8
	far.material_override = fm
	add_child(far)
	_build_lamps()
	_build_walls()
	_build_bollards()
	# reflection probe: the alley's walls and lamps for the rough wet stone (SSR covers what is on screen)
	refl_probe = ReflectionProbe.new()
	refl_probe.position = Vector3(0.0, 2.5, -9.5)
	refl_probe.size = Vector3(2.7, 5.0, 23.0)
	refl_probe.box_projection = true
	refl_probe.interior = false
	refl_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	refl_probe.intensity = 0.25
	refl_probe.max_distance = 30.0
	refl_probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	add_child(refl_probe)
	_apply_modes()
	_log_light_size("build")


func _log_light_size(tag: String) -> void:
	var sz := []
	for o in lights:
		sz.append((o as OmniLight3D).light_size)
	print("     WETSTREET light_size used (%s): BULB_R const %.2f, light_r %.2f, lamps %s" % [tag, BULB_R, light_r, sz])


func lamp_count() -> int:
	return 1 if legacy else LAMPS.size()


func bollard_pos() -> Vector3:
	return BOLLARD


func _occluders() -> Array:
	var out := []
	for l in LAMPS:
		var lp: Vector3 = l[0]
		out.append([lp.x + float(l[3]), lp.z, 0.07, lp.y + 0.6])
	out.append([BOLLARD.x, BOLLARD.z, 0.12, 0.9])
	return out


func _apply_modes() -> void:
	# ground materials
	if probe >= 0:
		ground.material_override = mat_probe
		asphalt_mesh.material_override = mat_probe
	elif dry:
		ground.material_override = mat_dry
		asphalt_mesh.material_override = mat_asph_dry
	else:
		ground.material_override = mat_wet
		asphalt_mesh.material_override = mat_asph_wet
	water.visible = not dry and probe < 0
	env.ssr_enabled = probe < 0 and not dry
	refl_probe.visible = probe < 0 and not legacy
	for i in lights.size():
		var o: OmniLight3D = lights[i]
		o.visible = (i == 0) if (legacy or probe >= 0) else true
		o.light_size = light_r
	for n in set_pieces:
		(n as Node3D).visible = not legacy and probe < 0
	for n in _bollards:
		(n as Node3D).visible = probe >= 0 or not legacy
	if probe >= 0:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0, 0, 0)
		env.ambient_light_energy = 0.0
		env.glow_enabled = false
	elif legacy:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.01, 0.012, 0.02)
		env.ambient_light_energy = 0.0
		env.glow_enabled = true
	else:
		env.background_mode = Environment.BG_SKY
		env.ambient_light_energy = 0.04
		env.glow_enabled = true


func set_legacy(on: bool) -> void:
	legacy = on
	_apply_modes()


func set_probe(i: int) -> void:
	probe = i
	_apply_modes()


func set_light_radius(r: float) -> void:
	light_r = r
	_apply_modes()
	_log_light_size("set_light_radius")


## planted control for bar F2: the wet scene without screen-space reflections or the reflection probe
func set_reflections(on: bool) -> void:
	env.ssr_enabled = on and probe < 0 and not dry
	refl_probe.visible = on and probe < 0 and not legacy


## planted control for bar F2c: the wet scene (same albedo, SSR, probe) but with the DRY roughness on the stones
func set_dry_roughness(on: bool) -> void:
	if on:
		mat_wet.roughness_texture = null
		mat_wet.roughness = DRY_ROUGH_COBBLE
	else:
		mat_wet.roughness_texture = mat_wet.albedo_texture
		mat_wet.roughness = 1.0


func set_dry(on: bool) -> void:
	dry = on
	_apply_modes()


var _bollards: Array = []


func _tex_mat(dname: String, nname: String, tint: Color, tile_m: float, rough: float) -> StandardMaterial3D:
	var base := ProjectSettings.globalize_path("res://assets/ch5c/")
	var d := Image.load_from_file(base + dname)
	d.generate_mipmaps()
	var n := Image.load_from_file(base + nname)
	n.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(d)
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = ImageTexture.create_from_image(n)
	m.roughness = rough
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / tile_m
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


## dark brick wall on the left (Poly Haven "Dark Brick Wall", CC0), timber fence on the right ("Weathered Planks", CC0), a closing wall at the far end
func _build_walls() -> void:
	## albedo maps at their own albedo (tint 1; pass 1 had unexplained 0.5 tints). Poly Haven CC0: https://polyhaven.com/a/dark_brick_wall (1.05 m),
	## https://polyhaven.com/a/weathered_planks (2.0 m)
	var brick := _tex_mat("brick_diff.jpg", "brick_nor_gl.jpg", Color(1, 1, 1), 1.05, 0.85)
	var wood := _tex_mat("fence_diff.jpg", "fence_nor_gl.jpg", Color(1, 1, 1), 2.0, 0.8)
	var gate := StandardMaterial3D.new()
	gate.albedo_color = Color(0.03, 0.045, 0.045)      ## the photo's gate rgb (40, 46, 46)
	gate.roughness = 0.6
	var house := StandardMaterial3D.new()
	house.albedo_color = Color(0.6, 0.58, 0.55)        ## the white house front beyond the gate
	house.roughness = 0.9
	var mid := 0.5 * (END_Z + 1.5)
	var span := 1.5 - END_Z + 2.0
	var spans := [
		[Vector3(-WALL_X - 0.15, 2.5, mid), Vector3(0.3, 5.0, span), brick],
		[Vector3(PLINTH_X + 0.15, PLINTH_H * 0.5, mid), Vector3(0.3, PLINTH_H, span), brick],
		[Vector3(FENCE_X + 0.05, FENCE_H * 0.5, mid), Vector3(0.1, FENCE_H, span), wood],
		[Vector3(0.0, 1.0, END_Z - 0.15), Vector3(WALL_X + FENCE_X + 0.2, 2.0, 0.3), gate],
		[Vector3(0.0, 2.5, END_Z - 5.5), Vector3(12.0, 5.0, 0.3), house],
	]
	for sp in spans:
		var w := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = sp[1]
		w.mesh = bm
		w.position = sp[0]
		w.material_override = sp[2]
		add_child(w)
		set_pieces.append(w)


func _build_bollards() -> void:
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.08, 0.08, 0.09)
	bm.roughness = 0.5
	for o in _occluders():
		if float(o[3]) > 1.0:
			continue
		var m := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = float(o[2])
		cm.bottom_radius = float(o[2])
		cm.height = float(o[3])
		m.mesh = cm
		m.position = Vector3(o[0], float(o[3]) * 0.5, o[1])
		m.material_override = bm
		add_child(m)
		_bollards.append(m)


## a soft radial glare: a smooth falloff that is exactly 0 at the quad edge (no disc edge)
static func glare_texture(n: int = 256) -> ImageTexture:
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var r := Vector2(float(x) + 0.5 - float(n) * 0.5, float(y) + 0.5 - float(n) * 0.5).length() / (float(n) * 0.5)
			var a := 0.0
			if r < 1.0:
				var s := 1.0 - r
				a = s * s * s * (0.35 / (0.04 + r * r * 14.0) + 0.04) * 0.6
			a = clampf(a, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func _build_lamps() -> void:
	var gtex := glare_texture()
	for i in LAMPS.size():
		var l: Array = LAMPS[i]
		_build_lamp(l[0], l[3], l[1], float(l[2]), float(l[4]), gtex, i)


func _build_lamp(lpos: Vector3, post_dx: float, col: Vector3, energy: float, emission: float, gtex: Texture2D, idx: int) -> void:
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.06, 0.06, 0.07)
	pm.roughness = 0.5
	var arm_y := lpos.y + 0.6
	var post := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.06
	cm.bottom_radius = 0.09
	cm.height = arm_y
	post.mesh = cm
	post.position = Vector3(lpos.x + post_dx, arm_y * 0.5, lpos.z)
	post.material_override = pm
	if idx == 0:      ## lamps 1-3 are wall / off-frame lights: no post
		add_child(post)
	else:
		post.free()
	var arm := MeshInstance3D.new()
	var am := BoxMesh.new()
	am.size = Vector3(absf(post_dx), 0.05, 0.05)
	arm.mesh = am
	arm.position = Vector3(lpos.x + post_dx * 0.5, arm_y, lpos.z)
	arm.material_override = pm
	if idx == 0:
		add_child(arm)
	else:
		arm.free()
	var cable := MeshInstance3D.new()
	var km := CylinderMesh.new()
	km.top_radius = 0.01
	km.bottom_radius = 0.01
	km.height = arm_y - lpos.y
	cable.mesh = km
	cable.position = Vector3(lpos.x, lpos.y + (arm_y - lpos.y) * 0.5, lpos.z)
	cable.material_override = pm
	if idx == 0:
		add_child(cable)
	else:
		cable.free()
	var bulb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	var br := BULB_VIS if idx == 0 else 0.08     ## the photo's cyan light is a small source
	sm.radius = br
	sm.height = br * 2.0
	bulb.mesh = sm
	bulb.position = lpos
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var ec := Color(col.x, col.y, col.z)
	bm.albedo_color = ec
	bm.emission_enabled = true
	bm.emission = ec
	bm.emission_energy_multiplier = emission
	bulb.material_override = bm
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bulb)
	# glare: an additive billboard with the soft radial texture (not a disc)
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	gm.albedo_texture = gtex
	gm.albedo_color = Color(col.x, col.y * 0.9, col.z * 0.8, 1.0)
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	gm.no_depth_test = false
	gm.disable_receive_shadows = true
	var glare := MeshInstance3D.new()
	var gq := QuadMesh.new()
	gq.size = Vector2(7.0, 7.0) if idx == 0 else Vector2(0.8, 0.8)
	glare.mesh = gq
	glare.material_override = gm
	glare.position = lpos
	glare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glare)
	set_pieces.append(glare)
	var o := OmniLight3D.new()
	o.position = lpos - Vector3(0, BULB_VIS + 0.02, 0)
	o.omni_range = 40.0 if idx == 0 else 10.0
	o.omni_attenuation = 2.0
	o.light_energy = energy
	o.light_color = Color(col.x, col.y, col.z)
	o.light_size = light_r
	o.shadow_enabled = true
	o.shadow_blur = 1.0     ## Godot default. Godot's omni PCSS disk radius is light_size x shadow_blur (servers/rendering/renderer_rd: light_storage.cpp soft_shadow_scale = shadow_blur; scene_forward_lights_inc.glsl tangent *= soft_shadow_size * soft_shadow_scale), so pass 1's 0.5 halved the 0.3 m emitter
	o.omni_shadow_mode = OmniLight3D.SHADOW_CUBE
	add_child(o)
	lights.append(o)
