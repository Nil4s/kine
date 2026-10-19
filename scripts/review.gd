class_name Review
## REVIEW WITH FRAME COMMENTS (ROADMAP 29, local-first: no server, no accounts, nothing uploaded).
## (1) "Review: export a review page" writes ONE self-contained HTML file, exports/review/<scene>_<date>.html (_2, _3 ...
## never over an earlier one): the playblast's frames as JPEG data URIs, a scrubber with frame numbers, a comment box per
## frame (kept in the page's own localStorage) and "Download comments" (a small JSON). No external script or style.
## (2) "Review: import comments..." reads that JSON; each comment is a note at its frame, shown on the timeline; a click
## jumps the playhead there. Notes live in the scene under "notes": [{"frame", "text"}] sorted by frame, in the file
## only when there are any. Frames are the scene's own frames (t = frame / fps), so a preview range does not shift them.
## Everything here is static or pure; main.gd owns the capture, the file dialog, the undo step and the timeline.

const DIR := "res://exports/review"
const FORMAT := "poser-review-comments"
const FRAME_W := 640        # the page's frames are this wide at most (JPEG): a page of a few seconds stays a few MB
const JPEG_Q := 0.8
const TEXT_MAX := 500       # characters per comment
const COLOR := Color(0.3, 0.85, 0.95)   # the note marks on the timeline ruler (cyan: not a marker's colours)

const PAGE := """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>__TITLE__</title>
<style>
:root { --bg:#f6f5f2; --ink:#1d1d1b; --mute:#6b6a65; --line:#d9d6ce; --card:#ffffff; --accent:#2d6cdf; }
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --bg:#16161a; --ink:#ecebe6; --mute:#9a988f; --line:#33323a; --card:#202027; --accent:#7aa7ff; } }
:root[data-theme="dark"] { --bg:#16161a; --ink:#ecebe6; --mute:#9a988f; --line:#33323a; --card:#202027; --accent:#7aa7ff; }
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--ink); font: 15px/1.45 system-ui, -apple-system, Segoe UI, sans-serif; }
main { max-width: 980px; margin: 0 auto; padding: 16px; }
h1 { font-size: 20px; margin: 6px 0 12px; }
h2 { font-size: 15px; margin: 22px 0 8px; color: var(--mute); font-weight: 600; text-transform: uppercase; letter-spacing: .04em; }
#stage { display: block; width: 100%; height: auto; background: #000; border-radius: 6px; min-height: 120px; }
#scrub { width: 100%; margin: 12px 0 4px; accent-color: var(--accent); }
#label { color: var(--mute); font-variant-numeric: tabular-nums; }
.row { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; margin-top: 8px; }
button { font: inherit; padding: 6px 12px; border-radius: 6px; border: 1px solid var(--line); background: var(--card); color: var(--ink); cursor: pointer; }
button:hover { border-color: var(--accent); }
textarea { width: 100%; font: inherit; padding: 8px; border-radius: 6px; border: 1px solid var(--line); background: var(--card); color: var(--ink); resize: vertical; }
#saved { color: var(--mute); font-size: 13px; }
#list { padding-left: 0; list-style: none; margin: 0; }
#list li { padding: 8px 0; border-bottom: 1px solid var(--line); }
#list button { padding: 2px 8px; margin-right: 8px; }
.empty { color: var(--mute); }
@media (max-width: 480px) { main { padding: 12px; } }
</style>
</head>
<body>
<main>
<h1>__TITLE__</h1>
<img id="stage" alt="the playblast frame shown">
<input id="scrub" type="range" min="0" max="0" value="0" aria-label="frame">
<div id="label"></div>
<div class="row"><button id="prev" type="button">Previous frame</button><button id="next" type="button">Next frame</button><span class="empty">Left and right arrow keys step a frame.</span></div>
<h2>Comment on this frame</h2>
<textarea id="note" rows="3" placeholder="Write a comment for this frame..."></textarea>
<div class="row"><button id="dl" type="button">Download comments (.json)</button><span id="saved"></span></div>
<h2>All comments</h2>
<ol id="list"></ol>
</main>
<script>
var REVIEW = __DATA__;
(function () {
  var R = REVIEW, N = R.frames.length, KEY = "poser-review:" + R.scene + ":" + R.date;
  var comments = {}, k = 0;
  function $(id) { return document.getElementById(id); }
  function frameOf(i) { return R.first + i; }
  try { comments = JSON.parse(localStorage.getItem(KEY) || "{}") || {}; } catch (e) { comments = {}; }
  function persist() {
    try { localStorage.setItem(KEY, JSON.stringify(comments)); $("saved").textContent = "saved in this browser"; }
    catch (e) { $("saved").textContent = "browser storage is off: use Download comments to keep them"; }
    renderList();
  }
  function renderList() {
    var ul = $("list"), keys = Object.keys(comments).map(Number).sort(function (a, b) { return a - b; });
    ul.innerHTML = "";
    if (!keys.length) { var none = document.createElement("li"); none.className = "empty"; none.textContent = "No comments yet."; ul.appendChild(none); return; }
    keys.forEach(function (f) {
      var li = document.createElement("li"), b = document.createElement("button"), txt = document.createElement("span");
      b.type = "button"; b.textContent = "frame " + f;
      b.onclick = function () { show(f - R.first); };
      txt.textContent = comments[f];
      li.appendChild(b); li.appendChild(txt); ul.appendChild(li);
    });
  }
  function show(i) {
    k = Math.max(0, Math.min(N - 1, i));
    $("stage").src = R.frames[k];
    $("scrub").value = k;
    $("label").textContent = "frame " + frameOf(k) + "  (" + k + " of " + (N - 1) + ", " + (frameOf(k) / R.fps).toFixed(2) + " s)";
    $("note").value = comments[frameOf(k)] || "";
  }
  $("scrub").max = Math.max(0, N - 1);
  $("scrub").oninput = function () { show(Number(this.value)); };
  $("prev").onclick = function () { show(k - 1); };
  $("next").onclick = function () { show(k + 1); };
  $("note").oninput = function () {
    var f = frameOf(k), v = this.value.trim();
    if (v === "") { delete comments[f]; } else { comments[f] = v; }
    persist();
  };
  document.addEventListener("keydown", function (e) {
    if (e.target.tagName === "TEXTAREA") { return; }
    if (e.key === "ArrowLeft") { show(k - 1); }
    if (e.key === "ArrowRight") { show(k + 1); }
  });
  $("dl").onclick = function () {
    var list = Object.keys(comments).map(Number).sort(function (a, b) { return a - b; }).map(function (f) {
      return { frame: f, text: String(comments[f]).trim() };
    }).filter(function (c) { return c.text !== ""; });
    var doc = { format: "poser-review-comments", version: 1, scene: R.scene, fps: R.fps, comments: list };
    var blob = new Blob([JSON.stringify(doc, null, 2) + "\n"], { type: "application/json" });
    var a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = R.scene + "_comments.json";
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(function () { URL.revokeObjectURL(a.href); }, 1000);
  };
  renderList();
  show(0);
})();
</script>
</body>
</html>
"""


