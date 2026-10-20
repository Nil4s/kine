class_name CheatSheet
extends RefCounted
## P22 (docs/ROADMAP_400.md): a printable cheat sheet made from the command registry (main._commands()), so it can never
## list a command or a key that is not there. Page 1: every command with a key, two columns. Then every command grouped by
## its prefix ("Grip:", "Camera:" ...), name + what it does. One HTML file, print styles included (A4, no background).


static func group_of(name: String) -> String:
	var i := name.find(":")
	return name.left(i).strip_edges() if i > 0 and i < 22 else "General"


static func _esc(s: String) -> String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


## cmds: the registry rows ({"name", "keys", "desc"}); returns {"html", "keyed", "groups"}
static func build(cmds: Array, title := "Kine cheat sheet") -> Dictionary:
	var keyed := []
	var groups := {}
	for c in cmds:
		var n := String(c.get("name", ""))
		if n == "":
			continue
		if String(c.get("keys", "")) != "":
			keyed.append(c)
		var g := group_of(n)
		if not groups.has(g):
			groups[g] = []
		groups[g].append(c)
	keyed.sort_custom(func(a, b): return String(a["name"]) < String(b["name"]))
	var names := groups.keys()
	names.sort_custom(func(a, b): return (groups[a] as Array).size() > (groups[b] as Array).size() if (groups[a] as Array).size() != (groups[b] as Array).size() else String(a) < String(b))
	var h := PackedStringArray()
	h.append("<!doctype html><html><head><meta charset='utf-8'><title>%s</title><style>" % _esc(title))
	h.append("body{font:12px/1.35 system-ui,sans-serif;color:#111;background:#fff;margin:24px}h1{font-size:20px;margin:0 0 4px}")
	h.append("h2{font-size:13px;text-transform:uppercase;letter-spacing:.06em;border-bottom:1px solid #999;margin:14px 0 4px}")
	h.append(".cols{columns:2;column-gap:28px}.row{break-inside:avoid;display:flex;gap:8px;padding:1px 0}")
	h.append("kbd{font:600 11px ui-monospace,monospace;border:1px solid #888;border-radius:3px;padding:0 4px;white-space:nowrap}")
	h.append(".n{font-weight:600}.d{color:#444}.g{break-inside:avoid}@media print{body{margin:10mm}h2{break-after:avoid}}")
	h.append("@page{size:A4;margin:10mm}</style></head><body>")
	h.append("<h1>%s</h1><div class='d'>%d commands, %d with a key. Made from Kine's own command list (Help: printable cheat sheet).</div>" % [_esc(title), cmds.size(), keyed.size()])
	h.append("<h2>Keys</h2><div class='cols'>")
	for c in keyed:
		h.append("<div class='row'><kbd>%s</kbd><span class='n'>%s</span></div>" % [_esc(String(c["keys"])), _esc(String(c["name"]))])
	h.append("</div><div style='break-before:page'></div>")
	for g in names:
		h.append("<div class='g'><h2>%s (%d)</h2><div class='cols'>" % [_esc(g), (groups[g] as Array).size()])
		for c in groups[g]:
			var k := String(c.get("keys", ""))
			h.append("<div class='row'>%s<span><span class='n'>%s</span> <span class='d'>%s</span></span></div>" % [("<kbd>%s</kbd>" % _esc(k)) if k != "" else "", _esc(String(c["name"])), _esc(String(c.get("desc", "")))])
		h.append("</div></div>")
	h.append("</body></html>")
	return {"html": "\n".join(h), "keyed": keyed.size(), "groups": names}


static func write(cmds: Array, path: String) -> Dictionary:
	var r := build(cmds)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		r["why"] = "could not write %s: pick another folder" % path
		return r
	f.store_string(r["html"])
	f.close()
	r["path"] = path
	return r
