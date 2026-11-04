# CH12 reference: a footbridge that sways (London Millennium Bridge, June 2000)

Written 2026-11-04 BEFORE the model was run. Nothing could be fetched online in this lane, so every number from the paper below is from memory and marked UNVERIFIED where I am not sure; the bars use the paper's FORMULA applied to the model's own mass, damping and frequency, never a remembered result.

## 1. Source

Dallard P., Fitzpatrick A.J., Flint A., Le Bourva S., Low A., Ridsdill Smith R.M., Willford M. (2001) "The London Millennium Footbridge", The Structural Engineer 79(22), 17-33; companion: same authors, "London Millennium Bridge: pedestrian-induced lateral vibration", J. Bridge Eng. 6(6), 412-417.

Read from memory (UNVERIFIED):
- Central span 144 m (south 108 m, north 81 m), deck 4 m wide, steel edge box girders with lateral suspension cables. Lateral first modes: south span ~0.8 Hz, centre ~0.48 Hz (used here), north ~1.05 Hz; the lateral instability occurred when the crowd's lateral walking frequency (half the ~1 Hz step rate) met the 0.5 Hz mode.
- Pedestrian lateral force at the walking frequency: about 25 N amplitude per person at ~1 Hz step rate (5 percent of body weight; the brief's figure, used as F0).
- Synchronous lateral excitation: above a critical number the crowd's lateral force is proportional to deck VELOCITY, F = k v per person, k about 300 N s/m for lateral frequencies 0.5 to 1.0 Hz. The deck then receives negative damping N k / 2 for a uniformly spread crowd and a sine mode; instability when it exceeds the structural damping 2 zeta omega M. This gives the paper's
  **N_crit = 8 pi zeta f M / k** (M = modal mass with the mode normalised to 1 at the crowd's position, zeta structural damping ratio, f modal frequency).
  Check: N k / 2 = 2 zeta omega M with omega = 2 pi f gives N = 8 pi zeta f M / k. Same formula, so the factor 8 pi is the sine-mode, uniform-crowd one (average phi^2 = 1/2).
- Structural lateral damping 0.5 to 0.8 percent; the paper's actual modal masses and critical numbers (order 150 pedestrians for the worst spans) are NOT used as bars: UNVERIFIED, and the model is a simply supported span, not a suspension bridge.
- Retrofit 2002: 37 viscous dampers (lateral, ~15 to 20 percent damping target) plus 54 tuned mass dampers; modelled as lateral viscous dashpots only.
- Euler-Bernoulli simply supported beam: f_n = n^2 pi / (2 L^2) sqrt(E I / (rho A)).

## 2. The model (choices recorded before running)

- Central span only, simply supported: L = 144 m, 48 stations of 3 m. Lateral and vertical held at both ends, ends free to rotate, one x restraint at the left. Cables are NOT modelled (edge girders carry the lateral stiffness, see the next point): the real bridge's lateral stiffness comes from its cables, so this is a "simplified" bridge as the brief allows.
- Two steel box edge girders at z = +/- 1.9 m (deck 4 m): E 210 GPa, G 81 GPa, rho 7850, A = 0.053 m2, own Iz 0.045 m4 (vertical), own Iy 0.005 m4 (lateral), J 0.02. A cross frame (A 0.02, I 1.0 m4, rho 100) at every station ties girder, deck centre line and girder so the pair acts as one lateral section (composite I = 2 A 1.9^2 + 2 Iy).
- Total dead mass 2000 kg/m including the deck mass, which is a lumped mass on the centre line (girders 832 kg/m). UNVERIFIED order of magnitude of the paper's deck mass.
- Section choice FROM the paper's stated stiffness: area A chosen so the closed form f1 = pi/(2 L^2) sqrt(E I_lat / m') = 0.48 Hz (the paper's central span value): EI_lat = E (2 A 1.9^2 + 2 Iy) = 8.4e10 N m2, m' = 2000, f1 = 0.486 Hz by hand. Recorded before any run.
- Vertical first mode by hand from the same section: EI_vert = E 2 Iz = 1.89e10, f = 0.230 Hz.
- Damping: mass-proportional Rayleigh, alpha = 2 zeta omega1, zeta = 0.006 (paper range 0.5 to 0.8 percent).
- Modal mass: sum over nodes of lumped mass x phi^2 (mode normalised to 1 at midspan); about 144 t by hand (m' L / 2).
- Critical number by the paper's formula for this model: N_c = 8 pi x 0.006 x 0.486 x 144000 / 300 = 35 pedestrians (by hand); the test recomputes it from the model's own f and M.

## 3. The crowd (Dallard's synchronous lateral excitation as a phase-locking oscillator)

Each pedestrian i has a lateral phase theta_i, force F0 sin(theta_i) (F0 = 25 N) on the deck centre line at x_i (spread uniformly over the span), and
 theta_i' = omega_i + cp v_loc cos(theta_i),   v_loc = deck lateral velocity at x_i.
cp = 0 is a free-running (random-phase) walker, the control. With cp > 0 a walker whose natural lateral frequency omega_i is within cp v / 2 of the deck's locks to it with its force in phase with the deck velocity (sin(theta) = cos(psi)); the crowd's in-phase mean force is then F0 pi (cp v / 2)/(2 W') per walker for frequencies uniform over a width W' = 2 pi x 0.1 rad/s, i.e. linear in v with k = pi F0 cp / (4 W'). cp = 4 W' k / (pi F0) = 9.6 rad/m is set so that k = 300 N s/m. That is a CALIBRATION to the paper's k, not a derived result; what the test then measures (the onset N against the formula) checks the dynamics (finite crowd, partial locking, position weighting phi^2, transient lock-up), not the gain.
- Lateral frequencies uniform over 0.1 Hz centred on the deck's first lateral frequency: the worst case (the crowd at resonance).
- Start phases and frequency offsets come from fixed golden-ratio sequences (reproducible, no RNG).
- Saturation: the force amplitude per walker is 25 N, so the in-phase force stops growing when all are locked (v about 0.065 m/s), and the amplitude levels off (limit cycle).
- Not modelled: the walkers' own mass, vertical forcing, foot-fall harmonics, walkers changing pace by "stopping" or the real crowd density limits.

## 4. Solver

`KineFrameNative` / `Ch10Frame` (CH10), extended for CH12 (additive): model key `dashpots` = (global dof, c) pairs on the damping diagonal; Newmark job key `crowd` with the phase-locked walkers above (C++ loop, GDScript twin); outputs `crowd_power`, `crowd_theta`. Newmark average acceleration, dt 0.02 s (period error (omega dt)^2 / 12 = 3e-4).

## 5. Retrofit

Lateral viscous dashpots on the centre-line nodes at stations 19 to 29 (the middle of the span), total sized so the modal damping rises from 0.6 to 5 percent (c_total = (0.05 - 0.006) 2 omega M). That raises the formula's critical number by 0.05 / 0.006 = 8.3 times.
