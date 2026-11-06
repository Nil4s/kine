## crash_upload.gd - L16 OPT-IN CRASH REPORT UPLOAD. OFF by default; the endpoint is EMPTY by default (Kine is not public).
## The path is: build_payload (redacts) -> preview (the user reads EXACTLY the bytes that would go) -> the user confirms -> send,
## which calls a sink Callable(endpoint, body) -> bool. Nothing here opens a socket; the app supplies the real sink, tests a fake.
## send refuses unless: enabled, an endpoint is set, the user confirmed, a sink exists, the body came from build_payload (marker line)
## and still holds no drive path and no e-mail address.
class_name CrashUpload
extends RefCounted

const MARK := "KINE-CRASH-PAYLOAD v1 (paths, user names and e-mail addresses removed)"


static func default_cfg() -> Dictionary:
	return {"enabled": false, "endpoint": ""}


static func _rx(p: String) -> RegEx:
	var r := RegEx.new()
	r.compile(p)
	return r


static func _esc(t: String) -> String:
	var o := ""
	for ch in t:
		o += ("\\" + ch) if ch in ".*+?^${}()|[]\\" else ch
	return o


## home folders, drive paths, e-mails and the given user names are replaced; res:// and user:// stay
static func redact(s: String, users: Array) -> String:
	var out := _rx("[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+").sub(s, "<email>", true)
	out = _rx("(?i)(/home/|/users/)[^/\\\\\\s]+").sub(out, "<home>", true)
	out = CrashReport.scrub(out)
	for u in users:
		var nm := str(u).strip_edges()
		if nm.length() >= 2:
			out = _rx("(?i)" + _esc(nm)).sub(out, "<user>", true)
	return out


## true when the text still carries a user name, a drive path, a home path or an e-mail
static func leaks(s: String, users: Array) -> bool:
	if _rx("(?<![A-Za-z])[A-Za-z]:[\\\\/]").search(s) != null:
		return true
	if _rx("[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+").search(s) != null:
		return true
	if _rx("(?i)(/home/|/users/)[^/\\\\\\s<]").search(s) != null:
		return true
	var low := s.to_lower()
	for u in users:
		if str(u).strip_edges().length() >= 2 and str(u).strip_edges().to_lower() in low:
			return true
	return false


## ctx {version, os, users}: the exact text that would be sent
static func build_payload(raw_report: String, ctx: Dictionary) -> String:
	var users: Array = ctx.get("users", [])
	var head := "%s\nversion: %s\nos: %s\n----\n" % [MARK, redact(str(ctx.get("version", "")), users), redact(str(ctx.get("os", "")), users)]
	return head + redact(raw_report, users)


## what the user reads before anything is sent: the payload byte for byte, with its size and destination
static func preview(payload: String, cfg: Dictionary) -> String:
	var ep := str(cfg.get("endpoint", ""))
	return "This is EXACTLY what would be sent (%d bytes) to %s. Nothing is sent until you confirm.\n=====\n%s\n=====" % [payload.to_utf8_buffer().size(), ep if ep != "" else "(no endpoint set)", payload]


static func send(cfg: Dictionary, payload: String, confirmed: bool, sink: Callable) -> Dictionary:
	if not bool(cfg.get("enabled", false)):
		return {"sent": false, "why": "crash upload is off"}
	var ep := str(cfg.get("endpoint", "")).strip_edges()
	if ep == "":
		return {"sent": false, "why": "no endpoint is set"}
	if not confirmed:
		return {"sent": false, "why": "the user has not confirmed after reading the preview"}
	if not sink.is_valid():
		return {"sent": false, "why": "no sink"}
	if not payload.begins_with(MARK) or leaks(payload.substr(MARK.length()), []):
		return {"sent": false, "why": "the payload is not a redacted one from build_payload"}
	var okk = sink.call(ep, payload)
	return {"sent": bool(okk), "why": "" if bool(okk) else "the sink failed"}
