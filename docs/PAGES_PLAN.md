# Kine pages: the repage plan (draft, 2026-10-19)

Today Kine is one screen with ribbon tabs (POSE, ANIMATE, SET, CHECK, EXPORT, VIEW). The next step is
PAGES, the way DaVinci Resolve splits Media / Edit / Fusion / Color: one bar of pages along the bottom,
each page with its own layout built for one job, all sharing ONE file, ONE character, ONE undo history.

Blender's lesson to keep: modeling, sculpting and animating in one program. Blender's pain to avoid:
modes inside modes, hidden state ("why can't I select this?"), and a character that has to be exported
from one tool to be rigged in another.

## The pages

| page | job | what lives there now / what is new |
|---|---|---|
| BODY | make the character | NEW: parametric human from ANSUR II (height, mass, proportions as real percentiles), auto-rig to the UE5 skeleton, face shapes |
| MODEL | edit the mesh | NEW: points / edges / faces, extrude, loop cut, bevel, booleans, symmetry |
| SCULPT | shape with brushes | NEW: brushes, multires levels, sculpt ON the posed character |
| SURFACE | UVs, materials, retopology | NEW: auto UVs, materials, retopo to animation-ready loops |
| POSE | pose one moment | today's POSE tab, inspector, pose library, packs |
| ANIMATE | cards, timeline, curves | today's ANIMATE tab, scene strip, dope sheet, graph, markers, audio, video capture |
| STAGE | the set and the cast | today's SET tab: props, stairs, cameras and shots, crowd, several fighters, cloth, hair |
| CHECK | is it right | today's CHECK tab: grade, human check (10), gait, balance, hits, frame data |
| DELIVER | get it out | today's EXPORT tab: glb, fbx, usd, bvh, batch, playblast, plugins |

## Easier than Blender: the rules every page follows

1. No hidden modes. The page you are on is the mode; its name is always visible and every tool on it works.
2. Every tool says what it will do before you click (hover hints exist today) and refuses with a next step.
3. One undo across pages: sculpt, then animate, then Ctrl+Z walks back through both.
4. The skeleton is known from the first second, so MODEL and SCULPT can be anatomy-aware:
   topology that deforms well at the joints by default, brushes that know where muscles are,
   a sculpt you can check in any pose of the animation (no export round trip to see if it bends right).
5. Retopology is automatic to edge loops placed where the rig bends.
6. Real-human references stay: proportions, joint limits and motion checks are numbers with sources.

## Order

1. Page switcher + move today's tabs into POSE / ANIMATE / STAGE / CHECK / DELIVER (no new features;
   every existing test must still pass). The scene strip at the bottom gets its rework here.
2. BODY page (ANSUR II body + auto-rig): first use of the new mesh core.
3. MODEL page on that mesh core.
4. SCULPT page.
5. SURFACE page.
6. Face as real geometry (replaces the painted face).
