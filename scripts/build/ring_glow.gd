class_name RingGlow
extends RefCounted
## ITEM 275 EMISSIVE RINGS AS ONE CONTINUOUS BAND. Why a ring made of lit sectors reads as dashes (measured on the GPU film's fan rings):
##   1. THE MESH: the ring is N sketch sectors with a gap between each (a sketch refuses overlapping loops, so the gaps cannot be closed): 12 sectors
##      with 3 degrees between them leave 10 % of the circle dark, and each gap is a hard unlit slot.
##   2. THE EMISSION PER FACE: every sector is its own material, so a chase or a hue step is a staircase from sector to sector, not a gradient.
##   3. THE BLOOM: at the film's distance a 3 degree gap is about 2 px wide; a bloom threshold of 1.4 and low energy does not fill it.
## The fix is geometry and shading together: ONE closed annulus mesh (band_mesh) whose emission is a function of the angle round the ring (material):
## the hue runs round it smoothly, the chase is a smooth lobe, there is no gap to bloom across.

const MAX_K := 16.0

const SHADER := "shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float hue_t = 0.0;
uniform float hue_turns = 1.0;
uniform float head = 0.0;
uniform float base_k = 1.4;
uniform float peak_k = 5.0;
uniform float breathe = 1.0;
uniform float chase_on = 1.0;
varying vec2 pos;
vec3 hsv(float h) {
	return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
}
void vertex() { pos = VERTEX.xy; }
void fragment() {
	float a = atan(pos.y, pos.x);
	float th = a < 0.0 ? a + 6.2831853 : a;
	float d = mod(head - th, 6.2831853);
	float k = mix(base_k, base_k + (peak_k - base_k) * exp(-d * 1.6), chase_on);
	vec3 col = hsv(fract(hue_t + th / 6.2831853 * hue_turns));
	ALBEDO = col * k * breathe;
}
"


## a closed flat band of radii ri..ro round the Z axis (facing +Z), z0..z1 thick, `segs` quads round (smooth: 128 by default)
static func band_mesh(ri: float, ro: float, z0: float, z1: float, segs := 128) -> ArrayMesh:
	var v := PackedVector3Array()
	var idx := PackedInt32Array()
	for k in segs:
		var a0 := TAU * float(k) / segs
		var a1 := TAU * float(k + 1) / segs
		var b := v.size()
		v.append(Vector3(cos(a0) * ri, sin(a0) * ri, z1))
		v.append(Vector3(cos(a0) * ro, sin(a0) * ro, z1))
		v.append(Vector3(cos(a1) * ro, sin(a1) * ro, z1))
		v.append(Vector3(cos(a1) * ri, sin(a1) * ri, z1))
		idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
		var c := v.size()   # the outer wall, so the band reads from the side too
		v.append(Vector3(cos(a0) * ro, sin(a0) * ro, z0))
		v.append(Vector3(cos(a1) * ro, sin(a1) * ro, z0))
		v.append(Vector3(cos(a1) * ro, sin(a1) * ro, z1))
		v.append(Vector3(cos(a0) * ro, sin(a0) * ro, z1))
		idx.append_array([c, c + 1, c + 2, c, c + 2, c + 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## the band's material: a hue that runs smoothly round the ring, a chase lobe at angle `head`, strength k between base_k and peak_k
static func material(hue_t := 0.0, head := 0.0, base_k := 2.0, peak_k := 5.0, chase := true) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	sm.shader = sh
	update(sm, hue_t, head, base_k, peak_k, 1.0, chase)
	sm.set_meta("ring_glow", Vector3(0.9, 0.9, 0.9))   # the studio's floor mirror reads this (a mean glow colour, strength ring_k)
	sm.set_meta("ring_k", base_k)
	return sm


static func update(sm: ShaderMaterial, hue_t: float, head: float, base_k: float, peak_k: float, breathe := 1.0, chase := true) -> void:
	sm.set_shader_parameter("hue_t", hue_t)
	sm.set_shader_parameter("head", head)
	sm.set_shader_parameter("base_k", clampf(base_k, 0.0, MAX_K))
	sm.set_shader_parameter("peak_k", clampf(peak_k, 0.0, MAX_K))
	sm.set_shader_parameter("breathe", breathe)
	sm.set_shader_parameter("chase_on", 1.0 if chase else 0.0)
	sm.set_meta("ring_k", base_k * breathe)


## the brightness (0..1, the strongest channel) of `img` at n points round a circle (centre px, radius px): the brightest pixel within `win` px of each point, so a 1 px wobble of
## the ring does not read as a gap
static func along(img: Image, centre: Vector2, radius: float, n := 360, win := 2) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for k in n:
		var a := TAU * float(k) / n
		var p := centre + Vector2(cos(a), sin(a)) * radius
		var best := 0.0
		for dy in range(-win, win + 1):
			for dx in range(-win, win + 1):
				var x := int(round(p.x)) + dx
				var y := int(round(p.y)) + dy
				if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
					var c := img.get_pixel(x, y)
					best = maxf(best, maxf(c.r, maxf(c.g, c.b)))   # brightness = the strongest channel (a rainbow ring has hue-dependent Rec709 luminance)
		out.append(best)
	return out


## min / median of a profile (the ring's no-gap number: >= 0.5 means no gap)
static func min_over_median(p: PackedFloat32Array) -> float:
	var s := Array(p)
	s.sort()
	var med := float(s[s.size() / 2])
	return float(s[0]) / maxf(med, 1e-6)
