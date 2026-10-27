## RENDER QUEUE (common_gaps CG4): scene files, each with its own format, run one after another. Each job is timed and its log
## line ends with the time ("[0.42 s]"); a job that cannot be exported is named there and the queue goes on. The work is
## BatchExport.export_one (the same writers, a fresh Scene and Body per file), so a queued file's bytes are the bytes of that
## scene exported alone. The batch dialog (scripts/batch_dialog.gd) runs its ticked scenes through this queue.
## Shot renders are not queued: the shot render draws the open scene through the viewport (main.gd _render_shots).
class_name RenderQueue
extends RefCounted


## one job: a scene file and a format id (glb, bvh, usda, fbx)
static func job(scene: String, fmt: String) -> Dictionary:
	return {"scene": scene, "fmt": fmt}


## the folder the files are written to: an exported build maps res://scenes/_wip into the user's folder (UserPaths.w)
static func out_dir(dir: String) -> String:
	return UserPaths.w(dir.strip_edges().replace("\\", "/").trim_suffix("/"))


## one job, timed. Returns BatchExport.export_one's result plus "secs" (wall time of the job) and "line" (its log line)
static func run_one(j: Dictionary, folder: String, taken: Dictionary) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var r := BatchExport.export_one(String(j["scene"]), String(j["fmt"]), folder, taken)
	r["secs"] = float(Time.get_ticks_usec() - t0) / 1000000.0
	r["line"] = "%s  [%.2f s]" % [r["msg"], r["secs"]]
	return r


## every job in order, into dir. A bad folder stops the queue before anything is written (its sentence is the only line).
## progress (optional) is called as progress(i, n, scene file name) before each job. Returns {done, files, failed (the not-ok
## results), results (every job's result, in order), lines (the summary)}
static func run(jobs: Array, dir: String, progress := Callable()) -> Dictionary:
	var bad := BatchExport.check_dir(dir)
	if bad != "":
		return {"done": 0, "files": [], "failed": [], "results": [], "lines": [bad]}
	var folder := out_dir(dir)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var res := {"done": 0, "files": [], "failed": [], "results": [], "lines": []}
	var taken := {}
	for i in jobs.size():
		var j: Dictionary = jobs[i]
		if progress.is_valid():
			progress.call(i, jobs.size(), String(j["scene"]).get_file())
		var r := run_one(j, folder, taken)
		(res["results"] as Array).append(r)
		if r["ok"]:
			(res["files"] as Array).append(r["file"])
		else:
			(res["failed"] as Array).append(r)
	res["done"] = (res["files"] as Array).size()
	res["lines"] = summary_lines(res["done"], res["results"])
	return res


## the summary: "batch: n done, m failed", then one line per job in order, each with its time
static func summary_lines(done: int, results: Array) -> Array:
	var failed := 0
	for r in results:
		if not bool((r as Dictionary)["ok"]):
			failed += 1
	var out := ["batch: %d done, %d failed" % [done, failed]]
	for r in results:
		out.append("  " + String((r as Dictionary)["line"]))
	return out
