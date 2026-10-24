"""Stand-in for tools/gen_video.py in tests (no ComfyUI): copies the clip named by GEN_STUB_SRC to the out path, or makes
nothing when it is unset (ComfyUI down). Same arguments: <prompt> <out> [--seconds --seed].
GEN_STUB_SLEEP: seconds to sleep first (a test's Cancel). GEN_STUB_SLOW_CALL=n: sleep only on the n-th call (1-based).
GEN_STUB_LOG: a file each call appends its out path to (the call number is the line count), so a test can count the takes
and find their files. GEN_STUB_ARGS: a file each call appends its arguments to, as a JSON list (the flags a test checks)."""
import json
import os
import shutil
import sys
import time

log = os.environ.get("GEN_STUB_LOG", "")
n = 1
if log:
    n = (open(log).read().count("\n") if os.path.exists(log) else 0) + 1
    with open(log, "a") as f:
        f.write(sys.argv[2] + "\n")

args_log = os.environ.get("GEN_STUB_ARGS", "")
if args_log:
    with open(args_log, "a") as f:
        f.write(json.dumps(sys.argv[1:]) + "\n")

src = os.environ.get("GEN_STUB_SRC", "")
slow = float(os.environ.get("GEN_STUB_SLEEP", "0") or 0)
only = int(os.environ.get("GEN_STUB_SLOW_CALL", "0") or 0)
if only and n != only:
    slow = 0
if slow > 0:
    time.sleep(slow)
if src and os.path.isfile(src):
    shutil.copyfile(src, sys.argv[2])
    print("VIDEO %s" % sys.argv[2])
else:
    print("ERROR ComfyUI is not answering")
    sys.exit(1)
