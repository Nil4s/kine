# KineCAD: exact solids for BUILD mode (Open CASCADE)

`native/cad/` builds `kine_cad.dll` (GDExtension class `KineCAD`) on top of Open CASCADE Technology 8.0.1 (OCCT).
GDScript never names the class: `scripts/kcad.gd` (the door) loads `scripts/kcad_native.gd` only when `ClassDB.class_exists("KineCAD")`.
No DLL (or no OCCT DLLs next to it) = `KCad.available()` is false, builders return 0, `KCad.last_error()` says what is missing; Kine starts and its tests pass (tests/cad_test.gd SKIPs).
It is a separate DLL from `kine_native` on purpose: the sculpt pilot must never depend on the OCCT DLLs.

API (ids are ints, 0 = failed): box, cylinder, sphere, translate, rotate, union, cut, intersect, fillet_all(radius), shell(thickness, open_dir),
volume, area, face_count, edge_count, tessellate(deflection, angle) -> ArrayMesh with normals (Godot clockwise winding), export_step, import_step.
Phase 2 (sketch -> solid, KineCAD version 2; wrapper helpers in scripts/kcad.gd): `sketch_face / sketch_wire(items, origin, x_dir, normal)` with items
`KCad.line / arc (3 points) / circle / bspline (interpolating, closed = periodic)` (or `KCad.polygon(pts)`), `path_wire(points3d)`, `face_from_wire`,
`extrude(face, dist, both, taper)`, `revolve(profile, axis_origin, axis_dir, radians)`, `sweep(profile, path_wire)`, `loft(ids, ruled, solid)`,
`edges(id)` / `faces(id)` (ids + centre / normal / length / adjacent faces, for picking), `fillet_edges / chamfer_edges(id, edge_ids, size)`,
`mirror / mirror_join`, `pattern_linear / pattern_circular` (copies fused), `mass_properties(id)` -> {volume, area, center, inertia}. Edge and face ids are
positions in that shape's own list: stable for one shape id, NOT across derived shapes (re-read `edges()` after every op).
Notes: `LocOpe_DPrism` (taper) measures height along the slanted wall, so the extension asks for `dist / cos(taper)` and mirrors the half for `both`;
volumes use Gauss-Kronrod per knot span (the default fixed Gauss rule was 0.3% off on a B-spline wall); Godot `Vector3` is float32, so centres and inertia
from `mass_properties` are good to ~1e-7 only. Needs `TKFeat` (added to `LIBS`; `stage_dlls.py` picks the DLL up).
Test: `godot --headless --path . -s tests/cad_test.gd`. Picture: `godot --path . --position 4000,4000 -s tools/cad_pilot_shot.gd -- out.png`.

## Licence (read C:/Temp/claude/cad/licence.md summary; OCCT = LGPL 2.1 + Open CASCADE exception)
Fine for a closed paid app ONLY as shared DLLs next to kine_cad.dll (never statically linked), with: the LGPL text + `OCCT_LGPL_EXCEPTION.txt` in a
`licenses/` folder, an About line "uses Open CASCADE Technology (LGPL 2.1)", OCCT source reachable (we ship it unmodified: link to tag V8_0_1 + a mirror of the
tarball, or a 3-year written offer), the user able to swap the OCCT DLLs, and a commercial EULA that does not forbid reverse engineering the CAD module for
debugging modifications. Do not patch OCCT (a patch must be published). mingw runtime DLLs (libstdc++, libgcc_s_seh, libwinpthread) have the GCC runtime exception.

## Toolchain: why we build OCCT ourselves
godot-cpp is built with mingw g++ (ucrt64), so OCCT must be the same ABI. The MSYS2 `opencascade` package (7.9.2) is mingw-ucrt too, but depends on VTK, FFmpeg,
FreeImage, Tcl/Tk, OpenVR (~260 MB, dozens of DLLs). conda-forge / the official Windows installers are MSVC builds (C++ ABI does not mix with mingw). So: OCCT
from source with mingw, only the modelling + STEP toolkits, no visualization / Draw / FreeType / TBB. ~20 minutes on 10 cores; do it once.

