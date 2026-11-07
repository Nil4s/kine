## floor_material.gd - FLOOR MATERIAL (N035). A scene's floor sets the shoe-floor friction coefficient mu that the friction judges read:
## Momentum (a stop: the horizontal ground force of a planted foot is at most mu x its vertical load, 1 body weight standing, so the stop's
## bar is min(1.6 BW, mu BW); a pivot: the friction couple scales with mu) and the Force view (the friction cone). "" = no material = the
## judges are exactly what they were. Sources and the numbers' honesty: the header of tests/floorinjury_test.gd.
## Agent tool `floor` (agent_tools.gd, MCP): {action: read | list | set (material) | clear}; set and clear are ONE undo step each.
class_name FloorMaterial
extends RefCounted

const MU := {"mat": 0.75, "concrete": 1.0, "wet_tile": 0.2, "wood": 0.5, "sand": 0.4}
const SRC := {"mat": "rubber sole on dry rubber floor tiles 0.75 (Tribology in Industry 2022; UNVERIFIED: 0.75 not in its text)", "concrete": "rubber on dry concrete 1.0 (trade article, weak)",
	"wet_tile": "wet old tile 0.2-0.3 (tile-cleaning patent table), the low end", "wood": "0.5 = the US floor-safety static COF (Miller 1983, UNVERIFIED (no source found)): a placeholder, no shoe-on-wood value found",
	"sand": "0.4 mine: sand on a floor drops friction below wet (campus study, no number read)"}


## the scene's mu, or -1 with no material
static func mu_of(S: Scene) -> float:
	return float(MU[S.floor_mat]) if MU.has(S.floor_mat) else -1.0


static func serve(m: Node, p: Dictionary) -> Dictionary:
	var a := String(p.get("action", "read"))
	var S: Scene = m.S
	if a == "read":
		return {"ok": true, "result": {"material": S.floor_mat, "mu": mu_of(S) if S.floor_mat != "" else null}}
	if a == "list":
		return {"ok": true, "result": {"materials": MU.duplicate(), "sources": SRC.duplicate()}}
	if a == "set":
		var k := String(p.get("material", ""))
		if not MU.has(k):
			return {"ok": false, "error": "material is one of %s (got '%s')" % [", ".join(MU.keys()), k]}
		m._push_undo()
		S.floor_mat = k
	elif a == "clear":
		m._push_undo()
		S.floor_mat = ""
	else:
		return {"ok": false, "error": "action is one of read, list, set, clear"}
	if m.has_method("_refresh"):
		m._refresh()
	return {"ok": true, "result": {"material": S.floor_mat, "mu": mu_of(S) if S.floor_mat != "" else null}}
