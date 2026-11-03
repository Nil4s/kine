class_name ClipLicence
extends RefCounted
## C16 (complaint 581): a plain-English licence line for a library clip, from licence data ALREADY in the repo, never invented.
## Sources, in order: (1) a note <name>.licence.txt beside the file (Importer writes one; its first line is the licence the
## user gave); (2) a "licence" key in the file itself (a shared pose pack: CC0 / CC-BY / All rights reserved, worded by
## PosePack.LICENCE_SAY). Neither = NOT_RECORDED.
const NOT_RECORDED := "licence not recorded"


static func line(src: String) -> String:
	var base := src.get_basename()
	var note := base + ".licence.txt"
	if not note.begins_with("res://") and not note.begins_with("user://") and not note.is_absolute_path():
		note = "res://" + note
	if FileAccess.file_exists(note):
		var first := FileAccess.get_file_as_string(note).split("\n")[0].strip_edges()
		var low := first.to_lower()
		if first != "" and not low.contains("not given") and not low.contains("not recorded"):
			return "Licence: %s (from %s)" % [first.trim_prefix("licence:").strip_edges(), note.get_file()]
		return NOT_RECORDED
	var path := src if (src.begins_with("res://") or src.begins_with("user://") or src.is_absolute_path()) else "res://" + src
	if path.ends_with(".json") and FileAccess.file_exists(path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary and d.has("licence") and String(d["licence"]) in PosePack.LICENCES:
			var l := String(d["licence"])
			return "Licence: %s, %s" % [l, PosePack.LICENCE_SAY[l]]
	return NOT_RECORDED
