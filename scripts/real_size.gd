class_name RealSize
extends RefCounted
## REAL-SIZE SANITY (ROADMAP_400 B27 ★): a mesh's size checked against the CURRENT fighter's body. A sword 3 m long, a
## helmet smaller than the head, a glove twice the hand: flagged, and the sentence names the body length it used.
##   check(mesh, kind, B, name) -> {"verdict": "ok" | "suspicious" | "wrong", "text": the sentence, "findings": [...], ...}
## The static API is what the model checks page (B30) calls: findings(mesh, kind, B) -> [{"id", "level", "text"}].
##
## THE KIND: the user's pick, else guessed (guess_kind): the mesh's name ("Sword_LP", "helm"), then where it sits on the
## body: the A19 anatomy tags (skull / face = helmet, palm / knuckles / fingers = glove, sole / heel / foot_top = boot,
## chest and back muscles = armour plate) or, without them, the A18 body regions, counted only on verts within NEAR of
## their bone (a mesh worn ON that part); else "prop" (a generic prop).
## ITS SIZE: the oriented bounding box (obb): the principal axes of the verts (PCA, a Jacobi eigen solve in 64-bit), or
## the axis-aligned box when that one is smaller (vertex-weighted PCA tilts on an unevenly meshed box); sides sorted
## long -> short, metres. A weapon / glove / boot / shield / plate / prop is judged by its LONG side, a helmet by its
## SHORT side (the narrowest opening the head goes through, across the box: an outside size, so a helmet that fails it
## fails inside too).
## THE REFERENCE: RANGES, each a multiple of one of THIS fighter's lengths (refs(B), measured on its rest skeleton by
## Proportions.lengths, so a fighter with 20% longer arms gets a sword range 20% longer and 20% wider):
##   arm = upper arm + forearm (shoulder -> wrist, ANSUR's acromion-radiale + radiale-stylion), forearm (elbow -> wrist),
##   hand (wrist -> middle fingertip), foot (heel -> toe tip), trunk (hip -> shoulder height), stature, head breadth
##   (the head's skin points across, left -> right: the B.skin["head"] points the contact solver uses).
## THE VERDICT: inside [lo, hi] = ok; outside but within WRONG_K of it = suspicious; further = wrong (a helmet's floor is
## harder: under the head breadth itself it cannot go on, so that is wrong at once).
## UNITS: a wrong size that lands inside the range at 1/100, 1/1000 (or 100x / 1000x) is a units slip: "looks like it was
## made in cm" + the factor, and rescale() applies it about the box's centre (mesh_tools op "Model: real-size rescale";
## the readout's button; one KMeshUndo step).

const WRONG_K := 1.5        # outside the range by up to this factor (either way) = suspicious, further = wrong
const NEAR := 0.15          # m: a vert this near its bone counts toward "worn on that part" (the guess by body region)
const WORN_FRAC := 0.6      # ... and this share of all the verts must be near one part for the guess to name it

