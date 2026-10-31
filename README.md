<p align="center"><img src="assets/brand/kine_logo_dark.svg" alt="Kine" width="360"></p>

# Kine

Kine is a desktop app for makers. You can design simple parts, build and pose a character, animate it, and hand a part to the character to hold. It is made by Teschima Studios and built with Godot 4.7.2. It was called Poser until recently.

> Status: pre-release. There is no public launch, no installer and no website yet. Windows is the main platform. Linux and macOS start through `pose.sh` but get less testing. The project version in `project.godot` is 0.4.0.

## What Kine does

### Easy Part: design a part without CAD training

Easy Part builds a part from plain choices and sliders, in millimetres. Every step goes in a history list you can scrub, undo and replay.

- Start from a box, cylinder, sphere, tube or plate, or from a template: sword, axe, shield, chair, crate, gear, rack, slot hole, phone stand, shelf bracket, box with lid, room, yard, and car shapes with wheels.
- Draw a sketch with typed lengths and live dimensions, then pull it up, spin it round, round the edges, hollow it, cut a hole or a slot, and add finger joints.
- Parts library (`scripts/easy_part.gd`): ISO screws, nuts (ISO 4032) and washers (ISO 7089) in M3 to M6, gears, racks, cam and follower, bearings with their seats, hinges, springs, magnets, and 2x4 and MDF wood boards. A library part stays parametric: change the screw size and its hole follows.
- "Type it": write a line of words such as a size and wall thickness, and Kine builds the box.
- Checks and readouts: size, weight from the material, print time, overhang for printing, "what fits here", real-size references (a hand, a coin, a phone), a section (cut) view, an exploded view, and a flat pattern for a laser-cut box.
- Give to a character: a character holds the part in one hand, at the grip point you set, and a typed move is slowed by the part's weight.
- Save and share parts in My parts. A printable instruction sheet opens in your browser.
- Exact solids need the native CAD library (see "Run it"). Without it, Kine still starts and the rest of the app works.

### Characters and animation

- A mannequin on the UE5 skeleton, plus an optional smooth body.
- Card-based blocking (arrive, move, hold), a timeline, a dope sheet and a graph editor, IK hands and feet, weapon grips, a pose library, and typing a move in words to get blocking.
- A rulebook that grades a scene (balance, contacts, hits, frame data, human limits) and offers a one-click fix for each finding. A real-mocap statistic flags poses real people do not make.
- Animation from a video, a live webcam puppet, hand import, and mixing a mocap clip with a typed mood. These need Python packages you install yourself.
- Ragdoll: hit, fall and get back up.

### Modelling, sculpting and surface

- A half-edge mesh with extrude, bevel, loop cut, knife, booleans, proportional editing, modifiers, UVs, PBR materials, vertex and weight paint, and sculpting with masks.
- Body-aware tools: armour made from the body, shrinkwrap, auto weights, and a flag when a prop is the wrong real size for the character.

### Export and sharing

- Animation: glTF (.glb), BVH, FBX, USD (.usda and layers), Unity / Unreal / Godot files, and a PoseTable for a game. See `docs/EXPORT.md`.
- Meshes: OBJ and GLB from the export dialog.
- STEP: Kine can import a STEP file into Build mode and the CAD library can write STEP (`KCad.export_step`, tested in `tests/cad_test.gd`). There is no STEP button in the export dialog yet.
- STL and 3MF export are not built yet (`docs/ROADMAP_400.md`, item N05).
- Share a pose or a short scene as a QR code, or as a `.kinepack` file.
- Drive the app without a window through `tools/poser_cli.gd` and `tools/mcp/poser_mcp.py` (see `README_AI.md`).

Plans: `docs/APP_ROADMAP.md` (milestones), `docs/ROADMAP_400.md` (feature list), `docs/INNOVATIONS.md` (body-aware ideas).

## Run it

1. Install Godot 4.7.2, the standard build (not .NET). Other 4.7 builds may work; 4.7.2 is what the tests use.
2. Clone this repo.
3. Start it:
   - Windows: `pose.bat`
   - Linux / macOS: `sh pose.sh`

   The launcher finds Godot from `POSER_GODOT`, a `godot/` folder beside the launcher, your `PATH`, or a one-line `godot.path` file. You can also open `project.godot` in the Godot editor and press Play.

### The native CAD library is not in git

Exact solids (fillets, shells, booleans, STEP) come from `kine_cad.dll`, built on Open CASCADE Technology 8.0.1. The DLLs are build products and live in `native/bin/`, which git ignores. Without them, `KCad.available()` is false, the CAD builders return nothing, and the tests for them skip.

To build them, follow `native/CAD_BUILD.md` (MinGW, Open CASCADE from source, godot-cpp, then `native/cad/stage_dlls.py`). The sculpt pilot `kine_native.dll` builds from `native/` the same way and does not need Open CASCADE.

### Optional Python tools

Some features start a Python helper on your machine. Install only what you use:

- Video import and live webcam: `pip install mediapipe opencv-python`, plus a MediaPipe pose model file (see the header of `tools/see_video.py`).
- QR share: `pip install segno zxing-cpp pillow`.
- Make it physical: `pip install mujoco scipy`.

Kine does not ship these. Their licences are listed in `THIRD_PARTY_NOTICES.md`.

## Test it

```sh
python tools/run_par.py              # every suite in parallel, windows off-screen
python tools/run_par.py --changed    # only the suites your changes touch
python tools/run_par.py kmesh cli    # only those suites
```

`tools/run_par.py` reads its suite list from `tools/run_all.sh` and uses Godot 4.7.2 at the path in its `G` variable (set the `G` environment variable to your own Godot). Window suites render off-screen; set `SHOW=1` to watch them. Logs go to `$TMP/poser_suites/`. A few suites are slow and need a larger `TIMEOUT`: see `CLAUDE.md`.

## Repo map

| Path | What |
|---|---|
| `main.tscn`, `scripts/` | the app (`scripts/main.gd` is the entry point) |
| `scripts/build/` | Easy Part and Build mode: part templates, sketches, flat patterns |
| `native/` | C++ GDExtensions: `cad/` (Open CASCADE) and `src/` (sculpt pilot) |
| `tests/` | one test script per suite |
| `tools/` | test runner, command line, MCP server, Python helpers |
| `scenes/`, `poses/`, `moves/`, `data/` | example scenes, poses and data |
| `docs/` | roadmaps, research, export notes |
| `licences/` | licence texts that must ship with a build |

## Licence

Kine is source-available, not open source.

- Free under [PolyForm Noncommercial 1.0.0](LICENSES/PolyForm-Noncommercial-1.0.0.md) for personal use, hobby projects, study, research, schools and charities.
- Free under [PolyForm Small Business 1.0.0](LICENSES/PolyForm-Small-Business-1.0.0.md) for a company with fewer than 100 people and under 1,000,000 USD revenue (2019 dollars, adjusted for inflation) in the prior tax year. You choose whichever fits. See [LICENSE](LICENSE).
- Bigger companies, and uses neither licence allows, need a paid [commercial licence](COMMERCIAL.md).

What you make with Kine, and the files you export, is yours ([NOTICE.md](NOTICE.md)).

Kine uses other people's work: Godot Engine (MIT), Open CASCADE Technology (LGPL 2.1 with the Open CASCADE exception), godot-cpp (MIT), and CC0 Quaternius characters. Kine uses Open CASCADE Technology as separate shared libraries. The full list, with licence texts, is in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [licences/](licences/).
