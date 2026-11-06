## PERF SCOUT (L54, 11-06): the scout itself lives in tests/perfscout_test.gd so wtest.sh can run it:
##   WT_MAX=8 bash /c/Users/Nick/tools/kine_workers/wtest.sh perfscout        (SCOUT_ONLY=scene|prof|part|mesh|body|misc for one section)
## Rows go to the log ("ROW|op|n|ms|reps|native") and C:/Temp/claude/perfscout/rows.jsonl. Results: docs/PERF_SCOUT_1106.md.
extends "res://tests/perfscout_test.gd"
