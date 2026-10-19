# Stunt load report: the bars and where they come from

Code: `scripts/stunt_load.gd` (opened by "Check: stunt load report"; never part of the default Check). ROADMAP 24.
Every finding is a NOTE, never MUST FIX. Each number is either **cited** (a source named here, with its status) or
**ours** (a choice of this code, stated as such). Status key as in HUMAN_LIMITS.md: **read** = in an abstract or full text
that was opened; **secondary** = quoted by another paper, the primary not read; **not verified** = the brief's cite, no source
text found in this session.

## 1. Landing load (LANDING LOAD)

Model (ours): the centre of mass (COM) touches down with speed v, taken from the last airborne frame (60 fps) plus the
frame's gravity correction g/(2 fps). It stops over a distance d (the drop from touchdown to the lowest COM point before it
rises). Mean stopping deceleration a = v^2 / (2d) (constant-deceleration model). Peak vertical ground reaction, in body
weights (BW) = 1 + a/g. Stops under 5 mm (ours) are below one 60 fps frame and are not graded.

| bar | value | source | status |
|---|---|---|---|
| peak vGRF in a drop landing from about 0.3-0.5 m | **3-7 BW** | Dufek & Bates 1991 (Med Sci Sports Exerc) and McNitt-Gray 1993 (J Biomech), as the brief cites them | **not verified**: the search found the papers' names quoted by others, not their numbers. A 1991-era secondary quote gives 3.5-7 BW (Valiant & Cavanagh 1985). Treat 3-7 BW as the brief's range until the primaries are read |
| a fall's impact speed | sqrt(2 g h) | free fall, physics | exact (used by the test) |

Expected values for the synthetic drop (test `tests/stunt_load_test.gd`, 0.492 m realised drop, impact 3.107 m/s):
stiff knees (d = 3 cm) = 16.4 g = 17.4 BW, **above** the bar; soft bent knees (d = 10 cm) = 4.9 g = 5.9 BW, inside it.

## 2. Knee valgus at landing (KNEE VALGUS)

Measured: frontal-plane valgus = 180 deg minus the included angle at the knee (hip-knee and ankle-knee lines, x-y plane),
positive when the knee is medial, read over the first 0.1 s of the landing (ours window).

| bar | value | source | status |
|---|---|---|---|
| knee valgus at landing | **10 deg** | **ours**: a provisional threshold. Hewett, Myer & Ford 2005 (AJSM 33(4):492-501) is the study of valgus loading and ACL risk in 205 female athletes, with 78% sensitivity and 73% specificity for knee abduction moment (abstract read). No numeric valgus cutoff was found in the abstract, so none is used | the paper is read; the cutoff is not. Do not cite 10 deg as Hewett's |

## 3. Spine (SPINE COMPRESS, SPINE FLEX+TWIST)

Compression model (ours, static, not validated): L5/S1 force = m_UB g (|forward offset of the upper body| / lever + cos(flexion)),
with the upper body at 0.5 of body mass (ours), the lever 0.05 m (ours, the erector spinae's arm), flexion the trunk's
forward lean (neck minus pelvis, deg).

| bar | value | source | status |
|---|---|---|---|
| L5/S1 compression action limit | **3400 N** | Waters, Putz-Anderson, Garg & Fine 1993 (Ergonomics 36(7):749-776), the revised NIOSH equation's limit | **secondary**: the 3.4 kN figure was confirmed through a 2015 critique (Int J Ind Ergon) that cites it; the primary was not read. The 2015 paper also says the RWL can give loads above the limit with moderate-to-large forward flexion |
| maximum permissible compression | not used | Waters 1993 (6400 N) | **not verified**: not read, so it is not used |
| combined flexion + twist | flexion **45 deg** and twist **20 deg** together | **ours**. McGill's back-injury work calls combined flexion and twist the load to avoid (the qualitative claim, primary not read); the numbers are ours | ours |

Twist = the angle between the hip line and the shoulder line, seen from above (0 = square).

## 4. Neck (NECK FLEX SPEED)

Measured: the head's forward flexion on the neck (head joint minus neck joint, deg), peak of the rate over the scene (deg/s).

| bar | value | source | status |
|---|---|---|---|
| neck flexion speed | **200 deg/s** | **ours**. Searched for a fall or whiplash volunteer peak: the sled and fall studies found report rear-impact angles without a usable deg/s peak (rear-end sled test at 0.6 m/s, five male volunteers, values not in the abstract) | no source. Provisional |

Note for Nick's scenes: the bat swing in `combo3.json` reaches 882 deg/s of head flexion at 3.03 s. That is a bar-exceeding
value against an ours-bar, not a checked limit. It is reported as a NOTE and is not a finding about injury.

## 5. What is not done

- No landing bar is verified from a primary. The 3-7 BW range is the brief's, unchecked.
- The valgus, flexion+twist and neck bars are ours. None is a published threshold.
- Scenes are kinematic: a landing's load is what the keyed timing implies at 60 fps. A stop under one frame is not graded.
- The default Check does not include this report; it stays a separate, opt-in NOTE list.
