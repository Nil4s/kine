## PRECISE PICK (Nick 10-19: "clicking a body part should be 100% precise to the body"). The click and the highlight
## both read the SKINNED MESH as it is drawn this frame, not proxy capsules:
##   PICK: a ray against the mannequin's triangles at their posed positions (the skin's bind poses through the
##     skeleton's current pose, applied to the vertex positions the mesh holds now, so a corrective shape or a finger
##     curl is in it). The nearest hit wins. Its part is the one with the largest skin weight AT THE HIT POINT: the
##     three corners' weights blended by the hit's barycentric coordinates, each bone counted as its part (a bone that
##     is not a body joint, a twist or a finger's tip bone, counts as its nearest ancestor that is; the root as the
##     pelvis: the rule Overlays.split_parts already uses for the pieces).
##   BROAD PHASE: each mesh piece's triangles are cut once, at rest, into small spatial chunks (CHUNK triangles, a
##     median split on the longest axis); after a pose change every chunk gets the box of its posed vertices. A ray
##     tests the piece's box, then the chunk boxes it crosses, then only those chunks' triangles.
##   HIGHLIGHT: one ShaderMaterial, the meshes' material_overlay. Its vertex shader reads the vertex's own skin
##     (BONE_INDICES, BONE_WEIGHTS), maps each bind to its part through a small texture, and takes the part with the
##     largest summed weight (the DOMINANT part: the same sum as the pick's, at the vertex). A second texture holds each
##     part's look (colour, fill strength, rim strength). The tint is per vertex and interpolated across a triangle, so
##     where two parts meet the colour fades over one triangle (no hard seam); the fragment adds a thin rim where the
##     region turns away from the camera (its silhouette) and a thin line where the fill ends (its border).
## dominant_part() is the CPU twin of the shader's choice (tests compare the two on every vertex).
class_name SkinPick
extends RefCounted

const CHUNK := 24          # triangles per broad-phase chunk (13.7k triangles -> ~600 chunks)
const NPART := 64          # the state texture's width (Body.ORDER has 52 parts)
const GROW := 0.0         # m: how far out along the normal the tint shell sits (0: the overlay pass draws at the skin's own depth)

var sk: Skeleton3D
var skin: Skin
var parts: Array = Body.ORDER
var bind_part := PackedInt32Array()   # skin bind -> part index in parts
var bind_bone := PackedInt32Array()   # skin bind -> skeleton bone
var surfs := []    # one per distinct vertex set: {"mi", "si", "mesh_id", "rest", "bones", "w", "per", "pos"}
var groups := []   # one per (mesh piece, surface): {"part", "mi", "k", "chunks": [{"tris", "vix", "box"}], "box"}
var dirty := true
var last_ms := 0.0           # the last pose refresh's cost (ms)
var mat: ShaderMaterial      # the highlight pass: every skinned mesh's material_overlay
var _state_img: Image
var _state_tex: ImageTexture
var _last_pose := []
var _last_xf := Transform3D()   # the skeleton's place at the last refresh (a moved stage re-skins too)
var _state := {}             # part -> [Color (a = fill), rim] as last written (state_of reads it)


## meshes: the MeshInstance3Ds drawn with the skin (the body's pieces, or one whole mannequin); part_of: mesh -> the
## part its triangles were split for ("" = a whole mesh: it is not hidden part by part)
func build(meshes: Array, the_sk: Skeleton3D, part_of := {}) -> void:
	sk = the_sk
	surfs = []
	groups = []
	skin = null
	for mi in meshes:
		if (mi as MeshInstance3D).skin != null:
			skin = (mi as MeshInstance3D).skin
			break
	if skin == null or sk == null:
		return
	_map_binds()
	for mi in meshes:
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for si in m.mesh.get_surface_count():
			var arr: Array = m.mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var k := -1
			for q in surfs.size():
				if (surfs[q]["rest"] as PackedVector3Array).size() == verts.size() and surfs[q]["rest"] == verts:
					k = q
					break
			if k < 0:
				var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
				surfs.append({"mi": m, "si": si, "mesh_id": m.mesh.get_instance_id(), "rest": verts, "bones": bones,
					"w": arr[Mesh.ARRAY_WEIGHTS], "per": bones.size() / maxi(verts.size(), 1), "pos": PackedVector3Array()})
				k = surfs.size() - 1
			var ix = arr[Mesh.ARRAY_INDEX]
			if ix == null:
				continue
			groups.append({"part": String(part_of.get(m, "")), "mi": m, "k": k, "chunks": _chunks(verts, ix), "box": AABB()})
	_make_mat()
	for mi in meshes:
		(mi as MeshInstance3D).material_overlay = mat   # drawn over whatever material the mesh has (its own, the heat)
	dirty = true


