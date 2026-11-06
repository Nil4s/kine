"""CH17: build the 1 MGD water treatment plant through the Kine MCP `--cad` route (tools/mcp/poser_mcp.py), measure the cost, write docs/ch17/plant.json
(records, poses, ports, envelopes, the MCP's own check_fit and bom answers) and docs/ch17/mcp_log.json (every call: tool, ms, reply bytes, bytes sent).

  python tools/ch17_mcp.py [--godot <exe>] [--no-mcp]       (--no-mcp writes the plant data only, with empty mcp answers)

All numbers are mm. A part's local origin is its bounding-box minimum corner; pos is the world place of that corner. Brief: docs/CH17_BRIEF.md."""
import json, os, sys, time, math

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(HERE, "mcp"))
GODOT = "C:/Users/Nick/Tools/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe"
for i, a in enumerate(sys.argv):
    if a == "--godot":
        GODOT = sys.argv[i + 1]

GAP = 0.2
WALL, FLOOR, PY = 300.0, 400.0, 800.0      # wall, floor, pipe centre height
DN250 = (273.0, 261.0)                     # OD, ID
DN200 = (219.0, 207.0)

RECORDS, PARTS, CONNS, ENVS = {}, [], [], []


def prim(feats, kind, op, **kw):
    f = {"t": "prim", "id": "f%d" % (len(feats) + 1), "name": "%s%d" % (kind.capitalize(), len(feats) + 1), "kind": kind, "op": op}
    f.update({k: float(v) if isinstance(v, (int, float)) else v for k, v in kw.items()})
    if op != "new":
        f["into"] = 0
    feats.append(f)


def record(key, feats, material):
    RECORDS[key] = {"version": 1, "name": key, "seq": len(feats), "features": feats, "bom": {"material": material}}
    return key


def add(name, rec, pos, role, material, ports=None):
    pts = {}
    for k, (w, d, bore) in (ports or {}).items():
        pts[k] = {"p": [w[0] - pos[0], w[1] - pos[1], w[2] - pos[2]], "d": list(d), "bore": bore}
    PARTS.append({"name": name, "id": name, "rec": rec, "pos": list(pos), "role": role, "material": material, "ports": pts})


def basin(key, w, h, d, door=None):
    f = []
    prim(f, "box", "new", x=0, y=0, z=0, w=w, h=h, d=d)
    prim(f, "box", "cut", x=WALL, y=FLOOR, z=WALL, w=w - 2 * WALL, h=h - FLOOR, d=d - 2 * WALL)
    return record(key, f, "concrete_rc")


def pipe(name, a, b, dn):
    """straight steel pipe from world point a to b (same y and one of x/z equal)"""
    od, idm = dn
    r = od / 2.0
    ax = 0 if abs(a[0] - b[0]) > 1e-9 else 2
    ln = abs(b[ax] - a[ax]) - 2 * GAP     # 0.2 mm short at each end: KCad.translate takes a float32 Vector3 (about 2 um at 58 m), so a flush contact reads as 3-8 mm3 of overlap
    lo = list(a if a[ax] < b[ax] else b)
    lo[ax] += GAP
    f = []
    axn = "x" if ax == 0 else "z"
    prim(f, "tube", "new", x=0 if ax == 0 else r, y=r, z=r if ax == 0 else 0, axis=axn, r=r, r_in=idm / 2.0, len=ln)
    key = record("PIPE_%d_%d_%s" % (int(od), int(ln), axn), f, "steel")
    pos = [lo[0], PY - r, lo[2] - r] if ax == 0 else [lo[0] - r, PY - r, lo[2]]
    d0 = [0, 0, 0]
    d1 = [0, 0, 0]
    d0[ax] = -1
    d1[ax] = 1
    add(name, key, pos, "pipe", "steel", {"a": (lo, d0, idm), "b": ([lo[0] + (ln if ax == 0 else 0), lo[1], lo[2] + (ln if ax == 2 else 0)], d1, idm)})
    return name


def conn(a, b):
    CONNS.append([a, b])


