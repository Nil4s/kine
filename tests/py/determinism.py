"""THE SAME FRAME TWICE (GATES U3, item 98). argv: the Godot executable, the project path, a scratch dir.
  1 three scripted shots, each rendered twice in two processes: byte-identical PNGs
  2 --frame N --fps F lands exactly on t = N / F: the shot equals --t at that time, byte for byte
  3 `serve` state at 5 moments, in two processes, one asking FORWARD and one in REVERSE order: identical answers
    (a pose that depended on the one before it, an IK warm start, would show here), and frame=N == t=N/F
Prints "ok ..." / "FAIL ..." lines, last "DETERMINISM n_ok n_fail"."""
import hashlib, json, os, queue, subprocess, sys, threading

G, PROJ, TMP = sys.argv[1], sys.argv[2], sys.argv[3]
oks = fails = 0


def ok(c, what):
    global oks, fails
    print(("ok   " if c else "FAIL ") + what, flush=True)
    if c:
        oks += 1
    else:
        fails += 1


def shot(name, args):
    out = os.path.join(TMP, name + ".png")
    if os.path.exists(out):
        os.remove(out)
    # the test runners' off-screen host window (tools/offscreen_host.ps1): the app renders into it, not on Nick's screen
    host = ["--wid", os.environ["KINE_TEST_WID"], "--position", "-30000,-30000"] if os.environ.get("KINE_TEST_WID") else []
    subprocess.run([G, *host, "--path", PROJ, "--", *args, "--shot", out], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=180)
    if not os.path.exists(out):
        return None
    return hashlib.md5(open(out, "rb").read()).hexdigest()


SHOTS = [("combo3_t1", ["--scene", "res://scenes/combo3.json", "--t", "1.0"]),
         ("combo3_dummy_hit", ["--scene", "res://scenes/combo3.json", "--dummy", "1.4", "--frame", "92", "--fps", "30"]),
         ("walk_bat_side", ["--scene", "res://scenes/walk_bat.json", "--frame", "40", "--view", "2"])]
for name, args in SHOTS:
    a = shot(name + "_a", args)
    b = shot(name + "_b", args)
    ok(a is not None and a == b, "1 %s rendered twice: %s / %s" % (name, a and a[:10], b and b[:10]))
    if a is not None and b is not None and a != b:   # keep both pictures: a mismatch seen once under load (round 39) had no cause found
        import shutil
        keep = os.path.join(os.environ.get("TEMP", TMP), "poser_determinism_mismatch")
        os.makedirs(keep, exist_ok=True)
        for k in ("_a", "_b"):
            shutil.copy(os.path.join(TMP, name + k + ".png"), os.path.join(keep, name + k + ".png"))
        print("     both kept in %s" % keep, flush=True)

t92 = repr(92 / 30)
c = shot("combo3_dummy_hit_t", ["--scene", "res://scenes/combo3.json", "--dummy", "1.4", "--t", t92])
ok(c is not None and c == shot("combo3_dummy_hit_a", SHOTS[1][1]), "2 --frame 92 --fps 30 == --t %s, byte for byte" % t92)


def session():
    p = subprocess.Popen([G, "--headless", "--path", PROJ, "-s", "tools/poser_cli.gd", "--", "serve"],
                         stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, encoding="utf-8", bufsize=1)
    q = queue.Queue()
    threading.Thread(target=lambda: [q.put(l) for l in iter(p.stdout.readline, "")] + [q.put(None)], daemon=True).start()
    n = [0]

    def read():
        while True:
            line = q.get(timeout=120)
            if line is None:
                raise SystemExit("FAIL the server closed")
            if line.strip().startswith("{"):
                return json.loads(line)

    def call(method, params=None):
        n[0] += 1
        p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": n[0], "method": method, "params": params or {}}) + "\n")
        p.stdin.flush()
        return read()
    read()   # ready
    return p, call


TIMES = [0.5, 1.25, 2.0, 3.0666, 3.9]
answers = []
for order in (TIMES, list(reversed(TIMES))):
    p, call = session()
    try:
        call("open", {"path": "scenes/combo3.json"})
        got = {}
        for t in order:
            r = call("state", {"t": t})
            got[t] = r.get("result", r)
        got["frame"] = call("state", {"frame": 60, "fps": 30}).get("result")
        got["t2"] = call("state", {"t": 2.0}).get("result")
        call("quit")
    finally:
        try:
            p.wait(timeout=30)   # let it exit on its own: main's _exit_tree removes its poser_test_<pid>.cfg
        except subprocess.TimeoutExpired:
            p.kill()
    answers.append(got)
A, B = answers
same = [t for t in TIMES if json.dumps(A[t], sort_keys=True) == json.dumps(B[t], sort_keys=True)]
ok(len(same) == 5, "3 state at 5 moments, two processes, forward vs reverse order: %d of 5 identical" % len(same))
if len(same) < 5:
    for t in TIMES:
        if t not in same:
            ja, jb = A[t].get("joints", {}), B[t].get("joints", {})
            d = [(k, ja[k], jb[k]) for k in ja if ja[k] != jb.get(k)]
            print("     t=%s differs: %d joints, e.g. %s" % (t, len(d), d[:2]))
ok("points" in A[0.5] and len(A[0.5]["points"]) == 17 and A[0.5]["weapon"] is not None,
   "  state says where 17 parts are (points, m) and the weapon: head %s" % A[0.5].get("points", {}).get("head"))
fa = dict(A["frame"]); fb = dict(A["t2"])
ok(json.dumps(fa, sort_keys=True) == json.dumps(fb, sort_keys=True), "  frame 60 at 30 fps == t 2.0, every field")
ok(A[3.0666]["joints"] != A[2.0]["joints"], "  (and the moments differ from each other: the check can fail)")
print("DETERMINISM %d %d" % (oks, fails))
