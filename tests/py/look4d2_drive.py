"""Drives tools/mcp/poser_mcp.py --cad for tests/look4d2_test.gd. argv: godot executable, dir (holds asm.json, cam.json; writes mcp_out.json)."""
import json, os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tools", "mcp"))
import mcp_bench as B

G, D = sys.argv[1], sys.argv[2]
asm = json.load(open(os.path.join(D, "asm.json")))
cam = json.load(open(os.path.join(D, "cam.json")))
plain = B.Client(G, cad=False)
R = {"tools_default": len(plain.tools), "default_has": any(k in plain.tools for k in ("look4d", "sweep"))}
plain.p.kill()
c = B.Client(G, cad=True)
R["tools_cad"] = len(c.tools)
R["cad_new"] = [k for k in c.tools if k in ("look4d", "sweep")]
c.call("cad_asm", {"ops": [{"op": "load", "assembly": asm}]})
R["calls"] = {}
def go(key, tool, args):
    v, err, ms, nb, tb = c.call(tool, args)
    R["calls"][key] = {"args": args, "v": v, "err": bool(err), "bytes": tb, "ms": ms}
base = {"cam": cam, "t": 0.6, "h": 0.06}
go("l0", "look4d", dict(base, level=0))
go("l1", "look4d", dict(base, level=1))
go("l2", "look4d", dict(base, level=2, part="piston"))
go("l3", "look4d", dict(base, level=3, ids=["piston", "rod"], t1=0.9, step=0.1))
go("delta", "look4d", dict(base, since=0.5))
go("image", "look4d", dict(base, level=0, image=True))
R["calls"]["image"]["args"] = {}
go("sweep", "sweep", {"drive": "Crank", "from": 0.0, "to": 350.0, "steps": 36})
R["calls"]["sweep"]["args"] = {}
json.dump(R, open(os.path.join(D, "mcp_out.json"), "w"))
c.p.kill()
