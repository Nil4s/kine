extends SceneTree
## CH1c: out/ch1/members.json -> a HouseCheck house record -> HouseCheck.check, every line printed.
## godot --headless --path . -s tools/ch1_members_to_house.gd [-- <outdir>]   writes <outdir>/house_check.txt and house_record.json (default res://out/ch1)
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var od: String = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://out/ch1")
	var mj = JSON.parse_string(FileAccess.get_file_as_string("res://out/ch1/members.json"))
	var h := Ch1House.from_members(mj)
	var rep := Ch1House.report(mj)
	for l in rep:
		print(l)
	var f := FileAccess.open(od + "/house_check.txt", FileAccess.WRITE)
	f.store_string("\n".join(rep) + "\n")
	f.close()
	f = FileAccess.open(od + "/house_record.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(h, " "))
	f.close()
	var fl := Ch1House.failing(mj)
	print("FAILING ", fl.size())
	quit(1 if fl.size() > 0 else 0)
