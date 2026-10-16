"""Drive tools/mcp/poser_mcp.py with the OFFICIAL python MCP SDK's stdio client (an implementation we did not write),
as Claude Code would (GATES V1). argv: the Godot executable, the project path.
Prints "ok ..." / "FAIL ..." lines and "MCP DRIVE n_ok n_fail"."""
import asyncio, json, os, sys

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

G, PROJ = sys.argv[1], sys.argv[2]
OUT = "scenes/_wip/zz_mcp_test.json"
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


async def main():
    params = StdioServerParameters(command=sys.executable, args=[os.path.join(PROJ, "tools", "mcp", "poser_mcp.py"), "--godot", G])
    async with stdio_client(params) as (rd, wr):
        async with ClientSession(rd, wr) as s:
            init = await s.initialize()
            ok(init.serverInfo.name == "poser" and init.capabilities.tools is not None,
               "1 initialize: server '%s', protocol %s, tools offered" % (init.serverInfo.name, init.protocolVersion))
            tl = (await s.list_tools()).tools
            names = [t.name for t in tl]
            ok(len(tl) == 12 and all(t.description and t.inputSchema.get("type") == "object" for t in tl),
               "2 tools/list: %d tools, each with a description and an input schema: %s" % (len(tl), names))
            r = await s.call_tool("open", {"path": "scenes/combo3.json"})
            ok(not r.isError and len(body(r)["cards"]) == 12, "3 open combo3: 12 cards")
            r = await s.call_tool("pose", {"text": "raise the right arm 30"})
            b = body(r)
            ok(not r.isError and b["ops"][0]["joint"] == "upperarm_r", "4 pose in words: upperarm_r reached %s" % b["ops"][0].get("reached"))
            r = await s.call_tool("state", {"t": 1.25})
            st = body(r)
            ok(not r.isError and abs(st["t"] - 1.25) < 1e-9 and len(st["points"]) == 17 and r.structuredContent is not None,
               "5 state at t=1.25: 17 points (head %s), structured content too" % st["points"]["head"])
            r = await s.call_tool("check", {})
            c = body(r)
            ok(not r.isError and "findings" in c, "6 check: %d findings, %d must fix" % (len(c["findings"]), c["must_fix"]))
            p = os.path.join(PROJ, OUT)
            if os.path.exists(p):
                os.remove(p)
            r = await s.call_tool("save", {"out": OUT})
            ok(not r.isError and os.path.exists(p), "7 save into scenes/_wip: written")
            r = await s.call_tool("save", {"out": "scenes/combo3.json"})
            ok(r.isError and "_wip" in r.content[0].text, "8 save onto Nick's scene: a tool error, serve's reason: '%s'" % r.content[0].text[:70])
            r = await s.call_tool("run", {"steps": ["card=1", "pose=flap the arm"]})
            ok(r.isError and "flap" in r.content[0].text, "9 a bad step: a tool error naming it")
            r = await s.call_tool("state", {"t": 0.5})
            ok(not r.isError, "10 the session lives on after the errors")
    ok(True, "11 the client closed the session cleanly")
    if os.path.exists(os.path.join(PROJ, OUT)):
        os.remove(os.path.join(PROJ, OUT))


try:
    asyncio.run(main())
except Exception as e:
    ok(False, "the client failed: %r" % e)
print("MCP DRIVE %d %d" % (oks, fails))
