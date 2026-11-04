#!/usr/bin/env python3
"""token_cost: where did the tokens (and money / weekly quota) go?

Scans Claude Code logs (~/.claude/projects/**/*.jsonl) for one session plus its
subagents and prints:

  * totals per model: input, cache write, cache read, output, est. $
  * the lead vs every subagent lane, most expensive first
  * per tool: how many calls, how many tokens their RESULTS added to context
    (a tool result is paid again on every later turn as cache read)
  * the context size per turn (the main driver of cache-read cost)
  * "idle" turns: tiny output on a huge context (polling / status checks)

Prices are ESTIMATES (USD per million tokens), override with --prices.
On a subscription the dollars are only a yardstick for the weekly quota.

Usage:
  python tools/token_cost.py                      # newest kine session
  python tools/token_cost.py --session 789aa9b0
  python tools/token_cost.py --since 2026-11-04   # only turns after a date
  python tools/token_cost.py --top 30 --json out.json
"""
from __future__ import annotations

import argparse
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path

PROJECTS = Path.home() / ".claude" / "projects"

# USD per 1M tokens: input, output. cache write 5m = 1.25x in, 1h = 2x in, read = 0.1x in
PRICES = {
    "opus": (5.0, 25.0),
    "sonnet": (3.0, 15.0),
    "haiku": (1.0, 5.0),
}


def family(model: str) -> str:
    m = (model or "").lower()
    for k in PRICES:
        if k in m:
            return k
    return "opus" if m and m != "<synthetic>" else "none"


def cost(fam: str, u: dict) -> float:
    if fam not in PRICES:
        return 0.0
    pin, pout = PRICES[fam]
    cc = u.get("cache_creation") or {}
    w1h = cc.get("ephemeral_1h_input_tokens", 0) or 0
    w5m = cc.get("ephemeral_5m_input_tokens", 0) or 0
    wall = u.get("cache_creation_input_tokens", 0) or 0
    if w1h + w5m == 0:
        w5m = wall
    return (
        (u.get("input_tokens", 0) or 0) * pin
        + w5m * pin * 1.25
        + w1h * pin * 2.0
        + (u.get("cache_read_input_tokens", 0) or 0) * pin * 0.1
        + (u.get("output_tokens", 0) or 0) * pout
    ) / 1e6


def result_len(block) -> int:
    c = block.get("content")
    if isinstance(c, str):
        return len(c)
    if isinstance(c, list):
        n = 0
        for x in c:
            if isinstance(x, dict):
                if x.get("type") == "text":
                    n += len(x.get("text", ""))
                elif x.get("type") == "image":
                    n += 6000  # ~1.5k tokens per image, rough
        return n
    return 0


class Stats:
    def __init__(self, name: str):
        self.name = name
        self.tok = Counter()  # in, cw, cr, out
        self.cost = 0.0
        self.turns = 0
        self.models = Counter()
        self.ctx = []  # context size per turn
        self.idle = 0  # turns with <150 output tokens and >100k context
        self.idle_cost = 0.0
        self.tool_calls = Counter()
        self.tool_result_chars = Counter()
        self.first = None
        self.last = None
        self.task = ""


def scan(path: Path, name: str, since: str | None) -> Stats:
    s = Stats(name)
    seen = set()
    tool_name = {}
    with open(path, "rb") as fh:
        for raw in fh:
            # cheap prefilter: skip lines that can't matter
            if b'"assistant"' not in raw and b'tool_result' not in raw and b'"user"' not in raw:
                continue
            try:
                e = json.loads(raw)
            except Exception:
                continue
            ts = e.get("timestamp") or ""
            if since and ts and ts < since:
                continue
            t = e.get("type")
            m = e.get("message") or {}
            if t == "assistant":
                for b in m.get("content") or []:
                    if isinstance(b, dict) and b.get("type") == "tool_use":
                        tool_name[b.get("id")] = b.get("name", "?")
                        if b.get("id") not in seen:
                            s.tool_calls[b.get("name", "?")] += 1
                            seen.add(b.get("id"))
                mid = m.get("id")
                u = m.get("usage")
                if not u or mid in seen:
                    continue
                seen.add(mid)
                fam = family(m.get("model"))
                if fam == "none":
                    continue
                c = cost(fam, u)
                s.cost += c
                s.turns += 1
                s.models[m.get("model")] += 1
                inn = u.get("input_tokens", 0) or 0
                cw = u.get("cache_creation_input_tokens", 0) or 0
                cr = u.get("cache_read_input_tokens", 0) or 0
                out = u.get("output_tokens", 0) or 0
                s.tok.update({"in": inn, "cw": cw, "cr": cr, "out": out})
                ctx = inn + cw + cr
                s.ctx.append(ctx)
                if out < 150 and ctx > 100_000:
                    s.idle += 1
                    s.idle_cost += c
                s.first = s.first or ts
                s.last = ts or s.last
            elif t == "user":
                cont = m.get("content")
                if isinstance(cont, str) and not s.task:
                    s.task = cont
                if isinstance(cont, list):
                    for b in cont:
                        if not isinstance(b, dict):
                            continue
                        if b.get("type") == "tool_result":
                            s.tool_result_chars[tool_name.get(b.get("tool_use_id"), "?")] += result_len(b)
                        elif b.get("type") == "text" and not s.task:
                            s.task = b.get("text", "")
    return s


def fmt_tok(n: float) -> str:
    for unit, div in (("B", 1e9), ("M", 1e6), ("k", 1e3)):
        if n >= div:
            return f"{n/div:.1f}{unit}"
    return str(int(n))


