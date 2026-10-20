## snap_diff.gd - the one-line diff a timed version snapshot carries (ROADMAP R20). Pure data: two scenes in, a short
## sentence out, built from SceneReport's rows: "cards 12 -> 13; card 4 hold 0.30 s -> 0.50 s; right arm changed on 3 cards".
class_name SnapDiff
extends RefCounted

const MAX_CLAUSES := 4


static func summary(A: Scene, B: Scene, part_name := Callable()) -> String:
	var rows := SceneReport.report(A, B, part_name)
	if rows.is_empty():
		return "no change"
	var out := []
	if A.cards.size() != B.cards.size():
		out.append("cards %d -> %d" % [A.cards.size(), B.cards.size()])
	var joints := {}   # joint text -> {card index: true}
	var other := {"added": 0, "removed": 0, "moved": 0}
	for r in rows:
		var kind: String = r["kind"]
		if kind == "timing":
			var t := String(r["text"])
			out.append("card %d %s" % [int(r["card"]) + 1, t.substr(t.find("timing:") + 8)])
		elif kind == "joint":
			var j := String(part_name.call(r["joint"])) if part_name.is_valid() else String(r["joint"])
			if not joints.has(j):
				joints[j] = {}
			joints[j][int(r["card"])] = true
		elif other.has(kind):
			other[kind] += 1
		elif kind == "weapon":
			out.append("card %d weapon changed" % (int(r["card"]) + 1))
		else:
			out.append("%s changed" % kind)
	for j in joints:
		var n: int = (joints[j] as Dictionary).size()
		if n == 1:
			out.append("%s changed on card %d" % [j, int((joints[j] as Dictionary).keys()[0]) + 1])
		else:
			out.append("%s changed on %d cards" % [j, n])
	if other["moved"] > 0:
		out.append("%d card%s moved" % [other["moved"], "" if other["moved"] == 1 else "s"])
	if other["added"] + other["removed"] > 0 and A.cards.size() == B.cards.size():
		out.append("%d added, %d removed" % [other["added"], other["removed"]])
	if out.size() > MAX_CLAUSES:
		var more := out.size() - MAX_CLAUSES
		out = out.slice(0, MAX_CLAUSES)
		out.append("+%d more" % more)
	return "; ".join(out)