## Build (all outside the repo; D:/kine_native is the working root)
1. OCCT source: `https://github.com/Open-Cascade-SAS/OCCT/archive/refs/tags/V8_0_1.tar.gz` -> D:/kine_native/occt/src (tar --strip-components=1). Ninja: https://github.com/ninja-build/ninja/releases (ninja.exe in D:/kine_native/tools).
2. Configure + build + install (mingw, release, shared):
```
export PATH=/c/msys64/ucrt64/bin:/d/kine_native/tools:$PATH
cd /d/kine_native/occt && mkdir build && cd build
cmake -G Ninja -S ../src -B . -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ \
  -DCMAKE_INSTALL_PREFIX=D:/kine_native/occt/install -DBUILD_LIBRARY_TYPE=Shared \
  -DBUILD_MODULE_Visualization=OFF -DBUILD_MODULE_Draw=OFF -DBUILD_MODULE_DataExchange=ON -DBUILD_MODULE_ApplicationFramework=ON \
  -DUSE_FREETYPE=OFF -DUSE_TBB=OFF -DUSE_FREEIMAGE=OFF -DUSE_RAPIDJSON=OFF -DUSE_DRACO=OFF -DUSE_TCL=OFF -DUSE_VTK=OFF -DUSE_FFMPEG=OFF -DUSE_OPENVR=OFF
ninja -j 10 && ninja install     # ninja resumes if interrupted
```
3. The extension (godot-cpp as for the sculpt pilot: D:/kine_native/godot-cpp + D:/kine_native/api/extension_api.json), from `native/cad`:
```
PATH=/c/msys64/ucrt64/bin:$PATH python -m SCons platform=windows use_mingw=yes target=template_release arch=x86_64 \
    custom_api_file=D:/kine_native/api/extension_api.json
python stage_dlls.py       # copies the OCCT + mingw runtime DLLs this DLL imports (objdump -p, transitive) into native/bin/
```
`native/cad/SConstruct` forces `disable_exceptions=no` (OCCT throws; its headers use try/catch) and links the C++ runtime dynamically (OCCT's DLLs use
libstdc++-6.dll and exceptions cross the boundary). godot-cpp's static lib is rebuilt when that flag flips, so build the sculpt pilot with
`disable_exceptions=no` too (`python -m SCons ... disable_exceptions=no` in native/) to stop it rebuilding every time.
`native/bin/` is git-ignored: no DLL and no OCCT binary is committed.

## What ships (measured)
kine_cad.dll 0.76 MB + 29 DLLs next to it = 62.5 MB raw, 23.4 MB zipped (OCCT toolkits 58 MB; libstdc++ 2.4 MB). The visualisation DLLs (TKV3d, TKService,
TKHLR, ...) come in only because TKXCAF links them; dropping the XCAF dependency (use STEPControl only, not XCAF) would cut ~6 MB. TKDESTEP (8.7 MB) and
TKGeomBase / TKGeomAlgo (5.6 MB each) are the big ones.

## Known limits of the pilot
- `tessellate` meshes single-threaded (`BRepMesh_IncrementalMesh` parallel=false): with the parallel flag OCCT's thread pool deadlocks at process exit when
  Godot unloads the DLL (the process never ends). Fix later: shut the pool down in the extension terminator, then switch parallel back on for big parts.
- `import_step` checks the file exists first: in this build OCCT's STEP reader kills the process on a missing path instead of failing.
- Meshes are not welded across B-rep faces (each face keeps its own vertices; positions match to <1e-9, so welding by position gives a watertight mesh, as the test does).
- Shapes live in a table inside the DLL (ids): call `KCad.release(id)` / `release_all()`.