## each skin bind -> its bone and its part (a bone outside Body.ORDER -> its nearest ancestor inside; none -> pelvis)
func _map_binds() -> void:
	var ours := {}
	for pi in parts.size():
		var j: String = parts[pi]
		var b := sk.find_bone("Head" if j == "head" else j)
		if b >= 0:
			ours[b] = pi
	bind_part = PackedInt32Array()
	bind_bone = PackedInt32Array()
	for k in skin.get_bind_count():
		var b := SkinPaint.bind_bone(skin, sk, k)
		bind_bone.append(b)
		var c := b
		while c >= 0 and not ours.has(c):
			c = sk.get_bone_parent(c)
		bind_part.append(int(ours[c]) if c >= 0 else 0)


## the triangles of one index array cut into chunks of at most CHUNK by a median split on the centroids' longest axis
func _chunks(verts: PackedVector3Array, ix: PackedInt32Array) -> Array:
	var nt := ix.size() / 3
	var cen := PackedVector3Array()
	cen.resize(nt)
	for t in nt:
		cen[t] = (verts[ix[t * 3]] + verts[ix[t * 3 + 1]] + verts[ix[t * 3 + 2]]) / 3.0
	var out := []
	var stack := [PackedInt32Array(range(nt))]
	while not stack.is_empty():
		var ts: PackedInt32Array = stack.pop_back()
		if ts.size() <= CHUNK:
			var tris := PackedInt32Array()
			var seen := {}
			for t in ts:
				for q in 3:
					var v := ix[t * 3 + q]
					tris.append(v)
					seen[v] = true
			out.append({"tris": tris, "vix": PackedInt32Array(seen.keys()), "box": AABB()})
			continue
		var lo := cen[ts[0]]
		var hi := lo
		for t in ts:
			lo = lo.min(cen[t])
			hi = hi.max(cen[t])
		var ax := (hi - lo).max_axis_index()
		var vals := PackedFloat32Array()
		vals.resize(ts.size())
		for i in ts.size():
			vals[i] = cen[ts[i]][ax]
		var sorted := vals.duplicate()
		sorted.sort()
		var med := sorted[sorted.size() / 2]
		var a := PackedInt32Array()
		var b := PackedInt32Array()
		for i in ts.size():
			if vals[i] < med or (vals[i] == med and a.size() < ts.size() / 2):
				a.append(ts[i])
			else:
				b.append(ts[i])
		if a.is_empty() or b.is_empty():   # every centroid on one value: split by count
			a = ts.slice(0, ts.size() / 2)
			b = ts.slice(ts.size() / 2)
		stack.append(a)
		stack.append(b)
	return out


## force the next pick to skin the vertices again (a pick also notices a changed pose, place or mesh by itself)
func mark() -> void:
	dirty = true


## the posed world position of every vertex and the box of every chunk, if the pose changed since the last time
func refresh() -> void:
	if skin == null or not sk.is_inside_tree():
		return
	var nb := sk.get_bone_count()
	var lp := []   # the skeleton's local poses now: unchanged (and the place and the meshes) = nothing to do
	lp.resize(nb)
	for b in nb:
		lp[b] = sk.get_bone_pose(b)
	var meshes_same := true
	for s in surfs:
		var mi: MeshInstance3D = s["mi"]
		if mi.mesh != null and mi.mesh.get_instance_id() != s["mesh_id"]:
			meshes_same = false
	if not dirty and meshes_same and sk.global_transform == _last_xf and lp == _last_pose:
		return
	_last_xf = sk.global_transform
	_last_pose = lp
	dirty = false
	var t0 := Time.get_ticks_usec()
	var g := []   # each bone's pose in the skeleton's space: the local poses of its chain (parents come first)
	g.resize(nb)
	for b in nb:
		var p := sk.get_bone_parent(b)
		g[b] = (g[p] as Transform3D) * (lp[b] as Transform3D) if p >= 0 else lp[b]
	var mats := []
	var xf := sk.global_transform
	for k in skin.get_bind_count():
		mats.append(xf * (g[bind_bone[k]] as Transform3D) * skin.get_bind_pose(k))
	for s in surfs:
		var mi: MeshInstance3D = s["mi"]
		if mi.mesh != null and mi.mesh.get_instance_id() != s["mesh_id"]:   # a corrective shape rebuilt the mesh: its
			s["mesh_id"] = mi.mesh.get_instance_id()                      # vertices moved, read the ones drawn now
			s["rest"] = mi.mesh.surface_get_arrays(int(s["si"]))[Mesh.ARRAY_VERTEX]
		var per: int = s["per"]
		var bo: PackedInt32Array = s["bones"]
		var w: PackedFloat32Array = s["w"]
		var v: PackedVector3Array = s["rest"]
		var out := PackedVector3Array()
		out.resize(v.size())
		for i in v.size():
			var p := Vector3.ZERO
			var vi := v[i]
			for q in per:
				var x := w[i * per + q]
				if x > 0.0:
					p += ((mats[bo[i * per + q]] as Transform3D) * vi) * x
			out[i] = p
		s["pos"] = out
	for gr in groups:
		var pos: PackedVector3Array = surfs[gr["k"]]["pos"]
		var gb := AABB()
		var first := true
		for c in gr["chunks"]:
			var vix: PackedInt32Array = c["vix"]
			var bx := AABB(pos[vix[0]], Vector3.ZERO)
			for i in vix:
				bx = bx.expand(pos[i])
			bx = bx.grow(0.0005)
			c["box"] = bx
			gb = bx if first else gb.merge(bx)
			first = false
		gr["box"] = gb
	last_ms = (Time.get_ticks_usec() - t0) / 1000.0