def build_plant():
    # ---- equipment
    basin("B_INTAKE", 3000, 3500, 6000)
    add("INTAKE", "B_INTAKE", [-24000, 0, -3000], "intake", "concrete_rc", {"outA": ([-21000, PY, 800], (1, 0, 0), 261.0), "outB": ([-21000, PY, -800], (1, 0, 0), 261.0)})
    basin("B_RM", 1600, 2000, 2600)
    add("RM", "B_RM", [0, 0, -1300], "basin", "concrete_rc", {"inA": ([0, PY, 800], (-1, 0, 0), 261.0), "inB": ([0, PY, -800], (-1, 0, 0), 261.0), "out": ([1600, PY, 0], (1, 0, 0), 261.0)})
    basin("B_FLOC", 5700, 4400, 5100)
    add("FLOC", "B_FLOC", [3000, 0, -2550], "basin", "concrete_rc", {"in": ([3000, PY, 0], (-1, 0, 0), 261.0), "out": ([8700, PY, 0], (1, 0, 0), 261.0)})
    basin("B_SED", 16600, 4600, 12600)
    sp = {"in": ([10500, PY, 0], (-1, 0, 0), 261.0)}
    for i, c in enumerate((-4500, 0, 4500)):
        sp["out%d" % (i + 1)] = ([27100, PY, c], (1, 0, 0), 207.0)
    add("SED", "B_SED", [10500, 0, -6300], "basin", "concrete_rc", sp)
    basin("B_FILTER", 4600, 3500, 4100)
    for i, c in enumerate((-4500, 0, 4500)):
        add("F%d" % (i + 1), "B_FILTER", [29000, 0, c - 2050], "filter", "concrete_rc", {"in": ([29000, PY, c], (-1, 0, 0), 207.0), "out": ([33600, PY, c], (1, 0, 0), 207.0)})
    basin("B_CW", 8600, 4400, 14600)
    cp = {"out1": ([44100, PY, 800], (1, 0, 0), 261.0), "out2": ([44100, PY, -800], (1, 0, 0), 261.0)}
    for i, c in enumerate((-4500, 0, 4500)):
        cp["in%d" % (i + 1)] = ([35500, PY, c], (-1, 0, 0), 207.0)
    add("CW", "B_CW", [35500, 0, -7300], "basin", "concrete_rc", cp)
    # pump: box 1000 x 800 x 600 at y 400.., motor cylinder r 250 x 600 on top
    f = []
    prim(f, "box", "new", x=0, y=0, z=0, w=1000, h=800, d=600)
    prim(f, "cylinder", "join", x=500, y=800, z=300, axis="y", r=250, len=600)
    record("PUMP", f, "steel")

    def pump(nm, x0, z):
        add(nm, "PUMP", [x0, 400, z - 300], "pump", "steel", {"in": ([x0, PY, z], (-1, 0, 0), 261.0), "out": ([x0 + 1000, PY, z], (1, 0, 0), 261.0)})
    pump("RPA", -17000, 800)
    pump("RPB", -10000, -800)
    pump("HPA", 46100, 800)
    pump("HPB", 52000, -800)
    f = []
    prim(f, "box", "new", x=0, y=0, z=0, w=600, h=600, d=600)
    record("STUB", f, "steel")
    for nm, z in (("STUBA", 800), ("STUBB", -800)):
        add(nm, "STUB", [58000, 500, z - 300], "stub", "steel", {"in": ([58000, PY, z], (-1, 0, 0), 261.0)})
    # ---- pipes (name, from, to, dn, connect-a, connect-b)
    P = [("P_IN_RPA", (-21000, PY, 800), (-17000, PY, 800), DN250, "INTAKE.outA", "RPA.in"),
         ("P_RPA_RM", (-16000, PY, 800), (0, PY, 800), DN250, "RPA.out", "RM.inA"),
         ("P_IN_RPB", (-21000, PY, -800), (-10000, PY, -800), DN250, "INTAKE.outB", "RPB.in"),
         ("P_RPB_RM", (-9000, PY, -800), (0, PY, -800), DN250, "RPB.out", "RM.inB"),
         ("P_RM_FLOC", (1600, PY, 0), (3000, PY, 0), DN250, "RM.out", "FLOC.in"),
         ("P_FLOC_SED", (8700, PY, 0), (10500, PY, 0), DN250, "FLOC.out", "SED.in")]
    for i, c in enumerate((-4500, 0, 4500)):
        P.append(("P_SED_F%d" % (i + 1), (27100, PY, c), (29000, PY, c), DN200, "SED.out%d" % (i + 1), "F%d.in" % (i + 1)))
    for i, c in enumerate((-4500, 0, 4500)):
        P.append(("P_F%d_CW" % (i + 1), (33600, PY, c), (35500, PY, c), DN200, "F%d.out" % (i + 1), "CW.in%d" % (i + 1)))
    P += [("P_CW_HPA", (44100, PY, 800), (46100, PY, 800), DN250, "CW.out1", "HPA.in"),
          ("P_HPA_STUBA", (47100, PY, 800), (58000, PY, 800), DN250, "HPA.out", "STUBA.in"),
          ("P_CW_HPB", (44100, PY, -800), (52000, PY, -800), DN250, "CW.out2", "HPB.in"),
          ("P_HPB_STUBB", (53000, PY, -800), (58000, PY, -800), DN250, "HPB.out", "STUBB.in")]
    for nm, a, b, dn, ca, cb in P:
        pipe(nm, a, b, dn)
        conn(nm + ".a", ca)
        conn(nm + ".b", cb)
    # ---- chemical building: walls 300, roof 200, no floor slab, a west door 900 x 2300
    f = []
    prim(f, "box", "new", x=0, y=0, z=0, w=12000, h=4200, d=6500)
    prim(f, "box", "cut", x=WALL, y=0, z=WALL, w=12000 - 2 * WALL, h=4000, d=6500 - 2 * WALL)
    prim(f, "box", "cut", x=0, y=0, z=3600, w=WALL, h=2310, d=900)      # door: world z -13400 .. -12500
    record("B_CHEM", f, "concrete_rc")
    add("BLDG", "B_CHEM", [12000, 0, -17000], "building", "concrete_rc")
    f = []
    prim(f, "cylinder", "new", x=1500, y=0, z=1500, axis="y", r=1500, len=3000)
    record("ALUM_TANK", f, "steel")
    add("ALUM", "ALUM_TANK", [17500, 0, -15500], "tank", "steel")
    f = []
    prim(f, "box", "new", x=0, y=0, z=0, w=2000, h=2300, d=600)
    record("MCC_CAB", f, "steel")
    add("MCC", "MCC_CAB", [13000, 0, -11400], "mcc", "steel")
    # ---- envelopes (world mm). walkways, exit route, MCC working space, pump envelopes
    def env(nm, kind, lo, hi, rule, owner="", allow=()):
        ENVS.append({"name": nm, "kind": kind, "min": lo, "max": hi, "rule": rule, "owner": owner, "allow": list(allow)})
    env("ENV_N", "walkway", [-24000, 0, 8000], [58600, 2300, 9200], "OSHA 1910.36(g)(2) 28 in wide, (g)(1) 7 ft 6 in")
    env("ENV_S", "walkway", [-24000, 0, -9200], [58600, 2300, -8000], "OSHA 1910.36(g)(2), (g)(1)")
    env("ENV_W", "walkway", [10800, 0, -13400], [11990, 2300, -8000], "OSHA 1910.36(g)(2), (g)(1): the way from the south walkway to the door")
    env("ENV_EXIT", "exit", [12100, 0, -13398], [17400, 2300, -12502], "OSHA 1910.36(g): exit access inside the building to the west door")
    env("ENV_MCC", "working", [13000, 0, -12466.8], [15000, 2300, -11400], "OSHA 1910.303(g)(1): 3.5 ft deep, 30 in / equipment wide, 6.5 ft / equipment high", owner="MCC")
    for nm, x0, z, pin, pout in (("RPA", -17000, 800, "P_IN_RPA", "P_RPA_RM"), ("RPB", -10000, -800, "P_IN_RPB", "P_RPB_RM"),
                                 ("HPA", 46100, 800, "P_CW_HPA", "P_HPA_STUBA"), ("HPB", 52000, -800, "P_CW_HPB", "P_HPB_STUBB")):
        env("ENV_" + nm, "pump", [x0 - 900, 0, z - 300 - 900], [x0 + 1000 + 900, 400 + 800 + 600 + 1000, z + 300 + 900], "ASSUMED 900 mm round, motor top + 1000 above", owner=nm, allow=[pin, pout])


