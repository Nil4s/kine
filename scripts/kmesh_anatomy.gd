class_name KMeshAnatomy
extends Node
## ANATOMY TAGS (ROADMAP_400 A19 ★): the finer layer on top of A18's regions. Every vertex of a KMesh carries one tag
## (deltoid_l, patella_r, knuckles_l, skull ...) in the A09 vertex channel "anat_tag" (a float index into TAGS, -1 = none),
## saved with the mesh and carried through every edit:
##   SEED: painted once on the base body (the mannequin skin) by rule, from A18's nearest bone SEGMENT + where the vertex
##     is along that bone (t: 0 at its joint, 1 at its child's) + the angle around it (front / back / up / out). Each
##     vertex is first taken back to the REST pose by its own bone (rest * pose^-1, skeleton space), so the rules read the
##     T pose whatever the pose and wherever the fighter stands: +z front, +y up, +x the character's left.
##   PAINT: the tag brush sets a tag on every vertex within its radius of the stroke (one undo step per stroke; the
##     radius is BRUSH_PX on screen where the stroke starts, at least BRUSH_R).
##   CARRY: the channel is a LABEL channel (KMesh.LABEL_ATTRS): ops that copy a source vertex (extrude, inset, bridge,
##     dissolve, merge, delete, repair: A09 attr_remap) copy its tag; subdivision gives an edge point one of its ends'
##     tags and a face point the most common tag of its corners (never a blend of two indices). Verts that still have
##     none (a primitive added beside) take the nearest tagged neighbour's (fill_untagged), else the rule.
##   TRANSFER: another mesh near the body (armour, clothes, a sculpt of the skin) takes, at each vertex, the tag of the
##     nearest corner of the nearest TRIANGLE of the tagged mesh (nearest surface point, not nearest vertex).
## THE RULES (boundaries after Gray's Anatomy, 41st ed. (S. Standring, 2016), the surface anatomy of the upper limb, lower
## limb, back and abdominal wall, and F. Netter, Atlas of Human Anatomy, 7th ed. (2019), plates of the limb compartments):
##   head: the face is the front of the head (within ~70 deg of straight ahead) from the chin up to the hairline (3/4 of
##     the head bone); the rest is skull. neck: the back is trapezius (its upper fibres), the rest neck.
##   clavicle: its lateral end, from the top, is the deltoid's origin (acromion); the top front is the collarbone, the low
##     front pectoral (clavicular head), the top back trapezius, the low back the scapula.
##   chest (spine_03): front above its lowest quarter pectoral (the pectoralis major reaches the 6th rib), below it the
##     abdominals (rectus, from the 5th-7th costal cartilages) or obliques laterally; back: within 4.5 cm of the spine
##     trapezius (middle and lower fibres), the scapula over the upper two thirds laterally, latissimus below and on the
##     sides (the lateral thorax under the arm).
##   abdomen (spine_01/02): rectus abdominis within 7 cm of the middle line in front, the obliques lateral to it and on the
##     sides; the back: erector spinae (lower_back) within 6 cm of the spine, latissimus outside it.
##   pelvis: front above the hip joints abdominals / obliques as above, below it the groin (medial) or the hip
##     (tensor fasciae latae, gluteus medius: lateral); the back is glutes.
##   upper arm: the deltoid wraps the top 22 % of the humerus all round (but the armpit side) and its lateral face down to
##     the deltoid tuberosity (45 %, about mid humerus); the elbow point (olecranon) is the back of the last 12 %; the rest
##     biceps in front, triceps behind.
##   forearm: the olecranon is the back of its first 12 %; the flexors are the palm side (the anterior compartment), the
##     extensors the back-of-hand side (the posterior compartment; the T pose holds the palms down).
##   hand: palm side palm; the back of the hand, with its last fifth (the metacarpal heads) knuckles; the top of a proximal
##     phalanx's first quarter knuckles too; the thumb's metacarpal palm (thenar eminence) or back of the hand; fingers.
##   thigh: the patella is the front (+-40 deg) of the last 14 % (the kneecap sits on the distal femur, its apex about a
##     cm above the joint line); glutes the back of the first 15 % (above the gluteal fold); hamstrings the back
##     (beyond +-115 deg); adductors the inner side (medial, beyond -45 deg) above the knee; quadriceps the rest.
##   shin (calf bone): the patella (its ligament) is the front of the first 8 %; the back is the calf (gastrocnemius,
##     soleus, down to the Achilles), the rest the shin (tibia, tibialis anterior, peroneals).
##   foot: its bottom (under 60 % of the ball joint's height) is the sole, the back of the heel the heel, the rest the
##     top of the foot.
## Tags with a side take the bone's side; the trunk's take the side of the middle plane the vertex is on; a vertex ON
## the plane (within MID_TOL) takes the left one either way (the same answer however the body is placed).
## As a Node this is the model preview's "colour by anatomy" view (kmesh_edit_ui.gd, Alt+H; it and Shift+H's regions
## replace each other): a tint layer in each tag's colour, a legend of the tags present (bottom right of the free view;
## a click on a row picks that tag for the brush), the hover readout ("biceps_l: biceps brachii (left), in upperarm_l"),
## Alt+drag paints the brush tag, Alt+Shift+click picks the tag under the mouse.

