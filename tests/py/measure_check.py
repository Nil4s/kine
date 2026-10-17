"""MEASURE, checked (GATES V2). argv: the Godot executable, the project path.
Each `measure` is recomputed HERE, in python, from `state` answers (the points, rounded 0.1 mm), so the two must agree
to that rounding: distance, angle, height, the central-difference speed of a hand and of the weapon tip. The clearance
is held to the landing (a different code path, Dummy.landed): when the swing has landed on the solid dummy, the
closest the weapon comes is ~0 (touching, not through), and standing apart at t = 0 it is well clear. One physical bar:
the bat tip's peak speed in a swing is a human one. And docs/AGENT_MATH.md is current.
Prints "ok ..." / "FAIL ..." and "MEASURE n_ok n_fail"."""
import json, math, os, queue, subprocess, sys, threading

G, PROJ = sys.argv[1], sys.argv[2]
oks = fails = 0


def ok(c, what):
    global oks, fails
    print(("ok   " if c else "FAIL ") + what, flush=True)
    if c:
        oks += 1
    else:
        fails += 1


p = subprocess.Popen([G, "--headless", "--path", PROJ, "-s", "tools/poser_cli.gd", "--", "serve"],
                     stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, encoding="utf-8", bufsize=1)
q = queue.Queue()
threading.Thread(target=lambda: [q.put(l) for l in iter(p.stdout.readline, "")] + [q.put(None)], daemon=True).start()
n = [0]


def read():
    while True:
        line = q.get(timeout=180)
        if line is None:
            raise SystemExit("FAIL the server closed")
        if line.strip().startswith("{"):
            return json.loads(line)


def call(method, params=None):
    n[0] += 1
    p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": n[0], "method": method, "params": params or {}}) + "\n")
    p.stdin.flush()
    r = read()
    if "error" in r:
        print("     (%s error: %s)" % (method, r["error"]["message"][:120]))
    return r


def sub(a, b):
    return [x - y for x, y in zip(a, b)]


def norm(v):
    return math.sqrt(sum(x * x for x in v))


def ang(a, b, c):
    u, v = sub(a, b), sub(c, b)
    return math.degrees(math.acos(max(-1.0, min(1.0, sum(x * y for x, y in zip(u, v)) / (norm(u) * norm(v))))))


def meas(t, what):
    return {m["what"]: m for m in call("measure", {"t": t, "what": what})["result"]["measures"]}