## kind -> {"label", "dim": "long" | "short", "ref", "lo", "hi", "add" (m added to both ends), "floor" (x ref: under it =
## wrong at once), "src"}. Ranges are typical published figures turned into multiples of the DEFAULT fighter's lengths
## (arm 54.7 cm, forearm 27.3, hand 23.2, foot 30.3, trunk 50.9, stature 182.9, head breadth 17.3), checked to hold
## Body.KINDS' own weapon of that name (tests/realsize_test.gd).
const RANGES := {
	"sword": {"label": "sword", "dim": "long", "ref": "arm", "lo": 1.1, "hi": 1.8,
		"src": "one-handed (arming) swords run ~0.6-1.0 m overall (Oakeshott types X-XIV; Body.KINDS sword 0.92 m)"},
	"longsword": {"label": "longsword", "dim": "long", "ref": "arm", "lo": 1.8, "hi": 2.5,
		"src": "hand-and-a-half swords 1.0-1.35 m overall (Body.KINDS longsword 1.20 m)"},
	"katana": {"label": "katana", "dim": "long", "ref": "arm", "lo": 1.6, "hi": 2.0,
		"src": "a ~60-73 cm blade + a ~25-30 cm tsuka, ~0.9-1.1 m overall (Body.KINDS katana 1.00 m)"},
	"dagger": {"label": "dagger", "dim": "long", "ref": "forearm", "lo": 0.6, "hi": 1.6,
		"src": "daggers ~16-44 cm overall; Body.KINDS' dagger (0.30 m) is longer than a 27 cm forearm, so 'under a forearm' alone would flag it"},
	"spear": {"label": "spear", "dim": "long", "ref": "stature", "lo": 0.9, "hi": 1.7,
		"src": "infantry spears ~1.7-3 m (Body.KINDS spear 2.00 m)"},
	"staff": {"label": "staff", "dim": "long", "ref": "stature", "lo": 0.85, "hi": 1.5,
		"src": "a bo is 6 shaku (1.82 m), quarterstaffs 1.8-2.7 m (Body.KINDS staff 1.80 m)"},
	"axe": {"label": "axe", "dim": "long", "ref": "arm", "lo": 0.7, "hi": 2.3,
		"src": "hand axes ~40-80 cm, a Dane axe's haft 0.9-1.2 m (Body.KINDS long_axe 1.20 m)"},
	"hammer": {"label": "hammer / mace", "dim": "long", "ref": "arm", "lo": 0.5, "hi": 2.2,
		"src": "maces and war hammers ~30-80 cm, pole hammers ~1.1 m (Body.KINDS long_hammer 1.10 m)"},
	"bat": {"label": "bat", "dim": "long", "ref": "arm", "lo": 1.2, "hi": 1.65,
		"src": "adult bats 26-34 in (66-86 cm; Body.KINDS metal_bat 0.84 m)"},
	"helmet": {"label": "helmet", "dim": "short", "ref": "head_breadth", "lo": 1.0, "hi": 2.0, "add": 0.01, "floor": 1.0,
		"src": "the head must go in: the narrowest side at least the head breadth + 1 cm; a great helm is ~1.8 head breadths"},
	"glove": {"label": "glove", "dim": "long", "ref": "hand", "lo": 0.85, "hi": 1.15,
		"src": "a glove is the hand's length (wrist -> middle fingertip) +- 15%"},
	"boot": {"label": "boot", "dim": "long", "ref": "foot", "lo": 1.0, "hi": 1.3,
		"src": "a shoe or boot is the foot plus ~1-3 cm of toe room and sole, up to ~1.3 feet with a thick toe cap"},
	"shield": {"label": "shield", "dim": "long", "ref": "stature", "lo": 0.15, "hi": 0.85,
		"src": "a buckler ~30 cm, a heater ~0.8 m, a kite or scutum ~1.2-1.5 m"},
	"plate": {"label": "armour plate", "dim": "long", "ref": "trunk", "lo": 0.2, "hi": 1.3,
		"src": "a pauldron or greave ~15-40 cm, a breastplate ~35-50 cm tall, a cuirass with tassets ~65 cm"},
	"prop": {"label": "prop", "dim": "long", "ref": "stature", "lo": 0.005, "hi": 3.0,
		"src": "a generic prop: anything from a coin to a cart; only a units slip or a giant is flagged"},
}
const KINDS := ["sword", "longsword", "katana", "dagger", "spear", "staff", "axe", "hammer", "bat", "helmet", "glove",
	"boot", "shield", "plate", "prop"]

## the words a name may hold, per kind, checked in this order against each WORD of the name (split at anything not a
## letter; a word matches when it begins with one of these, a short one (3 letters or fewer) only whole: "Sword_LP" ->
## sword, "helmet01" -> helm, "combat" is no bat, "body" no bo)
const WORDS := [
	["longsword", ["longsword", "long sword", "great sword", "bastard", "claymore", "zweihander", "greatsword"]],
	["katana", ["katana", "tachi", "wakizashi", "nodachi"]],
	["dagger", ["dagger", "knife", "dirk", "stiletto", "tanto", "kunai", "sai"]],
	["sword", ["sword", "blade", "sabre", "saber", "scimitar", "rapier", "gladius", "falchion", "cutlass"]],
	["spear", ["spear", "lance", "pike", "javelin", "halberd", "glaive", "naginata", "trident", "polearm"]],
	["staff", ["staff", "bo", "quarterstaff", "stick", "rod", "cane"]],
	["axe", ["axe", "battleaxe", "hatchet", "tomahawk"]],
	["hammer", ["hammer", "mace", "maul", "club", "flail", "morningstar"]],
	["bat", ["bat"]],
	["helmet", ["helmet", "helm", "hood", "hat", "cap", "crown", "mask", "kabuto"]],
	["glove", ["glove", "gauntlet", "mitt", "fist"]],
	["boot", ["boot", "shoe", "sandal", "sabaton", "greave_foot"]],
	["shield", ["shield", "buckler", "targe", "scutum", "pavise"]],
	["plate", ["armor", "armour", "plate", "cuirass", "breastplate", "pauldron", "greave", "vambrace", "bracer", "tasset", "chest"]],
]
## where a mesh sits (A19 tag stems / A18 regions) -> the kind it would be worn as
const TAG_KIND := {"skull": "helmet", "face": "helmet", "palm": "glove", "hand_back": "glove", "knuckles": "glove",
	"fingers": "glove", "foot_top": "boot", "sole": "boot", "heel": "boot", "pectoral": "plate", "abdominals": "plate",
	"obliques": "plate", "latissimus": "plate", "lower_back": "plate", "scapula": "plate", "trapezius": "plate"}
