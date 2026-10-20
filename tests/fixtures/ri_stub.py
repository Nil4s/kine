"""Stand-in for tools/see_image.py in tests/refimg_test.gd: run as `python -I stub image out` (the stub IS the tool), it copies the picture's
sidecar landmark file (<image>.lm.json, written by the test) to out, as the real detector would write its own."""
import shutil
import sys

shutil.copyfile(sys.argv[1] + ".lm.json", sys.argv[2])
print("POSE stub %s" % sys.argv[2])
