# Kine open gaps, 2026-11-07 (lane L66, audit)

Status as of base 9d633e2a. Counts come from ROADMAP_400.md ticks and the `(partial:` notes lane L66 added, and from
INNOVATIONS_STATUS.md. "Done" needs a file and a commit (or a test) that lane L66 could name. "Partial" means a file or
commit exists but the item's named bar or hook is missing. "Open" means grep found nothing for it. Doc-only pass: no tests
were run, so no PASS is claimed for any row.

## Counts per track (ROADMAP_400.md, 400 items)

| track | done | partial | open |
|---|---|---|---|
| A Mesh core | 16 | 0 | 4 |
| B MODEL | 25 | 0 | 5 |
| C SCULPT | 13 | 0 | 17 |
| D SURFACE UVs | 6 | 2 | 7 |
| E Materials + paint | 4 | 1 | 15 |
| F Retopo | 6 | 0 | 9 |
| G BODY | 5 | 3 | 17 |
| H Skinning | 6 | 1 | 18 |
| I Face | 2 | 4 | 14 |
| J Rigging | 4 | 8 | 13 |
| K Viewport + render | 12 | 2 | 16 |
| L Animation parity | 2 | 1 | 27 |
| M Physics + sim | 0 | 4 | 16 |
| N Pipeline | 3 | 2 | 20 |
| O Scripting | 1 | 1 | 13 |
| P Workflow + UX | 8 | 6 | 11 |
| Q Performance | 2 | 1 | 12 |
| R Hair, garments, props | 0 | 1 | 14 |
| **total** | **115** | **37** | **248** |

Before this pass the header said 106 merged. The 9 new ticks (C05, C06, H05, J06, J18, K04, K05, L06, Q08) each have a file and a commit. Star items stay at 29 of 119.

## Innovations (INNOVATIONS.md N001-N100, INNOVATIONS_STATUS.md)

| set | done | partial | open |
|---|---|---|---|
| N001-N100 (all rows now present) | 19 | 27 | 54 |

The 15 star items are as in INNOVATIONS_STATUS.md. ROADMAP.md I1-I50 was not re-counted here.

## The 15 biggest real open gaps for a body-aware fight / game tool

Ranked by user value. Each line: what is missing, then the evidence that it is missing.

1. **Two-body targets (N050)**: "my right fist to HIS chin at 0.6 s", solved on the partner's moving body. Evidence: no
   solver by that name; the two-body files (throw_fixtures, lock_fixtures) build fixed clips, not named targets.
2. **Ragdoll export with cone limits (N085)**: joint cone limits and masses to engine physical bones. Evidence: no
   engine writer for ragdolls; grep `physical.?bone|cone.?limit|physics_bone` over scripts/, native/src/, tools/ = 0 hits.
3. **Contact / foot-plant curves per clip for engine foot IK (N086)**: scripts/foot_plant.gd detects plants only.
   Evidence: grep `contact curve|planted curve` = 0 hits; no export of per-clip weights.
4. **Impact alignment at the contact frame (N034)**: a wrist bent on a punch, a locked knee on a kick. Evidence: grep
   `impact alignment` = 0 hits.
5. **Hit reaction picked by body region (N042)**: liver, chin, thigh pick different reactions. Evidence: anatomy tags
   exist (scripts/kmesh_anatomy.gd) but no reaction reads them; ragdoll.gd knockout is one generic fall.
6. **Lift and slam with real mass (N049)**: grep `slam` = 0 hits; no posture or back-load solve for a lifted body.
7. **Grab contracts (N051)**: a hand that stays on the partner's moving limb with a grip-book grip. Evidence: no grab
   contract; grep `grab contract` = 0; grip_book.gd covers the held prop only.
8. **Disarm truth (N045)**: lever on the wrist against the grip. Evidence: grep `disarm` hits are keyboard help text only.
9. **One vs many scheduling (N048)**: attackers scheduled by reach around the hero. Evidence: grep `one vs many|group
   fight` = 0 hits; crowd.gd copies a clip, it does not schedule attackers.
10. **Effort face from torque (I13)**: clench at peak torque. Evidence: grep `clench` = 0 hits; face.gd:25 keys an
    effort mix by hand on a card, nothing reads torque.
11. **Pain face from hit force (I14)**: pain expression picked by the hit's force and timing. Evidence: face.gd:23 keys
    pain by hand on a card; nothing reads the hit (grep `pain face|pain expression` in code = 0 hits).
12. **Engine sockets from anatomy (N089)**: weapon_r, back_sheath, hip_holster, head_fx placed on anatomy and exported.
    Evidence: grep `back_sheath|hip_holster|head_fx` = 0 hits; `weapon_r` only in turntable.gd.
13. **Runtime body-limit check for the engine (N090)**: an add-on that flags blends that break a limit in play.
    Evidence: no such script in scripts/ (ls shows none named runtime or check for engines).
14. **Contact deformation (H22)**: a fist or a foot flattens the soft tissue it presses. Evidence: grep `contact deform`
    = 0 hits; soft_body.gd is opt-in and under the mannequin only.
15. **Collision momentum sharing (N046)**: a shoulder charge shares momentum by mass and keys both bodies. Evidence: grep
    `tackle|body collision` finds one comment; no two-body impulse exists.

## Method and limits

- Attribution: a concatenated, line-indexed copy of every tracked file under scripts/, tests/ and native/src (3211 files),
  and the full git log (4283 commits), grepped per keyword. Keyword hits alone are not evidence; each tick was checked
  against the file header or the commit subject.
- Not checked: the 54 open N items beyond the keyword list, and the I1-I50 table. Open does not mean impossible.
