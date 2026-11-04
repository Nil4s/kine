# CH5c feedback: wet cobblestone street on the engine's PBR

Branch w4-ch5c (from origin/poser-ui-rounds 422461fe). Files: scripts/wet_street.gd (no ground shader any more), tests/ch5c_test.gd, tools/ch5c_prep_tiles.py, assets/ch5c/.
Renders (1280x720, pose x = 0): C:/Users/Nick/tools/kine_workers/out/ch5c/ch5c_night.png, side by side with ref2.jpg: ch5c_side_by_side.png. Logs: out/ch5c/ch5*_run.log.

## Asphalt veil source (measured on the CH5b shader, commit 67a12af7)
Dry asphalt mean luminance 0.156; lamps off 0.051; specular only 0.108. The veil is the lamps' GGX specular on a single-normal flat strip. Ambient sky and wall bounce are about 0.025 each. Not albedo, not fog.

## What was built
StandardMaterial3D ground (world-baked albedo+roughness and normal maps from one height function), a displaced mesh (bowls are geometry), a flat water quad at the level with SSR, a ReflectionProbe, five OmniLight3D with engine shadows, soft glare texture (0 at the edge).
Stone layout: Poly Haven CC0 "Cobblestone Floor 04" (https://polyhaven.com/a/cobblestone_floor_04, Rob Tuytel): outlines segmented into 141 setts, its displacement map is the stone relief. Asphalt: "Worn Asphalt" (https://polyhaven.com/a/worn_asphalt, Amal Kumar), CC0.
Lane extended to 34 m and lamp 0 moved to z = -33 (photo geometry). light_size 0.3 m (a 0.6 x 0.3 m luminaire window, from memory), printed in every log.

## Bars (run from b90113c2, ch5 ch5b ch5c; ch5/ch5b bars unchanged)
See the report; red: B (3 non-lamp puddles show peak 1.00; pose 2 lamp 3.9 px off), D 1.21 vs 2.32, F 2.4x, F2 1.6x (control 1.6x also fails, but so does the real scene), H 0.061 vs band 0.227-0.378, S2 CONTROL.
S2 PENUMBRA passes at 6.2 px BUT its control (light_size 0) gives 16.5 px: the edge width is set by the engine's shadow-map filtering at 37 m, not by the emitter size, so the pass is not evidence of a physical penumbra. The photo has no thin vertical object casting a shadow on the lane, so there is no photo penumbra to compare.

## Bar F stamping (reported, not edited)
F samples "stone tops" at the centres of a regular 110 mm grid that stopped matching the stones in CH5b pass 2, 3x3 pixel mean. Points land in joints and on flanks; the sheen lives on dome highlights. F2 (per-stone top-10% highlight, same rule in wet and dry, control: SSR and probe off) was added and committed before its run.
Bar H was re-sourced from ref2.jpg before its first run (pre-run change of an unrun bar): the photo's only flat patch, hand mask assets/ch5c/ref2_flat_patch_mask.png, mean 0.302; wet render must be within +-25 %.
