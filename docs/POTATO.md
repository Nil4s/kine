# Kine on a low-end PC (graphics quality + the perf probe)

View > Graphics quality: Auto / Low / Medium / High (scripts/quality.gd, remembered in the settings file, `[graphics] mode`).

| | renderer | MSAA | 3D scale | sun / positional shadow map | shadow filter | sun shadow distance |
|---|---|---|---|---|---|---|
| Low | Compatibility | off | 0.67 | 1024 / 1024 | hard | 20 m |
| Medium | Mobile | 2x | 0.85 | 2048 / 2048 | 1 | 40 m |
| High | Forward+ | 4x | 1.0 | 4096 / 4096 | 2 | 100 m |

* Only the **renderer** needs a restart (it is fixed when the process starts): the app writes `override.cfg` (next to the .exe; in the project folder from the editor build) and asks "Restart now / Later". A `--rendering-method` flag on the command line wins and never asks.
* **Auto** picks a tier at start from the adapter name (Intel / UHD / HD / Iris / Vega / GTX 9xx-105x are always Low), VRAM when Godot can tell, cores and RAM; on the first run a 3 s benchmark of the live scene (120 frames, vsync off) lifts or drops one tier. The pick is saved per adapter and used from the next start: the picture never changes by itself in a session.
* Tests start on High (the old picture) unless they save a mode.
* `python tools/perfprobe.py [--mode as_is|compat|mobile|lowcpu] [--stress clips50,props100,mesh1m,tex4k,city]` tours every page and writes CSV + markdown (default `C:/Temp/claude/perf/`); `tests/perfprobe_scene.gd` is the scene it launches. `tests/perfpresets_test.gd` is the suite.