const CH := "anat_tag"
const BRUSH_R := 0.03      # m: the tag brush's smallest radius (mesh space)
const BRUSH_PX := 40.0     # px: ... and its radius on screen, at the depth where the stroke starts (the larger wins)
const OFF_TINT := 0.002    # m: the tag layer sits this far out along the vertex normal (over A18's region layer)
const LEGEND_PAD := 12.0
const TCELL := 0.01        # m: the triangle grid of transfer() (a triangle sits in every cell its box touches)
const MID_TOL := 0.0005    # m: a vert this near x = 0 is on the middle plane (its side tag is the left one)
const MID := ["skull", "face", "neck", "abdominals", "lower_back", "groin"]
const PAIRED := ["trapezius", "collarbone", "scapula", "pectoral", "latissimus", "obliques", "glutes", "hip",
	"deltoid", "biceps", "triceps", "olecranon", "forearm_flexors", "forearm_extensors", "palm", "hand_back", "knuckles",
	"fingers", "quadriceps", "hamstrings", "adductors", "patella", "shin", "calf", "foot_top", "sole", "heel"]
## the tags. APPEND ONLY: a saved mesh stores indices into this table
const TAGS := ["skull", "face", "neck", "abdominals", "lower_back", "groin",
	"trapezius_l", "trapezius_r", "collarbone_l", "collarbone_r", "scapula_l", "scapula_r", "pectoral_l", "pectoral_r",
	"latissimus_l", "latissimus_r", "obliques_l", "obliques_r", "glutes_l", "glutes_r", "hip_l", "hip_r",
	"deltoid_l", "deltoid_r", "biceps_l", "biceps_r", "triceps_l", "triceps_r", "olecranon_l", "olecranon_r",
	"forearm_flexors_l", "forearm_flexors_r", "forearm_extensors_l", "forearm_extensors_r", "palm_l", "palm_r",
	"hand_back_l", "hand_back_r", "knuckles_l", "knuckles_r", "fingers_l", "fingers_r",
	"quadriceps_l", "quadriceps_r", "hamstrings_l", "hamstrings_r", "adductors_l", "adductors_r",
	"patella_l", "patella_r", "shin_l", "shin_r", "calf_l", "calf_r", "foot_top_l", "foot_top_r",
	"sole_l", "sole_r", "heel_l", "heel_r"]
## the words of the hover readout
const NAMES := {"skull": "skull (cranium)", "face": "face", "neck": "neck (sternocleidomastoid)", "abdominals": "rectus abdominis",
	"lower_back": "erector spinae", "groin": "groin", "trapezius": "trapezius", "collarbone": "collarbone (clavicle)",
	"scapula": "scapula (shoulder blade)", "pectoral": "pectoralis major", "latissimus": "latissimus dorsi",
	"obliques": "external obliques", "glutes": "gluteus maximus", "hip": "hip (tensor fasciae latae, gluteus medius)",
	"deltoid": "deltoid", "biceps": "biceps brachii", "triceps": "triceps brachii", "olecranon": "elbow point (olecranon)",
	"forearm_flexors": "forearm flexors", "forearm_extensors": "forearm extensors", "palm": "palm", "hand_back": "back of the hand",
	"knuckles": "knuckles", "fingers": "fingers", "quadriceps": "quadriceps", "hamstrings": "hamstrings", "adductors": "adductors",
	"patella": "kneecap (patella)", "shin": "shin (tibia, tibialis anterior)", "calf": "calf (gastrocnemius, soleus)",
	"foot_top": "top of the foot", "sole": "sole", "heel": "heel"}


static func tag_index(tag: String) -> int:
	return TAGS.find(tag)


## "biceps_l" -> "biceps", "skull" -> "skull"
static func stem_of(tag: String) -> String:
	return tag.left(-2) if tag.ends_with("_l") or tag.ends_with("_r") else tag


static func mirror_tag(tag: String) -> String:
	if tag.ends_with("_l"):
		return tag.left(-2) + "_r"
	if tag.ends_with("_r"):
		return tag.left(-2) + "_l"
	return tag


## each muscle's hue (degrees), chosen so that neighbours on the body differ; the left lighter, the right deeper
const HUES := {"skull": 32, "face": 52, "neck": 95, "abdominals": 330, "lower_back": 45, "groin": 70,
	"trapezius": 200, "collarbone": 60, "scapula": 275, "pectoral": 0, "latissimus": 160, "obliques": 115, "glutes": 300,
	"hip": 185, "deltoid": 28, "biceps": 220, "triceps": 100, "olecranon": 305, "forearm_flexors": 260,
	"forearm_extensors": 50, "palm": 0, "hand_back": 180, "knuckles": 320, "fingers": 140, "quadriceps": 210,
	"hamstrings": 25, "adductors": 90, "patella": 345, "shin": 270, "calf": 150, "foot_top": 60, "sole": 330, "heel": 200}


static func color_of(tag: String) -> Color:
	var st := stem_of(tag)
	if not HUES.has(st):
		return Color(0.5, 0.5, 0.5)
	var h: float = HUES[st] / 360.0
	if tag.ends_with("_r"):
		return Color.from_hsv(h, 0.85, 0.6)
	if tag.ends_with("_l"):
		return Color.from_hsv(h, 0.45, 0.98)
	return Color.from_hsv(h, 0.65, 0.82)