const REGION_KIND := {"head": "helmet", "hand_l": "glove", "hand_r": "glove", "foot_l": "boot", "foot_r": "boot",
	"chest": "plate", "abdomen": "plate"}
## the reference lengths' words: [its name, how it is measured, the unit it is counted in]
const REF_WORDS := {"arm": ["arm", "shoulder to wrist", "arm lengths"], "forearm": ["forearm", "elbow to wrist", "forearm lengths"],
	"hand": ["hand", "wrist to middle fingertip", "hand lengths"], "foot": ["foot", "heel to toe tip", "foot lengths"],
	"trunk": ["trunk", "hip to shoulder", "trunk lengths"], "stature": ["height", "floor to the top of the head", "times the height"],
	"head_breadth": ["head breadth", "across, ear to ear", "head breadths"]}
## a units slip: [factor applied to fix it, the words]
const UNITS := [[0.01, "made in cm (100x too big)"], [0.001, "made in mm (1000x too big)"],
	[100.0, "made in m but scaled as cm (100x too small)"], [1000.0, "1000x too small (m read as mm)"]]

static var _default_body: Body


# ---------------------------------------------------------------- the box

## the oriented bounding box of the verts: {"size": [long, mid, short] m, "axes": [3 unit Vector3, same order],
## "center": Vector3 (mesh space), "corners": PackedVector3Array (8), "pca": true when the principal axes won}
static func obb(m: KMesh) -> Dictionary:
	var n := m.vert_count() if m != null else 0
	if n == 0:
		return {"size": [0.0, 0.0, 0.0], "axes": [Vector3.RIGHT, Vector3.UP, Vector3.BACK], "center": Vector3.ZERO, "corners": PackedVector3Array(), "pca": false}
	var mx := 0.0
	var my := 0.0
	var mz := 0.0
	for p in m.verts:
		mx += p.x
		my += p.y
		mz += p.z
	mx /= n
	my /= n
	mz /= n
	var c := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	for p in m.verts:
		var d := [float(p.x) - mx, float(p.y) - my, float(p.z) - mz]
		for i in 3:
			for j in range(i, 3):
				c[i][j] += d[i] * d[j]
	for i in 3:
		for j in range(0, i):
			c[i][j] = c[j][i]
	var pca := _box(m, _eigvecs(c))
	var aab := _box(m, [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]])
	var vol := func(b: Dictionary) -> float: return (b["ext"][0] + 1e-9) * (b["ext"][1] + 1e-9) * (b["ext"][2] + 1e-9)
	var use_pca: bool = vol.call(pca) < vol.call(aab) * (1.0 - 1e-9)
	var b: Dictionary = pca if use_pca else aab
	var order := [0, 1, 2]
	order.sort_custom(func(i, j): return b["ext"][i] > b["ext"][j])
	var axes := []
	var size := []
	for i in order:
		axes.append(Vector3(b["ax"][i][0], b["ax"][i][1], b["ax"][i][2]))
		size.append(float(b["ext"][i]))
	var ctr := Vector3.ZERO
	for i in 3:
		ctr += Vector3(b["ax"][i][0], b["ax"][i][1], b["ax"][i][2]) * float(b["mid"][i])
	var corners := PackedVector3Array()
	for sx in [-0.5, 0.5]:
		for sy in [-0.5, 0.5]:
			for sz in [-0.5, 0.5]:
				corners.append(ctr + axes[0] * size[0] * sx + axes[1] * size[1] * sy + axes[2] * size[2] * sz)
	return {"size": size, "axes": axes, "center": ctr, "corners": corners, "pca": use_pca}


