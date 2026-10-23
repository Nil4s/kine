# Kine

**Pose, animate, model and check a fighting character in one app.** Kine (formerly Poser) is a desktop
animation tool built in Godot 4.7, by Teschima Studios. It starts from a mannequin on the UE5 skeleton and
grows into a full character pipeline: you pose card by card, the app grades the motion like a coach would,
and the mesh tools know the model is a body.

> Status: early (0.1.0), in active development. Windows is the main platform; Linux and macOS launch
> through `pose.sh`.

## What it does

- **Pose and animate.** Card-based blocking (arrive / move / hold), timeline, dope sheet, graph editor,
  IK hands and feet, weapon grips for one and two hands, pose library, type a move in words and get blocking.
- **Check.** A rulebook grades every scene (balance, contacts, hits, frame data, human limits) and every
  finding comes with a one-click fix. Deformation over the scene, "will this deform?" and "weights broke
  here" point at the frames and joints that go wrong.
- **Model, sculpt, surface.** A half-edge mesh with extrude, bevel, loop cut, knife, booleans, fill,
  proportional editing, snapping, modifiers, UVs (unwrap, pack, editor, export), PBR materials, vertex and
  weight paint, sculpting with masks, symmetry, face sets, alphas and matcaps.
- **Body-aware.** Every vertex knows its nearest bone, body region and anatomy tag. That powers armour
  made from the body, shrinkwrap onto the skin, model checks graded for animation, real-size sanity
  (a 3 m sword gets flagged against the fighter's arm) and auto weights.
- **Deliver.** Export .glb, .fbx, .bvh and engine-ready files; playblasts; share a viewer page.

Some of the modelling features above are on integration branches and not yet merged into the default
branch. See `docs/ROADMAP_400.md` for what is done and what is next.

## Run it

1. Install [Godot 4.7](https://godotengine.org/download) (the standard build, not .NET).
2. Clone this repo.
3. Start it:
   - Windows: `pose.bat`
   - Linux / macOS: `sh pose.sh`

   The launcher finds Godot from `POSER_GODOT`, a `godot/` folder beside the launcher, your `PATH`, or a
   one-line `godot.path` file. You can also open `project.godot` in the Godot editor and press Play.

## Test it

```sh
sh tools/run_all.sh            # every suite, one line each, then SUITES n/n PASS
sh tools/run_all.sh kmesh cli  # only those suites
```

Some suites open a real window; that is expected. Logs go to `$TMP/poser_suites/`.
`README_AI.md` explains how to drive the app headless from the command line (`tools/poser_cli.gd`).

## Repo map

| Path | What |
|---|---|
| `main.tscn`, `scripts/` | the app (`scripts/main.gd` is the entry point) |
| `tests/` | one test script per suite |
| `tools/` | test runner, CLI, helpers |
| `scenes/`, `poses/`, `moves/`, `data/` | example scenes, poses and data |
| `docs/` | roadmaps, research, export notes, the scene schema |

## Licence

Code: [MIT](LICENSE). What you make with Kine is yours, and the bundled mannequin is CC0; see
[NOTICE.md](NOTICE.md).