static func ensure(mesh: KMesh) -> void:
	if not mesh.has_attr(CH):
		mesh.add_attr(CH, KMesh.AD_VERT, TYPE_FLOAT, -1.0)


static func tag_of(mesh: KMesh, v: int) -> String:
	if not mesh.has_attr(CH) or v < 0 or v >= mesh.verts.size():
		return ""
	var t := int(mesh.get_attr(CH, v))
	return TAGS[t] if t >= 0 and t < TAGS.size() else ""


## the hover words: "biceps_l: biceps brachii (left), in upperarm_l"; where nothing is tagged, A18's region
static func readout(mesh: KMesh, v: int) -> String:
	var tg := tag_of(mesh, v)
	var reg: String = KMeshBody.label(mesh, v)["region"]
	if tg == "":
		return "no anatomy tag" + (", in " + reg if reg != "" else "")
	var sd := " (left)" if tg.ends_with("_l") else (" (right)" if tg.ends_with("_r") else "")
	return "%s: %s%s%s" % [tg, NAMES.get(stem_of(tg), stem_of(tg)), sd, ", in " + reg if reg != "" else ""]


## tag -> vertex count, for the tags present ("none" for untagged verts)
static func counts(mesh: KMesh) -> Dictionary:
	var out := {}
	if not mesh.has_attr(CH):
		return out
	for t in (mesh.attr_data(CH) as PackedFloat32Array):
		var nm: String = TAGS[int(t)] if t >= 0.0 else "none"
		out[nm] = int(out.get(nm, 0)) + 1
	return out


# ---------------------------------------------------------------- the seed

## what the rules need from a skeleton: per BONES index the map from WORLD to that bone's REST pose in skeleton space
## ("unpose"), and the rest segments in skeleton space ("seg": bone -> [a, b])
static func body_from_skeleton(sk: Skeleton3D) -> Dictionary:
	var gx := sk.global_transform if sk.is_inside_tree() else sk.transform
	var gi := gx.affine_inverse()
	var un := []
	un.resize(KMeshBody.BONES.size())
	for bi in KMeshBody.BONES.size():
		un[bi] = gi
	var ix := {}
	for b in sk.get_bone_count():
		ix[sk.get_bone_name(b).to_lower()] = b
	for bi in KMeshBody.BONES.size():
		var nm: String = KMeshBody.BONES[bi]
		if ix.has(nm):
			un[bi] = sk.get_bone_global_rest(ix[nm]) * sk.get_bone_global_pose(ix[nm]).affine_inverse() * gi
	var seg := {}
	for s in KMeshBody.segments_from_skeleton(sk, false):   # rest, in world: back to skeleton space
		seg[s["bone"]] = [gi * (s["a"] as Vector3), gi * (s["b"] as Vector3)]
	return {"unpose": un, "seg": seg}


## Tag the verts (all, or only `only`) by the rules. segs: KMeshBody.segments_from_skeleton(sk, true) (the A18 labels are
## refreshed against them first); xf: the mesh's local space -> world. -> {"ms", "n"}
static func seed_tags(mesh: KMesh, sk: Skeleton3D, xf := Transform3D.IDENTITY, only := PackedInt32Array(), all := true) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	KMeshBody.refresh(mesh, KMeshBody.segments_from_skeleton(sk, true), xf)
	var bd := body_from_skeleton(sk)
	ensure(mesh)
	var ch: PackedFloat32Array = mesh.attr_data(CH)
	var bon: PackedFloat32Array = mesh.attr_data(KMeshBody.CH_BONE)
	var ids := only
	if all:
		ids = PackedInt32Array()
		ids.resize(mesh.verts.size())
		for i in ids.size():
			ids[i] = i
	var un: Array = bd["unpose"]
	for v in ids:
		var b := int(bon[v])
		if b < 0:
			continue
		var u: Transform3D = un[b]
		ch[v] = TAGS.find(rule(KMeshBody.BONES[b], u * (xf * mesh.verts[v]), bd["seg"]))
	mesh.set_attr_data(CH, ch)
	return {"ms": (Time.get_ticks_usec() - t0) / 1000.0, "n": ids.size()}


## the component of r along the part of `axis` square to the unit d (0 when axis runs along d)
static func _comp(r: Vector3, d: Vector3, axis: Vector3) -> float:
	var o := axis - d * d.dot(axis)
	return r.dot(o.normalized()) if o.length() > 0.3 else 0.0


