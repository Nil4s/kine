## part_sheet.gd - P106 ONE-CLICK INSTRUCTION SHEET (Friday plan item 106; Kine's own idea). Easy Part's "Instruction sheet" button writes one
## printable page: the parts list (each built piece with its volume), then every step with its picture (the part as it stands after that
## step) and its plain words. An HTML file in the Kine folder: open it in the browser, print, Save as PDF. Tests write under PartSheet.dir.
## Not an exploded view yet: the pictures show the part as built, step by step.
class_name PartSheet
extends RefCounted

const DIR := "user://instruction_sheets"
const PIC := Vector2i(240, 180)

static var dir := ""   # "" = DIR; a test may point it at its own user:// folder


static func _esc(s: String) -> String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")


## the page text. steps = [{"upto": feature index, "words": plain words, "png": PNG bytes ("" = no picture)}]; vols = cm3 per piece
static func to_html(title: String, steps: Array, vols: Array, size_mm: Vector3, hardware := []) -> String:
	var h := "<!doctype html>\n<html lang=\"en\"><head><meta charset=\"utf-8\"><title>Instructions - %s</title>\n<style>\n" % _esc(title)
	h += "body{font:15px/1.45 system-ui,Segoe UI,sans-serif;margin:24px auto;max-width:820px;color:%s;background:#fff}\n" % Tok.c("ink").to_html(false)
	h += "h1{font-size:24px;margin:0 0 4px;color:%s}h2{font-size:18px;margin:22px 0 8px;color:%s;border-bottom:2px solid %s}\n" % [Tok.c("heading").to_html(false), Tok.c("heading").to_html(false), Tok.c("accent").to_html(false)]
	h += ".sub{margin:0 0 6px}.piece{font-weight:700}\n"
	h += ".step{display:flex;gap:14px;align-items:center;border:1px solid #ccc;border-left:8px solid %s;border-radius:4px;padding:8px;margin:0 0 10px;break-inside:avoid}\n" % Tok.c("accent").to_html(false)
	h += ".step img{width:240px;height:180px;border:1px solid #bbb;flex:none}.num{font-size:22px;font-weight:700;min-width:36px}\n"
	h += "@media print{body{margin:8mm}}\n</style></head><body>\n"
	h += "<h1>%s</h1>\n<p class=\"sub\">Size %.0f x %.0f x %.0f mm</p>\n" % [_esc(title), size_mm.x, size_mm.z, size_mm.y]
	h += "<h2>Parts list</h2>\n<ul>\n"
	for i in vols.size():
		h += "<li><span class=\"piece\">%.1f cm3</span>, piece %d</li>\n" % [float(vols[i]), i + 1]
	h += "</ul>\n"
	if not hardware.is_empty():   # p063: the screws Fasten these two put in
		h += "<h2>Hardware</h2>\n<ul>\n"
		for hw in hardware:
			h += "<li><span class=\"piece\">%s</span></li>\n" % _esc(String(hw))
		h += "</ul>\n"
	h += "<h2>Steps</h2>\n"
	for i in steps.size():
		var st: Dictionary = steps[i]
		h += "<div class=\"step\"><span class=\"num\">%d</span>" % (i + 1)
		var png: PackedByteArray = st.get("png", PackedByteArray())
		if not png.is_empty():
			h += "<img alt=\"step %d\" src=\"data:image/png;base64,%s\">" % [i + 1, Marshalls.raw_to_base64(png)]
		h += "<div>%s</div></div>\n" % _esc(String(st["words"]))
	if steps.is_empty():
		h += "<p>No steps yet.</p>\n"
	return h + "</body></html>\n"


## the part as it stands after feature `upto`, painted, as PNG bytes. A step with no solid yet (a sketch) shows the part
## as it first gets one, so every step has a picture. "" when the part never has a solid
static func picture(lt: LibraryThumbs, rec: Dictionary, upto: int) -> PackedByteArray:
	var res := Part.replay(rec, upto)
	var k := upto
	while res["mesh"] == null and k < (rec.get("features", []) as Array).size() - 1:
		k += 1
		res = Part.replay(rec, k)
	if res["mesh"] == null:
		return PackedByteArray()
	var mi := MeshInstance3D.new()
	mi.mesh = res["mesh"]
	Part.paint(res["mesh"], res["looks"])
	var node := Node3D.new()
	node.add_child(mi)
	var img: Image = await lt.draw_node(node, PIC)
	if img == null or img.is_empty():
		return PackedByteArray()
	return img.save_png_to_buffer()


## writes the page for the record (the whole part at the end). steps = [{"upto", "words"}] (one per step with words). Returns the file's
## path, or "" when the part has no solid or the file cannot be written
static func write(host: Node, rec: Dictionary, title: String, steps: Array) -> String:
	var fin := Part.replay(rec)
	if fin["mesh"] == null:
		return ""
	var vols: Array = []
	for v in fin["volumes"]:
		vols.append(float(v) * 1.0e6)
	var size_mm: Vector3 = (fin["aabb"] as AABB).size / Part.MM
	var lt := LibraryThumbs.new()
	host.add_child(lt)
	var out: Array = []
	for st in steps:
		var png := await picture(lt, rec, int(st["upto"]))
		out.append({"upto": st["upto"], "words": st["words"], "png": png})
	lt.queue_free()
	var base := dir if dir != "" else DIR
	var folder := UserPaths.w(base)
	var abs := ProjectSettings.globalize_path(folder)
	DirAccess.make_dir_recursive_absolute(abs)
	var nm := title.validate_filename().replace(" ", "_")
	var path := "%s/%s_sheet.html" % [abs, nm]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(to_html(title, out, vols, size_mm, PartFasten.hardware_lines(rec)))
	f.close()
	return path
