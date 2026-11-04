#!/usr/bin/env python3
"""kine_call.py: call Kine's serve methods from ONE shell command (no MCP client needed).

Each METHOD is followed by its params: inline JSON, or @file.json. All calls run in one headless Kine, in order,
so `part_build ... part_facts {}` sees the part just built. Results print as compact JSON, one line per call.

  python tools/kine_call.py part_build @arm.json
  python tools/kine_call.py part_build '{"steps": [...], "save": true}' part_facts '{"cap": 20}'
  python tools/kine_call.py commands '{"find": "mirror pose"}'

For an agent this is the cheap way in: one tool call per build, a short reply, nothing else in its context.
A @file holding {"features": [...]} or a list of steps is sent to part_build as its steps.
"""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "mcp"))
from poser_mcp import Session  # noqa: E402  (the same headless `poser_cli serve` the MCP server uses)


def params(arg: str, method: str):
    if arg.startswith("@"):
        with open(arg[1:], encoding="utf-8") as fh:
            d = json.load(fh)
        if method == "part_build" and isinstance(d, list):
            return {"steps": d}
        if method == "part_build" and isinstance(d, dict) and "features" in d and "steps" not in d and "part" not in d:
            return {"part": d, **{k: v for k, v in d.items() if k in ("save", "name", "facts")}}
        return d
    return json.loads(arg) if arg.strip() else {}


def main() -> int:
    a = sys.argv[1:]
    if not a or a[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    calls = []
    i = 0
    while i < len(a):
        m = a[i]
        i += 1
        p = {}
        if i < len(a) and a[i].startswith(("{", "@")):   # this method's params; else the next word is the next method
            p = params(a[i], m)
            i += 1
        calls.append((m, p))
    sess = Session()
    code = 0
    try:
        for m, p in calls:
            r = sess.call(m, p)
            if "error" in r:
                code = 1
                print(json.dumps({"method": m, "error": r["error"].get("message"), "data": r["error"].get("data")}, separators=(",", ":")))
            else:
                print(json.dumps({"method": m, "result": r.get("result")}, separators=(",", ":")))
    finally:
        sess.stop()
    return code


if __name__ == "__main__":
    sys.exit(main())