## THE RULE: the tag of rest-pose point p (skeleton space) nearest to bone `bone` (see the class comment). Positions
## only: a mesh welded from a file may wind its faces either way, so its normals are not trusted
static func rule(bone: String, p: Vector3, seg: Dictionary) -> String:
	var side := bone.right(2) if bone.ends_with("_l") or bone.ends_with("_r") else ""
	var stem := bone.trim_suffix(side)
	var sg := 1.0 if side == "_l" else -1.0
	if side != "" and absf(p.x) < MID_TOL:   # on the middle plane the nearest bone's side is a coin toss: one answer
		side = "_l"
	var mside := "_l" if p.x >= -MID_TOL else "_r"
	var s: Array = seg.get(bone, [p, p + Vector3.UP])
	var a: Vector3 = s[0]
	var ab: Vector3 = s[1] - a
	var l2 := maxf(ab.length_squared(), 1e-12)
	var t := (p - a).dot(ab) / l2                 # along the bone, unclamped
	var r := (p - a) - ab * t                     # square off the bone
	var rl := maxf(r.length(), 1e-9)
	var d := ab / sqrt(l2)
	var fz := _comp(r, d, Vector3.BACK) / rl       # +1 straight ahead (+z)
	var fy := _comp(r, d, Vector3.UP) / rl         # +1 straight up (0 for an upright bone)
	var fo := _comp(r, d, Vector3.RIGHT) / rl * sg # +1 straight out from the middle line (0 for an arm bone)
	var th := rad_to_deg(atan2(fo, fz))            # round an upright bone: 0 front, 90 out, -90 in, 180 back
	var ax := absf(p.x)
	match stem:
		"head":
			return "face" if fz > 0.35 and t < 0.75 else "skull"
		"neck_01":
			return "trapezius" + mside if fz < -0.3 else "neck"
		"clavicle":
			if t > 0.85 and fy > 0.0 and fz > -0.5:
				return "deltoid" + side
			if fz >= 0.0:
				return ("collarbone" if fy > -0.3 else "pectoral") + side
			return ("trapezius" if fy > 0.3 else "scapula") + side
		"spine_03":
			var top: float = (seg["neck_01"][0] as Vector3).y if seg.has("neck_01") else a.y + ab.y
			var h := (p.y - a.y) / maxf(top - a.y, 1e-6)
			if fz > 0.4:
				if h > 0.25:
					return "pectoral" + mside
				return "abdominals" if ax < 0.07 else "obliques" + mside
			if fz < -0.4:
				if ax < 0.045:
					return "trapezius" + mside
				return ("scapula" if h > 0.35 else "latissimus") + mside
			return "latissimus" + mside
		"spine_01", "spine_02":
			if fz > 0.35:
				return "abdominals" if ax < 0.07 else "obliques" + mside
			if fz < -0.35:
				return "lower_back" if ax < 0.06 else "latissimus" + mside
			return "obliques" + mside
		"pelvis":
			var hy: float = (seg["thigh_l"][0] as Vector3).y if seg.has("thigh_l") else a.y
			if fz < -0.3:
				return "glutes" + mside
			if p.y < hy - 0.06 and ax < 0.05:
				return "groin"
			if fz > 0.3:
				if p.y >= hy:
					return "abdominals" if ax < 0.07 else "obliques" + mside
				return "groin" if ax < 0.07 else "hip" + mside
			return "hip" + mside
		"upperarm":
			if (t < 0.22 and fy > -0.5) or (t < 0.45 and fy > 0.55):
				return "deltoid" + side
			if t > 0.88 and fz < -0.6:
				return "olecranon" + side
			return ("biceps" if fz >= 0.0 else "triceps") + side
		"lowerarm":
			if t < 0.12 and fz < -0.6:
				return "olecranon" + side
			return ("forearm_flexors" if fy < 0.0 else "forearm_extensors") + side
		"hand":
			if fy < -0.2:
				return "palm" + side
			return ("knuckles" if t > 0.8 else "hand_back") + side
		"thigh":
			if t > 0.86 and absf(th) < 40.0:
				return "patella" + side
			if t < 0.15 and absf(th) > 105.0:
				return "glutes" + side
			if absf(th) > 115.0:
				return "hamstrings" + side
			if th < -45.0 and t < 0.8:
				return "adductors" + side
			return "quadriceps" + side
		"calf":
			if t < 0.08 and absf(th) < 40.0:
				return "patella" + side
			return ("calf" if fz < -0.3 else "shin") + side
		"foot", "ball":
			var ank: Vector3 = (seg["foot" + side][0] as Vector3) if seg.has("foot" + side) else a
			var bally: float = (seg["ball" + side][0] as Vector3).y if seg.has("ball" + side) else a.y
			if p.y < bally * 0.6:   # the bottom of the foot (the ball's joint sits ~1.5 cm over the floor)
				return "sole" + side
			if p.z < ank.z - 0.02 and p.y < ank.y:
				return "heel" + side
			return "foot_top" + side
		"thumb_01":
			return ("palm" if fy < 0.0 else "hand_back") + side
	if stem.ends_with("_01") and t < 0.25 and fy > 0.3:   # a proximal phalanx's top at its root: the knuckle
		return "knuckles" + side
	return "fingers" + side


# ---------------------------------------------------------------- paint, fill, transfer

