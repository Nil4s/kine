# Twinning (ROADMAP 19)

## What it is, and the source

Twinning is the animator's word for two halves of a pose, or two limbs, doing the same thing at the same time, mirrored
or in step, so the motion reads flat. Animation Mentor's write-up describes it as the lack of correct overlap and
contrast, with two parts: twinned posing (a pose that looks mirrored down the middle) and twinned timing (both halves
move with identical timing). It also says that twinning is occasionally wanted on purpose.
Source: Animation Mentor, https://animationmentor.com/?p=4836 (read through a web search excerpt, not the full page).
Richard Williams' book was named in the brief but could not be checked here, so it is not cited.

The walking exclusion rests on the gait source already in `scripts/rulebook.gd` (GAIT): at walking speeds the arms are
out of phase with each other and 1:1 with the legs (Kubo et al. 2004, PMID 15351887). Legs alternate in a walk, so a
walk's legs do not mirror-twin and the rule does not need a walk switch.

## The measure

- Mirror: the one `Body.mirror_pose` uses. A left joint takes its twin's rotation reflected, (x, y, z, w) -> (x, -y, -z, w).
  The difference of a pair is `ang_deg(compose(L, angles_L), reflect(compose(R, angles_R)))`, averaged over the pair's
  two joints (upper arm and lower arm; thigh and calf).
- Moving: the slower side's mean joint speed over the pair, in deg/s, must exceed S.
- A frame is flagged when its centred 0.3 s mean difference is under D and the frame is moving. A run of at least 0.3 s
  of flagged frames (18 frames at 60 fps) is a finding: "arms twin from t0 to t1 s: offset one side by 2-4 frames or
  change its pose".

## Thresholds (ours, not sourced)

- D = 10 deg, the mean mirror difference that counts as twins. Chosen as a small angle: a joint that differs from its
  mirror by less than about a tenth of a turn across 0.3 s is twinned in the eye.
- S = 60 deg/s, the speed that counts as moving. Chosen above a slow sway, below a real arm swing (the rulebook's
  swings run 300 deg/s and more).

## Calibration on Nick's scenes (scenes/*.json, read only)

At D = 10 and S = 60 nothing fires on any scene. The lowest 0.3 s mirror difference while both sides move is:
arms 28-51 deg on every scene that moves its arms (thrust 28 is the closest). Legs reach about 3 deg in combo3,
hit_react and swing_fore, but only in frames too short to form a 0.3 s run (under 20 flagged frames).
Sensitivity (one run each): at D = 15 and at D = 20 with S = 60, still nothing; at D = 20 with S = 30 only combo3's
legs fire for 0.37 s (3.90-4.27 s). The arm bar is far from the scenes' closest arm approach, so the rule is quiet on
them by design, not by a tuned gap.

## Fix

"Fix: offset the picked side by 3 frames" moves the picked side's upper and lower arm (or thigh and calf) later by
3 frames over each flagged range. A joint with no part keys is baked over the whole scene at the frame rate first
(a part key replaces the card blend for its joint); a joint with keys has its window baked. The window's baked angles
move later by 3 frames, the keys in the 3 frames after the window go, and the caller takes one undo snapshot.
