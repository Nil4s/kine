# data_gen/mocap_stat.json  (ROADMAP I48, real-mocap pose check)

A small STATISTIC derived from real motion capture. No raw motion-capture data and no BVH/ASF/AMC file is stored here.

Source: Carnegie Mellon University Graphics Lab Motion Capture Database, http://mocap.cs.cmu.edu/ . Its home page says:
"This dataset of motions is free for all uses." and "You may include this data in commercially-sold products, but you may not
resell this data directly, even in converted form." Full quotes and the checks: docs/physics_constants_i48.md.
Credit (the page asks for it when results are published): "The data used in this project was obtained from mocap.cs.cmu.edu.
The database was created with funding from NSF EIA-0196217."

Not used, by Kine's licence rules: AMASS, LAFAN1, SMPL.

What is in the file (all made by tools/i48_dump.gd then tools/i48_build.py):
- `groups`: for shoulder + elbow (arm), hip + knee (leg) and the spine chain: a smoothed occupancy table of 20-degree cells over
  Kine's own joint angles (counts blurred over neighbouring cells), and 200 quantiles of the density real frames have there.
- `poses`: 300 representative real poses (k-means medoids over 21 joints, angles rounded to 2 degrees) for the "nearest real pose" ghost.
  These are 300 quantised poses out of 23072 frames, not a copy of the database.
Built from 44 clips (subjects 02, 07, 08, 10, 11, 13, 14, 15, 16, 17, 35, 56, 74, 75, 76, 79, 80, 87, 90, 91, 135, 141, 143: walking,
boxing, kicks, punches, martial-arts walks, jumps), taken from the project's own asf/amc zip (allasfamc.zip, offered by the FAQ),
converted to BVH by our own converter and retargeted onto Kine's skeleton by the app's AnimImport, at 30 frames per second.
Rebuild: see the header of tools/i48_dump.gd and tools/i48_build.py.
