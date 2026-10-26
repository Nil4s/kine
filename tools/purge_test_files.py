"""Purge the leftovers of past test runs from Kine's user data folder.

    python tools/purge_test_files.py              # DRY RUN (default): counts per pattern and total MB, deletes nothing
    python tools/purge_test_files.py --delete     # deletes the matched top-level entries
    python tools/purge_test_files.py --dir PATH   # another folder (default: %APPDATA%/Godot/app_userdata/Poser)

Only top-level entries whose whole name matches one of the anchored patterns below are candidates. The patterns are
the ones the test suites write with their own process id (see scripts/test_files.gd, which removes a run's own files
at the end of the run; this tool clears the ones left by runs before that). Nothing else is ever matched: not the real
autosaves (autosave_<n>.json), not the real journal, not Nick's folders, not files with no process id in the name.
Sub-folders are removed whole, and only when their name matches. The list is the same as TestFiles.PATTERNS.
"""
import argparse
import os
import re
import shutil
import sys

# PID stands for any process id (digits). Keep this list in step with scripts/test_files.gd (PATTERNS).
PATTERNS = [
    ("autosave_test", r"autosave_test_\d+(_\d+|_later)?\.json"),
    ("zz_next_tool", r"zz_next_tool_\d+\.json"),
    ("zz_suggestion_journal", r"zz_suggestion_journal_\d+\.json"),
    ("zz_style_print", r"zz_style_print_\d+\.json"),
    ("zz_next_pose", r"zz_next_pose_\d+\.json"),
    ("zz_smart_drag", r"zz_smart_drag_\d+\.json"),
    ("zz_best_take", r"zz_best_take_\d+\.json"),
    ("macros_test", r"macros_test_\d+\.json"),
    ("poser_test_cfg", r"poser_test_\d+\.cfg"),
    ("zz_lib", r"zz_lib_\d+"),
    ("monkey_out", r"monkey_out_\d+"),
    ("walk_out", r"walk\d+_out_\d+"),
    ("i22_out", r"zz_i22_out_\d+"),
    ("i_run", r"i\d+_\d+"),
]


def default_dir():
    return os.path.join(os.environ.get("APPDATA", ""), "Godot", "app_userdata", "Poser")


def size_of(path):
    if os.path.isfile(path):
        return os.path.getsize(path)
    total = 0
    for root, _dirs, files in os.walk(path):
        for f in files:
            try:
                total += os.path.getsize(os.path.join(root, f))
            except OSError:
                pass
    return total


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--delete", action="store_true", help="delete the matches (default: dry run, deletes nothing)")
    ap.add_argument("--dir", default=default_dir(), help="the user data folder")
    a = ap.parse_args()
    if not os.path.isdir(a.dir):
        print("no such folder: %s" % a.dir)
        return 1
    compiled = [(name, re.compile(rx + r"\Z")) for name, rx in PATTERNS]
    counts = {name: [0, 0, 0] for name, _ in compiled}   # entries, files inside, bytes
    matches = []
    unmatched = 0
    for entry in sorted(os.listdir(a.dir)):
        hit = None
        for name, rx in compiled:
            if rx.match(entry):
                hit = name
                break
        if hit is None:
            unmatched += 1
            continue
        full = os.path.join(a.dir, entry)
        size = size_of(full)
        nfiles = 1 if os.path.isfile(full) else sum(len(f) for _, _, f in os.walk(full))
        counts[hit][0] += 1
        counts[hit][1] += nfiles
        counts[hit][2] += size
        matches.append((full, hit))
    total_entries = sum(c[0] for c in counts.values())
    total_bytes = sum(c[2] for c in counts.values())
    mode = "DELETE" if a.delete else "DRY RUN (nothing deleted; add --delete to remove)"
    print("folder: %s" % a.dir)
    print("mode:   %s" % mode)
    print("%-24s %8s %10s %10s" % ("pattern", "entries", "files", "MB"))
    for name, _ in compiled:
        e, f, b = counts[name]
        print("%-24s %8d %10d %10.1f" % (name, e, f, b / 1048576.0))
    print("%-24s %8d %10s %10.1f" % ("TOTAL matched", total_entries, "", total_bytes / 1048576.0))
    print("not matched (left alone): %d top-level entries" % unmatched)
    if a.delete:
        done = 0
        for full, _ in matches:
            try:
                if os.path.isdir(full):
                    shutil.rmtree(full)
                else:
                    os.remove(full)
                done += 1
            except OSError as ex:
                print("could not remove %s: %s" % (full, ex))
        print("removed %d of %d entries" % (done, len(matches)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
