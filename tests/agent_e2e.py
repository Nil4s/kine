"""AN AGENT BUILDS A FIGHT (GATES T5, item 100). From an EMPTY scene, through `poser_cli serve` only (no file is
edited), build a 30-card bat combo as an agent would: words for the poses, the registry for the weapon and the cards,
then CHECK -> FIX -> CHECK until nothing is MUST FIX. The saved file must validate. Every request and the gist of
every answer is printed, the run as the agent saw it.
  python tests/agent_e2e.py <godot.exe> <project dir> [--keep]     (--keep leaves scenes/_wip/agent_fight.json)
Last line: "AGENT E2E PASS" or "AGENT E2E FAIL <why>"."""
import json, os, queue, subprocess, sys, threading, time
T0 = time.time()   # the transcript shows the seconds since the start

G, PROJ = sys.argv[1], sys.argv[2]
KEEP = "--keep" in sys.argv
OUT = "scenes/_wip/agent_fight.json" if KEEP else "scenes/_wip/zz_agent_fight.json"

p = subprocess.Popen([G, "--headless", "--path", PROJ, "-s", "tools/poser_cli.gd", "--", "serve"],
                     stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, encoding="utf-8", bufsize=1)
lines = queue.Queue()
threading.Thread(target=lambda: [lines.put(l) for l in iter(p.stdout.readline, "")] + [lines.put(None)], daemon=True).start()
n = 0


def read_msg():
    while True:
        try:
            line = lines.get(timeout=120)
        except queue.Empty:
            raise SystemExit("AGENT E2E FAIL the server did not answer in 120 s")
        if line is None:
            raise SystemExit("AGENT E2E FAIL the server closed its output")
        if line.strip().startswith("{"):
            return json.loads(line)


def call(method, params=None, quiet=False):
    global n
    n += 1
    p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": n, "method": method, "params": params or {}}) + "\n")
    p.stdin.flush()
    r = read_msg()
    if not quiet:
        gist = r["error"]["message"][:110] if "error" in r else json.dumps(r["result"])[:110]
        print("%5.1fs" % (time.time() - T0), end="")
        print("  -> %-9s %-62s %s %s" % (method, json.dumps(params or {})[:62], "ERR" if "error" in r else "ok ", gist), flush=True)
    return r


def must(r, what):
    if "error" in r:
        raise SystemExit("AGENT E2E FAIL %s: %s" % (what, r["error"]["message"]))
    return r["result"]


# the moves, in words (scripts/pose_words.gd): absolute angles ("to N"), so each card is the same whatever came before
GUARD = "raise the right arm to -40, swing the right arm forward to 30, bend the right elbow to 95, raise the left arm to -40, swing the left arm forward to 35, bend the left elbow to 100, turn the body left to 0, turn the chest left to 0, swing the left leg forward to 15, bend the left knee to 20, bend the right knee to 15"
LOAD = "turn the body right to 20, turn the chest right to 10, raise the right arm to -10, swing the right arm forward to 10, bend the right elbow to 110, bend the right knee to 25"
HIPS = "turn the body left to 15, turn the chest right to 6, raise the right arm to -10, swing the right arm forward to 15, bend the right elbow to 105"
HIT = "turn the body left to 30, turn the chest left to 15, raise the right arm to -30, swing the right arm forward to 70, bend the right elbow to 25"
FOLLOW = "turn the body left to 35, turn the chest left to 17, raise the right arm to -45, swing the right arm forward to 90, bend the right elbow to 40"
RECOVER = GUARD
LOW = "raise the right arm to -60, swing the right arm forward to 45, bend the right elbow to 60, bend the left knee to 45, bend the right knee to 45"
COMBO = [("guard", GUARD), ("load", LOAD), ("hips lead", HIPS), ("hit", HIT), ("follow-through", FOLLOW)]

try:
    hello = read_msg()
    print("server ready, methods: %s" % hello["params"]["methods"])
    must(call("new"), "new")
    must(call("run", {"steps": ["reset_body", "weapon_metal_bat", "weapon_in_right_hand"]}), "the weapon")
    # 6 combos of 5 cards = 30, the last of each combo varied so the clip isn't one loop
    plan = []
    for k in range(6):
        for name, words in COMBO:
            plan.append(("%s %d" % (name, k + 1), words))
    plan[-1] = ("recover 6", RECOVER)
    plan[9] = ("low guard 2", LOW)
    for i, (name, words) in enumerate(plan):
        steps = ["pose=" + words, "add", "name=" + name]
        r = call("run", {"steps": steps}, quiet=i not in (0, 1, 29))
        must(r, "card %d '%s'" % (i + 1, name))
    d = must(call("describe"), "describe")
    print("built %d cards, %.2f s" % (len(d["cards"]), d["length_s"]))
    names = [c["name"] for c in d["cards"]]
    if names != [nm for nm, _ in plan]:
        raise SystemExit("AGENT E2E FAIL the cards are not named as planned: %s" % names[:6])
    if len(d["cards"]) != 30:
        raise SystemExit("AGENT E2E FAIL %d cards, not 30" % len(d["cards"]))
    # CHECK -> FIX -> CHECK: an agent fixes what has a fix, slows what doesn't, and stops when nothing is MUST FIX
    for round_ in range(12):
        c = must(call("check"), "check")
        mf = [f for f in c["findings"] if f["sev"] == "MUST FIX"]
        print("round %d: %d findings, %d must fix %s" % (round_ + 1, len(c["findings"]), len(mf), [(f["rule"], f["card"]) for f in mf][:6]))
        if not mf:
            break
        f = mf[0]
        if f["fix"]:
            r = call("run", {"steps": ["fix=%d" % f["n"]]})
            if "error" in r:   # a fix that can't apply: slow that card instead
                must(call("run", {"steps": ["card=%d" % f["card"], "slower_10", "slower_10"]}), "slow card %d" % f["card"])
        else:
            must(call("run", {"steps": ["card=%d" % f["card"], "slower_10", "slower_10"]}), "slow card %d" % f["card"])
    else:
        raise SystemExit("AGENT E2E FAIL still %d must fix after 12 rounds" % len(mf))
    if os.path.exists(os.path.join(PROJ, OUT)):
        os.remove(os.path.join(PROJ, OUT))
    s = must(call("save", {"out": OUT}), "save")
    v = must(call("validate", {"path": OUT}), "validate")
    print("saved %s: %d cards, %.2f s; validates: %s" % (OUT, s["cards"], s["length_s"], v["valid"]))
    must(call("quit"), "quit")
    if not v["valid"]:
        raise SystemExit("AGENT E2E FAIL the saved file does not validate: %s" % v["errors"][:2])
    print("AGENT E2E PASS (%d requests)" % n)
finally:
    try:
        p.wait(timeout=30)   # let it exit on its own: main's _exit_tree removes its poser_test_<pid>.cfg
    except subprocess.TimeoutExpired:
        p.kill()
    if not KEEP and os.path.exists(os.path.join(PROJ, OUT)):
        os.remove(os.path.join(PROJ, OUT))
