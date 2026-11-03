extends RefCounted
## C46 (finishes #289 from C38): the Combine dialog runs a combine with MORE THAN MAX_SYNC_TOOLS tools through BooleanSafe.run_job (one tool per frame, a
## progress line, Cancel). OK on such a combine: the bodies before the step are replayed, the job cuts/joins/intersects them stepwise, and the answer is parked
## here (`pre`); the commit's replay then TAKES it in Part._combine_step instead of doing the work a second time, so the volume is the job's, step for step the
## same operations as the synchronous path. Cancel releases every temp and leaves the record and the bodies untouched. Small combines never come here.
const BSAFE := preload("res://scripts/build/boolean_safe.gd")
const BUI := preload("res://scripts/build/boolean_progress_ui.gd")
const KCad := preload("res://scripts/kcad.gd")
const MAX_SYNC_TOOLS := 8        # N: more than this many tools = the stepwise job

static var pre := {}             # {"key": String, "id": int}: a finished job's answer, waiting for the commit's replay
static var running := false


static func is_heavy(f: Dictionary) -> bool:
	return String(f.get("t", "combine")) == "combine" and (f.get("tools", []) as Array).size() > MAX_SYNC_TOOLS and not bool(f.get("nudge", false))


static func key(f: Dictionary) -> String:
	return JSON.stringify([int(f.get("target", -1)), f.get("tools", []), String(f.get("op", "join")), bool(f.get("keep", false))])


## the finished answer for this step (ownership passes to the caller), or 0
static func take(f: Dictionary) -> int:
	if pre.is_empty() or String(pre["key"]) != key(f):
		return 0
	var id := int(pre["id"])
	pre = {}
	return id


static func discard() -> void:
	if not pre.is_empty():
		KCad.release(int(pre["id"]))
	pre = {}


static func ready(f: Dictionary) -> bool:
	return not pre.is_empty() and String(pre["key"]) == key(f)


## starts the job for the dialog's feature f (an async function: call it without await; it calls pu.ok_pressed() again when the answer is ready)
static func start(pu, f: Dictionary, edit: int) -> void:
	if running:
		return
	running = true
	discard()
	var rec: Dictionary = pu._ensure().duplicate(true)
	var ft: Array = rec["features"]
	var upto := -1
	if edit >= 0:
		upto = edit - 1
		ft = ft.slice(0, edit)
		rec["features"] = ft
	var rp := Part.replay(rec, upto, {"keep": true})
	var ids: Array = rp.get("ids", [])
	var tg := int(f["target"])
	var tools: Array = []
	var bad := tg < 0 or tg >= ids.size()
	for t in f["tools"]:
		if int(t) < 0 or int(t) >= ids.size() or int(t) == tg:
			bad = true
		else:
			tools.append(ids[int(t)])
	if bad:   # let the synchronous path say why
		for i in ids:
			KCad.release(i)
		running = false
		pu.ok_btn.disabled = false
		pu.dlg_info.text = "These bodies cannot be combined."
		return
	var ui := BUI.new()
	pu.dlg_box.add_child(ui)
	var job := {"cancel": false}
	ui.cancel_pressed.connect(func(): job["cancel"] = true)
	job["on_progress"] = func(d, tt, txt): ui.set_progress(d, tt, txt)
	pu.ok_btn.disabled = true
	pu._say("Combining %d tools one at a time. Cancel stops it and leaves the part as it was." % tools.size())
	var res: Dictionary = await BSAFE.run_job(pu.m.get_tree(), ids[tg], tools, String(f["op"]), job)
	var made := int(res["id"])
	for i in ids:
		if not (bool(res["ok"]) and i == made):   # cancelled / failed: made is the target itself, a temp of ours too
			KCad.release(i)
	if is_instance_valid(ui):
		ui.queue_free()
	running = false
	if pu.dlg.is_empty() or String(pu.dlg.get("t", "")) != "combine":
		if bool(res["ok"]):
			KCad.release(made)
		return
	if bool(res["ok"]):
		pre = {"key": key(f), "id": made}
		pu.ok_pressed()
		return
	pu.ok_btn.disabled = false
	if bool(res["cancelled"]):
		pu.dlg_info.text = String(res["words"])
		pu._say(String(res["words"]))
	else:
		pu.dlg_info.text = String(res["words"])