## one note, cleaned: frame an int >= 0, text trimmed and cut to TEXT_MAX
static func clean(d: Dictionary) -> Dictionary:
	return {"frame": maxi(0, int(d.get("frame", 0))), "text": String(d.get("text", "")).strip_edges().left(TEXT_MAX)}


## the scene file's list -> clean notes, by frame (anything without a frame or with no text is dropped; a repeat is once)
static func notes_from_list(l) -> Array:
	var out := []
	if l is Array:
		for d in l:
			if d is Dictionary and d.has("frame"):
				var n := clean(d)
				if n["text"] != "" and not out.has(n):
					out.append(n)
	return by_frame(out)


static func by_frame(ns: Array) -> Array:
	var out := ns.duplicate(true)
	out.sort_custom(func(a, b): return int(a["frame"]) < int(b["frame"]))
	return out


## the notes of a comments file (the page's download): {"ok", "notes", "why"}. Anything else is refused and nothing is read
static func from_comments(text: String) -> Dictionary:
	var d = JSON.parse_string(text)
	if not (d is Dictionary) or String(d.get("format", "")) != FORMAT or not (d.get("comments") is Array):
		return {"ok": false, "notes": [], "why": "not a review comments file (no \"%s\" format with a comments list)" % FORMAT}
	return {"ok": true, "notes": notes_from_list(d["comments"]), "why": ""}


## the scene's notes plus the new ones, the new ones that are not there yet only (by frame and text), by frame
static func merge(have: Array, add: Array) -> Array:
	var out := have.duplicate(true)
	for n in add:
		if not out.has(n):
			out.append(n.duplicate(true))
	return by_frame(out)


## the time of a scene frame in seconds
static func time_of(frame: int, fps: int) -> float:
	return float(frame) / float(maxi(fps, 1))


## the first free page path for base (a scene name) and date: <DIR>/<base>_<date>.html, then _2, _3 ... (never over one)
static func page_path(base: String, date: String, dir := DIR) -> String:
	var stem := "%s/%s_%s" % [dir, base, date]
	var out := stem + ".html"
	var n := 2
	while FileAccess.file_exists(out):
		out = "%s_%d.html" % [stem, n]
		n += 1
	return out


## one playblast frame (a PNG file) -> a JPEG data URI, FRAME_W wide at most. "" when it cannot be read
static func frame_uri(png: String) -> String:
	var im := Image.load_from_file(png)
	if im == null or im.is_empty():
		return ""
	if im.get_width() > FRAME_W:
		im.resize(FRAME_W, maxi(1, roundi(float(im.get_height()) * FRAME_W / im.get_width())), Image.INTERPOLATE_BILINEAR)
	return "data:image/jpeg;base64," + Marshalls.raw_to_base64(im.save_jpg_to_buffer(JPEG_Q))


## the whole page: the template with the data (scene, fps, the scene frame of the first page frame, date, the frames)
## inline. A "</" in the data is written "<\/" so no string can close the script early
static func html(scene: String, fps: int, first: int, frames: Array, date: String) -> String:
	var data := JSON.stringify({"scene": scene, "fps": fps, "first": first, "date": date, "frames": frames}).replace("</", "<\\/")
	return PAGE.replace("__DATA__", data).replace("__TITLE__", (scene + " review").xml_escape())
