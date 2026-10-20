# Physics constants: measured values and where Kine uses them

Rule: one row per constant, value taken from a source that was opened (job gt2, 2026-10-20). UNVERIFIED = no source opened; the code keeps its old value and the UI says "(unverified)".

## Weapons, impact, strength (gt2)

| Constant | Value | Units | Used in | Source | Quote / cell |
|---|---|---|---|---|---|
| WeaponTorque.WRIST_MAX | 14.9 | N m | scripts/weapon_torque.gd (I30 ceiling, wrist) | "Isokinetic Strength Profile of the Wrist Muscles: A Study of Healthy Women and Men", PMC12551099 (2025), Table 1; 20 men, 20 women, dominant wrist, Biodex, 90 deg/s, peak moment | radial deviation, concentric, men "14.9 ± 3.4" |
| (same table, other cells, men / women, concentric) | flexion 17.0 ± 4.1 / 12.1 ± 2.4; extension 8.8 ± 1.7 / 5.3 ± 1.1; ulnar dev. 26.5 ± 6.6 / 20.0 ± 5.3; radial dev. 14.9 ± 3.4 / 8.5 ± 3.0 (eccentric: 20.0, 11.5, 30.3, 18.9 men) | N m | - | same | "Angular speed was set at 90°/s for all tests." |
| WeaponTorque.SHOULDER_MAX | 77.2 (SD 13.8) | N m | scripts/weapon_torque.gd (I30 ceiling, shoulder) | Aronis, Kurz, Wimmer, Hackl, Angeli, Gfohler, "Maximum Shoulder Torque and Muscle Activation During Standing Arm Flexion", J Funct Morphol Kinesiol 11(1):20 (2026), Table 1; 14 healthy men, age 37.1 ± 12.6, isometric flexion, standing | 90 deg elevation "77.24" (SD "13.81"); 160 deg "43.19" |
| K_WRIST | 19.5 | N m/rad (0.34 N m/deg) | scripts/weapon_rebound.gd (I40 wrist spring) | Milner, Cloutier, Leger, Franklin, "Inability to activate muscles maximally during cocontraction and the effect on joint stiffness", Exp Brain Res 107:293 (1995); 10 subjects (4 women, 6 men) 21-38 y, experiment 1; wrist stiffness 150-200 ms after a 3 deg displacement | "stiffness when stiffening the wrist without load was only 0.34 Nm/deg" (maximal voluntary stiffening); "0.56 Nm/deg" at the limit of stability (= 32 N m/rad); passive 0.07 N m/deg (= 4.0 N m/rad); relaxed wrist about 3 N m/rad (De Serres & Milner 1991, quoted in Milner 2002 Exp Brain Res 143:406) |
| E (steel weapon on steel weapon) | 0.46 | - | scripts/weapon_rebound.gd E_STEEL | Ciornei & Alaci, "The effects of geometry and material properties on the coefficient of restitution", Ann. Univ. Oradea, Fasc. Management and Technological Engineering, issue 3 (2014), Table I; steel ball (12.7 and 17.45 mm) dropped 0.28-1.27 m onto a steel prism | steel prism case 1 "0.436 0.480 0.490 0.506 0.529", case 2 "0.397 0.432 0.427 0.425 0.483"; mean of the ten = 0.46; falls with speed |
| E (aluminium prop) | 0.28 | - | scripts/weapon_rebound.gd E_ALUMINIUM | same, Table I, steel ball on aluminium prism | case 1 "0.284 0.316 0.285 0.353 0.359", case 2 "0.209 0.249 0.193 0.268 0.286"; mean of the ten = 0.28 |
| E (wood prop) | 0.5 UNVERIFIED | - | scripts/weapon_rebound.gd E_WOOD | none opened (a thin abstract gives wood-on-wood 0.49: not opened) | old heuristic kept |
| TimingCoach.V_PEAK_HI | 11.95 +- 1.84 | m/s | scripts/timing_coach.gd, style_dial.gd | Stanley, Thomson, Smith, Lamb, "Biomechanical characteristics of amateur boxers", Int J Perf Anal Sport 18:835 (2018); 15 male amateur boxers, 3D mocap, bag | "lead hook exhibited the greatest peak fist velocity (11.95 ± 1.84 m/s)" (abstract, via repository record) |
| TimingCoach.V_PEAK_LO | 7.1 +- 0.5 | m/s | scripts/timing_coach.gd | Sensors 2025, 25(11):3270 (PMC12157019), section 3.2; 21 elite male MMA fighters | "mean punch velocities were 8.4 ± 0.6 m/s for straight punches and 7.1 ± 0.5 m/s for swing punches" - note: this is a MEAN fist speed over the final 10 ms before impact, not a peak (the code comment called it a peak; corrected) |
| Fatigue.DECLINE_REF | 10.3 % | - | scripts/fatigue.gd, exertion.gd | same Sensors 2025 paper, fatigued speeds 7.5 +- 0.7 (straight), 6.4 +- 0.6 (swing) | the paper gives no percentage; derived: (8.4-7.5)/8.4 = 10.7 %, (7.1-6.4)/7.1 = 9.9 %, mean 10.3 % |

