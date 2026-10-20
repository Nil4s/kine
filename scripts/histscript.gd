## HISTORY AS A SCRIPT (ROADMAP_400 O15): every palette command run in the session is logged (id, human name, time,
## the part picked, a typed "Pose: ..." phrase), and "Help: save this session as a script" writes the log as a .kscript
## in user://scripts/. "Help: run a script..." plays one through the SAME dispatch as the local API (AgentTools.step),
## as ONE undo step. This file is storage + text only (the way macros.gd is); main.gd holds the hook and the player.
## A .kscript is one line per action:  `run <command id>`  |  `set sel <part>`  |  `set pose <words>`  |  `# comment`
## (set card <n> / set joint <j> <bend,side,twist> / set name <text> are read too: they map to the API's step tokens)
class_name Histscript
extends RefCounted

const DIR := "user://scripts"
const EXT := ".kscript"
const HEAD := "# Kine script v1"
const ROW := "Script: "   # the S box shows a script as "Script: <name>"


## one log entry -> its script lines (the human name as a comment first, with the time in the session)
static func lines_of(e: Dictionary) -> Array:
	var out := ["# %s  (t=%.1fs)" % [String(e["name"]).replace("\n", " "), float(e.get("t", 0.0))]]
	if e.get("sel", "") != "":
		out.append("set sel %s" % e["sel"])
	if e.get("words", "") != "":
		out.append("set pose %s" % String(e["words"]).replace("\n", " "))
	else:
		out.append("run %s" % e["id"])
	return out


static func text_of(log: Array) -> String:
	var out := [HEAD]
	for e in log:
		out.append_array(lines_of(e))
	return "\n".join(out) + "\n"


## [{"line": n, "tok": the API step token, "text": the line}] for the runnable lines; a line that is not understood
## gets "tok" = "" and the reason in "error". Blank lines and # comments are skipped (their numbers are kept)
static func parse(text: String) -> Array:
	var rows := []
	var ls := text.split("\n")
	for i in ls.size():
		var ln := String(ls[i]).strip_edges()
		if ln == "" or ln.begins_with("#"):
			continue
		var verb := ln.get_slice(" ", 0)
		var rest := ln.substr(verb.length()).strip_edges()
		var tok := ""
		var err := ""
		if verb == "run" and rest != "":
			tok = rest
		elif verb == "set" and rest.find(" ") > 0:
			var p := rest.get_slice(" ", 0)
			var v := rest.substr(p.length()).strip_edges()
			match p:
				"sel": tok = "sel=" + v
				"pose": tok = "pose=" + v
				"card": tok = "card=" + v
				"name": tok = "name=" + v
				"joint": tok = "set=" + v
				_: err = "unknown parameter '%s' (set sel / pose / card / joint / name)" % p
		else:
			err = "cannot read '%s' (a line is `run <command id>` or `set <param> <value>`)" % ln
		rows.append({"line": i + 1, "tok": tok, "text": ln, "error": err})
	return rows


static func next_name() -> String:
	var n := 1
	while FileAccess.file_exists("%s/session_%d%s" % [DIR, n, EXT]):
		n += 1
	return "session_%d" % n


## writes user://scripts/<name>.kscript -> the path, "" when it could not be written
static func save(name: String, log: Array) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var path := "%s/%s%s" % [DIR, name, EXT]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(text_of(log))
	return path


static func list_names() -> Array:
	var out := []
	var d := DirAccess.open(DIR)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(EXT):
			out.append(f.get_basename())
	out.sort()
	return out