## The brush: every vertex within `radius` of `centre` (mesh space) takes `tag`. -> the verts that changed
static func paint(mesh: KMesh, centre: Vector3, radius: float, tag: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	var ti := TAGS.find(tag)
	if ti < 0:
		return out
	ensure(mesh)
	var ch: PackedFloat32Array = mesh.attr_data(CH)
	var r2 := radius * radius
	for v in mesh.verts.size():
		if mesh.verts[v].distance_squared_to(centre) <= r2 and int(ch[v]) != ti:
			ch[v] = ti
			out.append(v)
	if not out.is_empty():
		mesh.set_attr_data(CH, ch)
	return out


## untagged verts (-1) take the tag of the nearest tagged vert along the edges (breadth first, in vertex order: the
## same answer every time). -> how many were filled (verts on a piece with no tag at all stay -1)
static func fill_untagged(mesh: KMesh) -> int:
	if not mesh.has_attr(CH):
		return 0
	var ch: PackedFloat32Array = mesh.attr_data(CH)
	var q := PackedInt32Array()
	var todo := 0
	for v in ch.size():
		if ch[v] >= 0.0:
			q.append(v)
		else:
			todo += 1
	if todo == 0 or q.is_empty():
		return 0
	var filled := 0
	var head := 0
	while head < q.size():
		var v := q[head]
		head += 1
		for w in mesh.vert_neighbors(v):
			if ch[w] < 0.0:
				ch[w] = ch[v]
				filled += 1
				q.append(w)
	mesh.set_attr_data(CH, ch)
	return filled


## closest point to p on triangle abc as barycentric weights (Ericson, Real-Time Collision Detection, 5.1.5)
static func _closest_bary(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return Vector3(1, 0, 0)
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return Vector3(0, 1, 0)
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		var v := d1 / (d1 - d3)
		return Vector3(1.0 - v, v, 0)
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return Vector3(0, 0, 1)
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		var w := d2 / (d2 - d6)
		return Vector3(1.0 - w, 0, w)
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		var w2 := (d4 - d3) / ((d4 - d3) + (d5 - d6))
		return Vector3(0, 1.0 - w2, w2)
	var den := 1.0 / (va + vb + vc)
	var vv := vb * den
	var ww := vc * den
	return Vector3(1.0 - vv - ww, vv, ww)


## Every vert of dst takes the tag of src's nearest surface point (of the nearest triangle's corners, the tag with the
## most barycentric weight there) among the
## triangles that face the same way as the vert (so a shell over a hand of interpenetrating parts reads the surface it
## lies over, not a buried finger root; the nearest of all when none does). src_xf / dst_xf: each mesh's local space ->
## world. Verts further than max_d from src keep what they had. -> {"ms", "n", "far", "dist" (m, per dst vert: how far
## its surface point is; INF when too far)}
static func transfer(src: KMesh, dst: KMesh, src_xf := Transform3D.IDENTITY, dst_xf := Transform3D.IDENTITY, max_d := 0.25, facing := true) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	ensure(dst)
	var out: PackedFloat32Array = dst.attr_data(CH)
	if not src.has_attr(CH) or src.faces.is_empty():
		return {"ms": 0.0, "n": 0, "far": dst.verts.size()}
	var st: PackedFloat32Array = src.attr_data(CH)
	var sp := PackedVector3Array()
	sp.resize(src.verts.size())
	for i in sp.size():
		sp[i] = src_xf * src.verts[i]
	var tri := PackedInt32Array()
	for f in src.faces:
		var fp: PackedInt32Array = f
		for i in range(1, fp.size() - 1):
			tri.append_array([fp[0], fp[i], fp[i + 1]])
	var nt := tri.size() / 3
	var tn := PackedVector3Array()   # outward triangle normals (each mesh's winding read from its signed volume)
	tn.resize(nt)
	var tc := PackedVector3Array()   # each triangle's bounding sphere (a cheap "can it be nearer?" first)
	var trad := PackedFloat32Array()
	tc.resize(nt)
	trad.resize(nt)
	var vol := 0.0
	for k in nt:
		var a := sp[tri[k * 3]]
		var cc := (a + sp[tri[k * 3 + 1]] + sp[tri[k * 3 + 2]]) / 3.0
		tc[k] = cc
		trad[k] = sqrt(maxf(maxf(cc.distance_squared_to(a), cc.distance_squared_to(sp[tri[k * 3 + 1]])), cc.distance_squared_to(sp[tri[k * 3 + 2]])))
		var c := (sp[tri[k * 3 + 1]] - a).cross(sp[tri[k * 3 + 2]] - a)
		tn[k] = c.normalized()
		vol += a.dot(sp[tri[k * 3 + 1]].cross(sp[tri[k * 3 + 2]]))
	var so := 1.0 if vol >= 0.0 else -1.0
	var dvol := 0.0
	var dw := PackedVector3Array()
	dw.resize(dst.verts.size())
	for i in dw.size():
		dw[i] = dst_xf * dst.verts[i]
	for f in dst.faces:
		var fp: PackedInt32Array = f
		for i in range(1, fp.size() - 1):
			dvol += dw[fp[0]].dot(dw[fp[i]].cross(dw[fp[i + 1]]))
	var dso := (1.0 if dvol >= 0.0 else -1.0) * so
	var dnb := dst_xf.basis.inverse().transposed()
	var dvn := dst.vert_normals
	var inv := 1.0 / TCELL
	var grid := {}
	for k in nt:
		var a := sp[tri[k * 3]]
		var lo := a.min(sp[tri[k * 3 + 1]]).min(sp[tri[k * 3 + 2]])
		var hi := a.max(sp[tri[k * 3 + 1]]).max(sp[tri[k * 3 + 2]])
		for x in range(floori(lo.x * inv), floori(hi.x * inv) + 1):
			for y in range(floori(lo.y * inv), floori(hi.y * inv) + 1):
				for z in range(floori(lo.z * inv), floori(hi.z * inv) + 1):
					var key := Vector3i(x, y, z)
					if grid.has(key):
						(grid[key] as Array).append(k)   # (an Array: a packed array in a Dictionary is a copy)
					else:
						grid[key] = [k]
	var stamp := PackedInt32Array()
	stamp.resize(nt)
	stamp.fill(-1)
	var rmax := ceili(max_d * inv) + 1
	var far := 0
	var dist := PackedFloat32Array()
	dist.resize(dst.verts.size())
	dist.fill(INF)
	for v in dst.verts.size():
		var p: Vector3 = dw[v]
		var dn: Vector3 = (dnb * dvn[v]).normalized() * dso   # in src's winding
		var c := Vector3i(floori(p.x * inv), floori(p.y * inv), floori(p.z * inv))
		var cl := Vector3(c) * TCELL
		var edge := minf(minf(minf(p.x - cl.x, p.y - cl.y), p.z - cl.z), minf(minf(cl.x + TCELL - p.x, cl.y + TCELL - p.y), cl.z + TCELL - p.z))
		var bd := INF
		var bt := -1.0   # the tag found (facing), and whether one was
		var bf := false
		var ad := INF   # the nearest of all, facing or not
		var at := -1.0
		var af := false
		for r in rmax + 1:
			for x in range(-r, r + 1):
				for y in range(-r, r + 1):
					for z in range(-r, r + 1):
						if maxi(absi(x), maxi(absi(y), absi(z))) != r:
							continue
						var cell = grid.get(c + Vector3i(x, y, z))
						if cell == null:
							continue
						for k in (cell as Array):
							if stamp[k] == v:
								continue
							stamp[k] = v
							var sd := p.distance_to(tc[k]) - trad[k]
							if sd > 0.0 and sd * sd >= bd:   # (bd: INF until a facing one is found, so the fallback stays exact)
								continue
							var i0 := tri[k * 3]
							var i1 := tri[k * 3 + 1]
							var i2 := tri[k * 3 + 2]
							var w := _closest_bary(p, sp[i0], sp[i1], sp[i2])
							var d := p.distance_squared_to(sp[i0] * w.x + sp[i1] * w.y + sp[i2] * w.z)
							# the tag holding most of the point's weight (two corners of one tag outvote a nearer third)
							var s0 := st[i0]
							var s1 := st[i1]
							var s2 := st[i2]
							var w0 := w.x + (w.y if s1 == s0 else 0.0) + (w.z if s2 == s0 else 0.0)
							var w1 := w.y + (w.x if s0 == s1 else 0.0) + (w.z if s2 == s1 else 0.0)
							var w2 := w.z + (w.x if s0 == s2 else 0.0) + (w.y if s1 == s2 else 0.0)
							var tag := s0 if w0 >= w1 and w0 >= w2 else (s1 if w1 >= w2 else s2)
							if d < ad:
								ad = d
								at = tag
								af = true
							if d < bd and (not facing or tn[k].dot(dn) >= 0.0):
								bd = d
								bt = tag
								bf = true
			if bf and sqrt(bd) <= edge + r * TCELL:   # every triangle not seen yet is at least that far
				break
		if not bf:
			bd = ad
			bt = at
			bf = af
		if not bf or sqrt(bd) > max_d:
			far += 1
			continue
		out[v] = bt
		dist[v] = sqrt(bd)
	dst.set_attr_data(CH, out)
	return {"ms": (Time.get_ticks_usec() - t0) / 1000.0, "n": dst.verts.size() - far, "far": far, "dist": dist}


## the tag layer: every face, each corner in its vertex's tag colour, OFF_TINT out along the vertex normal
static func layer_mesh(mesh: KMesh) -> ArrayMesh:
	var am := ArrayMesh.new()
	if not mesh.has_attr(CH) or mesh.faces.is_empty():
		return am
	var tg: PackedFloat32Array = mesh.attr_data(CH)
	var pal := PackedColorArray()
	for t in TAGS:
		pal.append(color_of(t))
	var pos := PackedVector3Array()
	var cols := PackedColorArray()
	var nor := PackedVector3Array()
	for fi in mesh.face_count():
		var fp: PackedInt32Array = mesh.faces[fi]
		for i in range(1, fp.size() - 1):
			for c in [0, i + 1, i]:   # Godot's front face is clockwise; KMesh counter-clockwise
				var v: int = fp[c]
				var n := mesh.vert_normals[v]
				pos.append(mesh.verts[v] + n * OFF_TINT)
				nor.append(n)
				var t := int(tg[v])
				cols.append(pal[t] if t >= 0 else Color(0.5, 0.5, 0.5))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = nor
	arr[Mesh.ARRAY_COLOR] = cols
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am


# ---------------------------------------------------------------- the model preview's view (an instance per KMeshEditUI)

var ui: Node                  # the KMeshEditUI
var on := false               # "colour by anatomy" shown
var layer: MeshInstance3D
var legend: PanelContainer
var brush := ""               # the tag the brush paints ("" = none picked yet)
var hover_text := ""
var hover_at := Vector2.ZERO
var stroking := false
var stroke_dabs := PackedVector3Array()   # the dab centres of the stroke in progress / the last one (mesh space)
var stroke_changed := PackedInt32Array()  # the verts it changed
var stroke_r := BRUSH_R       # the stroke's radius (mesh space)
var _last_px := Vector2.INF
var _sig := 0                 # the mesh's vertex count + faces when last checked for untagged verts
var _dsig := 0                # the verts + faces + tags the layer was last drawn from
var _mat: StandardMaterial3D


func setup(edit_ui: Node) -> void:
	ui = edit_ui
	name = "kmesh_anatomy"


## every frame while the preview is open (and once at its start): every vert tagged, the layer fresh
func tick() -> void:
	if ui == null or not ui.on or ui.mesh == null or ui.view == null:
		return
	var mesh: KMesh = ui.mesh
	var sig := hash([mesh.verts.size(), mesh.faces.size(), mesh.has_attr(CH)])
	if sig != _sig:
		_sig = sig
		_tag_all()
	if not on:
		return
	var dsig := hash([mesh.verts, mesh.faces, mesh.attr_data(CH) if mesh.has_attr(CH) else null])   # moved, re-cut, painted, undone
	if dsig != _dsig or layer == null or not is_instance_valid(layer) or layer.get_parent() != ui.view:
		_dsig = dsig
		_rebuild()


## the channel there and every vert tagged: the rule for a mesh that has none, else the neighbours' tags, else the rule
func _tag_all() -> bool:
	var mesh: KMesh = ui.mesh
	var sk: Skeleton3D = ui.m.skel
	if not mesh.has_attr(CH):
		if sk == null:
			return false
		seed_tags(mesh, sk, ui.view.global_transform)
		return true
	var none := PackedInt32Array()
	var ch: PackedFloat32Array = mesh.attr_data(CH)
	for v in ch.size():
		if ch[v] < 0.0:
			none.append(v)
	if none.is_empty():
		return false
	fill_untagged(mesh)
	if sk != null:
		none.clear()
		ch = mesh.attr_data(CH)
		for v in ch.size():
			if ch[v] < 0.0:
				none.append(v)
		if not none.is_empty():
			seed_tags(mesh, sk, ui.view.global_transform, none, false)
	return true


func toggle() -> void:
	on = not on
	if on and ui.body != null and ui.body.on:
		ui.body.toggle()   # the two colourings replace each other (one tint layer, one legend at the bottom right)
	_sig = 0
	tick()
	_rebuild()
	if on:
		var c := counts(ui.mesh)
		ui.m._say("Model: colour by anatomy on: %d tags on this mesh. Hover for the tag, Alt+drag paints %s, Alt+Shift+click picks a tag. Alt+H turns it off" % [c.size(), brush if brush != "" else "(pick a tag first: a legend row or Alt+Shift+click)"])
	else:
		hover_text = ""
		ui.m._say("Model: colour by anatomy off (Alt+H turns it on)")


func close() -> void:
	on = false
	stroking = false
	hover_text = ""
	layer = null
	_sig = 0
	if legend != null:
		legend.visible = false


func _rebuild() -> void:
	if ui.view == null:
		return
	if layer == null or not is_instance_valid(layer) or layer.get_parent() != ui.view:
		layer = MeshInstance3D.new()
		layer.name = "anatomy_tags"
		ui.view.add_child(layer)
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.roughness = 0.8
	layer.visible = on
	layer.mesh = layer_mesh(ui.mesh) if on else null
	layer.material_override = _mat
	_legend_update()


func _legend_update() -> void:
	if legend == null:
		legend = PanelContainer.new()
		legend.name = "anatomy_legend"
		legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var st := StyleBoxFlat.new()
		st.bg_color = Color(Tok.c("float"), 0.92)
		st.set_corner_radius_all(8)
		st.set_content_margin_all(8)
		legend.add_theme_stylebox_override("panel", st)
		var vb := VBoxContainer.new()
		vb.name = "box"
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_theme_constant_override("separation", 4)
		legend.add_child(vb)
		var hd: Label = ui.m._label("", 14, "text")
		hd.name = "head"
		vb.add_child(hd)
		var gr := GridContainer.new()
		gr.name = "rows"
		gr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gr.add_theme_constant_override("h_separation", 14)
		gr.add_theme_constant_override("v_separation", 3)
		vb.add_child(gr)
		for t in TAGS:
			var row := HBoxContainer.new()
			row.name = t
			row.mouse_filter = Control.MOUSE_FILTER_STOP   # a click picks this tag for the brush
			row.tooltip_text = "Paint %s with Alt+drag" % t
			row.gui_input.connect(_row_input.bind(t))
			row.add_theme_constant_override("separation", 6)
			var sw := ColorRect.new()
			sw.name = "swatch"
			sw.color = color_of(t)
			sw.custom_minimum_size = Vector2(14, 14)
			sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
			sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(sw)
			var lb: Label = ui.m._label("", 13, "text:0.8")
			lb.name = "words"
			row.add_child(lb)
			gr.add_child(row)
		ui.m.ui_root.add_child(legend)
	legend.visible = on and ui.on
	if not legend.visible:
		return
	var c := counts(ui.mesh)
	var shown := 0
	for t in TAGS:
		var row: Control = legend.get_node("box/rows/" + t)
		row.visible = c.has(t)
		if row.visible:
			shown += 1
			(row.get_node("words") as Label).text = "%s%s %d" % ["> " if t == brush else "", t, int(c.get(t, 0))]
	(legend.get_node("box/head") as Label).text = "Anatomy (Alt+H)  brush: %s" % (brush if brush != "" else "click a row")
	var cl: Rect2 = ui.m.nav_clear_rect()   # bottom right of the free view, as many columns as the height needs
	var gr: GridContainer = legend.get_node("box/rows")
	var row_h := 20.0
	var fit := maxi(1, int((cl.size.y * 0.6 - 40.0) / row_h))
	gr.columns = maxi(1, ceili(float(shown) / fit))
	legend.reset_size()
	var sz := legend.get_combined_minimum_size()
	legend.position = Vector2(cl.end.x - sz.x - LEGEND_PAD, cl.end.y - sz.y - LEGEND_PAD)


func _row_input(ev: InputEvent, t: String) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		set_brush(t)


func set_brush(t: String) -> bool:
	if TAGS.find(t) < 0:
		return false
	brush = t
	if legend != null and legend.visible:
		_legend_update()
	ui.m._say("Model: the anatomy brush paints %s (Alt+drag)" % t)
	return true


## the mesh-space surface point under screen point p, or null
func _hit(p: Vector2):
	var h: Dictionary = ui.view.pick(ui.m.cam, p, 1e6)
	if h.is_empty():
		return null
	var r: Array = ui.view.ray_at(ui.m.cam, p)
	return ui.view.global_transform.affine_inverse() * ((r[0] as Vector3) + (r[1] as Vector3) * float(h["t"]))


## Alt+press: start a stroke (one undo step) or, with Shift, pick the tag under the mouse. -> used
func press(p: Vector2, pick_only: bool) -> bool:
	if not on:
		return false
	if pick_only:
		var h: Dictionary = ui.view.pick(ui.m.cam, p, 1e6)
		if not h.is_empty() and int(h["vert"]) >= 0 and tag_of(ui.mesh, int(h["vert"])) != "":
			set_brush(tag_of(ui.mesh, int(h["vert"])))
		return true
	if brush == "":
		ui.m._say("Model: pick a tag for the brush first: click a legend row, or Alt+Shift+click the mesh")
		return true
	var hp = _hit(p)
	if hp == null:
		return true
	var cam: Camera3D = ui.m.cam
	var depth := cam.global_position.distance_to(ui.view.global_transform * (hp as Vector3))
	var per_px := 2.0 * depth * tan(deg_to_rad(cam.fov) * 0.5) / maxf(cam.get_viewport().get_visible_rect().size.y, 1.0)
	stroke_r = maxf(BRUSH_R, BRUSH_PX * per_px)
	ui.undo.begin(ui.mesh)
	stroking = true
	stroke_dabs = PackedVector3Array()
	stroke_changed = PackedInt32Array()
	_last_px = Vector2.INF
	drag(p)
	return true


## the mouse moved with the stroke on: dabs every 4 px along the way
func drag(p: Vector2) -> void:
	if not stroking:
		return
	var pts := [p]
	if _last_px != Vector2.INF and _last_px.distance_to(p) > 4.0:
		pts = []
		var n := ceili(_last_px.distance_to(p) / 4.0)
		for i in range(1, n + 1):
			pts.append(_last_px.lerp(p, float(i) / n))
	_last_px = p
	var any := false
	for q in pts:
		var hp = _hit(q)
		if hp == null:
			continue
		stroke_dabs.append(hp)
		var ch := paint(ui.mesh, hp, stroke_r, brush)
		if not ch.is_empty():
			stroke_changed.append_array(ch)
			any = true
	if any:
		_rebuild()


func release() -> void:
	if not stroking:
		return
	stroking = false
	ui.undo.commit("paint anatomy %s" % brush)
	_rebuild()
	ui.m._say("Model: painted %s on %d verts (one undo step: Ctrl+Z takes it back)" % [brush, stroke_changed.size()])


## the mouse moved over the view (no button down): the vertex under it, read out. -> the vertex or -1
func hover(p: Vector2) -> int:
	hover_text = ""
	if not on or ui.view == null:
		return -1
	var h: Dictionary = ui.view.pick(ui.m.cam, p, 1e6)
	if h.is_empty() or int(h["vert"]) < 0:
		return -1
	hover_text = readout(ui.mesh, int(h["vert"]))
	hover_at = p
	return int(h["vert"])


func draw(ov: Control) -> void:
	if not on or hover_text == "":
		return
	var f := ov.get_theme_default_font()
	var fs := 14
	var sz := f.get_string_size(hover_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var at := hover_at + Vector2(16, -10)
	ov.draw_rect(Rect2(at - Vector2(6, sz.y - 2), sz + Vector2(12, 8)), Color(Tok.c("float"), 0.92), true)
	ov.draw_string(f, at, hover_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Tok.c("text"))
