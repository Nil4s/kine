"""PERF PROBE: Kine through a scripted tour of every page (or one stress case), with the process's CPU and RAM sampled from outside.
    python tools/perfprobe.py [--mode as_is|compat|mobile|lowcpu|custom] [--secs 10] [--pages BODY,POSE] [--out C:/Temp/claude/perf]
                              [--renderer forward_plus|mobile|gl_compatibility] [--affinity 2] [--scale3d 0.67] [--quality low|medium|high]
    python tools/perfprobe.py --stress clips50,clips100,props20,mesh1m,tex4k,city [--mode ...]
Modes (the four emulations of a low-end PC on this machine):
  as_is   the project's own renderer (Forward+), 4x MSAA, scale 1.0
  compat  --rendering-method gl_compatibility
  mobile  --rendering-method mobile
  lowcpu  CPU affinity of the Godot process tree limited to 2 cores (psutil) and render scale 0.67
tests/perfprobe_scene.gd runs inside Godot (windowed at --position 4000,4000, 1280 x 720, vsync off) and writes one JSON line per page;
this script reads them, attributes its 0.5 s psutil samples (CPU % of ONE core, summed over the process tree; RSS) to the page that
was running, and writes <out>/<name>.csv and <name>.md. Only the PIDs it started are ever stopped.
"""
import argparse, csv, json, os, statistics, subprocess, sys, time
import psutil

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.environ.get("GODOT_GUI", "C:/Users/Nick/Tools/Godot/4.7.2/Godot_v4.7.2-stable_win64.exe")
PAGES = ["BODY", "POSE", "ANIMATE", "STAGE", "CHECK", "DELIVER", "MODEL", "SCULPT", "SURFACE"]
MODES = {
    "as_is": {"renderer": None, "affinity": 0, "scale3d": None},
    "compat": {"renderer": "gl_compatibility", "affinity": 0, "scale3d": None},
    "mobile": {"renderer": "mobile", "affinity": 0, "scale3d": None},
    "lowcpu": {"renderer": None, "affinity": 2, "scale3d": 0.67},
}


def tree(p):
    try:
        return [p] + p.children(recursive=True)
    except psutil.Error:
        return []


def run_probe(name, secs, pages, stress, cfg, out, quality=None, timeout=None):
    """one Godot launch; returns (events, samples). samples: (page, cpu_percent_of_one_core, rss_mb)"""
    os.makedirs(out, exist_ok=True)
    jl = os.path.join(out, name + ".jsonl")
    if os.path.exists(jl):
        os.remove(jl)
    cmd = [GODOT, "--path", HERE, "--position", "4000,4000", "--resolution", "1280x720", "--audio-driver", "Dummy"]
    if cfg["renderer"]:
        cmd += ["--rendering-method", cfg["renderer"]]
    cmd += ["-s", "tests/perfprobe_scene.gd", "--", "--out=" + jl, "--secs=%g" % secs]
    if cfg["scale3d"]:
        cmd.append("--scale3d=%g" % cfg["scale3d"])
    if quality:
        cmd.append("--quality=" + quality)
    if pages:
        cmd.append("--pages=" + ",".join(pages))
    if stress:
        cmd.append("--stress=" + stress)
    t0 = time.time()
    proc = subprocess.Popen(cmd, cwd=HERE, stdout=open(os.path.join(out, name + '.log'), 'w'), stderr=subprocess.STDOUT, creationflags=0x08000000)
    ps = psutil.Process(proc.pid)
    ncores = psutil.cpu_count()
    cur = "boot"
    samples = []
    read = 0
    events = []
    deadline = timeout or (secs * 12 + 240 if not stress else secs + 600)
    primed = set()
    while proc.poll() is None and time.time() - t0 < deadline:
        procs = tree(ps)
        if cfg["affinity"]:
            for p in procs:
                try:
                    p.cpu_affinity(list(range(cfg["affinity"])))
                except psutil.Error:
                    pass
        cpu = 0.0
        rss = 0.0
        for p in procs:
            try:
                c = p.cpu_percent(None)
                if p.pid in primed:
                    cpu += c
                primed.add(p.pid)
                rss += p.memory_info().rss
            except psutil.Error:
                pass
        if os.path.exists(jl):
            with open(jl, "r", encoding="utf-8") as f:
                f.seek(read)
                data = f.read()
            nl = data.rfind("\n")
            if nl >= 0:
                read += len(data[: nl + 1].encode("utf-8"))
                for line in data[: nl + 1].splitlines():
                    try:
                        ev = json.loads(line)
                    except ValueError:
                        continue
                    events.append(ev)
                    if ev.get("ev") == "start":
                        cur = ev["page"]
                    elif ev.get("ev") in ("end", "stress"):
                        cur = "between"
        samples.append((cur, cpu, rss / 1048576.0))
        time.sleep(0.5)
    if os.path.exists(jl):   # the lines written between the last poll and the exit
        with open(jl, "r", encoding="utf-8") as f:
            f.seek(read)
            for line in f.read().splitlines():
                try:
                    events.append(json.loads(line))
                except ValueError:
                    pass
    if proc.poll() is None:   # a hang: stop OUR process tree only
        for p in tree(ps)[::-1]:
            try:
                p.kill()
            except psutil.Error:
                pass
        events.append({"ev": "timeout"})
    return events, samples


