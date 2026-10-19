# WEIGHT FEEL (ROADMAP 40)

A heavy weapon is slow to swing. `Weight: time the swing to the weapon` (scripts/weight_feel.gd) retimes the wind-up and the
recovery of a swing by the held weapon's moment of inertia about the shoulder. The contact (hit) card keeps its pose and its hold.

## The relation

Swing speed falls as the implement's moment of inertia rises (Cross & Bower 2006, fit `V = C / I^n`, n = 0.27 for the rods
they swung). Over a fixed arc the time is inversely as the speed, so

    T / T_ref = (I / I_ref)^0.27        I = m r^2 + I_cm

* m: the weapon's mass (Body.KINDS "mass": bat 0.90 kg (32 oz), staff 1.4, long hammer 2.5, long axe 1.8 (Dane axe 1-2 kg), dagger 0.30).
* r: shoulder to the weapon's centre of mass: the arm's reach (upper arm + forearm + 0.6 hand of the body's own skeleton, about 0.65 m) plus the centre of mass's place along the weapon from the grip (KINDS "com" x length, grip 0.18 m from the butt).
* I_cm = m (k len)^2, k the radius of gyration (KINDS "k"; a uniform rod 0.289).
* I_ref: the metal bat's. The scene's timing is taken as authored for the bat until the command has run; the contact card then keeps `weight_i`, the inertia its timing fits, so running it again is a no-op and a change of weapon retimes by the ratio.

Numbers on the default body: dagger 0.136, bat 0.915, long hammer 4.48 kg m2 about the shoulder; wind-up x0.60, x1.00, x1.53.
One run never changes the timing by more than x0.5 / x2.0.

## Sources (what was and was not read)

* R. Cross and R. Bower, "Effects of swing-weight on swing speed and racket power", Journal of Sports Sciences 24(1), 23-30 (2006): six rods, swing speed `V = C / I^n`; the search abstract read gives n = 0.27 for one set of conditions. Only the abstract/snippet was read here, not the full text: check n against the paper's PDF (physics.usyd.edu.au/~cross) before quoting it elsewhere.
* G. Fleisig, N. Zheng, D. Stodden, J. Andrews, "Relationship between bat mass properties and bat velocity", Sports Engineering 5, 1-8 (2002): bat speed falls as the moment of inertia rises (qualitative support; the paper itself was not retrievable).
* Koenig et al., "The influence of moment of inertia on baseball/softball bat swing speed", Sports Engineering (Springer): swing speed generally decreases as the bat's moment of inertia about a vertical axis through the batter's body increases (as cited by secondary sources).
* A. Nathan, Illinois "Physics of Baseball", swing speed vs bat and batter mass (same family of results).

## Limits

* The exponent comes from rods and bats swung with the wrist or the whole arm, not measured about the shoulder for a dagger or a hammer; the shoulder axis is the extension the roadmap asks for.
* Masses and centres of mass are round numbers per weapon kind, not measured items.
* The contact time moves by exactly the change in the wind-up (the contact card stays where it is in the swing, not at the same second); the hit marker rides with it.
