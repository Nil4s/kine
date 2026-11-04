# C79: why a clean quit() of the exported Kine took ~90 s, and the fix

C78 found that the exported `Kine.exe` needed about 90 s to exit after a clean `quit()` (headless), so its smoke test ended with `OS.kill`. A user closing the app in its first minute would have felt the same.

## Cause
`main.gd` calls `SlicerSend.prewarm()` at start-up: the Export dialog's slicer lookup runs on a WorkerThreadPool task. That task ran `OS.execute("reg", ["query", <Uninstall key>, "/s"])` for three registry keys. On this machine one of them takes 15.7 s alone (`reg query HKLM\...\Uninstall /s`, 256 KB of output); under load from other processes it took 3 to 60 s. At quit the engine finishes the worker pool (`WorkerThreadPool::finish`) and waits for every running task, so the main thread sat idle until the registry dump was done. Nothing else was involved: not OCCT, not `kine_native` / `kine_cad` terminate callbacks, not audio, not python, not a Thread of ours.

How it was found (all measured on the exported build, headless, temp APPDATA):
- Phase timestamps (`tools/c79_trace.gd`, printed by the smoke): `quit()` called -> every `_exit_tree` -> main `tree_exiting` -> root predelete takes 0.3 s. The whole delay is AFTER the scene tree is gone (engine cleanup), main thread at 0 CPU (13.2 s CPU before, 13.2 s after, 4 s apart).
- Bisect modes `--c79-at=start|part|free` (quit before Part opens, after Part, after freeing main by hand): 4.4 to 15 s in every mode, so not Part, not CAD, not the scene's node free (that is 0.15 s). Same with the DLLs removed (c79b), so not the GDExtensions either. A tiny empty project quits in 0.4 s.
- A stack sample of all 30 threads in the gap (suspend, read RIP and the stack, resume; only our own process): 20 idle pool threads, and ONE pool thread named `WorkerThread 0` in a `Sleep` loop inside `OS::execute`, the others blocked on it. Only one `WorkerThreadPool.add_task` runs `OS.execute` at start: `SlicerSend._job`.
- `reg query ... /s` timed by hand: 15.7 s, 2.7 s, 0.5 s for the three keys.

## Fix
`scripts/build/slicer_send.gd`: the query now runs through `OS.execute_with_pipe` and the worker polls the pipe (`_reg_query`). `SlicerSend.shutdown()` sets a stop flag and kills the `reg.exe` this lookup started (only those pids); `main._exit_tree` calls it first. A stopped lookup returns without caching a half result. Behaviour is otherwise the same: the same list is found (bar 1 compares it to the old OS.execute code kept in the test), the cache and `prewarm`/`detect_cached`/`forget` are unchanged. `detect_system()` called directly still runs in full (so a test that frees one Main and builds the next is unaffected).

## Phase times (headless smoke: Part + box + mesh, then `quit()`; wall clock from the line "quit() called")
| phase (ms after quit()) | exported before | exported after | source before | source after |
|---|---|---|---|---|
| root children `_exit_tree` | 50 / 111 | 52 / 104 | 44 / 112 | 51 / 111 |
| main `tree_exiting` | 170 | 154 | 193 | 155 |
| root predelete | 226 / 319 | 204 / 250 | 256 / 346 | 194 / 244 |
| process exit | **61 643** | **841** | **4 346** | **1 145** |

The earlier C78 figure (~90 s) and these (61.6 s, and 4.4 to 15 s in the bisect runs) differ only by what the machine was doing at the time: the reg dump's length is the variable. The source run had the same wait (4.3 s), it just looked small. The remaining 0.8 to 1.1 s is the engine's ordinary cleanup; the GDExtension terminate callbacks fall inside it (the RID-leak lines print 0.6 s after predelete, so nothing slow sits there). No timestamps were added inside the native terminate callbacks, since the measured whole of that stretch is under a second.

## Bars (tests/c79_test.sh, tests/c79_test.gd)
Shell test (bars committed in `c8945b53` before any number was read): S1 exported smoke, `quit()` to process exit < 5 s, exit 0, no `OS.kill` (the smoke has none now); S2 same through the editor binary (control run); S3 the clock can fail; S4 all phase lines present. Result: S1 841 ms, S2 1145 ms, before the fix S1 failed at 61 643 ms.
Unit bars (`tests/c79_test.gd`, registered `c79:w`; written together with the fix, with the old lookup kept as the reference and a control that shows the query is slow enough to measure): same slicer list as the old code; `shutdown()` 300 ms into a lookup ends it in 2 ms; the control without shutdown still runs at 400 ms; a stopped lookup caches nothing; a direct call after shutdown runs in full.

## Runs
c79 (6 ok), c78 unit (7 ok), easypart (73 ok), peasy3 (23 ok), freestart (14 ok), n05 (15 ok, it exercises prewarm and the cache): all pass with `WT_MAX=8`. `tests/c78_test.sh` with the smoke on `quit()`: C78 PASS (B3 smoke exit 0 in 13.7 s whole process, no OS.kill). B7 had a race of its own (the uninstaller's helper still deletes `unins000.exe` after `Kine.exe` is gone; the test waited only for Kine.exe, and failed twice once the exit was clean); the wait now covers the folder being empty, the bar is unchanged. c77 is not in this branch's base (it lives on `w4-c77`), so it was not run here.

## Notes
- `tools/c78_smoke.gd` now ends with a real `get_tree().quit()` plus the phase tracer (`tools/c79_trace.gd`), and has bisect switches `--c79-at=start|part|partfree|free`.
- Other long blocking calls inside tasks at close (video import, fix preview, bake) already have their own stop in `main._exit_tree`; this one did not.