## the part under the ray from o along d (d need not be normalised): [part, distance along the ray, world point], or
## ["", INF, Vector3.ZERO] off the body. hidden: parts whose piece is hidden (a click goes through them)
func pick(o: Vector3, d: Vector3, hidden := {}) -> Array:
	refresh()
	var dn := d.normalized()
	var best := INF
	var hit := Vector3.ZERO
	var hk := -1
	var htri := Vector3i(-1, -1, -1)
	for gr in groups:
		if hidden.has(gr["part"]) or not (gr["mi"] as MeshInstance3D).is_visible_in_tree():
			continue
		if not _box_hit(gr["box"], o, dn, best):
			continue
		var pos: PackedVector3Array = surfs[gr["k"]]["pos"]
		for c in gr["chunks"]:
			if not _box_hit(c["box"], o, dn, best):
				continue
			var tris: PackedInt32Array = c["tris"]
			for t in range(0, tris.size(), 3):
				var r = Geometry3D.ray_intersects_triangle(o, dn, pos[tris[t]], pos[tris[t + 1]], pos[tris[t + 2]])
				if r == null:
					continue
				var dist := ((r as Vector3) - o).dot(dn)
				if dist >= 0.0 and dist < best:
					best = dist
					hit = r
					hk = gr["k"]
					htri = Vector3i(tris[t], tris[t + 1], tris[t + 2])
	if hk < 0:
		return ["", INF, Vector3.ZERO]
	return [part_at(hk, htri, hit), best, hit]


## the ray enters the box nearer than best (or starts inside it)
static func _box_hit(bx: AABB, o: Vector3, dn: Vector3, best: float) -> bool:
	if bx.has_point(o):
		return true
	var r = bx.intersects_ray(o, dn)
	return r != null and ((r as Vector3) - o).dot(dn) < best


## the part with the largest skin weight at point p of triangle tri (surface k): the corners' part weights blended by p's
## barycentric coordinates
func part_at(k: int, tri: Vector3i, p: Vector3) -> String:
	var s: Dictionary = surfs[k]
	var pos: PackedVector3Array = s["pos"]
	var bc := Geometry3D.get_triangle_barycentric_coords(p, pos[tri.x], pos[tri.y], pos[tri.z])
	var sums := {}
	for q in 3:
		var bw: float = bc[q]
		var pw := part_weights(k, tri[q])
		for pi in pw:
			sums[pi] = float(sums.get(pi, 0.0)) + float(pw[pi]) * bw
	return parts[_argmax(sums)]


## vertex i of surface k: part index -> its summed skin weight
func part_weights(k: int, i: int) -> Dictionary:
	var s: Dictionary = surfs[k]
	var per: int = s["per"]
	var bo: PackedInt32Array = s["bones"]
	var w: PackedFloat32Array = s["w"]
	var out := {}
	for q in per:
		var x := w[i * per + q]
		if x > 0.0:
			var pi := bind_part[bo[i * per + q]]
			out[pi] = float(out.get(pi, 0.0)) + x
	return out


## the largest; a tie goes to the lower part index (the shader's rule)
static func _argmax(sums: Dictionary) -> int:
	var bp := -1
	var bw := -1.0
	for pi in sums:
		var x: float = sums[pi]
		if x > bw or (x == bw and int(pi) < bp):
			bw = x
			bp = pi
	return maxi(bp, 0)


