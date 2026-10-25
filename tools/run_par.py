"""ALL SUITES IN PARALLEL (round 37): the same suites, verdicts and logs as tools/run_all.sh, run by N workers at once.
    python tools/run_par.py [-j N] [--changed [ref]] [--shard i/n] [--retry] [--dry] [name | name:mode ...]
(from the poser folder; LOGS / G / TIMEOUT as run_all.sh). The suite list is READ from run_all.sh (one list), each name
once. A suite FAILS on a non-zero exit, any "FAIL" line, or a SCRIPT ERROR (then it is stopped 5 s later).
  -j N            workers (default $JOBS, else half the logical cores, at most 8: the house cap)
  --changed [ref] only the suites the changed files reach (default ref: the merge-base with poser-ui-rounds, plus
                  uncommitted and untracked files; "A..B" = that commit range only). Prints what it picked and why.
  --shard i/n     run only every n-th suite starting at the i-th (1-based), after --changed / names: CI's matrix
  --retry         (or RETRY=1) a failed suite runs once more, alone; a pass then counts, its line says
                  "(flaky: passed on retry)" and the SUITES line ends "FLAKY: a b". The first log is kept as name.log.first
  --dry           print the plan and run nothing
Lines print in list order: the parallel batch first, then the SERIAL suites (run one at a time after it), then retries.
Each Godot runs at BELOW_NORMAL priority with no console window. OFF SCREEN (Windows): Godot pulls a --position that is
off every screen back to 0,0 (measured 10-23: the "off-screen" windows sat at -8,-31, in full view), so window suites
are parented with --wid to ONE host window at -30000,-30000 (tools/offscreen_host.ps1: never activated, no taskbar
button); Godot renders into it as into any window. TOPLEVEL suites resize their own window, which an embedded window
cannot: they get --position only (Godot shows them at 0,0). A test's own child Godot gets the host as $KINE_TEST_WID
(tests/py/determinism.py uses it; r13's child does not: a window-suite parent blocked in OS.execute deadlocks a child
embedded in the same host, so that child still shows for ~9 s). SHOW=1 puts every window on screen, with sound."""
import os, re, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
G = os.environ.get("G", "C:/Users/Nick/Tools/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe")
LOGS = os.environ.get("LOGS", os.path.join(os.environ.get("TMP", "/tmp"), "poser_suites"))
TIMEOUT = int(os.environ.get("TIMEOUT", "400"))
BELOW_NORMAL = 0x00004000
CREATE_NO_WINDOW = 0x08000000   # no console window per process (Nick 10-18: "170 windows opening is crazy")
HIDE = os.environ.get("SHOW", "") == ""
OFFSCREEN = ["--position", "-30000,-30000"]
REAL_AUDIO = {"audio_track", "audiotracks"}   # sync bars need the real driver (Dummy reports position in ~70 ms chunks)
SILENT = ["--audio-driver", "Dummy"]   # no test makes a sound on Nick's speakers (10-18: "we have beep sounds")
# window suites that set their own window size: an embedded (--wid) window keeps its host's size, so those checks fail
# there ("asked 1280 x 720 ... stays 1600 x 900"). Found 10-23 by running every listed test that sets get_window().size
# / window_set_size (21) embedded, then each failure again as a top-level window: these 3 failed only embedded (or, for
# ring_edges, failed differently); pathwalk's 10.5 deg facing gap fails either way, so it is not here.
TOPLEVEL = {"small_window", "r25", "ring_edges", "easycam", "easy_overlap"}   # easycam and easy_overlap set the window size themselves (1600x900, 1280x720)
# shared state on disk (the scenes list, moves/ and trash/, exports, the CLI's files): kept out of the parallel batch.
# r50b: actors_file read every file in scenes/ while others wrote there (parsed a half-written file). 10-23: + every
# test writing a fixed res://(scenes|moves|...)/zz* path, and the suites that list scenes/.
SERIAL_SHARED = {"scene_list", "browser_tree", "browser", "versions", "cli", "serve", "agent", "mcp", "glb_export",
                 "bvh_export", "meshexport", "engine_names", "autosave", "names_disk", "launcher", "empty_paths", "confirm", "examples",
                 "actors_file", "audio_track", "anim_import", "bvh_import", "usd_export", "check_all", "clicks",
                 "game_table", "journal", "markers", "mirror_list", "r20", "recent", "refimg", "set", "grip_book",
                 "posematch", "save_prompt", "drafts"}
