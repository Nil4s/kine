## undo_budget.gd - THE UNDO MEMORY BUDGET (Friday plan 175): the newest few undo steps stay as they are; older ones are packed
## (var_to_bytes + ZSTD) into one byte blob on the step and unpacked in place when Undo / Redo / the History panel needs them.
## Over the budget (a setting: [undo] budget_mb in the settings file, 64 by default) the oldest steps are forgotten, with a note.
## Object references (scenes, actors) stay on the step as they are: only plain data is packed.
class_name UndoBudget
extends RefCounted

const KEEP_PLAIN := 10          # the newest steps of each list stay unpacked
const MAX_STEPS := 400          # a hard count; the byte budget is what normally ends the stack
const DEFAULT_MB := 64.0
const NOTE := "oldest undo steps forgotten to save memory"
## kept as they are on every step: object references, and the words the lists, the tree and the tooltips read
const PLAIN_KEYS := ["actor", "hero", "spath", "hero_actors", "rt", "scene", "others", "hint", "name", "easy", "lib", "swap", "drag", "_sz", "_z", "_zn"]

static var budget_mb := -1.0    # < 0: not read yet (settings), a test sets it directly
static var keep_plain := -1     # < 0: KEEP_PLAIN (or the KINE_UNDO_KEEP environment variable, for tests that pack everything)
static var packed_total := 0    # steps packed since start (a counter for tests)


static func _keep() -> int:
	if keep_plain < 0:
		var e := OS.get_environment("KINE_UNDO_KEEP")
		keep_plain = int(e) if e != "" else KEEP_PLAIN
	return keep_plain


static func _budget_bytes(m: Object) -> int:
	if budget_mb < 0.0:
		budget_mb = DEFAULT_MB
		var cf := ConfigFile.new()
		if cf.load(String(m.get("settings"))) == OK:
			budget_mb = maxf(0.25, float(cf.get_value("undo", "budget_mb", DEFAULT_MB)))
	return int(budget_mb * 1048576.0)


static func _has_obj(v: Variant) -> bool:
	match typeof(v):
		TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
			return true
		TYPE_ARRAY:
			for x in v:
				if _has_obj(x):
					return true
		TYPE_DICTIONARY:
			for k in v:
				if _has_obj(k) or _has_obj(v[k]):
					return true
	return false


## the plain data of a step that can be packed
static func _data(u: Dictionary) -> Dictionary:
	var part := {}
	for k in u.keys():
		if not PLAIN_KEYS.has(k) and not _has_obj(u[k]):
			part[k] = u[k]
	return part


static func pack(u: Dictionary) -> void:
	if u.has("_z"):
		return
	var part := _data(u)
	if part.is_empty():
		return
	var raw := var_to_bytes(part)
	u["_zn"] = raw.size()
	u["_z"] = raw.compress(FileAccess.COMPRESSION_ZSTD)
	u.erase("_sz")
	for k in part:
		u.erase(k)
	packed_total += 1


## a packed step back to plain, in place (a no-op on a plain one)
static func unpack(u: Dictionary) -> void:
	if not u.has("_z"):
		return
	var raw: PackedByteArray = (u["_z"] as PackedByteArray).decompress(int(u["_zn"]), FileAccess.COMPRESSION_ZSTD)
	var part: Dictionary = bytes_to_var(raw)
	for k in part:
		u[k] = part[k]
	u.erase("_z")
	u.erase("_zn")


## bytes a step holds now / bytes it would hold unpacked
static func size_of(u: Dictionary) -> int:
	if u.has("_z"):
		return (u["_z"] as PackedByteArray).size()
	if not u.has("_sz"):
		u["_sz"] = var_to_bytes(_data(u)).size()
	return int(u["_sz"])


static func raw_size_of(u: Dictionary) -> int:
	return int(u["_zn"]) if u.has("_z") else size_of(u)


## {"bytes": what the two lists hold now, "raw": what they would hold unpacked, "packed": steps packed, "steps": steps}
static func stats(m: Object) -> Dictionary:
	var b := 0
	var r := 0
	var n := 0
	var pk := 0
	for lst in [m.get("undo"), m.get("redo")]:
		for e in lst:
			b += size_of(e)
			r += raw_size_of(e)
			n += 1
			pk += 1 if (e as Dictionary).has("_z") else 0
	return {"bytes": b, "raw": r, "packed": pk, "steps": n}


static func _pack_old(lst: Array) -> void:
	var keep := _keep()
	for i in range(lst.size() - keep):
		pack(lst[i])


## after a step was pushed / undone / redone: pack the old ones, then forget the oldest while over the budget
static func settle(m: Object) -> void:
	var undo: Array = m.get("undo")
	var redo: Array = m.get("redo")
	_pack_old(undo)
	_pack_old(redo)
	var keep := _keep()
	var tree: UndoTree = m.get("_tree")
	if tree != null:
		var live := []
		for lst in [undo, redo]:
			for i in range(maxi(0, lst.size() - keep), lst.size()):
				live.append(lst[i])
		for id in tree.nodes:
			var st: Variant = tree.nodes[id]["state"]
			if st is Dictionary and not st.has("_z"):
				var is_live := false
				for l in live:
					if is_same(l, st):
						is_live = true
						break
				if not is_live:
					pack(st)
	var budget := _budget_bytes(m)
	var total := 0
	for lst in [undo, redo]:
		for e in lst:
			total += size_of(e)
	var forgot := false
	while total > budget and undo.size() > 1:
		var gone: Dictionary = undo.pop_front()
		total -= size_of(gone)
		m.set("undo_dropped", int(m.get("undo_dropped")) + 1)
		if tree != null:
			tree.trim_root()
		forgot = true
	if forgot:
		m.set("undo_note", NOTE)
		if m.get("ui_status") != null:
			m.call_deferred("_say_plain", NOTE)
