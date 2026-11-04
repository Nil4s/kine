# CH10 feedback: the CH1 house under wind and El Centro

Date 2026-11-03. Test: `tests/ch10_test.gd` (bars committed in 76d890fb before any number was read). Solver: `native/src/kine_frame_native.cpp` (KineFrameNative), twin `scripts/build/ch10_frame.gd`.

## Numbers against the bars

| bar | result |
|---|---|
| a1 cantilever tip and first omega vs closed form, 1% | 0.0000 pct, C++ and GDScript |
| a2 portal sway and first omega, 1% | 0.065 pct, 0.055 pct |
| b1 wind total vs hand calc | 13,454 N vs 13,343 N (0.83 pct; Kz 0.575 model vs 0.57 table) |
| b2 reactions = applied | 0.000 pct |
| b3 wall lateral deflection vs hand calc, 5% | wall L 2.90 pct, wall R 4.55 pct |
| c first period inside [0.5 Ta, 1.7 Ta] = [0.068, 0.232] s | **FAIL**: z 0.252 s, x 0.290 s (Ta 0.1366 s) |
| d Newmark undamped SDOF energy drift < 0.5% over 1000 steps | 5.8e-14; control (2% damping) fails the same bar |
| e1 code house peak drift ratio < 0.020 | z 0.00702 (17.3 mm), x 0.01415 (34.9 mm) |
| e2 line L unbraced >= 1.5x code | 0.01316 = 1.88x; stays UNDER 0.020 |
| e3 no z bracing (L and R) > 0.020 | 0.02377, period 0.516 s |
| e4 C++ == GDScript within 1e-9 (10-member frame) | 1.5e-14 static, 1.0e-14 omega, 1.6e-13 Newmark |
| f solve time per Newmark step | 33.4 ms (5115 free dofs, band 485) |

## What the model says

- The code house is stiff in z (T 0.25 s) and softer in x (0.29 s, only the gable-end walls carry x). Unscaled El Centro (0.349 g) gives drift ratios of 0.7 to 1.4 percent, under the 0.020 limit.
- A linear model cannot show the one-line racking failure. Taking the bracing off line L made drift 1.88 times larger and still under 0.020. The registered "planted house exceeds the allowable" wording is met only by e3.
- e3 shows the code margin is used up once both lines are gone: 0.02377 against 0.020.

## Bar c is a finding

The model period is longer than 1.7 Ta (and longer than Cu Ta, 0.219 to 0.232 s for SDC B, Table 12.8-1 Cu 1.6 to 1.7). Too long means too soft or too heavy: Ga = 11 kips/in is the low SDPWS row; gypsum, partitions and corner returns add stiffness the model ignores; rigid anchorage already flatters it (real hold-down slip lengthens the period further). Sensitivity to Ga 16 was not run. See `docs/CH10_REFERENCE.md` section 7.

## Honest limits

- Linear elastic. No nail-slip hysteresis, no pinching, no strength cap, no collapse. The unscaled record gives an elastic base shear of order 500 plf, above the 400 plf nominal capacity of the 6d/6 in row, so real nails would yield; this model cannot say what happens next.
- Roof diaphragm Ga 7.5 kips/in is an unverified halving. Ct = 0.02, x = 0.75, Cp values and SD1 are from memory or unlooked-up site data.
- Wind: walls only; roof components omitted. Axis offsets up to 0.12 m collapsed to member axes. Gypsum modelled as mass only.
- Quake runs use dt 0.02 s (about 2 pct period elongation at T 0.25 s). The video series uses dt 0.01.
- One component at a time; no torsion check beyond what the frame gives.

## Video

`C:/Users/Nick/tools/kine_workers/out/ch10/ch10_el_centro.mp4` (1075 frames at 20 fps, 54 s of record at 1/5 real time per frame step; drift x25 stated on screen; code house left, line L removed right; drift-vs-time plot with the 0.020 line at 49 mm). Frames 0 and 100 were opened: both houses render, the right house sheared visibly more at 5 s, the plot cursor moves. The plot shows the roof-mean drift (code peak 11.1 mm, under-braced 18.4 mm), not the max-node drift the bars use.

## Build

`cd native && bash /c/Users/Nick/tools/kine_workers/native_build.sh` (wrapper over `python -m SCons platform=windows use_mingw=yes target=template_release arch=x86_64 custom_api_file=D:/kine_native/api/extension_api.json`).

## Open findings

- Bar c (first sway period inside the ASCE 7 band 0.068 to 0.232 s) fails: 0.2898 s sheathing only, 0.2841 s with the gypsum skin. Kept as registered in `tests/ch10_period_test.gd`, not in run_all.sh. Run by hand: `bash /c/Users/Nick/tools/kine_workers/wtest.sh <id> ch10_period` (expected: FAIL, 1 fail).
