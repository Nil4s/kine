class_name ShareLink
extends RefCounted
## N23 SHARE AS A VIEWER PAGE: a folder user://share/<scene>/ with the .glb and an index.html that plays it (orbit, play/pause,
## a time scrubber, the scene name, the Kine credit), plus <scene>_one_file.html: the same page with the .glb inside it as base64,
## ONE file to send. Nothing is uploaded; the only address in a page is the pinned <model-viewer> script on jsDelivr.
## (A page opened from a folder by file:// cannot fetch a sibling file in Chrome; the one-file page has no such limit,
## and index.html works on any web host or `python -m http.server`.)

const ROOT := "user://share"
const CDN := "https://cdn.jsdelivr.net/npm/@google/model-viewer@3.4.0/dist/model-viewer.min.js"


static func esc(s: String) -> String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")


## the glb's own JSON chunk -> {"anims": N, "frames": keys of animation 0's first sampler, "nodes": N}; {} when not a glb
static func glb_info(b: PackedByteArray) -> Dictionary:
	if b.size() < 20 or b.decode_u32(0) != 0x46546C67:
		return {}
	var jl := b.decode_u32(12)
	var j = JSON.parse_string(b.slice(20, 20 + jl).get_string_from_utf8())
	if not (j is Dictionary):
		return {}
	var an: Array = j.get("animations", [])
	var fr := 0
	if an.size() > 0:
		var smp: Array = (an[0] as Dictionary)["samplers"]
		fr = int((j["accessors"][int(smp[0]["input"])] as Dictionary)["count"])
	return {"anims": an.size(), "frames": fr, "nodes": (j.get("nodes", []) as Array).size()}


## the page. b64 = "" -> the .glb is loaded by its relative file name (glb_name); else it is decoded from the page itself.
static func html(scene_name: String, glb_name: String, b64: String, frames: int, fps: int) -> String:
	var n := esc(scene_name)
	var src_js := ("const b64 = \"%s\";\nconst bin = atob(b64), u8 = new Uint8Array(bin.length);\nfor (let i = 0; i < bin.length; i++) u8[i] = bin.charCodeAt(i);\nmv.src = URL.createObjectURL(new Blob([u8], {type: \"model/gltf-binary\"}));" % b64) if b64 != "" else "mv.src = \"%s\";" % glb_name.uri_encode()
	return """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="icon" href="data:,">
<title>%s - Kine</title>
<script type="module" src="%s"></script>
<style>
:root{--bg:#15171c;--fg:#e8e6e1;--dim:#9aa0a8;--acc:#e0a04a;--bar:#232730}
@media (prefers-color-scheme: light){:root{--bg:#f1efe9;--fg:#1d2026;--dim:#5d646d;--acc:#b0701a;--bar:#e0ddd4}}
html,body{margin:0;height:100%%;background:var(--bg);color:var(--fg);font:15px system-ui,sans-serif}
body{display:flex;flex-direction:column}
header{padding:12px 16px;display:flex;align-items:baseline;gap:12px}
h1{margin:0;font-size:20px}
header span{color:var(--dim)}
model-viewer{flex:1;min-height:240px;width:100%%;--poster-color:transparent;background:var(--bg)}
footer{display:flex;align-items:center;gap:12px;padding:10px 16px;background:var(--bar)}
button{background:var(--acc);color:#111;border:0;border-radius:6px;padding:7px 16px;font:inherit;cursor:pointer}
input[type=range]{flex:1;accent-color:var(--acc)}
#t{color:var(--dim);min-width:11em;text-align:right;font-variant-numeric:tabular-nums}
small{color:var(--dim);padding:0 16px 10px;background:var(--bar)}
#err{display:none;padding:8px 16px;color:var(--acc)}
</style></head><body>
<header><h1>%s</h1><span>%d frames at %d fps</span></header>
<div id="err"></div>
<model-viewer id="mv" camera-controls touch-action="pan-y" autoplay shadow-intensity="1" exposure="1" interaction-prompt="none" alt="%s, an animated character"></model-viewer>
<footer><button id="pp">Pause</button><input id="sc" type="range" min="0" max="1000" value="0" aria-label="time"><span id="t">0.00 s</span></footer>
<small>Made with Kine by Teschima Studios. Drag to orbit, scroll to zoom. Nothing here is uploaded.</small>
<script>
const mv = document.getElementById("mv"), pp = document.getElementById("pp"), sc = document.getElementById("sc"), tt = document.getElementById("t"), er = document.getElementById("err");
let scrub = false;
const num = (x) => (typeof x === "number" && isFinite(x)) ? x : 0;
customElements.whenDefined("model-viewer").then(() => {
mv.addEventListener("load", () => { er.style.display = "none"; });
mv.addEventListener("error", (ev) => { if (mv.loaded || !ev.detail || ev.detail.type !== "loadfailure") return; er.style.display = "block"; er.textContent = "The animation file could not be loaded. If you opened this page from a folder, open the _one_file.html page instead."; });
pp.onclick = () => { if (mv.paused) { mv.play(); } else { mv.pause(); } };
mv.addEventListener("play", () => pp.textContent = "Pause");
mv.addEventListener("pause", () => pp.textContent = "Play");
sc.addEventListener("input", () => { scrub = true; mv.pause(); mv.currentTime = (sc.value / 1000) * num(mv.duration); });
sc.addEventListener("change", () => scrub = false);
%s
});
(function tick() {
  const d = num(mv.duration), t = num(mv.currentTime);
  if (!scrub && d > 0) sc.value = Math.round(1000 * (t %% d) / d);
  tt.textContent = t.toFixed(2) + " / " + d.toFixed(2) + " s";
  requestAnimationFrame(tick);
})();
</script></body></html>
""" % [n, CDN, n, frames, fps, n, src_js]


## writes <root>/<scene>/<glb>, index.html and <scene>_one_file.html from an already exported .glb; returns {} on a failure
static func write(glb_path: String, scene_name: String, frames: int, fps: int, root := ROOT) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(glb_path)
	if bytes.is_empty():
		return {}
	var base := scene_name.validate_filename() if scene_name != "" else "scene"
	var dir := "%s/%s" % [root, base]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gname := "%s.glb" % base
	var out := {"dir": dir, "glb": "%s/%s" % [dir, gname], "index": "%s/index.html" % dir, "one": "%s/%s_one_file.html" % [dir, base]}
	if glb_path != out["glb"]:
		var f := FileAccess.open(out["glb"], FileAccess.WRITE)
		if f == null:
			return {}
		f.store_buffer(bytes)
		f.close()
	var pages := {"index": html(scene_name, gname, "", frames, fps), "one": html(scene_name, gname, Marshalls.raw_to_base64(bytes), frames, fps)}
	for k in pages:
		var h := FileAccess.open(out[k], FileAccess.WRITE)
		if h == null:
			return {}
		h.store_string(pages[k])
		h.close()
	out["glb_bytes"] = bytes.size()
	out["one_bytes"] = FileAccess.get_file_as_bytes(out["one"]).size()
	return out
