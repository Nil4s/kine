## update_check.gd - L16 OPT-IN UPDATE CHECK. OFF by default; the release feed address is EMPTY by default (Kine is not public: there is
## no real endpoint). The user turns it on and types an address. The feed is a small JSON file:
##   {"latest":"0.5.0","notes":"...","url":"..."}   or   {"releases":[{"version":"0.5.0","notes":"..."}, ...]}
## The check compares semver against the build's version and returns a plain-text notice (shown on the status line: never a dialog).
## This file never opens the network: it takes a reader Callable (address -> String or null). file_reader reads file:// only; the app
## supplies a network reader for web addresses, and tests supply only file readers.
class_name UpdateCheck
extends RefCounted


static func default_cfg() -> Dictionary:
	return {"enabled": false, "feed_url": ""}


## [major, minor, patch, release_flag] (release_flag 1 = a release, 0 = a pre-release such as -rc1), or [] when it is not x.y.z
static func parse(v: String) -> Array:
	var s := v.strip_edges()
	if s.begins_with("v") or s.begins_with("V"):
		s = s.substr(1)
	var pre := false
	var dash := s.find("-")
	if dash >= 0:
		pre = true
		s = s.substr(0, dash)
	var parts := s.split(".")
	if parts.size() != 3:
		return []
	var out := []
	for p in parts:
		if not p.is_valid_int():
			return []
		out.append(int(p))
	out.append(0 if pre else 1)
	return out


## -1, 0, 1 (a is older, same, newer). An invalid version compares as 0 (nothing to say)
static func compare(a: String, b: String) -> int:
	var pa := parse(a)
	var pb := parse(b)
	if pa.is_empty() or pb.is_empty():
		return 0
	for i in 4:
		if pa[i] != pb[i]:
			return 1 if pa[i] > pb[i] else -1
	return 0


## feed text + the build's version -> {state: newer|current|error, notify, modal:false, version, notes, url, text}
static func evaluate(feed_text: String, build: String) -> Dictionary:
	var res := {"state": "error", "notify": false, "modal": false, "version": "", "notes": "", "url": "", "text": ""}
	var j = JSON.parse_string(feed_text)
	if typeof(j) != TYPE_DICTIONARY:
		res["text"] = "update check: the feed is not readable"
		return res
	var best := {}
	if j.has("latest"):
		best = {"version": str(j["latest"]), "notes": str(j.get("notes", "")), "url": str(j.get("url", ""))}
	if j.get("releases") is Array:
		for r in j["releases"]:
			if r is Dictionary and not parse(str(r.get("version", ""))).is_empty():
				if best.is_empty() or compare(str(r["version"]), str(best["version"])) > 0:
					best = {"version": str(r["version"]), "notes": str(r.get("notes", "")), "url": str(r.get("url", ""))}
	if best.is_empty() or parse(str(best["version"])).is_empty() or parse(build).is_empty():
		res["text"] = "update check: the feed holds no usable version"
		return res
	res["version"] = best["version"]
	res["notes"] = best["notes"]
	res["url"] = best["url"]
	if compare(str(best["version"]), build) > 0:
		res["state"] = "newer"
		res["notify"] = true
		res["text"] = "Kine %s is available (you have %s)%s" % [best["version"], build, (": " + str(best["notes"])) if str(best["notes"]) != "" else ""]
	else:
		res["state"] = "current"
		res["text"] = "Kine %s is up to date" % build
	return res


## cfg {enabled, feed_url}; reader: Callable(address) -> String or null
static func check(cfg: Dictionary, build: String, reader: Callable) -> Dictionary:
	var off := {"state": "off", "notify": false, "modal": false, "text": ""}
	if not bool(cfg.get("enabled", false)):
		return off
	var url := str(cfg.get("feed_url", "")).strip_edges()
	if url == "":
		off["state"] = "no_feed"
		off["text"] = "update check is on but no feed address is set"
		return off
	var bad := {"state": "error", "notify": false, "modal": false, "text": "update check: the feed could not be read"}
	if not (url.begins_with("file://") or url.begins_with("http://") or url.begins_with("https://")):
		return bad
	if not reader.is_valid():
		return bad
	var body = reader.call(url)
	if body == null:
		return bad
	return evaluate(str(body), build)


## file:// only. Anything else (a network address) returns null: this reader never touches the network.
static func file_reader(url: String):
	if not url.begins_with("file://"):
		return null
	var p := url.substr(7)
	if p.begins_with("/") and p.length() > 2 and p[2] == ":":
		p = p.substr(1)   # file:///C:/x -> C:/x
	if not FileAccess.file_exists(p):
		return null
	return FileAccess.get_file_as_string(p)
