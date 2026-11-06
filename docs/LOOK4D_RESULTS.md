# LOOK4D results (21 blind Sonnet readers, 83 questions x 6 scenes, design v2.2)

Arms: A screenshot · B 2x2 filmstrip · C annotated 4D image · D numeric digest · CD = C+D · Z = question text only · Dscr = scrambled digest. Accuracy is pooled over 3 reps. CIs are a 95% cluster bootstrap over questions.

| arm | all | balanced | motion (S1-S4) | non-lookup | S6 null |
|---|---|---|---|---|---|
| A screenshot | 0.655 | 0.564 | 0.560 | 0.691 | 0.923 |
| B filmstrip | 0.590 | 0.551 | 0.607 | 0.610 | 0.744 |
| C 4D image | 0.892 | 0.838 | 0.821 | 0.862 | 0.949 |
| D digest | **0.968** | **0.992** | **0.917** | **0.976** | 0.974 |
| C+D | 0.960 | 0.970 | 0.881 | 0.943 | 1.000 |
| Z no stimulus | 0.546 | 0.493 | 0.643 | 0.553 | 0.590 |
| Dscr scrambled | 0.514 | 0.356 | 0.583 | 0.561 | 0.641 |

## Bars (as registered)
- **P1, C beats B on motion by at least 10 points:** PASS. +21.4 [+2.4, +40.5].
- **P2, C+D at least D on every type, and +5 on spatial:** FAIL.
  - Spatial is -3.3 [-11.4, +2.4].
  - On predict, C+D is -17: two questions were wrong in all 3 reps (s1_engine q13, s2_arm q15), where the picture overrode the digest. D got them right.
  - Under the registered rule, this means **ship D-only**.
- **No-harm, C+D within 5 of D:** PASS (-0.8).
- **Null, S6 C+D within 10 of A:** PASS (+7.7).
- **Scrambled, Dscr within 10 of Z:** PASS (-3.2). **D beats Dscr by at least 20:** PASS (+45.4). The instrument is reading content.
- **Token bar, D cheaper than A:** FAIL, as reported earlier. The median D is 513 tokens against 442 for A, and it is above A in 3 of 6 scenes.
- **Balanced accuracy** reverses no verdict.
- **Reported only:** C+D minus A on motion is +32.1 [+9.5, +53.6].

## Readings
1. A single screenshot is close to guessing on motion: A 0.56 against Z 0.64. On balanced accuracy over all questions it is barely above the text-only arm (0.56 against 0.49).
2. A filmstrip at equal pixels is worse than one screenshot overall (0.59 against 0.66), because the frames are 4x smaller.
3. The annotated 4D image turns pixels into usable perception: 0.66 rises to 0.89 at the same pixel budget. Numbered marks with a legend, arrows and ghost trails are what work. Colour-as-number is not used.
4. Exact numbers win outright (0.97). Adding the picture does not help, and can mislead on prediction.
5. Caveats:
   - The reps are near-duplicates: a duplicate Dscr_r1 run agreed 97.6% with the first. The bootstrap is therefore over questions, not readers.
   - There are only 28 motion questions on S1-S4.
   - All readers were one model, Sonnet.
   - Accidental duplicate: one extra Dscr_r1 run was launched by mistake. Its first answers were frozen before grading, and the second run is unused.

## Recommendation
- The agent route should be D, the digest. The image should be C, used only when a human or an agent needs layout or a visual check. The plain screenshot should not be used as an agent's eyes.
- Next: make D cheaper than A by dropping static parts to names only and sending changed fields only (a delta per frame).

## LOOK4D-2 verdict (11-06, 10 fresh blind Sonnet readers, 2 reps per arm, graded against the registration in LOOK4D_DESIGN.md)

Primary set: 59 of 66 questions. CIs are a cluster bootstrap over questions (4000 resamples).

| Arm | Primary | Packet tokens |
|---|---|---|
| L012 (levels 0+1+2) | 1.000 | ~58k |
| L01 (levels 0+1) | 0.873 | ~16k |
| D1 (v1 digest) | 0.856 | ~23k |
| Z (no scene data) | 0.754 | ~6k |
| L012scr (scrambled labels) | 0.669 | ~58k |

| Bar | Result | Verdict |
|---|---|---|
| H1 L012 − D1 ≥ +15 | +14.4 [+6.8, +23.7] | **FAIL by 0.6 points** (registered on the point; not moved) |
| H2 L01 ≥ D1 − 5 | +1.7 [−1.7, +5.1] | PASS: level 1 is no worse than D at ~70% of its tokens |
| C1 L012scr within 10 of Z | −8.5 [−21.2, +5.1] | PASS |
| C2 L012 − L012scr ≥ +20 | +33.1 [+22.9, +44.1] | PASS: the labels carry the gain, not packet length |

Per type (primary): L012 is 1.00 on every type. D1 is weakest on balance (0.42) and joint_limit (0.81). Z guesses 0.67–1.00 on several types, so these questions have a high guess floor: Z is 75%, not 50%.

Format-limit questions (7 ttc): L012 also scored 1.00 on them, although `answer_from_levels` returns None. Readers worked the answers out from the level-2 gap list plus level-1 velocities. The registered exclusion stands, and the result is reported here only.

**What this means:**
- Level 2 answers every detail question correctly.
- The registered margin over D was missed by 0.6 points, mainly because D was already at 86% and the guess floor is high.
- Level 1 is a safe, cheaper default.
- Ship L01 as the default. Use level 2 on demand, per part, through the MCP look4d tool; that is how it is wired, so a reader pays its cost only for the parts it asks about.
- The fix candidate (a pair gap and ttc in level 2) stays open.
