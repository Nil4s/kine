#!/usr/bin/env python
"""L16: the notices must cover every shipped DLL.   python check_notices.py <THIRD_PARTY_NOTICES.txt> <manifest.tsv | dir-of-dlls>
Each DLL must appear on a line of the notices together with its licence text. Exit 1 and one MISSING line per failure."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dll_licence import licence
notices, src = sys.argv[1:3]
lines = open(notices, encoding="utf-8").read().splitlines()
if os.path.isdir(src):
    names = sorted(f for f in os.listdir(src) if f.lower().endswith(".dll"))
else:
    names = [l.split("\t")[0] for l in open(src).read().splitlines() if l.strip()]
bad = 0
for n in names:
    lic = licence(n)
    if lic is None:
        print("MISSING: no licence known for %s" % n); bad += 1
    elif not any(n in l and lic in l for l in lines):
        print("MISSING: %s is not listed with its licence in the notices" % n); bad += 1
if not names:
    print("MISSING: no DLLs to check"); bad += 1
print("checked %d DLLs, %d problems" % (len(names), bad))
sys.exit(1 if bad else 0)
