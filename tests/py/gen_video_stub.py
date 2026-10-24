"""Stand-in for tools/gen_video.py in tests (no ComfyUI): copies the clip named by GEN_STUB_SRC to the out path, or makes
nothing when it is unset (ComfyUI down). Same arguments: <prompt> <out> [--seconds --seed]."""
import os
import shutil
import sys

src = os.environ.get("GEN_STUB_SRC", "")
slow = float(os.environ.get("GEN_STUB_SLEEP", "0") or 0)   # a test's Cancel-mid-run: the stand-in takes this long first
if slow > 0:
	import time
	time.sleep(slow)
if src and os.path.isfile(src):
    shutil.copyfile(src, sys.argv[2])
    print("VIDEO %s" % sys.argv[2])
else:
    print("ERROR ComfyUI is not answering")
    sys.exit(1)
