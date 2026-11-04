#!/bin/bash
# c74 bar: blueprint and s257 must exit 0 within 400 s (batch 16's parallel OCCT mesher left them hanging to the 900 s timeout).
rc=0
for s in blueprint s257; do
  out=$(TIMEOUT=400 bash /c/Users/Nick/tools/kine_workers/wtest.sh $s 2>&1 | head -1); echo "$out"
  echo "$out" | grep -q "^PASS .* exit 0 " || rc=1
done
exit $rc
