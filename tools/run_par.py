"""ALL SUITES IN PARALLEL (round 37): the same suites, verdicts and logs as tools/run_all.sh, run by N workers at once.
    python tools/run_par.py [-j 8] [name ...]        (from the poser folder; LOGS / G / TIMEOUT as run_all.sh)
Each Godot process runs at BELOW_NORMAL priority (the desktop stays usable). A suite FAILS on a non-zero exit, any
"FAIL" line, or a SCRIPT ERROR (then it is stopped 5 s later). The suite list is READ from run_all.sh (one list).
Suites in SERIAL (below) touch a shared file the others read, so they run one at a time after the parallel batch."""
import os, re, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
G = os.environ.get("G", "C:/Users/Nick/Tools/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe")
LOGS = os.environ.get("LOGS", os.path.join(os.environ.get("TMP", "/tmp"), "poser_suites"))
TIMEOUT = int(os.environ.get("TIMEOUT", "400"))
BELOW_NORMAL = 0x00004000
CREATE_NO_WINDOW = 0x08000000   # no console window per process (Nick 10-18: "170 windows opening is crazy")
# window suites still need a real window to render, but it opens OFF the screen; SHOW=1 puts them back where you see them
HIDE = os.environ.get("SHOW", "") == ""
OFFSCREEN = ["--position", "-30000,-30000"]
REAL_AUDIO = {"audio_track"}   # mutes the Master bus itself; its sync bar needs the real driver (Dummy reports position in ~70 ms chunks)
SILENT = ["--audio-driver", "Dummy"]   # no test makes a sound on Nick's speakers (10-18: "we have beep sounds")
# shared state on disk (the scenes list, moves/ and trash/, exports, the CLI's files): kept out of the parallel batch
SERIAL = {"scene_list", "browser_tree", "browser", "versions", "cli", "serve", "agent", "mcp", "glb_export",
          "bvh_export", "engine_names", "autosave", "names_disk", "launcher", "empty_paths", "confirm", "examples",
          "actors_file", "audio_track"}   # audio_track: real-time sync, needs a quiet machine; actors_file reads every file in scenes/ while others write there (r50b: parsed a half-written file)


def suites():
    src = open(os.path.join(HERE, "tools", "run_all.sh"), encoding="utf-8").read()
    out = []
    for var in ("ALL", "EXTRA"):
        m = re.search(var + r'="([^"]*)"', src, re.S)
        out += m.group(1).split()
    return [tuple(s.split(":")) for s in out]


def run(s):
    name, mode = s
    f = os.path.join("tests", name + "_test.gd")
    if not os.path.exists(os.path.join(HERE, f)):
        f = os.path.join("tests", name + ".gd")
    log = os.path.join(LOGS, name + ".log")
    args = [G] + (["--headless"] if mode == "h" else (OFFSCREEN if HIDE else [])) + (SILENT if HIDE and name not in REAL_AUDIO else []) + ["--path", ".", "-s", f]
    t0 = time.time()
    why = ""
    with open(log, "w", encoding="utf-8", errors="replace") as fh:
        p = subprocess.Popen(args, cwd=HERE, stdout=fh, stderr=subprocess.STDOUT,
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
            if el >= TIMEOUT:
                why = "TIMEOUT %ds" % TIMEOUT
                p.kill()
                break
        p.wait()
    code = 124 if why else p.returncode
    txt = open(log, encoding="utf-8", errors="replace").read().splitlines()
    oks = sum(1 for l in txt if l.startswith("ok"))
    fails = sum(1 for l in txt if (l.startswith("FAIL") and not l.startswith("FAILS")) or re.match(r"^[A-Z_ ]+ FAIL", l))
    errs = sum(1 for l in txt if "SCRIPT ERROR" in l)
    ok = code == 0 and fails == 0 and errs == 0
    line = "%-4s %-15s ok %-4d fail %-3d script-errors %-3d exit %-3d %4ds %s" % (
        "PASS" if ok else "FAIL", name, oks, fails, errs, code, time.time() - t0, why)
    print(line, flush=True)
    return ok


def main():
    a = sys.argv[1:]
    j = 8
    if "-j" in a:
        i = a.index("-j")
        j = min(int(a[i + 1]), 8)   # the house cap: 8 workers
        del a[i:i + 2]
    allx = suites()
    pick = [s for s in allx if not a or s[0] in a]
    os.makedirs(LOGS, exist_ok=True)
    t0 = time.time()
    par = [s for s in pick if s[0] not in SERIAL]
    ser = [s for s in pick if s[0] in SERIAL]
    with ThreadPoolExecutor(max_workers=j) as ex:
        res = list(ex.map(run, par))
    res += [run(s) for s in ser]
    print("SUITES %d/%d PASS   %d workers, %.0f s   (logs: %s)" % (sum(res), len(res), j, time.time() - t0, LOGS))
    sys.exit(len(res) - sum(res))


if __name__ == "__main__":
    main()
