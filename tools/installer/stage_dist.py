#!/usr/bin/env python
"""C78: stage the files an installed Kine needs beside Kine.exe, FROM A DEPENDENCY WALK (objdump -p imports, transitive), not a list.
   python stage_dist.py <native_bin_dir> <dist_dir> [--manifest out.txt]
Copies kine_native.*.dll and kine_cad.*.dll, then every DLL they import (transitively) that is found in native_bin_dir or the mingw/OCCT dirs.
A DLL that is neither found nor a Windows system DLL (present in System32) is an ERROR (exit 2): the build must not ship a missing dependency.
Everything lands FLAT in <dist_dir> (Godot's loader looks beside the exe for a res:// library that is not on disk)."""
import os, re, shutil, subprocess, sys
src_bin, dist = sys.argv[1], sys.argv[2]
manifest = sys.argv[sys.argv.index("--manifest") + 1] if "--manifest" in sys.argv else None
mingw = os.environ.get("KINE_MINGW_BIN", "C:/msys64/ucrt64/bin")
occt = os.environ.get("KINE_OCCT", "D:/kine_native/occt/install") + "/win64/gcc/bin"
objdump = mingw + "/objdump.exe"
sysdir = os.path.join(os.environ.get("SystemRoot", "C:/Windows"), "System32")
roots = [f for f in os.listdir(src_bin) if re.match(r"kine_(native|cad)\.windows\.template_release\.x86_64\.dll$", f)]
if len(roots) != 2:
    print("ERROR: need kine_native and kine_cad release DLLs in", src_bin, "found", roots); sys.exit(2)
os.makedirs(dist, exist_ok=True)
seen, todo, rows, missing = {}, [os.path.join(src_bin, r) for r in roots], [], []
def find(name):
    for d in (src_bin, occt, mingw):
        p = os.path.join(d, name)
        if os.path.exists(p): return p
    return None
for r in todo[:]: seen[os.path.basename(r).lower()] = r
while todo:
    cur = todo.pop()
    out = subprocess.run([objdump, "-p", cur], capture_output=True, text=True).stdout
    for name in re.findall(r"DLL Name: (\S+)", out):
        k = name.lower()
        if k in seen or k.startswith("api-ms-win-") or k.startswith("ext-ms-"): continue
        if os.path.exists(os.path.join(sysdir, name)) and not find(name):
            seen[k] = None; continue    # a Windows system DLL: stays the OS's
        p = find(name)
        if p is None:
            missing.append((os.path.basename(cur), name)); seen[k] = None; continue
        seen[k] = p; todo.append(p)
for k, p in sorted(seen.items()):
    if p is None: continue
    dst = os.path.join(dist, os.path.basename(p))
    shutil.copy2(p, dst)
    rows.append((os.path.basename(p), os.path.getsize(dst)))
if missing:
    for a, b in missing: print("ERROR: %s imports %s: not found and not a Windows DLL" % (a, b))
    sys.exit(2)
tot = sum(s for _, s in rows)
for n, s in rows: print("%-40s %10d" % (n, s))
print("staged %d DLLs, %d bytes" % (len(rows), tot))
if manifest:
    open(manifest, "w").write("\n".join("%s\t%d" % r for r in rows) + "\n")
