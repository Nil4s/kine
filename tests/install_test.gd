## godot --path . -s tests/install_test.gd     (L16 INSTALLER: opt-in update check, opt-in crash upload, clean-machine install script, notices)
## Bars (written BEFORE the code; none is changed after):
##  U1 semver: 0.10.0 > 0.4.0 (numbers, not text), a leading v is read, 0.5.0-rc1 < 0.5.0, junk is invalid
##  U2 default OFF with an EMPTY feed: a default config never calls the reader, and no source file holds a real URL
##  U3 PLANTED: a feed with a NEWER version notifies, an OLDER one does not, an EQUAL one does not, junk is an error with no notice;
##     enabled with an empty feed does nothing; the notice is plain text (no modal); http(s) with no network reader is refused
##  C1 redaction: drive paths, \Users\<name>, /home/<name>, the user name on its own and e-mails are gone; res:// and user:// stay
##  C2 the preview IS the payload (byte for byte) and says how many bytes and where
##  C3 default OFF: disabled, empty endpoint, not confirmed -> the fake sink is never called; all three set -> called once, with the
##     preview's bytes. PLANTED: the raw text holds the user name (the detector sees it), the sent body does not
##  C4 the settings file round-trips and a missing file reads as OFF + empty
##  S1 the smoke flag: `--install-smoke` in a child Godot exits 0 and prints INSTALL_SMOKE OK; a planted missing file exits 3
##  I1 the clean-machine pieces exist: .wsb is well-formed XML mapping the installer, the .ps1 parses clean and installs silently,
##     runs the smoke flag, checks the exit code and files, uninstalls and checks the folder is gone
##  N1 notices: every DLL in native/bin (OpenCascade libTK* included) is named in the generated notices WITH a licence;
##     PLANTED: a DLL dropped from the notices fails the checker (exit 1); a DLL nobody has a licence for fails the generator
extends SceneTree

const DIR := "user://zz_install_test"
var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func g(p: String) -> String:
	return ProjectSettings.globalize_path(p)


func wr(p: String, s: String) -> void:
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(s)
	f.close()


