#!/usr/bin/env python3
"""Worker cost dashboard (Friday plan 180): token usage per day per model for the last 7 days,
read from the Claude Code session logs, plus the dollar cost the kine_workers logs recorded per day.
Writes ONE self-contained HTML (table + inline SVG bar chart, no external libraries) to C:/Temp/claude/cost.html.

Usage: python tools/cost_dashboard.py [days=7] [out=C:/Temp/claude/cost.html]
Reads only token counts, model names and timestamps from the JSONL; never message text, never keys."""
import datetime as dt
import glob
import html
import json
import os
import sys

PROJ = os.path.expanduser("~/.claude/projects/C--Users-Nick")
WORKER_LOGS = "C:/Users/Nick/Tools/kine_workers/logs"
DAYS = int(sys.argv[1]) if len(sys.argv) > 1 else 7
OUT = sys.argv[2] if len(sys.argv) > 2 else "C:/Temp/claude/cost.html"


def local_day(ts: str) -> dt.date:
    t = dt.datetime.fromisoformat(ts.replace("Z", "+00:00"))
    return t.astimezone().date()


def collect(first_day: dt.date):
    """{(day, model): [input, output, cache_read, cache_write, calls]} deduped on the API request."""
    rows: dict = {}
    seen = set()
    for p in glob.glob(PROJ + "/**/*.jsonl", recursive=True):
        try:
            if dt.date.fromtimestamp(os.path.getmtime(p)) < first_day:
                continue
            fh = open(p, encoding="utf-8", errors="replace")
        except OSError:
            continue
        with fh:
            for line in fh:
                if '"usage"' not in line:
                    continue
                try:
                    d = json.loads(line)
                    m = d["message"]
                    u = m["usage"]
                    day = local_day(d["timestamp"])
                except Exception:
                    continue
                if day < first_day:
                    continue
                key = (d.get("requestId") or m.get("id") or d.get("uuid"), u.get("output_tokens"))
                if key[0] and key in seen:
                    continue
                seen.add(key)
                model = m.get("model") or "unknown"
                if model.startswith("<"):
                    continue
                r = rows.setdefault((day, model), [0, 0, 0, 0, 0])
                r[0] += int(u.get("input_tokens") or 0)
                r[1] += int(u.get("output_tokens") or 0)
                r[2] += int(u.get("cache_read_input_tokens") or 0)
                r[3] += int(u.get("cache_creation_input_tokens") or 0)
                r[4] += 1
    return rows


def worker_cost(first_day: dt.date):
    """{day: [usd, runs]} from the last JSON line of each worker log, dated by the file's mtime."""
    out: dict = {}
    for p in glob.glob(WORKER_LOGS + "/*.json"):
        day = dt.date.fromtimestamp(os.path.getmtime(p))
        if day < first_day:
            continue
        c = None
        try:
            for line in open(p, encoding="utf-8", errors="replace"):
                if line.startswith("{") and "total_cost_usd" in line:
                    try:
                        c = json.loads(line)
                    except Exception:
                        pass
        except OSError:
            continue
        if c:
            r = out.setdefault(day, [0.0, 0])
            r[0] += float(c["total_cost_usd"])
            r[1] += 1
    return out


def fmt(n: int) -> str:
    return f"{n:,}"


def bar_chart(days, totals, w=720, h=240):
    mx = max(max(totals), 1)
    pad_l, pad_b, pad_t = 56, 34, 14
    bw = (w - pad_l - 10) / max(len(days), 1)
    s = [f'<svg viewBox="0 0 {w} {h}" width="100%" role="img" aria-label="Tokens per day (output + input + cache write)">']
    for i in range(5):
        y = pad_t + (h - pad_b - pad_t) * i / 4
        v = mx * (1 - i / 4)
        s.append(f'<line x1="{pad_l}" y1="{y:.1f}" x2="{w-6}" y2="{y:.1f}" stroke="#8884" stroke-width="1"/>')
        s.append(f'<text x="{pad_l-6}" y="{y+4:.1f}" font-size="10" text-anchor="end" fill="currentColor">{v/1e6:.1f}M</text>')
    for i, (d, t) in enumerate(zip(days, totals)):
        bh = (h - pad_b - pad_t) * t / mx
        x = pad_l + i * bw + bw * 0.15
        y = h - pad_b - bh
        s.append(f'<rect x="{x:.1f}" y="{y:.1f}" width="{bw*0.7:.1f}" height="{bh:.1f}" fill="#d97757"><title>{d}: {fmt(t)} tokens</title></rect>')
        s.append(f'<text x="{x+bw*0.35:.1f}" y="{h-pad_b+14}" font-size="10" text-anchor="middle" fill="currentColor">{d.strftime("%m-%d")}</text>')
    s.append("</svg>")
    return "\n".join(s)


