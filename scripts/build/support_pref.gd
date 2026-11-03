class_name SupportPref
## C27: how hard the slicer's supports should grip the print. The choice is written into the 3MF as slicer metadata
## (PrusaSlicer key names), so a slicer that reads them uses the gap and interface. "Slicer default" writes nothing.
const NAMES := ["Slicer default", "Easy to remove", "Strong"]
const SETS := [
	{},
	{"mode": "easy", "support_material_contact_distance": "0.3", "support_material_interface_layers": "3"},
	{"mode": "strong", "support_material_contact_distance": "0.1", "support_material_interface_layers": "0"},
]
const WORDS := [
	"Supports use your slicer's own settings.",
	"Easy to remove: supports sit 0.3 mm off the part with 3 interface layers, so they snap off; the surface under them is rougher.",
	"Strong: supports sit 0.1 mm off the part with no interface, so they hold overhangs well; they are harder to remove and mark the surface.",
]


static func of(i: int) -> Dictionary:
	return (SETS[clampi(i, 0, SETS.size() - 1)] as Dictionary).duplicate()


static func words(i: int) -> String:
	return String(WORDS[clampi(i, 0, WORDS.size() - 1)])


## the metadata lines to insert in the model xml ("" for the default)
static func xml_lines(s: Dictionary) -> String:
	var out := PackedStringArray()
	out.append("<metadata name=\"BambuStudio:3mfVersion\">1</metadata>")   # C32: without it Bambu Studio treats the file as a plain mesh and ignores Metadata/*.config
	for k in ["mode", "support_material_contact_distance", "support_material_interface_layers"]:
		if s.has(k):
			out.append("<metadata name=\"%s\">%s</metadata>" % ["Kine:SupportMode" if k == "mode" else k, s[k]])
	return "\n".join(out)


## reads the settings back from a written .3mf: {} when none
static func read_3mf(path: String) -> Dictionary:
	var z := ZIPReader.new()
	if z.open(path) != OK:
		return {}
	var txt := z.read_file("3D/3dmodel.model").get_string_from_utf8()
	z.close()
	var out := {}
	var rx := RegEx.create_from_string("<metadata name=\"([^\"]+)\">([^<]*)</metadata>")
	for mt in rx.search_all(txt):
		var n: String = mt.get_string(1)
		if n.begins_with("support_material") or n == "Kine:SupportMode":
			out["mode" if n == "Kine:SupportMode" else n] = mt.get_string(2)
	return out


## C32: the files the slicers read. Bambu Studio: Metadata/project_settings.config (JSON, its own key names).
## PrusaSlicer: Metadata/Slic3r_PE.config ("; key = value" lines). Returns [[path, text], ...]; [] for the default.
static func slicer_files(s: Dictionary) -> Array:
	if s.is_empty():
		return []
	var gap := String(s["support_material_contact_distance"])
	var layers := String(s["support_material_interface_layers"])
	var bbs := {
		"from": "project", "name": "project_settings",
		"support_top_z_distance": gap, "support_bottom_z_distance": gap,
		"support_interface_top_layers": layers, "support_interface_bottom_layers": layers,
	}
	var pe := "; support_material_contact_distance = %s
; support_material_interface_layers = %s
" % [gap, layers]
	return [["Metadata/project_settings.config", JSON.stringify(bbs, "    ")], ["Metadata/Slic3r_PE.config", pe]]


## reads the slicer files back from a written .3mf: {bbs_gap, bbs_layers, pe_gap, pe_layers} (missing keys absent)
static func read_slicer_files(path: String) -> Dictionary:
	var z := ZIPReader.new()
	var out := {}
	if z.open(path) != OK:
		return out
	if z.file_exists("Metadata/project_settings.config"):
		var j = JSON.parse_string(z.read_file("Metadata/project_settings.config").get_string_from_utf8())
		if j is Dictionary:
			for k in ["support_top_z_distance", "support_bottom_z_distance", "support_interface_top_layers", "support_interface_bottom_layers"]:
				if j.has(k):
					out[k] = j[k]
	if z.file_exists("Metadata/Slic3r_PE.config"):
		for ln in z.read_file("Metadata/Slic3r_PE.config").get_string_from_utf8().split("
"):
			var kv := ln.trim_prefix("; ").split(" = ")
			if kv.size() == 2:
				out[kv[0]] = kv[1]
	z.close()
	return out