## the extents of the verts along three orthonormal axes (rows): {"ax", "ext": [3], "mid": [3] (the centre's coordinates)}
static func _box(m: KMesh, ax: Array) -> Dictionary:
	var lo := [INF, INF, INF]
	var hi := [-INF, -INF, -INF]
	for p in m.verts:
		for i in 3:
			var t: float = float(p.x) * ax[i][0] + float(p.y) * ax[i][1] + float(p.z) * ax[i][2]
			lo[i] = minf(lo[i], t)
			hi[i] = maxf(hi[i], t)
	return {"ax": ax, "ext": [hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2]], "mid": [(hi[0] + lo[0]) * 0.5, (hi[1] + lo[1]) * 0.5, (hi[2] + lo[2]) * 0.5]}


## the eigenvectors of a symmetric 3x3 (cyclic Jacobi, 64-bit), as 3 rows
static func _eigvecs(c: Array) -> Array:
	var a := [c[0].duplicate(), c[1].duplicate(), c[2].duplicate()]
	var v := [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]
	for _sweep in 50:
		var off: float = absf(a[0][1]) + absf(a[0][2]) + absf(a[1][2])
		if off < 1e-30:
			break
		for pq in [[0, 1], [0, 2], [1, 2]]:
			var p: int = pq[0]
			var q: int = pq[1]
			if absf(a[p][q]) < 1e-300:
				continue
			var th: float = (a[q][q] - a[p][p]) / (2.0 * a[p][q])
			var t: float = (1.0 if th >= 0.0 else -1.0) / (absf(th) + sqrt(th * th + 1.0))
			var cs := 1.0 / sqrt(t * t + 1.0)
			var sn := t * cs
			for k in 3:
				var akp: float = a[k][p]
				var akq: float = a[k][q]
				a[k][p] = cs * akp - sn * akq
				a[k][q] = sn * akp + cs * akq
			for k in 3:
				var apk: float = a[p][k]
				var aqk: float = a[q][k]
				a[p][k] = cs * apk - sn * aqk
				a[q][k] = sn * apk + cs * aqk
			for k in 3:
				var vkp: float = v[k][p]
				var vkq: float = v[k][q]
				v[k][p] = cs * vkp - sn * vkq
				v[k][q] = sn * vkp + cs * vkq
	# columns of v are the eigenvectors: return them as rows, normalised
	var out := []
	for j in 3:
		var w := Vector3(v[0][j], v[1][j], v[2][j]).normalized()
		out.append([float(w.x), float(w.y), float(w.z)])
	return out


# ---------------------------------------------------------------- the body

## THIS fighter's reference lengths, m (rest pose). B null = the default body
static func refs(B: Body = null) -> Dictionary:
	if B == null:
		if _default_body == null:
			_default_body = Body.new()
			_default_body.load_files("res://data/skeleton.json", "res://data/body_limits.json")
		B = _default_body
	var L := Proportions.lengths(B)
	var hb := 0.0
	var hl := 0.0
	var pts: Array = B.skin.get("head", [])
	if not pts.is_empty():
		var bb := AABB(pts[0], Vector3.ZERO)
		for q in pts:
			bb = bb.expand(q)
		hb = bb.size.x
		hl = bb.size.z
	return {"arm": float(L["upper_arm"]) + float(L["forearm"]), "forearm": float(L["forearm"]), "hand": float(L["hand"]),
		"foot": float(L["foot"]), "trunk": float(L["trunk"]), "stature": float(L["stature"]), "head_breadth": hb, "head_length": hl}


## the ok range of a kind on these refs: {"lo", "hi", "wrong_lo", "wrong_hi", "ref", "ref_m"} (m)
static func range_of(kind: String, rf: Dictionary) -> Dictionary:
	var r: Dictionary = RANGES[kind]
	var ref_m := float(rf[r["ref"]])
	var add := float(r.get("add", 0.0))
	var lo := ref_m * float(r["lo"]) + add
	var hi := ref_m * float(r["hi"]) + add
	var wlo := ref_m * float(r["floor"]) if r.has("floor") else lo / WRONG_K
	return {"lo": lo, "hi": hi, "wrong_lo": wlo, "wrong_hi": hi * WRONG_K, "ref": r["ref"], "ref_m": ref_m}


