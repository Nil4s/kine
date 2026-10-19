"""Stand-in for tools/see_video.py in tests/multicam_app_test.gd: run as `python -I stub tool video out`, it copies the
video's sidecar pose file (<video>.pose.json, written by the test) to out, as the real tracker would write its pose file."""
import shutil
import sys

shutil.copyfile(sys.argv[1] + ".pose.json", sys.argv[2])
print("POSE stub %s" % sys.argv[2])
