"""Stand-in for tools/gen_video.py in tests (no ComfyUI): copies the clip named by GEN_STUB_SRC to the out path, or makes
nothing when it is unset (ComfyUI down). Same arguments: <prompt> <out> [--seconds --seed]."""
import os
import shutil
import sys

src = os.environ.get("GEN_STUB_SRC", "")
if src and os.path.isfile(src):
    shutil.copyfile(src, sys.argv[2])
    print("VIDEO %s" % sys.argv[2])
else:
    print("ERROR ComfyUI is not answering")
    sys.exit(1)
