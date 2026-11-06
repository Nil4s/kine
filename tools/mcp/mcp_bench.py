"""MCPFAST measurement driver: talks MCP (JSON-RPC over stdio, raw) to tools/mcp/poser_mcp.py, times every call and counts reply bytes.

  python tools/mcp/mcp_bench.py <godot> [--cad] [--out file.json] [--n 15]      (needs the files tools/mcpfast_dump.gd writes)

Importable: Client(godot, cad, math) -> .call(tool, args) -> (parsed result, isError, ms, reply_bytes, text_bytes)
"""
import json, os, subprocess, sys, time

PROJ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DUMP = "C:/Temp/claude/mcpfast"


class Client:
    def __init__(self, godot, cad=True, math=False):
        args = [sys.executable, os.path.join(PROJ, "tools", "mcp", "poser_mcp.py"), "--godot", godot]
        if cad:
            args.append("--cad")
        if math:
            args.append("--math")
        self.t_spawn = time.time()
        self.p = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, encoding="utf-8", bufsize=1)
        self.n = 0
        t0 = time.time()
        self.rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "bench", "version": "1"}})
        self.init_ms = (time.time() - t0) * 1000
        self.send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        self.tools = [t["name"] for t in self.rpc("tools/list", {})[0]["result"]["tools"]]

    def send(self, o):
        self.p.stdin.write(json.dumps(o) + "\n")
        self.p.stdin.flush()

    def rpc(self, method, params):
        self.n += 1
        t0 = time.time()
        self.send({"jsonrpc": "2.0", "id": self.n, "method": method, "params": params})
        line = self.p.stdout.readline()
        return json.loads(line), (time.time() - t0) * 1000, len(line.encode("utf-8"))

    def call(self, tool, args=None):
        r, ms, nb = self.rpc("tools/call", {"name": tool, "arguments": args or {}})
        if "error" in r:
            return r["error"], True, ms, nb, nb
        res = r["result"]
        text = res["content"][0]["text"]
        try:
            val = json.loads(text)
        except Exception:
            val = text
        return val, bool(res.get("isError")), ms, nb, len(text.encode("utf-8"))

    def close(self):
        try:
            self.p.stdin.close()
            self.p.wait(timeout=30)
        except Exception:
            self.p.kill()


def pct(xs, q):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(round(q * (len(xs) - 1))))]


def load():
    return json.load(open(DUMP + "/recs.json")), json.load(open(DUMP + "/asm.json"))


def tweak(rec, k):
    """the same record with one number nudged by k um: a different hash, the same build cost"""
    r = json.loads(json.dumps(rec))
    for f in r["features"]:
        for key, v in f.items():
            if key in ("r", "d", "dist", "w", "h") and isinstance(v, (int, float)) and not isinstance(v, bool):
                f[key] = v + 0.001 * k
                return r
    r["name"] = r.get("name", "p") + str(k)
    return r


def timed(c, tool, args, n):
    out = []
    for _ in range(n):
        v, err, ms, nb, tb = c.call(tool, args() if callable(args) else args)
        out.append((ms, nb, tb, err))
    ms = [o[0] for o in out]
    return {"p50": round(pct(ms, 0.5), 1), "p95": round(pct(ms, 0.95), 1), "bytes": out[-1][1], "text_bytes": out[-1][2], "errors": sum(1 for o in out if o[3]), "n": n}


def main():
    godot = sys.argv[1]
    cad = "--cad" in sys.argv
    n = int(sys.argv[sys.argv.index("--n") + 1]) if "--n" in sys.argv else 15
    outp = sys.argv[sys.argv.index("--out") + 1] if "--out" in sys.argv else None
    recs, asm = load()
    res = {"mode": "cad" if cad else "baseline", "tools": {}}
    t0 = time.time()
    c = Client(godot, cad=cad, math=not cad)
    res["init_ms"] = round(c.init_ms, 1)
    v, err, ms, nb, tb = c.call("open", {"path": "scenes/combo3.json"})   # the first call: the session boot is in it (cad prewarms during initialize)
    res["cold_first_call_ms"] = round(ms, 1)
    res["cold_wall_ms"] = round((time.time() - t0) * 1000, 1)
    res["startup_ms"] = v.get("startup_ms") if isinstance(v, dict) else None
    T = res["tools"]
    T["open"] = timed(c, "open", {"path": "scenes/combo3.json"}, n)
    T["pose"] = timed(c, "pose", {"text": "raise the right arm 30"}, n)
    T["state"] = timed(c, "state", {"t": 1.25}, n)
    T["measure"] = timed(c, "measure", {"what": ["distance hand_r head", "height head"], "t": 1.0}, n)
    T["describe"] = timed(c, "describe", {}, n)
    T["check"] = timed(c, "check", {}, n)
    T["commands"] = timed(c, "commands", {"find": "mirror pose"}, n)
    rec = recs["piston"]
    k = [0]
    def fresh():
        k[0] += 1
        return {"steps": tweak(rec, k[0])["features"], "name": "Piston"}
    T["part_build (screen, new record)"] = timed(c, "part_build", fresh, max(5, n // 3))
    T["part_facts (screen)"] = timed(c, "part_facts", {}, n)
    if cad:
        k[0] = 0
        def fresh2():
            k[0] += 1
            return {"name": "Piston", "record": tweak(rec, k[0])}
        T["cad_part build (cold record)"] = timed(c, "cad_part", fresh2, max(5, n // 3))
        c.call("cad_part", {"name": "Piston", "record": rec})
        T["cad_part replay (cache hit)"] = timed(c, "cad_part", {"name": "Piston", "record": rec}, n)
        T["cad_part by name only"] = timed(c, "cad_part", {"name": "Piston"}, n)
        v, err, ms, nb, tb = c.call("cad_reset", {})
        t1 = time.time()
        v, err, ms, nb, tb = c.call("cad_asm", {"ops": [{"op": "load", "assembly": asm}]})
        res["cad_asm load (7 parts, cold)"] = {"ms": round(ms, 1), "bytes": nb, "err": err}
        T["cad_asm place (1 op)"] = timed(c, "cad_asm", {"ops": [{"op": "place", "id": "p1", "pos": [0, 0, 0]}]}, n)
        T["cad_asm drive_to"] = timed(c, "cad_asm", {"ops": [{"op": "drive_to", "drive": "Crank", "value": 40}]}, n)
        v, err, ms, nb, tb = c.call("check_fit", {})
        res["check_fit cold"] = {"ms": round(ms, 1), "bytes": nb, "err": err}
        T["check_fit (cached solids)"] = timed(c, "check_fit", {}, n)
        T["check_fit detail"] = timed(c, "check_fit", {"detail": True}, n)
        T["bom"] = timed(c, "bom", {}, n)
        T["eval_gd"] = timed(c, "eval_gd", {"code": "H.assembly()['parts'].size()"}, n)
        T["batch (place + check_fit)"] = timed(c, "batch", {"calls": [{"tool": "cad_asm", "args": {"ops": [{"op": "drive_to", "drive": "Crank", "value": 41}]}}, {"tool": "check_fit", "args": {}}]}, n)
    c.close()
    if outp:
        json.dump(res, open(outp, "w"), indent=1)
    print(json.dumps(res, indent=1))


if __name__ == "__main__":
    main()
