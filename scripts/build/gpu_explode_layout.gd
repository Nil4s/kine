class_name GpuExplodeLayout
extends RefCounted
## s262c: the GPU card's exploded view as SPEC v2 asks (hall_compare/gpu/SPEC.md): layers with BIG gaps so the PCB face shows between them.
## fans +Z 300 mm, shroud +220, cooler +130, backplate -90, X-bracket -140, backplate screws and spring screws -150, IO bracket -X 60, the PCB and everything soldered to it stays.
## Each of the 4 springs rides with ITS spring screw (nearest in the card plane): one layer per pair, so a spring leaves with its screw, before the backplate.
## Installed as ExplodeKeys.layout_hook; the planner still orders the layers and the check still audits the result.

const FANS := ["Fan rotor", "Fan blade", "Fan rim", "Fan sticker", "Fan mark", "Fan ring"]


static func group_of(name_in: String) -> String:
	var name := name_in
	var sp := name.rfind(" ")
	if sp > 0 and name.substr(sp + 1).is_valid_int():
		name = name.substr(0, sp)   # "Fan mark 2" is "Fan mark" (copies carry a number)
	if name in FANS or name.begins_with("Ring glow"):
		return "fans"
	if name == "Shroud" or name == "Shroud facet" or name.begins_with("RGB bar"):
		return "shroud"
	if name == "Fins" or name == "Heat pipe" or name == "Base plate":
		return "cooler"
	if name.begins_with("Backplate screw"):
		return "bpscrews"
	if name == "Backplate":
		return "backplate"
	if name == "X-bracket":
		return "xbracket"
	if name == "Spring screw":
		return "spring"
	if name == "Spring":
		return "spring"
	if name == "IO bracket":
		return "io"
	return "board"


## metres, signed along the plan axis (+Z); io is along -X
const DIST := {"fans": 0.300, "shroud": 0.220, "cooler": 0.130, "backplate": -0.090, "xbracket": -0.140, "bpscrews": -0.150, "spring": -0.150, "io": 0.060}


## the hook: (boxes, names) -> {layers, dist (per layer, signed, 0 = stays), extra_axis {layer: world axis}}
static func layout(boxes: Array, names: Array) -> Dictionary:
	var by := {}
	var springs: Array = []
	var screws: Array = []
	for i in names.size():
		var g := group_of(String(names[i]))
		if g == "spring":
			(screws if String(names[i]) == "Spring screw" else springs).append(i)
			continue
		if not by.has(g):
			by[g] = []
		by[g].append(i)
	var order := ["fans", "shroud", "cooler", "bpscrews", "xbracket", "backplate", "io"]
	var layers: Array = []
	var dist: Array = []
	var extra := {}
	var labels: Array = []
	for g in order:
		if by.has(g):
			# the backplate screws are one layer EACH: a layer's box is the union of its bodies, and 8 screws round the plate would make a box as big as the plate
			for grp in (by[g].map(func(b): return [b]) if g == "bpscrews" else [by[g]]):
				layers.append(grp)
				dist.append(float(DIST[g]))
				labels.append(g)
			if g == "io":
				extra[layers.size() - 1] = Vector3(-1, 0, 0)
	# springs: pair each screw with the nearest spring in the card plane
	var free_sp := springs.duplicate()
	for sc in screws:
		var best := -1
		var bd := INF
		var c: Vector3 = (boxes[sc] as AABB).get_center()
		for sp in free_sp:
			var d := Vector2(c.x, c.y).distance_to(Vector2((boxes[sp] as AABB).get_center().x, (boxes[sp] as AABB).get_center().y))
			if d < bd:
				bd = d
				best = sp
		var pair := [sc]
		if best >= 0:
			pair.append(best)
			free_sp.erase(best)
		layers.insert(0, pair)
		dist.insert(0, float(DIST["spring"]))
		labels.insert(0, "spring")
		for k in extra.keys():
			pass
	# the layers inserted at 0 shifted the extra index
	var ex2 := {}
	for k in extra:
		ex2[int(k) + screws.size()] = extra[k]
	var rest: Array = by.get("board", [])
	for sp in free_sp:
		rest.append(sp)
	layers.append(rest)
	dist.append(0.0)
	labels.append("board")
	return {"layers": layers, "dist": dist, "extra_axis": ex2, "labels": labels}
