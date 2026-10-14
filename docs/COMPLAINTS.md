# The ten complaints (round 5, Nick 10-14: "check the 10 complains")

What 3D animators say their tools lack, read from forums, schools and tool docs, and what Poser now does about each.
Every "done" has a test; every number was measured, not assumed.

| # | complaint | what Poser does | where | proof |
|---|---|---|---|---|
| 1 | Gimbal flips: a joint spins round between two keys | MEASURED: none. Joints are swing/twist with limits, never Euler gimbals. Worst turn over 32 scenes is 58.4 deg/frame (3505 deg/s); bar 105 deg/frame (pitcher's shoulder 4766 +- 772 deg/s, mean + 2 SD) | `tests/flip_survey.gd` | a planted 180 deg twist reads 180 and is caught |
| 2 | Foot sliding | Check rule FOOT SLIDE: a down, settled foot drifting over 2.5 cm | `scripts/rulebook.gd`, `docs/MOTION_RULES.md` | `tests/rules_test.gd`: fires on a 0.8 mm/frame creep, quiet on a step, a still foot, 2.4 cm, a lifted foot |
| 3 | "I can't see my spacing" | Spacing ghosts (Shift+O): weapon + forearms every 0.1 s, 0.5 s each way, orange before / green after | `scripts/overlays.gd` | `tests/tools_window_test.gd`; looked at in the top and side views |
| 4 | No whole-body mirror | Mirror the pose (Shift+M) and Mirror the scene (a left-handed copy in `_wip`) | `Body.mirror_pose`, `main._mirror_scene` | 43 poses mirror to 0.001 mm (a naive mirror misses by 1619 mm); the mirrored combo3 plays as the reflection to 0.00 mm over 281 frames and Check grades it the same |
| 5 | Copy / paste a pose | Was already there: save a pose, click it in the list | Poses panel | `tests/mirror_test.gd`: 0 mm round trip |
| 6 | Stepped preview for blocking | Animator tools > Stepped preview: each card's pose holds until the next arrives. View only, never saved; Check still grades the real motion | `Scene.stepped` | half-way into a move the body IS the previous card (0.000 mm) |
| 7 | Dead holds | Animator tools > Moving holds: in a hold the upper body drifts 8% toward the next card, feet planted. Saved with the scene; undoable | `Scene.moving_holds`, `HOLD_DRIFT` | 2.1 cm of a 57 cm move; feet 0 mm; seam 1.0 mm. 8% is taste, not data |
| 8 | Graph editor is a wall of curves | Speed graph (Y): three strips (weapon tip, hips, head), each its own scale, the cards as lines, click to scrub. Speed, not channels: what the eye sees | `main._draw_graph` | head peak on the graph sits at 3.03 s, where Check flags the lurch (3.13 s) |
| 9 | Retiming is painful | Was already there: poses are cards, timing is each card's move / hold | Scene row | |
| 10 | Can't see arcs, ghosts, in-betweens | Trails (T, Shift+T), onion skin (O), tween slider, BVH export: round 2 | `scripts/overlays.gd` | round 2 gates |

## Sources
- Gimbal: [polycount thread](https://polycount.com/discussion/comment/2646094)
- Spacing, holds, stepped: [Animation Mentor](https://www.animationmentor.com/?p=39005); [Taylor & Francis, stepped keys and moving holds](https://www.taylorfrancis.com/books/9780429443138/chapters/10.1201/9780429443138-8); [Modo spacing chart](https://learn.foundry.com/modo/Content/help/pages/animation/tools/spacing_chart.html)
- Mirror: [Bloop Animation, pose mirror](https://www.bloopanimation.com/lesson/pose-mirror-2)
- Foot sliding: [mocaponline, animation debugging](https://mocaponline.com/blogs/mocap-news/animation-debugging-troubleshooting); bars from Karunratanakul et al. 2023 as used in [OmniControl](https://arxiv.org/pdf/2310.08580) and [Flexible motion in-betweening](https://arxiv.org/pdf/2405.11126)
- Joint speed bar: shoulder internal rotation 4765.7 +- 771.9 deg/s, adult pitchers, K. R. Campbell, "Biomechanics of pitching", [ISBS proceedings, Table 2](https://ojs.ub.uni-konstanz.de/cpa/article/view/1673/1575) (read from the PDF)
