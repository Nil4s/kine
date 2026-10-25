## godot --headless --path . -s tests/check_all_test.gd     (GATES Y1, UPGRADES #70)
## CHECK EVERY SCENE: `poser_cli check_all --html` in its own process over scenes/: every scene's count in the JSON and
## in the report's table equals that scene's own `check` (each run as its own process too); the report's rows of
## findings per scene and its rule totals add up; then a folder in scenes/_wip with a scene named <b>&"x" (escaped in
## the HTML: the name as text, no <b> element) and a one-card scene (listed as skipped). Refused, with nothing
## written: --html into scenes/, and "scenes/_wip/../" (the escape the --out guard let through before round 18), for
## check_all's --html and run's --out alike.
extends SceneTree

var fails := 0
const WIP := "res://scenes/_wip/zz_y1"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func cli(args: Array) -> Dictionary:
	var out := []
	OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "tools/poser_cli.gd", "--"] + args, out, true)
	for line in String(out[0]).split("\n"):
		if line.begins_with("{"):
			return JSON.parse_string(line)
	return {"ok": false, "error": "no JSON line: " + String(out[0]).right(300)}


## the same rules with the same counts (JSON numbers come back as floats; key order does not matter)
func same_counts(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a:
		if not b.has(k) or int(a[k]) != int(b[k]):
			return false
	return true


func count(hay: String, needle: String) -> int:
	return hay.count(needle)


## the report's findings table for one file: the text between its <table class="scene" data-file="f"> and </table>
func section(html: String, f: String) -> String:
	var a := html.find("<table class=\"scene\" data-file=\"%s\">" % f.xml_escape(true))
	if a < 0:
		return ""
	return html.substr(a, html.find("</table>", a) - a)


func _init() -> void:
	var html_path := OS.get_environment("TEMP").replace("\\", "/") + "/poser_check_all_test.html"
	if FileAccess.file_exists(html_path):
		DirAccess.remove_absolute(html_path)
	var r := cli(["check_all", "--html", html_path, "--json"])
	var html := FileAccess.get_file_as_string(html_path)
	var rows: Array = r.get("scenes", [])
	ok(r.get("ok", false) and rows.size() >= 8 and html.begins_with("<!doctype html>"), "1 check_all over scenes/: %d scenes, %d findings, the report written (%d bytes)" % [rows.size(), r.get("findings", -1), html.length()])

	# every scene against its own check, in its own process
	var bad := []
	var sum := 0
	var tot := {}
	for row in rows:
		var c := cli(["check", "scenes/" + row["file"], "--json"])
		var by := {}
		for x in c.get("findings", []):
			by[x["rule"]] = int(by.get(x["rule"], 0)) + 1
		var in_html := count(section(html, row["file"]), "<tr class=\"f\">")
		if int(row["findings"]) != c.get("findings", []).size() or int(row["must_fix"]) != int(c.get("must_fix", -1)) or in_html != int(row["findings"]) \
				or not same_counts(row["rules"], by):
			bad.append([row["file"], row["findings"], c.get("findings", []).size(), in_html])
		sum += int(row["findings"])
		for k in row["rules"]:
			tot[k] = int(tot.get(k, 0)) + int(row["rules"][k])
	ok(bad.is_empty(), "2 every scene: the JSON's count, its must-fix count, its rule counts and its rows in the report = its own `check` (%d scenes, %d processes; bad: %s)" % [rows.size(), rows.size(), bad])
	var tot_ok: bool = sum == int(r["findings"]) and tot.size() == r["rules"].size()
	for k in tot:
		tot_ok = tot_ok and int(r["rules"].get(k, -1)) == tot[k] and ("data-rule=\"%s\">%d</th>" % [String(k).xml_escape(true), tot[k]]) in html
	ok(tot_ok and count(html, "<tr class=\"f\">") == sum, "3 the totals add up: %d findings = the scenes' sum = the report's rows; each rule's total in the JSON and the report's totals row %s" % [sum, tot])

	# a folder of its own: an awkward name, and a scene too short to check
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(WIP))
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json"))
	d["scene"] = "<b>&\"x\""
	var f := FileAccess.open(WIP + "/a.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	d["cards"] = [d["cards"][0]]
	d["scene"] = "one"
	f = FileAccess.open(WIP + "/b.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	var h2_path := WIP + "/report.html"
	var r2 := cli(["check_all", "scenes/_wip/zz_y1", "--html", "scenes/_wip/zz_y1/report.html", "--json"])
	var h2 := FileAccess.get_file_as_string(h2_path)
	var names: Array = r2.get("scenes", []).map(func(x): return x["scene"])
	ok(r2.get("ok", false) and names.size() == 2 and "&lt;b&gt;&amp;&quot;x&quot;" in h2 and not "<b>&" in h2 and not "<b>" in h2,
		"4 a scene named <b>&\"x\": the name escaped in the report (as text, no <b> element), the JSON keeps it as typed (%s)" % [names])
	var sk: Array = r2.get("scenes", []).filter(func(x): return x.has("skipped"))
	ok(sk.size() == 1 and sk[0]["file"] == "b.json" and "skipped: fewer than 2 cards" in h2, "5 a one-card scene: listed, skipped (Check needs two), the run goes on")

	# refusals: nothing written
	var before := DirAccess.get_files_at("res://scenes")
	var refs := [cli(["check_all", "--html", "scenes/zz_report.html"]), cli(["check_all", "--html", "scenes/_wip/../zz_report.html"]),
		cli(["run", "scenes/combo3.json", "mirror_the_whole_pose", "--out", "scenes/_wip/../zz_esc.json"])]
	var after := DirAccess.get_files_at("res://scenes")
	ok(refs.all(func(x): return not x.get("ok", true) and "scenes/_wip/" in String(x.get("error", ""))) and before == after
		and not FileAccess.file_exists("res://scenes/zz_report.html") and not FileAccess.file_exists("res://scenes/zz_esc.json"),
		"6 refused, nothing written: --html into scenes/, --html via scenes/_wip/../, run --out via scenes/_wip/../ (%s)" % [refs.map(func(x): return String(x.get("error", "")).left(50))])

	for p in [WIP + "/a.json", WIP + "/b.json", h2_path, "res://scenes/zz_report.html", "res://scenes/zz_esc.json"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(WIP))
	DirAccess.remove_absolute(html_path)
	ok(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(WIP)), "7 the test's folder and files removed")
	print("CHECK ALL: %d failed" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