Notes
- The wrist figures are dynamic (isokinetic 90 deg/s) peak moments, which is the right ceiling for a swing (a moving muscle gives less than its isometric maximum). Adult men are used because the Kine body is a 75 kg adult male; women's cells are 0.5-0.8 of men's (radial deviation 8.5 vs 14.9).
- WRIST_MAX takes radial deviation: a weapon held in line with the forearm swings by deviating the wrist, and radial is the weaker of the two deviation directions (ulnar 26.5). Flexion 17.0, extension 8.8 (the swing torque is a magnitude, its direction is not split).
- SHOULDER_MAX is the best angle (90 deg elevation) of a flexion curve; at 160 deg the same men give 43 N m. Abduction in N m was not found (Bradley & Pierpoint 2023 give N/kg only).
- The steel COR is a small ball on a flat prism, the only measured steel/aluminium COR with a table that was opened. No bat-on-bat or blade-on-blade measurement was found. The ball-on-bat COR (Nathan) is a different pair and was not used.
- Kine props (Body.KINDS): metal_bat = aluminium, staff = wood, long_hammer / long_axe / dagger = steel.
# Measured physics constants (gt3: balance, stepping, braking, falls, reaction)

| name | value | used at | source | quote / cell |
|---|---|---|---|---|
| BRACE_BW, STEP_BW (peak horizontal braking GRF) | 1.6 BW (was 1.5 / 3.0) | scripts/momentum.gd | Dos'Santos et al., table in Harper et al. 2022 Sports Med 52, "Biomechanical and neuromuscular performance requirements of horizontal deceleration" (PMC9474351), 27 male multi-sport players | "PFC peak horizontal GRF (BW): 90 = 1.60, 180 = 1.54" |
| braking-step horizontal GRF (alt.) | 16.7 N/kg fast (1.70 BW), 12.9 N/kg slow (1.31 BW) | context | same table | "Braking horizontal GRF (N/kg): fast = 16.7, slow = 12.9" |
| rapid-deceleration total GRF | 40-60 N/kg (~4-6 BW) | context (3 BW "landing" bar was resultant, not horizontal) | Verheul et al. in same table, 15 team-sport players | "Peak total GRF ~ 40-60 N/kg" |
| YAW_ARM 0.25 m, TILT_ARM 0.15 m | UNVERIFIED | scripts/momentum.gd | none opened | |
| first-step latency | 0.25 +- 0.04 s backward; 0.36-0.42 s forward | scripts/recovery.gd (context) | Mansfield et al. 2015 Front Aging Neurosci 7:201, Table 3, young adults, leg length 91 +- 4 cm | "Step latency (s) HY 0.25 +- 0.04" |
| first-step length | 0.31 +- 0.06 m backward; 0.27-0.33 m forward (at step threshold) | context | same | "Step length (m) HY 0.31 +- 0.06" |
| STEP_T 0.25 s (swing duration) | UNVERIFIED | scripts/recovery.gd | latency reported, swing duration not | |
| MAX_STEP_LEG 0.8 | UNVERIFIED | scripts/recovery.gd | Kluft 2017 / Bieryla 2015 measure it; numbers not in open text | |
| breakfall TUCK_MIN 25, ELBOW_OK 30, SPEED_OK 2.5 | UNVERIFIED | scripts/breakfall.gd | none opened | |
| contact order (ushiro ukemi) | hand, forearm and trunk hit before head lowest | scripts/breakfall.gd | Hashimoto et al. via Lockhart 2022 review (PMC8998643) | "impact of the hand, forearm and trunk hitting the tatami" |
| forward fall arm rule | forearm/hand must be first contact, else ARM = fail | scripts/breakfall.gd | secondary (lab forward falls, >90 % on hands; Kodokan mae ukemi); no mae-ukemi measurement found | UNVERIFIED as to numbers |
| REACT (simple visual RT) | 0.29 s (was 0.20) | scripts/counter.gd | Liu, See, Chang et al. 2018 Arch Budo 14 | "292.33 +-45.4 ms" elite karate, n=28; novice 306, non-athletes 335 |
| MV 0.12 s | UNVERIFIED | scripts/counter.gd | | |
# Physics constants: where each number comes from

One row per constant: value, units, where it is used, source, and the table cell. A value without a source I opened is marked UNVERIFIED.

## Body segment parameters (gt1, 2026-10-20)

