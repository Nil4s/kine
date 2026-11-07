class_name AccessPrefs
extends RefCounted
## L115: the choices Settings makes for font scale, colour-blind colours, length unit and the brush pie; remembered in user://kine_access.cfg
## (KINE_ACCESS_FILE names another; a test without that variable never reads or writes the real file).
const SCALES := [1.0, 1.25, 1.5]
## L135: the pen choices per brush page (sculpt | vpaint | wpaint) and the weapon-parts name / materials, remembered with the rest
static var pen_target := {"sculpt": "strength", "vpaint": "strength", "wpaint": "strength"}
static var pen_tilt_sculpt := false


static func file() -> String:
	var e := OS.get_environment("KINE_ACCESS_FILE")
	return e if e != "" else "user://kine_access.cfg"


static func save(key: String, v: Variant) -> void:
	var cf := ConfigFile.new()
	cf.load(file())
	cf.set_value("access", key, v)
	cf.save(file())


## at boot: put the remembered choices into the live state (a fresh profile changes nothing)
static func apply(main: Node, testing := false) -> void:
	if testing and OS.get_environment("KINE_ACCESS_FILE") == "":
		return
	var cf := ConfigFile.new()
	if cf.load(file()) != OK:
		return
	for pg in pen_target.keys():
		pen_target[pg] = String(cf.get_value("access", "pen_target_" + pg, "strength"))
	pen_tilt_sculpt = bool(cf.get_value("access", "pen_tilt_sculpt", false))
	WeaponParts.model_name = String(cf.get_value("access", "wp_name", "sword"))
	WeaponParts.mats = {}
	for r in WeaponParts.ROLES:
		if cf.has_section_key("access", "wp_mat_" + r):
			WeaponParts.mats[r] = String(cf.get_value("access", "wp_mat_" + r, ""))
	Units.set_unit(String(cf.get_value("access", "unit", "cm")))
	main.set("pie_on", bool(cf.get_value("access", "pie", false)))
	Access.set_colourblind(bool(cf.get_value("access", "colourblind", false)))
	var f := float(cf.get_value("access", "font_scale", 1.0))
	if absf(f - 1.0) > 1e-6:
		Access.set_font_scale.call_deferred(main, f)
