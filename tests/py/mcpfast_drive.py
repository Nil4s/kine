"""Drives tools/mcp/poser_mcp.py --cad (raw stdio client, tools/mcp/mcp_bench.py) for tests/mcpfast_test.gd and writes every result to <out>.
argv: godot executable, out json. Needs C:/Temp/claude/mcpfast/{recs,asm}.json (tools/mcpfast_dump.gd; the test writes them first)."""
import json, os, sys, time
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tools", "mcp"))
import mcp_bench as B

G, OUT = sys.argv[1], sys.argv[2]
recs, asm = B.load()
c = B.Client(G, cad=True)
R = {"tools": c.tools}
R["parts_cold"] = {}
for nm, rec in recs.items():
    v, err, ms, nb, tb = c.call("cad_part", {"name": nm, "record": rec})
    R["parts_cold"][nm] = {"v": v, "err": err, "ms": ms, "bytes": nb}
# d: the cache. a hit equals a cold replay (cad_reset, then the same call); a changed record invalidates
v1, e1, ms1, _, _ = c.call("cad_part", {"name": "piston", "record": recs["piston"]})
v2, e2, ms2, _, _ = c.call("cad_part", {"name": "piston"})                     # by name
c.call("cad_reset", {})
v3, e3, ms3, _, _ = c.call("cad_part", {"name": "piston", "record": recs["piston"]})  # cold again
alt = B.tweak(recs["piston"], 5000)                                            # one number nudged by 5 mm
v4, e4, ms4, _, _ = c.call("cad_part", {"name": "piston", "record": alt})
v5, e5, ms5, _, _ = c.call("cad_part", {"name": "piston", "record": alt})
R["cache"] = {"hit": v1, "byname": v2, "cold": v3, "changed": v4, "changed_again": v5, "ms": [ms1, ms2, ms3, ms4, ms5], "err": [e1, e2, e3, e4, e5]}
# the assembly: load, terse and detail check_fit, bom
c.call("cad_reset", {})
v, err, ms, nb, tb = c.call("cad_asm", {"ops": [{"op": "load", "assembly": asm}]})
R["load"] = {"v": v, "err": err, "ms": ms, "bytes": nb}
v, err, ms, nb, tb = c.call("check_fit", {})
R["fit_cold"] = {"v": v, "err": err, "ms": ms, "bytes": nb}
v, err, ms, nb, tb = c.call("check_fit", {})
R["fit_terse"] = {"v": v, "err": err, "ms": ms, "bytes": nb}
v, err, ms, nb, tb = c.call("check_fit", {"detail": True})
R["fit_detail"] = {"v": v, "err": err, "ms": ms, "bytes": nb}
v, err, ms, nb, tb = c.call("bom", {})
R["bom"] = {"v": v, "err": err, "ms": ms, "bytes": nb}
v, err, ms, nb, tb = c.call("bom", {"detail": True})
R["bom_detail"] = {"v": v, "bytes": nb}
# b: warm latency, 9 calls each (build = a changed record, a real replay)
def lat(tool, args, n=9):
    xs = []
    nbs = []
    for _ in range(n):
        a = args() if callable(args) else args
        v, err, ms, nb, tb = c.call(tool, a)
        xs.append(ms)
        nbs.append(nb)
    return {"p50": B.pct(xs, 0.5), "p95": B.pct(xs, 0.95), "max": max(xs), "bytes": max(nbs)}
k = [0]
def fresh():
    k[0] += 1
    return {"name": "piston_w", "record": B.tweak(recs["piston"], k[0])}
