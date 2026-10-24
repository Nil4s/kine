## godot --headless --path . -s tools/catalog_check.gd [-- <catalog.json>]   (the shipped data/catalog.json by default)
## every source file exists, every goes_after id exists, no duplicate ids: exit 0 when the catalog is good, 1 otherwise
extends SceneTree


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else Catalog.PATH
	var entries := Catalog.load(path)
	var bad := Catalog.problems(entries) if not entries.is_empty() else ["%s: no entries (missing or not a list)" % path]
	for b in bad:
		print("BAD  " + b)
	print("catalog %s: %d entries, %s" % [path, entries.size(), "OK" if bad.is_empty() else "%d problem(s)" % bad.size()])
	quit(1 if not bad.is_empty() else 0)