# ---------------------------------------------------------------- the kind

## {"kind", "why"}: the name's words, then where it is worn (A19 tags, then A18 regions, verts near their bone), else prop
static func guess_kind(m: KMesh, mesh_name := "") -> Dictionary:
	var toks := name_words(mesh_name)
	for kw in WORDS:
		for w in kw[1]:
			for t in toks:
				var hit: bool = (t == w or t == w + "s") if w.length() <= 3 else t.begins_with(w)   # "bo" is no "body"
				if hit or (w.contains(" ") and " ".join(toks).contains(w)):
					return {"kind": kw[0], "why": "the name '%s' says %s" % [mesh_name, w]}
	var n := m.vert_count() if m != null else 0
	if n == 0:
		return {"kind": "prop", "why": "an empty mesh"}
	var near := PackedByteArray()
	near.resize(n)
	var has_cm := m.has_attr(KMeshBody.CH_CM)
	for v in n:
		near[v] = 1 if not has_cm or (float(m.get_attr(KMeshBody.CH_CM, v)) >= 0.0 and float(m.get_attr(KMeshBody.CH_CM, v)) <= NEAR * 100.0) else 0
	if has_cm:
		var by := {}
		if m.has_attr(KMeshAnatomy.CH):
			for v in n:
				var t := KMeshAnatomy.tag_of(m, v)
				if near[v] and t != "":
					var k: String = TAG_KIND.get(KMeshAnatomy.stem_of(t), "")
					if k != "":
						by[k] = int(by.get(k, 0)) + 1
			var best := _top(by)
			if best != "" and by[best] >= WORN_FRAC * n:
				return {"kind": best, "why": "%d%% of it sits on the %s (anatomy tags)" % [roundi(100.0 * by[best] / n), {"helmet": "head", "glove": "hand", "boot": "foot", "plate": "trunk"}[best]]}
		by = {}
		if m.has_attr(KMeshBody.CH_REGION):
			for v in n:
				var r: String = KMeshBody.label(m, v)["region"]
				var k: String = REGION_KIND.get(r, "")
				if near[v] and k != "":
					by[k] = int(by.get(k, 0)) + 1
			var best := _top(by)
			if best != "" and by[best] >= WORN_FRAC * n:
				return {"kind": best, "why": "%d%% of it sits on the %s (body regions)" % [roundi(100.0 * by[best] / n), {"helmet": "head", "glove": "hand", "boot": "foot", "plate": "trunk"}[best]]}
	return {"kind": "prop", "why": "no name or body part says what it is: pick the kind"}


## the name's words, lower case: split at anything not a letter, and where a small letter meets a capital ("GreatSword")
static func name_words(s: String) -> PackedStringArray:
	var out := PackedStringArray()
	var cur := ""
	for i in s.length():
		var ch := s[i]
		var letter := ch.to_lower() != ch.to_upper()
		if letter and cur != "" and ch == ch.to_upper() and s[i - 1] == s[i - 1].to_lower():
			out.append(cur)
			cur = ""
		if letter:
			cur += ch.to_lower()
		elif cur != "":
			out.append(cur)
			cur = ""
	if cur != "":
		out.append(cur)
	return out


static func _top(by: Dictionary) -> String:
	var best := ""
	for k in by:
		if best == "" or by[k] > by[best]:
			best = k
	return best


# ---------------------------------------------------------------- the check

static func fmt(m: float) -> String:
	return "%.2f m" % m if m >= 1.0 else ("%.1f cm" % (m * 100.0) if m >= 0.01 else "%.1f mm" % (m * 1000.0))


static func _fmt_range(lo: float, hi: float) -> String:
	if hi < 1.0:
		return "%.0f-%.0f cm" % [lo * 100.0, hi * 100.0]
	return "%.2f-%.2f m" % [lo, hi]


static func _band(x: float, rg: Dictionary) -> String:
	if x >= rg["lo"] - 1e-9 and x <= rg["hi"] + 1e-9:
		return "ok"
	if x < rg["wrong_lo"] or x > rg["wrong_hi"]:
		return "wrong"
	return "suspicious"


