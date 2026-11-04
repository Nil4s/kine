#!/usr/bin/env python
"""C78: build THIRD_PARTY_NOTICES.txt for the installer from THIRD_PARTY_NOTICES.md + the DLLs actually staged (manifest from stage_dist.py).
   python make_notices.py <repo> <manifest> <out.txt>"""
import sys, os
repo, manifest, out = sys.argv[1:4]
md = open(os.path.join(repo, "THIRD_PARTY_NOTICES.md"), encoding="utf-8").read()
rows = [l.split("\t") for l in open(manifest).read().splitlines() if l]
t = ["KINE: THIRD-PARTY NOTICES (installed build)", "=" * 60, "",
     "The Kine program (Kine.exe) is Teschima Studios' own work; see LICENSE.",
     "Kine uses Open CASCADE Technology 8.0.1 (LGPL 2.1 with the Open CASCADE Exception 1.0).",
     "The Open CASCADE libraries are NOT linked into Kine.exe. They are the separate, unmodified shared libraries",
     "libTK*.dll in the install folder, loaded at run time by kine_cad.windows.template_release.x86_64.dll. You may replace them",
     "with your own build of Open CASCADE of a compatible version (the same names, built with MinGW-w64 UCRT64). Source: tag V8_0_1 of",
     "https://github.com/Open-Cascade-SAS/OCCT . Licence texts are in the licences folder (LGPL-2.1.txt, OCCT_LGPL_EXCEPTION.txt).",
     "The MinGW-w64 runtime (libstdc++-6, libgcc_s_seh-1, libwinpthread-1) is under the GCC Runtime Library Exception / MIT-style licence.",
     "", "Shared libraries installed beside Kine.exe (generated from the build, name and size in bytes):", ""]
t += ["  %-40s %10s" % (n, s) for n, s in rows]
t += ["", "=" * 60, "Full notice list (THIRD_PARTY_NOTICES.md of the source tree):", "", md]
open(out, "w", encoding="utf-8").write("\n".join(t))
print("wrote", out)
