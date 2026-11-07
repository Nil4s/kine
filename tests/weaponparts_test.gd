## godot --path . -s tests/weaponparts_test.gd     (ROADMAP_400 B28; boots main.tscn: the parts are tagged through the MODEL commands)
## WEAPON PARTS ON A MODEL (scripts/weapon_parts.gd, scripts/weapon_parts_ui.gd). A sword is built from primitives of known size
## (pommel + grip cylinders of 64 sides, guard + blade boxes), turned and moved off the origin so no axis is lucky; its four parts
## are tagged grip / guard / blade / pommel through the commands (MeshTools.op "wpart_grip" ... on the selected faces) and
## "wpart_book" puts the weapon in the grip book (GripBook, a test folder of its own). Bars, written before the code:
##   1 VOLUME  each part's closed-mesh volume is within 0.5% of the analytic box / cylinder volume (a 64-gon is 0.16% under a circle)
##   2 MASS    each part's mass = its mesh volume x its material's density (to 1e-9 relative), also within 0.5% of the analytic mass;
##             every part names its material, density and a source. Densities come from KMeshMeasure.MATERIALS; their sources
##             (EN 1991-1-1 tables A.1/A.4 for steel, USDA FPL-GTR-190 table 5-3a for oak) are UNVERIFIED (from memory, not
##             re-checked this lane), the numbers are textbook values, a real blade varies a few %.
##   3 COM     the weapon's centre of mass is within 1 mm of the analytic mass-weighted centre of the four parts
##   4 BOOK    the entry is in the grip book (file read back through GripBook.find), carries mass, centre of mass and the four parts;
##             its grip axis is the grip part's long axis, pointing from the pommel toward the blade: angle error < 1 degree
##   5 REFUSE  a blade with one face missing (open) is refused WITH a reason naming the hole; no volume, no mass, no entry written,
##             and a book that held the good entry still holds it unchanged
##   6 UNDO    each tag command is exactly one undo step; Ctrl+Z-style undo takes that tag off (face count 0 again), redo puts it back
##   7 PLANTED a deliberately wrong volume (the cylinder's bounding box, 27% over) is run through the SAME 0.5% check and must FAIL it
##   8 COMMANDS the five commands are in MeshTools.TOOLS (the palette) with a description
extends SceneTree

const BOOK := "user://wp_book"
const SEG := 64
const R_POM := 0.02
const D_POM := 0.03
const R_GRIP := 0.015
const D_GRIP := 0.12
const GUARD := Vector3(0.12, 0.02, 0.03)
const BLADE := Vector3(0.05, 0.80, 0.006)
const Y_POM := 0.015
const Y_GRIP := 0.09
const Y_GUARD := 0.16
const Y_BLADE := 0.57
const MAT := {"grip": "oak", "guard": "steel", "blade": "steel", "pommel": "steel"}
var fails := 0
var m: Node
var ed: KMeshEditUI
var xf := Transform3D(Basis.from_euler(Vector3(0.35, 0.2, -0.5)), Vector3(0.4, 0.2, -0.3))
var faces_of := {}   # role -> PackedInt32Array of face indices in the built mesh


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


## the four parts as one mesh (verts moved by xf); faces_of says which faces are which
func build() -> KMesh:
	var vs := PackedVector3Array()
	var fs: Array = []
	var parts := [["pommel", KMeshPrims.cylinder(R_POM, D_POM, SEG, 1), Y_POM], ["grip", KMeshPrims.cylinder(R_GRIP, D_GRIP, SEG, 1), Y_GRIP],
		["guard", KMeshPrims.cube(GUARD, 1), Y_GUARD], ["blade", KMeshPrims.cube(BLADE, 1), Y_BLADE]]
	faces_of = {}
	for p in parts:
		var pm: KMesh = p[1]
		var base := vs.size()
		var fl := PackedInt32Array()
		for v in pm.verts:
			vs.append(xf * (Vector3(v.x, v.y + float(p[2]), v.z)))
		for f in pm.faces:
			var nf := PackedInt32Array()
			for i in f:
				nf.append(int(i) + base)
			fl.append(fs.size())
			fs.append(nf)
		faces_of[p[0]] = fl
	return KMesh.new().from_arrays(vs, fs)


