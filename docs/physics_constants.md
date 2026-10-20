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