func run(exe: String, args: Array) -> Array:
	var out := []
	var code := OS.execute(exe, args, out, true)
	return [code, "".join(out)]


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(g(DIR))
	var feed_new := g(DIR) + "/feed_new.json"
	var feed_old := g(DIR) + "/feed_old.json"
	var feed_eq := g(DIR) + "/feed_eq.json"
	var feed_bad := g(DIR) + "/feed_bad.json"
	wr(feed_new, '{"latest":"0.5.0","notes":"new things","url":"file://elsewhere"}')
	wr(feed_old, '{"latest":"0.3.9"}')
	wr(feed_eq, '{"latest":"0.4.0"}')
	wr(feed_bad, "this is not json {")
	var reads := [0]
	var reader := func(u: String):
		reads[0] += 1
		return UpdateCheck.file_reader(u)

	# U1
	ok(UpdateCheck.parse("0.4.0") == [0, 4, 0, 1], "U1 parse 0.4.0")
	ok(UpdateCheck.compare("0.10.0", "0.4.0") == 1, "U1 0.10.0 is newer than 0.4.0 (numbers, not text)")
	ok(UpdateCheck.compare("v1.2.3", "1.2.3") == 0, "U1 a leading v is read")
	ok(UpdateCheck.compare("0.5.0-rc1", "0.5.0") == -1, "U1 a release candidate is older than its release")
	ok(UpdateCheck.compare("0.4.0", "0.4.1") == -1, "U1 patch order")
	ok(UpdateCheck.parse("banana").is_empty() and UpdateCheck.parse("").is_empty() and UpdateCheck.parse("1.2").is_empty(), "U1 junk is invalid")

	# U2
	var d := UpdateCheck.default_cfg()
	ok(d.get("enabled", true) == false and str(d.get("feed_url", "x")) == "", "U2 default config: OFF, feed address empty")
	reads[0] = 0
	var r := UpdateCheck.check(d, "0.4.0", reader)
	ok(r.get("state") == "off" and reads[0] == 0 and not r.get("notify", true), "U2 default config: state off, the reader was never called")
	var banned := RegEx.new()
	banned.compile("https?://[A-Za-z0-9-]+\\.[A-Za-z]")
	for p in ["res://scripts/update_check.gd", "res://scripts/crash_upload.gd"]:
		ok(FileAccess.file_exists(p) and banned.search(FileAccess.get_file_as_string(p)) == null, "U2 no real URL in " + p)

	# U3
	var on_new := {"enabled": true, "feed_url": "file://" + feed_new}
	r = UpdateCheck.check(on_new, "0.4.0", reader)
	ok(r.get("state") == "newer" and r.get("notify") == true and str(r.get("version")) == "0.5.0", "U3 PLANTED newer feed notifies (0.5.0)")
	ok("0.5.0" in str(r.get("text", "")) and "0.4.0" in str(r.get("text", "")), "U3 the notice names both versions")
	ok(r.get("modal", true) == false, "U3 the notice is not a modal dialog")
	r = UpdateCheck.check({"enabled": true, "feed_url": "file://" + feed_old}, "0.4.0", reader)
	ok(r.get("state") == "current" and r.get("notify") == false, "U3 PLANTED older feed does NOT notify")
	r = UpdateCheck.check({"enabled": true, "feed_url": "file://" + feed_eq}, "0.4.0", reader)
	ok(r.get("notify") == false, "U3 equal version does not notify")
	r = UpdateCheck.check({"enabled": true, "feed_url": "file://" + feed_bad}, "0.4.0", reader)
	ok(r.get("state") == "error" and r.get("notify") == false, "U3 junk feed is an error, no notice")
	r = UpdateCheck.check({"enabled": true, "feed_url": "file://" + g(DIR) + "/nope.json"}, "0.4.0", reader)
	ok(r.get("state") == "error" and r.get("notify") == false, "U3 missing feed file is an error, no notice")
	reads[0] = 0
	r = UpdateCheck.check({"enabled": true, "feed_url": ""}, "0.4.0", reader)
	ok(r.get("state") == "no_feed" and reads[0] == 0 and r.get("notify") == false, "U3 enabled with an empty feed address does nothing")
	r = UpdateCheck.check({"enabled": true, "feed_url": "feed.invalid/x"}, "0.4.0", reader)
	ok(r.get("state") == "error", "U3 an address that is neither file:// nor http(s) is an error")
	ok(UpdateCheck.file_reader("https://feed.invalid/x.json") == null, "U3 the file reader never opens the network")
	r = UpdateCheck.check({"enabled": true, "feed_url": "https://feed.invalid/x.json"}, "0.4.0", UpdateCheck.file_reader)
	ok(r.get("state") == "error" and r.get("notify") == false, "U3 http(s) with no network reader supplied: refused, no notice")
	var multi := '{"releases":[{"version":"0.4.5"},{"version":"0.6.1","notes":"n"},{"version":"0.5.0"}]}'
	ok(UpdateCheck.evaluate(multi, "0.4.0").get("version") == "0.6.1", "U3 a releases list: the highest version wins")

	# C1
	var me := "Nicolau"
	var raw := "Kine crash report. Page: Part. user %s opened C:\\Users\\%s\\Desktop\\car.kscene and /home/%s/x.json\nmail %s@example.test failed at res://main.tscn and user://autosave.json\nD:\\work\\%s\\a.txt" % [me, me, me, me.to_lower(), me]
	var red := CrashUpload.redact(raw, [me])
	ok(not (me.to_lower() in red.to_lower()), "C1 the user name is gone everywhere (paths, bare, e-mail)")
	ok(not ("C:\\" in red) and not ("D:\\" in red) and not ("/home/" in red) and not ("@" in red), "C1 no drive path, home path or e-mail is left")
	ok("res://main.tscn" in red and "user://autosave.json" in red, "C1 res:// and user:// stay as they are")
	ok(CrashUpload.leaks(raw, [me]) and not CrashUpload.leaks(red, [me]), "C1 the leak detector sees the raw text and not the redacted one")

	# C2, C3
	var rep := {"enabled": true, "endpoint": "fake://sink"}
	var payload := CrashUpload.build_payload(raw, {"version": "0.4.0", "os": "Windows", "users": [me]})
	var prev := CrashUpload.preview(payload, rep)
	ok(payload in prev, "C2 the preview contains the payload byte for byte")
	ok(str(payload.to_utf8_buffer().size()) in prev and "fake://sink" in prev, "C2 the preview says how many bytes and where")
	ok(not CrashUpload.leaks(payload, [me]), "C2 the payload itself holds no user name")
	var got := []
	var sink := func(ep: String, body: String) -> bool:
		got.append([ep, body])
		return true
	var d2 := CrashUpload.default_cfg()
	ok(d2.get("enabled", true) == false and str(d2.get("endpoint", "x")) == "", "C3 default config: OFF, endpoint empty")
	var s1 := CrashUpload.send(d2, payload, true, sink)
	ok(s1.get("sent") == false and got.is_empty(), "C3 default config: nothing is sent")
	s1 = CrashUpload.send({"enabled": true, "endpoint": ""}, payload, true, sink)
	ok(s1.get("sent") == false and got.is_empty(), "C3 enabled but no endpoint: nothing is sent")
	s1 = CrashUpload.send(rep, payload, false, sink)
	ok(s1.get("sent") == false and got.is_empty(), "C3 enabled with an endpoint but the user has not confirmed: nothing is sent")
	s1 = CrashUpload.send(rep, payload, true, sink)
	ok(s1.get("sent") == true and got.size() == 1 and got[0][0] == "fake://sink" and got[0][1] == payload, "C3 all three set: the sink got the previewed bytes, once")
	ok(not CrashUpload.leaks(got[0][1], [me]), "C3 PLANTED: the body at the sink holds no user name")
	s1 = CrashUpload.send(rep, "oops " + me, true, sink)
	ok(s1.get("sent") == false and got.size() == 1, "C3 a payload that still leaks a user name is refused")
	ok(CrashUpload.send({"enabled": true, "endpoint": "fake://sink"}, payload, true, Callable()).get("sent") == false, "C3 no sink supplied: not sent")

	# C4
	var cf := g(DIR) + "/online.cfg"
	DirAccess.remove_absolute(cf)
	ok(OnlineOpt.load_cfg(cf).get("update", {}).get("enabled", true) == false and OnlineOpt.load_cfg(cf).get("crash", {}).get("endpoint", "x") == "", "C4 a missing settings file reads as OFF + empty")
	OnlineOpt.save_cfg(cf, {"update": {"enabled": true, "feed_url": "file://x"}, "crash": {"enabled": true, "endpoint": "fake://y"}})
	var back := OnlineOpt.load_cfg(cf)
	ok(back["update"]["enabled"] == true and back["update"]["feed_url"] == "file://x" and back["crash"]["endpoint"] == "fake://y", "C4 the settings round-trip")
	OnlineOpt.save_cfg(cf, OnlineOpt.load_cfg(g(DIR) + "/none.cfg"))
	ok(OnlineOpt.load_cfg(cf)["update"]["enabled"] == false, "C4 saving the defaults keeps it OFF")

	# S1
	var proj := g("res://").rstrip("/")
	var exe := OS.get_executable_path()
	var sm := run(exe, ["--headless", "--path", proj, "--", "--install-smoke"])
	ok(sm[0] == 0 and "INSTALL_SMOKE OK" in sm[1], "S1 --install-smoke exits 0 and prints INSTALL_SMOKE OK (exit %d)" % sm[0])
	var sf := run(exe, ["--headless", "--path", proj, "--", "--install-smoke", "--install-need=res://data/no_such_file.bin"])
	ok(sf[0] == 3 and "INSTALL_SMOKE FAIL" in sf[1], "S1 PLANTED: a required file that is missing exits 3 (exit %d)" % sf[0])

	# I1
	var wsb := FileAccess.get_file_as_string("res://tools/installer/sandbox/kine_install_test.wsb")
	var xp := XMLParser.new()
	var wsb_ok := xp.open_buffer(wsb.to_utf8_buffer()) == OK
	var tags := []
	while wsb_ok and xp.read() == OK:
		if xp.get_node_type() == XMLParser.NODE_ELEMENT:
			tags.append(xp.get_node_name())
	ok(wsb_ok and "Configuration" in tags and "MappedFolder" in tags and "LogonCommand" in tags, "I1 the .wsb is well-formed and maps a folder and has a logon command")
	ok("<Networking>Disable" in wsb, "I1 the sandbox has no network")
	var ps := "res://tools/installer/sandbox/kine_install_test.ps1"
	var pst := FileAccess.get_file_as_string(ps)
	for need in ["/VERYSILENT", "--install-smoke", "ExitCode", "unins", "Test-Path", "INSTALL_TEST PASS", "INSTALL_TEST FAIL"]:
		ok(need in pst, "I1 the .ps1 holds: " + need)
	var pc := run("powershell", ["-NoProfile", "-Command", "$e=$null;[void][System.Management.Automation.Language.Parser]::ParseFile('" + g(ps) + "',[ref]$null,[ref]$e);if($e.Count -gt 0){$e | ForEach-Object { $_.Message };exit 1}"])
	ok(pc[0] == 0, "I1 the .ps1 parses with no errors " + str(pc[1]).left(200))

	# N1
	var names := []
	for f in DirAccess.get_files_at("res://native/bin"):
		if f.to_lower().ends_with(".dll"):
			names.append(f)
	var real := names.size() >= 20
	if not real:
		names = ["kine_native.windows.template_release.x86_64.dll", "kine_cad.windows.template_release.x86_64.dll", "libTKernel.dll", "libTKMath.dll", "libTKBRep.dll", "libTKBool.dll", "libstdc++-6.dll", "libgcc_s_seh-1.dll", "libwinpthread-1.dll"]
	print("N1 DLL list from ", ("native/bin (%d)" % names.size()) if real else "the built-in fixture (no native/bin)")
	var man := g(DIR) + "/dlls.tsv"
	var lines := []
	for n in names:
		lines.append("%s\t%d" % [n, 1000])
	wr(man, "\n".join(lines) + "\n")
	var out := g(DIR) + "/NOTICES.txt"
	DirAccess.remove_absolute(out)
	var py := "python"
	var gen := run(py, [proj + "/tools/installer/make_notices.py", proj, man, out])
	ok(gen[0] == 0 and FileAccess.file_exists(out), "N1 make_notices.py writes the notices from the manifest (exit %d)" % gen[0])
	var chk := run(py, [proj + "/tools/installer/check_notices.py", out, man])
	ok(chk[0] == 0, "N1 every staged DLL is named in the notices with a licence: " + str(chk[1]).left(200))
	var occ := 0
	var txt := FileAccess.get_file_as_string(out)
	for n in names:
		if str(n).begins_with("libTK"):
			occ += 1
			if not (n in txt):
				ok(false, "N1 OpenCascade lib missing from notices: " + n)
	ok(occ > 0 and "LGPL" in txt and "Open CASCADE" in txt, "N1 %d OpenCascade libs covered, LGPL + exception text present" % occ)
	# planted: drop one DLL's line from the notices
	var cut := []
	for l in txt.split("\n"):
		if not ("libTKMath.dll" in l):
			cut.append(l)
	wr(g(DIR) + "/NOTICES_cut.txt", "\n".join(cut))
	var bad := run(py, [proj + "/tools/installer/check_notices.py", g(DIR) + "/NOTICES_cut.txt", man])
	ok(bad[0] == 1 and "libTKMath.dll" in bad[1], "N1 PLANTED: a DLL missing from the notices fails the checker (exit %d)" % bad[0])
	wr(g(DIR) + "/man_extra.tsv", "\n".join(lines) + "\nlibmystery-9.dll\t5\n")
	var unk := run(py, [proj + "/tools/installer/make_notices.py", proj, g(DIR) + "/man_extra.tsv", g(DIR) + "/NOTICES_unk.txt"])
	ok(unk[0] != 0 and "libmystery-9.dll" in unk[1], "N1 PLANTED: a DLL with no known licence fails the generator (exit %d)" % unk[0])
	var chk2 := run(py, [proj + "/tools/installer/check_notices.py", out, g(DIR) + "/man_extra.tsv"])
	ok(chk2[0] == 1, "N1 PLANTED: a staged DLL the notices never heard of fails the checker")

	print("install: %d fail" % fails)
	quit(1 if fails > 0 else 0)