def env_record(e):
    lo, hi = e["min"], e["max"]
    f = []
    prim(f, "box", "new", x=0, y=0, z=0, w=hi[0] - lo[0], h=hi[1] - lo[1], d=hi[2] - lo[2])
    return {"version": 1, "name": e["name"], "seq": 1, "features": f}


class Log:
    def __init__(self, client):
        self.c, self.rows = client, []

    def call(self, tool, args, label=None):
        t0 = time.time()
        v, err, ms, nb, tb = self.c.call(tool, args)
        self.rows.append({"label": label or tool, "tool": tool, "ms": round(ms, 1), "reply_bytes": nb, "sent_bytes": len(json.dumps(args, separators=(",", ":"))), "error": bool(err)})
        if err:
            raise RuntimeError("%s failed: %s" % (tool, str(v)[:400]))
        return v


def main():
    build_plant()
    out = {"meta": {"Q_m3s": 1.0e6 * 0.003785411784 / 86400.0, "note": "docs/CH17_BRIEF.md"}, "records": RECORDS, "parts": PARTS, "connections": CONNS,
           "envelopes": ENVS, "source": "INTAKE", "sinks": ["STUBA", "STUBB"],
           "prices": {"concrete_rc": {"density_kg_m3": 2400.0, "price_per_kg": 0.0625}, "steel": {"density_kg_m3": 7850.0, "price_per_kg": 3.0}},
           "mcp": {"overlap_pairs": 0, "pairs": 0, "env_hits": [], "bom": {"mass_kg": 0.0, "cost": 0.0, "lines": 0}}}
    dest = os.path.join(ROOT, "docs", "ch17")
    os.makedirs(dest, exist_ok=True)
    if "--no-mcp" in sys.argv:
        json.dump(out, open(os.path.join(dest, "plant.json"), "w"))
        return
    os.environ["APPDATA"] = "C:/Temp/claude/eng2/appdata"
    os.environ["LOCALAPPDATA"] = "C:/Temp/claude/eng2/localappdata"
    import mcp_bench as B
    t_start = time.time()
    c = B.Client(GODOT, cad=True)
    boot_s = time.time() - t_start
    L = Log(c)
    L.call("cad_reset", {})
    # 1. every distinct record in one batch
    L.call("batch", {"calls": [{"tool": "cad_part", "args": {"name": k, "record": r}} for k, r in RECORDS.items()]}, "batch cad_part x%d" % len(RECORDS))
    # 2. the assembly in one call
    ops = [{"op": "new"}] + [{"op": "add", "part": p["rec"], "id": p["id"], "name": p["name"], "pos": p["pos"], "rot": [0, 0, 0]} for p in PARTS]
    L.call("cad_asm", {"ops": ops}, "cad_asm add x%d" % len(PARTS))
    # 3. overlaps of the plant itself
    fit = L.call("check_fit", {"prec": 6}, "check_fit (plant)")
    out["mcp"]["pairs"] = int(fit["pairs"])
    out["mcp"]["overlap_pairs"] = len(fit["overlaps"])
    out["mcp"]["fit_reply"] = fit
    # The `bom` tool is NOT called: at plant scale AssemblyBom meshes every record at 0.3 mm (Assembly.built) and the call ends the Godot session (MCP gap 1, docs/CH17_FEEDBACK.md).
    # The same sum, with exact solids, through eval_gd:
    lines = ["var dens := {'concrete_rc': [2400.0, 0.0625], 'steel': [7850.0, 3.0]}", "var m := 0.0", "var c := 0.0", "var seen := {}",
             "for p in H.assembly()['parts']:", "\tvar v := 0.0", "\tfor s in H.solids(p['rec']['name']):", "\t\tv += KCad.volume(s)",
             "\tvar d = dens[p['rec']['bom']['material']]", "\tm += v * d[0]", "\tc += v * d[0] * d[1]", "\tseen[p['rec']['name']] = true",
             "return {'mass_kg': m, 'cost': c, 'lines': seen.size()}"]
    code = "\n".join(lines)
    bom = L.call("eval_gd", {"code": code, "prec": 9}, "eval_gd bom (exact volumes)")
    print("EVAL REPLY", json.dumps(bom)[:600])
    bom = bom.get("value", bom.get("result", bom)) if isinstance(bom, dict) else bom
    out["mcp"]["bom"] = {"mass_kg": bom["mass_kg"], "cost": bom["cost"], "lines": bom["lines"], "via": "eval_gd"}
    # 4. the envelopes as parts, one more check_fit, then take them out again
    L.call("batch", {"calls": [{"tool": "cad_part", "args": {"name": e["name"], "record": env_record(e)}} for e in ENVS]}, "batch cad_part envelopes x%d" % len(ENVS))
    L.call("cad_asm", {"ops": [{"op": "add", "part": e["name"], "id": e["name"], "name": e["name"], "pos": e["min"], "rot": [0, 0, 0]} for e in ENVS]}, "cad_asm add envelopes")
    fit2 = L.call("check_fit", {"prec": 6}, "check_fit (envelopes)")
    hits = []
    for a_, b_, ov in fit2["overlaps"]:
        if a_.startswith("ENV_") != b_.startswith("ENV_"):
            hits.append([a_, b_] if a_.startswith("ENV_") else [b_, a_])
    out["mcp"]["env_hits"] = hits
    L.call("cad_asm", {"ops": [{"op": "remove", "id": e["name"]} for e in ENVS]}, "cad_asm remove envelopes")
    c.close()
    wall = time.time() - t_start
    log = {"godot_boot_s": round(boot_s, 1), "total_s": round(wall, 1), "calls": len(L.rows), "reply_bytes": sum(r["reply_bytes"] for r in L.rows),
           "sent_bytes": sum(r["sent_bytes"] for r in L.rows), "call_ms": round(sum(r["ms"] for r in L.rows), 1), "rows": L.rows}
    json.dump(log, open(os.path.join(dest, "mcp_log.json"), "w"), indent=1)
    json.dump(out, open(os.path.join(dest, "plant.json"), "w"))
    print(json.dumps({k: v for k, v in log.items() if k != "rows"}))
    print(json.dumps(out["mcp"], default=str)[:3000])


if __name__ == "__main__":
    main()
