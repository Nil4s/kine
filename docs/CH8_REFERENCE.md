# CH8 reference: what the liquid solver is judged against

Written before any solver number was read (the bars live in `tests/ch8_test.gd`).

## 1. Martin & Moyce 1952: the collapse of a water column (dam break)

J. C. Martin and W. J. Moyce, "Part IV. An experimental study of the collapse of liquid columns on a rigid horizontal plane",
Phil. Trans. R. Soc. Lond. A 244 (1952), 312-324. Water column of width `a`, height `n^2 a`, released on a flat floor; they filmed the
surge front. Non-dimensional: `Z = x/a` (front position from the back wall of the column, in column widths) against `T = t * sqrt(2g/a)`.

The case used here is the one every later paper reproduces: `n^2 = 2` (column a wide, 2a tall).

| T = t sqrt(2g/a) | Z = x/a (surge front) |
|---|---|
| 0.00 | 1.00 (the column's face) |
| 0.41 | 1.11 |
| 0.84 | 1.22 |
| 1.19 | 1.44 |
| 1.43 | 1.67 |
| 1.63 | 1.89 |
| 1.83 | 2.11 |
| 2.00 | 2.33 |

**Caveat, stated plainly.** There is no network in this session and the paper is not in the repo. These values are the points
published in the SPH/MPS dam-break literature that reproduces Martin & Moyce's Fig. (e.g. Koshizuka & Oka, Nucl. Sci. Eng. 123 (1996), 421;
Colagrossi & Landrini, J. Comput. Phys. 191 (2003), 448), as I remember them. They are NOT checked against the paper here, so the
10 % bar below is a bar against that reproduction. Whoever has the paper should compare the seven rows once. Every Z is a multiple of 1/9
(10/9, 11/9, 13/9, ...), which fits readings taken off the film in ninths of a column width.

Two independent sanity checks that do not depend on my memory of the table:

* **Ritter's frictionless dam-break bound.** The shallow-water front speed is `2 sqrt(g h0)`, with `h0 = 2a`, which in these variables
  is `Z = 1 + 2T`. A real front with floor friction and a finite column stays under it. Every table row is under it (T = 2: 5.0 vs 2.33).
* Late-time slope: the measured front advances at about 1 column width per unit T (rows 1.43 to 2.00: 0.66 Z in 0.57 T).

How the surge front is read from particles (the film showed the foot of the sheet): the furthest `x` of any particle within `0.15 a` of
the floor, minus the column's face. Time is `t = T * sqrt(a / 2g)`.

## 2. Hydrostatics

Pressure at the bottom of a still column of depth `H`: `p = rho g H` (rho = 1000 kg/m^3, g = 9.81 m/s^2). On this discretisation the
bottom layer cell holds exactly `rho g H` when the column is `H/h` cells and the free surface is at the top face of the top cell, because
the pressure is zero in the air cell above and one `rho g h` is added per cell down.

## 3. The method (own code; no MIT/AGPL code copied)

* Particles carry position, velocity and the affine matrix `C` (APIC): C. Jiang, C. Schroeder, A. Selle, J. Teran, A. Stomakhin,
  "The affine particle-in-cell method", ACM Trans. Graph. 34(4) (SIGGRAPH 2015). Quadratic B-spline weights, `D = h^2/4`, so
  `C = (4/h^2) sum_i w_i u_i (x_i - x_p)^T`.
* Particle/grid hybrid with a staggered grid and a pressure projection: Y. Zhu and R. Bridson, "Animating sand as a fluid",
  ACM Trans. Graph. 24(3) (SIGGRAPH 2005) (FLIP); R. Bridson, "Fluid Simulation for Computer Graphics", 2nd ed., CRC Press 2015
  (MAC grid, free-surface Dirichlet condition p = 0 in air, solid faces with u.n = 0, PCG with modified incomplete Cholesky MIC(0),
  tau = 0.97, sigma = 0.25).
* Density drift correction (particles squeezed in a cell ask the divergence for a positive target in proportion to the excess).
  This is a common practical device, written here from its idea, not from any package.
* Solid boundaries: a Kine part's real triangle mesh is voxelised conservatively (a cell is solid if any triangle touches it:
  triangle/box separating-axis test), so a 4 mm wall is at least one cell thick and cannot be tunnelled.
* Surface: the particle density is splatted to cell centres with the same kernel, blurred, and an iso surface at 0.5 of rest density is
  extracted by **marching tetrahedra** (each cell cut into six tetrahedra around the main diagonal). This is the tetrahedral cousin of marching
  cubes: it has no ambiguous cases and a 16-case table; it gives a few more triangles than the 256-case cube table. The normals come from the
  gradient of the density field.