# wall-clock bars: under load they measure the neighbours, not the code. Built 10-23 by grepping tests/*.gd for
# (a) an ok()/check() condition on a variable derived from Time.get_ticks_msec/usec, (b) an ok() message with
# "N ms"/"%f ms" beside bar/under/</budget, (c) a condition comparing a *ms/*us/elapsed/took/stall/fps/p95 value,
# then read by eye, dropping those whose "ms" is animation time (eyelife playblast shading i15 i17 i2 i5 i27 i9
# pathrun r27 rise proportions actors_export multicam_app popup_leak).
SERIAL_TIMING = set("""romclash lint actors_hit actors_main alphas anatomy armour audio_track audiotracks bodymesh boolean cloth
cross_contact crowd decimate deformscene dqskin drag_speed dummy_async edgeflow fix_preview gentle grip_save grip_wrap
i1 i4 i7 i8 i12 i16 i22 i44 i45 kmesh kmesh_attrs live_layer llm_client lod meshfile meshsel modstack motion_match pages
perf4 perfdoc photomat play_perf play_speed precise_pick r13 r21 scene_diff scene_thumbs sculpt searchall shrinkwrap
subdiv topomirror uvexport uvunwrap""".split())
SERIAL = SERIAL_SHARED | SERIAL_TIMING
# --changed, when the change is too broad to map (main.gd, run_all.sh ...) or reaches no listed suite
SMOKE = "math:h rules:h fix:h units:h cli:h timeline:w ring:w browser:w undo_tree:w theme:w status_bar:w matcap:w bevel:h".split()
BROAD = {"scripts/main.gd", "main.tscn", "project.godot", "tools/run_all.sh", "tools/run_par.py"}
HOSTWID = ""


def suites():
    src = open(os.path.join(HERE, "tools", "run_all.sh"), encoding="utf-8").read()
    out = []
    for var in ("ALL", "EXTRA"):
        for m in re.finditer(r'^' + var + r'="(?:\$' + var + r' )?([^"]*)"', src, re.M):
            out += m.group(1).split()
    seen, res = set(), []
    for s in out:   # the EXTRA lines repeat ~24 names: each runs once
        n, mode = s.split(":")
        if n not in seen:
            seen.add(n)
            res.append((n, mode))
    return res


def test_file(name):
    f = os.path.join("tests", name + "_test.gd")
    return f if os.path.exists(os.path.join(HERE, f)) else os.path.join("tests", name + ".gd")


