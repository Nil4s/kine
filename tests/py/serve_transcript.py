"""SERVE TRANSCRIPT (round 46, GATES BB0): a fixed request script through `poser_cli serve`; every response line written
as it came. Recorded once BEFORE serve's handler moved into scripts/agent_tools.gd (refs/agent/serve_transcript.jsonl);
tests/agent_tools_test.gd runs it again and compares byte for byte.
    python tests/py/serve_transcript.py <godot exe> <project dir> <out.jsonl>"""
import json
import os
import subprocess
import sys

REQ = [
    {"method": "commands"},
    {"method": "new"},
    {"method": "run", "params": {"steps": ["add", "pose=raise the right arm 90, bend the left elbow 45", "add",
                                           "card=1", "name=start", "card=2", "name=reach"]}},
    {"method": "pose", "params": {"text": "bend the right knee 40"}},
    {"method": "run", "params": {"steps": ["add", "retime=1-3:150", "undo", "redo"]}},
    {"method": "describe"},
    {"method": "state", "params": {"t": 0.4}},
    {"method": "measure", "params": {"t": 0.5, "what": ["distance hand_r head", "angle upperarm_r lowerarm_r hand_r",
                                                         "height head", "speed hand_r", "com", "balance"]}},
    {"method": "check"},
    {"method": "validate"},
    {"method": "open", "params": {"path": "scenes/combo3.json"}},
    {"method": "run", "params": {"steps": ["card=3", "sel=lowerarm_r", "set=lowerarm_r:60,0,0", "update"]}},
    {"method": "diff", "params": {"path": "scenes/combo3.json"}},
    {"method": "check"},
    {"method": "save", "params": {"out": "scenes/combo3.json"}},
    {"method": "run", "params": {"steps": ["card=99"]}},
    {"method": "nope"},
    {"method": "quit"},
]


def main():
    exe, proj, out = sys.argv[1], sys.argv[2], sys.argv[3]
    p = subprocess.Popen([exe, "--headless", "--path", proj, "-s", "tools/poser_cli.gd", "--", "serve"],
                         stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
                         encoding="utf-8", bufsize=1)
    lines = []

    def answer():
        while True:
            l = p.stdout.readline()
            if l == "":
                return None
            if l.startswith("{"):
                return l.rstrip("\n")

    lines.append(answer())   # the ready notification
    for i, q in enumerate(REQ):
        q = dict(q, jsonrpc="2.0", id=i + 1)
        p.stdin.write(json.dumps(q) + "\n")
        p.stdin.flush()
        lines.append(answer())
    p.wait(timeout=60)
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        for l in lines:
            f.write((l if l is not None else "<no answer>") + "\n")
    print("TRANSCRIPT %d lines -> %s" % (len(lines), out))


if __name__ == "__main__":
    main()
