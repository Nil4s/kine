# A grip for any prop (ROADMAP 18)

The weapon wrap (scripts/grip_wrap.gd, docs/GRIP_RESEARCH.md) closes the fingers round a capsule: a handle is a
segment and a radius. A prop has any shape, so scripts/any_grip.gd takes the prop as a **signed distance field**
(m, negative inside) and uses the same rule per finger segment:

    gap(segment) = min over the segment's axis of field(point) - the segment's radius

Each joint closes until its segment, or one beyond it, touches the surface (within 1 mm), or stops at its limit
(Buchholz & Armstrong 1992). The joints close together in Gulke's ratio (MCP 28 : PIP 43 : DIP 26 deg, Gulke et al.
2010). A power grasp then settles every segment onto the surface. The thumb closes until a thumb segment meets the
prop, its base chosen from a small grid. The weapon path is not changed: grip_wrap.gd and body.gd are untouched.

## Where the field comes from

| Prop | Field | Exact? |
|---|---|---|
| built-in kinds (props.gd: box, crate, table, ball, ...) | min over the prop's solids and spheres (Props.solids, Props._sd) | yes, to the box and sphere surfaces |
| imported model (a .glb in the library) | voxel grid of the distance to its triangles (AnyGrip.MeshField), trilinear | to the grid: 4 mm cells, coarser for a large mesh (work bound 1.5e6 triangle tests) |

The mesh field's sign comes from the nearest triangle's normal, with the normals oriented by the mesh's signed volume.
Outside the grid the field returns the distance to the grid plus 1 cm, which is never a contact.

## Choosing the pattern by shape

Feix et al. 2016 (the GRASP taxonomy, IEEE Trans Hum-Mach Syst 46(1)) sorts grasps by the object and the hand's use:
power grasps (the object held against the palm by the fingers, the thumb as a buttress) and precision grasps (the
object held by the pads). The pattern is taken from the object's form, which is the taxonomy's own axis:

| Shape (AnyGrip.shape_of) | Test | Grasp (Feix) | What the closure does |
|---|---|---|---|
| sphere | spheres key, or vertices all the same distance from their centre (spread under 3%) | spherical power grasp | power: fingers wrap and settle, thumb closes to the surface |
| cylinder | sorted sizes s1 >= 1.6 s2 and s2 >= 0.85 s3 | power cylinder grasp | power |
| plate | thinnest size under 2.5 cm | precision (disk-like) | precision: fingertips close and stop, no settling |
| block | anything else | power, the palm on a side | power |

The hook/lateral grasp for a box edge is not built: a box is a block and gets the power grasp. That is a gap, not a
result: a box held by one edge needs the hook pattern and an edge test.

## Placing the hand

grip_wrap.gd starts from a hand placed on the handle by the grip file. For a prop, AnyGrip.place_hand does the same
job by search: it finds the surface point nearest the palm (Newton steps on the field), orients the hand so the
curl points at the surface and the fingers lie tangent to it, moves the wrist with the arm's own IK (Body.fit_hand),
and backs the palm off until no open finger starts inside the prop (a finger that starts inside is held there by the
closure). The curl direction is measured on the rig (the index knuckle bent 10 deg, the tip's motion), so no joint
frame is assumed. An arm placed by IK is limited by the wrist: a prop on the far side of the palm needs a turn the
wrist cannot make (measured: a cylinder straight out along the reach left the palm 40 mm off).

## What the test shows (tests/any_grip_test.gd, one run)

- 4 cm cylinder (12 cm tall, 24 sides, a mesh): classed cylinder; fingertips at +0.1, -0.9, +0.2, +1.2 mm of the
  surface (all within 3 mm); no finger segment inside; the thumb's tip on the surface (+1.0 mm).
- 22 cm ball (props.gd "ball"): classed sphere; fingertips at +0.1, +0.1, +0.2 mm and the pinky at its limit, 19 mm
  off (within the rule); no finger segment inside.
- Not met: the ball's thumb starts 33 mm inside the ball. The palm sits 10 mm off the surface; the thumb base is
  inside the ball's curvature from the palm's thumb side, and no base pose on the grid starts outside. The test
  reports this as a failing check on purpose.
- Weapon wrap: GripWrap.wrap rows are bit-identical before and after the prop wraps.
- Keys: key_hand puts the 15 finger and thumb joints at the playhead.
- Timing: the mesh field for the cylinder about 0.4 s; the wrap 0.1 to 0.2 s; the ball's wrap 0.1 s.

## What is not done

- The thumb opposition on a large sphere (above).
- Hook and lateral grasps for a box edge (only the shape classes above).
- A prop lying flat or on its side: place_hand takes the flexion axis up (or forward when the palm faces straight up
  or down), so a horizontal cylinder is not placed with its own axis.
- The grip for an imported model is built but not tested (the test uses a built-in mesh and a built-in kind).
- The palm is not moved by the command (Grip: wrap ...): the hand is where the user holds it; the closure only
  moves the fingers and the thumb.
