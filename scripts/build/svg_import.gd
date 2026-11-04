## C55: SvgImport is now a thin name for the one SVG parser, sketch_import.gd (C53). C15's scale report, width_mm rescale and lower-left origin
## live there as SketchImport.report(); this file keeps the old call names (parse / words / add_to / len_of) so C15's UI and tests are unchanged.
class_name SvgImport
extends RefCounted

const SI := preload("res://scripts/build/sketch_import.gd")


static func len_of(s: String) -> Dictionary:
	return SI.len_of(s)


static func parse(text: String, opts := {}) -> Dictionary:
	return SI.report(text, opts)


static func words(rep: Dictionary) -> String:
	return SI.words(rep)


static func add_to(rec: Dictionary, rep: Dictionary, plane_name := "front") -> String:
	return SI.add_to(rec, rep, plane_name)
