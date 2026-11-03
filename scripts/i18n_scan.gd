class_name I18nScan
extends RefCounted
## C11 (complaint #804): which UI strings in the code have no pt_BR translation. UI string = a literal assigned to a control's `.text`,
## or the first argument of the `_btn / _label / _chip / _check` helpers, in scripts/*.gd. Formatted messages (contain % or {),
## code-like words (no space, lowercase snake_case) and strings with no letter are not UI words and are skipped.
const DIR := "res://scripts"


static func unesc(s: String) -> String:
	return s.replace("\\\"", "\"").replace("\\n", "\n")


const PO := "res://data/i18n/pt_BR.po"


static func msgids(po := PO) -> Dictionary:
	var out := {}
	var re := RegEx.new()
	re.compile("^msgid \"((?:[^\"\\\\]|\\\\.)*)\"")
	for ln in FileAccess.get_file_as_string(po).split("\n"):
		var r := re.search(ln.strip_edges(false, true))
		if r != null and r.get_string(1) != "":
			out[unesc(r.get_string(1))] = true
	return out


static func strings_in(src: String) -> Array:
	var re := RegEx.new()
	re.compile("(?:\\.text\\s*=\\s*|\\b(?:_btn|_label|_chip|_check)\\()\"((?:[^\"\\\\%{]|\\\\[\"n])+)\"")
	var out := []
	for r in re.search_all(src):
		var s := unesc(r.get_string(1))
		if s.strip_edges() == "" or not _has_letter(s) or (s.find(" ") < 0 and s == s.to_lower() and s.find("_") >= 0):
			continue
		out.append(s)
	return out


static func _has_letter(s: String) -> bool:
	for i in s.length():
		var c := s.unicode_at(i)
		if (c >= 65 and c <= 90) or (c >= 97 and c <= 122):
			return true
	return false


## every UI string in scripts/ -> true
static func all_strings(dir := DIR) -> Dictionary:
	var out := {}
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			for s in strings_in(FileAccess.get_file_as_string(dir + "/" + f)):
				out[s] = true
	return out


## UI strings with no msgid, sorted
static func missing(strings: Dictionary, ids: Dictionary) -> Array:
	var out := []
	for s in strings:
		if not ids.has(s):
			out.append(s)
	out.sort()
	return out