## the DOMINANT part of vertex i of surface k: the part the highlight gives that vertex (the shader's vertex() rule)
func dominant_part(k: int, i: int) -> String:
	return parts[_argmax(part_weights(k, i))]


# ---------------------------------------------------------------- the highlight

const SHADER := """shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
// PRECISE PICK's highlight (scripts/skin_pick.gd): each vertex is tinted by the look of its DOMINANT part
uniform sampler2D bind_part : filter_nearest, repeat_disable;   // x = skin bind: r = part index
uniform sampler2D part_look : filter_nearest, repeat_disable;   // x = part: row 0 rgb colour (linear) a fill; row 1 r rim
uniform float grow = 0.0006;
varying vec4 v_col;
varying float v_rim;
varying float v_on;

void vertex() {
	int pi[4];
	for (int i = 0; i < 4; i++) {
		pi[i] = int(texelFetch(bind_part, ivec2(int(BONE_INDICES[i]), 0), 0).r + 0.5);
	}
	float best = -1.0;
	int bp = 0;
	for (int i = 0; i < 4; i++) {
		if (BONE_WEIGHTS[i] <= 0.0) { continue; }
		float s = 0.0;
		for (int j = 0; j < 4; j++) {
			if (pi[j] == pi[i] && BONE_WEIGHTS[j] > 0.0) { s += BONE_WEIGHTS[j]; }
		}
		if (s > best || (s == best && pi[i] < bp)) { best = s; bp = pi[i]; }
	}
	vec4 look = texelFetch(part_look, ivec2(bp, 0), 0);
	v_col = vec4(look.rgb * look.a, look.a);
	v_rim = texelFetch(part_look, ivec2(bp, 1), 0).r;
	v_on = look.a > 0.0 ? 1.0 : 0.0;
	VERTEX += NORMAL * grow;
}

void fragment() {
	float a = v_col.a;
	vec3 c = a > 0.0001 ? v_col.rgb / a : vec3(0.0);
	float face = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = (1.0 - smoothstep(0.18, 0.42, face)) * v_rim;          // the silhouette of the region
	float fw = max(fwidth(v_on), 0.0001);
	float edge = (1.0 - smoothstep(0.0, 1.5 * fw, abs(v_on - 0.5))) * v_rim;   // where the fill ends
	ALBEDO = c;
	ALPHA = clamp(a + max(rim, edge) * 0.9, 0.0, 1.0) * step(0.02, v_on + v_rim);
}
"""


func _make_mat() -> void:
	var bimg := Image.create(maxi(bind_part.size(), 1), 1, false, Image.FORMAT_RF)
	for k in bind_part.size():
		bimg.set_pixel(k, 0, Color(float(bind_part[k]), 0, 0))
	_state_img = Image.create(NPART, 2, false, Image.FORMAT_RGBAF)
	_state_tex = ImageTexture.create_from_image(_state_img)
	if mat == null:
		mat = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = SHADER
		mat.shader = sh
		mat.render_priority = 0   # under the joint dots (they draw at 1, through everything)
	mat.set_shader_parameter("bind_part", ImageTexture.create_from_image(bimg))
	mat.set_shader_parameter("part_look", _state_tex)
	mat.set_shader_parameter("grow", GROW)
	_state = {}


## the looks: part -> [Color (rgb in sRGB as the tokens give it, a = fill strength 0..1), rim strength 0..1]. Parts not
## given are untinted. Nothing is written when the looks did not change
func set_looks(looks: Dictionary) -> void:
	if _state_img == null or looks == _state:
		return
	_state = looks.duplicate(true)
	_state_img.fill(Color(0, 0, 0, 0))
	for j in looks:
		var pi := parts.find(j)
		if pi < 0 or pi >= NPART:
			continue
		var c: Color = looks[j][0]
		var lin := Color(c.r, c.g, c.b).srgb_to_linear()
		_state_img.set_pixel(pi, 0, Color(lin.r, lin.g, lin.b, c.a))
		_state_img.set_pixel(pi, 1, Color(float(looks[j][1]), 0, 0, 1))
	_state_tex.update(_state_img)


## the look a part has now ([] = none)
func look_of(j: String) -> Array:
	return _state.get(j, [])


## every vertex the highlight tints for part j (its dominant part is j): [[surface k, vertex i], ...]
func vertices_of(j: String) -> Array:
	var out := []
	for k in surfs.size():
		var n: int = (surfs[k]["rest"] as PackedVector3Array).size()
		for i in n:
			if dominant_part(k, i) == j:
				out.append([k, i])
	return out