try:
    read()
    call("open", {"path": "scenes/combo3.json"})
    T = 1.25
    st = call("state", {"t": T})["result"]
    P = st["points"]
    m = meas(T, ["distance hand_r head", "angle upperarm_r lowerarm_r hand_r", "angle thigh_l calf_l foot_l", "height head"])
    d = norm(sub(P["hand_r"], P["head"]))
    ok(abs(m["distance hand_r head"]["value"] - d) < 3e-4 and m["distance hand_r head"]["unit"] == "m",
       "distance hand_r head at %.2f s: measure %.4f m, from state's points %.4f" % (T, m["distance hand_r head"]["value"], d))
    a = ang(P["upperarm_r"], P["lowerarm_r"], P["hand_r"])
    ok(abs(m["angle upperarm_r lowerarm_r hand_r"]["value"] - a) < 0.1, "the right elbow's opening: measure %.2f deg, from points %.2f" % (m["angle upperarm_r lowerarm_r hand_r"]["value"], a))
    k = ang(P["thigh_l"], P["calf_l"], P["foot_l"])
    ok(abs(m["angle thigh_l calf_l foot_l"]["value"] - k) < 0.1, "the left knee's opening: measure %.2f deg, from points %.2f" % (m["angle thigh_l calf_l foot_l"]["value"], k))
    ok(abs(m["height head"]["value"] - P["head"][1]) < 2e-4, "height head: %.4f m = the point's y" % m["height head"]["value"])
    # speeds mid-swing (at 1.25 s combo3 holds still: 0 = 0 would check nothing)
    T = 3.0
    m = meas(T, ["speed hand_r", "speed weapon_tip"])
    ok(m["speed weapon_tip"]["value"] > 1.0, "(at %.2f s the bat is moving: %.2f m/s, so the speed checks can fail)" % (T, m["speed weapon_tip"]["value"]))
    h = 1.0 / 30
    s0 = call("state", {"t": T - h})["result"]
    s1 = call("state", {"t": T + h})["result"]
    v = norm(sub(s1["points"]["hand_r"], s0["points"]["hand_r"])) / (2 * h)
    ok(abs(m["speed hand_r"]["value"] - v) < 0.01 and m["speed hand_r"]["unit"] == "m/s",
       "speed hand_r: measure %.3f m/s, from two states 1/30 s either side %.3f" % (m["speed hand_r"]["value"], v))
    vt = norm(sub(s1["weapon"]["tip"], s0["weapon"]["tip"])) / (2 * h)
    ok(abs(m["speed weapon_tip"]["value"] - vt) < 0.02, "speed weapon_tip: measure %.3f m/s, from the states' weapon tips %.3f" % (m["speed weapon_tip"]["value"], vt))

    # the bat tip's peak speed through the scene: a human swing (10-20 m/s at the tip for a bat or staff; 40 m/s is a
    # pro baseball bat-head speed). Above 45 the clip is faster than any human: REPORTED, the number is what it is
    L = call("describe")["result"]["length_s"]
    peak, at = 0.0, 0.0
    f = 0
    while f / 30 <= L:
        sp = meas(f / 30, ["speed weapon_tip"])["speed weapon_tip"]["value"]
        if sp > peak:
            peak, at = sp, f / 30
        f += 1
    print("     the bat tip's peak in combo3: %.1f m/s at %.2f s" % (peak, at))
    ok(5.0 < peak < 45.0, "the bat tip's peak speed is a human one: %.1f m/s (5 < it < 45)" % peak)

    # clearance vs the landing: the dummy (on from the start, 1.5 m out) one step closer, 1.25 m: combo3's swing lands
    call("run", {"steps": ["dummy_closer"]})
    c0 = call("measure", {"t": 0.0, "what": ["clearance"]})["result"]["measures"][0]
    ok(c0["value"] > 0.1 and c0["unit"] == "m", "clearance at t = 0, standing apart: %.3f m (nearest %s)" % (c0["value"], c0["part"]))
    lo, lo_t, plays = 9.0, 0.0, ""
    f = 0
    while f / 30 <= L:
        r = call("measure", {"t": f / 30, "what": ["clearance"]})["result"]
        plays = r["plays"]
        cv = r["measures"][0]["value"]
        if cv < lo:
            lo, lo_t = cv, f / 30
        f += 1
    print("     closest the weapon comes: %.4f m at %.2f s (%s)" % (lo, lo_t, plays))
    ok(plays == "landed on the dummy" and -0.02 < lo < 0.02, "on the solid dummy the swing lands: the closest is %.4f m, touching, not through (|it| < 2 cm)" % lo)
    # com and balance through serve: standing at t = 0 (the dummy has no say in them)
    r0 = call("measure", {"t": 0.0, "what": ["com", "balance"]})["result"]["measures"]
    st0 = call("state", {"t": 0.0})["result"]
    c, bl = r0[0]["value"], r0[1]
    feet_x = (st0["points"]["foot_l"][0] + st0["points"]["foot_r"][0]) / 2
    ok(len(c) == 3 and 0.85 < c[1] < 1.1 and abs(c[0] - feet_x) < 0.15 and bl["unit"] == "m" and bl["value"] > 0 and len(bl["feet_down"]) == 2,
       "com %s m, between the feet (their middle x %.3f); balance %.3f m inside, feet down %s" % (c, feet_x, bl["value"], bl["feet_down"]))
    bad = call("measure", {"t": 1.0, "what": ["distance hand_r nose"]})
    ok("error" in bad and "nose" in bad["error"]["message"], "a part that isn't: refused, named ('%s')" % bad.get("error", {}).get("message", "")[:60])
    call("quit")
finally:
    try:
        p.wait(timeout=30)   # let it exit on its own: main's _exit_tree removes its poser_test_<pid>.cfg
    except subprocess.TimeoutExpired:
        p.kill()
r = subprocess.run([sys.executable, os.path.join(PROJ, "tools", "agent_math_doc.py"), "--check"], capture_output=True, text=True)
ok(r.returncode == 0, "docs/AGENT_MATH.md is current with data/body_limits.json (%s)" % r.stdout.strip())
print("MEASURE %d %d" % (oks, fails))
