#!/usr/bin/env python3
"""new_challenge: write the boilerplate every Kine challenge lane needs (CH16 cost analysis, item 2).

Usage (from the repo root):  python tools/new_challenge.py CH16 "Sony a7 class camera"
Creates docs/CHxx_REFERENCE.md, docs/CHxx_FEEDBACK.md, docs/chxx/, tests/chxx_test.gd
and registers the suite in tools/run_all.sh. Refuses to overwrite anything.
Bars and their planted controls still have to be written by the lane BEFORE the first run.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

TEST = '''extends SceneTree
## {id}: {title}
## Bars (write them here and COMMIT THIS FILE BEFORE THE FIRST RUN; never loosen one):
##   1 <measurement vs a cited value>   PLANTED: <the broken version that must fail>
var fails := 0
var oks := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	oks += 1 if c else 0
	fails += 0 if c else 1


## a planted control: it must be caught (c false means the fault was seen, so the control passes)
func ctl(caught: bool, w: String) -> void:
	ok(caught, "CONTROL " + w)


func _init() -> void:
	# your bars here
	print("{suite}: %d ok, %d fail" % [oks, fails])
	quit(1 if fails > 0 else 0)
'''

REFERENCE = '''# {id} reference: {title}

Every number used by the model or a bar: its value, its source and SEEN (read it), MEMORY (remembered, unverified) or ASSUMED.
Cache external facts HERE on first use; do not fetch the same page twice (CH16 cost analysis, item 5).

| quantity | value | source | SEEN/MEMORY/ASSUMED |
|---|---|---|---|
'''

FEEDBACK = '''# {id} feedback: {title}

Per docs/CHALLENGE_FEEDBACK.md. Fill every section; a lane is not done without them.

## 1. Result
The bar table (ok/fail, every planted control), the key numbers against the cited real object, the last commit.

## 2. Engineering level reached
Per discipline (mechanical, structural, electrical, ...), on the L1-L5 scale, with evidence and what the next level needs.

## 3. What Kine lacked
| needed | exists today | workaround | cost | proposed feature |
|---|---|---|---|---|

## 4. What looks wrong
After LOOKING at the contact sheet, the section and the video frames.

## 5. What was changed after seeing results
Every amended bar and why.

## 6. Cost (Nick's measurement request)
Hardest steps; which Kine features you used; every place you wrote GDScript because the app had no tool.
'''


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    cid, title = sys.argv[1].upper(), sys.argv[2]
    if not re.fullmatch(r"CH[0-9]+[A-Z]?", cid):
        print("the id looks like CH16 or CH16b")
        return 2
    suite = cid.lower()
    root = Path.cwd()
    made = []
    for rel, text in [
        (f"docs/{cid}_REFERENCE.md", REFERENCE),
        (f"docs/{cid}_FEEDBACK.md", FEEDBACK),
        (f"tests/{suite}_test.gd", TEST),
    ]:
        p = root / rel
        if p.exists():
            print(f"refusing to overwrite {rel}")
            return 1
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text.format(id=cid, title=title, suite=suite), encoding="utf-8")
        made.append(rel)
    (root / "docs" / suite).mkdir(parents=True, exist_ok=True)
    run_all = root / "tools" / "run_all.sh"
    if run_all.exists():
        with run_all.open("a", encoding="utf-8", newline="\n") as f:
            f.write(f'EXTRA="$EXTRA {suite}:w"   # {suite}: {title} (tests/{suite}_test.gd)\n')
        made.append("tools/run_all.sh (registered)")
    print("wrote:")
    for m in made:
        print("  " + m)
    print(f"next: write the bars + planted controls in tests/{suite}_test.gd, commit, then run")
    print(f"  WT_MAX=8 bash /c/Users/Nick/tools/kine_workers/wtest.sh {suite} easypart peasy3 freestart")
    return 0


if __name__ == "__main__":
    sys.exit(main())
