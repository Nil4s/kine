# Third-party notices

Kine's own code is source-available (PolyForm Noncommercial or Small Business, plus a commercial licence): see `LICENSE`.
This file lists other people's work that Kine ships, links or needs, the licence of each, and what we must do about it.
Full licence texts that must travel with a build are in `licences/`.

Only things that ship with Kine, are linked into it, or that the app asks the user to install are listed.
Programs used only as a reference or in our own tests (Blender, ComfyUI, Isaac Lab) are not shipped and are not dependencies.

## 1. Ships with a Kine build

| Component | Version | Licence | Where | What we must do |
|---|---|---|---|---|
| Godot Engine (the export template inside every exported Kine build) | 4.7.2 | MIT, plus the licences of the libraries inside Godot (listed in Godot's `COPYRIGHT.txt`) | not in the repo; added by the export preset | Ship the Godot MIT notice and Godot's third-party list with every build: `licences/Godot-MIT.txt` and `licences/Godot-4.7.2-COPYRIGHT.txt`. Show them in an About / Licences screen or put the folder beside the exe. The full text of each library licence Godot names is available at run time from `Engine.get_license_text()` and `Engine.get_license_info()`, so an About screen can print them. |
| godot-cpp (C++ bindings, linked into `kine_native` and `kine_cad`) | not pinned in the repo (built from `D:/kine_native/godot-cpp`) | MIT | built into `native/bin/*.dll` (git-ignored) | Keep the MIT notice with the DLLs: `licences/godot-cpp-MIT.txt`. Record the exact godot-cpp commit used for each release. |
| Open CASCADE Technology (OCCT), the CAD kernel under `KineCAD` | 8.0.1 (tag `V8_0_1`) | LGPL 2.1 with the Open CASCADE exception 1.0 | not in the repo; `native/cad/` builds `kine_cad.dll` against it; its DLLs are staged by `native/cad/stage_dlls.py` into `native/bin/` (git-ignored) | See section 2. |
| MinGW-w64 runtime DLLs: `libstdc++-6`, `libgcc_s_seh-1`, `libwinpthread-1` | MSYS2 ucrt64, version not recorded | GPL-3.0 with the GCC Runtime Library Exception (libstdc++, libgcc); permissive MIT-style (winpthreads) | staged next to `kine_cad.dll` by `stage_dlls.py` | The GCC runtime exception lets us ship them with a non-GPL program. Name them in the About / Licences screen. Record the exact versions at release time and keep the MSYS2 package licence files with them. |
| Quaternius "Universal Animation Library 2" mannequin | Standard | CC0 1.0 | `assets/mannequin.glb` | Nothing required. Credited anyway in `assets/LICENSES.txt`. |
| Quaternius "Universal Base Characters" Superhero_Male, fitted onto the mannequin skeleton | Standard | CC0 1.0 | `assets/body_smooth.glb` (built by `tools/smoothbody_build.gd`) | Nothing required. Credited in `assets/LICENSES.txt`. |
| Carnegie Mellon University Graphics Lab Motion Capture Database, as a derived statistic (occupancy tables, 300 quantised poses) | 44 clips from the project's own asf/amc zip | "Free for all uses"; may be in commercially sold products; the raw data may not be resold, even converted | `data_gen/mocap_stat.json`; notes in `data_gen/README.md` and `docs/physics_constants_i48.md` | No raw or converted clips are in the repo; keep it so. Keep the acknowledgement in Help / About: "The data used in this project was obtained from mocap.cs.cmu.edu. The database was created with funding from NSF EIA-0196217." |
| Kine's own artwork, icons, tip pictures, brand files | n/a | Kine's own licence (icons are drawn in code, `scripts/icons.gd`; the brand SVGs use no fonts) | `assets/brand/`, `assets/tips/`, `scripts/icons.gd` | Nothing third-party. The name "Kine" and its logos are not licensed to others (`LICENSE`). |
| Fonts | none | n/a | The repo contains no font file. The UI uses Godot's built-in default font, whose licence is in Godot's `COPYRIGHT.txt` (covered by the Godot row). | If we add a font later, add its row here (OFL fonts need the OFL text shipped). |

There are no Godot addons in the repo (no `addons/` folder).

## 2. Open CASCADE (LGPL 2.1 + OCCT exception): the exact obligations

OCCT is the one component with real obligations. The licence is LGPL 2.1 with the Open CASCADE exception 1.0
(`licences/LGPL-2.1.txt`, `licences/OCCT_LGPL_EXCEPTION.txt`; both copied from tag `V8_0_1` of
https://github.com/Open-Cascade-SAS/OCCT). Kine uses it only through `native/cad/`, and only as shared DLLs.

When we ship a build that contains the OCCT DLLs we must:

1. **Keep OCCT as separate shared DLLs** next to `kine_cad.dll`. Never link it statically into `kine_cad.dll`, Kine or any other file. (`native/cad/SConstruct` links the `.dll.a` import libraries, so this holds today.)
2. **Ship the licence texts**: `licences/LGPL-2.1.txt` and `licences/OCCT_LGPL_EXCEPTION.txt` inside the build.
3. **Give prominent notice in the supporting documentation** that Kine uses Open CASCADE Technology. This is the condition of the OCCT exception. Put a line in the About / Licences screen and in the README of the download: "Kine uses Open CASCADE Technology (LGPL 2.1 with the Open CASCADE exception)". The README of this repo has it.
4. **Make the OCCT source available.** We ship it unmodified, so link to tag `V8_0_1` (https://github.com/Open-Cascade-SAS/OCCT/archive/refs/tags/V8_0_1.tar.gz) and keep a mirror of that tarball, or give a written offer valid for 3 years. A link alone is weaker than a mirror: keep the mirror.
5. **Let the user swap the OCCT DLLs.** Do not sign, hash-check or otherwise block replacing them with a rebuilt OCCT of the same version. `native/CAD_BUILD.md` documents the build.
6. **Not forbid reverse engineering for debugging modifications** to the CAD module in the commercial licence or EULA. LGPL 2.1 section 6 requires that terms for our own work let the customer modify the combined work for their own use and reverse engineer it to debug those modifications. The current `LICENSE` and `COMMERCIAL.md` do not forbid this and do not say it either: see the report's "Needs a decision".
7. **Not patch OCCT.** A patch must be published under the LGPL.

`KCad` keeps working without the DLLs (`KCad.available()` is false and the app starts), so a build can also leave OCCT out.
The sculpt pilot `kine_native.dll` (`native/src/`) does not use OCCT and must not depend on its DLLs.

## 3. Not shipped: installed by the user when they use a feature

Kine starts and works without these. They are separate packages the user installs with pip from their own source. We do not bundle them.
If we ever bundle a Python runtime or any of these, each row becomes an obligation and must be re-checked first. Licences below are as published upstream; verify the exact version before bundling.

| Package / file | Used by | Licence | Note |
|---|---|---|---|
| mediapipe, opencv-python | video import, live webcam puppet, hand import (`tools/see_video.py`, `tools/live_pose.py`) | Apache-2.0 | If bundled: ship the Apache-2.0 text and NOTICE files. opencv-python wheels also carry FFmpeg (LGPL): check that too. |
| MediaPipe model files `pose_landmarker_heavy.task`, `hand_landmarker.task` | same | Apache-2.0 (Google; downloaded by the user, not in the repo) | If we ever ship the model files, include the Apache-2.0 text and a notice. |
| segno, zxing-cpp, pillow | QR share (`tools/qr_tool.py`) | BSD-3-Clause, Apache-2.0, HPND | Not bundled. |
| mujoco, scipy, numpy | "Make it physical" (`scripts/make_physical.gd`, `tools/physics/`) | Apache-2.0, BSD-3-Clause, BSD-3-Clause | Not bundled. |
| torch, h5py, isaaclab, rsl_rl | research scripts in `tools/physics/isaac/` only | various (Isaac Lab is BSD-3-Clause) | Research scripts, not part of a build. |
| Blender (`bpy`) | `tools/blender_check.py`, `tests/py/*` | GPL | Used only as an external checker by our tests. Nothing is linked or shipped. Not a dependency. |
| ComfyUI + Wan 2.1 | `tools/gen_video.py` (talks to 127.0.0.1) | GPL-3.0 (ComfyUI), Apache-2.0 (Wan 2.1) | A separate program on the user's machine. Not shipped. |

## 4. Test and reference data in the repo

| File | Source | Status |
|---|---|---|
| `tests/fixtures/mixamo_rig.fbx`, `mixamo_rig_ref.json` | Made by our own script `tests/fixtures/make_mixamo_fbx.py` from Kine's own skeleton; only the bone names follow Mixamo's | Own work. Not a Mixamo asset. |
| `tests/fixtures/gen_hammer.webm` | Generated with Wan 2.1 text-to-video (Apache-2.0) through `tools/gen_video.py` | Generated clip. |
| `tests/fixtures/fps16_hammer_2s.webm`, `refs/video/*.json` | Source of the footage not recorded in the repo | See the report's "Needs a decision". |
| `data_gen/mocap_stat.json` | Derived from CMU mocap, section 1 | Covered above. |
