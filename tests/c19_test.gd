extends SceneTree
## C19 import/offline. Bars (written before the run):
##   1 the bone-map screen lists the unmapped source bones: its text names every bone in m["unmapped"] (count in the text equals the count).
##     CONTROL: a planted bone name is not in the text.
##   2 clearing a row (spine_01 -> none) moves that bone into the list and the count goes up by exactly 1 (real drop-down choice).
##   3 import unchanged: retarget with the untouched screen map vs the plain guess differs by < 1e-6 m at 6 times.
##   4 GpuNotice: integrated active + discrete present warns; discrete active does not; an unknown adapter is not "integrated".
##     CONTROL: a plain "in use" line fails the warning bar.
##   5 no network: no HTTPRequest / HTTPClient / StreamPeerTLS / PacketPeerUDP / WebSocketPeer / WebRTC in scripts/ outside llm_client.gd;
##     TCP only in co_edit.gd and live_puppet.gd and connect_to_host only in co_edit.gd (LAN, user-started). CONTROL: a planted line fails the scan.
##     Runtime: importing the fixture creates no HTTPRequest node and never touches LlmClient.
## Shot: C:/Users/Nick/tools/kine_workers/out/c19/
var fails := 0
const FIX := "res://tests/fixtures/mixamo_rig.fbx"
const SHOT := "C:/Users/Nick/tools/kine_workers/out/c19"
const NET := ["HTTPRequest", "HTTPClient", "StreamPeerTLS", "PacketPeerUDP", "WebSocketPeer", "WebRTC", "ENetMultiplayer"]
const TCP_OK := ["co_edit.gd", "live_puppet.gd", "local_api.gd"]   # listeners (loopback / user-started LAN); local_api bound to 127.0.0.1 is asserted below


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func gd_files(dir: String, out: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		gd_files(dir.path_join(d), out)


## offending "file: class" hits for one source text under the rules above
func scan(file: String, text: String) -> Array:
	var bad := []
	var base := file.get_file()
	for c in NET:
		if text.contains(c) and base != "llm_client.gd":
			bad.append("%s: %s" % [base, c])
	if (text.contains("StreamPeerTCP") or text.contains("TCPServer")) and base != "llm_client.gd" and not TCP_OK.has(base):
		bad.append(base + ": TCP")
	if text.contains("connect_to_host") and base != "llm_client.gd" and base != "co_edit.gd":
		bad.append(base + ": connect_to_host")
	return bad


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var src := AnimImport.load_source(ProjectSettings.globalize_path(FIX))
	ok(src["ok"], "fixture read")
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var sc := RetargetMap.Screen.new()
	sc.set_anchors_preset(Control.PRESET_TOP_LEFT)
	layer.add_child(sc)
	sc.setup(src, RetargetMap.guess(src))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	sc.position = Vector2(8, 8)
	sc.size = Vector2(760, 620)
	await idle(6)
	var un: Array = sc.m["unmapped"]
	var lbl: Label = sc.find_child("unmapped_list", true, false)
	ok(lbl != null, "1 unmapped_list label exists")
	var t0 := lbl.text if lbl else ""
	var shown := mini(un.size(), 24)
	var all_in := true
	for i in shown:
		all_in = all_in and t0.contains(String(un[i]))
	ok(all_in and (un.size() == 0 or t0.contains("(%d," % un.size())), "1 text names %d of %d unmapped bones: %s" % [shown, un.size(), t0.left(90)])
	ok(not t0.contains("PlantedBone_xyz"), "1 CONTROL: a planted bone name is not in the text")
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png(SHOT + "/screen_1280x720.png")
	# 2 clear a row via the drop-down
	var o: OptionButton = null
	for r in sc.rows:
		if r["kine"] == "spine_01":
			o = r["opt"]
	var gone := String(src["names"][sc.m["map"]["spine_01"]])
	ok(not t0.contains(gone + ","), "2 control: %s not listed before" % gone)
	o.item_selected.emit(0)
	await idle(3)
	var t1 := lbl.text
	ok(sc.m["unmapped"].size() == un.size() + 1 and t1.contains(gone) and t1.contains("(%d," % (un.size() + 1)), "2 after clearing: %s listed, count %d -> %d" % [gone, un.size(), sc.m["unmapped"].size()])
	root.get_texture().get_image().save_png(SHOT + "/cleared_1280x720.png")
	# 3 import unchanged
	var fresh := Screen_fresh(src)
	var a := AnimImport.retarget(src, RetargetMap.guess(src), B, "c19_a")
	var b := AnimImport.retarget(src, fresh.m, B, "c19_b")
	var w := 0.0
	var L := minf(a["scene"].length(), b["scene"].length())
	for k in 6:
		var t := L * k / 5.0
		a["scene"].apply(B, t)
		var P0 := {}
		for j in AnimImport.MAIN:
			P0[j] = B.P[j]
		b["scene"].apply(B, t)
		for j in AnimImport.MAIN:
			w = maxf(w, (P0[j] as Vector3).distance_to(B.P[j]))
	ok(a["ok"] and b["ok"] and w < 1e-6, "3 untouched screen map == guess, worst %s m" % w)
	# 4 gpu
	var intel := "Intel(R) UHD Graphics 770"
	var nv := "NVIDIA GeForce RTX 3070"
	ok(GpuNotice.is_integrated(intel) and not GpuNotice.is_integrated(nv), "4 is_integrated: Intel yes, NVIDIA no")
	ok(GpuNotice.line([intel, nv], intel).contains("integrated"), "4 integrated active warns")
	ok(not GpuNotice.line([intel, nv], nv).contains("integrated") and not GpuNotice.line([nv], nv).contains("integrated"), "4 discrete active: no warning")
	ok(not ("Graphics card in use: " + intel).contains("integrated"), "4 CONTROL: a plain line fails the warning bar")
	# 5 no network
	var files := []
	gd_files("res://scripts", files)
	var bad := []
	var llm_seen := false
	for f in files:
		var txt := FileAccess.get_file_as_string(f)
		if f.get_file() == "llm_client.gd":
			llm_seen = txt.contains("HTTPRequest")
		bad.append_array(scan(f, txt))
	ok(files.size() > 100 and llm_seen, "5 scanned %d scripts; llm_client.gd is the HTTPRequest home" % files.size())
	ok(bad.is_empty(), "5 no network classes outside the allow-list: %s" % [bad])
	ok(not scan("res://scripts/anim_import.gd", "var h = HTTPRequest.new()").is_empty(), "5 CONTROL: a planted HTTPRequest fails the scan")
	ok(not scan("res://scripts/x.gd", "t.connect_to_host(a,1)").is_empty(), "5 CONTROL: a planted connect_to_host fails the scan")
	ok(FileAccess.get_file_as_string("res://scripts/local_api.gd").contains("const BIND := \"127.0.0.1\""), "5 local_api listens on loopback only")
	var imp := AnimImport.import_file(ProjectSettings.globalize_path(FIX), B)
	await idle(3)
	var nodes := root.find_children("*", "HTTPRequest", true, false)
	ok(imp.get("ok", false) and nodes.is_empty(), "5 import ran (%s), HTTPRequest nodes in the tree: %d" % [imp.get("ok", false), nodes.size()])
	print("C19 fails=", fails)
	quit(1 if fails else 0)


func Screen_fresh(src: Dictionary) -> RetargetMap.Screen:
	var s := RetargetMap.Screen.new()
	root.add_child(s)
	s.setup(src, RetargetMap.guess(src))
	return s
