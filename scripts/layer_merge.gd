## MERGE DOWN (round 49, GATES NA3, UPGRADES_300 #256; Maya's "Merge Layers", Blender's NLA "Apply"): the layers go INTO
## the cards and are removed. The cards keep their times; each card's pose is changed so the scene WITHOUT layers plays,
## at that card's arrival, what the scene WITH them played there.
## Why not "card pose = what plays at its arrival": playback is not the cards' poses at the arrivals (natural overlap
## has the trunk still on its way; pins and the floor plant the legs), so writing the played pose into a card would play
## something else again. Instead a fixed-point pass: each card gets (wanted - played) added, replay, again, ITERS times,
## on every joint and the hips' position; it stops early when the worst miss is under 0.01 deg.
## Between the arrivals the merged scene is the cards' own in-between, which is NOT the layered in-between when a layer's
## weight is keyed; the worst miss over every frame is measured and returned, never assumed.
class_name LayerMerge
extends RefCounted

const ITERS := 6


static func _body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	return b


## S changed in place: cards re-posed, S.layer = {}, S.layers = []. Returns {"iters", "at_cards" (deg, worst at the
## arrivals), "every_frame" (deg, worst over every frame), "frame_at" (where), "cards" (how many changed)}
static func merge(S: Scene) -> Dictionary:
	var ts := S.times()
	var n := S.cards.size()
	var want := []   # what the layered scene plays at each arrival: [ang dict, offset]
	var P := _body()
	for i in n:
		S.apply(P, float(ts[i][1]))
		want.append([P.ang.duplicate(), P.offset])
	var fps := float(maxi(S.fps, 1))
	var frames := []   # the layered scene at every frame, for the honest in-between number
	var L := S.length()
	var k := 0
	while k / fps <= L + 1e-9:
		S.apply(P, k / fps)
		frames.append(P.ang.duplicate())
		k += 1
	var cards0 := JSON.stringify(S.cards)
	S.layer = {}
	S.layers = []
	var C := _body()
	var it := 0
	var worst := 0.0
	while it < ITERS:
		worst = 0.0
		var miss := []
		for i in n:
			S.apply(P, float(ts[i][1]))
			var d := {}
			for j in P.ang:
				var e: Vector3 = (want[i][0][j] as Vector3) - (P.ang[j] as Vector3)
				d[j] = e
				worst = maxf(worst, e.length())
			miss.append([d, (want[i][1] as Vector3) - P.offset])
		if worst < 0.01:
			break
		for i in n:
			C.from_dict(S.cards[i]["pose"])
			for j in miss[i][0]:
				C.ang[j] = C.clamp_ang(j, (C.ang[j] as Vector3) + (miss[i][0][j] as Vector3))
			C.offset += miss[i][1]
			C.fk()
			C.apply_grip()
			S.cards[i]["pose"] = C.to_dict()
		it += 1
	var fw := 0.0
	var fat := ""
	for f in frames.size():
		S.apply(P, f / fps)
		for j in P.ang:
			var e := ((frames[f][j] as Vector3) - (P.ang[j] as Vector3)).length()
			if e > fw:
				fw = e
				fat = "%s at %.3f s" % [j, f / fps]
	var changed := 0
	var c0: Array = JSON.parse_string(cards0)
	for i in n:
		if JSON.stringify(c0[i]["pose"]) != JSON.stringify(JSON.parse_string(JSON.stringify(S.cards[i]["pose"]))):
			changed += 1
	return {"iters": it, "at_cards": worst, "every_frame": fw, "frame_at": fat, "cards": changed}
