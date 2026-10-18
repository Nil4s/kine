# How people hold a handle (round 47, UPGRADES_300 #338)

Nick 10-18: "a standard method for hands and grips on weapons depending on how it's held, because the circumference
of a grip is usually the same ... so we never have this issue with hands again"; "a magnetic version for hands".
Read 10-18 through PubMed (abstracts; numbers below are the papers' own, quoted where used).

## The sources and what each gives us

| Source | What it measured | What Poser takes from it |
|---|---|---|
| Napier 1956, J Bone Joint Surg Br 38-B:902 ([DOI](https://doi.org/10.1302/0301-620X.38B4.902)) | the classification: POWER grip (the object clamped between fingers and palm, the thumb as a buttress) vs PRECISION grip (held between finger pads and thumb) | the grip TYPES: a bat, axe, staff, sword are power grips; a flipped dagger, a bow's string hand are precision |
| Buchholz & Armstrong 1992, J Biomech 25:149 ([DOI](https://doi.org/10.1016/0021-9290(92)90272-3)) | a hand model that predicts a power grasp by "wrapping" each finger round the object until its segments touch; two types: transverse volar (thumb abducted, for power) and diagonal volar (thumb adducted, "an element of precision"); validated on 6 people gripping cylinders: predicted flexion "5.3% or 2.8 deg +/- 12.2 deg larger than the measured angles"; good for MCP and PIP, DIP more variable | THE METHOD: the solver wraps, segment by segment, until contact. Their error band (12 deg SD) is the honest size of our bar against a real hand |
| Gulke et al. 2010, J Hand Surg Am 35:797 ([DOI](https://doi.org/10.1016/j.jhsa.2009.12.031)) | 48 people, 5 cylinder sizes, a sensor glove: during the grip "the mean flexion of the proximal interphalangeal joints was 43 degrees, that of the metacarpophalangeal joints was 28 degrees, and that of the distal interphalangeal joints was 26 degrees"; PIP flexion significantly greater than MCP and DIP | the ORDER: the middle joint bends most; a bar on the solver's mean over sizes |
| Lee & Rim 1991, J Biomed Eng 13:152 ([DOI](https://doi.org/10.1016/0141-5425(91)90062-c)) | 4 people, 5 cylinder sizes: "flexion angles at the MCP and PIP joints gradually increase as cylinder diameter decreases, but ... at the DIP joint the angle remains constant" | the TREND bar: thinner handle, more MCP and PIP flexion |
| Lee & Jung 2015, Ergonomics 59:890 ([DOI](https://doi.org/10.1080/00140139.2015.1108458)) | 10 people, cylinders 2, 4, 6, 8 cm: "the joint angle increased linearly as the object size decreased"; size mattered more than shape or weight | the sweep range for the trend bar (20-80 mm) |
| Wu et al. 2009, Med Eng Phys 31:1214 ([DOI](https://doi.org/10.1016/j.medengphy.2009.07.018)) | a finger model on measured grip data: DIP and PIP joint moments "reach their maximums at a cylinder diameter of about 31mm" | context: handles are made near 30-35 mm on purpose |
| Maleki-Ghahfarokhi et al. 2022, Ergonomics 66:1015 ([DOI](https://doi.org/10.1080/00140139.2022.2122587)) | two-handed T-handles, 20 people: of 3-5 cm diameters "the 3 cm diameter handle was associated with better usability and comfort"; torque higher with the hands 1.0-1.5 shoulder spans apart | context for two-handed weapons: the hands far apart on a long haft is how people get leverage (Nick's axe edit put them 0.7-0.9 m apart) |
| Negi et al. 2025, Work 82:1110 ([DOI](https://doi.org/10.1177/10519815251353464)) | 200 farm workers' hands: tool handles designed at 32-34.1 mm | context: a real tool handle diameter |

Our weapons' handles (Body.KINDS r_handle): bat, staff 32 mm; long hammer, long axe 34 mm; dagger 26 mm. All inside
the range the papers measured.

## The method (from Buchholz & Armstrong, in Poser's joints)

1. The hand is placed on the handle as today (the grip file's local_pos / local_rot: the palm against it).
2. Each long finger WRAPS: the MCP bends until the proximal phalanx touches the handle (or its limit), then the PIP
   until the middle phalanx touches, then the DIP until the tip touches. Touch = the capsules' surfaces within 1 mm.
3. The thumb by type: POWER (transverse) wraps the other way round the handle; DIAGONAL lies along it.
4. A thinner handle needs more turn before each segment touches, so the trend of Lee & Rim falls out of the method
   instead of being typed in.

## What it must reproduce

- Nick's own hand-fitted grips (data/grips/metal_bat.json, staff.json; his long-axe hands, scenes/axe_strike_pose.json)
  within the size of the model's own real-hand error (Buchholz: 12 deg SD), reported joint by joint.
