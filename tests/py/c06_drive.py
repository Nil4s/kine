"""C06: drive tools/mcp/poser_mcp.py with the OFFICIAL python MCP SDK client. Bars (written before the numbers were read):
 1 default tools/list is the old 12 (no maths tool leaks in), 2 with --math the six maths tools are listed,
 3 part_facts over MCP: the desk top within 1 mm of 750, a gap of 10 mm between two cubes, 4 frame_facts: brightest piece is the white emitter,
 5 part_warn, part_assert, nature answer (no 'no method'), 6 look_facts answers with a tool error that is not 'no method' (nothing is drawn headless).
argv: Godot exe, project path. Prints ok/FAIL lines and 'C06 DRIVE n_ok n_fail'."""
import asyncio, json, os, sys

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

G, PROJ = sys.argv[1], sys.argv[2]
NEW = ["frame_facts", "look_facts", "nature", "part_warn", "part_facts", "part_assert"]
oks = fails = 0


def ok(c, what):
    global oks, fails
    print(("ok   " if c else "FAIL ") + what, flush=True)
    if c:
        oks += 1
    else:
        fails += 1


def body(r):
    return json.loads(r.content[0].text) if not r.isError else r.content[0].text


n = [0]


def rect(x0, y0, x1, y1, dist, nm):
    n[0] += 1
    sk = "s%d" % n[0]
    n[0] += 1
    return [{"t": "sketch", "id": sk, "name": nm + " sketch", "plane": "front", "ents": [{"k": "rect", "a": [x0, y0], "b": [x1, y1]}], "dims": []},
            {"t": "extrude", "id": "e%d" % n[0], "name": nm, "sketch": sk, "dist": dist, "both": False, "op": "new"}]


def part(name, feats):
    return {"version": 1, "name": name, "seq": 99, "features": feats}


DESK = part("desk", rect(-580, 0, -520, 720, 600, "L") + rect(520, 0, 580, 720, 600, "R") + rect(-580, 720, 580, 750, 600, "Top"))
CUBES = part("cubes", rect(0, 0, 20, 20, 20, "A") + rect(30, 0, 50, 20, 20, "B"))
LAMPS = part("lamps", rect(-700, 300, -300, 700, 200, "A") + rect(-100, 500, 100, 700, 200, "C") + [
    {"t": "bname", "id": "n1", "name": "n1", "body": 0, "called": "Wall"}, {"t": "bname", "id": "n2", "name": "n2", "body": 1, "called": "Lamp"},
    {"t": "appear", "id": "a1", "name": "Glow", "body": 1, "preset": "Custom", "color": [1, 1, 1], "rough": 0.5, "metal": 0.0, "alpha": 1.0, "emission": [1, 1, 1], "emission_energy": 8.0}])
CAM = {"pos": [0, 0.5, 3], "target": [0, 0.5, 0], "fov": 45}


async def session(args, fn):
    params = StdioServerParameters(command=sys.executable, args=[os.path.join(PROJ, "tools", "mcp", "poser_mcp.py"), "--godot", G] + args)
    async with stdio_client(params) as (rd, wr):
        async with ClientSession(rd, wr) as s:
            await s.initialize()
            await fn(s)


async def plain(s):
    names = [t.name for t in (await s.list_tools()).tools]
    ok(len(names) == 12 and not any(k in names for k in NEW), "1 default tools/list: %d tools, none of the maths tools" % len(names))


async def math(s):
    tl = (await s.list_tools()).tools
    names = [t.name for t in tl]
    ok(len(tl) == 18 and all(k in names for k in NEW) and all(t.description for t in tl), "2 --math tools/list: %d tools, the six maths tools there" % len(tl))
    r = await s.call_tool("part_facts", {"part": DESK})
    b = body(r)
    top = b["box_mm"]["max"][1] if not r.isError and "box_mm" in b else -1
    ok(not r.isError and abs(top - 750.0) <= 1.0, "3a part_facts desk top %s mm (bar 750 +- 1)" % top)
    r = await s.call_tool("part_facts", {"part": CUBES, "gap": [1, 2]})
    b = body(r)
    g = b["gap"]["gap_mm"] if not r.isError and "gap" in b else None
    ok(g is not None and abs(g - 10.0) <= 0.01, "3b gap between two cubes %s mm (bar 10.000)" % g)
    r = await s.call_tool("frame_facts", {"part": LAMPS, "camera": CAM, "w": 1280, "h": 720})
    b = body(r)
    br = b["light"]["brightest_piece"] if not r.isError and "light" in b else r.content[0].text[:80]
    ok(br == "Lamp", "4 frame_facts brightest piece: %s (want Lamp)" % br)
    r = await s.call_tool("part_warn", {"part": DESK})
    ok(not r.isError, "5a part_warn answers: %s" % r.content[0].text[:60])
    r = await s.call_tool("part_assert", {"part": CUBES, "lines": ["A touches B"]})
    ok("no method" not in r.content[0].text, "5b part_assert answers: %s" % r.content[0].text[:60])
    r = await s.call_tool("nature", {"op": "list"})
    ok(not r.isError, "5c nature answers: %s" % r.content[0].text[:60])
    r = await s.call_tool("look_facts", {"piece": "Lamp"})
    ok(r.isError and "no method" not in r.content[0].text, "6 look_facts: a real answer from serve, not a missing method: %s" % r.content[0].text[:80])


async def main():
    await session([], plain)
    await session(["--math"], math)


try:
    asyncio.run(main())
except Exception as e:
    ok(False, "the client failed: %r" % e)
print("C06 DRIVE %d %d" % (oks, fails))
