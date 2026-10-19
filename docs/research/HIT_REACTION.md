# Automatic hit reactions (ROADMAP 14, round 52)

Code: `scripts/hit_reaction.gd` (HitReaction), the contact rows from `scripts/dummy.gd` (Dummy.fighter_hits, now with a
striking-spot velocity `vec`), the command "Hits: make the struck fighter react" in `scripts/main.gd` (`_hit_react`).
Test: `tests/hit_reaction_test.gd` (registered as `hit_reaction:w`).

**What this is:** a plausible physical response of the struck fighter to the momentum a blow delivers, for 0.3-0.6 s,
baked as editable cards. **What this is not:** a ragdoll. There is no floor contact, no gravity during the window, no
friction, no collision response between the body parts, and no solver for the full articulated dynamics. Each joint is a
damped spring back to its own animation; the momentum is handed down the chain by a fixed rule. The numbers below are
design choices, checked for consistency, not fitted to real impacts.

## 1. The contact (input)

From Dummy.fighter_hits, one row per contact: the onset time `t`, the contact point `at` (hero space, the midpoint of the
two capsules' closest points), the striking spot's velocity `vec` (its finite difference over one frame), the striker's
part (`part`) and the struck part (`on`), and for a weapon the distance `u` up the weapon from its butt.

## 2. Momentum

    J = m_eff x v_rel

- **v_rel** = the striking spot's velocity minus the struck spot's own velocity from its animation (the spot is the same
  body point, found from the struck fighter's pose one card frame apart).
- **m_eff, a weapon:** the weapon is a uniform rod of mass m (kg) about its grip. Its moment of inertia about the grip is
  I_grip = m (L^2/12 + (L/2 - g)^2), where L is the length and g the grip's distance from the knob. A contact at distance d
  from the grip gives m_eff = I_grip / d^2 (the lever's effective mass, the standard bat "sweet spot" formula). d is at least
  0.2 m: a contact nearer the grip counts as 0.2 m out, because the hand gives and the mass should not be infinite.
- **m_eff, a limb or the body:** the mass of the pieces the striking part moves (one side of the body): the hand and
  forearm for a lowerarm, the whole arm for an upperarm, the trunk and head for a spine part.

Test values: a bat (m = 0.9 kg, L = 0.84 m; the test's bat is not held, so its grip is at the knob) hit at u = 0.6 m:
m_eff = 0.588 kg.

## 3. The impulse on the struck fighter

Let p be the contact point in the struck fighter's space, and let the struck joint j be the joint its part rides on
(Body.cap's rule). Its chain is j, its parent, ..., the pelvis.

**Joint j takes the impulse about its own pivot P_j:**

    Omega_j = (p - P_j) x J / I_j

I_j is the moment of inertia about P_j of every body piece distal to j (its own chain includes j), in the scalar
approximation: I_j = sum over those pieces of m_k (k_k L_k)^2 + m_k d_k^2, where d_k is the piece's COM distance from P_j
(parallel axis). The pieces and their de Leva masses are in section 5.

**Each ancestor takes CHAIN times the angular velocity of the joint below it:**

    Omega_{parent} = CHAIN x Omega_j        (CHAIN = 0.5, a design choice: the momentum is damped as it goes up)

**A joint's own rate is its world rate minus its parent's world rate**, projected on the joint's three axes (bend, side,
twist). Summing the rates down the chain gives back Omega_j, so the world rate of the struck segment is exactly
(p - P_j) x J / I_j, and no momentum is counted twice.

**The pelvis (the body's COM) takes the linear shove:**

    v_pelvis(0) = J / M        (M = the body's mass: the sum of the pieces, 75 kg for the default body)

## 4. Integration (0.3-0.6 s)

Every joint on the chain, and the pelvis's offset, is a damped spring back to the animation:

    a = -w^2 d - 2 zeta w v          (d = deviation from the animation's angle, v = its rate)

- joints: w = 2 pi x 2.5 Hz, zeta = 0.5 (design choice: about a quarter second to come back)
- pelvis offset: w = 2 pi x 1.5 Hz, zeta = 0.7
- step: 240 Hz, semi-implicit Euler, the animation's angles interpolated between card frames.
- joint limits are hard stops (Body.clamp_ang): a joint that reaches its limit is held there and its velocity into the
  limit is set to zero. The limits are the ones the body already uses (data/body_limits.json).
- the window: from the hit to the first card arrival at 0.3-0.6 s after it (see section 6). The deviation blends out over
  its last 0.2 s (smoothstep to 0), so the body is back on its own animation at the window's end.

Why the joint chain is "damped": each ancestor's share is CHAIN times the one below, and the springs damp every joint.
The head or chest hit does not go into the other joints at full strength.

## 5. Segment inertia (de Leva 1996)

- Masses: de Leva (1996), J. Biomech. 29(9) 1223-1230, Table 4 (male and female), through Proportions.DE_LEVA (already in
  the repo, read from the paper; docs/research/PROPORTIONS.md). A piece is a bone: each joint owns the bone from itself to
  its child; the trunk's share is split over the pelvis, the three spine joints and the neck; a limb's over its upper
  arm, forearm and hand.
- COM position: the de Leva COM fraction along each segment (Table 4), applied to the bone's endpoints. Approximation:
  the endpoints are the nearest landmarks in this skeleton, not de Leva's exact ones (Proportions.gd states the same).
- Radii of gyration k (fraction of the segment length, about the COM): head 0.495, trunk 0.503, upper arm 0.322, forearm
  0.303, hand 0.297, thigh 0.323, shank 0.302, foot 0.475. **These are from memory of de Leva (1996) Table 4 as quoted in
  Winter, Biomechanics and Motor Control of Human Movement (4th ed., 2009), Table 4.1. They have not been re-read from the
  paper in this round. Check them before a number from this model is quoted.**

## 6. The window and the cards

- The window ends at the first card arrival in [0.3, 0.6] s after the hit (the cards after it keep their times, so the
  other fighter's timeline stays in step with the hero's). If no arrival is in that range, the window ends at 0.6 s; if the
  scene ends first, at 0.3 s.
- Cards before the hit stay. The card the hit falls in is cut at the hit. An anchor card at the hit holds the animation's
  pose there; it is reached in at most 0.1 s from the card before it.
- The reaction is reduced to cards the way the video import reduces a dense capture (VideoImport.every_for: the even
  spacing of 1/6 s), then every card frame the played blend needs is added until the replay is within 1 deg at every 240 Hz
  step. The check is against Scene.apply itself, because the scene's natural easing (Scene.natural) staggers each joint's
  blend by its level (a linear model of the blend, as the card maker's refine assumes, missed by 16 deg on the first try).
- The cards are linear (ease "linear"). They are one dense card per 1/60 s before the reduction.

## 7. Numbers (the test, run once)

| bar | value |
|---|---|
| head, bat from the right, 12 m/s: J, peak world angular speed | 7.06 kg m/s, 414 deg/s |
| same at 24 m/s | 828 deg/s, ratio 2.000 (bar: 2 within 15%) |
| head position at the peak | +50.6 mm in +x (the hero's left): the head turns away from the bat |
| chest, 12 m/s: J, M | 7.06 kg m/s, 75 kg |
| pelvis speed, first 1/240 s | 0.0889 m/s = 94.5% of J/M (bar: within 10%; the 5.5% is the spring's damping 2 zeta w dt) |
| pelvis speed averaged over the first card frame (1/60 s) | 0.0815 m/s = 86.6% of J/M (not a bar: the damping over 1/60 s) |
| joint limits, every 240 Hz step | worst 0.000000 deg past the limit |
| replay of the baked cards vs the simulation, 240 Hz steps | head 0.78 deg, chest 0.18 deg (bar: 1 deg) |
| one undo step | yes: the command is one step; Ctrl+Z restores the victim's cards exactly |

The peak angular speed is linear in the impulse, so the 2x ratio is the model's linearity, not an independent check of its
size. Whether 414 deg/s (7 rad/s) for a head hit at 12 m/s is right in magnitude has not been checked against real impact
data. It is the result of the m_eff, de Leva and spring choices above.

## 8. Sources

- de Leva, P. (1996). Adjustments to Zatsiorsky-Seluyanov's segment inertia parameters. J. Biomech. 29(9), 1223-1230.
  (masses and COM fractions: via Proportions.DE_LEVA; radii of gyration: see the caveat in section 5.)
- Winter, D. A. (2009). Biomechanics and Motor Control of Human Movement, 4th ed. (Table 4.1, the de Leva values as quoted.)
- Drillis & Contini (1966), via Winter (2009), for segment lengths (in Proportions.gd).
- Bat rod: the uniform-rod moment of inertia about an end (m L^2/3) and about the centre (m L^2/12), with the parallel-axis
  theorem: standard mechanics, the form used in section 2.
- Weapon masses: ESTIMATES (not measured): a 33 in baseball bat ~0.9 kg; a 1.8 m staff ~1.1 kg; a 1.1 m long hammer ~2.5 kg;
  a dagger ~0.3 kg; a Dane axe 1-2 kg (1.5 kg used: the same figure the body.gd KINDS note gives, from en.wikipedia.org/
  wiki/Dane_axe, read in round 45).

## 9. Not done

- No floor contact or gravity during the window: the struck fighter does not fall, and a shove the feet cannot take
  still moves the COM (on a real body the feet would hold it). A reaction that pushes the body far (a long window, a
  heavy weapon) can look floaty.
- No collision response between the body's own parts; the hit point's contact is not re-solved each frame.
- The chain's share (CHAIN = 0.5) and the spring constants are design choices, not fitted.
- The radii of gyration are from memory (section 5).
- The screenshot (the job's tmp folder) shows the app at a reaction frame, with the hero in the camera's view: the struck
  fighter is not framed in close view.
- The command reacts to the first contact on a body part in the fighters' report only. Other contacts (a second strike, a
  block, a clash) are not reacted to.
