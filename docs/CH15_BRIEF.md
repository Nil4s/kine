# CH15 brief: a nuclear power plant (pressurized water reactor), its blueprint and its construction section video

Nick (11-04): a nuclear plant with its blueprint and a building-section video. It needs electrical knowledge, the plant itself, and a lot of challenge. It can be inspired by a real one, used only for measurements.

**Reference plant:** Angra 2 (Angra dos Reis, Brazil): a Siemens/KWU pressurized water reactor, 4 loops, about 1350 MWe, spherical steel containment inside a concrete shield building, seawater once-through cooling.
- Every number comes from public sources (IAEA PRIS, Eletronuclear, the KWU/Konvoi literature, textbooks). Mark each one SEEN / MEMORY / ASSUMED, as the CH14 reference does.
- Where Angra 2's own value is not public, use a cited same-class PWR value and say so.
- The scope is plant-level public engineering only: layout, heat balance, steam cycle, electrical, structure, decay heat, construction sequence. No fuel-cycle or enrichment detail is needed or wanted.

## Deliverables
1. **Plant model:** Kine Parts and an Assembly at real scale, at block level:
   - reactor building (steel sphere + concrete shell) with the primary circuit inside: vessel, 4 steam generators, 4 coolant pumps, pressurizer, loop piping
   - turbine hall (HP + LP turbines, generator, condensers)
   - switchyard and transformers
   - auxiliary and fuel buildings, diesel buildings, seawater intake and outfall
2. **Blueprint:** site plan and a reactor-building section, as dimensioned 2D drawings (Kine's blueprint/SVG export), with a title block and scale.
3. **Electrical one-line diagram:** generator -> generator breaker -> main step-up transformers -> grid (500 kV). Also unit auxiliary transformers, house buses, emergency diesel generators and safety buses, every bus with its voltage and every transformer with its MVA.
4. **Construction section video:** the build sequence (excavation and mat, containment shell, polar crane, vessel and steam-generator lift-in, dome, turbine hall), rendered with a section cut. Make a contact sheet and LOOK at it.
5. **Feedback** per docs/CHALLENGE_FEEDBACK.md: engineering level per discipline, the Kine gaps table, what looks wrong.

## Bars
Commit them BEFORE their first run. Each has a planted control that must fail.
1. **Primary heat balance:** Q = m_dot cp (T_out - T_in) over the core, from the cited flow and temperatures, within 3 pct of the cited thermal power. cp is taken at the mean temperature and 15.5 MPa (IAPWS-IF97 or a cited table). PLANTED: the flow of one loop instead of four fails.
2. **Steam cycle:** a Rankine cycle at the cited steam-generator outlet and condenser conditions, with water/steam properties from IAPWS-IF97 (implement the region equations needed, or a cited table with interpolation; check 5 points against the IF97 verification tables to 1e-6).
   - Gross efficiency within the plant's cited gross output / thermal power +-3 points, and below Carnot between the same temperatures.
   - PLANTED: an ideal-gas steam model misses the band.
3. **Electrical:**
   - generator MVA = P / pf
   - terminal current I = S / (sqrt(3) V) at the cited terminal voltage, by hand
   - main transformer MVA >= the generator's
   - auxiliary transformers >= the house load
   - diesel count x rating >= the safety-bus load with N+1 or N+2 redundancy as cited
   - PLANTED: one fewer diesel than the redundancy needs fails.
4. **Decay heat:** after shutdown, the fraction of thermal power by the Way-Wigner formula (or ANS-5.1, cited) at 10 s, 1 h, 1 day, checked by hand. The emergency feedwater flow that boils it off at 1 h must be within the cited pump capacity. PLANTED: using 0 s operating time fails.
5. **Containment:** steel sphere membrane stress sigma = p R / (2 t) at the cited design pressure and diameter, within the cited steel's allowable (ASME III class MC style). PLANTED: a cylinder formula p R / t at the same thickness is flagged as a different result.
6. **Layout:** every building's footprint and height within 5 pct of the measured public value (satellite or drawing, cited), and no two buildings overlap (the CH13 bar-j style overlap check on the Assembly). PLANTED: a turbine hall moved into the reactor building is caught.
7. **Build sequence:** each stage only adds parts that rest on parts already built (support check). The video has the stages in order, and the section cut shows the inside. PLANTED: the dome placed before the walls fails.
8. **Hand arithmetic:** every number in bars 1-5 equals its hand value to 1e-9.

## Rules (same as every lane)
- Heavy maths goes in C++ with a GDScript twin and an equality bar, or stays in GDScript when cheap. IAPWS-IF97 is a good C++ candidate.
- Test with `wtest.sh ch15 easypart peasy3 freestart`.
- `git add` by name only; never push, merge or PR (the lead does).
- No MIT or AGPL code.
- Stop and report honestly when a bar can't be met. Don't loosen it.
