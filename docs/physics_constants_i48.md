# I48 Real-mocap pose check: source, licence, numbers

## Licence (checked 2026-10-20 on http://mocap.cs.cmu.edu/ and https://mocap.cs.cmu.edu/faqs.php)
Home page, verbatim:
- "This dataset of motions is free for all uses."
- "This data is free for use in research projects. You may include this data in commercially-sold products, but you may not resell this data directly, even in converted form."
- "If you publish results obtained using this data, we would appreciate it if you would send the citation to your published paper to jkh+mocap@cs.cmu.edu, and also would add this text to your acknowledgments section: The data used in this project was obtained from mocap.cs.cmu.edu. The database was created with funding from NSF EIA-0196217."
- "Please don't crawl this database!" (so: one zip listing, 44 clips fetched by ranged read of the file the FAQ offers, 4 search pages)
FAQ: "May I have a copy of the entire database? Sure! Please don't crawl this database for all motions. Here is a zipfile of all asf's and amc's."

Decision: the use here (a statistic computed from the data, inside a product; 300 quantised poses as reference; no raw file shipped, nothing resold)
is inside those terms. The "converted form" clause forbids reselling the data; a derived statistic and 300 rounded poses of 23072 frames is
not the data. The acknowledgement text is in data_gen/README.md and Help. Kine's own rules: AMASS, LAFAN1, SMPL are never used; no GPL code
(the asf/amc to bvh converter is our own, written from the Acclaim format description; the parser and retarget are the app's).

## Pipeline (all offline; raw files stay in the job tmp folder, never committed)
1. 44 clips (asf/amc) of subjects 02, 07, 08, 10, 11, 13, 14, 15, 16, 17, 35, 56, 74, 75, 76, 79, 80, 87, 90, 91, 135, 141, 143.
2. Own converter to BVH, every 4th frame (30 fps), lengths x (1/0.45)*2.54/100 = 0.056444 m per unit (CMU FAQ: "multiplied by this scale to convert to meters").
   Local rotation = C M C^-1 (C the bone's axis rotation, M the dof rotation); checked against Kine's human range on a walk (07_01): knee 0 to 68 deg with
   side/twist ~0; the other convention C^-1 M C gave knee side 23 / twist 50 deg, so it was refused.
3. tools/i48_dump.gd: AnimImport.load_source / map_bones / retarget onto Kine (22 of 22 main bones matched), bend/side/twist per frame -> 23072 frames.
4. tools/i48_build.py: occupancy tables + density quantiles + 300 medoid poses -> data_gen/mocap_stat.json (251 KB).

## Held-out check (the statistic built without 7 clips: 02_01, 11_01, 13_01, 143_12, 15_13, 74_03, 90_05; 3524 frames)
| flagged below | share of the unseen frames |
|---|---|
| 1% | 6.2% |
| 2% | 12.1% |
| 5% | 23.1% |
The line is therefore 1%: about 1 in 16 frames of a clip the statistic never saw is flagged (acrobatics 90_05 and other unseen activities account for much of it).
The line is a judgement of what is worth looking at, not a physical limit.

## Limits
- The corpus is walking, boxing, kicks, punches, martial-arts walks and a few jumps: a pose from a sport it lacks (gymnastics, grappling on the floor) is flagged as "not seen", which is not "impossible".
- Left and right are pooled (right mirrored onto left by negating twist, as Body.mirror_side does).
- Subjects are adults of one lab's capture suit and skeleton calibration; the retarget to Kine's proportions keeps angles, not positions.
- CMU hand/toe channels are noisy (their note), so only the 21 body joints (no fingers) are compared, and the nearest-pose search leaves the pelvis out (it carries the clip's facing).
