"""Drive `poser_cli serve` as an agent would: a real Godot subprocess, one JSON-RPC request per line, each answered
before the next is sent. argv: the Godot executable, the project path. Prints "ok ..." / "FAIL ..." lines and a last
line "SERVE DRIVE n_ok n_fail". Used by tests/serve_test.gd (GATES T4)."""
import json, os, queue, subprocess, sys, threading

G, PROJ = sys.argv[1], sys.argv[2]
OUT = "scenes/_wip/zz_serve_test.json"
fails = 0
oks = 0


def ok(c, what):
    global fails, oks
    print(("ok   " if c else "FAIL ") + what, flush=True)
    if c:
        oks += 1
    else:
        fails += 1


p = subprocess.Popen([G, "--headless", "--path", PROJ, "-s", "tools/poser_cli.gd", "--", "serve"],
                     stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, encoding="utf-8", bufsize=1)


lines = queue.Queue()
threading.Thread(target=lambda: [lines.put(l) for l in iter(p.stdout.readline, "")] + [lines.put(None)], daemon=True).start()


def read_msg():
    """the next JSON line from the server (Godot's own banner lines are skipped); a server that doesn't answer in
    60 s is a failure, never a hang"""
    while True:
        try:
            line = lines.get(timeout=60)
        except queue.Empty:
            raise SystemExit("no answer in 60 s")
        if line is None:
            raise SystemExit("the server closed its output")
        line = line.strip()
        if line.startswith("{"):
            return json.loads(line)


n = 0


def call(method, params=None, raw=None):
    global n
    n += 1
    req = raw if raw is not None else json.dumps({"jsonrpc": "2.0", "id": n, "method": method, "params": params or {}})
    p.stdin.write(req + "\n")
    p.stdin.flush()
    return read_msg()


try:
    hello = read_msg()
    ok(hello.get("method") == "ready" and "run" in hello["params"]["methods"], "the server says ready, with its methods")
    r = call("describe")
    ok(r["result"]["cards"] == [], "1 describe: the session starts empty")
    r = call("open", {"path": "scenes/combo3.json"})
    ok(len(r["result"]["cards"]) == 12, "2 open combo3: 12 cards")
    r = call("pose", {"text": "raise the right arm 30"})
    ok("result" in r and r["result"]["ops"][0]["joint"] == "upperarm_r", "3 pose: the right arm, reached %s" % r.get("result", {}).get("ops", [{}])[0].get("reached"))
    reached = r["result"]["ops"][0]["reached"]
    r = call("state")
    ok(abs(r["result"]["joints"]["upperarm_r"]["side"] - reached) < 0.01, "4 state: the session kept the pose (side %s)" % r["result"]["joints"]["upperarm_r"]["side"])
    # (+10 would stop at 69: the bat's contact, reported as "stopped short"; -20 is free)
    r = call("run", {"steps": ["card=4", "pose=bend the right elbow -20", "update"]})
    ok("result" in r and [s["ok"] for s in r["result"]["steps"]] == [True, True, True] and r["result"]["steps"][2]["cards_changed"], "5 run: card 4 picked, posed and updated")
    r = call("diff", {"path": "scenes/combo3.json"})
    cards = r["result"]["cards"]
    ok(len(cards) == 1 and cards[0]["b"] == 4 and cards[0]["joints"][0]["joint"] == "lowerarm_r" and cards[0]["joints"][0]["d"][0] == -20.0, "6 diff against the file: exactly card 4's elbow %s" % r["result"]["lines"])
    r = call("check")
    ok("result" in r and "must_fix" in r["result"], "7 check: %d findings, %d must fix" % (len(r["result"]["findings"]), r["result"]["must_fix"]))
    r = call("validate")
    ok(r["result"]["valid"], "8 validate the live scene: valid")
    r = call("fly")
    ok(r["error"]["code"] == -32601 and "methods are" in r["error"]["message"], "9 a method that isn't: -32601, '%s'" % r["error"]["message"][:70])
    r = call("run", {"steps": ["card=1", "pose=flap the arm"]})
    ok(r["error"]["code"] == -32000 and r["error"]["data"]["steps"][0]["ok"] and "flap" in r["error"]["message"], "10 a bad step: -32000 naming it, step 1 still reported")
    r = call(None, raw="{not json")
    ok(r["error"]["code"] == -32700, "11 a line that isn't JSON: -32700")
    r = call("save", {"out": "scenes/combo3.json"})
    ok(r["error"]["code"] == -32602 and "_wip" in r["error"]["message"], "12 save onto Nick's scene: refused")
    if os.path.exists(os.path.join(PROJ, OUT)):
        os.remove(os.path.join(PROJ, OUT))
    r = call("save", {"out": OUT})
    saved = os.path.join(PROJ, OUT)
    ok("result" in r and os.path.exists(saved) and json.load(open(saved, encoding="utf-8"))["cards"][3]["name"] == "follow-through", "13 save into scenes/_wip: written")
    r = call("quit")
    ok(r["result"].get("bye") and p.wait(timeout=30) == 0, "14 quit: the server ends, exit 0")
finally:
    if p.poll() is None:
        p.kill()
    if os.path.exists(os.path.join(PROJ, OUT)):
        os.remove(os.path.join(PROJ, OUT))
print("SERVE DRIVE %d %d" % (oks, fails))
