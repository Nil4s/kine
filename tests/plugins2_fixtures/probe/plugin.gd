extends RefCounted
var last := {}


func command(api, id: String) -> bool:
	match id:
		"all":
			return all(api)
		"m_set_joint": api.set_joint(0, "head", Vector3(10, 5, 2))
		"m_add_card": api.add_card("Added")
		"m_remove_card": api.remove_card(1)
		"m_set_timing": api.set_timing(0, 0.9, 0.7)
		"m_rename_card": api.rename_card(0, "Renamed")
		"m_move_object": api.move_object(0, Vector3(2, 0, 1))
		"m_add_object": api.add_object("crate", Vector3(0, 0, 2))
		"m_remove_object": api.remove_object(0)
		"m_set_key": api.set_key("head", 0.25, Vector3(20, 0, 0))
		"m_remove_key": api.remove_key("head", 0.5)
		"m_tool": api.run_tool("set=head:15,0,0")
	return true


func all(api) -> bool:
	var L := {}
	L["ver"] = api.api_version()
	L["n"] = api.card_count()
	L["cards"] = api.cards()
	L["joints"] = api.joint_names()
	L["perm_files"] = api.has_permission("files")
	L["perm_nope"] = api.has_permission("nope")
	L["info"] = api.scene_info()
	L["objs0"] = api.objects()
	L["add_obj"] = api.add_object("crate", Vector3(0, 0, 2))
	L["bad_obj"] = api.add_object("no_such_kind_zz", Vector3.ZERO)
	L["move_obj"] = api.move_object(0, Vector3(2, 0, 1))
	L["objs1"] = api.objects()
	L["rm_obj"] = api.remove_object(int(L["add_obj"]["index"]))
	L["setj"] = api.set_joint(0, "head", Vector3(10, 5, 2))
	L["add_card"] = api.add_card("Added")
	L["timing"] = api.set_timing(0, 0.9, 0.7)
	L["rename"] = api.rename_card(0, "Renamed")
	L["setk"] = api.set_key("head", 0.25, Vector3(500, 0, 0))
	L["keys"] = api.keys("head")
	L["rmk"] = api.remove_key("head", 0.5)
	L["rm_card"] = api.remove_card(int(L["add_card"]["index"]))
	L["mesh"] = api.mesh_info()
	L["verts"] = api.mesh_vertices(10)
	L["sel0"] = api.selection()
	L["selc"] = api.select_card(1)
	L["selj"] = api.select_joint("hand_r")
	L["sel1"] = api.selection()
	L["tool"] = api.run_tool("sel=head")
	L["tool_bad"] = api.run_tool("quit")
	L["exp"] = api.export("bvh")
	L["exp_bad"] = api.export("exe")
	L["set"] = api.set_setting("count", 7)
	L["get"] = api.get_setting("count", 0)
	L["get_def"] = api.get_setting("absent", "dflt")
	L["wd"] = api.write_data("a.txt", "hi")
	L["rd"] = api.read_data("a.txt")
	L["wf"] = api.write_file("exports/p.txt", "proj")
	L["rf"] = api.read_file("exports/p.txt")
	api.log("probe done")
	last = L
	return true
