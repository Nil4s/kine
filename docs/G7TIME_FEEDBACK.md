# G7TIME: Assembly drives on a timeline, and a shared render helper (gaps G7 and G11)

Branch `w4-g7time` (from `origin/poser-ui-rounds`). Test: `tests/g7time_test.gd`, registered in `tools/run_all.sh` as `g7time:w`.

## What was built

- **Keys in the Assembly record** (`scripts/build/assembly_anim.gd`, class `AssemblyAnim`). One more optional entry next to `drives`, `links` and `joints`. A record without it loads, runs and saves exactly as before (bar f).
  - Format: `"anim": {"fps": 30, "length": 2.0, "tracks": [{"drive": "Crank", "keys": [[t, value, interp], ...]}]}`.
  - `interp` says how the curve leaves that key toward the next one (PartKeys' convention). The choices are `linear`, `smooth` and `constant` (hold). `smooth` is the app's default ease, `Scene._ease`'s x²(3 - 2x).
  - Before the first key and after the last, the value is held (Curves' `constant` extrapolation). A drive with no track stays at 0, which is its record pose.
  - Frame k is at k / fps, with both ends included: 2 s at 30 fps is 61 frames, PartMotion's count.
- **Playback.**
  - `AssemblyAnim.pose_at(asm, t)` is stateless: the drive values go through the links, then the loop solver gives each part's move, plus the solver's states in doubles.
  - `AssemblyAnim.frames(asm)` runs `AssemblyLoop.sweep`, solving each frame from the last frame's pose.
  - With two keyed drives, each is solved on its own and the moves are composed. One loop driven by two drives at once is not solved as a single system (see section 6).
- **Check motion along the animation.**
  - `AssemblyAnim.check(asm)` passes every frame's poses to `AssemblyMotion.check_motion`, through its new `moves` / `states` / `values` options. Every clash also carries its step `k`.
  - Each clash has a time `t` as well as the drive value. Each pair's first clash time is then refined by bisection between the last clear frame and the first clashing one, with 14 halvings of a frame.
  - The panel's line reads: "Lid and Ceiling: from 1.86 s (65.08 deg), worst 184.0 mm3 at 2 s (70 deg)".
- **The timeline strip** sits in the Check motion panel, under the drive's slider. Nothing was added to the Easy Part panel.
  - Length (s) field, Play / Pause, a time slider and the current time.
  - **Key** stores the picked drive's value at the current time. The value comes from the drive slider if that was moved last, otherwise from the timeline. The new key uses the Linear / Smooth / Hold choice.
  - **Delete key** removes the key at the current time.
  - A line lists the keys.
  - Each key edit and each length change is ONE undo step.
  - When the picked drive has keys, **Run the sweep** checks every frame of the animation and puts the first clash's time on screen.
- **The shared render helper** (`scripts/build/assembly_render.gd`, class `AssemblyRender`). One call does all of it: `await AssemblyRender.render(host, asm, opts)`.
  - Output: PNG frames (`frame_0000.png` ...), a contact sheet (`sheet.png`), and an `.mp4` through PlayblastExport's ffmpeg encode when ffmpeg is found. Without ffmpeg it gives frames + sheet and says so.
  - Options: `width` / `height`, `times`, and `camera` (pos / look / fov, or a Transform3D). The default camera is framed on the box the parts sweep through, optionally from `view_dir`.
  - More options: `cut` (SectionLook's section, one cap colour per part), `only` (draw just these parts), `sheet_tile` / `sheet_cols` and `background`.
  - `AssemblyRender.sheet(images)` and `tile_of()` work on any list of images.
- **Export.**
  - The Assembly panel's Export row has a new **Video** button. It films the animation at 1280 x 720, looking the way the view looks now, into `<exports>/<name>_motion_<stamp>/`.
  - The S box has the same action: **"Assembly: film the motion"**.

## 1. Result

Bars were committed before the first run (294dbdbf). First run: 26 ok, 1 fail (section 5). Second run: 27 ok, 0 fail.

| bar | result | numbers |
|---|---|---|
| a interpolation | ok | 9 times vs hand values (linear 15; smooth 23.75 / 10 / -3.75; hold -10; held 50 / 10; 30 at a key): worst 0 (bar 1e-9). Keys given out of order come back in time order. 2 s at 30 fps = 61 frames, the last at 2.0 s |
| a CONTROL key at 1.1 s instead of 1 s | ok | misses the hand values by 1.82 |
| b CH13 engine 0 -> 720 deg / 2 s / 30 fps | ok | 61 frames. Drive vs 12k deg: worst 5.7e-14. Piston pin vs r cos t + sqrt(l² - (r sin t)²), and crank pin vs (r sin t, r cos t): worst 5.5e-11 mm (bar 1e-6). 60 ms for all frames |
| b CONTROL reversed track | ok | 41.17 mm off at frame 22 (264 deg). The piston alone can't see a reversal (y(-t) = y(t)); the crank pin can |
| c clash in time, linear | ok | Lid x Ceiling only, first at 1.8596 s (65.08 deg). Hand onset 1.8494 s (64.73 deg); one frame is 0.0333 s |
| c clash in time, smooth key | ok | first at 1.6760 s; hand onset 1.6637 s (bisection on 70 s(t/2) = 64.73) |
| c CONTROL keyed 0 -> 60 deg | ok | 0 clashes |
| d render: frames | ok | 13 PNGs (2 s at 6 fps), each 320 x 240, written in 0.9 s |
| d render: sheet | ok | 4 x 4 tiles of 256 x 192. Tile i is byte-equal to frame i shrunk; the 3 spare tiles are the fill |
| d render: moving vs static | ok | each consecutive pair differs in 974-1750 pixels inside the piston's own silhouettes (bar 100). The head's 1937 pixels (eroded 3 px) are byte-equal in all 13 frames |
| d mp4 | ok | written (ffmpeg 9.0.2, winget) |
| d CONTROL frozen track | ok | 13 frames, 0 pixels differ from frame 0 |
| e CONTROL no keys | ok | the timeline at 1 s leaves the piston at 66.7 mm; Play is disabled |
| e add keys | ok | Key at 0 s (Smooth) and Key at 2 s (drive slider 360) give `[[0,0,"smooth"],[2,360,"linear"]]` in 2 undo steps |
| e scrub | ok | at 0.5 s: crank 56.25 deg (hand 360 x s(0.25)). Piston mesh 55.62691 mm vs closed form - 34 mm: 6.1e-6 mm (float32, bar 1e-4) |
| e play | ok | ran 150 frames to 2.0 s and stopped, with time rising. Piston back at TDC 66.70000 |
| e Export Video | ok | 61 frames, sheet and mp4. The status line says "Filmed 61 frames to e_video: sheet.png, Single-cylinder_engine_(CH13).mp4" |
| e Run | ok | 61 frames swept, "No clash over the whole animation" |
| e delete + undo | ok | Delete key at 2 s leaves 1 key (3 undo steps). Three Ctrl+Z give the identical record with no `anim` |
| f old records | ok | old_assembly.json, drive_199.json (#199) and joint_204.json each open in the screen; with the timeline moved, each saves back equal. joint_204.json was written by the #204 code (3adcba84) before any change here |
| f CONTROL | ok | the #204 record with one key doesn't compare equal |
| g payoff | ok | CH13 sheet re-made: 13 tiles (6 x 3). The section at 40 deg shows 12294 cap-colour pixels (ch13 bar i: >= 800) |
| g CONTROL | ok | the uncut view has 0 cap-colour pixels |

**Payoff (g):** the CH13 contact sheet, plus the whole and cut section views, take **11 lines** of helper calls. CH13 wrote ch13_scene.gd (71 lines) plus grab / diff / cap_px / the sheet loop in ch13_test.gd (77 lines), 148 in all. CH14's ch14_scene.gd (199 lines) and CH15's ch15_scene.gd (106) did the same job for their own scenes.

Suites (one wtest call, final code): g7time 27/0, g2loop 24/0, g1motion 22/0, ch13 92/0, ch14 60/0, ch15 44/0, easypart 73/0, peasy3 23/0, freestart 14/0.

## 2. Engineering level reached

- **Mechanism animation: L3.** The keyed motion is checked against hand values to 1e-9. The engine's motion over two revolutions matches the slider-crank closed form to 5.5e-11 mm at every frame. Clash onsets in time are within 12 ms of the hand onset. Each bar has a planted control.
- **Why not L4:** there are no velocities or accelerations along the timeline: piston speed, a peak-acceleration check, inertia forces at the keyed speed. The same Jacobian as G2 would give them. There is no motion profile that follows a design rule (cam laws, jerk limits), and "smooth" is one fixed ease. Two drives in one loop aren't solved together.

## 3. What Kine lacked (rows for the ledger)

| needed | exists today | workaround | cost | proposed feature |
|---|---|---|---|---|
| keyframed drives and a sequence video of a mechanism | **this branch**: AssemblyAnim + AssemblyRender | none needed now | 11 lines for CH13's sheet + section | done |
| velocity / acceleration along the animation | positions only | none | could not do it | J qdot = -dPhi/dv per frame; a plot under the timeline |
| one loop moved by two drives (an excavator arm: two cylinders) | each drive solved alone | none | could not do it | known parts from every keyed drive in one AssemblyLoop model |
| the build sequence (parts appearing in stages) on the same timeline | nothing (G33) | none | not attempted | a "stage" track: parts shown from time t, the render helper films it |
| keys on the curve, drawn | a text line lists the keys | none | reading numbers | key ticks on the time slider, and a small curve view (reuse the dopesheet's drawing) |

## 4. What looks wrong (C:/Temp/claude/g7time/timeline.png, undone.png, g_sheet/sheet.png, g_section_cut/frame_0000.png, e_video/sheet.png, LOOKED at)

- **timeline.png:** the strip fits under the drive slider, and the panel ends just above the bottom bar at 1280 x 720.
  - It reads: "0.5 s: Crank at 56.25 deg", Length 2 s, Play, the slider at a quarter, "0.5 s", then Key / Delete key (greyed: no key at 0.5 s) / Linear, and "Crank keys (deg): 0 s: 0, 2 s: 360".
  - The crank is turned and the rod leans, which is right for 56 deg.
  - **Wrong:** with several clash lines listed, Check motion's panel would run past the bottom bar. It doesn't scroll, and that was already true of the panel before this branch. The app's status line also shows through under the Close button.
- **g_sheet/sheet.png:** 13 engine frames over two revolutions. The rod swings and the piston moves in the transparent cylinder.
  - Frames 0, 6 and 12 match (TDC), as do frames 3 and 9 (BDC).
  - The spare tiles are dark grey, which marks them as empty but is a heavy block on a light sheet.
- **g_section_cut/frame_0000.png:** the cut is through the bore axis, and each part has its own cap colour. The crankcase (orange), cylinder walls (green), piston (pink), rod (teal), pin (blue), crank pin (purple) and head read as separate parts. It looks right.
- **e_video/sheet.png (the Export Video path, 320 x 180):** the camera frames the bounding sphere, so a tall engine in a 16:9 frame fills only the middle third of the width. 61 tiles make a sheet of small thumbnails. A long animation should get a sampled sheet (every n-th frame); today all frames go in.

## 5. What was changed after seeing results (no bar or tolerance was changed)

- **c smooth failed on the first run.** The first clash was reported at frame 51 (1.70 s, 65.75 deg), but the hand onset was 1.6637 s and the window was one frame (0.0333 s), so the report came 0.036 s after the onset.
  - The cause: at frame 50 (64.81 deg) the lid is already 0.045 mm into the ceiling, but that is 0.05 mm3, under the 1 mm3 contact threshold. Frame sampling can therefore report a clash up to one frame after the threshold crossing, and the crossing itself comes slightly after geometric contact.
  - **Code change:** `AssemblyAnim.check` now bisects each pair's first clash between the last clear frame and the first clashing one (14 halvings), and lists that as `first_t` (`first_frame_t` keeps the frame time).
  - **Test procedure change:** bar c now reads the listed first time (`by_pair.first_t`, the time the panel shows) instead of the earliest clashing frame.
  - New results: 1.8596 s (linear) and 1.6760 s (smooth), both 0.35 deg after the hand onset. That is where the overlap passes 1 mm3. The bar and tolerance are unchanged.
- **The key list text** changed from "0.0 s 0" to "0 s: 0" after looking at timeline.png. This was text only.

## 6. What is left

- **Two drives in one loop:** each keyed drive is solved alone and the moves are composed. That is right for drives that move separate parts or chains, and wrong for one loop with two inputs.
- **Velocities and accelerations** along the timeline (see section 2).
- **The build sequence half of G7** (stages, parts appearing) is G33's job. The render helper is ready to film it once there is a stage track.
- **Compare-with-a-photo half of G21:** the helper renders sequences, but there is still no side-by-side against a photo.
- **The Check motion panel needs a scroll** when the clash list is long (section 4).
- **The sheet for long animations** should sample every n-th frame, and the default camera should fit the box to the frame's aspect, not the bounding sphere.