def main():
    today = dt.date.today()
    first = today - dt.timedelta(days=DAYS - 1)
    days = [first + dt.timedelta(days=i) for i in range(DAYS)]
    rows = collect(first)
    wc = worker_cost(first)

    per_day = {d: [0, 0, 0, 0, 0] for d in days}
    for (d, _m), r in rows.items():
        for i in range(5):
            per_day[d][i] += r[i]
    # the bar = fresh work: input + output + cache writes (cache reads are the same context re-served)
    totals = [per_day[d][0] + per_day[d][1] + per_day[d][3] for d in days]

    h = ['<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">',
         "<title>Worker cost per day</title><style>",
         ":root{--bg:#fff;--fg:#1f1f1f;--mut:#666;--line:#ddd}@media(prefers-color-scheme:dark){:root{--bg:#161616;--fg:#eee;--mut:#999;--line:#333}}",
         "body{background:var(--bg);color:var(--fg);font:14px system-ui,sans-serif;margin:0;padding:16px;max-width:900px}",
         "h1{font-size:20px}h2{font-size:15px;margin-top:28px}table{border-collapse:collapse;width:100%}",
         "th,td{padding:5px 8px;border-bottom:1px solid var(--line);text-align:right}th:first-child,td:first-child,th:nth-child(2),td:nth-child(2){text-align:left}",
         ".tot td{font-weight:600}.mut{color:var(--mut)}.wrap{overflow-x:auto}</style></head><body>",
         f"<h1>Worker cost per day, last {DAYS} days</h1>",
         f'<p class="mut">Generated {dt.datetime.now():%Y-%m-%d %H:%M} from Claude Code session logs (token counts only). Days are local time.</p>',
         "<h2>Tokens per day (input + output + cache writes)</h2>", bar_chart(days, totals),
         '<h2>By day and model</h2><div class="wrap"><table><tr><th>Day</th><th>Model</th><th>Input</th><th>Output</th><th>Cache read</th><th>Cache write</th><th>Calls</th></tr>']
    for d in days:
        ms = sorted(((m, r) for (dd, m), r in rows.items() if dd == d), key=lambda x: -x[1][1])
        for m, r in ms:
            h.append(f"<tr><td>{d}</td><td>{html.escape(m)}</td>" + "".join(f"<td>{fmt(x)}</td>" for x in r) + "</tr>")
        t = per_day[d]
        h.append(f'<tr class="tot"><td>{d}</td><td>day total</td>' + "".join(f"<td>{fmt(x)}</td>" for x in t) + "</tr>")
    g = [sum(per_day[d][i] for d in days) for i in range(5)]
    h.append('<tr class="tot"><td>All</td><td>' + f"{DAYS} days</td>" + "".join(f"<td>{fmt(x)}</td>" for x in g) + "</tr></table></div>")
    h.append("<h2>Dollar cost recorded by the kine_workers logs</h2><div class=\"wrap\"><table><tr><th>Day</th><th></th><th>Runs</th><th>USD</th></tr>")
    for d in days:
        if d in wc:
            h.append(f"<tr><td>{d}</td><td></td><td>{wc[d][1]}</td><td>${wc[d][0]:.2f}</td></tr>")
    h.append(f'<tr class="tot"><td>All</td><td></td><td>{sum(v[1] for v in wc.values())}</td><td>${sum(v[0] for v in wc.values()):.2f}</td></tr></table></div>')
    h.append("</body></html>")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(h))
    for d in days[-3:]:
        t = per_day[d]
        print(f"{d}: in {fmt(t[0])} out {fmt(t[1])} cache_r {fmt(t[2])} cache_w {fmt(t[3])} calls {t[4]}  worker ${wc.get(d, [0])[0]:.2f}")
    print("wrote", OUT)


if __name__ == "__main__":
    main()
