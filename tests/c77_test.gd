## godot --headless --path . -s tests/c77_test.gd
## C77: exit-hang guard. Bars (written before any run): (1) every OCCT parallel switch in native/ (SetRunParallel(..), BRepMesh_IncrementalMesh
## 5th argument, OSD_Parallel::, OSD_ThreadPool::DefaultPool(n>1)) is gated by the KINE_PAR_MESH getenv expression; (2) every scripts/*.gd file
## with Thread.start has a wait_to_finish; (3) CONTROL: planted strings with an ungated parallel switch / a start with no wait are CAUGHT.
extends SceneTree

var fails := 0
const GATE := 'std::getenv("KINE_PAR_MESH") != nullptr'


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	if not c:
		fails += 1


func files(dir: String, ext: Array, out: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.get_extension() in ext:
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		files(dir + "/" + d, ext, out)


## offending lines of a C++ text: a parallel switch whose line lacks the gate
func cpp_bad(text: String) -> Array:
	var bad := []
	var rx := RegEx.create_from_string(r"SetRunParallel\s*\(|OSD_Parallel::|BRepMesh_IncrementalMesh\s+\w+\s*\(|BRepMesh_IncrementalMesh\s*\(")
	var n := 0
	for line in text.split("\n"):
		n += 1
		var t := line.strip_edges()
		if t.begins_with("//"):
			continue
		if rx.search(t) == null:
			continue
		var is_mesh := t.contains("BRepMesh_IncrementalMesh")
		if is_mesh:
			if not t.contains(GATE):
				bad.append(n)
		elif not t.contains(GATE):
			bad.append(n)
	return bad


func gd_bad(text: String) -> bool:
	return text.contains("Thread.new") and text.contains(".start(") and not text.contains("wait_to_finish")


func _init() -> void:
	run.call_deferred()


func run() -> void:
	await process_frame
	var cf := []
	files("res://native/cad/src", ["cpp", "h"], cf)
	files("res://native/src", ["cpp", "h"], cf)
	ok(cf.size() > 3, "scanned %d native sources" % cf.size())
	var bad_total := 0
	for f in cf:
		var b := cpp_bad(FileAccess.get_file_as_string(f))
		if not b.is_empty():
			print("   ungated parallel switch: %s lines %s" % [f, b])
		bad_total += b.size()
	ok(bad_total == 0, "no ungated OCCT parallel switch (%d)" % bad_total)
	var gf := []
	files("res://scripts", ["gd"], gf)
	var gbad := []
	for f in gf:
		if gd_bad(FileAccess.get_file_as_string(f)):
			gbad.append(f)
	ok(gbad.is_empty(), "every GDScript Thread.start has a wait_to_finish in its file %s" % str(gbad))
	var te := FileAccess.get_file_as_string("res://native/cad/src/register_types.cpp")
	ok(te.contains("DefaultPool()->Init(1)"), "extension deinit drops the OCCT pool workers")
	# controls
	ok(cpp_bad("BRepMesh_IncrementalMesh inc(s, d, false, a, true);\n").size() == 1, "CONTROL: ungated mesh parallel=true is caught")
	ok(cpp_bad("fuse.SetRunParallel(true);\n").size() == 1, "CONTROL: SetRunParallel(true) is caught")
	ok(cpp_bad("fuse.SetRunParallel(" + GATE + ");\n").is_empty(), "CONTROL: gated SetRunParallel passes")
	ok(gd_bad("var t := Thread.new()\nt.start(f)\n"), "CONTROL: Thread.start with no wait_to_finish is caught")
	print("c77: %d fail" % fails)
	quit(1 if fails else 0)