def find_session(arg: str | None) -> Path | None:
    files = sorted(PROJECTS.rglob("*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True)
    files = [p for p in files if "subagents" not in p.parts]
    if arg:
        p = Path(arg)
        if p.exists():
            return p
        return next((p for p in files if arg in p.stem), None)
    for p in files:
        with open(p, "rb") as fh:
            fh.seek(max(0, p.stat().st_size - 500_000))
            if b"kine" in fh.read().lower() or b"poser" in str(p).lower().encode():
                return p
    return None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--session")
    ap.add_argument("--since", help="ISO date/time, eg 2026-11-04 or 2026-11-04T10:00")
    ap.add_argument("--top", type=int, default=15)
    ap.add_argument("--prices", help='JSON eg {"opus":[5,25],"sonnet":[3,15]}')
    ap.add_argument("--json", help="write raw numbers to this file")
    a = ap.parse_args()
    if a.prices:
        PRICES.update({k: tuple(v) for k, v in json.loads(a.prices).items()})
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    main_p = find_session(a.session)
    if not main_p:
        print("no session found", file=sys.stderr)
        return 1
    subs_dir = main_p.with_suffix("") / "subagents"
    subs = sorted(subs_dir.glob("*.jsonl")) if subs_dir.exists() else []
    print(f"session {main_p.stem}: lead {main_p.stat().st_size/1e6:.0f} MB + {len(subs)} subagent logs"
          + (f", since {a.since}" if a.since else ""))

    lead = scan(main_p, "LEAD", a.since)
    lanes = [scan(p, p.stem, a.since) for p in subs]
    lanes = [l for l in lanes if l.turns]
    everyone = [lead] + lanes

    tot = Counter()
    tot_cost = 0.0
    by_model = defaultdict(lambda: [0, 0.0])
    tools_calls, tools_chars = Counter(), Counter()
    for s in everyone:
        tot.update(s.tok)
        tot_cost += s.cost
        for mdl, n in s.models.items():
            by_model[mdl][0] += n
        tools_calls.update(s.tool_calls)
        tools_chars.update(s.tool_result_chars)
    # cost per model (re-attribute by share of turns per stats; exact enough)
    for s in everyone:
        n = sum(s.models.values()) or 1
        for mdl, k in s.models.items():
            by_model[mdl][1] += s.cost * k / n

    print("\n== Totals ==")
    print(f"turns {sum(s.turns for s in everyone)}   est. ${tot_cost:,.2f}")
    print(f"input {fmt_tok(tot['in'])}  cache-write {fmt_tok(tot['cw'])}  "
          f"cache-read {fmt_tok(tot['cr'])}  output {fmt_tok(tot['out'])}")
    fam_share = Counter()
    for s in everyone:
        n = sum(s.models.values()) or 1
        for mdl, k in s.models.items():
            f = family(mdl)
            pin, pout = PRICES.get(f, (0, 0))
            share = k / n
            fam_share["cache-read"] += s.tok["cr"] * share * pin * 0.1 / 1e6
            fam_share["cache-write"] += s.tok["cw"] * share * pin * 1.6 / 1e6
            fam_share["output"] += s.tok["out"] * share * pout / 1e6
            fam_share["input"] += s.tok["in"] * share * pin / 1e6
    print("where the $ goes (approx): " + ", ".join(
        f"{k} {v/ max(tot_cost,1e-9)*100:.0f}%" for k, v in fam_share.most_common()))

    print("\n== By model ==")
    for mdl, (n, c) in sorted(by_model.items(), key=lambda x: -x[1][1]):
        print(f"  {mdl:28s} turns {n:6d}   ${c:9,.2f}")

    print("\n== Lead vs lanes ==")
    lane_cost = sum(l.cost for l in lanes)
    print(f"  LEAD : {lead.turns} turns, ${lead.cost:,.2f}, avg context {fmt_tok(sum(lead.ctx)/max(1,len(lead.ctx)))}, "
          f"max {fmt_tok(max(lead.ctx or [0]))}")
    print(f"         idle turns (<150 out, >100k ctx): {lead.idle} costing ${lead.idle_cost:,.2f}")
    print(f"  LANES: {len(lanes)} agents, ${lane_cost:,.2f}, avg ${lane_cost/max(1,len(lanes)):,.2f} per lane")

    print(f"\n== {a.top} most expensive lanes ==")
    for l in sorted(lanes, key=lambda x: -x.cost)[: a.top]:
        avg = sum(l.ctx) / max(1, len(l.ctx))
        print(f"  ${l.cost:7,.2f}  {l.turns:4d} turns  ctx avg {fmt_tok(avg):>6s} max {fmt_tok(max(l.ctx)):>6s}  "
              f"{' '.join(l.task.split())[:90]}")

    print("\n== Tools: calls and result size (results are re-read every later turn) ==")
    print(f"  {'tool':22s} {'calls':>7s} {'result tok':>11s} {'tok/call':>9s}")
    for name, chars in tools_chars.most_common(a.top):
        n = tools_calls.get(name, 0) or 1
        print(f"  {name:22s} {tools_calls.get(name,0):7d} {fmt_tok(chars/4):>11s} {fmt_tok(chars/4/n):>9s}")

    if a.json:
        Path(a.json).write_text(json.dumps({
            "total_cost": tot_cost, "tokens": tot, "by_model": by_model,
            "lead": {"cost": lead.cost, "turns": lead.turns, "idle": lead.idle, "idle_cost": lead.idle_cost},
            "lanes": [{"id": l.name, "cost": l.cost, "turns": l.turns, "task": l.task[:200],
                       "tools": l.tool_calls, "first": l.first, "last": l.last} for l in lanes],
            "tools": {k: {"calls": tools_calls[k], "result_chars": v} for k, v in tools_chars.items()},
        }, indent=1, default=dict), encoding="utf-8")
        print(f"\n(json written to {a.json})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