def summarise(events, samples):
    rows = []
    stressed = {e["page"] for e in events if e.get("ev") == "stress"}   # a stress case logs its "end" line and then the same with build_ms
    for ev in events:
        if ev.get("ev") not in ("end", "stress") or (ev["ev"] == "end" and ev["page"] in stressed):
            continue
        pg = ev["page"]
        ss = [s for s in samples if s[0] == pg][2:]   # the first second of a page is its warm-up
        ev = dict(ev)
        ev["cpu_med"] = round(statistics.median([s[1] for s in ss]), 1) if ss else None
        ev["cpu_max"] = round(max([s[1] for s in ss]), 1) if ss else None
        ev["ram_med_mb"] = round(statistics.median([s[2] for s in ss]), 0) if ss else None
        ev["ram_peak_mb"] = round(max([s[2] for s in ss]), 0) if ss else None
        rows.append(ev)
    return rows


COLS = [("page", "page"), ("fps_med", "FPS med"), ("fps_1low", "FPS 1% low"), ("ft_med_ms", "frame ms"), ("ft_p99_ms", "p99 ms"),
        ("ft_max_ms", "max ms"), ("first_max_ms", "1st-s max ms"), ("cpu_med", "CPU % (1 core=100)"), ("ram_med_mb", "RAM MB"),
        ("ram_peak_mb", "RAM peak"), ("static_mb", "Godot static MB"), ("vram_mb", "VRAM MB"), ("draws", "draws"), ("prims", "prims")]


def write(name, rows, out, title):
    keys = [k for k, _ in COLS] + ["renderer", "adapter", "scale3d", "msaa", "tier", "build_ms", "cur_page"]
    with open(os.path.join(out, name + ".csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=keys, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)
    lines = ["### " + title, "", "| " + " | ".join(h for _, h in COLS) + " |", "|" + "---|" * len(COLS)]
    for r in rows:
        lines.append("| " + " | ".join(str(r.get(k, "")) for k, _ in COLS) + " |")
    if rows:
        lines += ["", "renderer %s, adapter %s, 3D scale %s, MSAA %s; page check (cur_page == page): %s" % (
            rows[0].get("renderer"), rows[0].get("adapter"), rows[0].get("scale3d"), rows[0].get("msaa"),
            "ok" if all(r.get("cur_page") == r["page"] for r in rows) else ", ".join("%s->%s" % (r["page"], r.get("cur_page")) for r in rows if r.get("cur_page") != r["page"]))]
    open(os.path.join(out, name + ".md"), "w", encoding="utf-8").write("\n".join(lines) + "\n")
    return "\n".join(lines)


LIMITS = {"fps": 20.0, "ram_mb": 3072.0, "hang_ms": 2000.0}


def breaks(r):
    why = []
    if r.get("fps_med") is not None and r["fps_med"] < LIMITS["fps"]:
        why.append("FPS %.1f < 20" % r["fps_med"])
    if (r.get("ram_peak_mb") or 0) > LIMITS["ram_mb"]:
        why.append("RAM %d MB > 3 GB" % r["ram_peak_mb"])
    hang = max(r.get("ft_max_ms", 0) or 0, r.get("build_ms", 0) or 0, r.get("first_max_ms", 0) or 0)
    if hang > LIMITS["hang_ms"]:
        why.append("hang %d ms > 2 s" % hang)
    return why


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", default="as_is", choices=list(MODES) + ["custom"])
    ap.add_argument("--secs", type=float, default=10.0)
    ap.add_argument("--pages", default="")
    ap.add_argument("--stress", default="")
    ap.add_argument("--out", default="C:/Temp/claude/perf")
    ap.add_argument("--renderer", default=None)
    ap.add_argument("--affinity", type=int, default=0)
    ap.add_argument("--scale3d", type=float, default=None)
    ap.add_argument("--quality", default=None)
    ap.add_argument("--name", default="")
    a = ap.parse_args()
    cfg = dict(MODES[a.mode]) if a.mode != "custom" else {"renderer": a.renderer, "affinity": a.affinity, "scale3d": a.scale3d}
    pages = [p for p in a.pages.split(",") if p]
    if a.stress:
        res = []
        for case in a.stress.split(","):
            ev, sm = run_probe("stress_%s_%s" % (a.mode, case), a.secs, None, case, cfg, a.out, a.quality)
            rows = summarise(ev, sm)
            if not rows:
                rows = [{"page": case, "fps_med": None, "note": "no result (%s)" % ("timeout" if any(e.get("ev") == "timeout" for e in ev) else "crash")}]
            for r in rows:
                r["why"] = breaks(r) if r.get("fps_med") is not None else ["no result: " + r.get("note", "")]
                res.append(r)
                print(case, r.get("fps_med"), r.get("ram_peak_mb"), r.get("build_ms"), r["why"], flush=True)
        name = a.name or "stress_" + a.mode
        write(name, res, a.out, "Stress: " + a.stress + " (" + a.mode + ")")
        with open(os.path.join(a.out, name + "_limits.md"), "w", encoding="utf-8") as f:
            f.write("| case | FPS med | frame max ms | build ms | RAM peak MB | VRAM MB | static MB | breaks |\n|---|---|---|---|---|---|---|---|\n")
            for r in res:
                f.write("| %s | %s | %s | %s | %s | %s | %s | %s |\n" % (r["page"], r.get("fps_med"), r.get("ft_max_ms"), r.get("build_ms"),
                        r.get("ram_peak_mb"), r.get("vram_mb"), r.get("static_mb"), "; ".join(r["why"]) or "ok"))
        return
    name = a.name or a.mode
    ev, sm = run_probe(name, a.secs, pages, None, cfg, a.out, a.quality)
    rows = summarise(ev, sm)
    print(write(name, rows, a.out, "Kine perf probe: " + name))
    if any(e.get("ev") == "timeout" for e in ev) or not any(e.get("ev") == "done" for e in ev):
        print("WARNING: the probe did not finish (timeout or crash); pages done: %d" % len(rows))
        sys.exit(1)


if __name__ == "__main__":
    main()