## THE CHECK. kind "" or "auto" = guess it. B = the fighter (null = the default body). mesh_name helps the guess.
## -> {"kind", "kind_why", "picked" (the user named the kind), "size" ([long, mid, short] m), "measured" (m), "dim",
##     "lo", "hi", "ref", "ref_m", "verdict", "text", "units": {} | {"factor", "say", "after"}, "box" (obb()), "findings"}
static func check(m: KMesh, kind := "", B: Body = null, mesh_name := "") -> Dictionary:
	var picked := kind != "" and kind != "auto"
	var g := {"kind": kind, "why": "picked"} if picked else guess_kind(m, mesh_name)
	var k: String = g["kind"] if RANGES.has(g["kind"]) else "prop"
	var r: Dictionary = RANGES[k]
	var box := obb(m)
	var size: Array = box["size"]
	var x: float = size[0] if r["dim"] == "long" else size[2]
	var rf := refs(B)
	var rg := range_of(k, rf)
	var out := {"kind": k, "kind_why": g["why"], "picked": picked, "size": size, "measured": x, "dim": r["dim"],
		"lo": rg["lo"], "hi": rg["hi"], "ref": rg["ref"], "ref_m": rg["ref_m"], "box": box, "units": {}}
	if m == null or m.vert_count() == 0:
		out["verdict"] = "wrong"
		out["text"] = "no verts: nothing to measure"
		out["findings"] = [{"id": "real_size", "level": "fail", "text": out["text"]}]
		return out
	var v := _band(x, rg)
	out["verdict"] = v
	var rw: Array = REF_WORDS[rg["ref"]]
	var what := "long" if r["dim"] == "long" else "across its narrowest side"
	var art := "an" if "aeiou".contains(String(r["label"]).left(1)) else "a"
	var how := ""
	if r.has("add"):
		how = "%s %s needs at least the %s + %.0f cm (this fighter's %s is %s, %s), up to %.1f× it" % [art, r["label"], rw[0], float(r["add"]) * 100.0, rw[0], fmt(rg["ref_m"]), rw[1], float(r["hi"])]
	else:
		how = "%s %s is usually %s-%s %s (this fighter's %s is %s, %s)" % [art, r["label"], _num(r["lo"]), _num(r["hi"]), rw[2], rw[0], fmt(rg["ref_m"]), rw[1]]
	out["text"] = "%s %s: %s, so %s. %s" % [fmt(x), what, how, _fmt_range(rg["lo"], rg["hi"]), {"ok": "OK", "suspicious": "SUSPICIOUS", "wrong": "WRONG"}[v]]
	var fs := [{"id": "real_size", "level": {"ok": "ok", "suspicious": "warn", "wrong": "fail"}[v], "text": out["text"]}]
	if v != "ok":
		for u in UNITS:
			var y: float = x * float(u[0])
			if y >= rg["lo"] and y <= rg["hi"]:
				out["units"] = {"factor": float(u[0]), "say": "looks like it was %s: x%s gives %s" % [u[1], _num(u[0]), fmt(y)], "after": y}
				fs.append({"id": "real_size_units", "level": "warn", "text": out["units"]["say"], "fix": "rescale", "factor": float(u[0])})
				out["text"] += ". It " + out["units"]["say"]
				break
	out["findings"] = fs
	return out


static func _num(f: float) -> String:
	return str(snappedf(f, 0.001)).trim_suffix(".0")


## the findings alone (B30's model checks page): [{"id", "level": "ok" | "warn" | "fail", "text"(, "fix", "factor")}]
static func findings(m: KMesh, kind := "", B: Body = null, mesh_name := "") -> Array:
	return check(m, kind, B, mesh_name)["findings"]


## scale the mesh by f about `about` (mesh space); the shape keys' basis and deltas with it. The caller wraps it in one
## KMeshUndo step
static func rescale(m: KMesh, f: float, about: Vector3) -> void:
	var vs := m.verts
	for i in vs.size():
		vs[i] = about + (vs[i] - about) * f
	m.verts = vs
	if not m.shapes.is_empty():
		var bs: PackedVector3Array = m.shapes.get("basis", PackedVector3Array())
		for i in bs.size():
			bs[i] = about + (bs[i] - about) * f
		m.shapes["basis"] = bs
		for key in m.shapes.get("keys", []):
			var d: PackedVector3Array = key.get("delta", PackedVector3Array())
			for i in d.size():
				d[i] *= f
			key["delta"] = d
	m.rebuild()
