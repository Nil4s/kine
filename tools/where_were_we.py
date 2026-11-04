#!/usr/bin/env python3
"""where_were_we: recover what Claude was doing before a limit/crash cut it off.

Reads the local Claude Code session logs (~/.claude/projects/**/*.jsonl) and the
git/GitHub state of this repo, then prints a short "handoff" report:

  * newest sessions that touched poser/kine (main + subagents)
  * Nick's last messages, Claude's last replies, the last tool calls
  * last todo list, PRs Claude opened, files it edited
  * the repo: current branch, recently active branches, unmerged work, open PRs

Only the tail of each log is read, so 300 MB logs are fine.

Usage:
  python tools/where_were_we.py                 # report on the newest session
  python tools/where_were_we.py --list 20       # list the 20 newest sessions
  python tools/where_were_we.py --session <id or path>
  python tools/where_were_we.py --tail-mb 30 --msgs 15 --out handoff.md
  python tools/where_were_we.py --no-git        # logs only
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path

PROJECTS = Path.home() / ".claude" / "projects"
REPO = Path(__file__).resolve().parent.parent
KEYWORDS = ("poser", "kine")


# ---------------------------------------------------------------- log reading
def tail_lines(path: Path, mb: float) -> list[str]:
    size = path.stat().st_size
    want = int(mb * 1024 * 1024)
    with open(path, "rb") as fh:
        if size > want:
            fh.seek(size - want)
            fh.readline()  # drop the partial first line
        data = fh.read()
    return data.decode("utf-8", errors="replace").splitlines()


def parse(lines: list[str]) -> list[dict]:
    out = []
    for ln in lines:
        try:
            out.append(json.loads(ln))
        except Exception:
            pass
    return out


def head_cwd(path: Path) -> str:
    """cwd of a session, read from its first few lines."""
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            for _ in range(40):
                ln = fh.readline()
                if not ln:
                    break
                if '"cwd"' in ln:
                    try:
                        return json.loads(ln).get("cwd", "")
                    except Exception:
                        pass
    except OSError:
        pass
    return ""


def all_sessions() -> list[Path]:
    if not PROJECTS.exists():
        return []
    files = [p for p in PROJECTS.rglob("*.jsonl")]
    files.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    return files


def relevant(path: Path) -> bool:
    s = str(path).lower()
    if any(k in s for k in KEYWORDS):
        return True
    # main sessions started elsewhere (eg. home dir) that worked on kine
    try:
        tail = "\n".join(tail_lines(path, 0.5)).lower()
    except OSError:
        return False
    return any(k in tail for k in KEYWORDS)


def is_subagent(p: Path) -> bool:
    return "subagents" in p.parts


# ---------------------------------------------------------------- extraction
def short(s: str, n: int) -> str:
    s = " ".join(str(s).split())
    return s if len(s) <= n else s[: n - 3] + "..."


def tool_summary(name: str, inp: dict) -> str:
    if not isinstance(inp, dict):
        return name
    for key in ("command", "file_path", "filePath", "pattern", "description", "url", "prompt"):
        if key in inp:
            return f"{name}: {short(inp[key], 160)}"
    return f"{name}: {short(json.dumps(inp), 160)}"


def user_text(msg) -> str | None:
    c = msg.get("content")
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        texts = [b.get("text", "") for b in c if isinstance(b, dict) and b.get("type") == "text"]
        if texts:
            return "\n".join(texts)
    return None


def extract(entries: list[dict]) -> dict:
    r = {"user": [], "assistant": [], "tools": [], "todos": None, "prs": [],
         "edits": [], "errors": [], "first_ts": None, "last_ts": None,
         "cwd": None, "branch": None}
    for e in entries:
        ts = e.get("timestamp")
        if ts:
            r["first_ts"] = r["first_ts"] or ts
            r["last_ts"] = ts
        if e.get("cwd"):
            r["cwd"] = e["cwd"]
        if e.get("gitBranch"):
            r["branch"] = e["gitBranch"]
        t = e.get("type")
        if t == "pr-link":
            r["prs"].append(f"#{e.get('prNumber')} {e.get('prUrl')}")
            continue
        msg = e.get("message") or {}
        if t == "user" and not e.get("isMeta"):
            txt = user_text(msg)
            if txt and not txt.startswith("<") and "tool_result" not in txt[:40]:
                r["user"].append((ts, txt))
            c = msg.get("content")
            if isinstance(c, list):
                for b in c:
                    if isinstance(b, dict) and b.get("type") == "tool_result" and b.get("is_error"):
                        body = b.get("content")
                        if isinstance(body, list):
                            body = " ".join(x.get("text", "") for x in body if isinstance(x, dict))
                        r["errors"].append((ts, short(body or "", 200)))
        elif t == "assistant":
            c = msg.get("content")
            if not isinstance(c, list):
                continue
            for b in c:
                if not isinstance(b, dict):
                    continue
                if b.get("type") == "text" and b.get("text", "").strip():
                    r["assistant"].append((ts, b["text"]))
                elif b.get("type") == "tool_use":
                    name, inp = b.get("name", "?"), b.get("input") or {}
                    r["tools"].append((ts, tool_summary(name, inp)))
                    if name in ("TodoWrite", "todowrite") and isinstance(inp, dict):
                        r["todos"] = inp.get("todos")
                    if name in ("Edit", "Write", "MultiEdit", "NotebookEdit") and isinstance(inp, dict):
                        fp = inp.get("file_path") or inp.get("filePath")
                        if fp:
                            r["edits"].append(fp)
    return r


# ---------------------------------------------------------------- git
def run(cmd: list[str]) -> str:
    try:
        return subprocess.run(cmd, cwd=REPO, capture_output=True, text=True,
                              encoding="utf-8", errors="replace", timeout=60).stdout.strip()
    except Exception as ex:  # noqa: BLE001
        return f"({cmd[0]} failed: {ex})"


def git_report(base: str) -> list[str]:
    run(["git", "fetch", "--quiet", "origin", base.removeprefix("origin/")])
    if not base.startswith("origin/") and run(["git", "rev-parse", "--verify", "--quiet", f"origin/{base}"]):
        base = f"origin/{base}"  # the local copy is often stale
    o = ["## Repo state", ""]
    o.append(f"- current: `{run(['git', 'rev-parse', '--abbrev-ref', 'HEAD'])}` at "
             f"`{run(['git', 'log', '-1', '--format=%h %s'])}`")
    dirty = [l for l in run(["git", "status", "--porcelain"]).splitlines()
             if not l.endswith(".uid") and not l.startswith("??")]
    o.append(f"- uncommitted tracked changes: {len(dirty)}")
    for l in dirty[:15]:
        o.append(f"    {l}")
    o += ["", f"Recently active branches (and commits not yet in `{base}`):", ""]
    wt = {}  # branch -> worktree path
    cur = None
    for l in run(["git", "worktree", "list", "--porcelain"]).splitlines():
        if l.startswith("worktree "):
            cur = l[9:]
        elif l.startswith("branch refs/heads/") and cur:
            wt[l[18:]] = cur
    refs = run(["git", "for-each-ref", "--sort=-committerdate", "--count=15",
                "--format=%(refname:short)|%(committerdate:relative)|%(subject)", "refs/heads"])
    for line in refs.splitlines():
        name, when, subj = (line.split("|", 2) + ["", ""])[:3]
        ahead = run(["git", "rev-list", "--count", f"{base}..{name}"])
        flag = "MERGED" if ahead == "0" else f"{ahead} unmerged"
        dirty_wt = ""
        if name in wt and Path(wt[name]).exists():
            st = subprocess.run(["git", "status", "--porcelain", "-uno"], cwd=wt[name],
                                capture_output=True, text=True, errors="replace").stdout.split("\n")
            n = len([s for s in st if s.strip()])
            if n:
                dirty_wt = f", **{n} uncommitted files in worktree**"
        o.append(f"- `{name}` ({when}, {flag}{dirty_wt}): {short(subj, 90)}")
    o += ["", "Open PRs:", ""]
    prs = run(["gh", "pr", "list", "--state", "open", "--limit", "15",
               "--json", "number,title,headRefName,baseRefName,updatedAt",
               "--template", "{{range .}}- #{{.number}} {{.headRefName}} -> {{.baseRefName}}: {{.title}}\n{{end}}"])
    o.append(prs or "- none")
    o += ["", "Recently merged PRs:", ""]
    o.append(run(["gh", "pr", "list", "--state", "merged", "--limit", "8",
                  "--json", "number,title,mergedAt",
                  "--template", "{{range .}}- #{{.number}} {{.title}} ({{.mergedAt}})\n{{end}}"]) or "- none")
    return o


# ---------------------------------------------------------------- report
def fmt_ts(ts: str | None) -> str:
    if not ts:
        return "?"
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone().strftime("%m-%d %H:%M")
    except ValueError:
        return ts


def session_report(path: Path, a) -> list[str]:
    r = extract(parse(tail_lines(path, a.tail_mb)))
    size = path.stat().st_size / 1e6
    o = [f"## Session `{path.stem}`", "",
         f"- file: `{path}` ({size:.1f} MB, read last {a.tail_mb} MB)",
         f"- cwd: `{r['cwd']}`  branch: `{r['branch']}`",
         f"- window covered: {fmt_ts(r['first_ts'])} -> {fmt_ts(r['last_ts'])}", ""]
    o.append(f"### Nick's last {a.msgs} messages")
    for ts, t in r["user"][-a.msgs:]:
        o.append(f"- [{fmt_ts(ts)}] {short(t, a.width)}")
    o += ["", f"### Claude's last {a.msgs} replies"]
    for ts, t in r["assistant"][-a.msgs:]:
        o.append(f"- [{fmt_ts(ts)}] {short(t, a.width)}")
    o += ["", f"### Last {a.tools} tool calls"]
    for ts, t in r["tools"][-a.tools:]:
        o.append(f"- [{fmt_ts(ts)}] {t}")
    if r["todos"]:
        o += ["", "### Last todo list"]
        for td in r["todos"]:
            st = td.get("status", "?")
            mark = {"completed": "x", "in_progress": ">", "cancelled": "-"}.get(st, " ")
            o.append(f"- [{mark}] {td.get('content') or td.get('activeForm')}")
    if r["prs"]:
        o += ["", "### PRs opened in this window"]
        o += [f"- {p}" for p in dict.fromkeys(r["prs"])]
    if r["edits"]:
        o += ["", "### Files edited (most recent last)"]
        o += [f"- {p}" for p in list(dict.fromkeys(reversed(r["edits"])))[:25][::-1]]
    if r["errors"]:
        o += ["", "### Last tool errors"]
        o += [f"- [{fmt_ts(ts)}] {t}" for ts, t in r["errors"][-5:]]
    return o


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--session", help="session id (or part of it) or a .jsonl path")
    ap.add_argument("--list", type=int, metavar="N", help="list the N newest relevant sessions and exit")
    ap.add_argument("--tail-mb", type=float, default=15)
    ap.add_argument("--msgs", type=int, default=10)
    ap.add_argument("--tools", type=int, default=25)
    ap.add_argument("--width", type=int, default=400, help="max chars per message")
    ap.add_argument("--subagents", type=int, default=5, help="also summarise N newest subagent logs")
    ap.add_argument("--base", default="poser-ui-rounds")
    ap.add_argument("--no-git", action="store_true")
    ap.add_argument("--out", help="also write the report to this file")
    a = ap.parse_args()

    sessions = all_sessions()
    if a.list:
        n = 0
        for p in sessions:
            if relevant(p):
                kind = "sub " if is_subagent(p) else "MAIN"
                mt = datetime.fromtimestamp(p.stat().st_mtime).strftime("%m-%d %H:%M")
                print(f"{mt}  {kind}  {p.stat().st_size/1e6:7.1f}MB  {p.parent.name}/{p.name}")
                n += 1
                if n >= a.list:
                    break
        return 0

    if a.session:
        sp = Path(a.session)
        main_s = sp if sp.exists() else next((p for p in sessions if a.session in p.stem), None)
        if not main_s:
            print(f"no session matching {a.session}", file=sys.stderr)
            return 1
    else:
        main_s = next((p for p in sessions if not is_subagent(p) and relevant(p)), None)
        if not main_s:
            print("no Claude sessions found under", PROJECTS, file=sys.stderr)
            return 1

    out = [f"# Where were we? ({datetime.now():%Y-%m-%d %H:%M})", ""]
    out += session_report(main_s, a)

    if a.subagents:
        subs_dir = main_s.with_suffix("") / "subagents"
        subs = sorted(subs_dir.glob("*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True) if subs_dir.exists() else []
        if subs:
            out += ["", f"## Newest {min(a.subagents, len(subs))} subagents (of {len(subs)})", ""]
            for p in subs[: a.subagents]:
                r = extract(parse(tail_lines(p, 2)))
                first = r["user"][0][1] if r["user"] else "?"
                last = r["assistant"][-1][1] if r["assistant"] else "(no reply)"
                out.append(f"- **{p.stem}** cwd `{r['cwd']}` last {fmt_ts(r['last_ts'])}")
                out.append(f"    task: {short(first, 250)}")
                out.append(f"    last: {short(last, 250)}")

    if not a.no_git:
        out += [""] + git_report(a.base)

    text = "\n".join(out)
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    print(text)
    if a.out:
        Path(a.out).write_text(text, encoding="utf-8")
        print(f"\n(written to {a.out})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
