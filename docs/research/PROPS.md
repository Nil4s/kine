# Generic props: real sizes and where they come from

GAP_ANALYSIS row 22 ("4 weapons; no generic prop (box, door, ball)"). Every number a prop kind in
`scripts/props.gd` is built from is listed here with its source. `tests/props_generic_test.gd` reads the
`kind.field = value` lines below and holds `Props.KINDS` to them (to 0.1 mm / 1 g).

## The numbers

| prop | number | source |
|---|---|---|
| football | `ball.circumference_min = 0.68` m, `ball.circumference_max = 0.70` m | IFAB Laws of the Game, Law 2 (The Ball): circumference 68-70 cm |
| football | `ball.mass_min = 0.41` kg, `ball.mass_max = 0.45` kg | IFAB Law 2: 410-450 g at the start of the match |
| football | `ball.diameter = 0.2196` m, `ball.mass = 0.43` kg | ours: the middle of each range (69 cm / pi = 21.96 cm; 430 g) |
| door leaf | `door.width = 0.8128` m, `door.height = 2.032` m | the common US interior door, 32 x 80 in (Bob Vila, "standard size for doors": "The standard door width for interior doors is 32 inches", "Standard door height for interiors is 80 inches") |
| door leaf | `door.thickness = 0.035` m | 1 3/8 in (34.9 mm): "The standard interior door thickness is 1 3/8 inches" (Bob Vila) |
| moving box | `moving_box.length = 0.4159` m, `moving_box.width = 0.3207` m, `moving_box.height = 0.3207` m | U-Haul Small Moving Box, 16-3/8 x 12-5/8 x 12-5/8 in (1.5 cu ft), uhaul.com product 3245 |
| chair | `chair.seat_height = 0.45` m | inside the seated popliteal height range 15.0-19.9 in = `chair.popliteal_min = 0.381` m .. `chair.popliteal_max = 0.505` m (5th female .. 95th male; GVSU seating handout, citing BIFMA's ergonomics guideline G1) |
| table | `table.top_height = 0.75` m | NOT verified: EN 527-1 (office desks) gives its heights from the 5th-95th percentile European user, but its table could not be read; 0.72-0.76 m is what desks sold to it list (e.g. 720 mm). Kept as round 37 built it |

The brief named 0.80 x 2.03 m for the door and 0.45 x 0.30 x 0.30 m for the box. The door uses the exact US
size it rounds (0.813 x 2.032 m); the box uses a real product's size (U-Haul Small) rather than a round guess.

## How each one is built

- **ball** (`ball`): one sphere, radius 0.1098 m, resting on the floor (its centre 0.1098 m up). It is the first
  kind with a sphere: `Props.solids` returns it as an entry with `"r"`, and `Props._sd` measures a true sphere, so
  the contact checks (Rulebook THROUGH A PROP) see a ball, not its bounding cube. Mass is data (`"mass"`); the throw
  physics (`scripts/throw.gd`) does not use mass, so the ball falls like any prop (gravity does not depend on mass).
- **door** (`door`): a leaf only (the frame is the `door_frame` kind). Its origin is the HINGE axis on the floor; the
  leaf runs along +X from it. `"swing"` (deg) turns the leaf about the hinge; + swings the free edge toward +Z. The
  swing is keyable (below). Mirror reflects the hinge side: yaw -> 180 - yaw, swing -> -swing.
- **moving box** (`moving_box`): one box, held in both hands when both are near (main `TWO_HANDS`).
- **chair, table**: unchanged (round 37); listed here for their sources.
- **a mesh file**: Import model (or a .glb dropped on the window) already makes a kind of its own from the model's
  bounding box (round 37, SS6, `Props.register`); it takes keys and carries like every kind.

## Keys over time

A prop may hold `"keys": [{"t", "pos", "yaw", "swing"}]`. Played with the part keys' curve (`PartKeys.at`: a
monotone cubic, eases out of the first key and into the last, never overshoots), position and (yaw, swing) as two
curves. Commands (search, S): "Prop: key its place here", "Prop: delete its keys", "Door: open 15 deg (key here)",
"Door: close 15 deg (key here)". A keyed prop dragged (or Shift+dragged to turn it, Ctrl snaps to 5 deg) is keyed at
the playhead. In the file: `"swing"` and `"keys"` only when there are any, so an older scene saves byte for byte.

## Carried, and a constraint on it

Pick up / Put down (round 39) hold a prop in a hand from one card to another. A Child Of constraint whose target is a
prop now follows the prop where it IS at that moment (`Scene.prop_xf_at`: in the carrying hand, or where its keys put
it). Before, it followed the prop's stored place, so a box carried by the right hand left the left hand behind.
"Constraint: target the picked prop" makes a prop the target.

## Sources

- IFAB, Laws of the Game, Law 2 - The Ball: https://www.theifab.com/laws/chapter/22/section/32
- Bob Vila, standard door sizes: https://www.bobvila.com/articles/standard-size-for-doors
- U-Haul Small Moving Box: https://www.uhaul.com/MovingSupplies/Boxes/Standard-Sized-Moving-Boxes/Small-Moving-Box?id=3245
- GVSU seating measurements (popliteal height, citing BIFMA G1): https://www.gvsu.edu/cms4/asset/30F6D8A1-9140-75C7-2CAACF4A83B9D5A8/seatingmeasurements.pdf
- BSI, BS EN 527-1 (office work tables and desks, dimensions), not read: https://knowledge.bsigroup.com/products/office-furniture-work-tables-and-desks-dimensions