func analytic() -> Dictionary:
	var vol := {"pommel": PI * R_POM * R_POM * D_POM, "grip": PI * R_GRIP * R_GRIP * D_GRIP, "guard": GUARD.x * GUARD.y * GUARD.z, "blade": BLADE.x * BLADE.y * BLADE.z}
	var cy := {"pommel": Y_POM, "grip": Y_GRIP, "guard": Y_GUARD, "blade": Y_BLADE}
	var mass := {}
	var msum := 0.0
	var c := Vector3.ZERO
	for k in vol:
		mass[k] = vol[k] * float(KMeshMeasure.MATERIALS[MAT[k]]["kg_m3"])
		msum += mass[k]
		c += (xf * Vector3(0, cy[k], 0)) * mass[k]
	return {"vol": vol, "mass": mass, "total": msum, "com": c / msum}


func select_role(role: String) -> void:
	ed.sel.set_mode(KMeshSelect.FACE)
	ed.sel.faces = {}
	for fi in faces_of[role]:
		ed.sel.faces[int(fi)] = true
	ed.view.mark_dirty()


func rel(a: float, b: float) -> float:
	return absf(a - b) / maxf(absf(b), 1e-12)


## the volume check of bar 1/7 as one function, so the planted fake meets the same code
func vol_ok(got: float, want: float) -> bool:
	return rel(got, want) < 0.005


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._kmesh_edit_start()
	await idle(3)
	ed = m.kmed
	GripBook.dir = BOOK
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BOOK))
	var km: KMesh = ed.mesh
	var sword := build()
	km.verts = sword.verts
	km.faces = sword.faces
	km.attrs = {}
	km.rebuild()
	ed.view.mark_dirty()
	await idle(2)
	var A := analytic()

	# 8 commands in the palette
	var listed := 0
	for e in MeshTools.TOOLS:
		if String(e.get("do", "")) in ["op:wpart_grip", "op:wpart_guard", "op:wpart_blade", "op:wpart_pommel", "op:wpart_book"] and String(e.get("desc", "")) != "":
			listed += 1
	ok(listed == 5, "(8) the five weapon-part commands are in the palette with a description: %d of 5" % listed)

	# 6 one undo step per tag, undo takes it off, redo puts it back
	var undo_ok := true
	var st_ok := true
	for role in ["grip", "guard", "blade", "pommel"]:
		select_role(role)
		var s0: int = ed.undo.steps.size()
		MeshTools.op("wpart_" + role, m)
		st_ok = st_ok and ed.undo.steps.size() == s0 + 1
		undo_ok = undo_ok and WeaponParts.faces_of(km, role).size() == (faces_of[role] as PackedInt32Array).size()
		if role == "pommel":
			ed.undo.undo()
			var off := WeaponParts.faces_of(km, role).size()
			ed.undo.redo()
			var back := WeaponParts.faces_of(km, role).size()
			undo_ok = undo_ok and off == 0 and back == (faces_of[role] as PackedInt32Array).size()
	ok(st_ok and undo_ok, "(6) each of the 4 tag commands is exactly one undo step %s; tags hold the right face counts, undo takes the pommel's off and redo puts it back %s" % [st_ok, undo_ok])

	# 1 / 2 / 3 through the analysis the book command uses
	var r := WeaponParts.analyse(km, MAT)
	var worst_v := 0.0
	var worst_m := 0.0
	var exact := true
	var named := true
	if r.get("ok", false):
		for k in A["vol"]:
			var p: Dictionary = r["parts"][k]
			worst_v = maxf(worst_v, rel(float(p["volume_m3"]), A["vol"][k]))
			worst_m = maxf(worst_m, rel(float(p["mass_kg"]), A["mass"][k]))
			exact = exact and rel(float(p["mass_kg"]), float(p["volume_m3"]) * float(p["kg_m3"])) < 1e-9
			named = named and String(p.get("material", "")) == MAT[k] and float(p.get("kg_m3", 0)) == float(KMeshMeasure.MATERIALS[MAT[k]]["kg_m3"]) and String(p.get("src", "")) != ""
	ok(r.get("ok", false) and worst_v < 0.005, "(1) closed-mesh volume of every part within 0.5%% of the analytic one: worst %.4f%%" % (worst_v * 100.0))
	ok(r.get("ok", false) and exact and worst_m < 0.005 and named, "(2) mass = volume x density to 1e-9 %s, within 0.5%% of analytic mass (worst %.4f%%), material + density + source named %s" % [exact, worst_m * 100.0, named])
	var com_err := 1e9
	if r.get("ok", false):
		com_err = ((r["com"] as Vector3) - (A["com"] as Vector3)).length()
	ok(com_err < 0.001, "(3) weapon centre of mass %.3f mm from the analytic mass-weighted one (bar 1 mm); total mass %.4f kg vs analytic %.4f" % [com_err * 1000.0, float(r.get("mass_kg", 0.0)), A["total"]])

	# 4 the grip book
	MeshTools.op("wpart_book", m)
	var kind := WeaponParts.KIND_PREFIX + "sword"
	var e := GripBook.find(kind, WeaponParts.ENTRY)
	var axis_err := 999.0
	var want_axis: Vector3 = (xf.basis * Vector3.UP).normalized()
	var has := not e.is_empty() and e.has("grip_axis") and e.has("mass_kg") and e.has("com") and (e.get("parts", {}) as Dictionary).size() == 4
	if has:
		var ga := Vector3(e["grip_axis"][0], e["grip_axis"][1], e["grip_axis"][2])
		axis_err = rad_to_deg(ga.angle_to(want_axis))
	ok(has and axis_err < 1.0 and absf(float(e.get("mass_kg", 0.0)) - A["total"]) / A["total"] < 0.005,
		"(4) grip book entry %s/%s: 4 parts, mass %.4f kg, grip axis error %.3f deg (bar 1), the axis points pommel -> blade" % [kind, WeaponParts.ENTRY, float(e.get("mass_kg", 0.0)), axis_err])

	# 5 an open part is refused with a reason
	var before := FileAccess.get_file_as_string(GripBook.path_of(kind))
	var bf: PackedInt32Array = faces_of["blade"]
	var tags: PackedFloat32Array = km.attr_data(WeaponParts.ATTR)
	var open := km
	var keep: Array = []
	for fi in open.face_count():
		if fi != int(bf[0]):
			keep.append(open.faces[fi])
	var tg2 := PackedFloat32Array()
	for fi in open.face_count():
		if fi != int(bf[0]):
			tg2.append(tags[fi])
	var holey := KMesh.new().from_arrays(open.verts.duplicate(), keep)
	holey.add_attr(WeaponParts.ATTR, KMesh.AD_FACE, TYPE_FLOAT, 0.0)
	holey.set_attr_data(WeaponParts.ATTR, tg2)
	var rr := WeaponParts.analyse(holey, MAT)
	var why := String(rr.get("why", ""))
	var res := WeaponParts.join_book(holey, "sword", MAT)
	var after := FileAccess.get_file_as_string(GripBook.path_of(kind))
	ok(not rr.get("ok", true) and not rr.has("mass_kg") and why.contains("blade") and why.contains("open") and not res.get("ok", true) and after == before,
		"(5) blade with a face missing: refused (%s); no mass given, book file unchanged %s" % [why, after == before])

	# 7 a planted wrong volume must fail the same check
	var fake_vol: float = (2.0 * R_GRIP) * (2.0 * R_GRIP) * D_GRIP   # the bounding box of the grip cylinder
	ok(not vol_ok(fake_vol, A["vol"]["grip"]) and vol_ok(A["vol"]["grip"] * 0.9984, A["vol"]["grip"]),
		"(7) PLANTED: the grip's bounding-box volume (%.1f%% over) FAILS the 0.5%% check, a 64-gon cylinder (0.16%% under) passes it" % ((fake_vol / A["vol"]["grip"] - 1.0) * 100.0))
	print("WEAPONPARTS ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails else 0)
