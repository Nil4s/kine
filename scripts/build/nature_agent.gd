class_name NatureAgent
extends RefCounted
## nature_agent.gd - FRIDAY 225: the agent_tools "nature" method. {op: "list"} the items; {op: "add", item: {...}} one item (see Nature for the kinds); {op: "words", text: "2 oak trees 5 m tall"};
## {op: "remove", id}; {op: "clear"}; {op: "measure"} the numbers read from what is made (a tree's height and crown, a hedge's length, a scatter's placed count).
## Each change is ONE undo step. Returns {"ok", ...} or {"ok": false, "error"}.

static func serve(m: Node, p: Dictionary) -> Dictionary:
	var op := String(p.get("op", "list"))
	var bd: Dictionary = m.S.building
	match op:
		"list":
			return {"ok": true, "items": (bd.get("nature", []) as Array).duplicate(true)}
		"measure":
			var out := []
			for it in bd.get("nature", []):
				var r := {"id": it["id"], "kind": it["kind"]}
				match String(it["kind"]):
					"tree":
						var t := Nature.make_tree(it)
						var bb := Nature._bounds(t)
						r["height"] = snappedf(bb.end.y, 0.001)
						r["crown"] = snappedf(maxf(bb.size.x, bb.size.z), 0.001)
						r["branches"] = t["branches"]
						r["leaves"] = t["leaf_n"]
					"hedge", "path":
						r["length"] = snappedf(Nature.path_length(it["path"]), 0.001)
					"scatter":
						var sc := Nature.scatter(it, bd)
						r["placed"] = sc["placed"]
						r["asked"] = sc["asked"]
						r["why"] = sc["why"]
				out.append(r)
			return {"ok": true, "measures": out}
		"add":
			var it := Nature.clean(p.get("item", {}))
			if it.is_empty():
				return {"ok": false, "error": "nature add needs {\"item\": {\"kind\": tree|hedge|shrub|grass|flowers|path|scatter, ...}} (see scripts/build/nature.gd for each kind's numbers)"}
			m._step_hint = "Nature: " + String(it["kind"])
			m._push_undo()
			if m.S.building.is_empty():
				m.S.building = Building.make("Untitled")
			var id := Nature.add(m.S.building, it)
			m.bld.sync()
			return {"ok": true, "id": id}
		"words":
			var r2 := NatureWords.parse(String(p.get("text", "")), bd)
			if not bool(r2["ok"]):
				return {"ok": false, "error": String(r2["error"]), "ignored": r2["ignored"]}
			m._step_hint = "Words: " + String(r2["say"])
			m._push_undo()
			if m.S.building.is_empty():
				m.S.building = Building.make("Untitled")
			NatureWords.apply(m.S.building, String(p.get("text", "")))
			m.bld.sync()
			return {"ok": true, "say": r2["say"], "ignored": r2["ignored"], "count": (r2["items"] as Array).size()}
		"remove":
			if Nature.item_of(bd, String(p.get("id", ""))).is_empty():
				return {"ok": false, "error": "nature remove needs {\"id\": an item id from list}"}
			m._step_hint = "Nature: remove"
			m._push_undo()
			Nature.remove(m.S.building, String(p["id"]))
			m.bld.sync()
			return {"ok": true}
		"clear":
			m._step_hint = "Nature: clear"
			m._push_undo()
			m.S.building.erase("nature")
			m.bld.sync()
			return {"ok": true}
	return {"ok": false, "error": "nature ops: list, add, words, remove, clear, measure (got '%s')" % op}
