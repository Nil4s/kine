extends SceneTree
## godot --headless --path . -s tools/mcpfast_dump.gd   writes CH13's part records and its TDC assembly (with the G2 loop) as JSON for tools/mcp/mcp_bench.py
const P := preload("res://scripts/build/ch13_parts.gd")


func _init() -> void:
	var dir := "C:/Temp/claude/mcpfast"
	DirAccess.make_dir_recursive_absolute(dir)
	var recs := {}
	for nm in P.NAMES:
		recs[nm] = P.record(nm)
	var asm: Dictionary = P.loop_assembly()
	for src in [["recs.json", recs], ["asm.json", asm]]:
		var f := FileAccess.open(dir + "/" + src[0], FileAccess.WRITE)
		f.store_string(JSON.stringify(src[1]))
	print("dumped ", recs.keys(), " asm parts ", asm["parts"].size(), " bytes recs ", JSON.stringify(recs).length(), " asm ", JSON.stringify(asm).length())
	quit(0)