def git(*a):
    r = subprocess.run(["git"] + list(a), cwd=HERE, capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None


def changed(ref, listed):
    """the suites the changed files reach, and why (printed)"""
    if not ref:
        for b in ("poser-ui-rounds", "origin/poser-ui-rounds"):
            mb = git("merge-base", "HEAD", b)
            if mb:
                ref = mb.strip()
                break
        else:
            ref = "HEAD"
    files = set((git("diff", "--name-only", ref) or "").split())
    if ".." not in ref:
        files |= set((git("ls-files", "--others", "--exclude-standard") or "").split())
    print("# --changed vs %s: %d files" % (ref, len(files)))
    # an index: every word and every res:// path each test and each script/tool names
    def index(d, strip):
        out = {}
        for fn in os.listdir(os.path.join(HERE, d)):
            if fn.endswith(".gd"):
                src = open(os.path.join(HERE, d, fn), encoding="utf-8", errors="replace").read()
                out[strip(d, fn)] = (set(re.findall(r"\w+", src)) | set(re.findall(r"res://[\w./-]+", src)), src)
        return out
    tests = index("tests", lambda d, fn: fn[:-3].removesuffix("_test"))
    users = {}
    for d in ("scripts", "tools"):
        users.update(index(d, lambda d, fn: d + "/" + fn))
    keys = {}

    def key(f):   # the names a file is reached by: its class_name and its res:// path
        if f not in keys:
            src = users[f][1] if f in users else (open(os.path.join(HERE, f), encoding="utf-8", errors="replace").read() if os.path.isfile(os.path.join(HERE, f))
                                                  else git("show", "%s:%s" % (ref.split("..")[0], f)) or "")   # deleted: its old text
            m = re.search(r"^class_name\s+(\w+)", src, re.M)
            keys[f] = {"res://" + f} | ({m.group(1)} if m else set())
        return keys[f]

    def refs(k):
        return sorted(n for n, (w, _) in tests.items() if w & k)

    def suite_list_only(r):   # every changed line of run_all.sh is an ALL= / EXTRA= suite list: adding a suite is not a broad change
        d = git("diff", r.split("..")[0], "--", "tools/run_all.sh") or ""
        ch = [l[1:] for l in d.splitlines() if l[:1] in "+-" and not l.startswith(("+++", "---"))]
        return bool(ch) and all(re.match(r'\s*(ALL|EXTRA)="', l) for l in ch)

    chosen, broad, code = [], [], False
    for f in sorted(files):
        if f == "tools/run_all.sh" and suite_list_only(ref):
            print("#   %s: only the suite list changed (a new suite runs as itself)" % f)
            continue
        if f in BROAD:
            broad.append(f)
            print("#   %s: too broad to map" % f)
            continue
        if re.search(r"\.(md|txt|uid)$|^(docs|plans|parked)/|^LICENSE$|^\.github/", f):
            continue
        code = True
        if f.startswith("tests/") and f.endswith(".gd"):
            chosen.append(os.path.basename(f)[:-3].removesuffix("_test"))
            print("#   %s: the suite itself" % f)
            continue
        k = key(f)
        cls = " ".join(x for x in k if not x.startswith("res://"))
        direct = refs(k)
        chosen += direct
        via = []
        if f.endswith(".gd"):   # one level further: tests naming a script that names it (main.gd: every app test boots it)
            for u, (w, _) in sorted(users.items()):
                if u in (f, "scripts/main.gd") or not (w & k):
                    continue
                t = refs(key(u))
                if t:
                    via.append("via %s: %s" % (os.path.basename(u), " ".join(t)))
                    chosen += t
        print("#   %s%s: %s%s" % (f, " (%s)" % cls if cls else "", " ".join(direct) or "no test names it", "".join("; " + v for v in via)))
    sel, unl = [], []
    for n in sorted(set(chosen)):
        (sel if n in listed else unl).append(n)
    sel = [(n, listed[n]) for n in sel]
    if unl:
        print("#   also reached, not in ALL/EXTRA (name them as name:h or name:w to run):", " ".join(unl))
    smoke = [tuple(s.split(":")) for s in SMOKE]
    if broad:
        print("#   too broad (%s): adding the smoke set" % " ".join(broad))
        sel += [s for s in smoke if s not in sel]
    elif not sel and code:
        print("#   no listed suite reaches the change: the smoke set")
        sel = smoke
    print("# chosen (%d): %s" % (len(sel), " ".join(n for n, _ in sel)), flush=True)
    return sel


def start_host():
    """the off-screen host window (Windows); its HWND, or "" """
    global HOSTWID
    hf = os.path.join(LOGS, ".host.%d.hwnd" % os.getpid())
    if os.path.exists(hf):
        os.remove(hf)
    try:
        subprocess.Popen(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                          os.path.join(HERE, "tools", "offscreen_host.ps1"), "-HwndFile", hf, "-Owner", str(os.getpid())],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=CREATE_NO_WINDOW)
    except OSError:
        return ""
    for _ in range(80):
        if os.path.exists(hf) and open(hf).read().strip():
            HOSTWID = open(hf).read().strip()
            return hf
        time.sleep(0.25)
    return ""


def run(s, tag=""):
    name, mode = s
    f = test_file(name)
    log = os.path.join(LOGS, name + ".log")
    win = []
    if mode != "h" and HIDE:
        win = (["--wid", HOSTWID] if HOSTWID and name not in TOPLEVEL else []) + OFFSCREEN
        win += SILENT if name not in REAL_AUDIO else []
    args = [G] + (["--headless"] if mode == "h" else win) + ["--path", ".", "-s", f]
    with open(os.path.join(LOGS, "launches.txt"), "a") as lf:
        lf.write(time.strftime("%H:%M:%S ") + " ".join(args) + "\n")
    lim = TIMEOUT
    m = re.search(r"\b%s=(\d+)" % name, SLOW)
    if m and int(m.group(1)) > lim:
        lim = int(m.group(1))
    t0 = time.time()
    why = ""
    with open(log, "w", encoding="utf-8", errors="replace") as fh:
        env = dict(os.environ, KINE_TEST_WID=HOSTWID) if HOSTWID else None   # a test's own child Godot uses it too
        p = subprocess.Popen(args, cwd=HERE, stdout=fh, stderr=subprocess.STDOUT, env=env,
                             creationflags=(BELOW_NORMAL | (CREATE_NO_WINDOW if HIDE else 0)) if os.name == "nt" else 0)
        seen = 0.0
        while p.poll() is None:
            time.sleep(1)
            el = time.time() - t0
            txt = open(log, encoding="utf-8", errors="replace").read()
            if not seen and "SCRIPT ERROR" in txt:
                seen = el
            if seen and el - seen >= 5:
                why = "stopped after a script error"
                p.kill()
                break
            if el >= lim:
                why = "TIMEOUT %ds" % lim
                p.kill()
                break
        p.wait()
    code = 124 if why else p.returncode
    txt = open(log, encoding="utf-8", errors="replace").read().splitlines()
    oks = sum(1 for l in txt if l.startswith("ok"))
    fails = sum(1 for l in txt if (l.startswith("FAIL") and not l.startswith("FAILS")) or re.match(r"^[A-Z_ ]+ FAIL", l))
    errs = sum(1 for l in txt if "SCRIPT ERROR" in l)
    ok = code == 0 and fails == 0 and errs == 0
    if tag:
        why = (why + " " + tag).strip()
    line = "%-4s %-15s ok %-4d fail %-3d script-errors %-3d exit %-3d %4ds %s" % (
        "PASS" if ok else "FAIL", name, oks, fails, errs, code, time.time() - t0, why)
    return ok, line


