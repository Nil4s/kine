## WHERE THE USER'S FILES GO (10-24). An exported build packs res:// READ-ONLY, so every scene, pose and move the app saves
## (Save scene, Easy's clips in scenes/_wip, imports, restores) must go to a folder the user owns: Documents/Kine (else
## user://Kine). Run from source (the editor, the tests), res:// is writable and stays where it was: nothing changes there.
## w(p): where a file meant for res://scenes|moves|poses/... is WRITTEN (and read back); any other path is returned as it is.
## dirs(d): the folders a list reads for res:// folder d: the bundled one (read-only in a build) and the user's copy of it.
class_name UserPaths
extends RefCounted

const OWNED := ["res://scenes", "res://moves", "res://poses", "res://exports", "res://bodies", "res://meshes", "res://trash"]

static var force := false   # a test: behave as an exported build
static var root := ""       # a test: the user's folder (else Documents/Kine, else user://Kine)


static func exported() -> bool:
	return force or OS.has_feature("template")


static func user_root() -> String:
	if root != "":
		return root
	var docs := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	return docs.path_join("Kine") if docs != "" else "user://Kine"


static func w(p: String) -> String:
	if not exported():
		return p
	for o in OWNED:
		if p == o or p.begins_with(o + "/"):
			return user_root().path_join(p.trim_prefix("res://"))
	return p


static func dirs(d: String) -> Array:
	var u := w(d.trim_suffix("/"))
	return [d] if u == d.trim_suffix("/") else [d, u + ("/" if d.ends_with("/") else "")]
