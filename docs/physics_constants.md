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
