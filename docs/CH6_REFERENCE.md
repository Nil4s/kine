# CH6 reference: a bowline, tied by a hand, then loaded

Written BEFORE any rope was simulated (11-03). Nothing here was measured on a physical rope by me; the numbers are
published ones and are marked as such.

## Sources

- Clifford W. Ashley, *The Ashley Book of Knots* (1944), knot #1010, "Bowline" (the diagram: a loop made in the standing
  part, the end passed up through it, round behind the standing part, and down through the loop again). Public-domain era
  diagram, redrawn in countless sources; I worked from the written tying sequence, not a scan.
- The "rabbit, hole, tree" tying sequence (Scouts / Animated Knots by Grog / Wikipedia "Bowline"): hole = an overhand loop
  in the standing part with the working end side crossing OVER the standing part; rabbit (working end) comes up through the
  hole from behind, goes round BEHIND the tree (the standing part), and goes back down the hole.
- Knot efficiency (breaking strength with the knot / without): CMC Rescue, "Evaluating Rescue Knot Efficiency in 11 mm
  General Use Ropes" (cmcpro.com): bowline 67 %, 75 %, 58 % on three ropes; larger bends give higher efficiency.
  Secondary sources quote 60-75 % (not used in any bar).
- Tail guidance: 10-12 rope diameters past the knot (common rescue / sailing guidance; secondary sources).

## What is and is not "measured"

No physical rope was tied. Geometry used by the bars comes from the written sequence and the diagram proportions: the hole
(collar) must pass a pinch of two fingertips (about 2 cm wide), so its inner diameter is at least 4 rope diameters; the
finished loop sits snug on what it is tied round; the knot body (collar, nip and the doubled legs) spans a few rope
diameters, so "core length" is compared with itself before and after loading, never with an absolute figure.

## Topology: the crossing sequence

Frame: x right, y up, viewer on +z. The rope is traced from the standing end S0 (the end that is loaded) to the working
end W. Strands: A = the standing part rising along x = 0; H = the hole, a loop of A turned counter-clockwise; E = the
outgoing leg that leaves the hole over A at crossing c3; L = the big loop round the peg; R = the return leg of the loop,
passing BEHIND the hole to the waiting working end; W = the working end after it is threaded.

Tying path of W: waits behind the hole centre; rises through the hole (front); goes down in front of the hole's bottom
strand; dips behind A (A over W); rises and returns over A (A under W) = one full turn round A, the collar; goes back up in
front of the hole's bottom strand; and descends through the hole (front to back).

Hand-derived crossing sequence of that diagram viewed from +z (O = this strand passes over, U = under). Numbers are
crossings; each appears twice.

    S0 -> A: 1O 2U 3U   (1 = W behind A, 2 = W over A, 3 = E over A, at the foot of the hole)
        -> H (circle):   6O 4U 5U 3O   (6 = R passes behind the circle's upper right arc, 4 / 5 = W legs in front of the
                          circle's bottom strand, 3 = E leaves over A)
        -> E, L, R:      6U
        -> W:            4O 1U 2O 5O

    raw code: 1O 2U 3U 6O 4U 5U 3O 6U 4O 1U 2O 5O      (12 crossings; a projection of the dressed knot is not minimal)

The tests reduce a code with Reidemeister I and II moves (a crossing next to itself on one strand; two crossings adjacent
on both strands with one strand over at both) over 64 view directions, keep the shortest, and compare it with the same
reduction of the reference polyline `Ch6Knot.reference()` after relabelling in order of first appearance, allowing a mirror
(all O/U swapped; the left-hand bowline is the same knot). The clasp 1/2 (A over at one, under at the other) is a hook,
not a bigon that moves away: a slip knot or a wrongly crossed bowline fails it.

Also required (invariants that do not depend on the view): the rope loop links the peg once (winding of the closed
loop about the peg axis = +-1), and W's last strand is inside the loop.

## Numbers the bars rely on

| Quantity | Value | Where from |
|---|---|---|
| rope radius r | 4 mm (8 mm rope) | typical 8 mm kernmantle / laid rope; knot is 3D so tests use r, not mm |
| hole inner diameter | >= 4 diameters | fingertip pinch must pass it |
| tail past knot | >= 10 diameters (8 cm) | guidance above |
| knot efficiency | 58-75 % | CMC 11 mm tests (not used for a bar; holding is judged by no slip) |
| friction rope on rope | mu = 0.4 (planted control mu = 0) | dry nylon / polyester on itself 0.2-0.5 |
| capstan | T2/T1 = exp(mu theta) | Euler-Eytelwein, exact for a rope on a fixed cylinder at the verge of slipping |

## Bars (also in tests/ch6_test.gd, committed before the first number was read)

See the header of tests/ch6_test.gd; they are not restated here so they cannot drift.
