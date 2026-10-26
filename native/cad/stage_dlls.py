#!/usr/bin/env python
"""Copy the DLLs kine_cad needs (OCCT + mingw runtime) next to it in native/bin/. Walks `objdump -p` imports transitively.
   python stage_dlls.py   (env: KINE_OCCT, KINE_MINGW_BIN). Prints the shipped set and its size."""
import os, re, shutil, subprocess, sys
here = os.path.dirname(os.path.abspath(__file__))
bin_dir = os.path.normpath(os.path.join(here, "..", "bin"))
occt_bin = os.environ.get("KINE_OCCT", "D:/kine_native/occt/install") + "/win64/gcc/bin"
mingw_bin = os.environ.get("KINE_MINGW_BIN", "C:/msys64/ucrt64/bin")
objdump = mingw_bin + "/objdump.exe"
root = os.path.join(bin_dir, "kine_cad.windows.template_release.x86_64.dll")
seen, todo, total = set(), [root], 0
while todo:
    cur = todo.pop()
    out = subprocess.run([objdump, "-p", cur], capture_output=True, text=True).stdout
    for name in re.findall(r"DLL Name: (\S+)", out):
        if name.lower() in seen:
            continue
        for d in (occt_bin, mingw_bin):
            src = os.path.join(d, name)
            if os.path.exists(src):
                seen.add(name.lower())
                dst = os.path.join(bin_dir, name)
                if not os.path.exists(dst):
                    shutil.copy2(src, dst)
                todo.append(dst)
                total += os.path.getsize(dst)
                print("%-28s %9d" % (name, os.path.getsize(dst)))
                break
print("total shipped next to kine_cad.dll: %d bytes (kine_cad.dll itself %d)" % (total, os.path.getsize(root)))