R["lat"] = {"build": lat("cad_part", fresh), "replay": lat("cad_part", {"name": "piston", "record": recs["piston"]}), "fit": lat("check_fit", {})}
c.call("cad_part", {"name": "piston", "record": recs["piston"]})
# the cold control: all seven parts replayed from nothing
c.call("cad_reset", {})
v, err, ms, nb, tb = c.call("cad_asm", {"ops": [{"op": "load", "assembly": asm}]})
R["lat"]["cold_load_ms"] = ms
# c: the sizes of the terse replies
R["sizes"] = {"build": R["parts_cold"]["piston"]["bytes"], "replay": R["lat"]["replay"]["bytes"], "fit": R["fit_terse"]["bytes"], "fit_detail": R["fit_detail"]["bytes"]}
# e: eval_gd
E = {}
def ev(key, code):
    v, err, ms, nb, tb = c.call("eval_gd", {"code": code})
    E[key] = {"v": v, "err": err}
ev("expr", "H.assembly()['parts'].size() * 2 + 1")
ev("scripts", 'H.write("res://scripts/zz_mcpfast_forbidden.gd", "x")')
ev("scripts_dotdot", 'H.write("res://scenes/_wip/../../scripts/zz_mcpfast_forbidden2.gd", "x")')
ev("user", 'H.write("user://zz_mcpfast.txt", "x")')
ev("wip", 'return H.write("res://scenes/_wip/zz_mcpfast_ok.txt", "hello")')
ev("temp", 'return H.write("C:/Temp/claude/mcpfast/zz_ok.txt", "hello")')
ev("raw_file", 'var f = FileAccess.open("res://scenes/_wip/zz_raw.txt", FileAccess.WRITE)\nreturn 1')
ev("raw_os", 'return OS.get_name()')
ev("raw_save", 'var i = Image.create(2, 2, false, Image.FORMAT_RGB8)\ni.save_png("res://scenes/_wip/zz_img.png")\nreturn 1')
ev("vol", 'return KCad.volume(H.solids("piston")[0])')
R["eval"] = E
# CH13 rebuilt through MCP calls only (the win): from nothing, one batch per phase
c.call("cad_reset", {})
sent = 0
rec_bytes = len(json.dumps(recs, separators=(",", ":")))
t0 = time.time()
calls = [{"tool": "cad_part", "args": {"name": nm, "record": rec}} for nm, rec in recs.items()]
v1, e1, ms_a, nb_a, _ = c.call("batch", {"calls": calls})
ops = []
for q in asm["parts"]:
    ops.append({"op": "add", "part": q["name"].lower(), "id": q["id"], "name": q["name"], "pos": q["pos"], "rot": q["rot"]})
for j in asm.get("joints", []):
    ops.append(dict(j, op="joint"))
for d in asm.get("drives", []):
    ops.append({"op": "drive", "name": d["name"], "part": d["part"], "kind": d["kind"], "axis": d["axis"], "origin": d["origin"], "range": d["range"]})
v2, e2, ms_b, nb_b, _ = c.call("cad_asm", {"ops": ops})
calls = []
for th in range(0, 360, 10):
    calls.append({"tool": "cad_asm", "args": {"ops": [{"op": "drive_to", "drive": "Crank", "value": th}]}})
    calls.append({"tool": "check_fit", "args": {}})
v3, e3, ms_c, nb_c, _ = c.call("batch", {"calls": calls})
v4, e4, ms_d, nb_d, _ = c.call("bom", {})
R["ch13"] = {"wall_ms": (time.time() - t0) * 1000, "calls": 4, "returned_bytes": nb_a + nb_b + nb_c + nb_d, "sent_bytes": rec_bytes + len(json.dumps(ops, separators=(",", ":"))) + 36 * 90 + 40,
             "ms": [ms_a, ms_b, ms_c, ms_d], "bytes": [nb_a, nb_b, nb_c, nb_d], "err": [e1, e2, e3, e4], "setup": v2 if isinstance(v2, str) else {k: v2.get(k) for k in ("n", "joints", "drives")} if isinstance(v2, dict) else None,
             "angles": 36, "overlap_angles": sum(1 for x in v3 if isinstance(x, dict) and x.get("overlaps")) if isinstance(v3, list) else None,
             "errors_text": [x for x in (v1, v2, v3, v4) if isinstance(x, str)][:2]}
c.close()
json.dump(R, open(OUT, "w"))
print("DRIVE DONE")
