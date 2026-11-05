# CH1e reference: the fastener values, with sources

Every per-fastener value used by `scripts/build/ch1e_fast.gd`. CD = load duration factor. Simpson values are published at CD 160 (wind/seismic basis); AWC DA-2 and the NDS values are CD 1.0 reference values. The module keeps both (T10/V10 and T16/V16).

## Sources

| Value | Source |
|---|---|
| Fastening schedule (stud_to_plate 4-8d box toe, joist_to_plate 4-8d, rafter_to_plate 3-16d box toe, rafter_to_ridge 4-16d box toe, plate_to_plate 16d at 16 in, plate_lap 3-10d, stud_to_stud 16d at 24 in, header built-up 16d at 16 in each edge, header_to_stud 5-8d, sheathing 6d common 6/12 in) | IRC 2021 Table R602.3(1), as stored in `HouseCheck.FASTENERS` |
| Anchor bolts 1/2 in, 6 ft o.c., within 12 in of ends and at least 7 diameters, 7 in embed | IRC 2021 R403.1.6 |
| Toenail withdrawal W (Ctn 0.67 included), G 0.50: 8d box 0.113x2.5 = 28, 16d box 0.135x3.5 = 48 lb (SPF G 0.42: 18, 31) | AWC Design Aid DA-2 "Toenail Connections" (NDS 2001+ values) |
| Toenail lateral Z (Ctn 0.83 included), G 0.50: 8d box 60, 10d box 77, 16d box 86, 6d common 57, 8d common 80, 16d common 117 lb (SPF: 50, 65, 73, 44, 62, 99) | AWC DA-2 |
| Face-nail lateral Z = DA-2 toenail Z / 0.83 (16d common 141, 10d box 92.8) | derived from DA-2 |
| Face-nail withdrawal W = 1380 G^2.5 D lb per inch of penetration | NDS Eq. 12.2-1 as quoted in `docs/CH11_REFERENCE.md`; NOT opened here: flagged |
| H2.5A: ten 0.131x1.5 nails, uplift 625 lb (DF/SP), 540 (SPF/HF), F1 = F2 = 110 lb, CD 160 | Simpson Strong-Tie C-C-2021 p.277 |
| HDU2-SDS2.5: 14 ga, six 1/4x2.5 SDS screws, 5/8 in anchor, tension 3,075 lb (DF/SP), 2,215 (SPF/HF), CD 160 | Simpson Strong-Tie C-C-2021 p.52 |
| 6d common sheathing nail, 3/8 in OSB, 6 in edge: ASD 200 plf = 100 lb per edge nail at CD 1.6 | SDPWS 2015 Table 4.3A, read in `docs/CH10_REFERENCE.md` section 2 |
| 1/2 in anchor bolt shear in a 2x sill, 1,040 lb at CD 1.6 | Clark County NV BD-CI-038 via a search summary: SECONDARY |
| 1/2 in anchor bolt tension min(steel 2,368, concrete 4,515) = 2,368 lb | `HouseCheck.anchor_capacity` ACI/A307 hand calculation: still UNVERIFIED |
| Nail head diameters | ASTM F1667 from memory; drawn only, used by no capacity |

## Replacements of CH1d / CH11 values marked UNVERIFIED

| Constant | Old | New | Basis |
|---|---|---|---|
| `HouseCheck.TIES["toenail3-8d"]` | 113 | 134.4 (3 x 28 x 1.6) | AWC DA-2; `TIES_UNVERIFIED` now empty |
| `H2.5A` (`TIES`) | 625 (retailer) | 625 | now primary: Simpson C-C-2021 p.277 |
| CH11 `TOE_8D_W_LB` | 37.67 | 28 | DA-2 |
| CH11 `TOE_8D_Z_LB` | 52.3 | 60 | DA-2 |
| CH11 `TOE_16D_W` | (typed) | 48 | DA-2 |
| CH11 `TOE_16D_Z_LB` | 69.7 | 86 | DA-2 |
| CH11 `FACE_16D_Z_LB` | 122 | 141 | derived from DA-2 |
| CH11 `H25A_V_LB` | 315 | 110 (F1/F2, CD 1.6) | Simpson p.277 |
| CH11 `ANCHOR_V_LB` | 600 | 1040 (CD 1.6) | secondary source |
| CH11 `ANCHOR_T_LB` | 1500 | 2368 | hand calc, still flagged |

CH11 is a parked branch and was only read; its constants are listed as the replacements the CH11 owner should take. Not fastener values and therefore not replaced: `UPLIFT_LB_PER_FT` 3.7, `FC_PERP` (625 not confirmed), the CH10 roof Ga 7.5 (SDPWS Table 4.2C unread). CH10 uses no joint capacity, so it is unaffected.

## Findings recorded by the placement

- Partition sole plates V1/V2 sit on the 4 in slab with no footing: a 7 in embed is impossible, so no bolts are placed there (49 listed, 33 placed). IRC R403.1.6 anchors exterior and bearing walls; flagged.
- Roof sheathing joints are offset 19 mm from the rafter pair, and the gable panel bottom edge has no framing: some edge nails there are unsupported; recorded, exempt from the wall schedule bar.
- Corners get no hold-down (no doubled end post on the exterior segment); HDU2 is placed only on segments at least h/3.5 wide.
- Toenail tips into 38 mm members protrude up to about 15 mm (3.5 in nail through 3 in of lumber); tail allowance 16 mm.
- The plate washer 3x3x0.229 in is a design choice.
