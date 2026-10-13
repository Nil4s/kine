# Poser - spec (Nick 2026-10-12)

Nick: "one manekin body i can interact, move the joints, and plan a movement set ... limits of the body itself, so it
must have collision to itself ... hands can carry one stick holding it straight ... record and build a small file we
can access and add other steps ... carry a math code so you can understand how all of it is positioned, no more guess".
Decided with Nick: a separate Godot project (cheap, free of the game), posing both ways (drag a part + exact sliders),
a joint STOPS at its limit (no breaking it), a real-looking body (not capsules).

## Parts
- `scripts/body.gd` - the math only (MATH.md): angles -> rotations -> positions, limits, mirror, glTF write-back.
- `scripts/main.gd` - the window: the skinned mannequin (assets/mannequin.glb, Quaternius UAL2, CC0), mouse, panel.
- `data/skeleton.json` - the rest body, from `tools/export_skeleton.py <glb>` (any hero on the UE bone names).
- `data/body_limits.json` - every joint's axes and ranges, in plain degrees, editable.
- `moves/*.json` - poses and (step 3) moves: angles + quaternions + positions, readable without running anything.
- `tests/math_test.gd` - proves the math (`godot --headless --path . -s tests/math_test.gd`).

## Steps (each a launchable build Nick tries)
1. DONE 10-12: the mannequin, limits, drag/sliders/twist, hips, camera views, mirror, save a pose.
2. Self-collision (capsules per part: an arm stops on the chest, a leg on the other leg) + the stick: a straight rod
   in the right hand, the left hand can hold it and slide; the rod stops at the body. Drag a hand/foot (IK) too.
3. Moves: a timeline of key poses with times, play/scrub, insert/copy/mirror a key, in-betweens eased and checked
   against the same limits + collision (bad frames listed, not hidden). File: moves/<name>.json.
4. Bake: a move -> a clip in a game hero glb, byte-safe (gltf_local per key), then the game's wrist_check + meshcheck.
   The game's checker reads data/body_limits.json so both judge by one body.