Source for every row below: de Leva P. (1996), "Adjustments to Zatsiorsky-Seluyanov's segment inertia parameters", J Biomech 29(9):1223-1230,
Table 4 (p. 228). Opened as the open PDF https://ebm.ufabc.edu.br/wp-content/uploads/2013/12/Leva-1996.pdf and read from the page image.
Population: Zatsiorsky-Seluyanov's samples of college-aged Caucasians, 100 men (73.0 kg, 1.741 m) and 15 women (61.9 kg, 1.735 m; the table
prints "1.735" as 173.5 m). The table gives means only (no SD). Masses are % of body mass; COM and radii are % of the segment length between
the endpoints named. Single table in code: `Proportions.DE_LEVA` (scripts/proportions.gd), helpers `Proportions.kperp` (rms of sagittal and
transverse r) and `Proportions.klong`. Used by: `HitReaction.pieces` (and through it Force view, momentum, ragdoll, reaction direction, SpinCheck),
`HitPhysics` arm pieces, `HumanLimits.kt`, `Proportions.com / masses`.

Endpoints used (the skeleton has these landmarks): head VERT -> CERV (alternative row), trunk CERV -> MIDH (alternative row), upper arm SJC -> EJC,
forearm EJC -> WJC, hand WJC -> MET3, thigh HJC -> KJC, shank KJC -> LMAL, foot HEEL -> TTIP. HumanLimits' fingertip hand uses the WJC -> DAC3 row.

| segment | sex | mass % | COM % | sagittal r % | transverse r % | longitudinal r % | table row |
|---|---|---|---|---|---|---|---|
| head (VERT-CERV) | M / F | 6.94 / 6.68 | 50.02 / 48.41 | 30.3 / 27.1 | 31.5 / 29.5 | 26.1 / 26.1 | "Head* VERT CERV" |
| trunk (CERV-MIDH) | M / F | 43.46 / 42.57 | 51.38 / 49.64 | 32.8 / 30.7 | 30.6 / 29.2 | 16.9 / 14.7 | "Trunk CERV MIDH" |
| upper arm | M / F | 2.71 / 2.55 | 57.72 / 57.54 | 28.5 / 27.8 | 26.9 / 26.0 | 15.8 / 14.8 | "Upper arm SJC EJC" |
| forearm | M / F | 1.62 / 1.38 | 45.74 / 45.59 | 27.6 / 26.1 | 26.5 / 25.7 | 12.1 / 9.4 | "Forearm EJC WJC" |
| hand (WJC-MET3) | M / F | 0.61 / 0.56 | 79.00 / 74.74 | 62.8 / 53.1 | 51.3 / 45.4 | 40.1 / 33.5 | "Hand WJC MET3" |
| thigh | M / F | 14.16 / 14.78 | 40.95 / 36.12 | 32.9 / 36.9 | 32.9 / 36.4 | 14.9 / 16.2 | "Thigh HJC KJC" |
| shank | M / F | 4.33 / 4.81 | 44.59 / 44.16 | 25.5 / 27.1 | 24.9 / 26.7 | 10.3 / 9.3 | "Shank KJC LMAL" |
| foot (HEEL-TTIP) | M / F | 1.37 / 1.29 | 44.15 / 40.14 | 25.7 / 29.9 | 24.5 / 27.9 | 12.4 / 13.9 | "Foot* HEEL TTIP" |
| hand (WJC-DAC3) | M / F | 0.61 / 0.56 | 36.91 / 35.02 | 28.5 / 24.1 | 23.3 / 20.6 | 18.2 / 15.2 | "Hand* STYL DAC3" is the unadjusted row; the adjusted "Hand WJC DAC3" row is 28.8 / 24.4, 23.5 / 20.8, 18.4 / 15.4, which is what `DE_LEVA_HAND_DAC3` holds |

Replaced values: `HitReaction.K` (head .495, trunk .503, upper arm .322, forearm .303, hand .297, thigh .323, shank .302, foot .475) were
"FROM MEMORY" and are Dempster-type radii about the COM that do not match de Leva's table (de Leva upper arm: .277 rms, forearm .271, hand .574,
thigh .329, foot .251). `SpinCheck.RG` was also from memory (hand .570 vs .574 table male, head .309 vs .309 rms, others within .01 but female
values were missing). `HitPhysics` used 0.3 L for every arm piece and a fixed 0.0004 kg m^2/kg for the hand. All now read the table.

UNVERIFIED (not replaced, no source opened): the weapon masses (`HitReaction.WEAPON_KG`, estimates), the hit-reaction spring constants
(`WN`, `ZETA`, `CHAIN`, `WN_P`, `ZETA_P`), `SpinCheck` BAND / FREE_DEG / PIVOT / A_LO / A_HI (heuristics, stated as mine in the code).