SLOW = ""


def main():
    global SLOW
    a = sys.argv[1:]
    cores = os.cpu_count() or 2
    j = int(os.environ.get("JOBS", "0")) or max(1, min(8, cores // 2))
    retry = os.environ.get("RETRY", "0") not in ("", "0")
    dry = False
    shard = None
    ref, use_changed = "", False
    names = []
    i = 0
    while i < len(a):
        x = a[i]
        if x == "-j":
            j = min(int(a[i + 1]), 8)   # the house cap: 8 workers
            i += 1
        elif x == "--retry":
            retry = True
        elif x == "--dry":
            dry = True
        elif x == "--shard":
            k, n = a[i + 1].split("/")
            shard = (int(k), int(n))
            i += 1
        elif x == "--changed":
            use_changed = True
            if i + 1 < len(a) and not a[i + 1].startswith("-") and ":" not in a[i + 1] and git("rev-parse", "-q", "--verify", a[i + 1].split("..")[0] + "^{commit}"):
                ref = a[i + 1]
                i += 1
        else:
            names.append(x)
        i += 1
    src = open(os.path.join(HERE, "tools", "run_all.sh"), encoding="utf-8").read()
    m = re.search(r'^SLOW="([^"]*)"', src, re.M)
    SLOW = m.group(1) if m else ""
    allx = suites()
    listed = dict(allx)
    pick = []
    if use_changed:
        pick += changed(ref, listed)
    for x in names:
        n, _, mode = x.partition(":")
        pick.append((n, mode or listed.get(n, "-")))
    if not use_changed and not names:
        pick = allx
    seen, uniq = set(), []
    for s in pick:
        if s[0] not in seen:
            seen.add(s[0])
            uniq.append(s)
    pick = uniq
    if shard:
        pick = pick[shard[0] - 1::shard[1]]
    os.makedirs(LOGS, exist_ok=True)
    missing = [s for s in pick if s[1] == "-" or not os.path.exists(os.path.join(HERE, test_file(s[0])))]
    pick = [s for s in pick if s not in missing]
    par = [s for s in pick if s[0] not in SERIAL]
    ser = [s for s in pick if s[0] in SERIAL]
    if dry:
        print("# parallel (%d at once, %d): %s" % (j, len(par), " ".join("%s:%s" % s for s in par)))
        print("# then serial (%d): %s" % (len(ser), " ".join("%s:%s" % s for s in ser)))
        print("# missing: %s" % " ".join(n for n, _ in missing))
        return 0
    hf = start_host() if os.name == "nt" and HIDE and any(md == "w" for _, md in pick) else ""
    if os.name == "nt" and HIDE and any(md == "w" for _, md in pick) and not hf:
        print("# WARNING: the off-screen host did not start: window suites use --position only (Godot shows them at 0,0)")
    t0 = time.time()
    res = {}
    for n, _ in missing:
        print("MISSING %s" % n, flush=True)
        res[n] = False
    held = []

    def show(s, r):
        res[s[0]] = r[0]
        if not r[0] and retry:
            held.append(s)
        else:
            print(r[1], flush=True)

    try:
        with ThreadPoolExecutor(max_workers=j) as ex:
            futs = [(s, ex.submit(run, s)) for s in par]
            for s, fu in futs:   # in list order
                show(s, fu.result())
        for s in ser:
            show(s, run(s))
        flaky = []
        for s in held:
            lg = os.path.join(LOGS, s[0] + ".log")
            os.replace(lg, lg + ".first")
            r = run(s, "(retry)")
            if r[0]:
                flaky.append(s[0])
                res[s[0]] = True
                print(r[1].replace("(retry)", "(flaky: passed on retry)"), flush=True)
            else:
                print(r[1].replace("(retry)", "(failed again on retry)"), flush=True)
    finally:
        if hf and os.path.exists(hf):
            os.remove(hf)   # the host closes itself
    good = sum(res.values())
    print("SUITES %d/%d PASS   %d workers, %.0f s   (logs: %s)%s" % (good, len(res), j, time.time() - t0, LOGS,
                                                                    "   FLAKY: " + " ".join(flaky) if flaky else ""))
    return len(res) - good


if __name__ == "__main__":
    sys.exit(main())
